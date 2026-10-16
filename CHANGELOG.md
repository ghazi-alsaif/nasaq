# Changelog

## Unreleased (1.4.0)
- Lock screen: the sharp desktop fades into the lock (blur, clock and password), and on unlock the lock fades back to the sharp desktop before the windows return, so both directions move (instant with Motion off or in power saver). The snapshot is now taken at full size in about 80 ms (scaling it down cost half a second) and loaded before the lock's first frame, so there is no black blink; the blur is computed once and only the fade moves, so it stays smooth on a 5K screen. The fade starts once the lock is actually on screen.
- Now playing on the lock screen: cover, title and artist with previous, play/pause and next above the power row, for whichever player is playing (or paused). Settings › System › Now playing on the lock screen.

## 1.3.0 — 2026-10-15
- Stay awake while media plays: while a video or music plays (any MPRIS player: browsers, Spotify, mpv) or a window is fullscreen, a Wayland idle inhibitor keeps the screensaver and the auto-lock away. Omarchy's own Stay awake switch is left alone, and Omarchy's screensaver window doesn't count as fullscreen. Settings › System, on by default.
- Status toasts in the island: Caps Lock on/off (read from the keyboard LED by the new `nasaq-keywatch`, which uses the same udev rule as the App Switcher), the keyboard language after a switch, and the charger plugged in or out. Small and silent, in the volume pill. Settings › Widgets › Island.
- Quiet while locked: notifications that arrive while the screen is locked go to history without a popup or chime (critical ones still sound), so the island's unseen dot is waiting after unlock. `nasaq.lock` publishes the state in `~/.local/state/nasaq/locked`. Settings › Notifications.
- Game mode: `SUPER + ALT + G`, a Quick Settings row, Settings › System, or `omarchy-shell nasaq.gamemode toggle`. Hyprland animations, blur and shadows off (kept off across config reloads), notifications quiet, hot corners off; off reloads the config (and Saver's look if it is on). The island says when it changes.
- Desktop widget column on the left, the right, or both sides (two columns; each card picks its side in Settings › Widgets, the lower half defaults to the right). The window gap follows on each side.
- The Matrix screensaver closes when the mouse moves or a button is pressed, not only on a key.
- Caps Lock is Caps Lock: NASAQ removes Omarchy's `compose:caps` and `shift:both_capslock_cancel` from whatever the keyboard options are (layout switching and the rest stay), in `nasaq-post.lua`. Settings › Shortcuts › Keyboard brings Omarchy's Compose key back (`~/.config/omarchy/nasaq/compose-caps`).
- Settings › Widgets: the island section is called "Island" (the 1.1.2 rename missed it).

## 1.2.1 — 2026-10-15
- Nothing optional any more: NASAQ is one experience, so the installer no longer asks. It installs whatever is missing (the packages `tesseract-data-ara`, `cava`, `nwg-displays`, `kitty`, `ptyxis`, `libqalculate` and `fastfetch`, the App Switcher's udev rule, the login screen, the boot and shutdown screens and the terminal greeting) and leaves alone what is already there. `--update` does the same, so an existing install gets the parts it skipped. sudo is used only when something is missing. `--yes` is still accepted and changes nothing.
- README (English and Arabic): the Motion section, fullscreen behaviour, Search keys and calculator, the switcher's frame and the Overview's order and glass.

## 1.2.0 — 2026-10-15
Motion: every part of NASAQ now moves on one rhythm, the same as the windows. Tested item by item on the MSI laptop.

- One motion rhythm for all of NASAQ (`nasaq.commons/Motion.qml` with `NAnim`, `NFade`, `NColour`): the same durations and curves as NASAQ's Hyprland window animations. Settings › Appearance › Motion: Normal, Reduced or Off; power saver turns it off.
- Island, Quick Settings and the window-look card: size and corners move on one curve, so the shape arrives as one piece; the bar pill hands over to the card without a flash or a brightness step; the card unmaps right after it closes; content fades in once the shape has opened.
- Notification centre slides and fades as one piece and unmaps when the slide ends. Search: a single highlight glides between results, the card resizes smoothly. Switcher fades in (closing stays instant). Settings pages fade and slide in; dropdowns open with a short fade. Desktop cards glide to their new place.
- Fullscreen awareness: while a film or game is fullscreen, only critical notifications show and without the chime (the rest go to history), and hot corners are off.
- One glass: search, switcher, notification centre, window look and desktop widgets get the same blur and alpha as the island.
- Overview: right-click a window for float or tile, fullscreen, move to workspace 1–5 and close; middle-click closes it. Windows appear in their on-screen order and with the desktop's glass (blurred wallpaper behind, the window opacity on top).
- Window rules removed (Settings › Workspaces & Windows, `nasaq-rules`): more to maintain than they were worth. The installer removes the old command and its generated Hyprland layer.
- Wheel over the island changes the volume; wheel over the workspace numbers changes workspace.
- Search: Ctrl+J/K (and N/P) move through results; when qalc is installed it answers sums the built-in calculator cannot (sqrt(2), 5!, today + 40 days).
- Switcher: one frame glides between the windows as TAB moves the selection.
- Dropdowns in Settings are glass like the panels, and a second click on the field closes the list (Escape too).
- Island: the unseen dot appears right after a notification silenced by fullscreen or Do Not Disturb (it used to wait until the card was opened). No doubled clock at the end of the close.
- Desktop: Tasks & notes takes the height the other cards leave, wherever it sits, so it no longer pushes cards below off the screen.
- Installer: a failed optional package install (for example with sudo closed) warns and carries on instead of stopping the whole update.
- Fixed (since 1.0.2): Settings › Widgets › Calendar showed a blank status and Refresh did nothing.

## 1.1.2 — 2026-10-14
- New tagline: one consistent line across the whole Omarchy desktop, from power-on to power-off; inspired by the best of every operating system, built for Hyprland.
- Linux names in the interface, the Plugins page, the Shortcuts list and the README: Island (was Dynamic Island), Quick Settings (was Control Center), Overview (was Mission Control), Search (was Spotlight), Preview (was Quick Look), Workspace N in the Overview (was Desktop N). The features and the IPC targets (`nasaq.island`, `nasaq.control-center`, `nasaq.overview`, `nasaq.spotlight`) are unchanged, so scripts and binds keep working. Arabic labels follow.
- Hyprland curves renamed to `nasaqEnter`, `nasaqExit` and `nasaqBounce` (same values).
- README no longer promises middle-click to close a window in the Overview; it was never implemented.
- Omarchy updates: a new `nasaq-doctor` puts NASAQ back when Omarchy moves things under it: the Hyprland lines, the bar (id, centre anchor, NASAQ widgets), its plugins and the Omarchy plugins it replaces staying off, the menu block, and the login screen selection (through the existing root helper). It runs after every `omarchy update` (replacing the separate clone-check hook, so there is one notification), and through a systemd user path unit whenever `~/.config/hypr/hyprland.lua` is rewritten, since Update › Config › Hyprland resets that folder without running the update hooks. `--restore-hypr` brings back the user's own Hyprland files from the reset's `.bak` copies. It also reports plugin copies whose Omarchy originals changed, and NASAQ plugins that logged load errors. Settings › Advanced runs it on demand.
- Clone check: the login-theme entry no longer records the active SDDM selection, so installing NASAQ's own login screen no longer looks like an Omarchy change after the next update.
- Fixed: the Clear / Undo button in the expanded island did nothing beyond its label. It sat in a delegate that could not reach the island's timer (ReferenceError: clearTimer is not defined), so a Clear never completed.

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
