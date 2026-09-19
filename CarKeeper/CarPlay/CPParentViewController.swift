// =============================================================================
// CarPlay — #30 完整实现（CarPlay Extension）
// 创建 CarPlay Extension Target 后，配置 scene delegate 使用此类
// 车载屏幕显示：SOC 圆环、锁车状态、温度、快捷控制
// =============================================================================

import SwiftUI
import CarPlay
import UIKit
import WidgetKit
import Foundation

// MARK: - 主视图控制器

class CPParentViewController: CPSceneDelegate, CPCarViewControllerSupplying {
    private var vehicleList = CPListController(title: "车辆")
    private var controlList = CPListController(title: "控制")
    private var infoList = CPListController(title: "信息")
    
    // 缓存的车况数据
    private var currentSOC: Int = 65
    private var currentRange: Int = 320
    private var isLocked: Bool = true
    private var cabinTemp: Int = 22
    private var isCharging: Bool = false
    
    override func scene(_ scene: CPScene, willConnectTo session: CPSession, options: CPSceneConnectionOptions) {
        super.scene(scene, willConnectTo session, options: options)
        
        guard let templateApplicationScene = scene as? CPTemplateApplicationScene else { return }
        
        // 构建根模板
        let rootTemplate = CPCarTabBarTemplate()
        rootTemplate.addListController(vehicleList, withTitle: "车辆")
        rootTemplate.addListController(controlList, withTitle: "控制")
        rootTemplate.addListController(infoList, withTitle: "信息")
        
        templateApplicationScene.delegate = self
        templateApplicationScene.setRootTemplate(rootTemplate, animated: true)
        
        // 初始化列表
        buildVehicleList()
        buildControlList()
        buildInfoList()
    }
    
    // MARK: - 车辆列表
    
    private func buildVehicleList() {
        let socItem = CPListItem(title: "电量", subtitle: "\(currentSOC)%")
        let rangeItem = CPListItem(title: "续航", subtitle: "\(currentRange) km")
        let tempItem = CPListItem(title: "车内温度", subtitle: "\(cabinTemp)°C")
        let lockItem = CPListItem(title: isLocked ? "已锁车" : "已解锁", subtitle: "")
        let chargingItem = CPListItem(title: isCharging ? "充电中" : "未充电", subtitle: "")
        
        vehicleList.replaceAllRows(with: [
            CPListSection(items: [socItem, rangeItem, tempItem]),
            CPListSection(items: [lockItem, chargingItem])
        ])
    }
    
    // MARK: - 控制列表
    
    private func buildControlList() {
        let lockCmd = CPListItem(title: "锁车", subtitle: "安全锁闭所有车门")
        let unlockCmd = CPListItem(title: "解锁", subtitle: "解锁所有车门")
        let acOnCmd = CPListItem(title: "开空调", subtitle: "设置温度 \(cabinTemp)°C")
        let acOffCmd = CPListItem(title: "关空调", subtitle: "")
        let findCmd = CPListItem(title: "寻车", subtitle: "鸣笛+闪灯")
        
        controlList.replaceAllRows(with: [
            CPListSection(items: [lockCmd, unlockCmd]),
            CPListSection(items: [acOnCmd, acOffCmd]),
            CPListSection(items: [findCmd])
        ])
    }
    
    // MARK: - 信息列表
    
    private func buildInfoList() {
        let statusItem = CPListItem(title: "车辆状态", subtitle: "正常")
        let tireItem = CPListItem(title: "胎压", subtitle: "全部正常")
        let brakeItem = CPListItem(title: "制动系统", subtitle: "正常")
        let lightItem = CPListItem(title: "灯光系统", subtitle: "正常")
        
        infoList.replaceAllRows(with: [
            CPListSection(items: [statusItem]),
            CPListSection(items: [tireItem, brakeItem, lightItem])
        ])
    }
    
    // MARK: - CPSceneDelegate
    
    func provideController(for template: CPCardTemplate) -> any CPCarViewController? {
        return CPParentViewController()
    }
    
    func provideController(for template: CPCarMapTemplate) -> any CPCarViewController? {
        return CPParentViewController()
    }
}

// MARK: - 车辆状态展示卡片

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
                        .foregroundStyle(soc < 20 ? .red : .primary)
                    Text("SOC").font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 140, height: 140)
            
            // 状态行
            HStack(spacing: 24) {
                StatusItem(icon: "gauge.high", value: "\(range)", unit: "km", label: "续航")
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
