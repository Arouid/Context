-- Groups.lua: groups of displays (grow direction, spacing), placement on screen, and the two ways
-- to move things: Blizzard's Edit Mode through LibEditMode when the library is embedded, and the
-- plain drag of /context edit as the fallback. Positions are saved as offsets from the screen
-- center either way. Out of combat only: combat starting locks everything again.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
--
-- Group definition (ContextDB.groups[id]): { id, name, grow = "RIGHT" | "LEFT" | "UP" | "DOWN",
-- spacing, pos = { x, y }, children = { displayId, ... } }.
local _, ns = ...
local L = ns.L

local Groups = {}
ns.Groups = Groups

local frames = {}        -- group id -> frame
local editing = false    -- the plain drag's state (the library keeps its own)
local handles = setmetatable({}, { __mode = "k" })   -- frame -> its plain-drag overlay

----------------------------------------------------------------------------------------------------
-- Pure layout (tested headless)
----------------------------------------------------------------------------------------------------

-- Groups.Positions(sizes, grow, spacing) -> offsets, width, height. `sizes` is a list of
-- { w, h }; each offset is { x, y } of that child's TOPLEFT from the group's TOPLEFT (y goes down).
function Groups.Positions(sizes, grow, spacing)
    spacing = spacing or 0
    local offsets, width, height = {}, 0, 0
    local horizontal = grow == "RIGHT" or grow == "LEFT"
    local run = 0
    for i, s in ipairs(sizes) do
        if horizontal then
            offsets[i] = { x = run, y = 0 }
            run = run + s.w + spacing
            height = math.max(height, s.h)
        else
            offsets[i] = { x = 0, y = run }
            run = run + s.h + spacing
            width = math.max(width, s.w)
        end
    end
    if #sizes > 0 then run = run - spacing end
    if horizontal then width = run else height = run end
    if grow == "LEFT" then
        for i, s in ipairs(sizes) do offsets[i].x = width - offsets[i].x - s.w end
    elseif grow == "UP" then
        for i, s in ipairs(sizes) do offsets[i].y = height - offsets[i].y - s.h end
    end
    return offsets, width, height
end

----------------------------------------------------------------------------------------------------
-- Positions: anchor from a saved pos, save a pos from where a frame is
----------------------------------------------------------------------------------------------------

-- Groups.Clamp(x, y, w, h, screenW, screenH) -> x, y: offsets from the screen center kept so a
-- frame of w x h stays on a screenW x screenH screen. A missing or broken number (NaN, infinite)
-- is 0; a screen size of 0 (not known yet) clamps nothing. Pure, tested headless. Seen in game
-- 2026-10-10: a drag saved x = -1003 for the group, its icons at the left edge, nothing to find.
local function Finite(v)
    if type(v) ~= "number" or v ~= v then return false end
    local s = tostring(v)   -- Elune (the test runtime) says NaN == NaN and NaN < inf: the text tells
    return not (s:find("nan", 1, true) or s:find("inf", 1, true))
end

function Groups.Clamp(x, y, w, h, screenW, screenH)
    local function Fix(v) if Finite(v) then return v end return 0 end
    local function Within(v, size, screen)
        if type(screen) ~= "number" or screen <= 0 then return v end
        local limit = math.max((screen - Fix(size)) / 2, 0)
        return math.max(-limit, math.min(limit, v))
    end
    return Within(Fix(x), w, screenW), Within(Fix(y), h, screenH)
end

-- Groups.Screen() -> width, height of UIParent in its own scale (the space our offsets live in).
function Groups.Screen()
    local ok, w, h = pcall(UIParent.GetSize, UIParent)
    if ok and type(w) == "number" and type(h) == "number" then return w, h end
    return 0, 0
end

-- Anchors the frame's center on the saved offsets, pulled back onto the screen; a saved pos that
-- needed pulling is corrected in place, so the SavedVariables say where the frame really is.
local function Anchor(frame, pos)
    local sw, sh = Groups.Screen()
    local w, h = frame:GetSize()
    local x, y = Groups.Clamp(pos and pos.x, pos and pos.y, w, h, sw, sh)
    if pos and (pos.x ~= x or pos.y ~= y) then pos.x, pos.y = x, y end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    pcall(frame.SetClampedToScreen, frame, true)   -- the engine's own guard, whatever the math did
