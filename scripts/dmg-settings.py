# dmgbuild settings for Luna.dmg (used by scripts/make-dmg.sh).
#
# The window: Luna on the left, Applications on the right, on the background from
# scripts/dmg-background.swift. Icon positions are icon centres in points from the top left; keep them in
# sync with the arrow in the background.
import os.path

app = defines.get("app", "build/Luna.app")  # noqa: F821 (dmgbuild provides `defines`)
background = defines.get("background", "build/dmg/background.tiff")  # noqa: F821
volume_icon = defines.get("icon", "Resources/AppIcon.icns")  # noqa: F821

files = [app]
symlinks = {"Applications": "/Applications"}
icon = volume_icon

format = "ULFO"  # LZFSE: smaller than zlib, opens on macOS 10.11 and later
filesystem = "HFS+"

# 400 points of background plus Finder's title bar.
window_rect = ((200, 140), (660, 432))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = "auto"

icon_size = 112
text_size = 13
arrange_by = None
grid_offset = (0, 0)
label_pos = "bottom"
icon_locations = {
    os.path.basename(app): (170, 190),
    "Applications": (490, 190),
}
