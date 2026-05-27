"""Rebuild Restaurants.json with comprehensive OpenStreetMap coverage.

Pulls every named food establishment (restaurant / fast_food / cafe / ice_cream
/ pub) in the bounded area from the Overpass API, maps OSM tags to our schema,
then merges our hand-verified curated entries on top (curated wins on any name
match, so their richer descriptions / prices / dishes are preserved).

Run: python scripts/rebuild_seed.py
"""
import json, re, math, uuid, urllib.parse, urllib.request

SEED = "WoodlandsEats/Resources/Restaurants.json"
BBOX = (30.00, -95.57, 30.21, -95.35)  # S, W, N, E — the six areas, trimming Champions/Houston/Porter
NS = uuid.NAMESPACE_URL
KEYS = ["id", "name", "latitude", "longitude", "area", "address", "cuisines",
        "priceTier", "isFastFood", "website", "phone", "description", "signatureDishes"]

# Commodity fast-food chains — always flagged as fast food (hidden by default),
# even if OSM tagged them "restaurant".
FASTFOOD_DENY = {
    "mcdonald", "burgerking", "tacobell", "wendy", "kfc", "kentuckyfried",
    "subway", "sonic", "popeye", "arby", "jackinthebox", "dairyqueen", "domino",
    "pizzahut", "littlecaesar", "papajohn", "deltaco", "carlsjr", "hardee",
    "churchschicken", "whitecastle", "checkers", "rallys", "quiznos",
    "wienerschnitzel", "longjohnsilver", "captainds", "krystal", "pandaexpress",
    "chickfila",
}
# Rankable QSR / fast-casual — NOT flagged even though OSM tags them "fast_food".
QSR_ALLOW = {
    "whataburger", "torchy", "chipotle", "raisingcane", "fiveguys",
    "innout", "shakeshack", "cava", "velvettaco", "fuzzy", "freebirds",
    "modpizza", "jerseymike", "pterry", "layne", "salata", "sweetgreen",
    "willie", "mooyah", "smashburger", "culver", "portillo", "panera",
    "firehouse", "jasonsdeli", "newk", "peiwei",
}

# Area centroids for nearest-match fallback when addr:city is absent/unknown.
CENTROIDS = {
    "woodlands": (30.170, -95.490),
    "shenandoah": (30.178, -95.453),
    "oakRidgeNorth": (30.150, -95.447),
    "oldTownSpring": (30.061, -95.416),
    "klein": (30.020, -95.520),
    "spring": (30.085, -95.400),
}
CITY_MAP = {
    "the woodlands": "woodlands", "woodlands": "woodlands",
    "shenandoah": "shenandoah", "oak ridge north": "oakRidgeNorth",
    "klein": "klein", "spring": "spring",
}
AREA_NAME = {
    "woodlands": "The Woodlands", "spring": "Spring", "shenandoah": "Shenandoah",
    "oakRidgeNorth": "Oak Ridge North", "oldTownSpring": "Old Town Spring", "klein": "Klein",
}
CUISINE_MAP = {
    "burger": "burgers", "burgers": "burgers", "american": "american",
    "mexican": "mexican", "tex-mex": "texMex", "tex_mex": "texMex",
    "taco": "mexican", "tacos": "mexican", "burrito": "mexican",
    "pizza": "pizza", "italian": "italian", "pasta": "italian",
    "chinese": "chinese", "dim_sum": "chinese", "dumpling": "chinese", "hot_pot": "chinese",
    "japanese": "japanese", "sushi": "sushi", "ramen": "japanese",
    "thai": "thai", "vietnamese": "vietnamese", "pho": "vietnamese",
    "korean": "korean", "indian": "indian", "pakistani": "indian",
    "seafood": "seafood", "poke": "seafood", "fish": "seafood",
    "steak_house": "steakhouse", "steak": "steakhouse",
    "barbecue": "bbq", "bbq": "bbq",
    "coffee_shop": "cafeBakery", "coffee": "cafeBakery", "cafe": "cafeBakery",
    "tea": "cafeBakery", "bubble_tea": "cafeBakery", "bakery": "cafeBakery", "donut": "cafeBakery",
    "sandwich": "american", "sub": "american", "deli": "american",
    "chicken": "american", "fried_chicken": "american", "wings": "american",
    "breakfast": "breakfastBrunch", "brunch": "breakfastBrunch",
    "ice_cream": "dessert", "dessert": "dessert", "frozen_yogurt": "dessert", "donuts": "cafeBakery",
    "mediterranean": "mediterranean", "greek": "mediterranean", "lebanese": "mediterranean",
    "turkish": "mediterranean", "middle_eastern": "mediterranean", "tapas": "mediterranean",
    "french": "french", "southern": "southern", "soul_food": "southern", "cajun": "southern",
    "latin_american": "latin", "latin": "latin", "caribbean": "latin", "cuban": "latin",
    "peruvian": "latin", "venezuelan": "latin", "colombian": "latin",
    "juice": "healthy", "smoothie": "healthy", "salad": "healthy",
    "vegetarian": "healthy", "vegan": "healthy", "healthy": "healthy",
}
AMENITY_DEFAULT = {"cafe": ["cafeBakery"], "ice_cream": ["dessert"], "pub": ["american"]}
AMENITY_PRICE = {"fast_food": "$", "ice_cream": "$", "cafe": "$", "pub": "$$", "restaurant": "$$"}
AMENITY_LABEL = {"restaurant": "restaurant", "fast_food": "quick-service spot",
                 "cafe": "cafe", "ice_cream": "ice cream shop", "pub": "pub",
                 "food_court": "food court"}
