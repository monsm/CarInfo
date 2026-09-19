import SwiftUI
import Photos

// 车辆档案 —— iOS 27 Liquid Glass：
// 车辆名片（渐变标牌 + VIN 复制条 + 三项时效徽章）+ 分组档案卡。

struct VehicleView: View {
    private let store = AppStore.shared

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize = ContentSizeCategory.med
    @State private var isRefreshing = false         // 下拉刷新涟漪标志
    // #NEW-105 维保相册
    @State private var maintenancePhotos: [String] = []  // Base64 图片
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: UIImage? = nil

    private var isLoading: Bool { store.carId.isEmpty }
    private var isEmpty:   Bool { !store.carId.isEmpty && store.car == nil }
    // #40 上次保养里程（从 UserDefaults 读取）
    private var lastServiceMiles: Int? {
        guard let mileageStr = UserDefaults.standard.string(forKey: "carkeeper_last_service_mileage") else { return nil }
        return Int(mileageStr)
    }

    var body: some View {
        Group {
            if isLoading {
                // 加载中：bootstrap 尚未完成或 carId 为空
                PageLoadingView("正在加载车辆档案…")
            } else if isEmpty {
                // 空状态：carId 已设置但未绑定车辆
                PageEmptyView("未绑定车辆",
                              subtitle: "请先在「我的」页面绑定车辆后重试",
                              icon: "car.fill")
            } else if let sum = VM.vehicleSummary(store.car) {
                // 正常内容：显示车辆档案
                ScrollView {
                    VStack(spacing: DynamicTypeScale.spacing(Theme.cardSpacing, dynamicTypeSize)) {
                        plateCard(sum)
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            CardBox(title: group.name) {
                                VStack(spacing: 0) {
                                    ForEach(Array(group.rows.enumerated()), id: \.offset) { idx, row in
                                        KVRow(k: row.k, v: row.v)
                                            .padding(.vertical, 8)
                                        if idx < group.rows.count - 1 { ListDivider() }
                                    }
                                }
                            }
                        }
                    }
                    .adaptivePagePadding(dynamicTypeSize)
                    .adaptiveSafeAreaBottom(8, dynamicTypeSize)
                }
                .scrollBounceBehavior(.basedOnSize)
                // #NEW-105 维保相册
                if !isLoading && !isEmpty {
                    maintenanceSection
                        .padding(.horizontal)
                }
            } else {
                // 兜底：car 数据解析失败
                PageErrorView("车辆数据解析失败，请重新进入页面") { _ in }
            }
        }
        .pageBackground(.accentColor)
        .navigationTitle("车辆档案")
            .navBarStyle()
            .accessibilityLabel(Text("车辆档案"))
            .accessibilityHint(Text("车牌、VIN、车型配置与保险保养信息"))
        .refreshable {
            isRefreshing = true
            try? await Task.sleep(nanoseconds: 500_000_000)
            Task { await store.fetchVehicleData() }
            isRefreshing = false
        }
        .glassRefreshRipple(isRefreshing: $isRefreshing)
        .onAppear { loadMaintenancePhotos() }
    }

    // MARK: 维保相册
    private var maintenanceSection: some View {
        CardBox(title: "维保照片", cornerRadius: Theme.Radius.card) {
            if maintenancePhotos.isEmpty {
                Button("添加维保照片") {
                    showPhotoPicker = true
                }
                .font(Theme.caption)
                .foregroundStyle(.accentColor)
                .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(maintenancePhotos.indices, id: \.self) { idx in
                            if let data = Data(base64Encoded: maintenancePhotos[idx]),
                               let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 100, height: 75)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        Button {
                            showPhotoPicker = true
                        } label: {
                            Image(systemName: "plus")
                                .font(Theme.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 100, height: 75)
                                .background(.thin, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }

    private func saveMaintenancePhotos() {
        if let data = try? JSONEncoder().encode(maintenancePhotos) {
            UserDefaults.standard.set(data, forKey: "carkeeper_maintenance_photos")
        }
    }

    private func loadMaintenancePhotos() {
        guard let data = UserDefaults.standard.data(forKey: "carkeeper_maintenance_photos"),
              let photos = try? JSONDecoder().decode([String].self, from: data) else { return }
        maintenancePhotos = photos
    }

    // MARK: 名片 — Apple Style Vehicle Card
    private func plateCard(_ sum: VehicleSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                // 车牌徽章
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 96, height: 58)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 10, y: 4)
                    VStack(spacing: 3) {
                        Text("新能源").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                        Text(sum.plate).font(.title.weight(.bold).design(.rounded)).foregroundStyle(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(sum.name.isEmpty ? "未绑定车辆" : sum.name)
                        .font(Theme.d4.weight(.bold))
                    Text(sum.model).font(Theme.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            // VIN 复制条
            vinBar(sum)
            // 三徽章行
            HStack(spacing: 10) {
                badgeRow("控车码", sum.pinText, cls: sum.pinCls)
                if let d = sum.insuranceDays {
                    badgeRow("保险", d < 0 ? "已到期" : "剩 \(d) 天", cls: d < 0 ? "bad" : "ok")
                }
                if let d = sum.serviceDays {
                    badgeRow("服务", d < 0 ? "已到期" : "剩 \(d) 天", cls: d < 0 ? "bad" : (d < 60 ? "warn" : "ok"))
                }
                // #16 维保提醒
                if let reminder = sum.serviceReminder {
                    Text(reminder)
                        .font(Theme.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.12), in: Capsule())
                }
                // #40 维保价格估算
                if let miles = sum.mileage,
                   let lastMiles = lastServiceMiles {
                    let upcomingMiles = miles - lastMiles
                    let interval = AppStore.defaultServiceInterval
                    let timesSince = upcomingMiles / interval
                    let nextServiceMiles = lastMiles + (timesSince + 1) * interval
                    let estPrice = timesSince >= 3 ? AppStore.majorServicePriceEstimate : AppStore.servicePriceEstimate
                    HStack {
                        Image(systemName: "wrench.and.screwdriver").font(Theme.caption).foregroundStyle(.accentColor)
                        Text("下次保养预计费用")
                            .font(Theme.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("约 ¥\(estPrice)")
                            .font(Theme.caption.weight(.semibold)).foregroundStyle(.accentColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thin, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeCompress()
        .glassHeroCard()
        .glassLongPressDeform()
    }

    private func vinBar(_ sum: VehicleSummary) -> some View {
        Button {
            if !sum.vin.isEmpty {
                UIPasteboard.general.string = sum.vin
                ToastManager.shared.show("VIN 已复制", icon: "doc.on.doc.fill")
            }
        } label: {
            HStack {
                Text("VIN \(sum.vin.isEmpty ? "--" : sum.vin)")
                    .font(Theme.monoLg)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "doc.on.doc.fill")
                    .font(Theme.caption)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(10)
            .background(.thin, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func badgeRow(_ k: String, _ v: String, cls: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(Theme.micro).foregroundStyle(.secondary)
            Text(v).font(Theme.caption.bold())
                .foregroundStyle(Theme.statusColor(cls) == Color.secondary ? Color.primary : Theme.statusColor(cls))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thin, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: 档案分组（数据不变）
    private struct Row { let k: String; let v: String }
    private struct Grp { let name: String; let rows: [Row] }

    private var groups: [Grp] {
        guard let c = store.car else { return [] }
        func s2(_ k: String) -> String? {
            let v = ciString(c, [k])
            return (v?.isEmpty ?? true) ? nil : v
        }
        func row(_ k: String, _ label: String, suffix: String = "") -> Row? {
            guard let v = s2(k) else { return nil }
            return Row(k: label, v: v + suffix)
        }
        var out: [Grp] = []
        let idRows = [row("CarId", "车辆 ID"), row("CarName", "车辆名称"), row("PlateNumber", "车牌号"),
                      row("IsNev", "能源类型", suffix: "")]
            .compactMap { $0 }
        if !idRows.isEmpty { out.append(Grp(name: "身份信息", rows: idRows)) }

        let basic = [row("ModelCode", "车型代码"), row("ConfName", "配置名称"), row("BrandCode", "品牌代码"),
                     row("SeriesCode", "车系代码"), row("CarType", "车辆类型"), row("Color", "车身颜色"),
                     row("EngineNo", "发动机编号"), row("TenantId", "租户标识")].compactMap { $0 }
        if !basic.isEmpty { out.append(Grp(name: "车型配置", rows: basic)) }

        let ins = [row("InsuranceEndDate", "保险到期"), row("InsuranceCompany", "保险公司"),
                   row("InsurancePhone", "保险电话"), row("RegisterTime", "注册时间"),
                   row("ProductTime", "生产时间")].compactMap { $0 }
        if !ins.isEmpty { out.append(Grp(name: "注册与保险", rows: ins)) }

        let svc = [row("MaintainSpaceMileage", "保养间隔", suffix: " km"),
                   row("LastMaintainMileage", "上次保养里程", suffix: " km"),
                   row("LastOnlineTime", "最后在线"), row("ActiveTime", "激活时间")].compactMap { $0 }
        if !svc.isEmpty { out.append(Grp(name: "服务与保养", rows: svc)) }

        let deviceInfo = [row("CurrentDeviceType", "设备类型")].compactMap { $0 }
        if !deviceInfo.isEmpty { out.append(Grp(name: "设备信息", rows: deviceInfo)) }

        let extra = [
            ("IsCaCar", "是否CA车辆", { let v = ciString(c, ["IsCaCar"]); return (v == "true" || v == "1") ? "是" : "否" }),
            ("BindedJD", "绑定京东", { let v = ciBool(c, ["BindedJD"]); return v ? "已绑定" : "未绑定" }),
            ("RealnameAuthStatus", "实名认证", { let v = ciString(c, ["RealnameAuthStatus"]); return (v == "AUTHED" || v == "authed") ? "已认证" : "未认证" })
        ].compactMap { k, label, fn in
            let v = fn()
            return Row(k: k, v: label + "：" + v)
        }
        if !extra.isEmpty { out.append(Grp(name: "扩展信息", rows: extra)) }

        // 车况报文 — 来自 tbox control 缓存（对齐小程序 vehicle.js）
        let ctl = store.caches["control"] as? [String: Any]
        var ctlRows: [Row] = []
        if let ctl, let pv = ciNumber(ctl, ["protocolVer"]) {
            ctlRows.append(Row(k: "协议版本", v: "V\(pv)"))
        }
        if let tl = ciString(ctl, ["ignitionTime"]), !tl.isEmpty { ctlRows.append(Row(k: "点火时间", v: tl)) }
        if let ll = ciString(ctl, ["lastLoginTime"]), !ll.isEmpty { ctlRows.append(Row(k: "报文登录时间", v: ll)) }
        if !ctlRows.isEmpty { out.append(Grp(name: "车况报文", rows: ctlRows)) }
        return out
    }
}

// MARK: - #NEW-105 图片选择器 Sheet
struct PhotoPickerSheet: View {
    @Binding var selectedImage: UIImage?
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("选择维保照片")
                    .font(Theme.h3)
                VStack(spacing: 12) {
                    Button {
                        selectedImage = nil
                        // 使用系统相机
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            let picker = UIImagePickerController()
                            picker.sourceType = .camera
                            picker.delegate = PhotoPickerDelegate { img in
                                selectedImage = img
                                onConfirm()
                                dismiss()
                            }
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let rootVC = windowScene.windows.first?.rootViewController {
                                rootVC.present(picker, animated: true)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "camera.fill").font(.title2)
                            Text("拍照")
                                .font(Theme.body)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        selectedImage = nil
                        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
                            let picker = UIImagePickerController()
                            picker.sourceType = .photoLibrary
                            picker.delegate = PhotoPickerDelegate { img in
                                selectedImage = img
                                onConfirm()
                                dismiss()
                            }
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let rootVC = windowScene.windows.first?.rootViewController {
                                rootVC.present(picker, animated: true)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "photo.on.rectangle").font(.title2)
                            Text("从相册选择")
                                .font(Theme.body)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("添加照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private class PhotoPickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let onPick: (UIImage?) -> Void
    init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        onPick(info[.originalImage] as? UIImage)
        picker.dismiss(animated: true)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        onPick(nil)
        picker.dismiss(animated: true)
    }
}
