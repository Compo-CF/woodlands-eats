# Submission Day — End-to-End Guide

The playbook for taking Woodlands Eats from build 14 on TestFlight to live on the App Store. Pull this doc up on your second screen.

## Prerequisites (verify before starting)

- [ ] **Apple Developer Program** active — `developer.apple.com/account`
- [ ] **Two-factor auth** on Apple ID
- [ ] **Build 14 in TestFlight** (build 14 = c33b9be, includes the Report/Block UGC moderation flow)
- [ ] **CloudKit Production schema deployed** for the build-14 record types (see Step 1 below)
- [ ] **GitHub Pages enabled** at the repo: Settings → Pages → Source `main`, folder `/docs` → confirm `https://compo-cf.github.io/woodlands-eats/privacy.html` loads
- [ ] **Latest code pushed** and CI is green
- [ ] **App icon** — already in `WoodlandsEats/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` (tier-stack motif, F is purple as of build 13)

---

## Step 1 — Deploy CloudKit Production schema (build 14 additions)

Build 14 introduces three CloudKit schema additions that must be deployed to **Production** (TestFlight and App Store builds both read Production):

1. **DishPhoto.submitterUserID** (String field on the existing type) — stores the uploader's opaque iCloud user ID so blocks can be enforced.
2. **PhotoReport** (new record type, user-owned) — fields `photoID` (String), `reporterID` (String).
3. **PhotoModerated** (new record type, admin-owned) — fields `photoID` (String), `decision` (String, "hidden" or "approved").

**To deploy:**

