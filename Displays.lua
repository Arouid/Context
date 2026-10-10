-- Displays.lua: the display engine. A display definition (saved in ContextDB.displays) names a
-- source, a base look and a list of STATES, each a condition tree with the look it adds while it
-- holds. On every refresh the sources answer, the evaluator decides each state (true / false / can't
-- say), the active looks merge over the base, and the widget gets the duration object so the engine
-- counts for it. A state the evaluator can't decide keeps its last Lua-decided value, or goes to
-- the engine when the look is a color on a timed bar (a color curve on the duration object).
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
--
-- Definition (the spec's Contract):
--   { id, type = "icon" | "bar", schema = 1, group = groupId or nil,
--     source = { kind = "spell" | "aura" | "enchant", spell = id | name | { id, name }, unit, filter, slot },
--     visibility = "always" | "whenPresent" | "whenOnCooldown" | "whenReady",
--     look = { ... },                       -- over Looks.Default(type)
--     states = { { name, when = <condition tree>, look = { ... } }, ... },
--     actions = { { on = <state name>, do = "glow" | "sound" | ..., ... }, ... },   -- Actions.lua
--     pos = { point, x, y } }               -- only for a display outside a group
-- Inputs a condition may test: spell: onCooldown, ready, remaining, enabled, charges, maxCharges,
-- usable, noPower, inRange; aura: present, missing, stacks, remaining; enchant: present, remaining,
-- charges; always: combat, hasTarget; from Blizzard's Cooldown Manager when it tracks the spell
-- (CooldownManager.lua, way B): cdmActive, cdmReady, cdmOnCooldown, cdmPandemic, cdmGlow.
local _, ns = ...
local Sources, Conditions, Looks, Widgets = ns.Sources, ns.Conditions, ns.Looks, ns.Widgets

local Displays = {}
ns.Displays = Displays

local live = {}          -- id -> { def, frame, lastStates = { [stateIndex] = bool }, visible }
local order = {}         -- ids in a stable order
local dirty = false
local TICK = 0.2

----------------------------------------------------------------------------------------------------
-- Pure parts (tested headless)
----------------------------------------------------------------------------------------------------

local function Flip(answer)
    if not answer then return nil end
    if answer.hidden or answer.value == nil then return answer end
    return { value = not answer.value, way = answer.way, hidden = false, reason = answer.reason }
end

-- Displays.Inputs(def, snaps, extra) -> the inputs table for the evaluator, from source snapshots:
-- snaps.cooldown / snaps.charges / snaps.usable / snaps.noPower / snaps.inRange / snaps.aura /
-- snaps.enchant as Sources return them; extra = { combat = bool, hasTarget = bool }.
function Displays.Inputs(def, snaps, extra)
    local inputs = {}
    local kind = def.source and def.source.kind
    if kind == "spell" then
        local cd = snaps.cooldown
        if cd then
            inputs.onCooldown, inputs.ready = cd.onCooldown, Flip(cd.onCooldown)
            inputs.remaining, inputs.enabled = cd.remaining, cd.enabled
        end
        if snaps.charges then inputs.charges, inputs.maxCharges = snaps.charges.current, snaps.charges.max end
        inputs.usable, inputs.noPower, inputs.inRange = snaps.usable, snaps.noPower, snaps.inRange
    elseif kind == "aura" then
        local a = snaps.aura
        if a then
            inputs.present, inputs.missing = a.present, Flip(a.present)
            inputs.stacks, inputs.remaining = a.stacks, a.remaining
        end
    elseif kind == "enchant" then
        local e = snaps.enchant
        if e then inputs.present, inputs.missing, inputs.remaining, inputs.charges = e.present, Flip(e.present), e.remaining, e.charges end
    end
    if extra then inputs.combat, inputs.hasTarget = extra.combat, extra.hasTarget end
    Displays.MergeEdges(inputs, snaps.cdm)
    return inputs
end

-- Displays.MergeEdges(inputs, cdm): the Cooldown Manager's edges (way B) for a tracked spell. They
-- add cdmActive / cdmReady / cdmOnCooldown / cdmPandemic / cdmGlow, and they REPLACE a presence or
-- a cooldown state the sources couldn't read (hidden): Blizzard's item saw the aura come and go.
function Displays.MergeEdges(inputs, cdm)
    if type(cdm) ~= "table" then return inputs end
    inputs.cdmActive, inputs.cdmReady, inputs.cdmOnCooldown = cdm.active, cdm.ready, cdm.onCooldown
    inputs.cdmPandemic, inputs.cdmGlow = cdm.pandemic, cdm.glow
    if cdm.active and (inputs.present == nil or inputs.present.hidden) then
        inputs.present, inputs.missing = cdm.active, Flip(cdm.active)
    end
    if cdm.onCooldown and (inputs.onCooldown == nil or inputs.onCooldown.hidden) then
        inputs.onCooldown, inputs.ready = cdm.onCooldown, Flip(cdm.onCooldown)
    end
    return inputs
end

-- Displays.Resolve(def, inputs, lastStates, secretTest) -> states, looks, visible:
--   states[i] = { active = bool, visualOnly = bool, result }: a state the evaluator can't decide
--   keeps lastStates[i] (the spec's "keep the last Lua-decided state"), false when there is none;
--   looks = the active states' looks in order; visible = true / false / nil (can't say).
function Displays.Resolve(def, inputs, lastStates, secretTest)
    local states, looks = {}, {}
    for i, state in ipairs(def.states or {}) do
        local r = Conditions.Evaluate(state.when, inputs, secretTest)
        local active = r.state
        if active == nil then active = lastStates and lastStates[i] or false end
        states[i] = { active = active, visualOnly = r.visualOnly, result = r }
        if active and state.look then looks[#looks + 1] = state.look end
    end
    return states, looks, Displays.Visible(def, inputs, secretTest)
end

local VISIBILITY = {
    whenPresent = { test = "present", compare = "==", value = true },
    whenOnCooldown = { test = "onCooldown", compare = "==", value = true },
    whenReady = { test = "onCooldown", compare = "==", value = false },
}

-- Displays.Visible(def, inputs) -> true / false / nil (can't say: keep what is shown).
function Displays.Visible(def, inputs, secretTest)
    local cond = VISIBILITY[def.visibility or "always"]
    if cond == nil then return true end
    return Conditions.Evaluate(cond, inputs, secretTest).state
end

-- Displays.EngineThreshold(state) -> seconds, color when the state is "remaining < X" (or <=)
-- with only a color in its look: the one shape the engine can draw from a duration object.
function Displays.EngineThreshold(state)
    local w = state and state.when
    if type(w) ~= "table" or w.op ~= nil or w.test ~= "remaining" then return nil end
    if (w.compare ~= "<" and w.compare ~= "<=") or type(w.value) ~= "number" then return nil end
    local look = state.look
    if type(look) ~= "table" or type(look.color) ~= "table" then return nil end
    for k in pairs(look) do if k ~= "color" then return nil end end
    return w.value, look.color
end

----------------------------------------------------------------------------------------------------
-- Reading the game
----------------------------------------------------------------------------------------------------

local function Snapshots(def)
    local src, snaps = def.source or {}, {}
    local now = GetTime()
    if src.kind == "spell" then
        snaps.cooldown = Sources.SpellCooldown(src.spell, now)
        snaps.charges = Sources.SpellCharges(src.spell)
        snaps.usable, snaps.noPower = Sources.SpellUsable(src.spell)
        snaps.inRange = Sources.SpellInRange(src.spell)
    elseif src.kind == "aura" then
        snaps.aura = Sources.Aura(src.unit or "player", src.spell, src.filter or "HELPFUL", now)
    elseif src.kind == "enchant" then
        snaps.enchant = Sources.WeaponEnchant(src.slot or 0)
    end
    if ns.CooldownManager and src.spell ~= nil then snaps.cdm = ns.CooldownManager.Snapshot(src.spell) end
    return snaps
end

local function Extra()
    return { combat = InCombatLockdown and InCombatLockdown() or false,
             hasTarget = UnitExists and UnitExists("target") or false }
end

local function SpellTexture(spell)
    if type(spell) == "table" then spell = spell.id or spell.name end
    if spell == nil or not C_Spell or not C_Spell.GetSpellTexture then return nil end
    local ok, tex = pcall(C_Spell.GetSpellTexture, spell)
    return ok and tex or nil
end

local function SpellName(spell)
    if type(spell) == "table" then return spell.name or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell.id)) end
    if type(spell) == "string" then return spell end
    return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell) or tostring(spell)
