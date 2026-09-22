import SwiftUI
import Foundation

// =============================================================================
//  车辆消息与事件 —— 出行页的一节（原「消息」页）
//
//  批 7 把这一页并进「出行」：消息里最多的就是点火/熄火/控制事件，
//  它们和行程时间轴讲的是同一件事（车何时动过、在哪里）。
//  它现在只提供内容（`MessagesSection`），页面外壳归 `TripsEventsView`。
// =============================================================================
//  ① 搜索交给系统：.searchable（iOS 的消息搜索本来就长在那里）
//  ② 筛选是「全部 / 未读」一个分段控件 + 标签胶囊，不再用两个语义不明的图标按钮
//  ③ 列表按天分组：分组标题在画布上、行在分组表面上、行间发丝线
//  ④ 行是邮件式排版：未读点 + 标题（未读加粗）+ 时间 + 正文两行 + 可展开明细
//     阅读状态不再只靠颜色：未读有圆点，标题字重也不同（颜色 + 字重双通道）。
// =============================================================================

struct MessagesSection: View {
    private let store = AppStore.shared
    @State private var items: [MessageItem] = []
    @State private var loading = true
    @State private var expanded: Set<String> = []
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var searchText = ""
    @State private var filterTag: String? = nil
    @State private var showUnreadOnly = false

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
        /// 事件坐标（来自 `jumpParam.uriParams`）—— 有点才能「在图上看看」。
        /// **不存**路径：车端不上传轨迹（`isPrivacyDrvingHistory: 1`）。
        var coordinate: (lat: Double, lng: Double)?
    }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                // 「全部已读」原来是导航栏按钮，并入之后这一节没有自己的导航栏。
                DSSectionHeader(title: "车辆消息与事件",
                                trailing: items.allSatisfy { $0.read } ? nil : "全部已读",
                                action: items.allSatisfy { $0.read } ? nil : { markAllRead() })

                // 搜索原来挂在 `.searchable` 上（消息 App 的写法）。
                // 这一节不是页面，所以搜索框回到内容里。
                searchField
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
        }
        .onAppear { loadIfNeeded() }
        .onDisappear { loadTask?.cancel(); loadTask = nil }
    }

    /// 搜索框：与全局搜索同一个图形语汇（放大镜 + 输入框），不再向导航栏要位置。
    private var searchField: some View {
        HStack(spacing: TokensSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(TokensTypo.fixed(15))
                .foregroundStyle(TokensPalette.tertiary)
            TextField("搜索标题或内容", text: $searchText)
                .font(TokensTypo.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(Text("搜索消息"))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(TokensTypo.fixed(15))
                        .foregroundStyle(TokensPalette.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("清除搜索"))
            }
        }
        .padding(.horizontal, TokensSpacing.md)
        .frame(height: TokensSpacing.row)
        .background(RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
            .fill(TokensPalette.nightSurface))
    }

    // MARK: - 筛选条（分段控件 + 标签胶囊）

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            DSSegmented(options: [(value: false, title: "全部"), (value: true, title: "未读")],
                        selection: $showUnreadOnly)
                .padding(.top, TokensSpacing.xs)

            if !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TokensSpacing.sm) {
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
            withAnimation(TokensMotion.count) { filterTag = selected ? nil : tag }
            TokensHaptic.select()
        } label: {
            Text(label)
                .font(TokensTypo.footnote.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? TokensPalette.ambient : TokensPalette.secondary)
                .padding(.horizontal, TokensSpacing.md)
                .frame(height: 30)
                .background(Capsule().fill(selected ? TokensPalette.ambient.opacity(0.15) : TokensPalette.glassLight))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.md) {
            HStack(spacing: TokensSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("正在加载消息…")
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
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
                HStack(alignment: .top, spacing: TokensSpacing.sm) {
                    Circle()
                        .fill(item.read ? Color.clear : TokensPalette.ambient)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: TokensSpacing.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                            Text(item.title)
                                // 未读靠**字重**而不是颜色（颜色已经全给了语义状态）
                                .font(TokensTypo.body.weight(item.read ? .regular : .semibold))
                                .foregroundStyle(TokensPalette.primary)
                                .lineLimit(2)
                            if !item.tag.isEmpty {
                                Text(item.tag)
                            .font(TokensTypo.caption2.weight(.semibold))
                            .foregroundStyle(TokensPalette.statusColor(item.tagCls))
                            }
                            Spacer(minLength: TokensSpacing.sm)
                            Text(shortTime(item.time))
                            .font(TokensTypo.footnote)
                            .foregroundStyle(TokensPalette.secondary)
                            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                                .font(TokensTypo.fixed(11, weight: .semibold))
                                .foregroundStyle(TokensPalette.tertiary)
                        }

                        if !item.body.isEmpty {
                            Text(item.body)
                                .font(TokensTypo.subheadline)
                                .foregroundStyle(TokensPalette.secondary)
                                .lineLimit(isOpen ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if isOpen {
                            VStack(alignment: .leading, spacing: 6) {
                                if !item.plate.isEmpty { detailRow("car.fill", "车辆", item.plate) }
                                if !item.location.isEmpty { detailRow("mappin.and.ellipse", "位置", item.location) }
                                if !item.time.isEmpty { detailRow("clock", "时间", item.time) }
                                if !item.read { detailRow("envelope.open", "状态", "已标记为已读") }
                                // 事件自带坐标时才给这个入口：点一下把地图镜头移过去。
                                // 这里只给「地点」，不给「路径」—— 车端不上传轨迹。
                                if let c = item.coordinate {
                                    Button {
                                        store.mapFocus = AppStore.MapFocus(lat: c.lat, lng: c.lng,
                                                                           label: item.title)
                                        // 读单例而不是环境对象：这一节不是页面，
                                        // 不保证环境里有 NavState（`MapSpineView` 同此约定）。
                                        NavState.shared.popToRoot()
                                        TokensHaptic.select()
                                    } label: {
                                        HStack(spacing: TokensSpacing.sm) {
                                            Image(safeSymbol: "map", fallback: "location")
                                                .font(TokensTypo.fixed(12))
                                            Text("在图上看看")
                                                .font(TokensTypo.caption.weight(.semibold))
                                        }
                                        .foregroundStyle(TokensPalette.ambient)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.top, TokensSpacing.xs)
                        }
                    }
                }
                .padding(.vertical, TokensSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSRowButtonStyle())
            .accessibilityLabel(Text("\(item.read ? "已读" : "未读")，\(item.title)"))
            .accessibilityHint(Text(isOpen ? "双击收起详情" : "双击展开详情并标记已读"))
        }
    }

    private func detailRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
            Image(safeSymbol: icon, fallback: "circle")
                .font(TokensTypo.fixed(12))
                .foregroundStyle(TokensPalette.tertiary)
                .frame(width: 16, alignment: .center)
            Text(label)
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.secondary)
            Spacer(minLength: TokensSpacing.sm)
            Text(value)
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.primary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func toggle(_ item: MessageItem) {
        withAnimation(TokensMotion.value) {
            if expanded.contains(item.id) {
                expanded.remove(item.id)
            } else {
                expanded.insert(item.id)
                markRead(item.id)
            }
        }
        TokensHaptic.select()
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
        TokensHaptic.result(true)
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
            // 幂等键用服务端的 `stubId`（`1:<uuid>:<时间戳>:<序号>`），它是为去重而生的；
            // 退回 `id`，再退回行号。同一件事在两次拉取里必须是**同一个 id**，
            // 否则「已读」状态与事件去重都会失效。
            let id = ciString(m, ["StubId", "stubId"])
                ?? ciString(m, ["Id", "id"]) ?? "row-\(idx)"
            let title = ciString(m, ["Title", "title"]) ?? "车辆通知"
            let body = Self.resolveBody(m)
            let rawLoc = ciString(m, ["Content", "content"]) ?? ""
            let location = (rawLoc != body && !rawLoc.isEmpty && rawLoc != "null" && rawLoc != "无") ? rawLoc : ""
            let cat = Self.classify(title: title, content: body.isEmpty ? rawLoc : body)
            // 未读（红点）判据用 `new`：2026-09-22 那份报文里 5 条事件全是
            // `readStatus: 0` 而 `new: false`，车主的手机上**没有**红点 ——
            // 说明 `readStatus` 在这套服务里并没有被用起来，`new` 才是红点的真相。
            // 两个字段都缺时才退回旧判据（ReadStatus == 1 即已读）。
            // 展开过的消息记入本地已读集合（服务端没有 mark-read 接口）。
            let isNew = ciBool(m, ["New", "new"])
            let serverRead = isNew.map { !$0 }
                ?? ((ciNumber(m, ["ReadStatus", "readStatus"]) ?? 0) == 1)
            let p = AppStore.jumpParams(m)
            var coord: (lat: Double, lng: Double)? = nil
            if let lat = VM.vnum(p["lat"]), let lng = VM.vnum(p["lng"]) { coord = (lat, lng) }
            return MessageItem(
                id: id, title: title, body: body, location: location,
                time: ciString(m, ["CreatedAt", "createdAt"]) ?? "",
                plate: ciString(m, ["realReceiverId"]) ?? "",
                read: serverRead || readSet.contains(id), tag: cat.tag, tagCls: cat.cls,
                coordinate: coord
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
