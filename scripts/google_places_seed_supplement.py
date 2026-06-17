"""Targeted supplementary Google Places seed for the v1.2 polygon strip
that the previous run missed: downtown Magnolia, Pinehurst, Lake Conroe,
and the top of Montgomery County reach.

Why this exists: the v1.2 re-seed on Mac was run against an older
service_area.py (probably from main, not v1.2) whose bbox ended at
~lon -95.65 W and ~lat 30.39 N. The current polygon extends to
lon -95.82 W (downtown Magnolia is at -95.75) and lat 30.444 N. The
existing seed therefore has ZERO restaurants in:

  - Downtown Magnolia (30.21, -95.75) — empty within 4 mi
  - Pinehurst proper (30.16, -95.69) — only 2 entries
  - Lake Conroe / NW Montgomery County (lat > 30.39)

This script does NOT re-pull the already-covered geography. It only
queries the new west + north strips. Cost: ~$3-5 (vs ~$30-60 for a
full re-run).

Strategy:
  - 14 text queries targeted at downtown Magnolia, Pinehurst, Lake
    Conroe State Park, Montgomery TX, etc.
  - 5x10 nearby grid covering just the western strip
    (lon -95.82 to -95.65, lat 30.02 to 30.44).
  - 8x1 nearby grid covering the northern strip
    (lat 30.39 to 30.44, lon -95.65 to -95.36).
  - Dedup against existing entries.
  - Sort + write back to Restaurants.json.

Run:
  export GOOGLE_PLACES_API_KEY="..."
  python3 scripts/google_places_seed_supplement.py
"""
import os, sys, json, re, math, time, uuid, urllib.request

SEED = "WoodlandsEats/Resources/Restaurants.json"
KEY = os.environ.get("GOOGLE_PLACES_API_KEY")
if not KEY:
    sys.exit("Set the GOOGLE_PLACES_API_KEY env var first.")

# Reuse the canonical service-area polygon. contains() drops any hit
# outside the polygon (Google text queries sometimes return spots from
# adjacent cities — Tomball, Cypress, Huntsville).
from service_area import contains  # noqa: F401

NS = uuid.NAMESPACE_URL

# Same centroid set as google_places_seed.py — keep in sync.
CENTROIDS = {
    "woodlands": (30.170, -95.490), "shenandoah": (30.178, -95.453),
    "oakRidgeNorth": (30.150, -95.447), "oldTownSpring": (30.061, -95.416),
    "klein": (30.020, -95.520), "spring": (30.085, -95.400),
    "conroe": (30.310, -95.460), "magnolia": (30.160, -95.660),
    "atascocita": (30.115, -95.370), "montgomery": (30.390, -95.690),
}

# Targeted text queries — every one is aimed at the west or north strip.
TEXT_QUERIES = [
    # Downtown Magnolia / Pinehurst
    "restaurants in downtown Magnolia TX",
    "restaurants in Magnolia TX 77354",
    "restaurants in Magnolia TX 77355",
    "restaurants in Pinehurst TX",
    "places to eat Magnolia TX",
    "dining Magnolia TX",
    "FM 1488 Magnolia restaurants",
    "FM 1774 Magnolia restaurants",
    "Magnolia town center restaurants",
    # Montgomery / Lake Conroe
    "restaurants in Montgomery TX 77316",
    "restaurants in Montgomery TX 77356",
    "Lake Conroe restaurants",
    "Lake Conroe State Park dining",
    "Montgomery TX downtown restaurants",
    "Hwy 105 Montgomery restaurants",
    # Generic NW County
    "restaurants in northwest Montgomery County TX",
]

FIELDS = ",".join([
    "places.id", "places.displayName", "places.location",
    "places.formattedAddress", "places.types", "places.primaryType",
    "places.priceLevel", "places.websiteUri", "places.nationalPhoneNumber",
    "places.editorialSummary", "places.businessStatus",
])

FIELDS_NEARBY = FIELDS

