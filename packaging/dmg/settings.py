# dmgbuild settings for the Spreek installer DMG (used by scripts/release.sh).
# Defines: app (path to Spreek.app), background (PNG; a background@2x.png next to it is
# picked up for Retina), icon (volume .icns).

app = defines["app"]

format = "ULFO"  # LZFSE: smaller than zlib, opens on macOS 10.11+
filesystem = "APFS"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]
background = defines["background"]

window_rect = ((200, 140), (600, 360))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
icon_size = 112
text_size = 13
icon_locations = {
    "Spreek.app": (150, 160),
    "Applications": (450, 160),
}
