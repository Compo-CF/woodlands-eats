"""scripts/dedupe_near_twins.py

Free dedup pass for Restaurants.json. Finds pairs that the original
distance-based dedup missed: same restaurant entered twice with
near-identical names but coordinates further apart than the 0.5-mile
threshold the seed scripts use.

Real example from build 33: "Suxico Sushi" had a curated entry at
(30.1555, -95.4525) and a Google Places entry at (30.1272, -95.4513)
— same address (588 Sawdust Rd), name matches exactly, but 3km apart
because the hand-entered curated coordinates were wrong by 3km. Two
pins on the map for one restaurant.

Match criteria for "this is the same restaurant":
  1. Normalized names match (case-insensitive, accent-stripped,
     & <-> and, "the " prefix optional)
  2. Distance < 5 km (catches up-to-3-mile coordinate errors)
  3. First 4 chars of street address match (catches "588 Sawdust"
     vs "588 Sawdust Rd, USA" but rejects different addresses)

Merge strategy when twins are found:
  - Keep the entry with more populated optional fields (phone,
    website, signatureDishes count, description length) — usually
    the curated one has the richer description
  - But take coordinates from the entry with the MORE RECENTLY
    ENRICHED action signals (reservable/delivery/takeout set) —
    that came from the Google Places run, which is authoritative
    on location
  - Drop the loser, keep the winner ID

Run:
  python3 scripts/dedupe_near_twins.py            # writes the seed
  python3 scripts/dedupe_near_twins.py --dry-run  # report only
"""
import json
import math
import os
import re
import sys
import unicodedata

SEED = "WoodlandsEats/Resources/Restaurants.json"

MAX_DISTANCE_KM = 5.0
KEYS = ["id", "name", "latitude", "longitude", "area", "address", "cuisines",
        "priceTier", "isFastFood", "website", "phone", "description",
        "signatureDishes", "reservable", "delivery", "takeout", "dineIn"]