# Same set used by the main seed (kept in sync — see google_places_seed.py).
NEARBY_TYPES = [
    "restaurant", "fast_food_restaurant", "cafe", "bar", "bakery",
    "ice_cream_shop", "meal_takeaway", "meal_delivery",
    "sandwich_shop", "coffee_shop", "donut_shop",
    "ramen_restaurant", "sushi_restaurant", "pizza_restaurant",
    "mexican_restaurant", "italian_restaurant", "chinese_restaurant",
    "japanese_restaurant", "thai_restaurant", "vietnamese_restaurant",
    "korean_restaurant", "indian_restaurant", "mediterranean_restaurant",
    "american_restaurant", "seafood_restaurant", "steak_house",
    "barbecue_restaurant", "brazilian_restaurant", "french_restaurant",
    "greek_restaurant", "spanish_restaurant", "turkish_restaurant",
    "vegan_restaurant", "vegetarian_restaurant", "brunch_restaurant",
    "breakfast_restaurant", "hamburger_restaurant", "chicken_shop",
]

NEARBY_RADIUS_M = 1500

# --- Targeted grids -----------------------------------------------------------
# West strip: lon -95.82 to -95.65 (the new area beyond the old western edge)
# Lat 30.02 to 30.44.
def _strip(lat_min, lat_max, lon_min, lon_max, n_lat, n_lon):
    lats = [lat_min + (lat_max - lat_min) * (i + 0.5) / n_lat for i in range(n_lat)]
    lons = [lon_min + (lon_max - lon_min) * (i + 0.5) / n_lon for i in range(n_lon)]
    return [(la, lo) for la in lats for lo in lons]

WEST_CENTERS = _strip(30.02, 30.44, -95.82, -95.65, 10, 5)
NORTH_CENTERS = _strip(30.39, 30.444, -95.65, -95.36, 2, 8)
NEARBY_CENTERS = [(la, lo) for (la, lo) in (WEST_CENTERS + NORTH_CENTERS) if contains(la, lo)]


# --- Shared helpers (copied from google_places_seed.py, kept minimal) ---------

NAME_STOP = {"the", "&", "and", "of", "co", "inc", "llc", "restaurant", "cafe", "tx",
             "texas", "ltd", "company", "co.", "no.", "no", "store"}


def norm(s):
    n = re.sub(r"[^a-z0-9]", "", s.lower())
    for w in NAME_STOP:
        n = n.replace(w, "")
    return n


def haversine_mi(a, b, c, d):
    R = 3958.8
    p1, p2 = math.radians(a), math.radians(c)
    dp, dl = math.radians(c - a), math.radians(d - b)
    h = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2 * R * math.asin(math.sqrt(h))


def assign_area(lat, lon):
    if haversine_mi(lat, lon, *CENTROIDS["oldTownSpring"]) < 0.6:
        return "oldTownSpring"
    cands = {k: v for k, v in CENTROIDS.items() if k != "oldTownSpring"}
    return min(cands, key=lambda k: haversine_mi(lat, lon, *cands[k]))


PRICE_MAP = {
    "PRICE_LEVEL_FREE": "$", "PRICE_LEVEL_INEXPENSIVE": "$",
    "PRICE_LEVEL_MODERATE": "$$", "PRICE_LEVEL_EXPENSIVE": "$$$",
    "PRICE_LEVEL_VERY_EXPENSIVE": "$$$$",
}

