import SwiftUI

// 我的：用户卡 + 车辆卡 + 常用入口 + 退出登录
struct MineView: View {
    private let store = AppStore.shared
    @State private var showAboutAlert = false
    // 检查更新状态
    @State private var updateBusy = false
    @State private var updateMsg: String? = nil
    @State private var downloadPct: Double = 0
    @State private var showDownload = false
    @State private var showToken = false
    @State private var tokenDraft: String = ""
    @State private var downloadFile: URL? = nil
    @State private var shareItems: [Any] = []
    @State private var shareSheetFlag = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.cardSpacing) {
                profileCard
                if let car = store.car { carCard(car) }
                tilesCard
                updateCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
        }
        .scrollBounceBehavior(.basedOnSize)
        .pageBackground(.accentColor)
        .navigationTitle("我的").navBarStyle()
        .alert("关于 长安车管家", isPresented: $showAboutAlert) {
            Button("关闭", role: .cancel) { }
        } message: {
            Text(aboutText)
        }
        .alert("GitHub Token", isPresented: $showToken) {
            TextField("粘贴 Token", text: $tokenDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
            Button("保存") {
                UpdateService.githubToken = tokenDraft
                updateMsg = tokenDraft.isEmpty ? "已清空 Token" : "Token 已保存，点「检查更新」获取最新构建"
            }
            Button("取消", role: .cancel) { }
        }
        .sheet(isPresented: $shareSheetFlag) { ShareSheet(items: shareItems) }
    }

    // MARK: 身份卡 — Apple Profile Card
    private var profileCard: some View {
        let um = VM.userModel(store.user)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                // 头像
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 68, height: 68)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 12, y: 5)
                    Text(um?.avatar ?? "主")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(um?.name ?? "车主").font(.system(size: 21, weight: .bold))
                    HStack(spacing: 10) {
                        Text(um?.mobile ?? "--")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if um?.authed == true {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.green)
                                Text("已实名")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.green)
                            }
                        }
                    }
                }
                Spacer()
            }
            // 分割线
            Divider().opacity(0.4)
            // 底部统计
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "car.fill").font(.system(size: 14)).foregroundStyle(Color.accentColor)
                    Text(String(store.cars?.count ?? 0) + " 辆车")
                        .font(.system(size: 14, weight: .medium))
                }
                Spacer()
                if let gt = um?.gender, !gt.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: gt == "男" ? "person.fill" : "person.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(gt).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 12) {
                if let bt = um.birthday, !bt.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(bt).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                if let lt = um.lastLoginTime, !lt.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(lt).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .glassHeroCard()
    }

    // MARK: 车辆卡
    private func carCard(_ car: [String: Any]) -> some View {
        let sum = VM.vehicleSummary(car)
        return Button {
            NotificationCenter.default.post(name: .navToVehicle, object: nil)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "car.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .background(.thin, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(sum?.name ?? "未绑定车辆").font(.system(size: 17, weight: .semibold))
                    Text(sum?.plate ?? "暂无车牌").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                if let d = sum?.insuranceDays {
                    Pill(text: d < 0 ? "保险到期" : "保险剩 \(d) 天",
                         cls: d < 0 ? "bad" : (d <= 30 ? "warn" : "ok"), dot: false)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .glassCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 常用磁贴
    private var tilesCard: some View {
        CardBox(title: "常用功能") {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    tile("shield.lefthalf.filled", "健康报告", tint: .green) { post(.navToHealth) }
                    tile("battery.100", "电池充电", tint: .green) { post(.navToBattery) }
                }
                HStack(spacing: 10) {
                    tile("chart.bar.xaxis", "全量数据", tint: .indigo) { post(.navToData) }
                    tile("doc.text.fill", "车辆档案", tint: .orange) { post(.navToVehicle) }
                }
                HStack(spacing: 10) {
                    tile("bubble.left.fill", "消息中心", tint: .blue) { post(.navToMessages) }
                    tile("wrench.adjustable", "开发者工具", tint: .purple) { post(.navToDev) }
                }
            }
        }
    }

    // MARK: 检查更新
    private var updateCard: some View {
        CardBox(title: "检查更新", side: nil) {
            VStack(alignment: .leading, spacing: 10) {
                Text("下载最新 GitHub 构建的 ipa，分享后用自签工具安装")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                if showDownload {
                    VStack(spacing: 6) {
                        ProgressView(value: downloadPct)
                            .tint(.accentColor)
                        Text("正在下载… \(Int(downloadPct * 100))%")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                if let m = updateMsg {
                    Text(m).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) { updateButtons() }
            }
        }
    }

    // 常用入口大尺寸磁贴
    private func tile(_ symbol: String, _ label: String, tint: Color,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.10))
                        .frame(width: 48, height: 48)
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.thin, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    @ViewBuilder
    private func updateButtons() -> some View {
        HStack(spacing: 10) {
            mainUpdateButton
            if downloadFile != nil { shareButton }
            tokenButton
        }
    }

    private var mainUpdateButton: some View {
        Button {
            checkUpdate()
        } label: {
            HStack(spacing: 6) {
                if updateBusy { ProgressView().controlSize(.mini).tint(.white) }
                Text(updateBusy ? "检查中…" : "检查更新")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(Color.accentColor))
        }
        .buttonStyle(.plain)
        .disabled(updateBusy)
    }

    private var shareButton: some View {
        Button {
            shareItems = [downloadFile as Any]
            shareSheetFlag = true
        } label: {
            Label("分享安装包", systemImage: "square.and.arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.thin, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var tokenButton: some View {
        Button {
            tokenDraft = UpdateService.githubToken
            showToken = true
        } label: {
            Label("Token", systemImage: "key.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.thin, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }

    private var aboutText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "长安车管家 v\(v) (\(b))\n网络通道：直连（iOS 原生）\n\n车况数据实时来自车辆车联网服务，仅用于本人车辆管理。"
    }

    private func logout() {
        store.logout()
        // RootView 监听 isLoggedIn 变化后自动切回登录页
    }

    private func checkUpdate() {
        updateBusy = true
        updateMsg = "正在检查最新构建…"
        shareItems = []
        downloadPct = 0
        showDownload = true
        Task { @MainActor in
            do {
                if UpdateService.githubToken.isEmpty {
                    updateMsg = "请先点「GitHub Token」填入私库访问 Token"
                    updateBusy = false
                    return
                }
                let rel = try await UpdateService.fetchLatestRelease(token: UpdateService.githubToken)
                updateMsg = "发现构建 \(rel.name) · \(rel.displaySize)，开始下载…"
                showDownload = true
                let file = try await UpdateService.downloadIPA(url: rel.ipaUrl) { pct in downloadPct = pct }
                downloadFile = file
                updateMsg = "已下载 \(file.lastPathComponent)，点「分享安装包」弹出系统分享菜单"
                showDownload = false
                shareItems = [file as Any]
                shareSheetFlag = true
            } catch {
                updateMsg = "❌ \(error.localizedDescription)"
                showDownload = false
            }
            updateBusy = false
        }
    }
}
