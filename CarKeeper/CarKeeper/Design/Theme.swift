import SwiftUI
import MapKit
import CoreHaptics
import AVFoundation
import Photos

// =============================================================================
// SafeSymbol —— SF Symbol 名称兜底
// 背景：历史代码里散落着若干并不存在的图标名（例如 "tire"、"gauge.full"、
//      "battery.3quarter.fill"），而 Image(systemName:) 遇到不存在的名字会渲染成
//      空白 —— 在界面上看起来就是「这个位置的图标缺失了」。
// 约定：凡是「图标名字是变量 / 拼出来的」地方，一律走 Image(safeSymbol:)，
//      名字无效时退回一个一定存在的图标，保证界面永不出现空白图标。
// =============================================================================
enum SafeSymbol {
    private static var cache: [String: String] = [:]

    /// 返回一个可用的 symbol 名：请求的名字不存在时返回 fallback
    static func name(_ requested: String, fallback: String = "questionmark.circle.fill") -> String {
        if let hit = cache[requested] { return hit }
        let resolved = UIImage(systemName: requested) != nil ? requested : fallback
        cache[requested] = resolved
        return resolved
    }
}

extension Image {
    /// 构造 systemName 图标，但名字无效时自动退回 fallback（避免图标凭空消失）
    init(safeSymbol name: String, fallback: String = "questionmark.circle.fill") {
        self.init(systemName: SafeSymbol.name(name, fallback: fallback))
    }
}

// =============================================================================
// Theme.swift —— 只剩下「一处只能有一份」的那些东西
// =============================================================================
// 这一份文件曾经是第二代设计系统（1128 行：CardBox / ExpandingCardBox / KVRow /
// ListDivider / glassCard / FluidHeroFont / Dynamic Type 工具 / 页面状态视图…）。
// 那些都已删除，因为它们全部有第四代（`Tokens.swift` + `DS.swift`）的对应物：
// 同一个 App 里同一件事有两个名字，就一定会有人用错那一个。
//
// 现在这里只剩三类，每一类都只有一份：
//   ① 全 App 唯一的画布与光（AppCanvas / CanvasDecorLayer / SheetCanvasModifier）
//   ② 全 App 唯一的小零件（StatusDot / Pill）
//   ③ 被「车与账号」直接使用的两个视图（月报、省电开关）
// `Theme` 与 `Color(hex:)` 也一并删了：字体一律从 `TokensTypo` 出，
// 颜色一律从 `TokensPalette` 出，不再保留第二个入口。
// =============================================================================

extension View {
    // 页面底色 + 统一页面边距
    // 刻意不接受任何颜色参数：页面底色只能是 TokensPalette.background 这一层。
    //
    // v5：画布之上再叠一层**主题装饰**（CanvasDecorLayer）。
    // 它永远在内容之下（写在 background 里，不是 overlay），所以不遮挡、不吃点击。
    // 装饰不是“氛围背景”的回归：它只表达这套艺术方向的做法 ——
    //   夜光 = 一束来自车所在地的光；纸上 = 纸面在光下的不均；巨字 = 发丝网格。
    func pageBackground() -> some View {
        // 画布与光**不在这一层**：它们在 App 根部（`CarKeeperApp` 里的 `AppCanvas`）。
        // 原因很实际：逐屏去加背景，就一定会有屏幕漏掉 —— 改之前 28 屏里只有 2 屏有画布，
        // 这正是「换了主题却看不出变化」的根源。光只在根上画一次，方向就永远不会自相矛盾。
        contentMargins(.horizontal, TokensSpacing.page, for: .scrollContent)
    }

    // 卡片修饰符（glassCard / glassHeroCard）已删：全 App 的卡片只有 `DSCard` 一个来源。
    // 这两个方法曾经和 DSCard 长得几乎一样（同一块不透明面 + 艺术主题下发丝描边），
    // 但它们是第二套命名 —— 同一件事有两个名字，就一定会有人用错那个。

}

