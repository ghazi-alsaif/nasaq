# Shared by login/install-login.sh and login/install-plymouth.sh (sourced).
# Both system steps use one root-owned helper and one sudoers rule:
#   /usr/local/bin/nasaq-login-sync   follows the theme for the login and boot screens
#   /etc/sudoers.d/nasaq-login        lets the installing user run exactly that helper
HELPER=/usr/local/bin/nasaq-login-sync
SUDOERS=/etc/sudoers.d/nasaq-login
MARK="# Written by NASAQ (login/install-login.sh)"

# Install (or refresh) the helper and the rule. $R must be the repository.
install_helper_and_rule() {
  local rule user
  user=$(id -un)
  rule=$(mktemp)
  # No arguments allowed (""). Checked with visudo before it goes in.
  printf '%s\n%s ALL=(root) NOPASSWD: %s ""\n' "$MARK" "$user" "$HELPER" > "$rule"
  if ! visudo -cf "$rule" >/dev/null; then rm -f "$rule"; echo "sudoers rule failed validation; nothing installed." >&2; return 1; fi
  sudo install -d -o root -g root -m 0755 /usr/local/bin
  sudo install -o root -g root -m 0755 "$R/bin/nasaq-login-sync" "$HELPER"
  sudo install -o root -g root -m 0440 "$rule" "$SUDOERS"
  rm -f "$rule"
}

# Remove them once neither the login screen nor the boot screens are installed.
remove_helper_if_unused() {
  [[ -d /usr/share/sddm/themes/nasaq-login || -d /usr/share/plymouth/themes/nasaq ]] && return 0
  sudo rm -f "$SUDOERS" "$HELPER"
}

# Rebuild the boot image the way Omarchy does.
rebuild_boot_image() {
  if command -v limine-mkinitcpio >/dev/null; then sudo limine-mkinitcpio >/dev/null; else sudo mkinitcpio -P >/dev/null; fi
}
