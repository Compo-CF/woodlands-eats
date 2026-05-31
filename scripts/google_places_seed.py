"""Bulk-add restaurants from Google Places (New API) into Restaurants.json.

Aggressive v2 pass: ~75 text searches (cuisine x area, shopping centers, major
roads) PLUS a 5x5 grid of searchNearby calls covering the whole bounding box,
and tightened name-dedupe that strips area markers so variants like
"Black Walnut - The Woodlands" merge with "Black Walnut Cafe."

Setup (one-time):
  console.cloud.google.com -> project -> enable "Places API (New)" + billing
  -> create API key restricted to Places API (New)

Run:
  export GOOGLE_PLACES_API_KEY="..."
  python3 scripts/google_places_seed.py

Re-runnable: existing entries are dedup-skipped, only genuinely-new spots are
added (deterministic uuid5 from the Google place id).
"""
import os, sys, json, re, math, time, uuid, urllib.request

SEED = "WoodlandsEats/Resources/Restaurants.json"
KEY = os.environ.get("GOOGLE_PLACES_API_KEY")
if not KEY:
    sys.exit("Set the GOOGLE_PLACES_API_KEY env var first.")

LAT_MIN, LAT_MAX = 30.00, 30.21
LON_MIN, LON_MAX = -95.57, -95.35
NS = uuid.NAMESPACE_URL
KEYS = ["id", "name", "latitude", "longitude", "area", "address", "cuisines",
        "priceTier", "isFastFood", "website", "phone", "description", "signatureDishes"]
CENTROIDS = {
    "woodlands": (30.170, -95.490), "shenandoah": (30.178, -95.453),
    "oakRidgeNorth": (30.150, -95.447), "oldTownSpring": (30.061, -95.416),
    "klein": (30.020, -95.520), "spring": (30.085, -95.400),
}

TEXT_QUERIES = [
    # broad area sweeps
    "restaurants in The Woodlands TX", "restaurants in Spring TX",
    "restaurants in Old Town Spring TX", "restaurants in Shenandoah TX",
    "restaurants in Oak Ridge North TX", "restaurants in Klein TX",
    # shopping centers / districts
    "restaurants Market Street The Woodlands", "restaurants Hughes Landing The Woodlands",
    "restaurants Waterway Square The Woodlands", "restaurants Town Center The Woodlands",
    "restaurants Indian Springs Village The Woodlands",
    "restaurants Sterling Ridge Village The Woodlands",
    "restaurants Creekside Park Village Green The Woodlands",
    "restaurants Cochran's Crossing The Woodlands",
    "restaurants Panther Creek The Woodlands",
    "restaurants Grogan's Mill The Woodlands",
    "restaurants Pinecroft Center The Woodlands",
    "restaurants Metropark Square Shenandoah TX",
    "restaurants CityPlace Springwoods Village TX",
    "restaurants Harmony Commons Spring TX",
    # roads / corridors
    "restaurants Six Pines Dr The Woodlands",
    "restaurants Lake Robbins Dr The Woodlands",
    "restaurants Research Forest Dr The Woodlands",
    "restaurants Woodlands Pkwy",
    "restaurants Sawdust Rd Spring TX",
    "restaurants Kuykendahl Rd Spring TX",
    "restaurants Gosling Rd Spring TX",
    "restaurants Cypresswood Dr Spring TX",
    "restaurants Spring Cypress Rd Spring TX",
    "restaurants Stuebner Airline Rd Spring TX",
    "restaurants Louetta Rd Spring TX",
    "restaurants FM 2920 Spring TX",
    "restaurants Champion Forest Dr Spring TX",
    "restaurants Rayford Rd Spring TX",
    # cuisine x area
    "italian restaurants The Woodlands TX", "italian restaurants Spring TX",
    "mexican restaurants The Woodlands TX", "mexican restaurants Spring TX",
    "tex mex The Woodlands TX", "tex mex Spring TX",
    "sushi The Woodlands TX", "sushi Spring TX",
    "chinese restaurants The Woodlands TX", "chinese restaurants Spring TX",
    "japanese restaurants The Woodlands TX",
    "thai restaurants The Woodlands TX", "thai restaurants Spring TX",
    "indian restaurants The Woodlands TX", "indian restaurants Spring TX",
    "vietnamese The Woodlands TX", "vietnamese Spring TX",
    "korean The Woodlands TX", "korean Spring TX",
    "bbq The Woodlands TX", "bbq Spring TX",
    "steakhouse The Woodlands TX", "steakhouse Spring TX",
    "seafood The Woodlands TX", "seafood Spring TX",
    "breakfast The Woodlands TX", "breakfast Spring TX",
    "brunch The Woodlands TX", "brunch Spring TX",
    "pizza The Woodlands TX", "pizza Spring TX",
    "burgers The Woodlands TX", "burgers Spring TX",
    "mediterranean The Woodlands TX", "greek The Woodlands TX",
    "vegan The Woodlands TX", "healthy The Woodlands TX",
    "cafe The Woodlands TX", "cafe Spring TX",
    "bakery The Woodlands TX", "bakery Spring TX",
    "ice cream The Woodlands TX", "dessert The Woodlands TX",
    "wine bar The Woodlands TX", "cocktail bar The Woodlands TX",
    # discovery / signal
    "new restaurants The Woodlands TX", "new restaurants Spring TX",
    "best restaurants The Woodlands TX", "hidden gem restaurants The Woodlands",
    "upscale dining The Woodlands TX",
]

