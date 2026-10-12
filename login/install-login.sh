#!/bin/bash
# NASAQ login screen (SDDM theme), in the same look as the NASAQ lock screen,
# following the active Omarchy theme.
#   login/install-login.sh            install or refresh (asks for sudo)
#   login/install-login.sh --remove   back to the previous login screen
# Run as the user, not root. The user copy in ~/.local/share/nasaq-login is the
# source of truth (tools/sync-from-live.sh reads it).
#
# What it puts on the system (all root-owned):
#   /usr/share/sddm/themes/nasaq-login/      the theme
#   /etc/sddm.conf.d/zz-nasaq-login.conf     selects it
#   /usr/local/bin/nasaq-login-sync          writes the theme's colours and wallpaper
#   /etc/sudoers.d/nasaq-login               lets this user run that one helper
#                                            without a password (the theme-set hook)
#
# Omarchy has no setting for a custom login theme: `omarchy refresh sddm` and
# Style > Unlock only rewrite its own /usr/share/sddm/themes/omarchy. So the
# theme gets its own folder, and the config is named zz-… because sddm reads
# /etc/sddm.conf.d in order and the last [Theme] wins; it has to come after
# Omarchy's 99-omarchy-login.conf (Current=omarchy) and autologin.conf.
set -euo pipefail
R="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
SRC="$R/login/nasaq-login"
USERCOPY="$HOME/.local/share/nasaq-login"
DST=/usr/share/sddm/themes/nasaq-login
CONF=/etc/sddm.conf.d/zz-nasaq-login.conf
HELPER=/usr/local/bin/nasaq-login-sync
SUDOERS=/etc/sudoers.d/nasaq-login
MARK="# Written by NASAQ (login/install-login.sh)"
BACKUP="$HOME/.local/state/nasaq/sddm-backup"

(( EUID != 0 )) || { echo "Run as your user (it asks for sudo itself)." >&2; exit 1; }
user=$(id -un)

if [[ ${1:-} == --remove ]]; then
  sudo rm -f "$CONF" "$SUDOERS" "$HELPER"
  if [[ -f $BACKUP/${CONF##*/} ]]; then sudo install -m644 "$BACKUP/${CONF##*/}" "$CONF" && rm -f "$BACKUP/${CONF##*/}"; fi
  sudo rm -rf "${DST:?}"
  echo " ✓ login screen back to the previous one"
  exit 0
fi

# 1. The user copy (theme files only; colours, wallpaper and scale are written
#    by the helper into the system copy on every theme change).
mkdir -p "$USERCOPY"
for f in Main.qml MatrixRain.qml metadata.desktop theme.conf; do cp "$SRC/$f" "$USERCOPY/$f"; done

# 2. The sudoers rule, checked before it goes in. No arguments allowed ("").
rule=$(mktemp)
trap 'rm -f "${rule:?}"' EXIT
printf '%s\n%s ALL=(root) NOPASSWD: %s ""\n' "$MARK" "$user" "$HELPER" > "$rule"
visudo -cf "$rule" >/dev/null || { echo "sudoers rule failed validation; nothing installed." >&2; exit 1; }

# 3. System files.
sudo install -d -o root -g root -m 0755 "$DST" /etc/sddm.conf.d /usr/local/bin
for f in Main.qml MatrixRain.qml metadata.desktop theme.conf; do
  sudo install -o root -g root -m 0644 "$USERCOPY/$f" "$DST/$f"
done
sudo install -o root -g root -m 0755 "$R/bin/nasaq-login-sync" "$HELPER"
sudo install -o root -g root -m 0440 "$rule" "$SUDOERS"
# Keep a config of the same name that NASAQ did not write, for --remove.
if [[ -f $CONF ]] && ! grep -qF "$MARK" "$CONF"; then
  mkdir -p "$BACKUP"; cp "$CONF" "$BACKUP/"
fi
printf '%s\n[Theme]\nCurrent=nasaq-login\n' "$MARK" | sudo tee "$CONF" >/dev/null
sudo chmod 0644 "$CONF"
# Anything sorting after it with its own [Theme] would win; say so.
for f in /etc/sddm.conf.d/*.conf; do
  [[ $f > $CONF ]] && grep -q '^\[Theme\]' "$f" && echo " ! $f comes after $CONF and also sets a theme" >&2
done

# 4. Match the current theme right away (the same call the theme-set hook makes).
sudo -n "$HELPER" || echo " ! could not run $HELPER; the login screen keeps its default colours" >&2
echo " ✓ login screen installed (shows after logging out; autologin skips it)"
