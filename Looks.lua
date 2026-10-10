-- Looks.lua: how a display looks. Defaults per display type, the merge of a state's look over the
-- base look, and the media lookups (LibSharedMedia when another addon ships it, the game's own
-- fonts and textures otherwise). Pure except the media lookups: tested headless.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
local _, ns = ...

local Looks = {}
ns.Looks = Looks

-- The game's own media, always there. LibSharedMedia names are looked up first when present.
Looks.FONTS = {
    ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
    ["Skurri"] = "Fonts\\skurri.ttf",
    ["Morpheus"] = "Fonts\\MORPHEUS.ttf",
}
Looks.TEXTURES = {
    ["Blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar",
    ["Flat"] = "Interface\\Buttons\\WHITE8x8",
    ["Raid"] = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}
Looks.BORDERS = {
    ["None"] = nil,
    ["Flat"] = "Interface\\Buttons\\WHITE8x8",
    ["Tooltip"] = "Interface\\Tooltips\\UI-Tooltip-Border",
}
Looks.OUTLINES = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE", mono = "OUTLINE, MONOCHROME" }

-- Looks.Media(kind, name) -> path or nil. kind: "font" | "statusbar" | "border".
function Looks.Media(kind, name)
    if name == nil then return nil end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local path = LSM:Fetch(kind, name, true)
        if path then return path end
    end
    if kind == "font" then return Looks.FONTS[name] or name end
    if kind == "statusbar" then return Looks.TEXTURES[name] or name end
    if kind == "border" then return Looks.BORDERS[name] end
    return name
end

-- Looks.Default(type) -> a fresh default look for "icon" or "bar". Colors are { r, g, b, a }.
function Looks.Default(displayType)
    if displayType == "bar" then
        return {
            width = 180, height = 18, texture = "Blizzard", color = { 0.25, 0.78, 0.92, 1 },
            background = { 0, 0, 0, 0.6 }, border = { style = "Flat", size = 1, color = { 0, 0, 0, 1 } },
            spark = true, icon = true, alpha = 1,
            text = { show = true, font = "Friz Quadrata", size = 11, outline = "outline", color = { 1, 1, 1, 1 } },
            timer = { show = true, font = "Friz Quadrata", size = 11, outline = "outline", color = { 1, 1, 1, 1 } },
            glow = false,
        }
    end
    return {
        size = 36, alpha = 1, color = { 1, 1, 1, 1 }, desaturate = false, zoom = 0.08,
        border = { style = "Flat", size = 1, color = { 0, 0, 0, 1 } },
        swipe = { show = true, color = { 0, 0, 0, 0.8 }, reverse = false, edge = true },
        timer = { show = true, font = "Friz Quadrata", size = 12, outline = "outline", color = { 1, 1, 1, 1 }, point = "CENTER" },
        stacks = { show = true, font = "Friz Quadrata", size = 11, outline = "outline", color = { 1, 1, 1, 1 }, point = "BOTTOMRIGHT" },
        glow = false, outOfRange = { color = { 0.8, 0.1, 0.1, 1 } },
    }
end

-- Looks.Merge(base, over) -> a new table: `over` written on top of a deep copy of `base`. Tables
-- merge recursively, except color lists (4 numbers), which are replaced whole.
local function IsColor(t)
    return type(t) == "table" and type(t[1]) == "number" and #t >= 3 and #t <= 4
end

local function Copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and Copy(v) or v end
    return out
end

function Looks.Merge(base, over)
    local out = base and Copy(base) or {}
    for k, v in pairs(over or {}) do
        if type(v) == "table" and type(out[k]) == "table" and not IsColor(v) then
            out[k] = Looks.Merge(out[k], v)
        else
            out[k] = type(v) == "table" and Copy(v) or v
        end
    end
    return out
end

-- Looks.Resolve(displayType, baseLook, stateLooks) -> the effective look: defaults, then the
-- display's own look, then each active state's look in order.
function Looks.Resolve(displayType, baseLook, stateLooks)
    local look = Looks.Merge(Looks.Default(displayType), baseLook)
    for _, over in ipairs(stateLooks or {}) do look = Looks.Merge(look, over) end
    return look
end

-- Looks.ApplyFont(fontString, text) sets font, size, outline and color from a text look.
function Looks.ApplyFont(fontString, text)
    if not fontString or not text then return end
    local path = Looks.Media("font", text.font) or Looks.FONTS["Friz Quadrata"]
    fontString:SetFont(path, text.size or 12, Looks.OUTLINES[text.outline or "outline"] or "OUTLINE")
    local c = text.color or { 1, 1, 1, 1 }
    fontString:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

-- Looks.ApplyBorder(frame, border): a plain backdrop-free border made of four textures, created once.
function Looks.ApplyBorder(frame, border)
    if not frame then return end
    frame.ctxBorder = frame.ctxBorder or {}
    local edges = frame.ctxBorder
    local show = border and border.style and border.style ~= "None" and (border.size or 0) > 0
    for i = 1, 4 do
        if not edges[i] then
            edges[i] = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        end
        edges[i]:SetShown(show and true or false)
    end
    if not show then return end
    local size = border.size or 1
    local c = border.color or { 0, 0, 0, 1 }
    local path = Looks.Media("border", border.style) or Looks.BORDERS["Flat"]
    for i = 1, 4 do
        edges[i]:SetTexture(path)
        edges[i]:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        edges[i]:ClearAllPoints()
    end
    edges[1]:SetPoint("TOPLEFT", -size, size); edges[1]:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", size, 0)
    edges[2]:SetPoint("BOTTOMLEFT", -size, -size); edges[2]:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", size, 0)
    edges[3]:SetPoint("TOPLEFT", -size, 0); edges[3]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0)
    edges[4]:SetPoint("TOPRIGHT", size, 0); edges[4]:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, 0)
end

-- Looks.Color(c) -> r, g, b, a from a color list, white when missing.
function Looks.Color(c)
    if type(c) ~= "table" then return 1, 1, 1, 1 end
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end
