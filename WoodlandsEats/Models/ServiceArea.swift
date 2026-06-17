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
    ///
    /// v1.2 expansion: pushed the western and northern edges out to cover
    /// Montgomery TX, full Magnolia (downtown + west), Pinehurst, and
    /// Lake Conroe State Park area. Roughly 2x the v1.1 polygon area.
    static let polygon: [(lat: Double, lon: Double)] = [
        (30.4181863, -95.8203585),   // NW — far west of Magnolia, NW of Montgomery
        (30.1892862, -95.7824814),   // W — covers Magnolia downtown
        (30.1252361, -95.6967624),   // W south — Pinehurst area
        (30.0783069, -95.6507571),   // W mid-south — Tomball edge
        (30.0230324, -95.55806),     // S middle-west (unchanged)
        (30.026005, -95.3596195),    // SE — slight smoothing vs v1.1
        (30.0806836, -95.3712924),   // E south
        (30.1240483, -95.3678592),   // E — Atascocita / Kingwood edge
        (30.3198431, -95.3932651),   // NE
        (30.4418687, -95.4420169),   // N mid — over Lake Conroe / NW Conroe
        (30.443753, -95.5940047),    // N — top of Montgomery county reach
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
