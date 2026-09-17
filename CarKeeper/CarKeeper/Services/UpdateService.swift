import Foundation
import UIKit

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
            throw UpdateError.fetchFailed(msg.prefix(200))
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
        let (location, _) = try await downloadWithProgress(request: request, progress: progress)
        try FileManager.default.moveItem(at: location, to: target)
        return target
    }

    /// URLSessionDownloadTask + 进度（downloadTask 无内建进度回调，轮询 progress object 最稳）
    static func downloadWithProgress(request: URLRequest, progress: @escaping (Double) -> Void) async -> (URL, URLResponse) {
        await withCheckedContinuation { (cont: CheckedContinuation<(URL, URLResponse), Error>) in
            let task = URLSession.shared.downloadTask(with: request) { tmpURL, resp, error in
                if let err = error {
                    if (err as NSError).code == NSURLErrorCancelled { return } // 取消不 resume 两次
                    cont.resume(throwing: err)
                } else if let url = tmpURL {
                    progress(1.0)
                    cont.resume(returning: (url, resp ?? URLResponse()))
                } else {
                    cont.resume(throwing: URLError(.unknown))
                }
            }
            let progressObj = task.progress
            task.resume()
            // 轮询进度直至任务结束
            let queue = DispatchQueue.global(qos: .utility)
            queue.async {
                var finished = false
                while !finished {
                    Thread.sleep(forTimeInterval: 0.2)
                    let frac = progressObj.fractionCompleted
                    progress(min(1.0, frac))
                    if progressObj.isFinished { finished = true; break }
                }
            }
        }
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
