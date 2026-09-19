// =============================================================================
// Widget — #27 锁屏 Widget（概念实现）
// 显示 SOC 圆环 + 锁车状态 + 车内温度
// 注：实际 Widget 需要创建 Today Extension Target
// =============================================================================

import SwiftUI
import WidgetKit

struct CarWidgetBundle: WidgetBundle {
    var body: some Widget {
        CarWidget()
        CarWidgetSmall()
        CarWidgetMedium()
    }
}

// MARK: - 小型 Widget（SOC 圆环）
struct CarWidget: Widget {
    let kind: String = "CarWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("车辆状态")
        .description("显示电量、锁车状态和温度")
        .supportedFamilies([.systemSmall])
    }
}

struct WidgetView: View {
    let entry: TimelineEntry
    var body: some View {
        VStack(spacing: 8) {
            Text("SOC")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(entry.soc)%")
                .font(.title)
                .fontWeight(.bold)
            HStack {
                Image(systemName: entry.locked ? "lock.fill" : "lock.open.fill")
                    .font(.caption)
                Text(entry.locked ? "已锁" : "未锁")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            Text("室内 \(entry.temp)°C")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }
}

// MARK: - 中型 Widget（详细信息）
struct CarWidgetMedium: Widget {
    let kind: String = "CarWidgetMedium"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            VStack(spacing: 12) {
                // SOC 大圆环
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                        .frame(width: 80, height: 80)
                    Circle()
                        .trim(from: 0, to: CGFloat(entry.soc) / 100)
                        .stroke(
                            LinearGradient(
                                colors: entry.soc > 50 ? [.green, .teal] : [.orange, .red],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                    Text("\(entry.soc)%")
                        .font(.system(size: 20, weight: .bold))
                }
                
                HStack {
                    VStack {
                        Image(systemName: entry.locked ? "lock.fill" : "lock.open.fill")
                        Text(entry.locked ? "已锁" : "未锁")
                            .font(.caption2)
                    }
                    Spacer()
                    VStack {
                        Image(systemName: "thermometer")
                        Text("室内 \(entry.temp)°C")
                            .font(.caption2)
                    }
                    Spacer()
                    VStack {
                        Image(systemName: "bolt.fill")
                        Text(entry.charging ? "充电中" : "未充电")
                            .font(.caption2)
                    }
                }
            }
            .padding(16)
        }
        .configurationDisplayName("车辆详情")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - 小型 Widget（状态卡片）
struct CarWidgetSmall: Widget {
    let kind: String = "CarWidgetSmall"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            HStack(spacing: 16) {
                VStack {
                    Text("SOC")
                        .font(.caption2)
                    Text("\(entry.soc)%")
                        .font(.headline)
                        .foregroundStyle(.accentColor)
                }
                Divider()
                    .opacity(0.5)
                VStack {
                    Text("温度")
                        .font(.caption2)
                    Text("\(entry.temp)°C")
                        .font(.headline)
                }
                Spacer()
                Image(systemName: entry.locked ? "lock.fill" : "lock.open.fill")
                    .font(.title2)
                    .foregroundStyle(entry.locked ? .green : .orange)
            }
            .padding(12)
        }
        .configurationDisplayName("快速状态")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Timeline Provider
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), soc: 65, temp: 22, locked: true, charging: false)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), soc: 65, temp: 22, locked: true, charging: false)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        var entries: [SimpleEntry] = []
        let now = Date()
        
        // 生成未来 1 小时的条目（每 5 分钟更新）
        for hourOffset in 0..<12 {
            let entryDate = Calendar.current.date(byAdding: .minute, value: hourOffset * 5, to: now)!
            let soc = max(0, 65 - hourOffset * 2) // 模拟电量消耗
            let entry = SimpleEntry(date: entryDate, soc: soc, temp: 22, locked: true, charging: false)
            entries.append(entry)
        }
        
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let soc: Int
    let temp: Int
    let locked: Bool
    let charging: Bool
}
