-- Editor.lua: the minimal editor's logic. Condition trees as sentences, how a state was decided
-- (the evaluator's way letter and visual-only flag from the last evaluation), a small set of
-- ready-made conditions to add a state from, and the editing operations on a definition. The
-- honesty rule of the spec: a state whose last evaluation was visual-only (a hidden value) can
-- only be given look actions (glow, color, show, hide), never a sound or a message.
-- No free-form tree editing yet. The window is in EditorWindow.lua. Pure parts tested headless.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
local _, ns = ...
local L = ns.L

local Editor = {}
ns.Editor = Editor

----------------------------------------------------------------------------------------------------
-- Sentences
----------------------------------------------------------------------------------------------------

Editor.TEST_LABELS = {
    ready = L["ready"], onCooldown = L["on cooldown"], remaining = L["remaining"], enabled = L["enabled"],
    charges = L["charges"], maxCharges = L["max charges"], usable = L["usable"], noPower = L["no power"],
    inRange = L["in range"], present = L["present"], missing = L["missing"], stacks = L["stacks"],
    combat = L["in combat"], hasTarget = L["has a target"],
    cdmActive = L["active (Cooldown Manager)"], cdmReady = L["ready (Cooldown Manager)"],
    cdmOnCooldown = L["on cooldown (Cooldown Manager)"], cdmPandemic = L["pandemic (Cooldown Manager)"],
    cdmGlow = L["glowing (Cooldown Manager)"],
}
Editor.KIND_LABELS = {
    glow = L["glow"], color = L["color"], show = L["show"], hide = L["hide"], sound = L["sound"],
    speak = L["speak"], message = L["screen message"], chat = L["chat line"],
}

local function LeafSentence(cond)
    local label = Editor.TEST_LABELS[cond.test] or tostring(cond.test)
    local op, value = cond.compare, cond.value
    if op == nil and value == nil then return label end
    op = op or "=="
    if (op == "==" and value == true) or (op == "~=" and value == false) then return label end
    if (op == "==" and value == false) or (op == "~=" and value == true) then return L["not"] .. " " .. label end
    return label .. " " .. op .. " " .. tostring(value)
end

-- Editor.Sentence(cond) -> the condition tree as one sentence: "ready", "remaining < 5",
-- "not present", "ready and (stacks >= 3 or in combat)".
local function Sentence(cond, nested)
    if type(cond) ~= "table" then return "?" end
    if cond.op == nil then return LeafSentence(cond) end
    if cond.op == "not" then
        local child = cond.condition or (cond.conditions and cond.conditions[1])
        return L["not"] .. " " .. Sentence(child, true)
    end
    local parts = {}
    for i, child in ipairs(cond.conditions or {}) do parts[i] = Sentence(child, true) end
    local joined = table.concat(parts, " " .. (cond.op == "and" and L["and"] or L["or"]) .. " ")
    if nested and #parts > 1 then return "(" .. joined .. ")" end
    return joined
end
Editor.Sentence = Sentence

-- Editor.Decided(liveState) -> how the last evaluation decided this state (a live state entry
-- of Displays: { active, visualOnly, result }), as a sentence.
function Editor.Decided(s)
    local r = s and s.result
    if not r then return L["not evaluated yet"] end
    if r.visualOnly then return string.format(L["visual only here (way %s)"], tostring(r.way or "D")) end
    if r.state == nil then return string.format(L["can't say now (way %s, %s)"], tostring(r.way or "?"), tostring(r.reason)) end
    return string.format(L["decided by Lua (way %s)"], tostring(r.way or "A"))
end

-- Editor.MayHide(cond) -> true when the tree compares a number the game hides in combat.
local HIDES = { remaining = true, stacks = true, charges = true }
function Editor.MayHide(cond)
    if type(cond) ~= "table" then return false end
    if cond.op == nil then return HIDES[cond.test] == true end
    for _, child in ipairs(cond.conditions or { cond.condition }) do
        if Editor.MayHide(child) then return true end
    end
    return false
end

-- Editor.SourceSentence(source) -> "spell Frost Nova", "aura Clearcasting on player"...
function Editor.SourceSentence(src)
    if type(src) ~= "table" then return "?" end
    local spell = src.spell
    if type(spell) == "table" then spell = spell.name or spell.id end
    if src.kind == "aura" then return string.format(L["aura %s on %s"], tostring(spell), tostring(src.unit or "player")) end
    if src.kind == "enchant" then return string.format(L["weapon enchant, slot %s"], tostring(src.slot or 0)) end
    return string.format(L["spell %s"], tostring(spell))
end

-- Editor.DescribeAction(action) -> "sound 8960", "chat line \"...\"", "glow".
function Editor.DescribeAction(a)
    local kind = a["do"]
    local label = Editor.KIND_LABELS[kind] or tostring(kind)
    if kind == "sound" then return label .. " " .. tostring(a.file or a.sound) end
    if a.text then return label .. ' "' .. tostring(a.text) .. '"' end
    return label
end

----------------------------------------------------------------------------------------------------
-- Ready-made conditions
----------------------------------------------------------------------------------------------------

Editor.READY_MADE = {
    { key = "ready", test = "ready" },
    { key = "onCooldown", test = "onCooldown" },
    { key = "remaining", test = "remaining", compare = "<", needsValue = true, default = 5 },
    { key = "present", test = "present" },
    { key = "missing", test = "missing" },
    { key = "stacks", test = "stacks", compare = ">=", needsValue = true, default = 2 },
    { key = "inRange", test = "inRange" },
    { key = "combat", test = "combat" },
}

-- Editor.MakeState(key, value, color) -> a state definition { name, when, look }, or nil, problem.
-- The leaf carries no `way`: the input's own way (A, B, E...) shows through in the evaluation.
function Editor.MakeState(key, value, color)
    local ready
    for _, r in ipairs(Editor.READY_MADE) do if r.key == key then ready = r end end
    if not ready then return nil, "unknown-condition" end
    local when, name
    if ready.needsValue then
        if type(value) ~= "number" then return nil, "needs-value" end
        when = { test = ready.test, compare = ready.compare, value = value }
        name = ready.key .. ready.compare .. tostring(value)
    else
        when = { test = ready.test, compare = "==", value = true }
        name = ready.key
    end
    return { name = name, when = when, look = color and { color = color } or {} }
end

----------------------------------------------------------------------------------------------------
-- Editing a definition
----------------------------------------------------------------------------------------------------

local function Def(id)
    return ns.db and ns.db.displays and ns.db.displays[id]
end

-- A live display is invalidated; one that isn't built yet is built, out of combat only (Build
-- reaches Blizzard's Edit Mode through LibEditMode).
local function Changed(id)
    local def = Def(id)
    if ns.Displays and def and not ns.Displays.Invalidate(id) then
        if not (InCombatLockdown and InCombatLockdown()) then ns.Displays.Build(def) end
    end
    if Editor.Refresh then Editor.Refresh() end
end

-- Editor.Hidden(id, stateName) -> true when the state's last evaluation was visual-only.
function Editor.Hidden(id, name)
    local entry = ns.Displays and ns.Displays.Get(id)
    if not entry or not entry.states then return false end
    for i, state in ipairs(entry.def.states or {}) do
        if state.name == name then
            local s = entry.states[i]
            return s ~= nil and s.visualOnly == true
        end
    end
    return false
end

-- Editor.ActionKinds(id, stateName) -> the kinds the honesty rule allows on this state now.
function Editor.ActionKinds(id, name)
    local kinds, hidden = {}, Editor.Hidden(id, name)
    for _, kind in ipairs(ns.Actions.KINDS) do
        if not hidden or ns.Actions.IsLook(kind) then kinds[#kinds + 1] = kind end
    end
    return kinds
end

-- Editor.AddState(id, key, value, color) -> true, or false, problem.
function Editor.AddState(id, key, value, color)
    local def = Def(id)
    if not def then return false, "no-display" end
    local state, problem = Editor.MakeState(key, value, color)
    if not state then return false, problem end
    def.states = def.states or {}
    for _, s in ipairs(def.states) do if s.name == state.name then return false, "duplicate" end end
    def.states[#def.states + 1] = state
    Changed(id)
    return true
end

-- Editor.RemoveState(id, stateName) -> true when removed, with the actions on it.
function Editor.RemoveState(id, name)
    local def = Def(id)
    if not def then return false, "no-display" end
    local states, actions, removed = {}, {}, false
    for _, s in ipairs(def.states or {}) do
        if s.name == name then removed = true else states[#states + 1] = s end
    end
    for _, a in ipairs(def.actions or {}) do if a.on ~= name then actions[#actions + 1] = a end end
    def.states, def.actions = states, actions
    if removed then Changed(id) end
    return removed
end

-- Editor.AddAction(id, stateName, kind, params) -> true, or false, problem ("look-only" when the
-- honesty rule refuses a sound or a message on a hidden-value state).
function Editor.AddAction(id, name, kind, params)
    local def = Def(id)
    if not def then return false, "no-display" end
    if Editor.Hidden(id, name) and not ns.Actions.IsLook(kind) then return false, "look-only" end
    local action = { on = name, ["do"] = kind }
    for k, v in pairs(params or {}) do action[k] = v end
    local ok, problem = ns.Actions.Validate(action, def)
    if not ok then return false, problem end
    def.actions = def.actions or {}
    def.actions[#def.actions + 1] = action
    Changed(id)
    return true
end

-- Editor.RemoveAction(id, index) -> true when removed.
function Editor.RemoveAction(id, index)
    local def = Def(id)
    if not def or not def.actions or not def.actions[index] then return false end
    table.remove(def.actions, index)
    Changed(id)
    return true
end

-- Editor.SetStateColor(id, stateName, color) -> true: the color the state adds to the look.
function Editor.SetStateColor(id, name, color)
    local def = Def(id)
    if not def then return false end
    for _, s in ipairs(def.states or {}) do
        if s.name == name then
            s.look = s.look or {}
            s.look.color = color
            Changed(id)
            return true
        end
    end
    return false
end
