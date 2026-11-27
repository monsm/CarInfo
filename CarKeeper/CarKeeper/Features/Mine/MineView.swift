import SwiftUI
import PhotosUI

struct MineView: View {
    private let store = AppStore.shared
    @State private var logoutConfirm = false
    @EnvironmentObject var nav: NavState
    @State private var tab: HomeSub = .settings
    @ObservedObject private var wallpaper = WallpaperService.shared
    @State private var wallpaperPickItem: PhotosPickerItem?

    @MainActor
    private var cards: [StackCard] {
        var out = HomeMode.mine.headCards
        out.append(StackCard(id: "tabs", content: AnyView(
            DSSegmentPicker(options: HomeSub.mineTabs.map { (value: $0, title: $0.title) },
                            selection: $tab,
                            label: "段落"))))
        switch tab {
        case .emergency:
            out.append(StackCard(id: "emergency", title: "应急",
                                 content: AnyView(EmergencyPanel())))
        case .dev:
            out.append(StackCard(id: "dev", title: "诊断", content: AnyView(DevView())))
        default:
            out.append(contentsOf: sectionCards)
        }
        return out
    }

    private func consumeHint() {
        guard let hint = nav.homeSub, HomeSub.mineTabs.contains(hint) else { return }
        tab = hint
        nav.homeSub = nil
    }

    @MainActor
    private var sectionCards: [StackCard] {
        var out: [StackCard] = [
            StackCard(id: "profile", title: "账号", content: AnyView(profileCard))
        ]
        out.append(StackCard(id: "settings", title: "设置", content: AnyView(settingsGroups)))
        out.append(StackCard(id: "about", title: "关于", content: AnyView(aboutCard)))
        return out
    }

