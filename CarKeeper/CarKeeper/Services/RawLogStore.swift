import Foundation

// 请求 / 响应原文日志（对应小程序 service.js 的 _rawLogPush）。
// 内存环形 60 条 + 每条正文截断 3000 字符，供「开发者工具」页查看 / 复制。
// Authorization 头打码避免 token 泄露。

final class RawLogStore: @unchecked Sendable {
    static let shared = RawLogStore()

    private let lock = NSLock()
    private var entries: [String] = []
    private let maxEntries = 60
    private let maxChars = 3000

    private init() {}

    private func clip(_ s: String, _ n: Int) -> String {
        s.count > n ? String(s.prefix(n)) + "…(截断,共\(s.count)字符)" : s
    }

    private func now() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    private func push(_ entry: String) {
        lock.lock()
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        lock.unlock()
        // 同步输出到系统日志（Console.app / Device Logs 可查）
        NSLog("[CarKeeper] %@", entry)
    }

    func logRequest(method: String, url: String, body: Data?) {
        let bodyText = body.map { String(data: $0, encoding: .utf8) ?? "[二进制 \($0.count)B]" } ?? "nil"
        let masked = "Authorization=…(已打码)"
        let entry = "[\(now())] REQ \(method) \(url)\nbody=\(clip(bodyText, maxChars))\nheaders=\(masked)"
        push(entry)
    }

    func logResponse(status: Int, url: String, body: Data, contentType: String) {
        let isBinary = contentType.hasPrefix("image/") || contentType.contains("octet-stream")
        let bodyText = isBinary ? "[二进制 \(body.count)B, \(contentType)]" : (String(data: body, encoding: .utf8) ?? "")
        let entry = "[\(now())] RES \(status) \(url)\nbody=\(clip(bodyText, maxChars))"
        push(entry)
    }

    func logError(method: String, url: String, message: String) {
        let entry = "[\(now())] ERR \(method) \(url)\n\(clip(message, maxChars))"
        push(entry)
    }

    func entries() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    func joined() -> String {
        entries().joined(separator: "\n\n──────────\n\n")
    }

    func clear() {
        lock.lock(); entries.removeAll(); lock.unlock()
    }

    func count() -> Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }
}
