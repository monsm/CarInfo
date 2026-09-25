import Foundation
import SwiftUI

// 检查更新：查询 GitHub 仓库 tag=latest 的 Release（由 Actions 每次构建覆盖上传 ipa），
// 下载其 ipa 附件到 App 沙盒，再以系统分享菜单（UIActivityViewController）弹出。
//
// 2026-09-25（用户第 5 条）：令牌**写在代码里**（`Services/GithubToken.swift`，唯一一处），
// 不再是「每台设备手输一次、缓存在 UserDefaults」—— 那条路上的按钮在输入前什么都不做。
//
// 2026-09-25 晚（用户第 9 条：界面上弹出原始 JSON `{"message":"Bad credentials","status":"401"}`）：
// 两处真错一起修掉，两条都是**量出来的**（`curl` 直打 GitHub，命令记在 `GithubToken.swift`）：
//   · 那把令牌确实无效（401）—— 但**仓库是公开库**（匿名 200），所以它本来就不需要；
//     于是 `GithubToken.value` 清空，这一层改成「有令牌就带上、没有就匿名」。
//     此前 `token` 为空会直接抛 `noToken`，于是「没配令牌」也能让按钮失效 —— 那条路删了。
//   · 错误体原来是**原样倒给用户看**的（`String(data:)` 截前 200 字）。现在由
//     `humanMessage(status:body:)` 译成一句人话：401 说令牌、404 说找不到、403 说限流。
//     这是全站那条「按钮按了要能说出结果」的同一条 —— 只是这一次「结果」是 GitHub 的错误。
enum UpdateService {

    // 仓库 monsm/CarInfo（私库）。如需改仓库只改这里两个常量即可。
    static let repoOwner = "monsm"
    static let repoName = "CarInfo"
    static let tagLatest = "latest"

    /// 令牌只有**一个**出处（不是 UserDefaults、也不是本文件的常量）：
    /// 它住 `GithubToken.value`，因为「这个 key 写在哪」应该只有一个人能回答。
    /// 只读属性而不是可写：没有任何界面能改它了（那个 Token 弹窗已删）。
    /// 当前值是**空串**（理由与实测记在 `GithubToken.swift`：公开库匿名可读）。
    static var githubToken: String { GithubToken.value }

    /// 请求头。**令牌为空就不带 Authorization**：这个仓库是公开的，匿名读 Release 返回 200
    ///（实测，见 `GithubToken.swift`）。留着一个空 token 拼出 `Bearer ` 反而会被 401 ——
    /// 那是这把令牌上一版报的错的样子，所以这一行必须按「有没有」分支，不能无条件拼。
    static func apiHeader(_ token: String) -> [String: String] {
        var h = ["Accept": "application/vnd.github+json"]
        if !token.isEmpty { h["Authorization"] = "Bearer \(token)" }
        return h
    }

    /// 把 GitHub 的错误体译成**一句人话**。
    ///
    /// 触发它的那一幕（用户第 9 条截图）：一张玻璃卡里摊着整块原始 JSON ——
    /// `{"message":"Bad credentials","documentation_url":"…","status":"401"}`。
    /// 那是**服务端的字段名**，不是给人读的话。
    ///
    /// 三种状态各有一句对症的话，因为三种病因不同、出路也不同：
    ///   401 → 令牌的事（而当前令牌为空，所以这条出现就说明有人刚填了一把坏的）
    ///   404 → 找不到仓库或 `latest` 那个 Release（公开库读不到私库，这是最常见的原因）
    ///   403 → 限流（匿名 60 次/小时）—— 这条**已经真的发生过**：写这一轮的时候，
    ///         本机连续调了几次接口就被回了一个 `403 rate limit exceeded`
    ///         （带 `X-RateLimit-Remaining: 0`），而那时正是手机最可能碰到的情形
    ///         （运营商出口是大内网共享的 IP）。
    /// 三句都控在 30 字以内 —— `scan/copy.py` 对界面文案就是这么盯的（超了就报红），
    /// 而这三句真的会显示在「我的 → 关于」那张卡里。
    static func humanMessage(status: Int, body: Data) -> String {
        let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let api = obj?["message"] as? String
        switch status {
        case 401:
            return "访问令牌无效或过期（401）"
        case 404:
            return "找不到最新版本（404）"
        case 403:
            return "被 GitHub 限流了，稍后再试"
        default:
            if let api, !api.isEmpty { return "HTTP \(status)：\(api)" }
            let raw = String(data: body, encoding: .utf8) ?? ""
            return raw.isEmpty ? "HTTP \(status)" : "HTTP \(status)：\(raw.prefix(200))"
        }
    }

    // ---------- Release 结构 ----------
    struct ReleaseInfo: Identifiable {
        let id: Int
        let name: String
        let body: String
        let publishedAt: String
        let ipaUrl: String
        let zipUrl: String
        let ipaSizeMB: Double