CUISINE_FROM_TYPE = {
    "italian_restaurant": "italian", "pizza_restaurant": "pizza",
    "mexican_restaurant": "mexican", "chinese_restaurant": "chinese",
    "japanese_restaurant": "japanese", "thai_restaurant": "thai",
    "vietnamese_restaurant": "vietnamese", "korean_restaurant": "korean",
    "indian_restaurant": "indian", "mediterranean_restaurant": "mediterranean",
    "american_restaurant": "american", "seafood_restaurant": "seafood",
    "steak_house": "steakhouse", "sushi_restaurant": "sushi",
    "barbecue_restaurant": "bbq", "brazilian_restaurant": "latin",
    "french_restaurant": "french", "vegan_restaurant": "healthy",
    "vegetarian_restaurant": "healthy", "brunch_restaurant": "breakfastBrunch",
    "breakfast_restaurant": "breakfastBrunch", "hamburger_restaurant": "burgers",
    "chicken_shop": "american", "bakery": "cafeBakery", "cafe": "cafeBakery",
    "coffee_shop": "cafeBakery", "donut_shop": "dessert",
    "ice_cream_shop": "dessert", "sandwich_shop": "american",
    "ramen_restaurant": "japanese", "fast_food_restaurant": "american",
}

FAST_FOOD_TYPES = {
    "fast_food_restaurant", "sandwich_shop", "hamburger_restaurant",
    "chicken_shop", "donut_shop", "meal_takeaway",
}


def map_place(p):
    name = (p.get("displayName") or {}).get("text", "").strip()
    loc = p.get("location") or {}
    lat, lon = loc.get("latitude"), loc.get("longitude")
    if not (name and lat and lon):
        return None
    if not contains(lat, lon):
        return None
    if p.get("businessStatus") in ("CLOSED_PERMANENTLY", "CLOSED_TEMPORARILY"):
        return None

    types = set((p.get("types") or []) + [p.get("primaryType") or ""])
    cuisines = []
    for t in types:
        c = CUISINE_FROM_TYPE.get(t)
        if c and c not in cuisines:
            cuisines.append(c)
    if not cuisines:
        cuisines = ["other"]

    is_fast_food = any(t in FAST_FOOD_TYPES for t in types)
    price = PRICE_MAP.get(p.get("priceLevel"), "$$")
    desc = (p.get("editorialSummary") or {}).get("text") or \
           f"Sourced from Google Places ({assign_area(lat, lon)})."

    return {
        "google_id": p.get("id"),
        "name": name,
        "latitude": float(lat),
        "longitude": float(lon),
        "area": assign_area(lat, lon),
        "address": p.get("formattedAddress") or "",
        "cuisines": cuisines,
        "priceTier": price,
        "isFastFood": is_fast_food,
        "website": p.get("websiteUri"),
        "phone": p.get("nationalPhoneNumber"),
        "description": desc,
        "signatureDishes": [],
    }


