"""scripts/retag_areas.py

Re-assign a restaurant's `area` field ONLY IF its nearest centroid is one
of the three new areas (Conroe / Magnolia / Atascocita) added in build 33.
Restaurants whose nearest centroid is still one of the original six are
left alone — their existing area string came from address-city parsing
during the seed run, which is more authoritative than nearest-centroid.

Why this asymmetric approach: nearest-centroid is a clumsy fallback. For
the original six areas (which had address-based tagging from the start),
applying nearest-centroid would shuffle hundreds of restaurants between
Spring / Old Town Spring / Klein based on geometry rather than what their
actual postal address says. We only use centroid logic to RESCUE
restaurants that pre-build-33 had no good home (Conroe / Magnolia /
Atascocita didn't exist as areas yet, so they got auto-tagged to whatever
old area was nearest).

Idempotent; safe to re-run.

Run:
  python3 scripts/retag_areas.py            # writes the seed
  python3 scripts/retag_areas.py --dry-run  # report only
"""
import json, math, os, sys

SEED = "WoodlandsEats/Resources/Restaurants.json"
KEYS = ["id", "name", "latitude", "longitude", "area", "address", "cuisines",
        "priceTier", "isFastFood", "website", "phone", "description",
        "signatureDishes", "reservable", "delivery", "takeout", "dineIn"]

# (area_key, lat, lon). Mirror of the Area enum in
# WoodlandsEats/Models/Enums.swift. Keep these in sync.
CENTROIDS = [
    ("woodlands",      30.170, -95.490),
    ("spring",         30.085, -95.400),
    ("shenandoah",     30.178, -95.453),
    ("oakRidgeNorth",  30.150, -95.447),
    ("oldTownSpring",  30.061, -95.416),
    ("klein",          30.020, -95.520),
    # Build 33 additions:
    ("conroe",         30.310, -95.460),
    ("magnolia",       30.160, -95.660),
    ("atascocita",     30.115, -95.370),
    # v1.2 (build 39+) addition for the expanded NW polygon:
    ("montgomery",     30.390, -95.690),   # downtown Montgomery TX
    # v1.8 southern/eastern expansion:
    ("tomball",        30.097, -95.616),
    ("cypress",        29.972, -95.697),
    ("champions",      29.990, -95.525),   # Champions Forest / FM 1960 W
    ("kingwood",       30.054, -95.185),
]


def haversine_mi(lat1, lon1, lat2, lon2):
    R = 3958.8  # earth radius in miles
    p1 = math.radians(lat1); p2 = math.radians(lat2)
    dlat = math.radians(lat2 - lat1); dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlon / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


# Only retag restaurants whose nearest centroid is one of these new areas.
# Existing assignments to the original six are preserved. (Conroe / Magnolia /
# Atascocita already had a retag pass in build 33; rerunning is idempotent.
# Montgomery is the v1.2 new area — its centroid is far enough from the
# others that adding it here won't re-disturb the previous re-tag pass.)
# v1.8: tomball/cypress/champions/kingwood join the retag-eligible set.
# Also rescues the pre-existing mislabels (e.g. 'Crust Pizza Co. -
# Tomball' tagged magnolia because tomball didn't exist as an area yet).
NEW_AREAS = {"conroe", "magnolia", "atascocita", "montgomery",
             "tomball", "cypress", "champions", "kingwood"}


def nearest_area(lat, lon):
    best, best_d = None, float("inf")
    for area, clat, clon in CENTROIDS:
        d = haversine_mi(lat, lon, clat, clon)
        if d < best_d:
            best, best_d = area, d
    return best


def fmt_coord(x):
    return f"{x:.5f}".rstrip("0").rstrip(".")


def serialize(doc):
    """Same line-per-field format the other scripts use, so diffs stay readable."""
    out = ["{", '  "restaurants": [']
    rs = doc["restaurants"]
    for i, r in enumerate(rs):
        out.append("    {")
        present = [k for k in KEYS if k in r]
        for j, k in enumerate(present):
            v = r[k]
            sval = fmt_coord(v) if k in ("latitude", "longitude") else json.dumps(v, ensure_ascii=False)
            out.append(f'      "{k}": {sval}' + ("," if j < len(present) - 1 else ""))
        out.append("    }" + ("," if i < len(rs) - 1 else ""))
    out += ["  ]", "}"]
    return "\n".join(out) + "\n"


def main():
    dry_run = "--dry-run" in sys.argv
    doc = json.load(open(SEED, encoding="utf-8"))
    rs = doc["restaurants"]
    total = len(rs)
    print(f"Loaded {total} restaurants from {SEED}")
    if dry_run:
        print("DRY RUN — no changes will be written\n")
    else:
        print()

    moved = 0
    before_counts = {}
    after_counts = {}
    moves = {}   # (from -> to) -> count

    for r in rs:
        before = r.get("area", "?")
        before_counts[before] = before_counts.get(before, 0) + 1
        nearest = nearest_area(r["latitude"], r["longitude"])
        # Only retag if the nearest centroid is one of the NEW areas — we
        # trust the original address-based area tags for the original six.
        new = nearest if nearest in NEW_AREAS else before
        after_counts[new] = after_counts.get(new, 0) + 1
        if before != new:
            moved += 1
            key = f"{before} -> {new}"
            moves[key] = moves.get(key, 0) + 1
            if not dry_run:
                r["area"] = new

    if not dry_run:
        tmp = SEED + ".tmp"
        open(tmp, "w", encoding="utf-8").write(serialize(doc))
        os.replace(tmp, SEED)

    verb = "Would move" if dry_run else "Moved"
    print(f"{verb} {moved} of {total} restaurants ({moved * 100 // total}%)\n")

    print("Before:")
    for area in sorted(before_counts, key=lambda a: -before_counts[a]):
        print(f"  {before_counts[area]:4d}  {area}")

    print("\nAfter:")
    for area in sorted(after_counts, key=lambda a: -after_counts[a]):
        delta = after_counts[area] - before_counts.get(area, 0)
        sign = "+" if delta > 0 else ("" if delta == 0 else "")
        delta_str = f" ({sign}{delta:+d})" if delta else ""
        print(f"  {after_counts[area]:4d}  {area}{delta_str}")

    if moves:
        print("\nTop transitions:")
        for k in sorted(moves, key=lambda m: -moves[m])[:15]:
            print(f"  {moves[k]:4d}  {k}")


if __name__ == "__main__":
    main()