CUISINE_DISPLAY = {"burgers": "Burger", "american": "American", "mexican": "Mexican",
                   "texMex": "Tex-Mex", "pizza": "Pizza", "italian": "Italian",
                   "chinese": "Chinese", "japanese": "Japanese", "sushi": "Sushi",
                   "thai": "Thai", "vietnamese": "Vietnamese", "korean": "Korean",
                   "indian": "Indian", "seafood": "Seafood", "steakhouse": "Steakhouse",
                   "bbq": "BBQ", "cafeBakery": "Coffee & bakery", "breakfastBrunch": "Breakfast",
                   "dessert": "Dessert", "mediterranean": "Mediterranean", "french": "French",
                   "southern": "Southern", "latin": "Latin", "healthy": "Healthy"}


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def haversine_mi(a, b, c, d):
    R = 3958.8
    p1, p2 = math.radians(a), math.radians(c)
    dp, dl = math.radians(c - a), math.radians(d - b)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))


def assign_area(lat, lon, city):
    # Old Town Spring is a tight historic district — only the small radius counts.
    if haversine_mi(lat, lon, *CENTROIDS["oldTownSpring"]) < 0.6:
        return "oldTownSpring"
    # Trust an explicit, specific city tag (but 'Spring' is too broad — fall to geography).
    if city:
        key = CITY_MAP.get(city.strip().lower())
        if key and key != "spring":
            return key
    # Nearest centroid among the geographic areas (Old Town Spring handled above).
    cands = {k: v for k, v in CENTROIDS.items() if k != "oldTownSpring"}
    return min(cands, key=lambda k: haversine_mi(lat, lon, *cands[k]))


def map_cuisines(tags, amenity):
    raw = tags.get("cuisine", "")
    out = []
    for part in raw.split(";"):
        m = CUISINE_MAP.get(part.strip().lower())
        if m and m not in out:
            out.append(m)
    if not out:
        out = AMENITY_DEFAULT.get(amenity, ["other"])
    return out[:3]


def build_address(tags, area_disp):
    hn, st = tags.get("addr:housenumber", ""), tags.get("addr:street", "")
    street = f"{hn} {st}".strip()
    city = tags.get("addr:city", "") or area_disp
    zc = tags.get("addr:postcode", "")
    comps = [c for c in [street, city] if c]
    comps.append(f"TX {zc}".strip())
    return ", ".join(comps)


def describe(cuisines, amenity, area_disp):
    label = AMENITY_LABEL.get(amenity, "restaurant")
    prim = cuisines[0] if cuisines else "other"
    if prim != "other" and prim in CUISINE_DISPLAY:
        return f"{CUISINE_DISPLAY[prim]} {label} in {area_disp}."
    return f"{label.capitalize()} in {area_disp}."


def website(tags):
    w = tags.get("website") or tags.get("contact:website")
    if not w:
        return None
    return w if w.startswith("http") else "https://" + w


