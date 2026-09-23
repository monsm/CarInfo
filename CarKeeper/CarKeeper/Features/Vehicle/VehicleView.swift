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

    // 【已删】private var lastServiceMiles: Int?
    // 它是 `UserDefaults.string(forKey: "carkeeper_last_service_mileage")`，
    // 而那个键是用 `set(Int, forKey:)` 写的 —— 类型不符，**永远返回 nil**，
    // 所以「下次保养里程」那一节从来没被显示过。保养计划现在统一走 store.maintenancePlan。

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
                              message: "请先绑定车辆",
                              actionTitle: "重新加载") { reloadVehicle() }
            } else if VM.vehicleSummary(store.car, store.controlCache) != nil {
                content()
            } else {
                DSPlaceholder(icon: "exclamationmark.triangle",
                              title: "档案解析失败",
                              message: "车辆数据不完整",
                              actionTitle: "重新加载",
                              cls: "warn") { reloadVehicle() }
            }
        }
                .dsPageTitle("车辆档案")
        .accessibilityLabel(Text("车辆档案"))
        .accessibilityHint(Text("点一行可复制"))
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
                TokensHaptic.result(true)
            }
            .dsSheetCanvas()
        }
    }

    // MARK: - 内容

    private func content() -> some View {
        StackPageView(accent: HomeMode.vehicle.accent, label: "车辆档案",
                      cards: sectionCards)
    }

    /// 档案这一段的卡（**不含巨字头** —— 头归 `VehicleHubView` 那一叠）。
    ///
    /// 只有这一处决定「档案分几张卡」：hub 与自己两条路径都调它。
    /// 拆卡的分法是按**问题**分的 —— 这辆车是谁（身份）、它有什么毛病（提示）、
    /// 它经历过什么（档案/照片/记账），而不是按控件类型。
    @MainActor
    var sectionCards: [StackCard] {
        guard let sum = VM.vehicleSummary(store.car, store.controlCache) else {
            return [StackCard(id: "empty", content: AnyView(
                GlassCardEmpty(text: "车辆数据不完整", icon: "exclamationmark.triangle")))]
        }
        return [
            StackCard(id: "identity", title: "身份",
                      value: sum.plate, cls: "ok",
                      content: AnyView(identitySection(sum))),
            // 用车提示：由这辆车的读数推出来的提醒（原 `车辆提示` 页）
            StackCard(id: "tips", title: "用车提示", content: AnyView(VehicleTipsSection())),
            // 档案里的里程与车架号来自车控报文（`control`）—— 时间戳跟的是那个源，
            // 不是「这一页什么时候画出来的」。
            StackCard(id: "archive", title: "档案",
                      at: store.cacheTime("control"),
                      content: AnyView(archiveGroups)),
            StackCard(id: "photos", title: "维保照片", content: AnyView(photoSection)),
            // 里程记账：花在车上的每一笔（原「我的」里的独立页 + sheet）
            StackCard(id: "journal", title: "里程记账", content: AnyView(MileageJournalSection()))
        ]
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.md) {
            HStack(spacing: TokensSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("加载中…")
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
            }
            DSSkeleton(height: 96)
            DSSkeleton(height: 132)
        }
        .padding(.horizontal, TokensSpacing.page)
        .padding(.top, TokensSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - ① 身份区

    private func identitySection(_ sum: VehicleSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeader(title: "车辆")

            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                Text(sum.plate.isEmpty ? "未绑定车牌" : sum.plate)
                    // 车牌是**全屏最大的字**，也是这一页的标题：走 metric（等宽数字家族的定尺字）
                    .font(TokensTypo.metric(34).weight(.semibold))
                    .foregroundStyle(TokensPalette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if isNev {
                    DSChip(text: "新能源", cls: "acc", icon: "bolt.fill")
                }
                Spacer(minLength: TokensSpacing.sm)
            }

            Text(sum.name.isEmpty ? "未绑定车辆" : sum.name)
                .font(TokensTypo.title2)
                .foregroundStyle(TokensPalette.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, TokensSpacing.sm)

            if !sum.model.isEmpty {
                Text(sum.model)
                    .font(TokensTypo.subheadline)
                    .foregroundStyle(TokensPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            // ② 时效读数：控车码 / 保险 / 服务
            let items = statItems(sum)
            if items.count > 1 {
                DSStatStrip(items: items)
                    .padding(.top, TokensSpacing.xl)
                    .overlay(alignment: .top) { DSDivider() }
                    .overlay(alignment: .bottom) { DSDivider() }
            }

            // ③ VIN：整车唯一身份，点一下复制
            vinRow(sum)
                .padding(.top, TokensSpacing.lg)

            if let reminder = sum.serviceReminder {
                DSNotice(kind: .warning, text: reminder)
                    .padding(.top, TokensSpacing.md)
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
            HStack(spacing: TokensSpacing.sm) {
                Image(safeSymbol: "barcode", fallback: "number")
                    .font(TokensTypo.fixed(15))
                    .foregroundStyle(TokensPalette.secondary)
                Text("VIN")
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                Text(sum.vin.isEmpty ? "--" : sum.vin)
                    .font(TokensTypo.dataSmall)
                    .foregroundStyle(TokensPalette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: TokensSpacing.sm)
                Image(safeSymbol: "doc.on.doc", fallback: "doc.on.doc")
                    .font(TokensTypo.fixed(15))
                    .foregroundStyle(TokensPalette.ambient)
            }
            .frame(minHeight: TokensSpacing.row)
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
                    footer: "点一行可复制") {
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
                footer: "只存本机") {
            DSGroupRow(showsSeparator: false) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TokensSpacing.sm) {
                        ForEach(Array(maintenancePhotos.enumerated()), id: \.offset) { idx, b64 in
                            if let data = Data(base64Encoded: b64), let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 104, height: 78)
                                    .clipShape(RoundedRectangle(cornerRadius: TokensRadius.small,
                                                                 style: .continuous))
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
                            VStack(spacing: TokensSpacing.xs) {
                                Image(safeSymbol: "plus", fallback: "plus")
                                    .font(TokensTypo.fixed(20, weight: .light))
                                Text("添加")
                                    .font(TokensTypo.caption)
                            }
                            .foregroundStyle(TokensPalette.secondary)
                            .frame(width: 104, height: 78)
                            .background(RoundedRectangle(cornerRadius: TokensRadius.small, style: .continuous)
                                .fill(TokensPalette.fillSubtle))
                        }
                        .accessibilityLabel(Text("添加维保照片"))
                    }
                    .padding(.vertical, TokensSpacing.md)
                }
            }
        }
    }

    private func deletePhoto(at idx: Int) {
        guard maintenancePhotos.indices.contains(idx) else { return }
        withAnimation(TokensMotion.value) { _ = maintenancePhotos.remove(at: idx) }
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
        TokensHaptic.result(true)
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
            // 哨兵值（"0000-00-00" / "0000-00-00\n\t\t00:00:00"）是「没有登记」，不是数据。
            // 不加这道守卫，档案表会写出「激活时间 0000-00-00」这种零年零月。
            guard let v = VM.antiSentinel(s2(k)) else { return nil }
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

        // 保险到期单独摆一行：哨兵值意味着「小程序里没登记过」，这本身就是一条信息，
        // 不能用“整行消失”掩盖（而参考实现（C#）是干脆不显示）。
        var ins: [Row] = [Row(k: "保险到期",
                             v: VM.antiSentinel(s2("InsuranceEndDate")) ?? "未登记（小程序里没有填）")]
        ins += [row("InsuranceCompany", "保险公司"), row("InsurancePhone", "保险电话"),
                row("RegisterTime", "注册时间"), row("ProductTime", "生产时间")].compactMap { $0 }
        out.append(Grp(name: "注册与保险", rows: ins))

        var svc = [row("MaintainSpaceMileage", "保养间隔", suffix: " km"),
                   row("LastMaintainMileage", "上次保养里程", suffix: " km"),
                   row("LastOnlineTime", "最后在线"), row("ActiveTime", "激活时间")].compactMap { $0 }
        // #40 下次保养里程与预计费用。
        // 数据源统一：`store.maintenancePlan`（间隔与上次保养来自服务端
        // maintainSpaceMileage / lastMaintainMileage，缺字段才退回本机记录）。
        if let plan = store.maintenancePlan {
            let timesSince = max(0, (plan.current - plan.last) / max(1, plan.interval))
            let estPrice = timesSince >= 3 ? AppStore.majorServicePriceEstimate : AppStore.servicePriceEstimate
            let gap = plan.remaining >= 0 ? "再跑 \(plan.remaining) km" : "已超 \(abs(plan.remaining)) km"
            svc.append(Row(k: "下次保养里程", v: "\(plan.next) km（\(gap)）"))
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
        if let ll = ciString(ctl, ["lastLoginTime"]), !ll.isEmpty { ctlRows.append(Row(k: "登录时间", v: ll)) }
        if !ctlRows.isEmpty { out.append(Grp(name: "车况", rows: ctlRows)) }
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
                VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                    DSGroup(title: "来源") {
                        DSGroupRow {
                            DSRow(icon: "camera.fill", title: "拍照") { present(.camera, "拍照") }
                        }
                        DSGroupRow(showsSeparator: false) {
                            DSRow(icon: "photo.on.rectangle", title: "从相册选择") { present(.photoLibrary, "相册") }
                        }
                    }
                    Text("压缩后只存本机")
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, TokensSpacing.sm)
            }
            // v5：不自己铺底 —— 画布与光在 App 根部只画一次，这里再铺一层
            //       就是一块盖住光的墙（原生主题下与原来逐像素相同：根画布就是同一个颜色）。
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
