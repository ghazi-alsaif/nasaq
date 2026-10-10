-- NASAQ (نَسَق) — part of the NASAQ shell layer for Omarchy. Personal changes belong in the files that load this one.
-- Ptyxis هي الطرفية الافتراضية (الوحيدة التي تدعم BiDi للعربية).
-- قاعدة Omarchy في default/hypr/apps/terminals.lua لا تعرفها، فنَسِمها هنا
-- حتى تنطبق عليها قواعد الثيم والاختصارات الخاصة بالطرفيات.
o.window("org\\.gnome\\.Ptyxis", { tag = "+terminal" })

-- Omarchy's default/hypr/envs.lua puts /usr/share/omarchy/bin at the FRONT of
-- PATH, so a same-named script in ~/.local/bin can never shadow a packaged
-- omarchy command for anything Hyprland spawns (keybindings, the menu, the
-- Quickshell idle service). Prepend a dedicated overrides directory ahead of
-- it. It holds only the screensaver overrides, so nothing else is shadowed.
-- Remove this block to go back to stock behaviour.
local overrides = (os.getenv("HOME") or "") .. "/.local/share/omarchy-overrides"
local path_parts = { overrides }
for entry in (os.getenv("PATH") or "/usr/local/bin:/usr/bin"):gmatch("[^:]+") do
  if entry ~= overrides then table.insert(path_parts, entry) end
end
if not path_parts[2] or path_parts[2] ~= (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/bin" then
  table.insert(path_parts, 2, (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/bin")
end
hl.env("PATH", table.concat(path_parts, ":"))
