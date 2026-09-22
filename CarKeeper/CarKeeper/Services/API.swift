import Foundation
import Security

// MARK: - 配置
//
// 直连长安官方接口（不再经过云函数代理）。
// - 域名白名单限制只存在于微信小程序，iOS 原生 App 无此限制；
// - URLSession 默认 keep-alive（HTTP/2 + 连接复用），picSend 与 smsSend 大概率落到
//   同一 CDN 节点，天然缓解「无验证码记录」问题；
// - 仍保留「无记录安全重试一次」与「码不匹配不重试」的语义。

enum APIConfig {
    static let authURL = "https://scrm.changan.com.cn/app-m/prod-api/auth/cac"
    static let baseURL = "https://m.iov.changan.com.cn"
    static let userAgent = "changAnFan/4.6.3 (iPhone; iOS 26.5; Scale/3.00)"
    static let registrationId = "2c8735c5a6f753229aec45789dcd3a1f4"
    static let version = "4.6.3"
}

// MARK: - 会话 / Token 存取

let tokenStorageKey = "car_token_config"
let cacheStorageKey = "car_data_cache"
let rawLogStorageKey = "changan_raw_log"

/// 令牌存储：**Keychain**，不再是 UserDefaults。
///
/// 为什么必须换：2026-09-22 的抓包逐字符比对证明，服务端的 `refresh_token` **不轮换**
/// （请求里的与响应里回来的完全相同，`expires_in: 86400`）。一个泄露的 refresh_token
/// 能长期换出新 access_token；而 UserDefaults 会进 iCloud / iTunes 备份，
/// 备份文件与越狱设备都能直接读到它。
///
/// `kSecAttrAccessibleAfterFirstUnlock` 是刻意的：后台刷新（BGTask）要在锁屏后跑，
/// 用 `WhenUnlocked` 会在锁屏后台读不到令牌 —— 表现出来就是「锁屏以后车况就不再刷新」，
/// 一个很难查的“网络问题”。
enum TokenStore {
    private static let service = "com.you.CarKeeper.token"
    private static let account = "car_token_config"

    private static func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func readKeychain() -> Data? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private static func writeKeychain(_ data: Data) {
        var q = baseQuery()
        SecItemDelete(q as CFDictionary)   // 先删再加：SecItemAdd 遇到已存在会返回 errSecDuplicateItem
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    /// 退出登录 / 清空数据时用。
    /// ⚠️ 只删 UserDefaults 里的旧键是不够的：令牌已经搬到 Keychain，
    /// 不删 Keychain 就等于「退出登录后凭证还在设备上」。
    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
        UserDefaults.standard.removeObject(forKey: tokenStorageKey)
    }

    static func read() -> TokenConfig? {
        // 一次性迁移：旧版本把令牌放在 UserDefaults 里。
        // 读到就搬进 Keychain 并**删掉明文**，然后照常返回 —— 用户无感，不用重新登录。
        if let legacy = UserDefaults.standard.data(forKey: tokenStorageKey) {
            writeKeychain(legacy)
            UserDefaults.standard.removeObject(forKey: tokenStorageKey)
            return try? JSONDecoder().decode(TokenConfig.self, from: legacy)
        }
        guard let data = readKeychain() else { return nil }
        return try? JSONDecoder().decode(TokenConfig.self, from: data)
    }

    static func write(_ cfg: TokenConfig) {
        guard let data = try? JSONEncoder().encode(cfg) else { return }
        writeKeychain(data)
    }
    static func currentToken() -> String {
        TokenStore.read()?.accessToken ?? ""
    }
    static func save(_ cfg: TokenConfig) {
        TokenStore.write(cfg)
        // AppStore 是 @MainActor；这里在后台调用，需 hop 回主线程更新 UI 状态。
        let logged = !cfg.accessToken.isEmpty
        let mob = cfg.mobile
        Task { @MainActor in
            AppStore.shared.isLoggedIn = logged
            AppStore.shared.phone = mob
        }
    }
}

