-- Probe.lua: /context probe [spell]: prints what the sources answer for a spell's cooldown and for
-- the matching aura on you, with the way (A-E) each answer was decided. The first thing to try in
-- game before any display exists: out of combat, then in combat, then in a dungeon.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
local _, ns = ...
local L = ns.L

-- Phase 1 defaults: Frost Nova (cooldown) and Clearcasting (the Arcane Concentration proc).
local DEFAULT_SPELL = "Frost Nova"
local DEFAULT_AURA = "Clearcasting"

-- One printable line for an answer: the value when plain, else why there is none.
local function Describe(answer)
    if answer == nil then return L["not read"] end
    if answer.hidden then return string.format(L["hidden (way %s)"], answer.way or "D") end
    if answer.value == nil then
        return string.format(L["unknown (way %s, %s)"], answer.way or "?", tostring(answer.reason))
    end
    return string.format("%s (%s)", tostring(answer.value), answer.way or "?")
end

-- What Blizzard's Cooldown Manager said about the spell, when the player tracks it there.
local function PrintEdges(spell)
    local cdm = ns.CooldownManager
    if not cdm then return end
    if not cdm.Available() then
        ns:Print("  " .. L["Cooldown Manager: off"])
        return
    end
    local snap = cdm.Snapshot(spell)
    if not snap then
        ns:Print("  " .. L["Cooldown Manager: not tracked (no edge seen yet)"])
        return
    end
    ns:Printf("  " .. L["Cooldown Manager: last edge %s, active %s, ready %s, glow %s"],
        tostring(snap.lastEdge), Describe(snap.active), Describe(snap.ready), Describe(snap.glow))
end

local function PrintSpell(spell)
    local cd = ns.Sources.SpellCooldown(spell, GetTime())
    if cd == nil then
        ns:Printf(L["%s: unknown spell"], spell)
        return
    end
    ns:Printf("%s: " .. L["on cooldown"] .. " %s, " .. L["remaining"] .. " %s, " .. L["enabled"] .. " %s",
        spell, Describe(cd.onCooldown), Describe(cd.remaining), Describe(cd.enabled))
    if cd.duration ~= nil then
        local hasSecrets = cd.duration.HasSecretValues and cd.duration:HasSecretValues()
        ns:Printf("  " .. L["duration object: %s"], hasSecrets and L["carries hidden values"] or L["plain"])
    end
    local charges = ns.Sources.SpellCharges(spell)
    if charges ~= nil then
        ns:Printf("  " .. L["charges"] .. " %s / %s", Describe(charges.current), Describe(charges.max))
    end
    local usable, noPower = ns.Sources.SpellUsable(spell)
    ns:Printf("  " .. L["usable"] .. " %s, " .. L["no power"] .. " %s, " .. L["in range"] .. " %s",
        Describe(usable), Describe(noPower), Describe(ns.Sources.SpellInRange(spell)))
    PrintEdges(spell)
end

local function PrintAura(unit, spell)
    local aura = ns.Sources.Aura(unit, spell, "HELPFUL", GetTime())
    ns:Printf("%s " .. L["on %s"] .. ": " .. L["present"] .. " %s", tostring(spell), unit, Describe(aura.present))
    PrintEdges(spell)
    if aura.present and aura.present.value == true then
        ns:Printf("  " .. L["stacks"] .. " %s, " .. L["remaining"] .. " %s, " .. L["duration object: %s"],
            Describe(aura.stacks), Describe(aura.remaining), aura.duration and L["plain"] or L["not read"])
    end
end

-- ns.Probe(arg): `arg` is the rest of the slash line: a spell name, or nothing for the defaults.
function ns.Probe(arg)
    arg = (arg or ""):match("^%s*(.-)%s*$")
    local restricted = C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
    ns:Printf(L["auras restricted now: %s"], tostring(restricted == true))
    if arg ~= "" then
        PrintSpell(arg)
        PrintAura("player", arg)
    else
        PrintSpell(DEFAULT_SPELL)
        PrintAura("player", DEFAULT_AURA)
    end
    local enchant = ns.Sources.WeaponEnchant(Enum and Enum.WeaponSlot and Enum.WeaponSlot.MainHand or 0)
    ns:Printf(L["main hand enchant"] .. ": %s", Describe(enchant.present))
    -- Errors kept instead of thrown: a display's refresh (paused 5 s) and a Cooldown Manager hook body.
    if ns.Displays and ns.Displays.lastError then ns:Printf(L["last display error: %s"], tostring(ns.Displays.lastError)) end
    if ns.CooldownManager and ns.CooldownManager.lastError then ns:Printf(L["last hook error: %s"], tostring(ns.CooldownManager.lastError)) end
end
