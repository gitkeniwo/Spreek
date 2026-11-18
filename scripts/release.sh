#!/usr/bin/env bash
# Cuts a release: bumps the version, tags it and pushes. GitHub Actions does the rest
# (.github/workflows/release.yml: tests, signed build, DMG, GitHub release, Homebrew cask).
#
#   scripts/release.sh 0.3.0              release 0.3.0
#   scripts/release.sh 0.3.0 --notes FILE use FILE (Markdown) as the release notes' "Changes"
#   scripts/release.sh 0.3.0 --dry-run    only build the DMG locally: build/release/Spreek-0.3.0.dmg
#
# A version different from MARKETING_VERSION in project.yml is written there and committed
# ("Spreek 0.3.0"). The annotated tag v0.3.0 carries the notes as its message. After you
# confirm, main and the tag are pushed; the tag starts the release workflow.
# Only allowed from main, with a clean tree and a version newer than the current one.
#
# Dry run needs: Xcode, xcodegen, rsvg-convert, uv and the signing certificate (see
# scripts/build-release.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

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
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: scripts/release.sh X.Y.Z [--notes FILE] [--dry-run]" >&2; exit 1; }
tag="v$version"

step() { printf '\n==> %s\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

if $dry_run; then
  exec scripts/build-release.sh "$version"
fi

# --- Preconditions ---------------------------------------------------------------------------
[[ -z $(git status --porcelain) ]] || die "working tree not clean"
# Releases are cut from main, never from a feature branch.
branch=$(git symbolic-ref --short -q HEAD) || die "detached HEAD; check out main first"
[[ $branch == main ]] || die "on branch $branch, not main"
[[ -z $notes_file || -f $notes_file ]] || die "no such notes file: $notes_file"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "tag $tag already exists locally"
git fetch -q origin main
[[ $(git rev-parse HEAD) == "$(git rev-parse origin/main)" ]] || die "main is not in sync with origin/main"
git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1 && die "tag $tag already exists on origin"

current=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)
[[ -n $current ]] || die "MARKETING_VERSION not found in project.yml"
# Only ever go forward: a typo such as 0.1.4 after 0.2.0 would otherwise publish an "older".
newest=$(printf '%s\n%s\n' "$current" "$version" | sort -V | tail -n 1)
[[ $version != "$current" && $newest == "$version" ]] \
  || die "$version is not newer than $current (MARKETING_VERSION in project.yml)"

# --- Confirm ---------------------------------------------------------------------------------
step "Release $current → $version"
if [[ -n $notes_file ]]; then cat "$notes_file"; else echo "(no notes)"; fi
printf '\nCommit "Spreek %s", tag %s, and push main and the tag to origin (starts the release). Continue? [y/N] ' "$version" "$tag"
read -r answer
[[ $answer == y || $answer == Y ]] || die "aborted, nothing changed"

# --- Tag and push ----------------------------------------------------------------------------
sed -i '' "s/^\( *MARKETING_VERSION: \)\".*\"$/\1\"$version\"/" project.yml
git commit -q -m "Spreek $version" project.yml
if [[ -n $notes_file ]]; then
  git tag -a "$tag" -F "$notes_file"
else
  git tag -a "$tag" -m "Spreek $version"
fi
git push origin main "$tag"

step "Pushed $tag"
echo "Watch the build: gh run watch --repo gitkeniwo/Spreek"
echo "Upgrade afterwards:  brew update && brew upgrade --cask spreek"
