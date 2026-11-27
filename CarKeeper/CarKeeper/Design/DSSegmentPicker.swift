import SwiftUI

struct DSSegmentPicker<T: Hashable>: View {
    var options: [(value: T, title: String)]
    @Binding var selection: T
    var label: String

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Text(option.title).tag(option.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(Text(label))
    }
}
