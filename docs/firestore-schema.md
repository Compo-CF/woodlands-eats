# Firestore Schema — S-Tier Eats Cross-Platform Migration

Source of truth for the Firestore data model that replaces CloudKit during
the iOS → cross-platform migration (paving the way for Android v1.0).

> Companion to `app-store-metadata.md`. Treat as the canonical reference
> when wiring iOS dual-write, building the Android client, and writing
> Firestore Security Rules.

## Why Firestore

CloudKit is Apple-only. Android (and any future web/Windows client)
cannot read CloudKit data. Firestore is Google's NoSQL cross-platform
document database with SDKs for iOS, Android, Web, and server-side. The
identity model (Firebase Authentication with anonymous auth) maps well
to CloudKit's implicit per-iCloud-account attribution: the user never
sees a sign-in flow, but each device gets a stable identifier.

**Free-tier capacity (Spark plan):**
- Firestore: 50K reads/day, 20K writes/day, 1 GB storage
- Authentication: unlimited anonymous auth
- Cloud Storage (photos): 5 GB free
- Plenty of headroom up to ~1,000 active users

## Identity model

| Concept | CloudKit | Firestore |
|---|---|---|
| User identifier | iCloud user record name (opaque hash) | Firebase Anonymous Auth UID |
| Per-device or per-account? | Per-account (iCloud-shared) | Per-installation by default; we override to be per-account |
| Cross-device sync | Automatic via iCloud | Manual via iCloud Key-Value Store as broker for the Firebase UID |
| Admin recognition | Hardcoded `adminUserIDs: Set<String>` in iOS | `users/{uid}.isAdmin = true` field in Firestore + security rules |

**Cross-device identity flow:**
1. App launches, checks iCloud KVS for an existing `firebaseUID` key.
2. If present: sign in with that UID (Firebase Anonymous Auth restored from custom token if needed, or use stored credential).
3. If not present: do a fresh anonymous auth → store the resulting UID in iCloud KVS so the user's other devices pick it up.
4. iCloud KVS sync is automatic and free; small key/value writes propagate within seconds.

For users without iCloud signed in: per-device Firebase UID (no
cross-device sync). Matches today's CloudKit fallback behavior.

## Collection-by-collection schema

All collections use lowercase camelCase names. Document IDs use
predictable composite patterns where possible (so we can fetch a record
directly without queries).

### 1. `placements`

User-placed tier rankings. Drives both "My Tiers" (per-user view) and
the Community board (per-restaurant consensus).

```
Document ID:  {userID}_{restaurantID}
Fields:
  userID         string
  restaurantID   string
  tier           string    "S" | "A" | "B" | "C" | "F"
  score          number    5 | 4 | 3 | 2 | 1
  note           string?   optional "why" behind the placement (v2.0), max 280 chars.
                           Absent field = no note; cleared via FieldValue.delete().
  createdAt      timestamp
  updatedAt      timestamp
```

**Read patterns:**
- My placements: `where userID == auth.uid`
- Community consensus for a restaurant: `where restaurantID == X` then average `score`
- Foodie Pros consensus: filter the above by the set of UIDs in `proApprovals`

### 2. `closureReports`

User reports a restaurant as permanently closed.

```
Document ID:  {userID}_{restaurantID}
Fields:
  userID         string
  restaurantID   string
  createdAt      timestamp
```

**Read patterns:**
- Count reports per restaurant: aggregation
- "Did I report this?": existence check on the composite doc ID

### 3. `closureDecisions`

Admin verdict on whether a restaurant is permanently closed. One doc
per restaurant, admin-owned.

```
Document ID:  {restaurantID}
Fields:
  restaurantID   string
  decision       string    "closed" | "open"
  decidedAt      timestamp
  adminID        string
```

**Read pattern:** all confirmed-closed: `where decision == "closed"` —
mirrors today's `CloudKitService.confirmedClosedIDs`. Drives Browse/Map
strikethrough + drop.

### 4. `profiles`

User identity card + Foodie Pro request status.

```
Document ID:  {userID}
Fields:
  userID         string
  displayName    string    self-entered, e.g., "Anthony Compofelice"
  status         string    "" | "requested" | "approved"
  createdAt      timestamp
  updatedAt      timestamp
```

Note: `status` is owner-writable for `""` and `"requested"`; only the
admin can write `"approved"`. Enforced via security rules.

### 5. `proApprovals`

Admin verdict that a user is an approved Foodie Pro. Existence of the
doc = approved. Separate from `profiles` so the write authority is
clearly admin-only.

