"""Finder layout written directly by dmgbuild, without GUI scripting in CI."""
import os

application = os.path.abspath(defines["app"])
files = [application]
symlinks = {"Applications": "/Applications"}
format = "UDZO"
filesystem = "HFS+"
background = os.path.abspath(defines["background"])
window_rect = ((180, 160), (720, 460))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_pathbar = False
show_tab_view = False
arrange_by = None
icon_size = 144
text_size = 16
label_pos = "bottom"
icon_locations = {"Sustain.app": (180, 250), "Applications": (540, 250)}
hide_extensions = []  # Never add FinderInfo xattrs to the signed app bundle.
