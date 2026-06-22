# App Store Metadata — S-Tier Eats

Drafts for the fields you'll fill in App Store Connect. Edit before submission. Character limits are Apple's hard caps.

> Note: the app's bundle identifier and CloudKit container stay as
> `com.compofelice.WoodlandsEats` / `iCloud.com.compofelice.WoodlandsEats`
> forever (Apple's accounting + all community data are keyed on them). Only
> the user-facing strings — App Store name, home-screen label, and the
> Map-tab header — read "S-Tier Eats."

---

## App name
**S-Tier Eats**

If taken in the store, fall back to one of: `S-Tier Eats — Tier List`, `S-Tier Eats: Woodlands`, `S-Tier Eats TX`.

## Subtitle (30 char limit)
**The Woodlands & Spring, ranked** — 30 chars ✓

*Alternates:*
- `Rank The Woodlands & Spring` (27)
- `Local restaurants, ranked` (25)
- `Tier-list The Woodlands eats` (28)

## Promotional text (170 chars — editable anytime without review)
> 2,300+ restaurants from The Woodlands to Conroe to Atascocita, ranked by you on a classic S/A/B/C/F tier list. No stars, no algorithm — just where each spot belongs.

(166 chars — leaves room for seasonal pulls like "Spring crawfish season tier list inside.")

## Description (4000 char limit, plain text only)

```
S-Tier Eats is a restaurant discovery app for The Woodlands, Spring, and the surrounding towns — ranked by you on a classic S/A/B/C/F tier list instead of stars.

WHY A TIER LIST
Five-star ratings smear everything into a featureless 3.9-to-4.4 blob. A tier list forces you to pick: is this place ELITE, or just GREAT, or just FINE? Your tier list becomes a memory of your favorites — and the community average becomes a genuinely useful "is this worth going to" answer.

WHAT'S INSIDE
• 2,300+ restaurants curated across ten areas: The Woodlands, Spring, Shenandoah, Oak Ridge North, Old Town Spring, Klein, Conroe, Magnolia, Atascocita, and Montgomery
• Live map with every spot color-coded by your tier (and the unranked ones a neutral gray, so the map becomes a snapshot of your taste over time)
• Distance-sorted list with one-tap Apple Maps directions
• Filters for area, cuisine, price tier, and a fast-food toggle (off by default)
• Dish photos on every restaurant — add your own from your library, see what others have added
• Community Tier List: every restaurant rolled up into the crowd's consensus tier, with a separate "Foodie Pros" view for vetted contributors
• "Permanently closed?" crowd reports surface defunct restaurants with a visible flag
• Suggest a missing restaurant from inside the app — admin-approved entries become public

WHAT'S NOT INSIDE
No social feed. No follower counts. No subscriptions. No personalized tracking. No data brokered to third parties. No real-name accounts.

HOW IDENTITY WORKS
Sign-in is implicit — your iCloud account handles attribution invisibly, so there's no password, no email signup, no profile to maintain. Your rankings sync across your own devices and (anonymously) contribute to the community average. The optional "display name" only appears to the app administrator if you request Foodie Pro status.

COVERAGE EXAMPLES
Fine dining, sushi, BBQ, breakfast spots, Tex-Mex, Vietnamese, food halls, bakeries, and the inevitable chains — categorized so you can filter the fast food out (or in) at any time.

A NOTE ON THE COMMUNITY
This is a tiny, local app made by one person who lives in the area. If you spot a restaurant that should be in here, use "Suggest a restaurant" on the Profile tab. If you spot a permanently-closed listing, hit "Report as permanently closed" on its detail page. The list improves every week because of that.

CONTACT
acompofelice@outlook.com — for bug reports, takedown requests, or anything else.
```

## Keywords (100 char limit, comma-separated, NO spaces after commas)
```
restaurants,woodlands,spring,texas,tier,list,food,dining,bbq,tex-mex,sushi,map,local,eats
```
(95 chars ✓ — note: "S-Tier Eats" already includes the words "top", "tier", and "eats" in the app name itself, so the keyword field doesn't need to repeat them. Apple matches search on name + subtitle + keywords combined.)

## Support URL
`https://github.com/Compo-CF/woodlands-eats/issues`

## Marketing URL (optional)
Skip for v1.0.

## Privacy Policy URL
`https://compo-cf.github.io/woodlands-eats/privacy.html`

(Becomes live after GitHub Pages is enabled — Settings → Pages → Source: `main`, folder: `/docs`.)

## Category
- **Primary:** Food & Drink
- **Secondary:** Travel *(optional)*

## Age Rating
**12+** (because user-generated content can theoretically include anything until moderated). Answer truthfully when the questionnaire asks about "User-Generated Content" — say YES, the app has user content. Apple typically lands this at 12+ for the dish-photo + ranking surface.

## Price tier
**Free**

## Copyright
`© 2026 Anthony Compofelice`

---

## App Privacy declaration (App Store Connect → App Privacy)

This is the questionnaire that's bigger than Fishing's. Walk through it carefully — wrong answers here are a top-5 cause of first-submission rejection.

**Q: Does your app collect data from this app?**
→ **Yes**

**Q: What data does your app collect?**
Check ALL of these, then answer the follow-ups for each:

### 1. Location → Precise Location
- Linked to identity? **No**
- Used for tracking? **No**
- Purpose: **App Functionality**
- Optional? **Yes** (the app still works if denied; just no distance sort or "near me")

### 2. User Content → Photos or Videos (dish photos)
- Linked to identity? **No** (linked only to an opaque iCloud user ID, not to a name/email)
- Used for tracking? **No**
- Purpose: **App Functionality**
- Optional? **Yes** (uploading is a user choice)

### 3. User Content → Other User Content (tier placements, closed-reports, suggestions)
- Linked to identity? **No**
- Used for tracking? **No**
- Purpose: **App Functionality**
- Optional? **Yes**

### 4. Identifiers → User ID (the opaque iCloud user record name)
- Linked to identity? **No** (it's an opaque hash, not your Apple ID)
- Used for tracking? **No**
- Purpose: **App Functionality**

### 5. Contact Info → Name (the optional display name)
- Linked to identity? **No** (self-entered; not verified or tied to your Apple ID)
- Used for tracking? **No**
- Purpose: **App Functionality**
- Optional? **Yes**

Do NOT check: Browsing History, Search History, Health & Fitness, Financial Info, Sensitive Info, Contacts, Diagnostics (unless you add analytics later).

---

## User-Generated Content questionnaire (under App Information → App Review)

Apple asks specifically about UGC. Answer:

**Q: Does your app contain, show, or access user-generated content?**
→ **Yes**

**Q: Have you implemented:**
- [x] A method for filtering objectionable material — *Admin review queue on the Profile tab moderates photo reports within 24 hours.*
- [x] A mechanism for users to flag objectionable content — *Long-press a dish photo → "Report photo."*
- [x] A mechanism for blocking abusive users — *Long-press a dish photo → "Block this uploader." Locally enforced on the reporter's device.*
- [x] Published contact info — *In the privacy policy and in the app description.*

---

## TestFlight "What to Test" notes (for build 14 → first App Store submission)

```
Build 14 — final App Store candidate.

New in this build:
• Long-press a dish photo to report it or block the uploader.
• Admin "Photo reports" section on the Profile tab (admin iCloud only).
• Hidden photos disappear for everyone; blocks are local-only.

Please test:
• Long-pressing a photo shows "Report photo" and "Block this uploader."
• After tapping Report, the photo disappears from your view immediately.
• Block makes that uploader's other photos disappear too (test by uploading two photos from one account, blocking, switching tabs and back).
• Map pins: F-tier should look distinctly purple, unranked stays gray.
• All previous features (suggest, closure reports, Foodie Pro, community board) still work.

Bug reports to acompofelice@outlook.com.
```

---

## Screenshots needed (do these on the Mac via simulator)

**Required: 6.7" iPhone (1290 × 2796 px PNG)** — 3-10 of them. Run the app on iPhone 15/16 Pro Max in the simulator.

Capture exactly these 5:

1. **Map tab** — pan to show The Woodlands + Spring with a healthy mix of colored (your ranked) and gray (unranked) pins. Aim for 30-50 visible pins, not the full 1,400.
2. **Restaurant detail** — open a well-loved spot (e.g., Crisp or Hubbell & Hudson or anything with a community rank + photos). Frame so the header, tier picker, community badge, and "Add" photo button are all visible.
3. **My Tiers** — your personal S/A/B/C/F board with at least a few placements in each tier. Aim for 5-8 restaurants per tier.
4. **Community tab** — show the S/A/B/C/F community board with the "Everyone" / "Foodie Pros" toggle visible at top.
5. **Profile tab** — show the Profile form: Display name field filled, Foodie Pro section, and the "Suggest a missing restaurant" button. *(Don't capture the admin sections — those won't appear under the typical reviewer's iCloud account anyway.)*

Take each one as a clean simulator screenshot (`Cmd+S` in the simulator menu, or `xcrun simctl io booted screenshot ~/Desktop/eats-N.png` from terminal). PNG, no annotations — Apple wants vanilla screenshots.

**Optional but recommended:** Capture the same 5 on an iPad simulator if you want to support iPad. *(Current `project.yml` is iPhone-only, so skip.)*

---

## App Review notes (textbox on Submit screen)

Paste this into the "Notes for the App Review team" field. Reviewers love context — it shortens the review and prevents misunderstandings.

```
Hi reviewer,

S-Tier Eats is a hyperlocal restaurant discovery + S/A/B/C/F tier list
app for The Woodlands and Spring, Texas. It uses CloudKit for the
community features so there's no separate account to create.

Identity: implicit iCloud (no SIWA, no email signup). On first launch
just tap Allow when iOS asks about Location; the app does the rest.

UGC moderation (Guideline 1.2):
• Long-press any dish photo for Report + Block actions.
• Reports route to the admin moderation queue on the Profile tab.
• The admin (me) reviews and responds within 24 hours via the in-app
  Hide control or via the email address below.
• Blocks are local to the reporter's device.

Contact: acompofelice@outlook.com

Thanks!
```

---

# v1.1 Submission Supplement (build 21)

Everything in this section is incremental to the v1.0 (build 19) submission above. Use this checklist the moment v1.0 is approved + released — submit v1.1 the same day so the privacy declaration update lands while you're already in the ASC flow.

> Build history note: build 20 was the first v1.1 binary uploaded but its
> AdMob banner returned no-fill (it reused the Fishing app's ad unit, which
> AdMob server-side binds to Fishing's bundle ID). Build 21 swapped in
> S-Tier Eats's own AdMob app + ad unit. **Submit build 21**, not build 20.

## What's new in v1.1
- AdMob banner ad (single banner, bottom of Map and Browse tabs, non-personalized mode)
- Ko-fi "Buy me a coffee" link prominently on the Profile tab
- About sheet from Profile → About S-Tier Eats
- Native pin clustering on the Map tab (handles the 1,854-pin density gracefully)
- Restaurant detail action row: Call · Directions · Reserve · Order · Website pills, data-aware (only render when the underlying signal supports the action)
- First-tap delivery-app picker (DoorDash vs Uber Eats), persisted in Profile preferences

## Required ASC changes BEFORE submitting build 21

### 1. Description — update one line

Find the "WHAT'S NOT INSIDE" paragraph. Replace `No advertising.` with `No personalized tracking.` The full paragraph becomes:

> No social feed. No follower counts. No subscriptions. No personalized tracking. No data brokered to third parties. No real-name accounts.

(Already updated in this doc.)

### 2. App Privacy declaration — ADD four new data categories

Keep the five entries from v1.0. ADD these four to disclose Google AdMob's SDK behavior. All four are "Linked to user: No" and "Used for tracking: No" because we run AdMob in non-personalized mode without the advertising identifier.

#### 6. Identifiers → Device ID
- Linked to identity? **No**
- Used for tracking? **No**
- Purpose: **Third-Party Advertising** + **Analytics**
- (AdMob receives a per-request device fingerprint to serve and report on the banner ad. Not joined to any of the App's CloudKit data.)

#### 7. Usage Data → Product Interaction
- Linked to identity? **No**
- Used for tracking? **No**
- Purpose: **Third-Party Advertising** + **Analytics**

#### 8. Diagnostics → Crash Data
- Linked to identity? **No**
- Used for tracking? **No**
- Purpose: **App Functionality** + **Analytics**
- (AdMob SDK reports its own crashes to Google.)

#### 9. Diagnostics → Performance Data
- Linked to identity? **No**
- Used for tracking? **No**
- Purpose: **App Functionality** + **Analytics**
- (AdMob SDK reports loading times and rendering performance.)

### 3. Privacy policy URL — already updated

`docs/privacy.html` is already revised for v1.1. The published URL stays the same: `https://compo-cf.github.io/woodlands-eats/privacy.html`. GitHub Pages will redeploy the moment v1.1 is pushed to `main`.

### 4. Promotional text — optional refresh

Current (v1.0) text is fine. If you want to highlight the new actions:

> 1,800+ restaurants from The Woodlands to Spring, ranked by you on a classic S/A/B/C/F tier list. Now with one-tap Call, Reserve, and Order from any restaurant.

(168 chars ✓)

### 5. Keywords — no change

Keep `restaurants,woodlands,spring,texas,tier,list,food,dining,bbq,tex-mex,sushi,map,local,eats`.

### 6. Screenshots — no change required

The action row visually changes the detail-view screenshot, but it's small enough that you can keep the existing 5 screenshots for v1.1. Optional follow-up: re-capture the detail screenshot to include the new pills. Skip for now — ship v1.1 with the existing screenshots and update opportunistically.

## "What's New in This Version" copy

You'll paste this into the release-notes field when you create the v1.1 version in ASC. **Pick one** — option A is fully transparent, option B is silent on the ad, option C frames the ad positively.

### Option A — transparent (recommended)
```
What's new in 1.1:
• Quick actions on every restaurant page: Call, Directions, Reserve a table, or Order delivery — all without leaving the app
• Smarter map: 1,800+ pins now cluster as you zoom out
• Coffee tip jar in Profile — your support keeps the app going
• A small banner ad has been added to help keep the app free

Thanks to everyone who's been ranking. Bug reports always welcome.
```

### Option B — silent on the ad
```
What's new in 1.1:
• Quick actions on every restaurant: Call, Directions, Reserve, Order
• The map now clusters pins as you zoom out for a cleaner overview
• Coffee tip jar in Profile
• Performance and stability improvements
```

### Option C — ad framed positively
```
What's new in 1.1:
• Tap Call, Directions, Reserve, or Order right from any restaurant page
• Smarter map with pin clustering for the 1,800+ spots in the area
• Profile now has a quick coffee tip jar
• A small banner now lives at the bottom of two tabs so the app can stay free — no full-screen ads, no personalized tracking
```

## ASC submission steps (run in order, after v1.0 is live)

1. **App Store Connect → My Apps → S-Tier Eats → + Version or Platform → iOS**
   - Version string: **1.1**
   - Click Create
2. **Description** — paste the updated description (the one-line "No personalized tracking" change is already in this doc).
3. **What's New in This Version** — paste your chosen option above.
4. **Build** — scroll to "Build" section, click **+**, select **build 21** (NOT build 20 — that one's the no-fill version we already obsoleted).
5. **App Privacy** — left sidebar → App Privacy → Edit Data Types. Add the four new categories from §2 above. Save.
6. **Promotional text** — optional refresh from §4.
7. **App Review Information** — keep the v1.0 reviewer notes. Optionally append:
   > v1.1 adds a non-personalized AdMob banner ad on the Map and Browse tabs and an OpenTable / DoorDash / Uber Eats / phone / website action row on each restaurant detail page. No personalized tracking; the App does not request the advertising identifier and does not show an ATT prompt.
8. **Save** → top-right.
9. **Add for Review** → top-right, then **Submit for Review**.
10. Wait ~24-48 hours.

## Things that could trip the review

- **Reviewers occasionally bounce builds that add ad SDKs without an App Privacy update.** This checklist prevents that. Double-check the four new categories are present before submitting.
- **The privacy policy's effective date is now June 4, 2026.** Make sure GitHub Pages has redeployed before submission — visit the URL in a private browser tab and confirm you see "Effective date: June 4, 2026" at the top.
- **If the reviewer asks where the ATT prompt is**, the answer is: there isn't one. AdMob runs in NPA (non-personalized) mode, which by definition doesn't use the IDFA, so no ATT prompt is required. You can preempt this in the reviewer notes (§7 above).

---

# v1.3 Submission Supplement (build 42)

Skips v1.2 from a public-release standpoint — v1.2 (builds 40/41) was
TestFlight-only and is rolled into the v1.3 submission. Existing live
users move from v1.1 → v1.3 in one update.

## What's new in v1.3 (vs v1.1 live)

From the v1.2 work-train:
- Polygon expansion northwest: Montgomery TX, downtown Magnolia,
  Pinehurst, and the Lake Conroe State Park area
- Catalog grew to 2,335 restaurants across ten areas
- Tier-order sort on Browse list (alongside Nearby and A-Z)
- "Mark as visited" toggle with green check on Browse rows
- Catalog cleanup pass (vape, supplements, plazas, private clubs)
- Map style picker (Standard / Hybrid / Satellite) + cluster-list
  fallback at max zoom
- Build 36 hot-fix: My Tiers now restores from CloudKit on launch

From v1.3 proper:
- CloudKit sync for the Visited list (survives reinstall + syncs
  across the user's devices on next launch)
- My Stats screen in Profile (visited count, S/A/B/C/F distribution,
  top cuisines, areas explored)
- 3-screen onboarding flow with in-app location explanation before
  the iOS permission prompt
- "Show app tour" replay in Profile → About

## Required ASC changes BEFORE submitting build 42

### 1. Description — already updated in this doc

The "nine areas" line now reads "ten areas" with Montgomery added.
Inline edit done (search the doc for `ten areas`).

### 2. App Privacy declaration — NO change

The new CloudKit `VisitedList` record type falls under the existing
"Other User Content" declaration (§3 of the v1.0 declaration). No new
data categories collected. No SDK changes since v1.1.

### 3. Promotional text — optional refresh

Current text still accurate. Optional v1.3 refresh:

> 2,300+ restaurants across ten areas — now reaching Montgomery and
> downtown Magnolia. Rank by tier, sync visits across your devices,
> and see your Stats in Profile.

(167 chars ✓)

### 4. Keywords — no change

Keep `restaurants,woodlands,spring,texas,tier,list,food,dining,bbq,tex-mex,sushi,map,local,eats`.

### 5. Screenshots — no change for v1.3 ship

Existing 5 screenshots cover the core surface. Tier sort + visited
check + My Stats are visible additions but not material to the
discovery story. Update opportunistically in a v1.3.1 patch.

### 6. CloudKit production schema — must be deployed BEFORE App Store
release

`VisitedList` record type (fields: `restaurantIDs` LIST<STRING>,
`count` INT<64>) must be deployed to the Production environment of
the iCloud.com.compofelice.WoodlandsEats container BEFORE v1.3 hits
public users. Otherwise visited toggles will silently fail to sync
and badges won't survive reinstall.

CloudKit Console → S-Tier Eats container → Deploy Schema Changes →
confirm VisitedList in the diff → Deploy.

## "What's New in This Version" copy

Live users are on v1.1 (build 36). v1.3 bundles everything since:
catalog cleanups (builds 37/41), map style picker + cluster-list at
max zoom (build 38), polygon expansion + tier sort + visited toggle
(builds 39-41), CloudKit visited sync + My Stats + onboarding refresh
(build 42). The release-notes copy is sectioned by user benefit, not
by build number, so the user can scan it in one breath.

```
v1.3 — a big update with everything we've been working on.

BIGGER MAP
• Coverage expanded northwest to include Montgomery TX, downtown
  Magnolia, Pinehurst, and the Lake Conroe State Park area.
  2,300+ restaurants now span ten areas.
• Map style picker — switch between Standard, Hybrid, and Satellite
  views from the toolbar.
• Pin clusters at max zoom now expand into a tappable list — no
  more clusters you can't drill into.

SMARTER BROWSE
• New Tier sort on the Browse tab — see your S-tier picks at the
  top of the list, alongside the existing Nearby and A-Z sorts.

PERSONAL TRACKING
• Mark restaurants you've visited. A small green check appears
  next to their name on the Browse list so you can see where
  you've been at a glance.
• Your visited list syncs via iCloud — survives reinstall and
  carries across your iPhone and iPad.
• New My Stats screen in Profile: visited count, S/A/B/C/F tier
  distribution, top cuisines, and areas explored.

BETTER FIRST LAUNCH
• Refreshed three-screen onboarding for new users — the location
  prompt now has an in-app explanation first instead of a cold
  iOS dialog.
• Replay the app tour any time from Profile → Show app tour.

CATALOG QUALITY
• Multiple cleanup passes removed non-restaurants that Google's
  data had been lumping in: vape shops, supplement stores,
  shopping plazas, wedding venues, private golf clubs, and more.

Thanks to everyone who's been ranking. Bug reports and restaurant
suggestions always welcome.
```

(1,620 chars ✓ — well under the 4,000 cap)

## App Review notes (append to existing v1.0 notes)

```
v1.3 supplement:

• Geographic expansion — service polygon now reaches Montgomery TX
  and downtown Magnolia. ~2,335 restaurants total across 10 areas.
• New "Visited" personal flag on restaurant detail pages. The flag
  is local-first (UserDefaults) and mirrored to a private CloudKit
  record type (`VisitedList`) so it survives reinstall and syncs
  across the user's own devices. Not exposed to other users; no
  community aggregation.
• "My Stats" screen aggregates the user's tier placements + visited
  list into a read-only dashboard. No new data collection.
• Onboarding now explains location need in-app before iOS prompts.

No new SDKs since v1.1. No new permissions requested. No new
external content. App Privacy declaration unchanged from v1.1.
```

## ASC submission steps (run in order)

1. **App Store Connect → My Apps → S-Tier Eats → + Version**
   - Version string: **1.3**
   - Click Create
2. **What's New in This Version** — paste the v1.3 copy above.
3. **Description** — paste the updated text (the "ten areas" change is
   already inline above; copy the full v1.0 description block with
   that one line replaced).
4. **Build** — click **+**, select **build 42**.
5. **App Privacy** — verify the existing v1.1 categories are still
   accurate. No additions needed for v1.3.
6. **Promotional text** — optional refresh from §3.
7. **App Review Information** — append the v1.3 supplement to the
   existing reviewer notes.
8. **Save** → top-right.
9. **Add for Review** → **Submit for Review**.
10. Wait ~24-48 hours for Apple's response.

## Things that could trip the review

- **Reviewers may ask why the app uses CloudKit when there's no
  visible account.** The implicit-iCloud-identity precedent is
  already in the v1.0 reviewer notes. No change needed unless asked.
- **Make sure CloudKit production schema was deployed BEFORE you
  submit.** If a reviewer marks a restaurant as visited on their
  test device and the badge doesn't survive a relaunch, they may
  flag it as broken. The v1.3 supplement reviewer notes don't
  prevent this — only the schema deploy does.

---

# v1.3.1 Submission Supplement (build 44)

Small fixes-and-polish patch shipped immediately after v1.3 to address
bugs surfaced in the v1.3 TestFlight cycle. No new SDKs, no new
permissions, no metadata-affecting changes beyond What's New.

## What's new in v1.3.1

User-visible:
- **Multi-photo upload** — add up to 5 dish photos in one go. Picker
  switched from single-select to multi-select; uploads run
  sequentially with an X/Y progress indicator on the Add button.
- **Photo-loading polish** — skeleton placeholder while the initial
  CloudKit photo fetch is in flight, so the "No photos yet"
  message no longer flashes for 500ms on every detail-view open.
- **Community tab loads instantly** — stale-while-revalidate cache
  in UserDefaults. First render uses cached data (no spinner);
  fresh data fills in behind. ~2-5s wait → <100ms perceived.
- **Undo "permanently closed" report** — the toggle button has
  always existed in the UI; the underlying ownership check was
  broken (Apple's CloudKit returns `__defaultOwner__` from
  creatorUserRecordID for the user's own records). Fix: parse
  ownership from recordName prefix, same as placements.
- **Foodie Pro requires a full name** — admin can now actually
  verify identity before approval. Validation: ≥2 whitespace-
  separated parts, each ≥2 chars. Section footer warns up front.
- **Closure reports gated by admin review** — user reports
  generate a soft "X reports of possible closure — pending
  review" notice on detail pages, but the red "Permanently
  closed" banner and Browse-list strikethrough only appear after
  admin verification. Drastically reduces false closures.

Admin-only:
- **New Profile section: Pending closure reports** — restaurants
  with user closure reports awaiting admin decision, sorted by
  report count. Confirm / Reject buttons; rejecting silences
  further admin attention without removing the user reports.

## Required ASC changes BEFORE submitting build 44

### 1. Description — no change

`ten areas` already in place from v1.3. Catalog count still 2,617.

### 2. App Privacy — no change

`ClosureDecision` is admin-owned per-restaurant metadata, not user
data. No new collection categories.

### 3. Promotional text — no change required

The v1.3 promo text still applies. Optional refresh:

> 2,300+ restaurants across ten areas. Rank by tier, sync visits,
> add multiple dish photos, see your stats. Now with faster
> community rankings.

(166 chars ✓)

### 4. Screenshots — no change

Same surface as v1.3.

### 5. CloudKit production schema — must deploy `ClosureDecision`
BEFORE submission

New record type for v1.3.1:
  `ClosureDecision`
    fields:
      restaurantID  (String)
      decision      (String — "closed" | "open")

Same deploy flow as `VisitedList` in v1.3:
  Xcode debug build → trigger one Confirm/Reject from admin Profile
  section → confirm Development schema has ClosureDecision → CloudKit
  Console → Deploy Schema Changes → Production.

If schema isn't deployed before the App Store release, admin
Confirm/Reject actions will silently no-op (the existing `try?`
swallows the error) and Browse strikethroughs / closure banners
will never trigger for users.

## "What's New in This Version" copy

v1.3 never publicly shipped — v1.3.1 was queued during v1.3's review,
then v1.3 was pulled in favor of shipping v1.3.1 directly. So v1.3.1's
release notes must cover EVERYTHING since v1.1 (last live), not just
the v1.3.1 deltas. Combined copy below, organized by user benefit.

```
v1.3.1 — a big update with everything we've been working on.

BIGGER MAP
• Coverage expanded northwest: Montgomery TX, downtown Magnolia,
  Pinehurst, and the Lake Conroe State Park area are now in.
  2,600+ restaurants across ten areas.
• Map style picker — switch between Standard, Hybrid, and Satellite
  views from the toolbar.
• Pin clusters at max zoom now expand into a tappable list — no
  more clusters you can't drill into.

SMARTER BROWSE
• New Tier sort on the Browse tab — see your S-tier picks at the
  top of the list, alongside the existing Nearby and A-Z sorts.

PERSONAL TRACKING
• Mark restaurants you've visited. A small green check appears
  next to their name on the Browse list so you can see where
  you've been at a glance.
• Your visited list syncs via iCloud — survives reinstall and
  carries across your iPhone and iPad.
• New My Stats screen in Profile: visited count, S/A/B/C/F tier
  distribution, top cuisines, and areas explored.

FASTER + SMOOTHER
• Community tab loads instantly. Your previous view of the rankings
  appears immediately while fresh data fills in behind the scenes.
• Add up to 5 dish photos at once with a single tap.
• Photo grids no longer flash empty for a moment when opening a
  restaurant.
• Undo a "permanently closed" report you made by mistake — the
  button now toggles between Report and Undo as expected.

BETTER FIRST LAUNCH
• Refreshed four-screen onboarding for new users with a clear
  explanation before the iOS location prompt.
• Replay the tour any time from Profile → Show app tour.

CATALOG QUALITY
• Multiple cleanup passes removed non-restaurants that Google's
  data had been lumping in: vape shops, supplement stores,
  shopping plazas, wedding venues, private golf clubs, and more.
• "Permanently closed" reports are now reviewed before they
  affect the Browse list — false reports no longer surface as
  strikethroughs on restaurants that are still open.

Thanks to everyone who's been ranking. Bug reports and restaurant
suggestions always welcome.
```

(~2,050 chars ✓ well under the 4,000 cap)

## App Review notes (append to existing v1.3 notes)

```
v1.3.1 supplement:

• Multi-photo dish upload (UI-only change; no new permissions).
• Community-tab cache layer (UserDefaults; no new SDKs).
• Closure-report admin moderation: user reports now generate a
  soft "pending review" notice; the red "Permanently closed"
  banner and strikethrough only appear after admin verification
  via a new in-app Profile admin section. New ClosureDecision
  CloudKit record type (admin-owned, like PhotoModerated).
• Bug fix: closure-report ownership check used creatorUserRecordID
  which returns __defaultOwner__ for the user's own records on
  Apple's CloudKit — switched to recordName-prefix ownership
  check (same pattern as placements).
• Foodie Pro request now requires display name to contain ≥2
  whitespace-separated parts so the admin can verify identity.

No new SDKs. No new permissions. No new external content.
App Privacy declaration unchanged from v1.3.
```

## ASC submission steps

1. **App Store Connect → My Apps → S-Tier Eats → + Version**
   - Version string: **1.3.1**
   - Click Create
2. **What's New in This Version** — paste the v1.3.1 copy above.
3. **Description** — no change from v1.3.
4. **Build** — click **+**, select **build 44**.
5. **App Review Information** — append the v1.3.1 supplement.
6. **Save** → top-right.
7. **Add for Review** → **Submit for Review**.
8. Wait ~24-48 hours.

---

# v1.5 Submission Supplement (build 47)

Skips v1.4 as a public release — that train stays in TestFlight only.
Live users move 1.3 → 1.5 in one update, getting the v1.4 rank system
PLUS the v1.5 additions (closure-drop, rank shortcut, milestone
prompts) in a single shot.

## What's new in v1.5 (vs v1.3 live)

From the v1.4 work-train (rolled into this release):
- **Foodie rank progression**: 5-tier system (Newcomer → Foodie →
  Critic → Connoisseur → Tastemaker). Earned by placing restaurants
  in tiers. Hitting a new tier fires a celebration sheet with the
  rank icon + tier color + progress to next.
- **My Stats rank card**: prominent rank display at the top of the
  My Stats screen with a progress bar to the next tier.
- **Profile rank chip**: compact rank badge in the Profile tab
  showing current rank + placement count.

New in v1.5:
- **Quick rank shortcut**: tap the rank icon in the top-left of the
  Map or Browse tab to jump straight to Profile. Hidden for users
  with zero placements (no rank yet to surface).
- **Closed restaurants drop from discovery**: admin-confirmed-closed
  spots no longer appear on the Map or in Browse. They stay in My
  Tiers so personal ranking history is preserved, and remain
  reachable via deep link or via My Tiers tap-through.
- **Closure admin queue polish**: a just-decided closure stays
  cleared from the admin queue even during CloudKit's eventual-
  consistency window (no more 'I just rejected this, why is it back?').
- **Milestone prompts**: Apple's native review prompt fires when a
  user crosses to Critic (15 placements); a Ko-fi support sheet
  fires at Connoisseur (30 placements). Both one-shot per major
  version, both fire after the rank-up celebration dismisses.

## Required ASC changes BEFORE submitting build 47

### 1. Description — no change

`ten areas` from v1.3 still accurate. Catalog count still 2,617.

### 2. App Privacy — no change

No new data types collected. The new review prompt uses Apple's
native API (no developer-visible data); the Ko-fi prompt opens an
external URL (no in-app data captured).

### 3. Promotional text — optional refresh

> Rank restaurants on a tier list and earn your foodie status —
> Newcomer to Tastemaker. 2,300+ spots across ten areas in The
> Woodlands, Spring, Conroe, Magnolia, and more.

(168 chars ✓)

### 4. Screenshots — optional refresh

The Profile + My Stats screens look different with the new rank
card. Existing screenshots cover the core surface so re-shoot is
optional. If you want one refresh: the Profile screen with the
rank chip visible is the best showcase.

### 5. CloudKit production schema — no change

v1.5 adds zero new record types. The `ClosureDecision` type from
v1.3.1 is the most recent schema work; that's already deployed.

## "What's New in This Version" copy

```
v1.5 — earn your foodie rank

YOUR FOODIE RANK
• Five tiers — Newcomer, Foodie, Critic, Connoisseur, Tastemaker —
  earned by placing restaurants on your tier list. Hit a new tier
  and a little celebration fires.
• See your current rank in three places: a tap-target icon on the
  Map and Browse tabs (top-left, jumps you to Profile), the Profile
  tab itself, and a progress card on My Stats showing how close you
  are to the next tier.

CLEANER DISCOVERY
• Restaurants confirmed permanently closed now drop from the Map
  and Browse list. They stay in your My Tiers list so your personal
  ranking history is preserved.
• Quick tap on the rank icon in the top-left jumps you to the
  Profile tab without scrolling through the tab bar.

UNDER THE HOOD
• Smoother admin closure queue — just-decided spots stay gone even
  during the brief CloudKit sync window.
• Smarter prompts: we'll occasionally ask if you'd rate the app
  (Apple's standard prompt, capped to a few times a year) or want
  to tip the developer — both fired at meaningful milestones, both
  easy to skip.

Thanks to everyone who's been ranking. The catalog keeps getting
tighter because of you.
```

(~1,330 chars ✓)

## App Review notes (append to existing notes)

```
v1.5 supplement:

• Adds a 5-tier rank progression (Newcomer/Foodie/Critic/
  Connoisseur/Tastemaker) computed client-side from the user's
  tier-placement count. Tier-up celebration sheet fires from
  ContentView when the rank changes.
• Adds two milestone prompts wired into the celebration dismissal:
  Apple's native @Environment(\\.requestReview) at Critic tier (15
  placements), and a custom Ko-fi support sheet at Connoisseur (30
  placements). Both gated by per-major-version @AppStorage flags
  so they fire once each. The review prompt uses Apple's standard
  API only; no custom App Store deep link.
• Confirmed-closed restaurants (ClosureDecision decision='closed')
  drop from RestaurantStore.filteredRestaurants so Map + Browse no
  longer surface them. My Tiers reads restaurants directly to
  preserve the user's personal history.
• Adds a top-left ToolbarItem on Map + Browse showing the user's
  rank icon; tap programmatically switches the TabView selection
  to .profile via a new EnvironmentValues.tabSelection binding.
• Includes ALL features from the v1.4 TestFlight train (which was
  never publicly released): foodie rank progression, celebration
  sheet, rank card on My Stats, rank chip on Profile.

No new SDKs. No new permissions. No new external content. No new
CloudKit record types. App Privacy declaration unchanged from v1.3.
```

## ASC submission steps

1. **App Store Connect → My Apps → S-Tier Eats → + Version**
   - Version string: **1.5**
   - Click Create
2. **What's New** — paste the v1.5 copy above
3. **Description** — no change from v1.3
4. **Build** — click **+** → select **build 47**
5. **App Review Information** — append v1.5 supplement
6. **Save** → top-right
7. **Add for Review** → **Submit for Review**

## Things that could trip the review

- **Reviewers occasionally flag review-prompt placement.** Apple's
  guideline says don't ask for a review at frustration moments or
  on every launch. Ours fires at a positive milestone (tier-up)
  with the OS-level 3/year cap behind it. Note this in reviewer
  notes (already included above).
- **Ko-fi external link is fine.** Physical-service tip jar opens
  in Safari, no IAP entitlement needed (covered under Guideline
  3.1.3(e) like the Amazon Associates precedent).
