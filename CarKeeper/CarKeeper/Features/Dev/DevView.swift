import SwiftUI

// 开发者工具：网络通道说明 + 请求/响应日志（复制/清空）+ 排查指引 + 清缓存
// 对应小程序 dev.js。iOS 直连模式，无云函数版本头，改为展示 App 构建版本与日志。

struct DevView: View {
    private let store = AppStore.shared
    @State private var logOpen = false
    @State private var logCount = 0
    @State private var logText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.cardSpacing) {
                // 网络通道
                CardBox(title: "网络通道", side: "直连（iOS 原生）") {
                    VStack(spacing: 8) {
                        KVRow(k: "API 域名", v: APIConfig.baseURL.replacingOccurrences(of: "https://", with: ""))
                        KVRow(k: "User-Agent", v: APIConfig.userAgent)
                        KVRow(k: "版本", v: appVersion)
                        KVRow(k: "登录模式", v: "直连")
                    }
                }

                // 请求 / 响应日志
                CardBox(title: "请求 / 响应日志", side: "\(logCount) 条",
                        sideCls: logCount > 0 ? "ok" : "na") {
                    Button {
                        logOpen.toggle()
                        if logOpen { refreshLog() }
                    } label: {
                        HStack {
                            Text(logOpen ? "收起" : "展开").font(.system(size: 14))
                            Image(systemName: logOpen ? "chevron.up" : "chevron.down").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if logOpen {
                        ScrollView {
                            Text(logText.isEmpty ? "（暂无记录：先发起一次请求，如刷新数据或下发指令）" : logText)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(.thin, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .frame(maxHeight: 360)
                        HStack(spacing: 10) {
                            Button { refreshLog() } label: {
                                Label("刷新", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            Button { copyLog() } label: {
                                Label("复制全部", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            Button { clearLog() } label: {
                                Label("清空", systemImage: "trash").foregroundStyle(.red)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                // 排查指引
                CardBox(title: "排查指引") {
                    VStack(spacing: 0) {
                        guideRow("云函数部署步骤") {
                            let text = "iOS 版无云函数（直连长安接口）。若登录失败请检查：\n1. 网络连接正常\n2. 重新触发一次图形验证码刷新\n3. 在开发者工具页查看最近请求日志的 via 头"
                            UIPasteboard.general.string = text
                        }
                        guideRow("短信 / 登录失败排查") {
                            let text = "短信 / 登录失败排查：\n1. 刷新图形验证码后立即输入发送（不要隔太久）\n2. 直连模式下出口 IP 固定，CDN 节点绑定稳定\n3. 仍失败请复制本页请求日志（含 REQ / RES 原文）给开发者"
                            UIPasteboard.general.string = text
                        }
                        guideRow("清除车辆数据缓存") {
                            store.clearCache()
                            refreshLog()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .pageBackground(.secondary)
        .navigationTitle("开发者工具").navBarStyle()
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (\(b))"
    }

    private func refreshLog() {
        logCount = RawLogStore.shared.count()
        logText = RawLogStore.shared.joined()
    }

    private func copyLog() {
        if logText.isEmpty { refreshLog() }
        UIPasteboard.general.string = logText.isEmpty ? "（暂无日志）" : logText
    }

    private func clearLog() {
        RawLogStore.shared.clear()
        logText = "（已清空）"
        logCount = 0
    }

    private func guideRow(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).font(.system(size: 14))
                Spacer()
                Text("复制").font(.system(size: 13)).foregroundStyle(Color.accentColor)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
