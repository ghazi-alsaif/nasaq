# NASAQ (نَسَق)

An opinionated shell layer for [Omarchy](https://omarchy.org) by **GHS — Ghazi Hamad Alsaif**.
Omarchy carries DHH's taste; NASAQ carries GHS's: one coherent, macOS-flavoured desktop that respects Arabic and is configured from a single settings window.

- **No second shell.** NASAQ is a set of plugins running inside Omarchy's own Quickshell process — no duplicate notification, lock or idle daemons.
- **Omarchy stays untouched.** Nothing under `/usr/share/omarchy` is modified; a post-update check tells you when Omarchy changed something NASAQ builds on.
- **Everything from a GUI.** NASAQ Settings (SUPER + ALT + N) has real controls for every feature, and a Plugins page that turns any shell plugin on or off.
- **Arabic first.** Shortcuts that keep working under the Arabic layout, Arabic OCR, translation through Claude, prayer times and the Hijri date, and an RTL interface (test).

Install (Omarchy 4.0.4+):

```bash
git clone https://github.com/<you>/nasaq ~/.local/share/nasaq && cd ~/.local/share/nasaq && ./install.sh
```

`./update.sh` updates, `./uninstall.sh` restores your files, `./uninstall.sh --purge` also removes NASAQ's settings. See [README.md](README.md) (Arabic) for the feature list. MIT licence; see [NOTICE.md](NOTICE.md).
