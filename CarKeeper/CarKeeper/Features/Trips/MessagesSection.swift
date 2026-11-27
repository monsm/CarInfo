import SwiftUI
import Foundation



struct MessagesSection: View {
    private let store = AppStore.shared
    @State private var items: [MessageItem] = []
    @State private var loading = true
    @State private var expanded: Set<String> = []
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var lastError = ""
    @State private var searchText = ""
    @State private var filterTag: String? = nil
    @State private var showUnreadOnly = false
    @State private var fullBodies: Set<String> = []
    @Environment(\.cardViewport) private var cardViewport

    @Binding var shownDays: Int

    private static let needLogin = "请先登录，登录后才会收到车辆事件"

    private func markRead(_ id: String) {
        guard !id.isEmpty else { return }
        var s = MessageReadState.load()
        guard s.insert(id).inserted else { return }
        MessageReadState.save(s)
        for i in items.indices { if items[i].id == id { items[i].read = true } }
    }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                DSSectionHeader(trailing: items.allSatisfy { $0.read } ? nil : "全部已读",
                                action: items.allSatisfy { $0.read } ? nil : { markAllRead() })

                searchField
                filterBar

                if loading {
                    loadingState
                } else if filteredItems.isEmpty {
                    DSPlaceholder(icon: "bubble.left.and.bubble.right",
                                  title: lastError.isEmpty ? "暂无消息" : "消息获取失败",
                                  message: lastError.isEmpty ? emptyHint : lastError,
                                  actionTitle: "重新加载") { reload() }
                } else {
                    ForEach(visibleGrouped) { group in
                        DSGroup(title: group.label,
                                trailing: group.unread > 0 ? "\(group.unread) 未读" : "\(group.items.count) 条") {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                                messageRow(item, showsSeparator: idx < group.items.count - 1)
                            }
                        }
                    }
                    if visibleGrouped.count < filteredGrouped.count {
                        DSGroup {
                            DSGroupRow(showsSeparator: false) {
                                moreDaysNote(filteredGrouped.count - visibleGrouped.count)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { loadIfNeeded() }
        .onChange(of: store.carId) { _, newId in
            guard !newId.isEmpty else { return }
            loadIfNeeded()
        }
        .onDisappear { loadTask?.cancel(); loadTask = nil }
    }

    private var searchField: some View {
        HStack(spacing: TokensSpacing.sm) {
            Image(safeSymbol: "magnifyingglass", fallback: "magnifyingglass")
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
                    Image(safeSymbol: "xmark.circle.fill", fallback: "xmark.circle.fill")
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
            .fill(TokensPalette.panel))
    }


    private var filterBar: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            DSSegmentPicker(options: [(value: false, title: "全部"), (value: true, title: "未读")],
                            selection: $showUnreadOnly,
                            label: "消息筛选")
                .padding(.top, TokensSpacing.xs)

            if !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TokensSpacing.sm) {
                        tagChip(nil)
                        ForEach(allTags, id: \.self) { tag in
                            tagChip(tag)
                        }
                    }
                    .padding(.vertical, TokensSpacing.xxs)
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
                .background(Capsule().fill(selected ? TokensPalette.ambient.opacity(0.15) : TokensPalette.fillSubtle))
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
        return "近 \(APIClient.messageDays) 天没有事件"
    }


    private func messageRow(_ item: MessageItem, showsSeparator: Bool) -> some View {
        let isOpen = expanded.contains(item.id)
        return DSGroupRow(showsSeparator: showsSeparator) {
            withHint(Text(isOpen ? "双击收起详情" : "双击展开详情并标记已读")) {
                rowButton(item, isOpen: isOpen)
            }
        }
    }

