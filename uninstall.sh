#!/bin/bash
# Remove NASAQ and give Omarchy its own shell back.   ./uninstall.sh [--purge] [--from-backup]
#   --purge         also delete your NASAQ settings (~/.config/omarchy/nasaq, ~/.local/state/nasaq)
#   --from-backup   instead of taking NASAQ out of shell.json and the Hyprland files
#                   surgically, put back the copies taken before NASAQ was first installed
#                   (this also undoes every change Omarchy's own migrations made since).
# What stays on purpose: ~/.config/fastfetch (it may be yours), ~/.local/share/nasaq-data
# (your tasks and notes) and the packages NASAQ installed (pacman -Rs them if unwanted).
set -uo pipefail
C="${HOME:?}/.config"; B="${HOME:?}/.local/bin"; S="${HOME:?}/.local/share"
PURGE=false FROM_BACKUP=false
for a in "$@"; do case $a in --purge) PURGE=true ;; --from-backup) FROM_BACKUP=true ;; esac; done
STOCK="${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json"

# 1. shell.json: NASAQ's plugins out, the bar back to Omarchy's own, the Omarchy
#    plugins NASAQ replaced back on. Everything else in the file (idle times,
#    your own plugins) is left as it is.
if $FROM_BACKUP; then
  backup=$(cat "$HOME/.local/state/nasaq/last-install-backup" 2>/dev/null || true)
  if [[ -n $backup && -d $backup ]]; then
    (cd "$backup" && find . -type f) | while read -r f; do cp "$backup/$f" "$C/${f#./}"; done
    echo " ✓ restored your files from ${backup/#$HOME/\~}"
  else
    echo " ! no backup found: taking NASAQ out of your files instead"; FROM_BACKUP=false
  fi
fi
if ! $FROM_BACKUP && [[ -f $C/omarchy/shell.json ]]; then
  cp "$C/omarchy/shell.json" "$C/omarchy/shell.json.before-nasaq-uninstall"
  python3 - "$C/omarchy/shell.json" "$STOCK" <<'PY'
import json, sys, os
p, stock_p = sys.argv[1], sys.argv[2]
d = json.load(open(p))
stock = json.load(open(stock_p)) if os.path.exists(stock_p) else {}
nasaq = lambda x: str(x.get("id") if isinstance(x, dict) else x).startswith("nasaq.")
d["plugins"] = [x for x in d.get("plugins", []) if not nasaq(x)]
d["disabledPlugins"] = [x for x in d.get("disabledPlugins", []) if x not in ("omarchy.lock", "omarchy.osd", "omarchy.notifications") and not str(x).startswith("nasaq.")]
if not d["disabledPlugins"]: del d["disabledPlugins"]
d.pop("cloneSourceRestores", None)
bar = d.get("bar", {})
if str(bar.get("id", "")).startswith("nasaq."):
    # NASAQ replaced the whole layout at install, so the whole layout goes back.
    keep = {k: bar[k] for k in ("position", "transparent") if k in bar}
    d["bar"] = dict(stock.get("bar", {})); d["bar"].update(keep)
else:
    lay = bar.get("layout", {})
    for sec in list(lay):
        if isinstance(lay[sec], list): lay[sec] = [w for w in lay[sec] if not nasaq(w)]
    if str(bar.get("centerAnchor", "")).startswith("nasaq."): bar.pop("centerAnchor", None)
open(p, "w").write(json.dumps(d, indent=2) + "\n")
PY
  echo " ✓ shell.json: Omarchy's bar, lock, notifications and OSD are back (copy kept as shell.json.before-nasaq-uninstall)"
fi
rm -f "$HOME/.local/state/nasaq/last-install-backup"

# 2. Hyprland: the lines that load NASAQ's layers, by content (with or without a marker).
for f in "$C/hypr/hyprland.lua" "$C/hypr/looknfeel.lua" "$C/hypr/bindings.lua"; do
  [[ -f $f ]] && sed -i -E '/nasaq-(pre|post|looknfeel|bindings)\.lua/d; /^-- .*NASAQ$/d' "$f"
done
find "${C:?}/hypr" -maxdepth 1 -name 'nasaq-*.lua' -delete
echo " ✓ Hyprland: NASAQ's lines and layers removed"