// =============================================================================
// SheetCanvas —— 浮层背后的同一束光
// =============================================================================
// 浮层（sheet / fullScreenCover）会盖住整屏：根部的 AppCanvas 在它**后面**，
// 于是弹层一开，光就被挡在外面 —— 光只铺到一半，比没有光更糟。
//
// 这一支用 `presentationBackground` 把同一束光补到浮层背后：
//   • 不用 `.background`：那是给内容铺底，浮层自己的面还压在上面；
//     `presentationBackground` 才是「这个呈现层的背景」这件事本身。
//   • 原生主题**什么都不做**（原生 = 现状）：浮层继续用系统自带的面，逐像素不变。
//   • 光不吃点击（AppCanvas 里已经 allowsHitTesting(false)），它只是光。
extension View {
    func dsSheetCanvas() -> some View {
        modifier(SheetCanvasModifier())
    }
}

struct SheetCanvasModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if TokensPalette.decor == .none {
            content
        } else {
            content.presentationBackground { AppCanvas() }
        }
    }
}

// =============================================================================
// AppCanvas —— 全 App 的画布：整棵界面背后的一层光
// =============================================================================
// 光池的位置与强度来自 `SkyLight`（车所在经纬度 + 此刻算出的**真实太阳位置**），
// 纸面颗粒、暗角、发丝网格同理 —— 这不是「氛围背景」的回归，每一层都对应一个物理量。
//
// 为什么画在根部而不是每屏自己画：
//   ① 逐屏去加，一定会有屏幕漏掉（改之前 28 屏里只有 2 屏有画布）；
//   ② 同一束光必须只有一份 —— 两个屏幕上的光方向不一样，比没有光更糟。
// @MainActor：AppStore 是 @MainActor（View 的 body 本来就在主线程上）。
struct AppCanvas: View {
    /// 天气实况（云量）。**订阅**它：快照到达时整棵树重画一次 ——
    /// 光依赖一份异步到达的数据，不订阅就会停在「取到天气之前」的那一版。
    @ObservedObject private var weather = WeatherService.shared

    @MainActor private var sky: SkyLight? {
        guard let c = AppStore.shared.currentLocation?.coordinate else { return nil }
        return SkyLight.now(at: Date(), coordinate: c, weather: weather.current)
    }

    var body: some View {
        ZStack {
            TokensPalette.canvasGradient
            if let light = sky {
                // 与地图主屏用的是同一套光层：换个屏幕，光不会换个方向
                SkyOverlay(light: light)
            } else {
                CanvasDecorLayer()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        // 取天气挂在根画布上（它每一屏都在），而不是逐屏去取：
        // TTL 是护栏，不该被当成调度器。取不到就退回晴空模型，界面照实写明。
        .task {
            let coordinate = await MainActor.run { AppStore.shared.currentLocation?.coordinate }
            guard let coordinate else { return }
            await WeatherService.shared.refreshIfNeeded(coordinate: coordinate)
        }
    }
}

// =============================================================================
// CanvasDecorLayer —— 按当前主题给画布叠一层装饰
// =============================================================================
// 三种装饰各对应一种艺术方向的做法，不是随机氛围：
//   lightPool    夜光：一束来自车所在地的光（暖色、位置固定、不是动画）
//   paperGrain   纸上：纸面在光下的色温不均（印刷物不会完全均匀）
//   hairlineGrid 巨字：发丝网格 —— 版面本身就是内容
//
// 它只出现在 pageBackground() 的 background 里（内容之下），并且关闭命中测试，
// 所以不会遮挡、不会吃掉任何点击。
struct CanvasDecorLayer: View {
    private var decor: CanvasDecor { TokensPalette.decor }

    var body: some View {
        switch decor {
        case .none:
            Color.clear

        case .lightPool:
            // 光池曾经在这里画一块固定在右上角的暖光 —— 那是错的：光的**方向**是物理量，
            // 不该由版式决定。现在光池由 `SkyOverlay` 按真实太阳方位角画（见 AppCanvas）。
            // 这一档只兜底「还没有车的位置」：那就没有光，不编一个方向。
            Color.clear

        case .paperGrain:
            // 纸面的色温不均：用**主题自己的颜料**极淡地洗两层。
            // 原来这里是两组写死的暖棕 RGB —— 那是「这张纸的颜色」被写进了版式层：
            // 换主题之后它就成了画面上唯一不跟随的东西。
            ZStack {
                RadialGradient(
                    colors: [TokensPalette.accent.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.18, y: 0.08),
                    startRadius: 0,
                    endRadius: 420
                )
                RadialGradient(
                    colors: [TokensPalette.secondary.opacity(0.06), .clear],
                    center: UnitPoint(x: 0.90, y: 0.85),
                    startRadius: 0,
                    endRadius: 520
                )
            }

        case .hairlineGrid:
            GeometryReader { geo in
                Path { p in
                    let step: CGFloat = 44
                    var x: CGFloat = 0
                    while x <= geo.size.width {
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: geo.size.height))
                        x += step
                    }
                    var y: CGFloat = 0
                    while y <= geo.size.height {
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        y += step
                    }
                }
                .stroke(TokensPalette.primary.opacity(CanvasDecor.hairlineGrid.strength), lineWidth: 0.5)
            }
        }
    }
}

