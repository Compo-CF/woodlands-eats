"""scripts/verify_coords.py

Google Places coordinate verification — catches pure location errors
(pin in wrong shopping center, hand-typed coordinate off by miles, etc.)
that the name-based twin dedup can't see.

For each restaurant: Google Places Text Search by name + address with a
locationBias circle around the current coords. If a confident match comes
back and its coordinates differ from the seed by more than THRESHOLD_M,
we treat the seed as wrong and update.

Cost: ~$0.032 per Text Search call × ~2,350 rows ≈ $75. Run --dry-run
or --limit N first to validate.

Usage:
    export GOOGLE_PLACES_API_KEY="..."
    python3 scripts/verify_coords.py --dry-run --limit 100   # validate
    python3 scripts/verify_coords.py --dry-run               # full preview
    python3 scripts/verify_coords.py                         # apply
    python3 scripts/verify_coords.py --threshold 1000        # 1km threshold
"""
import argparse
import json
import math
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SEED = REPO_ROOT / "WoodlandsEats" / "Resources" / "Restaurants.json"

API_URL = "https://places.googleapis.com/v1/places:searchText"
FIELD_MASK = ",".join([
    "places.id",
    "places.displayName",
    "places.formattedAddress",
    "places.location",
])

# How many meters of disagreement before we consider the seed wrong.
DEFAULT_THRESHOLD_M = 500
# How far apart can Google's result be from our seed before we no longer
# trust it's the same restaurant. Keeps Google from "correcting" a
# Conroe restaurant to a same-name one in Dallas.
SANITY_LIMIT_M = 8000

KEYS = ["id", "name", "latitude", "longitude", "area", "address", "cuisines",
        "priceTier", "isFastFood", "website", "phone", "description",
        "signatureDishes", "reservable", "delivery", "takeout", "dineIn"]


