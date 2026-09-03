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
import SwiftUI

/// `MKMapView` bridged into SwiftUI, because clustering requires it.
///
/// The bridge is deliberately thin: it diffs annotations, forwards selection,
/// and applies camera changes. It holds no product logic. Everything about what
/// a pin means lives in `MapStore`.
struct ListingMapView: UIViewRepresentable {
    let listings: [Listing]
    let selectedID: UUID?
    let userCoordinate: CLLocationCoordinate2D?
    @Binding var region: MKCoordinateRegion
    /// Bumped by the store on every deliberate camera move.
    let regionIntent: Int
    let onSelect: (Listing) -> Void
    let onDeselect: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll   // POIs compete with price pins
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false               // drawn only once authorized
        map.register(PricePinView.self, forAnnotationViewWithReuseIdentifier: PricePinView.reuseIdentifier)
        map.register(ClusterPinView.self, forAnnotationViewWithReuseIdentifier: ClusterPinView.reuseIdentifier)
        map.setRegion(region, animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(annotationsOn: map, with: listings)
        context.coordinator.sync(selectionOn: map, to: selectedID)
        context.coordinator.sync(userLocationOn: map, to: userCoordinate)
        context.coordinator.apply(region: region, intent: regionIntent, to: map)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ListingMapView
        private var annotationsByID: [UUID: ListingAnnotation] = [:]

        /// True only while `sync(selectionOn:)` is driving MapKit, so the
        /// delegate can tell our own selection changes from a renter's tap.
        /// Without it, switching pins reported a deselect (state mutation from
        /// inside `updateUIView`) and then re-entered `select()`, re-issuing the
        /// fly-to. Delivery is synchronous on iOS 26, so `defer` suffices.
        private var isSyncingSelection = false

        /// The last camera intent applied. Compared by identity rather than by
        /// geometry: see `apply(region:intent:to:)`.
        private var appliedIntent = -1
        private var isApplyingProgrammatically = false

        init(_ parent: ListingMapView) {
            self.parent = parent
        }

        // MARK: - Diffing

        func sync(annotationsOn map: MKMapView, with listings: [Listing]) {
            let incoming = Set(listings.map(\.id))
            let existing = Set(annotationsByID.keys)
            guard incoming != existing else { return }

            let removedIDs = existing.subtracting(incoming)
            if !removedIDs.isEmpty {
                let removed = removedIDs.compactMap { annotationsByID[$0] }
                map.removeAnnotations(removed)
                removedIDs.forEach { annotationsByID[$0] = nil }
            }

            let addedIDs = incoming.subtracting(existing)
            if !addedIDs.isEmpty {
                let added = listings
                    .filter { addedIDs.contains($0.id) }
                    .map { listing -> ListingAnnotation in
                        let annotation = ListingAnnotation(listing: listing)
                        annotationsByID[listing.id] = annotation
                        return annotation
                    }
                map.addAnnotations(added)
            }
        }

        func sync(selectionOn map: MKMapView, to id: UUID?) {
            let target = id.flatMap { annotationsByID[$0] }
            let current = map.selectedAnnotations.first as? ListingAnnotation

            if current?.listing.id == target?.listing.id { return }
            isSyncingSelection = true
            defer { isSyncingSelection = false }
            if let current { map.deselectAnnotation(current, animated: true) }
            if let target { map.selectAnnotation(target, animated: true) }
        }

        func sync(userLocationOn map: MKMapView, to coordinate: CLLocationCoordinate2D?) {
            // `showsUserLocation` is only flipped on once the renter has agreed,
            // so MapKit never asks for authorization on our behalf.
            map.showsUserLocation = coordinate != nil
        }

        /// Applied by intent, not by geometry.
        ///
        /// Comparing the requested region to `map.region` cannot work: MapKit
        /// fits a region to the view's aspect ratio, so a square span always
        /// comes back inflated (measured at 0.012 requested, 0.0205 reported).
        /// No tolerance both absorbs that and still detects a real camera move.
        func apply(region: MKCoordinateRegion, intent: Int, to map: MKMapView) {
            guard intent != appliedIntent else { return }
            appliedIntent = intent
            isApplyingProgrammatically = true
            map.setRegion(region, animated: true)
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }   // MapKit's own puck

            if annotation is MKClusterAnnotation {
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: ClusterPinView.reuseIdentifier, for: annotation
                )
            }
            return mapView.dequeueReusableAnnotationView(
                withIdentifier: PricePinView.reuseIdentifier, for: annotation
            )
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard !isSyncingSelection else { return }
            if let cluster = view.annotation as? MKClusterAnnotation {
                // Tapping a cluster zooms to its members rather than selecting
                // an arbitrary one of them.
                mapView.deselectAnnotation(cluster, animated: false)
                let coordinates = cluster.memberAnnotations.map { Coordinate($0.coordinate) }
                if let region = SanFrancisco.region(enclosing: coordinates) {
                    // A renter-initiated move, so it is applied here and written
                    // back without going through the intent counter.
                    isApplyingProgrammatically = true
                    mapView.setRegion(region, animated: true)
                    parent.region = region
                }
                return
            }
            guard let annotation = view.annotation as? ListingAnnotation else { return }
            parent.onSelect(annotation.listing)
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard !isSyncingSelection else { return }
            guard view.annotation is ListingAnnotation else { return }
            guard mapView.selectedAnnotations.isEmpty else { return }
            parent.onDeselect()
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Only a genuine pan or zoom writes back. Echoing our own
            // programmatic move used to overwrite the store with MapKit's
            // aspect-fitted region, which destroyed an 0.012 span request and
            // stored 0.2139 instead.
            if isApplyingProgrammatically {
                isApplyingProgrammatically = false
                return
            }
            parent.region = mapView.region
        }
    }
}
#endif
