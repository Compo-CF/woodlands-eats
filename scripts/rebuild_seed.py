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
# Permanently-closed / non-existent OSM ids (2026-05 verification pass) — never re-add.
CLOSED_DENYLIST = {
    "bcddecf2-7cae-587d-b18d-f470dc40692e", "f2db3d41-da7b-5817-9891-075dd411d457",
    "98eef6e9-7062-53d0-bc32-db68a062b643", "6fc00f6b-205f-5f02-a759-2d92c2cab979",
    "fc4480c6-5d8b-5140-9851-81bad7f8fe8f", "1c105cb6-8a65-58f8-8220-50c1ca58084e",
    "12932c59-678d-56a2-be2f-57eb9cd7c2c4", "0ad16c94-2fb8-5346-8b9a-e1895fb18bbe",
    "b2a5d81a-1234-545a-b42c-75d64380c9d1", "53a2cae4-2950-5fc1-9db8-7d53e803981d",
    "2a497275-e086-56d1-b61e-ecf4d2a1248b", "f5d43282-31e8-5907-8ec2-1f6ec26b2f89",
    "0c074afb-27b2-50ff-9e0e-a837a5db532f", "853afe7b-c11d-5298-82ee-f94b90fcb6ae",
    "2bb59141-72a6-51e2-bc22-63668d03d48e", "0e06e387-eca7-5d11-a7bf-1b08a210a1b0",
    "449fdfe2-f98a-56dd-8d9a-583753ea3c30", "45cdd31c-fc8b-528c-8026-1f160dc33543",
    "ca203df6-9dea-5589-a3a3-aebe60db6f81", "2d91f0ee-5786-5593-b14d-a84e13864f2c",
    "4fe1a2af-26b4-510e-a0db-00b083d21fbf", "08b305ae-599d-562b-bddc-a29aec83a620",
    "4f7a2709-11fe-593b-9d32-f892576ef4e9", "3dcf318e-4ad5-5cf4-bd8f-3a51b050a813",
    "c97bc326-1006-590b-8122-23124132c216", "fe43ed90-f96b-5ecb-8b37-2905a04563fc",
    "6a3be9ea-a0f2-5f96-b4b7-032e30b6b96c", "41187a4f-1b5e-5f61-8031-98c113700f10",
    "78190f5b-5351-585e-bc0d-b46f6d59fdc5", "0a1ae06f-6fa2-57eb-bc4d-453b328878b8",
    "774bc6be-7f74-57d2-b156-cee6ee8dcda4", "48a93fd1-a6d7-53c0-b9dd-a13a8e675773",
    "9968576d-6bca-5249-a16e-b0ed6d94248c", "273dfe41-23d9-5198-a24d-be2056e3b093",
    "6b733629-ca79-54da-b15f-342dbbcf90d5", "6a5ec8e9-3bab-5701-9f4b-16d1abeea9f3",
    "82a7f6ae-d5d3-5dd8-b5a5-2ac0c2ef4125", "db6c9d4a-e253-52c0-8316-b1f1070eb292",
    "319dc5a9-3e50-5955-8403-ed23061f3cc0", "7044fbd0-f501-5bce-9b91-fc10bc9a401c",
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
    import time
    cond = '"amenity"~"^(restaurant|fast_food|cafe|ice_cream|food_court|pub)$"'
    s, w, n, e = BBOX
    q = (f"[out:json][timeout:120];(node[{cond}]({s},{w},{n},{e});"
         f"way[{cond}]({s},{w},{n},{e}););out center tags;")
    endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    ]
    last = None
    for attempt in range(3):
        for ep in endpoints:
            try:
                req = urllib.request.Request(ep, data=("data=" + urllib.parse.quote(q)).encode(),
                                             headers={"User-Agent": "WoodlandsEats/1.0"})
                return json.loads(urllib.request.urlopen(req, timeout=180).read())["elements"]
            except Exception as ex:
                last = ex
                time.sleep(4)
    raise last


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
        if rec["id"] in CLOSED_DENYLIST:      # known permanently-closed — skip
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
        matched = None
        for c in curated:
            cn = norm(c["name"])
            if len(cn) >= 4 and (cn in on or on in cn) and \
               haversine_mi(c["latitude"], c["longitude"], o["latitude"], o["longitude"]) < 0.7:
                matched = c
                break
        if matched is not None:
            # Adopt the OSM POI coordinate for the curated entry — it's placed on
            # the restaurant, more accurate than the curated address geocode.
            matched["latitude"] = o["latitude"]
            matched["longitude"] = o["longitude"]
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
