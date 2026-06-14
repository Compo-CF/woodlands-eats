import Foundation
import CoreLocation

/// Geographic bounds of the S-Tier Eats catalog.
///
/// The polygon below is the source of truth for "is this restaurant in our
/// service area?" — both for the iOS app (admin approval of user-submitted
/// suggestions in ProfileView) and for the seed pipeline (filtering Google
/// Places results to the catchment area). The Python twin in
/// `scripts/service_area.py` carries the exact same vertices.
///
/// The vertices were drawn in Google My Maps and exported as KML, then
/// pasted here. To expand or refine the service area:
///   1. Open the saved layer in Google My Maps
///   2. Edit the polygon
///   3. Export as KML
///   4. Replace the `polygon` array below AND the POLYGON list in
///      scripts/service_area.py — the two must move together or admin
///      approval and seed coverage will drift apart
///
/// Membership is tested via the standard ray-casting point-in-polygon
/// algorithm — O(n) where n is the vertex count (currently 9, so trivial).
enum ServiceArea {
    /// (latitude, longitude) pairs in draw order. The polygon implicitly
    /// closes from the last point back to the first.
    static let polygon: [(lat: Double, lon: Double)] = [
        (30.3980518, -95.685776),     // NW — west of Magnolia toward Lake Conroe
        (30.1454267, -95.6596835),    // W mid
        (30.0842485, -95.6356509),    // W south, Tomball/Klein border
        (30.0230324, -95.55806),      // S middle-west
        (30.0069793, -95.385712),     // SE corner, FM 1960 / Champions
        (30.0949426, -95.4083713),    // east notch — concavity excludes a slice
        (30.1240483, -95.3678592),    // E — Atascocita / Kingwood edge
        (30.3198431, -95.3932651),    // NE
        (30.3056167, -95.4584964),    // N mid-east
    ]

    /// True if (lat, lon) is inside the service-area polygon.
    /// Ray-casting: shoot a horizontal ray east from the test point and
    /// count edge crossings — odd count means inside.
    static func contains(lat: Double, lon: Double) -> Bool {
        var inside = false
        let n = polygon.count
        var j = n - 1
        for i in 0..<n {
            let xi = polygon[i].lon, yi = polygon[i].lat
            let xj = polygon[j].lon, yj = polygon[j].lat
            let intersects = ((yi > lat) != (yj > lat))
                && (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi)
            if intersects { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Axis-aligned bounding box for the polygon. Useful for seed-grid
    /// generation: start with a rectangle of search points covering this
    /// box, then filter through `contains` to drop points outside the
    /// polygon.
    static var boundingBox: (latMin: Double, latMax: Double,
                             lonMin: Double, lonMax: Double) {
        let lats = polygon.map { $0.lat }
        let lons = polygon.map { $0.lon }
        return (lats.min()!, lats.max()!, lons.min()!, lons.max()!)
    }
}
