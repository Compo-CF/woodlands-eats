#!/bin/bash
# Build S-Tier Eats and upload it to TestFlight, entirely from the command line (run on the Mac).
#
#   scripts/testflight.sh                 pull, test, archive, upload
#   scripts/testflight.sh --build 42      force a build number
#   scripts/testflight.sh --skip-tests    skip the test step
#   scripts/testflight.sh --no-pull       use the working copy as-is
#   scripts/testflight.sh --upload-only   retry just the upload of the last archive (no rebuild)
#
# Build number defaults to the git commit count (+ BUILD_OFFSET): always increasing, and each
# TestFlight build maps to an exact commit. Uploading the same commit twice is rejected by Apple
# (duplicate build), which is correct: nothing changed.
#
# Signing/upload auth, in order of preference:
#   1. App Store Connect API key with the **Admin** role (App Manager can't use Apple's cloud
#      signing: "Cloud signing permission error"), if ~/.asc-upload.env (shared by every app;
#      ~/.transmute-upload.env is also accepted) defines
#        ASC_KEY_ID=XXXXXXXXXX
#        ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#        ASC_KEY_PATH=$HOME/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
#   2. Otherwise the Apple ID signed into Xcode (Xcode > Settings > Accounts).
#
# Adapted from Transmute's scripts/testflight.sh. Needs Xcode 15.3+. Written for macOS's bash 3.2.
set -euo pipefail

# --- Per-app settings --------------------------------------------------------
APP_NAME="S-Tier Eats"
PROJECT="WoodlandsEats.xcodeproj"
SCHEME="WoodlandsEats"
BUILD_OFFSET=0          # added to the commit count; raise it if App Store Connect already has higher builds
HAS_TESTS=0             # no test target
run_tests() { :; }
# ------------------------------------------------------------------------------

TEAM_ID="7H5T5AR2X5"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO/build"
ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"

ORIG_ARGS=("$@")
BUILD_NUMBER=""
RUN_TESTS=$HAS_TESTS
PULL=1
UPLOAD_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --build) BUILD_NUMBER="$2"; shift 2 ;;
        --skip-tests) RUN_TESTS=0; shift ;;
        --no-pull) PULL=0; shift ;;
        --upload-only) UPLOAD_ONLY=1; PULL=0; RUN_TESTS=0; shift ;;
        -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

step() { printf '\n\033[1;35m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31mFAILED: %s\033[0m\n' "$1" >&2; exit 1; }

cd "$REPO"

# --- 1. Source -------------------------------------------------------------
if [ "$PULL" -eq 1 ]; then
    step "Pulling latest from GitHub ($(git rev-parse --abbrev-ref HEAD))"
    BEFORE="$(git rev-parse HEAD)"
    git pull --ff-only || fail "git pull (local changes or diverged branch?)"
    # bash has already read this file; if the pull changed it, restart on the new version.
    if ! git diff --quiet "$BEFORE" HEAD -- scripts/testflight.sh; then
        echo "testflight.sh was updated; restarting with the new version."
        exec "$0" --no-pull ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
    fi
fi
if [ -n "$(git status --porcelain)" ]; then
    echo "Warning: uncommitted changes in the working copy; they will be included in this build."
fi
COMMIT="$(git rev-parse --short HEAD)"
# Version: MARKETING_VERSION if project.yml has one, else the literal CFBundleShortVersionString.
VERSION="$(grep -E '^[[:space:]]*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)"
if [ -z "$VERSION" ]; then
    VERSION="$(grep -E '^[[:space:]]*CFBundleShortVersionString:' project.yml | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)"
fi
if [ "$UPLOAD_ONLY" -eq 1 ]; then
    [ -d "$ARCHIVE" ] || fail "no archive at $ARCHIVE to upload (run without --upload-only first)"
    PLIST="$ARCHIVE/Info.plist"
    BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$PLIST")"
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$PLIST")"
    COMMIT="(existing archive)"
elif [ -z "$BUILD_NUMBER" ]; then
    BUILD_NUMBER="$(( $(git rev-list --count HEAD) + BUILD_OFFSET ))"
fi
echo "$APP_NAME $VERSION ($BUILD_NUMBER) from commit $COMMIT"

# --- 2. Project --------------------------------------------------------------
if [ "$UPLOAD_ONLY" -eq 0 ]; then
    step "Generating Xcode project"
    if command -v xcodegen >/dev/null 2>&1; then
        XCODEGEN="xcodegen"
    elif [ -x "$HOME/bin/xcodegen" ]; then
        XCODEGEN="$HOME/bin/xcodegen"
    else
        fail "xcodegen not found (looked in PATH and ~/bin)"
    fi
    "$XCODEGEN" generate --quiet
fi

# --- 3. Tests ----------------------------------------------------------------
if [ "$RUN_TESTS" -eq 1 ]; then
    step "Running tests"
    run_tests || fail "tests (or rerun with --skip-tests)"
fi

# --- 4. Auth -----------------------------------------------------------------
AUTH_ARGS=()
for ENV_FILE in "$HOME/.asc-upload.env" "$HOME/.transmute-upload.env"; do
    if [ -f "$ENV_FILE" ]; then
        # shellcheck disable=SC1090
        . "$ENV_FILE"
        break
    fi
done
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_PATH:-}" ]; then
    [ -f "$ASC_KEY_PATH" ] || fail "ASC_KEY_PATH not found: $ASC_KEY_PATH"
    AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH"
               -authenticationKeyID "$ASC_KEY_ID"
               -authenticationKeyIssuerID "$ASC_ISSUER_ID")
    echo "Auth: App Store Connect API key $ASC_KEY_ID"
else
    echo "Auth: Apple ID signed into Xcode"
fi

# --- 5. Archive --------------------------------------------------------------
rm -rf "$EXPORT_DIR"
mkdir -p "$BUILD_DIR"
if [ "$UPLOAD_ONLY" -eq 0 ]; then
    step "Archiving (Release, generic iOS device)"
    rm -rf "$ARCHIVE"
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -archivePath "$ARCHIVE" \
        -allowProvisioningUpdates \
        ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        -quiet \
        || fail "archive (scroll up for the first 'error:' line)"
    BUILT="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE/Info.plist")"
    [ "$BUILT" = "$BUILD_NUMBER" ] \
        || fail "archive has build $BUILT, expected $BUILD_NUMBER (project.yml needs CFBundleVersion: \"\$(CURRENT_PROJECT_VERSION)\")"
fi

# --- 6. Export + upload ----------------------------------------------------------
step "Uploading to App Store Connect"
OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
</dict>
</plist>
EOF
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OPTIONS" \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates \
    ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
    || fail "upload. Read the 'error:' line above:
  'Cloud signing permission error' -> the API key needs the Admin role, not App Manager
  'Failed to Use Accounts'         -> Xcode's saved login is broken: Xcode > Settings > Accounts,
                                      remove all Apple IDs, sign in again (or set up ~/.asc-upload.env,
                                      see the top of this script). Then: scripts/testflight.sh --upload-only
  'bundle version must be higher'  -> this build number is already in App Store Connect
                                      (raise BUILD_OFFSET in this script, or pass --build N)"

step "Done"
echo "Uploaded $APP_NAME $VERSION ($BUILD_NUMBER), commit $COMMIT."
echo "It appears in App Store Connect > TestFlight after processing (usually 5-15 minutes)."
