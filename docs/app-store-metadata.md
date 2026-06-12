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
No social feed. No follower counts. No subscriptions. No advertising. No data brokered to third parties. No real-name accounts.

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
