// This module is iOS-only by its imports: UIKit, MapKit annotation views,
// UIImage, and iOS-only SwiftUI. The package declares macOS so that the pure
// modules (ALCore, ALAuth, ALLocation) have an honest availability floor —
// without it, Xcode building for "My Mac" fails in ALCore on `Duration` and
// `Task`. Guarding this file means the module compiles to nothing on macOS
// rather than failing to resolve UIKit, so EVERY scheme builds on EVERY
// destination and nobody has to know which one to pick.
#if os(iOS)
import SwiftUI

/// The three photographs shipped with the prototype.
///
/// Three photos across thirty buildings is a stand-in, not a shipping decision.
/// Each listing leads with a different one and gets its own crop anchor, so two
/// buildings opened back to back do not show an identical frame, but the
/// repetition is visible by the fourth. Real per-building photography replaces
/// this enum wholesale, and nothing outside it needs to change.
public enum ListingPhoto: String, CaseIterable, Sendable {
    case facade = "listing_facade"
    case living = "listing_living"
    case bay = "listing_bay"

    public var caption: String {
        switch self {
        case .facade: "Facade"
        case .living: "Living room"
        case .bay: "Bay window"
        }
    }

    /// The photo a given building leads with, rotated by a stable offset.
    public static func lead(for seed: Int) -> ListingPhoto {
        allCases[abs(seed) % allCases.count]
    }

    /// The three photos in this building's order.
    public static func ordered(seed: Int) -> [ListingPhoto] {
        let offset = abs(seed) % allCases.count
        return (0 ..< allCases.count).map { allCases[(offset + $0) % allCases.count] }
    }
}

/// Bundle image loading that cannot fail silently.
///
/// `Image(_:bundle:)` resolves **asset catalog** names. These photographs are
/// loose files declared with `.process("Resources")`, so that initialiser found
/// nothing and SwiftUI rendered an empty view — the thumbnail slot reserved its
/// 52pt and drew nothing, with no error anywhere. `UIImage(named:in:with:)`
/// searches the bundle itself, and a miss now renders a labelled placeholder
/// instead of blank space.
extension ListingPhoto {
    /// Loaded by URL, which is the only lookup that finds a loose resource.
    ///
    /// Two initialisers were tried and both fail for files declared with
    /// `.process("Resources")` rather than sat in an asset catalog:
    /// `Image(_:bundle:)` resolves asset-catalog names only and rendered an
    /// empty view, and `UIImage(named:in:with:)` also returned nil. Only
    /// `Bundle.module.url(forResource:withExtension:)` plus
    /// `UIImage(contentsOfFile:)` resolves them.
    ///
    /// The failure path returns nil rather than trapping: a missing photograph
    /// should degrade to a placeholder, not take down a renter's session.
    var image: UIImage? {
        guard let url = Bundle.module.url(forResource: rawValue, withExtension: "jpg"),
              let loaded = UIImage(contentsOfFile: url.path)
        else { return nil }
        return loaded
    }
}

/// A photo plate with a deterministic crop anchor per building.
public struct ListingPhotoView: View {
    private let photo: ListingPhoto
    private let seed: Int
    private let showsCaption: Bool

    public init(photo: ListingPhoto, seed: Int, showsCaption: Bool = false) {
        self.photo = photo
        self.seed = seed
        self.showsCaption = showsCaption
    }

    /// A stable per-building crop anchor. Five positions is enough to break
    /// the repetition without pushing the subject out of frame.
    private var cropAnchor: Alignment {
        switch abs(seed) % 5 {
        case 0: .center
        case 1: .top
        case 2: .bottom
        case 3: .leading
        default: .trailing
        }
    }

    private var photoImage: Image {
        if let image = photo.image {
            Image(uiImage: image)
        } else {
            Image(systemName: "photo")
        }
    }

    public var body: some View {
        // A .resizable/.scaledToFill image inside a clipped container is the
        // only combination that crops rather than distorts; .aspectRatio on the
        // Image alone will letterbox instead.
        photoImage
            .resizable()
            .aspectRatio(contentMode: .fill)
            // The anchor is what actually varies the crop. It was documented
            // and then never applied, so two buildings sharing a photograph
            // rendered the identical frame.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cropAnchor)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if showsCaption {
                    Text(photo.caption.uppercased())
                        .font(ALTypography.mono(9, weight: .medium))
                        .tracking(0.9)
                        .foregroundStyle(ALColor.inkSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                }
            }
            // The crop anchor varies per building so a shared photo does not
            // read as the same room twice.
            .contentShape(Rectangle())
            .accessibilityLabel(photo.caption)
    }
}
#endif
