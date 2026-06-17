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
    (30.4181863, -95.8203585),   # NW -- far west of Magnolia, NW of Montgomery
    (30.1892862, -95.7824814),   # W -- covers Magnolia downtown
    (30.1252361, -95.6967624),   # W south -- Pinehurst area
    (30.0783069, -95.6507571),   # W mid-south -- Tomball edge
    (30.0230324, -95.55806),     # S middle-west (unchanged)
    (30.026005, -95.3596195),    # SE -- slight smoothing vs v1.1
    (30.0806836, -95.3712924),   # E south
    (30.1240483, -95.3678592),   # E -- Atascocita / Kingwood edge
    (30.3198431, -95.3932651),   # NE
    (30.4418687, -95.4420169),   # N mid -- over Lake Conroe / NW Conroe
    (30.443753, -95.5940047),    # N -- top of Montgomery county reach
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
