import SwiftUI
import UIKit
import Photos

// =============================================================================
//  车辆档案 —— v4 信息架构
// =============================================================================
//  ① 身份区：车牌（等宽大字）+ 车辆名 + 车型 + 新能源标记
//     不再用彩色车牌方块 —— 车牌是文字，不是色块。
//  ② 时效区：控车码 / 保险 / 服务 三条读数（带语义色与图标）
//  ③ VIN：单独一行，点击复制（整车唯一的全局身份）
//  ④ 档案分组：身份 / 配置 / 注册保险 / 服务保养 / 设备 / 扩展 / 车况报文，
//     每行点一下即复制该字段 —— 报修、报案、投保时都要抄这些。
//  ⑤ 维保照片：本机相册，长按可删。
// =============================================================================

struct VehicleView: View {
    private let store = AppStore.shared

    @State private var maintenancePhotos: [String] = []   // Base64 图片
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: UIImage? = nil

    private var isLoading: Bool { store.carId.isEmpty }
    private var isEmpty:   Bool { !store.carId.isEmpty && store.car == nil }

    /// #40 上次保养里程（从 UserDefaults 读取）
    private var lastServiceMiles: Int? {
        guard let mileageStr = UserDefaults.standard.string(forKey: "carkeeper_last_service_mileage") else { return
 nil }
        return Int(mileageStr)
    }

    private var isNev: Bool {
        guard let v = ciString(store.car, ["IsNev"])?.lowercased() else { return false }
        return v == "1" || v == "true" || v == "yes" || v == "是"
    }

    /// 车辆数据解析失败时的重试入口
    private func reloadVehicle() {
        Task { await store.fetchVehicleData() }
    }