    private func rowButton(_ item: MessageItem, isOpen: Bool) -> some View {
        Button { toggle(item) } label: {
            HStack(alignment: .top, spacing: TokensSpacing.sm) {
                Circle()
                    .fill(item.read ? Color.clear : TokensPalette.ambient)
                    .frame(width: 8, height: 8)
                    .padding(.top, TokensSpacing.sm)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: TokensSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                        Text(item.title)
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
                        Image(safeSymbol: isOpen ? "chevron.up" : "chevron.down",
                                fallback: isOpen ? "chevron.up" : "chevron.down")
                            .font(TokensTypo.fixed(11, weight: .semibold))
                            .foregroundStyle(TokensPalette.tertiary)
                    }

                    if !item.body.isEmpty {
                        let bp = bodyPlan(item, open: isOpen)
                        Text(bp.text)
                            .font(TokensTypo.subheadline)
                            .foregroundStyle(TokensPalette.secondary)
                            .lineLimit(bp.lineLimit)
                            .fixedSize(horizontal: false, vertical: true)
                        if bp.restLines > 0 {
                            DSCardMoreRow(rest: bp.restLines, unit: "行",
                                          screens: bp.screens, open: false) {
                                withAnimation(TokensMotion.count) { _ = fullBodies.insert(item.id) }
                            }
                        } else if isOpen, bp.truncatable, fullBodies.contains(item.id) {
                            DSCardMoreRow.collapse {
                                withAnimation(TokensMotion.count) { _ = fullBodies.remove(item.id) }
                            }
                        }
                    }

                    if isOpen {
                        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                            if !item.plate.isEmpty { detailRow("car.fill", "车辆", item.plate) }
                            if !item.location.isEmpty { detailRow("mappin.and.ellipse", "位置", item.location) }
                            if !item.time.isEmpty { detailRow("clock", "时间", item.time) }
                            if !item.read { detailRow("envelope.open", "状态", "已标记为已读") }
                            if let c = item.coordinate {
                                Button {
                                    store.mapFocus = AppStore.MapFocus(lat: c.lat, lng: c.lng,
                                                                       label: item.title)
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
                                .padding(.top, TokensSpacing.xxs)
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
    }

    private func withHint<V: View>(_ hint: Text, _ content: () -> V) -> some View {
        content().accessibilityHint(hint)
    }


    private var fitWidth: CGFloat { CardFit.contentWidth(cardViewport) }

    private struct BodyPlan {
        var text: String
        var lineLimit: Int?
        var restLines: Int
        var screens: Double
        var truncatable: Bool
    }

    private func bodyPlan(_ item: MessageItem, open: Bool) -> BodyPlan {
        guard open else {
            return BodyPlan(text: item.body, lineLimit: 2, restLines: 0,
                            screens: 0, truncatable: false)
        }
        let plan = CardFit.plan(text: item.body, style: .subheadline, width: fitWidth,
                                viewport: cardViewport, reserved: chromeHeight(item))
        if fullBodies.contains(item.id) {
            return BodyPlan(text: item.body, lineLimit: nil, restLines: 0,
                            screens: plan.screens, truncatable: plan.truncatable)
        }
        return BodyPlan(text: plan.text, lineLimit: nil, restLines: plan.restLines,
                        screens: plan.screens, truncatable: plan.truncatable)
    }

    private func chromeHeight(_ item: MessageItem) -> CGFloat {
        let right = item.tag.isEmpty ? shortTime(item.time)
                                     : "\(item.tag) \(shortTime(item.time))"
        let rightW = CardFit.textWidth(right, style: .footnote)
        let titleW = max(0, fitWidth - rightW - TokensSize.iconColumn - TokensSpacing.sm)
        var cost = CardFit.textHeight(item.title, style: .body, width: titleW, cap: 2)
        cost += TokensSpacing.xs
        cost += TokensSpacing.md * 2
        cost += TokensSpacing.xs
        var rows = 0
        if !item.plate.isEmpty { rows += 1 }
        if !item.location.isEmpty { rows += 1 }
        if !item.time.isEmpty { rows += 1 }
        if !item.read { rows += 1 }
        if rows > 0 {
            cost += CGFloat(rows) * (CardFit.Typo.footnote.lineHeight + TokensSpacing.sm)
            cost += CGFloat(rows - 1) * TokensSpacing.sm
        }
        if item.coordinate != nil { cost += TokensSpacing.md }
        return cost
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

    private func shortTime(_ t: String) -> String {
        guard let last = t.split(separator: " ").last else { return t }
        let parts = last.split(separator: ":")
        if parts.count >= 2 { return "\(parts[0]):\(parts[1])" }
        return String(last)
    }


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

    private var filteredGrouped: [MessageGrouping.DayGroup] {
        MessageGrouping.groups(filteredItems)
    }

    private func moreDaysNote(_ rest: Int) -> some View {
        HStack(spacing: TokensSpacing.sm) {
            Image(safeSymbol: "arrow.down.circle", fallback: "arrow.down.circle")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.tertiary)
            Text("往下滑，更早的 \(rest) 天接着出来")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, TokensSpacing.snug)
    }

    private func markAllRead() {
        var s = MessageReadState.load()
        items.forEach { s.insert($0.id) }
        MessageReadState.save(s)
        for i in items.indices { items[i].read = true }
        TokensHaptic.result(true)
        ToastManager.shared.show("已全部标为已读", icon: "checkmark.circle.fill")
    }

    private var visibleGrouped: [MessageGrouping.DayGroup] {
        Array(filteredGrouped.prefix(shownDays))
    }


    private func reload() {
        loadTask?.cancel()
        loading = true
        loadTask = Task { await load() }
    }

    private func loadIfNeeded() {
        guard !TokenStore.currentToken().isEmpty else {
            lastError = Self.needLogin
            loading = false
            return
        }
        guard loadTask == nil || loadTask!.isCancelled else { return }
        if let last = store.caches["messages"] as? [[String: Any]], !last.isEmpty {
            apply(last)
        }
        loadTask = Task { await load() }
    }

    @MainActor
    private func load() async {
        guard !TokenStore.currentToken().isEmpty else {
            lastError = Self.needLogin
            loading = false
            return
        }
        loading = true
        do {
            let list = try await APIClient.shared.getMessages()
            apply(list)
            lastError = ""
            if list.isEmpty {
                NSLog("loadMessages: 区间内 0 条（近 \(APIClient.messageDays) 天）")
            }
            if !list.isEmpty {
                store.saveCache(["messages": list])
            }
        } catch {
            lastError = error.localizedDescription
            NSLog("loadMessages: \(error.localizedDescription)")
            ToastManager.shared.show("消息获取失败", icon: "wifi.exclamationmark")
        }
        loading = false
    }

    private func apply(_ list: [[String: Any]]) {
        items = MessageDecoder.decode(list, readSet: MessageReadState.load())
    }
}
