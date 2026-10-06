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
    /// Standard / Satellite / Hybrid. Persisted by the parent via
    /// @AppStorage so the user's choice survives launches.
    let mapType: MKMapType
    @Binding var selected: Restaurant?
    /// Called when the user taps a cluster that's already so zoomed-in
    /// that more zooming won't separate it (multiple restaurants at the
    /// same address, e.g. food halls or strip malls). The parent shows a
    /// ClusterListSheet so the user can still pick an individual entry.
    let onClusterAtMaxZoom: ([Restaurant]) -> Void

    /// Threshold below which "tap a cluster" stops zooming and falls back
    /// to the list sheet. 0.003 latitude span ~ 330 meters visible, which
    /// is roughly Apple's max-zoom on iPhone. Below this, two pins at the
    /// same address still collide and zoom-in does nothing.
    private static let maxZoomLatitudeDelta = 0.003

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        // v2.7: a muted standard map (no loud green/POIs) so the tier pins are
        // the only color on screen — reads far more "designed" than the default.
        map.preferredConfiguration = Self.configuration(for: mapType)
        context.coordinator.appliedMapType = mapType
        map.register(RestaurantAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: RestaurantAnnotationView.reuseID)
        map.register(ClusterAnnotationView.self,
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

        // Apply the current map style if it's changed (muted standard /
        // imagery / hybrid), tracked via the coordinator so we don't rebuild
        // the configuration on every SwiftUI update.
        if coordinator.appliedMapType != mapType {
            coordinator.appliedMapType = mapType
            map.preferredConfiguration = Self.configuration(for: mapType)
        }

        // Diff annotations: remove ones no longer in the filtered set, add new ones.
        // NOTE: `uniquingKeysWith` rather than `uniqueKeysWithValues` is critical —
        // build 33 crashed at first map mount because the re-seeded Restaurants.json
        // contained 3 duplicate UUIDs (similar-name variants the seed dedup missed,
        // e.g. "BLEND - Bourbons & Cocktails" vs "BLEND - Bourbons and Cocktails").
        // `uniqueKeysWithValues` traps on duplicate keys with EXC_BREAKPOINT;
        // `uniquingKeysWith` keeps the last value silently. Last-wins is fine here
        // — duplicate restaurants render as a single pin either way.
        let current = map.annotations.compactMap { $0 as? RestaurantAnnotation }
        let desiredByID = Dictionary(restaurants.map { ($0.id, $0) },
                                     uniquingKeysWith: { _, latest in latest })
        let currentByID = Dictionary(current.map { ($0.restaurant.id, $0) },
                                     uniquingKeysWith: { _, latest in latest })

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

    /// Translate the persisted MKMapType into a modern MKMapConfiguration.
    /// Standard uses the muted emphasis + POIs hidden so our tier pins are the
    /// only thing with color; satellite/hybrid keep imagery.
    static func configuration(for type: MKMapType) -> MKMapConfiguration {
        switch type {
        case .satellite, .satelliteFlyover:
            return MKImageryMapConfiguration(elevationStyle: .flat)
        case .hybrid, .hybridFlyover:
            let c = MKHybridMapConfiguration(elevationStyle: .flat)
            c.pointOfInterestFilter = .excludingAll
            return c
        default:
            let c = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            c.pointOfInterestFilter = .excludingAll
            return c
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: ClusteringMapView
        var didInitialFit = false
        /// The map type currently applied as a configuration, so updateUIView
        /// only rebuilds the configuration when the user actually switches it.
        var appliedMapType: MKMapType?
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
                // v2.7: custom circular badge (see ClusterAnnotationView) instead
                // of the default black marker balloon — prepareForDisplay sizes
                // and labels it from the member count.
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: cluster)
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let ann = view.annotation as? RestaurantAnnotation {
                parent.selected = ann.restaurant
                mapView.deselectAnnotation(ann, animated: false)
            } else if let cluster = view.annotation as? MKClusterAnnotation {
                let currentSpan = mapView.region.span.latitudeDelta
                if currentSpan > ClusteringMapView.maxZoomLatitudeDelta {
                    // Still room to zoom — descend toward the cluster.
                    // 0.4x per tap so we don't snap to a too-tight bounding
                    // box.
                    let region = MKCoordinateRegion(
                        center: cluster.coordinate,
                        span: MKCoordinateSpan(
                            latitudeDelta: currentSpan * 0.4,
                            longitudeDelta: mapView.region.span.longitudeDelta * 0.4))
                    mapView.setRegion(region, animated: true)
                } else {
                    // Already as zoomed-in as MKMapView gets. More zooming
                    // won't separate the pins (same address / strip mall).
                    // Hand the cluster's members back to the parent so it
                    // can show a list picker — Apple Maps does the same.
                    let restaurants = cluster.memberAnnotations.compactMap {
                        ($0 as? RestaurantAnnotation)?.restaurant
                    }
                    if !restaurants.isEmpty {
                        parent.onClusterAtMaxZoom(restaurants)
                    }
                }
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

/// v2.7: a flat circular cluster badge — brand purple fill, white count, thin
/// white ring + soft shadow — replacing the default black marker balloon. Sized
/// by member count so dense areas read heavier. Much more "designed" than the
/// stock cluster and keeps the muted map uncluttered.
final class ClusterAnnotationView: MKAnnotationView {
    /// Brand accent (matches Color.nightOut).
    private static let fill = UIColor(red: 0.42, green: 0.36, blue: 0.96, alpha: 1)

    private let circle = UIView()
    private let countLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        collisionMode = .circle
        backgroundColor = .clear

        circle.backgroundColor = Self.fill
        circle.layer.borderColor = UIColor.white.cgColor
        circle.layer.borderWidth = 2
        circle.layer.shadowColor = UIColor.black.cgColor
        circle.layer.shadowOpacity = 0.22
        circle.layer.shadowRadius = 3
        circle.layer.shadowOffset = CGSize(width: 0, height: 1)
        circle.isUserInteractionEnabled = false
        addSubview(circle)

        countLabel.textColor = .white
        countLabel.textAlignment = .center
        countLabel.isUserInteractionEnabled = false
        addSubview(countLabel)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let count = cluster.memberAnnotations.count
        countLabel.text = count > 999 ? "999+" : "\(count)"

        // IMPORTANT: the annotation view's own bounds stay FIXED. Resizing
        // `self` here would change the collision footprint MapKit uses for
        // clustering → it re-clusters → the count changes → it resizes again,
        // an endless shift-and-recount loop (the v2.7 jitter bug). Only the
        // inner circle scales with density, inside a constant 60pt box.
        let box: CGFloat = 60
        bounds = CGRect(x: 0, y: 0, width: box, height: box)
        let d: CGFloat = count < 10 ? 38 : count < 50 ? 44 : count < 200 ? 48 : 52
        circle.frame = CGRect(x: (box - d) / 2, y: (box - d) / 2, width: d, height: d)
        circle.layer.cornerRadius = d / 2
        countLabel.frame = circle.frame
        countLabel.font = .systemFont(ofSize: count > 99 ? 12 : 14, weight: .bold)
        centerOffset = .zero
    }
}
