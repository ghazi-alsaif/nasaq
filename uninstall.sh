#!/bin/bash
# Remove NASAQ and restore the files it changed.   ./uninstall.sh [--purge]
#   --purge also deletes your NASAQ settings (~/.config/omarchy/nasaq).
set -euo pipefail
C="${HOME:?}/.config"; B="${HOME:?}/.local/bin"; S="${HOME:?}/.local/share"

backup=$(cat "$HOME/.local/state/nasaq/last-install-backup" 2>/dev/null || true)
if [[ -n $backup && -d $backup ]]; then
  (cd "$backup" && find . -type f) | while read -r f; do cp "$backup/$f" "$C/${f#./}"; done
  echo " ✓ restored your files from ${backup/#$HOME/\~}"
else
  echo " ! no backup found: removing NASAQ's lines from your files"
fi
rm -f "$HOME/.local/state/nasaq/last-install-backup"

# Strip what NASAQ added even after a restore: an older backup (taken by a
# reinstall) may already contain it.
for f in "$C/hypr/hyprland.lua" "$C/hypr/looknfeel.lua" "$C/hypr/bindings.lua"; do
  [[ -f $f ]] && sed -i '/-- NASAQ$/d' "$f"
done
# The menu block: NASAQ's rows, the hidden stock About/System rows and their links.
menu="$C/omarchy/extensions/omarchy-menu.jsonc"
if [[ -f $menu ]] && grep -q '// NASAQ (added by' "$menu"; then
  sed -i '\#// NASAQ (added by#,\#^[[:space:]]*// /NASAQ[[:space:]]*$#d' "$menu"
  echo " ✓ NASAQ removed from the Omarchy menu"
fi

# Optional parts: the boot screens and the login screen (back to the previous ones) and the
# terminal greeting block. ~/.config/fastfetch is left alone: it may be yours.
if [[ -d /usr/share/plymouth/themes/nasaq ]]; then
  "$(dirname "$(readlink -f "$0")")/login/install-plymouth.sh" --remove || echo " ! could not remove the boot screens (needs sudo)"
fi
if [[ -f /etc/sddm.conf.d/zz-nasaq-login.conf || -d /usr/share/sddm/themes/nasaq-login ]]; then
  "$(dirname "$(readlink -f "$0")")/login/install-login.sh" --remove || echo " ! could not remove the login screen (needs sudo)"
fi
if grep -qs '# >>> NASAQ fastfetch >>>' "$HOME/.bashrc"; then
  sed -i '/^# >>> NASAQ fastfetch >>>$/,/^# <<< NASAQ fastfetch <<<$/d' "$HOME/.bashrc"
  echo " ✓ terminal greeting removed from ~/.bashrc"
fi

find "${C:?}/omarchy/plugins" -maxdepth 1 -name 'nasaq.*' -exec rm -rf {} +
find "${C:?}/hypr" -maxdepth 1 -name 'nasaq-*.lua' -delete
for s in nasaq-settings nasaq-sound nasaq-clone-check nasaq-auto-brightness nasaq-display-check nasaq-arabic-binds nasaq-keys \
         nasaq-scratch nasaq-display nasaq-translate nasaq-ask nasaq-agent-ask nasaq-calendar nasaq-rules nasaq-auto nasaq-altwatch nasaq-login-sync \
         hypr-quit-app screensaver-mode; do
  rm -f "${B:?}/${s:?}"
done
rm -f "${S:?}/omarchy-overrides/omarchy-launch-screensaver" "${S:?}/omarchy-overrides/omarchy-screensaver"
find "${C:?}/omarchy/hooks/post-update.d" "${C:?}/omarchy/hooks/theme-set.d" -maxdepth 1 -name 'nasaq-*.sh' -delete 2>/dev/null || true
systemctl --user disable --now nasaq-auto-brightness.service >/dev/null 2>&1 || true
for t in "$C"/systemd/user/nasaq-auto-*.timer; do [[ -e $t ]] && systemctl --user disable --now "$(basename "$t")" >/dev/null 2>&1; done || true

if [[ ${1:-} == --purge ]]; then
  rm -rf "${C:?}/omarchy/nasaq" "${HOME:?}/.local/state/nasaq"
  echo " ✓ NASAQ settings removed"
fi
[[ -f /etc/udev/rules.d/69-nasaq-input.rules ]] && sudo rm -f /etc/udev/rules.d/69-nasaq-input.rules 2>/dev/null && echo " ✓ udev rule removed"
omarchy-shell -q shell rescanPlugins || true
hyprctl reload >/dev/null 2>&1 || true
omarchy restart shell >/dev/null 2>&1 || true
echo " ✓ NASAQ removed. Omarchy is back to its own shell."
