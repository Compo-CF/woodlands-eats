"""Bulk-add restaurants from Google Places (New API) into Restaurants.json.

v3 pass (2026-05-31): explicitly engineered to escape the 60-result cap that
v2 silently hit in dense corridors.

  - 10x10 grid (vs v2's 5x5) with 1500m radius -> fewer restaurants per cell,
    so densest cells (Hughes Landing, Market Street, Sawdust corridor) actually
    return their long tail instead of just the top-60 popular spots.
  - ~250 text queries (vs v2's 75): adds bars, lounges, food halls, food
    trucks, breweries, taquerias, panaderias, juice/boba/tea, brand-specific
    chain queries, and recent-opening discovery queries.
  - Expanded NEARBY_TYPES: adds sushi/ramen/taco/sandwich/donut/deli/brunch
    primary types so the nearby pass surfaces specialty spots.
  - Tighter chain dedup: v2 wiped legitimate same-name chains within 0.5 mi
    (two Starbucks in adjacent centers both flagged dup). v3 requires
    proximity < 0.08 mi (~420 ft) for an EXACT normalized-name match, so
    chain duplicates survive. Substring-match still uses 0.5 mi.

Setup (one-time):
  console.cloud.google.com -> project -> enable "Places API (New)" + billing
  -> create API key restricted to Places API (New)

Run:
  export GOOGLE_PLACES_API_KEY="..."
  python3 scripts/google_places_seed.py

Re-runnable: existing entries are dedup-skipped, only genuinely-new spots are
added (deterministic uuid5 from the Google place id).

Cost: ~750-1000 API calls total. At Google's $32/1000 SKU this is ~$25-32,
well within the $200/month free credit.
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
    # ─── broad area sweeps ─────────────────────────────────────────────
    "restaurants in The Woodlands TX", "restaurants in Spring TX",
    "restaurants in Old Town Spring TX", "restaurants in Shenandoah TX",
    "restaurants in Oak Ridge North TX", "restaurants in Klein TX",
    "places to eat The Woodlands TX", "places to eat Spring TX",
    "dining The Woodlands TX", "dining Spring TX",

    # ─── shopping centers / districts / villages ───────────────────────
    "restaurants Market Street The Woodlands", "restaurants Hughes Landing The Woodlands",
    "restaurants Waterway Square The Woodlands", "restaurants Town Center The Woodlands",
    "restaurants Indian Springs Village The Woodlands",
    "restaurants Sterling Ridge Village The Woodlands",
    "restaurants Creekside Park Village Green The Woodlands",
    "restaurants Cochran's Crossing The Woodlands",
    "restaurants Panther Creek The Woodlands",
    "restaurants Grogan's Mill The Woodlands",
    "restaurants Pinecroft Center The Woodlands",
    "restaurants Alden Bridge The Woodlands",
    "restaurants Carlton Woods The Woodlands",
    "restaurants Metropark Square Shenandoah TX",
    "restaurants CityPlace Springwoods Village TX",
    "restaurants Harmony Commons Spring TX",
    "restaurants Vintage Park Spring TX",
    "restaurants Spring Town Center TX",
    "restaurants Woodlands Mall TX",
    "restaurants Portofino Shopping Center Shenandoah",
    "restaurants Pinecroft Place The Woodlands",

    # ─── roads / corridors ─────────────────────────────────────────────
    "restaurants Six Pines Dr The Woodlands",
    "restaurants Lake Robbins Dr The Woodlands",
    "restaurants Research Forest Dr The Woodlands",
    "restaurants Woodlands Pkwy",
    "restaurants Lake Woodlands Dr",
    "restaurants Grogans Mill Rd",
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
    "restaurants Riley Fuzzel Rd Spring TX",
    "restaurants Birnham Woods Dr Spring TX",
    "restaurants Hardy Toll Rd Spring TX",
    "restaurants I-45 Spring TX",
    "restaurants Aldine Westfield Rd Spring TX",

    # ─── cuisine x area (broad) ────────────────────────────────────────
    "italian restaurants The Woodlands TX", "italian restaurants Spring TX",
    "mexican restaurants The Woodlands TX", "mexican restaurants Spring TX",
    "tex mex The Woodlands TX", "tex mex Spring TX",
    "sushi The Woodlands TX", "sushi Spring TX",
    "chinese restaurants The Woodlands TX", "chinese restaurants Spring TX",
    "japanese restaurants The Woodlands TX", "japanese restaurants Spring TX",
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
    "mediterranean The Woodlands TX", "mediterranean Spring TX",
    "greek The Woodlands TX", "greek Spring TX",
    "vegan The Woodlands TX", "vegetarian The Woodlands TX",
    "healthy The Woodlands TX", "healthy Spring TX",

    # ─── cafe / bakery / dessert / drinks ──────────────────────────────
    "cafe The Woodlands TX", "cafe Spring TX",
    "coffee shop The Woodlands TX", "coffee shop Spring TX",
    "bakery The Woodlands TX", "bakery Spring TX",
    "panaderia Spring TX", "panaderia The Woodlands TX",
    "donut shop The Woodlands TX", "donut shop Spring TX",
    "ice cream The Woodlands TX", "ice cream Spring TX",
    "dessert The Woodlands TX", "dessert Spring TX",
    "boba tea The Woodlands TX", "boba tea Spring TX",
    "milk tea Spring TX", "bubble tea The Woodlands TX",
    "juice bar The Woodlands TX", "smoothie Spring TX",
    "tea house The Woodlands TX",

    # ─── bars / breweries / nightlife (food-serving) ───────────────────
    "wine bar The Woodlands TX", "wine bar Spring TX",
    "cocktail bar The Woodlands TX", "cocktail lounge Spring TX",
    "sports bar The Woodlands TX", "sports bar Spring TX",
    "gastropub The Woodlands TX", "gastropub Spring TX",
    "bar and grill The Woodlands TX", "bar and grill Spring TX",
    "tavern Spring TX", "pub The Woodlands TX",
    "brewery The Woodlands TX", "brewery Spring TX",
    "taproom The Woodlands TX", "beer garden Spring TX",
    "speakeasy The Woodlands TX",

    # ─── specialty / niche cuisines ────────────────────────────────────
    "ramen The Woodlands TX", "ramen Spring TX",
    "pho The Woodlands TX", "pho Spring TX",
    "dim sum The Woodlands TX", "hot pot Spring TX",
    "korean bbq The Woodlands TX",
    "taqueria Spring TX", "taqueria The Woodlands TX",
    "taco truck Spring TX",
    "torta Spring TX", "elote Spring TX",
    "biryani Spring TX", "halal Spring TX",
    "lebanese The Woodlands TX", "shawarma Spring TX",
    "ethiopian Houston", "venezuelan Spring TX",
    "peruvian The Woodlands TX", "colombian Spring TX",
    "argentinian The Woodlands TX", "cuban Spring TX",
    "filipino Spring TX", "polish Houston TX",
    "russian Spring TX", "ukrainian Spring TX",

    # ─── format-specific ───────────────────────────────────────────────
    "food truck The Woodlands TX", "food truck Spring TX",
    "food hall The Woodlands TX",
    "deli The Woodlands TX", "deli Spring TX",
    "sandwich shop The Woodlands TX",
    "diner The Woodlands TX", "diner Spring TX",
    "buffet The Woodlands TX", "buffet Spring TX",
    "hibachi The Woodlands TX",
    "rotisserie chicken The Woodlands TX",
    "rooftop restaurant The Woodlands TX",
    "waterfront restaurant The Woodlands TX",
    "outdoor dining The Woodlands TX",
    "late night food The Woodlands TX",
    "24 hour restaurant Spring TX",
    "open late Spring TX",

    # ─── chain-specific (catches missed locations of known chains) ─────
    "Starbucks The Woodlands TX", "Starbucks Spring TX",
    "Whataburger Spring TX", "Whataburger The Woodlands TX",
    "Chipotle Spring TX", "Chipotle The Woodlands TX",
    "Torchys Tacos Spring TX", "Torchys Tacos The Woodlands TX",
    "Chick-fil-A Spring TX", "Chick-fil-A The Woodlands TX",
    "Raising Canes Spring TX",
    "Five Guys The Woodlands TX",
    "Panera Bread The Woodlands TX",
    "Jersey Mikes Spring TX",
    "Jasons Deli The Woodlands TX",
    "Snooze AM Eatery The Woodlands TX",
    "First Watch Spring TX",
    "Black Walnut Cafe The Woodlands TX",
    "Crisp The Woodlands TX",
    "Hubbell Hudson Spring TX",
    "Del Frisco The Woodlands TX",
    "Eddie V The Woodlands TX",
    "Truluck The Woodlands TX",
    "Fleming Steakhouse The Woodlands TX",
    "Perry Steakhouse The Woodlands TX",
    "Carrabbas Spring TX",
    "Olive Garden Spring TX",
    "BJs Brewhouse Spring TX",
    "Cheesecake Factory The Woodlands TX",
    "PF Changs The Woodlands TX",
    "Chuys Spring TX",
    "Lupe Tortilla The Woodlands TX",
    "El Tiempo Cantina Spring TX",
    "Berryhill Tacos Spring TX",

    # ─── discovery / signal / freshness ────────────────────────────────
    "new restaurants The Woodlands TX 2024", "new restaurants The Woodlands TX 2025",
    "new restaurants Spring TX 2024", "new restaurants Spring TX 2025",
    "just opened restaurants The Woodlands TX",
    "now open Spring TX restaurants",
    "best restaurants The Woodlands TX", "best restaurants Spring TX",
    "hidden gem restaurants The Woodlands",
    "local restaurants The Woodlands TX",
    "family owned restaurants Spring TX",
    "upscale dining The Woodlands TX",
    "casual dining Spring TX",
    "kid friendly restaurants The Woodlands TX",
    "patio dining The Woodlands TX",
    "happy hour The Woodlands TX", "happy hour Spring TX",
]

# 10x10 grid of (lat, lon) centers covering the bbox with 1500m radius —
# tighter cells than v2 so dense corridors don't hit the 60-result cap.
def _grid(n=10):
    lats = [LAT_MIN + (LAT_MAX - LAT_MIN) * (i + 0.5) / n for i in range(n)]
    lons = [LON_MIN + (LON_MAX - LON_MIN) * (i + 0.5) / n for i in range(n)]
    return [(la, lo) for la in lats for lo in lons]

NEARBY_CENTERS = _grid(10)
NEARBY_RADIUS_M = 1500

# Expanded NEARBY_TYPES — adds specialty primary types that v2 missed.
NEARBY_TYPES = [
    "restaurant", "fast_food_restaurant", "cafe", "bar", "bakery",
    "ice_cream_shop", "meal_takeaway", "meal_delivery",
    "sandwich_shop", "coffee_shop", "donut_shop",
    "breakfast_restaurant", "brunch_restaurant",
    "sushi_restaurant", "ramen_restaurant", "pizza_restaurant",
    "barbecue_restaurant", "seafood_restaurant", "steak_house",
    "mexican_restaurant", "italian_restaurant", "chinese_restaurant",
    "japanese_restaurant", "thai_restaurant", "vietnamese_restaurant",
    "indian_restaurant", "mediterranean_restaurant", "french_restaurant",
    "korean_restaurant", "vegan_restaurant", "vegetarian_restaurant",
    "dessert_restaurant", "tea_house",
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

# Google Places types we REJECT outright in map_place(). Text searches
# like "restaurants Hughes Landing" can surface hotels/groceries/etc.
# whose Google entry happens to mention "restaurant"; the nearby grid is
# already filtered by NEARBY_TYPES, but text search bypasses that filter.
# Drop any place where one of these appears in its types[] list.
TYPE_DENY = {
    "lodging", "hotel", "motel", "resort_hotel", "bed_and_breakfast",
    "extended_stay_hotel",
    "grocery_store", "supermarket", "convenience_store", "gas_station",
    "pharmacy", "drugstore",
    "department_store", "home_goods_store", "hardware_store",
    "electronics_store", "clothing_store", "shoe_store", "jewelry_store",
    "book_store", "furniture_store",
    "movie_theater", "casino", "amusement_park", "tourist_attraction",
    "gym", "fitness_center", "hair_care", "beauty_salon", "spa",
    "veterinary_care", "pet_store",
    "car_repair", "car_dealer", "car_rental", "car_wash",
    "school", "university", "primary_school", "secondary_school", "library",
    "church", "place_of_worship", "mosque", "synagogue", "hindu_temple",
    "hospital", "doctor", "dentist", "physiotherapist",
    "atm", "bank", "finance",
    "real_estate_agency", "lawyer", "accounting", "insurance_agency",
    "storage", "post_office", "moving_company",
    "rv_park", "campground", "park",
    "apartment_complex",
}


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
    "donut_shop": "dessert", "tea_house": "cafeBakery",
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
    # Regression guard: reject hotels, grocery stores, gas stations, etc.
    # that text-search may have surfaced. Nearby search is already type-
    # filtered, but text-search "restaurants Hughes Landing" can return
    # the Embassy Suites because its description mentions a restaurant.
    if any(t in TYPE_DENY for t in types):
        return None
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


def is_duplicate(name_norm, lat, lon, existing):
    """v3 dedup: tightened so legitimate chain locations survive.

    - Exact normalized-name match: only flag dup if within 0.08 mi (~420 ft).
      Two Starbucks in adjacent shopping centers (~0.2 mi apart) BOTH survive.
    - Substring match (one contains the other): 0.5 mi as before, since
      'Tasty Pizza' vs 'Tasty Pizza Spring' is the same place even across a
      block.
    """
    if len(name_norm) < 3:
        return True   # too short to dedupe meaningfully, drop to be safe
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

    # 1. Text search — broad query vocabulary.
    print(f"Running {len(TEXT_QUERIES)} text queries (3 pages each, ~{len(TEXT_QUERIES)*3} calls)...")
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
            time.sleep(2)   # nextPageToken needs a brief warm-up
        time.sleep(0.3)
        if (i + 1) % 25 == 0:
            print(f"  ...{i+1}/{len(TEXT_QUERIES)} queries done, {len(places)} unique in-box so far")

    # 2. Nearby grid — 10x10 with 1500m radius beats the 60-result cap.
    print(f"\nRunning {len(NEARBY_CENTERS)} nearby cells (~{len(NEARBY_CENTERS)} calls)...")
    for i, (lat, lon) in enumerate(NEARBY_CENTERS):
        try:
            resp = places_nearby(lat, lon)
            calls += 1
        except Exception as e:
            print(f"  nearby ({lat},{lon}) failed: {e}")
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
        if (i + 1) % 25 == 0:
            print(f"  ...{i+1}/{len(NEARBY_CENTERS)} cells done, {len(places)} unique in-box so far")

    print(f"\nMade {calls} API calls. Fetched {len(places)} unique places in box.")

    # 3. Dedupe against existing seed (tightened logic — see is_duplicate).
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
        added.append(p["name"])

    doc["restaurants"].sort(key=lambda r: (r["area"], r["name"].lower()))
    tmp = SEED + ".tmp"
    open(tmp, "w", encoding="utf-8").write(serialize(doc))
    os.replace(tmp, SEED)
    print(f"\nAdded {len(added)} | dup-skipped {skipped_dup} | TOTAL {len(doc['restaurants'])}")
    for n in added[:80]:
        print("  +", n)
    if len(added) > 80:
        print(f"  ... and {len(added)-80} more")


if __name__ == "__main__":
    main()
