#!/usr/bin/env bash
# Renders the app icons from the SVGs in art/icons
# into App/Assets.xcassets:
#   AppIcon.appiconset      the bundle icon (Snavel, the default)
#   AppIcon-<id>.imageset   each selectable icon, for the Dock at runtime and the Settings picker
#   MenuBar-<id>.imageset   its paired menu-bar template image (18 pt)
#
# The SVGs are exported from art/icons/generator.html (open it with #export appended to
# the URL to get the export JSON). Needs rsvg-convert: brew install librsvg
#
# Usage: scripts/render-icons.sh
set -euo pipefail
cd "$(dirname "$0")/.."

src=art/icons
assets=App/Assets.xcassets
ids=(snavel ara beo nachtegaal merel raaf)
default=snavel

png() { rsvg-convert --width "$2" --height "$2" --keep-aspect-ratio "$1" -o "$3"; }

# Bundle icon.
set_dir="$assets/AppIcon.appiconset"
rm -rf "$set_dir" && mkdir -p "$set_dir"
images=""
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    suffix=$([[ $scale == 2 ]] && echo "@2x" || true)
    name="icon_${size}x${size}${suffix}.png"
    png "$src/icon-$default.svg" $((size * scale)) "$set_dir/$name"
    images+="    { \"filename\" : \"$name\", \"idiom\" : \"mac\", \"scale\" : \"${scale}x\", \"size\" : \"${size}x${size}\" },"$'\n'
  done
done
printf '{\n  "images" : [\n%s  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' "${images%,$'\n'}"$'\n' > "$set_dir/Contents.json"

for id in "${ids[@]}"; do
  # Selectable icon: 512 pt, so the Dock stays sharp at its largest magnification.
  dir="$assets/AppIcon-$id.imageset"
  rm -rf "$dir" && mkdir -p "$dir"
  png "$src/icon-$id.svg" 512 "$dir/icon.png"
  png "$src/icon-$id.svg" 1024 "$dir/icon@2x.png"
  cat > "$dir/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "icon.png", "idiom" : "mac", "scale" : "1x" },
    { "filename" : "icon@2x.png", "idiom" : "mac", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

  # Paired menu-bar glyph: black on transparent, rendered as a template.
  dir="$assets/MenuBar-$id.imageset"
  rm -rf "$dir" && mkdir -p "$dir"
  png "$src/menubar-$id.svg" 18 "$dir/menubar.png"
  png "$src/menubar-$id.svg" 36 "$dir/menubar@2x.png"
  cat > "$dir/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "menubar.png", "idiom" : "mac", "scale" : "1x" },
    { "filename" : "menubar@2x.png", "idiom" : "mac", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}
JSON
done

echo "Rendered AppIcon ($default) and ${#ids[@]} icon/menu-bar pairs into $assets"
