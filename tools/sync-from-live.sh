#!/bin/bash
# Copy the NASAQ parts of this machine into the repository (never personal data).
# Run from anywhere: tools/sync-from-live.sh
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
C="$HOME/.config"; B="$HOME/.local/bin"
# The scripts and hooks to copy are whatever the repository already ships (a
# hand-written list once dropped nasaq-altwatch); a new script is added with git add.
bins=$(ls "$R/bin"); theme_hooks=$(ls "$R/hooks/theme-set.d"); update_hooks=$(ls "$R/hooks/post-update.d")
rm -rf "$R/plugins" "$R/hypr" "$R/bin" "$R/overrides" "$R/sounds" "$R/hooks" "$R/help"
mkdir -p "$R"/{plugins,hypr,bin,overrides,sounds,hooks/theme-set.d,hooks/post-update.d,help,defaults}
for d in "$C"/omarchy/plugins/nasaq.*/; do rsync -a --exclude .git --exclude '*.bak*' "$d" "$R/plugins/$(basename "$d")/"; done
cp "$C"/hypr/nasaq-{pre,post,looknfeel,bindings}.lua "$R/hypr/"
for s in $bins; do cp -L "$B/$s" "$R/bin/$s"; done
cp -L "$HOME/.local/share/omarchy-overrides/omarchy-launch-screensaver" "$R/overrides/"
rsync -a "$HOME/.local/share/screensaver-matrix/" "$R/overrides/screensaver-matrix/"
rsync -a "$HOME/.local/share/sounds/nasaq/" "$R/sounds/"
for h in $theme_hooks; do cp "$C/omarchy/hooks/theme-set.d/$h" "$R/hooks/theme-set.d/"; done
for h in $update_hooks; do cp "$C/omarchy/hooks/post-update.d/$h" "$R/hooks/post-update.d/"; done
rsync -a "$C/omarchy/nasaq/help/" "$R/help/"
cp "$C/omarchy/nasaq/windows-default.json" "$R/defaults/windows.json"
cp "$C/omarchy/nasaq/windows-default.json" "$R/defaults/windows-default.json"
# Login screen: the user copy kept by login/install-login.sh. Its backdrop and
# uiScale are per machine (made from the wallpaper and the monitor scale), so they stay out.
if [[ -d $HOME/.local/share/nasaq-login ]]; then
  for f in Main.qml MatrixRain.qml metadata.desktop; do cp "$HOME/.local/share/nasaq-login/$f" "$R/login/nasaq-login/$f"; done
fi
# Boot screens: the user copy of the templates (the rendered images are per theme and stay out).
if [[ -d $HOME/.local/share/nasaq-plymouth ]]; then
  cp "$HOME"/.local/share/nasaq-plymouth/{nasaq.script.in,nasaq.plymouth.in} "$R/login/nasaq-plymouth/"
  for f in entry bullet progress_box progress_bar trail0 trail1 trail2 trail3 trail4 trail5 trail6 trail7; do
    cp "$HOME/.local/share/nasaq-plymouth/$f.png" "$R/login/nasaq-plymouth/"
  done
fi
echo "synced into $R"
# Privacy gate: nothing personal may leave this machine.
if grep -rnIiE "ghazi|hostinger|147\.93|myvps|movieboxpro|حائل|buraydah|27\.52188|al\.saif" "$R"/{plugins,hypr,bin,overrides,hooks,help,defaults,login,fastfetch} 2>/dev/null; then
  echo "PRIVACY CHECK FAILED: personal data above. Fix before committing." >&2; exit 1
fi
echo "privacy check passed"