```
Document ID:  {userID}
Fields:
  userID         string
  approvedAt     timestamp
  approvedBy     string    admin UID
```

### 6. `dishPhotos`

User-uploaded dish photo metadata. Binary lives in Firebase Cloud
Storage; this collection stores the metadata + path.

```
Document ID:  auto-generated
Fields:
  restaurantID       string
  submitterUserID    string
  caption            string?     optional, max ~140 chars in UI
  storagePath        string      "dishPhotos/{photoID}.jpg" in Cloud Storage
  uploadedAt         timestamp
```

**Android v1.0**: read-only (display photos, no upload). iOS continues
to handle the upload flow. Android v1.1 may add upload.

### 7. `photoReports`

User reports a dish photo as objectionable. App Review Guideline 1.2
compliance.

```
Document ID:  {reporterID}_{photoID}
Fields:
  photoID        string
  reporterID     string
  createdAt      timestamp
```

### 8. `photoModerated`

Admin verdict on a reported photo. Hidden photos are filtered out for
all users; approved photos drop out of the admin review queue but stay
visible.

```
Document ID:  {photoID}
Fields:
  photoID        string
  decision       string    "hidden" | "approved"
  decidedAt      timestamp
  adminID        string
```

### 9. `suggestions`

User-submitted "missing restaurant" suggestions. `SuggestionDismissed`
from CloudKit merges in here as `status: "rejected"` — one less
collection.

```
Document ID:  auto-generated
Fields:
  name              string
  address           string
  area              string         e.g., "woodlands" (matches iOS Area enum rawValue)
  cuisines          array<string>  e.g., ["bbq", "american"]
  description       string
  submitterUserID   string
  status            string         "pending" | "approved" | "rejected"
  createdAt         timestamp
```

**Admin queue**: `where status == "pending"` ordered by `createdAt` desc.

### 10. `liveRestaurants`

Admin-approved community-suggested restaurants. Merged into the
client-side catalog at launch (alongside the bundled
`Restaurants.json` seed).

```
Document ID:  {restaurantID}   (UUID assigned at approval time)
Fields:
  name                  string
  latitude              number
  longitude             number
  area                  string
  address               string
  cuisines              array<string>
  priceTier             string     "$" | "$$" | "$$$" | "$$$$"
  isFastFood            boolean
  website               string?
  phone                 string?
  description           string
  signatureDishes       array<string>
  reservable            boolean?
  delivery              boolean?
  takeout               boolean?
  dineIn                boolean?
  approvedAt            timestamp
  approvedBy            string     admin UID
  originalSuggestionID  string     reference back to suggestion doc
```

### 11. `visitedLists`

