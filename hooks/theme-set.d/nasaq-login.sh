#!/bin/bash
# NASAQ: the login screen follows the new theme. Skipped quietly when the
# login screen (and its one sudoers rule) is not installed.
[[ -x /usr/local/bin/nasaq-login-sync ]] || exit 0
sudo -n /usr/local/bin/nasaq-login-sync >/dev/null 2>&1 || true
