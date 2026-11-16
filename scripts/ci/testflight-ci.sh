#!/usr/bin/env bash
# TestFlight from a GitHub macOS runner (.github/workflows/ios-release.yml), manual signing:
# the shared Apple Distribution cert (temp keychain, set up by the workflow) + the API-made
# App Store profile "S-Tier Eats AppStore CI" (~/appstoreconnect/ci_signing.py on Windows).
# The Mac keeps using scripts/testflight.sh (automatic signing).
# Build number = git commit count (same rule as testflight.sh). Env: ASC_KEY_ID, ASC_ISSUER_ID,
# ASC_KEY_PATH. Pass --no-upload to stop after a signed export.
set -euo pipefail
cd "$(dirname "$0")/../.."
UPLOAD=1; [ "${1:-}" = "--no-upload" ] && UPLOAD=0
TEAM_ID="7H5T5AR2X5"
BUNDLE_ID="com.compofelice.WoodlandsEats"
APP_PROFILE="S-Tier Eats AppStore CI"
BUILD_DIR="build"; ARCHIVE="$BUILD_DIR/WoodlandsEats.xcarchive"; EXPORT_DIR="$BUILD_DIR/export"
mkdir -p "$BUILD_DIR"

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate
# project.yml commits aps-environment=development (the Mac's automatic signing promotes it on export).
# The App Store profile carries "production" and manual signing needs an exact match: CI-only edit of
# the generated (gitignored) entitlements file.
/usr/libexec/PlistBuddy -c "Set :aps-environment production" WoodlandsEats/WoodlandsEats.entitlements

BUILD_NUMBER="$(git rev-list --count HEAD)"
VERSION="$(grep -E '^ *CFBundleShortVersionString:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
echo "S-Tier Eats $VERSION ($BUILD_NUMBER)"

# Never ship a placeholder AdMob app id (crashes at launch).
grep -qE 'GADApplicationIdentifier: *ca-app-pub-[0-9]+~[0-9]+' project.yml || { echo "GADApplicationIdentifier missing/placeholder"; exit 1; }

AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

xcodebuild archive \
  -project WoodlandsEats.xcodeproj -scheme WoodlandsEats -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$ARCHIVE" \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution" DEVELOPMENT_TEAM="$TEAM_ID" \
  STIER_APP_PROFILE="$APP_PROFILE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  > "$BUILD_DIR/archive.log" 2>&1 || true
[ -d "$ARCHIVE" ] || { echo "archive failed"; grep -E "error:" "$BUILD_DIR/archive.log" | sort -u | head -40; tail -30 "$BUILD_DIR/archive.log"; exit 1; }
BUILT="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE/Info.plist")"
[ "$BUILT" = "$BUILD_NUMBER" ] || { echo "archive has build $BUILT, expected $BUILD_NUMBER"; exit 1; }

DEST=export; [ "$UPLOAD" -eq 1 ] && DEST=upload
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>$DEST</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Apple Distribution</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>$BUNDLE_ID</key><string>$APP_PROFILE</string>
    </dict>
    <key>uploadSymbols</key><true/>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
set +e
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR" "${AUTH[@]}" > "$BUILD_DIR/upload.log" 2>&1
RC=$?
set -e
tail -25 "$BUILD_DIR/upload.log"
[ "$RC" -eq 0 ] || { echo "export/upload failed (rc $RC)"; grep -E "error" "$BUILD_DIR/upload.log" | head -20; exit 1; }
if [ "$UPLOAD" -eq 0 ]; then
  IPA="$(ls "$EXPORT_DIR"/*.ipa)"; echo "Signed IPA: $IPA ($(du -h "$IPA" | cut -f1))"
  unzip -q -o "$IPA" -d "$BUILD_DIR/ipa"
  codesign -dvv "$BUILD_DIR"/ipa/Payload/*.app 2>&1 | grep -E "Authority|TeamIdentifier|Identifier" || true
  codesign -d --entitlements :- "$BUILD_DIR"/ipa/Payload/*.app 2>/dev/null | grep -A1 aps-environment || true
fi
echo "Done: S-Tier Eats $VERSION ($BUILD_NUMBER) $( [ "$UPLOAD" -eq 1 ] && echo 'uploaded to TestFlight' || echo exported )."
