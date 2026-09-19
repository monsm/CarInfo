// =============================================================================
// E50 AccessibilityReader — VoiceOver 朗读顺序优化 + 颜色盲模式
// =============================================================================

import SwiftUI

// MARK: - AccessibilityReader：为所有 View 添加朗读优先级
extension View {
    /// 设置 VoiceOver 朗读顺序优先级（数字越小越先朗读）
    func accessibilityReadOrder(_ order: Int) -> some View {
        self
            .accessibilitySortPriority(Double(-order))
            .accessibilityLabel(Text(self.accessibilityLabelContent ?? ""))
    }
    
    private var accessibilityLabelContent: String? { nil }
}

// MARK: - E53 颜色盲模式
struct ColorBlindModeView: View {
    @AppStorage("colorBlindMode") private var mode: Int = 0
    let options = [("正常", 0), ("Protanopia", 1), ("Deuteranopia", 2), ("Tritanopia", 3)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("色彩辅助模式").font(Theme.h4)
            Picker("模式", selection: $mode) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, item in
                    Text(item.0).tag(item.1)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .accessibilityLabel(Text("色彩辅助模式选择"))
        }
        .padding()
        .glassCard(corner: Theme.Radius.medium)
    }
}

// MARK: - Preview
struct AccessibilityReader_Previews: PreviewProvider {
    static var previews: some View {
        ColorBlindModeView()
            .previewDisplayName("Color Blind Mode")
    }
}
