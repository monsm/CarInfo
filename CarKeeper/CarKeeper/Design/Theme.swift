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
//   ① 全 App 唯一的画布（AppCanvas）
//   ② 全 App 唯一的小零件（StatusDot / Pill）
//   ③ 被「车与账号」直接使用的两个视图（月报、省电开关）
// `Theme` 与 `Color(hex:)` 也一并删了：字体一律从 `TokensTypo` 出，
// 颜色一律从 `TokensPalette` 出，不再保留第二个入口。
// =============================================================================

// =============================================================================
//  `pageBackground()` 已于 2026-09-25 删除
// =============================================================================
//
//  它原来是一个 `extension View`，名字说的是「页面底色 + 统一页面边距」，
//  而函数体里只剩一行 `contentMargins(.horizontal, TokensSpacing.page, for: .scrollContent)` ——
//  **底色与光早就不在这里了**（它们在 App 根部的 `AppCanvas`：逐屏去加背景一定会有屏幕漏掉）。
//
//  留下的那一行不是无害的：`contentMargins` 加在**这一页滚动内容的左右**上，
//  于是「调用过它的页面」的卡叠比「没调用的页面」窄 20pt。实测（2026-09-25，402pt 宽的机器，
//  量的是卡里那层分组面到屏幕边的距离）：
//
//      车辆（没调用）          面宽 328pt，左右各空 36pt = 18(卡内缩) + 18(卡内边距)
//      出行 / 车控 / 我的       同样的面只有 288pt，左右各空 56pt —— 多出来的正是那 20pt
//
//  用户 2026-09-25 第 1 条报的就是这个：「只有现在和车辆界面的卡片宽度合格」。
//
//  所以它被删掉，而不是留着：一个叫「页面底色」却不产生底色、只把卡片变窄的函数，
//  与「一个叫 `glass` 却不产生玻璃的参数」是同一类谎（`DSCard` 头注里记过那一条）。
//  真正需要那 20pt 页边距的两处（登录页 / 「光」浮层）现在自己把它写明白。

// =============================================================================
// SheetCanvas —— 浮层背后的同一束光
// =============================================================================
// 浮层（sheet / fullScreenCover）会盖住整屏：根部的 AppCanvas 在它**后面**，
// 于是弹层一开，光就被挡在外面 —— 光只铺到一半，比没有光更糟。
//
// 这一支用 `presentationBackground` 把同一束光补到浮层背后：
//   • 不用 `.background`：那是给内容铺底，浮层自己的面还压在上面；
//     `presentationBackground` 才是「这个呈现层的背景」这件事本身。
//  2026-09-25 删除：它只在**艺术方向**下才做事（原生主题下 `content` 原样返回，
//  所以九处 `.dsSheetCanvas()` 调用点全部一行不改地删掉了）。主题只剩原生之后，
//  这个 modifier 是一个恒等变换 —— 一个叫「浮层画布」却什么都不做的 modifier，
//  与它下面那个 `CanvasDecorLayer` 是同一类东西。

// =============================================================================
// AppCanvas —— 全 App 的画布
// =============================================================================
// 为什么画在根部而不是每屏自己画：逐屏去加，一定会有屏幕漏掉（改之前 28 屏里只有 2 屏有画布），
// 而「底色」这件事只有一个答案 —— 每屏各画一次就有第二种。
//
// 2026-09-25：它上面原来还叠着一层「光」（`SkyOverlay` + `CanvasDecorLayer`：
// 光池 / 纸纹 / 发丝网格，位置与强度由车所在地的**真实太阳位置**算出）。
// 那两层只在艺术方向下出现（原生主题一个像素都不画），随艺术主题一起删除。
// 光引擎本身（`SkyLight`）留着 —— 它不是装饰：地图上那颗车灯的亮度就是它算的。
struct AppCanvas: View {
    var body: some View {
        TokensPalette.canvasGradient
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

// =============================================================================
//  已删除：`CanvasDecorLayer`（2026-09-25，随艺术主题）
// =============================================================================
//  它按当前主题给画布叠一层装饰：光池（夜光）/ 纸纹（纸上）/ 发丝网格（巨字）。
//  三个分支里有两个本来就是 `Color.clear`，第三个是「没有车的位置时也不编方向」——
//  也就是说它在**默认（原生）主题下什么都不画**。用户 2026-09-25 定下只用原生，
//  于是这三档一起删掉：装饰是「主题的做法」，不是界面的一层。

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
        let data = ReportData(
            monthLabel: DateText.shared.string(now, "yyyy年M月"),
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
