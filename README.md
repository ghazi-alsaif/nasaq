<h1 align="center">NASAQ</h1>

<p align="center"><strong>One consistent line across your whole <a href="https://omarchy.org">Omarchy</a> desktop, from power-on to power-off.</strong><br>
Inspired by the best of every operating system, built for Hyprland.<br>
Also available in <a href="README.ar.md">Arabic</a>.</p>

<p align="center">
<a href="https://github.com/ghazi-alsaif/nasaq/releases"><img src="https://img.shields.io/github/v/release/ghazi-alsaif/nasaq?label=release&color=2e7d4f" alt="Release"></a>
<a href="https://omarchy.org"><img src="https://img.shields.io/badge/Omarchy-4.0.4%2B-3b6d8c" alt="Omarchy"></a>
<a href="#languages"><img src="https://img.shields.io/badge/UI-English%20%7C%20Arabic-3b6d8c" alt="Languages"></a>
<a href="LICENSE"><img src="https://img.shields.io/github/license/ghazi-alsaif/nasaq?color=6b7280" alt="License"></a>
</p>

<p align="center"><img src="docs/screenshots/desktop.png" alt="NASAQ desktop" width="900"></p>

## What NASAQ is (and is not)

- **A layer, not a fork.** NASAQ is a set of plugins that run inside Omarchy's own Quickshell process. There is no second shell, no second notification daemon, no second lock screen. Omarchy keeps updating normally.
- **Nothing under `/usr/share/omarchy` is touched.** NASAQ lives in `~/.config/omarchy/plugins`, `~/.config/hypr/nasaq-*.lua`, `~/.local/bin` and `~/.config/omarchy/nasaq`. A post-update check warns you if an Omarchy update changed something NASAQ builds on.
- **Reversible.** The installer backs up every file it changes, and `uninstall.sh` takes NASAQ out of them again: Omarchy's own bar, lock, notifications and OSD come back.
- **One settings window.** `SUPER + ALT + N` opens NASAQ Settings: 12 pages with real controls for every feature, including a Plugins page that turns any shell plugin on or off, whether NASAQ's, Omarchy's or a community one.
- **One look from power-on to power-off.** Boot, login, lock and shutdown screens share the lock screen's design and take their colours and wallpaper from the active Omarchy theme. Every NASAQ surface draws from the same glass, radius, text tints, font and date line, and follows the theme whether it is dark or light.
- **Built for more than one language.** The interface ships in English, with Arabic as the first additional language, including right-to-left layout: today the Settings window is fully translated, and the other surfaces (lock, Quick Settings, notifications, Search) follow in 1.6.0. Translations are plain JSON files, so another language is one file away. Shortcuts keep working under non-Latin keyboard layouts, and OCR reads whichever languages you install.

## The name

NASAQ is an Arabic word for *order, harmony, a consistent pattern*: things arranged so they follow one line and fit together. Omarchy already gives you a beautiful Arch + Hyprland desktop shaped by DHH's taste. NASAQ is one person's taste layered on top of it: a desktop where every piece looks and behaves like the others, and everything is configured from one window.

## Features

### The bar

<p align="center"><img src="docs/screenshots/bar-left.png" alt="Bar, left" width="760"><br>
<img src="docs/screenshots/bar-center.png" alt="Bar, centre" width="420">&nbsp;&nbsp;<img src="docs/screenshots/bar-right.png" alt="Bar, right" width="400"></p>

Left: the Omarchy menu, pinned app launchers, and the **workspace numbers**. The active workspace is highlighted, workspaces that hold windows are shown in full, empty ones are dimmed. Centre: the island with the clock and the next prayer countdown. Right: tray, keyboard layout, Wi-Fi and power state. Scroll over the workspace numbers to change workspace, or over the island to change the volume. The bar is Omarchy's bar. NASAQ adds its widgets to it through `shell.json`, so `omarchy bar` commands still work.

### The island

<p align="center"><img src="docs/screenshots/island.png" alt="The island" width="420"></p>

The island in the top centre is a living element: one pill that changes shape for whatever needs your attention. Collapsed, it shows the time, and optionally a countdown to the next prayer. Click it and it expands into a card with the date (Gregorian, and Hijri if you want it), the weather, what is playing, and a stopwatch and Pomodoro timer. Volume and brightness OSDs, and notifications, appear by morphing the island itself rather than as separate pop-ups. So do short status notes: Caps Lock on or off, the keyboard language you switched to, and the charger plugged in or out.

