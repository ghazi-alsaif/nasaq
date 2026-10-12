#!/bin/bash
# Compare this machine's installed NASAQ files with the repository checkout.
#   tools/check-install.sh            report differences (exit 1 if any)
#   tools/check-install.sh --quiet    only the summary line
# Compares what install.sh copies: plugins, scripts, Hyprland layers, hooks,
# overrides, sounds, help. Settings and user data are personal and not compared.
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
C="$HOME/.config"; B="$HOME/.local/bin"; S="$HOME/.local/share"
quiet=false; [[ ${1:-} == --quiet ]] && quiet=true
diffs=0
report() { diffs=$((diffs + 1)); $quiet || echo "  $1"; }
cmp_tree() {   # cmp_tree <repo dir> <installed dir> <label>
  local a=$1 b=$2 label=$3
  [[ -d $b ]] || { report "missing  $label (not installed)"; return; }
  while IFS= read -r -d '' f; do
    rel=${f#"$a"/}
    if [[ ! -e $b/$rel ]]; then report "missing  $label/$rel"
    elif ! cmp -s "$f" "$b/$rel"; then report "differs  $label/$rel"; fi
  done < <(find "$a" -type f -not -name '*.bak*' -print0)
  while IFS= read -r -d '' f; do
    rel=${f#"$b"/}
    [[ -e $a/$rel ]] || report "extra    $label/$rel (installed, not in repo)"
  done < <(find "$b" -type f -not -name '*.bak*' -not -path '*/.git/*' -print0)
}
for d in "$R"/plugins/nasaq.*/; do n=$(basename "$d"); cmp_tree "${d%/}" "$C/omarchy/plugins/$n" "plugins/$n"; done
for f in "$R"/bin/*; do n=$(basename "$f"); [[ -e $B/$n ]] || { report "missing  bin/$n"; continue; }; cmp -s "$f" "$B/$n" || report "differs  bin/$n"; done
for f in "$R"/hypr/*.lua; do n=$(basename "$f"); [[ -e $C/hypr/$n ]] || { report "missing  hypr/$n"; continue; }; cmp -s "$f" "$C/hypr/$n" || report "differs  hypr/$n"; done
for f in "$R"/hooks/theme-set.d/* "$R"/hooks/post-update.d/*; do rel=${f#"$R"/hooks/}; [[ -e $C/omarchy/hooks/$rel ]] || { report "missing  hooks/$rel"; continue; }; cmp -s "$f" "$C/omarchy/hooks/$rel" || report "differs  hooks/$rel"; done
cmp -s "$R/overrides/omarchy-launch-screensaver" "$S/omarchy-overrides/omarchy-launch-screensaver" || report "differs  overrides/omarchy-launch-screensaver"
cmp_tree "$R/overrides/screensaver-matrix" "$S/screensaver-matrix" "overrides/screensaver-matrix"
cmp_tree "$R/sounds" "$S/sounds/nasaq" "sounds"
cmp_tree "$R/help" "$C/omarchy/nasaq/help" "help"
for g in nasaq-pre nasaq-post nasaq-looknfeel nasaq-bindings; do grep -qs "$g.lua" "$C/hypr/hyprland.lua" "$C/hypr/looknfeel.lua" "$C/hypr/bindings.lua" || report "hook     $g.lua is not loaded from your Hyprland files"; done
grep -qs '// NASAQ (added by' "$C/omarchy/extensions/omarchy-menu.jsonc" || report "menu     NASAQ block missing from omarchy-menu.jsonc"
[[ -f /etc/udev/rules.d/69-nasaq-input.rules ]] || report "udev     69-nasaq-input.rules not installed (ALT+TAB uses the timing fallback)"
rev=$(git -C "$R" rev-parse --short HEAD 2>/dev/null || echo "?")
host=$(hostname)
if ((diffs == 0)); then echo "✓ $host matches the repository at $rev"; exit 0
else echo "✗ $host: $diffs difference(s) from the repository at $rev (run ./install.sh --update, or tools/sync-from-live.sh if this machine is the source)"; exit 1; fi
