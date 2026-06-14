"""Add newly-discovered restaurants (2026-05 research pass) to Restaurants.json.
Geocodes each by full address (Nominatim), drops out-of-box and near-duplicate
(same name within 0.5 mi of an existing pin), assigns a stable uuid5 id.
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
    ("LOCAL Public Eatery", "9595 Six Pines Dr Ste 200, The Woodlands, TX 77380", "woodlands", ["american","burgers","pizza"], "$$", "https://localpubliceatery.com/lpe-woodlands/", None, "From-scratch Americana gastropub at Market Street with burgers, wood-fired pizzas and a retractable-roof patio. Opened Aug 2025.", ["Burgers","Wood-fired pizzas"]),
    ("Monarca Modern Mexican Cocina", "26400 Kuykendahl Rd Ste 100, The Woodlands, TX 77375", "woodlands", ["mexican"], "$$$", "https://monarcarest.com/", "832-559-3855", "Chef-driven contemporary Mexican in Creekside Park with Josper-grilled meats, seafood and a speakeasy bar. Opened 2024.", ["Josper-grilled steak","Tacos"]),
    ("Mimi Garden", "8021 Research Forest Dr Ste A, The Woodlands, TX 77382", "woodlands", ["chinese"], "$$", "https://mimigardentx.com/", "281-323-4060", "Independent Chinese spot for hand-made dumplings, bao and dim sum. Opened late 2024.", ["Soup dumplings","Steamed bao"]),
    ("Simply Pho & Grill", "8000 McBeth Way, The Woodlands, TX 77382", "woodlands", ["vietnamese"], "$$", "https://www.simplyphogrill.com/", "346-459-1009", "Family-owned Vietnamese in Sterling Ridge serving pho, banh mi and grilled dishes. Opened 2024.", ["Pho","Grilled pork bao"]),
    ("Eat This", "442 Sawdust Rd, Spring, TX 77380", "woodlands", ["healthy","american"], "$$", "https://eatthisthewoodlands.com/", None, "Fast-casual 'clean comfort food' with bowls and house-smoked items on Sawdust Rd. Opened May 2024.", ["Loaded meatloaf","Steak fajita bowl"]),
    ("Prime Beef Shabu", "6700 Woodlands Pkwy Ste 250, The Woodlands, TX 77382", "woodlands", ["japanese"], "$$", "https://www.primebeefshabu.com/", "281-651-2542", "All-you-can-eat Japanese shabu-shabu hot pot with individual broths. Opened March 2025.", ["Shabu-shabu hot pot"]),
    ("Original ChopShop", "10720 Kuykendahl Rd Ste D, The Woodlands, TX 77381", "woodlands", ["healthy","american"], "$$", "https://originalchopshop.com/locations/texas/the-woodlands/", "346-771-6862", "Health-focused fast-casual in Indian Springs with protein bowls, salads and fresh juices. Opened Sept 2024.", ["Protein bowls","Fresh-pressed juices"]),
    ("The Stand", "2000 Hughes Landing Blvd Ste F-700, The Woodlands, TX 77380", "woodlands", ["american","burgers"], "$$", "https://www.thestand.com/location/the-woodlands-texas/", None, "California-born better-burger concept at Hughes Landing with burgers, shakes and veg options.", ["Burgers","Hand-spun shakes"]),
    ("Fries & Grind", "1810 Rayford Rd, Spring, TX 77386", "spring", ["burgers"], "$", "https://friesandgrind.toast.site", "832-510-6325", "Smash-burger spot that opened a permanent Rayford Rd location in the Milstead food-truck park. Opened Sept 2025.", ["Smash burger","Truffle parmesan fries"]),
    ("Susanita's Tex-Mex Y Ritas", "4915 FM 2920 Rd Ste 100, Spring, TX 77388", "spring", ["texMex","mexican"], "$$", "https://www.susanitas.com", "281-323-4596", "Family-owned Tex-Mex with multi-generational recipes and margaritas. Opened spring 2025.", ["Fajitas","Margaritas"]),
    ("Mi Rancho Mexican Grill & Bar", "24527 Gosling Rd Ste 101, Spring, TX 77389", "spring", ["texMex","mexican"], "$$", "https://miranchogrill.com", None, "Tex-Mex grill and bar near Gosling Rd and the Grand Parkway. New in 2025.", ["Ribeye tacos","Enchiladas Suizas"]),
    ("Aldanberto's Mexican Food", "4841 Louetta Rd, Spring, TX 77388", "spring", ["mexican"], "$", "https://www.aldanbertos.com", None, "24-hour Mexican spot serving breakfast plates, burritos and street tacos. Opened Jan 2025.", ["Breakfast burritos","Street tacos"]),
    ("The Republic Grille - Spring", "3486 Discovery Creek Blvd, Spring, TX 77386", "spring", ["american","southern"], "$$$", "https://www.therepublicgrille.com", "281-719-2001", "Independently-owned Texas comfort food in Harmony Commons near Grand Parkway and Rayford Rd.", ["Chicken fried steak","Shrimp & grits"]),
    ("SwitcHouse Plates N' Pours", "1200 Lake Plaza Dr, Spring, TX 77389", "spring", ["american","steakhouse"], "$$$", "https://cityplaceswitchouse.com", None, "Texas-cuisine restaurant and bar inside the CityPlace Marriott at Springwoods Village.", ["Texas entrees","Craft cocktails"]),
    ("Sushi Rebel", "1700 City Plaza Dr, Spring, TX 77389", "spring", ["sushi","japanese"], "$$$", None, None, "Stylish sushi concept from the Uptown Sushi owners in the CityPlace / Springwoods Village development.", ["Specialty rolls","Sashimi"]),
    ("Mimi Garden", "202 Sawdust Rd Ste 110, Spring, TX 77380", "spring", ["chinese"], "$$", "https://mimigardentx.com/", None, "Second, larger location of the dumpling and bao specialist; added Peking duck. Opened March 2026.", ["Soup dumplings","Peking duck"]),
    ("Slice of Venice Pizzeria", "5275 Louetta Rd, Spring, TX 77379", "klein", ["italian","pizza"], "$$", "https://www.slicesofvenice.com", None, "Chef-driven Italian by Venice-born chef Francesco Gennari with hand-tossed pizzas and scratch pasta. Opened Jan 2025.", ["Granny pizza","Pinsa Romana"]),
    ("Terlingua's Tex-Mex Garage", "16000 Stuebner Airline Rd Ste M, Spring, TX 77379", "klein", ["texMex","mexican"], "$$", "https://www.terlinguastexmexgaragetx.com", "832-953-8313", "Independent Tex-Mex restaurant and bar with fajitas, enchiladas and specialty cocktails. Opened Oct 2025.", ["Fajitas","Enchiladas"]),
    ("Trill Burgers", "6810 Louetta Rd, Spring, TX 77379", "klein", ["burgers","american"], "$$", "https://www.trillburgers.com", None, "Houston smash-burger brand co-founded by Bun B; second brick-and-mortar on Louetta Rd. Opened April 2025.", ["OG Burger","Trill fries"]),
    ("Bamburger", "3624 FM 2920 Rd Ste 6, Spring, TX 77388", "klein", ["burgers","american"], "$", "https://bamburger.online", None, "Fast-casual smash-burger spot on FM 2920 with vegan options, fries and shakes. Opened Jan 2025.", ["Classic Bamburger","Shakes"]),
    ("Chubby's Seafood & Grill", "3422 FM 2920 Rd, Spring, TX 77388", "klein", ["seafood","mexican"], "$$", "https://chubbysgrill.com", None, "Mexican-seafood grill serving ceviche tostadas, flautas and grilled fish. Opened Jan 2025.", ["Ceviche tostadas","Grilled fish"]),
    ("Rusty Horseshoe Bar and Grill", "19940 Kuykendahl Rd, Spring, TX 77379", "klein", ["american","southern"], "$$", "https://horseshoehtx.com", None, "Bar and grill with live music in the former Bareback Icehouse space; wings, burgers and cocktails. Opened Jan 2025.", ["Wings","Burgers"]),
    ("Paleteria La Reina", "3710 FM 2920 Rd Ste 105, Spring, TX 77388", "klein", ["dessert","mexican"], "$", "https://orderpaleterialareina.com", None, "Mexican ice cream and treats shop with paletas, mangonadas, churros and milkshakes. Opened Dec 2024.", ["Mangonadas","Fruit paletas"]),
    ("P. Terry's Burger Stand", "20255 Champion Forest Dr, Spring, TX 77379", "klein", ["burgers","american"], "$", "https://pterrys.com", None, "Austin-based all-natural burger stand; Champion Forest Dr location opened April 2025.", ["Double burger","Hand-spun shakes"]),
    ("Pho Eva", "7306 Louetta Rd Ste A-114, Spring, TX 77379", "klein", ["vietnamese"], "$$", None, None, "Vietnamese pho shop with customizable beef, pork and veg bowls on Louetta Rd. Opened March 2026.", ["Customizable pho","Spring rolls"]),
    ("Sal e Brasa Brazilian Steakhouse", "1700 Research Forest Dr, Shenandoah, TX 77381", "shenandoah", ["steakhouse","latin"], "$$$", "https://www.salebrasausa.com", "281-805-0999", "Brazilian churrasco steakhouse with tableside-carved meats and a buffet. Soft-opened April 2025.", ["Picanha","Churrasco rodizio"]),
    ("Gloria's Latin Cuisine", "18484 Interstate 45 S, Shenandoah, TX 77384", "shenandoah", ["latin","texMex"], "$$", "https://www.gloriascuisine.com/locations/the-woodlands", "936-267-3955", "Salvadoran and Tex-Mex with a large bar and patio along I-45. Opened 2024.", ["Pupusas","Fajitas"]),
    ("KPOT Korean BBQ & Hot Pot", "17937 Interstate 45 N Ste 115, Shenandoah, TX 77385", "shenandoah", ["korean"], "$$", "https://thekpot.com/location/shenandoah-i-45-n/", None, "All-you-can-eat interactive Korean BBQ and hot pot along I-45. Opened Oct 2024.", ["Korean BBQ","Hot pot"]),
    ("Kyuramen", "8821 Metropark Dr Ste 700, Shenandoah, TX 77385", "shenandoah", ["japanese"], "$$", "https://www.kyuramen.com/locations/shenandoah", "281-305-9788", "Modern Japanese ramen shop at Metropark Square. Opened fall 2024.", ["Tonkotsu ramen","Spicy miso ramen"]),
    ("Black Bear Diner", "8821 Metropark Dr, Shenandoah, TX 77385", "shenandoah", ["american","breakfastBrunch"], "$$", "https://blackbeardiner.com/location/the-woodlands/", "936-283-5312", "Family-friendly bear-themed all-day diner at Metropark Square with comfort classics. Opened ~2023.", ["Pancakes","Pot roast"]),
]


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def haversine_mi(a, b, c, d):
    R = 3958.8
    p1, p2 = math.radians(a), math.radians(c)
    dp, dl = math.radians(c - a), math.radians(d - b)
    h = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2 * R * math.asin(math.sqrt(h))


def geocode(query):
    params = urllib.parse.urlencode({"q": query, "format": "json", "limit": 1, "countrycodes": "us"})
    req = urllib.request.Request("https://nominatim.openstreetmap.org/search?" + params, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return (float(data[0]["lat"]), float(data[0]["lon"])) if data else None


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
    for (name, addr, area, cuisines, price, web, phone, desc, dishes) in CANDIDATES:
        try:
            res = geocode(re.sub(r",?\s*(Ste\.?|Suite|Unit|#)\s*[A-Za-z0-9\-]+", "", addr, flags=re.I))
        except Exception:
            res = None
        time.sleep(1.1)
        if not res:
            skipped.append((name, "no geocode")); continue
        lat, lon = res
        if not (LAT_MIN <= lat <= LAT_MAX and LON_MIN <= lon <= LON_MAX):
            skipped.append((name, f"out of box {round(lat,3)},{round(lon,3)}")); continue
        nn = norm(name)
        dup = any((nn in en or en in nn) and len(en) >= 4 and haversine_mi(lat, lon, elat, elon) < 0.5
                  for (en, elat, elon) in existing)
        if dup:
            skipped.append((name, "dup of existing")); continue
        rid = str(uuid.uuid5(NS, f"woodlandseats:manual:{name}|{addr}"))
        doc["restaurants"].append({
            "id": rid, "name": name, "latitude": round(lat, 5), "longitude": round(lon, 5),
            "area": area, "address": addr, "cuisines": cuisines, "priceTier": price,
            "isFastFood": False, "website": web, "phone": phone,
            "description": desc, "signatureDishes": dishes,
        })
        existing.append((nn, lat, lon))
        added.append(name)

    doc["restaurants"].sort(key=lambda r: (r["area"], r["name"].lower()))
    tmp = SEED + ".tmp"
    open(tmp, "w", encoding="utf-8").write(serialize(doc))
    os.replace(tmp, SEED)

    print(f"Added {len(added)} | Skipped {len(skipped)} | TOTAL {len(doc['restaurants'])}")
    print("\nADDED:")
    for n in added: print("  +", n)
    print("\nSKIPPED:")
    for n, why in skipped: print(f"  - {n}: {why}")


if __name__ == "__main__":
    main()
