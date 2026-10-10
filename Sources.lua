-- Sources.lua: what a display shows. Every read of the game answers in THREE values (true / false /
-- nil = can't say) tagged by the way it was decided (forever-techniques section 0):
--   A  a readable side channel (never-secret fields, plain values)
--   B  the event itself (a range update)
--   C  geometry and time (not used here yet)
--   D  the engine decides: the value is hidden, only a widget can draw it
--   E  asked first (a C_Secrets predicate) and told the value would be hidden here
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
--
-- An answer is { value = ..., way = "A".."E", hidden = bool, reason = token, secret = ... }:
-- `value` is plain or nil, never a secret; a hidden value is kept in `secret` for engine widgets
-- (SetAlphaFromBoolean and friends) and `hidden` is true. Reasons are code tokens for the editor.
--
-- Rules checked against Blizzard's Forever source (build 70245, Blizzard_APIDocumentationGenerated):
-- - C_Spell.GetSpellCooldown: isActive, isEnabled, isOnGCD are NeverSecret (isOnGCD only trusted
--   inside SPELL_UPDATE_COOLDOWN); startTime and duration are secret when cooldowns are restricted.
-- - C_Spell.GetSpellCharges: maxCharges and isActive NeverSecret; currentCharges may be secret.
-- - C_Spell.GetSpellCooldownDuration / GetSpellChargeDuration: duration objects, fed to widgets.
-- - C_UnitAuras.GetUnitAuraBySpellID: RequiresNonSecretAura, so ask C_Secrets.ShouldSpellAuraBeSecret
--   first; by name only while auras aren't restricted; an index read only after
--   C_Secrets.ShouldUnitAuraIndexBeSecret says plain (the refusal can't be caught with pcall).
-- - C_Item.GetWeaponEnchantInfo(slot): a list of { hasEnchant, timeLeft (ms), charges, enchantID }.
local _, ns = ...

local Sources = {}
ns.Sources = Sources

local isSecret = issecretvalue or function() return false end

local function Answer(value, way, reason)
    if isSecret(value) then
        return { value = nil, way = "D", hidden = true, reason = reason or "hidden", secret = value }
    end
    return { value = value, way = way, hidden = false, reason = reason }
end
Sources.Answer = Answer

local function Unknown(reason, way)
    return { value = nil, way = way or "A", hidden = false, reason = reason }
end

-- A value the engine may use but Lua never reads (way D).
local function Hidden(secret, reason)
    return { value = nil, way = "D", hidden = true, reason = reason or "hidden", secret = secret }
end

-- Asked first (way E) and told the value would be hidden here: not read at all. Still `hidden`, so
-- a condition on it goes visual-only and the display falls to its engine-driven form.
local function AskedHidden(reason)
    return { value = nil, way = "E", hidden = true, reason = reason or "asked-hidden" }
end

-- Plain subtraction with the clock, or nil when either side is hidden.
local function Remaining(expiration, now)
    if expiration == nil or isSecret(expiration) or isSecret(now) then return nil end
    local left = expiration - now
    if left < 0 then left = 0 end
    return left
end

----------------------------------------------------------------------------------------------------
-- Spell cooldowns
----------------------------------------------------------------------------------------------------

-- Asks whether this spell's cooldown numbers would be hidden right now (way E). nil = no predicate.
local function CooldownHidden(spell)
    local secrets = C_Secrets
    if secrets and secrets.ShouldSpellCooldownBeSecret then
        return secrets.ShouldSpellCooldownBeSecret(spell) == true
    end
    if secrets and secrets.ShouldCooldownsBeSecret then return secrets.ShouldCooldownsBeSecret() == true end
    return nil
end

-- Sources.SpellCooldown(spell[, now]) -> snapshot of a spell's cooldown, or nil for an unknown spell:
--   known      Answer(true, A)
--   onCooldown Answer(bool, A)   from the never-secret isActive
--   enabled    Answer(bool, A)   false while the cooldown is on hold
--   onGCD      Answer(bool, A)   nil outside SPELL_UPDATE_COOLDOWN (trust rule from the docs)
--   remaining  Answer(seconds, A) when the numbers are plain, else hidden (D) or asked-hidden (E)
--   duration   the LuaDurationObject for a Cooldown widget (way D), ignoring the GCD
function Sources.SpellCooldown(spell, now, inEvent)
    local api = C_Spell
    if not api or not api.GetSpellCooldown then return nil end
    local info = api.GetSpellCooldown(spell)
    if info == nil then return nil end
    local snap = { known = Answer(true, "A", "cooldown-info") }
    snap.onCooldown = Answer(info.isActive == true, "A", "isActive")
    snap.enabled = Answer(info.isEnabled ~= false, "A", "isEnabled")
    if inEvent and info.isOnGCD ~= nil then
        snap.onGCD = Answer(info.isOnGCD == true, "A", "isOnGCD")
    else
        snap.onGCD = Unknown("gcd-outside-event")
    end
    local hidden = CooldownHidden(spell)
    if hidden == true then
        snap.remaining = AskedHidden("asked-hidden")
    elseif not info.isActive then
        snap.remaining = Answer(0, "A", "not-active")
    elseif isSecret(info.startTime) or isSecret(info.duration) then
        snap.remaining = Hidden(info.duration, "hidden")
    else
        snap.remaining = Answer(Remaining(info.startTime + info.duration, now or GetTime()), "A", "computed")
    end
    if api.GetSpellCooldownDuration then snap.duration = api.GetSpellCooldownDuration(spell, true) end
    return snap
end

-- Sources.SpellCharges(spell) -> nil for a spell without charges, else:
--   max        Answer(n, A)      never secret
--   recharging Answer(bool, A)   never secret
--   current    Answer(n, A) or hidden (D)
--   duration   the LuaDurationObject of one recharge (way D)
function Sources.SpellCharges(spell)
    local api = C_Spell
    if not api or not api.GetSpellCharges then return nil end
    local info = api.GetSpellCharges(spell)
    if info == nil then return nil end
    local snap = {
        max = Answer(info.maxCharges, "A", "maxCharges"),
        recharging = Answer(info.isActive == true, "A", "isActive"),
        current = Answer(info.currentCharges, "A", "currentCharges"),
    }
    if api.GetSpellChargeDuration then snap.duration = api.GetSpellChargeDuration(spell) end
    return snap
end

-- Sources.SpellUsable(spell) -> usable Answer(bool, A), noPower Answer(bool, A).
function Sources.SpellUsable(spell)
    local api = C_Spell
    if not api or not api.IsSpellUsable then return Unknown("no-api"), Unknown("no-api") end
    local usable, noPower = api.IsSpellUsable(spell)
    if usable == nil then return Unknown("unknown-spell"), Unknown("unknown-spell") end
    return Answer(usable == true, "A", "isUsable"), Answer(noPower == true, "A", "insufficientPower")
end

----------------------------------------------------------------------------------------------------
-- Range: the event is the answer (way B), IsSpellInRange the fallback (way A)
----------------------------------------------------------------------------------------------------

local rangeByKey = {}      -- spell key -> true / false (last SPELL_RANGE_CHECK_UPDATE), nil = no check
local rangeWatched = {}    -- spell key -> true once EnableSpellRangeCheck was asked for

local function RangeKey(spell)
    if type(spell) == "number" then return spell end
    if type(spell) == "string" then
        local lowered = spell:lower()
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spell)
            if info and info.spellID then return info.spellID end
        end
        return lowered
    end
    return nil
end

-- Sources.WatchRange(spell, enable): asks the game to send SPELL_RANGE_CHECK_UPDATE for the spell.
function Sources.WatchRange(spell, enable)
    local key = RangeKey(spell)
    if key == nil then return false end
    if enable == nil then enable = true end
    if C_Spell and C_Spell.EnableSpellRangeCheck then
        C_Spell.EnableSpellRangeCheck(spell, enable)
    end
    rangeWatched[key] = enable or nil
    if not enable then rangeByKey[key] = nil end
    return true
end

-- Sources.OnRangeEvent(spellIdentifier, isInRange, checksRange): feed SPELL_RANGE_CHECK_UPDATE here.
function Sources.OnRangeEvent(spellIdentifier, isInRange, checksRange)
    local key = RangeKey(spellIdentifier)
    if key == nil then return end
    if checksRange == false or isSecret(isInRange) then
        rangeByKey[key] = nil
    else
        rangeByKey[key] = isInRange == true
    end
end

-- Sources.SpellInRange(spell[, unit]) -> Answer: the last event (B) when the spell is watched and a
-- check was made; else C_Spell.IsSpellInRange (A: true / false, nil when no target or rangeless).
function Sources.SpellInRange(spell, unit)
    local key = RangeKey(spell)
    if key ~= nil and rangeWatched[key] and rangeByKey[key] ~= nil then
        return Answer(rangeByKey[key], "B", "range-event")
    end
    if C_Spell and C_Spell.IsSpellInRange then
        local inRange = C_Spell.IsSpellInRange(spell, unit)
        if inRange == nil then return Unknown("no-range-check") end
        return Answer(inRange == true, "A", "IsSpellInRange")
    end
    return Unknown("no-api")
end

function Sources.ResetRange()
    for k in pairs(rangeByKey) do rangeByKey[k] = nil end
    for k in pairs(rangeWatched) do rangeWatched[k] = nil end
end

----------------------------------------------------------------------------------------------------
-- Auras on a unit
----------------------------------------------------------------------------------------------------

-- Way E: would this spell's aura be hidden here? true / false, nil when the predicate is missing.
local function AuraHidden(spellID)
    local secrets = C_Secrets
    if type(spellID) == "number" and secrets and secrets.ShouldSpellAuraBeSecret then
        return secrets.ShouldSpellAuraBeSecret(spellID) == true
    end
    return nil
end

-- Way E: are auras restricted in general right now? false when the client has no secrets.
local function AurasRestricted()
    local secrets = C_Secrets
    if secrets and secrets.ShouldAurasBeSecret then return secrets.ShouldAurasBeSecret() == true end
    return false
end

-- Builds the aura part of a snapshot from AuraData found by a plain lookup.
local function AuraFound(snap, unit, aura, way, now)
    snap.present = Answer(true, way, "found")
    snap.auraInstanceID = aura.auraInstanceID
    snap.spellID = aura.spellId
    snap.stacks = Answer(aura.applications, "A", "applications")
    if aura.duration ~= nil and not isSecret(aura.duration) and aura.duration == 0 then
        snap.remaining = Answer(nil, "A", "no-expiration")
    elseif isSecret(aura.expirationTime) then
        snap.remaining = Hidden(aura.expirationTime, "hidden")
    else
        snap.remaining = Answer(Remaining(aura.expirationTime, now or GetTime()), "A", "computed")
    end
    local api, secrets = C_UnitAuras, C_Secrets
    local id = aura.auraInstanceID
    if api and api.GetAuraDuration and id ~= nil and not isSecret(id) then
        local instanceHidden = secrets and secrets.ShouldUnitAuraInstanceBeSecret
            and secrets.ShouldUnitAuraInstanceBeSecret(unit, id) == true
        if not instanceHidden then snap.duration = api.GetAuraDuration(unit, id) end
    end
    return snap
end

-- Sources.Aura(unit, spell[, filter][, now]) -> snapshot:
--   present   Answer(true/false/nil): true by spell ID or name (A); false only by NAME while auras
--             aren't restricted (an ID proves presence, not absence: ranks); nil and hidden when
--             auras are restricted (E: an engine aura container can still show it)
--   stacks, remaining, duration, auraInstanceID, spellID: filled when present
-- `spell` is a spell ID (number), a name (string), or { id = number, name = string }.
function Sources.Aura(unit, spell, filter, now)
    local api = C_UnitAuras
    local snap = {}
    if not api then snap.present = Unknown("no-api"); return snap end
    local id, name
    if type(spell) == "table" then id, name = spell.id, spell.name
    elseif type(spell) == "number" then id = spell
    else name = spell end
    if id ~= nil and name == nil and C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(id) end
    if id == nil and name ~= nil and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(name)   -- knowledge-gated: nil for a proc you can't cast
        if info and info.spellID then id = info.spellID end
    end

    local hiddenByID = AuraHidden(id)
    if id ~= nil and hiddenByID ~= true and api.GetUnitAuraBySpellID then
        local aura = api.GetUnitAuraBySpellID(unit, id)
        if aura ~= nil then return AuraFound(snap, unit, aura, "A", now) end
    end
    if AurasRestricted() then
        snap.present = AskedHidden(hiddenByID and "asked-hidden" or "restricted")
        return snap
    end
    if name ~= nil and api.GetAuraDataBySpellName then
        local aura = api.GetAuraDataBySpellName(unit, name, filter)
        if aura ~= nil then return AuraFound(snap, unit, aura, "A", now) end
        snap.present = Answer(false, "A", "absent-by-name")
        return snap
    end
    snap.present = id ~= nil and Unknown("absent-by-id-only") or Unknown("no-name")
    return snap
end

-- Sources.ScanAuras(unit, filter, visit[, maxIndex]) -> complete, count. Walks aura indexes while
-- C_Secrets.ShouldUnitAuraIndexBeSecret says plain, calling visit(aura, index). Stops at the first
-- hidden index (complete = false) or at the end (complete = true). Never reads without asking.
function Sources.ScanAuras(unit, filter, visit, maxIndex)
    local api, secrets = C_UnitAuras, C_Secrets
    if not api or not api.GetAuraDataByIndex or not secrets or not secrets.ShouldUnitAuraIndexBeSecret then
        return false, 0
    end
    local count = 0
    for index = 1, maxIndex or 40 do
        if secrets.ShouldUnitAuraIndexBeSecret(unit, index, filter) ~= false then return false, count end
        local aura = api.GetAuraDataByIndex(unit, index, filter)
        if aura == nil then return true, count end
        count = count + 1
        visit(aura, index)
    end
    return true, count
end

----------------------------------------------------------------------------------------------------
-- Weapon enchants
----------------------------------------------------------------------------------------------------

-- Sources.WeaponEnchant(slot[, now]) -> snapshot for Enum.WeaponSlot.MainHand / OffHand / Ranged:
--   present  Answer(bool, A)
--   remaining Answer(seconds, A) (the game gives milliseconds), charges Answer(n, A), enchantID
function Sources.WeaponEnchant(slot)
    local api = C_Item
    local snap = {}
    if not api or not api.GetWeaponEnchantInfo then snap.present = Unknown("no-api"); return snap end
    local list = api.GetWeaponEnchantInfo(slot)
    if type(list) ~= "table" then snap.present = Unknown("no-list"); return snap end
    for _, enchant in pairs(list) do
        if enchant.hasEnchant == true then
            snap.present = Answer(true, "A", "hasEnchant")
            snap.enchantID = enchant.enchantID
            snap.charges = Answer(enchant.charges, "A", "charges")
            if enchant.timeLeft ~= nil and not isSecret(enchant.timeLeft) then
                snap.remaining = Answer(enchant.timeLeft / 1000, "A", "timeLeft")
            else
                snap.remaining = Answer(enchant.timeLeft, "A", "timeLeft")
            end
            return snap
        end
    end
    snap.present = Answer(false, "A", "no-enchant")
    return snap
end

----------------------------------------------------------------------------------------------------
-- Events the sources listen to
----------------------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "SPELL_RANGE_CHECK_UPDATE" then Sources.OnRangeEvent(...) end
end)
