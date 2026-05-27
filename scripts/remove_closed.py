"""Remove permanently-closed / non-existent restaurants flagged by the six
web-verification agents (2026-05 data-refresh pass). Run AFTER recheck_coords.py
so it operates on the coordinate-corrected file.

Run: python scripts/remove_closed.py
"""
import json, os

SEED = "WoodlandsEats/Resources/Restaurants.json"
KEYS = ["id", "name", "latitude", "longitude", "area", "address", "cuisines",
        "priceTier", "isFastFood", "website", "phone", "description", "signatureDishes"]

CLOSED = {
    # indices 0-94
    "bcddecf2-7cae-587d-b18d-f470dc40692e",  # Boston Market
    "f2db3d41-da7b-5817-9891-075dd411d457",  # Fatimas Pupusas and Tacos
    "98eef6e9-7062-53d0-bc32-db68a062b643",  # Ichigo Curry and Ramen
    "6fc00f6b-205f-5f02-a759-2d92c2cab979",  # Mama Juanita's
    # indices 95-189
    "fc4480c6-5d8b-5140-9851-81bad7f8fe8f",  # Vina Deli
    "1c105cb6-8a65-58f8-8220-50c1ca58084e",  # Vito's Famous
    "12932c59-678d-56a2-be2f-57eb9cd7c2c4",  # Americas Woodlands (rebranded)
    "0ad16c94-2fb8-5346-8b9a-e1895fb18bbe",  # Baker Street Pub Grill
    "b2a5d81a-1234-545a-b42c-75d64380c9d1",  # Daisy's Coffee Shop (notfound)
    "53a2cae4-2950-5fc1-9db8-7d53e803981d",  # Hubbell & Hudson Bistro (became TRIS, closed)
    "2a497275-e086-56d1-b61e-ecf4d2a1248b",  # James Coney Island
    "f5d43282-31e8-5907-8ec2-1f6ec26b2f89",  # The Taco Bar (notfound)
    # indices 190-284
    "0c074afb-27b2-50ff-9e0e-a837a5db532f",  # Wisdom Vegan Bakery
    "853afe7b-c11d-5298-82ee-f94b90fcb6ae",  # Killen's BBQ (closed Dec 2025)
    "2bb59141-72a6-51e2-bc22-63668d03d48e",  # Famous Cajun Grill
    "0e06e387-eca7-5d11-a7bf-1b08a210a1b0",  # I.CE.NY
    "449fdfe2-f98a-56dd-8d9a-583753ea3c30",  # Poke Man
    # indices 285-379
    "45cdd31c-fc8b-528c-8026-1f160dc33543",  # Wahoo's Fish Taco
    "ca203df6-9dea-5589-a3a3-aebe60db6f81",  # Dog Haus Biergarten
    "2d91f0ee-5786-5593-b14d-a84e13864f2c",  # El Kiosko #13
    "4fe1a2af-26b4-510e-a0db-00b083d21fbf",  # El Pibe (notfound)
    "08b305ae-599d-562b-bddc-a29aec83a620",  # Gorditas Y Tacos La Bala (notfound)
    "4f7a2709-11fe-593b-9d32-f892576ef4e9",  # Hooters
    "3dcf318e-4ad5-5cf4-bd8f-3a51b050a813",  # Krispy Krunchy Chicken (notfound)
    # indices 380-474
    "c97bc326-1006-590b-8122-23124132c216",  # "Mr" (malformed/notfound)
    "fe43ed90-f96b-5ecb-8b37-2905a04563fc",  # Razzoo's Cajun Cafe
    "6a3be9ea-a0f2-5f96-b4b7-032e30b6b96c",  # Red Lobster
    "41187a4f-1b5e-5f61-8031-98c113700f10",  # Spring Food Park
    "78190f5b-5351-585e-bc0d-b46f6d59fdc5",  # Taco Corner (notfound)
    "0a1ae06f-6fa2-57eb-bc4d-453b328878b8",  # The Bep (notfound)
    "774bc6be-7f74-57d2-b156-cee6ee8dcda4",  # Zoe's Mexican Treats (notfound)
    "48a93fd1-a6d7-53c0-b9dd-a13a8e675773",  # Atsumi
    "9968576d-6bca-5249-a16e-b0ed6d94248c",  # Broken Barrel
    # indices 475-568
    "273dfe41-23d9-5198-a24d-be2056e3b093",  # Local Pour
    "6b733629-ca79-54da-b15f-342dbbcf90d5",  # Press Waffle Co.
    "6a5ec8e9-3bab-5701-9f4b-16d1abeea9f3",  # Radunare Italian American Table
    "82a7f6ae-d5d3-5dd8-b5a5-2ac0c2ef4125",  # Potbelly (Market St)
    "db6c9d4a-e253-52c0-8316-b1f1070eb292",  # Uni Sushi
    "319dc5a9-3e50-5955-8403-ed23061f3cc0",  # Uptown Asian Fusion
    "7044fbd0-f501-5bce-9b91-fc10bc9a401c",  # Zoner's Pizza Joint
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


def main():
    doc = json.load(open(SEED, encoding="utf-8"))
    before = len(doc["restaurants"])
    found = {r["id"] for r in doc["restaurants"]} & CLOSED
    doc["restaurants"] = [r for r in doc["restaurants"] if r["id"] not in CLOSED]
    tmp = SEED + ".tmp"
    open(tmp, "w", encoding="utf-8").write(serialize(doc))
    os.replace(tmp, SEED)
    print(f"Removed {before - len(doc['restaurants'])} of {len(CLOSED)} flagged | remaining {len(doc['restaurants'])}")
    missing = CLOSED - found
    if missing:
        print(f"WARNING: {len(missing)} flagged ids not found in file: {missing}")


if __name__ == "__main__":
    main()
