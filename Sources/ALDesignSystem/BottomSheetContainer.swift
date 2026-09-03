// This module is iOS-only by its imports: UIKit, MapKit annotation views,
// UIImage, and iOS-only SwiftUI. The package declares macOS so that the pure
// modules (ALCore, ALAuth, ALLocation) have an honest availability floor —
// without it, Xcode building for "My Mac" fails in ALCore on `Duration` and
// `Task`. Guarding this file means the module compiles to nothing on macOS
// rather than failing to resolve UIKit, so EVERY scheme builds on EVERY
// destination and nobody has to know which one to pick.
#if os(iOS)
import SwiftUI

/// A persistent bottom surface with detents, drag, and snapping.
///
/// Why this exists instead of `.sheet`
///
/// The listings surface never dismisses, and a permanently-presented `.sheet`
/// holds the window's ONLY presentation slot. That is not a detail — it made the
/// signup wall unreachable from all four of its entry points, because
/// `RootView`'s own `.sheet` and `.fullScreenCover` silently resolved to the
/// same host and were dropped. Every unit test passed throughout.
///
/// So the persistent surface stops being a modal. It is a sibling in the
/// ZStack, which frees the real presentation slot for the things that genuinely
/// are transient: the wall, the detail, the explainer, the recovery sheet, the
/// search picker. Those then present over the map, as they should.
///
/// Two things come out better rather than worse for being hand-built:
///
/// 1. Background interaction is structural instead of opt-in. This view
///    occupies only its own frame, so the map above it is pannable by
///    construction — no `presentationBackgroundInteraction` needed, and no
///    `upThrough:` threshold to get wrong.
/// 2. The detent set can change freely. `presentationDetents(_:selection:)`
///    documents nothing about a selection that is not a member of a new set,
///    and swapping the set raced the corrective `onChange`. Here the snapping
///    rule is visible and ours.
public struct BottomSheetContainer<Content: View>: View {

    /// Heights as a fraction of the available height, ascending.
    private let detents: [CGFloat]
    @Binding private var selection: CGFloat
    private let content: Content

    /// Live drag offset in points. Positive is downward, which shrinks the
    /// surface.
    @State private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        detents: [CGFloat],
        selection: Binding<CGFloat>,
        @ViewBuilder content: () -> Content
    ) {
        self.detents = detents.sorted()
        self._selection = selection
        self.content = content()
    }

    public var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.height
            let lowest = (detents.first ?? 0.25) * available
            let highest = (detents.last ?? 0.58) * available
            let height = min(max(selection * available - dragOffset, lowest), highest)

            VStack(spacing: 0) {
                grabber(available: available)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
            }
            .frame(height: height, alignment: .top)
            .background(ALColor.surface)
            .clipShape(
                .rect(
                    topLeadingRadius: ALMetrics.sheetRadius,
                    topTrailingRadius: ALMetrics.sheetRadius
                )
            )
            .shadow(color: .black.opacity(0.16), radius: 18, y: -2)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        // Only the surface's own frame is interactive, so the map above stays
        // live without any extra opt-in.
        .ignoresSafeArea(edges: .bottom)
    }

    private func grabber(available: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(ALColor.inkTertiary.opacity(0.4))
                .frame(width: 38, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        // A generous hit area: 4pt is not a drag target.
        .contentShape(Rectangle())
        .gesture(dragGesture(available: available))
        .accessibilityElement()
        .accessibilityLabel("Sheet height")
        .accessibilityValue(accessibilityValue(available: available))
        .accessibilityHint("Swipe up or down to resize")
        .accessibilityAdjustableAction { direction in
            guard let index = detents.firstIndex(of: selection) else {
                selection = detents.first ?? selection
                return
            }
            switch direction {
            case .increment: selection = detents[min(index + 1, detents.count - 1)]
            case .decrement: selection = detents[max(index - 1, 0)]
            @unknown default: break
            }
        }
    }

    private func accessibilityValue(available: CGFloat) -> String {
        guard let index = detents.firstIndex(of: selection) else { return "custom" }
        switch index {
        case 0: return detents.count == 1 ? "fixed" : "collapsed"
        case detents.count - 1: return "expanded"
        default: return "medium"
        }
    }

    private func dragGesture(available: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard detents.count > 1 else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                guard detents.count > 1 else { return }
                // Project the flick so a fast short swipe still changes detent.
                let projected = selection * available
                    - (value.translation.height + value.predictedEndTranslation.height * 0.3)
                let targetFraction = projected / available
                let nearest = detents.min {
                    abs($0 - targetFraction) < abs($1 - targetFraction)
                } ?? selection

                if reduceMotion {
                    dragOffset = 0
                    selection = nearest
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        dragOffset = 0
                        selection = nearest
                    }
                }
            }
    }
}
#endif