### Notifications and Notification Center

<p align="center"><img src="docs/screenshots/notification.png" alt="Notification" width="640"></p>

A notification grows out of the island, with the app icon, title and body, then shrinks back. Per-app rules let you mute, group, or keep an app's notifications quiet while Do Not Disturb is on.

<p align="center"><img src="docs/screenshots/notification-center.png" alt="Notification Center" width="360"></p>

`SUPER + N` slides the Notification Center in from the right: history grouped by app, clear-all (the groups leave one after another), and a Do Not Disturb switch. Swipe a group sideways to clear it.

### Quick Settings

<p align="center"><img src="docs/screenshots/control-center.png" alt="Quick Settings" width="420"></p>

`SUPER + ALT + C`, or a hot corner, opens Quick Settings: Wi-Fi, Bluetooth, keyboard layout, Do Not Disturb, Game mode, screen recording (pick an area, a live timer while it records, one click to stop), a VPN switch when NetworkManager has one, display brightness (laptop panel, Apple display or an external monitor over DDC/CI) with auto-brightness, sound with an output picker, a Windows page (transparency, blur, shadows, shape), power profile, and lock / sleep / restart / shut down.

### Desktop widgets

A column of glass widgets sits on the desktop behind your windows (see the screenshot at the top): a large clock with the date, weather for your city, an optional prayer-times card, an Up Next card fed by iCal calendar links, a system card with CPU, memory and temperatures, Now Playing with media controls, and a Tasks / Notes card. `SUPER + ALT + D` hides and shows the column.

Make the column yours, in Settings > Widgets:

- Put the column on the left, on the right, or on both sides (two columns, with each card on the side you pick). Windows tile around it.
- Every card has an on/off switch. The column closes the gap where a card is off.
- Drag the handle next to a card to put the cards in any order.
- The Tasks / Notes card takes the height the other cards leave, wherever it sits.
- Prayer times, in the column and in the island, are off with one switch if you do not need them.

### Search

![Search](docs/screenshots/spotlight.png)

`ALT + SPACE` opens Search. Type to find apps (ranked by how often and how recently you open them), open windows, and files, with a preview pane on the right that previews images, text and documents and shows size and date. Search also does arithmetic, currency and unit conversion, and web search. Start a line with `?` and the rest is a question for your default Omarchy agent (Claude, Codex, OpenCode, Copilot or Gemini, whichever `omarchy default agent` points at). The answer appears inline. `CTRL + J / K` (or `N / P`) move through the results. With `libqalculate` installed, Search also answers what its own calculator can't, such as square roots, factorials and dates (`today + 40 days`).

### Overview

![Overview](docs/screenshots/mission-control.png)

`SUPER + TAB`, a three-finger swipe up, or the top-left hot corner opens the Overview: live previews of every window on the current workspace, with the workspace strip at the top. Click a window to focus it, or drag it to another workspace. Middle-click closes a window; right-click shows its actions (float or tile, fullscreen, move to a workspace, close). Windows sit in the same order as on screen, with the same glass as on the desktop.

### App Switcher

<p align="center"><img src="docs/screenshots/app-switcher.png" alt="App Switcher" width="720"></p>

`ALT + TAB` cycles windows in most-recently-used order with live previews: hold ALT, press TAB to move, release ALT to switch instantly. This needs one udev rule, which the installer puts in `/etc/udev/rules.d/69-nasaq-input.rules`: it gives your user read access to the keyboard input devices (keyboards only, not mice or touchpads), so the switcher and the Caps Lock watcher can see key state; without it the switcher falls back to a short timer. A single frame glides from window to window as you press TAB.

### Motion

Everything in NASAQ moves to one rhythm, on the same curves Hyprland uses for your windows. The island grows into its card and shrinks back into the bar in one piece. Panels slide in solid, Search's highlight glides between results, and settings pages fade in. Choose Normal, Reduced or Off in Settings > Appearance > Motion. Power-saving mode turns motion off by itself.

### Hot corners

Push the pointer into a corner to trigger an action. Defaults: top-left Overview, top-right Notification Center, bottom-left show desktop, bottom-right lock. Each corner is set from Settings > Workspaces & Windows.

### Scratchpads

![Scratchpad](docs/screenshots/scratchpad.png)

