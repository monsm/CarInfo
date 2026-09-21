import SwiftUI
import Foundation

// =============================================================================
//  消息 —— v4 信息架构
// =============================================================================
//  ① 搜索交给系统：.searchable（iOS 的消息搜索本来就长在那里）
//  ② 筛选是「全部 / 未读」一个分段控件 + 标签胶囊，不再用两个语义不明的图标按钮
//  ③ 列表按天分组：分组标题在画布上、行在分组表面上、行间发丝线
//  ④ 行是邮件式排版：未读点 + 标题（未读加粗）+ 时间 + 正文两行 + 可展开明细
//     阅读状态不再只靠颜色：未读有圆点，标题字重也不同（颜色 + 字重双通道）。
// =============================================================================

struct MessagesView: View {
    private let store = AppStore.shared
    @State private var items: [MessageItem] = []
    @State private var loading = true
    @State private var expanded: Set<String> = []
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var searchText = ""
    @State private var filterTag: String? = nil
    @State private var showUnreadOnly = false
    @EnvironmentObject var nav: NavState

    // 本地已读持久化（无服务端 mark-read 接口，用 UserDefaults 记已读消息 ID）。
    private static let readKey = "changan_read_message_ids"
    private static var localRead: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: readKey) ?? []) }
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
            VStack(alignment: .leading, spacing: KanseiSpacing.lg) {
                filterBar

                if loading {
                    loadingState
                } else if filteredItems.isEmpty {
                    if store.carId.isEmpty {
                        DSPlaceholder(icon: "bubble.left.and.bubble.right",
                                      title: "暂无消息",
                                      message: emptyHint)
                    } else {
                        DSPlaceholder(icon: "bubble.left.and.bubble.right",
                                      title: "暂无消息",
                                      message: emptyHint,
                                      actionTitle: "重新加载") { reload() }
                    }
                } else {
                    ForEach(filteredGrouped) { group in
                        DSGroup(title: group.label,
                                trailing: group.unread > 0 ? "\(group.unread) 未读" : "\(group.items.count) 条") {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                                messageRow(item, showsSeparator: idx < group.items.count - 1)
                            }
                        }
                    }
                }
            }
            .padding(.top, KanseiSpacing.sm)
            .padding(.bottom, KanseiSpacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(KanseiPalette.background)
        .navigationTitle("消息")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜索标题或内容")
        .accessibilityLabel(Text("消息"))
        .accessibilityHint(Text("车辆通知和历史消息，支持搜索、按标签筛选与只看未读"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("全部已读") { markAllRead() }
                    .font(KanseiTypo.subheadline.weight(.semibold))
                    .foregroundStyle(KanseiPalette.ambient)
                    .disabled(items.allSatisfy { $0.read })
                    .accessibilityLabel(Text("全部标为已读"))
            }
        }
        .onAppear { loadIfNeeded() }
        .onDisappear { loadTask?.cancel(); loadTask = nil }
        .refreshable { await load() }
    }

    // MARK: - 筛选条（分段控件 + 标签胶囊）

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: KanseiSpacing.sm) {
            DSSegmented(options: [(value: false, title: "全部"), (value: true, title: "未读")],
                        selection: $showUnreadOnly)
                .padding(.top, KanseiSpacing.xs)

            if !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: KanseiSpacing.sm) {
                        tagChip(nil)
                        ForEach(allTags, id: \.self) { tag in
                            tagChip(tag)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func tagChip(_ tag: String?) -> some View {
        let selected = filterTag == tag
        let label = tag ?? "全部标签"
        return Button {
            withAnimation(KanseiMotion.count) { filterTag = selected ? nil : tag }
            DSHaptic.select()
        } label: {
            Text(label)
                .font(KanseiTypo.footnote.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? KanseiPalette.ambient : KanseiPalette.secondary)
                .padding(.horizontal, KanseiSpacing.md)
                .frame(height: 30)
                .background(Capsule().fill(selected ? KanseiPalette.ambient.opacity(0.15) : KanseiPalette.glassLight))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                ProgressView().controlSize(.small)
                Text("正在加载消息…")
                    .font(KanseiTypo.footnote)
                    .foregroundStyle(KanseiPalette.secondary)
            }
            DSSkeleton(height: 88)
            DSSkeleton(height: 88)
            DSSkeleton(height: 88)
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyHint: String {
        if store.carId.isEmpty { return "请先绑定车辆" }
        if !searchText.isEmpty { return "没有找到匹配「\(searchText)」的消息" }
        if showUnreadOnly { return "所有消息都已读" }
        if let tag = filterTag { return "「\(tag)」标签下没有消息" }
        return "车辆暂无推送消息"
    }

    // MARK: - 消息行

    private func messageRow(_ item: MessageItem, showsSeparator: Bool) -> some View {
        let isOpen = expanded.contains(item.id)
        return DSGroupRow(showsSeparator: showsSeparator) {
            Button { toggle(item) } label: {
                HStack(alignment: .top, spacing: DS.Space.sm) {
                    Circle()
                        .fill(item.read ? Color.clear : KanseiPalette.ambient)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                            Text(item.title)
                                .font(.system(size: 17, weight: item.read ? .regular : .semibold))
                                .foregroundStyle(KanseiPalette.primary)
                                .lineLimit(2)
                            if !item.tag.isEmpty {
                                Text(item.tag)
                            .font(KanseiTypo.caption2.weight(.semibold))
                            .foregroundStyle(KanseiPalette.statusColor(item.tagCls))
                            }
                            Spacer(minLength: DS.Space.sm)
                            Text(shortTime(item.time))
                            .font(KanseiTypo.footnote)
                            .foregroundStyle(KanseiPalette.secondary)
                            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(KanseiPalette.tertiary)
                        }

                        if !item.body.isEmpty {
                            Text(item.body)
                                .font(KanseiTypo.subheadline)
                                .foregroundStyle(KanseiPalette.secondary)
                                .lineLimit(isOpen ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if isOpen {
                            VStack(alignment: .leading, spacing: 6) {
                                if !item.plate.isEmpty { detailRow("car.fill", "车辆", item.plate) }
                                if !item.location.isEmpty { detailRow("mappin.and.ellipse", "位置", item.location) }
                                if !item.time.isEmpty { detailRow("clock", "时间", item.time) }
                                if !item.read { detailRow("envelope.open", "状态", "已标记为已读") }
                            }
                            .padding(.top, DS.Space.xs)
                        }
                    }
                }
                .padding(.vertical, DS.Space.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSRowButtonStyle())
            .accessibilityLabel(Text("\(item.read ? "已读" : "未读")，\(item.title)"))
            .accessibilityHint(Text(isOpen ? "双击收起详情" : "双击展开详情并标记已读"))
        }
    }

    private func detailRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            Image(safeSymbol: icon, fallback: "circle")
                .font(.system(size: 12))
                .foregroundStyle(KanseiPalette.tertiary)
                .frame(width: 16, alignment: .center)
            Text(label)
                .font(DS.Typo.caption)
                .foregroundStyle(KanseiPalette.secondary)
            Spacer(minLength: DS.Space.sm)
            Text(value)
                .font(DS.Typo.caption)
                .foregroundStyle(KanseiPalette.primary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func toggle(_ item: MessageItem) {
        withAnimation(DS.MotionTokens.value) {
            if expanded.contains(item.id) {
                expanded.remove(item.id)
            } else {
                expanded.insert(item.id)
                markRead(item.id)
            }
        }
        DSHaptic.select()
    }

    /// "2026-09-19 22:31:05" → "22:31"（列表里只需要时刻，完整时间在展开明细里）
    private func shortTime(_ t: String) -> String {
        guard let last = t.split(separator: " ").last else { return t }
        let parts = last.split(separator: ":")
        if parts.count >= 2 { return "\(parts[0]):\(parts[1])" }
        return String(last)
    }

    // MARK: - 过滤与分组

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

    /// 按天分组（今天 / 昨天 / 前天 / M月d日 / 更早），「更早」永远排在最后
    struct DayGroup: Identifiable {
        var id: String { label }
        let label: String
        let items: [MessageItem]
        let unread: Int
        let sortKey: String
    }

    private var filteredGrouped: [DayGroup] {
        let map: [String: [MessageItem]] = Dictionary(grouping: filteredItems) { dayKey($0.time) }
        let all = map.map { key, its in
            DayGroup(label: dayLabel(key),
                     items: its,
                     unread: its.filter { !$0.read }.count,
                     sortKey: its.first?.time ?? "")
        }
        let dated = all.filter { $0.label != "更早" }.sorted { $0.sortKey > $1.sortKey }
        let earlier = all.filter { $0.label == "更早" }
        return dated + earlier
    }

    private func markAllRead() {
        var s = Self.localRead
        items.forEach { s.insert($0.id) }
        Self.localRead = s
        for i in items.indices { items[i].read = true }
        DSHaptic.result(true)
        ToastManager.shared.show("已全部标为已读", icon: "checkmark.circle.fill")
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

    // MARK: - 数据

    private func reload() {
        loadTask?.cancel()
        loading = true
        loadTask = Task { await load() }
    }

    private func loadIfNeeded() {
        guard !store.carId.isEmpty else { loading = false; return }
        guard loadTask == nil || loadTask!.isCancelled else { return }
        // 与小程序一致：先渲染缓存（哪怕过期），再决定要不要联网。
        // 此前的空白根因：缓存命中与请求失败两条路都停在空列表 ——
        // 只有“网络成功”这一条路能填充 items，缓存只写不读。
        if let cached = store.caches["messages"] as? [[String: Any]], !cached.isEmpty {
            apply(cached)
        }
        if store.needsRefresh("messages") || items.isEmpty {
            loadTask = Task { await load() }
        } else {
            loading = false
        }
    }

    @MainActor
    private func load() async {
        guard !store.carId.isEmpty else { loading = false; return }
        loading = true
        do {
            let list = try await APIClient.shared.getMessages()
            apply(list)
            store.saveCache(["messages": list])
        } catch {
            // 失败时保留已渲染的缓存内容（与小程序一致），并明确告知，而不是悄悄清空
            NSLog("loadMessages: \(error.localizedDescription)")
            ToastManager.shared.show("消息获取失败，展示缓存", icon: "wifi.exclamationmark")
        }
        loading = false
    }

    /// 服务端消息行 → 界面模型。缓存与网络共用同一条映射路径，两边永远一致。
    private func apply(_ list: [[String: Any]]) {
        let readSet = Self.localRead
        items = list.enumerated().compactMap { idx, m in
            let id = ciString(m, ["Id", "id"]) ?? "row-\(idx)"
            let title = ciString(m, ["Title", "title"]) ?? "车辆通知"
            let body = Self.resolveBody(m)
            let rawLoc = ciString(m, ["Content", "content"]) ?? ""
            let location = (rawLoc != body && !rawLoc.isEmpty && rawLoc != "null" && rawLoc != "无") ? rawLoc : ""
            let cat = Self.classify(title: title, content: body.isEmpty ? rawLoc : body)
            // 未读判定与小程序对齐（pages/messages/messages.js）：服务端 ReadStatus == 1 即已读。
            // 此前多出的 `New` 字段反推分支是 App 自造的，服务端语义未知，已删除。
            // 展开过的消息记入本地已读集合（无服务端标记接口）。
            let serverRead = (ciNumber(m, ["ReadStatus", "readStatus"]) ?? 0) == 1
            let read = serverRead || readSet.contains(id)
            return MessageItem(
                id: id, title: title, body: body, location: location,
                time: ciString(m, ["CreatedAt", "createdAt"]) ?? "",
                plate: ciString(m, ["realReceiverId", "RealReceiverId"]) ?? "",
                read: read, tag: cat.tag, tagCls: cat.cls
            )
        }
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
