import Foundation


func ciPick(_ dict: [String: Any]?, _ names: [String]) -> Any? {
    guard let dict, !dict.isEmpty else { return nil }
    var lower: [String: Any] = [:]
    for (k, v) in dict { lower[k.lowercased()] = v }
    for n in names {
        if let v = lower[n.lowercased()], v as? NSNull == nil {
            return v
        }
    }
    return nil
}

func ciString(_ dict: [String: Any]?, _ names: [String]) -> String? {
    guard let v = ciPick(dict, names) else { return nil }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}

func ciNumber(_ dict: [String: Any]?, _ names: [String]) -> Double? {
    guard let v = ciPick(dict, names) else { return nil }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) }
    return nil
}

func ciNumberInt(_ dict: [String: Any]?, _ names: [String]) -> Int? {
    guard let v = ciPick(dict, names) else { return nil }
    if let i = v as? Int { return i }
    if let n = v as? NSNumber { return n.intValue }
    if let d = v as? Double { return Int(d) }
    if let s = v as? String { return Int(s) }
    return nil
}

func ciBool(_ dict: [String: Any]?, _ names: [String]) -> Bool? {
    guard let v = ciPick(dict, names) else { return nil }
    if let b = v as? Bool { return b }
    if let s = v as? String {
        switch s.lowercased() {
        case "true", "1", "authed": return true
        case "false", "0", "unauth", "none": return false
        default: return nil
        }
    }
    if let n = v as? NSNumber { return n.boolValue }
    return nil
}

func ciArray(_ dict: [String: Any]?, _ names: [String]) -> [[String: Any]]? {
    guard let v = ciPick(dict, names) else { return nil }
    if let arr = v as? [[String: Any]] { return arr }
    if let arr = v as? [Any] { return arr.compactMap { $0 as? [String: Any] } }
    return nil
}

func ciObject(_ dict: [String: Any]?, _ names: [String]) -> [String: Any]? {
    guard let v = ciPick(dict, names) else { return nil }
    return v as? [String: Any]
}

func unwrapEntity(_ any: Any?) -> [String: Any]? {
    if let arr = any as? [Any] { return arr.compactMap { $0 as? [String: Any] }.first }
    guard let dict = any as? [String: Any] else { return nil }
    let wrapperKeys: Set<String> = ["carlocationresp", "data", "result", "entity", "row", "body"]
    if dict.count == 1, let (k, v) = dict.first, wrapperKeys.contains(k.lowercased()) {
        if let inner = v as? [String: Any] { return inner.isEmpty ? dict : inner }
        if let arr = v as? [Any] { return arr.compactMap { $0 as? [String: Any] }.first ?? dict }
    }
    return dict
}


func ciVal(_ cache: [String: Any?], _ key: String) -> [String: Any]? {
    (cache[key]) as? [String: Any]
}
func nestedObject(_ o: [String: Any]?, _ key: String) -> [String: Any]? {
    guard let o else { return nil }
    return (o[key]) as? [String: Any]
}

func cacheObject(_ cache: [String: Any?], _ key: String) -> [String: Any]? {
    (cache[key]) as? [String: Any]
}

func jsonToAny(_ text: String) -> [String: Any]? {
    jsonValue(text) as? [String: Any]
}

func jsonValue(_ text: String) -> Any? {
    guard let data = text.data(using: .utf8),
          let any = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments])
    else { return nil }
    return any
}


struct TokenConfig: Codable {
    var accessToken: String
    var refreshToken: String
    var mobile: String
    var updateTime: String?
    var expiresAt: Date?
}
