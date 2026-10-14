#!/bin/bash
# NASAQ: after an Omarchy update, put back what the update moved (Hyprland lines,
# bar, menu, login screen) and say so in one notification. See bin/nasaq-doctor.
"$HOME/.local/bin/nasaq-doctor" --fix --notify >/dev/null 2>&1 || true
