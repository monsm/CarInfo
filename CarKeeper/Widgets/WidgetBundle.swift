// =============================================================================
//  WidgetBundle — 桌面/锁屏小组件 + 充电实时活动（锁屏 + 灵动岛）
// =============================================================================
//  设计语言与 App 内完全同一套（v4）：令牌取自 Shared/WidgetTokens.swift，
//  App 的 DS.Palette 也从那里取，所以两边不会漂移。
//
//  核心机制沿用 App 首屏那一句：**光带就是电量**。
//  亮的长度 = SOC，暗的部分 = 还没充的。没有仪表盘、没有续航环。
//
//  数据来源：App Group 里的一个 Codable 快照（SharedStore.snapshotKey），
//  由 App 车况刷新后写入（AppStore.syncSharedDefaults → SharedStore.write）。
//  ⚠️ 键名与结构只有一份定义（Shared/WidgetTokens.swift），这里不再各写一遍。
// =============================================================================

import SwiftUI
import WidgetKit
import ActivityKit

// =============================================================================
// MARK: - Timeline Entry / Provider
// =============================================================================

struct VehicleEntry: TimelineEntry {
    let date: Date
    let snapshot: VehicleSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> VehicleEntry {
        VehicleEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (VehicleEntry) -> Void) {
        // 组件库里的预览用占位数据（看起来像一个真在充电的早晨）；
        // 真机上读不到就交空快照 —— 界面会明确说"尚未同步"，而不是编一个数字。
        if context.isPreview {
            completion(VehicleEntry(date: Date(), snapshot: .placeholder))
        } else {
            completion(VehicleEntry(date: Date(), snapshot: SharedStore.read() ?? VehicleSnapshot()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VehicleEntry>) -> Void) {
        let snapshot = SharedStore.read() ?? VehicleSnapshot()
        let entry = VehicleEntry(date: Date(), snapshot: snapshot)
        // 充电中 5 分钟一次，闲时 15 分钟。真正何时刷新由系统决定（会被合并/推迟），
        // 所以充电时真正"活着"的界面是实时活动，不是小组件。
        let minutes = snapshot.charging ? 5 : 15
        let next = Calendar.current.date(byAdding: .minute, value: minutes, to: Date())
            ?? Date().addingTimeInterval(TimeInterval(minutes * 60))
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// =============================================================================
// MARK: - 共用零件（与 App 的 DSLightBar / DSStatRow 同一形态）
// =============================================================================

/// 光条 = 电量。亮的部分是已充的，暗的是还没充的。
struct WTLightBar: View {
    var progress: Double
    var fill: AnyShapeStyle = AnyShapeStyle(WT.Palette.lightBar)
    var track: AnyShapeStyle = AnyShapeStyle(WT.Palette.track)
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: max(geo.size.width * CGFloat(max(0, min(1, progress))), height))
            }
        }
        .frame(height: height)
    }
}

/// 分组标题（小字号 + 字距，与 App 的 DSSectionHeader 同一处理）
struct WTLabel: View {
    var text: String

    var body: some View {
        Text(text)
            .font(WT.Typo.sectionLabel)
            .tracking(0.6)
            .foregroundStyle(WT.Palette.labelTertiary)
    }
}

/// 事实行：左键右值（值走等宽数字）。行与行之间只有发丝线，没有容器。
struct WTFact: View {
    var label: String
    var value: String
    var valueCls: String = "na"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WT.Space.sm) {
            Text(label)
                .font(WT.Typo.footnote)
                .foregroundStyle(WT.Palette.labelSecondary)
            Spacer(minLength: WT.Space.xs)
            Text(value)
                .font(WT.Typo.data(14))
                .foregroundStyle(valueCls == "na" ? WT.Palette.label : WT.Palette.status(valueCls))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minHeight: 20)
    }
}

struct WTHairline: View {
    var body: some View {
        Rectangle()
            .fill(WT.Palette.hairline)
            .frame(height: 0.5)
    }
}