end

----------------------------------------------------------------------------------------------------
-- Color curves for engine-side thresholds (Grid2's technique, reported)
----------------------------------------------------------------------------------------------------

local function MakeColor(c)
    if CreateColor then return CreateColor(Looks.Color(c)) end
    local r, g, b, a = Looks.Color(c)
    return { r = r, g = g, b = b, a = a }
end

-- A linear curve with a near-vertical edge at `seconds` (EverAuras' 0.0001 rule): `low` below it,
-- `base` from it up. nil when the client has no color curves.
local function ThresholdCurve(seconds, low, base)
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end
    local ok, curve = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not curve then return nil end
    pcall(curve.SetType, curve, Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear or 0)
    pcall(curve.AddPoint, curve, 0, MakeColor(low))
    pcall(curve.AddPoint, curve, math.max(seconds - 0.0001, 0), MakeColor(low))
    pcall(curve.AddPoint, curve, seconds, MakeColor(base))
    pcall(curve.AddPoint, curve, seconds + 36000, MakeColor(base))
    return curve
end

-- The curve of the first engine-shaped threshold state, built once per display.
local function EngineCurve(entry, baseLook)
    if entry.curve ~= nil then return entry.curve or nil end
    entry.curve = false
    for _, state in ipairs(entry.def.states or {}) do
        local seconds, color = Displays.EngineThreshold(state)
        if seconds then
            entry.curve = ThresholdCurve(seconds, color, baseLook.color) or false
            break
        end
    end
    return entry.curve or nil
end

----------------------------------------------------------------------------------------------------
-- Applying a refresh to a widget
----------------------------------------------------------------------------------------------------

-- `feed` is true after a game event: only then are duration objects handed to the widgets, so a
-- running swipe or bar is never restarted by the 0.2 s tick that re-reads the states.
local function ApplyIcon(entry, snaps, inputs, look, feed)
    local f = entry.frame
    f:SetTextureID(SpellTexture(entry.def.source.spell))
    if feed then
        local duration, fresh
        if snaps.cooldown then duration = snaps.cooldown.duration
        elseif snaps.aura then duration = snaps.aura.duration; fresh = snaps.aura.auraInstanceID ~= entry.lastAura; entry.lastAura = snaps.aura.auraInstanceID end
        f:SetDuration(duration, fresh)
    end
    if snaps.cooldown and look.desaturateOnCooldown then
        f.icon:SetDesaturated(inputs.onCooldown and inputs.onCooldown.value == true)
    end
    f:SetStacks(snaps.aura and snaps.aura.stacks or (snaps.charges and snaps.charges.current))
    f:SetInRange(inputs.inRange and inputs.inRange.value)
end

local function ApplyBar(entry, snaps, inputs, look, baseLook, feed)
    local f = entry.frame
    local src = entry.def.source
    f:SetTextureID(SpellTexture(src.spell))
    f:SetName(entry.def.name or SpellName(src.spell))
    local duration = (snaps.cooldown and snaps.cooldown.duration) or (snaps.aura and snaps.aura.duration)
    if duration then
        if feed then f:SetDuration(duration); entry.duration = duration end
        local curve = EngineCurve(entry, baseLook)
        if curve and f:SetColorFromCurve(duration, curve) then return end
    else
        local rem = inputs.remaining and inputs.remaining.value
        f:SetPlainTime(rem, entry.total or rem)
    end
    f:SetColor(Looks.Color(look.color))
end

-- Refreshes one display: sources -> inputs -> states -> look -> widget. `feed` = after an event.
local function Refresh(entry, feed)
    local def = entry.def
    local snaps = Snapshots(def)
    local inputs = Displays.Inputs(def, snaps, Extra())
    local states, stateLooks, visible = Displays.Resolve(def, inputs, entry.lastStates)
    if ns.Actions then
        -- Look actions follow the active states; edge actions fire once on a false -> true change.
        local extra, shown = ns.Actions.Looks(def, states)
        for _, l in ipairs(extra) do stateLooks[#stateLooks + 1] = l end
        if shown ~= nil then visible = shown end
        ns.Actions.OnStates(entry, states)
    end
    entry.lastStates = {}
    for i, s in ipairs(states) do entry.lastStates[i] = s.active end
    entry.states, entry.inputs = states, inputs
    -- While an edit mode is open every display stays shown so it can be dragged.
    if visible ~= nil and not (ns.Groups and ns.Groups.IsEditing()) then entry.frame:SetShown(visible) end
    local baseLook = Looks.Merge(Looks.Default(def.type), def.look)
    local look = Looks.Resolve(def.type, def.look, stateLooks)
    entry.frame:SetLook(look)
    if def.type == "bar" then ApplyBar(entry, snaps, inputs, look, baseLook, feed) else ApplyIcon(entry, snaps, inputs, look, feed) end
end

----------------------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------------------

function Displays.Get(id) return live[id] end
function Displays.Order() return order end

-- Displays.Build(def): creates (or re-creates) the widget of one definition.
function Displays.Build(def)
    if type(def) ~= "table" or not def.id then return nil end
    local old = live[def.id]
    if old and old.frame then old.frame:Hide() end
    local parent = ns.Groups and ns.Groups.Parent(def.group) or UIParent
    local frame = def.type == "bar" and Widgets.Bar(parent) or Widgets.Icon(parent)
    local entry = { def = def, frame = frame, lastStates = {} }
    live[def.id] = entry
    if not old then order[#order + 1] = def.id end
    if def.source and def.source.kind == "spell" then Sources.WatchRange(def.source.spell, true) end
    if ns.Groups then ns.Groups.Place(entry) end
    dirty = true
    return entry
end

-- Displays.Remove(id): hides and forgets a display (its definition stays where it was).
function Displays.Remove(id)
    local entry = live[id]
    if not entry then return end
    entry.frame:Hide()
    live[id] = nil
    for i, v in ipairs(order) do if v == id then table.remove(order, i) break end end
    if ns.Groups then ns.Groups.Layout(entry.def.group) end
end

-- Displays.RefreshAll(feed): feed = true re-feeds the duration objects (after an event; the
-- default), false only re-reads the states and looks (the tick).
function Displays.RefreshAll(feed)
    if feed == nil then feed = true end
    if ns.Actions then ns.Actions.Flush() end   -- the Cooldown Manager's edges queued by the hooks
    for _, id in ipairs(order) do
        local entry = live[id]
        if entry then Refresh(entry, feed) end
    end
    dirty = false
end

function Displays.MarkDirty() dirty = true end

-- Displays.Invalidate(id) -> true when the display is live: after an edit of its states or
-- actions, the engine curve is rebuilt and the state history starts over (the next refresh is a
-- first look: no edge action fires for what is already true).
function Displays.Invalidate(id)
    local entry = live[id]
    if not entry then return false end
    entry.curve, entry.lastStates = nil, {}
    dirty = true
    return true
end

local EVENTS = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USABLE", "PLAYER_TARGET_CHANGED",
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "SPELLS_CHANGED",
    "SPELL_RANGE_CHECK_UPDATE", "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED" }

-- Displays.Start(): builds every saved definition and starts listening. Called at PLAYER_LOGIN.
function Displays.Start()
    for id, def in pairs(ns.db.displays or {}) do
        def.id = def.id or id
        Displays.Build(def)
    end
    if ns.Groups then ns.Groups.LayoutAll() end
    local frame = CreateFrame("Frame")
    for _, event in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, event) end
    if frame.RegisterUnitEvent then pcall(frame.RegisterUnitEvent, frame, "UNIT_AURA", "player", "target") else pcall(frame.RegisterEvent, frame, "UNIT_AURA") end
    frame:SetScript("OnEvent", function() dirty = true end)
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if dirty then
            elapsed = 0
            Displays.RefreshAll(true)
        elseif elapsed >= TICK then
            elapsed = 0
            Displays.RefreshAll(false)
        end
    end)
    Displays.frame = frame
    if ns.CooldownManager then ns.CooldownManager.Start() end
    if ns.Actions then ns.Actions.Start() end
    Displays.RefreshAll()
end
