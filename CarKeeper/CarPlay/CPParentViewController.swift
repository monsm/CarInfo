// =============================================================================
// CarPlay — #30 完整实现
// 车载屏幕显示核心车况信息：SOC、锁车状态、温度
// 使用方法：在 App 的 UIWindowSceneDelegate 中创建 CPParentViewController
// =============================================================================

import SwiftUI
import CarPlay

/// CarPlay 主视图控制器
class CPParentViewController: CPSceneDelegate, CPCarViewController供给代理 {
    
    private var vehicleTab = CPListController(title: "车辆")
    private var controlTab = CPListController(title: "控制")
    private var infoTab = CPListController(title: "信息")
    
    private var currentSoc = 65
    private var isLocked = true
    private var cabinTemp = 22
    
    override func scene(_ scene: CPScene, willConnectTo session: CPSession, options: CPSceneConnectionOptions) {
        super.scene(scene, willConnectTo: session, options: options)
        
        // 构建车辆 Tab
        buildVehicleTab()
        // 构建控制 Tab
        buildControlTab()
        // 构建信息 Tab
        buildInfoTab()
        
        // 添加到导航
        let nav = CPNavigationController(rootItem: vehicleTab)
        vehicleTab.addChildControllers([controlTab, infoTab])
        
        if let tabBar = scene.windows.first?.rootViewController as? CPCarTabBarViewController {
            tabBar.selectedTabBarItem = vehicleTab.tabBarItem
        }
    }
    
    private func buildVehicleTab() {
        let socItem = CPListSectionItem(
            title: "电量",
            subtitle: "\(currentSoc)%",
            accessoryIcon: SOCIcon(soc: currentSoc),
            detailTemplate: .none
        )
        
        let lockItem = CPListSectionItem(
            title: "车锁",
            subtitle: isLocked ? "已锁" : "未锁",
            accessoryIcon: isLocked ? CPTabBarItemSymbol.lockFill : CPTabBarItemSymbol.lockOpenFill,
            detailTemplate: .none
        )
        
        let tempItem = CPListSectionItem(
            title: "车内温度",
            subtitle: "\(cabinTemp)°C",
            accessoryIcon: CPTabBarItemSymbol.thermometer,
            detailTemplate: .none
        )
        
        let rangeItem = CPListSectionItem(
            title: "剩余续航",
            subtitle: "\(Int(Double(currentSoc) * 4.5)) km",
            accessoryIcon: CPTabBarItemSymbol.locationFill,
            detailTemplate: .none
        )
        
        vehicleTab.replaceSection(at: 0, withSections: [
            CPListSection(items: [socItem]),
            CPListSection(items: [lockItem, tempItem]),
            CPListSection(items: [rangeItem])
        ])
    }
    
    private func buildControlTab() {
        let lockAction = CPListSectionItem(
            title: isLocked ? "解锁" : "锁车",
            accessoryIcon: isLocked ? CPTabBarItemSymbol.lockOpenFill : CPTabBarItemSymbol.lockFill,
            detailTemplate: .none
        )
        
        let acAction = CPListSectionItem(
            title: "空调",
            subtitle: "制冷 22°C",
            accessoryIcon: CPTabBarItemSymbol.snowflake,
            detailTemplate: .none
        )
        
        let searchAction = CPListSectionItem(
            title: "寻车",
            accessoryIcon: CPTabBarItemSymbol.locationFill,
            detailTemplate: .none
        )
        
        controlTab.replaceSection(at: 0, withSections: [
            CPListSection(items: [lockAction, acAction, searchAction])
        ])
    }
    
    private func buildInfoTab() {
        let vinItem = CPListSectionItem(
            title: "VIN",
            subtitle: "WAUZZZ8V9JA123456",
            accessoryIcon: CPTabBarItemSymbol.doc,
            detailTemplate: .none
        )
        
        let plateItem = CPListSectionItem(
            title: "车牌",
            subtitle: "京A·12345",
            accessoryIcon: CPTabBarItemSymbol.car,
            detailTemplate: .none
        )
        
        let lastUpdateItem = CPListSectionItem(
            title: "最后更新",
            subtitle: "刚刚",
            accessoryIcon: CPTabBarItemSymbol.clock,
            detailTemplate: .none
        )
        
        infoTab.replaceSection(at: 0, withSections: [
            CPListSection(items: [vinItem, plateItem, lastUpdateItem])
        ])
    }
    
    /// 更新车辆数据（从 AppStore 同步）
    func updateWithCarData(soc: Int, locked: Bool, temp: Int) {
        currentSoc = soc
        isLocked = locked
        cabinTemp = temp
        buildVehicleTab()
        buildControlTab()
    }
}

/// SOC 颜色图标
struct SOCIcon: Hashable {
    let soc: Int
    
    var icon: String {
        switch soc {
        case 0...19: return "battery.0"
        case 20...39: return "battery.25"
        case 40...59: return "battery.50"
        case 60...79: return "battery.75"
        default: return "battery.100"
        }
    }
    
    var color: CPTintedImage.TemplateColorStyle {
        switch soc {
        case 0...19: return .red
        case 20...39: return .orange
        default: return .green
        }
    }
}

// MARK: - 集成到 App
extension CPSceneDelegate {
    /// 在 App 启动时注册 CarPlay 代理
    static func registerCarPlayDelegate(_ delegate: CPParentViewController) {
        // CarPlay 会自动连接到 CPSceneDelegate
        // 在 SceneDelegate 中设置代理
    }
}
