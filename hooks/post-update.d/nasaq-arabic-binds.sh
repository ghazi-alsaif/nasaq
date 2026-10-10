#!/bin/bash
# NASAQ: an Omarchy update can add letter shortcuts; re-create them on keycodes.
if [[ $(nasaq-arabic-binds status 2>/dev/null) == on ]]; then nasaq-arabic-binds on >/dev/null 2>&1 || true; fi
