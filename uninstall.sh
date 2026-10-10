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
  for f in "$C/hypr/hyprland.lua" "$C/hypr/looknfeel.lua" "$C/hypr/bindings.lua"; do
    [[ -f $f ]] && sed -i '/-- NASAQ$/d' "$f"
  done
  echo " ! no backup found: removed the NASAQ lines from your Hyprland files"
fi

find "${C:?}/omarchy/plugins" -maxdepth 1 -name 'nasaq.*' -exec rm -rf {} +
find "${C:?}/hypr" -maxdepth 1 -name 'nasaq-*.lua' -delete
for s in nasaq-settings nasaq-sound nasaq-clone-check nasaq-auto-brightness nasaq-display-check nasaq-arabic-binds nasaq-keys \
         nasaq-scratch nasaq-display nasaq-translate nasaq-ask nasaq-calendar nasaq-rules nasaq-auto nasaq-dynamic-theme \
         hypr-quit-app screensaver-mode; do
  rm -f "${B:?}/${s:?}"
done
rm -f "${S:?}/omarchy-overrides/omarchy-launch-screensaver" "${S:?}/omarchy-overrides/omarchy-screensaver"
find "${C:?}/omarchy/hooks/post-update.d" -maxdepth 1 -name 'nasaq-*.sh' -delete 2>/dev/null || true
systemctl --user disable --now nasaq-auto-brightness.service >/dev/null 2>&1 || true
for t in "$C"/systemd/user/nasaq-auto-*.timer; do [[ -e $t ]] && systemctl --user disable --now "$(basename "$t")" >/dev/null 2>&1; done || true

if [[ ${1:-} == --purge ]]; then
  rm -rf "${C:?}/omarchy/nasaq" "${HOME:?}/.local/state/nasaq"
  echo " ✓ NASAQ settings removed"
fi
omarchy-shell -q shell rescanPlugins || true
hyprctl reload >/dev/null 2>&1 || true
omarchy restart shell >/dev/null 2>&1 || true
echo " ✓ NASAQ removed. Omarchy is back to its own shell."
