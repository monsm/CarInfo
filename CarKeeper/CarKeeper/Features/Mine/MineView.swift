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
                // 身份条
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 56, height: 56)
                        Text(VM.userModel(store.user)?.avatar ?? "主")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.user.map { ciString($0, ["UserFullname", "UserNickname"]) ?? "车主" } ?? "车主")
                            .font(.system(size: 17, weight: .semibold))
                        HStack(spacing: 8) {
                            Text((store.user.map { ciString($0, ["Mobile"]) ?? "" } ?? "")).font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                            if (store.user.map { ciBool($0, ["RealnameAuthed"]) ?? false } ?? false) == true {
                                Text("已实名").font(.system(size: 12)).foregroundStyle(.green)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color(.systemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // 车辆卡
                if let car = store.car {
                    let sum = VM.vehicleSummary(car)
                    HStack(spacing: 14) {
                        Image(systemName: "car.fill").font(.system(size: 32)).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sum?.name ?? "未绑定车辆").font(.system(size: 17, weight: .semibold))
                            Text(sum?.plate ?? "暂无车牌").font(.system(size: 13)).foregroundStyle(.secondary)
                            if let end = sum?.insuranceEnd, !end.isEmpty {
                                HStack(spacing: 6) {
                                    Text("保险至 \(end)").font(.system(size: 12)).foregroundStyle(.secondary)
                                    if let d = sum?.insuranceDays {
                                        Text(d < 0 ? "已到期" : "剩 \(d) 天")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(d < 0 ? Color.red : (d <= 30 ? Color.orange : Color.green))
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Color(.systemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NotificationCenter.default.post(name: .navToVehicle, object: nil)
                    }
                }

                // 常用入口（磁贴接上深潜页导航）
                CardBox(title: "常用") {
                    HStack(spacing: 20) {
                        tile("shield.fill", "健康报告") { post(.navToHealth) }
                        tile("battery.100", "电池充电") { post(.navToBattery) }
                        tile("chart.bar", "全量分析") { post(.navToData) }
                        tile("doc.text", "车辆档案") { post(.navToVehicle) }
                    }
                    .frame(maxWidth: .infinity)
                }

                // 检查更新
                CardBox(title: "检查更新") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("下载最新 GitHub 构建的 ipa，分享后可用 AltStore/自签工具安装")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                        if showDownload {
                            VStack(spacing: 6) {
                                ProgressView(value: downloadPct)
                                Text("正在下载… \(Int(downloadPct * 100))%").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        if let m = updateMsg {
                            Text(m).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) { updateButtons() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("我的")
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

    // 常用入口磁贴。
    private func tile(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(.secondary)
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func updateButtons() -> some View {
        HStack(spacing: 12) {
            Button(updateBusy ? "检查中…" : "检查更新") { checkUpdate() }
                .font(.system(size: 14, weight: .medium))
                .disabled(updateBusy)
            if downloadFile != nil {
                Button("分享安装包") {
                    shareItems = [downloadFile as Any]
                    shareSheetFlag = true
                }
                .font(.system(size: 14, weight: .medium))
            }
            Button("GitHub Token") { tokenDraft = UpdateService.githubToken; showToken = true }
                .font(.system(size: 14)).foregroundStyle(.secondary)
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }

    private func utilityRow(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol).frame(width: 24).foregroundStyle(.secondary)
                Text(label).font(.system(size: 15))
                Spacer()
                if label == "退出登录" {
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
