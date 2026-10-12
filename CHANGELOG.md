# Changelog

## 1.1.1 — 2026-10-12
- README screenshots retaken on a laptop at 1920x1080, with a new "Session screens" section (lock, login, boot).
- One name rule on the lock, login and boot screens: the account's full name (first GECOS field) when it is set, otherwise the user name exactly as it is. The lock screen no longer capitalises the user name, and the avatar shows the first letter of the shown name.

## 1.1.0 — 2026-10-12
The session screens follow the theme: boot, login, lock and shutdown now share one look and take their colours from the active Omarchy theme. Tested with clean installs on two machines.

- Boot screens: fonts are resolved through fontconfig, so the images render whether plain JetBrains Mono or its Nerd Font build is installed (found on the iMac, which only has the Nerd Font).
- Boot and shutdown screens (optional installer step): a Plymouth theme, `nasaq`, in the same look as the lock and login screens, with the disk-unlock pill, the Matrix rain and the greeting per mode (Hello on boot, See you soon on restart, Goodbye on shutdown). `nasaq-login-sync` renders every image in the theme's colours (words in JetBrains Mono, like the lock screen's clock; the name pill uses the account name) and fills the theme colours into the script. It rebuilds the boot image once, only when the images changed. The theme-set hook now runs the helper in the background, and runs are serialised. uninstall.sh restores the previous Plymouth theme.
- Sentence case on the session screens: "Hello", "See you soon" and "Goodbye", and on the lock screen and control center "Turn off display now", "Do not disturb", "Power mode", "Shut down", "Fix speakers", "Known networks", "Other networks", "Nearby devices", "Not connected", "Wi-Fi settings…" and "Bluetooth settings…". The user name shows exactly as the account has it (it was lowercased).
- Lock screen follows the active theme with exactly the login screen's mapping, so the two look like one: foreground for text, icons and the glass of the pills; accent for the avatar, cursor, selection and the Matrix rain; background as the base; urgent for the wrong password and the armed power button. Colours come live from Omarchy's `Color`, so a theme change repaints the lock even while it is up. The control center (on the lock screen and in the bar) uses the same mapping.
- Login screen helper (`nasaq-login-sync`) reads `colors.toml` exactly the way Omarchy's shell does (named keys, then `color0`/`color7`/`color4`; urgent from `red` or `color1`), and uses `background` as the base like the lock screen, so both screens always get the same values.
- Login screen (optional installer step): an SDDM theme in the same look as the lock screen, following the active Omarchy theme. Every colour (text, glass pills, avatar, cursor, selection, errors, Matrix rain in the theme accent) and the blurred wallpaper come from the theme, and a theme-set hook refreshes them on every theme change. A root-owned helper, `/usr/local/bin/nasaq-login-sync`, writes the colours and wallpaper; the step adds one sudoers rule that allows only that helper. It is installed in its own folder with `/etc/sddm.conf.d/zz-nasaq-login.conf`, since Omarchy has no setting for a custom login theme. uninstall.sh restores the previous login screen.
- Terminal greeting (optional installer step): fastfetch with NASAQ's compact layout when a terminal opens. The step adds a marked block to `~/.bashrc` and never overwrites an existing `~/.config/fastfetch`. uninstall.sh removes the block.
- Optional installer steps are also offered under `--update` while they are not installed.

## 1.0.5 — 2026-10-12
- Bar launchers: a new `bars.extraLaunchers` setting adds buttons after the default (or customised) launchers instead of replacing them. Settings > Bars & Panels now has editors for both lists (add, edit, remove).
- Tasks and notes moved out of the clone folder: they now live in `~/.local/share/nasaq-data/notes.json`. The desktop widget moves the old `~/.local/share/nasaq/notes.json` there once on startup, so nothing NASAQ writes at runtime ends up inside the repository any more.
- Omarchy menu: NASAQ now sits above About and System (… NASAQ, About, System). The installer replaces NASAQ's own menu block on every run, `--update` included, so existing installs get the new order too. uninstall.sh removes the whole block, including the hidden stock rows and their links.
- uninstall.sh restores the backup taken before the first install (a reinstall or `--update` no longer repoints it at an already-modified copy), and always strips NASAQ's Hyprland lines and menu block afterwards.
- Prayer "now" alert: fires up to ten minutes late again (it was one minute), so a laptop waking from sleep still announces the prayer. The 20-second prayer timer now checks the passed prayer before moving on to the next, so it isn't skipped after a wake. The "N minutes before" reminder is unchanged.
- Island Clear: closing the card no longer clears at once. The five-second Undo keeps running, so the card can be reopened to undo; the clear happens when the timer ends. A Clear All from the Notification Center during those seconds cancels the pending one, so it can't dismiss toasts that arrive afterwards.
- Comment wording left over from the rename (power, lock, windows, island, control center).
- `tools/check-install.sh` reports whether a machine's installed NASAQ files match the checkout.

## 1.0.4 — 2026-10-12
- Fixed: `nasaq-altwatch` was missing from the repository, so ALT + TAB on a fresh install could not switch on releasing Alt and the shell logged a warning every 3 s. The watcher now ships, and the switcher backs off instead of retrying every 3 s if it cannot start.
- Desktop widgets: GPU temperature on NVIDIA's proprietary driver (via nvidia-smi, never waking a suspended GPU). Found on an MSI laptop clean install.

## 1.0.3 — 2026-10-10
- Notification Center: the first open after a shell start no longer sweeps in from the left; the panel is anchored to the right edge and slides by its own width.

## 1.0.2 — 2026-10-10
- Settings > Widgets: drag the handle next to a card to change the column order. Tasks & notes stretches to the bottom only when it is last; anywhere else it keeps a fixed height.
- README: a short list on customising the widget column.

## 1.0.1 — 2026-10-10
- Settings > Widgets: a switch for every desktop card (clock, prayer times, weather, up next, system, now playing, tasks & notes) and one for the prayer countdown and prayer row in the Dynamic Island. Prayer features are opt-out for anyone who does not need them.

## 1.0.0 — 2026-10-10
First public release of NASAQ (نَسَق) for Omarchy 4.0.4.
- One settings window (SUPER + ALT + N) with 12 pages and a Plugins page that turns any shell plugin on or off.
- Dynamic Island: clock, Hijri date, prayer times, now playing, OSD, notifications, stopwatch, pomodoro.
- Spotlight: apps by frecency, open windows, files with Quick Look, calculator, currency, units, web, and “? ask the default agent” (also ؟).
- Mission Control, App Switcher (ALT + TAB with live previews), hot corners, named scratchpads, window rules.
- Desktop widget column: clock, prayer, weather, up next (iCal), system card with temperatures, now playing, notes.
- Notifications from the island with per-app rules and grouping.
- Arabic: shortcuts that work under the Arabic layout, Arabic OCR, translation via the default Omarchy agent, Arabic interface with RTL layout.
- Shortcut editor that can move or turn off any Omarchy shortcut, safely and reversibly.
- Lock screen (password + fingerprint), Low Power Mode and power profiles, screensaver modes (Matrix / image / ASCII), screen frame (off by default), universal clipboard and quit-app shortcuts.
- Display settings with automatic revert, auto brightness, devices, health checks, snapshots and restore.
