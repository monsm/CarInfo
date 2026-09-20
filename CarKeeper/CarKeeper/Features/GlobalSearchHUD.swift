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
                // 搜索框
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    TextField("搜索车况、设置...", text: $searchText)
                        .font(.title3)
                        .textFieldStyle(.plain)
                        .foregroundColor(.primary)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                // 搜索结果
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(searchResults) { result in
                            SearchResultRow(result: result) {
                                result.action()
                                isPresented = false
                            }
                        }
                    }
                    .padding()
                }

                Spacer()
            }
            .padding(.top, 16)
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
        Button(action: action) {
            HStack(spacing: 12) {
                Image(safeSymbol: result.icon, fallback: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(Kansei.Color.ambient)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.headline)
                    Text(result.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
