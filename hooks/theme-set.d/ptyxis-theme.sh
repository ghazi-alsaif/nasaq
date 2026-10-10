#!/bin/bash
# Omarchy theme-set hook: mirror the active theme into Ptyxis.
#
# Omarchy generates terminal colors for alacritty, foot, kitty and ghostty from
# the theme's colors.toml, but ships no template for Ptyxis. This hook fills the
# gap: it writes a Ptyxis palette from whatever theme is now active and points
# the default profile at it, so Ptyxis tracks `omarchy theme set` like the
# terminals Omarchy themes natively.

set -euo pipefail

COLORS="$HOME/.local/state/omarchy/current/theme/colors.toml"
PALETTE_DIR="$HOME/.local/share/org.gnome.Ptyxis/palettes"
PALETTE_ID="omarchy"
PALETTE_FILE="$PALETTE_DIR/$PALETTE_ID.palette"

command -v ptyxis >/dev/null 2>&1 || exit 0
[[ -f $COLORS ]] || exit 0

# Read a key out of the flat colors.toml; second argument is the fallback.
color() {
  local value
  value=$(sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$COLORS" | head -1)
  echo "${value:-$2}"
}

mode=$(color mode dark)

bg=$(color background "#1e1e2e")
fg=$(color foreground "#cdd6f4")
black=$(color darker_background "$bg")
bright_black=$(color muted "#585b70")
white=$(color light_foreground "$fg")
bright_white=$(color bright_foreground "$fg")

red=$(color red "#f38ba8")
green=$(color green "#a6e3a1")
yellow=$(color yellow "#f9e2af")
blue=$(color blue "#89b4fa")
magenta=$(color magenta "#f5c2e7")
cyan=$(color cyan "#94e2d5")

# Bright variants are optional in a theme; fall back to the base hue.
bright_red=$(color bright_red "$red")
bright_green=$(color bright_green "$green")
bright_yellow=$(color bright_yellow "$yellow")
bright_blue=$(color bright_blue "$blue")
bright_magenta=$(color bright_magenta "$magenta")
bright_cyan=$(color bright_cyan "$cyan")

# Both sections carry the same colors. Ptyxis picks one by its interface style,
# which is set below to match the theme, so the theme reads correctly either way
# and a light/dark toggle never falls back to unrelated colors.
emit_section() {
  cat <<SECTION
[$1]
Foreground=$fg
Background=$bg
Color0=$black
Color1=$red
Color2=$green
Color3=$yellow
Color4=$blue
Color5=$magenta
Color6=$cyan
Color7=$white
Color8=$bright_black
Color9=$bright_red
Color10=$bright_green
Color11=$bright_yellow
Color12=$bright_blue
Color13=$bright_magenta
Color14=$bright_cyan
Color15=$bright_white

BellForeground=$fg
BellBackground=$bg
RemoteForeground=$fg
RemoteBackground=$bg
SuperuserForeground=$fg
SuperuserBackground=$bg

SECTION
}

mkdir -p "$PALETTE_DIR"
{
  echo "[Palette]"
  echo "Name=Omarchy"
  echo
  emit_section Light
  emit_section Dark
} >"$PALETTE_FILE"

gsettings set org.gnome.Ptyxis interface-style "$mode" 2>/dev/null || true

# Point every profile at the palette, not just the default one.
mapfile -t uuids < <(
  gsettings get org.gnome.Ptyxis profile-uuids 2>/dev/null |
    tr -d "[]' " | tr ',' '\n' | grep -v '^$'
)
for uuid in "${uuids[@]}"; do
  schema="org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$uuid/"
  # Ptyxis reloads a palette when the key changes value, so bounce it off
  # another id to pick up new colors written to the same filename.
  gsettings set "$schema" palette "gnome" 2>/dev/null || true
  gsettings set "$schema" palette "$PALETTE_ID" 2>/dev/null || true
done
