-- Actions.lua: what a display DOES when one of its states changes. Two families:
--   look actions   glow | color | show | hide: held while the state holds. A visual-only state
--                  (the engine, or the last Lua-decided value, draws it) may have them.
--   edge actions   sound | speak | message | chat: fired ONCE when a state goes false -> true, and
--                  only when the evaluator decided it in Lua (Conditions.CanFireActions): a hidden
--                  value never makes a sound, never posts a line. Never again on a refresh.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
--
-- A definition's `actions` list (the spec's Contract): { on = <state name> | "cdm:<edge>", do = <kind>, ... }
--   sound    sound = a sound kit ID (number: PlaySound) or a LibSharedMedia sound name / file path
--            (string: PlaySoundFile, looked up in the library when it is loaded); file = a file
--            path or FileDataID for PlaySoundFile; channel = "Master" | "SFX" | ... (optional)
--   speak    text: C_CombatAudioAlert.SpeakText(text, category, allowOverlap) when the game's
--            combat audio alerts are on, else C_VoiceChat.SpeakText with the TTS settings
--   message  text, color = { r, g, b }, where = "errors" (UIErrorsFrame, default) | "raid"
--            (RaidWarningFrame), duration (raid only)
--   chat     text: the player's own chat frame, never a channel (solo-safe, lockdown-safe)
--   color    color = { r, g, b, a }      glow, show, hide: no parameter
-- A text takes {name} (the display's name) and {state}.
-- "cdm:<edge>" listens to Blizzard's Cooldown Manager for the display's source spell (edges of
-- CooldownManager.lua: available, onCooldown, chargeGained, auraApplied, auraRemoved, pandemic,
-- active, inactive, glowShown, glowHidden): way B, Lua-decided, so edge actions may fire on them,
-- in combat too. The hook only queues; the display engine's refresh fires (Flush).
-- Nothing here touches a protected frame: show / hide act on our own widgets, the messages go to
-- Blizzard's unprotected message frames.
--
-- Checked in Blizzard's Forever source (build 70245): C_CombatAudioAlert.SpeakText(text,
-- CombatAudioAlertCategory, allowOverlap) and IsEnabled(); C_VoiceChat.SpeakText(voiceID, text,
-- rate, volume, overlap); C_TTSSettings.GetVoiceOptionID / GetSpeechRate / GetSpeechVolume;
-- PlaySound(soundKitID, ...); UIErrorsFrame:AddMessage(text, r, g, b, a) (SimpleMessageFrameAPI);
-- RaidWarningFrame:AddMessage(text, colorInfo, displayTime) (Blizzard_RaidWarning). PlaySoundFile
-- is in neither the generated docs nor Blizzard's code: called only when it exists, under pcall.
local _, ns = ...
local Conditions = ns.Conditions

local Actions = {}
ns.Actions = Actions

Actions.KINDS = { "glow", "color", "show", "hide", "sound", "speak", "message", "chat" }
Actions.LOOK = { glow = true, color = true, show = true, hide = true }
local VALID = {}
for _, kind in ipairs(Actions.KINDS) do VALID[kind] = true end

----------------------------------------------------------------------------------------------------
-- Pure parts (tested headless)
----------------------------------------------------------------------------------------------------

function Actions.IsLook(kind) return Actions.LOOK[kind] == true end

-- Actions.Allowed(kind, result) -> true when an action of this kind may act on a state whose
-- evaluation gave `result`: a look always may (even visual-only); the others need Lua's decision.
function Actions.Allowed(kind, result)
    if Actions.IsLook(kind) then return true end
    return Conditions.CanFireActions(result)
end

-- Actions.CdmEdgeOf(on) -> the Cooldown Manager edge name when `on` is "cdm:<edge>", else nil.
function Actions.CdmEdgeOf(on)
    if type(on) ~= "string" then return nil end
    return on:match("^cdm:(%w+)$")
end

-- Actions.Validate(action[, def]) -> ok, problem. With a definition, `on` must name one of its
-- states (or a Cooldown Manager edge).
function Actions.Validate(action, def)
    if type(action) ~= "table" then return false, "no-action" end
    local kind = action["do"]
    if not VALID[kind] then return false, "bad-kind" end
    if type(action.on) ~= "string" or action.on == "" then return false, "no-state" end
    if def and not Actions.CdmEdgeOf(action.on) then
        local found = false
        for _, state in ipairs(def.states or {}) do if state.name == action.on then found = true end end
        if not found then return false, "unknown-state" end
    end
    if kind == "sound" and action.sound == nil and action.file == nil then return false, "needs-sound" end
    if (kind == "speak" or kind == "message" or kind == "chat") and type(action.text) ~= "string" then return false, "needs-text" end
    if kind == "color" and type(action.color) ~= "table" then return false, "needs-color" end
    return true