`` SUPER + ` `` drops a terminal over whatever you are doing and hides it again with the same key. Any app can be a scratchpad: add one in Settings > Workspaces & Windows with a command, a key and a size.

### NASAQ Settings

![Settings](docs/screenshots/settings.png)

`SUPER + ALT + N`. Pages: General (interface language and direction, font, screenshots, OCR languages), Appearance, Bars & Panels (including the bar's app launchers, plus extra ones added after the defaults), Widgets, Launcher, Notifications, Workspaces & Windows, System (displays with automatic revert, auto-brightness, devices, health checks), Shortcuts, AI & Automation, Plugins, Advanced. Every setting takes effect immediately. **Save snapshot** records all of NASAQ's files in a local git repository; **Restore** goes back to any snapshot, and a restore can itself be undone.

![Plugins page](docs/screenshots/settings-plugins.png)

The Plugins page lists every plugin the shell knows about, grouped as NASAQ, Omarchy and community, with a switch for each, a rescan button, and "Add a plugin from git". Plugins the rest of NASAQ depends on are marked Required.

![Shortcuts page](docs/screenshots/settings-shortcuts.png)

The Shortcuts page lists all shortcuts, Omarchy's and NASAQ's. Each can be changed to a different key or turned off, without editing Lua by hand and without losing Omarchy's updates: NASAQ writes a small remap layer that is loaded before Omarchy's defaults. The keyboard-layout switch regenerates every letter shortcut on key codes, so `SUPER + W`, `SUPER + Q` and friends keep working while a non-Latin layout (Arabic, for example) is active. NASAQ also gives Caps Lock back its usual job (Omarchy makes it a Compose key and puts Caps Lock on both Shifts); a switch on the same page restores Omarchy's way.

### Session screens

<p align="center"><img src="docs/screenshots/lock.png" alt="Lock screen" width="440">&nbsp;&nbsp;<img src="docs/screenshots/login.png" alt="Login screen" width="440"></p>
<p align="center"><img src="docs/screenshots/boot.png" alt="Boot screen" width="440"></p>

From the moment the machine starts until it shuts down, every screen has the same design: your wallpaper blurred, a large clock or greeting, the Matrix rain in the theme's accent, and glass pills for the name and password. All of them take their colours from the active Omarchy theme and change with it.

- **Lock screen** (`SUPER + CTRL + L`): part of NASAQ's shell, with separate password and fingerprint flows. It sits on your own desktop, blurred: the sharp desktop fades into the lock, and on unlock it fades back before the windows return. Whatever is playing shows above the power row with previous, play/pause and next, so music can be paused without unlocking (Settings › System). Theme changes repaint it live, even while it is up.
- **Login screen**: an SDDM theme. A small root-owned helper rewrites its colours and wallpaper on every theme change; it is one of the few things NASAQ installs outside your home directory (with the boot screens, the udev rule above and one sudoers rule that allows that helper alone; the full list is under "Where things live"). With autologin it only shows after logging out.
- **Boot and shutdown screens**: a Plymouth theme with the disk-unlock pill and a greeting per mode: Hello on boot, See you soon on restart, Goodbye on shutdown. The same helper renders the images in the theme's colours and rebuilds the boot image once, only when they changed (up to a minute, in the background).

### More

- **Terminal greeting**: system info from fastfetch each time a terminal opens.
- **Fullscreen**: while a film or game is fullscreen, notifications wait quietly in the Notification Center (critical ones still show, without the sound) and hot corners are off.
- **Stay awake while media plays**: a video, music, or anything fullscreen keeps the screensaver and auto-lock away. It doesn't touch the Stay awake switch.
- **Game mode** (`SUPER + ALT + G`, or Quick Settings): animations, blur and shadows off, notifications quiet, hot corners off. Off puts everything back.
- **Locked screen**: notifications that arrive while the screen is locked don't pop up or chime behind it. They wait in the Notification Center, with the island's dot showing after you unlock.
- **Power**: a power-saving mode and per-profile behaviour (Saver, Balanced, Performance). Before the battery dies (3 % by default), a critical alert and a 30-second countdown in the island, then hibernate; the charger cancels it.
- **Display**: resolution, scale and position with a 15-second automatic revert, and auto-brightness from the ambient sensor or the clock.
- **Translation**: `SUPER + CTRL + ALT + L` translates the selected text; add SHIFT to OCR and translate a region of the screen. Both use your default Omarchy agent.
- **Universal clipboard**: `SUPER + C / V / X` copy, paste and cut in every app, including terminals.
- **Quit app**: `SUPER + Q` closes the whole application, not just one window.
- **Fix sound**: `SUPER + ALT + A` (and a row in Quick Settings › Sound) restarts the audio stack when the speakers go silent while everything looks fine. A machine that needs more can put its own script at `~/.local/bin/fix-sound`, which then runs instead.
- **Automations** (time- or event-triggered commands), editable from Settings.
- **Screensaver modes**: Matrix, image, or Omarchy's stock ASCII.
- **Themes**: every NASAQ surface follows the active Omarchy theme and updates when you change it.
- **Screen frame** (off by default): a soft rounded frame in the theme colour drawn inside the window gaps.

## Shortcuts

| Keys | Action |
|---|---|
| `SUPER + ALT + N` | NASAQ Settings |
| `ALT + SPACE` | Search |
| `ALT + TAB` | App Switcher |
| `SUPER + TAB` | Overview |
| `SUPER + N` | Notification Center |
| `SUPER + ALT + C` | Quick Settings |
| `SUPER + ALT + D` | Show / hide desktop widgets |
| `SUPER + ALT + G` | Game mode |
| `` SUPER + ` `` | Terminal scratchpad |
| `SUPER + Q` | Quit app |
| `SUPER + C / V / X` | Universal copy / paste / cut |
| `SUPER + CTRL + ALT + L` | Translate selection |
| `SUPER + CTRL + ALT + SHIFT + L` | Translate a screen region (OCR) |
| `SUPER + ALT + A` | Fix sound |
| `?` in Search | Ask the default agent |

