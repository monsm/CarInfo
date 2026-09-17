import SwiftUI

// 消息中心：日期分组 + 就地展开详情 + 未读计数
struct MessagesView: View {
    private let store = AppStore.shared
    @State private var items: [MessageItem] = []
    @State private var loading = true
    @State private var expanded: Set<String> = []

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
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(grouped.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group.items) { item in
                            messageRow(item)
                        }
                    } header: {
                        HStack {
                            Text(group.label).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                            if group.unread > 0 {
                                Text("\(group.unread) 未读").font(.system(size: 11)).foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("消息")
        .onAppear { Task { await load() } }
        .refreshable { await load() }
    }

    private var grouped: [(label: String, items: [MessageItem], unread: Int)] {
        let map: [String: [MessageItem]] = Dictionary(grouping: items) { dayKey($0.time) }
        let dated = map
            .map { key, its in
                (label: dayLabel(key), items: its, unread: its.filter { !$0.read }.count,
                 sortKey: its.first?.time ?? "")
            }
            .filter { $0.label != "更早" }
            .sorted { a, b in a.sortKey > b.sortKey }
        let earlier = map
            .map { key, its in
                (label: dayLabel(key), items: its, unread: its.filter { !$0.read }.count)
            }
            .filter { $0.label == "更早" }
        // 有日期分组在前（新→旧），无日期（更早）垫底。
        let result: [(label: String, items: [MessageItem], unread: Int)] =
            dated.map { ($0.label, $0.items, $0.unread) } + earlier.map { ($0.label, $0.items, $0.unread) }
        return result
    }

    private func dayKey(_ t: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "(\\d{4})[-/](\\d{1,2})[-/](\\d{1,2})")
            , let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t))
            , let range = Range(m.range, in: t) else { return "" }
        return String(t[range])
    }

    private func dayLabel(_ key: String) -> String {
        guard !key.isEmpty else { return "更早" }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let d = df.date(from: key) else { return "更早" }
        let cal = Calendar.current
        let today = Date()
        let diff = cal.dateComponents([.day], from: d, to: today).day ?? 0
        switch diff {
        case 0: return "今天"
        case 1: return "昨天"
        case 2: return "前天"
        default:
            let f = DateFormatter(); f.dateFormat = "M月d日"
            return f.string(from: d)
        }
    }

    private func messageRow(_ item: MessageItem) -> some View {
        let isOpen = expanded.contains(item.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(item.read ? Color.clear : Color.accentColor).frame(width: 8, height: 8)
                Text(item.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                if !item.tag.isEmpty {
                    Text(item.tag).font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.statusColor(item.tagCls).opacity(0.12)))
                        .foregroundStyle(Theme.statusColor(item.tagCls))
                }
                Spacer()
                if isOpen {
                    Image(systemName: "chevron.up").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            if !item.body.isEmpty {
                Text(item.body).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(isOpen ? nil : 2)
            }
            if isOpen {
                if !item.location.isEmpty {
                    KVRow(k: "地点", v: item.location)
                }
                if !item.time.isEmpty {
                    KVRow(k: "时间", v: item.time)
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            if expanded.contains(item.id) { expanded.remove(item.id) }
            else { expanded.insert(item.id) }
        }
    }

    @MainActor
    private func load() async {
        guard !store.carId.isEmpty else { return }
        loading = true
        do {
            let list = try await APIClient.shared.getMessages()
            items = list.enumerated().compactMap { idx, m in
                let id = ciString(m, ["Id", "id"]) ?? "row-\(idx)"
                let title = ciString(m, ["Title", "title"]) ?? "车辆通知"
                let body = Self.resolveBody(m)
                let rawLoc = ciString(m, ["Content", "content"]) ?? ""
                let location = (rawLoc != body && !rawLoc.isEmpty && rawLoc != "null" && rawLoc != "无") ? rawLoc : ""
                let cat = Self.classify(title: title, content: body.isEmpty ? rawLoc : body)
                return MessageItem(
                    id: id, title: title, body: body, location: location,
                    time: ciString(m, ["CreatedAt", "createdAt"]) ?? "",
                    plate: ciString(m, ["realReceiverId", "RealReceiverId"]) ?? "",
                    read: (ciNumber(m, ["ReadStatus", "readStatus"]) ?? 0) == 1.0,
                    tag: cat.tag, tagCls: cat.cls
                )
            }
            store.saveCache(["messages": list])
        } catch {
            NSLog("loadMessages: \(error.localizedDescription)")
        }
        loading = false
    }

    private static func resolveBody(_ m: [String: Any]) -> String {
        for k in ["content", "detail", "description", "msgcontent", "body", "pushcontent", "message", "msg", "text"] {
            let v = ciString(m, [k]) ?? ""
            if !v.isEmpty && v != "null" && v != "无" { return v }
        }
        return ""
    }

    private static func classify(title: String, content: String) -> (tag: String, cls: String) {
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
