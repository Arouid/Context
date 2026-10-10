-- EditorWindow.lua: the editor's window (/context editor). Left: the groups and their displays,
-- then the standalone displays. Right, for the selected display: its source and visibility, each
-- state as a sentence with how it was decided at the last evaluation and its actions ("visual only
-- here" marked), a row to add an action (only look actions on a hidden-value state), a row to add
-- a state from the ready-made conditions with its color. The logic is in Editor.lua.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
--
-- Templates checked in Blizzard's Forever source (build 70245): BackdropTemplate,
-- UIPanelButtonTemplate, UIPanelCloseButton, InputBoxTemplate; ColorPickerFrame:
-- SetupColorPickerAndShow(info) with r, g, b, opacity, hasOpacity, swatchFunc, opacityFunc,
-- cancelFunc (seen working for addons on Forever by Mage Kit, 2026-10-07). Nothing protected.
local _, ns = ...
local L = ns.L
local Editor = ns.Editor

local WIDTH, HEIGHT, LIST_W, ROW = 660, 480, 180, 22
local win, listChild, panel
local selected            -- the selected display id
local pools = {}          -- kind -> { [i] = widget, used = n }
local drafts = {}         -- "id/state" -> what the add rows hold between refreshes

----------------------------------------------------------------------------------------------------
-- Pooled widgets, laid out from the top of their parent on every refresh
----------------------------------------------------------------------------------------------------

local function Acquire(kind, make, parent)
    local pool = pools[kind]
    if not pool then pool = { used = 0 }; pools[kind] = pool end
    pool.used = pool.used + 1
    local w = pool[pool.used]
    if not w then w = make(parent); pool[pool.used] = w end
    w:Show()
    return w
end

local function ReleaseAll()
    for _, pool in pairs(pools) do
        for i = 1, #pool do pool[i]:Hide() end
        pool.used = 0
    end
end

local function MakeLabel(parent) return parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") end
local function MakeTitle(parent) return parent:CreateFontString(nil, "OVERLAY", "GameFontNormal") end

local function MakeButton(parent)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetScript("OnClick", function(self) if self.onClick then self.onClick(self) end end)
    return b
end

local function MakeInput(parent)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetAutoFocus(false)
    e:SetSize(60, 20)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnTextChanged", function(self, userInput) if userInput and self.onChange then self.onChange(self:GetText()) end end)
    return e
end

local function MakeSwatch(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexture("Interface\\Buttons\\WHITE8x8")
    b:SetScript("OnClick", function(self) if self.onClick then self.onClick(self) end end)
    return b
end

-- Label(parent, kind, text, x, y, width): kind = "title" | "label" | "listTitle".
local function Label(parent, kind, text, x, y, width)
    local f = Acquire(kind, kind == "label" and MakeLabel or MakeTitle, parent)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    f:SetWidth(width or 300)
    f:SetJustifyH("LEFT")
    f:SetText(text or "")
    f.text = text
    return f
end

local function Button(parent, kind, text, x, y, width, onClick)
    local b = Acquire(kind, MakeButton, parent)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetSize(width or 60, 20)
    b:SetText(text or "")
    b.text, b.onClick = text, onClick
    return b
end

local function Input(parent, x, y, width, text, onChange)
    local e = Acquire("input", MakeInput, parent)
    e:ClearAllPoints()
    e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    e:SetWidth(width)
    e.onChange = nil
    e:SetText(text or "")
    e.onChange = onChange
    return e
end

local function Swatch(parent, x, y, color, onClick)
    local b = Acquire("swatch", MakeSwatch, parent)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b.tex:SetVertexColor(ns.Looks.Color(color))
    b.onClick = onClick
    return b
end

-- Blizzard's color picker; Cancel gives the color back as it was.
local function PickColor(color, onDone)
    local picker = ColorPickerFrame
    if not picker or not picker.SetupColorPickerAndShow then
        ns:Print(L["The game's color picker isn't available here."])
        return false
    end
    local r, g, b, a = ns.Looks.Color(color)
    local function Apply()
        local nr, ng, nb = picker:GetColorRGB()
        local na = picker.GetColorAlpha and picker:GetColorAlpha() or a
        onDone({ nr, ng, nb, na })
    end
    picker:SetupColorPickerAndShow({ r = r, g = g, b = b, opacity = a, hasOpacity = true,
        swatchFunc = Apply, opacityFunc = Apply, cancelFunc = function() onDone({ r, g, b, a }) end })
    return true
end

local function DisplayName(def)
    if def.name then return def.name end
    local spell = def.source and def.source.spell
    if type(spell) == "table" then return spell.name or tostring(spell.id) end
    return spell ~= nil and tostring(spell) or def.id
end

local function SortedIds(t)
    local ids = {}
    for id in pairs(t or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

----------------------------------------------------------------------------------------------------
-- The list
----------------------------------------------------------------------------------------------------

local function ListButton(id, x, y)
    local def = ns.db.displays[id]
    if not def then return y end
    local text = DisplayName(def)
    if id == selected then text = "|cffffd100" .. text .. "|r" end
    Button(listChild, "listButton", text, x, y, LIST_W - x - 4, function() Editor.Select(id) end)
    return y - ROW
end

local function RenderList()
    local y, inGroup = -4, {}
    for _, gid in ipairs(SortedIds(ns.db.groups)) do
        local g = ns.db.groups[gid]
        Label(listChild, "listTitle", g.name or gid, 4, y, LIST_W - 8)
        y = y - ROW
        for _, cid in ipairs(g.children or {}) do
            inGroup[cid] = true
            y = ListButton(cid, 14, y)
        end
    end
    for _, id in ipairs(SortedIds(ns.db.displays)) do
        if not inGroup[id] then y = ListButton(id, 4, y) end
    end
    listChild:SetHeight(math.max(-y, 1))
end

----------------------------------------------------------------------------------------------------
-- The details of the selected display
----------------------------------------------------------------------------------------------------

local function Draft(key, default)
    local d = drafts[key]
    if not d then d = default; drafts[key] = d end
    return d
end

local function Header(def, y)
    Label(panel, "title", string.format("%s (%s)", DisplayName(def), tostring(def.type)), 0, y, 440)
    y = y - ROW
    Label(panel, "label", L["source"] .. ": " .. Editor.SourceSentence(def.source) .. "   " .. L["visibility"] .. ": " .. tostring(def.visibility or "always"), 0, y, 440)
    return y - ROW - 4
end

-- The row that adds an action to a state: a kind to cycle through (the honesty rule filters it),
-- its parameter, Add.
local function AddActionRow(id, name, y)
    local kinds = Editor.ActionKinds(id, name)
    local d = Draft(id .. "/" .. name, { kind = 1, text = "" })
    if d.kind > #kinds then d.kind = 1 end
    local kind = kinds[d.kind]
    Label(panel, "label", "  + " .. L["action"] .. ":", 0, y - 4, 70)
    Button(panel, "button", Editor.KIND_LABELS[kind] or kind, 74, y, 100, function() d.kind = d.kind % #kinds + 1; Editor.Refresh() end)
    if kind == "sound" or kind == "speak" or kind == "message" or kind == "chat" then
        Input(panel, 186, y, 150, d.text, function(text) d.text = text end)
    elseif kind == "color" then
        d.color = d.color or { 1, 0.2, 0.2, 1 }
        Swatch(panel, 184, y - 2, d.color, function() PickColor(d.color, function(c) d.color = c; Editor.Refresh() end) end)
    end
    Button(panel, "button", L["Add"], 344, y, 50, function()
        local params = {}
        if kind == "sound" then params.sound = tonumber(d.text or "") or d.text
        elseif kind == "color" then params.color = d.color
        elseif not ns.Actions.IsLook(kind) then params.text = d.text or "" end
        local ok, problem = Editor.AddAction(id, name, kind, params)
        if not ok then ns:Printf(L["Can't add this action: %s"], tostring(problem)) end
    end)
    return y - ROW
end

local function StateBlock(id, def, i, state, y)
    local entry = ns.Displays.Get(id)
    local live = entry and entry.states and entry.states[i]
    local color = (live and live.active) and "|cff33ff33" or "|cffaaaaaa"
    Label(panel, "title", color .. tostring(state.name) .. "|r: " .. Editor.Sentence(state.when), 0, y, 370)
    Button(panel, "button", L["Remove"], 400, y, 70, function() Editor.RemoveState(id, state.name) end)
    y = y - ROW
    local decided = Editor.Decided(live)
    if Editor.MayHide(state.when) and not (live and live.result and live.result.visualOnly) then
        decided = decided .. " " .. L["(may be visual only in combat)"]
    end
    Label(panel, "label", "  " .. decided, 0, y, 440)
    y = y - ROW
    Label(panel, "label", "  " .. L["color"] .. ":", 0, y - 2, 60)
    Swatch(panel, 60, y - 2, state.look and state.look.color or { 1, 1, 1, 1 }, function()
        PickColor(state.look and state.look.color or { 1, 1, 1, 1 }, function(c) Editor.SetStateColor(id, state.name, c) end)
    end)
    y = y - ROW
    for index, a in ipairs(def.actions or {}) do
        if a.on == state.name then
            Label(panel, "label", "  - " .. Editor.DescribeAction(a), 0, y - 2, 360)
            Button(panel, "button", "x", 400, y, 24, function() Editor.RemoveAction(id, index) end)
            y = y - ROW
        end
    end
    return AddActionRow(id, state.name, y) - 6
end

-- Actions on the Cooldown Manager's edges (on = "cdm:<edge>") have no state row of their own.
local function EdgeActions(id, def, y)
    for index, a in ipairs(def.actions or {}) do
        if ns.Actions.CdmEdgeOf(a.on) then
            Label(panel, "label", string.format(L["on Cooldown Manager edge %s: %s"], ns.Actions.CdmEdgeOf(a.on), Editor.DescribeAction(a)), 0, y - 2, 360)
            Button(panel, "button", "x", 400, y, 24, function() Editor.RemoveAction(id, index) end)
            y = y - ROW
        end
    end
    return y
end

local function AddStateRow(id, y)
    local d = Draft(id, { cond = 1, value = "" })
    local ready = Editor.READY_MADE[d.cond] or Editor.READY_MADE[1]
    Label(panel, "title", L["Add a state"], 0, y, 200)
    y = y - ROW
    Button(panel, "button", Editor.TEST_LABELS[ready.test] or ready.key, 0, y, 120, function()
        d.cond = d.cond % #Editor.READY_MADE + 1
        Editor.Refresh()
    end)
    if ready.needsValue then
        Label(panel, "label", ready.compare, 126, y - 4, 20)
        Input(panel, 150, y, 50, d.value ~= "" and d.value or tostring(ready.default), function(text) d.value = text end)
    end
    Label(panel, "label", L["color"] .. ":", 210, y - 4, 40)
    Swatch(panel, 250, y - 2, d.color or { 1, 1, 1, 1 }, function()
        PickColor(d.color or { 1, 1, 1, 1 }, function(c) d.color = c; Editor.Refresh() end)
    end)
    Button(panel, "button", L["Add"], 344, y, 50, function()
        local value = tonumber(d.value ~= "" and d.value or tostring(ready.default or ""))
        local ok, problem = Editor.AddState(id, ready.key, value, d.color)
        if not ok then ns:Printf(L["Can't add this state: %s"], tostring(problem)) end
    end)
    return y - ROW
end

local function RenderPanel()
    local def = selected and ns.db.displays[selected]
    if not def then
        Label(panel, "label", L["Pick a display on the left."], 0, -4, 440)
        panel:SetHeight(ROW)
        return
    end
    local y = Header(def, -4)
    for i, state in ipairs(def.states or {}) do y = StateBlock(selected, def, i, state, y) end
    y = EdgeActions(selected, def, y)
    y = AddStateRow(selected, y - 6)
    panel:SetHeight(math.max(-y, 1))
end

----------------------------------------------------------------------------------------------------
-- The window
----------------------------------------------------------------------------------------------------

local function Wheel(scroll)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local child = self:GetScrollChild()
        local max = math.max((child and child:GetHeight() or 0) - (self:GetHeight() or 0), 0)
        self:SetVerticalScroll(math.min(math.max((self:GetVerticalScroll() or 0) - delta * 40, 0), max))
    end)
end

local function Build()
    win = CreateFrame("Frame", "ContextEditor", UIParent, "BackdropTemplate")
    win:SetSize(WIDTH, HEIGHT)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if win.SetBackdrop then
        win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        win:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    end
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText(L["Context editor"])
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local refresh = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    refresh:SetSize(70, 20)
    refresh:SetPoint("TOPRIGHT", -30, -6)
    refresh:SetText(L["Refresh"])
    refresh:SetScript("OnClick", function() Editor.Refresh() end)
    local list = CreateFrame("ScrollFrame", nil, win)
    list:SetPoint("TOPLEFT", 10, -34)
    list:SetSize(LIST_W, HEIGHT - 44)
    listChild = CreateFrame("Frame", nil, list)
    listChild:SetSize(LIST_W, 1)
    list:SetScrollChild(listChild)
    Wheel(list)
    local details = CreateFrame("ScrollFrame", nil, win)
    details:SetPoint("TOPLEFT", LIST_W + 20, -34)
    details:SetPoint("BOTTOMRIGHT", -10, 10)
    panel = CreateFrame("Frame", nil, details)
    panel:SetSize(WIDTH - LIST_W - 30, 1)
    details:SetScrollChild(panel)
    Wheel(details)
    if UISpecialFrames then table.insert(UISpecialFrames, "ContextEditor") end
    win:Hide()   -- a new frame is shown: Toggle opens it
    win:SetScript("OnShow", function() Editor.Refresh() end)
end

-- Editor.Refresh(): redraws the list and the details from the saved definitions and the live
-- states. Nothing happens while the window is closed.
function Editor.Refresh()
    if not win or not win:IsShown() then return false end
    ReleaseAll()
    RenderList()
    RenderPanel()
    return true
end

function Editor.Select(id)
    selected = id
    Editor.Refresh()
end

-- Editor.Toggle() -> true when the window is now shown.
function Editor.Toggle()
    if not win then Build() end
    if win:IsShown() then
        win:Hide()
        return false
    end
    win:Show()
    Editor.Refresh()
    return true
end

function Editor.Window() return win end

-- Editor.Texts() -> the texts drawn in the list and the panel at the last refresh (for the tests).
function Editor.Texts()
    local list = {}
    for _, pool in pairs(pools) do
        for i = 1, pool.used do
            if pool[i].text ~= nil then list[#list + 1] = tostring(pool[i].text) end
        end
    end
    return list
end