    var body: some View {
        Group {
            if isLoading {
                loadingState
            } else if isEmpty {
                DSPlaceholder(icon: "car",
                              title: "未绑定车辆",
                              message: "请先在「我的」页面绑定车辆后重试",
                              actionTitle: "重新加载") { reloadVehicle() }
            } else if let sum = VM.vehicleSummary(store.car) {
                content(sum)
            } else {
                DSPlaceholder(icon: "exclamationmark.triangle",
                              title: "档案解析失败",
                              message: "车辆数据已返回，但缺少可识别的字段",
                              actionTitle: "重新加载",
                              cls: "warn") { reloadVehicle() }
            }
        }                .background(KanseiPalette.background)
                .navigationTitle("车辆档案")
        .accessibilityLabel(Text("车辆档案"))
        .accessibilityHint(Text("车牌、VIN、车型配置与保险保养信息，点任意字段可复制"))
        .refreshable {
            await store.fetchVehicleData()
        }
        .onAppear { loadMaintenancePhotos() }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerSheet(selectedImage: $selectedPhoto) {
                guard let img = selectedPhoto,
                      let data = img.jpegData(compressionQuality: 0.6) else { return }
                maintenancePhotos.append(data.base64EncodedString())
                saveMaintenancePhotos()
                DSHaptic.result(true)
            }
        }
    }

    // MARK: - 内容

    private func content(_ sum: VehicleSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                identitySection(sum)
                archiveGroups
                photoSection
            }
            .padding(.top, DS.Space.sm)
            .padding(.bottom, DS.Space.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                ProgressView().controlSize(.small)
                Text("正在加载车辆档案…")
                    .font(DS.Typo.footnote)
                    .foregroundStyle(KanseiPalette.secondary)
            }
            DSSkeleton(height: 96)
            DSSkeleton(height: 132)
        }
        .padding(.horizontal, DS.Space.page)
        .padding(.top, DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - ① 身份区

    private func identitySection(_ sum: VehicleSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeader(title: "车辆")

            HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                Text(sum.plate.isEmpty ? "未绑定车牌" : sum.plate)
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .foregroundStyle(KanseiPalette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if isNev {
                    DSChip(text: "新能源", cls: "acc", icon: "bolt.fill")
                }
                Spacer(minLength: DS.Space.sm)
            }

            Text(sum.name.isEmpty ? "未绑定车辆" : sum.name)
                .font(DS.Typo.title2)
                .foregroundStyle(KanseiPalette.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.sm)

            if !sum.model.isEmpty {
                Text(sum.model)
                    .font(DS.Typo.subheadline)
                    .foregroundStyle(KanseiPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            // ② 时效读数：控车码 / 保险 / 服务
            let items = statItems(sum)
            if items.count > 1 {
                DSStatStrip(items: items)
                    .padding(.top, DS.Space.xl)
                    .overlay(alignment: .top) { DSDivider() }
                    .overlay(alignment: .bottom) { DSDivider() }
            }

            // ③ VIN：整车唯一身份，点一下复制
            vinRow(sum)
                .padding(.top, DS.Space.lg)

            if let reminder = sum.serviceReminder {
                DSNotice(kind: .warning, text: reminder)
                    .padding(.top, DS.Space.md)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// 控车码 / 保险 / 保养 三条时效读数（语义色由剩余天数决定）
    private func statItems(_ sum: VehicleSummary) -> [DSStatStrip.Item] {
        var items: [DSStatStrip.Item] = [
            .init("控车码", sum.pinText, cls: sum.pinCls, icon: "lock.fill")
        ]
        if let d = sum.insuranceDays {
            items.append(.init("保险", d < 0 ? "已到期" : "剩 \(d) 天",
                               cls: d < 0 ? "bad" : (d < 30 ? "warn" : "ok"),
                               icon: "shield.lefthalf.filled"))
        }
        if let d = sum.serviceDays {
            items.append(.init("保养", d < 0 ? "已到期" : "剩 \(d) 天",
                               cls: d < 0 ? "bad" : (d < 60 ? "warn" : "ok"),
                               icon: "wrench.and.screwdriver.fill"))
        }
        return items
    }

    private func vinRow(_ sum: VehicleSummary) -> some View {
        Button {
            copy(sum.vin, label: "VIN")
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(safeSymbol: "barcode", fallback: "number")
                    .font(.system(size: 15))
                    .foregroundStyle(KanseiPalette.secondary)
                Text("VIN")
                    .font(DS.Typo.footnote)
                    .foregroundStyle(KanseiPalette.secondary)
                Text(sum.vin.isEmpty ? "--" : sum.vin)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(KanseiPalette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: DS.Space.sm)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15))
                    .foregroundStyle(KanseiPalette.ambient)
            }
            .frame(minHeight: DS.Space.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSRowButtonStyle())
        .accessibilityLabel(Text("VIN \(sum.vin)，点击复制"))
    }

    // MARK: - ④ 档案分组

    private var archiveGroups: some View {
        let gs = groups
        return ForEach(Array(gs.enumerated()), id: \.element.name) { _, group in
            DSGroup(title: group.name,
                    trailing: "\(group.rows.count)",
                    footer: "点任意一行可复制该字段") {
                ForEach(Array(group.rows.enumerated()), id: \.element.k) { idx, r in
                    DSGroupRow(showsSeparator: idx < group.rows.count - 1) {
                        DSRow(title: r.k, value: r.v) { copy(r.v, label: r.k) }
                    }
                }
            }
        }
    }

    // MARK: - ⑤ 维保照片

    private var photoSection: some View {
        DSGroup(title: "维保照片",
                trailing: maintenancePhotos.isEmpty ? nil : "\(maintenancePhotos.count) 张",
                footer: "照片只保存在本机，不会上传服务器") {
            DSGroupRow(showsSeparator: false) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.sm) {
                        ForEach(Array(maintenancePhotos.enumerated()), id: \.offset) { idx, b64 in
                            if let data = Data(base64Encoded: b64), let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 104, height: 78)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deletePhoto(at: idx)
                                        } label: {
                                            Label("删除照片", systemImage: "trash")
                                        }
                                    }
                                    .accessibilityLabel(Text("维保照片 \(idx + 1)"))
                            }
                        }
                        Button {
                            showPhotoPicker = true
                        } label: {
                            VStack(spacing: DS.Space.xs) {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .light))
                                Text("添加")
                                    .font(DS.Typo.caption)
                            }
                            .foregroundStyle(KanseiPalette.secondary)
                            .frame(width: 104, height: 78)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                                .fill(KanseiPalette.fillSubtle))
                        }
                        .accessibilityLabel(Text("添加维保照片"))
                    }
                    .padding(.vertical, DS.Space.md)
                }
            }
        }
    }

    private func deletePhoto(at idx: Int) {
        guard maintenancePhotos.indices.contains(idx) else { return }
        withAnimation(DS.Motion.value) { _ = maintenancePhotos.remove(at: idx) }
        saveMaintenancePhotos()
        ToastManager.shared.show("照片已删除", icon: "trash")
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

    private func copy(_ value: String, label: String) {
        guard !value.isEmpty, value != "--" else { return }
        UIPasteboard.general.string = value
        DSHaptic.result(true)
        ToastManager.shared.show("\(label) 已复制", icon: "doc.on.doc.fill")
    }

    // MARK: - 档案数据（字段与来源不变）

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
                      row("Vin", "车架号")]
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

        var svc = [row("MaintainSpaceMileage", "保养间隔", suffix: " km"),
                   row("LastMaintainMileage", "上次保养里程", suffix: " km"),
                   row("LastOnlineTime", "最后在线"), row("ActiveTime", "激活时间")].compactMap { $0 }
        // #40 下次保养里程与预计费用（本地里程推算，不新增数据源）
        if let miles = VM.vehicleSummary(store.car)?.mileage, let lastMiles = lastServiceMiles {
            let interval = AppStore.defaultServiceInterval
            let timesSince = max(0, (miles - lastMiles) / max(1, interval))
            let nextMiles = lastMiles + (timesSince + 1) * interval
            let estPrice = timesSince >= 3 ? AppStore.majorServicePriceEstimate : AppStore.servicePriceEstimate
            svc.append(Row(k: "下次保养里程", v: "\(nextMiles) km"))
            svc.append(Row(k: "下次保养预计费用", v: "约 ¥\(estPrice)"))
        }
        if !svc.isEmpty { out.append(Grp(name: "服务与保养", rows: svc)) }

        let deviceInfo = [row("CurrentDeviceType", "设备类型")].compactMap { $0 }
        if !deviceInfo.isEmpty { out.append(Grp(name: "设备信息", rows: deviceInfo)) }

        var extra: [Row] = []
        if let v = ciString(c, ["IsCaCar"]) {
            extra.append(Row(k: "是否 CA 车辆", v: (v == "true" || v == "1") ? "是" : "否"))
        }
        if let v = ciBool(c, ["BindedJD"]) {
            extra.append(Row(k: "绑定京东账号", v: v ? "已绑定" : "未绑定"))
        }
        if let v = ciString(c, ["RealnameAuthStatus"]), !v.isEmpty {
            let authed = v.lowercased() == "authed" || v == "已认证"
            extra.append(Row(k: "实名认证", v: authed ? "已认证" : "未认证"))
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
    /// UIImagePickerController.delegate 是 weak 引用，必须由视图强引用持有 delegate，
    /// 否则它会在 present 之前就被释放，选中的照片永远回不来。
    @State private var pickerDelegate: PhotoPickerDelegate? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    DSGroup(title: "来源") {
                        DSGroupRow {
                            DSRow(icon: "camera.fill", title: "拍照") { present(.camera, "拍照") }
                        }
                        DSGroupRow(showsSeparator: false) {
                            DSRow(icon: "photo.on.rectangle", title: "从相册选择") { present(.photoLibrary, "相册") }
                        }
                    }
                    Text("照片会以压缩后的形式保存在本机，用于维修与保养记录。")
                        .font(DS.Typo.footnote)
                        .foregroundStyle(KanseiPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, DS.Space.sm)
            }
            .background(KanseiPalette.background)
            .navigationTitle("添加照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func present(_ source: UIImagePickerController.SourceType, _ label: String) {
        selectedImage = nil
        guard UIImagePickerController.isSourceTypeAvailable(source) else {
            ToastManager.shared.show("此设备不支持\(label)", icon: "exclamationmark.triangle")
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = source
        let delegate = PhotoPickerDelegate { img in
            selectedImage = img
            onConfirm()
            dismiss()
        }
        pickerDelegate = delegate
        picker.delegate = delegate
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        rootVC.present(picker, animated: true)
    }
}

private class PhotoPickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let onPick: (UIImage?) -> Void
    init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info:
 [UIImagePickerController.InfoKey : Any]) {
        onPick(info[.originalImage] as? UIImage)
        picker.dismiss(animated: true)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        onPick(nil)
        picker.dismiss(animated: true)
    }
}
