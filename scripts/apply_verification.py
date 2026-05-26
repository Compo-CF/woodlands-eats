"""One-off: apply verification-pass findings to Restaurants.json.

Removes permanently-closed / non-existent entries and corrects two that were
real but listed at the wrong location. Re-serializes in the seed's house style.
"""
import json

SEED = "WoodlandsEats/Resources/Restaurants.json"
KEYS = ["id", "name", "latitude", "longitude", "area", "address", "cuisines",
        "priceTier", "website", "phone", "description", "signatureDishes"]

PFX = "C1D2E3F4-0000-4000-A000-0000000000"
REMOVE = {PFX + s for s in ["04", "05", "14", "45", "47", "50"]}  # closed / not real

FIX = {
    PFX + "46": {  # Fogo de Chão — actually at Hughes Landing Restaurant Row
        "address": "1900 Hughes Landing Blvd Ste 400, The Woodlands, TX 77380",
        "latitude": 30.17102, "longitude": -95.4716,
    },
    PFX + "49": {  # Saltgrass — correct street number / zip
        "address": "19533 Interstate 45 S, Shenandoah, TX 77385",
        "latitude": 30.179, "longitude": -95.453,
    },
}


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


doc = json.load(open(SEED, encoding="utf-8"))
before = len(doc["restaurants"])
doc["restaurants"] = [r for r in doc["restaurants"] if r["id"] not in REMOVE]
for r in doc["restaurants"]:
    if r["id"] in FIX:
        r.update(FIX[r["id"]])
open(SEED, "w", encoding="utf-8").write(serialize(doc))
print(f"Removed {before - len(doc['restaurants'])} | Fixed {len(FIX)} | Remaining {len(doc['restaurants'])}")
