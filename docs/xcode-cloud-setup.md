# Xcode Cloud Setup — replacing MacInCloud

This is a one-time setup. After it's done, every `git push` to the right branch
triggers an automatic build on Apple's infrastructure. No Mac required for the
day-to-day cycle.

## What's already in place

- ✅ `ci_scripts/ci_post_clone.sh` — installs XcodeGen and regenerates the
  `.xcodeproj` on every Xcode Cloud worker (workers are stateless, the
  project file isn't in git, so this has to happen before any build runs).
- ✅ `project.yml` — XcodeGen spec, single source of truth for build settings.
- ✅ Apple Developer account with Team ID `7H5T5AR2X5`.
- ✅ App Store Connect record for S-Tier Eats (bundle id
  `com.compofelice.WoodlandsEats`).

## Step 1 — Connect the GitHub repo to Xcode Cloud

ASC has a web UI for this since mid-2024; no Mac needed.

1. **ASC → S-Tier Eats → Xcode Cloud tab** (top of the page, next to TestFlight)
2. Click **Get Started**
3. **Source Code** → pick **GitHub** (or whatever host the repo lives on)
4. Auth the **Apple ↔ GitHub** integration (one-time OAuth) — grants Xcode
   Cloud read access to the specific repository, NOT your entire GitHub account
5. Select the repository: `Compo-CF/woodlands-eats`
6. Apple verifies access. Should take <1 minute.

If it fails: GitHub may need org-level approval if the repo is under a GitHub
organization. For a personal repo it's instant.

## Step 2 — Create the workflows

A "workflow" is a trigger + actions chain. Recommend three:

### Workflow A: "PR Check"
- **Start condition**: Pull request to `main` or `v1.1`
- **Actions**: Build for iOS
- **Post-actions**: (none)
- **Purpose**: Catches compile errors before merge. Doesn't archive or upload.

### Workflow B: "TestFlight"
- **Start condition**: Push to `v1.1` branch
- **Actions**: Archive for iOS
- **Post-actions**: Upload to TestFlight → Internal Testing group
- **Environment variables** (in workflow settings): `CI_INTERNAL_TESTERS_GROUP` =
  the name of the internal testers group in TestFlight (default works for most)
- **Purpose**: Every push to v1.1 builds and lands on your iPhone via
  TestFlight within ~10 minutes. Zero manual steps.

### Workflow C: "App Store Release"
- **Start condition**: Push of a git tag matching `release-*` (e.g. `release-1.2`)
- **Actions**: Archive for iOS
- **Post-actions**: Upload to App Store Connect for review
- **Purpose**: When you're ready to ship a version, tag the commit with
  `git tag release-1.2 && git push origin release-1.2` and the workflow archives
  and uploads. ASC submission flow still manual (Build attach + Submit).

You can configure all three in the same Xcode Cloud setup, or start with just
Workflow B and add the others later.

### Per-workflow settings worth checking

- **macOS version**: Latest stable (Sequoia or newer)
- **Xcode version**: Latest stable that supports iOS 17+ deployment
- **Build number management**: Pick **"Increment build number automatically"**.
  Xcode Cloud bumps CFBundleVersion per build, no manual project.yml edit
  needed each time. Anthony's CI ledger so far has been manual — switching to
  auto keeps it sequential and unique.
  - With this on, the `CFBundleVersion: "36"` in project.yml becomes a starting
    floor; Xcode Cloud increments from there.

## Step 3 — First test build

1. Make a trivial change on the `v1.1` branch (e.g. a comment in a Swift file)
2. `git push origin v1.1`
3. **ASC → S-Tier Eats → Xcode Cloud** — should show a build kicking off within
   a minute
4. Click into the build to watch logs in real-time
5. Should take 6-12 minutes for the first build (cold cache for SPM dependencies)
6. Subsequent builds: 4-8 minutes (warm cache)

If `ci_post_clone.sh` errors out (xcodegen not found, brew install fails, etc),
the log will show exactly where. Common first-run issues:
- **Permission denied on the script** — fixed in this commit (chmod +x)
- **Homebrew not installed** — actually IS preinstalled on Xcode Cloud workers,
  this should never trip
- **Signing failures** — Xcode Cloud manages signing certificates automatically
  if you have a Developer account; first build sometimes needs the workflow's
  "Signing & Capabilities" pane visited

## Step 4 — Cut the MacInCloud cord

Once you've seen one full successful build land on TestFlight via Xcode Cloud,
the MacInCloud subscription is redundant. You can:
- Cancel the MacInCloud subscription
- Keep it active for one billing cycle as backup in case Xcode Cloud chokes
  on something specific to this project
- Or pause the subscription month-to-month if MacInCloud supports it

## Things that DON'T change

- TestFlight on your iPhone is still the interactive testing surface.
- App Store Connect submission flow is the same (Build attach + Submit for
  Review, etc.).
- App Store Analytics is the same.
- The `project.yml` is the source of truth and Xcode Cloud will respect every
  setting you put there.

## Things that DO change for the better

- No more `~/bin/xcodegen generate` manually.
- No more wedged bash sessions on MacInCloud.
- No more "did I forget to bump the build number?" (workflow auto-increments).
- Builds are reproducible — Apple's CI runs from a clean clone every time, so
  there's no "works on my Mac but fails in CI" drift.
- Free tier (25 build hours/month) is more than enough for a solo dev.
- Mac is no longer in the critical path.

## Things to watch out for

- **CloudKit container access**: Xcode Cloud workers have access to the
  CloudKit container `iCloud.com.compofelice.WoodlandsEats` via the Developer
  account. No extra setup needed, but if a build fails with "CloudKit
  entitlement not granted," the fix is to confirm the container is associated
  with the Apple Developer account (it is).
- **AdMob initialization in CI**: AdMob's SDK runs at app startup. If any
  test plans get added later that boot the AdMob SDK, they need the
  `GADApplicationIdentifier` in Info.plist to be valid. It is, no change
  needed.
- **Secrets**: If/when affiliate IDs or API keys move out of source, Xcode
  Cloud has an "Environment Variables → Secret" feature for storing keys
  that get exposed to build scripts via env vars. Not needed today.
