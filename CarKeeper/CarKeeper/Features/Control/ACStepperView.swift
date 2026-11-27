import SwiftUI
import UIKit


struct ACStepperView: View {
    @Environment(\.dismiss) private var dismiss
    @State var temp: Int
    @State private var tempDisplayCount = 0

    init(initialTemp: Binding<Int>) {
        _temp = State(initialValue: initialTemp.wrappedValue)
    }

    var body: some View {
        VStack(spacing: TokensSpacing.lg) {
            Capsule().fill(TokensPalette.secondary.opacity(0.4)).frame(width: 40, height: 5)
            VStack(spacing: TokensSpacing.xs) {
                Text("空调温度").font(TokensTypo.title)
                Text("17 – 33 ℃").font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
            }
            HStack(spacing: TokensSpacing.xl) {
                tempButton("minus", canDo: temp > 17) { temp -= 1 }
                VStack(spacing: 0) {
                    Text("\(tempDisplayCount)")
                        .font(TokensTypo.display(72))
                        .foregroundStyle(TokensPalette.ambient)
                        .contentTransition(.numericText())
                    Text("℃").font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
                }
                tempButton("plus", canDo: temp < 33) { temp += 1 }
            }
            .padding(.vertical, TokensSpacing.sm)
            Button {
                NotificationCenter.default.post(name: .tempConfirmed, object: temp)
                dismiss()
            } label: {
                Text("确定")
                    .font(TokensTypo.title3)
                    .foregroundStyle(TokensPalette.labelOnTint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TokensSpacing.md)
                    .background(RoundedRectangle(cornerRadius: TokensRadius.medium,
                                                 style: .continuous)
                        .fill(TokensPalette.ambient))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, TokensSpacing.sm)
            Button("取消") { dismiss() }
                .font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
        }
        .padding(TokensSpacing.xxl)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.65, blendDuration: 0.9)) {
                tempDisplayCount = temp
            }
        }
        .onChange(of: temp) { _, newTemp in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.6)) {
                tempDisplayCount = newTemp
            }
        }
    }

    private func tempButton(_ sym: String, canDo: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(safeSymbol: sym + ".circle.fill", fallback: sym + ".circle.fill")
                .font(TokensTypo.display(42))
                .foregroundStyle(canDo ? TokensPalette.ambient : Color(.systemGray4))
        }
        .buttonStyle(.plain)
        .disabled(!canDo)
    }
}
