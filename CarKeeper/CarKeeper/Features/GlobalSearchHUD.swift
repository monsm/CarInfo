// =============================================================================
// #NEW-123 全局搜索 HUD — 从任意页面下滑触发搜索
// =============================================================================

import SwiftUI

struct GlobalSearchHUD: View {
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []

    struct SearchResult: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let action: () -> Void
    }

    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                // 搜索框（它是浮在内容之上的一层 → 玻璃合法）
                HStack(spacing: TokensSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(TokensTypo.title3)
                        .foregroundStyle(TokensPalette.secondary)

                    TextField("搜索车况、设置...", text: $searchText)
                        .font(TokensTypo.subheadline)
                        .textFieldStyle(.plain)
                        .foregroundColor(TokensPalette.primary)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(TokensPalette.secondary)
                        }
                    }
                }
                .padding(TokensSpacing.md)
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous))
                .overlay {
                    // 艺术方向下给浮层一条发丝边（浮层自己也有线，与卡片同一规则）
                    if TokensPalette.decor != .none {
                        RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                            .strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.line)
                    }
                }
                .padding(.horizontal, TokensSpacing.page)

                // 搜索结果：一个分组 + 行，不再是一叠各自带底的卡片
                ScrollView {
                    if searchResults.isEmpty {
                        Text(searchText.isEmpty ? "输入关键词，搜车况与设置。" : "没有匹配的项。")
                            .font(TokensTypo.footnote)
                            .foregroundStyle(TokensPalette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TokensSpacing.page)
                            .padding(.top, TokensSpacing.md)
                    } else {
                        DSGroup {
                            ForEach(searchResults) { result in
                                DSGroupRow {
                                    SearchResultRow(result: result) {
                                        result.action()
                                        isPresented = false
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, TokensSpacing.page)
                        .padding(.top, TokensSpacing.md)
                    }
                }

                Spacer()
            }
            .padding(.top, TokensSpacing.md)
        }
        .onChange(of: searchText) { _, text in
            searchResults = performSearch(text)
        }
        .onAppear {
            searchResults = []
        }
    }

    private func performSearch(_ text: String) -> [SearchResult] {
        guard !text.isEmpty else { return [] }

        let allItems: [SearchResult] = [
            SearchResult(
                title: "车辆状态",
                subtitle: "SOC、里程、温度等实时数据",
                icon: "car.fill",
                action: {}
            ),
            SearchResult(
                title: "远程控车",
                subtitle: "锁车、解锁、开空调",
                icon: "dot.radiowaves.left.and.right",
                action: {}
            ),
            SearchResult(
                title: "电池健康",
                subtitle: "电池状态与充电记录",
                icon: "battery.100",
                action: {}
            ),
            SearchResult(
                title: "胎压监测",
                subtitle: "四轮胎压与温度",
                icon: "exclamationmark.triangle.fill",
                action: {}
            ),
            SearchResult(
                title: "维保记录",
                subtitle: "保养历史与提醒",
                icon: "wrench.and.screwdriver",
                action: {}
            ),
            SearchResult(
                title: "设置",
                subtitle: "通知、主题、账号",
                icon: "gear",
                action: {}
            )
        ]

        return allItems.filter { item in
            item.title.localizedCaseInsensitiveContains(text) ||
            item.subtitle.localizedCaseInsensitiveContains(text)
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
