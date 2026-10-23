"""One-off: resolve duplicate restaurant IDs in Restaurants.json.

The catalog grew from several ID schemes (hand-crafted sequential + uuid5 from
google/osm/manual keys), and 8 IDs ended up shared by two restaurants each. The
app dedups by ID (last-wins), so for every collision one restaurant was silently
dropped from the map + search — and the two sat on an unbreakable same-address
cluster.

Fix, per collision group (keeping the LAST entry's id, since that's the one the
app currently shows / may carry rankings):
  - If an earlier entry is an EXACT duplicate of the kept one (same normalized
    name AND address) -> delete it (a true dup the near-twin pass missed).
  - Otherwise -> give it a fresh, guaranteed-unique uuid5 id so it renders as
    its own pin (two real businesses / two locations that collided).

Idempotent: re-running finds no duplicates and changes nothing.
"""
import json
import re
import uuid
from collections import defaultdict

NS = uuid.NAMESPACE_URL
PATH = "WoodlandsEats/Resources/Restaurants.json"


def norm_name(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


def norm_addr(s: str) -> str:
    s = (s or "").lower().replace("suite", "ste")
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


doc = json.load(open(PATH, encoding="utf-8"))
rows = doc["restaurants"]

groups = defaultdict(list)
for i, r in enumerate(rows):
    groups[r["id"]].append(i)

drop = set()
deleted, reassigned = [], []
for rid, idxs in groups.items():
    if len(idxs) < 2:
        continue
    keep = idxs[-1]  # last-wins: the entry the app currently renders
    for i in idxs[:-1]:
        a, b = rows[i], rows[keep]
        if norm_name(a["name"]) == norm_name(b["name"]) and norm_addr(a["address"]) == norm_addr(b["address"]):
            drop.add(i)
            deleted.append(f"{a['name']} | {a['address']}")
        else:
            newid = str(uuid.uuid5(NS, f"woodlandseats:fixdup:{a['name']}|{a['address']}"))
            a["id"] = newid
            reassigned.append(f"{a['name']} ({a['area']}) -> {newid}")

doc["restaurants"] = [r for i, r in enumerate(rows) if i not in drop]

ids = [r["id"] for r in doc["restaurants"]]
assert len(ids) == len(set(ids)), "STILL have duplicate ids after fix"

open(PATH, "w", encoding="utf-8").write(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")

print(f"deleted {len(deleted)} exact duplicate(s):")
for d in deleted:
    print("  -", d)
print(f"reassigned {len(reassigned)} colliding id(s):")
for r in reassigned:
    print("  -", r)
print("total restaurants now:", len(doc["restaurants"]))
