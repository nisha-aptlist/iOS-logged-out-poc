// This module is iOS-only by its imports: UIKit, MapKit annotation views,
// UIImage, and iOS-only SwiftUI. The package declares macOS so that the pure
// modules (ALCore, ALAuth, ALLocation) have an honest availability floor —
// without it, Xcode building for "My Mac" fails in ALCore on `Duration` and
// `Task`. Guarding this file means the module compiles to nothing on macOS
// rather than failing to resolve UIKit, so EVERY scheme builds on EVERY
// destination and nobody has to know which one to pick.
#if os(iOS)
import ALCore
import MapKit

/// Fixed geography for the logged-out experience.
///
/// The city is hardcoded on purpose. An anonymous first launch has no saved
/// search and no profile, and asking for location before showing a single
/// listing is the most-denied prompt in mobile. So the map opens on San
/// Francisco and location stays a deliberate, later tap.
public enum SanFrancisco {
    /// Biased north of the city's true centre so the landmass sits in the band
    /// between the filter row and the listings sheet, rather than a third of
    /// the screen being the Pacific and Marin.
    public static let center = CLLocationCoordinate2D(latitude: 37.7480, longitude: -122.4430)

    public static let cityRegion = MKCoordinateRegion(
        center: center,
        span: MKCoordinateSpan(latitudeDelta: 0.125, longitudeDelta: 0.125)
    )

    /// Close enough that pins separate and street names appear.
    public static let blockSpan = MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)

    /// A region enclosing a set of points, padded so pins are not flush to the
    /// bezel. Nil for an empty set, which the caller must handle rather than
    /// receiving a region centred on (0, 0) in the Atlantic.
    public static func region(enclosing coordinates: [Coordinate]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }

        var minLat = first.latitude, maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLng = min(minLng, coordinate.longitude)
            maxLng = max(maxLng, coordinate.longitude)
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLng + maxLng) / 2
            ),
            span: MKCoordinateSpan(
                // A single result would otherwise produce a zero span, which
                // MapKit resolves to a maximum zoom sitting inside a wall.
                latitudeDelta: max((maxLat - minLat) * 1.6, 0.01),
                longitudeDelta: max((maxLng - minLng) * 1.6, 0.01)
            )
        )
    }
}
#endif
