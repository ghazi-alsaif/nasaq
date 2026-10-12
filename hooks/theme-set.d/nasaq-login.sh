#!/bin/bash
# NASAQ: the login screen and the boot/shutdown screens follow the new theme.
# Detached, because rebuilding the boot image can take up to a minute; the
# helper serialises runs. Skipped quietly when neither is installed (no rule).
[[ -x /usr/local/bin/nasaq-login-sync ]] || exit 0
setsid -f sudo -n /usr/local/bin/nasaq-login-sync </dev/null >/dev/null 2>&1 || true
