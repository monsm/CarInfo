import SwiftUI

// =============================================================================
//  MapSkySheet —— 地图页那颗「光」表（原 `MapSpineView.skySheet`）
// =============================================================================
//
//  2026-09-25 从 `MapSpineView.swift` 拆出来：那个文件涨到 **1201 行**，
//  越过了 `lintcfg.py` 的 1200 阈值 —— 而那个阈值的用法是「把东西拆出去」，
//  不是「把文件加进排除清单」（清单只减不增，见 `.swiftlint.yml` 的说明）。
//
//  为什么拆的是它：这张表是**一整屏的自成一体的东西**（导航栏 + 两张分节标题 +
//  一张事实表 + 一个时刻滑块 + 一段出处说明），宿主只需要给它三样东西 ——
//  当前数据、滑块的两个状态、以及「重取天气」那一个动作。换句话说，
//  它与地图页其余部分之间的接口小到可以用手指头数完。
//
//  ⚠️ 界面一字未改：拆的是文件，不是设计（同样的分节标题、同样的 `dsSurface`
//  面板、同样的两个工具栏按钮）。唯一变的是「关掉这张表」——
//  原来写 `showSky = false`（宿主的状态），现在写 `isOpen = false`（同一个状态的绑定）。
// =============================================================================

struct MapSkySheet: View {
    /// 这一屏的数据（事实表与光都从它出）
    let data: MapSpineData
    /// 时刻滑块的位置（0...23，小时）
    @Binding var skyHour: Double
    /// 「看此刻」还是「看那一刻」—— 一旦拖过滑块就变成后者
    @Binding var skyLive: Bool
    /// 这张表开着没有（宿主用 `.sheet(isPresented:)` 绑的就是它）
    @Binding var isOpen: Bool
    /// 重取天气。那段逻辑属于宿主的取数链（`refreshWeatherIfNeeded`），
    /// 所以只把动作传进来 —— 拆分的边界画在「谁去取数」而不是「谁画工具栏」上。
    let retryWeather: () async -> Void

    /// 天气实况（表里那条「没取到」的提示要看它）。
    /// 自己订阅单例，不要求宿主传进来 —— 与地图页那行订阅的是同一个对象。
    @ObservedObject private var weather = WeatherService.shared

    /// 算光用的时刻（实时就是现在）
    private var skyDate: Date {
        SkyLight.date(hour: skyLive ? nil : Int(skyHour.rounded()), from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                    if let sky = data.sky(at: skyDate) {
                        DSSectionHeader(title: "此刻的光")
                        VStack(alignment: .leading, spacing: 0) {
                            SkyFactTable(facts: sky.facts)
                        }
                        .padding(.horizontal, TokensSpacing.md)
                        .dsSurface(padding: 0)

                        // 时刻滑块 —— 样品里最标志性的那件东西：
                        // 把「此刻」变成「可以拖的时刻」，一拖就能看完一天的光（深夜→日出→正午→黄昏）。
                        // 它同时是这一整套光的**证明**：不是配的色，拖一下就自己看见。
                        DSSectionHeader(title: "看哪一刻的光")
                        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                                Text(skyLive ? "此刻（实时）"
                                             : String(format: "%02d:00", Int(skyHour.rounded())))
                                    .font(TokensTypo.digits(20))
                                    .foregroundStyle(TokensPalette.primary)
                                Spacer(minLength: 0)
                                if !skyLive {
                                    Button("回到此刻") {
                                        TokensHaptic.tap()
                                        skyLive = true
                                    }
                                    .font(TokensTypo.footnote)
                                    .foregroundStyle(TokensPalette.accent)
                                    .buttonStyle(.plain)
                                }
                            }
                            Slider(value: $skyHour, in: 0...23)
                                .tint(TokensPalette.accent)
                                .onChange(of: skyHour) { _, _ in skyLive = false }
                            Text("按你所在时区。")
                                .font(TokensTypo.caption)
                                .foregroundStyle(TokensPalette.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // 面板的底来自 `dsSurface`（全 App 唯一的分组表面），
                        // 不再自己画一个 RoundedRectangle —— 2026-09-25 材质审核
                        // 找到的第三套「卡的面」。换成 DS 之后它顺带拿到艺术方向下的
                        // 那圈发丝线（纸与墨的语言里，一块面本来就是靠线画出来的）。
                        .dsSurface(padding: TokensSpacing.md)

                        if case .failed(let msg) = weather.status {
                            DSNotice(kind: .warning,
                                     text: "天气没取到（\(msg)），上面是晴空模型的算法值。")
                        }

                        Text("太阳高度角与方位角由车的位置算出（NOAA，不联网）。"
                             + "云量、降水来自 Open-Meteo 实况。"
                             + "没有实况就退回晴空模型。")
                            .font(TokensTypo.footnote)
                            .foregroundStyle(TokensPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        MapNotice(text: "不知道车在哪儿")
                    }
                }
                .padding(.top, TokensSpacing.sm)
                .padding(.bottom, TokensSpacing.xxl)
                // 页面左右边距**写在这里**：原来它来自 `pageBackground()` 里那句
                // `contentMargins(.horizontal, 20, for: .scrollContent)`，而那个修饰符
                // 2026-09-25 整段删掉（它叫「页面底色」却只把卡片变窄，见 `Theme.swift`）。
                // 这一屏的正文原来一分横向边距都没有、全赖那一句，所以拆的时候必须补上。
                .padding(.horizontal, TokensSpacing.page)
            }
            .navigationTitle("光")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium, .large])
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await retryWeather() }
                    } label: {
                        if weather.status == .loading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("重取天气")
                        }
                    }
                    .font(TokensTypo.footnote)
                    .disabled(weather.status == .loading)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { isOpen = false }
                }
            }
        }
    }
}