end

-- SavePos(frame, holder): writes holder.pos from the frame's center, as offsets from the screen
-- center (both read in UIParent's scale), then re-anchors the frame on it (whatever point a drag
-- left it on). Anchor pulls the offsets back onto the screen before they are kept.
local function SavePos(frame, holder)
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not cx or not ux then return end
    local okF, fs = pcall(frame.GetEffectiveScale, frame)
    local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
    if okF and okU and type(fs) == "number" and type(us) == "number" and us > 0 then cx, cy = cx * fs / us, cy * fs / us end
    holder.pos = { x = math.floor(cx - ux + 0.5), y = math.floor(cy - uy + 0.5) }
    Anchor(frame, holder.pos)
end

-- ForEachMovable(fn): fn(frame, label, holder) for every group and every standalone display.
local function ForEachMovable(fn)
    for id, def in pairs(ns.db.groups or {}) do fn(Groups.Parent(id), def.name or id, def) end
    for _, id in ipairs(ns.Displays.Order()) do
        local entry = ns.Displays.Get(id)
        if entry and not entry.def.group then fn(entry.frame, entry.def.name or id, entry.def) end
    end
end

----------------------------------------------------------------------------------------------------
-- Blizzard's Edit Mode (LibEditMode, embedded unmodified under Libs/ when present)
----------------------------------------------------------------------------------------------------

local registered = setmetatable({}, { __mode = "k" })   -- frame -> the table holding its pos
local hooked = false

local function Lib()
    return LibStub and LibStub("LibEditMode", true) or nil
end

-- The library anchored the frame where the drag ended (point, x, y from UIParent); the saved
-- position stays an offset from the screen center, so read the center back and re-anchor.
local function OnMoved(frame)
    local holder = registered[frame]
    if holder then SavePos(frame, holder) end
end

local function HookLibrary(lib)
    if hooked then return end
    hooked = true
    -- Entering: show what a state keeps hidden so it can be dragged; the refresh leaves the shown
    -- state alone while editing (Groups.IsEditing). Leaving: a dirty refresh hides it again.
    lib:RegisterCallback("enter", function()
        ForEachMovable(function(frame) if not frame:IsShown() then frame:Show() end end)
    end)
    lib:RegisterCallback("exit", function() ns.Displays.MarkDirty() end)
    -- The layout callback fires at login once Blizzard's layouts are known: re-anchor on the saved
    -- positions (the library has no positions of its own for our frames).
    lib:RegisterCallback("layout", function()
        ForEachMovable(function(frame, _, holder) Anchor(frame, holder.pos) end)
    end)
end

-- Register(frame, label, holder) -> true when the frame went into Blizzard's Edit Mode (once per
-- frame). `label` is the name shown on its selection, `holder` the table whose pos is used.
local function Register(frame, label, holder)
    local lib = Lib()
    if not lib then return false end
    -- A reused widget keeps its registration but follows its new definition (Displays.Build).
    if registered[frame] then registered[frame] = holder return false end
    HookLibrary(lib)
    registered[frame] = holder
    local pos = holder.pos or {}
    lib:AddFrame(frame, OnMoved, { point = "CENTER", x = pos.x or 0, y = pos.y or 0 }, tostring(label))
    return true
end

-- Groups.InEditMode() -> true while Blizzard's Edit Mode is open with the library loaded.
function Groups.InEditMode()
    local lib = Lib()
    return lib ~= nil and lib:IsInEditMode() == true
end

----------------------------------------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------------------------------------

-- Groups.Parent(groupId) -> the group's frame (created on demand), or UIParent without a group.
function Groups.Parent(groupId)
    if not groupId then return UIParent end
    local def = ns.db.groups and ns.db.groups[groupId]
    if not def then return UIParent end
    local f = frames[groupId]
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(36, 36)
        f.groupID = groupId
        frames[groupId] = f
    end
    -- A new definition under a known id (the first time; /context reset then a preset in the same
    -- session): anchor on its pos and make it the table Edit Mode saves into, not the one reset threw away.
    if f.def ~= def then
        f.def = def
        Anchor(f, def.pos)
        Register(f, def.name or groupId, def)
    end
    return f
