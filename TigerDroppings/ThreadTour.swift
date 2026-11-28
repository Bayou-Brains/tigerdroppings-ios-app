import SwiftUI
import UIKit

/// First-time coach marks on a thread: the summary (sparkles) button, then Live.
@MainActor
@Observable
final class ThreadTourController {
    static let shared = ThreadTourController()
    static let seenKey = "hasSeenThreadTour"
    static let demoStepKey = "demoTourStep"

    enum Step: Int {
        case ai = 1
        case live = 2
    }

    var step: Step? = nil
    var anchors: [String: CGRect] = [:]

    var isActive: Bool { step != nil }

    var currentAnchorId: String? {
        switch step {
        case .ai: return "ai"
        case .live: return "live"
        case nil: return nil
        }
    }

    var currentAnchor: CGRect? {
        if currentAnchorId == "live" {
            if let live = anchors["live"], isPlausible(live),
               let ai = anchors["ai"], isPlausible(ai), live.width <= ai.width * 1.6 {
                return live
            }
            if let live = anchors["live"], isPlausible(live), anchors["ai"] == nil {
                return live
            }
            if let ai = anchors["ai"], isPlausible(ai) {
                // Toolbar Live frames are often unusable; the three trailing buttons
                // are the same size, with a tight gap, so estimate from sparkles.
                let w = ai.width
                let gap: CGFloat = 8
                return CGRect(x: ai.minX - gap - w, y: ai.minY, width: w, height: ai.height)
            }
            return nil
        }
        if let id = currentAnchorId, let r = anchors[id], isPlausible(r) { return r }
        return nil
    }

    private var forcedDemo: Bool {
        UserDefaults.standard.integer(forKey: Self.demoStepKey) > 0
    }

    func setAnchor(_ id: String, _ frame: CGRect) {
        guard isPlausible(frame) else { return }
        let r = CGRect(x: frame.minX.rounded(), y: frame.minY.rounded(),
                       width: frame.width.rounded(), height: frame.height.rounded())
        if anchors[id] != r { anchors[id] = r }
    }

    func isPlausible(_ r: CGRect) -> Bool {
        // Tight control/chip in the navigation bar, not a zero-origin or full-width bar.
        guard r.width >= 16, r.width <= 220, r.height >= 16, r.height <= 72 else { return false }
        let screen = Self.windowBounds
        return r.midY >= 50 && r.midY <= 170 && r.minX >= -4 && r.maxX <= screen.width + 4
    }

    static var windowBounds: CGRect {
        keyWindow?.bounds ?? UIScreen.main.bounds
    }

    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first
    }

    /// Walk the key window to find the toolbar buttons by accessibility id/label.
    func refreshAnchorsFromWindow() {
        guard let window = Self.keyWindow else { return }
        var found: [String: CGRect] = [:]
        func walk(_ view: UIView) {
            let id = view.accessibilityIdentifier ?? ""
            let label = view.accessibilityLabel ?? ""
            let frame = view.convert(view.bounds, to: window)
            if isPlausible(frame) {
                if id == "liveToggle" || label == "Go Live" || label == "Live" {
                    let existing = found["live"]
                    if existing == nil || frame.width * frame.height > existing!.width * existing!.height {
                        found["live"] = frame
                    }
                }
                if id == "summarizeThread" || label == "Summarize thread" {
                    let existing = found["ai"]
                    if existing == nil || frame.width * frame.height > existing!.width * existing!.height {
                        found["ai"] = frame
                    }
                }
            }
            view.subviews.forEach(walk)
        }
        walk(window)
        for (id, frame) in found { setAnchor(id, frame) }
    }

    func startIfNeeded() {
        let destination: Step
        if forcedDemo {
            destination = Step(rawValue: UserDefaults.standard.integer(forKey: Self.demoStepKey)) ?? .ai
        } else {
            guard !UserDefaults.standard.bool(forKey: Self.seenKey), step == nil else { return }
            destination = .ai
        }
        Task { @MainActor in
            // Wait until the toolbar buttons have real frames before showing the bubble.
            for _ in 0..<40 {
                refreshAnchorsFromWindow()
                // AI frame is reliable and also lets us estimate the Live chip.
                if anchors["ai"] != nil || anchors[destination == .ai ? "ai" : "live"] != nil {
                    step = destination
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            refreshAnchorsFromWindow()
            step = destination
        }
    }

    func next() {
        if step == .ai {
            refreshAnchorsFromWindow()
            step = .live
        } else {
            finish()
        }
    }

    func finish() {
        step = nil
        if !forcedDemo {
            UserDefaults.standard.set(true, forKey: Self.seenKey)
        }
    }

    /// Leaving the thread mid-tour hides it, but it can show again next time.
    func dismissIfActive() {
        if !forcedDemo { step = nil }
    }
}

extension View {
    /// Reports this view's global frame so the thread tour can point at it.
    func tourAnchor(_ id: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            ThreadTourController.shared.setAnchor(id, frame)
        }
    }
}

struct ThreadTourOverlay: View {
    @Bindable var tour: ThreadTourController

    var body: some View {
        GeometryReader { geo in
            let screen = ThreadTourController.windowBounds
            let origin = geo.frame(in: .global).origin
            let target = tour.currentAnchor.map { r in
                CGRect(x: r.minX - origin.x, y: r.minY - origin.y, width: r.width, height: r.height)
            }
            ZStack(alignment: .topLeading) {
                dim(size: geo.size, hole: target)
                    .contentShape(Rectangle())
                    .onTapGesture { tour.finish() }
                    .accessibilityLabel("Skip the tour")
                    .accessibilityAddTraits(.isButton)

                if let step = tour.step, let target {
                    highlight(target)
                    bubble(step: step, target: target, size: geo.size, screenWidth: screen.width, originX: origin.x)
                }
            }
        }
        .ignoresSafeArea()
        .appTextSize()
        .onAppear { tour.refreshAnchorsFromWindow() }
    }

    private func dim(size: CGSize, hole: CGRect?) -> some View {
        Canvas { ctx, canvasSize in
            var path = Path(CGRect(origin: .zero, size: canvasSize))
            if let hole {
                let pad = hole.insetBy(dx: -7, dy: -6)
                path.addRoundedRect(in: pad, cornerSize: CGSize(width: 10, height: 10), style: .continuous)
            }
            ctx.fill(path, with: .color(.black.opacity(0.58)), style: FillStyle(eoFill: true))
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(true)
    }

    private func highlight(_ target: CGRect) -> some View {
        let pad = target.insetBy(dx: -7, dy: -6)
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.lsuGold, lineWidth: 2)
            .frame(width: pad.width, height: pad.height)
            .position(x: pad.midX, y: pad.midY)
            .allowsHitTesting(false)
    }

    private func bubble(step: ThreadTourController.Step, target: CGRect, size: CGSize, screenWidth: CGFloat, originX: CGFloat) -> some View {
        let width: CGFloat = min(280, size.width - 40)
        let pad: CGFloat = 20
        // Clamp in screen coordinates, then convert back to the overlay's local space.
        let minLocalX = pad - originX
        let maxLocalX = screenWidth - originX - width - pad
        let x = min(max(target.midX - width / 2, minLocalX), max(minLocalX, maxLocalX))
        let arrowX = min(max(target.midX - x - 8, 12), width - 28)
        let text: String = {
            switch step {
            case .ai: return "Tap here for a quick summary of this thread."
            case .live: return "Live mode auto-updates this thread every 5 seconds."
            }
        }()
        let buttonTitle = step == .ai ? "Next" : "Done"
        return VStack(spacing: 0) {
            TourArrow()
                .fill(Color(white: 0.14))
                .frame(width: 16, height: 8)
                .padding(.leading, arrowX)
                .frame(width: width, alignment: .leading)
            VStack(alignment: .leading, spacing: 12) {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Spacer(minLength: 0)
                    Button(buttonTitle) { tour.next() }
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(Color.lsuGold, in: Capsule())
                        .foregroundStyle(.black)
                        .accessibilityIdentifier(step == .ai ? "threadTourNext" : "threadTourDone")
                }
            }
            .padding(14)
            .frame(width: width, alignment: .leading)
            .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.lsuGold.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        }
        .frame(width: width, alignment: .top)
        .offset(x: x, y: target.maxY + 10)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(step == .ai ? "Tour, step 1 of 2" : "Tour, step 2 of 2")
    }
}

private struct TourArrow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
