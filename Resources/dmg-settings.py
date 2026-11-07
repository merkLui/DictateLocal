# dmgbuild settings for the release disk image: the app on the left, an arrow, and the
# Applications folder on the right, so installing is one drag. Used by scripts/ci/package.sh.
import os.path

app = defines.get("app", "dist/DictateLocal.app")  # noqa: F821 (provided by dmgbuild)
app_name = os.path.basename(app)

format = "ULFO"
filesystem = "APFS"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

background = "builtin-arrow"
window_rect = ((200, 200), (640, 280))
icon_size = 128
text_size = 13
icon_locations = {app_name: (140, 120), "Applications": (500, 120)}
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
