#!/bin/zsh
# Builds a Release app, signs it with Developer ID, optionally notarizes, packages a DMG,
# and optionally publishes it on beardfm.app: the download for new users plus a Sparkle update
# for existing users.
#
# Usage:  Tools/release.sh [--notarize] [--upload]
#   --notarize   uses the notarytool keychain profile in $NOTARY_PROFILE (default "ipodpromax-notary",
#                the team-wide profile shared with iPod Pro Max, Shortcuts Menu and Leveler). Create one with:
#                xcrun notarytool store-credentials <name> --apple-id you@example.com --team-id J9228F689B
#   --upload     (requires --notarize) signs the DMG for Sparkle with the EdDSA key in the keychain
#                (account "transcriber"), copies it into the beardfm.app site as downloads/Transcriber-<version>.dmg
#                and downloads/Transcriber.dmg, adds it to transcriber/appcast.xml (with release-notes/<version>.html
#                if present), and deploys the site with `npm run deploy`. Commit the beardfm.app changes afterwards.
#
# Output: dist/Transcriber <version>.dmg
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SITE="${BEARDFM_SITE:-$HOME/Movies/Apps/beardfm.app}"
NOTARIZE=0
UPLOAD=0
for arg in "$@"; do
  case "$arg" in
    --notarize) NOTARIZE=1 ;;
    --upload) UPLOAD=1 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done
[[ $UPLOAD -eq 1 && $NOTARIZE -eq 0 ]] && { echo "--upload requires --notarize so users never get an unnotarized build."; exit 1; }
NOTARY_PROFILE="${NOTARY_PROFILE:-ipodpromax-notary}"

BUILD="$ROOT/build/release"
DIST="$ROOT/dist"
rm -rf "$BUILD"
mkdir -p "$BUILD" "$DIST"

echo "▶ Building Release…"
xcodebuild -project "Transcriber.xcodeproj" -scheme "Transcriber" -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$BUILD/DerivedData" build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES 2>&1 | grep -E "error:|BUILD" || true

APP="$BUILD/DerivedData/Build/Products/Release/Transcriber.app"
[[ -d "$APP" ]] || { echo "Build failed: app not found"; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILDNUM=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
echo "▶ Version $VERSION ($BUILDNUM)"

DEVID=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
[[ -n "$DEVID" ]] || { echo "No Developer ID Application certificate found in the keychain."; exit 1; }
echo "▶ Signing with $DEVID"
# Sign Sparkle's nested code inside-out (per Sparkle's docs), then the app.
# No entitlements: the app is unsandboxed and needs no hardened-runtime exceptions.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign() { codesign --force --options runtime --timestamp --sign "$DEVID" "$@"; }
sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
sign "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [[ $NOTARIZE -eq 1 ]]; then
  echo "▶ Notarizing app…"
  ZIP="$BUILD/app.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
fi

echo "▶ Packaging DMG…"
STAGE="$BUILD/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/Transcriber $VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Transcriber" -srcfolder "$STAGE" -ov -format UDZO -imagekey zlib-level=9 "$DMG" > /dev/null
codesign --force --timestamp --sign "$DEVID" "$DMG"
if [[ $NOTARIZE -eq 1 ]]; then
  echo "▶ Notarizing DMG…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

if [[ $UPLOAD -eq 1 ]]; then
  [[ -d "$SITE/site/static" ]] || { echo "beardfm.app site not found at $SITE (set BEARDFM_SITE)."; exit 1; }
  SPARKLE_BIN=$(find "$BUILD/DerivedData/SourcePackages/artifacts" -type d -name bin -path "*parkle*" | head -1)
  [[ -x "$SPARKLE_BIN/sign_update" ]] || { echo "Sparkle's sign_update tool wasn't found."; exit 1; }
  echo "▶ Signing update for Sparkle…"
  SIGNATURE=$("$SPARKLE_BIN/sign_update" --account transcriber "$DMG")
  MIN_MACOS=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$APP/Contents/Info.plist")
  UPDATE_NAME="Transcriber-$VERSION.dmg"

  echo "▶ Copying into beardfm.app…"
  mkdir -p "$SITE/site/static/downloads" "$SITE/site/static/transcriber"
  cp "$DMG" "$SITE/site/static/downloads/$UPDATE_NAME"
  cp "$DMG" "$SITE/site/static/downloads/Transcriber.dmg"

  echo "▶ Publishing Sparkle update…"
  NOTES=()
  [[ -f "$ROOT/release-notes/$VERSION.html" ]] && NOTES=("$ROOT/release-notes/$VERSION.html")
  "$ROOT/Tools/update-appcast.py" "$SITE/site/static/transcriber/appcast.xml" "$VERSION" "$BUILDNUM" "$MIN_MACOS" \
    "https://beardfm.app/downloads/$UPDATE_NAME" "$SIGNATURE" "${NOTES[@]}"
  (cd "$SITE" && npm run deploy > /dev/null)
  echo "▶ Update $VERSION ($BUILDNUM) is live. Commit the beardfm.app changes (downloads/ and transcriber/appcast.xml)."
fi

ls -la "$DMG"
echo "✔ Done: $DMG"
