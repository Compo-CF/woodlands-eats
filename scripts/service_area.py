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
    # (lat, lon) in draw order -- closes implicitly to the first point
    (30.3980518, -95.685776),     # NW -- west of Magnolia toward Lake Conroe
    (30.1454267, -95.6596835),    # W mid
    (30.0842485, -95.6356509),    # W south, Tomball/Klein border
    (30.0230324, -95.55806),      # S middle-west
    (30.0069793, -95.385712),     # SE corner, FM 1960 / Champions
    (30.0949426, -95.4083713),    # east notch -- concavity excludes a slice
    (30.1240483, -95.3678592),    # E -- Atascocita / Kingwood edge
    (30.3198431, -95.3932651),    # NE
    (30.3056167, -95.4584964),    # N mid-east
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
