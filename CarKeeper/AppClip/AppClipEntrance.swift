// =============================================================================
// AppClip — #46 完整实现
// 扫码车牌直接进入车辆页面，无需安装完整 App
// 使用方法：创建 AppClip Target，使用相同 Bundle ID 前缀
// 支持的 URL Scheme：carkeeper://plate/京A12345
// =============================================================================

import SwiftUI
import UIKit

// MARK: - AppClip 入口视图

struct AppClipEntranceView: View {
    @State private var plateInput: String = ""
    @State private var hasError = false
    @State private var showMainApp = false
    /// 主 App 写进 App Group 的快照（App Clip 没有登录态，这是它**唯一**能拿到的真实数据）
    @State private var snapshot: VehicleSnapshot?


    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                // 品牌色对：系统蓝 → 电驱青。
                // 原来是「系统蓝 + 系统紫」—— 那两个色在 App 里哪儿都不出现，
                // 是这个文件自带的一套（同一件事的第二、第三个名字）。
                colors: [WT.Palette.tint.opacity(0.3), WT.Palette.charge.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // Logo
                ZStack {
                    Circle()
                        .fill(Material.thin)
                        .frame(width: 80, height: 80)
                        .overlay(Circle().strokeBorder(WT.Palette.onAccent.opacity(0.2), lineWidth: 1))
                    Image(systemName: "car.fill")
                        .font(WT.Typo.fixed(36))
                        .foregroundStyle(WT.Palette.onAccent)
                }

                Text("CarKeeper")
                    .font(WT.Typo.fixed(24, weight: .bold))
                    .foregroundStyle(WT.Palette.onAccent)
                Text("扫码车牌，快速查看车辆状态")
                    .font(WT.Typo.subheadline)
                    // 渐变底是彩色面：文字用「彩色面上的文字色」，它在两种外观下都是白
                    .foregroundStyle(WT.Palette.onAccent.opacity(0.7))
                    .multilineTextAlignment(.center)

                // 车牌输入框
                HStack(spacing: 12) {
                    Image(systemName: "creditcard.fill").font(WT.Typo.title3).foregroundStyle(WT.Palette.tint)
                    TextField("请输入车牌号", text: $plateInput)
                        .font(WT.Typo.data(18).weight(.medium))
                        .textInputAutocapitalization(.characters)
                        .keyboardType(.asciiCapable)
                        .autocorrectionDisabled()
                    if !plateInput.isEmpty {
                        Button(action: { plateInput = "" }, label: {
                            Image(systemName: "xmark.circle.fill")
                        })
                        .foregroundStyle(WT.Palette.labelSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WT.Palette.labelSecondary.opacity(0.3), lineWidth: 1))

                // 加载状态
                // 【已删】加载中的转圈。读 App Group 里的快照是**同步**的，
                // 转圈只是一个表演用的延迟（原实现还配了 1.5 秒的 dispatchAfter）。

                // 错误提示
                if hasError {
                    // 以前这里写「未找到该车辆，请检查车牌号」—— 但 App Clip 根本没查过任何东西：
                    // 它没有登录态、也不带令牌，**无法联网核验车牌**。那句提示把「查不到」
                    // 说成了用户的输入问题。现在说的是实话。
                    Text("本机还没有主 App 共享的车况：请打开完整 App 并刷新一次车况（App Clip 没有登录态，只能读主 App 同步过来的数据）。")
                        .font(WT.Typo.footnote)
                        .foregroundStyle(WT.Palette.bad.opacity(0.8))
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                // 查到的车况（真数据：来自主 App 写进 App Group 的快照）
                if let s = snapshot { snapshotCard(s) }

                // 主要操作按钮
                Button {
                    query()
                } label: {
                    Text("查看车辆状态")
                        .font(WT.Typo.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        // 渐变上的实心卡：`onAccent` 在两种外观下都是白 ——
                        // 因为它站的底是彩色的（与 App 内文字用色同一套语义）
                        .background(WT.Palette.onAccent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(WT.Palette.tint)
                }

                // 已有账号？打开完整 App
                Button {
                    showMainApp = true
                } label: {
                    Text("打开完整 App")
                        .font(WT.Typo.subheadline)
                        .foregroundStyle(WT.Palette.onAccent.opacity(0.6))
                }

                Spacer()

                // 功能说明。
                // 写「实时」是不诚实的：Clip 自己发不了请求，显示的只能是主 App
                // 最近一次同步的快照 —— 可能是几分钟前，也可能是几小时前。
                VStack(spacing: 12) {
                    Text("显示的是主 App 最近一次同步的车况")
                        .font(WT.Typo.caption)
                        .foregroundStyle(WT.Palette.onAccent.opacity(0.6))
                    FeatureItem(icon: "battery.100", label: "电量与续航")
                    FeatureItem(icon: "thermometer", label: "车内温度")
                    FeatureItem(icon: "lock.fill", label: "门锁与充电")
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $showMainApp) {
            Text("跳转到主 App（需已安装）")
        }
    }

    // MARK: - 数据

    /// 读主 App 写进 App Group 的快照。
    /// App Clip **不发请求**：它没有登录态、也没有令牌，所以「查车牌」这件事**做不到**；
    /// 能做的只有把主 App 最近一次同步的车况拿过来。拿不到就说拿不到。
    private func query() {
        // `hasData` 是快照自带的判据（`updatedAt == .distantPast` 表示从未同步过）：
        // 没有它就会把一份“全 0 的默认快照”当成真实车况显示出来。
        let s = SharedStore.read()
        snapshot = (s?.hasData ?? false) ? s : nil
        hasError = (snapshot == nil)
    }

    /// 车况卡：每一项都是快照里的真字段，没有的就不显示（不填默认值）。
    private func snapshotCard(_ s: VehicleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.agoText(s.updatedAt))
                    .font(WT.Typo.caption)
                    .foregroundStyle(WT.Palette.labelSecondary)
                Spacer(minLength: 8)
                if !plateInput.isEmpty {
                    // 车牌是你输入的：Clip 无从核验，所以就这么标着
                    Text("车牌（你输入）\(plateInput)")
                        .font(WT.Typo.caption)
                        .foregroundStyle(WT.Palette.labelSecondary)
                }
            }
            HStack(spacing: 18) {
                clipStat("电量", "\(s.soc)%")
                clipStat("续航", "\(s.rangeKm) km")
                clipStat("车内", s.cabinTemp.isEmpty ? "—" : s.cabinTemp)
            }
            HStack(spacing: 18) {
                clipStat("门锁", s.locked ? "已锁" : "未锁")
                clipStat("充电", s.charging ? (s.chargePower.map { String(format: "%.1f kW", $0) } ?? "充电中") : "未充电")
                clipStat("总里程", "\(s.mileageKm) km")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func clipStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(WT.Typo.caption)
                .foregroundStyle(WT.Palette.labelSecondary)
            Text(value)
                .font(WT.Typo.data(16))
                .foregroundStyle(WT.Palette.onAccent)
        }
    }

    /// 「主 App 同步于 x 前」。写清数据来源与龄期，比写「实时」诚实。
    private static func agoText(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 60 { return "主 App 刚刚同步" }
        if s < 3600 { return "主 App \(Int(s / 60)) 分钟前同步" }
        if s < 86400 { return "主 App \(Int(s / 3600)) 小时前同步" }
        return "主 App \(Int(s / 86400)) 天前同步"
    }
}

struct FeatureItem: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            // 注：AppClip target 不包含 Design/Theme.swift，用不了 SafeSymbol 兜底，
            // 所以这里只能用确实存在的 symbol 名（battery.100 / thermometer / lock.fill）
            Image(systemName: icon).font(WT.Typo.title3).foregroundStyle(WT.Palette.onAccent.opacity(0.8))
            Text(label)
                .font(WT.Typo.subheadline)
                .foregroundStyle(WT.Palette.onAccent.opacity(0.8))
        }
    }
}

// MARK: - AppClip 路由处理

enum CarClipRoute {
    static func handle(url: URL) -> AppClipEntranceView? {
        // 解析 carkeeper://plate/京A12345
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "plate",
              components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty == false else {
            return nil
        }
        // 通过 binding 传入车牌（需要包装为 StateObject 或 @State）
        return AppClipEntranceView()
    }
}

// MARK: - AppClipAppDelegate

// AppClip 是 application 类型 target，必须有一个入口点（否则链接期缺 _main）。
// @main 配合 UIApplicationDelegate 会合成 main()，无需额外的 App struct。
@main
class CarClipAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if let route = CarClipRoute.handle(url: url) {
            // 这里应该切换根视图，实际需要更复杂的处理
            print("AppClip opened for plate: \(url.absoluteString)")
        }
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }
}

// MARK: - 预览

struct AppClipEntrance_Previews: PreviewProvider {
    static var previews: some View {
        AppClipEntranceView()
    }
}