All of Omarchy's own shortcuts stay as they are, and any of them can be changed from the Shortcuts page.

## Requirements

- Omarchy 4.0.4 or newer, which brings Hyprland 0.56+ and Quickshell 0.3+. NASAQ uses Hyprland's Lua configuration and Omarchy's plugin system.
- Packages the installer adds when they are missing (ones already installed are left alone): `tesseract-data-ara` (OCR data for Arabic; add other `tesseract-data-*` packages for your languages), `cava` (audio visualiser), `nwg-displays` (graphical display layout), `kitty` and `ptyxis` (scratchpad terminals), `libqalculate` (stronger calculator in Search), `fastfetch` (terminal greeting).
- For the login and boot screens: SDDM and Plymouth (both part of Omarchy), ImageMagick and a monospace font (JetBrains Mono or its Nerd Font build, else any monospace).
- Optional: one of the Omarchy agents (`claude`, `codex`, `opencode`, `copilot`, `gemini`) for questions in Search and for translation.
- Optional prayer times come from [AlAdhan](https://aladhan.com), weather from [Open-Meteo](https://open-meteo.com), currency rates from [open.er-api.com](https://open.er-api.com). All are free and need no key.

## Install

```bash
git clone https://github.com/ghazi-alsaif/nasaq ~/.local/share/nasaq
cd ~/.local/share/nasaq
./install.sh
```

The installer:

1. checks the Omarchy version and backs up `shell.json`, your three Hyprland Lua files and the menu extension into `~/.local/state/nasaq/`;
2. copies the plugins, scripts, hooks, sounds and defaults into your home directory;
3. adds one `pcall(dofile, ...)` line to each of `hyprland.lua`, `looknfeel.lua` and `bindings.lua`, so NASAQ's layers load with yours;
4. sets up NASAQ's bar (the layout is replaced on a first install; `--update` and a re-install over a NASAQ bar keep yours) and adds NASAQ's entries to the Omarchy menu;
5. installs the missing packages and the udev rule (keyboards only) for the App Switcher and the Caps Lock watcher;
6. installs the NASAQ login screen (`sudo`; installs the theme to `/usr/share/sddm/themes/nasaq-login` and selects it in `/etc/sddm.conf.d/zz-nasaq-login.conf`; to follow theme changes it adds one sudoers rule, `/etc/sudoers.d/nasaq-login`, that lets you run a single root-owned helper, `/usr/local/bin/nasaq-login-sync`, and nothing else) and the terminal greeting (a marked block in `~/.bashrc`; an existing `~/.config/fastfetch` is never overwritten). `--update` installs them too while they are missing;
7. installs the NASAQ boot and shutdown screens (`sudo`; installs the Plymouth theme `nasaq`, selects it, remembers the previous one, and rebuilds the boot image once; it uses the same single helper and sudoers rule as the login screen);
8. restarts the shell.

Nothing is optional and nothing is asked: NASAQ is meant to be used whole. If a step fails (no password, offline), the rest still installs and running `./install.sh --update` later finishes it. Then press `SUPER + ALT + N`.

Set your city for weather (and prayer times, if you use them) in Settings > Widgets. Pick the interface language in Settings > General.

## Update

```bash
cd ~/.local/share/nasaq && ./update.sh
```

`update.sh` pulls the latest release and runs `install.sh --update`, which refreshes NASAQ's files and leaves your bar layout, menu and settings alone.

### Omarchy updates

NASAQ keeps itself in place when Omarchy changes things under it. `nasaq-doctor` runs after every `omarchy update`, and a watcher runs it whenever `shell.json` or your Hyprland files are rewritten (Omarchy's Update › Config › Hyprland and › Shell reset them without running the update hooks). It puts back what NASAQ added: its lines in your Hyprland files, its bar widgets and anchor in `shell.json`, the Omarchy plugins it replaces staying off, its menu entries and the login screen selection. It merges into your files (a copy goes to `~/.local/state/nasaq/doctor-backup/` first) and never re-enables a NASAQ plugin you turned off (the Plugins page notes your choice in NASAQ's settings, since Omarchy itself records an external plugin's "off" by dropping it from the list). You get one notification saying what it did. When Omarchy reset your whole Hyprland folder, `nasaq-doctor --restore-hypr` brings back your own lines from before the reset too. Run `nasaq-doctor` any time to check, or use Settings › Advanced.

## Uninstall

```bash
cd ~/.local/share/nasaq && ./uninstall.sh                # NASAQ out, Omarchy's shell back
cd ~/.local/share/nasaq && ./uninstall.sh --purge        # also removes NASAQ's settings
cd ~/.local/share/nasaq && ./uninstall.sh --from-backup  # put back the copies taken before the first install
```

By default the uninstaller takes NASAQ out of your files surgically: NASAQ's plugins and bar leave `shell.json` (Omarchy's own bar layout, lock, notifications and OSD come back; a copy is kept next to it), NASAQ's lines leave your Hyprland files and the menu, and everything it copied into your home goes (plugins, scripts, hooks, sounds, the screensaver, systemd units). The boot screens, the login screen and the udev rule go back to how they were (`sudo`; the boot image is rebuilt once), and the terminal greeting block comes out of `~/.bashrc`. `--from-backup` instead restores the copies taken before NASAQ was first installed, which also undoes every change Omarchy's own migrations made since. Kept on purpose: `~/.config/fastfetch` (it may be yours), `~/.local/share/nasaq-data` (your tasks and notes) and the packages that were installed.

## Where things live

| Path | What |
|---|---|
| `~/.config/omarchy/plugins/nasaq.*` | the 21 plugins |
| `~/.config/omarchy/nasaq/` | settings.json, island.json, windows.json, help |
| `~/.config/omarchy/nasaq/secrets.json` | private calendar links (never exported or snapshotted) |
| `~/.config/hypr/nasaq-*.lua` | generated Hyprland layers (binds, corners, scratchpads, layout binds, window look, desktop gap) |
| `~/.local/bin/nasaq-*` | helper scripts (settings snapshots, display, translation, scratchpads, ...) |
| `~/.local/share/nasaq-data/` | tasks and notes |
| `~/.local/share/nasaq-login/`, `~/.local/share/nasaq-plymouth/` | your copies of the login and boot themes |
| `/usr/share/sddm/themes/nasaq-login`, `/usr/share/plymouth/themes/nasaq` | the installed login and boot themes (root-owned) |
| `/usr/local/bin/nasaq-login-sync`, `/etc/sudoers.d/nasaq-login` | the helper that keeps them on the theme, and the one rule that allows it |
| `~/.local/state/nasaq/` | install backups |
| `~/.local/share/nasaq-settings/` | the snapshot repository |
| `~/.local/share/nasaq-data/` | your data: desktop tasks and notes (`notes.json`) |

## Languages

The NASAQ interface is available in **English** (default) and **Arabic**, with automatic right-to-left layout. Every string lives in `plugins/nasaq.commons/i18n/<language>.json`, so adding a language means adding one JSON file. Omarchy's own menus (such as `SUPER + SPACE`) stay in English.

## Credits and licence

NASAQ is made by **GHS (Ghazi Hamad Alsaif)** on top of [Omarchy](https://omarchy.org) by DHH and contributors, [Hyprland](https://hyprland.org) and [Quickshell](https://quickshell.org). Several plugins started as copies of Omarchy's own plugins or borrow ideas from the community plugins credited in [NOTICE.md](NOTICE.md).

MIT licence. See [LICENSE](LICENSE) and [CHANGELOG.md](CHANGELOG.md).
