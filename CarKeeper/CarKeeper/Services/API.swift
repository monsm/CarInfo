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
            // `data(using: .utf8)` 实际不会失败，但 `!` 在这里没有任何好处：
            // 退化成空 body 会让请求直接报错（可见），而崩是静默的。
            case let s as String: data = s.data(using: .utf8) ?? Data()
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
                m = "验证码不正确或已失效，请刷新后重新发送"
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
            throw APIError(message: "登录失败：凭证无效")
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

    /// 历史窗口的**跨度**：往回 30 天（用户 2026-09-24：「是要最近 30 天的消息」）。
    static let messageDays = 30

    /// 每一段的**形状**：7 天一段。
    ///
    /// 「跨度」与「形状」是两件事，别混：
    ///   · 形状 = 抓包里那一次请求的样子（`startTime` 到 `endTime` 相隔 7 天），**唯一被验证过**；
    ///   · 跨度 = 界面要覆盖多少历史（用户要 30 天就 30 天），按需要拉长。
    /// 于是 30 天的跨度 = 五段 7 天的请求（最后一段只有 2 天），跨越 30 天、形状逐段相同。
    ///
    /// 为什么不发一个「30 天窗口」的请求：服务端能不能接受更长的区间，没有任何证据 ——
    /// 它完全可能对超长区间返回空，而「窗口太小」与「窗口太大」在界面上长得一模一样（都是 0 条）。
    /// 所以不赌：跨度照用户要的拉长，形状一个字不动。
    ///
    /// ⚠️ 这条推论的另一半要写在明处：**如果 30 天里确实有事件而界面还是空的，那就不是跨度的问题**
    /// —— 去「我的 → 诊断 → 消息自检」看那四个数（HTTP 状态 / 响应字节数 / 服务端自报条数 /
    /// 我们解析到的条数）。那一页就是为「四种失败长得一模一样」造的仪器。
    static let messageSliceDays = 7

    /// 合并后的条数上限。
    ///
    /// 四周可能有上千条事件，而它们全都要渲染成「车的事件」那一段里的行
    ///（那一节不是惰性列表）。留一个上限是防「列表没有上限」这件事，
    /// 不是防数据量：报文里的顺序是新 → 旧，所以截掉的是最老的那一段。
    static let messageCap = 300

    func getMessages() async throws -> [[String: Any]] {
        // AppStore 是 @MainActor；parseMessages 会在协作线程跑，不能在那里假设主线程。
        // 在 getMessages（主线程入口）先取 cars 快照，再传给 parseMessages。
        let cars = await MainActor.run { AppStore.shared.cars }
        return try await withRefresh {
            let api = APIClient.shared
            let windows = Self.messageWindows(days: Self.messageDays,
                                              sliceDays: Self.messageSliceDays)

            // 每一周一个请求（与抓包验证过的形状一致），并行发出。
            // 并行而不是顺序：四周的数据彼此不依赖，而界面在等第一份。
            var texts: [String] = []
            var firstError: APIError?
            await withTaskGroup(of: Result<String, APIError>.self) { group in
                for w in windows {
                    group.addTask {
                        do { return .success(try await api.messagesText(from: w.start, to: w.end)) }
                        catch let e as APIError { return .failure(e) }
                        catch { return .failure(APIError(message: error.localizedDescription)) }
                    }
                }
                for await r in group {
                    switch r {
                    case .success(let t): texts.append(t)
                    // token 过期必须往上传：`withRefresh` 靠这个标记刷新后重试。
                    // 其余失败可以容忍 —— 一段拿不到不该让整份历史变空。
                    case .failure(let e):
                        if firstError == nil || (e.expired && !(firstError?.expired ?? false)) {
                            firstError = e
                        }
                    }
                }
            }
            if texts.isEmpty, let e = firstError { throw e }
            let batches = texts.map { Self.parseMessages($0, cars: cars) }
            return Self.mergeMessages(batches)
        }
    }

    /// 从「现在」往回切成**连续的 7 天窗口**（新 → 旧），一共覆盖 `days` 天。
    ///
    /// 纯函数（`now` 可传）——所以它可以被测试逐段核对，不需要真机也不需要网络：
    /// 见 `PureLogicTests.MessageWindowTests`。
    ///
    /// 最后一段通常短于 `sliceDays`：它顶到 `days` 那一天的边界就停 ——
    /// 不为了凑整段而多要（多要一天不算错，但「跨度」这个词会开始说不清）。
    static func messageWindows(days: Int, sliceDays: Int = 7,
                               now: Date = Date()) -> [(start: Date, end: Date)] {
        // 用 `Double` + 把单位写在名字里，而不是 `TimeInterval`：后者只是 `Double` 的别名，
        // 而多一个 SDK 名字就要在 `scan/scan.py` 的白名单里登记一次（还得附 Apple 文档）。
        let spanSeconds = Double(max(1, days)) * 24 * 3600
        let sliceSeconds = Double(max(1, sliceDays)) * 24 * 3600
        let floorDate = now.addingTimeInterval(-spanSeconds)
        var out: [(start: Date, end: Date)] = []
        var end = now
        while end > floorDate {
            let start = max(end.addingTimeInterval(-sliceSeconds), floorDate)
            out.append((start, end))
            end = start
        }
        return out
    }

    /// 一个窗口的原始响应正文。
    ///
    /// ⚠️ 必须同时传 token 参数：`messagesURL` 里内嵌的 URL 参数只是 URL 级的认证，
    /// `request()` 还需要 token 来设置 Authorization: Bearer 头。
    /// 缺了这行，服务端返回 200 但 `data.content` 为空（不报 token expired），
    /// 导致消息永远解析成空数组且 `withRefresh` 不会触发重试 —— 那是上一个根因。
    private func messagesText(from start: Date, to end: Date) async throws -> String {
        let res = try await request(url: messagesURL(from: start, to: end), method: "POST", body: [:],
                                    token: TokenStore.currentToken())
        return res.text
    }

    private func messagesURL(from start: Date, to end: Date) -> String {
        // ⚠️ 必须钉住 locale：没有它，设备若用非公历（佛历 / 和历 / 民国纪年），
        // 这里会打出「2569-09-24」这样的年份 —— 服务端收到一个不存在的区间，
        // 回 0 条，而界面只会说「暂无消息」。这类错不报错、不崩，只是永远空。
        // 构造器现在从 `DateText` 的池子里取（同一个 `en_US_POSIX`，同一个格式串）——
        // 这一条是报文格式，池子的键里有 locale，所以它不会被别人显示用的那个池子污染。
        let f: (Date) -> String = { d in
            DateText.shared.string(d, "yyyy-MM-dd HH:mm:ss", locale: "en_US_POSIX")
        }
        let enc: (String) -> String = { s in s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
        // limit=2000 + 7 天一段：与抓包对齐。日志实测 7 天约 55~64 条，2000 完全覆盖，
        // 无性能风险（那条 99287 字符的响应就是 55 条，约 100KB）。
        return "\(APIConfig.baseURL)/appserver/api/information/pageReceiverInfoByTime?actionType=2&page=&limit=2000&startTime=\(enc(f(start)))&endTime=\(enc(f(end)))&token=\(TokenStore.currentToken())"
    }

    // MARK: - 消息自检（诊断页的仪器）
    //
    //  存在的理由：这条接口的失败有四种**长得一模一样**的形态 ——
    //    ① 请求根本没发出去（没登录 / URL 拼错 / 断网）
    //    ② 发出去了但被拒（401 / 403 …）
    //    ③ 200，服务端说这个区间 0 条
    //    ④ 200，服务端给了 55 条，而**我们解析成 0 条**（解析没命中）
    //  而它们界面上都是「暂无消息」。来回问与猜已经几轮了，所以换测量：
    //  把一次原样请求的四个数并排放 —— HTTP 状态 / 响应字节数 / 服务端自报条数 /
    //  我们解析到的条数。这四个数一分清，四种形态就分家了。

    /// 一次「原样」请求的结果。
    struct MessageProbe: Identifiable {
        var id: String { title }
        let title: String
        /// **token 已打码**：这份结果会被人复制出去贴给我看。
        let url: String
        /// nil = 连响应都没拿到（请求没发出去）。
        let status: Int?
        let bytes: Int
        /// JSON 顶层键 —— 「拿到的是不是我们以为的那份东西」靠它一眼判断。
        let keys: [String]
        /// 服务端自报的 `numberOfElements`（它认为它给了几条）。
        let declared: Int?
        let pages: Int?
        /// 走**真实那条路**（`parseMessages`）数出来的条数。
        /// 它与 `declared` 分开报，正是为了把形态 ③ 与形态 ④ 分开 ——
        /// 只要有一个数不同，凶手就确定了。
        let parsed: Int
        let newest: String?
        let oldest: String?
        let note: String
    }

    /// 发一次原样请求并如实报告：**不合并、不兜底、不重试**。
    /// 它不参与正常取数（正常那条路在 `getMessages`）—— 自检页要的正是「没有我们的加工」。
    func probeMessageWindow(_ title: String, from start: Date, to end: Date) async -> MessageProbe {
        let raw = messagesURL(from: start, to: end)
        let safe = Self.maskedToken(raw)
        do {
            let res = try await request(url: raw, method: "POST", body: [:],
                                        token: TokenStore.currentToken())
            return Self.describeProbe(title: title, url: safe, status: res.status, body: res.text)
        } catch let e as APIError {
            // 被拒也是数据：状态码与它自己的话原样留着（别翻译成「网络错误」）。
            return MessageProbe(title: title, url: safe, status: e.statusCode, bytes: 0, keys: [],
                                declared: nil, pages: nil, parsed: 0, newest: nil, oldest: nil,
                                note: e.message)
        } catch {
            return MessageProbe(title: title, url: safe, status: nil, bytes: 0, keys: [],
                                declared: nil, pages: nil, parsed: 0, newest: nil, oldest: nil,
                                note: error.localizedDescription)
        }
    }

    /// 把一次响应读成事实（纯函数，不联网）。
    private static func describeProbe(title: String, url: String,
                                      status: Int, body: String) -> MessageProbe {
        let dict = jsonToAny(body)
        let shell = ciObject(dict, ["Data", "data"])
        let rows = dict.map { messageArray($0) } ?? []
        let times = rows.compactMap { ciString($0, ["CreatedAt", "createdAt"]) }.sorted()
        var note = ""
        if dict == nil, !body.isEmpty {
            // 不是 JSON（服务端有时在 200 里回一页 HTML）：把开头照抄出来。
            note = "不是 JSON：" + String(body.prefix(120))
        }
        return MessageProbe(title: title, url: url, status: status,
                            bytes: body.utf8.count,
                            keys: dict?.keys.sorted() ?? [],
                            declared: ciNumberInt(shell, ["numberOfElements"]),
                            pages: ciNumberInt(shell, ["totalPages"]),
                            parsed: Self.parseMessages(body).count,
                            newest: times.last, oldest: times.first,
                            note: note)
    }

    /// 抹掉 URL 里的 token —— 这份结果是给人看、会被复制出去的。
    /// 短于 8 位不动：`replacingOccurrences(of: "")` 会把替换串插进每个字符之间。
    static func maskedToken(_ url: String) -> String {
        let t = TokenStore.currentToken()
        guard t.count >= 8 else { return url }
        return url.replacingOccurrences(of: t, with: "***")
    }

    /// 把几段窗口的响应合成一份列表：按 `stubId`（退回 `id`）去重，按时间新 → 旧。
    ///
    /// `createdAt` 是 `yyyy-MM-dd HH:mm:ss`，**字典序就是时间序**，所以直接比字符串 ——
    /// 不引入第二个日期解析器（多一个解析器就多一处「两边解释不一样」）。
    /// 同样纯函数，同样可测（`PureLogicTests.MessageWindowTests`）。
    static func mergeMessages(_ batches: [[[String: Any]]]) -> [[String: Any]] {
        var seen = Set<String>()
        var out: [[String: Any]] = []
        for batch in batches {
            for m in batch {
                let id = ciString(m, ["StubId", "stubId"]) ?? ciString(m, ["Id", "id"]) ?? ""
                // 没有 id 的行照收：去重靠 id，缺 id 不等于这条不存在。
                if !id.isEmpty, !seen.insert(id).inserted { continue }
                out.append(m)
            }
        }
        out.sort { (ciString($0, ["CreatedAt", "createdAt"]) ?? "") >
                   (ciString($1, ["CreatedAt", "createdAt"]) ?? "") }
        return out.count > messageCap ? Array(out.prefix(messageCap)) : out
    }

    static func parseMessages(_ text: String, cars: [[String: Any]] = []) -> [[String: Any]] {
        let dict = jsonToAny(text) ?? [:]
        let content = Self.messageArray(dict)
        // 空数组不能静默：把顶层键打出来。
        // 2026-09-23 那次「消息一直是空」的调查里，最贵的代价就是
        // 分不清「服务端真的没给」和「解析没命中」——两者在界面上长得一模一样。
        if content.isEmpty {
            let top = dict.keys.sorted().joined(separator: ",")
            NSLog("parseMessages: 0 条；JSON 顶层键=[\(top)] 响应长度=\(text.count)")
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

    /// 从响应里挖出消息数组。
    /// 实测形状（2026-09-22 / 09-23 抓包，两次一致）：
    ///   `{ "data": { "number":0, "numberOfElements":55, ... "content": [ {...}, ... ] } }`
    /// 即分页外壳对象 + `content[]`。其余分支是为服务端改包装留的退路，
    /// 按「命中即返回」的顺序排：命中不了就返回空数组，由调用方打日志。
    private static func messageArray(_ dict: [String: Any]) -> [[String: Any]] {
        // 外层可能直接是数组，也可能是分页对象；再外面还套过 Result 壳。
        for shellKey in ["Data", "data", "Result", "result"] {
            guard let shell = ciPick(dict, [shellKey]) else { continue }
            if let arr = shell as? [[String: Any]], !arr.isEmpty { return arr }
            if let any = shell as? [Any] {
                let arr = any.compactMap { $0 as? [String: Any] }
                if !arr.isEmpty { return arr }
            }
            if let obj = shell as? [String: Any] {
                // 分页字段名各家不同，全列上（`content` 是实测的那个）。
                for listKey in ["Content", "content", "records", "list", "rows", "items"] {
                    if let inner = ciArray(obj, [listKey]) { return inner }
                }
            }
        }
        // 没有 data 壳：数组直接挂在顶层（或顶层就是数组的 content）。
        for listKey in ["Content", "content", "records", "list", "rows", "items"] {
            if let arr = ciArray(dict, [listKey]) { return arr }
        }
        return []
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