/// 读不到数据时的提示（绝不展示编造的数据）
struct WTSyncPrompt: View {
    var headline: String
    var detail: String
    @Environment(\.widgetFamily) private var family

    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    var body: some View {
        if isAccessory {
            // 锁屏配件只有一两行位置，只留一句
            Text("打开 App 同步")
                .font(WT.Typo.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: WT.Space.xs) {
                Spacer(minLength: 0)
                Text(headline)
                    .font(WT.Typo.headline)
                    .foregroundStyle(WT.Palette.label)
                Text(detail)
                    .font(WT.Typo.caption)
                    .foregroundStyle(WT.Palette.labelSecondary)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(WT.Space.widget)
        }
    }
}

/// 组件背景：内容族走画布色（与 App 同一画布），锁屏配件族交给系统（保持系统单色渲染）
private func wtBackground(_ family: WidgetFamily) -> Color {
    switch family {
    case .accessoryCircular, .accessoryRectangular, .accessoryInline:
        return .clear
    default:
        return WT.Palette.canvas
    }
}

// =============================================================================
// MARK: - ① 充电进度（桌面 小/中 + 锁屏 圆形/矩形）
// =============================================================================

struct ChargingProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChargingProgressWidget", provider: SnapshotProvider()) { entry in
            ChargingProgressView(entry: entry)
        }
        .configurationDisplayName("充电进度")
        .description("电量、充电功率与预计充满时间。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct ChargingProgressView: View {
    let entry: VehicleEntry
    @Environment(\.widgetFamily) private var family

    private var s: VehicleSnapshot { entry.snapshot }

    var body: some View {
        Group {
            if s.hasData {
                content
            } else {
                WTSyncPrompt(headline: "尚未同步", detail: "打开 App 查看一次车况")
            }
        }
        .containerBackground(for: .widget) {
            wtBackground(family)
        }
        .widgetURL(WT.Link.battery)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemMedium:
            medium
        default:
            small
        }
    }

    // ---- 桌面小：一个大数字 + 一条光带 ----
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: WT.Space.xs) {
                WTLabel(text: "充电")
                Spacer(minLength: 0)
                if s.charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WT.Palette.charge)
                }
            }
            Spacer(minLength: WT.Space.sm)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(s.soc)")
                    .font(WT.Typo.display(46))
                    .foregroundStyle(s.lowBattery ? WT.Palette.warn : WT.Palette.label)
                Text("%")
                    .font(WT.Typo.metric(20))
                    .foregroundStyle(WT.Palette.labelSecondary)
            }
            Text(s.charging ? s.powerText : "未在充电")
                .font(WT.Typo.footnote)
                .foregroundStyle(s.charging ? WT.Palette.charge : WT.Palette.labelSecondary)
                .lineLimit(1)
            WTLightBar(progress: s.fraction)
                .padding(.top, WT.Space.sm)
            Spacer(minLength: WT.Space.sm)
            Text(s.timeToFull.map { "续航 \(s.rangeKm) km · \($0)" } ?? "续航 \(s.rangeKm) km")
                .font(WT.Typo.caption)
                .foregroundStyle(WT.Palette.labelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(WT.Space.widget)
    }

    // ---- 桌面中：左边大数字与光带，右边三条事实 ----
    private var medium: some View {
        HStack(alignment: .top, spacing: WT.Space.xl) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: WT.Space.xs) {
                    WTLabel(text: "充电进度")
                    Spacer(minLength: 0)
                    if s.charging {
                        Text(s.powerText)
                            .font(WT.Typo.data(13))
                            .foregroundStyle(WT.Palette.charge)
                    }
                }
                Spacer(minLength: WT.Space.sm)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(s.soc)")
                        .font(WT.Typo.display(60))
                        .foregroundStyle(s.lowBattery ? WT.Palette.warn : WT.Palette.label)
                    Text("%")
                        .font(WT.Typo.metric(24))
                        .foregroundStyle(WT.Palette.labelSecondary)
                }
                WTLightBar(progress: s.fraction)
                    .padding(.top, WT.Space.sm)
                Spacer(minLength: 0)
                Text(s.charging ? "充电中" : (s.offline ? "离线 · 显示上次数据" : "未在充电"))
                    .font(WT.Typo.caption)
                    .foregroundStyle(s.charging ? WT.Palette.charge : WT.Palette.labelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                WTFact(label: "剩余续航", value: "\(s.rangeKm) km")
                WTHairline()
                WTFact(label: "预计充满", value: s.timeToFull ?? "--")
                WTHairline()
                WTFact(label: "车内温度", value: s.cabinTemp)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, WT.Space.xs)
        }
        .padding(WT.Space.widget)
    }

    // ---- 锁屏矩形：单色渲染下只靠字重与层级 ----
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: WT.Space.xs) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(s.charging ? "充电中 \(s.soc)%" : "电量 \(s.soc)%")
                    .font(WT.Typo.headline)
                Spacer(minLength: 0)
                if s.charging {
                    Text(s.powerText)
                        .font(WT.Typo.data(13))
                }
            }
            WTLightBar(
                progress: s.fraction,
                fill: AnyShapeStyle(Color.primary),
                track: AnyShapeStyle(Color.secondary.opacity(0.35)),
                height: 4
            )
            Text(s.timeToFull.map { "续航 \(s.rangeKm) km · \($0) 充满" } ?? "续航 \(s.rangeKm) km")
                .font(WT.Typo.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // ---- 锁屏圆形 ----
    private var circular: some View {
        Gauge(value: s.fraction) {
            Text("电量")
        } currentValueLabel: {
            Text("\(s.soc)%")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

// =============================================================================
// MARK: - ② 车辆状态（桌面 小/中）
// =============================================================================

struct VehicleStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VehicleStatusWidget", provider: SnapshotProvider()) { entry in
            VehicleStatusView(entry: entry)
        }
        .configurationDisplayName("车辆状态")
        .description("电量、续航、车锁与最后同步时间。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct VehicleStatusView: View {
    let entry: VehicleEntry
    @Environment(\.widgetFamily) private var family

    private var s: VehicleSnapshot { entry.snapshot }

    private var lockText: String { s.locked ? "已锁" : "未锁" }
    private var lockCls: String { s.locked ? "ok" : "warn" }

    var body: some View {
        Group {
            if !s.hasData {
                WTSyncPrompt(headline: "尚未同步", detail: "打开 App 查看一次车况")
            } else if family == .systemMedium {
                medium
            } else if family == .accessoryRectangular {
                rectangular
            } else {
                small
            }
        }
        .containerBackground(for: .widget) {
            wtBackground(family)
        }
        .widgetURL(WT.Link.vehicle)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: WT.Space.xs) {
                Circle()
                    .fill(s.offline ? WT.Palette.warn : WT.Palette.ok)
                    .frame(width: 6, height: 6)
                WTLabel(text: s.offline ? "离线" : "在线")
                Spacer(minLength: 0)
                Image(systemName: s.locked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(s.locked ? WT.Palette.labelSecondary : WT.Palette.warn)
            }
            Spacer(minLength: WT.Space.sm)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(s.soc)")
                    .font(WT.Typo.display(46))
                    .foregroundStyle(s.lowBattery ? WT.Palette.warn : WT.Palette.label)
                Text("%")
                    .font(WT.Typo.metric(20))
                    .foregroundStyle(WT.Palette.labelSecondary)
            }
            WTLightBar(progress: s.fraction)
                .padding(.top, WT.Space.sm)
            Spacer(minLength: WT.Space.sm)
            Text(s.charging ? "充电中 · 续航 \(s.rangeKm) km" : "续航 \(s.rangeKm) km")
                .font(WT.Typo.caption)
                .foregroundStyle(WT.Palette.labelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(WT.Space.widget)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: WT.Space.xl) {
            VStack(alignment: .leading, spacing: 0) {
                WTLabel(text: "剩余电量")
                Spacer(minLength: WT.Space.sm)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(s.soc)")
                        .font(WT.Typo.display(60))
                        .foregroundStyle(s.lowBattery ? WT.Palette.warn : WT.Palette.label)
                    Text("%")
                        .font(WT.Typo.metric(24))
                        .foregroundStyle(WT.Palette.labelSecondary)
                }
                WTLightBar(progress: s.fraction)
                    .padding(.top, WT.Space.sm)
                Spacer(minLength: 0)
                Text(s.charging ? "充电中 · \(s.powerText)" : "未在充电")
                    .font(WT.Typo.caption)
                    .foregroundStyle(s.charging ? WT.Palette.charge : WT.Palette.labelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                WTFact(label: "剩余续航", value: "\(s.rangeKm) km")
                WTHairline()
                WTFact(label: "车锁", value: lockText, valueCls: lockCls)
                WTHairline()
                WTFact(label: "车内温度", value: s.cabinTemp)
                WTHairline()
                WTFact(label: "总里程", value: "\(s.mileageKm) km")
                WTHairline()
                WTFact(label: "同步于", value: DateFormatter.wtRelative(s.updatedAt))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, WT.Space.xs)
        }
        .padding(WT.Space.widget)
    }

    private var rectangular: some View {
        HStack(spacing: WT.Space.sm) {
            Text("\(s.soc)%")
                .font(WT.Typo.metric(22))
            VStack(alignment: .leading, spacing: 1) {
                Text(s.charging ? "充电中 · 续航 \(s.rangeKm) km" : "续航 \(s.rangeKm) km")
                    .font(WT.Typo.footnote)
                Text("\(lockText) · \(s.cabinTemp)")
                    .font(WT.Typo.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// =============================================================================
// MARK: - ③ 充电实时活动（锁屏 + 灵动岛）
// =============================================================================

struct ChargingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChargingActivityAttributes.self) { context in
            ChargingLockScreenView(
                state: context.state,
                plate: context.attributes.plate,
                startedAt: context.attributes.startedAt
            )
            .activityBackgroundTint(WT.Palette.canvas)
            .widgetURL(WT.Link.battery)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(alignment: .firstTextBaseline, spacing: WT.Space.xs) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WT.Palette.charge)
                        Text("\(context.state.soc)")
                            .font(WT.Typo.metric(24))
                            .foregroundStyle(WT.Palette.label)
                        Text("%")
                            .font(WT.Typo.caption)
                            .foregroundStyle(WT.Palette.labelSecondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(context.state.powerText)
                            .font(WT.Typo.data(14))
                            .foregroundStyle(WT.Palette.charge)
                        Text(context.state.timeToFull.map { "\($0) 充满" } ?? "充电中")
                            .font(WT.Typo.caption2)
                            .foregroundStyle(WT.Palette.labelSecondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: WT.Space.xs) {
                        WTLightBar(progress: context.state.fraction)
                        Text("续航 \(context.state.rangeKm) km")
                            .font(WT.Typo.caption2)
                            .foregroundStyle(WT.Palette.labelSecondary)
                    }
                    .padding(.top, WT.Space.xxs)
                }
            } compactLeading: {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WT.Palette.charge)
            } compactTrailing: {
                Text("\(context.state.soc)%")
                    .font(WT.Typo.data(14))
                    .frame(width: 42)
            } minimal: {
                Text("\(context.state.soc)")
                    .font(WT.Typo.data(13))
            }
            .widgetURL(WT.Link.battery)
            .keylineTint(WT.Palette.charge)
        }
    }
}

