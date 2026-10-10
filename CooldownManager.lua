-- CooldownManager.lua: Blizzard's Cooldown Manager as an optional source of EDGES (way B). Its
-- untainted items see what our code can't in combat, and every item raises alerts on itself
-- (available, on cooldown, charge gained, aura applied / removed, pandemic) whether or not the
-- player set one. We post-hook those calls, once per item frame, and keep a per-spell state that
-- Displays.lua reads when a spell the player tracks there is one of ours.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
--
-- The hooking rules (forever-techniques/references/cooldown-manager.md): hooksecurefunc only, hook
-- per frame at OnAcquireItemFrame (plus one walk of the pool at start), state in a weak-keyed table
-- of ours (never a field on a Blizzard frame), re-resolve the spell on every acquire (pooled frames
-- move), tiny hook bodies, read identity from the item (its cooldownID is never secret; the live
-- spell ID may be). Checked in Blizzard_CooldownViewer/CooldownViewer.lua (build 70245): every
-- Trigger*Alert routes through CooldownViewerItemMixin:TriggerAlertEvent(event); buff items call
-- OnActiveStateChanged; cooldown items call OnSpellActivationOverlayGlowShowEvent / HideEvent.
local _, ns = ...

local CDM = {}
ns.CooldownManager = CDM

local isSecret = issecretvalue or function() return false end

local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }

-- Enum.CooldownViewerAlertEventType values (CooldownViewerConstantsDocumentation.lua) -> edge names.
CDM.EVENT_EDGES = { [1] = "available", [2] = "pandemic", [3] = "onCooldown", [4] = "chargeGained", [5] = "auraApplied", [6] = "auraRemoved" }

local items = setmetatable({}, { __mode = "k" })   -- item frame -> { cooldownID, spellID, keys = { ... } }
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

local function StateFor(keys)
    local state
    for _, k in ipairs(keys) do if states[k] then state = states[k] break end end
    state = state or {}
    for _, k in ipairs(keys) do states[k] = state end
    return state
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
    local Answer = ns.Sources.Answer
    local function one(v) if v == nil then return nil end return Answer(v, "B", "cdm-" .. tostring(state.lastEdge)) end
    return { active = one(state.active), ready = one(state.ready), onCooldown = one(state.onCooldown),
             pandemic = one(state.pandemic), glow = one(state.glow), lastEdge = state.lastEdge, at = state.at }
end

function CDM.Listen(fn) listeners[#listeners + 1] = fn end

local function Fire(item, edge)
    local info = items[item]
    if not info or not edge then return end
    local state = StateFor(info.keys)
    CDM.Transition(state, edge)
    state.at = GetTime and GetTime() or 0
    if ns.Displays then ns.Displays.MarkDirty() end
    for _, fn in ipairs(listeners) do pcall(fn, info.spellID, edge, state) end
end

----------------------------------------------------------------------------------------------------
-- Hooking
----------------------------------------------------------------------------------------------------

local function NameOf(id)
    if not C_Spell or not C_Spell.GetSpellName then return nil end
    local ok, name = pcall(C_Spell.GetSpellName, id)
    return ok and name or nil
end

-- Resolves which cooldown an item shows right now (pooled frames move): its cooldownID, then the
-- configured spell and linked spells from C_CooldownViewer.
local function Resolve(item)
    local ok, cooldownID = pcall(item.GetCooldownID, item)
    if not ok or cooldownID == nil or isSecret(cooldownID) then return nil end
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

local hooked = setmetatable({}, { __mode = "k" })

local function HookItem(item)
    if type(item) ~= "table" or hooked[item] then
        if item then Resolve(item) end
        return
    end
    hooked[item] = true
    Resolve(item)
    local hs = hooksecurefunc
    if type(item.TriggerAlertEvent) == "function" then
        hs(item, "TriggerAlertEvent", function(self, event) Fire(self, CDM.EdgeName(event)) end)
    end
    if type(item.OnActiveStateChanged) == "function" then
        hs(item, "OnActiveStateChanged", function(self)
            Resolve(self)
            local ok, active = pcall(self.IsActive, self)
            if ok and not isSecret(active) then Fire(self, active and "active" or "inactive") end
        end)
    end
    if type(item.OnSpellActivationOverlayGlowShowEvent) == "function" then
        hs(item, "OnSpellActivationOverlayGlowShowEvent", function(self) Fire(self, "glowShown") end)
        hs(item, "OnSpellActivationOverlayGlowHideEvent", function(self) Fire(self, "glowHidden") end)
    end
end

local function HookViewer(viewer)
    if type(viewer) ~= "table" then return false end
    if type(viewer.OnAcquireItemFrame) == "function" then
        hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, item) HookItem(item) end)
    end
    local pool = viewer.itemFramePool
    if pool and pool.EnumerateActive then
        local ok, iter, a, b = pcall(pool.EnumerateActive, pool)
        if ok and type(iter) == "function" then
            for item in iter, a, b do HookItem(item) end
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
-- yet (the Blizzard addon loading later) is picked up on the next call, one hook per viewer.
function CDM.Start()
    if type(hooksecurefunc) ~= "function" then return 0 end
    local count = 0
    for _, name in ipairs(VIEWERS) do
        if not hookedViewers[name] and HookViewer(_G[name]) then
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
end
