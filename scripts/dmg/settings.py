# dmgbuild settings for the WhisperFly disk image. Used by scripts/make-dmg.sh:
#
#   dmgbuild -s scripts/dmg/settings.py -D app=… -D background=… -D icon=… "WhisperFly 3.1.0" out.dmg
#
# dmgbuild writes the Finder window layout (.DS_Store) itself, so building the
# image never scripts Finder and never needs an Automation permission.
# Window size and icon positions must match render-background.swift.

import os.path

app = defines["app"]
app_name = os.path.basename(app)

# lzfse-compressed, read-only. Readable on macOS 10.11+, smaller than UDZO.
format = "ULFO"
filesystem = "APFS"

files = [app]
symlinks = {"Applications": "/Applications"}
# No `hide_extensions`: it sets Finder flags on the bundle itself, which breaks
# `codesign --verify --strict`. Finder hides ".app" on its own anyway.

icon = defines.get("icon")
background = defines["background"]

# Window content is the background's size: 660 × 420 points.
window_rect = ((200, 140), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False

arrange_by = None
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 13
icon_size = 128

# Icon centres, matching appCenter / applicationsCenter in the background.
icon_locations = {
    app_name: (180, 212),
    "Applications": (480, 212),
}
