// =============================================================================
//  CarPlay — 实时地图 + 车况状态 + 快捷控制
//
//  架构说明（2026-09-22 定案）：
//    · 车机扩展**不能自己联网**（App Store 审核红线），所有数据从 App Group
//      读取：主 App 在 syncSharedDefaults() 把 VehicleSnapshot 写进 group，
//      车机每 15 s 读一次，位置变更时自动重绑地图钉。
//    · 控制指令通过 NSNotification 跨进程投递到主 App（主 App 负责真正的
//      API 调用；车机只是"请求"，不直接请求服务器）。
//
//  界面结构：
//    ┌─────────────────────────────────────────┐
//    │  CPTemporarilyLocatedMapTemplate        │  ← 实时地图，钉在车辆位置
//    │                                         │
//    │     [SOC 圆环] 续航 XX km  充电中/已锁   │  ← 大标题式状态条
//    │                                         │
//    │  温度 22℃  🔒已锁  ⚡充电中             │  ← 一行状态
//    │                                         │
//    │  [锁车] [解锁] [寻车] [空调]            │  ← 四个大按钮
//    └─────────────────────────────────────────┘
//
//  颜色规则（与 App / Widget 同一套令牌）：
//    soc < 20%  → 橙色 warn（提醒补能）
//    soc < 10%  → 红色 bad  （立即补能）
//    charging   → 青色 charge（充电中）
//    其余       → 蓝色 accent / 绿色 ok
// =============================================================================

import Foundation
import CarPlay
import CoreLocation
import UIKit

// MARK: - 常量

private let appGroup = "group.com.you.CarKeeper"
/// 主 App 写 App Group 的 key，与 Shared/WidgetTokens.swift 的 snapshotKey 一致
private let snapshotKey = "snapshot_v1"
/// 刷新周期：15 秒 — 比车况轮询（60 s）略勤，保证车机上的信息不会太旧
private let refreshInterval: TimeInterval = 15.0

// MARK: - 车辆标注（Custom CPAnnotation 子类）

/// 车辆位置标注：在地图上画一个带 SOC 百分比的小圆圈，颜色按电量语义分级。
final class CarAnnotation: CPAnnotation {
    let coordinate: CLLocationCoordinate2D
    let chargeStatus: Bool
    let socPercent: Int
    /// 当前选中的状态（用来决定 callout 内容）
    var isSelected: Bool = false

