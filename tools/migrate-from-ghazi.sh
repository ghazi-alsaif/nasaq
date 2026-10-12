#!/bin/bash
# One-off migration from the old personal ghazi.* layer to NASAQ.
#
# Only for the machines that ran the ghazi.* layer before NASAQ existed: it is
# not called by install.sh. It copies the old layer's data to NASAQ's paths
# (never over data NASAQ already has), then moves what is left of the old layer
# into ~/Backups/ghazi-layer-retired-<date>/ (nothing is deleted).
#
#   tools/migrate-from-ghazi.sh            dry run: print what would happen
#   tools/migrate-from-ghazi.sh --apply    do it
#   tools/migrate-from-ghazi.sh --help     this text
#
# Data is also taken from an earlier ~/Backups/ghazi-layer-retired-*/ copy, so
# the tool still works on a machine whose layer was already moved away by hand.
set -euo pipefail

APPLY=false
case "${1:-}" in
  --apply) APPLY=true ;;
  "") ;;
  -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

DATE="$(date +%F)"
C="$HOME/.config"
OM="$C/omarchy"
ARCHIVE="$HOME/Backups/ghazi-layer-retired-$DATE"
copied=(); skipped=(); moved=(); notes=()

if $APPLY; then echo "Migrating from ghazi.* to NASAQ"; else echo "Dry run (nothing changes; add --apply to do it)"; fi
echo

say() { printf '  %s\n' "$1"; }
do_or_say() {  # description, then the command
  local what="$1"; shift
  if $APPLY; then "$@"; fi
  say "$what"
}

# Old copies to read from: the live home first, then earlier retired folders
# (newest first).
sources=("$HOME")
while IFS= read -r d; do [[ -n $d ]] && sources+=("${d%/}"); done < <(ls -1d "$HOME"/Backups/ghazi-layer-retired-*/ 2>/dev/null | sort -r)

# First existing copy of a path given relative to $HOME, or nothing.
find_src() {
  local rel="$1" s
  for s in "${sources[@]}"; do
    if [[ -e "$s/$rel" ]]; then printf '%s\n' "$s/$rel"; return 0; fi
  done
  return 0
}

short() { printf '%s' "${1/#$HOME/\~}"; }

# ── 1. Copy data to NASAQ's paths ─────────────────────────────────────────────
echo "Data:"
copy_pair() {  # old (relative to $HOME), new (absolute)
  local src dst="$2"
  src="$(find_src "$1")"
  [[ -n $src ]] || return 0
  if [[ -e "$dst" ]]; then
    skipped+=("$(short "$dst") (NASAQ already has it)")
    say "skip  $(short "$dst"): NASAQ already has it"
    return 0
  fi
  do_or_say "copy  $(short "$src") → $(short "$dst")" \
    bash -c 'mkdir -p "$(dirname "$2")" && cp -a "$1" "$2"' _ "$src" "$dst"
  copied+=("$(short "$dst")")
}

copy_pair ".config/omarchy/ghazi-windows.json" "$OM/nasaq/windows.json"
copy_pair ".config/omarchy/ghazi-windows-default.json" "$OM/nasaq/windows-default.json"
copy_pair ".config/omarchy/ghazi-island.json" "$OM/nasaq/island.json"
copy_pair ".config/omarchy/ghazi-power.json" "$OM/nasaq/power.json"
copy_pair ".config/omarchy/ghazi-overview.json" "$OM/nasaq/overview.json"
copy_pair ".local/share/ghazi-notes.json" "$HOME/.local/share/nasaq/notes.json"

# Every ghazi-* state file, whichever copy has it.
declare -A state_names=()
for s in "${sources[@]}"; do
  for f in "$s"/.local/state/ghazi-*; do
    [[ -e "$f" ]] && state_names["$(basename "$f")"]=1
  done
done
for n in "${!state_names[@]}"; do
  copy_pair ".local/state/$n" "$HOME/.local/state/nasaq/${n#ghazi-}"
done

# Save / Restore / Base history.
old_repo="$(find_src ".local/share/ghazi-settings")"
if [[ -n $old_repo ]]; then
  new_repo="$HOME/.local/share/nasaq-settings"
  if [[ ! -e "$new_repo" ]]; then
    do_or_say "copy  $(short "$old_repo") → $(short "$new_repo") (settings history)" cp -a "$old_repo" "$new_repo"
    copied+=("$(short "$new_repo")")
  else
    hist="$HOME/Backups/ghazi-settings-history-$DATE"
    if [[ -e "$hist" ]]; then
      say "skip  settings history: already kept in $(short "$hist")"
    else
      do_or_say "keep  $(short "$old_repo") → $(short "$hist") (NASAQ has its own history; not merged)" \
        bash -c 'mkdir -p "$(dirname "$2")" && cp -a "$1" "$2"' _ "$old_repo" "$hist"
      notes+=("Old settings history kept in $(short "$hist"); NASAQ's own history was left alone.")
    fi
    skipped+=("$(short "$new_repo") (NASAQ already has a history)")
  fi
