// =============================================================================
// E73-E78 平台特性深化
// =============================================================================

import SwiftUI
import WidgetKit

// MARK: - E73 Lock Screen Widget（Active State）
struct LockScreenWidget: View {
    let car: [String: Any]?
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "car.fill")
                Text("CarKeeper")
                    .font(.caption).fontWeight(.semibold)
                Spacer()
                if let energy = car?["energy"] as? [String: Any],
                   let soc = energy["socPct"] as? Int {
                    Text("\(soc)%")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(.green)
                }
            }
            
            // 快捷操作按钮
            HStack(spacing: 20) {
                Button {
                    // 锁车
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Circle())
                }
                Button {
                    // 解锁
                } label: {
                    Image(systemName: "lock.open.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(Color.green.opacity(0.2))
                        .clipShape(Circle())
                }
                Button {
                    // 寻车
                } label: {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Circle())
                }
            }
        }
        .padding()
    }
}

// MARK: - E74 Spotlight搜索集成
struct SpotlightSearchable: ViewModifier {
    @State private var searchQuery = ""
    
    func body(content: Content) -> some View {
        content
            .searchable(text: $searchQuery, prompt: "搜索车辆状态...")
            .onSubmit(of: .search) {
                // 处理搜索
            }
    }
}

extension View {
    func spotlightSearchable() -> some View {
        modifier(SpotlightSearchable())
    }
}

// MARK: - E75 Siri Suggestions
struct SiriSuggestionProvider: AppIntent {
    static let title: LocalizedStringResource = "快速查看车况"
    static let description = IntentDescription("通过Siri快速获取车辆状态")
    
    @Parameter(title: "车辆ID", default: "")
    var carId: String
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = "正在查看车辆状态..."
        return .result(dialog: dialog)
    }
}

// MARK: - E76 Apple Watch独立App
struct WatchMainView: View {
    var body: some View {
        List {
            Section("车辆状态") {
                NavigationLink("SOC") {}
                NavigationLink("胎压") {}
                NavigationLink("温度") {}
            }
            Section("远程控制") {
                NavigationLink("锁车") {}
                NavigationLink("开空调") {}
                NavigationLink("寻车") {}
            }
        }
    }
}

// MARK: - E77 iPad Split View
struct iPadSplitView: View {
    var body: some View {
        SplitView {
            SidebarView()
            DetailView()
        }
    }
}

struct SplitView<Sidebar: View, Detail: View>: View {
    let sidebar: Sidebar
    let detail: Detail
    
    init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar()
        self.detail = detail()
    }
    
    var body: some View {
        #if os(iOS)
        GeometryReader { geometry in
            if geometry.size.width > 768 {
                HStack(spacing: 0) {
                    sidebar.frame(width: 300)
                    Divider()
                    detail
                }
            } else {
                detail
            }
        }
        #else
        detail
        #endif
    }
}

// MARK: - E78 Mac Catalyst
struct MacCatalystView: View {
    var body: some View {
        ScrollView {
            // macOS适配的布局
            VStack(spacing: 20) {
                Text("CarKeeper for Mac")
                    .font(.title)
                // 更多macOS适配内容
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("设置") {}
            }
        }
    }
}
