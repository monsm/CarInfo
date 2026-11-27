import Foundation

struct MessageItem: Identifiable {
    let id: String
    var title: String
    var body: String
    var location: String
    var time: String
    var plate: String
    var read: Bool
    var tag: String
    var tagCls: String
    var coordinate: (lat: Double, lng: Double)?
}

enum MessageDecoder {
    static func decode(_ list: [[String: Any]], readSet: Set<String>) -> [MessageItem] {
        list.enumerated().compactMap { idx, m in
            let id = ciString(m, ["StubId", "stubId"])
                ?? ciString(m, ["Id", "id"]) ?? "row-\(idx)"
            let title = ciString(m, ["Title", "title"]) ?? "车辆通知"
            let body = MessageClassifier.resolveBody(m)
            let rawLoc = ciString(m, ["Content", "content"]) ?? ""
            let location = (rawLoc != body && !rawLoc.isEmpty && rawLoc != "null" && rawLoc != "无") ? rawLoc : ""
            let cat = MessageClassifier.classify(title: title, content: body.isEmpty ? rawLoc : body)
            let serverRead: Bool
            if let rs = ciNumber(m, ["ReadStatus", "readStatus"]) {
                serverRead = rs == 1
            } else {
                serverRead = ciBool(m, ["New", "new"]) == true ? false : true
            }
            let p = AppStore.jumpParams(m)
            var coord: (lat: Double, lng: Double)? = nil
            if let lat = VM.vnum(p["lat"]), let lng = VM.vnum(p["lng"]) { coord = (lat, lng) }
            return MessageItem(
                id: id, title: title, body: body, location: location,
                time: ciString(m, ["CreatedAt", "createdAt"]) ?? "",
                plate: ciString(m, ["receiverPlate"]) ?? ciString(m, ["realReceiverId"]) ?? "",
                read: serverRead || readSet.contains(id), tag: cat.tag, tagCls: cat.cls,
                coordinate: coord
            )
        }
    }
}

enum MessageClassifier {
    static func resolveBody(_ m: [String: Any]) -> String {
        for k in ["content", "detail", "description", "msgcontent", "body", "pushcontent", "message", "msg", "text"] {
            let v = ciString(m, [k]) ?? ""
            if !v.isEmpty && v != "null" && v != "无" { return v }
        }
        return ""
    }

    static func classify(title: String, content: String) -> (tag: String, cls: String) {
        let t = title + content
        if t.range(of: "报警|故障|异常|预警|警告|胎压|低电量", options: .regularExpression) != nil {
            return ("报警", "bad")
        }
        if t.range(of: "充电|充满|电量|续航|预约充电|充电桩", options: .regularExpression) != nil {
            return ("充电", "acc")
        }
        if t.range(of: "定位|位置|行驶|轨迹|围栏", options: .regularExpression) != nil {
            return ("定位", "na")
        }
        return ("", "")
    }
}

enum MessageGrouping {
    struct DayGroup: Identifiable {
        var id: String { label }
        let label: String
        let items: [MessageItem]
        let unread: Int
        let sortKey: String
    }

    static func groups(_ items: [MessageItem]) -> [DayGroup] {
        let map: [String: [MessageItem]] = Dictionary(grouping: items) { dayKey($0.time) }
        let all = map.map { key, its in
            let newestFirst = its.sorted { $0.time > $1.time }
            return DayGroup(label: dayLabel(key),
                            items: newestFirst,
                            unread: its.filter { !$0.read }.count,
                            sortKey: its.first?.time ?? "")
        }
        let dated = all.filter { $0.label != "更早" }.sorted { $0.sortKey > $1.sortKey }
        let earlier = all.filter { $0.label == "更早" }
        return dated + earlier
    }

    static func dayKey(_ t: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "(\\d{4})[-/](\\d{1,2})[-/](\\d{1,2})"),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let range = Range(m.range, in: t) else { return "" }
        return String(t[range])
    }

    static func dayLabel(_ key: String, now: Date = Date()) -> String {
        guard !key.isEmpty else { return "更早" }
        guard let d = DateText.shared.date(key, formats: ["yyyy-MM-dd"]) else { return "更早" }
        let cal = Calendar.current
        let diff = cal.dateComponents([.day], from: d, to: now).day ?? 0
        switch diff {
        case 0: return "今天"
        case 1: return "昨天"
        case 2: return "前天"
        default:
            return DateText.shared.string(d, "M月d日")
        }
    }
}

enum MessageReadState {
    static let key = "changan_read_message_ids"

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func save(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}
