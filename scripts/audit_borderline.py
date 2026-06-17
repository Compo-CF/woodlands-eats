"""scripts/audit_borderline.py

Surface borderline entries from Restaurants.json for human review.

Sibling to remove_non_restaurants.py — that script DROPS entries whose
names hit known non-restaurant patterns. This script does the opposite:
it FLAGS entries whose names contain suspicious-but-ambiguous words
(shop / store / studio / lounge / spa / smoke / vape / etc) so a human
can spot non-restaurants that slipped through. It writes nothing.

Categories of suspicion (printed grouped):

  HARD    — names that contain a strong non-restaurant signal and DON'T
            also contain a restaurant word. These are almost certainly
            non-restaurants; review and add to remove_non_restaurants.py
            denylist if confirmed.

  MEDIUM  — names with ambiguous keywords (lounge, studio, club, etc).
            Often legit (rooftop lounge, sushi studio, dinner club) but
            occasionally smoke lounges, dance studios, or social clubs.

  SOFT    — names that contain no obvious food/restaurant words at all
            (no kitchen/grill/cafe/cuisine/burgers/etc). These are most
            likely fine — many real restaurants have abstract names
            ("Hubbell & Hudson", "Olivette") — but the list is worth a
            scan for outliers.

Run:
  python3 scripts/audit_borderline.py
  python3 scripts/audit_borderline.py --hard       # just HARD category
  python3 scripts/audit_borderline.py --area conroe
"""
import json, re, sys, unicodedata

SEED = "WoodlandsEats/Resources/Restaurants.json"

