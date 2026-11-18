#!/usr/bin/env bash
# Builds a release DMG: universal Release build signed with a fixed self-signed certificate
# (not notarized), bundle checks, drag-to-Applications DMG. Works the same on a Mac and on CI.
#
#   scripts/build-release.sh 0.3.0     writes build/release/Spreek-0.3.0.dmg
#
# Environment:
#   SPREEK_SIGN_IDENTITY  signing identity (default "Spreek Self-Signed")
#   SPREEK_KEYCHAIN       keychain holding it, when it is not in the default search list
#
# The build number is 1000 + the commit count. The history was restarted when the project went
# public, and 0.2.0 had already shipped with a build number around 73, so numbers must keep
# increasing from there. Needs a full checkout (fetch-depth: 0 on CI).
#
# Needs: Xcode, xcodegen, rsvg-convert (brew install librsvg), uv (for dmgbuild).
set -euo pipefail
cd "$(dirname "$0")/.."

# Self-signed code-signing certificate (back up its .p12; a new one means every user has to
# re-grant Accessibility once).
SIGN_IDENTITY="${SPREEK_SIGN_IDENTITY:-Spreek Self-Signed}"
DMGBUILD=dmgbuild==1.6.7

version=${1:-}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: scripts/build-release.sh X.Y.Z" >&2; exit 1; }

step() { printf '\n==> %s\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

for tool in xcodebuild xcodegen rsvg-convert uvx; do
  command -v "$tool" >/dev/null || die "$tool not found"
done
keychain_args=()
[[ -z ${SPREEK_KEYCHAIN:-} ]] || keychain_args=("$SPREEK_KEYCHAIN")
security find-identity -p codesigning ${keychain_args[@]+"${keychain_args[@]}"} | grep -q "\"$SIGN_IDENTITY\"" \
  || die "no code-signing identity \"$SIGN_IDENTITY\" (security find-identity -p codesigning)"

build_number=$((1000 + $(git rev-list --count HEAD)))

out=build/release
dd=$out/DerivedData
rm -rf "$out/stage" "$out/dmg" "$out/Spreek-$version.dmg"
mkdir -p "$out/stage" "$out/dmg"

# --- Build ---------------------------------------------------------------------------------
step "Building Spreek $version ($build_number), universal, signed with $SIGN_IDENTITY"
xcodegen generate --quiet
# Command-line settings win over Config/Base.xcconfig and a personal Config/Local.xcconfig:
# releases are always signed with the fixed self-signed certificate, never with a developer
# certificate and never ad-hoc. A stable certificate keeps the code requirement (and so the
# user's Accessibility grant) valid across upgrades; an ad-hoc cdhash changes every build.
extra_flags=()
[[ -z ${SPREEK_KEYCHAIN:-} ]] || extra_flags=("OTHER_CODE_SIGN_FLAGS=--keychain $SPREEK_KEYCHAIN")
xcodebuild -project Spreek.xcodeproj -scheme Spreek -configuration Release \
  -derivedDataPath "$dd" -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM= \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
  ${extra_flags[@]+"${extra_flags[@]}"} \
  -quiet build

app=$out/stage/Spreek.app
ditto "$dd/Build/Products/Release/Spreek.app" "$app"

step "Checking the bundle"
plist=$app/Contents/Info.plist
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist") == "$version" ]] || die "bundle version mismatch"
archs=$(lipo -archs "$app/Contents/MacOS/Spreek")
[[ $archs == *arm64* && $archs == *x86_64* ]] || die "not universal: $archs"
codesign --verify --deep --strict "$app" || die "code signature invalid"
# The designated requirement must name the certificate, not a cdhash, or every upgrade
# would drop the user's Accessibility grant.
requirement=$(codesign -dr - "$app" 2>&1)
[[ $requirement != *cdhash* && $requirement == *'identifier "nl.spreek.app"'* && $requirement == *certificate* ]] \
  || die "signature is not certificate-based: $requirement"
echo "version $version ($build_number), $archs, signed with $SIGN_IDENTITY"

# --- DMG -----------------------------------------------------------------------------------
step "Making the DMG"
rsvg-convert --width 600 --height 360 packaging/dmg/background.svg -o "$out/dmg/background.png"
rsvg-convert --width 1200 --height 720 packaging/dmg/background.svg -o "$out/dmg/background@2x.png"
dmg=$out/Spreek-$version.dmg
uvx --quiet --from "$DMGBUILD" dmgbuild -s packaging/dmg/settings.py \
  -D app="$app" -D background="$out/dmg/background.png" \
  -D icon="$app/Contents/Resources/AppIcon.icns" \
  "Spreek $version" "$dmg"
hdiutil verify -quiet "$dmg"
echo "$dmg"
echo "sha256 $(shasum -a 256 "$dmg" | cut -d' ' -f1)"
