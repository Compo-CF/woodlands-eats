"""Retry geocoding for agent findings that merge_agent_findings.py couldn't resolve.

The first-pass merge failed on ~73 entries — almost all because Nominatim
chokes on suite/unit numbers in the address. This script attacks the
residual with three escalating strategies:

  1. Strip suite/unit/ste/# from the address, retry Nominatim.
  2. If Nominatim still fails, fall back to Google Places "Text Search"
     using "Name + cleaned address" as the query. Places returns lat/lon
     directly and is much more tolerant of suite-level addresses.
  3. If both fail, log it.

Dedup logic against the current seed is identical to merge_agent_findings.py
(0.08 mi for exact name match, 0.5 mi for substring). In-box filter applies.

Run:
  export GOOGLE_PLACES_API_KEY="..."
  python3 scripts/retry_geocode_failed.py
"""
import os, sys, json, re, math, time, uuid, glob, urllib.request, urllib.parse

SEED = "WoodlandsEats/Resources/Restaurants.json"
FINDINGS_DIR = "scripts/agent_findings"
NS = uuid.NAMESPACE_URL
# Bounds come from scripts/service_area.py (twin of ServiceArea.swift).
# LAT_MIN/MAX/LON_MIN/MAX is the polygon's bounding rectangle for grid use;
# contains() is the precise polygon test for filtering individual results.
from service_area import LAT_MIN, LAT_MAX, LON_MIN, LON_MAX, contains  # noqa: F401
KEYS = ["id", "name", "latitude", "longitude", "area", "address", "cuisines",
        "priceTier", "isFastFood", "website", "phone", "description", "signatureDishes"]
CENTROIDS = {
    "woodlands": (30.170, -95.490), "shenandoah": (30.178, -95.453),
    "oakRidgeNorth": (30.150, -95.447), "oldTownSpring": (30.061, -95.416),
    "klein": (30.020, -95.520), "spring": (30.085, -95.400),
}
NAME_STOP = ["thewoodlands", "oldtownspring", "oakridgenorth", "shenandoah",
             "spring", "klein", "woodlands", "tx", "texas", "houston"]
USER_AGENT = "WoodlandsEats/1.0 (acompofelice@outlook.com)"
KEY = os.environ.get("GOOGLE_PLACES_API_KEY")

EXCLUDE = {
    "woodlandsfinecigarstobaccos",
    "thewoodlandsfarmersmarketgrogansmill",
    "hellokittycafetrucklakewoodlands",
}

# Suite/unit patterns to strip. Order matters — most-specific first so the
# more permissive trailing fallback doesn't eat real street numbers.
SUITE_PATTERNS = [
    r",\s*(?:Ste\.?|Suite|Unit|Bldg\.?|Building|Apt\.?|Apartment)\s*[\w\-]+",
    r"\s+(?:Ste\.?|Suite|Unit|Bldg\.?|Building|Apt\.?|Apartment)\s*[\w\-]+",
    r"\s*#\s*[\w\-]+",
]


def strip_suite(address):
    a = address
    for pat in SUITE_PATTERNS:
        a = re.sub(pat, "", a, flags=re.IGNORECASE)
    return re.sub(r"\s+,", ",", re.sub(r"\s+", " ", a)).strip()


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


def geocode_nominatim(address):
    q = urllib.parse.urlencode({"q": address, "format": "json", "limit": 1, "countrycodes": "us"})
    url = f"https://nominatim.openstreetmap.org/search?{q}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        return (float(data[0]["lat"]), float(data[0]["lon"])) if data else None
    except Exception:
        return None


