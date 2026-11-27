import SwiftUI
import UIKit
import Photos


struct VehicleView: View {
    private let store = AppStore.shared
    @EnvironmentObject private var nav: NavState

    @State private var maintenancePhotos: [String] = []
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: UIImage? = nil
    @State private var tab: HomeSub = .profile

    private var isLoading: Bool { store.carId.isEmpty }
    private var isEmpty:   Bool { !store.carId.isEmpty && store.car == nil }


    private var isNev: Bool {
        guard let v = ciString(store.car, ["IsNev"])?.lowercased() else { return false }
        return v == "1" || v == "true" || v == "yes" || v == "是"
    }

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
        .onAppear {
            loadMaintenancePhotos()
            consumeHint()
        }
        .onChange(of: nav.homeSub) { _, _ in consumeHint() }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerSheet(selectedImage: $selectedPhoto) {
                guard let img = selectedPhoto,
                      let data = img.jpegData(compressionQuality: 0.6) else { return }
                maintenancePhotos.append(data.base64EncodedString())
                saveMaintenancePhotos()
                TokensHaptic.result(true)
            }
        }
    }


    private func content() -> some View {
        StackPageView(accent: HomeMode.vehicle.accent, label: "车辆", cards: cards)
    }

    @MainActor
    private var cards: [StackCard] {
        var out = HomeMode.vehicle.headCards
        out.append(StackCard(id: "tabs", content: AnyView(
            DSSegmentPicker(options: HomeSub.vehicleTabs.map { (value: $0, title: $0.title) },
                            selection: $tab,
                            label: "段落"))))
        switch tab {
        case .health:
            out.append(StackCard(id: "health", title: "体检",
                                 at: store.cacheTime("check"),
                                 content: AnyView(HealthDataView())))
        case .service:
            out.append(StackCard(id: "service", title: "保养",
                                 content: AnyView(MaintenanceMoneyView())))
        default:
            out.append(contentsOf: sectionCards)
        }
        return out
    }

    private func consumeHint() {
        guard let hint = nav.homeSub, HomeSub.vehicleTabs.contains(hint) else { return }
        tab = hint
        nav.homeSub = nil
    }

    @MainActor
    private var sectionCards: [StackCard] {
        guard let sum = VM.vehicleSummary(store.car, store.controlCache) else {
            return [StackCard(id: "empty", content: AnyView(
                GlassCardEmpty(text: "车辆数据不完整", icon: "exclamationmark.triangle")))]
        }
        var out: [StackCard] = [
            StackCard(id: "identity", title: "身份",
                      value: sum.plate, cls: "ok",
                      content: AnyView(identitySection(sum))),
        ]
        out.append(contentsOf: archiveGroups)
        out += [
            StackCard(id: "photos", title: "维保照片", content: AnyView(photoSection)),
            StackCard(id: "journal", title: "里程记账", content: AnyView(MileageJournalSection()))
        ]
        return out
    }

    private var loadingState: some View {
        DSLoadingSkeleton(message: "加载中…", heights: [96, 132])
            .padding(.horizontal, TokensSpacing.page)
            .padding(.top, TokensSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
    }


    private func identitySection(_ sum: VehicleSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                Text(sum.plate.isEmpty ? "未绑定车牌" : sum.plate)
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
                    .padding(.top, TokensSpacing.xxs)
            }

            let items = statItems(sum)
            if items.count > 1 {
                DSStatStrip(items: items)
                    .padding(.top, TokensSpacing.xl)
                    .overlay(alignment: .top) { DSDivider() }
                    .overlay(alignment: .bottom) { DSDivider() }
            }

            vinRow(sum)
                .padding(.top, TokensSpacing.lg)

            if let reminder = sum.serviceReminder {
                DSNotice(kind: .warning, text: reminder)
                    .padding(.top, TokensSpacing.md)
            }
        }
        .accessibilityElement(children: .contain)
    }

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


    private var archiveGroups: [StackCard] {
        let gs = groups
        guard !gs.isEmpty else { return [] }
        return gs.enumerated().map { idx, group in
            StackCard(
                id: "archive-\(idx)",
                title: group.name,
                value: "\(group.rows.count) 项",
                at: store.cacheTime("control"),
                content: AnyView(groupCard(group))
            )
        }
    }

    private func groupCard(_ group: Grp) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(group.rows.enumerated()), id: \.element.k) { idx, r in
                DSGroupRow(showsSeparator: idx < group.rows.count - 1) {
                    DSRow(title: r.k, value: r.v) { copy(r.v, label: r.k) }
                }
            }
            Text("点一行可复制")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
                .padding(.top, TokensSpacing.sm)
        }
    }


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


    private struct Row { let k: String; let v: String }
    private struct Grp { let name: String; let rows: [Row] }

    private var groups: [Grp] {
        guard let c = store.car else { return [] }
        func s2(_ k: String) -> String? {
            let v = ciString(c, [k])
            return (v?.isEmpty ?? true) ? nil : v
        }
        func row(_ k: String, _ label: String, suffix: String = "") -> Row? {
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

        var ins: [Row] = [Row(k: "保险到期",
                             v: VM.antiSentinel(s2("InsuranceEndDate")) ?? "未登记（小程序里没有填）")]
        ins += [row("InsuranceCompany", "保险公司"), row("InsurancePhone", "保险电话"),
                row("RegisterTime", "注册时间"), row("ProductTime", "生产时间")].compactMap { $0 }
        out.append(Grp(name: "注册与保险", rows: ins))

        var svc = [row("MaintainSpaceMileage", "保养间隔", suffix: " km"),
                   row("LastMaintainMileage", "上次保养里程", suffix: " km"),
                   row("LastOnlineTime", "最后在线"), row("ActiveTime", "激活时间")].compactMap { $0 }
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

struct PhotoPickerSheet: View {
    @Binding var selectedImage: UIImage?
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
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