// MARK: - 状态点（纯色圆点，无附加效果）
struct StatusDot: View {
    let cls: String
    var size: CGFloat = 8
    var body: some View {
        Circle()
            .fill(TokensPalette.statusColor(cls))
            .frame(width: size, height: size)
            .opacity(cls == "na" ? 0.35 : 1)
    }
}

// MARK: - 语义色玻璃胶囊
struct Pill: View {
    let text: String
    let cls: String
    var dot: Bool = true

    var body: some View {
        DSChip(text: text, cls: cls)
    }
}

// FluidHeroFont 已删：全 App 的「巨字」只有 `DSBigNumber` 一个来源。
// 它当时是第三套数字排版（自算流体字号 + rounded 字重），与 DSBigNumber 的
// 「超细字重 + 负字距」是两套语言。

// Dynamic Type 自适应工具（DynamicTypeScale / adaptivePagePadding / adaptiveSpacing /
// adaptiveSafeAreaBottom / dynamicTypeLineLimit / DynamicTypeCompress*）已删 —— 它们**从未被任何
// 页面调用过**，而且 `dynamicTypeCompress()` 在那个它唯一被用到的两处（「车与账号」的身份卡与车辆卡）
// 干的事是“再加一层 20pt 横向内边距”：卡片比同一屏的分组窄 20pt。删掉后两张卡与下面的分组对齐。
// 真正需要大字体适配的地方走系统语义阶梯（`TokensTypo.title/body/footnote`）——
// 它们本来就跟随 Dynamic Type，不需要另建一套缩放表。

// PageLoadingView / PageErrorView 已删：页面的加载态用 `DSSkeleton`，失败/空态用 `DSPlaceholder`。
// 它们的存在让同一件事有三个名字（PageLoadingView / DSSkeleton / DSSkeleton 手写），
// 而真正在用的页面（全量数据 / 健康报告 / 车辆档案）早就用的是 DS 那套。
// =============================================================================
/// 网络状态条：一整行、发丝线分隔、左对齐 —— 像车内状态灯，而不是飘在顶部的彩色胶囊。
/// 全局 Toast 提示（由 NavState.currentItem 驱动，挂载在根视图上）
// ShareableStatusInfo / generateShareableStatus 已删：那是一段没有任何调用点的“分享文案生成”，
// 而且它是第二套分享路径（真的导出在保养与钱里的 `ExportDataSection`）。
//
// ImagePicker / pickImageFromPhotoLibrary / ImagePickerCoordinator 已删：
// 用 `UIImagePickerController` 自己 present 是 UIKit 时代的写法（还得靠一个全局强引用来防止
// delegate 被提前释放）；照片入口走 SwiftUI 的 `PhotosPicker`，不再自己拼这一套。
//
// =============================================================================
// MARK: - 从 63decaa 被误删的实现（月报 / 省电开关）
// 注意：这一节原来还包括"充电站地图"与"驾驶评分"，两者已删 ——
// 它们各自是第二、第三套实现：充电站搜的是写死的北京坐标，评分用报文里
// 根本不存在的急加速/急刹车键名（永远 0 次 + 100 分）。现在两者都归到
// 地图主屏的「充电」层与评分页，那里才是唯一那份实现。
// =============================================================================