// MARK: - 网络错误

struct APIError: LocalizedError {
    let message: String
    var expired: Bool = false
    var noRefresh: Bool = false
    var statusCode: Int? = nil

    var errorDescription: String? { message }
}

// MARK: - 请求封装

final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = ["User-Agent": APIConfig.userAgent, "Accept": "*/*"]
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 60
        cfg.httpCookieStorage = nil
        self.session = URLSession(configuration: cfg)
    }

    struct Response {
        let status: Int
        let headers: [String: String]
        let body: Data
        var text: String { String(data: body, encoding: .utf8) ?? "" }
    }

    /// 发起一次请求（自动跟随重定向，并走全局自动重试）。
    ///
    /// 网络层瞬时故障（超时 / 断网 / 5xx）由 `Retrier.global` 按策略自动重发；
    /// 业务层错误（token 过期、4xx）抛出后不会重试，交由上层决定。
    func request(url: String, method: String = "POST", body: Any? = nil, token: String? = nil,
                 raw: Data? = nil, retryable: Bool = true) async throws -> Response {
        guard let u = URL(string: url) else {
            throw APIError(message: "非法 URL：\(url)")
        }
        var req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData)
        req.httpMethod = method
        req.setValue(APIConfig.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let raw {
            req.httpBody = raw
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        } else if let body {
            let data: Data
            switch body {
            case let s as String: data = s.data(using: .utf8)!
            default: data = try JSONSerialization.data(withJSONObject: body, options: [])
            }
            req.httpBody = data
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        RawLogStore.shared.logRequest(method: method, url: url, body: req.httpBody)

        let oneShot: () async throws -> Response = { [self] in
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw APIError(message: "无效的 HTTP 响应")
            }
            var hdrs: [String: String] = [:]
            for (k, v) in http.allHeaderFields {
                hdrs[String(describing: k)] = String(describing: v)
            }
            let ct = hdrs.first(where: { $0.key.lowercased() == "content-type" })?.value ?? ""
            RawLogStore.shared.logResponse(status: http.statusCode, url: url, body: data, contentType: ct)

            // token 过期检测（与小程序一致：响应体出现 "token expired" 字样）
            let text = String(data: data, encoding: .utf8) ?? ""
            if text.range(of: "token expired", options: .caseInsensitive) != nil {
                var err = APIError(message: "token expired")
                err.expired = true
                err.statusCode = http.statusCode
                throw err
            }
            guard (200..<300).contains(http.statusCode) else {
                var e = APIError(message: "HTTP \(http.statusCode): \(text.prefix(200))")
                e.statusCode = http.statusCode
                throw e
            }
            return Response(status: http.statusCode, headers: hdrs, body: data)
        }

        // 仅当调用方允许重试、且该请求是幂等的（GET / 幂等 POST）时走全局重试；
        // 车控等有副作用的 POST 由调用方传 retryable: false 关闭。
        if retryable {
            let op = "\(method) \(url)"
            return try await Retrier.global.run(oneShot, label: op)
        }
        return try await oneShot()
    }

    // MARK: 业务层

    /// 解包响应为 { ok, data, msg }。
    func unpack(_ text: String, expectData: Bool = true) -> (ok: Bool, data: Any?, msg: String) {
        guard let dict = jsonToAny(text) else { return (false, nil, "响应解析失败") }
        let code = ciNumber(dict, ["Code", "code"])
        let success = ciBool(dict, ["Success"])
        let ok = (success == true) || (code == 200) || (code == 0)
        let data = ciPick(dict, ["Data", "data"])
        let msg = ciString(dict, ["Msg", "msg", "Message", "message"]) ?? ""
        return (ok, data, msg)
    }

    // MARK: 认证接口

    func signF(uuid: String, tt: String) -> String {
        MD5.hash("WDNH" + MD5.hash(APIConfig.version) + "SEOB" + MD5.hash("1")
            + "WEBV" + MD5.hash("1.0") + "ZXOYX" + MD5.hash(uuid)
            + "OHJHQ" + MD5.hash(tt) + "BGJM")
    }

    func deviceId() -> String {
        "9999999723755" + String(30 + Int.random(in: 0...6))
    }

    private func buildParams(phone: String, extra: [String: String] = [:]) -> [String: String] {
        let uuid = Self.makeUUID()
        let tt = String(Date().timeIntervalSince1970 * 1000)
        var p: [String: String] = [
            "picKey": "null", "code": "null", "a": "1.0", "b": "1", "c": APIConfig.version,
            "d": tt, "e": uuid, "f": signF(uuid: uuid, tt: tt), "id": deviceId(),
            "smsCode": "null", "pageSize": "null", "type": "1", "pageNum": "null",
            "picCode": "null", "labelList": "null", "biz": "0", "password": "null",
            "csrfToken": "null", "registrationId": APIConfig.registrationId, "tel": "null",
            "modulus": "null", "username": phone
        ]
        for (k, v) in extra { p[k] = v }
        return p
    }

    private static func makeUUID() -> String {
        let tpl = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
        var out = ""
        for c in tpl {
            switch c {
            case "x": out += String(Int.random(in: 0...15), radix: 16)
            case "y": out += String((Int.random(in: 0...3) | 8), radix: 16)
            default: out.append(c)
            }
        }
        return out
    }

    /// 发送短信验证码。返回 (ok, noRecord, msg)。
    /// 仅在「无记录」时安全重试一次；「码不匹配」绝不重试（避免重复发短信）。
    func smsSend(phone: String, picCode: String) async -> (ok: Bool, noRecord: Bool, msg: String) {
        let params = buildParams(phone: phone, extra: [
            "smsCode": "null", "picCode": picCode, "code": picCode, "biz": "null",
            "tel": phone, "picKey": phone
        ])
        // 发短信有副作用（真实下发短信），绝不自动重试。
        let sendOnce: () async throws -> Response = { [self] in
            try await request(url: "\(APIConfig.authURL)/smsSend", method: "POST", body: params, retryable: false)
        }
        do {
            var res = try await sendOnce()
            if isNoRecordResp(res.text) {
                try await Task.sleep(nanoseconds: 600_000_000)
                res = try await sendOnce()
            }
            let (ok, _, msg) = unpack(res.text, expectData: false)
            if ok { return (true, false, "短信发送成功") }
            let raw = String(res.text.prefix(160))
            let noRecord = isNoRecordResp(res.text)
            let codeMismatch = !noRecord && res.text.range(of: #"\"code\"\s*:\s*500"#, options: .regularExpression) != nil
            let m: String
            if codeMismatch {
                m = "图形验证码不正确或已失效：请刷新验证码图片后立即重新输入发送"
            } else if !msg.isEmpty {
                m = msg
            } else {
                m = "发送失败"
            }
            return (false, noRecord, "\(m)（服务端响应: \(raw)）")
        } catch {
            return (false, false, "发送失败：\(error.localizedDescription)")
        }
    }

    /// 图形验证码：GET 二进制图片，MIME 嗅探（服务端 Content-Type 不可信）。
    func getPicCode(phone: String) async -> Data? {
        do {
            // GET 幂等，走全局重试；图形验证码命中同 CDN 节点更重要，多试几次反而更好。
            let res = try await request(url: "\(APIConfig.authURL)/picSend?picKey=\(phone.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? phone)",
                                        method: "GET")
            return res.body
        } catch {
            RawLogStore.shared.logError(method: "GET", url: "picSend", message: error.localizedDescription)
            return nil
        }
    }

    /// 登录。成功返回 accessToken。
    func login(phone: String, smsCode: String, picCode: String) async throws -> String {
        let params = buildParams(phone: phone, extra: ["smsCode": smsCode, "picCode": picCode, "picKey": "null", "code": "null"])
        let res = try await request(url: "\(APIConfig.authURL)/appLogin", method: "POST", body: params)
        let (ok, data, msg) = unpack(res.text)
        guard ok, let d = data else {
            throw APIError(message: "登录失败：\(msg.isEmpty ? "接口返回无效Token" : msg)")
        }
        let dict = d as? [String: Any] ?? [:]
        let token = ciString(dict, ["access_token", "accessToken", "access_Token"])
        guard let t = token, !t.isEmpty else {
            throw APIError(message: "登录失败：接口返回无效Token")
        }
        let refresh = ciString(dict, ["refresh_token", "refreshToken"]) ?? ""
        TokenStore.save(TokenConfig(accessToken: t, refreshToken: refresh, mobile: phone, updateTime: Date().description))
        return t
    }

    func isNoRecordResp(_ text: String) -> Bool {
        let head = String(text.prefix(200))
        return head.contains("\"msg\":null") && head.range(of: #"\"code\"\s*:\s*500"#, options: .regularExpression) != nil
    }

    // MARK: 数据接口（带 token 刷新）

    func getCars() async throws -> [[String: Any]] {
        try await withRefresh { [self] in
            let res = try await request(url: "\(APIConfig.baseURL)/appserver/api/car/getMyCars?isNev=1&token=\(TokenStore.currentToken())",
                                        method: "POST", body: [:])
            let (ok, data, msg) = unpack(res.text)
            guard ok else { throw APIError(message: msg.isEmpty ? "获取车辆列表失败" : msg) }
            if let arr = data as? [[String: Any]] { return arr }
            if let arr = data as? [Any] { return arr.compactMap { $0 as? [String: Any] } }
            return []
        }
    }

    func getUser() async throws -> [String: Any]? {
        try await withRefresh { [self] in
            let res = try await request(url: "\(APIConfig.baseURL)/appserver/api/user/getUserInfoByToken?token=\(TokenStore.currentToken())",
                                        method: "POST", body: [:])
            let (ok, data, msg) = unpack(res.text)
            guard ok else { throw APIError(message: msg.isEmpty ? "获取用户信息失败" : msg) }
            // 服务端可能把 user 包在单元素数组里（与小程序一致）
            if let arr = data as? [Any], let first = arr.first as? [String: Any] { return first }
            return data as? [String: Any]
        }
    }

    func getCarCheck(carId: String) async throws -> [String: Any]? {
        try await withRefresh { [self] in
            let res = try await request(url: "\(APIConfig.baseURL)/appserver/api/carcheck/getCheckResult?carId=\(carId)&isNev=1&token=\(TokenStore.currentToken())",
                                        method: "POST", body: [:])
            let unpacked = unpack(res.text)
            return unpacked.ok ? unwrapEntity(unpacked.data) : nil
        }
    }

    func getCarPm25(carId: String) async throws -> [String: Any]? {
        try await withRefresh { [self] in
            let res = try await request(url: "\(APIConfig.baseURL)/appserver/api/car/pm/getCarPm25ByCarId?carId=\(carId)&token=\(TokenStore.currentToken())",
                                        method: "POST", body: [:])
            let unpacked = unpack(res.text)
            return unpacked.ok ? unwrapEntity(unpacked.data) : nil
        }
    }

    func getCharge(carId: String) async throws -> [String: Any]? {
        try await withRefresh { [self] in
            let res = try await request(url: "\(APIConfig.baseURL)/appserver/api/charge/info?carId=\(carId)&token=\(TokenStore.currentToken())",
                                        method: "POST", body: [:])
            let unpacked = unpack(res.text)
            return unpacked.ok ? unwrapEntity(unpacked.data) : nil
        }
    }

    func getControl(carId: String) async throws -> [String: Any]? {
        try await withRefresh { [self] in
            let res = try await request(url: "\(APIConfig.baseURL)/api/car/getControlStatus?carId=\(carId)&token=\(TokenStore.currentToken())",
                                        method: "POST", body: [:])
            let unpacked = unpack(res.text)
            return unpacked.ok ? unwrapEntity(unpacked.data) : nil
        }
    }

    func getControlInfo(carId: String, taskId: String) async -> (ok: Bool, data: [String: Any]?, msg: String) {
        do {
            let res = try await withRefresh { [self] in
                try await request(url: "\(APIConfig.baseURL)/api/car/getControlInfo?carId=\(carId)&id=\(taskId)&token=\(TokenStore.currentToken())",
                                  method: "POST", body: [:])
            }
            let (ok, data, msg) = unpack(res.text)
            return (ok, data as? [String: Any], msg)
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    func getLocation(carId: String) async throws -> [String: Any]? {
        try await withRefresh { [self] in
            let res = try await request(url: "\(APIConfig.baseURL)/appserver/api/cardata/getCarLocation?carId=\(carId)&mapType=GCJ02&token=\(TokenStore.currentToken())",
                                        method: "POST", body: [:])
            let unpacked = unpack(res.text)
            // 定位报文可能是扁平对象，也可能被包在 CarLocationResp / 单元素数组里（剥壳后再用）。
            // 请求/响应原文已由 RawLogStore 记录，排障时可在 App 的原始日志页直接看报文形状。
            guard unpacked.ok, let d = unwrapEntity(unpacked.data) else { return nil }
            return d
        }
    }

    func getMessages() async throws -> [[String: Any]] {
        // AppStore 是 @MainActor；parseMessages 会在协作线程跑，不能在那里假设主线程。
        // 在 getMessages（主线程入口）先取 cars 快照，再传给 parseMessages。
        let cars = await MainActor.run { AppStore.shared.cars }
        return try await withRefresh { [self] in
            // ⚠️ 必须同时传 token 参数：messagesURL() 里内嵌的 URL 参数只是 URL 级的认证，
            // request() 还需要 token 来设置 Authorization: Bearer 头。
            // 缺了这行，服务端返回 200 但 data.content 为空（不报 token expired），
            // 导致消息永远解析成空数组且 withRefresh 不会触发重试——这就是消息一直空的根因。
            let res = try await request(url: messagesURL(), method: "POST", body: [:],
                                        token: TokenStore.currentToken())
            return Self.parseMessages(res.text, cars: cars)
        }
    }

    private func messagesURL() -> String {
        let now = Date()
        let past = now.addingTimeInterval(-7 * 24 * 3600)
        let f: (Date) -> String = { d in
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.string(from: d)
        }
        let enc: (String) -> String = { s in s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
        // limit=2000 + 7 天窗口：与小程序对齐，服务端最多返回 ~200 条
        // 日志实测 7 天消息约 64 条/次（log_20260917），2000 完全覆盖，无性能风险。
        // 进而卡 UI（日志 17:19:17 messages 响应 99287 字符已印证风险）。
        return "\(APIConfig.baseURL)/appserver/api/information/pageReceiverInfoByTime?actionType=2&page=&limit=2000&startTime=\(enc(f(past)))&endTime=\(enc(f(now)))&token=\(TokenStore.currentToken())"
    }

    static func parseMessages(_ text: String, cars: [[String: Any]] = []) -> [[String: Any]] {
        let dict = jsonToAny(text) ?? [:]
        // Data 可能是包含 Content 数组的对象，也可能直接是消息数组。
        let content: [[String: Any]]
        if let dataObj = ciObject(dict, ["Data", "data"]), let inner = ciArray(dataObj, ["Content", "content"]) {
            content = inner
        } else if let arr = ciPick(dict, ["Data", "data"]) as? [[String: Any]] {
            content = arr
        } else {
            content = []
        }
        // 映射车牌号（与小程序一致：realReceiverId 命中本地车辆列表则替换为车牌）
        // cars 由调用方在主线程取快照后传入（parseMessages 本身在协作线程跑，不能再 assumeIsolated）。
        var plateOf: [String: String] = [:]
        for c in cars {
            let id = ciString(c, ["carId", "CarId"]) ?? ""
            let plate = ciString(c, ["plateNumber", "PlateNumber"]) ?? ""
            if !id.isEmpty, !plate.isEmpty { plateOf[id] = plate }
        }
        return content.map { m in
            var copy = m
            if let id = ciString(m, ["realReceiverId"]) {
                if let p = plateOf[id] {
                    // 只写报文真实键（首字母小写）。
                    // 这里原先把 `realReceiverId` 与 `RealReceiverId` **同时**写一遍 ——
                    // 那是在**补偿一个读层缺陷**（大小写敏感的下标）。读层修好后（一律走 ci*），
                    // 双写只会凭空多出一个报文中不存在的键，让下一个读的人以为服务端真的发过它。
                    copy["realReceiverId"] = p
                }
            }
            return copy
        }
    }

    func sendControlCommand(cmd: String, carId: String, pin: String, temperature: Int = 17) async throws -> [String: Any]? {
        try await withRefresh { [self] in
            var url = "\(APIConfig.baseURL)/api/car/control?pin=\(pin)&cmd=\(cmd)&carId=\(carId)&phoneType=&phoneId=&token=\(TokenStore.currentToken())"
            if cmd == "OpenAir" { url += "&temperature=\(temperature)" }
            // 车控有副作用（锁车/开窗/开空调），绝不自动重试，避免重复执行。
            let res = try await request(url: url, method: "POST", body: [:], retryable: false)
            let (ok, data, msg) = unpack(res.text)
            guard ok else { throw APIError(message: msg.isEmpty ? "执行失败" : msg) }
            return data as? [String: Any]
        }
    }

    // MARK: token 刷新（并发去重）
    private let refreshInFlight = AtomicTaskHolder()

    private func refreshOnce() async throws {
        guard let cfg = TokenStore.read(), !cfg.refreshToken.isEmpty else {
            var e = APIError(message: "未找到刷新凭证，请重新登录")
            e.noRefresh = true
            throw e
        }
        try await refreshInFlight.runOnce { [self] in
            let res = try await request(url: "\(APIConfig.authURL)/refresh", method: "POST",
                                        body: ["refreshToken": cfg.refreshToken])
            let unpacked = unpack(res.text)
            guard unpacked.ok, let d = unpacked.data else {
                throw APIError(message: "Token 刷新失败：\(unpacked.msg.isEmpty ? "未知错误" : unpacked.msg)")
            }
            let dict = d as? [String: Any] ?? [:]
            let newAccess = ciString(dict, ["access_token", "accessToken", "access_Token"])
            guard let t = newAccess, !t.isEmpty else {
                throw APIError(message: "Token 刷新失败：响应中未找到 access_token")
            }
            let newRefresh = ciString(dict, ["refresh_token", "refreshToken"]) ?? cfg.refreshToken
            TokenStore.save(TokenConfig(accessToken: t, refreshToken: newRefresh, mobile: cfg.mobile, updateTime: Date().description))
        }
    }

    private func withRefresh<T>(_ fn: @escaping () async throws -> T) async throws -> T {
        do {
            return try await fn()
        } catch let err as APIError {
            guard err.expired else { throw err }
            try await refreshOnce()
            return try await fn()
        }
    }
}

// token 刷新并发去重：基于 actor 的原子持有器（Swift 6 原生、无锁、类型安全）。
actor AtomicTaskHolder {
    private var task: Task<Result<Void, Error>, Never>?

    /// 同一时刻只允许一个刷新任务在跑；其它调用者 await 其结果（或错误）。
    func runOnce(_ body: @escaping () async throws -> Void) async throws {
        if let existing = task {
            let r = await existing.value
            if case .failure(let e) = r { throw e }
            return
        }
        let t: Task<Result<Void, Error>, Never> = Task { () -> Result<Void, Error> in
            do { try await body(); return .success(()) }
            catch { return .failure(error) }
        }
        task = t
        let result = await t.value
        task = nil
        if case .failure(let e) = result { throw e }
    }
}

