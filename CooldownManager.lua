-- CooldownManager.lua: Blizzard's Cooldown Manager as an optional source of EDGES (way B). Its
-- untainted items see what our code can't in combat, and they raise alerts on themselves (on
-- cooldown, aura applied / removed, pandemic; available and charge gained only when the player set
-- an alert). We post-hook those calls, once per item frame, and keep a per-spell state that
-- Displays.lua reads when a spell the player tracks there is one of ours.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
--
-- The hooking rules (forever-techniques/references/cooldown-manager.md): hooksecurefunc only, hook
-- per frame at OnAcquireItemFrame (plus one walk of the pool at start), state in a weak-keyed table
-- of ours (never a field on a Blizzard frame), re-resolve the spell whenever the item is bound
-- (pooled frames move), tiny hook bodies that can't throw into Blizzard's loops, read identity and
-- state from the item (its cooldownID is never secret; the live spell ID may be).
-- Checked in Blizzard_CooldownViewer (build 70245), reviewed 2026-10-10 (spec criterion 8):
-- - a pooled frame is ACQUIRED before it gets its cooldownID (RefreshLayout, then RefreshData ->
--   SetCooldownID -> OnCooldownIDSet), and ResetCooldownData clears it on release: the binding is
--   made at OnCooldownIDSet and dropped at ResetCooldownData, never trusted across a release;
-- - CooldownViewerItemMixin:ShouldBeActive is "has a cooldownID": a cooldown item is active as
--   soon as it is bound; only a buff item's active state follows its aura (the Buff mixin);
-- - the viewer sends every item every SPELL_ACTIVATION_OVERLAY_GLOW_SHOW / HIDE and the item
--   returns early unless the spell is its own: a post-hook has to check the spell itself;
-- - TriggerAvailableAlert and TriggerChargeGainedAlert run from the item's OnUpdate, registered
--   only with a player-set alert (NeedsOnUpdateRegistration): the never-secret isActive of the
--   spell's cooldown ends an on-cooldown state instead.
local _, ns = ...

local CDM = {}
ns.CooldownManager = CDM

local isSecret = issecretvalue or function() return false end

-- The four viewers and what their items' active state means.
local VIEWERS = {
    { "EssentialCooldownViewer", "cooldown" }, { "UtilityCooldownViewer", "cooldown" },
    { "BuffIconCooldownViewer", "buff" }, { "BuffBarCooldownViewer", "buff" },
}

-- Enum.CooldownViewerAlertEventType -> edge names, from the client's enum when it has one; the
-- literal values are build 70245's (CooldownViewerConstantsDocumentation.lua), for the headless tests.
local EDGE_OF_EVENT = { Available = "available", PandemicTime = "pandemic", OnCooldown = "onCooldown",
    ChargeGained = "chargeGained", OnAuraApplied = "auraApplied", OnAuraRemoved = "auraRemoved" }
local LITERAL_EDGES = { [1] = "available", [2] = "pandemic", [3] = "onCooldown", [4] = "chargeGained", [5] = "auraApplied", [6] = "auraRemoved" }

local function EventEdges()
    local E = Enum and Enum.CooldownViewerAlertEventType
    if type(E) ~= "table" then return LITERAL_EDGES end
    local edges = {}
    for name, edge in pairs(EDGE_OF_EVENT) do
        if type(E[name]) == "number" then edges[E[name]] = edge end
    end
    return next(edges) and edges or LITERAL_EDGES
end
CDM.EVENT_EDGES = EventEdges()

-- Edges that state a level: repeating one without a change in between is not a new edge.
local LEVEL_EDGES = { active = true, inactive = true, glowShown = true, glowHidden = true }

local items = setmetatable({}, { __mode = "k" })   -- item frame -> { cooldownID, spellID, keys = { ... } }
local hooked = setmetatable({}, { __mode = "k" })  -- item frame -> "cooldown" | "buff" once its hooks are in
local states = {}        -- key (spell ID or lowercase name) -> state table (shared between keys)
local listeners = {}     -- fn(spellID, edge, state)
local hookedViewers = {} -- viewer global name -> true once its acquire hook is in

----------------------------------------------------------------------------------------------------
-- Pure parts (tested headless)
----------------------------------------------------------------------------------------------------

-- CDM.EdgeName(event) -> "available" ... or nil for an unknown alert event.
function CDM.EdgeName(event)
    if type(event) ~= "number" then return nil end
    return CDM.EVENT_EDGES[event]
end

-- CDM.Transition(state, edge) -> the same state table, updated by the edge: ready / onCooldown
-- from the cooldown edges, active / pandemic from the aura edges, glow from the proc glow events.
function CDM.Transition(state, edge)
    state.lastEdge = edge
    if edge == "available" then state.ready, state.onCooldown = true, false
    elseif edge == "onCooldown" then state.ready, state.onCooldown = false, true
    elseif edge == "auraApplied" or edge == "active" then state.active = true
    elseif edge == "auraRemoved" or edge == "inactive" then state.active, state.pandemic = false, false
    elseif edge == "pandemic" then state.pandemic = true
    elseif edge == "glowShown" then state.glow = true
    elseif edge == "glowHidden" then state.glow = false
    end
    return state