# 3. The menu block: NASAQ's rows, the hidden stock About/System rows and their links.
menu="$C/omarchy/extensions/omarchy-menu.jsonc"
if [[ -f $menu ]] && grep -q '// NASAQ (added by' "$menu"; then
  sed -i '\#// NASAQ (added by#,\#^[[:space:]]*// /NASAQ[[:space:]]*$#d' "$menu"
  echo " ✓ NASAQ removed from the Omarchy menu"
fi

# 4. System parts: boot screens, login screen, the udev rule (each needs sudo) and
#    the terminal greeting block.
here="$(dirname "$(readlink -f "$0")")"
if [[ -d /usr/share/plymouth/themes/nasaq ]]; then
  "$here/login/install-plymouth.sh" --remove || echo " ! could not remove the boot screens (needs sudo)"
fi
if [[ -f /etc/sddm.conf.d/zz-nasaq-login.conf || -d /usr/share/sddm/themes/nasaq-login ]]; then
  "$here/login/install-login.sh" --remove || echo " ! could not remove the login screen (needs sudo)"
fi
if [[ -f /etc/udev/rules.d/69-nasaq-input.rules ]]; then
  sudo rm -f /etc/udev/rules.d/69-nasaq-input.rules && sudo udevadm control --reload 2>/dev/null && echo " ✓ udev rule removed" || echo " ! could not remove /etc/udev/rules.d/69-nasaq-input.rules (needs sudo)"
fi
if grep -qs '# >>> NASAQ fastfetch >>>' "$HOME/.bashrc"; then
  sed -i '/^# >>> NASAQ fastfetch >>>$/,/^# <<< NASAQ fastfetch <<<$/d' "$HOME/.bashrc"
  echo " ✓ terminal greeting removed from ~/.bashrc"
fi

# 5. Everything install.sh copied into your home.
find "${C:?}/omarchy/plugins" -maxdepth 1 -name 'nasaq.*' -exec rm -rf {} +
for f in "$B"/nasaq-* "$B/hypr-quit-app" "$B/screensaver-mode"; do rm -f "$f"; done
rm -f "${S:?}/omarchy-overrides/omarchy-launch-screensaver" "${S:?}/omarchy-overrides/omarchy-screensaver"
rm -rf "${S:?}/screensaver-matrix" "${S:?}/sounds/nasaq" "${S:?}/nasaq-login" "${S:?}/nasaq-plymouth"
find "${C:?}/omarchy/hooks/post-update.d" "${C:?}/omarchy/hooks/theme-set.d" -maxdepth 1 \
  \( -name 'nasaq-*.sh' -o -name 'ptyxis-theme.sh' -o -name 'mlterm-theme.sh' \) -delete 2>/dev/null || true
rm -rf "${C:?}/omarchy/nasaq/help" "${C:?}/omarchy/nasaq/defaults"
# systemd: the doctor watcher, the brightness follower, the automation timers.
for u in nasaq-doctor.path nasaq-auto-brightness.service "$C"/systemd/user/nasaq-auto-*.timer; do
  u=${u##*/}; [[ $u == *\** ]] && continue
  systemctl --user disable --now "$u" >/dev/null 2>&1 || true
done
rm -f "$C"/systemd/user/nasaq-doctor.{path,service} "$C/systemd/user/nasaq-auto-brightness.service" "$C"/systemd/user/nasaq-auto-*.{timer,service}
systemctl --user daemon-reload >/dev/null 2>&1 || true
echo " ✓ NASAQ's files, hooks and services removed"

if $PURGE; then
  rm -rf "${C:?}/omarchy/nasaq" "${HOME:?}/.local/state/nasaq"
  echo " ✓ NASAQ settings removed"
else
  echo " • kept: ~/.config/omarchy/nasaq (settings) and ~/.local/state/nasaq (backups); --purge removes them"
fi
echo " • kept: ~/.local/share/nasaq-data (tasks and notes), ~/.config/fastfetch, installed packages"
hyprctl reload >/dev/null 2>&1 || true
omarchy restart shell >/dev/null 2>&1 || true
echo " ✓ NASAQ removed. Omarchy is back to its own shell."
