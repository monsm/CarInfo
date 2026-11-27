import SwiftUI
import UIKit


struct DevView: View {
    private let store = AppStore.shared
    @State private var showClearConfirm = false
    @State private var logTick = 0
    @ObservedObject private var memory = MemoryMonitor.shared
    @ObservedObject private var networkQuality = NetworkQualityMonitor.shared
    @ObservedObject private var chargeMonitor = ChargingStatusMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            kvGroup("运行状态", runtime)
            diagnosticsGroups
            actionsGroup
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { networkQuality.measureLatency() }
        .confirmationDialog("清除全部车端缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清除缓存", role: .destructive) {
                store.clearCache()
                TokensHaptic.result(true)
                ToastManager.shared.show("缓存已清除", icon: "trash")
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("只清空车况、充电、定位、环境、检测、消息缓存，不会退出登录。")
        }
    }






    private func kvGroup(_ title: String, _ rows: [(String, String)], footer: String? = nil) -> some View {
        DSGroup(title: title, footer: footer) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                DSGroupRow(showsSeparator: idx < rows.count - 1) {
                    DSKeyValueRow(key: row.0, value: row.1, mono: false)
                }
            }
        }
    }


    private var runtime: [(String, String)] {
        let mileage = UserDefaults.standard.integer(forKey: AppStore.currentMileageKey)
        let lastService = UserDefaults.standard.integer(forKey: AppStore.lastServiceMileageKey)
        let plan = store.maintenancePlan

        return [
            ("指令历史", "\(store.commandHistory.count) 条"),
            ("能耗记录", "\(store.energyHistory.count) 次"),
            ("网络状态", networkText),
            ("车辆 ID", store.carId.isEmpty ? "—" : store.carId),
            ("内存占用", memory.usedMemoryMB > 0
                ? String(format: "%.1f MB", memory.usedMemoryMB) + "（\(memoryLevelText)）"
                : "采样中…"),
            ("网络延迟", networkQuality.latency > 0
                ? String(format: "%.0f ms", networkQuality.latency) + " · \(networkQuality.connectionType)"
                : "未测出"),
            ("网络可达", networkQuality.isReachable ? "可达" : "不可达"),
            ("充电监控", chargeMonitor.summary),
            ("车端里程", mileage > 0 ? "\(mileage) km" : "未取到"),
            ("保养计划", plan.map { p in
                let src = p.fromServer ? "车厂计划" : "本机记录"
                return "\(p.last) + \(p.interval) = \(p.next) km（\(src)，当前 \(p.current)）"
            } ?? "未登记"),
            ("上次保养里程", lastService > 0 ? "\(lastService) km" : "未设置")
        ]
    }

    private var memoryLevelText: String {
        switch memory.warningLevel {
        case 2: return "临界"
        case 1: return "偏高"
        default: return "正常"
        }
    }

    private var networkText: String { store.networkStatus.rawValue }

    private var diagnosticsGroups: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            MessageProbeSection()
            rawLogGroup
        }
    }

    private var rawLogGroup: some View {
        let entries = RawLogStore.shared.allEntries()
        return DSGroup(title: "原始日志", trailing: "\(entries.count) 条",
                       footer: "最近 60 条，内存里；token / 控车码 / 车牌 / 坐标已打码。" +
                               "报「消息拿不到」时，先看 pageReceiverInfoByTime 那条的 status 与长度。") {
            DSGroupRow {
                DSRow(icon: "arrow.clockwise", title: "重新读取") { logTick += 1 }
            }
            DSGroupRow {
                DSRow(icon: "doc.on.doc", title: "复制全部日志") {
                    UIPasteboard.general.string = RawLogStore.shared.joined()
                    TokensHaptic.result(true)
                    ToastManager.shared.show("原始日志已复制", icon: "doc.on.doc.fill")
                }
            }
            if entries.isEmpty {
                DSGroupRow(showsSeparator: false) {
                    Text("还没有请求记录")
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.secondary)
                }
            } else {
                ForEach(Array(entries.prefix(8).enumerated()), id: \.offset) { idx, e in
                    DSGroupRow(showsSeparator: idx < min(8, entries.count) - 1) {
                        VStack(alignment: .leading, spacing: TokensSpacing.xxs) {
                            Text(Self.logHeadline(e))
                                .font(TokensTypo.fixed(11, weight: .regular).monospacedDigit())
                                .foregroundStyle(TokensPalette.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(e.count) 字符")
                                .font(TokensTypo.caption2)
                                .foregroundStyle(TokensPalette.tertiary)
                        }
                    }
                }
            }
        }
        .id(logTick)
    }

    private static func logHeadline(_ entry: String) -> String {
        entry.split(separator: "\n").first.map(String.init) ?? entry
    }


    private var actionsGroup: some View {
        DSGroup(title: "操作", footer: "诊断信息包含版本、车辆 ID、缓存与网络状态，用于报障。") {
            DSGroupRow {
                DSRow(icon: "doc.on.doc", title: "复制诊断信息") {
                    UIPasteboard.general.string = diagnostics
                    TokensHaptic.result(true)
                    ToastManager.shared.show("诊断信息已复制", icon: "doc.on.doc.fill")
                }
            }
            DSGroupRow(showsSeparator: false) {
                DSRow(icon: "trash", title: "清除缓存", subtitle: "不会退出登录") {
                    showClearConfirm = true
                }
            }
        }
    }

    private var diagnostics: String {
        var lines = ["【CarKeeper 诊断信息】", "版本 \(appVersion) (\(buildNumber))"]
        lines.append("车辆 ID：\(store.carId.isEmpty ? "未绑定" : store.carId)")
        lines.append("登录状态：\(store.isLoggedIn ? "已登录" : "未登录")")
        lines.append("网络状态：\(networkText)")
        for row in runtime { lines.append("\(row.0)：\(row.1)") }
        return lines.joined(separator: "\n")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

}