# HARD signals — non-restaurant words that are RARE in legit restaurant
# names. If a name contains one of these and DOES NOT contain a
# restaurant word, it's almost certainly not a restaurant.
HARD_SIGNALS = [
    # Smoking / vaping / cannabis (the user explicitly called these out)
    (r"\bvape\b", "vape"),
    (r"\bvapor\b", "vape"),
    (r"\bvaping\b", "vape"),
    (r"\b(e-?cig(arette)?)\b", "vape"),
    (r"\bsmoke shop\b", "smoke"),
    (r"\bsmoke\s+(supply|store|outlet)\b", "smoke"),
    (r"\btobacco\b", "smoke"),
    (r"\bcigar(s|ette)?\b(?!\s+(bar|lounge|club))", "smoke"),  # "Cigar Bar" / "Cigar Club" are OK
    (r"\bhookah\b", "smoke"),
    (r"\bkratom\b", "smoke"),
    (r"\bkava\b(?!\s+(bowl|bar|cafe|kitchen))", "smoke"),       # kava bowl/bar is a beverage cafe
    (r"\bcbd\b", "smoke"),
    (r"\bdelta[-\s]?[89]\b", "smoke"),
    (r"\bdispensary\b", "smoke"),
    (r"\bcannabis\b", "smoke"),
    (r"\bmarijuana\b", "smoke"),
    (r"\bsmoking\b", "smoke"),
    (r"\bpuff\s+(bar|shop|store|house)\b", "smoke"),
    # Medical — extra rigor on top of remove_non_restaurants.py
    (r"\bclinic\b(?!al\b)", "medical"),
    (r"\bdoctor'?s?\b", "medical"),
    (r"\bphysician'?s?\b", "medical"),
    (r"\bmd\b(?!s?$)", "medical"),
    (r"\bdo\b\s+(office|associates|clinic|center)", "medical"),
    (r"\bwellness\b", "medical"),
    (r"\bwell[\s-]?being\b", "medical"),
    (r"\bwellbeing\b", "medical"),
    (r"\brehab\b", "medical"),
    (r"\btherap(y|ist|ies|eutic)\b", "medical"),
    (r"\bmedical\b", "medical"),
    (r"\bmedicine\b", "medical"),
    (r"\bhealthcare\b", "medical"),
    (r"\bdental\b", "medical"),
    (r"\bdentist", "medical"),
    (r"\bortho(donti|pedic|paedic)", "medical"),
    (r"\bchiropract", "medical"),
    (r"\bdermatolog", "medical"),
    (r"\bpodiatr", "medical"),
    (r"\boptometr", "medical"),
    (r"\bophthalmolog", "medical"),
    (r"\bpediatr", "medical"),
    (r"\bcardiolog", "medical"),
    (r"\boncolog", "medical"),
    (r"\bgynecol", "medical"),
    (r"\bobgyn\b", "medical"),
    (r"\burgent care\b", "medical"),
    (r"\bemergency\b", "medical"),
    (r"\bhospital\b", "medical"),
    (r"\bpharmac(y|ies)\b", "medical"),
    (r"\bmed[-\s]?spa\b", "medical"),
    (r"\binjectable", "medical"),
    (r"\bbotox\b", "medical"),
    (r"\bfiller", "medical"),
    (r"\bplastic surgery\b", "medical"),
    (r"\bcosmetic surgery\b", "medical"),
    (r"\bweight loss\b", "medical"),
    (r"\bphysical therapy\b", "medical"),
    (r"\bmental health\b", "medical"),
    (r"\bcounsel(or|ing)\b", "medical"),
    (r"\bpsycholog", "medical"),
    (r"\bpsychiatr", "medical"),
    (r"\bbehavioral health\b", "medical"),
    (r"\bnutrition", "medical"),
    (r"\bsupplement", "medical"),
    (r"\bvitamin shoppe\b", "medical"),
    (r"\bgnc\b", "medical"),
    # Health/medical centers and "primary care"
    (r"\bprimary care\b", "medical"),
    (r"\bhealth (center|institute|group|associates?|partners?|services?|store|market)\b", "medical"),
    (r"\bfamily (medicine|practice|care)\b", "medical"),
    (r"\binternal medicine\b", "medical"),
    (r"\bsports medicine\b", "medical"),
    # Non-restaurant retail / services that snuck past remove_non_restaurants
    (r"\bself storage\b", "storage"),
    (r"\bauto (repair|body|parts|glass)\b", "auto"),
    (r"\btire\s+(shop|store|center)\b", "auto"),
    (r"\bcar wash\b", "auto"),
    (r"\boil change\b", "auto"),
    (r"\bbank\b(?!ok)", "bank"),                       # but not "Bankok" misspell
    (r"\bcredit union\b", "bank"),
    (r"\binsurance\b", "service"),
    (r"\bnotary\b", "service"),
    (r"\btitle company\b", "service"),
    (r"\brealtor\b", "service"),
    (r"\brealty\b", "service"),
    (r"\breal estate\b", "service"),
    (r"\battorney", "service"),
    (r"\blawyer", "service"),
    (r"\blaw firm\b", "service"),
    (r"\baccountant\b", "service"),
    (r"\bcpa\b", "service"),
    (r"\bbarber\b", "service"),
    (r"\bnail (salon|spa|bar)\b", "service"),
    (r"\bhair (salon|studio)\b", "service"),
    (r"\btattoo\b", "service"),
    (r"\bgun(s|smith|\s+shop|\s+store|\s+range)\b", "service"),
    (r"\bfirearms?\b", "service"),
    (r"\bammunition\b", "service"),
    (r"\bjewelry\b", "retail"),
    (r"\bjewel(ers?|er'?s)\b", "retail"),
    (r"\bboutique\b", "retail"),
    (r"\bclothing\b", "retail"),
    (r"\bapparel\b", "retail"),
    (r"\bfashion\b", "retail"),
    (r"\bshoe(s|\s+store)\b", "retail"),
    (r"\bfurniture\b", "retail"),
    (r"\bmattress\b", "retail"),
    (r"\bhome decor\b", "retail"),
    (r"\binterior design\b", "service"),
    (r"\bconstruction\b", "service"),
    (r"\bplumbing\b", "service"),
    (r"\belectric(ian|al)\b", "service"),
    (r"\broofing\b", "service"),
    (r"\bhvac\b", "service"),
    (r"\blandscap(e|ing)\b", "service"),
    (r"\bpest control\b", "service"),
    (r"\bcleaning service\b", "service"),
    (r"\blaundromat\b", "service"),
    (r"\bdry clean(ers?|ing)?\b", "service"),
    # Fitness / education (some restaurants share these words — saved by RESTAURANT_WORDS)
    (r"\bcrossfit\b", "fitness"),
    (r"\borangetheory\b", "fitness"),
    (r"\bfitness\b", "fitness"),
    (r"\bgym\b", "fitness"),
    (r"\bpilates\b", "fitness"),
    (r"\b(hot )?yoga\b", "fitness"),
    (r"\bzumba\b", "fitness"),
    (r"\bdance (studio|academy|school)\b", "service"),
    (r"\bmusic (school|academy|lessons?)\b", "service"),
    (r"\b(elementary|middle|high) school\b", "school"),
    (r"\bdaycare\b", "school"),
    (r"\bpreschool\b", "school"),
    (r"\btutoring\b", "school"),
    (r"\blearning center\b", "school"),
    (r"\bmontessori\b", "school"),
    # Religious / civic
    (r"\bchurch\b", "religious"),
    (r"\bmosque\b", "religious"),
    (r"\btemple\b(?!\s+(grandin))", "religious"),
    (r"\bsynagogue\b", "religious"),
    (r"\bministry\b", "religious"),
    # Veterinary
    (r"\bveterinar", "veterinary"),
    (r"\banimal hospital\b", "veterinary"),
    (r"\bpet (hospital|clinic|spa|grooming)\b", "veterinary"),
    (r"\bgrooming\b", "veterinary"),
    # Real estate / residential
    (r"\bapartments?\b", "residential"),
    (r"\bassisted living\b", "residential"),
    (r"\bsenior living\b", "residential"),
    (r"\bnursing home\b", "residential"),
]

