-- NASAQ (نَسَق) — part of the NASAQ shell layer for Omarchy. Personal changes belong in the files that load this one.
-- NASAQ shortcut editor: bindings registered on keys listed in
-- nasaq-remap.lua are moved to their new keys (or turned off). Loaded before
-- Omarchy's defaults so it applies to every binding. Delete the file to undo.
do
  local path = (os.getenv("HOME") or "") .. "/.config/hypr/nasaq-remap.lua"
  local f = io.open(path, "r")
  if f then
    f:close()
    local ok, remap = pcall(dofile, path)
    if ok and type(remap) == "table" and next(remap) then
      local names = { [49] = "GRAVE", [20] = "MINUS", [21] = "EQUAL", [59] = "COMMA", [60] = "PERIOD", [61] = "SLASH", [65] = "SPACE",
        [36] = "RETURN", [23] = "TAB", [9] = "ESCAPE", [22] = "BACKSPACE", [110] = "HOME", [115] = "END", [119] = "DELETE", [107] = "PRINT",
        [111] = "UP", [113] = "LEFT", [114] = "RIGHT", [116] = "DOWN", [34] = "BRACKETLEFT", [35] = "BRACKETRIGHT", [47] = "SEMICOLON", [48] = "APOSTROPHE", [51] = "BACKSLASH" }
      local letters = { 38, 56, 54, 40, 26, 41, 42, 43, 31, 44, 45, 46, 58, 57, 32, 33, 24, 27, 39, 28, 30, 55, 25, 53, 29, 52 }
      for i, code in ipairs(letters) do names[code] = string.char(64 + i) end
      for i = 0, 9 do names[10 + i] = tostring((i + 1) % 10) end
      local function canon(keys)
        local parts = {}
        for p in tostring(keys):upper():gmatch("[^%s%+]+") do table.insert(parts, p) end
        if #parts == 0 then return "" end
        local key = parts[#parts]
        local code = key:match("^CODE:(%d+)$")
        if code then key = names[tonumber(code)] or key end
        local has = {}
        for i = 1, #parts - 1 do has[(parts[i] == "CONTROL") and "CTRL" or parts[i]] = true end
        local out = {}
        for _, m in ipairs({ "SUPER", "CTRL", "SHIFT", "ALT" }) do if has[m] then table.insert(out, m) end end
        table.insert(out, key)
        return table.concat(out, " + ")
      end
      local orig_bind, orig_unbind = hl.bind, hl.unbind
      hl.bind = function(keys, ...)
        local to = remap[canon(keys)]
        if to == "" then return end
        return orig_bind(to or keys, ...)
      end
      hl.unbind = function(keys, ...)
        local to = remap[canon(keys)]
        if to == "" then return end
        return orig_unbind(to or keys, ...)
      end
    end
  end
end
