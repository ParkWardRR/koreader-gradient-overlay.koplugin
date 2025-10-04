-- KOReader plugin: Gradient Overlay (local segmentation + night mode support)
local Plugin = {
    name = "Gradient Overlay",
    description = "Local line-tracking gradient overlay with night mode detection",
    version = "1.1.0",
}

local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Screen = require("device").screen
local LuaSettings = require("luasettings")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/menu")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local SETTINGS_KEY = "plugins.gradient_overlay"
local defaults = {
    enabled = false,
    gradient_left = { r = 255, g = 100, b = 100 },     -- light mode start
    gradient_right = { r = 100, g = 100, b = 255 },    -- light mode end
    night_gradient_left = { r = 180, g = 60, b = 60 }, -- night mode start
    night_gradient_right = { r = 60, g = 60, b = 180 },-- night mode end
    opacity = 40,
    night_opacity = 60,
    bar_height_pct = 75,
    vertical_offset = 2,
    segment_method = "smart", -- smart|thirds|halves
    auto_detect_night = true,
}

local settings = LuaSettings:open(SETTINGS_KEY, defaults)
local active = settings:read("enabled")
local overlay_cache = {}
local last_night_state = nil

local function is_night_mode_active(reader_ui)
    if not reader_ui or not settings:read("auto_detect_night") then return false end
    -- Heuristic checks; KOReader’s internals vary by build [user guide/dev guide]
    local ok
    -- Document-level hints
    if reader_ui.doc_settings and reader_ui.doc_settings.night_mode ~= nil then
        return reader_ui.doc_settings.night_mode
    end
    -- AutoWarmth plugin (if present)
    ok = pcall(function()
        local AutoWarmth = require("plugins/autowarmth")
        if AutoWarmth and AutoWarmth.activate_nightmode ~= nil then
            return AutoWarmth.activate_nightmode
        end
    end)
    if type(ok) == "boolean" then return ok end
    -- View/document inversion hint
    if reader_ui.view and reader_ui.view.document and reader_ui.view.document.configurable then
        local cfg = reader_ui.view.document.configurable
        if cfg.nightmode_images == 1 then return true end
    end
    return false
end

local function lerp(a, b, t) return math.floor(a + (b - a) * t + 0.5) end

local function get_current_colors(reader_ui)
    local night = is_night_mode_active(reader_ui)
    if last_night_state ~= nil and last_night_state ~= night then
        overlay_cache = {}
    end
    last_night_state = night
    if night then
        return {
            left = settings:read("night_gradient_left"),
            right = settings:read("night_gradient_right"),
            opacity = settings:read("night_opacity"),
        }
    else
        return {
            left = settings:read("gradient_left"),
            right = settings:read("gradient_right"),
            opacity = settings:read("opacity"),
        }
    end
end

local function color_at_position(t, cols)
    t = math.max(0, math.min(1, t))
    local L, R = cols.left, cols.right
    return {
        r = lerp(L.r, R.r, t),
        g = lerp(L.g, R.g, t),
        b = lerp(L.b, R.b, t),
    }
end

