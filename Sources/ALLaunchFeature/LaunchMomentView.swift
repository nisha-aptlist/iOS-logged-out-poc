// This module is iOS-only by its imports: UIKit, MapKit annotation views,
// UIImage, and iOS-only SwiftUI. The package declares macOS so that the pure
// modules (ALCore, ALAuth, ALLocation) have an honest availability floor —
// without it, Xcode building for "My Mac" fails in ALCore on `Duration` and
// `Task`. Guarding this file means the module compiles to nothing on macOS
// rather than failing to resolve UIKit, so EVERY scheme builds on EVERY
// destination and nobody has to know which one to pick.
#if os(iOS)
import ALDesignSystem
import SwiftUI

/// The launch moment: "What does home mean to you?"
///
/// In the shipping app this plays once and advances on its own, because a screen
/// that waits for a tap is a step, and the front-door decision was that there
/// are no steps before the map. The looping, tap-to-continue behaviour is a
/// prototype affordance so the screen can be studied, and it is gated behind
/// `loops` rather than being the default.
///
/// Motion is honoured, not assumed: under Reduce Motion the sequence collapses
/// to a static question with no drift, no stagger, and no pulse.
public struct LaunchMomentView: View {
    /// Renter voices. Written, not collected. Real ones belong in research
    /// before this goes in front of anyone.
    private static let answers = [
        "A stoop to sit on.",
        "Ten minutes from my mom.",
        "Morning light in the kitchen.",
        "Rent I can make every month.",
        "A block I can walk at night."
    ]

    private static let question = ["What", "does", "home", "mean", "to", "you?"]
    private static let accentWord = "home"

    private let loops: Bool
    private let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var answerIndex = 0
    @State private var hasLanded = false

    public init(loops: Bool = false, onContinue: @escaping () -> Void) {
        self.loops = loops
        self.onContinue = onContinue
    }

    public var body: some View {
        ZStack {
            ALColor.surface.ignoresSafeArea()
            FogBackdrop(animated: !reduceMotion)

            VStack(spacing: 0) {
                Spacer()

                mark
                    .padding(.bottom, 30)

                questionText
                    .padding(.horizontal, 34)

                answerText
                    .padding(.top, 22)
                    .padding(.horizontal, 34)

                Spacer()

                cityRule
                    .padding(.bottom, 34)

                if loops || reduceMotion {
                    Text("TAP ANYWHERE TO CONTINUE")
                        .font(ALTypography.mono(9.5))
                        .tracking(1.5)
                        .foregroundStyle(ALColor.inkTertiary)
                        .padding(.bottom, 30)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onContinue)
        .task { await run() }
        // One announcement rather than six word fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("What does home mean to you? \(Self.answers[answerIndex])")
        .accessibilityHint("Double tap to continue to the map")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Sequence

    private func run() async {
        withAnimation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.62)) {
            hasLanded = true
        }

        // Reduce Motion collapses the sequence, but it must NOT collapse the
        // hand-off: returning here left a shipping build on a splash screen
        // with no visible instruction and no way forward.
        if reduceMotion {
            guard !loops else { return }        // looping demo waits for a tap
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            onContinue()
            return
        }

        var shown = 1
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(2_200))
            guard !Task.isCancelled else { return }

            // A non-looping launch hands off once every answer has had a turn.
            // Counting explicitly rather than watching the index wrap, which
            // would fire after the second answer, not the last.
            if !loops, shown >= Self.answers.count {
                onContinue()
                return
            }

            withAnimation(.easeInOut(duration: 0.42)) {
                answerIndex = (answerIndex + 1) % Self.answers.count
            }
            shown += 1
        }
    }

    // MARK: - Pieces

    /// A location pin whose interior is a roof. Location and home in one glyph,
    /// which is what the question is about.
    private var mark: some View {
        ZStack {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(ALColor.accent)
                .opacity(hasLanded ? 1 : 0)
                .offset(y: hasLanded ? 0 : -54)
                .scaleEffect(hasLanded ? 1 : 0.82)

            Image(systemName: "house.fill")
                .font(.system(size: 17))
                .foregroundStyle(ALColor.surface)
                .offset(y: -4)
                .opacity(hasLanded ? 1 : 0)
        }
        .overlay(alignment: .bottom) {
            if !reduceMotion {
                LandingRing(active: hasLanded)
                    .frame(width: 34, height: 9)
                    .offset(y: 8)
            }
        }
    }

    private var questionText: some View {
        // A single Text with an AttributedString so the question can wrap; a
        // word-per-view HStack cannot. Note the type is a fixed size, not a
        // text style, so it does not scale with Dynamic Type — see SPEC.md.
        Text(attributedQuestion)
            .font(ALTypography.display(31))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(hasLanded ? 1 : 0)
            .offset(y: hasLanded ? 0 : 14)
    }

    private var attributedQuestion: AttributedString {
        var result = AttributedString()
        for (index, word) in Self.question.enumerated() {
            var piece = AttributedString(word)
            piece.foregroundColor = word == Self.accentWord ? ALColor.accent : ALColor.ink
            result += piece
            if index != Self.question.count - 1 { result += AttributedString(" ") }
        }
        return result
    }

    private var answerText: some View {
        Text(Self.answers[answerIndex])
            .font(.system(size: 15.5))
            .foregroundStyle(ALColor.inkSecondary)
            .multilineTextAlignment(.center)
            .id(answerIndex)                      // so the transition fires
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .frame(height: 24)
    }

    private var cityRule: some View {
        HStack(spacing: 12) {
            rule
            Text("SAN FRANCISCO")
                .font(ALTypography.mono(9.5))
                .tracking(2.2)
                .foregroundStyle(ALColor.inkTertiary)
            rule
        }
        .opacity(hasLanded ? 1 : 0)
    }

    private var rule: some View {
        Rectangle().fill(ALColor.hairline).frame(width: 26, height: 1)
    }
}

/// Two slow masses of fog. The only ambient motion on the screen.
private struct FogBackdrop: View {
    let animated: Bool
    @State private var drift = false

    var body: some View {
        ZStack {
            fog(ALColor.surfaceSunk, size: 1.5)
                .offset(x: drift ? 40 : -30, y: drift ? -30 : 10)
            fog(ALColor.accentTint, size: 1.2)
                .offset(x: drift ? -40 : 30, y: drift ? 30 : -10)
        }
        .blur(radius: 40)
        .ignoresSafeArea()
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 22).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func fog(_ color: Color, size: CGFloat) -> some View {
        GeometryReader { proxy in
            Ellipse()
                .fill(color)
                .frame(width: proxy.size.width * size, height: proxy.size.height * 0.7)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

/// The ring that pulses out from the pin's tip once it lands.
private struct LandingRing: View {
    let active: Bool
    @State private var expanded = false

    var body: some View {
        Ellipse()
            .strokeBorder(ALColor.accent, lineWidth: 1.5)
            .scaleEffect(expanded ? 1.5 : 0.4)
            .opacity(expanded ? 0 : 0.7)
            .onChange(of: active) { _, isActive in
                guard isActive else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    expanded = true
                }
            }
    }
}
#endif
