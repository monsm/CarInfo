import Foundation

// 请求 / 响应原文日志（对应小程序 service.js 的 _rawLogPush）。
// 内存环形 60 条 + 每条正文截断 3000 字符，供「开发者工具」页查看 / 复制。
//
// ⚠️ 安全约束（务必保持）：
// 1. 所有 URL 查询串里的 token / pin、JSON 体里的 token / refreshToken / 护照类字段都要打码 ——
//    这个日志页可以被复制导出，原文含凭证等于凭证泄露；
// 2. 绝不把请求 / 响应正文写进 NSLog：系统日志可被设备日志工具收集，且历史上
//    车控接口把 pin 放在查询串里，一条 NSLog 就把 PIN 写进了系统日志。

final class RawLogStore: @unchecked Sendable {
    static let shared = RawLogStore()

    private let lock = NSLock()
    private var logEntries: [String] = []
    private let maxEntries = 60
    private let maxChars = 3000

    /// 需要打码的查询参数 / JSON 字段名（小写比较）
    private static let sensitiveKeys = [
        "token", "pin", "refreshtoken", "refresh_token", "accesstoken", "access_token",
        "password", "pwd", "csrfToken".lowercased()
    ]

    /// 需要打码的 JSON 字段名（车牌 / 手机号相关）
    private static let sensitiveValueKeys = [
        "phone", "mobile", "tel", "plate", "platenumber", "plateno"
    ]

    /// 个人 / 车辆身份字段。这些以前**没有**打码，而日志页可以一键复制导出：
    /// `vin`（车架号）、`idcard`（身份证）、`engineNo`、`userFullname` / `name` /
    /// `nickName` / `senderName`（姓名）、`tuid` / `cycuid` / `sid`（账号与服务端内部 ID）。
    private static let piiKeys = [
        "vin", "idcard", "idcardno", "certifino", "engineno", "tuid",
        "carnum", "carid", "userfullname", "username", "name", "nickname",
        "lastname", "sidname", "sendername", "senderid", "trackuserid",
        "sysuid", "cycuid", "cycid", "sid", "registrationid", "smskey",
        "carauthcode", "bindtoken", "bind_token"
    ]

    /// 位置类字段：字符串值整体打码，数值坐标只留整数部分（约 100 km 量级）。
    /// 理由：车的位置是这份日志里最敏感的东西之一，而排障根本不需要米级精度。
    private static let locationKeys = [
        "addrdesc", "addrname", "address", "community", "dist", "location"
    ]
    private static let coordinateKeys = ["lat", "lng"]

    /// 内部实现细节：`containerName` 是 K8s 内网容器名（`carbond-tu-api-5cbf6f4f7-pp7qx`）——
    /// 它藏着服务端的部署信息，不应该出现在一个可被用户导出的日志里。
    private static let infraKeys = ["containername"]

    private init() {}

    // MARK: - 脱敏

    /// 脱敏：1) `key=value` 形式的查询串；2) `"key":"value"` 形式的 JSON 字段；
    /// 3) 11 位手机号。
    func redact(_ input: String) -> String {
        var out = input

        // 1) 查询串 / 表单：token=xxx&pin=yyy
        for key in Self.sensitiveKeys + Self.sensitiveValueKeys {
            let pattern = "(?i)(\\b" + NSRegularExpression.escapedPattern(for: key) + "=)([^&\\s\"',}]+)"
            out = out.replacingOccurrences(of: pattern, with: "$1***", options: .regularExpression)
        }

        // 2) JSON：\"token\":\"xxx\"
        for key in Self.sensitiveKeys + Self.sensitiveValueKeys {
            let pattern = "(?i)(\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*:\\s*\")([^\"]*)"
            out = out.replacingOccurrences(of: pattern, with: "$1***", options: .regularExpression)
        }

        // 2b) 个人 / 车辆身份（VIN / 身份证 / 姓名 / 内部 ID）
        for key in Self.piiKeys {
            let pattern = "(?i)(\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*:\\s*\")([^\"]*)"
            out = out.replacingOccurrences(of: pattern, with: "$1***", options: .regularExpression)
        }

        // 2c) 地址文本 / 内部容器名
        for key in Self.locationKeys + Self.infraKeys {
            let pattern = "(?i)(\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*:\\s*\")([^\"]*)"
            out = out.replacingOccurrences(of: pattern, with: "$1***", options: .regularExpression)
        }

        // 2d) 坐标：只留整数部分（约 100 km 级）—— 排障不需要米级精度
        for key in Self.coordinateKeys {
            let pattern = "(?i)(\"" + key + "\"\\s*:\\s*)(-?[0-9]+)(\\.[0-9]+)?"
            out = out.replacingOccurrences(of: pattern, with: "$1$2", options: .regularExpression)
        }

        // 2e) 请求头里的 Bearer 凭证
        out = out.replacingOccurrences(
            of: "(?i)(authorization:\\s*bearer\\s+)(\\S+)",
            with: "$1***",
            options: .regularExpression
        )

        // 3) 裸手机号（11 位、1 开头）
        out = out.replacingOccurrences(
            of: "(?<![0-9])1[3-9][0-9]{9}(?![0-9])",
            with: "1**********",
            options: .regularExpression
        )
        return out
    }

    /// 只保留方法 + 路径，去掉 host 与查询串（给系统日志用）
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
        let entry = "[\(now())] REQ \(method) \(redact(url))\nbody=\(clip(redact(bodyText), maxChars))\nheaders=Authorization=…(已打码)"
        push(entry)
        // 系统日志只留「方法 + 路径」，不带任何参数与正文
        NSLog("[CarKeeper] REQ %@ %@", method, shortURL(url))
    }

    func logResponse(status: Int, url: String, body: Data, contentType: String) {
        let isBinary = contentType.hasPrefix("image/") || contentType.contains("octet-stream")
        let bodyText = isBinary ? "[二进制 \(body.count)B, \(contentType)]" : (String(data: body, encoding: .utf8) ?? "")
        let entry = "[\(now())] RES \(status) \(redact(url))\nbody=\(clip(redact(bodyText), maxChars))"
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

    func clear() {
        lock.lock(); logEntries.removeAll(); lock.unlock()
    }

    func count() -> Int {
        lock.lock(); defer { lock.unlock() }
        return logEntries.count
    }
}
