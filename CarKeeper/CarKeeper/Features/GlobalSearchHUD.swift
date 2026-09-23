// =============================================================================
// #NEW-123 全局搜索 HUD
// =============================================================================
//
// 上一版这个页面搜的是**写死的 6 条字符串**，而且每一条的 `action` 都是空闭包
// —— 点下去什么都不发生；它本身也没有任何入口（零外部引用）。
// 也就是说：你以为有一个「全局搜索」，实际是一个搜不到东西、点不动的假界面。
//
// 现在它搜的是真东西，搜到就能去：
//   • 页面（模式条上的每一档，跳转用统一导航 `NavState.openMode`）
//   • 车（车辆档案里的字段：车牌 / VIN / 车型 / 颜色）
//   • 车况读数（电量 / 续航 / 胎压 / 充电 —— 命中就跳到对应页）
//   • 行程（`store.tripHistory`：时间、里程、起止 SOC）
//   • 指令历史（`store.commandHistory`：指令名、成功与失败）
//   • （充电记录已删：它来自已删除的充电账本）
//
// 搜不到就照实说「没有匹配」，不编造结果。
// =============================================================================

import SwiftUI

struct GlobalSearchHUD: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var nav: NavState
    private let store = AppStore.shared

    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @FocusState private var focused: Bool

    struct SearchResult: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        /// 命中关键词的标题 —— 用于排序（标题命中排在正文命中之前）
        let action: () -> Void
    }

    var body: some View {
        ZStack {
            // 背景遮罩（浮层自己的一层，合法）。色相来自主题：纸主题的遮罩是墨，不是黑。
            TokensPalette.scrim.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                // 搜索框（浮在内容之上的一层 → 允许玻璃）
                HStack(spacing: TokensSpacing.sm) {
                    Image(safeSymbol: "magnifyingglass", fallback: "magnifyingglass")
                        .font(TokensTypo.title3)
                        .foregroundStyle(TokensPalette.secondary)

                    TextField("搜索页面、车、行程、指令、充电…", text: $searchText)
                        .font(TokensTypo.subheadline)
                        .textFieldStyle(.plain)
                        .foregroundColor(TokensPalette.primary)
                        .focused($focused)
                        .submitLabel(.search)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(safeSymbol: "xmark.circle.fill", fallback: "xmark.circle.fill")
                                .foregroundStyle(TokensPalette.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(TokensSpacing.md)
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous))
                .overlay {
                    if TokensPalette.decor != .none {
                        RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                            .strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.line)
                    }
                }
                .padding(.horizontal, TokensSpacing.page)

                ScrollView {
                    if searchResults.isEmpty {
                        DSPlaceholder(icon: searchText.isEmpty ? "magnifyingglass" : "questionmark.circle",
                                      title: searchText.isEmpty ? "搜什么？" : "没有匹配的项",
                                      message: searchText.isEmpty ? "搜页面、车牌、行程、指令。"
                        : "换个词试试。只搜本机已有数据。")
                            .padding(.horizontal, TokensSpacing.page)
                            .padding(.top, TokensSpacing.lg)
                    } else {
                        DSGroup(title: nil, trailing: "\(searchResults.count)") {
                            ForEach(Array(searchResults.enumerated()), id: \.element.id) { idx, result in
                                DSGroupRow(showsSeparator: idx < searchResults.count - 1) {
                                    SearchResultRow(result: result) {
                                        focused = false
                                        result.action()
                                        isPresented = false
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, TokensSpacing.page)
                        .padding(.top, TokensSpacing.md)
                        .padding(.bottom, TokensSpacing.xxl)
                    }
                }
            }
            .padding(.top, TokensSpacing.md)
        }
        .onChange(of: searchText) { _, text in
            searchResults = performSearch(text)
        }
        .onAppear {
            searchResults = []
            focused = true
        }
    }

    // MARK: - 搜索

    private func performSearch(_ text: String) -> [SearchResult] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 1 else { return [] }

        var out: [SearchResult] = []

        // ① 页面（静态清单 + 真实导航）
        for page in Self.pages {
            if page.title.lowercased().contains(q) || page.hint.lowercased().contains(q) {
                out.append(SearchResult(title: page.title, subtitle: page.hint, icon: page.icon) { [nav] in
                    // 是档位的就拨模式条（不要 push 第二份页面），档案/设置才 push
                    nav.openMode(for: page.link)
                })
            }
        }

        // ② 车（车辆档案里的真实字段）
        if let sum = VM.vehicleSummary(store.car, store.controlCache) {
            let fields: [(String, String)] = [
                ("车牌", sum.plate),
                ("VIN", sum.vin),
                ("车型", sum.model),
                ("颜色", sum.color)
            ]
            for f in fields where !f.1.isEmpty && f.1 != "--" {
                if f.1.lowercased().contains(q) {
                    out.append(SearchResult(title: "\(f.0) \(f.1)",
                                            subtitle: "车辆档案",
                                            icon: "car.fill") { [nav] in
                        nav.openMode(.vehicle)
                    })
                }
            }
        }

        // ③ 车况读数（命中「电量/续航/胎压/充电」这类词就跳到那一页）
        let energy = VM.energy(store.caches, store.car)
        let readings: [(String, String, String, Deeplink)] = [
            ("电量", "\(energy.soc)（\(energy.socPct)%）", "battery.100", .battery),
            ("续航", "\(energy.range) km", "gauge.with.dots.needle.50percent", .dashboard),
            ("胎压", "四轮压力与温度", "circle.dashed", .health),
            ("充电", energy.chargeText, "bolt.fill", .battery),
            ("空调", "车内温度与风量", "fan.fill", .control)
        ]
        for r in readings where r.0.contains(q) || q.contains(r.0) {
            out.append(SearchResult(title: "\(r.0)：\(r.1)", subtitle: "实时车况", icon: r.2) { [nav] in
                nav.openMode(for: r.3)
            })
        }

        // ④ 行程
        for trip in store.tripHistory.prefix(30) {
            let when = trip.startTime.formatted(date: .abbreviated, time: .shortened)
            let dist = String(format: "%.1f km", trip.distanceKm)
            let soc = "\(trip.startSoc)% → \(trip.endSoc)%"
            if when.lowercased().contains(q) || dist.lowercased().contains(q) || soc.lowercased().contains(q) {
                out.append(SearchResult(title: "行程 \(dist)",
                                        subtitle: "\(when) · \(soc)",
                                        icon: "point.topleft.down.curvedto.point.bottomright.up") { [nav] in
                    nav.openMode(.trips)
                })
            }
        }

        // ⑤ 指令历史
        for entry in store.commandHistory.prefix(30) {
            let when = entry.startedAt.formatted(date: .abbreviated, time: .shortened)
            let state = entry.success ? "成功" : "失败"
            if entry.name.lowercased().contains(q) || entry.cmd.lowercased().contains(q) {
                out.append(SearchResult(title: "指令 \(entry.name)",
                                        subtitle: "\(when) · \(state) · 用时 \(entry.durationText)",
                                        icon: entry.iconName) { [nav] in
                    // 指令记录现在住在车控页的「做过什么」里，所以搜到指令 → 去车控档
                    nav.openMode(.control)
                })
            }
        }

        // （⑥「充电记录」曾在这里：列出充电账本里的每一次会话与费用。
        //  账本 2026-09-23 整条删除，搜索里这一节也随之去掉。）

        // 标题命中排在前面；同权重保持来源顺序（页面 → 车 → 车况 → 行程 → 指令）
        let matched = out.filter { !$0.title.lowercased().contains(q) }
        let titled = out.filter { $0.title.lowercased().contains(q) }
        return Array((titled + matched).prefix(24))
    }

    /// 可搜的页面清单。与壳层的 `Deeplink` 一一对应（少一个就等于少一条入口）。
    /// 搜索里的「页面」= **档位本身**，不再手抄一份目录。
    ///
    /// 此前这是一份手写的 9 条静态数组，与 `HomeMode` 各写一遍 —— 加一档时
    /// 搜索里就会静默地少一条（而没有任何东西会出声）。现在从 `HomeMode.allCases`
    /// 派生，提示语与图标由一个**穷举** switch 给（无 default）：新加档位时
    /// 编译器会强制在这里表态。`.now` 不进列表 —— 它就是这张地图本身。
    ///
    /// 别名（`.dashboard` / `.score` / `.parking`）**不进这一列**：
    /// 它们指向的页面在上面已经各有一条；同一页摆两个入口，就是缝合的来源。
    private static let pages: [(title: String, hint: String, icon: String, link: Deeplink)] =
        HomeMode.allCases.compactMap { mode in
            guard let link = mode.deeplink else { return nil }
            let meta = pageMeta(for: mode)
            return (title: mode.title, hint: meta.hint, icon: meta.icon, link: link)
        }

    /// 一档的一句话与图标。穷举（无 default），理由同上。
    private static func pageMeta(for mode: HomeMode) -> (hint: String, icon: String) {
        switch mode {
        case .now: return ("位置与状态", "location.fill")
        case .vehicle: return ("档案、体检、保养", "car.fill")
        case .charge: return ("充电、电池、趋势", "bolt.fill")
        case .control: return ("锁车、空调、寻车", "dot.radiowaves.left.and.right")
        case .trips: return ("行程与事件", "chart.bar.fill")
        case .mine: return ("账号、设置、应急", "person.fill")
        }
    }
}

struct SearchResultRow: View {
    let result: GlobalSearchHUD.SearchResult
    let action: () -> Void

    var body: some View {
        // DSRow 自己就是那个按钮（传 action 时它会包一层 Button + 按压反馈），
        // 外面不再套一层 —— 套两层会出现两个按钮语义，读屏会念两遍。
        DSRow(icon: result.icon,
              title: result.title,
              subtitle: result.subtitle,
              showsChevron: true,
              action: action)
    }
}