fi
((${#copied[@]} + ${#skipped[@]})) || say "nothing to copy"
echo

# ── 2. Retire what is still live ──────────────────────────────────────────────
echo "Old layer:"
archive() {  # absolute path under $HOME
  local p="${1:?}" rel dst
  [[ -e "$p" || -L "$p" ]] || return 0
  rel="${p#"$HOME"/}"
  dst="${ARCHIVE:?}/$rel"
  [[ -e "$dst" || -L "$dst" ]] && dst="$dst.$(date +%s)"
  do_or_say "move  $(short "$p") → $(short "$dst")" \
    bash -c 'mkdir -p "$(dirname "$2")" && mv "${1:?}" "${2:?}"' _ "$p" "$dst"
  moved+=("$(short "$p")")
}

# Plugins: disable every ghazi.* still enabled, by folder and by shell.json.
plugin_ids=()
for d in "$OM"/plugins/ghazi.*; do [[ -d "$d" ]] && plugin_ids+=("$(basename "$d")"); done
if [[ -f "$OM/shell.json" ]]; then
  while IFS= read -r id; do [[ -n $id ]] && plugin_ids+=("$id"); done < <(python3 - "$OM/shell.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
off = set(d.get("disabledPlugins", []))
for x in d.get("plugins", []):
    i = x.get("id") if isinstance(x, dict) else x
    if isinstance(i, str) and i.startswith("ghazi.") and i not in off:
        print(i)
PY
)
fi
if ((${#plugin_ids[@]})); then
  for id in $(printf '%s\n' "${plugin_ids[@]}" | sort -u); do
    do_or_say "disable plugin $id" bash -c 'omarchy plugin disable "$1" >/dev/null 2>&1 || true' _ "$id"
  done
fi

# User services: stop and disable before moving the unit.
for u in "$C"/systemd/user/ghazi-*.service; do
  [[ -e "$u" ]] || continue
  do_or_say "disable service $(basename "$u")" \
    bash -c 'systemctl --user disable --now "$1" >/dev/null 2>&1 || true' _ "$(basename "$u")"
  archive "$u"
done

for p in "$OM"/plugins/ghazi.* "$C"/hypr/ghazi-*.lua "$HOME"/.local/bin/ghazi-* "$OM"/ghazi-* \
         "$OM"/hooks/*/ghazi-*.sh "$HOME"/.local/share/ghazi-notes.json "$HOME"/.local/share/ghazi-settings \
         "$HOME"/.local/state/ghazi-*; do
  archive "$p"
done
$APPLY && systemctl --user daemon-reload 2>/dev/null || true

# Hyprland: comment out (never delete) whatever loads ghazi-*.lua or calls
# omarchy-shell ghazi.*. A guarded `do … end` loader is commented as a whole,
# since commenting only its path line would leave a broken block.
hypr_out="$(python3 - "$APPLY" "$C"/hypr/*.lua <<'PY'
import re, sys
apply = sys.argv[1] == "true"
hit = re.compile(r'ghazi-[\w-]+\.lua|omarchy-shell\s+(-q\s+)?ghazi\.')
P = "-- [NASAQ] "
for path in sys.argv[2:]:
    if re.search(r'/ghazi-[^/]*\.lua$', path):
        continue
    lines = open(path).read().split("\n")
    marks = set()
    for i, l in enumerate(lines):
        if l.lstrip().startswith("--") or not hit.search(l):
            continue
        j = i - 1
        while j >= 0 and lines[j].strip() not in ("do",) and lines[j].startswith((" ", "\t")):
            j -= 1
        if j >= 0 and lines[j].strip() == "do" and i - j <= 3:
            k = i
            while k < len(lines) and not (lines[k].startswith("end") and lines[k].strip() == "end"):
                k += 1
            marks.update(range(j, min(k, len(lines) - 1) + 1))
        else:
            marks.add(i)
    marks = {i for i in marks if not lines[i].lstrip().startswith("--")}
    if not marks:
        continue
    print(f"comment {len(marks)} line(s) in {path}")
    if apply:
        for i in marks:
            lines[i] = P + lines[i]
        open(path, "w").write("\n".join(lines))
PY
)"
[[ -n $hypr_out ]] && while IFS= read -r l; do say "${l/$HOME/\~}"; done <<<"$hypr_out"

# Menu: drop the "Ghazi Settings" submenu. Its "ghazi-system" link stays as
# "system-link", because the stock System row is hidden in favour of it.
menu="$OM/extensions/omarchy-menu.jsonc"
if [[ -f "$menu" ]] && grep -qE '^\s*"ghazi(\.[^"]*)?"\s*:' "$menu"; then
  if $APPLY; then
    mkdir -p "$ARCHIVE/.config/omarchy/extensions"
    cp -a "$menu" "$ARCHIVE/.config/omarchy/extensions/omarchy-menu.jsonc"
    python3 - "$menu" <<'PY'
import re, sys
p = sys.argv[1]
out = []
for l in open(p).read().split("\n"):
    if re.match(r'\s*"ghazi(\.[^"]*)?"\s*:', l) or re.match(r'\s*// Ghazi: "Ghazi Settings"', l):
        continue
    out.append(l.replace('"ghazi-system":', '"system-link":', 1))
open(p, "w").write("\n".join(out))
PY
  fi
  say "remove the Ghazi Settings submenu from $(short "$menu") (backup in the archive)"
fi
((${#moved[@]})) || [[ -n $hypr_out ]] || say "nothing left to retire"
echo

# ── 3. Reload and report ──────────────────────────────────────────────────────
if $APPLY; then
  hyprctl reload >/dev/null 2>&1 || true
  errs="$(hyprctl configerrors 2>/dev/null || true)"
  if [[ -n ${errs//[[:space:]]/} ]]; then
    echo "Hyprland config errors:"; printf '%s\n' "$errs"; status=1
  else
    echo "Hyprland config: no errors"; status=0
  fi
  omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true
  echo
fi

echo "Summary:"
say "copied:  ${#copied[@]}"; for x in "${copied[@]}"; do say "  $x"; done
say "skipped: ${#skipped[@]}"; for x in "${skipped[@]}"; do say "  $x"; done
say "retired: ${#moved[@]}"
for x in "${notes[@]}"; do say "$x"; done
if $APPLY; then
  ((${#moved[@]})) && say "archive: $(short "$ARCHIVE")"
  exit "${status:-0}"
else
  echo; echo "Run again with --apply to do it."
fi
