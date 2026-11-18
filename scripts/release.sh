#!/usr/bin/env bash
# Builds a Spreek release and publishes it through the Homebrew tap (gitkeniwo/homebrew-spreek):
# universal Release build, signed with a fixed self-signed certificate (not notarized), drag-to-Applications DMG, GitHub release
# on the tap repo with the DMG attached, Casks/spreek.rb bumped to the new version and sha256.
#
#   scripts/release.sh 0.2.0              release 0.2.0
#   scripts/release.sh 0.2.0 --dry-run    build the DMG only: build/release/Spreek-0.2.0.dmg
#   scripts/release.sh 0.2.0 --notes FILE use FILE (Markdown) as the release notes' "Changes"
#
# A version different from MARKETING_VERSION in project.yml is written there and committed
# ("Spreek 0.2.0"). The build number is the commit count. The source tag (v0.2.0) is created
# locally and never pushed: this repo stays private, the tap repo is public.
# Publishing is only allowed from main, with a clean tree and a version newer than the current one.
#
# Needs: Xcode, xcodegen, rsvg-convert (brew install librsvg), uv (for dmgbuild), gh logged in
# with push access to the tap. Install: brew install --cask gitkeniwo/spreek/spreek
set -euo pipefail
cd "$(dirname "$0")/.."

TAP_REPO=gitkeniwo/homebrew-spreek
# Self-signed code-signing certificate in the login keychain (back up its .p12; a new one
# means every user has to re-grant Accessibility once).
SIGN_IDENTITY="${SPREEK_SIGN_IDENTITY:-Spreek Self-Signed}"
DMGBUILD=dmgbuild==1.6.7

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

version="" dry_run=false notes_file=""
while (($#)); do
  case $1 in
    --dry-run) dry_run=true ;;
    --notes) notes_file=${2:?--notes needs a file}; shift ;;
    -h|--help) usage ;;
    -*) echo "unknown option: $1" >&2; usage 1 ;;
    *) version=$1 ;;
  esac
  shift
done
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: scripts/release.sh X.Y.Z [--dry-run] [--notes FILE]" >&2; exit 1; }
tag="v$version"

step() { printf '\n==> %s\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

# --- Preconditions ---------------------------------------------------------------------------
for tool in xcodebuild xcodegen rsvg-convert uvx gh; do
  command -v "$tool" >/dev/null || die "$tool not found"
done
if ! $dry_run; then
  [[ -z $(git status --porcelain) ]] || die "working tree not clean"
  # Releases are cut from main, never from a feature branch: the version commit and the tag
  # would otherwise land on the branch instead of main.
  branch=$(git symbolic-ref --short -q HEAD) || die "detached HEAD; check out main first"
  [[ $branch == main ]] || die "on branch $branch, not main"
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "tag $tag already exists here"
  gh repo view "$TAP_REPO" >/dev/null || die "can't reach $TAP_REPO (gh auth status?)"
  gh release view "$tag" --repo "$TAP_REPO" >/dev/null 2>&1 && die "$TAP_REPO already has release $tag"
fi
security find-identity -p codesigning | grep -q "\"$SIGN_IDENTITY\"" \
  || die "no code-signing identity \"$SIGN_IDENTITY\" in the keychain (security find-identity -p codesigning)"
[[ -z $notes_file || -f $notes_file ]] || die "no such notes file: $notes_file"

# --- Version -------------------------------------------------------------------------------
current=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)
[[ -n $current ]] || die "MARKETING_VERSION not found in project.yml"
# Only ever go forward: a typo such as 0.1.4 after 0.2.0 would otherwise publish an "older".
if ! $dry_run; then
  newest=$(printf '%s\n%s\n' "$current" "$version" | sort -V | tail -n 1)
  [[ $version != "$current" && $newest == "$version" ]] \
    || die "$version is not newer than $current (MARKETING_VERSION in project.yml)"
fi
# (A dry run leaves project.yml alone; the build gets the version on the command line.)
if [[ $current != "$version" ]] && ! $dry_run; then
  step "Version $current → $version"
  sed -i '' "s/^\( *MARKETING_VERSION: \)\".*\"$/\1\"$version\"/" project.yml
  git commit -q -m "Spreek $version" project.yml
fi
build_number=$(git rev-list --count HEAD)

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
xcodebuild -project Spreek.xcodeproj -scheme Spreek -configuration Release \
  -derivedDataPath "$dd" -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM= \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
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
sha256=$(shasum -a 256 "$dmg" | cut -d' ' -f1)
echo "$dmg"
echo "sha256 $sha256"

if $dry_run; then
  echo
  echo "Dry run: nothing published. Open the DMG with: open $dmg"
  exit 0
fi

# --- Publish -------------------------------------------------------------------------------
step "GitHub release $tag on $TAP_REPO"
notes=$out/notes.md
{
  echo "## Install"
  echo
  echo '```sh'
  echo "brew install --cask gitkeniwo/spreek/spreek"
  echo '```'
  echo
  echo "Or download **Spreek-$version.dmg** below, open it and drag Spreek into Applications."
  echo
  echo "Spreek isn't notarized: the first time you open it, macOS blocks it. Go to"
  echo "**System Settings › Privacy & Security**, find *\"Spreek\" was blocked…* and click **Open Anyway**."
  echo
  echo "Requires macOS 15 (Sequoia) or later; Apple silicon and Intel."
  if [[ -n $notes_file ]]; then
    echo
    echo "## Changes"
    echo
    cat "$notes_file"
  fi
} > "$notes"
gh release create "$tag" "$dmg" --repo "$TAP_REPO" --title "Spreek $version" --notes-file "$notes"

step "Updating Casks/spreek.rb"
tap=$(mktemp -d)
trap 'rm -rf "$tap"' EXIT
gh repo clone "$TAP_REPO" "$tap" -- --quiet --depth 1
mkdir -p "$tap/Casks"
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sha256/" -e "s|@TAP_REPO@|$TAP_REPO|g" \
  packaging/homebrew/spreek.rb.in > "$tap/Casks/spreek.rb"
git -C "$tap" add Casks/spreek.rb
git -C "$tap" commit -q -m "spreek $version"
git -C "$tap" push -q origin HEAD

git tag -a "$tag" -m "Spreek $version"

step "Released Spreek $version"
echo "https://github.com/$TAP_REPO/releases/tag/$tag"
echo "Install:  brew install --cask gitkeniwo/spreek/spreek"
echo "Upgrade:  brew update && brew upgrade --cask spreek"
echo "Local tag $tag created (not pushed)."
