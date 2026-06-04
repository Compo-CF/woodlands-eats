#!/usr/bin/env python3
"""
scripts/enrich_actions.py

For each restaurant in WoodlandsEats/Resources/Restaurants.json, queries the
Google Places API (New) Text Search to capture the action-button signals:

  - reservable  -> shows the "Reserve" button on RestaurantDetailView
  - delivery    -> qualifies the row for the "Order" button
  - takeout     -> qualifies the row for the "Order" button
  - dineIn      -> currently informational; reserved for future filtering

Also backfills `phone` and `website` where the seed currently has null.

Idempotent: rows whose `reservable` field is non-null are skipped (--force
overrides). Checkpoint-writes every 50 calls so a crash doesn't lose progress.

Cost: ~$0.032 / Text Search call * 1,854 rows = ~$60 max if every row runs.
Re-runs after a partial completion only pay for the unfinished tail.

Usage:
    export GOOGLE_PLACES_API_KEY="..."
    python3 scripts/enrich_actions.py             # full run
    python3 scripts/enrich_actions.py --limit 20  # smoke-test a slice first
    python3 scripts/enrich_actions.py --force     # re-enrich everything
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
    "places.nationalPhoneNumber",
    "places.internationalPhoneNumber",
    "places.websiteUri",
    "places.reservable",
    "places.delivery",
    "places.takeout",
    "places.dineIn",
])

# Within this many meters, Google's hit is the same business.
# Tightened past 200m because The Woodlands has dense strip-center clusters
# where neighbors share a parking lot.
MAX_DISTANCE_METERS = 200


def haversine_m(lat1, lon1, lat2, lon2):
    """Meters between two (lat, lon) points."""
    R = 6_371_000
    p1 = math.radians(lat1); p2 = math.radians(lat2)
    dlat = math.radians(lat2 - lat1); dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlon / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def needs_enrichment(row, force=False):
    if force:
        return True
    # We use `reservable` as the canary — once set, the row is considered done.
    return row.get("reservable") is None


def search(api_key, query, lat, lon):
    body = json.dumps({
        "textQuery": query,
        "locationBias": {
            "circle": {
                "center": {"latitude": lat, "longitude": lon},
                "radius": 500.0,
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
        body = e.read().decode("utf-8", errors="replace")
        print(f"  HTTP {e.code}: {body[:200]}", file=sys.stderr)
        return None
    except urllib.error.URLError as e:
        print(f"  network error: {e}", file=sys.stderr)
        return None


def pick_match(places, target_name, target_lat, target_lon):
    """Return the best matching place dict, or None if nothing's close+plausible."""
    if not places:
        return None
    target_lc = target_name.lower()
    best = None
    best_score = -1
    for p in places:
        loc = p.get("location") or {}
        plat = loc.get("latitude"); plon = loc.get("longitude")
        if plat is None or plon is None:
            continue
        dist = haversine_m(target_lat, target_lon, plat, plon)
        if dist > MAX_DISTANCE_METERS:
            continue
        name = (p.get("displayName") or {}).get("text") or ""
        name_lc = name.lower()
        # Crude name match: equal / substring either way / shared first word.
        name_match = (
            name_lc == target_lc
            or name_lc in target_lc
            or target_lc in name_lc
            or (len(set(target_lc.split()) & set(name_lc.split())) >= 1)
        )
        if not name_match:
            continue
        score = 1000 - int(dist)  # closer = higher
        if score > best_score:
            best = p
            best_score = score
    return best


def update_row(row, place):
    """Mutate `row` in place with whatever the matched place has."""
    if row.get("phone") is None:
        phone = place.get("internationalPhoneNumber") or place.get("nationalPhoneNumber")
        if phone:
            row["phone"] = phone
    if row.get("website") is None:
        web = place.get("websiteUri")
        if web:
            row["website"] = web
    # Booleans: capture what Google returned. For keys Google omitted, treat
    # as False — if their dataset doesn't claim the feature, we shouldn't either.
    for k in ("reservable", "delivery", "takeout", "dineIn"):
        row[k] = bool(place.get(k, False))


def mark_unmatched(row):
    """When Google didn't find a confident match, lock the booleans to False
    so future runs don't keep retrying. Phone/website left alone."""
    for k in ("reservable", "delivery", "takeout", "dineIn"):
        if row.get(k) is None:
            row[k] = False


def checkpoint(data):
    SEED.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0,
                    help="Process at most N restaurants (0 = all)")
    ap.add_argument("--force", action="store_true",
                    help="Re-enrich rows even if already populated")
    ap.add_argument("--sleep", type=float, default=0.05,
                    help="Seconds to sleep between API calls (default 0.05)")
    args = ap.parse_args()

    api_key = os.environ.get("GOOGLE_PLACES_API_KEY")
    if not api_key:
        sys.exit("GOOGLE_PLACES_API_KEY not set in env")

    data = json.loads(SEED.read_text(encoding="utf-8"))
    rows = data["restaurants"]
    print(f"Loaded {len(rows)} restaurants from {SEED.relative_to(REPO_ROOT)}")

    todo = [r for r in rows if needs_enrichment(r, args.force)]
    print(f"{len(todo)} need enrichment "
          f"({len(rows) - len(todo)} already done)")
    if args.limit:
        todo = todo[:args.limit]
        print(f"  --limit applied, running on {len(todo)}")

    matched = unmatched = errors = 0
    for n, r in enumerate(todo, 1):
        name = r["name"]
        lat = r["latitude"]
        lon = r["longitude"]
        query = f"{name} {r.get('address', '')}".strip()

        resp = search(api_key, query, lat, lon)
        if resp is None:
            errors += 1
            time.sleep(0.5)
            continue

        place = pick_match(resp.get("places") or [], name, lat, lon)
        if place is None:
            unmatched += 1
            mark_unmatched(r)
        else:
            update_row(r, place)
            matched += 1

        if n % 50 == 0 or n == len(todo):
            print(f"  {n}/{len(todo)} processed "
                  f"(matched={matched}, unmatched={unmatched}, errors={errors})")
            checkpoint(data)

        time.sleep(args.sleep)

    checkpoint(data)
    print(f"\nDone. matched={matched}, unmatched={unmatched}, errors={errors}")
    print(f"Wrote updated seed to {SEED.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
