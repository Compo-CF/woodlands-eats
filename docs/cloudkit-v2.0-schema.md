# CloudKit schema changes for v2.0 (build 63)

TestFlight and App Store builds read the **Production** environment, so every
change below must be deployed to Production before v2.0 ships or the two new
social features degrade gracefully to empty (no crash, but notes/friends
won't persist or aggregate).

Container: `iCloud.com.compofelice.WoodlandsEats`.

The fastest path is the usual one: run a debug build on a real device, exercise
each feature once (which auto-creates the types/fields in **Development**),
then **Deploy Schema Changes → Production**. Manual definitions follow in case
auto-create misses anything.

## Feature 2 — Placement notes

1. **Placement** (existing record type) — add field **`note`** (String).
   - No index needed. Notes are read off Placement records that are already
     fetched by the `restaurantID` Queryable index (community-tier query) or
     by recordName (my-note lookup).
2. **NoteReport** (NEW record type, user-owned) — fields:
   - `placementName` (String) — the owning Placement's recordName.
   - `reporterID` (String).
   - **Requires a Queryable index on the system `recordName` field** — the
     admin queue fetches with a TRUEPREDICATE query (same pattern as
     `PhotoReport`). If PhotoReport's admin queue works in Production, add the
     identical recordName Queryable index here.
3. **AdminExclusion** (existing record type) — **no schema change**. The note
   hide/unhide reuses the existing `kind` (String) + `target` (String) fields
   with the new value `kind = "note"`, `target = <placement recordName>`.

## Feature 3 — Friends / follow graph

4. **FriendList** (NEW record type, user-owned) — fields:
   - `entries` (String List) — each `"userID|displayName"`.
   - `count` (Int64).
   - **No index needed** — read/written only by recordName (`friends_<user>`),
     one record per user, like `VisitedList`.
5. The **Friends board** aggregation reuses the existing **Placement**
   TRUEPREDICATE walk (already backed by the recordName Queryable index added
   for the community board). No new index.

## Summary of required index work

| Action | Type |
|---|---|
| Add `note` String field | Placement |
| Create record type + recordName Queryable index | NoteReport |
| Create record type (no index) | FriendList |
| (none) | AdminExclusion — reuses `kind`/`target` |

## No entitlement / capability changes

Both features use the already-enabled CloudKit public database and the
existing iCloud identity. No new entitlements, App Store Connect products,
Universal Link, or dev-portal capability changes are required for v2.0.
