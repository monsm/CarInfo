import SwiftUI
import Foundation

// 消息中心：日期分组 + 就地展开详情 + 未读计数
struct MessagesView: View {
    private let store = AppStore.shared
    @State private var items: [MessageItem] = []
    @State private var loading = true
    @State private var expanded: Set<String> = []
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var isRefreshing = false            // 下拉刷新涟漪标志
    // #NEW-5 搜索和筛选
    @State private var searchText = ""
    @State private var filterTag: String? = nil
    @State private var showUnreadOnly = false
    @EnvironmentObject var nav: NavState                // C3: 用于 pushNavigation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // 本地已读持久化（无服务端 mark-read 接口，用 UserDefaults 记已读消息 ID）。
    private static let readKey = "changan_read_message_ids"
    private static var localRead: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: readKey) ?? [])
        }
        set { UserDefaults.standard.set(Array(newValue), forKey: readKey) }
    }

    private func markRead(_ id: String) {
        guard !id.isEmpty else { return }
        var s = Self.localRead
        guard s.insert(id).inserted else { return }
        Self.localRead = s
        for i in items.indices { if items[i].id == id { items[i].read = true } }
    }

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
            // #NEW-5 搜索和筛选栏
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    TextField("搜索消息…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.caption)
                    Button(action: { filterTag = nil }) {
                        Image(systemName: filterTag != nil ? "xmark.circle.fill" : "line.3.horizontal.decrease")
                            .font(Theme.caption)
                            .foregroundStyle(filterTag != nil ? Color.accent : .secondary)
                    }
                    .accessibilityLabel(Text(filterTag != nil ? "清除筛选" : "按标签筛选"))
                    Button(action: { showUnreadOnly.toggle() }) {
                        Image(systemName: showUnreadOnly ? "eye.fill" : "eye.slash.fill")
                            .font(Theme.caption)
                            .foregroundStyle(showUnreadOnly ? Color.accent : .secondary)
                    }
                    .accessibilityLabel(Text(showUnreadOnly ? "显示全部消息" : "仅显示未读"))
                }
                // 筛选标签胶囊
                if !allTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button(filterTag == nil ? "全部" : allTags.first ?? "全部") {
                                filterTag = nil
                            }
                            .font(Theme.micro.bold())
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(filterTag == nil ? Color.accent : Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(filterTag == nil ? .white : .secondary)
                            ForEach(allTags.dropFirst(), id: \.self) { tag in
                                Button(tag) {
                                    filterTag = filterTag == tag ? nil : tag
                                }
                                .font(Theme.micro.bold())
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(filterTag == tag ? Color.accent : Color.secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(filterTag == tag ? .white : .secondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)

            if loading {
                PageLoadingView("正在加载消息…")
            } else if filteredItems.isEmpty {
                PageEmptyView("暂无消息", subtitle: searchText.isEmpty ? "车辆暂无推送消息" : "没有找到匹配的消息", icon: "bubble.left.and.bubble.right")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(filteredGrouped.enumerated()), id: \.offset) { _, group in
                        Section {
                            ForEach(group.items) { item in
                                messageRow(item)
                            }
                        } header: {
                            HStack(spacing: 8) {
                                Text(group.label)
                                    .font(.headline.bold())
                                    .foregroundStyle(.secondary)
                                if group.unread > 0 {
                                    Text("\(group.unread) 未读")
                                        .font(Theme.micro.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.accent))
                                }
                                Spacer()
                            }
                            .padding(.top, 6)
                        }
                    }
                }
                
            }
            
        }
        .scrollBounceBehavior(.basedOnSize)
        .pageBackground(Color.accent)
        .navigationTitle("消息")
            .navBarStyle()
            .accessibilityLabel(Text("消息"))
            .accessibilityHint(Text("车辆通知和历史消息列表，支持搜索和筛选"))
        .toolbar {
            // #NEW-5 全部已读按钮
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    markAllRead()
                } label: {
                    Text("全部已读")
                        .font(Theme.font(.caption as Font).bold())
                        .foregroundStyle(Color.accent)
                }
                .accessibilityLabel(Text("全部已读"))
            }
        }
        .onAppear { loadIfNeeded() }
        .onDisappear { loadTask?.cancel(); loadTask = nil }
        .refreshable { isRefreshing = true; await load(); isRefreshing = false }
        .glassRefreshRipple(isRefreshing: $isRefreshing)
    }

    // #NEW-5 过滤后的消息列表
    private var filteredItems: [MessageItem] {
        items.filter { item in
            let matchSearch = searchText.isEmpty ||
                item.title.localizedCaseInsensitiveContains(searchText) ||
                item.body.localizedCaseInsensitiveContains(searchText)
            let matchTag = filterTag == nil || item.tag == filterTag
            let matchUnread = !showUnreadOnly || !item.read
            return matchSearch && matchTag && matchUnread
        }
    }

    private var allTags: [String] {
        let tags = Set(items.map { $0.tag }).filter { !$0.isEmpty }
        return Array(tags).sorted()
    }

    private var filteredGrouped: [(label: String, items: [MessageItem], unread: Int)] {
        let map: [String: [MessageItem]] = Dictionary(grouping: filteredItems) { dayKey($0.time) }
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
        return dated.map { ($0.label, $0.items, $0.unread) } + earlier.map { ($0.label, $0.items, $0.unread) }
    }

    // #NEW-5 全部已读
    private func markAllRead() {
        var s = Self.localRead
        items.forEach { s.insert($0.id) }
        Self.localRead = s
        for i in items.indices { items[i].read = true }
        ToastManager.shared.show("已全部标为已读", icon: "checkmark.circle.fill")
    }

    // MARK: 分组（今天/昨天/前天/M月d日/更早）
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
        return VStack(alignment: .leading, spacing: 0) {
            // 顶部：标签 + 未读指示 + 标题
            HStack(spacing: 10) {
                if !item.read {
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 10, height: 10)
                        .shadow(color: Color.accent.opacity(0.5), radius: 4)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 10, height: 10)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(Theme.h4)
                            .lineLimit(1)
                        if !item.tag.isEmpty {
                            Text(item.tag)
                                .font(Theme.micro.bold())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Theme.statusColor(item.tagCls).opacity(0.12)))
                                .foregroundStyle(Theme.statusColor(item.tagCls))
                        }
                        Spacer()
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(Theme.font(.footnote as Font).bold())
                            .foregroundStyle(.tertiary)
                    }
                    if !item.time.isEmpty {
                        Text(item.time)
                            .font(Theme.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // 正文
            if !item.body.isEmpty {
                Text(item.body)
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(isOpen ? nil : 2)
                    .padding(.top, 8)
            }
            // 展开详情
            if isOpen && (!item.location.isEmpty || !item.time.isEmpty) {
                VStack(spacing: 6) {
                    if !item.location.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "map.pin").font(Theme.caption).foregroundStyle(.tertiary)
                            Text(item.location).font(Theme.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !item.time.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "clock").font(Theme.caption).foregroundStyle(.tertiary)
                            Text(item.time).font(Theme.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !item.plate.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "car.fill").font(Theme.caption).foregroundStyle(Color.accent)
                            Text(item.plate).font(Theme.font(.caption as Font).bold(), design: .monospaced)
                                .foregroundStyle(Color.accent)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeCompress()
        .glassCard(corner: 20)
        .glassLongPressDeform()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                if expanded.contains(item.id) { expanded.remove(item.id) }
                else {
                    expanded.insert(item.id)
                    markRead(item.id)
                }
            }
        }
    }

    private func loadIfNeeded() {
        guard !store.carId.isEmpty else { return }
        guard loadTask == nil || loadTask!.isCancelled else { return }
        if store.needsRefresh("messages") {
            loadTask = Task { await load() }
        }
    }

    @MainActor
    private func load() async {
        guard !store.carId.isEmpty else { return }
        loading = true
        do {
            let list = try await APIClient.shared.getMessages()
            let readSet = Self.localRead
            items = list.enumerated().compactMap { idx, m in
                let id = ciString(m, ["Id", "id"]) ?? "row-\(idx)"
                let title = ciString(m, ["Title", "title"]) ?? "车辆通知"
                let body = Self.resolveBody(m)
                let rawLoc = ciString(m, ["Content", "content"]) ?? ""
                let location = (rawLoc != body && !rawLoc.isEmpty && rawLoc != "null" && rawLoc != "无") ? rawLoc : ""
                let cat = Self.classify(title: title, content: body.isEmpty ? rawLoc : body)
                // 未读判定：服务端用 `new` 字段标记新消息（日志证实 `new:false` 即已读），
                // 其次 `readStatus` 非 0 视为已读，最后并本地已读集合（展开过即记入）。
                let isNew = ciBool(m, ["New", "new"]) ?? false
                let serverRead = (ciNumber(m, ["ReadStatus", "readStatus"]) ?? 0) != 0 || !isNew
                let read = serverRead || readSet.contains(id)
                return MessageItem(
                    id: id, title: title, body: body, location: location,
                    time: ciString(m, ["CreatedAt", "createdAt"]) ?? "",
                    plate: ciString(m, ["realReceiverId", "RealReceiverId"]) ?? "",
                    read: read, tag: cat.tag, tagCls: cat.cls
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
