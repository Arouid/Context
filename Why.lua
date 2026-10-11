-- Why.lua: /context why [displayId]: the facts that decide whether a display can be seen, read
-- back from its frame: size, anchor, parent, alpha, shown state, center against the screen. With
-- an id the full facts of that display and of its group; without one a line per display and per
-- group. Also feeds the lines of /context list. Nothing here is a secret: frame geometry is plain.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
--
-- Why it exists: in game on 2026-10-10 seven displays were listed "shown" and one icon was on
-- screen (five stacked on a 1 px group), then a drag saved the group at x = -1003 (the left edge).
-- Both facts were only visible in the SavedVariables after logout; this prints them at once.
local _, ns = ...
local L = ns.L

local Why = {}
ns.Why = Why

local function Read(obj, method, ...)
    if type(obj) ~= "table" or type(obj[method]) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(obj[method], obj, ...)
    if ok then return a, b, c, d, e end
    return nil
end

-- A number for the lines: whole numbers plain, others with one decimal (a clamped -968.5 stays
-- readable), `digits` when given; a -0 offset (a layout's -y) prints as 0.
local function Num(v, digits)
    if type(v) ~= "number" then return "?" end
    if v == 0 then v = 0 end
    if digits == nil then digits = (v == math.floor(v)) and 0 or 1 end
    return string.format("%." .. digits .. "f", v)
end

-- Why.Name(frame) -> how a frame is called in the lines: UIParent, a group, a display, its name.
function Why.Name(frame)
    if frame == nil then return L["none"] end
    if frame == UIParent then return "UIParent" end
    if type(frame) == "table" and frame.groupID then return L["group"] .. " " .. tostring(frame.groupID) end
    for _, id in ipairs(ns.Displays and ns.Displays.Order() or {}) do
        local entry = ns.Displays.Get(id)
        if entry and entry.frame == frame then return id end
    end
    local name = Read(frame, "GetName")
    return name and tostring(name) or L["a frame"]
end

-- Why.Facts(frame) -> { w, h, alpha, shown, visible, scale, parent, point, relativeTo,
-- relativePoint, x, y, cx, cy, screenW, screenH, onScreen }: what the frame answers, nil where
-- it answered nothing. The center is converted into UIParent's scale, the one the screen is in.
function Why.Facts(frame)
    local f = {}
    f.w, f.h = Read(frame, "GetSize")
    f.alpha = Read(frame, "GetAlpha")
    f.shown, f.visible = Read(frame, "IsShown"), Read(frame, "IsVisible")
    f.scale = Read(frame, "GetEffectiveScale")
    f.parent = Read(frame, "GetParent")
    f.points = Read(frame, "GetNumPoints")
    f.point, f.relativeTo, f.relativePoint, f.x, f.y = Read(frame, "GetPoint", 1)
    f.screenW, f.screenH = ns.Groups.Screen()
    local cx, cy = Read(frame, "GetCenter")
    local us = Read(UIParent, "GetEffectiveScale")
    if type(cx) == "number" and type(f.scale) == "number" and type(us) == "number" and us > 0 then cx, cy = cx * f.scale / us, cy * f.scale / us end
    f.cx, f.cy = cx, cy
    if type(cx) == "number" and type(cy) == "number" and f.screenW > 0 then
        f.onScreen = cx >= 0 and cx <= f.screenW and cy >= 0 and cy <= f.screenH
    end
    return f
end

-- Why.Summary(frame) -> "36 x 36, on screen" (or "no size", "not anchored", "off screen", "alpha 0").
function Why.Summary(frame)
    local f = Why.Facts(frame)
    local parts = {}
    if type(f.w) == "number" and type(f.h) == "number" and f.w > 0 and f.h > 0 then parts[#parts + 1] = Num(f.w) .. " x " .. Num(f.h)
    else parts[#parts + 1] = L["no size"] end
    if (f.points or 0) == 0 then parts[#parts + 1] = L["not anchored"] end
    if type(f.alpha) == "number" and f.alpha <= 0 then parts[#parts + 1] = "alpha 0" end
    if f.onScreen == true then parts[#parts + 1] = L["on screen"]
    elseif f.onScreen == false then parts[#parts + 1] = L["off screen"] end
    return table.concat(parts, ", ")
end

local function PrintFrame(label, frame, pos)
    local f = Why.Facts(frame)
    local shown = f.shown and L["shown"] or L["hidden"]
    local visible = f.visible == nil and "" or (", " .. (f.visible and L["visible"] or L["not visible"]))
    ns:Printf("%s: %s x %s, alpha %s, %s%s, %s", label, Num(f.w), Num(f.h), Num(f.alpha, 2), shown, visible,
        f.onScreen == nil and "?" or (f.onScreen and L["on screen"] or L["off screen"]))
    if (f.points or 0) > 0 then
        ns:Printf("  " .. L["anchor"] .. " %s -> %s %s (%s, %s)", tostring(f.point), Why.Name(f.relativeTo), tostring(f.relativePoint), Num(f.x), Num(f.y))
    else
        ns:Print("  " .. L["not anchored"])
    end
    local parentShown = Read(f.parent, "IsShown")
    ns:Printf("  " .. L["parent"] .. " %s (%s), " .. L["scale"] .. " %s", Why.Name(f.parent),
        parentShown == nil and "?" or (parentShown and L["shown"] or L["hidden"]), Num(f.scale, 2))
    ns:Printf("  " .. L["center"] .. " %s, %s; " .. L["screen center"] .. " %s, %s; " .. L["screen"] .. " %s x %s",
        Num(f.cx), Num(f.cy), Num(f.screenW / 2), Num(f.screenH / 2), Num(f.screenW), Num(f.screenH))
    if pos then ns:Printf("  " .. L["saved pos"] .. " %s, %s", tostring(pos.x), tostring(pos.y)) end
end

-- Why.Print(id): the full facts of one display, then of its group when it has one.
function Why.Print(id)
    local entry = ns.Displays and ns.Displays.Get(id)
    if not entry then
        ns:Printf(L["No display %s. /context list names them."], tostring(id))
        return false
    end
    local def = entry.def
    local where = def.group and (", " .. L["group"] .. " " .. tostring(def.group)) or ""
    PrintFrame(string.format("%s (%s%s)", id, def.type, where), entry.frame, (not def.group) and def.pos or nil)
    if entry.frame.textureID ~= nil then ns:Printf("  " .. L["texture"] .. " %s", tostring(entry.frame.textureID)) end
    if def.group and ns.db.groups and ns.db.groups[def.group] then
        PrintFrame(L["group"] .. " " .. tostring(def.group), ns.Groups.Parent(def.group), ns.db.groups[def.group].pos)
    end
    if ns.Displays.lastError then ns:Printf(L["last display error: %s"], tostring(ns.Displays.lastError)) end
    return true
end

-- Why.PrintAll(): one line per group, one per display.
function Why.PrintAll()
    for gid, g in pairs(ns.db.groups or {}) do
        ns:Printf("%s %s: %s (" .. L["saved pos"] .. " %s, %s)", L["group"], gid, Why.Summary(ns.Groups.Parent(gid)),
            tostring(g.pos and g.pos.x), tostring(g.pos and g.pos.y))
    end
    for _, id in ipairs(ns.Displays and ns.Displays.Order() or {}) do
        local entry = ns.Displays.Get(id)
        if entry then ns:Printf("  %s: %s", id, Why.Summary(entry.frame)) end
    end
    if ns.Displays and ns.Displays.lastError then ns:Printf(L["last display error: %s"], tostring(ns.Displays.lastError)) end
end
