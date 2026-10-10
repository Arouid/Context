-- TestGuide.lua: the in-game test guide (/context tests). Every row of the "Test guide" tables in
-- docs/verified-in-game.md as numbered steps (TestGuideSteps.lua), one at a time, grouped by where
-- you need to be, with the buttons a step needs. Your answers (as expected / not / skipped, a note,
-- the game build) and the last button's output are saved in ContextDB.testGuide.results: after you
-- log out, Claude reads them from SavedVariables. It opens at login while rows are left (a button
-- in it turns that off). English only on purpose: a testing tool, not a player feature.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
--
-- Same design as Mage Kit's test guide (Finess's other addon), written again for Context on
-- Blizzard's own templates (Blizzard_SharedXML, build 70245): UIPanelButtonTemplate for the
-- buttons, InputBoxTemplate for the note, BackdropTemplate for the window, a ScrollFrame for the
-- body; GetBuildInfo for the build, C_UI.Reload behind the Reload button.
local _, ns = ...

local Guide = {}
ns.TestGuide = Guide

local GROUPS = { { "T", "Anywhere" }, { "F", "Near mobs" }, { "D", "Dungeon" } }
local RESULTS = { ok = "|cff40ff40as expected|r", bad = "|cffff6060not as expected|r", skip = "|cff8c8c8cskipped|r" }
local W, H, BODY_W = 600, 560, 568
local MAX_OUTPUT = 40   -- lines of a button's output kept with an answer
local WHITE = "Interface\\Buttons\\WHITE8x8"

local win, current        -- the window, the step shown
local output, outputFor   -- the last button's lines, and the id of the step they belong to

local function Data()
    local d = ns.db.testGuide
    if not d then d = { showAtLogin = true }; ns.db.testGuide = d end
    d.results = d.results or {}   -- step id -> { result, at, build, version, note, output }
    d.last = d.last or {}         -- group letter -> the step id you were on
    d.group = d.group or "T"
    return d
end

local function Steps() return ns.TEST_STEPS or {} end

