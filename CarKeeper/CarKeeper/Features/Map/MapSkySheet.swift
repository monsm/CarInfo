import SwiftUI


struct MapSkySheet: View {
    let data: MapSpineData
    @Binding var skyHour: Double
    @Binding var skyLive: Bool
    @Binding var isOpen: Bool
    let retryWeather: () async -> Void

    @ObservedObject private var weather = WeatherService.shared

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
