-- KOReader plugin: Gradient Overlay (engine-aware, cached, partial refresh, per-book profiles)
local Plugin = {
  name = "Gradient Overlay",
  description = "Local line-tracking gradient overlay with engine-aware geometry, night mode, and per-book profiles",
  version = "1.2.0",
}

local UIManager    = require("ui/uimanager")
local Event        = require("ui/event")
local Screen       = require("device").screen
local Geom         = require("ui/geometry")
local LuaSettings  = require("luasettings")
local DocSettings  = require("docsettings")
local InfoMessage  = require("ui/widget/infomessage")
local InputDialog  = require("ui/widget/inputdialog")
local Menu         = require("ui/menu")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _            = require("gettext")

-- Global settings (device-wide)
local SETTINGS_KEY = "plugins.gradient_overlay"
local defaults = {
  enabled = false,
  gradient_left = { r = 255, g = 100, b = 100 },     -- light mode
  gradient_right = { r = 100, g = 100, b = 255 },
  night_gradient_left = { r = 180, g = 60, b = 60 }, -- night mode
  night_gradient_right = { r = 60, g = 60, b = 180 },
  opacity = 40,
  night_opacity = 60,
  bar_height_pct = 75,
  vertical_offset = 2,
  segment_method = "smart", -- smart|thirds|halves|token
  auto_detect_night = true,
  use_partial_refresh = true,
}
local settings = LuaSettings:open(SETTINGS_KEY, defaults)

-- Per-book profile (overrides)
local function get_doc_settings(reader_ui)
  if not reader_ui or not reader_ui.document then return nil end
  return DocSettings:open(reader_ui.document)
end

local function read_profile(reader_ui, key, fallback)
  local ds = get_doc_settings(reader_ui)
  if not ds then return fallback end
  local v = ds:read("gradient_overlay." .. key)
  if v == nil then return fallback end
  return v
end

local function write_profile(reader_ui, key, value)
  local ds = get_doc_settings(reader_ui)
  if not ds then return end
  ds:save("gradient_overlay." .. key, value)
end

local active = settings:read("enabled")
local overlay_cache = {}
local last_night_state = nil

-- Engine/theme helpers
local function safe_require(mod)
  local ok, m = pcall(require, mod)
  if ok then return m end
  return nil
end

local function is_night_mode_active(reader_ui)
  if not reader_ui or not settings:read("auto_detect_night") then return false end
  -- Common hints across builds; tolerate absence
  if reader_ui.doc_settings and reader_ui.doc_settings.night_mode ~= nil then
    return reader_ui.doc_settings.night_mode
  end
  local AutoWarmth = safe_require("plugins/autowarmth")
  if AutoWarmth and AutoWarmth.activate_nightmode ~= nil then
    return AutoWarmth.activate_nightmode
  end
  if reader_ui.view and reader_ui.view.document and reader_ui.view.document.configurable then
    local cfg = reader_ui.view.document.configurable
    if cfg.nightmode_images == 1 then return true end
  end
  return false
end

local function lerp(a, b, t) return math.floor(a + (b - a) * t + 0.5) end
local function clamp01(t) if t < 0 then return 0 elseif t > 1 then return 1 else return t end end

local function current_palette(reader_ui)
  local night = is_night_mode_active(reader_ui)
  if last_night_state ~= nil and last_night_state ~= night then
    overlay_cache = {}
  end
  last_night_state = night
  -- Read device defaults first, then per-book override if present
  local cols = {}
  if night then
    cols.left = read_profile(reader_ui, "night_gradient_left", settings:read("night_gradient_left"))
    cols.right = read_profile(reader_ui, "night_gradient_right", settings:read("night_gradient_right"))
    cols.opacity = read_profile(reader_ui, "night_opacity", settings:read("night_opacity"))
  else
    cols.left = read_profile(reader_ui, "gradient_left", settings:read("gradient_left"))
    cols.right = read_profile(reader_ui, "gradient_right", settings:read("gradient_right"))
    cols.opacity = read_profile(reader_ui, "opacity", settings:read("opacity"))
  end
  return cols, night
end

local function color_lerp(t, left, right)
  t = clamp01(t)
  return {
    r = lerp(left.r, right.r, t),
    g = lerp(left.g, right.g, t),
    b = lerp(left.b, right.b, t),
  }
end