// =============================================================================
// MonthlyReportSection — #39 驾驶报告月报
// 「我的」那一屏里的一节（展开后才算），可再导出一个 HTML 文件去分享
// （标题里曾写着「（PDFKit）」—— 它从来没有生成过 PDF，`import PDFKit` 也没用过）
// =============================================================================
struct MonthlyReportSection: View {
    @State private var expanded = false
    @State private var reportData: ReportData?
    
    /// 报表数据全部来自**本机真实记录**：行程历史（由点火/熄火事件自动生成）+ 评分。
    /// 每一项都可能算不出来 —— 那就显示「—」，不编。
    ///
    /// ⚠️ 这里原有 `chargeSessions` / `chargeKWh` 两行（充电次数与度数）。
    ///    充电账本 2026-09-23 整条删除，报表里那两行也随之去掉 ——
    ///    剩下的四项全是行程与评分，都是 App 记录的真实事件算出来的。
    struct ReportData {
        /// 例：2026年9月
        let monthLabel: String
        let tripCount: Int
        let totalMileage: Double
        /// 每 1% SOC 的续航（km）。不需要电池容量，所以是目前唯一算得出的能效口径。
        let kmPerPercent: Double?
        /// 平均电量：来自本机的 SOC 采样（**不是你整月的平均** —— 采样只保留最近一小段）。
        let avgSoc: Int?
        let driveScore: Int?

        /// 本月一条真记录都没有。这时不该画一张空表，而要直说为什么。
        var hasAnyRecord: Bool { tripCount > 0 }
        var mileageText: String { tripCount > 0 ? String(format: "%.1f km", totalMileage) : "—" }
        var tripText: String { tripCount > 0 ? "\(tripCount) 段" : "—" }
        var efficiencyText: String {
            kmPerPercent.map { String(format: "每 1%% 电量 %.1f km", $0) } ?? "—"
        }
        var avgSocText: String { avgSoc.map { "\($0)%" } ?? "—" }
        var scoreText: String { driveScore.map { "\($0) 分" } ?? "—" }
        var scoreGrade: String {
            guard let s = driveScore else { return "还没有足够的读数" }
            switch s {
            case 90...: return "S"
            case 80..<90: return "优秀"
            case 70..<80: return "良好"
            case 60..<70: return "一般"
            default: return "偏低"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.md) {
            DSGroup {
                DSGroupRow(showsSeparator: false) {
                    DSRow(icon: "doc.text.fill",
                          title: "本月驾驶报告",
                          subtitle: "里程 / 能耗 / 评分",
                          value: expanded ? "收起" : nil,
                          showsChevron: true) { toggle() }
                }
            }
            if expanded, let d = reportData {
                MonthlyReportCard(data: d)
            }
        }
    }

    /// 展开时才真的去算 —— 不必为一个没人看的报表在每次重绘都跑一遍行程统计。
    /// 它以前是拉起一个浮层；浮层是另一屏，现在就是这一屏往下多几行。
    private func toggle() {
        if expanded { expanded = false; return }
        reportData = generateReport()
        expanded = true
    }

    private func generateReport() -> ReportData {
        // 这里**曾经**是写死的 1250 km / 14.5 kWh / 8 次 / 65% / 85 分（注释写着「模拟生成」）。
        // 一份编造的月报比没有月报坏得多 —— 用户会拿它判断自己的车。
        let store = AppStore.shared
        let cal = Calendar.current
        let now = Date()
        let trips = store.tripHistory.filter {
            cal.isDate($0.startTime, equalTo: now, toGranularity: .month)
        }
        let distance = trips.reduce(0.0) { $0 + $1.distanceKm }
        // 每 1% SOC 的续航：把本月所有行程的里程与百分点各自求和再相除
        // （不能用「各段 km/% 的平均」——短途段的读数会被放大）。
        let socUsed = trips.reduce(0) { $0 + max(0, $1.startSoc - $1.endSoc) }
        let samples = HistoryStore.shared.soc.suffix(240).map { $0.v }
        let mf = DateFormatter()
        mf.dateFormat = "yyyy年M月"
        let data = ReportData(
            monthLabel: mf.string(from: now),
            tripCount: trips.count,
            totalMileage: distance,
            kmPerPercent: socUsed > 0 ? distance / Double(socUsed) : nil,
            avgSoc: samples.isEmpty ? nil : Int(samples.reduce(0, +) / Double(samples.count)),
            driveScore: store.drivingScore
        )
        return data
    }
}

/// 月报本体。它不再是浮层 —— 没有自己的导航栏、没有「关闭」按钮，
/// 因为它是「我的」那一屏往下多出来的几行（调用点就在上面那个展开动作里）。
struct MonthlyReportCard: View {
    let data: MonthlyReportSection.ReportData

