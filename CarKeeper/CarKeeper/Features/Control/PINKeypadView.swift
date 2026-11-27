import SwiftUI
import UIKit


struct PINKeypadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    private let keys = ["1","2","3","4","5","6","7","8","9","","0","del"]

    var body: some View {
        VStack(spacing: TokensSpacing.lg) {
            Capsule().fill(TokensPalette.secondary.opacity(0.4)).frame(width: 40, height: 5)
            VStack(spacing: TokensSpacing.xs) {
                Text("输入控车码").font(TokensTypo.title)
                Text("6 位数字，输满自动执行").font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
            }
            HStack(spacing: TokensSpacing.snug) {
                ForEach(0..<6, id: \.self) { i in
                    Text(i < pin.count ? String(pin[pin.index(pin.startIndex, offsetBy: i)]) : "")
                        .font(TokensTypo.metric(26))
                        .frame(width: 42, height: 54)
                        .background(TokensPalette.fillSubtle, in: RoundedRectangle(cornerRadius: 12, style:
 .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(i == pin.count ? TokensPalette.ambient : Color(.systemGray4),
                                          lineWidth: i == pin.count ? 2 : 1))
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                GridItem(.flexible())],
                      spacing: TokensSpacing.snug) {
                ForEach(keys, id: \.self) { k in
                    Button {
                        onKey(k)
                    } label: {
                        Group {
                            if k == "del" { Image(safeSymbol: "delete.left", fallback: "delete.left") }
                            else if k == "" { Color.clear }
                            else { Text(k) }
                        }
                        .font(TokensTypo.metric(26))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(TokensPalette.fillSubtle, in: RoundedRectangle(cornerRadius: 14, style:
 .continuous))
                        .foregroundStyle(TokensPalette.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("取消") { dismiss() }
                .font(TokensTypo.headline)
                .foregroundStyle(TokensPalette.secondary)
                .padding(.bottom, TokensSpacing.sm)
        }
        .padding(TokensSpacing.xxl)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func onKey(_ k: String) {
        if k == "del" { if !pin.isEmpty { pin.removeLast() } }
        else if !k.isEmpty { pin = String((pin + k).prefix(6)) }
        if pin.count == 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { confirm() }
        }
    }

    private func confirm() {
        guard pin.count == 6 else { return }
        NotificationCenter.default.post(name: .pinConfirmed, object: pin)
        dismiss()
    }
}
