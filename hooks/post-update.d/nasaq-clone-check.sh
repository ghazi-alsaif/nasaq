#!/bin/bash
# After an Omarchy update: tell the user if Omarchy changed what NASAQ's copies were made from.
"$HOME/.local/bin/nasaq-clone-check" || true
