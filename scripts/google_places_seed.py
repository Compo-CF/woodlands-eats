"""Bulk-add restaurants from Google Places (New API) into Restaurants.json.

Setup (one-time):
  1. console.cloud.google.com -> create project -> enable "Places API (New)"
  2. enable billing on the project
  3. create an API key -> restrict it to "Places API (New)"
  4. export GOOGLE_PLACES_API_KEY="..." in your shell

Run: python scripts/google_places_seed.py

The script runs ~15 text searches covering the six sub-areas, paginates each
to up to 60 places, dedupes by Google place id, filters to the bounding box,
maps types/price to our schema, and dedupes against existing entries by
normalized name + 0.5 mi proximity before adding.
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
QUERIES = [
    "restaurants in The Woodlands TX",
    "restaurants in Spring TX",
    "restaurants in Old Town Spring TX",
    "restaurants in Shenandoah TX",
    "restaurants in Oak Ridge North TX",
    "restaurants in Klein TX",
    "restaurants near Market Street The Woodlands",
    "restaurants near Hughes Landing The Woodlands",
    "restaurants in Springwoods Village TX",
    "restaurants on Louetta Rd Spring TX",
    "restaurants on FM 2920 Spring TX",
    "restaurants near Champion Forest Dr Spring TX",
    "restaurants in Creekside Park The Woodlands",
    "restaurants near Sterling Ridge The Woodlands",
    "restaurants near Rayford Rd Spring TX",
]
FIELDS = ",".join([
    "places.id", "places.displayName", "places.formattedAddress", "places.location",
    "places.types", "places.priceLevel", "places.websiteUri", "places.nationalPhoneNumber",
    "nextPageToken",
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


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


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


def places_search(query, page_token=None):
    body = {"textQuery": query}
    if page_token:
        body["pageToken"] = page_token
    req = urllib.request.Request(
        "https://places.googleapis.com/v1/places:searchText",
        data=json.dumps(body).encode(),
        headers={
            "Content-Type": "application/json",
            "X-Goog-Api-Key": KEY,
            "X-Goog-FieldMask": FIELDS,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


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
    for q in QUERIES:
        token = None
        for _ in range(3):
            try:
                resp = places_search(q, token)
            except Exception as e:
                print(f"query failed [{q}]: {e}"); break
            for p in resp.get("places", []):
                pid = p.get("id")
                if not pid or pid in seen:
                    continue
                seen.add(pid)
                m = map_place(p)
                if m: places.append(m)
            token = resp.get("nextPageToken")
            if not token: break
            time.sleep(2)  # nextPageToken needs a short delay before it works
        time.sleep(0.5)

    print(f"Fetched {len(places)} unique places in box from Google.")

    doc = json.load(open(SEED, encoding="utf-8"))
    existing = [(norm(r["name"]), r["latitude"], r["longitude"]) for r in doc["restaurants"]]
    added, skipped_dup = [], 0
    for p in places:
        nn = norm(p["name"])
        if any((nn in en or en in nn) and len(en) >= 4 and haversine_mi(p["latitude"], p["longitude"], elat, elon) < 0.5
               for (en, elat, elon) in existing):
            skipped_dup += 1; continue
        rid = str(uuid.uuid5(NS, f"woodlandseats:google:{p['google_id']}"))
        entry = {k: p.get(k) for k in ["name","latitude","longitude","area","address","cuisines","priceTier","isFastFood","website","phone","description","signatureDishes"]}
        entry["id"] = rid
        doc["restaurants"].append(entry)
        existing.append((nn, p["latitude"], p["longitude"]))
        added.append(p["name"])

    doc["restaurants"].sort(key=lambda r: (r["area"], r["name"].lower()))
    tmp = SEED + ".tmp"
    open(tmp, "w", encoding="utf-8").write(serialize(doc))
    os.replace(tmp, SEED)
    print(f"Added {len(added)} | dup-skipped {skipped_dup} | TOTAL {len(doc['restaurants'])}")
    for n in added[:50]:
        print("  +", n)
    if len(added) > 50:
        print(f"  ... and {len(added)-50} more")


if __name__ == "__main__":
    main()