def normalize_name(s):
    """Lowercase, strip diacritics, collapse '&' to 'and', strip 'the '
    prefix, drop punctuation. So 'Café & Bar' and 'cafe and bar' match."""
    s = "".join(c for c in unicodedata.normalize("NFKD", s)
                if not unicodedata.combining(c))
    s = s.lower()
    s = s.replace("&", " and ")
    s = re.sub(r"[^a-z0-9\s]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    if s.startswith("the "):
        s = s[4:]
    return s


def haversine_km(lat1, lon1, lat2, lon2):
    R = 6371.0
    p1 = math.radians(lat1); p2 = math.radians(lat2)
    dlat = math.radians(lat2 - lat1); dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlon / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def addr_street(a):
    """Normalized street segment — text before the first comma, lowercased,
    accent-stripped, punctuation stripped. So '588 Sawdust Rd' and
    '588 Sawdust Rd.' match, but '9011 Louetta' and '9011 Cypresswood'
    don't (which would happen if we only checked the street number)."""
    s = (a or "").split(",")[0].strip().lower()
    s = "".join(c for c in unicodedata.normalize("NFKD", s)
                if not unicodedata.combining(c))
    s = re.sub(r"[^a-z0-9\s]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    # Drop trailing "rd" / "dr" / "st" / "ave" etc. — they're inconsistent
    # in the seed and shouldn't gate twin detection
    s = re.sub(r"\s+(rd|dr|st|ave|blvd|ln|way|hwy|pkwy|ct|cir|pl|fwy)$", "", s)
    return s


def populated_score(r):
    """How 'rich' is this entry? Higher = more fields filled."""
    score = 0
    if r.get("phone"):                    score += 2
    if r.get("website"):                  score += 2
    if r.get("description") and not r.get("description", "").startswith("Sourced from Google"):
        score += 3   # hand-written description is gold
    score += len(r.get("signatureDishes") or [])
    score += len(r.get("cuisines") or [])
    return score


def has_enriched_action_signals(r):
    """True if the row has been through enrich_actions.py — those
    coords were stamped after the Google Places API check."""
    return r.get("reservable") is not None


def merge_twins(a, b):
    """Pick the keeper, copy in any data from the loser that's better."""
    # Coordinate authority: the entry that's been through enrich_actions
    # is the more recent geocoded source. If both or neither, keep the
    # one with the higher populated_score.
    a_enriched = has_enriched_action_signals(a)
    b_enriched = has_enriched_action_signals(b)
    if a_enriched and not b_enriched:
        coord_winner, content_winner = a, (a if populated_score(a) >= populated_score(b) else b)
    elif b_enriched and not a_enriched:
        coord_winner, content_winner = b, (a if populated_score(a) >= populated_score(b) else b)
    else:
        # Both or neither enriched — content_winner is the richer one,
        # coord_winner is also content_winner.
        content_winner = a if populated_score(a) >= populated_score(b) else b
        coord_winner = content_winner

    keeper = dict(content_winner)   # start from the content winner
    # Overlay coordinates from coord_winner
    keeper["latitude"] = coord_winner["latitude"]
    keeper["longitude"] = coord_winner["longitude"]
    # Backfill any null fields from the loser
    loser = b if content_winner is a else a
    for k in ("phone", "website", "description", "signatureDishes",
              "reservable", "delivery", "takeout", "dineIn"):
        if not keeper.get(k) and loser.get(k):
            keeper[k] = loser[k]
    return keeper, loser


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


def main():
    dry_run = "--dry-run" in sys.argv
    doc = json.load(open(SEED, encoding="utf-8"))
    rs = doc["restaurants"]
    print(f"Loaded {len(rs)} restaurants from {SEED}")
    if dry_run:
        print("DRY RUN — no changes will be written\n")
    else:
        print()

    # Group by (normalized name, normalized street). Any group with >1
    # entry is a candidate cluster — we then verify with distance.
    # Skip rows whose address has no street number (just "Klein, TX") —
    # those can't be safely compared as twins, the dedup would risk
    # merging legitimately distinct chain locations.
    groups = {}
    skipped_no_street = 0
    for r in rs:
        street = addr_street(r.get("address", ""))
        # Require at least one digit in the street segment.
        if not any(c.isdigit() for c in street):
            skipped_no_street += 1
            continue
        key = (normalize_name(r["name"]), street)
        groups.setdefault(key, []).append(r)
    if skipped_no_street:
        print(f"  (skipped {skipped_no_street} rows whose address has no street number — "
              f"unsafe to compare as twins)\n")

    candidates = []   # list of (a, b, distance_km)
    for key, group in groups.items():
        if len(group) < 2:
            continue
        # Within a group, all pairs. Usually len(group) is 2.
        for i in range(len(group)):
            for j in range(i + 1, len(group)):
                a, b = group[i], group[j]
                d = haversine_km(a["latitude"], a["longitude"],
                                 b["latitude"], b["longitude"])
                if d <= MAX_DISTANCE_KM:
                    candidates.append((a, b, d))

    print(f"Found {len(candidates)} suspected twin pairs (same name + same address-prefix, <= {MAX_DISTANCE_KM} km apart):\n")

    if not candidates:
        print("Nothing to dedupe. Seed is clean.")
        return

    # Resolve each pair → keep winner, drop loser. Track loser IDs.
    loser_ids = set()
    for a, b, d in candidates:
        if a["id"] in loser_ids or b["id"] in loser_ids:
            # Already resolved via a transitive group; skip.
            continue
        keeper, loser = merge_twins(a, b)
        loser_ids.add(loser["id"])
        # If keeper is one of a/b, replace it in the seed too (for coord/field updates).
        for i, r in enumerate(rs):
            if r["id"] == keeper["id"]:
                rs[i] = keeper
                break
        print(f"  KEEP  {keeper['name']!r}")
        print(f"        {keeper.get('address','')!r}")
        print(f"        @ {keeper['latitude']:.5f}, {keeper['longitude']:.5f}  ({keeper['area']})")
        print(f"  DROP  {loser['name']!r}")
        print(f"        {loser.get('address','')!r}")
        print(f"        @ {loser['latitude']:.5f}, {loser['longitude']:.5f}  ({loser['area']})  [{d:.2f} km away]")
        print()

    survivors = [r for r in rs if r["id"] not in loser_ids]

    if not dry_run:
        doc["restaurants"] = survivors
        tmp = SEED + ".tmp"
        open(tmp, "w", encoding="utf-8").write(serialize(doc))
        os.replace(tmp, SEED)

    verb = "Would drop" if dry_run else "Dropped"
    print(f"{verb} {len(loser_ids)} twin entries. {'After:' if not dry_run else 'New count would be:'} {len(survivors)}")


if __name__ == "__main__":
    main()