def haversine_m(lat1, lon1, lat2, lon2):
    R = 6_371_000
    p1 = math.radians(lat1); p2 = math.radians(lat2)
    dlat = math.radians(lat2 - lat1); dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlon / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def search(api_key, query, lat, lon):
    body = json.dumps({
        "textQuery": query,
        "locationBias": {
            "circle": {
                "center": {"latitude": lat, "longitude": lon},
                "radius": 5000.0,
            }
        },
        "maxResultCount": 3,
    }).encode("utf-8")
    req = urllib.request.Request(
        API_URL,
        data=body,
        headers={
            "Content-Type": "application/json",
            "X-Goog-Api-Key": api_key,
            "X-Goog-FieldMask": FIELD_MASK,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body_text = e.read().decode("utf-8", errors="replace")
        print(f"  HTTP {e.code}: {body_text[:200]}", file=sys.stderr)
        return None
    except urllib.error.URLError as e:
        print(f"  network error: {e}", file=sys.stderr)
        return None


def pick_match(places, target_name, target_lat, target_lon):
    """Best match within the sanity radius, preferring name similarity."""
    if not places:
        return None
    target_lc = target_name.lower()
    best, best_score = None, -1
    for p in places:
        loc = p.get("location") or {}
        plat = loc.get("latitude"); plon = loc.get("longitude")
        if plat is None or plon is None:
            continue
        dist = haversine_m(target_lat, target_lon, plat, plon)
        if dist > SANITY_LIMIT_M:
            continue
        name = ((p.get("displayName") or {}).get("text") or "").lower()
        # Require at least some name overlap so Google doesn't correct us
        # to a totally different restaurant near our coords.
        if not (name == target_lc or name in target_lc or target_lc in name
                or len(set(target_lc.split()) & set(name.split())) >= 1):
            continue
        score = 100000 - int(dist)
        if score > best_score:
            best, best_score = p, score
    return best


def fmt_coord(x):
    return f"{x:.5f}".rstrip("0").rstrip(".")


def serialize(doc):
    out = ["{", '  "restaurants": [']
    rs = doc["restaurants"]
    for i, r in enumerate(rs):
        out.append("    {")
        present = [k for k in KEYS if k in r]
        for j, k in enumerate(present):
            v = r[k]
            sval = fmt_coord(v) if k in ("latitude", "longitude") else json.dumps(v, ensure_ascii=False)
            out.append(f'      "{k}": {sval}' + ("," if j < len(present) - 1 else ""))
        out.append("    }" + ("," if i < len(rs) - 1 else ""))
    out += ["  ]", "}"]
    return "\n".join(out) + "\n"


def checkpoint(doc):
    tmp = str(SEED) + ".tmp"
    open(tmp, "w", encoding="utf-8").write(serialize(doc))
    os.replace(tmp, str(SEED))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="Report mismatches without writing the seed")
    ap.add_argument("--limit", type=int, default=0,
                    help="Process at most N restaurants (0 = all)")
    ap.add_argument("--threshold", type=int, default=DEFAULT_THRESHOLD_M,
                    help=f"Meters of disagreement to flag (default {DEFAULT_THRESHOLD_M})")
    ap.add_argument("--sleep", type=float, default=0.05,
                    help="Seconds between API calls (default 0.05)")
    args = ap.parse_args()

    api_key = os.environ.get("GOOGLE_PLACES_API_KEY")
    if not api_key:
        sys.exit("GOOGLE_PLACES_API_KEY not set in env")

    doc = json.loads(SEED.read_text(encoding="utf-8"))
    rows = doc["restaurants"]
    todo = rows[:args.limit] if args.limit else rows
    print(f"Loaded {len(rows)} restaurants; checking {len(todo)}")
    if args.dry_run:
        print(f"DRY RUN — no changes will be written")
    print(f"Threshold: {args.threshold}m\n")

    checked = 0
    no_match = 0
    in_tolerance = 0
    corrections = []   # list of (name, old_lat, old_lon, new_lat, new_lon, dist_m)
    errors = 0

    for n, r in enumerate(todo, 1):
        name = r["name"]
        lat = r["latitude"]
        lon = r["longitude"]
        query = f"{name} {r.get('address', '')}".strip()
        resp = search(api_key, query, lat, lon)
        checked += 1
        if resp is None:
            errors += 1
            time.sleep(0.5)
            continue
        place = pick_match(resp.get("places") or [], name, lat, lon)
        if place is None:
            no_match += 1
        else:
            ploc = place["location"]
            dist = haversine_m(lat, lon, ploc["latitude"], ploc["longitude"])
            if dist <= args.threshold:
                in_tolerance += 1
            else:
                corrections.append((name, lat, lon,
                                    ploc["latitude"], ploc["longitude"], dist))
                if not args.dry_run:
                    r["latitude"] = ploc["latitude"]
                    r["longitude"] = ploc["longitude"]

        if n % 50 == 0 or n == len(todo):
            print(f"  {n}/{len(todo)}  checked={checked}  in_tol={in_tolerance}  "
                  f"corrected={len(corrections)}  no_match={no_match}  errors={errors}")
            if not args.dry_run and corrections:
                checkpoint(doc)

        time.sleep(args.sleep)

    if not args.dry_run:
        checkpoint(doc)

    print(f"\nDone. checked={checked}, in_tolerance={in_tolerance}, "
          f"corrections={len(corrections)}, no_match={no_match}, errors={errors}")

    if corrections:
        # Sort by distance descending — biggest errors first
        corrections.sort(key=lambda c: -c[5])
        verb = "Would correct" if args.dry_run else "Corrected"
        print(f"\n{verb} (top 30 biggest errors):")
        for name, ola, olo, nla, nlo, d in corrections[:30]:
            print(f"  {d:7.0f}m   {name}")
            print(f"            old: {ola:.5f}, {olo:.5f}")
            print(f"            new: {nla:.5f}, {nlo:.5f}")


if __name__ == "__main__":
    main()