end

-- Actions.Looks(def, states) -> extra looks (a list, in action order), shown (true / false / nil):
-- the look actions of every state active now. A visual-only state counts: looks may follow it.
function Actions.Looks(def, states)
    local looks, shown = {}, nil
    local index = {}
    for i, state in ipairs(def.states or {}) do if state.name then index[state.name] = i end end
    for _, action in ipairs(def.actions or {}) do
        local i = index[action.on]
        local s = i and states and states[i]
        if s and s.active then
            local kind = action["do"]
            if kind == "glow" then looks[#looks + 1] = { glow = true }
            elseif kind == "color" then looks[#looks + 1] = { color = action.color }
            elseif kind == "show" then shown = true
            elseif kind == "hide" then shown = false end
        end
    end
    return looks, shown
end

-- Actions.Edges(def, prev, states) -> the edge actions to fire now: those on a state active now
-- that was inactive at the previous refresh (`prev[i] == false`: the first look is not a change)
-- and whose evaluation Lua decided (never a kept last value, never a hidden one).
function Actions.Edges(def, prev, states)
    local fire = {}
    prev = prev or {}
    for i, s in ipairs(states or {}) do
        local state = def.states and def.states[i]
        if state and s.active and prev[i] == false and Conditions.CanFireActions(s.result) then
            for _, action in ipairs(def.actions or {}) do
                if action.on == state.name and not Actions.IsLook(action["do"]) then
                    fire[#fire + 1] = { action = action, state = state.name }
                end
            end
        end
    end
    return fire
end

-- Actions.MatchesSpell(spell, spellID, nameOf) -> true when a display's source spell (an ID, a
-- name or { id, name }) is the spell a Cooldown Manager edge concerns. A secret (nil) ID: never.
function Actions.MatchesSpell(spell, spellID, nameOf)
    if spellID == nil then return false end
    local id, name
    if type(spell) == "table" then id, name = spell.id, spell.name
    elseif type(spell) == "number" then id = spell
    elseif type(spell) == "string" then name = spell end
    if id ~= nil and id == spellID then return true end
    if type(name) == "string" and nameOf then
        local n = nameOf(spellID)
        return type(n) == "string" and n:lower() == name:lower()
    end
    return false
end

-- Actions.CdmEdges(def, spellID, edge, nameOf) -> the edge actions of a display that listen for
-- this Cooldown Manager edge on its source spell.
function Actions.CdmEdges(def, spellID, edge, nameOf)
    local fire = {}
    local src = def.source
    if not src or src.spell == nil or not Actions.MatchesSpell(src.spell, spellID, nameOf) then return fire end
    for _, action in ipairs(def.actions or {}) do
        if Actions.CdmEdgeOf(action.on) == edge and not Actions.IsLook(action["do"]) then
            fire[#fire + 1] = { action = action, state = action.on }
        end
    end
    return fire
end

-- Actions.Format(text, ctx) -> the text with {name} and {state} filled from ctx.
function Actions.Format(text, ctx)
    ctx = ctx or {}
    return (tostring(text or ""):gsub("{(%a+)}", function(key) return tostring(ctx[key] or "") end))
end

-- Actions.ResolveSound(action, fetch) -> "kit", id | "file", path | nil. `fetch(name)` is the
-- LibSharedMedia lookup (nil when the library isn't there or doesn't know the name).
function Actions.ResolveSound(action, fetch)
    if action.file ~= nil then return "file", action.file end
    local sound = action.sound
    if type(sound) == "number" then return "kit", sound end
    if type(sound) == "string" and sound ~= "" then return "file", (fetch and fetch(sound)) or sound end
    return nil
end

----------------------------------------------------------------------------------------------------
-- Doing it in the game
----------------------------------------------------------------------------------------------------

local function Try(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function LSMFetch(name)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return nil end
    local ok, path = pcall(LSM.Fetch, LSM, "sound", name, true)
    return ok and path or nil
end

local function Sound(action)
    local how, what = Actions.ResolveSound(action, LSMFetch)
    if how == "kit" then return (Try(PlaySound, what, action.channel)) end
    if how == "file" then return (Try(PlaySoundFile, what, action.channel)) end
    return false
end

-- The game's combat audio alerts when the player has them on, else the chat text-to-speech.
local function Speak(text)
    local alerts = C_CombatAudioAlert
    if alerts and alerts.SpeakText and alerts.IsEnabled then
        local okE, enabled = Try(alerts.IsEnabled)
        if okE and enabled == true then
            local E = Enum and Enum.CombatAudioAlertCategory
            return (Try(alerts.SpeakText, text, E and E.General or 0, true))
        end
    end
    local voice, tts = C_VoiceChat, C_TTSSettings
    if not voice or not voice.SpeakText or not tts then return false end
    local kind = Enum and Enum.TtsVoiceType and Enum.TtsVoiceType.Standard or 0
    local okV, voiceID = Try(tts.GetVoiceOptionID, kind)
    local okR, rate = Try(tts.GetSpeechRate)
    local okVol, volume = Try(tts.GetSpeechVolume)
    return (Try(voice.SpeakText, okV and voiceID or 0, text, okR and rate or 0, okVol and volume or 100, true))
end

local function Message(action, text)
    local c = action.color or { 1, 0.82, 0, 1 }
    if action.where == "raid" and RaidWarningFrame and RaidWarningFrame.AddMessage then
        return (Try(RaidWarningFrame.AddMessage, RaidWarningFrame, text, { r = c[1], g = c[2], b = c[3] }, action.duration))
    end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        return (Try(UIErrorsFrame.AddMessage, UIErrorsFrame, text, c[1], c[2], c[3], c[4] or 1))
    end
    return false
end

-- Actions.Fire(action, ctx) -> true when the edge action ran. ctx = { name, state }. Look actions
-- are not fired: Looks() applies them with the state's look.
function Actions.Fire(action, ctx)
    local kind = action["do"]
    local text = Actions.Format(action.text, ctx)
    if kind == "sound" then return Sound(action) end
    if kind == "speak" then return Speak(text) end
    if kind == "message" then return Message(action, text) end
    if kind == "chat" then ns:Print(text); return true end
    return false
end

local function DisplayName(def)
    if def.name then return def.name end
    local spell = def.source and def.source.spell
    if type(spell) == "table" then return spell.name or tostring(spell.id) end
    if spell ~= nil then return tostring(spell) end
    return def.id
end

local function Context(entry, state)
    return { name = DisplayName(entry.def), state = state }
end

-- Actions.OnStates(entry, states) -> how many edge actions fired. Called by the display engine
-- on every refresh, before it records the states as the previous ones.
function Actions.OnStates(entry, states)
    local def = entry.def
    if not def.actions or #def.actions == 0 then return 0 end
    local count = 0
    for _, hit in ipairs(Actions.Edges(def, entry.lastStates, states)) do
        if Actions.Fire(hit.action, Context(entry, hit.state)) then count = count + 1 end
    end
    return count
end

----------------------------------------------------------------------------------------------------
-- The Cooldown Manager's edges: queued by the hook, fired by the refresh
----------------------------------------------------------------------------------------------------

local pending = {}
local listening = false

local function NameOf(id)
    if not C_Spell or not C_Spell.GetSpellName then return nil end
    local ok, name = pcall(C_Spell.GetSpellName, id)
    return ok and name or nil
end

-- Actions.Start() -> true the first time: listens to the Cooldown Manager's edges.
function Actions.Start()
    if listening or not ns.CooldownManager then return false end
    listening = true
    ns.CooldownManager.Listen(function(spellID, edge) pending[#pending + 1] = { spellID = spellID, edge = edge } end)
    return true
end

-- Actions.Flush() -> how many actions fired for the edges queued since the last flush.
function Actions.Flush()
    if #pending == 0 or not ns.Displays then return 0 end
    local queue = pending
    pending = {}
    local count = 0
    for _, e in ipairs(queue) do
        for _, id in ipairs(ns.Displays.Order()) do
            local entry = ns.Displays.Get(id)
            if entry and entry.def.actions then
                for _, hit in ipairs(Actions.CdmEdges(entry.def, e.spellID, e.edge, NameOf)) do
                    if Actions.Fire(hit.action, Context(entry, hit.state)) then count = count + 1 end
                end
            end
        end
    end
    return count
end