def _post(url, body, fields):
    req = urllib.request.Request(
        url, data=json.dumps(body).encode(),
        headers={
            "Content-Type": "application/json",
            "X-Goog-Api-Key": KEY,
            "X-Goog-FieldMask": fields,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def places_text(query, page_token=None):
    body = {"textQuery": query}
    if page_token:
        body["pageToken"] = page_token
    return _post("https://places.googleapis.com/v1/places:searchText", body, FIELDS)


def places_nearby(lat, lon):
    body = {
        "includedTypes": NEARBY_TYPES,
        "maxResultCount": 20,
        "locationRestriction": {
            "circle": {"center": {"latitude": lat, "longitude": lon}, "radius": NEARBY_RADIUS_M}
        },
    }
    return _post("https://places.googleapis.com/v1/places:searchNearby", body, FIELDS_NEARBY)


def fmt_coord(x):
    return f"{x:.5f}".rstrip("0").rstrip(".")


def serialize(doc):
    KEYS = ["id", "name", "latitude", "longitude", "area", "address", "cuisines",
            "priceTier", "isFastFood", "website", "phone", "description", "signatureDishes"]
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


def is_duplicate(name_norm, lat, lon, existing):
    if len(name_norm) < 3:
        return True
    for (en, elat, elon) in existing:
        if len(en) < 3:
            continue
        d = haversine_mi(lat, lon, elat, elon)
        if name_norm == en:
            if d < 0.08:
                return True
        elif name_norm in en or en in name_norm:
            if d < 0.5:
                return True
    return False


def main():
    seen, places = set(), []
    calls = 0

    print(f"Targeted supplementary seed for v1.2 west + north strips")
    print(f"  - {len(TEXT_QUERIES)} text queries (~{len(TEXT_QUERIES)*3} calls max)")
    print(f"  - {len(NEARBY_CENTERS)} nearby cells inside polygon (1500m radius each)")
    print(f"  - Total max calls: ~{len(TEXT_QUERIES)*3 + len(NEARBY_CENTERS)}")
    print()

    # 1. Text queries
    print(f"Running text queries...")
    for i, q in enumerate(TEXT_QUERIES):
        token = None
        for _ in range(3):
            try:
                resp = places_text(q, token)
                calls += 1
            except Exception as e:
                print(f"  text [{q}] failed: {e}")
                break
            for p in resp.get("places", []):
                pid = p.get("id")
                if not pid or pid in seen:
                    continue
                seen.add(pid)
                m = map_place(p)
                if m:
                    places.append(m)
            token = resp.get("nextPageToken")
            if not token:
                break
            time.sleep(2)
        time.sleep(0.3)
        print(f"  [{i+1:2d}/{len(TEXT_QUERIES)}] {q!r}  (running total in-box: {len(places)})")

    # 2. Nearby grid (west + north strips)
    print(f"\nRunning nearby grid cells...")
    for i, (lat, lon) in enumerate(NEARBY_CENTERS):
        try:
            resp = places_nearby(lat, lon)
            calls += 1
        except Exception as e:
            print(f"  nearby ({lat:.4f},{lon:.4f}) failed: {e}")
            continue
        for p in resp.get("places", []):
            pid = p.get("id")
            if not pid or pid in seen:
                continue
            seen.add(pid)
            m = map_place(p)
            if m:
                places.append(m)
        time.sleep(0.3)
        if (i + 1) % 10 == 0:
            print(f"  ...{i+1}/{len(NEARBY_CENTERS)} cells done, {len(places)} unique in-box so far")

    print(f"\nMade {calls} API calls. Fetched {len(places)} unique in-box places.")
    est_cost = calls * 0.032
    print(f"  Estimated cost: ~${est_cost:.2f}")

    # 3. Dedup against existing seed
    doc = json.load(open(SEED, encoding="utf-8"))
    existing = [(norm(r["name"]), r["latitude"], r["longitude"]) for r in doc["restaurants"]]
    added, skipped_dup = [], 0
    for p in places:
        nn = norm(p["name"])
        if is_duplicate(nn, p["latitude"], p["longitude"], existing):
            skipped_dup += 1
            continue
        rid = str(uuid.uuid5(NS, f"woodlandseats:google:{p['google_id']}"))
        entry = {k: p.get(k) for k in [
            "name","latitude","longitude","area","address","cuisines","priceTier",
            "isFastFood","website","phone","description","signatureDishes",
        ]}
        entry["id"] = rid
        doc["restaurants"].append(entry)
        existing.append((nn, p["latitude"], p["longitude"]))
        added.append(p)

    doc["restaurants"].sort(key=lambda r: (r["area"], r["name"].lower()))
    tmp = SEED + ".tmp"
    open(tmp, "w", encoding="utf-8").write(serialize(doc))
    os.replace(tmp, SEED)

    print(f"\nAdded {len(added)} | dup-skipped {skipped_dup} | TOTAL {len(doc['restaurants'])}")
    if added:
        from collections import Counter
        by_area = Counter(p["area"] for p in added)
        print("New restaurants by area:")
        for area in sorted(by_area, key=lambda a: -by_area[a]):
            print(f"  +{by_area[area]:3d}  {area}")
        print("\nFirst 40 added:")
        for p in added[:40]:
            print(f"  + [{p['area']:14s}] {p['name']}")
        if len(added) > 40:
            print(f"  ... and {len(added) - 40} more")


if __name__ == "__main__":
    main()