1. Open the [CloudKit Console](https://icloud.developer.apple.com/dashboard/) → select container `iCloud.com.compofelice.WoodlandsEats`.
2. Switch to **Development** environment. Open the **Schema** tab.
3. After installing build 14 on a real device and tapping Report on a photo (which will fail silently in Production but auto-create the schema in Development), confirm the new types appear:
   - `PhotoReport` with `photoID`, `reporterID`
   - `PhotoModerated` with `photoID`, `decision`
   - `DishPhoto` should now have a `submitterUserID` field
4. Hit **Deploy Schema Changes → Production**. Apple will confirm the diff before applying.

If the schema doesn't auto-create from Dev usage, you can also add the types manually:
- New Record Type → name `PhotoReport` → add `photoID` (String), `reporterID` (String).
- New Record Type → name `PhotoModerated` → add `photoID` (String), `decision` (String).
- On `DishPhoto`, Add Field → `submitterUserID` (String).

No new Queryable indexes are required for build 14 — the new types are looked up by recordName, which CloudKit indexes by default.

## Step 2 — Confirm build 14 in TestFlight

1. `appstoreconnect.apple.com` → My Apps → (Woodlands Eats) → TestFlight tab.
2. Build 14 should be processed and "Ready to Test." If it says "Missing Compliance," click the build, answer the encryption question (No: no non-exempt encryption), and submit.
3. Install it on your iPhone via the TestFlight app, log in, and confirm:
   - Long-pressing a dish photo shows "Report photo" + "Block this uploader."
   - Profile tab → admin "Photo reports" section renders (admin iCloud only).
   - F-tier pins are visibly purple, distinct from unranked gray.

If any of those fail, fix and bump to build 15 before submitting.

## Step 3 — Capture screenshots on the Mac simulator

5 screenshots at 6.7" iPhone (1290 × 2796 PNG). See `docs/app-store-metadata.md` for the exact list.

On the Mac:

```bash
cd ~/woodlands-eats   # or wherever the local clone lives
git pull --rebase
xcodegen generate
open WoodlandsEats.xcodeproj
```

In Xcode: choose iPhone 16 Pro Max as the simulator target → run. While the simulator's open:
- Manually set up the state for each screenshot (rank some places, place pins, etc.). Use your real iCloud rankings if you're signed in on the simulator — otherwise pre-rank a handful so the screenshots look populated, not empty.
- For each: simulator menu → File → Save Screen (or `xcrun simctl io booted screenshot ~/Desktop/eats-1.png`).
- Trim Apple's automatic statusbar overlay if any — usually fine as-is.

End state: 5 clean PNGs on the desktop, ready to drag into App Store Connect.

## Step 4 — Fill in App Store Connect

Browser, Mac or Windows either works:

1. App Store Connect → My Apps → **+** → New App (if not already created; if you've been using TestFlight, the app record already exists — skip to step 2).
   - Platform: iOS
   - Name: **Woodlands Eats**
   - Primary Language: English (U.S.)
   - Bundle ID: `com.compofelice.WoodlandsEats`
   - SKU: `woodlands-eats-001`
   - User Access: Full Access

2. **App Information** tab — fill all from `docs/app-store-metadata.md`:
   - Subtitle, category (Food & Drink primary, Travel secondary)
   - Privacy Policy URL: `https://compo-cf.github.io/woodlands-eats/privacy.html`
   - Age rating questionnaire — answer UGC = Yes, then Apple lands it at 12+.
   - Content Rights → does your app use third-party content: No.

3. **App Privacy** tab — fill exactly as listed in `docs/app-store-metadata.md` under "App Privacy declaration":
   - Location (Precise) — App Functionality, not linked to identity, not tracking
   - User Content → Photos or Videos
   - User Content → Other User Content
   - Identifiers → User ID
   - Contact Info → Name

4. **App Review Information** tab:
   - Paste the "App Review notes" block from `docs/app-store-metadata.md` into the notes field.
   - Contact: your name + the centricfiber email.
   - Demo account: not needed (no login).

5. **Version Information** ("1.0 Prepare for Submission"):
   - Promotional text + Description + Keywords from the metadata draft.
   - Support URL: GitHub Issues link.
   - Drag in the 5 screenshots.
   - **Build:** pick build 14.

6. **Submit for Review**.

## Step 5 — Wait + watch the inbox

Typical review: 24-48 hours. Apple emails on any state change.

If rejected, the top three first-submission causes for an app like Eats are:
1. **UGC moderation language unclear** — Apple wants the Report + Block flow described in plain English in the App Review notes. The notes block in `docs/app-store-metadata.md` already covers this.
2. **Privacy policy doesn't disclose CloudKit data** — the `docs/privacy.html` already enumerates every CloudKit record type and what's in it.
3. **Screenshots don't match the actual app** — if you rebuild the simulator state and the screenshots show 0 community rankings, Apple may flag it as misleading. Pre-populate some realistic state first.

Fix, bump CFBundleVersion (always bump on every upload — duplicates are auto-rejected), re-archive, resubmit.

## Step 6 — Approval

When Apple approves, the build is "Ready for Sale" but won't release until you tell it to:
- Auto-release on approval (set in App Store Connect → Pricing and Availability), OR
- Manual release (button in Version Information).

For v1.0, manual release is safer — gives you a chance to coordinate the launch.

After release: takes 30 min to a few hours to propagate across the App Store storefronts. Search by `Woodlands Eats` to confirm.

---

## Time estimates (v1.0)

| Stage | Time |
|---|---|
| CloudKit schema deploy | 10 min |
| TestFlight build-14 sanity check | 10 min |
| Screenshot capture | 30 min |
| App Store Connect form fill | 45 min |
| Submit + wait | 24-48 hr |
| **Hands-on total** | **~95 min** |

---

## Subsequent updates (post-v1.0)

| Step | Time |
|---|---|
| Bump `CFBundleVersion` in `project.yml` | 30 sec |
| `xcodegen generate && Product → Archive → Upload` | 15 min |
| If schema changed: deploy to Production | 5 min |
| Version notes in App Store Connect | 5 min |
| Submit | instant |

Approval on point updates is usually faster (12-24 hr) than v1.0.