Per-user "I've been here" set. Single doc per user (small payload, no
per-restaurant atomicity needed since it's purely personal data).

```
Document ID:  {userID}
Fields:
  userID         string
  restaurantIDs  array<string>    UUIDs as strings, deduplicated
  count          number
  updatedAt      timestamp
```

### 12. `dietaryTags` (v2.4)

Community-confirmed dietary/needs tags per restaurant. One doc per
(user, restaurant, tag) so confirmations dedupe and count.

```
Document ID:  {userID}_{restaurantID}_{tag}
Fields:
  userID         string
  restaurantID   string
  tag            string     DietaryTag rawValue: "glutenFree" | "vegetarian"
                            | "vegan" | "allergyAware" | "halal" | "kidFriendly"
                            | "kosher"
  updatedAt      timestamp
```

**Read patterns:**
- Per-restaurant tag counts: `where restaurantID == X`, group by `tag`.
- "Did I confirm this tag?": existence check on the composite doc ID.

### 13. `friendLists` (v2.0 Feature 3)

Per-user follow graph. Single doc per user; each entry encodes
`"userID|displayName"` (the display name is a cached snapshot for offline
list rendering — the authoritative name still comes from the followee's
`profiles` doc).

```
Document ID:  {userID}
Fields:
  userID         string
  entries        array<string>    ["<uid>|<displayName>", ...]
  count          number
  updatedAt      timestamp
```

### 14. `noteReports` (v2.0 Feature 2)

User reports a placement's note as objectionable. Idempotent per
(reporter, placement). The reported note lives inside the owning
placement doc (`placements.note`), so the report stores that placement's
composite doc ID as `placementName`.

```
Document ID:  {reporterID}_{placementName}
Fields:
  placementName  string     the reported placement's doc ID / recordName
  reporterID     string
  createdAt      timestamp
```

### 15. `adminExclusions` (v1.8 integrity + v2.0 note-hide)

Admin-owned integrity markers that every client filters against when
computing community aggregates. Replaces CloudKit's `AdminExclusion`.

```
Document ID:  {kind}_{target}
Fields:
  kind           string     "user" | "placement" | "note"
  target         string     userID (kind=user) | placement doc ID (placement/note)
  adminID        string
  createdAt      timestamp
```

- `kind == "user"`   → all of `target`'s placements stop counting (ban).
- `kind == "placement"` → that single rating stops counting.
- `kind == "note"`   → that placement's *note text* is suppressed
  everywhere; its tier still counts.

### Auxiliary: `users` (admin flag store)

Replaces the hardcoded `adminUserIDs: Set<String>` in the iOS
`CloudKitService`. Admins are flagged here; security rules read this to
authorize admin-only writes.

```
Document ID:  {userID}
Fields:
  userID         string
  isAdmin        boolean
  createdAt      timestamp
```

**Bootstrap**: after the v1.6 migration ships and Anthony's first
launch creates his Firebase UID, manually set `isAdmin: true` on that
UID via the Firestore Console.

## CloudKit → Firestore mapping summary

| CloudKit record type | Firestore collection | Doc ID pattern |
|---|---|---|
| `Placement` | `placements` | `{userID}_{restaurantID}` |
| `ClosureReport` | `closureReports` | `{userID}_{restaurantID}` |
| `ClosureDecision` | `closureDecisions` | `{restaurantID}` |
| `FoodieProfile` | `profiles` | `{userID}` |
| `ProApproval` | `proApprovals` | `{userID}` |
| `DishPhoto` | `dishPhotos` + Cloud Storage | auto |
| `PhotoReport` | `photoReports` | `{reporterID}_{photoID}` |
| `PhotoModerated` | `photoModerated` | `{photoID}` |
| `RestaurantSuggestion` | `suggestions` (with `status` field) | auto |
| `SuggestionDismissed` | *(merged into `suggestions.status = "rejected"`)* | — |
| `LiveRestaurant` | `liveRestaurants` | `{restaurantID}` |
| `VisitedList` | `visitedLists` | `{userID}` |
| `DietaryTag` | `dietaryTags` | `{userID}_{restaurantID}_{tag}` |
| `FriendList` | `friendLists` | `{userID}` |
| `NoteReport` | `noteReports` | `{reporterID}_{placementName}` |
| `AdminExclusion` | `adminExclusions` | `{kind}_{target}` |

16 CloudKit types → 15 Firestore collections + 1 auxiliary `users`
collection. (`SuggestionDismissed` merges into `suggestions.status`.)

**Not mirrored (structured dual-write covers structured data only):**
- `DishPhoto` **binary** — the CKAsset image needs Firebase Cloud Storage
  (upload JPEG, store download URL). The `dishPhotos` metadata collection
  exists in this schema but iOS does not yet write to it; tracked as its
  own task. Photo *reports* and *moderation* ARE mirrored.
- Suggestion approve/reject **status flips** — the Firestore `suggestions`
  doc uses an auto-ID that doesn't equal the CloudKit recordName, so the
  admin marker can't target it yet. Reconciled during Phase 3 backfill.

## Migration rollout plan

| Phase | Version | iOS behavior | Risk |
|---|---|---|---|
| **Today** | v1.5 (live) | CloudKit read + write | n/a |
| **Dual-write** | v1.6 | CloudKit read + write, also write to Firestore in parallel. One-time CloudKit→Firestore backfill on first launch. | Low — Firestore is shadow-only, CloudKit is authoritative |
| **Soak** | v1.6 in prod | 2-3 weeks of dual-write running. Monitor Firestore parity with CloudKit. | Low |
| **Read-cutover** | v1.7 | Read from Firestore. Write to both stores still. | Medium — first time users see Firestore-sourced data; rollback to v1.7.1 reverts to CloudKit reads if needed |
| **CloudKit removal** | v1.8 | Firestore only. CloudKit code deleted. | Low — Firestore has been the read source for weeks |
| **Android v1.0** | — | Native Kotlin/Compose app, Firestore-only. | Independent of iOS schedule |

## Migration safety guarantees

1. **No data loss for existing users**: migration COPIES from CloudKit
   to Firestore. Originals stay untouched. CloudKit is the safety net
   through v1.7.
2. **Silent first-launch**: no setup UI, no auth prompt, no "create an
   account" — anonymous Firebase Auth on first launch is invisible.
3. **Cross-device continuity**: Firebase UID stored in iCloud KVS, so a
   user's iPhone and iPad arrive at the same Firebase identity.
4. **Idempotent migration**: tracked per-record in `@AppStorage`. If
   interrupted, resumes safely on next launch.
5. **Skippable versions**: if a user updates v1.5 → v1.7 (skipping
   v1.6), v1.7's first launch runs the same migration. Same outcome.
6. **No iCloud account = per-device identity**: graceful fallback,
   matches today's CloudKit behavior for that edge case.

## Free-tier capacity check (at current scale)

Sample load — 100 active users × 5 sessions/week:

| Operation | Per session | Daily total | Spark limit | Headroom |
|---|---|---|---|---|
| Reads (catalog merge, visited restore, tier restore, community refresh) | ~5 | ~360 | 50K | 99% |
| Writes (place a tier, mark visited, occasional closure report) | ~3 | ~210 | 20K | 99% |
| Storage growth | — | tiny | 1 GB | ~99% (current catalog metadata < 10 MB) |
| Photo storage | — | varies | 5 GB | depends on uploads |

You can grow ~10× before hitting Spark limits and need to consider
upgrading to Blaze (pay-as-you-go; still well under $5/mo at that
scale).

## Security rules (sketch — implementation in `firestore.rules`)

```javascript
// Pseudo-rules. Real implementation goes in firestore.rules deployed
// via Firebase CLI.

placements:    write if request.auth.uid == resource.data.userID
               read  if true
closureReports: write if request.auth.uid == resource.data.userID
                read  if request.auth.uid == resource.data.userID || isAdmin()
closureDecisions: write if isAdmin()
                  read  if true
profiles:      write if request.auth.uid == resource.data.userID
                      && (request.resource.data.status != "approved" || isAdmin())
               read  if true
proApprovals:  write if isAdmin()
               read  if true
dishPhotos:    write if request.auth.uid == resource.data.submitterUserID
               read  if true
photoReports:  write if request.auth.uid == resource.data.reporterID
               read  if isAdmin()
photoModerated: write if isAdmin()
                read  if true
suggestions:   write if request.auth.uid == resource.data.submitterUserID
                      && (request.resource.data.status == "pending" || isAdmin())
               read  if true
liveRestaurants: write if isAdmin()
                 read  if true
visitedLists:  read, write if request.auth.uid == resource.data.userID
dietaryTags:   write if request.auth.uid == resource.data.userID
               read  if true
friendLists:   write if request.auth.uid == userID
               read  if true
noteReports:   write if request.auth.uid == resource.data.reporterID
               read  if isAdmin()
adminExclusions: write if isAdmin()
                 read  if true

function isAdmin() {
  return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true;
}
```

## Indexes (to declare in `firestore.indexes.json`)

Single-field indexes are auto-created by Firestore. Only declare
composites where compound queries require them:

- `placements`: `(restaurantID, score)` ascending — for community
  consensus aggregation
- `suggestions`: `(status, createdAt)` for the admin pending queue
  ordered by submission date

## Implementation order

A1. ✅ Schema documented in this file
A2. Add Firebase SDK to iOS via SPM, create `FirebaseService.swift`
    mirroring `CloudKitService`'s public API. Dual-write every existing
    `CloudKitService.save*` method.
A3. Build the one-time CloudKit→Firestore backfill (
    `MigrationService.swift`). Tracks per-record state in
    `@AppStorage("WoodlandsEats.migration.v1.6.state")`.
A4. Soak v1.6 in production for 2-3 weeks. Spot-check parity.
A5. Read-cutover in v1.7. Add a kill-switch `@AppStorage` flag so we
    can revert to CloudKit reads if Firestore shows problems.
A6. Scaffold Android Kotlin/Compose project. Set up the same Firebase
    project for Android.
A7. Build Android v1.0 screens.
A8. Submit to Play Store.
A9. Remove CloudKit code in iOS v1.8 once Android is alive and
    Firestore reads have been stable for a release cycle.

## Open questions to resolve before A2

- **Firestore project ID** confirmed as `fir-tier-eats`. Reference this
  in iOS GoogleService-Info.plist and Android google-services.json.
- **Admin bootstrap timing**: do it manually after Anthony's first
  v1.6 launch creates his Firebase UID. Need to make this clear in the
  release notes for Anthony's own reference (not user-facing).
- **AdMob on Android**: separate Android ad unit IDs needed in AdMob
  console. Use the same publisher account.