# MEDIUM signals — ambiguous; could be legit restaurant naming.
# Lounge could be a "Sushi Lounge" (real) or "Cigar Lounge" (smoke shop).
# Studio could be a "Pizza Studio" (chain) or "Yoga Studio" (fitness).
MEDIUM_SIGNALS = [
    (r"\blounge\b", "lounge"),
    (r"\bstudio\b", "studio"),
    (r"\bacademy\b", "academy"),
    (r"\binstitute\b", "institute"),
    (r"\bcenter\b", "center"),
    (r"\bcentre\b", "centre"),
    (r"\bclub\b", "club"),
    (r"\bsociety\b", "society"),
    (r"\bemporium\b", "emporium"),
    (r"\bgallery\b", "gallery"),
    (r"\bmarket\b", "market"),
    (r"\boutpost\b", "outpost"),
    (r"\bhall\b(?!\s+of)", "hall"),
    (r"\bcollective\b", "collective"),
]

# Same restaurant-word safety net the cleanup script uses. If a name
# contains one of these in addition to a hard signal, we DON'T flag it
# as HARD — these are real restaurants whose names happen to overlap.
RESTAURANT_WORDS = re.compile(
    r"\b(restaurant|bar(?!\s+method)|grill|cafe|kitchen|lounge|steakhouse|"
    r"diner|bistro|brewery|brasserie|tavern|pub|trattoria|pizzeria|pizza|"
    r"sushi|deli|bakery|patisserie|izakaya|cantina|cocina|taqueria|"
    r"churrascaria|coffeehouse|teahouse|smokehouse|alehouse|chophouse|"
    r"brewpub|gastropub|noodle|ramen|hot pot|bbq|barbecue|creamery|"
    r"ice cream|frozen yogurt|donut|donuts|kolache|pho|banh mi|sandwich|"
    r"burger|burgers|wings|tacos?|tortas|crawfish|seafood|oyster|dim sum|"
    r"chicken|hibachi|tap house|food (trucks?|halls?|parks?)|"
    r"bowls?|eatery|eats|juice|smoothie|salads?|wraps?|poke|acai|"
    r"vegan|vegetarian|shakes?|kombucha|crepe|gelato|froyo|"
    r"steak|sandwich(es)?|kabob|gyro|kabab|falafel|shawarma|empanada|"
    r"crawfish|cajun|creole|gumbo|jambalaya|po'?boy|muffuletta|"
    r"smoothie|frappe|latte|espresso|coffee|tea house|boba|bubble tea|"
    r"dessert|cupcake|cookie|chocolate|candy|sweets?|"
    r"meat market|butcher|smokeshack|bbq joint|"
    r"churreria|panaderia|carniceria|tortilleria)",
    re.IGNORECASE,
)


def normalize(s):
    return "".join(
        c for c in unicodedata.normalize("NFKD", s)
        if not unicodedata.combining(c)
    )


def categorize(name):
    """Returns (level, category_or_None, matched_word_or_None).
    level ∈ {"HARD", "MEDIUM", "SOFT", None}"""
    n = normalize(name)
    nl = n.lower()
    has_restaurant_word = bool(RESTAURANT_WORDS.search(n))

    for pat, cat in HARD_SIGNALS:
        m = re.search(pat, nl)
        if m:
            if has_restaurant_word:
                continue  # legit restaurant whose name overlaps a hard signal
            return ("HARD", cat, m.group(0))

    for pat, cat in MEDIUM_SIGNALS:
        m = re.search(pat, nl)
        if m:
            if has_restaurant_word:
                continue
            return ("MEDIUM", cat, m.group(0))

    if not has_restaurant_word:
        return ("SOFT", None, None)

    return (None, None, None)


def main():
    args = set(sys.argv[1:])
    only_hard = "--hard" in args
    area_filter = None
    for i, a in enumerate(sys.argv):
        if a == "--area" and i + 1 < len(sys.argv):
            area_filter = sys.argv[i + 1]

    doc = json.load(open(SEED, encoding="utf-8"))
    rs = doc["restaurants"]
    if area_filter:
        rs = [r for r in rs if r.get("area") == area_filter]
    total = len(rs)
    print(f"Auditing {total} restaurants from {SEED}\n")

    buckets = {"HARD": [], "MEDIUM": [], "SOFT": []}
    for r in rs:
        level, cat, mw = categorize(r["name"])
        if level:
            buckets[level].append((r, cat, mw))

    print(f"Summary:")
    print(f"  HARD   non-restaurant signals (review and add to denylist):   {len(buckets['HARD'])}")
    if not only_hard:
        print(f"  MEDIUM ambiguous (lounge / studio / club / etc):           {len(buckets['MEDIUM'])}")
        print(f"  SOFT   no obvious food words in the name:                  {len(buckets['SOFT'])}")
    print()

    if buckets["HARD"]:
        print("=" * 72)
        print("HARD — almost certainly non-restaurants. Eyeball and add patterns.")
        print("=" * 72)
        by_cat = {}
        for r, cat, mw in buckets["HARD"]:
            by_cat.setdefault(cat, []).append((r, mw))
        for cat in sorted(by_cat.keys()):
            print(f"\n[{cat}]  ({len(by_cat[cat])} entries)")
            for r, mw in sorted(by_cat[cat], key=lambda x: x[0]["name"].lower()):
                print(f"  - {r['name']}  ({r['area']})  -- matched '{mw}'")

    if only_hard:
        return

    if buckets["MEDIUM"]:
        print()
        print("=" * 72)
        print("MEDIUM — ambiguous. Mostly legit (sushi lounge, dinner club),")
        print("but scan for smoke lounges / dance studios / etc.")
        print("=" * 72)
        by_cat = {}
        for r, cat, mw in buckets["MEDIUM"]:
            by_cat.setdefault(cat, []).append((r, mw))
        for cat in sorted(by_cat.keys()):
            print(f"\n[{cat}]  ({len(by_cat[cat])} entries)")
            for r, mw in sorted(by_cat[cat], key=lambda x: x[0]["name"].lower())[:30]:
                print(f"  - {r['name']}  ({r['area']})")
            if len(by_cat[cat]) > 30:
                print(f"  ... and {len(by_cat[cat]) - 30} more")

    if buckets["SOFT"]:
        print()
        print("=" * 72)
        print("SOFT — no food/restaurant word in name. Usually fine, but scan.")
        print("=" * 72)
        for r, _, _ in sorted(buckets["SOFT"], key=lambda x: x[0]["name"].lower())[:80]:
            print(f"  - {r['name']}  ({r['area']})")
        if len(buckets["SOFT"]) > 80:
            print(f"  ... and {len(buckets['SOFT']) - 80} more")


if __name__ == "__main__":
    main()