    var body: some View {
        StackPageView(accent: HomeMode.mine.accent, label: "车与账号", cards: cards)
        .dsPageTitle("车与账号")
            .accessibilityLabel(Text("车与账号"))
            .accessibilityHint(Text("账号、设置、应急、诊断、关于"))
        .onAppear { consumeHint() }
        .onChange(of: nav.homeSub) { _, _ in consumeHint() }
        .refreshable {
            await store.fetchVehicleData()
        }
        .alert("退出登录", isPresented: $logoutConfirm) {
            Button("退出", role: .destructive) { logout() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("退出后需要重新登录，本机记录不会删除。")
        }
    }

    private var profileCard: some View {
        let um = VM.userModel(store.user)
        return DSCard(padding: TokensSpacing.md, radius: TokensRadius.large) {
            VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                HStack(spacing: TokensSpacing.lg) {
                    Text(um?.avatar ?? "主")
                        .font(TokensTypo.title2.weight(.semibold))
                        .foregroundStyle(TokensPalette.secondary)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(TokensPalette.fillSubtle))

                    VStack(alignment: .leading, spacing: TokensSpacing.xs) {
                        Text(um?.name ?? "车主")
                            .font(TokensTypo.title2)
                            .foregroundStyle(TokensPalette.primary)
                        Text(um?.mobile ?? "--")
                            .font(TokensTypo.footnote)
                            .foregroundStyle(TokensPalette.secondary)
                        if um?.authed == true {
                            Text("已实名认证")
                                .font(TokensTypo.footnote)
                                .foregroundStyle(TokensPalette.success)
                        }
                    }
                    Spacer(minLength: TokensSpacing.sm)
                    Image(safeSymbol: "chevron.right", fallback: "chevron.right")
                        .font(TokensTypo.fixed(13, weight: .semibold))
                        .foregroundStyle(TokensPalette.tertiary)
                }

                DSDivider()

                HStack(spacing: TokensSpacing.xl) {
                    profileStat(label: "车辆", value: "\(store.cars.count)", unit: "辆")
                    if let gt = um?.gender, !gt.isEmpty {
                        profileStat(label: "性别", value: gt, unit: nil)
                    }
                    if let bt = um?.birthday, !bt.isEmpty {
                        profileStat(label: "生日", value: bt, unit: nil)
                    }
                    Spacer(minLength: 0)
                }

                if let lt = um?.lastLoginTime, !lt.isEmpty {
                    HStack(spacing: TokensSpacing.xs) {
                        Image(safeSymbol: "clock", fallback: "clock")
                            .font(TokensTypo.fixed(11))
                        Text("上次登录 \(lt)")
                    }
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
                }
            }
        }
    }

    private func profileStat(label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.xxs) {
            Text(label)
                .font(TokensTypo.caption2.weight(.medium))
                .foregroundStyle(TokensPalette.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.xxs) {
                Text(value)
                    .font(TokensTypo.metric(20))
                    .foregroundStyle(TokensPalette.primary)
                if let unit {
                    Text(unit)
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }


    private var settingsGroups: some View {
        VStack(spacing: TokensSpacing.xl) {

            DSGroup(title: "应用") {
                customRow { wallpaperRow }
                customRow(last: true) { logoutRow }
            }


            PrivacySection()
        }
    }



    private func customRow<V: View>(last: Bool = false,
                                    @ViewBuilder _ content: @escaping () -> V) -> some View {
        DSGroupRow(showsSeparator: !last) { content() }
    }


    private var wallpaperRow: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            HStack {
                Text("背景图")
                    .font(TokensTypo.body)
                    .foregroundStyle(TokensPalette.primary)
                Spacer(minLength: TokensSpacing.sm)
                Text(wallpaper.source.title)
                    .font(TokensTypo.body)
                    .foregroundStyle(TokensPalette.secondary)
            }
            .frame(minHeight: TokensSpacing.row)
            DSSegmentPicker(options: WallpaperSource.allCases.map { (value: $0, title: $0.segmentTitle) },
                            selection: Binding(get: { wallpaper.source },
                                               set: { pickSource($0) }),
                            label: "背景图来源")

            Group {
                if let img = wallpaper.image {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120, alignment: .top)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .allowsHitTesting(false)
                        .clipShape(RoundedRectangle(cornerRadius: TokensRadius.medium))
                } else {
                    Rectangle()
                        .fill(TokensPalette.fillSubtle)
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: TokensRadius.medium))
                        .overlay {
                            Text("没有选图（铺画布底色）")
                                .font(TokensTypo.caption)
                                .foregroundStyle(TokensPalette.tertiary)
                        }
                }
            }

            HStack(spacing: TokensSpacing.sm) {
                if wallpaper.source == .photo {
                    PhotosPicker(selection: $wallpaperPickItem, matching: .images) {
                        Text("选一张")
                    }
                    .buttonStyle(.plain)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.accent)
                    .frame(minHeight: TokensSpacing.row)
                    .contentShape(Rectangle())
                }

                Spacer(minLength: 0)

                if wallpaper.failed {
                    Button("重试") {
                        TokensHaptic.tap()
                        wallpaper.reload()
                    }
                    .buttonStyle(.plain)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.accent)
                    .frame(minHeight: TokensSpacing.row)
                    .contentShape(Rectangle())
                }

                if wallpaper.image != nil {
                    Button("不铺") {
                        TokensHaptic.tap()
                        wallpaper.clear()
                    }
                    .buttonStyle(.plain)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                    .frame(minHeight: TokensSpacing.row)
                    .contentShape(Rectangle())
                }
            }

            Text(wallpaper.source.note)
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
            if wallpaper.source == .photo {
                Text("选偏亮、留白多的图（深色模式下玻璃卡压在暗图上读不清）")
                    .font(TokensTypo.caption2)
                    .foregroundStyle(TokensPalette.tertiary)
            }
            if wallpaper.failed {
                Text("取图没成功，先铺画布底色")
                    .font(TokensTypo.caption2)
                    .foregroundStyle(TokensPalette.warning)
            }
            if !wallpaper.credit.isEmpty {
                Text(wallpaper.credit)
                    .font(TokensTypo.caption2)
                    .foregroundStyle(TokensPalette.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, TokensSpacing.sm)
        .padding(.vertical, TokensSpacing.sm)
        .onChange(of: wallpaperPickItem) { _, item in
            Task {
                guard let item else { return }
                if let data = try await item.loadTransferable(type: Data.self) {
                    wallpaper.setPhoto(data)
                    TokensHaptic.select()
                }
                wallpaperPickItem = nil
            }
        }
    }

    private func pickSource(_ s: WallpaperSource) {
        TokensHaptic.select()
        if s == wallpaper.source { wallpaper.reload() } else { wallpaper.use(s) }
    }

    private var logoutRow: some View {
        Button {
            logoutConfirm = true
        } label: {
            HStack(spacing: TokensSpacing.sm) {
                Image(safeSymbol: "rectangle.portrait.and.arrow.right", fallback: "rectangle.portrait.and.arrow.right")
                    .font(TokensTypo.fixed(15))
                Text("退出登录").font(TokensTypo.headline)
                Spacer()
            }
            .foregroundStyle(TokensPalette.error)
            .padding(.vertical, TokensSpacing.snug)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var aboutCard: some View {
        DSGroup(title: "关于",
                footer: "车况数据实时来自车辆车联网服务，仅用于本人车辆管理。") {
            DSGroupRow(showsSeparator: false) {
                DSKeyValueRow(key: "版本", value: AppInfo.versionLine, mono: false)
            }
        }
    }

    private func logout() {
        store.logout()
    }
}