# 5x5 grid of (lat, lon) centers covering the bbox with ~2.4km radius overlap.
NEARBY_CENTERS = [
    (30.021, -95.548), (30.021, -95.504), (30.021, -95.460), (30.021, -95.416), (30.021, -95.372),
    (30.063, -95.548), (30.063, -95.504), (30.063, -95.460), (30.063, -95.416), (30.063, -95.372),
    (30.105, -95.548), (30.105, -95.504), (30.105, -95.460), (30.105, -95.416), (30.105, -95.372),
    (30.147, -95.548), (30.147, -95.504), (30.147, -95.460), (30.147, -95.416), (30.147, -95.372),
    (30.189, -95.548), (30.189, -95.504), (30.189, -95.460), (30.189, -95.416), (30.189, -95.372),
]
NEARBY_RADIUS_M = 2400

NEARBY_TYPES = [
    "restaurant", "fast_food_restaurant", "cafe", "bar", "bakery",
    "ice_cream_shop", "meal_takeaway", "meal_delivery",
]

FIELDS = ",".join([
    "places.id", "places.displayName", "places.formattedAddress", "places.location",
    "places.types", "places.priceLevel", "places.websiteUri", "places.nationalPhoneNumber",
    "nextPageToken",
])
FIELDS_NEARBY = ",".join([
    "places.id", "places.displayName", "places.formattedAddress", "places.location",
    "places.types", "places.priceLevel", "places.websiteUri", "places.nationalPhoneNumber",
])

TYPE_TO_CUISINE = {
    "pizza_restaurant": "pizza", "mexican_restaurant": "mexican",
    "italian_restaurant": "italian", "american_restaurant": "american",
    "chinese_restaurant": "chinese", "japanese_restaurant": "japanese",
    "sushi_restaurant": "sushi", "thai_restaurant": "thai",
    "vietnamese_restaurant": "vietnamese", "korean_restaurant": "korean",
    "indian_restaurant": "indian", "mediterranean_restaurant": "mediterranean",
    "french_restaurant": "french", "seafood_restaurant": "seafood",
    "steak_house": "steakhouse", "barbecue_restaurant": "bbq",
    "hamburger_restaurant": "burgers", "sandwich_shop": "american",
    "bakery": "cafeBakery", "coffee_shop": "cafeBakery",
    "cafe": "cafeBakery", "ice_cream_shop": "dessert",
    "dessert_restaurant": "dessert", "breakfast_restaurant": "breakfastBrunch",
    "brunch_restaurant": "breakfastBrunch", "vegetarian_restaurant": "healthy",
    "vegan_restaurant": "healthy", "ramen_restaurant": "japanese",
    "middle_eastern_restaurant": "mediterranean", "greek_restaurant": "mediterranean",
    "tex_mex_restaurant": "texMex", "fast_food_restaurant": "burgers",
}
PRICE_MAP = {
    "PRICE_LEVEL_INEXPENSIVE": "$", "PRICE_LEVEL_MODERATE": "$$",
    "PRICE_LEVEL_EXPENSIVE": "$$$", "PRICE_LEVEL_VERY_EXPENSIVE": "$$$$",
}
FASTFOOD_DENY = {"mcdonald","burgerking","tacobell","wendy","kfc","subway","sonic",
                 "popeye","arby","jackinthebox","dairyqueen","domino","pizzahut",
                 "littlecaesar","papajohn","deltaco","carlsjr","hardee","churchschicken",
                 "whitecastle","checkers","rallys","quiznos","wienerschnitzel",
                 "longjohnsilver","captainds","krystal","pandaexpress","chickfila"}
QSR_ALLOW = {"whataburger","torchy","chipotle","raisingcane","fiveguys","innout",
             "shakeshack","cava","velvettaco","fuzzy","freebirds","modpizza",
             "jerseymike","pterry","layne","salata","sweetgreen","willie","mooyah",
             "smashburger","culver","portillo","panera","firehouse","jasonsdeli","newk","peiwei"}

