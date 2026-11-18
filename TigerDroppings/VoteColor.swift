import SwiftUI

/// Vote "heat": net ratio (-1...1) times a confidence factor that grows with total votes.
/// 20-0 -> +0.92 (deep green), 10-5 -> +0.28 (light green), 5-20 -> -0.58 (strong red),
/// 1-0 -> +0.12 (faint), 6-5 -> +0.07 (neutral).
enum VoteHeat {
    static func score(up: Int, down: Int) -> Double {
        let total = Double(up + down)
        guard total > 0 else { return 0 }
        let net = (Double(up) - Double(down)) / total
        let confidence = 1 - exp(-total / 8)
        return net * confidence
    }

    static let green = Color(red: 0.13, green: 0.70, blue: 0.29)
    static let red = Color(red: 0.86, green: 0.17, blue: 0.17)

    /// Edge-bar color. 20-0 -> ~full green, 10-5 -> faint green (~0.39), 5-20 -> strong red (~0.67), neutral -> none.
    static func bar(up: Int, down: Int) -> Color {
        let s = score(up: up, down: down)
        guard abs(s) >= 0.08 else { return .clear }
        return (s > 0 ? green : red).opacity(min(1, 0.12 + 0.95 * abs(s)))
    }

    static let barWidth: CGFloat = 5
    static let separator = Color(white: 0.28)
    static let quoteBox = Color(white: 0.14)
    static let quoteText = Color(white: 0.72)
}

/// Black item with vote-colored bars on the left and right edges.
struct VoteEdges: ViewModifier {
    let up: Int
    let down: Int
    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(VoteHeat.bar(up: up, down: down)).frame(width: VoteHeat.barWidth)
            content.frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(VoteHeat.bar(up: up, down: down)).frame(width: VoteHeat.barWidth)
        }
        .background(Color.black)
    }
}

extension View {
    func voteEdges(up: Int, down: Int) -> some View { modifier(VoteEdges(up: up, down: down)) }
}
