-- NASAQ (نَسَق) — part of the NASAQ shell layer for Omarchy. Personal changes belong in the files that load this one.
-- NASAQ look'n'feel: frosted translucent windows, soft corners,
-- animated workspace switching.
-- Loaded after Omarchy's defaults, so everything here wins.

-- NOTE: the window look (opacity, blur and its colours, dim, shadows,
-- rounding, border, gaps_in) is set from Control Center > Windows and written
-- to nasaq-windows.lua, which is loaded at the end of this file and overrides
-- the values below. The values here are only the fallback if that file is gone.
-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
hl.config({
  decoration = {
    -- Soft, squircle-ish corners. Higher rounding_power = gentler curve.
    rounding = 14,
    rounding_power = 3.0,

    -- Frosted glass behind translucent windows.
    blur = {
      enabled = true,
      size = 4,
      passes = 2,
      new_optimizations = true,
      -- Blur what is actually behind the window, not just the wallpaper.
      xray = false,
      -- Blur regardless of how transparent the window is.
      ignore_opacity = true,
      noise = 0.015,
      contrast = 1.0,
      brightness = 0.8,
      vibrancy = 0.2,
      vibrancy_darkness = 0.25,
      popups = true,
      popups_ignorealpha = 0.4,
      special = true,
    },

    -- Subtle depth so the rounded edges read against the blur.
    -- No shadows: the NASAQ look is a flat look (tried macOS-style shadows 2026-10-06, rejected).
    shadow = {
      enabled = false,
    },
  },
})

-- Window transparency: focused window stays readable, unfocused recedes.
-- Values are "<active> <inactive> <fullscreen>".
-- Re-applies Omarchy's default-opacity tag, so apps that opted out
-- (video players, Steam, QEMU, PiP, webcam overlay) stay untouched.
o.window({ tag = "default-opacity" }, { opacity = "0.65 0.40 1.0" })

-- Browsers opt out of the tag above, so give them the same treatment.
o.window({ tag = "chromium-based-browser" }, { opacity = "0.65 0.40 1.0" })
o.window({ tag = "firefox-based-browser" }, { opacity = "0.65 0.40 1.0" })

-- Shell surfaces (launcher, bar panels, notifications) are full-screen
-- transparent layers, so a blur layer_rule on them frosts the whole screen.
-- Removed on purpose (2026-09-27): no blur behind menus/panels/notifications.
-- The bar alone is frosted again (2026-10-04), with the same blur as windows;
-- its 60% tint comes from bar.background-alpha in the theme's shell.toml.
hl.layer_rule({ match = { namespace = "omarchy-bar" }, blur = true, ignore_alpha = 0.25 })

-- Omarchy menu (SUPER+SPACE): blur only behind the card. The layer is
-- full-screen: card at menu background-alpha 0.6, backdrop (scrim) at 0.5.
-- ignore_alpha 0.55 skips the backdrop, so the rest of the screen stays sharp.
-- Keep the card's alpha above 0.55 and the scrim's below it in
-- themed/shell.toml.tpl, or the whole screen frosts.
hl.layer_rule({ match = { namespace = "omarchy-menu" }, blur = true, ignore_alpha = 0.55 })

-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
-- Workspace switching: slide the outgoing workspace out while it fades.
hl.animation({ leaf = "workspaces", enabled = true, speed = 5.5, bezier = "easeOutQuint", style = "slidefade 15%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4, bezier = "easeOutQuint", style = "slidevert" })

-- A slightly longer border fade reads better with the gradient theme borders.
hl.animation({ leaf = "border", enabled = true, speed = 6, bezier = "easeOutQuint" })

-- Window opening/closing reflows: neighbours glide into their new slots and
-- overshoot slightly before settling.
hl.config({
  misc = {
    animate_manual_resizes = true,
  },
})

-- easeOutBack: overshoots past the target, then settles back.
hl.curve("overshoot", { type = "bezier", points = { { 0.34, 1.56 }, { 0.64, 1 } } })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 5.5, bezier = "overshoot" })

-- ── حركات نوافذ على طريقة أبل (نَسَق) ─────────────────
-- للتراجع عنها لاحقاً: احذف هذا الجزء كاملاً إلى نهاية الملف.
-- فتح: النافذة تكبر من 70% وتتجاوز قليلاً ثم تستقر (macOpen).
-- إغلاق: تصغر وتختفي بسرعة بلا ارتداد.
hl.curve("macOpen", { type = "bezier", points = { { 0.22, 1.28 }, { 0.36, 1 } } })
hl.curve("macClose", { type = "bezier", points = { { 0.55, 0 }, { 0.75, 0.6 } } })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.6, bezier = "macOpen", style = "popin 70%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.4, bezier = "macClose", style = "popin 80%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 2.2, bezier = "easeOutQuint" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 2.0, bezier = "macClose" })

