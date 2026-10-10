-- Preset.lua: ready-made sets of displays. "Mage essentials" is the phase-1 set: the cooldown group
-- (Blink, Ice Block, Frost Nova, Counterspell, Evocation), the Clearcasting proc icon with a glow,
-- and the Ice Barrier bar that turns red under 5 s. Installed on a mage's first login with no
-- displays, or with /context preset mage.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
local _, ns = ...
local L = ns.L

local Preset = {}
ns.Preset = Preset

local function CooldownIcon(id, group, spell)
    return {
        id = id, type = "icon", schema = 1, group = group,
        source = { kind = "spell", spell = spell },
        visibility = "always",
        look = { size = 36, desaturateOnCooldown = true },
        states = {},
    }
end

-- Preset.Mage() -> groups, displays (id-keyed), untouched by the game: tested headless.
function Preset.Mage()
    local groups, displays = {}, {}
    groups["mage.cooldowns"] = {
        id = "mage.cooldowns", name = L["Mage cooldowns"], grow = "RIGHT", spacing = 4,
        pos = { x = 0, y = -200 },
        children = { "mage.blink", "mage.iceblock", "mage.frostnova", "mage.counterspell", "mage.evocation" },
    }
    displays["mage.blink"] = CooldownIcon("mage.blink", "mage.cooldowns", "Blink")
    displays["mage.iceblock"] = CooldownIcon("mage.iceblock", "mage.cooldowns", "Ice Block")
    displays["mage.frostnova"] = CooldownIcon("mage.frostnova", "mage.cooldowns", "Frost Nova")
    displays["mage.counterspell"] = CooldownIcon("mage.counterspell", "mage.cooldowns", "Counterspell")
    displays["mage.evocation"] = CooldownIcon("mage.evocation", "mage.cooldowns", "Evocation")
    displays["mage.clearcasting"] = {
        id = "mage.clearcasting", type = "icon", schema = 1, name = L["Clearcasting"],
        source = { kind = "aura", unit = "player", filter = "HELPFUL", spell = { id = 12536, name = "Clearcasting" } },
        visibility = "whenPresent",
        look = { size = 44 },
        pos = { x = 0, y = -140 },
        states = {
            { name = "up", when = { test = "present", compare = "==", value = true, way = "A" }, look = { glow = true } },
        },
    }
    displays["mage.icebarrier"] = {
        id = "mage.icebarrier", type = "bar", schema = 1, name = L["Ice Barrier"],
        source = { kind = "aura", unit = "player", filter = "HELPFUL", spell = "Ice Barrier" },
        visibility = "whenPresent",
        look = { width = 200, height = 18, color = { 0.25, 0.78, 0.92, 1 } },
        pos = { x = 0, y = -250 },
        states = {
            { name = "low", when = { test = "remaining", compare = "<", value = 5, way = "A" }, look = { color = { 1, 0.2, 0.2, 1 } } },
        },
    }
    return groups, displays
end

Preset.LIST = { mage = Preset.Mage }

-- Preset.Install(name) -> true when installed. Replaces the preset's own ids, keeps everything else.
function Preset.Install(name)
    local make = Preset.LIST[name]
    if not make then return false end
    local groups, displays = make()
    ns.db.groups = ns.db.groups or {}
    ns.db.displays = ns.db.displays or {}
    for id, g in pairs(groups) do
        local old = ns.db.groups[id]
        if old and old.pos then g.pos = old.pos end
        ns.db.groups[id] = g
    end
    for id, def in pairs(displays) do
        local old = ns.db.displays[id]
        if old and old.pos then def.pos = old.pos end
        ns.db.displays[id] = def
        if ns.Displays then ns.Displays.Build(def) end
    end
    if ns.Groups then ns.Groups.LayoutAll() end
    return true
end

-- Preset.AutoInstall(): a mage with no displays gets the mage set once.
function Preset.AutoInstall()
    if ns.db.presetInstalled then return false end
    if next(ns.db.displays or {}) ~= nil then return false end
    if not UnitClass then return false end
    local _, class = UnitClass("player")   -- not `UnitClass and UnitClass(...)`: `and` keeps one value
    if class ~= "MAGE" then return false end
    ns.db.presetInstalled = "mage"
    return Preset.Install("mage")
end