/// 锁屏实时活动：一行状态 + 一个大数字 + 光带。和 App 首屏同一套层级。
struct ChargingLockScreenView: View {
    let state: ChargingActivityAttributes.ContentState
    let plate: String
    let startedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: WT.Space.md) {
            HStack(spacing: WT.Space.sm) {
                Image(systemName: state.charging ? "bolt.fill" : "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state.charging ? WT.Palette.charge : WT.Palette.ok)
                Text(plate)
                    .font(WT.Typo.subheadline.weight(.semibold))
                    .foregroundStyle(WT.Palette.label)
                    .lineLimit(1)
                Text(state.charging ? "充电中" : "已结束")
                    .font(WT.Typo.footnote)
                    .foregroundStyle(WT.Palette.labelSecondary)
                Spacer(minLength: WT.Space.sm)
                Text(startedAt, style: .timer)
                    .font(WT.Typo.data(13))
                    .foregroundStyle(WT.Palette.labelSecondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: WT.Space.xl) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(state.soc)")
                        .font(WT.Typo.display(58))
                        .foregroundStyle(state.lowBattery ? WT.Palette.warn : WT.Palette.label)
                    Text("%")
                        .font(WT.Typo.metric(24))
                        .foregroundStyle(WT.Palette.labelSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("续航 \(state.rangeKm) km")
                        .font(WT.Typo.footnote)
                        .foregroundStyle(WT.Palette.labelSecondary)
                    Text(state.timeToFull.map { "预计 \($0) 充满" } ?? "功率 \(state.powerText)")
                        .font(WT.Typo.footnote)
                        .foregroundStyle(WT.Palette.charge)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }

            WTLightBar(progress: state.fraction)
        }
        .padding(WT.Space.lg)
    }
}

// =============================================================================
// MARK: - 扩展入口
// =============================================================================

/// ⚠️ 类名必须与 Widgets/Info.plist 的 NSExtensionPrincipalClass 一致
@main
struct CarKeeperWidgetBundle: WidgetBundle {
    var body: some Widget {
        VehicleStatusWidget()
        ChargingProgressWidget()
        ChargingLiveActivityWidget()
    }
}

// =============================================================================
// MARK: - 小工具
// =============================================================================

extension DateFormatter {
    /// "12 分钟前"（与 App 内的相对时间同一套措辞）
    static func wtRelative(_ date: Date) -> String {
        guard date != .distantPast else { return "--" }
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(diff / 60) 分钟前" }
        if diff < 86400 { return "\(diff / 3600) 小时前" }
        return "\(diff / 86400) 天前"
    }
}