end

local function Entries(def)
    local list = {}
    for _, id in ipairs(def.children or {}) do
        local entry = ns.Displays.Get(id)
        if entry and entry.def.group == def.id then list[#list + 1] = entry end
    end
    return list
end

-- Groups.Layout(groupId): places the group's children by its grow direction and spacing.
function Groups.Layout(groupId)
    local def = groupId and ns.db.groups and ns.db.groups[groupId]
    if not def then return end
    local frame = Groups.Parent(groupId)
    local entries = Entries(def)
    local sizes = {}
    for i, entry in ipairs(entries) do
        local w, h = entry.frame:GetSize()
        sizes[i] = { w = w or 36, h = h or 36 }
    end
    local offsets, width, height = Groups.Positions(sizes, def.grow or "RIGHT", def.spacing or 4)
    for i, entry in ipairs(entries) do
        entry.frame:ClearAllPoints()
        entry.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", offsets[i].x, -offsets[i].y)
    end
    frame:SetSize(math.max(width, 1), math.max(height, 1))
end

function Groups.LayoutAll()
    for id in pairs(ns.db.groups or {}) do Groups.Layout(id) end
end

-- Groups.Place(entry): a child goes through its group's layout, a standalone display to its pos.
function Groups.Place(entry)
    local def = entry.def
    if def.group and ns.db.groups and ns.db.groups[def.group] then
        local g = ns.db.groups[def.group]
        g.children = g.children or {}
        local listed = false
        for _, id in ipairs(g.children) do if id == def.id then listed = true end end
        if not listed then g.children[#g.children + 1] = def.id end
        Groups.Layout(def.group)
    else
        entry.frame:SetParent(UIParent)
        Anchor(entry.frame, def.pos)
        Register(entry.frame, def.name or def.id, def)
    end
end

----------------------------------------------------------------------------------------------------
-- Plain drag (/context edit): the fallback when the library isn't there
----------------------------------------------------------------------------------------------------

local function Handle(frame, label, holder)
    local h = handles[frame]
    if not h then
        h = CreateFrame("Frame", nil, frame)
        h:SetAllPoints()
        h:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
        h.bg = h:CreateTexture(nil, "BACKGROUND")
        h.bg:SetAllPoints()
        h.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        h.bg:SetVertexColor(0.2, 0.8, 1, 0.35)
        h.text = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        h.text:SetPoint("BOTTOM", h, "TOP", 0, 2)
        h:EnableMouse(true)
        h:RegisterForDrag("LeftButton")
        h:SetScript("OnDragStart", function() frame:StartMoving() end)
        h:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); SavePos(frame, h.holder) end)
        handles[frame] = h
    end
    h.holder = holder
    h.text:SetText(label or "")
    return h
end

-- Groups.SetEditMode(on) -> true when the mode changed. Refused in combat; with the library
-- loaded the frames belong to Blizzard's Edit Mode, so it only says where to go.
function Groups.SetEditMode(on)
    if Lib() then
        ns:Print(L["The displays are in Blizzard's Edit Mode: Esc, then Edit Mode."])
        return false
    end
    if on and InCombatLockdown and InCombatLockdown() then
        ns:Print(L["Edit mode isn't available in combat."])
        return false
    end
    editing = on and true or false
    ForEachMovable(function(frame, label, holder)
        frame:SetMovable(editing)
        local h = Handle(frame, label, holder)
        h:SetShown(editing)
        if editing and not frame:IsShown() then frame:Show(); h.wasHidden = true
        elseif not editing and h.wasHidden then h.wasHidden = nil; ns.Displays.MarkDirty() end
    end)
    ns:Print(editing and L["Edit mode: drag to move. /context edit again to lock."] or L["Edit mode off."])
    return true
end

-- Groups.IsEditing() -> true while either edit mode is open (the refresh then keeps every display
-- shown instead of applying its states' visibility).
function Groups.IsEditing() return editing or Groups.InEditMode() end

local combat = CreateFrame("Frame")
pcall(combat.RegisterEvent, combat, "PLAYER_REGEN_DISABLED")
combat:SetScript("OnEvent", function()
    if editing then
        Groups.SetEditMode(false)
        ns:Print(L["Edit mode closed: combat started."])
    end
end)
