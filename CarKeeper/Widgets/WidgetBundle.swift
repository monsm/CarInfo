// =============================================================================
// WidgetBundle — #27 锁屏 Widget（Today Extension 完整实现）
// 创建 Today Extension Target 后，将此文件内容复制到 Extension 中
// 使用方法：
//   1. Xcode → File → New → Target → Widget Extension
//   2. Bundle ID: com.yourcompany.CarKeeper.widget
//   3. 将本文件内容粘贴到 Extension 目录
//   4. 在 Info.plist 中添加 NSExtension → NSExtensionPoints
// =============================================================================

import SwiftUI
import WidgetKit
import Foundation

// MARK: - Timeline Entry

struct CarWidgetEntry: TimelineEntry {
    let date: Date
    let soc: Int
    let range: Int
    let temp: String
    let locked: Bool
    let charging: Bool
    let isOffline: Bool
    let lowBattery: Bool
    
    static func placeholder() -> CarWidgetEntry {
        CarWidgetEntry(date: Date(), soc: 65, range: 320, temp: "22℃", locked: true, charging: false, isOffline: false, lowBattery: false)
    }
    
    static func mock() -> CarWidgetEntry {
        CarWidgetEntry(date: Date(), soc: 78, range: 380, temp: "21℃", locked: true, charging: false, isOffline: false, lowBattery: false)
    }
}

// MARK: - Provider（数据源）

struct CarWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CarWidgetEntry {
        CarWidgetEntry.placeholder()
    }
    
    func getSnapshot(in context: Context, completion: @escaping (CarWidgetEntry) -> Void) {
        completion(CarWidgetEntry.mock())
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<CarWidgetEntry>) -> Void) {
        // 从 UserDefaults 读取实际数据（与 App 共享 App Group）
        let defaults = UserDefaults(suiteName: "group.com.carkeeper.data") ?? UserDefaults.standard
        let soc = defaults.integer(forKey: "widget_soc")
        let range = defaults.integer(forKey: "widget_range")
        let temp = defaults.string(forKey: "widget_temp") ?? "22℃"
        let locked = defaults.bool(forKey: "widget_locked")
        let charging = defaults.bool(forKey: "widget_charging")
        let isOffline = defaults.bool(forKey: "widget_offline")
        
        let entry = CarWidgetEntry(
            date: Date(), soc: max(0, min(100, soc)), range: max(0, range),
            temp: temp, locked: locked, charging: charging,
            isOffline: isOffline, lowBattery: soc < 20
        )
        
        // 每 5 分钟刷新一次
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Small Widget（锁屏/桌面小控件）

struct CarWidgetSmall: Widget {
    let kind: String = "CarWidgetSmall"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CarWidgetProvider()) { entry in
            CarWidgetSmallView(entry: entry)
        }
        .configurationDisplayName("车况概览")
        .description("显示 SOC、续航、温度、锁车状态")
        .supportedFamilies([.systemSmall])
    }
}

struct CarWidgetSmallView: View {
    let entry: CarWidgetEntry
    
    var body: some View {
        VStack(spacing: 6) {
            // SOC 圆环
            ZStack {
                Circle().stroke(Color.gray.opacity(0.3), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(entry.soc) / 100)
                    .stroke(
                        LinearGradient(
                            colors: entry.lowBattery ? [.red, .orange] : [.green, .teal],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 6
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(entry.soc)%")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(entry.lowBattery ? .red : .primary)
                    Text("SOC").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            
            // 状态行
            HStack(spacing: 8) {
                Label("\(entry.range)km", systemImage: "gauge")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                if entry.charging {
                    Label("⚡", systemImage: "bolt.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                }
                Label(entry.temp, systemImage: "thermometer")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            
            // 离线指示器
            if entry.isOffline {
                Text("离线")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
            }
        }
        .padding(8)
        .background(Color(.systemBackground).opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Medium Widget（扩展视图）

struct CarWidgetMedium: Widget {
    let kind: String = "CarWidgetMedium"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CarWidgetProvider()) { entry in
            CarWidgetMediumView(entry: entry)
        }
        .configurationDisplayName("车辆详情")
        .description("显示更详细的车辆状态和快捷操作")
        .supportedFamilies([.systemMedium])
    }
}

struct CarWidgetMediumView: View {
    let entry: CarWidgetEntry
    
    var body: some View {
        VStack(spacing: 10) {
            // 标题栏
            HStack {
                Text("我的车辆")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if entry.isOffline {
                    Text("离线")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                } else {
                    Text(entry.date, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            
            // 主要数据
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("电量").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text("\(entry.soc)%").font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(entry.lowBattery ? .red : .green)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("续航").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text("\(entry.range) km").font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("温度").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(entry.temp).font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
            
            // 快捷操作按钮
            HStack(spacing: 12) {
                CarWidgetButton(icon: entry.locked ? "lock.fill" : "lock.open.fill", label: entry.locked ? "已锁" : "未锁")
                CarWidgetButton(icon: "fan.fill", label: "空调")
                CarWidgetButton(icon: "horn.fill", label: "寻车")
            }
            
            // 充电状态
            if entry.charging {
                HStack {
                    ProgressView(value: CGFloat(entry.soc) / 100)
                        .progressViewStyle(LinearProgressViewStyle(tint: .green))
                    Text("\(entry.soc)%").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground).opacity(0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct CarWidgetButton: View {
    let icon: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - 注册 Widget

struct CarKeeperWidgetBundle: WidgetBundle {
    var body: some Widget {
        CarWidgetSmall()
        CarWidgetMedium()
    }
}
