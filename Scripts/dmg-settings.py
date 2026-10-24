"""Finder layout written directly into the image, without Finder automation."""
from pathlib import Path

application = Path(defines["app"]).resolve()
format = "UDZO"
filesystem = "HFS+"
files = [str(application)]
symlinks = {"Applications": "/Applications"}
icon = str(application / "Contents/Resources/AppIcon.icns")
background = defines["background"]
icon_locations = {application.name: (190, 220), "Applications": (570, 220)}
window_rect = ((180, 180), (760, 440))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
arrange_by = None
grid_spacing = 80
icon_size = 128
text_size = 15
label_pos = "bottom"
scroll_position = (0, 0)