-- Segmentation layer (local)
local function seg_smart(text)
  local breaks = {}
  local n = #text
  if n < 20 then return breaks end
  -- punctuation
  for i = 1, n do
    local ch = text:sub(i, i)
    if ch:match("[,;:%-—]") then breaks[#breaks + 1] = i end
  end
  -- conjunctions if sparse
  if #breaks < 2 then
    local keys = { " and ", " or ", " but ", " the ", " that ", " which ", " with ", " for ", " from ", " into ", " onto ", " upon ", " over ", " under " }
    for _, w in ipairs(keys) do
      local s = 1
      while true do
        local pos = text:find(w, s, true)
        if not pos then break end
        breaks[#breaks + 1] = pos + #w - 1
        s = pos + 1
      end
    end
  end
  -- long words if still sparse
  if #breaks < 2 then
    for word in text:gmatch("%S+") do
      if #word > 8 then
        local pos = text:find(word, 1, true)
        if pos then breaks[#breaks + 1] = pos + math.floor(#word / 2) end
      end
    end
  end
  table.sort(breaks)
  if #breaks == 0 then
    breaks = { math.floor(n * 0.4), math.floor(n * 0.7) }
  elseif #breaks == 1 then
    if breaks[1] < n * 0.3 then
      breaks[#breaks + 1] = math.floor(n * 0.7)
    else
      table.insert(breaks, 1, math.floor(n * 0.3))
    end
  end
  if #breaks > 4 then
    local pruned, step = {}, #breaks / 4
    for i = 1, 4 do pruned[#pruned + 1] = breaks[math.floor(i * step)] end
    breaks = pruned
  end
  return breaks
end

local function seg_simple(text, mode)
  local n = #text
  if mode == "halves" then
    return { math.floor(n / 2) }
  elseif mode == "thirds" then
    return { math.floor(n / 3), math.floor(2 * n / 3) }
  end
  return {}
end

local function seg_token(text)
  -- Optional tokenizer path via LuaNLP if installed; silent fallback
  local LuaNLP = safe_require("LuaNLP")
  if not LuaNLP then return seg_smart(text) end
  local tokens = {}
  for t in text:gmatch("%S+") do tokens[#tokens + 1] = t end
  if #tokens < 6 then return seg_smart(text) end
  -- Prefer breaks after token quartiles
  local idxs = { math.floor(#tokens * 0.25), math.floor(#tokens * 0.5), math.floor(#tokens * 0.75) }
  local breaks = {}
  local pos, ti = 0, 0
  for token in text:gmatch("%S+%s*") do
    ti = ti + 1
    pos = pos + #token
    for _, q in ipairs(idxs) do
      if ti == q then breaks[#breaks + 1] = pos end
    end
  end
  return breaks
end

local function get_breaks(text, method)
  if method == "thirds" or method == "halves" then return seg_simple(text, method) end
  if method == "token" then return seg_token(text) end
  return seg_smart(text)
end

-- Geometry: try to get real line rects; otherwise estimate
local function get_engine_line_rects(reader_ui)
  -- Try a few introspective hints; tolerate absence
  if reader_ui and reader_ui.view and reader_ui.view.getLineRects then
    local ok, rects = pcall(function() return reader_ui.view:getLineRects() end)
    if ok and rects and #rects > 0 then return rects end
  end
  if reader_ui and reader_ui.document and reader_ui.document.getLineRects then
    local ok, rects = pcall(function() return reader_ui.document:getLineRects() end)
    if ok and rects and #rects > 0 then return rects end
  end
  return nil
end

local function get_estimated_rects(num_lines)
  local h, w = Screen:getHeight(), Screen:getWidth()
  local top, bottom, left, right = 40, 60, 30, 30
  local rh, rw = h - top - bottom, w - left - right
  local lh = math.floor(rh / math.max(1, num_lines))
  local rects = {}
  for i = 1, num_lines do
    rects[#rects + 1] = { x0 = left, y0 = top + (i - 1) * lh, x1 = left + rw, y1 = top + i * lh }
  end
  return rects
end

-- Text extraction for current page (best-effort)
local function get_page_lines(reader_ui)
  if not reader_ui or not reader_ui.document then return nil end
  local doc = reader_ui.document
  local txt = ""
  if doc.getPageText then
    txt = doc:getPageText() or ""
  elseif doc.getTextFromPositions then
    local pos0 = { x = 0, y = 0, page = reader_ui:getCurrentPage() }
    local pos1 = { x = Screen:getWidth(), y = Screen:getHeight(), page = reader_ui:getCurrentPage() }
    txt = doc:getTextFromPositions(pos0, pos1) or ""
  end
  if txt == "" then return nil end
  local lines = {}
  for line in txt:gmatch("[^\r\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if #line > 3 then
      lines[#lines + 1] = line
      if #lines >= 60 then break end
    end
  end
  return lines
end

-- Cached gradient strip generator (per width/theme)
local BB = require("ffi/blitbuffer")
local strip_cache = {} -- key: width|r,g,b...|opacity

local function strip_key(width, left, right, opacity)
  return string.format("%d|%d,%d,%d|%d,%d,%d|%d", width, left.r, left.g, left.b, right.r, right.g, right.b, opacity)
end

local function get_gradient_strip(width, height, left, right, opacity)
  if width <= 0 or height <= 0 then return nil end
  local key = strip_key(width, left, right, opacity)
  local entry = strip_cache[key]
  if entry and entry.bb and not entry.bb:isFreed() then
    return entry.bb
  end
  local bb = BB.new(width, height, BB.TYPE_B8G8R8A8) -- BGRA buffer
  -- Fill strip by columns
  for x = 0, width - 1 do
    local t = width > 1 and (x / (width - 1)) or 0
    local c = color_lerp(t, left, right)
    local col = BB.Color8.fromRGB(c.r, c.g, c.b)
    bb:fillRect(x, 0, 1, height, col, opacity)
  end
  strip_cache[key] = { bb = bb }
  return bb
end

-- Draw one line’s gradient by blitting cached strip into the target region
local function draw_line_gradient_rect(r, line_text, breaks, palette)
  local x0, y0, x1, y1 = r.x0, r.y0, r.x1, r.y1
  local width, height = x1 - x0, y1 - y0
  if width <= 0 or height <= 0 then return end

  local bar_h = math.floor(height * (settings:read("bar_height_pct") / 100))
  local by0 = y0 + settings:read("vertical_offset")
  local by1 = math.min(y1, by0 + bar_h)
  if by1 <= by0 then return end

  local strip = get_gradient_strip(width, by1 - by0, palette.left, palette.right, palette.opacity)
  if not strip then return end

  -- If breaks exist, remap into sub-blits proportionally to character lengths
  local n = #line_text
  if n > 0 and breaks and #breaks > 0 then
    local segments = {}
    local last = 1
    for _, idx in ipairs(breaks) do
      if idx > last and idx <= n then
        segments[#segments + 1] = { s = last, e = idx }
        last = idx + 1
      end
    end
    if last <= n then segments[#segments + 1] = { s = last, e = n } end
    local acc = 0
    for _, seg in ipairs(segments) do
      local chars = seg.e - seg.s + 1
      local segw = math.floor(width * (chars / n))
      if acc + segw > width then segw = width - acc end
      if segw > 0 then
        Screen:blitFrom(strip, x0 + acc, by0, acc, 0, segw, by1 - by0)
      end
      acc = acc + segw
    end
  else
    Screen:blitFrom(strip, x0, by0, 0, 0, width, by1 - by0)
  end
end

-- Main render
local function render_overlay(reader_ui, widget)
  if not active or not reader_ui then return end
  local palette = (current_palette(reader_ui))

  local page_id = tostring(reader_ui:getCurrentPage() or 0) .. "|" .. tostring(last_night_state)
  if overlay_cache[page_id] then return end

  local lines = get_page_lines(reader_ui)
  if not lines or #lines == 0 then return end

  local rects = get_engine_line_rects(reader_ui)
  if not rects or #rects == 0 then
    rects = get_estimated_rects(#lines)
  end

  local area = { x = Screen:getWidth(), y = Screen:getHeight(), x0 = Screen:getWidth(), y0 = Screen:getHeight() }
  for i, r in ipairs(rects) do
    local line_text = lines[i] or ""
    local breaks = get_breaks(line_text, read_profile(reader_ui, "segment_method", settings:read("segment_method")))
    draw_line_gradient_rect(r, line_text, breaks, palette)
    -- Track minimal bounding box for partial refresh
    area.x0 = math.min(area.x0, r.x0); area.y0 = math.min(area.y0, r.y0)
    area.x  = math.min(area.x,  r.x0); area.y  = math.min(area.y,  r.y0)
  end

  overlay_cache[page_id] = true

  -- Request a partial refresh for the reading area
  if settings:read("use_partial_refresh") and widget then
    local region = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    UIManager:setDirty(widget, "partial", region)
  end
end

local function clear_caches()
  overlay_cache = {}
  strip_cache = {}
  last_night_state = nil
end

-- Presets
local PRESETS = {
  Classic = { light = {left={r=255,g=100,b=100}, right={r=100,g=100,b=255}, opacity=40},
              night  = {left={r=180,g=60,b=60},  right={r=60,g=60,b=180},  opacity=60} },
  Calm    = { light = {left={r=120,g=180,b=255}, right={r=120,g=255,b=180}, opacity=35},
              night  = {left={r=80,g=140,b=210},  right={r=80,g=210,b=140},  opacity=55} },
  HighContrast = { light = {left={r=255,g=80,b=80}, right={r=80,g=200,b=255}, opacity=60},
                   night  = {left={r=220,g=60,b=60}, right={r=60,g=180,b=240}, opacity=80} },
}

local function apply_preset(reader_ui, name)
  local p = PRESETS[name]; if not p then return end
  settings:save("gradient_left", p.light.left)
  settings:save("gradient_right", p.light.right)
  settings:save("opacity", p.light.opacity)
  settings:save("night_gradient_left", p.night.left)
  settings:save("night_gradient_right", p.night.right)
  settings:save("night_opacity", p.night.opacity)
  write_profile(reader_ui, "gradient_left", p.light.left)
  write_profile(reader_ui, "gradient_right", p.light.right)
  write_profile(reader_ui, "opacity", p.light.opacity)
  write_profile(reader_ui, "night_gradient_left", p.night.left)
  write_profile(reader_ui, "night_gradient_right", p.night.right)
  write_profile(reader_ui, "night_opacity", p.night.opacity)
  clear_caches()
end

-- Settings UI
local function show_settings(reader_ui)
  local items = {
    {
      text = _("Enable overlay"),
      checked_func = function() return active end,
      callback = function()
        active = not active
        settings:save("enabled", active)
        clear_caches()
        UIManager:show(InfoMessage:new{ text = active and _("Overlay enabled") or _("Overlay disabled") })
        if not active then UIManager:setDirty("all", "full") end
      end
    },
    {
      text = _("Auto-detect Night Mode"),
      checked_func = function() return settings:read("auto_detect_night") end,
      callback = function()
        settings:save("auto_detect_night", not settings:read("auto_detect_night"))
        clear_caches()
        UIManager:show(InfoMessage:new{ text = _("Night detection toggled") })
      end
    },
    {
      text = _("Segmentation: ") .. read_profile(reader_ui, "segment_method", settings:read("segment_method")),
      sub_item_table = {
        { text=_("Smart"),   checked_func=function() return read_profile(reader_ui,"segment_method",settings:read("segment_method"))=="smart" end,
          callback=function() write_profile(reader_ui,"segment_method","smart"); clear_caches() end },
        { text=_("Thirds"),  checked_func=function() return read_profile(reader_ui,"segment_method",settings:read("segment_method"))=="thirds" end,
          callback=function() write_profile(reader_ui,"segment_method","thirds"); clear_caches() end },
        { text=_("Halves"),  checked_func=function() return read_profile(reader_ui,"segment_method",settings:read("segment_method"))=="halves" end,
          callback=function() write_profile(reader_ui,"segment_method","halves"); clear_caches() end },
        { text=_("Tokenizer (if available)"),
          checked_func=function() return read_profile(reader_ui,"segment_method",settings:read("segment_method"))=="token" end,
          callback=function() write_profile(reader_ui,"segment_method","token"); clear_caches() end },
      }
    },
    {
      text = _("Presets"),
      sub_item_table = {
        { text="Classic",       callback=function() apply_preset(reader_ui,"Classic") end },
        { text="Calm",          callback=function() apply_preset(reader_ui,"Calm") end },
        { text="High Contrast", callback=function() apply_preset(reader_ui,"HighContrast") end },
      }
    },
  }
  local menu = Menu:new{ title = _("Gradient Overlay Settings"), item_table = items }
  UIManager:show(menu)
end

-- Widget & lifecycle
local GradientWidget = WidgetContainer:extend{}
function GradientWidget:init(p) self.plugin = p end
function GradientWidget:onPaintTo(bb, x, y)
  if self.plugin and self.plugin.ui and active then
    render_overlay(self.plugin.ui, self)
  end
end

function Plugin:init()
  self.ui.menu:registerToMainMenu(self)
end

function Plugin:addToMainMenu(items)
  items.gradient_overlay = {
    text = _("Gradient Overlay"),
    sub_item_table = {
      { text = _("Toggle / Settings"), callback = function() show_settings(self.ui) end },
    }
  }
end

function Plugin:onReaderReady()
  self.view = self.ui.view
  self.widget = GradientWidget:new{ plugin = self }
  self.ui:handleEvent(Event:new("AddWidget", self.widget))
end

local function schedule_redraw(self)
  UIManager:nextTick(function()
    if active then render_overlay(self.ui, self.widget) end
  end)
end

function Plugin:onPageUpdate() clear_caches() schedule_redraw(self) end
function Plugin:onDocumentReady() clear_caches() end
function Plugin:onSetPageMode() clear_caches() end
function Plugin:onNightModeChanged() clear_caches() schedule_redraw(self) end

return Plugin
