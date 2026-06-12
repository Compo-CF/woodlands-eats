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
> 1,800+ restaurants from The Woodlands to Spring, ranked by you on a classic S/A/B/C/F tier list. No stars, no algorithm — just where each spot belongs.

(154 chars — leaves room for seasonal pulls like "Spring crawfish season tier list inside.")

## Description (4000 char limit, plain text only)

```
S-Tier Eats is a restaurant discovery app for The Woodlands, Spring, and the surrounding towns — ranked by you on a classic S/A/B/C/F tier list instead of stars.

WHY A TIER LIST
Five-star ratings smear everything into a featureless 3.9-to-4.4 blob. A tier list forces you to pick: is this place ELITE, or just GREAT, or just FINE? Your tier list becomes a memory of your favorites — and the community average becomes a genuinely useful "is this worth going to" answer.

WHAT'S INSIDE
• 1,800+ restaurants curated across six areas: The Woodlands, Spring, Shenandoah, Oak Ridge North, Old Town Spring, and Klein
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