-- Rule-based segmentation: punctuation + conjunctions + long words
local function get_smart_breaks(text)
    local breaks = {}
    local len = #text
    if len < 20 then return breaks end
    for i = 1, len do
        local ch = text:sub(i, i)
        if ch:match("[,;:%-—]") then table.insert(breaks, i) end
    end
    if #breaks < 2 then
        local keys = { " and ", " or ", " but ", " the ", " that ", " which ", " with ", " for ", " from ", " into ", " onto ", " upon ", " over ", " under " }
        for _, w in ipairs(keys) do
            local s = 1
            while true do
                local pos = text:find(w, s, true)
                if not pos then break end
                table.insert(breaks, pos + #w - 1)
                s = pos + 1
            end
        end
    end
    if #breaks < 2 then
        for word in text:gmatch("%S+") do
            if #word > 8 then
                local pos = text:find(word, 1, true)
                if pos then table.insert(breaks, pos + math.floor(#word / 2)) end
            end
        end
    end
    table.sort(breaks)
    if #breaks == 0 then
        table.insert(breaks, math.floor(len * 0.4))
        table.insert(breaks, math.floor(len * 0.7))
    elseif #breaks == 1 then
        if breaks[1] < len * 0.3 then
            table.insert(breaks, math.floor(len * 0.7))
        else
            table.insert(breaks, 1, math.floor(len * 0.3))
        end
    end
    if #breaks > 4 then
        local pruned = {}
        local step = #breaks / 4
        for i = 1, 4 do pruned[#pruned + 1] = breaks[math.floor(i * step)] end
        breaks = pruned
    end
    return breaks
end

local function get_simple_breaks(text, method)
    local len = #text
    if method == "halves" then
        return { math.floor(len / 2) }
    elseif method == "thirds" then
        return { math.floor(len / 3), math.floor(2 * len / 3) }
    end
    return {}
end

local function get_line_breaks(text)
    local m = settings:read("segment_method")
    if m == "smart" then return get_smart_breaks(text) end
    return get_simple_breaks(text, m)
end

local function draw_line_gradient(x, y, width, height, text, breaks, cols)
    if width <= 0 or height <= 0 then return end
    local BB = require("ffi/blitbuffer")
    local opacity = cols.opacity
    local n = #text
    if n == 0 then return end
    local segments, last = {}, 1
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
            local t0 = (seg.s - 1) / n
            local t1 = seg.e / n
            local strips = math.max(4, math.floor(segw / 4))
            for k = 0, strips - 1 do
                local cx0 = x + acc + math.floor(k * segw / strips)
                local cx1 = x + acc + math.floor((k + 1) * segw / strips)
                local ts = t0 + (t1 - t0) * (k / math.max(1, strips - 1))
                local c = color_at_position(ts, cols)
                local col = BB.Color8.fromRGB(c.r, c.g, c.b)
                Screen:fillRect(cx0, y, math.max(1, cx1 - cx0), height, col, opacity)
            end
        end
        acc = acc + segw
    end
end

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
            if #lines >= 50 then break end
        end
    end
    return lines
end

local function get_line_positions(reader_ui, count)
    local pos = {}
    local h, w = Screen:getHeight(), Screen:getWidth()
    local top, bottom, left, right = 40, 60, 30, 30
    local rh, rw = h - top - bottom, w - left - right
    local lh = math.floor(rh / math.max(1, count))
    for i = 1, count do
        pos[#pos + 1] = {
            x = left,
            y = top + (i - 1) * lh + settings:read("vertical_offset"),
            width = rw,
            height = math.floor(lh * settings:read("bar_height_pct") / 100),
        }
    end
    return pos
end

local function render_overlay(reader_ui)
    if not active then return end
    local cols = get_current_colors(reader_ui)
    local key = tostring(reader_ui:getCurrentPage() or 0) .. "_" .. tostring(last_night_state)
    if overlay_cache[key] then return end
    local lines = get_page_lines(reader_ui)
    if not lines or #lines == 0 then return end
    local rects = get_line_positions(reader_ui, #lines)
    for i, line in ipairs(lines) do
        if rects[i] then
            local b = get_line_breaks(line)
            draw_line_gradient(rects[i].x, rects[i].y, rects[i].width, rects[i].height, line, b, cols)
        end
    end
    overlay_cache[key] = true
end

local function clear_cache() overlay_cache = {} ; last_night_state = nil end

local function show_settings()
    local items = {
        {
            text = _("Auto-detect Night Mode"),
            checked_func = function() return settings:read("auto_detect_night") end,
            callback = function()
                settings:save("auto_detect_night", not settings:read("auto_detect_night"))
                clear_cache()
                UIManager:show(InfoMessage:new{ text = _("Night detection toggled") })
            end
        },
        {
            text = _("Segmentation: ") .. settings:read("segment_method"),
            sub_item_table = {
                {
                    text = _("Smart (punctuation + conjunctions)"),
                    checked_func = function() return settings:read("segment_method") == "smart" end,
                    callback = function() settings:save("segment_method", "smart") clear_cache() end
                },
                {
                    text = _("Simple thirds"),
                    checked_func = function() return settings:read("segment_method") == "thirds" end,
                    callback = function() settings:save("segment_method", "thirds") clear_cache() end
                },
                {
                    text = _("Simple halves"),
                    checked_func = function() return settings:read("segment_method") == "halves" end,
                    callback = function() settings:save("segment_method", "halves") clear_cache() end
                },
            }
        },
        {
            text = _("Light Opacity: ") .. settings:read("opacity"),
            callback = function()
                local d = InputDialog:new{ title = _("Light mode opacity (0-255)"), input = tostring(settings:read("opacity")), input_type="number",
                    buttons = { { { text=_("Cancel"), callback=function() UIManager:close(d) end },
                                 { text=_("Save"), callback=function()
                                        local v = tonumber(d:getInputText())
                                        if v and v>=0 and v<=255 then settings:save("opacity", v) clear_cache() end
                                        UIManager:close(d)
                                   end } } } }
                UIManager:show(d)
            end
        },
        {
            text = _("Night Opacity: ") .. settings:read("night_opacity"),
            callback = function()
                local d = InputDialog:new{ title = _("Night mode opacity (0-255)"), input = tostring(settings:read("night_opacity")), input_type="number",
                    buttons = { { { text=_("Cancel"), callback=function() UIManager:close(d) end },
                                 { text=_("Save"), callback=function()
                                        local v = tonumber(d:getInputText())
                                        if v and v>=0 and v<=255 then settings:save("night_opacity", v) clear_cache() end
                                        UIManager:close(d)
                                   end } } } }
                UIManager:show(d)
            end
        },
        {
            text = _("Bar Height %: ") .. settings:read("bar_height_pct"),
            callback = function()
                local d = InputDialog:new{ title = _("Bar height percentage (10-100)"), input = tostring(settings:read("bar_height_pct")), input_type="number",
                    buttons = { { { text=_("Cancel"), callback=function() UIManager:close(d) end },
                                 { text=_("Save"), callback=function()
                                        local v = tonumber(d:getInputText())
                                        if v and v>=10 and v<=100 then settings:save("bar_height_pct", v) clear_cache() end
                                        UIManager:close(d)
                                   end } } } }
                UIManager:show(d)
            end
        },
    }
    local menu = Menu:new{ title = _("Gradient Overlay Settings"), item_table = items }
    UIManager:show(menu)
end

function Plugin:init() self.ui.menu:registerToMainMenu(self) end

function Plugin:addToMainMenu(items)
    items.gradient_overlay = {
        text = _("Gradient Overlay"),
        sub_item_table = {
            {
                text = _("Enable overlay"),
                checked_func = function() return active end,
                callback = function()
                    active = not active
                    settings:save("enabled", active)
                    clear_cache()
                    UIManager:show(InfoMessage:new{ text = active and _("Overlay enabled") or _("Overlay disabled") })
                    if not active then UIManager:setDirty("all", "full") end
                end
            },
            { text = _("Settings"), callback = function() show_settings() end },
        }
    }
end

function Plugin:onReaderReady()
    self.view = self.ui.view
    self.ui:handleEvent(Event:new("ReadyToRender"))
    self.widget = WidgetContainer:extend{}:new{}
    self.widget.onPaintTo = function(_, bb, x, y)
        if active and self.ui then render_overlay(self.ui) end
    end
    self.ui:handleEvent(Event:new("AddWidget", self.widget))
end

function Plugin:onPageUpdate() clear_cache() if active then UIManager:nextTick(function() render_overlay(self.ui) end) end end
function Plugin:onDocumentReady() clear_cache() end
function Plugin:onSetPageMode() clear_cache() end
function Plugin:onNightModeChanged() clear_cache() if active then UIManager:nextTick(function() render_overlay(self.ui) end) end end

return Plugin