-- iMac (2026-10-06): no black dimming on inactive windows. Opacity stays as on the laptop.
hl.config({
  decoration = {
    dim_inactive = false,
    dim_strength = 0.06,
  },
})

-- ── مؤشر الماك (apple_cursor في ~/.local/share/icons/macOS) ──
do
  local icons = (os.getenv("HOME") or "") .. "/.local/share/icons/macOS"
  local f = io.open(icons .. "/index.theme", "r")
  if f then
    f:close()
    hl.env("XCURSOR_THEME", "macOS")
    hl.env("HYPRCURSOR_THEME", "macOS")
  end
end

-- ── مساحة ودجتات سطح المكتب (nasaq.desktop) ──
-- النوافذ المرصوفة تبدأ بعد عمود الودجتات (360 + 10). هامش خاص بالنوافذ فقط،
-- فالشريط العائم والودجتات لا يتأثرون (حجز المساحة على مستوى الشاشة أو
-- exclusive zone للودجتات كان يضغط الشريط). ملء الشاشة يغطي كل شي.
hl.config({
  general = {
    gaps_out = { top = 10, right = 10, bottom = 10, left = 370 },
  },
})

-- The real left gap for this screen, written by nasaq.desktop (the 370 above
-- is the 1080p fallback). Loaded here so a reload never moves the windows.
do
  local desktop = (os.getenv("HOME") or "") .. "/.config/hypr/nasaq-desktop.lua"
  local f = io.open(desktop, "r")
  if f then
    f:close()
    pcall(dofile, desktop)
  end
end

-- Isolated theme-specific motion and atmosphere (loaded dynamically if theme provides atmosphere.lua).
do
  local atmosphere = (os.getenv("HOME") or "") .. "/.local/state/omarchy/current/theme/atmosphere.lua"
  local f = io.open(atmosphere, "r")
  if f then
    f:close()
    dofile(atmosphere)
  end
end

-- Window look chosen in Control Center > Windows (transparency, blur, dim,
-- shadows, shape). Loaded last so it wins; delete the file to fall back to the
-- above. pcall: a broken file must not stop the rules that follow.
do
  local windows = (os.getenv("HOME") or "") .. "/.config/hypr/nasaq-windows.lua"
  local f = io.open(windows, "r")
  if f then
    f:close()
    pcall(dofile, windows)
  end
end

-- Dynamic Island and control center cards: glass. Their layers are larger
-- than the card, so ignore_alpha keeps the blur to the card itself (its alpha
-- is the active-window opacity, never below 0.2) and off the transparent rest
-- and the closed pill (alpha 0.16).
hl.layer_rule({ match = { namespace = "nasaq-island" }, blur = true, ignore_alpha = 0.19 })
hl.layer_rule({ match = { namespace = "nasaq-control-center" }, blur = true, ignore_alpha = 0.19 })

-- Mission Control (nasaq.overview): Hyprland blurs behind its full-screen
-- layer with the same blur settings as the windows; xray shows only the
-- wallpaper underneath, not the windows.
hl.layer_rule({ match = { namespace = "nasaq-overview" }, blur = true, xray = true })

-- ── NASAQ generated layers (written by NASAQ Settings; never edit by hand) ──
-- Each file is optional and loaded in a pcall, so a missing or broken file
-- never stops Hyprland from loading the rest.
for _, name in ipairs({ "nasaq-env", "nasaq-monitors", "nasaq-rules", "nasaq-corners" }) do
  local path = (os.getenv("HOME") or "") .. "/.config/hypr/" .. name .. ".lua"
  local f = io.open(path, "r")
  if f then
    f:close()
    local ok, err = pcall(dofile, path)
    if not ok then print("nasaq: " .. name .. ".lua failed: " .. tostring(err)) end
  end
end

-- NASAQ Settings window: floating, centred, its own glass (no extra window opacity).
o.window({ title = "^NASAQ Settings$" }, { float = true, center = true, size = "1100 720", tag = "-default-opacity", opacity = "1 1" })

-- App switcher card: glass like the island.
hl.layer_rule({ match = { namespace = "nasaq-switcher" }, blur = true, ignore_alpha = 0.5 })