# Area / suffix words stripped from names before dedupe, so variants like
# "Black Walnut - The Woodlands" merge with "Black Walnut Cafe".
NAME_STOP = ["thewoodlands", "oldtownspring", "oakridgenorth", "shenandoah",
             "spring", "klein", "woodlands", "tx", "texas", "houston"]


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


def map_place(p):
    pid = p.get("id", "")
    name = (p.get("displayName") or {}).get("text", "").strip()
    addr = p.get("formattedAddress", "").strip()
    loc = p.get("location") or {}
    lat = loc.get("latitude"); lon = loc.get("longitude")
    if not (name and lat is not None and lon is not None):
        return None
    if not (LAT_MIN <= lat <= LAT_MAX and LON_MIN <= lon <= LON_MAX):
        return None
    types = p.get("types") or []
    cuisines = []
    for t in types:
        m = TYPE_TO_CUISINE.get(t)
        if m and m not in cuisines:
            cuisines.append(m)
    if not cuisines:
        cuisines = ["other"]
    price = PRICE_MAP.get(p.get("priceLevel", ""), "$$")
    nn = norm(name)
    is_ff = any(t in nn for t in FASTFOOD_DENY) or (
        "fast_food_restaurant" in types and not any(t in nn for t in QSR_ALLOW)
    )
    area = assign_area(lat, lon)
    return {
        "google_id": pid,
        "name": name, "latitude": round(lat, 5), "longitude": round(lon, 5),
        "area": area, "address": addr,
        "cuisines": cuisines[:3], "priceTier": price, "isFastFood": is_ff,
        "website": p.get("websiteUri"), "phone": p.get("nationalPhoneNumber"),
        "description": f"Sourced from Google Places ({area}).",
        "signatureDishes": [],
    }


def fmt_coord(x):
    return f"{x:.5f}".rstrip("0").rstrip(".")


def serialize(doc):
    out = ["{", '  "restaurants": [']
    rs = doc["restaurants"]
    for i, r in enumerate(rs):
        out.append("    {")
        for j, k in enumerate(KEYS):
            v = r[k]
            sval = fmt_coord(v) if k in ("latitude", "longitude") else json.dumps(v, ensure_ascii=False)
            out.append(f'      "{k}": {sval}' + ("," if j < len(KEYS) - 1 else ""))
        out.append("    }" + ("," if i < len(rs) - 1 else ""))
    out += ["  ]", "}"]
    return "\n".join(out) + "\n"


def main():
    seen, places = set(), []
    calls = 0

    # 1. Text search across cuisines, areas, shopping centers, corridors.
    for q in TEXT_QUERIES:
        token = None
        for _ in range(3):
            try:
                resp = places_text(q, token)
                calls += 1
            except Exception as e:
                print(f"text [{q}] failed: {e}")
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
            time.sleep(2)  # nextPageToken needs a brief warm-up
        time.sleep(0.3)

    # 2. Nearby grid — sweep every cell of the bounded area for restaurant-cluster types.
    for (lat, lon) in NEARBY_CENTERS:
        try:
            resp = places_nearby(lat, lon)
            calls += 1
        except Exception as e:
            print(f"nearby ({lat},{lon}) failed: {e}")
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

    print(f"Made {calls} API calls. Fetched {len(places)} unique places in box.")

    # 3. Dedupe against existing seed (normalized name + 0.5 mi proximity).
    doc = json.load(open(SEED, encoding="utf-8"))
    existing = [(norm(r["name"]), r["latitude"], r["longitude"]) for r in doc["restaurants"]]
    added, skipped_dup = [], 0
    for p in places:
        nn = norm(p["name"])
        if len(nn) < 3:
            skipped_dup += 1
            continue
        is_dup = any(
            len(en) >= 3 and (nn in en or en in nn) and
            haversine_mi(p["latitude"], p["longitude"], elat, elon) < 0.5
            for (en, elat, elon) in existing
        )
        if is_dup:
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
        added.append(p["name"])

    doc["restaurants"].sort(key=lambda r: (r["area"], r["name"].lower()))
    tmp = SEED + ".tmp"
    open(tmp, "w", encoding="utf-8").write(serialize(doc))
    os.replace(tmp, SEED)
    print(f"Added {len(added)} | dup-skipped {skipped_dup} | TOTAL {len(doc['restaurants'])}")
    for n in added[:80]:
        print("  +", n)
    if len(added) > 80:
        print(f"  ... and {len(added)-80} more")


if __name__ == "__main__":
    main()
