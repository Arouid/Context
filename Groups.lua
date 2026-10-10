-- Groups.lua: groups of displays (grow direction, spacing), placement on screen, and the edit mode
-- that unlocks every group and standalone display for dragging. Positions are saved as offsets
-- from the screen center. Out of combat only: combat starting locks everything again.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
--
-- Group definition (ContextDB.groups[id]): { id, name, grow = "RIGHT" | "LEFT" | "UP" | "DOWN",
-- spacing, pos = { x, y }, children = { displayId, ... } }.
-- Blizzard's Edit Mode integration (LibEditMode) is the planned next step; this is the plain drag.
local _, ns = ...
local L = ns.L

local Groups = {}
ns.Groups = Groups

local frames = {}        -- group id -> frame
local editing = false
local handles = setmetatable({}, { __mode = "k" })   -- frame -> its edit-mode overlay

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
-- Frames
----------------------------------------------------------------------------------------------------

local function Anchor(frame, pos)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", pos and pos.x or 0, pos and pos.y or 0)
end

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
        Anchor(f, def.pos)
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
    end
end

----------------------------------------------------------------------------------------------------
-- Edit mode: drag to move
----------------------------------------------------------------------------------------------------

local function SavePos(frame, holder)
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not cx or not ux then return end
    holder.pos = { x = math.floor(cx - ux + 0.5), y = math.floor(cy - uy + 0.5) }
    Anchor(frame, holder.pos)
end

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

local function ForEachMovable(fn)
    for id, def in pairs(ns.db.groups or {}) do fn(Groups.Parent(id), def.name or id, def) end
    for _, id in ipairs(ns.Displays.Order()) do
        local entry = ns.Displays.Get(id)
        if entry and not entry.def.group then fn(entry.frame, entry.def.name or id, entry.def) end
    end
end

-- Groups.SetEditMode(on) -> true when the mode changed. Refused in combat.
function Groups.SetEditMode(on)
    if on and InCombatLockdown and InCombatLockdown() then
        ns:Print(L["Edit mode isn't available in combat."])
        return false
    end
    editing = on and true or false
    ForEachMovable(function(frame, label, holder)
        frame:SetMovable(editing)
        frame:SetClampedToScreen(editing)
        local h = Handle(frame, label, holder)
        h:SetShown(editing)
        if editing and not frame:IsShown() then frame:Show(); h.wasHidden = true
        elseif not editing and h.wasHidden then h.wasHidden = nil; ns.Displays.MarkDirty() end
    end)
    ns:Print(editing and L["Edit mode: drag to move. /context edit again to lock."] or L["Edit mode off."])
    return true
end

function Groups.IsEditing() return editing end

local combat = CreateFrame("Frame")
pcall(combat.RegisterEvent, combat, "PLAYER_REGEN_DISABLED")
combat:SetScript("OnEvent", function()
    if editing then
        Groups.SetEditMode(false)
        ns:Print(L["Edit mode closed: combat started."])
    end
end)
