// This module is iOS-only by its imports: UIKit, MapKit annotation views,
// UIImage, and iOS-only SwiftUI. The package declares macOS so that the pure
// modules (ALCore, ALAuth, ALLocation) have an honest availability floor —
// without it, Xcode building for "My Mac" fails in ALCore on `Duration` and
// `Task`. Guarding this file means the module compiles to nothing on macOS
// rather than failing to resolve UIKit, so EVERY scheme builds on EVERY
// destination and nobody has to know which one to pick.
#if os(iOS)
import ALCore
import ALDesignSystem
import MapKit
import UIKit

/// Why MapKit annotations rather than SwiftUI `Annotation`
///
/// SwiftUI's `Map` has no clustering. At San Francisco's density thirty price
/// pins overlap into an unreadable stack at city zoom, and `clusteringIdentifier`
/// on `MKAnnotationView` is the only supported way to get real clustering with
/// MapKit's own collision handling. So the map is `MKMapView` behind a
/// `UIViewRepresentable`, and this file is the annotation layer.
final class ListingAnnotation: NSObject, MKAnnotation {
    let listing: Listing
    /// `@objc dynamic` because MapKit observes these with KVO.
    @objc dynamic var coordinate: CLLocationCoordinate2D

    var title: String? { listing.name }
    var subtitle: String? { listing.neighborhood }

    init(listing: Listing) {
        self.listing = listing
        self.coordinate = listing.coordinate.clLocationCoordinate
        super.init()
    }

    override func isEqual(_ object: Any?) -> Bool {
        (object as? ListingAnnotation)?.listing.id == listing.id
    }

    override var hash: Int { listing.id.hashValue }
}

/// A price pill with a tail, sized to its label.
final class PricePinView: MKAnnotationView {
    static let reuseIdentifier = "PricePin"

    private let label = UILabel()
    private let bubble = UIView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = PricePinView.reuseIdentifier
        // The pin is a wide pill, so a circular collision shape under-reports
        // overlap and MapKit leaves colliding pins uncustered.
        collisionMode = .rectangle
        canShowCallout = false
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure() {
        backgroundColor = .clear

        bubble.backgroundColor = UIColor(ALColor.accent)
        bubble.layer.cornerCurve = .continuous
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowOpacity = 0.24
        bubble.layer.shadowRadius = 4
        bubble.layer.shadowOffset = CGSize(width: 0, height: 2)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bubble)

        label.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        label.textColor = UIColor(ALColor.onAccent)
        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: topAnchor),
            bubble.leadingAnchor.constraint(equalTo: leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: trailingAnchor),
            bubble.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -5),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -9)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Reused views keep their transform, so a previously selected pin would
        // come back oversized. This is the classic annotation-recycling bug.
        transform = .identity
        label.text = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bubble.layer.cornerRadius = bounds.height / 2
    }

    override var annotation: MKAnnotation? {
        didSet { apply() }
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        let scale: CGFloat = selected ? 1.12 : 1
        guard animated else { transform = CGAffineTransform(scaleX: scale, y: scale); return }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }

    private func apply() {
        guard let listing = (annotation as? ListingAnnotation)?.listing else { return }
        // Reasserted after reuse: `prepareForReuse` drops it, and a pin with no
        // clustering identifier never joins a cluster again.
        clusteringIdentifier = PricePinView.reuseIdentifier
        collisionMode = .rectangle
        label.text = listing.rentRange.fromFormatted

        // `frame` is documented as undefined while a transform is live, and
        // `setSelected` leaves a 1.12 scale that a plain annotation
        // reassignment does not clear. Reset first, then size via bounds.
        transform = .identity
        // Sizing has to be explicit: MKAnnotationView does not honour intrinsic
        // content size, so an unsized view collapses to zero and vanishes.
        let size = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        bounds = CGRect(origin: .zero, size: size)
        centerOffset = CGPoint(x: 0, y: -size.height / 2 - 4)

        isAccessibilityElement = true
        accessibilityLabel = "\(listing.name), \(listing.neighborhood), from \(listing.rentRange.low.formatted)"
        accessibilityTraits = .button
    }
}

/// A count bubble standing for several buildings.
final class ClusterPinView: MKAnnotationView {
    static let reuseIdentifier = "ClusterPin"

    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        collisionMode = .circle
        canShowCallout = false
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// A `CGColor` is resolved once and never re-resolves, so the ring kept the
    /// previous appearance after a light/dark switch. Re-applied on every trait
    /// change instead.
    ///
    /// Registered through `registerForTraitChanges` rather than overriding
    /// `traitCollectionDidChange`, which is deprecated as of iOS 17.
    private func observeAppearance() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ClusterPinView, _) in
            view.applyBorder()
        }
    }

    private func applyBorder() {
        layer.borderColor = UIColor(ALColor.surface).resolvedColor(with: traitCollection).cgColor
    }

    private func configure() {
        backgroundColor = UIColor(ALColor.accent)
        applyBorder()
        observeAppearance()
        layer.borderWidth = 2.5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)

        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = UIColor(ALColor.onAccent)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        transform = .identity
    }

    override var annotation: MKAnnotation? {
        didSet {
            guard let cluster = annotation as? MKClusterAnnotation else { return }
            let buildings = cluster.memberAnnotations.count
            // Rentals, not buildings: every other count in the product reports
            // units, and a bubble reading "3" over 40 rentals under-sells the
            // inventory it is hiding.
            let rentals = cluster.memberAnnotations
                .compactMap { ($0 as? ListingAnnotation)?.listing.availableUnitCount }
                .reduce(0, +)
            label.text = "\(rentals)"
            let diameter: CGFloat = rentals > 99 ? 54 : (rentals > 9 ? 46 : 40)
            frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            layer.cornerRadius = diameter / 2

            isAccessibilityElement = true
            accessibilityLabel = "\(rentals) rentals in \(buildings) buildings. Double tap to zoom in."
            accessibilityTraits = .button
        }
    }
}
#endif
