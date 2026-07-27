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
    /// v1.8 expansion: pushed the southern and eastern edges out to add
    /// Tomball, Cypress, the Champions / FM 1960 corridor, and Kingwood /
    /// Humble. Must stay in lockstep with scripts/service_area.py.
    /// v2.2 expansion: modest edge push to fill the suburban ring —
    /// N up to Willis / N Conroe, W out toward Waller / Hockley, and small
    /// S (Cypress/1960) and E (Kingwood/Porter) nudges. Must stay in
    /// lockstep with scripts/service_area.py.
    static let polygon: [(lat: Double, lon: Double)] = [
        (30.50, -95.92),             // NW — Waller/Magnolia west, N of Montgomery
        (30.19, -95.85),             // W — Magnolia west edge
        (30.06, -95.85),             // W — Hockley / Waller edge
        (29.85, -95.75),             // SW — Cypress south (290 corridor)
        (29.85, -95.55),             // S — Willowbrook / Champions south
        (29.90, -95.38),             // S — FM 1960 east of 45
        (29.93, -95.22),             // SE — Humble south
        (30.00, -95.08),             // E — Kingwood SE corner
        (30.12, -95.08),             // E — Kingwood NE corner
        (30.15, -95.25),             // NE inner — Porter edge
        (30.3198431, -95.3932651),   // NE
        (30.52, -95.46),             // N mid — Willis / N Conroe
        (30.52, -95.64),             // N — top of Montgomery county reach
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