        var displaySize: String { ipaSizeMB > 0 ? String(format: "%.1f MB", ipaSizeMB) : "未知大小" }
    }

    /// 查询 tag=latest 的 Release（取其中 .ipa 附件）。
    static func fetchLatestRelease(token: String) async throws -> ReleaseInfo {
        //  这里原本有一句 `guard !token.isEmpty else { throw .noToken }` ——
        //  它把「没配令牌」当成一件办不到的事，而**公开库匿名就能读**（实测）。
        //  那句话现在连错误类型一起删了：令牌只影响带不带那个请求头（见 `apiHeader`）。
        // 不用 `!`：这三个常量拼出来的字符串如果哪天出意外（改了常量、带了空格），
        // 崩的是用户的 App，而这里本来就在一个 throws 函数里。
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/tags/\(tagLatest)") else {
            throw UpdateError.fetchFailed("更新地址拼不出来（仓库名或 tag 里有非法字符）")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in apiHeader(token) { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            // 不再把服务端的原文倒给用户看（那张 401 截图）。翻译在 `humanMessage` 里。
            throw UpdateError.fetchFailed(humanMessage(status: http.statusCode, body: data))
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UpdateError.fetchFailed("响应不是有效 JSON")
        }
        let assets = obj["assets"] as? [[String: Any]] ?? []
        var ipaURL = "", zipURL = "", ipaSize = ""
        for a in assets {
            let name = (a["name"] as? String) ?? ""
            let dl = (a["browser_download_url"] as? String) ?? ""
            if name.hasSuffix(".ipa") {
                ipaURL = dl
                ipaSize = (a["size"] as? Int).map { String(Double($0) / 1048576.0) } ?? ""
            }
            if name.hasSuffix(".zip") { zipURL = dl }
        }
        guard !ipaURL.isEmpty else { throw UpdateError.fetchFailed("Release 里没有 .ipa 附件") }
        return ReleaseInfo(
            id: (obj["id"] as? Int) ?? 0,
            name: (obj["name"] as? String) ?? tagLatest,
            body: (obj["body"] as? String) ?? "",
            publishedAt: (obj["published_at"] as? String) ?? "",
            ipaUrl: ipaURL,
            zipUrl: zipURL,
            ipaSizeMB: Double(ipaSize) ?? 0
        )
    }

    // ---------- 下载（带进度） ----------
    /// 下载 ipa 到 App 沙盒 Documents 目录，返回本地文件 URL。progress 回调 0~1。
    static func downloadIPA(url: String, progress: @escaping (Double) -> Void) async throws -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let target = dir.appendingPathComponent("CarKeeper-latest.ipa")
        try? FileManager.default.removeItem(at: target)

        // `url` 来自 GitHub 的 JSON（browser_download_url）—— 服务端给什么就是什么，
        // 直接 `!` 等于把服务端的一次异常变成一个崩溃。
        guard let remote = URL(string: url) else { throw URLError(.badURL) }
        let request = URLRequest(url: remote)
        let location = try await downloadWithProgress(request: request, progress: progress)
        try FileManager.default.moveItem(at: location, to: target)
        return target
    }

    /// 下载文件并轮询进度。downloadTask 无内建进度回调，轮询 progress 对象最稳。
    static func downloadWithProgress(request: URLRequest, progress: @escaping (Double) -> Void) async throws -> URL {
        let state = DownloadState()
        let task = URLSession.shared.downloadTask(with: request) { tmpURL, _, error in
            if let err = error { state.error = err }
            else if let url = tmpURL { state.url = url }
            else { state.error = URLError(.unknown) }
            state.done = true
        }
        task.progress.totalUnitCount = 1
        task.resume()
        while !state.done {
            progress(min(1.0, task.progress.fractionCompleted))
            if Task.isCancelled { task.cancel(); break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        progress(1.0)
        if let err = state.error { throw err }
        guard let url = state.url else { throw URLError(.unknown) }
        return url
    }

    // 完成回调与轮询线程共享的下发状态（用简单类避免跨线程捕获可变局部量）
    private final class DownloadState: @unchecked Sendable {
        var done = false
        var url: URL?
        var error: Error?
    }
}

enum UpdateError: LocalizedError {
    //  `.noToken` 已删（2026-09-25 第 9 条）：公开库匿名可读，所以「没有令牌」
    //  不是一种失败，而是一种默认。留着一个永远不会被抛出的 case，只会让下一个
    //  读到这里的人以为还有一条「必须先配令牌」的路。
    case fetchFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .fetchFailed(let m): return "获取更新失败：\(m)"
        case .downloadFailed(let m): return "下载失败：\(m)"
        }
    }
}

// ---------- 分享菜单：用 SwiftUI 弹 UIActivityViewController ----------
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
