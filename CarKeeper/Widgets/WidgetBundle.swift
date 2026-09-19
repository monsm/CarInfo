// =============================================================================
// Widget — #27 锁屏 Widget（完整实现）
// 显示 SOC 圆环 + 锁车状态 + 车内温度
// 使用方法：创建 Today Extension Target，将此文件内容复制到 Extensions 中
// WidgetKit 会自动发现并注册
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
        // 从 UserDefaults 读取真实数据
        let soc = UserDefaults.standard.integer(forKey: "carkeeper_widget_soc")
        let temp = UserDefaults.standard.integer(forKey: "carkeeper_widget_temp")
        let locked = UserDefaults.standard.bool(forKey: "carkeeper_widget_locked")
        let charging = UserDefaults.standard.bool(forKey: "carkeeper_widget_charging")
        return SimpleEntry(date: Date(), soc: soc > 0 ? soc : 65, temp: temp > 0 ? temp : 22, locked: locked, charging: charging)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        completion(placeholder(in: context))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        var entries: [SimpleEntry] = []
        let now = Date()
        let baseEntry = placeholder(in: context)
        
        // 生成未来 2 小时的条目（每 15 分钟更新）
        for minuteOffset in 0..<8 {
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset * 15, to: now)!
            // 模拟电量随时间变化
            let soc = max(0, min(100, baseEntry.soc - minuteOffset * (baseEntry.charging ? -3 : 1)))
            let entry = SimpleEntry(date: entryDate, soc: soc, temp: baseEntry.temp, locked: baseEntry.locked, charging: baseEntry.charging)
            entries.append(entry)
        }
        
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

// MARK: - 数据同步扩展
extension AppStore {
    /// Widget 刷新时调用，更新 UserDefaults 中的车辆状态
    func syncWidgetData() {
        let energy = VM.energy(caches, car)
        UserDefaults.standard.set(energy.socPct, forKey: "carkeeper_widget_soc")
        UserDefaults.standard.set(energy.socPct < 20, forKey: "carkeeper_widget_low_battery")
        // 温度从控制缓存读取
        if let control = caches["control"] as? [String: Any] {
            let cabinTemp = ciNumber(control, ["CabinTemperature", "cabinTemp"]).map { Int($0.rounded()) }
            UserDefaults.standard.set(cabinTemp ?? 22, forKey: "carkeeper_widget_temp")
        }
        // 充电状态
        if let charge = caches["charge"] as? [String: Any] {
            let status = charge["ChrgStatus"] as? String ?? ""
            UserDefaults.standard.set(status == "1" || status == "2", forKey: "carkeeper_widget_charging")
        }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let soc: Int
    let temp: Int
    let locked: Bool
    let charging: Bool
    
    var lowBattery: Bool { soc < 20 }
    var warningText: String? {
        if lowBattery { return "电量过低，请及时充电" }
        if charging { return "充电中..." }
        return nil
    }
}
