"""
Geocode Restaurants.json addresses via OpenStreetMap Nominatim and replace the
approximate seed coordinates with real address-level ones.

Nominatim usage policy: <=1 request/second, descriptive User-Agent. We sleep
1.2s between calls and keep the original coordinate whenever the result is
missing or falls outside the Woodlands/Spring bounding box (a mis-geocode guard).

Run:  python scripts/geocode_seed.py
"""
import json
import re
import sys
import time
import math
import urllib.parse
import urllib.request

SEED = "WoodlandsEats/Resources/Restaurants.json"
UA = "WoodlandsEats-geocoder/1.0 (acompofelice@outlook.com)"

# Bounding box that comfortably contains all six areas; reject anything outside.
LAT_MIN, LAT_MAX = 29.70, 30.45
LON_MIN, LON_MAX = -95.85, -95.15

KEYS = ["id", "name", "latitude", "longitude", "area", "address", "cuisines",
        "priceTier", "website", "phone", "description", "signatureDishes"]

SUITE_RE = re.compile(r",?\s*(Ste\.?|Suite|Unit|#)\s*[A-Za-z0-9\-]+", re.IGNORECASE)


def clean_address(addr: str) -> str:
    return SUITE_RE.sub("", addr).replace("  ", " ").strip()


def haversine_mi(lat1, lon1, lat2, lon2):
    r = 3958.8
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def geocode(query: str):
    params = urllib.parse.urlencode({
        "q": query, "format": "json", "limit": 1, "countrycodes": "us",
    })
    url = "https://nominatim.openstreetmap.org/search?" + params
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    if not data:
        return None
    return float(data[0]["lat"]), float(data[0]["lon"])


def fmt_coord(x: float) -> str:
    return f"{x:.5f}".rstrip("0").rstrip(".")


def serialize(doc) -> str:
    out = ["{", '  "restaurants": [']
    rs = doc["restaurants"]
    for i, r in enumerate(rs):
        out.append("    {")
        for j, k in enumerate(KEYS):
            v = r[k]
            if k in ("latitude", "longitude"):
                sval = fmt_coord(v)
            else:
                sval = json.dumps(v, ensure_ascii=False)
            out.append(f'      "{k}": {sval}' + ("," if j < len(KEYS) - 1 else ""))
        out.append("    }" + ("," if i < len(rs) - 1 else ""))
    out += ["  ]", "}"]
    return "\n".join(out) + "\n"


def main():
    doc = json.load(open(SEED, encoding="utf-8"))
    rs = doc["restaurants"]
    updated, kept, failed, big_moves = 0, [], [], []

    for r in rs:
        q = clean_address(r["address"])
        try:
            res = geocode(q)
        except Exception as e:
            res = None
            failed.append((r["name"], str(e)[:60]))
        if res:
            lat, lon = res
            if LAT_MIN <= lat <= LAT_MAX and LON_MIN <= lon <= LON_MAX:
                moved = haversine_mi(r["latitude"], r["longitude"], lat, lon)
                if moved >= 0.4:
                    big_moves.append((r["name"], round(moved, 2)))
                r["latitude"], r["longitude"] = round(lat, 5), round(lon, 5)
                updated += 1
            else:
                kept.append((r["name"], "out-of-box result"))
        else:
            kept.append((r["name"], "no result"))
        time.sleep(1.2)

    open(SEED, "w", encoding="utf-8").write(serialize(doc))

    print(f"Total: {len(rs)} | Updated: {updated} | Kept original: {len(kept)} | Errors: {len(failed)}")
    if kept:
        print("\nKept original coords (verify manually):")
        for n, why in kept:
            print(f"  - {n}: {why}")
    if big_moves:
        print("\nLarge coordinate corrections (>=0.4 mi moved — eyeball these):")
        for n, d in sorted(big_moves, key=lambda x: -x[1]):
            print(f"  - {n}: moved {d} mi")
    if failed:
        print("\nGeocode errors:")
        for n, e in failed:
            print(f"  - {n}: {e}")


if __name__ == "__main__":
    main()
