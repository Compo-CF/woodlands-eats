"""Merge the agent-researched restaurant lists into Restaurants.json.

Pipeline:
  1. Load all JSONs from scripts/agent_findings/*.json.
  2. Internal dedup across agents (normalize name, strip area suffixes).
  3. Geocode each entry's address via Nominatim (slow, 1 req/sec per their policy).
  4. Drop any entry outside the bounding box.
  5. Dedup against the existing Restaurants.json (same logic as
     google_places_seed.py's is_duplicate — 0.08 mi for exact name match,
     0.5 mi for substring match).
  6. Append the survivors to Restaurants.json with stable uuid5 ids.
  7. Idempotent — re-running skips already-merged entries.

Run:
  python3 scripts/merge_agent_findings.py
  (No API key needed; Nominatim is free with the User-Agent header set.)
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

# Restaurants the agents surfaced that we know shouldn't go in (cigar lounges,
# venues that aren't really restaurants, etc.). Keyed on normalized name.
EXCLUDE = {
    "woodlandsfinecigarstobaccos",   # cigar lounge, not a restaurant
    "thewoodlandsfarmersmarketgrogansmill",   # market/venue, not a restaurant
    "hellokittycafetrucklakewoodlands",   # pop-up, not a permanent location
}


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


def geocode(address):
    """Nominatim free geocoder. Returns (lat, lon) or None on failure.
    Rate-limited to 1 req/sec by their usage policy — caller must sleep."""
    q = urllib.parse.urlencode({"q": address, "format": "json", "limit": 1, "countrycodes": "us"})
    url = f"https://nominatim.openstreetmap.org/search?{q}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        if not data:
            return None
        return float(data[0]["lat"]), float(data[0]["lon"])
    except Exception as e:
        print(f"  geocode failed for [{address}]: {e}")
        return None


def is_duplicate(name_norm, lat, lon, existing):
    """Same logic as google_places_seed.py — exact name 0.08 mi, substring 0.5 mi."""
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
    findings = []
    for path in sorted(glob.glob(f"{FINDINGS_DIR}/*.json")):
        src = os.path.basename(path).removesuffix(".json")
        with open(path, encoding="utf-8") as f:
            for r in json.load(f):
                r["_source"] = src
                findings.append(r)
    print(f"Loaded {len(findings)} agent findings from {FINDINGS_DIR}/")

    # 1. Internal dedup (cross-agent) on normalized name + normalized address-prefix.
    seen, dedupe_in = set(), []
    for r in findings:
        nn = norm(r["name"])
        if nn in EXCLUDE:
            continue
        # Use first 8 chars of address (e.g., "24600 Go") as a secondary key,
        # so 2 entries with same name but different real addresses both survive.
        addr_prefix = re.sub(r"\s+", "", r["address"].lower())[:12]
        key = (nn, addr_prefix)
        if key in seen:
            continue
        seen.add(key)
        dedupe_in.append(r)
    print(f"After internal dedup: {len(dedupe_in)}")

    # 2. Geocode + filter to in-box.
    print(f"\nGeocoding via Nominatim (1 req/sec, ~{len(dedupe_in)}s)...")
    geocoded = []
    failed = []
    for i, r in enumerate(dedupe_in):
        coord = geocode(r["address"])
        time.sleep(1.05)
        if not coord:
            failed.append(r["name"])
            continue
        lat, lon = coord
        if not (LAT_MIN <= lat <= LAT_MAX and LON_MIN <= lon <= LON_MAX):
            failed.append(f"{r['name']} (out of box at {lat:.4f},{lon:.4f})")
            continue
        r["latitude"], r["longitude"] = round(lat, 5), round(lon, 5)
        r["area"] = r.get("area") or assign_area(lat, lon)
        geocoded.append(r)
        if (i + 1) % 25 == 0:
            print(f"  ...{i+1}/{len(dedupe_in)} geocoded, {len(geocoded)} in-box so far")
    print(f"Geocoded {len(geocoded)} in-box. {len(failed)} failed/out-of-box.")

    # 3. Dedup against existing seed.
    doc = json.load(open(SEED, encoding="utf-8"))
    existing = [(norm(r["name"]), r["latitude"], r["longitude"]) for r in doc["restaurants"]]
    added, dup_skipped = [], 0
    for r in geocoded:
        nn = norm(r["name"])
        if is_duplicate(nn, r["latitude"], r["longitude"], existing):
            dup_skipped += 1
            continue
        rid = str(uuid.uuid5(NS, f"woodlandseats:agent:{r['_source']}:{nn}"))
        entry = {
            "id": rid,
            "name": r["name"],
            "latitude": r["latitude"], "longitude": r["longitude"],
            "area": r["area"],
            "address": r["address"],
            "cuisines": r.get("cuisines") or ["other"],
            "priceTier": "$$",
            "isFastFood": False,
            "website": None,
            "phone": None,
            "description": r.get("notes") or f"Sourced from agent research ({r['_source']}).",
            "signatureDishes": [],
        }
        doc["restaurants"].append(entry)
        existing.append((nn, r["latitude"], r["longitude"]))
        added.append(r["name"])

    doc["restaurants"].sort(key=lambda r: (r["area"], r["name"].lower()))
    tmp = SEED + ".tmp"
    open(tmp, "w", encoding="utf-8").write(serialize(doc))
    os.replace(tmp, SEED)
    print(f"\nAdded {len(added)} | dup-skipped {dup_skipped} | TOTAL {len(doc['restaurants'])}")
    for n in added:
        print("  +", n)
    if failed:
        print(f"\n{len(failed)} did not geocode or fell out of box:")
        for n in failed:
            print("  -", n)


if __name__ == "__main__":
    main()