local function Group(letter)
    local list = {}
    for _, step in ipairs(Steps()) do
        if step[1]:sub(1, 1) == letter then list[#list + 1] = step end
    end
    return list
end

local function Answered(step)
    local r = Data().results[step[1]]
    return r ~= nil and (r.result == "ok" or r.result == "bad")
end

local function Counts(letter)
    local list, done = Group(letter), 0
    for _, step in ipairs(list) do if Answered(step) then done = done + 1 end end
    return done, #list
end

local function IndexOf(list, id)
    for i, step in ipairs(list) do if step[1] == id then return i end end
end

-- The first step after position i (wrapping) with no answer yet; nil when the group is done.
local function NextOpen(list, i)
    for k = 1, #list do
        local step = list[(i + k - 1) % #list + 1]
        if not Answered(step) then return step end
    end
end

local function Record(step)
    local results = Data().results
    local r = results[step[1]]
    if not r then r = {}; results[step[1]] = r end
    return r
end

-- A chat line without its color codes: what goes into the saved variables.
local function Plain(line)
    return (tostring(line):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

----------------------------------------------------------------------------------------------------
-- Buttons a step can ask for: each runs a /context command and keeps what it printed
----------------------------------------------------------------------------------------------------

-- Runs fn(...) with ns.Print also collecting the chat lines it prints. Returns the lines.
local function CaptureChat(fn, ...)
    local lines, orig = {}, ns.Print
    ns.Print = function(self, msg) lines[#lines + 1] = tostring(msg); orig(self, msg) end
    local ok, err = pcall(fn, ...)
    ns.Print = orig
    if not ok then lines[#lines + 1] = "|cffff6060That button failed: " .. tostring(err) .. "|r" end
    return lines
end

local function Command(text) return function() return CaptureChat(ns.Slash, ns, text) end end

local ACTIONS = {
    probe = { "Probe", Command("probe") },
    probe_barrier = { "Probe Ice Barrier", Command("probe Ice Barrier") },
    probe_cs = { "Probe Counterspell", Command("probe Counterspell") },
    list = { "List displays", Command("list") },
    preset = { "Preset mage", Command("preset mage") },
    edit = { "Edit", Command("edit") },
    editor = { "Editor", Command("editor") },
    reset = { "Reset displays", Command("reset") },
    reload = { "Reload UI", function()
        if C_UI and C_UI.Reload then C_UI.Reload() end
        return { "Reloading the interface..." }
    end },
}
Guide.ACTIONS = ACTIONS

local Show   -- below

local function RunAction(key)
    local action = ACTIONS[key]
    if not (action and current) then return end
    local ok, lines = pcall(action[2], current)
    if not ok then lines = { "|cffff6060That button failed: " .. tostring(lines) .. "|r" } end
    output = type(lines) == "table" and lines or { action[1] .. ": done." }
    outputFor = current[1]
    local kept = {}
    for i = 1, math.min(#output, MAX_OUTPUT) do kept[i] = Plain(output[i]) end
    if #output > MAX_OUTPUT then kept[#kept + 1] = "(cut)" end
    local r = Record(current)
    r.output = kept
    r.outputAt = date and date("%H:%M:%S") or nil
    Show(current)
end

----------------------------------------------------------------------------------------------------
-- Answers and moving around
----------------------------------------------------------------------------------------------------

local function BuildInfo()
    local ok, version, build = pcall(GetBuildInfo)
    if ok then return tostring(build), tostring(version) end
end

local function Answer(result)
    if not current then return end
    local r = Record(current)
    r.result = result
    r.at = date and date("%Y-%m-%d %H:%M") or nil
    r.build, r.version = BuildInfo()
    local note = win and win.note:GetText() or ""
    r.note = (note ~= nil and note ~= "") and note or nil
    local list = Group(Data().group)
    Show(NextOpen(list, IndexOf(list, current[1]) or 1) or current)
end

local function Step(delta)
    if not current then return end
    local list = Group(Data().group)
    local step = list[(IndexOf(list, current[1]) or 1) + delta]
    if step then Show(step) end
end

-- Shows the group on the step you left it at, else its first open step.
local function SwitchGroup(letter)
    local d = Data()
    d.group = letter
    local list = Group(letter)
    local at = IndexOf(list, d.last[letter] or "")
    Show((at and list[at]) or NextOpen(list, #list) or list[1])
end

----------------------------------------------------------------------------------------------------
-- The window
----------------------------------------------------------------------------------------------------

local function Label(parent, font, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetWidth(width or BODY_W)
    return fs
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- Sets a button's text and widens it when the text needs more room (never narrower than width).
local function Caption(b, text, width)
    b:SetText(text)
    local fs = b.GetFontString and b:GetFontString()
    local w = fs and fs.GetStringWidth and fs:GetStringWidth()
    b:SetWidth(math.max(width, (w or 0) + 20))
end

-- The scrolling middle: the steps, then four labeled parts (expect, control, wrong, output).
local PARTS = { "steps", "head", "text", "head", "text", "head", "text", "head", "text" }
local FONTS = { steps = "GameFontHighlight", head = "GameFontNormalSmall", text = "GameFontHighlightSmall" }

local function Body(w)
    local scroll = CreateFrame("ScrollFrame", nil, w)
    scroll:SetPoint("TOPLEFT", 14, -86)
    scroll:SetPoint("BOTTOMRIGHT", -14, 140)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(BODY_W, 10)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, (child:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - delta * 40)))
    end)
    child.parts = {}
    for i, kind in ipairs(PARTS) do child.parts[i] = Label(child, FONTS[kind]) end
    w.scroll, w.body = scroll, child
end

local function Stack(texts)
    local y = 0
    for i, fs in ipairs(win.body.parts) do
        local text = texts[i] or ""
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 0, -y)
        fs:SetText(text)
        if text ~= "" then y = y + (fs:GetStringHeight() or 12) + 8 end
    end
    win.body:SetHeight(math.max(y, 10))
    win.scroll:SetVerticalScroll(0)
end

local function GroupRow(w)
    w.groups = {}
    for i, g in ipairs(GROUPS) do
        local b = Button(w, g[1], 60, function() SwitchGroup(g[1]) end)
        if i == 1 then b:SetPoint("TOPLEFT", 12, -30) else b:SetPoint("LEFT", w.groups[i - 1], "RIGHT", 4, 0) end
        w.groups[i] = b
    end
end

local function ActionRow(w)
    w.actions = {}
    for i = 1, 4 do
        local b = Button(w, "", 60, function(self) RunAction(self.key) end)
        if i == 1 then b:SetPoint("BOTTOMLEFT", 12, 108) else b:SetPoint("LEFT", w.actions[i - 1], "RIGHT", 6, 0) end
        w.actions[i] = b
    end
end

local function AnswerRows(w)
    local noteLabel = Label(w, "GameFontNormalSmall", 40)
    noteLabel:SetPoint("BOTTOMLEFT", 14, 82)
    noteLabel:SetText("Note:")
    w.note = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
    w.note:SetSize(W - 84, 22)
    w.note:SetPoint("BOTTOMLEFT", 66, 76)
    w.note:SetAutoFocus(false)
    w.note:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    w.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local ok = Button(w, "As expected", 130, function() Answer("ok") end)
    ok:SetPoint("BOTTOMLEFT", 12, 42)
    Button(w, "Not as expected", 150, function() Answer("bad") end):SetPoint("LEFT", ok, "RIGHT", 8, 0)
    Button(w, "Skip for now", 120, function() Answer("skip") end):SetPoint("BOTTOMRIGHT", -12, 42)
    local back = Button(w, "< Back", 70, function() Step(-1) end)
    back:SetPoint("BOTTOMLEFT", 12, 10)
    Button(w, "Next >", 70, function() Step(1) end):SetPoint("LEFT", back, "RIGHT", 8, 0)
    w.login = Button(w, "", 170, function()
        local d = Data()
        d.showAtLogin = not d.showAtLogin
        Show(current)
    end)
    w.login:SetPoint("BOTTOMRIGHT", -12, 10)
end

local function Window()
    local w = CreateFrame("Frame", "ContextTestGuide", UIParent, "BackdropTemplate")
    w:SetSize(W, H)
    w:SetFrameStrata("HIGH")
    local pos = Data().pos
    if pos then w:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else w:SetPoint("LEFT", UIParent, "LEFT", 20, 40) end
    if w.SetBackdrop then
        w:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        w:SetBackdropColor(0.07, 0.07, 0.08, 0.95)
        w:SetBackdropBorderColor(0.3, 0.3, 0.32, 1)
    end
    w:SetMovable(true)
    w:EnableMouse(true)
    w:SetClampedToScreen(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", function(self) self:StartMoving() end)
    w:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if point then Data().pos = { point, relPoint, x, y } end
    end)
    local head = Label(w, "GameFontNormal")
    head:SetPoint("TOPLEFT", 14, -9)
    head:SetText("Context test guide (drag me). Answers are saved at logout.")
    Button(w, "X", 24, function() w:Hide() end):SetPoint("TOPRIGHT", -6, -6)
    w.title = Label(w, "GameFontNormal", W - 210)
    w.title:SetPoint("TOPLEFT", 14, -62)
    w.status = Label(w, "GameFontHighlightSmall", 170)
    w.status:SetPoint("TOPRIGHT", -14, -63)
    w.status:SetJustifyH("RIGHT")
    GroupRow(w)
    Body(w)
    ActionRow(w)
    AnswerRows(w)
    return w
end

local function Numbered(step)
    local lines = {}
    for i = 3, #step do lines[#lines + 1] = string.format("%d. %s", i - 2, step[i]) end
    return table.concat(lines, "\n")
end

-- The body's texts for a step: PARTS in order. The output shown is the last button's when it was
-- pressed on this step, else the one saved with the step.
local function Texts(step, r)
    local out = output or {}
    if outputFor ~= step[1] then out = r and r.output or {} end
    return { Numbered(step),
        "What you should see:", step.expect or "",
        step.control and "Known-good control:" or "", step.control or "",
        step.wrong and "If it's not that:" or "", step.wrong or "",
        #out > 0 and "Output of the last button (saved with your answer):" or "", table.concat(out, "\n") }
end

Show = function(step)
    if not win then return end
    local d = Data()
    if current and current ~= step then   -- a note typed but not answered yet is kept
        local text = win.note:GetText()
        if text and text ~= "" then Record(current).note = text end
    end
    current = step
    if step then d.group = step[1]:sub(1, 1) end   -- a step shown from elsewhere pulls its group along
    win.note:ClearFocus()   -- typing goes back to the game
    for i, g in ipairs(GROUPS) do
        local done, total = Counts(g[1])
        local text = string.format("%s %s %d/%d", g[1], g[2], done, total)
        Caption(win.groups[i], g[1] == d.group and ("|cffffd100" .. text .. "|r") or text, 60)
    end
    win.login:SetText(d.showAtLogin and "At login: opens" or "At login: stays shut")
    if not step then
        win.title:SetText("No step in this group.")
        win.status:SetText("")
        return Stack({})
    end
    d.last[d.group] = step[1]
    local list, r = Group(d.group), d.results[step[1]]
    win.title:SetText(step[1] .. "  " .. step[2])
    local answer = r and r.result and RESULTS[r.result] or "not answered"
    win.status:SetText(string.format("%d of %d - %s", IndexOf(list, step[1]) or 0, #list, answer))
    Stack(Texts(step, r))
    for i, b in ipairs(win.actions) do
        local key = step.act and step.act[i]
        b.key = key
        Caption(b, key and ACTIONS[key] and ACTIONS[key][1] or "", 60)
        b:SetShown(key ~= nil)
    end
    win.note:SetText(r and r.note or "")
end

----------------------------------------------------------------------------------------------------
-- Entry points
----------------------------------------------------------------------------------------------------

-- Guide.Open(): opens the guide on the group and step you left off at.
function Guide.Open()
    win = win or Window()
    win:Show()
    SwitchGroup(Data().group)
end

function Guide.Toggle()
    if win and win:IsShown() then win:Hide() else Guide.Open() end
end

function Guide.IsOpen() return win ~= nil and win:IsShown() == true end

-- Guide.OnLogin() -> true when the guide will open: steps are left and it wasn't turned off.
function Guide.OnLogin()
    if Data().showAtLogin == false then return false end
    for _, g in ipairs(GROUPS) do
        local done, total = Counts(g[1])
        if done < total then
            if C_Timer and C_Timer.After then C_Timer.After(3, Guide.Open) else Guide.Open() end
            return true
        end
    end
    return false
end

-- For the headless test.
Guide.Answer, Guide.Run, Guide.Plain = Answer, RunAction, Plain
Guide.Show = function(step) Show(step) end
Guide.Current = function() return current end