end

-- CDM.Forget(state, kind) -> the same state with what a RELEASED item of that kind knew set back
-- to unknown (the spec: never trusted across a release): a cooldown item owned ready / onCooldown /
-- glow, a buff item active / pandemic. A new edge fills them again.
function CDM.Forget(state, kind)
    if kind == "buff" then state.active, state.pandemic = nil, nil
    else state.ready, state.onCooldown, state.glow = nil, nil, nil end
    state.lastEdge = "released"
    return state
end

-- CDM.Keys(spellID, linkedSpellIDs, nameOf) -> the keys one tracked cooldown answers for: its spell
-- ID, its linked (aura) spell IDs, and their lowercase names (ranks share a name).
function CDM.Keys(spellID, linkedSpellIDs, nameOf)
    local keys, seen = {}, {}
    local function add(k)
        if k ~= nil and not isSecret(k) and not seen[k] then seen[k] = true; keys[#keys + 1] = k end
    end
    local function addSpell(id)
        add(id)
        local name = nameOf and id and not isSecret(id) and nameOf(id)
        if type(name) == "string" then add(name:lower()) end
    end
    addSpell(spellID)
    for _, id in ipairs(linkedSpellIDs or {}) do addSpell(id) end
    return keys
end

-- CDM.KeyOf(spell) -> the key a display's source spell looks up: a number, a lowercase name, or nil.
function CDM.KeyOf(spell)
    if type(spell) == "table" then return spell.id or (type(spell.name) == "string" and spell.name:lower()) end
    if type(spell) == "number" then return spell end
    if type(spell) == "string" then return spell:lower() end
    return nil
end

----------------------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------------------

local function ExistingState(keys)
    for _, k in ipairs(keys) do if states[k] then return states[k] end end
    return nil
end

local function StateFor(keys)
    local state = ExistingState(keys) or {}
    for _, k in ipairs(keys) do states[k] = state end
    return state
end

function CDM.Listen(fn) listeners[#listeners + 1] = fn end

-- One edge for a spell's state: transition, timestamp, the displays told, the listeners called.
local function Edge(state, spellID, edge)
    if LEVEL_EDGES[edge] and state.lastEdge == edge then return end
    CDM.Transition(state, edge)
    state.at = GetTime and GetTime() or 0
    if ns.Displays then ns.Displays.MarkDirty() end
    for _, fn in ipairs(listeners) do pcall(fn, spellID, edge, state) end
end

-- The "available" alert needs a player-set alert (see the header): when the state says on
-- cooldown and the never-secret isActive says the cooldown is over (and not on hold), that is our
-- own "available" edge, listeners included.
local function ReconcileReady(state)
    if state.onCooldown ~= true or state.spellID == nil then return end
    if not C_Spell or not C_Spell.GetSpellCooldown then return end
    local ok, info = pcall(C_Spell.GetSpellCooldown, state.spellID)
    if ok and type(info) == "table" and info.isActive == false and info.isEnabled ~= false then
        Edge(state, state.spellID, "available")
    end
end

-- CDM.Snapshot(spell) -> answers (way B) for a tracked spell, or nil when the Cooldown Manager
-- doesn't track it: active, ready, onCooldown, pandemic, glow (each nil until an edge said so).
function CDM.Snapshot(spell)
    local key = CDM.KeyOf(spell)
    local state = key and states[key]
    if not state then
        if type(spell) == "table" and spell.name then state = states[spell.name:lower()] end
        if not state then return nil end
    end
    ReconcileReady(state)
    local Answer = ns.Sources.Answer
    local function one(v) if v == nil then return nil end return Answer(v, "B", "cdm-" .. tostring(state.lastEdge)) end
    return { active = one(state.active), ready = one(state.ready), onCooldown = one(state.onCooldown),
             pandemic = one(state.pandemic), glow = one(state.glow), lastEdge = state.lastEdge, at = state.at }
end

----------------------------------------------------------------------------------------------------
-- Binding an item frame to the spell it shows
----------------------------------------------------------------------------------------------------

local function NameOf(id)
    if not C_Spell or not C_Spell.GetSpellName then return nil end
    local ok, name = pcall(C_Spell.GetSpellName, id)
    return ok and name or nil
end

-- Resolve(item) -> the item's binding right now, or nil (and none kept) while it has no cooldownID:
-- its cooldownID, then the configured spell and linked spells from C_CooldownViewer.
local function Resolve(item)
    local ok, cooldownID = pcall(item.GetCooldownID, item)
    if not ok or isSecret(cooldownID) or cooldownID == nil then items[item] = nil; return nil end
    local info = items[item]
    if info and info.cooldownID == cooldownID then return info end
    local spellID, linked
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local okI, cd = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
        if okI and type(cd) == "table" then
            spellID = not isSecret(cd.spellID) and cd.spellID or nil
            linked = cd.linkedSpellIDs
        end
    end
    info = { cooldownID = cooldownID, spellID = spellID, keys = CDM.Keys(spellID, linked, NameOf) }
    items[item] = info
    return info
end

-- Fire(item, edge): the edge goes to the spell the item shows RIGHT NOW (pooled frames move).
local function Fire(item, edge)
    local info = edge and Resolve(item)
    if not info then return end
    local state = StateFor(info.keys)
    if info.spellID ~= nil then state.spellID = info.spellID end
    Edge(state, info.spellID, edge)
end

-- Released (ResetCooldownData: the pool's reset, or a cleared cooldownID): the frame's binding
-- goes, and what that item knew about its spell is unknown until a new edge.
local function Unbind(item)
    local info = items[item]
    items[item] = nil
    local state = info and ExistingState(info.keys)
    if state then CDM.Forget(state, hooked[item]) end
end

-- A buff item's active state is its aura's presence (CooldownViewerBuffItemMixin:ShouldBeActive):
-- read from the item, plain values only.
local function ReadActive(item)
    local ok, active = pcall(item.IsActive, item)
    if ok and not isSecret(active) and active ~= nil then Fire(item, active and "active" or "inactive") end
end

----------------------------------------------------------------------------------------------------
-- Hooking
----------------------------------------------------------------------------------------------------

-- Hook(item, method, fn) -> true when hooked: a post-hook whose body can't reach Blizzard's loop
-- (an error is kept in CDM.lastError for the probe instead of aborting the viewer's other items).
local function Hook(item, method, fn)
    if type(item[method]) ~= "function" then return false end
    hooksecurefunc(item, method, function(...)
        local ok, err = pcall(fn, ...)
        if not ok then CDM.lastError = err end
    end)
    return true
end

-- The glow events reach every item; only the item's own spell (or a linked one) is an edge.
local function OnGlow(edge)
    return function(self, spellID)
        if isSecret(spellID) or spellID == nil then return end
        local info = Resolve(self)
        if not info then return end
        for _, k in ipairs(info.keys) do
            if k == spellID then Fire(self, edge) return end
        end
    end
end

local function HookItem(item, kind)
    if type(item) ~= "table" then return end
    if hooked[item] then Resolve(item) return end
    hooked[item] = kind
    Resolve(item)
    Hook(item, "TriggerAlertEvent", function(self, event) Fire(self, CDM.EdgeName(event)) end)
    Hook(item, "OnCooldownIDSet", function(self)
        Resolve(self)
        if kind == "buff" then ReadActive(self) end
    end)
    Hook(item, "ResetCooldownData", Unbind)
    Hook(item, "OnSpellActivationOverlayGlowShowEvent", OnGlow("glowShown"))
    Hook(item, "OnSpellActivationOverlayGlowHideEvent", OnGlow("glowHidden"))
    if kind == "buff" then
        Hook(item, "OnActiveStateChanged", ReadActive)
        ReadActive(item)
    end
end

local function HookViewer(viewer, kind)
    if type(viewer) ~= "table" then return false end
    if type(viewer.OnAcquireItemFrame) == "function" then
        hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, item)
            local ok, err = pcall(HookItem, item, kind)
            if not ok then CDM.lastError = err end
        end)
    end
    local pool = viewer.itemFramePool
    if pool and pool.EnumerateActive then
        local ok, iter, a, b = pcall(pool.EnumerateActive, pool)
        if ok and type(iter) == "function" then
            for item in iter, a, b do HookItem(item, kind) end
        end
    end
    return true
end

-- CDM.Available() -> true when Blizzard's Cooldown Manager is on for this character.
function CDM.Available()
    if not C_CooldownViewer or not C_CooldownViewer.IsCooldownViewerAvailable then return false end
    local ok, available = pcall(C_CooldownViewer.IsCooldownViewerAvailable)
    return ok and available == true
end

-- CDM.Start() -> number of viewers newly hooked. Safe to call again: a viewer that wasn't there
-- yet is picked up on the next call, one hook per viewer.
function CDM.Start()
    if type(hooksecurefunc) ~= "function" then return 0 end
    local count = 0
    for _, viewer in ipairs(VIEWERS) do
        local name, kind = viewer[1], viewer[2]
        if not hookedViewers[name] and HookViewer(_G[name], kind) then
            hookedViewers[name] = true
            count = count + 1
        end
    end
    return count
end

-- CDM.Tracked() -> a sorted list of { key, state } for /context probe and the editor.
function CDM.Tracked()
    local list = {}
    for key, state in pairs(states) do
        if type(key) == "number" then list[#list + 1] = { key = key, state = state } end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

function CDM.Reset()
    for k in pairs(states) do states[k] = nil end
    CDM.lastError = nil
end
