"""
scripts/service_area.py

Canonical service-area definition for S-Tier Eats. Python twin of
WoodlandsEats/Models/ServiceArea.swift -- the polygon vertices below
MUST match the ones in the Swift file. They came from a single Google
My Maps export and should always move together. If the two diverge,
admin approval (Swift) and seed coverage (Python) drift apart and
restaurants in newly added areas silently get the wrong treatment.

Re-export workflow:
  1. Edit the polygon in Google My Maps
  2. Export the layer as KML
  3. Paste vertices into BOTH this file and ServiceArea.swift
  4. Re-run google_places_seed.py to populate the new area

Exports:
  POLYGON          -- list of (lat, lon) tuples in draw order
  LAT_MIN, LAT_MAX -- bounding-box latitude edges
  LON_MIN, LON_MAX -- bounding-box longitude edges
  contains(lat, lon) -> bool   point-in-polygon ray-casting test
  bounding_box() -> tuple      (lat_min, lat_max, lon_min, lon_max)

Legacy scripts that used to hardcode LAT_MIN/LAT_MAX/LON_MIN/LON_MAX
as rectangle edges can now `from service_area import *` to pick up
the same names without code change, AND switch their rectangle-check
to `contains(lat, lon)` for polygon-accurate filtering.
"""

POLYGON = [
    # (lat, lon) in draw order -- closes implicitly to the first point.
    # v1.2: expanded west + north to cover Montgomery, full Magnolia,
    # Pinehurst, and Lake Conroe State Park area. ~2x the v1.1 area.
    # v1.8: expanded SOUTH + EAST to add Tomball, Cypress, the
    # Champions / FM 1960 corridor, and Kingwood / Humble.
    # v2.2: modest edge expansion to fill the suburban ring -- pushed the
    # N edge up to Willis / N Conroe (~30.52), the W edge out toward
    # Waller / Hockley (~-95.92), and nudged the S and E edges out a touch
    # (Cypress/1960 south ~29.85, Kingwood/Porter east ~-95.08).
    (30.50, -95.92),             # NW -- Waller/Magnolia west, N of Montgomery
    (30.19, -95.85),             # W -- Magnolia west edge
    (30.06, -95.85),             # W -- Hockley / Waller edge
    (29.85, -95.75),             # SW -- Cypress south (290 corridor)
    (29.85, -95.55),             # S -- Willowbrook / Champions south
    (29.90, -95.38),             # S -- FM 1960 east of 45
    (29.93, -95.22),             # SE -- Humble south
    (30.00, -95.08),             # E -- Kingwood SE corner
    (30.12, -95.08),             # E -- Kingwood NE corner
    (30.15, -95.25),             # NE inner -- Porter edge
    (30.3198431, -95.3932651),   # NE
    (30.52, -95.46),             # N mid -- Willis / N Conroe
    (30.52, -95.64),             # N -- top of Montgomery county reach
]


def bounding_box():
    """Returns (lat_min, lat_max, lon_min, lon_max) -- the axis-aligned
    envelope of the polygon."""
    lats = [p[0] for p in POLYGON]
    lons = [p[1] for p in POLYGON]
    return min(lats), max(lats), min(lons), max(lons)


LAT_MIN, LAT_MAX, LON_MIN, LON_MAX = bounding_box()


def contains(lat, lon):
    """Standard ray-casting point-in-polygon. Shoots a horizontal ray
    east from (lat, lon) and counts edge crossings -- odd = inside."""
    inside = False
    n = len(POLYGON)
    j = n - 1
    for i in range(n):
        xi, yi = POLYGON[i][1], POLYGON[i][0]
        xj, yj = POLYGON[j][1], POLYGON[j][0]
        if ((yi > lat) != (yj > lat)) and \
           (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside
