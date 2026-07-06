"""Remove non-restaurants from Restaurants.json.

The Google Places expansions pull in collateral: hotels, grocery stores,
gas stations, pharmacies, retail, country clubs, banquet halls — places
Google tags with restaurant-adjacent types even though they aren't consumer-
facing dining.

Approach:
  1. Apply a name-substring denylist (hotel chains, grocery, gas, pharmacy,
     retail, service businesses, etc).
  2. RESTAURANT_WORDS exception: if an entry's name ALSO contains a true
     restaurant word ("steakhouse", "kitchen", "grill", "cafe", etc), it's
     kept even when a denylist pattern matches. This preserves real
     restaurants whose names happen to contain a chain brand (e.g.,
     "Robard's Steakhouse" at The Westin survives, but "The Westin" drops).

Idempotent — re-runnable; entries already cleaned out stay out.

Run:
  python3 scripts/remove_non_restaurants.py            # writes the seed
  python3 scripts/remove_non_restaurants.py --dry-run  # report only
"""
import os, re, sys, json, unicodedata

SEED = "WoodlandsEats/Resources/Restaurants.json"
KEYS = ["id", "name", "latitude", "longitude", "area", "address", "cuisines",
        "priceTier", "isFastFood", "website", "phone", "description", "signatureDishes"]

# Substring patterns (case-insensitive) that signal non-restaurant entries.
# (pattern, category — for logging/reporting).
DENY_PATTERNS = [
    # ─── Hotels ──────────────────────────────────────────────────────
    (r"\bhilton\b", "hotel"),
    (r"\bhampton inn\b", "hotel"),
    (r"\bholiday inn\b", "hotel"),
    (r"\bembassy suites\b", "hotel"),
    (r"\bhyatt\b", "hotel"),
    (r"\bmarriott\b", "hotel"),
    (r"\bcourtyard by\b", "hotel"),
    (r"\bresidence inn\b", "hotel"),
    (r"\bspringhill suites\b", "hotel"),
    (r"\bfairfield inn\b", "hotel"),
    (r"\bbest western\b", "hotel"),
    (r"\bred roof\b", "hotel"),
    (r"\bdays inn\b", "hotel"),
    (r"\bla quinta\b", "hotel"),
    (r"\bcomfort (suites|inn)\b", "hotel"),
    (r"\bcountry inn\b", "hotel"),
    (r"\bquality inn\b", "hotel"),
    (r"\bwingate\b", "hotel"),
    (r"\btru by hilton\b", "hotel"),
    (r"\bhome2 suites\b", "hotel"),
    (r"\bdoubletree\b", "hotel"),
    (r"\bsheraton\b", "hotel"),
    (r"\bwestin\b", "hotel"),
    (r"\baloft\b", "hotel"),
    (r"\bmotel 6\b", "hotel"),
    (r"\bsuper 8\b", "hotel"),
    (r"\bextended stay\b", "hotel"),
    (r"\bmainstay suites\b", "hotel"),
    (r"\bsleep inn\b", "hotel"),
    (r"\bhomewood suites\b", "hotel"),
    (r"\bcandlewood suites\b", "hotel"),
    (r"\bstaybridge\b", "hotel"),
    (r"\btownplace suites\b", "hotel"),
    (r"\bmicrotel\b", "hotel"),
    (r"\bwoodspring suites\b", "hotel"),
    (r"\bresort\b", "hotel"),
    (r"\binn at\b", "hotel"),
    # ─── Grocery / supermarket ───────────────────────────────────────
    (r"\bh-?e-?b\b", "grocery"),
    (r"\bkroger\b", "grocery"),
    (r"\bwalmart\b", "grocery"),
    (r"\btarget\b", "grocery"),
    (r"\bcostco\b", "grocery"),
    (r"\bsam'?s club\b", "grocery"),
    (r"\bwhole foods\b", "grocery"),
    (r"\baldi\b", "grocery"),
    (r"\bsprouts\b", "grocery"),
    (r"\brandalls\b", "grocery"),
    (r"\bfiesta mart\b", "grocery"),
    (r"\btrader joe'?s\b", "grocery"),
    (r"\bfood town\b", "grocery"),
    (r"\bmi tienda\b", "grocery"),
    (r"\bla michoacana meat market\b", "grocery"),
    # ─── Convenience / gas ───────────────────────────────────────────
    (r"\b7-?eleven\b", "convenience"),
    (r"\bbuc-?ee'?s?\b", "convenience"),
    (r"\bracetrac\b", "convenience"),
    (r"\bshell\s+(?:gas|station|food mart)\b", "convenience"),
    (r"\bchevron\b", "convenience"),
    (r"\bexxon\b", "convenience"),
    (r"\bphillips 66\b", "convenience"),
    (r"\btexaco\b", "convenience"),
    (r"\bvalero\b", "convenience"),
    (r"\bspeedway\b", "convenience"),
    (r"\bstripes\b", "convenience"),
    (r"\bcefco\b", "convenience"),
    (r"\bcircle k\b", "convenience"),
    (r"\bquiktrip\b", "convenience"),
    (r"\bsunoco\b", "convenience"),
    # ─── Pharmacy ────────────────────────────────────────────────────
    (r"^cvs( pharmacy)?\b", "pharmacy"),
    (r"\bcvs pharmacy\b", "pharmacy"),
    (r"\bwalgreens\b", "pharmacy"),
    (r"\brite aid\b", "pharmacy"),
    # ─── Big-box / retail non-food ───────────────────────────────────
    (r"\bbest buy\b", "retail"),
    (r"\bhome depot\b", "retail"),
    (r"\blowe'?s\b", "retail"),
    (r"\boffice depot\b", "retail"),
    (r"\boffice max\b", "retail"),
    (r"\bstaples\b", "retail"),
    (r"\bpetco\b", "retail"),
    (r"\bpetsmart\b", "retail"),
    (r"\bgamestop\b", "retail"),
    (r"\bdollar (tree|general)\b", "retail"),
    (r"\bfamily dollar\b", "retail"),
    (r"\b99 cents only\b", "retail"),
    (r"\bbig lots\b", "retail"),
    (r"\bross\b", "retail"),
    (r"\bmarshalls\b", "retail"),
    (r"\bross dress for less\b", "retail"),
    (r"\bmichaels\b", "retail"),
    (r"\bhobby lobby\b", "retail"),
    # ─── Clubs / event venues / not consumer dining ──────────────────
    (r"\bcountry club\b", "club"),
    (r"\bgolf club\b", "club"),
    (r"\bbanquet\b", "event"),
    (r"\bevent center\b", "event"),
    (r"\breception hall\b", "event"),
    (r"\bvending\b", "service"),
    # ─── Schools / churches / institutions ───────────────────────────
    (r"\bisd\b", "school"),
    (r"\b(elementary|middle|high) school\b", "school"),
    (r"\bchurch\b", "religious"),
    (r"\bmosque\b", "religious"),
    (r"\bsynagogue\b", "religious"),
    # ─── Other obvious non-restaurants ───────────────────────────────
    (r"\bdaycare\b", "daycare"),
    (r"\bpreschool\b", "daycare"),
    (r"\bfitness\b", "fitness"),
    (r"\borangetheory\b", "fitness"),
    (r"\bcrunch fitness\b", "fitness"),
    (r"\blife time\b", "fitness"),
    (r"\bplanet fitness\b", "fitness"),
    (r"\byoga\b", "fitness"),
    (r"\bpilates\b", "fitness"),
    (r"\bcrossfit\b", "fitness"),
    (r"\bbarber\b", "service"),
    (r"\bnail (salon|spa|bar)\b", "service"),
    (r"\bhair (salon|studio)\b", "service"),
    (r"\bmedical (clinic|center)\b", "medical"),
    (r"\bdental\b", "medical"),
    (r"\burgent care\b", "medical"),
    (r"\bhospital\b", "medical"),
    (r"\bclinic\b(?!al)", "medical"),
    (r"\bself storage\b", "storage"),
    (r"\bauto repair\b", "auto"),
    (r"\btire (shop|store)\b", "auto"),
    (r"\boil change\b", "auto"),
    (r"\bcarwash\b", "auto"),
    (r"\bcar wash\b", "auto"),
    (r"\bjiffy lube\b", "auto"),
    (r"\bvalvoline\b", "auto"),
    (r"\bautozone\b", "auto"),
    (r"\bo'?reilly auto\b", "auto"),
    (r"\bnapa auto\b", "auto"),
    (r"\bdiscount tire\b", "auto"),
    (r"\bfedex\b", "shipping"),
    (r"\bups store\b", "shipping"),
    (r"\bpostnet\b", "shipping"),
    # ─── Banks (often have small cafes inside that get tagged) ───────
    (r"\bbank of america\b", "bank"),
    (r"\bjpmorgan\b", "bank"),
    (r"\bchase bank\b", "bank"),
    (r"\bwells fargo\b", "bank"),
    (r"\bcitibank\b", "bank"),
    (r"\bcredit union\b", "bank"),
    # ─── Apartments / real estate ────────────────────────────────────
    (r"\bapartments\b", "residential"),
    (r"\bapartment homes\b", "residential"),
    (r"\bassisted living\b", "residential"),
    (r"\bsenior living\b", "residential"),
    (r"\bnursing home\b", "residential"),
    (r"\brehab\b", "residential"),
    # ─── Wellness / home health / personal care ──────────────────────
    (r"\bwellness\b", "wellness"),
    (r"\bhome care\b", "home_health"),
    (r"\bhome health\b", "home_health"),
    (r"\bcaregivers?\b", "home_health"),
    # ─── Medical / cosmetic (extended) ───────────────────────────────
    (r"\bmed[\s-]?spa\b", "medical"),
    (r"\baesthetics?\b", "medical"),
    (r"\bdermatolog", "medical"),
    (r"\bchiropract", "medical"),
    (r"\bphysical therapy\b", "medical"),
    (r"\borthodonti", "medical"),
    (r"\bdentist", "medical"),
    (r"\beye (care|center)\b", "medical"),
    (r"\boptometr", "medical"),
    (r"\bcounseling\b", "medical"),
    (r"\btherap(y|ist)\b", "medical"),
    # ─── Personal services (extended) ────────────────────────────────
    (r"\b(day )?spa\b", "service"),
    (r"\bmassage\b", "service"),
    (r"\btattoo\b", "service"),
    (r"\bsmoke shop\b", "service"),
    (r"\bvape\b", "service"),
    (r"\bcigar (lounge|bar|shop)\b", "service"),
    # ─── Veterinary ──────────────────────────────────────────────────
    (r"\bveterinar", "veterinary"),
    (r"\banimal hospital\b", "veterinary"),
    (r"\bpet hospital\b", "veterinary"),
    # ─── Medical / health (rigorous pass — added after user spotted
    #     "Woodlands Functional Family Medicine" and "Alternative Health
    #     Center of the Woodlands" slipping through the original patterns)
    (r"\bfamily (medicine|practice)\b", "medical"),
    (r"\binternal medicine\b", "medical"),
    (r"\bfunctional (medicine|health)\b", "medical"),
    (r"\bintegrative (medicine|health)\b", "medical"),
    (r"\balternative (health|medicine|wellness)\b", "medical"),
    (r"\bholistic\b", "medical"),
    (r"\bnaturopath", "medical"),
    (r"\bhomeopath", "medical"),
    (r"\bacupuncture\b", "medical"),
    (r"\bayurved", "medical"),
    (r"\bprimary care\b", "medical"),
    (r"\bimmediate care\b", "medical"),
    (r"\bhealth center\b", "medical"),
    (r"\bhealthcare\b", "medical"),
    (r"\bhealth services?\b", "medical"),
    (r"\bhealth (institute|group|partners?|associates?)\b", "medical"),
    (r"\bphysicians?\b", "medical"),
    (r"\bpediatric", "medical"),
    (r"\bcardiology\b", "medical"),
    (r"\boncology\b", "medical"),
    (r"\bsurgery\b", "medical"),
    (r"\bsurgical\b", "medical"),
    (r"\bplastic surgery\b", "medical"),
    (r"\bcosmetic surgery\b", "medical"),
    (r"\bpsychiatr", "medical"),
    (r"\bpsycholog", "medical"),
    (r"\bbehavioral health\b", "medical"),
    (r"\bobgyn\b", "medical"),
    (r"\bgynecolog", "medical"),
    (r"\bnephrolog", "medical"),
    (r"\bneurolog", "medical"),
    (r"\bradiolog", "medical"),
    (r"\bpathology\b", "medical"),
    (r"\boptical\b", "medical"),
    (r"\bvision (center|clinic|care)\b", "medical"),
    (r"\bskin (care|center|clinic|institute)\b", "medical"),
    (r"\bbotox\b", "medical"),
    (r"\binjectables?\b", "medical"),
    (r"\biv (drip|therapy|infusion|lounge|bar)\b", "medical"),
    (r"\binfusion (center|clinic|lounge|bar|services?)\b", "medical"),
    (r"\brecovery (center|clinic)\b", "medical"),
    (r"\brehabilitation\b", "medical"),
    (r"\binstitute (of|for) (health|medicine|wellness)\b", "medical"),
    (r"\bweight loss\b", "medical"),
    (r"\bweight management\b", "medical"),
    (r"\bvein (clinic|center|institute)\b", "medical"),
    (r"\bdialysis\b", "medical"),
    (r"\bpain (clinic|center|management|institute)\b", "medical"),
    (r"\bbariatric\b", "medical"),
    (r"\bgastroenterolog", "medical"),
    (r"\borthopedic\b", "medical"),
    (r"\bhospice\b", "medical"),
    (r"\bfertility\b", "medical"),
    (r"\bnutrition (center|clinic|services?|counseling)\b", "medical"),
    (r"\bIVF\b", "medical"),
    (r"\bMRI\b", "medical"),
    (r"\bdiagnostic imaging\b", "medical"),
    (r"\bimaging center\b", "medical"),
    (r"\bblood (donation|center|drive|donor)\b", "medical"),
    (r"\bplasma\b", "medical"),
    (r"\b(dermatology|aesthetics?) (center|clinic|institute|group)\b", "medical"),
    (r"\borthodontist\b", "medical"),
    (r"\bdentistry\b", "medical"),
    (r"\bmedical group\b", "medical"),
    (r"\bmedical associates\b", "medical"),
    (r"\bmedical partners\b", "medical"),
    (r"\bmedical plaza\b", "medical"),
    (r"\bcounseling (center|services?)\b", "medical"),
    (r"\bmental health\b", "medical"),
    (r"\baddiction (treatment|recovery|center)\b", "medical"),
    (r"\baudiolog", "medical"),
    (r"\bhearing (aid|center|clinic)\b", "medical"),
    # Wellness/well-being centers and women's care (caught after Anthony
    # spotted "The Women's Centre for Well Being"). The earlier pattern
    # required `health` after "women's"; this catches the broader naming.
    (r"\bwell[\s-]?being\b", "medical"),               # well being, well-being, wellbeing
    (r"\bwomen'?s? (centre|center)\b", "medical"),     # women's/womens center/centre
    # ─── Second cleanup pass — Anthony spotted more health entries
    #     that the first pattern set didn't catch (Axiom Medical,
    #     Kindful Health, Woodlands Nutrition, etc.)
    (r"\bfamily care\b", "medical"),               # "Family Care" (no medicine/practice)
    (r"\bwomen'?s health\b", "medical"),
    (r"\bsports medicine\b", "medical"),
    (r"\bnatural health\b", "medical"),
    (r"\bnutrition\b", "medical"),                  # supplement stores + nutrition counseling
    (r"\bsupplements?\b", "medical"),
    (r"\bhealth (market|store|food store)\b", "medical"),
    # Broad — RESTAURANT_WORDS exception (kitchen / cafe / grill / etc) saves
    # legit food spots that happen to contain these words. Without the broad
    # form, names with trailing city suffixes like "Kindful Health, Spring,
    # TX" or "Navita Health | The Woodlands" slip past anchored patterns.
    (r"\bhealth\b", "medical"),
    (r"\bmedical\b", "medical"),
    (r"\bmedicine\b", "medical"),
    # ─── Shopping centers and venues (not the restaurants within) ────
    (r"\bvillage center\b", "venue"),
    (r"\bshopping center\b", "venue"),
    (r"\btown center\b", "venue"),
    (r"\bplaza\b", "venue"),
    # ─── Third cleanup pass — Anthony asked for a final non-restaurant
    #     sweep after the polygon expansion re-seed. Caught vitamin
    #     stores, cigar stores, temples, shopping plazas, wedding
    #     halls, grocery / meat markets, farm stands, bowling alleys,
    #     billiards halls (RESTAURANT_WORDS saves food-mart variants).
    (r"\btemple\b(?!\s+(restaurant|kitchen|cafe|grill|bbq|food))", "religious"),
    (r"\bcigars?\s+(international|superstore|emporium|store|shop|outlet)\b", "smoke"),
    (r"\bvitamin\s+(shoppe?|world|cottage|store|outlet)\b", "retail"),
    (r"\bnatural\s+living\b", "wellness"),
    (r"\bmarket(\s+|-)?place\b", "venue"),
    (r"\bsupermarket\b", "grocery"),
    (r"\binternational\s+market\b", "grocery"),
    (r"\basian\s+market\b", "grocery"),
    (r"\blatin\s+market\b", "grocery"),
    (r"\b(halal|kosher)\s+(meat|grocery|market)\b", "grocery"),
    (r"\bcarniceria\b", "grocery"),
    (r"\bfarms?\s+market\b", "grocery"),
    (r"\bfarmers'?\s+market\b", "venue"),
    (r"\bwedding\b", "event"),
    (r"\bhochzeit\b", "event"),
    (r"\bbowling\b", "entertainment"),
    (r"\bbilliards\b", "entertainment"),
    # ─── Fourth cleanup pass (2026-06-30) — Anthony spotted "North Woods
    #     Endocrinology" slipping through. The original medical denylist
    #     covered several -ology specialties (cardiology, oncology, etc.)
    #     but missed endocrinology + a handful of others. Comprehensive
    #     -ology / professional-suffix sweep.
    (r"\bendocrinolog", "medical"),
    (r"\burolog", "medical"),
    (r"\bophthalmolog", "medical"),
    (r"\brheumatolog", "medical"),
    (r"\bhematolog", "medical"),
    (r"\bimmunolog", "medical"),
    (r"\bpulmonolog", "medical"),
    (r"\botolaryngolog", "medical"),
    (r"\botorhinolaryngolog", "medical"),
    (r"\bent\s+(specialists?|associates?|clinic|center|group)\b", "medical"),
    (r"\bpodiatr", "medical"),
    (r"\bproctolog", "medical"),
    (r"\bvascular\s+(center|clinic|specialists?|institute)\b", "medical"),
    (r"\b(cancer|tumor)\s+(center|institute|clinic|treatment)\b", "medical"),
    (r"\bdiabetes\s+(center|clinic|specialists?|associates?)\b", "medical"),
    (r"\bheart\s+(center|clinic|specialists?|institute|hospital)\b", "medical"),
    (r"\bspine\s+(center|clinic|surgery|institute|specialists?)\b", "medical"),
    (r"\bsleep\s+(center|clinic|specialists?|lab|institute)\b", "medical"),
    (r"\ballerg(y|ies)\s+(center|clinic|specialists?|associates?)\b", "medical"),
    (r"\barthritis\s+(center|clinic|specialists?|associates?)\b", "medical"),
    (r"\bdiagnostic\s+(center|imaging|lab|services?)\b", "medical"),
    (r"\bvein\s+(institute|specialists?|center|clinic)\b", "medical"),
    (r"\bpodiatry\s+(group|associates?|clinic|center)\b", "medical"),
    (r"\bsurgical\s+(center|clinic|specialists?|group|associates?|institute)\b", "medical"),
    (r"\bsurgeons?\s+(group|associates?|of)\b", "medical"),
    # Professional-degree suffixes — strong signal a name is a doctor's
    # office, dental practice, or law firm rather than a restaurant.
    (r",\s*m\.?d\.?\b", "medical"),                        # "Ike Eni, MD"
    (r",\s*d\.?d\.?s\.?\b", "medical"),
    (r",\s*d\.?o\.?\b", "medical"),
    (r"\bpllc\b", "professional"),
    # Catering-only operations. The RESTAURANT_WORDS exception preserves
    # restaurants whose names include "Catering" alongside Kitchen/BBQ/
    # Bistro (Papillion's Kitchen and Catering, Trail Boss BBQ and catering).
    (r"\bcatering\b", "catering"),
    (r"\bcaterers?\b", "catering"),
    # Social / family services agencies caught by case (Munoz Family Services).
    (r"\bfamily\s+services\b", "services"),
    (r"\bsocial\s+services\b", "services"),
    # ─── Fifth cleanup pass (2026-06-30) — Anthony's second batch of
    #     spotted non-restaurants: malls, movie theaters, concert
    #     venues, apartment complexes, retail brands, medical brands.
    # Movie theaters (Cinemark, Cinépolis, Reel Luxury Cinemas, Regal,
    # AMC). RESTAURANT_WORDS exception preserves any rare cinema-cafe.
    (r"\bcinemark\b", "entertainment"),
    (r"\bcinemas?\b", "entertainment"),
    (r"\bcinepolis\b", "entertainment"),
    (r"\bregal\s+(cinemas?|theatres?)\b", "entertainment"),
    (r"\bamc\s+(theatres?|theaters?|dine-?in)\b", "entertainment"),
    (r"\bmovie\s+(theater|theatre)\b", "entertainment"),
    # Concert / outdoor venues (Cynthia Woods Mitchell Pavilion).
    (r"\bpavilion\b", "venue"),
    (r"\bamphitheat(er|re)\b", "venue"),
    # Alcohol retail (Total Wine & More — beverage warehouse, not a bar).
    (r"\btotal\s+wine\b", "alcohol retail"),
    (r"\bspec'?s\s+(liquors?|wines?)\b", "alcohol retail"),
    (r"\bbeverage\s+(world|warehouse|outlet|center)\b", "alcohol retail"),
    # Outdoor-grill retailers (Paradise Grills sells grills, doesn't cook).
    # NOTE: "outdoor kitchens" + name containing "Grills" hits the
    # RESTAURANT_WORDS exception — pattern alone isn't enough; pair with
    # an exact-name entry below.
    (r"\boutdoor\s+kitchens?\b", "grill retail"),
    (r"\bgrill\s+(showroom|gallery|store|outlet)\b", "grill retail"),
    # Medical brands not covered by generic -ology / -care patterns.
    (r"\bkinetix\b", "medical"),              # QC Kinetix
    (r"\bthrivecare\b", "medical"),           # Everest ThriveCare
    # Entertainment / activity venues (Activate Games is a gamified-room
    # chain — not a restaurant; arcades and escape rooms also).
    (r"\bactivate\s+games\b", "entertainment"),
    (r"\barcade\b", "entertainment"),
    (r"\bescape\s+rooms?\b", "entertainment"),
    (r"\baxe\s+throwing\b", "entertainment"),
    (r"\btrampoline\s+park\b", "entertainment"),
    # ─── Sixth cleanup pass (v1.8 geo expansion) — entertainment chains
    #     in the new Tomball/Cypress/Champions/Kingwood footprint.
    (r"\bmain\s+event\b", "entertainment"),        # bowling/arcade/laser chain
    (r"\blucky\s+strike\b", "entertainment"),      # bowling chain
    (r"\bkids\s+empire\b", "entertainment"),       # kids indoor playground
    (r"\bentertainment\s+center\b", "entertainment"),
    (r"\bfamily\s+entertainment\b", "entertainment"),
    (r"\bghost\s+kitchen\b", "facility"),
    (r"\bcloud\s+kitchen\b", "facility"),
    (r"\bcommissary\s+kitchen\b", "facility"),
    (r"\bcoming\s+soon\b", "placeholder"),         # not-yet-open listings
    (r"\bconcession", "venue"),                    # school/stadium stands
    (r"nong\s+trai", "farm"),                      # Vietnamese: farm
    # Retail (Barnes & Noble, jewelers, bookstores, designer brands).
    (r"\bbarnes\s+(&|and)\s+noble\b", "retail"),
    (r"\bbookstore\b", "retail"),
    (r"\bjewelers?\b", "retail"),
    (r"\bdesigner\s+(outlet|store|boutique)\b", "retail"),
    (r"\boutlet\s+mall\b", "retail"),
]

# Exact-name denylist for one-off specific entries that don't match a
# generalizable pattern (named shopping plazas, private country clubs
# without "country club" in the name, named farms that are produce
# stands, etc). Matched case-insensitively against the FULL name after
# normalization.
EXACT_NAME_DENY = {
    "indian springs center",
    "northland center",
    "pinecroft center",
    "the club at carlton woods",
    "the club at carlton woods creekside",
    "atkinson farms",
    "theiss farms market",
    # Fourth cleanup pass (2026-06-30) — specific entries flagged by
    # name inspection: street names, schools, business offices,
    # corporate groups not consumer-facing, duplicate/malformed names.
    "rayford harmony",
    "rayford road",
    "the woodlands korean school",
    "paw paw chico bbq - business office",
    "mb speakeasy - old town spring live music",
    "seacastle2",
    "the brew group",
    # Fifth cleanup pass (2026-06-30) — Anthony's second batch.
    # Districts, malls, apartment complexes, branded developments.
    "the woodlands mall",
    "market street square",
    "waterway square district",
    "lake woodlands crossing",
    "elevate spring crossing",
    "the woodlands crossing",
    "cochran's crossing",                          # Regency Centers shopping plaza
    "hughes landing",                              # Howard Hughes development
    "one lakes edge",                              # apartments
    "two lakes edge",                              # apartments
    "metropark square",                            # development
    "gentry square",                               # plaza (315 Gentry St)
    "centry square",                               # same plaza, malformed name
    # Retail brand storefronts (single-name luxury brand).
    "coach",
    # Medical brand storefronts (compound names that escape -care / -health patterns).
    "enihealthcare",
    "kathy veath",                                 # therapist/counselor by name
    # Grill retailer name contains "Grills" → RESTAURANT_WORDS exception
    # would save it. Exact-name overrides the exception.
    "paradise grills the woodlands outdoor kitchens",
    # Sixth cleanup pass (v1.8 geo expansion):
    "willowbrook court",                  # plaza listing, no data
    "congregate @willowbrook",            # ghost-kitchen facility ("Kitchen"
                                          # in its site would trip the
                                          # RESTAURANT_WORDS exception)
    "downtown humble",                    # district name, not a restaurant
    "old town tomball",                   # district name
    "foodtrucks(multiple)w/outdoorseating",  # placeholder listing
}

# Exception: legitimate restaurants whose names happen to contain a denylist
# brand. If an entry name matches RESTAURANT_WORDS in addition to a deny
# pattern, it survives. Catches real spots like "Robard's Steakhouse"
# (inside Westin) or "Avia Restaurant" (inside Embassy Suites).
RESTAURANT_WORDS = re.compile(
    r"\b(restaurant|bar(?!\s+method)|grill|cafe|kitchen|lounge|steakhouse|diner|"
    r"bistro|brewery|brasserie|tavern|pub|trattoria|pizzeria|pizza|sushi|"
    r"deli|bakery|patisserie|izakaya|cantina|cocina|taqueria|"
    r"churrascaria|coffeehouse|teahouse|smokehouse|alehouse|"
    r"chophouse|brewpub|gastropub|noodle|ramen|hot pot|bbq|barbecue|"
    r"creamery|ice cream|frozen yogurt|donut|donuts|kolache|"
    r"pho|banh mi|sandwich|burger|burgers|wings|tacos|tortas|"
    r"crawfish|seafood|oyster|sushi|dim sum|chicken|hibachi|tap house|"
    r"food (trucks?|halls?|parks?)|"
    # Healthy / modern food terms — added so the broad medical denylist
    # (health/medical/medicine/nutrition) doesn't accidentally drop poke
    # bowls, juice bars, vegan eateries, etc.
    r"bowls?|eatery|eats|juice|smoothie|salads?|wraps?|poke|acai|"
    r"vegan|vegetarian|shakes?|kombucha|crepe|gelato|froyo)",
    re.IGNORECASE,
)


def normalize(s):
    """Strip diacritics for matching: 'Café' / 'Cafè' / 'CAFÉ' all → 'Cafe'.
    Owner-typed restaurant names occasionally use the wrong accent variant
    (è vs é vs ê), so we collapse all of them before pattern matching."""
    return "".join(
        c for c in unicodedata.normalize("NFKD", s)
        if not unicodedata.combining(c)
    )


def should_drop(name):
    """Return (drop, category) for an entry name."""
    normalized = normalize(name)
    name_lower = normalized.lower()
    # Exact-name denylist runs first. These are unambiguous — no
    # RESTAURANT_WORDS exception (the names already don't contain food
    # words; that's why we have to list them out).
    if name_lower.strip() in EXACT_NAME_DENY:
        return (True, "exact-name")
    for pat, category in DENY_PATTERNS:
        if re.search(pat, name_lower):
            # Allow exception: legitimate restaurant inside a hotel/etc keeps
            # itself in if its name contains a real restaurant word.
            if RESTAURANT_WORDS.search(normalized):
                return (False, None)
            return (True, category)
    return (False, None)


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
    dry_run = "--dry-run" in sys.argv
    doc = json.load(open(SEED, encoding="utf-8"))
    before = len(doc["restaurants"])
    print(f"Loaded {before} restaurants from {SEED}")
    if dry_run:
        print("DRY RUN — no changes will be written\n")
    else:
        print()

    kept, dropped = [], []
    drop_by_category = {}
    for r in doc["restaurants"]:
        drop, category = should_drop(r["name"])
        if drop:
            dropped.append((r["name"], category, r["area"]))
            drop_by_category[category] = drop_by_category.get(category, 0) + 1
        else:
            kept.append(r)

    if not dry_run:
        doc["restaurants"] = kept
        doc["restaurants"].sort(key=lambda r: (r["area"], r["name"].lower()))
        tmp = SEED + ".tmp"
        open(tmp, "w", encoding="utf-8").write(serialize(doc))
        os.replace(tmp, SEED)

    verb = "Would drop" if dry_run else "Dropped"
    print(f"{verb} {len(dropped)} non-restaurants. {'After:' if not dry_run else 'New count would be:'} {len(kept)}\n")
    if drop_by_category:
        print("By category:")
        for cat, n in sorted(drop_by_category.items(), key=lambda x: -x[1]):
            print(f"  {n:4d}  {cat}")
    print(f"\nFull list of {'would-be-' if dry_run else ''}dropped entries:")
    for name, cat, area in sorted(dropped, key=lambda x: (x[1], x[0].lower())):
        print(f"  - [{cat:11s}] {name}  ({area})")


if __name__ == "__main__":
    main()
