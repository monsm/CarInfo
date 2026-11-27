import Foundation
import Security


enum APIConfig {
    static let authURL = "https://scrm.changan.com.cn/app-m/prod-api/auth/cac"
    static let baseURL = "https://m.iov.changan.com.cn"
    static let userAgent = "changAnFan/4.6.3 (iPhone; iOS 26.5; Scale/3.00)"
    static let registrationId = "2c8735c5a6f753229aec45789dcd3a1f4"
    static let version = "4.6.3"
}


let tokenStorageKey = "car_token_config"
let cacheStorageKey = "car_data_cache"
let rawLogStorageKey = "changan_raw_log"

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
        SecItemDelete(q as CFDictionary)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
        UserDefaults.standard.removeObject(forKey: tokenStorageKey)
    }

    static func read() -> TokenConfig? {
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
        let logged = !cfg.accessToken.isEmpty
        let mob = cfg.mobile
        Task { @MainActor in
            AppStore.shared.isLoggedIn = logged
            AppStore.shared.phone = mob
        }
    }
}


struct APIError: LocalizedError {
    let message: String
    var expired: Bool = false
    var noRefresh: Bool = false
    var statusCode: Int? = nil

    var errorDescription: String? { message }
}


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

        if retryable {
            let op = "\(method) \(url)"
            return try await Retrier.global.run(oneShot, label: op)
        }
        return try await oneShot()
    }


    func unpack(_ text: String, expectData: Bool = true) -> (ok: Bool, data: Any?, msg: String) {
        guard let dict = jsonToAny(text) else { return (false, nil, "响应解析失败") }
        let code = ciNumber(dict, ["Code", "code"])
        let success = ciBool(dict, ["Success"])
        let ok = (success == true) || (code == 200) || (code == 0)
        let data = ciPick(dict, ["Data", "data"])
        let msg = ciString(dict, ["Msg", "msg", "Message", "message"]) ?? ""
        return (ok, data, msg)
    }


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

    func smsSend(phone: String, picCode: String) async -> (ok: Bool, noRecord: Bool, msg: String) {
        let params = buildParams(phone: phone, extra: [
            "smsCode": "null", "picCode": picCode, "code": picCode, "biz": "null",
            "tel": phone, "picKey": phone
        ])
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

    func getPicCode(phone: String) async -> Data? {
        do {
            let res = try await request(url: "\(APIConfig.authURL)/picSend?picKey=\(phone.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? phone)",
                                        method: "GET")
            return res.body
        } catch {
            RawLogStore.shared.logError(method: "GET", url: "picSend", message: error.localizedDescription)
            return nil
        }
    }

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
            guard unpacked.ok, let d = unwrapEntity(unpacked.data) else { return nil }
            return d
        }
    }

    static let messageDays = 30

    static let messageSliceDays = 7

    static let messageCap = 300

    func getMessages() async throws -> [[String: Any]] {
        let cars = await MainActor.run { AppStore.shared.cars }
        return try await withRefresh {
            let api = APIClient.shared
            let windows = Self.messageWindows(days: Self.messageDays,
                                              sliceDays: Self.messageSliceDays)

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

    static func messageWindows(days: Int, sliceDays: Int = 7,
                               now: Date = Date()) -> [(start: Date, end: Date)] {
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

    private func messagesText(from start: Date, to end: Date) async throws -> String {
        let res = try await request(url: messagesURL(from: start, to: end), method: "POST", body: [:],
                                    token: TokenStore.currentToken())
        return res.text
    }

    private func messagesURL(from start: Date, to end: Date) -> String {
        let f: (Date) -> String = { d in
            DateText.shared.string(d, "yyyy-MM-dd HH:mm:ss", locale: "en_US_POSIX")
        }
        let enc: (String) -> String = { s in s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
        return "\(APIConfig.baseURL)/appserver/api/information/pageReceiverInfoByTime?actionType=2&page=&limit=2000&startTime=\(enc(f(start)))&endTime=\(enc(f(end)))&token=\(TokenStore.currentToken())"
    }


    struct MessageProbe: Identifiable {
        var id: String { title }
        let title: String
        let url: String
        let status: Int?
        let bytes: Int
        let keys: [String]
        let declared: Int?
        let pages: Int?
        let parsed: Int
        let newest: String?
        let oldest: String?
        let note: String
    }

    func probeMessageWindow(_ title: String, from start: Date, to end: Date) async -> MessageProbe {
        let raw = messagesURL(from: start, to: end)
        let safe = Self.maskedToken(raw)
        do {
            let res = try await request(url: raw, method: "POST", body: [:],
                                        token: TokenStore.currentToken())
            return Self.describeProbe(title: title, url: safe, status: res.status, body: res.text)
        } catch let e as APIError {
            return MessageProbe(title: title, url: safe, status: e.statusCode, bytes: 0, keys: [],
                                declared: nil, pages: nil, parsed: 0, newest: nil, oldest: nil,
                                note: e.message)
        } catch {
            return MessageProbe(title: title, url: safe, status: nil, bytes: 0, keys: [],
                                declared: nil, pages: nil, parsed: 0, newest: nil, oldest: nil,
                                note: error.localizedDescription)
        }
    }

    private static func describeProbe(title: String, url: String,
                                      status: Int, body: String) -> MessageProbe {
        let dict = jsonToAny(body)
        let shell = ciObject(dict, ["Data", "data"])
        let rows = dict.map { messageArray($0) } ?? []
        let times = rows.compactMap { ciString($0, ["CreatedAt", "createdAt"]) }.sorted()
        var note = ""
        if dict == nil, !body.isEmpty {
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

    static func maskedToken(_ url: String) -> String {
        let t = TokenStore.currentToken()
        guard t.count >= 8 else { return url }
        return url.replacingOccurrences(of: t, with: "***")
    }

    static func mergeMessages(_ batches: [[[String: Any]]]) -> [[String: Any]] {
        var seen = Set<String>()
        var out: [[String: Any]] = []
        for batch in batches {
            for m in batch {
                let id = ciString(m, ["StubId", "stubId"]) ?? ciString(m, ["Id", "id"]) ?? ""
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
        if content.isEmpty {
            let top = dict.keys.sorted().joined(separator: ",")
            NSLog("parseMessages: 0 条；JSON 顶层键=[\(top)] 响应长度=\(text.count)")
        }
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
                    copy["realReceiverId"] = p
                }
            }
            return copy
        }
    }

    private static func messageArray(_ dict: [String: Any]) -> [[String: Any]] {
        for shellKey in ["Data", "data", "Result", "result"] {
            guard let shell = ciPick(dict, [shellKey]) else { continue }
            if let arr = shell as? [[String: Any]], !arr.isEmpty { return arr }
            if let any = shell as? [Any] {
                let arr = any.compactMap { $0 as? [String: Any] }
                if !arr.isEmpty { return arr }
            }
            if let obj = shell as? [String: Any] {
                for listKey in ["Content", "content", "records", "list", "rows", "items"] {
                    if let inner = ciArray(obj, [listKey]) { return inner }
                }
            }
        }
        for listKey in ["Content", "content", "records", "list", "rows", "items"] {
            if let arr = ciArray(dict, [listKey]) { return arr }
        }
        return []
    }

    func sendControlCommand(cmd: String, carId: String, pin: String, temperature: Int = 17) async throws -> [String: Any]? {
        try await withRefresh { [self] in
            var url = "\(APIConfig.baseURL)/api/car/control?pin=\(pin)&cmd=\(cmd)&carId=\(carId)&phoneType=&phoneId=&token=\(TokenStore.currentToken())"
            if cmd == "OpenAir" { url += "&temperature=\(temperature)" }
            let res = try await request(url: url, method: "POST", body: [:], retryable: false)
            let (ok, data, msg) = unpack(res.text)
            guard ok else { throw APIError(message: msg.isEmpty ? "执行失败" : msg) }
            return data as? [String: Any]
        }
    }

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

actor AtomicTaskHolder {
    private var task: Task<Result<Void, Error>, Never>?

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

