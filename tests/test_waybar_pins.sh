#!/usr/bin/env sh

. "$(dirname -- "$0")/lib/common.sh"

module="$REPO_ROOT/Configs/.config/waybar/modules/pinned-apps.jsonc"
manager="$REPO_ROOT/Configs/.config/waybar/scripts/pinned-app"
waybar_helper="$REPO_ROOT/Configs/.local/lib/hyde/waybar.py"

jq empty "$module" 2>/dev/null || fail 'pinned-apps.jsonc is not valid JSON'
python -m py_compile "$manager" "$waybar_helper" 2>/dev/null ||
    fail 'the Waybar pin Python files do not parse'
[ -x "$manager" ] || fail 'the pin manager is not executable'

for slot in 1 2 3 4 5 6 7; do
    jq -e --arg module "image#pin-$slot" \
        '.["group/pinned-apps"].modules | index($module) != null' "$module" >/dev/null ||
        fail "slot $slot is missing from the pinned-app group"
    [ "$(jq -r --arg module "image#pin-$slot" '.[$module].size' "$module")" = 22 ] ||
        fail "slot $slot does not use a 22px real-image module"
done

python - "$waybar_helper" <<'PY' || fail 'layout extension did not place pins correctly'
import importlib.util
import sys
from pathlib import Path
from unittest import mock

path = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(path.parent))
spec = importlib.util.spec_from_file_location("waybar_pin_test", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

nested = {
    "include": [],
    "modules-center": ["group/center"],
    "group/center": {"modules": ["wlr/taskbar"]},
}
module.extend_layout_with_pinned_apps(nested)
module.extend_layout_with_pinned_apps(nested)
assert nested["modules-center"] == ["group/pinned-apps", "group/center"]
assert nested["include"] == ["$XDG_CONFIG_HOME/waybar/modules/pinned-apps.jsonc"]

direct = {"modules-left": ["wlr/taskbar#windows"], "include": []}
module.extend_layout_with_pinned_apps(direct)
assert direct["modules-left"] == ["group/pinned-apps", "wlr/taskbar#windows"]

fallback = {"modules-center": ["clock"], "include": []}
module.extend_layout_with_pinned_apps(fallback)
assert fallback["modules-center"] == ["clock", "group/pinned-apps"]

disabled = {
    "hyde-pinned-apps": False,
    "modules-center": ["hyprland/window"],
    "include": [],
}
module.extend_layout_with_pinned_apps(disabled)
assert disabled == {"modules-center": ["hyprland/window"], "include": []}

# A restart must stop the unit and remove any terminal-launched Waybar before
# starting one managed instance.  This guards against the double-bar failure.
with mock.patch.object(module, "HAS_SYSTEMD", True), \
     mock.patch.object(module, "kill_waybar_processes") as kill_processes, \
     mock.patch.object(module, "run_waybar") as run, \
     mock.patch.object(module.subprocess, "run") as subprocess_run:
    module.restart_waybar()
    subprocess_run.assert_called_once_with(
        ["systemctl", "--user", "stop", module.UNIT_NAME]
    )
    kill_processes.assert_called_once_with()
    run.assert_called_once_with()

modern = module.load_jsonc(path.parents[3] / ".config/waybar/layouts/modern.jsonc")
assert modern["hyde-pinned-apps"] is False
assert modern["group/modern-tools"]["drawer"]["transition-duration"] == 250
assert modern["group/modern-tools"]["modules"][0] == "custom/swaync"
assert modern["group/modern-launchers"]["drawer"]["transition-left-to-right"] is True
assert modern["group/modern-nav"]["modules"] == [
    "group/modern-launchers",
    "hyprland/workspaces",
]
PY

work_dir=$(mktemp -d) || exit 1
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/home/.local/share/applications" \
    "$work_dir/home/.local/share/icons/hicolor/scalable/apps" \
    "$work_dir/bin" "$work_dir/state"

cat > "$work_dir/home/.local/share/applications/com.brave.Browser.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Brave
Exec=brave
Icon=$work_dir/home/.local/share/icons/hicolor/scalable/apps/brave.svg
StartupWMClass=brave-browser
DESKTOP

cat > "$work_dir/home/.local/share/icons/hicolor/scalable/apps/brave.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"/>
SVG

cat > "$work_dir/bin/hyprctl" <<'STUB'
#!/usr/bin/env sh
printf '%s\n' '[{"address":"0x123","class":"brave-browser","initialClass":"brave-browser"}]'
STUB

cat > "$work_dir/bin/systemctl" <<'STUB'
#!/usr/bin/env sh
exit 0
STUB
chmod +x "$work_dir/bin/hyprctl" "$work_dir/bin/systemctl"

run_manager() {
    HOME="$work_dir/home" XDG_STATE_HOME="$work_dir/state" \
        PATH="$work_dir/bin:$PATH" "$manager" "$@"
}

status=$(run_manager status 1)
[ "$(printf '%s' "$status" | jq -r '.alt')" = 'com.brave.Browser.desktop' ] ||
    fail 'the first installed default application was not pinned'
printf '%s' "$status" | jq -e '.class | index("running") != null' >/dev/null ||
    fail 'a matching live window was not marked as running'

image=$(run_manager image 1)
[ "$(printf '%s\n' "$image" | sed -n '1p')" = \
    "$work_dir/home/.local/share/icons/hicolor/scalable/apps/brave.svg" ] ||
    fail 'the dock did not resolve the real desktop icon'
[ "$(printf '%s\n' "$image" | sed -n '2p')" = 'Brave · ouverte' ] ||
    fail 'the image module tooltip did not report the running state'

run_manager unpin 1
[ "$(run_manager status 1 | jq -r '.class[0]')" = empty ] ||
    fail 'an unpinned slot did not become empty'

printf '    dynamic pins and layout injection checked\n'
finish