    init(coordinate: CLLocationCoordinate2D,
         chargeStatus: Bool,
         socPercent: Int) {
        self.coordinate = coordinate
        self.chargeStatus = chargeStatus
        self.socPercent = socPercent
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - 场景委托（CarPlay 入口）

final class CPParentViewController: NSObject, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?
    private var mapTemplate: CPTemporarilyLocatedMapTemplate?
    private var statusTemplate: CPListTemplate?
    private var tabBar: CPTabBarTemplate?

    // 上次已知的位置，用于检测"车动了"
    private var lastCarLocation: CLLocation?
    // 上次已知的位置更新时间，决定要不要重绑钉
    private var lastPositionTime: Date?

    // 定时刷新
    private var refreshTimer: Timer?
    // 当前快照（nil = 还没同步过，显示离线态）
    private var currentSnapshot: VehicleSnapshot?

    // MARK: - 生命周期

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        startRefreshLoop()
        loadSnapshot()
        buildTemplates()
        showRoot()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - 刷新循环

    private func startRefreshLoop() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.loadSnapshot()
        }
    }

    private func loadSnapshot() {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        guard let data = defaults.data(forKey: snapshotKey) else {
            // 没有数据 = 还没同步过，保持当前状态不变
            return
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        guard let snap = try? dec.decode(VehicleSnapshot.self, from: data) else { return }
        guard snap.hasData else { return }
        currentSnapshot = snap
        // 位置变了 → 重绑地图钉
        if snap.lat != nil, snap.lng != nil {
            let newLoc = CLLocation(latitude: snap.lat!, longitude: snap.lng!)
            if lastCarLocation == nil
                || newLoc.distance(from: lastCarLocation!) > 50.0 {
                lastCarLocation = newLoc
                lastPositionTime = Date()
                refreshMapAnnotation()
            }
        }
        // 状态变化 → 刷新状态页
        refreshStatusTemplate()
    }

    // MARK: - 模板构建

    private func buildTemplates() {
        // 地图页
        let mapSnap = currentSnapshot ?? .placeholder
        let mapLocation: CLLocation?
        if let lat = mapSnap.lat, let lng = mapSnap.lng {
            mapLocation = CLLocation(latitude: lat, longitude: lng)
        } else {
            mapLocation = nil
        }
        let mapTpl = CPTemporarilyLocatedMapTemplate(carLocation: mapLocation)
        mapTpl.delegate = self
        mapTpl.title = "车辆位置"
        mapTpl.showsDefaultDistanceIndicators = true
        mapTpl.displaysTraffic = false
        mapTemplate = mapTpl

        // 状态页
        let statusTpl = CPListTemplate(title: "车况")
        statusTpl.sections = [statusSection()]
        statusTemplate = statusTpl

        // Tab 栏
        tabBar = CPTabBarTemplate(templates: [mapTpl, statusTpl])
    }

    private func showRoot() {
        guard let tabBar else { return }
        interfaceController?.setRootTemplate(tabBar, animated: false, completion: nil)
    }

    // MARK: - 状态页刷新

    private func refreshStatusTemplate() {
        let snap = currentSnapshot ?? .placeholder
        statusTemplate?.sections = [statusSection(snap: snap)]
    }

    private func statusSection(snap: VehicleSnapshot = .placeholder) -> CPListSection {
        let sec = CPListSection()
        // 大标题：SOC + 续航
        let socItem = CPListItem(
            text: String(snap.soc) + " %",
            detailText: "剩余续航 " + String(snap.rangeKm) + " km"
        )
        sec.addItem(socItem)

        // 充电状态
        if snap.charging {
            let chargeItem = CPListItem(
                text: "充电中",
                detailText: snap.powerText + (snap.timeToFull.map { " · 预计 \($0)" } ?? "")
            )
            sec.addItem(chargeItem)
        }

        // 车门锁状态
        let lockItem = CPListItem(
            text: snap.locked ? "已上锁" : "已解锁",
            detailText: nil
        )
        sec.addItem(lockItem)

        // 车内温度
        let tempItem = CPListItem(
            text: "车内温度",
            detailText: snap.cabinTemp
        )
        sec.addItem(tempItem)

        // 里程
        let mileItem = CPListItem(
            text: "总里程",
            detailText: String(snap.mileageKm) + " km"
        )
        sec.addItem(mileItem)

        // 更新时间
        let ageItem = CPListItem(
            text: "数据更新",
            detailText: dateAgo(snap.updatedAt)
        )
        sec.addItem(ageItem)

        return sec
    }

    // MARK: - 地图标注刷新

    private func refreshMapAnnotation() {
        guard let snap = currentSnapshot, let loc = lastCarLocation else { return }
        let coord = loc.coordinate
        // 移除旧标注
        if let old = mapTemplate?.annotations.first {
            mapTemplate?.removeAnnotation(old)
        }
        // 添加新标注
        let annotation = CarAnnotation(
            coordinate: coord,
            chargeStatus: snap.charging,
            socPercent: snap.soc
        )
        mapTemplate?.addAnnotation(annotation)
        mapTemplate?.setSelectedAnnotation(annotation, animated: true)
    }

    // MARK: - 辅助

    private func dateAgo(_ date: Date) -> String {
        let ago = Int(Date().timeIntervalSince(date))
        if ago < 60 { return "刚刚" }
        if ago < 3600 { return "\(ago / 60) 分钟前" }
        if ago < 86400 { return "\(ago / 3600) 小时前" }
        return "\(ago / 86400) 天前"
    }
}

// MARK: - 地图代理（处理点击标注、区域变更等）

extension CPParentViewController: CPMapTemplateDelegate {

    func map(_ mapTemplate: CPMapTemplate, didChangeVisibleRegion region: MKCoordinateRegion) {
        // 地图区域变化不做特殊处理
    }

    func map(_ mapTemplate: CPMapTemplate, didSelect annotation: CPAnnotation) {
        guard let carAnn = annotation as? CarAnnotation else { return }
        // 选中车辆标注 → 弹出 callout 显示关键状态
        let snap = currentSnapshot ?? .placeholder
        let callout = CPListTemplate(
            title: "车辆状态",
            sections: [
                CPListSection(items: [
                    CPListItem(
                        text: "电量",
                        detailText: "\(snap.soc)% · 续航 \(snap.rangeKm) km"
                    ),
                    CPListItem(
                        text: "车门",
                        detailText: snap.locked ? "已上锁" : "已解锁"
                    ),
                    CPListItem(
                        text: "充电",
                        detailText: snap.charging ? "正在充电" : "未连接"
                    )
                ])
            ]
        )
        mapTemplate.showCallout(annotation, template: callout, animated: true)
    }

    func map(_ mapTemplate: CPMapTemplate, didDeselect annotation: CPAnnotation) {
        // 取消选中不做特殊处理
    }

    func map(_ mapTemplate: CPMapTemplate, didFailToRetrieveAnnotationViewsForAnnotations annotations: [CPAnnotation]) {
        NSLog("CarPlay: 标注视图获取失败: \(annotations.count) 个")
    }
}
