// =============================================================================
// CarPlay — #30 CarPlay Extension
// 车载屏幕显示：SOC 圆环、锁车状态、温度、快捷控制
// 入口类由 CarPlay/Info.plist 的 NSExtensionPrincipalClass 指定：
//   $(PRODUCT_MODULE_NAME).CPParentViewController
//
// 说明：本文件原先使用的 CPSceneDelegate / CPListController / CPCarTabBarTemplate
//       / CPListItem(title:subtitle:) 等均不是 CarPlay 的真实 API，已按官方模板
//       体系（CPTemplateApplicationSceneDelegate + CPListTemplate/CPTabBarTemplate）
//       重写。
// =============================================================================

import SwiftUI
import CarPlay
import UIKit
import Foundation

// MARK: - 场景委托（构建车载模板）

final class CPParentViewController: NSObject, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?

    // 车辆 / 控制 / 信息 三组列表模板
    private let vehicleList = CPListTemplate(title: "车辆", sections: [])
    private let controlList = CPListTemplate(title: "控制", sections: [])
    private let infoList = CPListTemplate(title: "信息", sections: [])

    // 缓存的车况数据
    private var currentSOC: Int = 65
    private var currentRange: Int = 320
    private var isLocked: Bool = true
    private var cabinTemp: Int = 22
    private var isCharging: Bool = false

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        buildVehicleList()
        buildControlList()
        buildInfoList()

        let tabBar = CPTabBarTemplate(templates: [vehicleList, controlList, infoList])
        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
    }

    // MARK: - 车辆列表

    private func buildVehicleList() {
        let socItem = CPListItem(text: "电量", detailText: "\(currentSOC)%")
        let rangeItem = CPListItem(text: "续航", detailText: "\(currentRange) km")
        let tempItem = CPListItem(text: "车内温度", detailText: "\(cabinTemp)°C")
        let lockItem = CPListItem(text: isLocked ? "已锁车" : "已解锁", detailText: nil)
        let chargingItem = CPListItem(text: isCharging ? "充电中" : "未充电", detailText: nil)

        vehicleList.updateSections([
            CPListSection(items: [socItem, rangeItem, tempItem]),
            CPListSection(items: [lockItem, chargingItem])
        ])
    }

    // MARK: - 控制列表

    private func buildControlList() {
        let lockCmd = CPListItem(text: "锁车", detailText: "安全锁闭所有车门")
        let unlockCmd = CPListItem(text: "解锁", detailText: "解锁所有车门")
        let acOnCmd = CPListItem(text: "开空调", detailText: "设置温度 \(cabinTemp)°C")
        let acOffCmd = CPListItem(text: "关空调", detailText: nil)
        let findCmd = CPListItem(text: "寻车", detailText: "鸣笛+闪灯")

        // handler 是 CPListItem 的可选闭包属性，第二参数用于告知 CarPlay 操作已完成
        lockCmd.handler = { [weak self] _, completion in
            self?.isLocked = true
            completion()
        }
        unlockCmd.handler = { [weak self] _, completion in
            self?.isLocked = false
            completion()
        }
        acOnCmd.handler = { _, completion in completion() }
        acOffCmd.handler = { _, completion in completion() }
        findCmd.handler = { _, completion in completion() }

        controlList.updateSections([
            CPListSection(items: [lockCmd, unlockCmd]),
            CPListSection(items: [acOnCmd, acOffCmd]),
            CPListSection(items: [findCmd])
        ])
    }

    // MARK: - 信息列表

    private func buildInfoList() {
        let statusItem = CPListItem(text: "车辆状态", detailText: "正常")
        let tireItem = CPListItem(text: "胎压", detailText: "全部正常")
        let brakeItem = CPListItem(text: "制动系统", detailText: "正常")
        let lightItem = CPListItem(text: "灯光系统", detailText: "正常")

        infoList.updateSections([
            CPListSection(items: [statusItem]),
            CPListSection(items: [tireItem, brakeItem, lightItem])
        ])
    }
}

// MARK: - 车辆状态展示卡片（可在 iPhone 侧复用）

struct CarPlayStatusCardView: View {
    let soc: Int
    let range: Int
    let temp: Int
    let locked: Bool
    let charging: Bool

    var body: some View {
        VStack(spacing: 16) {
            // SOC 圆环
            ZStack {
                Circle().stroke(Color.gray.opacity(0.3), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(soc) / 100)
                    .stroke(
                        LinearGradient(
                            colors: soc < 20 ? [.red, .orange] : [.green, .teal],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 12
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(soc)%")
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(soc < 20 ? Color.red : Color.primary)
                    Text("SOC").font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 140, height: 140)

            // 状态行
            HStack(spacing: 24) {
                StatusItem(icon: "gauge", value: "\(range)", unit: "km", label: "续航")
                StatusItem(icon: "thermometer", value: "\(temp)", unit: "°C", label: "温度")
                StatusItem(icon: locked ? "lock.fill" : "lock.open.fill", value: locked ? "已锁" : "未锁", unit: "", label: "车门")
                if charging {
                    StatusItem(icon: "bolt.fill", value: "充电中", unit: "", label: "")
                }
            }
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct StatusItem: View {
    let icon: String
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Label(value + (unit.isEmpty ? "" : unit), systemImage: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 预览

struct CPParentViewController_Previews: PreviewProvider {
    static var previews: some View {
        CarPlayStatusCardView(soc: 78, range: 380, temp: 22, locked: true, charging: false)
    }
}
