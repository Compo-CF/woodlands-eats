"""Retry the 8 new restaurants that freeform geocoding missed, using Nominatim's
STRUCTURED query (street/city/postalcode) which resolves FM-road / suburban
addresses far better. Append any recovered ones to Restaurants.json.
"""
import json, re, math, time, uuid, os, urllib.parse, urllib.request

SEED = "WoodlandsEats/Resources/Restaurants.json"
UA = "WoodlandsEats-geocoder/1.0 (acompofelice@outlook.com)"
# Bounds come from scripts/service_area.py (twin of ServiceArea.swift).
# LAT_MIN/MAX/LON_MIN/MAX is the polygon's bounding rectangle for grid use;
# contains() is the precise polygon test for filtering individual results.
from service_area import LAT_MIN, LAT_MAX, LON_MIN, LON_MAX, contains  # noqa: F401
NS = uuid.NAMESPACE_URL
KEYS = ["id", "name", "latitude", "longitude", "area", "address", "cuisines",
        "priceTier", "isFastFood", "website", "phone", "description", "signatureDishes"]

CANDIDATES = [
    ("Eat This", "442 Sawdust Rd", "Spring", "77380", "woodlands", ["healthy","american"], "$$", "https://eatthisthewoodlands.com/", None, "Fast-casual 'clean comfort food' with bowls and house-smoked items on Sawdust Rd. Opened May 2024.", ["Loaded meatloaf","Steak fajita bowl"]),
    ("Susanita's Tex-Mex Y Ritas", "4915 FM 2920", "Spring", "77388", "spring", ["texMex","mexican"], "$$", "https://www.susanitas.com", "281-323-4596", "Family-owned Tex-Mex with multi-generational recipes and margaritas. Opened spring 2025.", ["Fajitas","Margaritas"]),
    ("Mi Rancho Mexican Grill & Bar", "24527 Gosling Rd", "Spring", "77389", "spring", ["texMex","mexican"], "$$", "https://miranchogrill.com", None, "Tex-Mex grill and bar near Gosling Rd and the Grand Parkway. New in 2025.", ["Ribeye tacos","Enchiladas Suizas"]),
    ("Terlingua's Tex-Mex Garage", "16000 Stuebner Airline Rd", "Spring", "77379", "klein", ["texMex","mexican"], "$$", "https://www.terlinguastexmexgaragetx.com", "832-953-8313", "Independent Tex-Mex restaurant and bar with fajitas, enchiladas and specialty cocktails. Opened Oct 2025.", ["Fajitas","Enchiladas"]),
    ("Bamburger", "3624 FM 2920", "Spring", "77388", "klein", ["burgers","american"], "$", "https://bamburger.online", None, "Fast-casual smash-burger spot on FM 2920 with vegan options, fries and shakes. Opened Jan 2025.", ["Classic Bamburger","Shakes"]),
    ("Chubby's Seafood & Grill", "3422 FM 2920", "Spring", "77388", "klein", ["seafood","mexican"], "$$", "https://chubbysgrill.com", None, "Mexican-seafood grill serving ceviche tostadas, flautas and grilled fish. Opened Jan 2025.", ["Ceviche tostadas","Grilled fish"]),
    ("Paleteria La Reina", "3710 FM 2920", "Spring", "77388", "klein", ["dessert","mexican"], "$", "https://orderpaleterialareina.com", None, "Mexican ice cream and treats shop with paletas, mangonadas, churros and milkshakes. Opened Dec 2024.", ["Mangonadas","Fruit paletas"]),
    ("P. Terry's Burger Stand", "20255 Champion Forest Dr", "Spring", "77379", "klein", ["burgers","american"], "$", "https://pterrys.com", None, "Austin-based all-natural burger stand; Champion Forest Dr location opened April 2025.", ["Double burger","Hand-spun shakes"]),
]


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def haversine_mi(a, b, c, d):
    R = 3958.8
    p1, p2 = math.radians(a), math.radians(c)
    dp, dl = math.radians(c - a), math.radians(d - b)
    return 2 * R * math.asin(math.sqrt(math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2))


def _get(params):
    req = urllib.request.Request("https://nominatim.openstreetmap.org/search?" + urllib.parse.urlencode(params),
                                 headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return (float(data[0]["lat"]), float(data[0]["lon"])) if data else None


def geocode(street, city, zc):
    variants = [
        {"street": street, "city": city, "state": "TX", "postalcode": zc, "country": "US", "format": "json", "limit": 1},
        {"street": street.replace("FM ", "Farm to Market "), "city": city, "state": "TX", "postalcode": zc, "country": "US", "format": "json", "limit": 1},
        {"q": f"{street}, {city}, TX {zc}", "format": "json", "limit": 1, "countrycodes": "us"},
        {"q": f"{street.replace('FM ', 'Farm to Market ')}, {city}, TX", "format": "json", "limit": 1, "countrycodes": "us"},
    ]
    for p in variants:
        try:
            r = _get(p)
        except Exception:
            r = None
        time.sleep(1.1)
        if r and LAT_MIN <= r[0] <= LAT_MAX and LON_MIN <= r[1] <= LON_MAX:
            return r
    return None


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
    doc = json.load(open(SEED, encoding="utf-8"))
    existing = [(norm(r["name"]), r["latitude"], r["longitude"]) for r in doc["restaurants"]]
    added, skipped = [], []
    for (name, street, city, zc, area, cuisines, price, web, phone, desc, dishes) in CANDIDATES:
        res = geocode(street, city, zc)
        if not res:
            skipped.append((name, "still no geocode")); continue
        lat, lon = res
        nn = norm(name)
        if any((nn in en or en in nn) and len(en) >= 4 and haversine_mi(lat, lon, elat, elon) < 0.5
               for (en, elat, elon) in existing):
            skipped.append((name, "dup")); continue
        rid = str(uuid.uuid5(NS, f"woodlandseats:manual:{name}|{street}, {city}, TX {zc}"))
        doc["restaurants"].append({
            "id": rid, "name": name, "latitude": round(lat, 5), "longitude": round(lon, 5),
            "area": area, "address": f"{street}, {city}, TX {zc}", "cuisines": cuisines,
            "priceTier": price, "isFastFood": False, "website": web, "phone": phone,
            "description": desc, "signatureDishes": dishes,
        })
        existing.append((nn, lat, lon))
        added.append(name)

    doc["restaurants"].sort(key=lambda r: (r["area"], r["name"].lower()))
    tmp = SEED + ".tmp"
    open(tmp, "w", encoding="utf-8").write(serialize(doc))
    os.replace(tmp, SEED)
    print(f"Recovered {len(added)} | still skipped {len(skipped)} | TOTAL {len(doc['restaurants'])}")
    for n in added: print("  +", n)
    for n, w in skipped: print(f"  - {n}: {w}")


if __name__ == "__main__":
    main()
