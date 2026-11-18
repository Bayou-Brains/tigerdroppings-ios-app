import SwiftUI

/// App-wide text size. Every view uses Dynamic Type text styles, so overriding the
/// environment's dynamicTypeSize scales all fonts and SF Symbols, and @ScaledMetric
/// paddings / bar widths scale with it. Stored as a step index in UserDefaults.
enum TextSize {
    static let key = "textSizeStep"
    static let defaultStep = 3
    static let steps: [(size: DynamicTypeSize, percent: Int)] = [
        (.xSmall, 82), (.small, 88), (.medium, 94), (.large, 100),
        (.xLarge, 112), (.xxLarge, 124), (.xxxLarge, 135), (.accessibility1, 160),
    ]
    static func clamp(_ step: Int) -> Int { min(max(step, 0), steps.count - 1) }
    static func size(_ step: Int) -> DynamicTypeSize { steps[clamp(step)].size }
    static func percent(_ step: Int) -> Int { steps[clamp(step)].percent }
}

struct AppTextSize: ViewModifier {
    @AppStorage(TextSize.key) private var step = TextSize.defaultStep
    func body(content: Content) -> some View {
        content.dynamicTypeSize(TextSize.size(step))
    }
}

extension View {
    /// Apply the user's Settings text size (also needed on sheets).
    func appTextSize() -> some View { modifier(AppTextSize()) }
}

struct TextSizeSettings: View {
    @AppStorage(TextSize.key) private var step = TextSize.defaultStep

    private var stepBinding: Binding<Double> {
        Binding(get: { Double(TextSize.clamp(step)) }, set: { step = TextSize.clamp(Int($0.rounded())) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Size")
                Spacer()
                Text("\(TextSize.percent(step))%").monospacedDigit().foregroundStyle(Color.lsuGold).fontWeight(.semibold)
            }
            HStack(spacing: 10) {
                Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                Slider(value: stepBinding, in: 0...Double(TextSize.steps.count - 1), step: 1)
                    .accessibilityLabel("Text size")
                    .accessibilityValue("\(TextSize.percent(step)) percent")
                Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
            }
            HStack {
                Button("Reset to 100%") { step = TextSize.defaultStep }
                    .font(.footnote).buttonStyle(.borderless)
                    .disabled(step == TextSize.defaultStep)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

/// Live preview in Settings: a sample post drawn by the real PostRow.
struct TextSizePreview: View {
    static let sample = Post(
        id: "preview", author: "BayouBengal", time: "2:14 pm", replyTo: "GeauxTigers",
        avatar: nil,
        blocks: [.quote(AttributedString("Defense looked fast tonight.")),
                 .text(AttributedString("Agreed. That second-half adjustment was the difference. Geaux Tigers!"))],
        up: 20, down: 0, page: 1)

    var body: some View {
        PostRow(post: Self.sample, isOP: true)
            .allowsHitTesting(false)
    }
}
