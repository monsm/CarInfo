import Foundation
import SwiftUI

// 检查更新：查询 GitHub 仓库 tag=latest 的 Release（由 Actions 每次构建覆盖上传 ipa），
// 下载其 ipa 附件到 App 沙盒，再以系统分享菜单（UIActivityViewController）弹出。
// 私库访问需要用户填入具备 repo 权限的 Personal Access Token（缓存在 UserDefaults）。
enum UpdateService {

    // 仓库 monsm/CarInfo（私库）。如需改仓库只改这里两个常量即可。
    static let repoOwner = "monsm"
    static let repoName = "CarInfo"
    static let tagLatest = "latest"

    private static let tokenKey = "github_token"

    static var githubToken: String {
        get { UserDefaults.standard.string(forKey: tokenKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    static func apiHeader(_ token: String) -> [String: String] {
        ["Authorization": "Bearer \(token)", "Accept": "application/vnd.github+json"]
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
        guard !token.isEmpty else { throw UpdateError.noToken }
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/tags/\(tagLatest)")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in apiHeader(token) { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw UpdateError.fetchFailed(String(msg.prefix(200)))
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

        let request = URLRequest(url: URL(string: url)!)
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
    case noToken
    case fetchFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .noToken: return "请先填写 GitHub Token（私库访问需要）"
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
