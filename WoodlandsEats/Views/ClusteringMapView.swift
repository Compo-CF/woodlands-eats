import SwiftUI
import MapKit
import UIKit

/// `MKMapView` wrapped for SwiftUI with native pin clustering.
///
/// At 1,854 restaurants, the previous SwiftUI `Map` rendered every pin
/// at every zoom — performance was acceptable but the visual was a wall
/// of dots. This wrapper hands pin layout to MapKit, which groups nearby
/// pins into a single cluster badge with a count and resolves them when
/// the user zooms in.
///
/// Per-pin tint reflects the user's tier (gray for unranked). Tap a pin
/// to select it; tap a cluster to zoom into its bounds.
struct ClusteringMapView: UIViewRepresentable {
    let restaurants: [Restaurant]
    /// Resolves a restaurant's UIColor based on the user's current tier.
    /// Caller passes a closure so this view stays free of TierListStore.
    let tierColor: (UUID) -> UIColor
    @Binding var selected: Restaurant?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll   // hide Apple POIs so our pins read clean
        map.register(RestaurantAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: RestaurantAnnotationView.reuseID)
        map.register(MKMarkerAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier:
                        MKMapViewDefaultClusterAnnotationViewReuseIdentifier)

        // UIKit-native location + compass buttons (replaces the SwiftUI
        // .mapControls modifier that lived on the old Map view).
        let locButton = MKUserTrackingButton(mapView: map)
        locButton.translatesAutoresizingMaskIntoConstraints = false
        locButton.layer.cornerRadius = 6
        locButton.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        map.addSubview(locButton)

        let compass = MKCompassButton(mapView: map)
        compass.compassVisibility = .visible
        compass.translatesAutoresizingMaskIntoConstraints = false
        map.addSubview(compass)

        NSLayoutConstraint.activate([
            locButton.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: 72),
            locButton.trailingAnchor.constraint(equalTo: map.trailingAnchor, constant: -8),
            compass.topAnchor.constraint(equalTo: locButton.bottomAnchor, constant: 8),
            compass.trailingAnchor.constraint(equalTo: locButton.trailingAnchor),
        ])

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator

        // Diff annotations: remove ones no longer in the filtered set, add new ones.
        let current = map.annotations.compactMap { $0 as? RestaurantAnnotation }
        let desiredByID = Dictionary(uniqueKeysWithValues: restaurants.map { ($0.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.restaurant.id, $0) })

        let toRemove = current.filter { desiredByID[$0.restaurant.id] == nil }
        if !toRemove.isEmpty { map.removeAnnotations(toRemove) }

        let toAdd = restaurants
            .filter { currentByID[$0.id] == nil }
            .map { RestaurantAnnotation(restaurant: $0, tierColor: tierColor($0.id)) }
        if !toAdd.isEmpty { map.addAnnotations(toAdd) }

        // Refresh tier color on already-present pins (the user may have
        // ranked / unranked something while the map was on screen).
        for ann in current {
            guard desiredByID[ann.restaurant.id] != nil else { continue }
            let newColor = tierColor(ann.restaurant.id)
            if ann.tierColor != newColor {
                ann.tierColor = newColor
                if let view = map.view(for: ann) as? RestaurantAnnotationView {
                    view.markerTintColor = newColor
                }
            }
        }

        // One-shot fit-to-annotations on first load so the map frames the seed
        // rather than starting at a hardcoded region.
        if !coordinator.didInitialFit && !restaurants.isEmpty {
            coordinator.didInitialFit = true
            map.showAnnotations(map.annotations.filter { !($0 is MKUserLocation) },
                                animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: ClusteringMapView
        var didInitialFit = false
        init(_ parent: ClusteringMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }   // system default blue dot
            if let ann = annotation as? RestaurantAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: RestaurantAnnotationView.reuseID,
                    for: ann) as! RestaurantAnnotationView
                view.markerTintColor = ann.tierColor
                view.glyphImage = UIImage(systemName: "fork.knife")
                view.clusteringIdentifier = "restaurant"
                return view
            }
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: cluster) as! MKMarkerAnnotationView
                view.markerTintColor = .label
                view.glyphText = "\(cluster.memberAnnotations.count)"
                return view
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let ann = view.annotation as? RestaurantAnnotation {
                parent.selected = ann.restaurant
                mapView.deselectAnnotation(ann, animated: false)
            } else if let cluster = view.annotation as? MKClusterAnnotation {
                // Cluster tap: zoom in so the cluster expands. Use 0.4x of
                // the current span so we descend gradually rather than
                // snapping to the cluster's tight bounding box.
                let region = MKCoordinateRegion(
                    center: cluster.coordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: mapView.region.span.latitudeDelta * 0.4,
                        longitudeDelta: mapView.region.span.longitudeDelta * 0.4))
                mapView.setRegion(region, animated: true)
                mapView.deselectAnnotation(cluster, animated: false)
            }
        }
    }
}

/// MKAnnotation backing a single restaurant pin. The tier color is stored
/// alongside so the view layer can re-tint without bouncing through the
/// TierListStore.
final class RestaurantAnnotation: NSObject, MKAnnotation {
    let restaurant: Restaurant
    var tierColor: UIColor
    var coordinate: CLLocationCoordinate2D { restaurant.coordinate }
    var title: String? { restaurant.name }

    init(restaurant: Restaurant, tierColor: UIColor) {
        self.restaurant = restaurant
        self.tierColor = tierColor
    }
}

/// Marker annotation view that participates in clustering. The reuse
/// identifier is shared with the registration in `makeUIView`.
final class RestaurantAnnotationView: MKMarkerAnnotationView {
    static let reuseID = "restaurant"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "restaurant"
        // The default `.rectangle` collision mode uses the marker's full
        // bounding box, which is generous and forces users to zoom in further
        // than necessary before pins separate. `.circle` inscribes a circle
        // into that box (~21% less area), so diagonal neighbors stop colliding
        // at a wider zoom and uncluster sooner.
        collisionMode = .circle
    }
    required init?(coder aDecoder: NSCoder) { fatalError("not implemented") }
}