    var body: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            Text(data.monthLabel)
                .font(TokensTypo.subheadline)
                .foregroundStyle(TokensPalette.secondary)

            if !data.hasAnyRecord {
                DSNotice(kind: .info, text: "本月还没有行程记录。")
            }

            DSGroup(title: "行驶统计") {
                DSGroupRow { DSKeyValueRow(key: "行程段数", value: data.tripText) }
                DSGroupRow { DSKeyValueRow(key: "总里程", value: data.mileageText) }
                // kWh/100km 需要电池容量（报文里 capacity 是 null），所以这里用口径说清楚的 km/1%
                DSGroupRow { DSKeyValueRow(key: "能效", value: data.efficiencyText) }
                DSGroupRow(showsSeparator: false) {
                    DSKeyValueRow(key: "平均电量（近期采样）", value: data.avgSocText)
                }
            }

            DSGroup(title: "驾驶评分") {
                DSGroupRow { DSKeyValueRow(key: "综合评分", value: data.scoreText) }
                DSGroupRow(showsSeparator: false) {
                    DSKeyValueRow(key: "评价", value: data.scoreGrade)
                }
            }

            Button("分享报告") { shareReport() }
                .buttonStyle(DSPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shareReport() {
        // 生成一份 HTML 再分享（这里曾写着「生成 PDF 并分享」—— 它从来没生成过 PDF）
        let html = generateHTMLReport()
        let url = saveHTMLToTemp(html: html)
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            vc.popoverPresentationController?.sourceView = scene.windows.first
            scene.windows.first?.rootViewController?.present(vc, animated: true)
        }
    }
    
    private func generateHTMLReport() -> String {
        return """
        <html><body style="font-family:system-ui;padding:20px;">
        <h1>月度驾驶报告</h1>
        <h2>行驶统计（\(data.monthLabel)）</h2>
        <ul>
        <li>行程段数: \(data.tripText)</li>
        <li>总里程: \(data.mileageText)</li>
        <li>能效: \(data.efficiencyText)</li>
        <li>平均电量（近期采样）: \(data.avgSocText)</li>
        </ul>
        <h2>驾驶评分</h2>
        <p>综合评分: \(data.scoreText) - \(data.scoreGrade)</p>
        </body></html>
        """
    }
    
    private func saveHTMLToTemp(html: String) -> URL {
        let filename = "monthly_report_\(Date().timeIntervalSince1970).html"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}


// =============================================================================
// PowerSavingToggle —— #31 省电模式开关
// 在设置页面或首页添加开关，关闭动画和后台刷新
// =============================================================================
struct PowerSavingToggle: View {
    @AppStorage("carkeeper_power_saving") private var enabled = false

    var body: some View {
        // 颜色只从令牌来：`.green` / `.orange` 是硬编码的第三个调色盘，
        // 换成艺术主题时它不会跟着变。
        Toggle(isOn: $enabled) {
            HStack(spacing: TokensSpacing.sm) {
                Image(systemName: enabled ? "battery.100" : "battery.25")
                    .foregroundStyle(enabled ? TokensPalette.success : TokensPalette.warning)
                VStack(alignment: .leading, spacing: 1) {
                    Text("省电模式")
                        .font(TokensTypo.body)
                        .foregroundStyle(TokensPalette.primary)
                    Text(enabled ? "已关闭动画与后台刷新" : "开启后关闭动画与后台刷新")
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.secondary)
                }
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: TokensPalette.accent))
        .frame(minHeight: TokensSpacing.row)
        .onChange(of: enabled) { _, newValue in
            if newValue {
                ToastManager.shared.show("省电模式已开启", icon: "battery.25")
            } else {
                ToastManager.shared.show("省电模式已关闭", icon: "battery.100")
            }
        }
    }
}