def fetch_osm():
    cond = '"amenity"~"^(restaurant|fast_food|cafe|ice_cream|food_court|pub)$"'
    s, w, n, e = BBOX
    q = (f"[out:json][timeout:120];(node[{cond}]({s},{w},{n},{e});"
         f"way[{cond}]({s},{w},{n},{e}););out center tags;")
    req = urllib.request.Request("https://overpass-api.de/api/interpreter",
                                 data=("data=" + urllib.parse.quote(q)).encode(),
                                 headers={"User-Agent": "WoodlandsEats/1.0"})
    return json.loads(urllib.request.urlopen(req, timeout=180).read())["elements"]


def osm_to_record(el):
    tags = el.get("tags", {})
    name = (tags.get("name") or "").strip()
    if not name:
        return None
    lat = el.get("lat") or el.get("center", {}).get("lat")
    lon = el.get("lon") or el.get("center", {}).get("lon")
    if lat is None or lon is None:
        return None
    amenity = tags.get("amenity", "restaurant")
    area = assign_area(lat, lon, tags.get("addr:city"))
    area_disp = AREA_NAME[area]
    cuisines = map_cuisines(tags, amenity)
    nn = norm(name)
    is_ff = any(t in nn for t in FASTFOOD_DENY) or \
        (amenity == "fast_food" and not any(t in nn for t in QSR_ALLOW))
    return {
        "id": str(uuid.uuid5(NS, f"osm:{el['type']}:{el['id']}")),
        "name": name,
        "latitude": round(lat, 5),
        "longitude": round(lon, 5),
        "area": area,
        "address": build_address(tags, area_disp),
        "cuisines": cuisines,
        "priceTier": AMENITY_PRICE.get(amenity, "$$"),
        "isFastFood": is_ff,
        "website": website(tags),
        "phone": tags.get("phone") or tags.get("contact:phone"),
        "description": describe(cuisines, amenity, area_disp),
        "signatureDishes": [],
    }


def fmt_coord(x):
    return f"{x:.5f}".rstrip("0").rstrip(".")


def serialize(records):
    out = ["{", '  "restaurants": [']
    for i, r in enumerate(records):
        out.append("    {")
        for j, k in enumerate(KEYS):
            v = r[k]
            sval = fmt_coord(v) if k in ("latitude", "longitude") else json.dumps(v, ensure_ascii=False)
            out.append(f'      "{k}": {sval}' + ("," if j < len(KEYS) - 1 else ""))
        out.append("    }" + ("," if i < len(records) - 1 else ""))
    out += ["  ]", "}"]
    return "\n".join(out) + "\n"


def main():
    # Curated entries are identified by their stable C1D2E3F4 id prefix, so this
    # rebuild is idempotent even if SEED already contains prior OSM output.
    all_existing = json.load(open(SEED, encoding="utf-8"))["restaurants"]
    curated = [r for r in all_existing if r["id"].startswith("C1D2E3F4")]
    for c in curated:           # curated spots are never commodity fast food
        c.setdefault("isFastFood", False)

    # Transform + dedupe OSM
    seen, osm = set(), []
    for el in fetch_osm():
        rec = osm_to_record(el)
        if not rec:
            continue
        key = (norm(rec["name"]), round(rec["latitude"], 3), round(rec["longitude"], 3))
        if key in seen:
            continue
        seen.add(key)
        osm.append(rec)

    # Merge: curated wins; drop OSM entries that duplicate a curated place.
    merged_out = 0
    keep = []
    for o in osm:
        on = norm(o["name"])
        dup = False
        for c in curated:
            cn = norm(c["name"])
            if len(cn) >= 4 and (cn in on or on in cn) and \
               haversine_mi(c["latitude"], c["longitude"], o["latitude"], o["longitude"]) < 0.7:
                dup = True
                break
        if dup:
            merged_out += 1
        else:
            keep.append(o)

    final = curated + keep
    final.sort(key=lambda r: (r["area"], r["name"].lower()))
    open(SEED, "w", encoding="utf-8").write(serialize(final))

    from collections import Counter
    print(f"OSM fetched/deduped: {len(osm)} | dropped as curated dup: {merged_out}")
    ff = sum(1 for r in final if r["isFastFood"])
    print(f"Curated kept: {len(curated)} | OSM added: {len(keep)} | TOTAL: {len(final)}")
    print(f"Fast food flagged: {ff} (hidden by default) | shown by default: {len(final) - ff}")
    print("By area:", dict(Counter(r["area"] for r in final)))
    print("By price:", dict(Counter(r["priceTier"] for r in final)))


if __name__ == "__main__":
    main()
