#!/bin/bash
# Copy the NASAQ parts of this machine into the repository (never personal data).
# Run from anywhere: tools/sync-from-live.sh
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
C="$HOME/.config"; B="$HOME/.local/bin"
rm -rf "$R/plugins" "$R/hypr" "$R/bin" "$R/overrides" "$R/sounds" "$R/hooks" "$R/help"
mkdir -p "$R"/{plugins,hypr,bin,overrides,sounds,hooks/theme-set.d,hooks/post-update.d,help,defaults}
for d in "$C"/omarchy/plugins/nasaq.*/; do rsync -a --exclude .git --exclude '*.bak*' "$d" "$R/plugins/$(basename "$d")/"; done
cp "$C"/hypr/nasaq-{pre,post,looknfeel,bindings}.lua "$R/hypr/"
for s in nasaq-settings nasaq-sound nasaq-clone-check nasaq-auto-brightness nasaq-display-check nasaq-arabic-binds nasaq-keys \
         nasaq-scratch nasaq-display nasaq-translate nasaq-ask nasaq-agent-ask nasaq-calendar nasaq-rules nasaq-auto nasaq-altwatch nasaq-login-sync hypr-quit-app screensaver-mode; do
  cp -L "$B/$s" "$R/bin/$s"
done
cp -L "$HOME/.local/share/omarchy-overrides/omarchy-launch-screensaver" "$R/overrides/"
rsync -a "$HOME/.local/share/screensaver-matrix/" "$R/overrides/screensaver-matrix/"
rsync -a "$HOME/.local/share/sounds/nasaq/" "$R/sounds/"
cp "$C"/omarchy/hooks/theme-set.d/{ptyxis,mlterm}-theme.sh "$C"/omarchy/hooks/theme-set.d/nasaq-login.sh "$R/hooks/theme-set.d/"
cp "$C"/omarchy/hooks/post-update.d/nasaq-{clone-check,arabic-binds}.sh "$R/hooks/post-update.d/"
rsync -a "$C/omarchy/nasaq/help/" "$R/help/"
cp "$C/omarchy/nasaq/windows-default.json" "$R/defaults/windows.json"
cp "$C/omarchy/nasaq/windows-default.json" "$R/defaults/windows-default.json"
# Login screen: the user copy kept by login/install-login.sh. Its backdrop and
# uiScale are per machine (made from the wallpaper and the monitor scale), so they stay out.
if [[ -d $HOME/.local/share/nasaq-login ]]; then
  for f in Main.qml MatrixRain.qml metadata.desktop; do cp "$HOME/.local/share/nasaq-login/$f" "$R/login/nasaq-login/$f"; done
fi
echo "synced into $R"
# Privacy gate: nothing personal may leave this machine.
if grep -rnIiE "ghazi|hostinger|147\.93|myvps|movieboxpro|حائل|buraydah|27\.52188|al\.saif" "$R"/{plugins,hypr,bin,overrides,hooks,help,defaults,login,fastfetch} 2>/dev/null; then
  echo "PRIVACY CHECK FAILED: personal data above. Fix before committing." >&2; exit 1
fi
echo "privacy check passed"