// =============================================================================
//  MapNotice —— 「这一层现在没有可看的东西」那一句
// =============================================================================
//
//  原来它是 `MapSpineView.emptyNotice(_:)`（一个只有图标 + 一句真话的 HStack，
//  不吃整屏、不装成空态卡）。四个地图图层、评分段与「光」表都用它 ——
//  也就是说它其实是一个**共用原语**，只是碰巧长在宿主身上。
//
//  拆文件时它跟着「光」表一起过来：那一支也需要它，而地图页那一侧保留同名方法
//  作为一行转发（`MapSpineLayers.swift` 与 `ScoreSection.swift` 的四处调用点
//  因此一字不改 —— 拆文件不该顺带改调用点）。
struct MapNotice: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: TokensSpacing.sm) {
            Image(safeSymbol: "info.circle", fallback: "info.circle")
                .font(TokensTypo.fixed(13))
                .foregroundStyle(TokensPalette.tertiary)
            Text(text)
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, TokensSpacing.sm)
    }
}

// =============================================================================
//  SkyFactTable —— 「光」表（2026-09-25 从 `Design/SkyOverlay.swift` 搬来）
// =============================================================================
//  它原来住在光层那个文件里，而那个文件随艺术主题一起删掉了；这一张表不是装饰 ——
//  它是这一页正文的**唯一**内容（`MapSkySheet` 就是「给光算出来的每一个数看」）。
//  一个视图跟着它的唯一读者走，比留在一个只服务于主题的文件里更说得通。
//
// SkyFactTable —— 「光」表
// =============================================================================
//
// 一行一个事实：左边是这一栏叫什么 + **它是怎么来的**，右边是值。
// 为什么值得占一页：光好不好看是主观的，但「这一屏的光从哪来」不该是主观的。
// 把规则印在值的旁边，这一屏就变得可以被争论 —— 而可以被争论，才谈得上被设计。
struct SkyFactTable: View {
    let facts: [SkyFact]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(facts) { f in
                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.md) {
                    VStack(alignment: .leading, spacing: TokensSpacing.xxs) {
                        Text(f.label)
                            .font(TokensTypo.caption)
                            .foregroundStyle(TokensPalette.secondary)
                        Text(f.note)
                            .font(TokensTypo.caption2)
                            .foregroundStyle(TokensPalette.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Text(f.value)
                        .font(TokensTypo.digits(13))
                        .foregroundStyle(TokensPalette.primary)
                        .fixedSize()
                }
                .padding(.vertical, TokensSpacing.sm)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(TokensPalette.hairline)
                        .frame(height: TokensHair.line)
                }
            }
        }
    }
}
