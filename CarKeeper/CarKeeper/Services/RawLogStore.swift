import Foundation


final class RawLogStore: @unchecked Sendable {
    static let shared = RawLogStore()

    private let lock = NSLock()
    private var logEntries: [String] = []
    private let maxEntries = 60
    private let maxChars = 3000

    private static let sensitiveKeys = [
        "token", "pin", "refreshtoken", "refresh_token", "accesstoken", "access_token",
        "password", "pwd", "csrftoken", "smscode", "piccode", "pickey"
    ]

    private static let sensitiveValueKeys = [
        "phone", "mobile", "tel", "plate", "platenumber", "plateno"
    ]

    private static let piiKeys = [
        "vin", "idcard", "idcardno", "certifino", "engineno", "tuid",
        "carnum", "carid", "userfullname", "username", "name", "nickname",
        "lastname", "sidname", "sendername", "senderid", "trackuserid",
        "sysuid", "cycuid", "cycid", "sid", "registrationid", "smskey",
        "carauthcode", "bindtoken", "bind_token"
    ]

    private static let locationKeys = [
        "addrdesc", "addrname", "address", "community", "dist", "location"
    ]

    private static let infraKeys = ["containername"]

    private static let rules: [(NSRegularExpression, String)] = {
        var out: [(NSRegularExpression, String)] = []

        func add(_ pattern: String, _ template: String) {
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                out.append((re, template))
            }
        }

        for key in sensitiveKeys + sensitiveValueKeys {
            let quoted = NSRegularExpression.escapedPattern(for: key)
            add("(\"\(quoted)\"\\s*:\\s*\")([^\"]*)", "$1***")
            add("(\\b\(quoted)=)([^&\\s\"',}]+)", "$1***")
        }
        for key in piiKeys + locationKeys + infraKeys {
            let quoted = NSRegularExpression.escapedPattern(for: key)
            add("(\"\(quoted)\"\\s*:\\s*\")([^\"]*)", "$1***")
        }
        for key in ["lat", "lng"] {
            add("(\"\(key)\"\\s*:\\s*)(-?[0-9]+)(\\.[0-9]+)?", "$1$2")
        }
        add("(authorization:\\s*bearer\\s+)(\\S+)", "$1***")
        add("(?<![0-9])1[3-9][0-9]{9}(?![0-9])", "1**********")
        return out
    }()

    private init() {}

    func redact(_ input: String) -> String {
        var out = input
        for (re, template) in Self.rules {
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            out = re.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: template)
        }
        return out
    }

    private func shortURL(_ url: String) -> String {
        let noQuery = url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url
        guard let range = noQuery.range(of: "//") else { return noQuery }
        let afterScheme = noQuery[range.upperBound...]
        guard let slash = afterScheme.firstIndex(of: "/") else { return noQuery }
        return String(afterScheme[slash...])
    }

    private func clip(_ s: String, _ n: Int) -> String {
        s.count > n ? String(s.prefix(n)) + "…(截断,共\(s.count)字符)" : s
    }

    private func now() -> String {
        DateText.shared.string(Date(), "yyyy-MM-dd HH:mm:ss")
    }

    private func push(_ entry: String) {
        lock.lock()
        logEntries.insert(entry, at: 0)
        if logEntries.count > maxEntries { logEntries.removeLast(logEntries.count - maxEntries) }
        lock.unlock()
    }

    func logRequest(method: String, url: String, body: Data?) {
        let bodyText = body.map { String(data: $0, encoding: .utf8) ?? "[二进制 \($0.count)B]" } ?? "nil"
        let entry = "[\(now())] REQ \(method) \(redact(url))\nbody=\(clip(redact(clip(bodyText, maxChars * 2)), maxChars))\nheaders=Authorization=…(已打码)"
        push(entry)
        NSLog("[CarKeeper] REQ %@ %@", method, shortURL(url))
    }

    func logResponse(status: Int, url: String, body: Data, contentType: String) {
        let isBinary = contentType.hasPrefix("image/") || contentType.contains("octet-stream")
        let bodyText = isBinary ? "[二进制 \(body.count)B, \(contentType)]" : (String(data: body, encoding: .utf8) ?? "")
        let entry = "[\(now())] RES \(status) \(redact(url))\nbody=\(clip(redact(clip(bodyText, maxChars * 2)), maxChars))"
        push(entry)
        NSLog("[CarKeeper] RES %d %@", status, shortURL(url))
    }

    func logError(method: String, url: String, message: String) {
        let entry = "[\(now())] ERR \(method) \(redact(url))\n\(clip(redact(message), maxChars))"
        push(entry)
        NSLog("[CarKeeper] ERR %@ %@", method, shortURL(url))
    }

    func allEntries() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return logEntries
    }

    func joined() -> String {
        allEntries().joined(separator: "\n\n──────────\n\n")
    }
}
