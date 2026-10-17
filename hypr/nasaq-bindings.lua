-- NASAQ (نَسَق) — part of the NASAQ shell layer for Omarchy. Personal changes belong in the files that load this one.
-- ── نسخ/لصق/قص عام: SUPER + C / V / X ──────────────────────────────────────
-- قاعدة واحدة لكل النظام: الطرفيات تأخذ CTRL+SHIFT، وكل ما عداها CTRL.
-- CTRL+SHIFT+C/V مدعوم في كل الطرفيات الحديثة (Ptyxis، konsole، alacritty،
-- kitty، foot، ghostty، wezterm)، بخلاف CTRL/SHIFT+Insert الذي لا يعرفه
-- Ptyxis. ونرسل رقم المفتاح لا اسم الحرف، لأن تخطيط العربية لا يحوي رموز
-- الحروف اللاتينية فتفشل الإرسالة كلياً وقت ما تكون اللوحة على العربية.

local KEY_C = "code:54"
local KEY_V = "code:55"
local KEY_X = "code:53"

-- نرسل التركيبة بمفاتيح صريحة بدون تحديد نافذة، حتى تصل للأسطح الطافية
-- (لوحات Omarchy) أيضاً. الفصل بين down/up يتفادى بقاء المفتاح عالقاً.
-- https://github.com/hyprwm/Hyprland/discussions/14099
local function send_shortcut_once(mods, key)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))

  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

-- أي نافذة يحتمل أنها طرفية: وسم Omarchy، أو اسم صنف فيه ما يدل على طرفية.
-- الاحتياط بالصنف يغطي أي طرفية جديدة لم يسمها Omarchy بعد.
local terminal_classes = "term|ptyxis|konsole|alacritty|kitty|foot|ghostty|wezterm|tmux|tilix|blackbox"

local function active_window_is_terminal()
  local window = hl.get_active_window()
  if not window then
    return false
  end

  for _, tag in ipairs(window.tags or {}) do
    -- الوسوم الديناميكية تنتهي بـ "*"
    if tag:gsub("%*$", "") == "terminal" then
      return true
    end
  end

  local class = (window.class or ""):lower()
  for pattern in terminal_classes:gmatch("[^|]+") do
    if class:find(pattern, 1, true) then
      return true
    end
  end

  return false
end

local function clipboard_shortcut(key)
  return function()
    send_shortcut_once(active_window_is_terminal() and "CTRL SHIFT" or "CTRL", key)
  end
end

hl.unbind("SUPER + C")
hl.unbind("SUPER + V")
hl.unbind("SUPER + X")

o.bind("SUPER + code:54", "Universal copy", clipboard_shortcut(KEY_C))
o.bind("SUPER + code:55", "Universal paste", clipboard_shortcut(KEY_V))
-- القص داخل الطرفية لا وجود له، لكن CTRL+SHIFT+X غير مؤذٍ، ونبقي القاعدة واحدة.
o.bind("SUPER + code:53", "Universal cut", clipboard_shortcut(KEY_X))

-- ── Overview و Search (إضافات nasaq.overview و nasaq.spotlight) ──
-- SUPER+TAB كان "المساحة التالية"؛ التنقل بين المساحات صار من داخل Mission
-- Control بالنقر أو بالأرقام 1-9.
hl.unbind("SUPER + TAB")
o.bind("SUPER + TAB", "Overview", "omarchy-shell nasaq.overview toggle")
o.bind("ALT + SPACE", "Search", "omarchy-shell nasaq.spotlight toggle")
o.bind("SUPER + N", "Notification Center", "omarchy-shell nasaq.notifcenter toggle")

-- Mac-style quit (SUPER + Q): close every window of the focused app.
-- code:24 = Q, so it works under the Arabic layout too.
o.bind("SUPER + code:24", "Quit app", os.getenv("HOME") .. "/.local/bin/hypr-quit-app")

-- ── Control center, desktop widgets, sound fix (added with the 2026-10-06 audit) ──
-- Keycodes rather than letters, so they work under the Arabic layout too:
-- code:54 = C, code:40 = D, code:38 = A.
o.bind("SUPER + ALT + code:54", "Quick Settings", "omarchy-shell nasaq.control-center toggle")
o.bind("SUPER + ALT + code:40", "Show / hide desktop widgets", "omarchy-shell nasaq.desktop toggle")
o.bind("SUPER + ALT + code:42", "Game mode", "omarchy-shell nasaq.gamemode toggle")
-- Restarts the audio stack (a machine's own ~/.local/bin/fix-sound runs instead if present).
o.bind("SUPER + ALT + code:38", "Fix sound", (os.getenv("HOME") or "") .. "/.local/bin/nasaq-fix-sound")

-- ── NASAQ generated bindings (written by NASAQ Settings; never edit by hand) ──
for _, name in ipairs({ "nasaq-binds-arabic", "nasaq-binds", "nasaq-scratchpads" }) do
  local path = (os.getenv("HOME") or "") .. "/.config/hypr/" .. name .. ".lua"
  local f = io.open(path, "r")
  if f then
    f:close()
    local ok, err = pcall(dofile, path)
    if not ok then print("nasaq: " .. name .. ".lua failed: " .. tostring(err)) end
  end
end

-- ── NASAQ Settings window (code:57 = N, works under the Arabic layout) ──
o.bind("SUPER + ALT + code:57", "NASAQ Settings", "omarchy-shell shell toggle nasaq.settings '{}'")

-- ── NASAQ: translate the selection with the default agent (code:46 = L, for Language) ──
o.bind("SUPER + CTRL + ALT + code:46", "Translate selection (agent)", os.getenv("HOME") .. "/.local/bin/nasaq-translate")
o.bind("SUPER + CTRL + ALT + SHIFT + code:46", "Translate a screen region (agent)", os.getenv("HOME") .. "/.local/bin/nasaq-translate --region")
