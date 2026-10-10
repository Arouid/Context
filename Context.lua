-- Context.lua: the core of the addon. Settings, saved variables and the /context command.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
--
-- Loads after the locale files. Saved variables are ready on this addon's own ADDON_LOADED; code
-- that needs every file of the .toc loaded waits for PLAYER_LOGIN.
local ADDON, ns = ...
local L = ns.L

ns.VERSION = "0.1.0"   -- keep it equal to ## Version in the .toc

-- Defaults. CopyDefaults fills in what's missing without touching what the player changed;
-- schemaVer is there for the day the saved data needs migrating.
ns.DEFAULTS = {
    schemaVer = 1,
    displays = {},   -- id -> display definition (Displays.lua)
    groups = {},     -- id -> group definition (Groups.lua)
}

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffContext|r " .. tostring(msg))
end

function ns:Printf(fmt, ...)
    self:Print(string.format(fmt, ...))
end

local function ListDisplays()
    local displays, groups = 0, 0
    for _ in pairs(ns.db.displays) do displays = displays + 1 end
    for _ in pairs(ns.db.groups) do groups = groups + 1 end
    ns:Printf(L["displays: %d, groups: %d"], displays, groups)
    for _, id in ipairs(ns.Displays and ns.Displays.Order() or {}) do
        local entry = ns.Displays.Get(id)
        if entry then
            local on = {}
            for i, s in ipairs(entry.states or {}) do
                if s.active then on[#on + 1] = (entry.def.states[i].name or tostring(i)) .. (s.visualOnly and "*" or "") end
            end
            ns:Printf("  %s (%s) %s %s", id, entry.def.type, entry.frame:IsShown() and L["shown"] or L["hidden"], table.concat(on, ", "))
        end
    end
end

local function ResetAll()
    local ids = {}   -- a copy: Remove edits the order list while it is walked
    for _, id in ipairs(ns.Displays and ns.Displays.Order() or {}) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do ns.Displays.Remove(id) end
    ns.db.displays, ns.db.groups = {}, {}
    ns.db.presetInstalled = nil
    ns:Print(L["All displays removed. /reload to clear the screen."])
end

local function Help()
    ns:Print(L["Commands:"])
    ns:Print("/context edit - " .. L["unlocks the displays to drag them (out of combat; Blizzard's Edit Mode when the library is loaded)"])
    ns:Print("/context editor - " .. L["opens the editor: states, how each is decided, actions"])
    ns:Print("/context preset mage - " .. L["installs a ready-made set of displays"])
    ns:Print("/context list - " .. L["lists the displays and their active states (* = visual only)"])
    ns:Print("/context probe [spell] - " .. L["prints what the sources answer for a spell (default: Frost Nova and Clearcasting)"])
    ns:Print("/context tests - " .. L["opens the step-by-step in-game test guide (testing)"])
    ns:Print("/context reset - " .. L["removes every display and group"])
    ns:Print("/context version - " .. L["shows the version"])
end

function ns:Slash(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "version" then
        self:Printf(L["version %s"], self.VERSION)
    elseif cmd == "probe" and self.Probe then
        self.Probe(rest)
    elseif cmd == "edit" and self.Groups then
        self.Groups.SetEditMode(not self.Groups.IsEditing())
    elseif cmd == "editor" and self.Editor then
        self.Editor.Toggle()
    elseif cmd == "preset" and self.Preset then
        local name = (rest or ""):lower()
        if self.Preset.Install(name) then self:Printf(L["Preset installed: %s"], name) else self:Printf(L["Unknown preset: %s"], name) end
    elseif cmd == "tests" and self.TestGuide then
        self.TestGuide.Toggle()
    elseif cmd == "list" then
        ListDisplays()
    elseif cmd == "reset" then
        ResetAll()
    else
        Help()
    end
end

SLASH_CONTEXT1 = "/context"
SlashCmdList["CONTEXT"] = function(msg) ns:Slash(msg) end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ContextDB = ContextDB or {}
        CopyDefaults(ContextDB, ns.DEFAULTS)
        ns.db = ContextDB
    elseif event == "PLAYER_LOGIN" then
        if ns.Preset then ns.Preset.AutoInstall() end
        if ns.Displays then ns.Displays.Start() end
        if ns.TestGuide then ns.TestGuide.OnLogin() end
        ns:Printf(L["loaded. Type /%s for help."], "context")
    end
end)
