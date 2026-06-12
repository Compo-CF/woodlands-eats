"""Re-geocode every restaurant address (Nominatim) and cross-check against the
current pin. Agreement (<=0.35 mi) validates the existing coord; a larger
disagreement means the current pin is suspect, so adopt the geocode and report
the move. Keeps the existing coord when geocoding fails or lands out of the box.

Run in background: python scripts/recheck_coords.py
"""
import json, re, math, time, os, urllib.parse, urllib.request

SEED = "WoodlandsEats/Resources/Restaurants.json"
UA = "WoodlandsEats-geocoder/1.0 (acompofelice@outlook.com)"
LAT_MIN, LAT_MAX = 30.00, 30.21
LON_MIN, LON_MAX = -95.57, -95.35
THRESH_MI = 0.35
KEYS = ["id", "name", "latitude", "longitude", "area", "address", "cuisines",
        "priceTier", "isFastFood", "website", "phone", "description", "signatureDishes"]
SUITE_RE = re.compile(r",?\s*(Ste\.?|Suite|Unit|#)\s*[A-Za-z0-9\-]+", re.IGNORECASE)


def clean_address(a):
    return SUITE_RE.sub("", a).replace("  ", " ").strip()


def haversine_mi(a, b, c, d):
    R = 3958.8
    p1, p2 = math.radians(a), math.radians(c)
    dp, dl = math.radians(c - a), math.radians(d - b)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))


def geocode(query):
    params = urllib.parse.urlencode({"q": query, "format": "json", "limit": 1, "countrycodes": "us"})
    req = urllib.request.Request("https://nominatim.openstreetmap.org/search?" + params,
                                 headers={"User-Agent": UA})
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
    rs = doc["restaurants"]
    corrected, validated, kept = [], 0, 0
    for r in rs:
        try:
            res = geocode(clean_address(r["address"]))
        except Exception:
            res = None
        if res:
            lat, lon = res
            if LAT_MIN <= lat <= LAT_MAX and LON_MIN <= lon <= LON_MAX:
                moved = haversine_mi(r["latitude"], r["longitude"], lat, lon)
                if moved > THRESH_MI:
                    corrected.append((r["name"], round(moved, 2)))
                    r["latitude"], r["longitude"] = round(lat, 5), round(lon, 5)
                else:
                    validated += 1
            else:
                kept += 1
        else:
            kept += 1
        time.sleep(1.1)

    tmp = SEED + ".tmp"
    open(tmp, "w", encoding="utf-8").write(serialize(doc))
    os.replace(tmp, SEED)

    print(f"Total {len(rs)} | corrected {len(corrected)} | validated {validated} | kept {kept}")
    print("\nCORRECTED (pin was off by >0.35 mi — moved to geocoded address):")
    for name, dist in sorted(corrected, key=lambda x: -x[1]):
        print(f"  {dist:5} mi  {name}")


if __name__ == "__main__":
    main()
