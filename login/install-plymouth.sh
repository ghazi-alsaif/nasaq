#!/bin/bash
# NASAQ boot and shutdown screens (Plymouth theme "nasaq"), in the same look as
# the lock and login screens and following the active Omarchy theme.
#   login/install-plymouth.sh            install or refresh (asks for sudo, rebuilds the boot image)
#   login/install-plymouth.sh --remove   back to the previous Plymouth theme
# Run as the user, not root. The user copy in ~/.local/share/nasaq-plymouth is
# the source of truth (tools/sync-from-live.sh reads it).
#
# The repository holds templates only (nasaq.script.in, nasaq.plymouth.in and
# the neutral pill, bullet, progress and rain images). nasaq-login-sync renders
# the real images and files from them in the theme's colours into
# /usr/share/plymouth/themes/nasaq, on install and on every theme change, and
# rebuilds the boot image when they changed (the boot screen lives in it).
set -euo pipefail
R="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=login/lib.sh
source "$R/login/lib.sh"
SRC="$R/login/nasaq-plymouth"
USERCOPY="$HOME/.local/share/nasaq-plymouth"
DST=/usr/share/plymouth/themes/nasaq

(( EUID != 0 )) || { echo "Run as your user (it asks for sudo itself)." >&2; exit 1; }
command -v plymouth-set-default-theme >/dev/null || { echo "Plymouth is not installed." >&2; exit 1; }

if [[ ${1:-} == --remove ]]; then
  previous=$(cat "$DST/.previous-theme" 2>/dev/null || true)
  [[ $previous =~ ^[A-Za-z0-9_.-]+$ && -d /usr/share/plymouth/themes/$previous ]] || previous=omarchy
  sudo plymouth-set-default-theme "$previous"
  sudo rm -rf "${DST:?}"
  remove_helper_if_unused
  rebuild_boot_image
  echo " ✓ boot screens back to \"$previous\" (boot image rebuilt)"
  exit 0
fi

# 1. User copy of the templates.
mkdir -p "$USERCOPY"
cp "$SRC"/*.png "$SRC"/nasaq.script.in "$SRC"/nasaq.plymouth.in "$USERCOPY/"

# 2. Helper and sudoers rule (shared with the login screen), then the templates.
install_helper_and_rule
sudo install -d -o root -g root -m 0755 "$DST" "$DST/templates"
for f in "$USERCOPY"/*.png "$USERCOPY"/nasaq.script.in "$USERCOPY"/nasaq.plymouth.in; do
  sudo install -o root -g root -m 0644 "$f" "$DST/templates/${f##*/}"
done

# 3. Remember the theme being replaced (for --remove), render, select, rebuild once.
current=$(plymouth-set-default-theme 2>/dev/null || true)
if [[ -n $current && $current != nasaq ]]; then
  printf '%s\n' "$current" | sudo tee "$DST/.previous-theme" >/dev/null
fi
sudo -n "$HELPER"            # renders; no rebuild yet while another theme is active
if [[ $current != nasaq ]]; then
  sudo plymouth-set-default-theme nasaq
  rebuild_boot_image
  echo " ✓ boot screens installed and selected (boot image rebuilt)"
else
  echo " ✓ boot screens refreshed"
fi
