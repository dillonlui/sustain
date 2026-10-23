"""Verify the shipped image's Finder metadata, not just build-time settings."""
import os
import sys
from ds_store import DSStore

root = sys.argv[1]
with DSStore.open(os.path.join(root, ".DS_Store"), "r") as store:
    icons = store["."]["icvp"]
    assert icons["iconSize"] == 144, "Installer icons must be large"
    assert icons["textSize"] == 16
    assert icons["backgroundType"] == 2, "Designed installer background is missing"
    assert store["Sustain.app"]["Iloc"] == (180, 250)
    assert store["Applications"]["Iloc"] == (540, 250)
    window = store["."]["bwsp"]
    assert not window["ShowToolbar"] and not window["ShowSidebar"]
assert os.readlink(os.path.join(root, "Applications")) == "/Applications"
assert os.path.isfile(os.path.join(root, ".background.tiff"))
print("Installer Finder layout verified")