def geocode_google_places(name, address):
    """Fall back to Google Places Text Search. Tolerant of suite addresses
    because it matches by place name + address, not raw geocoding."""
    if not KEY:
        return None
    body = {"textQuery": f"{name}, {address}"}
    req = urllib.request.Request(
        "https://places.googleapis.com/v1/places:searchText",
        data=json.dumps(body).encode(),
        headers={
            "Content-Type": "application/json",
            "X-Goog-Api-Key": KEY,
            "X-Goog-FieldMask": "places.location",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        places = data.get("places") or []
        if not places:
            return None
        loc = places[0].get("location") or {}
        if "latitude" not in loc or "longitude" not in loc:
            return None
        return float(loc["latitude"]), float(loc["longitude"])
    except Exception:
        return None


def is_duplicate(name_norm, lat, lon, existing):
    if len(name_norm) < 3:
        return True
    for (en, elat, elon) in existing:
        if len(en) < 3:
            continue
        d = haversine_mi(lat, lon, elat, elon)
        if name_norm == en and d < 0.08:
            return True
        if (name_norm in en or en in name_norm) and d < 0.5:
            return True
    return False


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
    if not KEY:
        print("WARN: GOOGLE_PLACES_API_KEY not set. Will only retry via Nominatim "
              "(skip Google Places fallback). Set the env var to enable the second pass.")

    # 1. Load agent findings.
    findings = []
    for path in sorted(glob.glob(f"{FINDINGS_DIR}/*.json")):
        src = os.path.basename(path).removesuffix(".json")
        with open(path, encoding="utf-8") as f:
            for r in json.load(f):
                r["_source"] = src
                findings.append(r)
    # Internal dedup.
    seen, dedupe_in = set(), []
    for r in findings:
        nn = norm(r["name"])
        if nn in EXCLUDE:
            continue
        addr_prefix = re.sub(r"\s+", "", r["address"].lower())[:12]
        key = (nn, addr_prefix)
        if key in seen:
            continue
        seen.add(key)
        dedupe_in.append(r)

    # 2. Read current seed. Anything whose name+address is ALREADY present
    # (by name match) is skipped — we only retry actual misses.
    doc = json.load(open(SEED, encoding="utf-8"))
    seed_names = {norm(r["name"]) for r in doc["restaurants"]}
    existing = [(norm(r["name"]), r["latitude"], r["longitude"]) for r in doc["restaurants"]]

    # 3. Build the residual list: findings whose normalized name isn't in
    # the seed yet. These are the ones that failed on first pass.
    residual = [r for r in dedupe_in if norm(r["name"]) not in seed_names]
    print(f"Residual to retry: {len(residual)} (out of {len(dedupe_in)} unique findings; "
          f"{len(dedupe_in) - len(residual)} already in seed)")

    # 4. Retry each with the cleaned address; fall back to Google Places.
    added, still_failed = [], []
    print("\nRetrying geocode (cleaned address → Nominatim → Google Places)...")
    for i, r in enumerate(residual):
        nn = norm(r["name"])
        cleaned = strip_suite(r["address"])
        coord = None

        # Strategy 1: Nominatim with cleaned address.
        if cleaned != r["address"]:
            coord = geocode_nominatim(cleaned)
            time.sleep(1.05)

        # Strategy 2: Google Places Text Search.
        if not coord and KEY:
            coord = geocode_google_places(r["name"], cleaned)
            time.sleep(0.3)

        if not coord:
            still_failed.append(r["name"])
            continue
        lat, lon = coord
        if not (LAT_MIN <= lat <= LAT_MAX and LON_MIN <= lon <= LON_MAX):
            still_failed.append(f"{r['name']} (out of box at {lat:.4f},{lon:.4f})")
            continue

        if is_duplicate(nn, lat, lon, existing):
            continue
        rid = str(uuid.uuid5(NS, f"woodlandseats:agent:{r['_source']}:{nn}"))
        entry = {
            "id": rid,
            "name": r["name"],
            "latitude": round(lat, 5), "longitude": round(lon, 5),
            "area": r.get("area") or assign_area(lat, lon),
            "address": cleaned,    # store the cleaned version
            "cuisines": r.get("cuisines") or ["other"],
            "priceTier": "$$",
            "isFastFood": False,
            "website": None,
            "phone": None,
            "description": r.get("notes") or f"Sourced from agent research ({r['_source']}).",
            "signatureDishes": [],
        }
        doc["restaurants"].append(entry)
        existing.append((nn, lat, lon))
        added.append(r["name"])
        if (i + 1) % 10 == 0:
            print(f"  ...{i+1}/{len(residual)} retried, {len(added)} added so far")

    doc["restaurants"].sort(key=lambda r: (r["area"], r["name"].lower()))
    tmp = SEED + ".tmp"
    open(tmp, "w", encoding="utf-8").write(serialize(doc))
    os.replace(tmp, SEED)

    print(f"\nRetry added {len(added)} | still-failed {len(still_failed)} | TOTAL {len(doc['restaurants'])}")
    for n in added:
        print("  +", n)
    if still_failed:
        print(f"\n{len(still_failed)} still unresolved:")
        for n in still_failed:
            print("  -", n)


if __name__ == "__main__":
    main()
