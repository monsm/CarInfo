// =============================================================================
// #NEW-129 桌面 Widget（独立于 Today Extension）— iOS 桌面小组件
// =============================================================================

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider
struct WidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), soc: 72, temp: 24, locked: true)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(WidgetEntry(date: Date(), soc: 68, temp: 23, locked: true))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        var entries: [WidgetEntry] = []
        let now = Date()
        for hourOffset in stride(from: 0, to: 24, by: 2) {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: now)!
            entries.append(WidgetEntry(date: entryDate, soc: 60 + hourOffset % 30, temp: 20 + hourOffset % 10, locked: hourOffset % 4 != 0))
        }
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let soc: Int
    let temp: Int
    let locked: Bool
}

// MARK: - Widget Views
struct CarWidgetEntryView: View {
    var entry: WidgetProvider.Entry
    
    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color(.systemBackground).opacity(0.85))
            
            VStack(spacing: 4) {
                HStack {
                    Image(systemName: entry.locked ? "lock.fill" : "lock.open.fill")
                        .font(.caption2)
                        .foregroundColor(entry.locked ? .green : .orange)
                    
                    Spacer()
                    
                    Text(entry.temp, format: .number)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("°C")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // SOC 进度条
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color(.systemGray4))
                    Capsule(style: .continuous)
                        .fill(entry.soc >= 80 ? .green : entry.soc >= 30 ? .blue : .red)
                        .frame(width: CGFloat(entry.soc) / 100 * (widgetSpacing.width - 16))
                        .animation(.easeInOut, value: entry.soc)
                }
                .frame(height: 6)
                
                Text("\(entry.soc)%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("EV CarKeeper")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
        .widgetBackground(Color.clear)
    }
}

struct CarWidgetSmall: Widget {
    let kind: String = "CarWidgetSmall"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            CarWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("车辆状态")
        .description("SOC、温度、锁车状态")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

struct CarWidgetMedium: Widget {
    let kind: String = "CarWidgetMedium"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "car.fill")
                    Text("My Car")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: entry.locked ? "lock.fill" : "lock.open.fill")
                        .foregroundColor(entry.locked ? .green : .orange)
                }
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("剩余续航")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("328 km")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("SOC")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(entry.soc)%")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                }
                
                // 充电进度
                if !entry.locked {
                    ProgressView(value: Double(entry.soc) / 100)
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding(.horizontal)
                }
                
                HStack {
                    VStack {
                        Image(systemName: "thermometer.medium")
                        Text("\(entry.temp)°C")
                            .font(.caption)
                    }
                    Spacer()
                    VStack {
                        Image(systemName: "bolt.fill")
                        Text("快充")
                            .font(.caption)
                    }
                    Spacer()
                    Button {
                        // 触发 widget refresh
                        WidgetCenter.shared.reloadAllTimelines()
                    } label: {
                        Image(systemName: "lock.fill")
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor.opacity(0.2))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
            }
            .padding(12)
        }
        .configurationDisplayName("CarKeeper 详情")
        .description("实时车况信息")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Extension Entry
@main
struct CarWidgetBundle: WidgetBundle {
    var body: some Widget {
        CarWidgetSmall()
        CarWidgetMedium()
    }
}
