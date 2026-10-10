-- Widgets.lua: the icon and bar widgets a display draws with. They take duration objects and hand
-- them to the engine (swipe, bar fill, timer text), so they keep counting when the numbers are
-- secret; everything that could be a secret goes to a setter that accepts one, never into Lua.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
--
-- Checked in Blizzard's Forever source (build 70245): Cooldown:SetCooldownFromDurationObject
-- (measured on Forever by Mage Kit, 2026-10-07), StatusBar:SetTimerDuration(duration,
-- interpolation, direction), C_DurationUtil.CreateDurationTextBinding (SetFontString, SetDuration,
-- SetEnabled, SetFormatter, SetZeroDurationText), C_StringUtil.CreateSecondsFormatter, the
-- ActionButtonSpellAlertTemplate glow (Blizzard_ActionBar/Shared/ActionButtonSpellAlerts.xml).
local _, ns = ...
local Looks = ns.Looks

local Widgets = {}
ns.Widgets = Widgets

local isSecret = issecretvalue or function() return false end

-- Something that may fail on a client where a declared API is missing: the display goes on without it.
local function Try(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

----------------------------------------------------------------------------------------------------
-- Shared pieces
----------------------------------------------------------------------------------------------------

-- A timer text that counts down by itself. Returns the binding or nil when the client lacks it.
local function MakeTimerBinding(fontString)
    local util = C_DurationUtil
    if not util or not util.CreateDurationTextBinding then return nil end
    local ok, binding = Try(util.CreateDurationTextBinding)
    if not ok or not binding then return nil end
    Try(binding.SetToDefaults, binding)
    if C_StringUtil and C_StringUtil.CreateSecondsFormatter then
        local okF, formatter = Try(C_StringUtil.CreateSecondsFormatter)
        if okF and formatter then
            Try(formatter.SetDefaultAbbreviation, formatter, Enum and Enum.SecondsFormatterAbbreviation and Enum.SecondsFormatterAbbreviation.OneLetter or 1)
            Try(formatter.SetDesiredUnitCount, formatter, 1)
            Try(binding.SetFormatter, binding, formatter)
        end
    end
    Try(binding.SetZeroDurationText, binding, "")
    Try(binding.SetExpiredText, binding, "")
    Try(binding.SetFontString, binding, fontString)
    return binding
end

-- Feeds a duration object to a binding; a nil duration clears the text.
local function BindDuration(binding, fontString, duration)
    if not binding then
        if fontString then fontString:SetText("") end
        return false
    end
    if duration == nil then
        Try(binding.SetEnabled, binding, false)
        if fontString then fontString:SetText("") end
        return true
    end
    local ok = Try(binding.SetDuration, binding, duration)
    if ok then Try(binding.SetEnabled, binding, true) end
    return ok
end

-- A proc glow from Blizzard's own template, created on demand; ours, never the alert manager's.
local function Glow(frame, on)
    if on and not frame.ctxGlow then
        local ok, glow = Try(CreateFrame, "Frame", nil, frame, "ActionButtonSpellAlertTemplate")
        if not ok or not glow then return end
        local w, h = frame:GetSize()
        glow:SetSize((w or 36) * 1.4, (h or 36) * 1.4)
        glow:SetPoint("CENTER")
        glow:Hide()
        frame.ctxGlow = glow
    end
    local glow = frame.ctxGlow
    if not glow then return end
    -- The template's animation groups; nil when the template changed (or in the headless stubs).
    local start = rawget(glow, "ProcStartAnim")
    local loop = rawget(glow, "ProcLoop")
    if on and not glow:IsShown() then
        glow:Show()
        if type(start) == "table" then Try(start.Play, start) end
    elseif not on and glow:IsShown() then
        if type(start) == "table" then Try(start.Stop, start) end
        if type(loop) == "table" then Try(loop.Stop, loop) end
        glow:Hide()
    end
end

-- A value that may be secret goes to SetText untouched (a secret sink); nil clears.
local function SetCount(fontString, answer)
    if not fontString then return end
    local v = answer and (answer.value ~= nil and answer.value or answer.secret)
    if v == nil then fontString:SetText("") return end
    if not isSecret(v) and (v == 0 or v == 1) then fontString:SetText("") return end
    Try(fontString.SetText, fontString, v)
end

----------------------------------------------------------------------------------------------------
-- Icon
----------------------------------------------------------------------------------------------------

local IconMixin = {}

function IconMixin:SetLook(look)
    self.look = look
    local size = look.size or 36
    self:SetSize(size, size)
    self:SetAlpha(look.alpha or 1)
    local zoom = look.zoom or 0
    self.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    self.icon:SetDesaturated(look.desaturate and true or false)
    self.icon:SetVertexColor(Looks.Color(look.color))
    Looks.ApplyBorder(self, look.border)
    local swipe = look.swipe or {}
    self.cooldown:SetDrawSwipe(swipe.show ~= false)
    self.cooldown:SetReverse(swipe.reverse and true or false)
    self.cooldown:SetDrawEdge(swipe.edge ~= false)
    if swipe.color then Try(self.cooldown.SetSwipeColor, self.cooldown, Looks.Color(swipe.color)) end
    local timer = look.timer or {}
    Looks.ApplyFont(self.timer, timer)
    self.timer:ClearAllPoints()
    self.timer:SetPoint(timer.point or "CENTER", 0, 0)
    self.timer:SetShown(timer.show ~= false)
    local stacks = look.stacks or {}
    Looks.ApplyFont(self.stacks, stacks)
    self.stacks:ClearAllPoints()
    self.stacks:SetPoint(stacks.point or "BOTTOMRIGHT", -2, 2)
    self.stacks:SetShown(stacks.show ~= false)
    Glow(self, look.glow and true or false)
    if self.ctxGlow then self.ctxGlow:SetSize(size * 1.4, size * 1.4) end
end

function IconMixin:SetTextureID(texture)
    if texture ~= self.textureID then
        self.textureID = texture
        if texture then self.icon:SetTexture(texture) else self.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
    end
end

-- SetDuration(durationObject, fresh): the engine runs the swipe and the text; nil clears both.
function IconMixin:SetDuration(duration, fresh)
    if duration == nil then
        Try(self.cooldown.Clear, self.cooldown)
        BindDuration(self.binding, self.timer, nil)
        return
    end
    if not Try(self.cooldown.SetCooldownFromDurationObject, self.cooldown, duration, fresh ~= false) then
        Try(self.cooldown.Clear, self.cooldown)
    end
    if (self.look and self.look.timer and self.look.timer.show ~= false) then
        if not BindDuration(self.binding, self.timer, duration) then
            Try(self.cooldown.SetHideCountdownNumbers, self.cooldown, false)
        end
    end
end

function IconMixin:SetStacks(answer) SetCount(self.stacks, answer) end

-- SetInRange(inRange): a plain false tints the icon with the look's out-of-range color.
function IconMixin:SetInRange(inRange)
    if inRange == false and self.look and self.look.outOfRange then
        self.icon:SetVertexColor(Looks.Color(self.look.outOfRange.color))
    elseif self.look then
        self.icon:SetVertexColor(Looks.Color(self.look.color))
    end
end

function Widgets.Icon(parent, name)
    local f = CreateFrame("Frame", name, parent)
    for k, v in pairs(IconMixin) do f[k] = v end
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    local ok, cd = Try(CreateFrame, "Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown = (ok and cd) or CreateFrame("Cooldown", nil, f)
    f.cooldown:SetAllPoints()
    Try(f.cooldown.SetHideCountdownNumbers, f.cooldown, true)
    local text = CreateFrame("Frame", nil, f)
    text:SetAllPoints()
    text:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
    f.timer = text:CreateFontString(nil, "OVERLAY")
    f.stacks = text:CreateFontString(nil, "OVERLAY")
    f.binding = MakeTimerBinding(f.timer)
    return f
end

----------------------------------------------------------------------------------------------------
-- Bar
----------------------------------------------------------------------------------------------------

local BarMixin = {}

function BarMixin:SetLook(look)
    self.look = look
    local w, h = look.width or 180, look.height or 18
    self:SetSize(w, h)
    self:SetAlpha(look.alpha or 1)
    local showIcon = look.icon ~= false
    self.icon:SetShown(showIcon)
    self.icon:SetSize(h, h)
    self.bar:ClearAllPoints()
    self.bar:SetPoint("TOPRIGHT")
    self.bar:SetPoint("BOTTOMLEFT", showIcon and (h + 1) or 0, 0)
    self.bar:SetStatusBarTexture(Looks.Media("statusbar", look.texture) or Looks.TEXTURES["Blizzard"])
    self.bar:SetStatusBarColor(Looks.Color(look.color))
    self.bg:SetVertexColor(Looks.Color(look.background))
    Looks.ApplyBorder(self, look.border)
    self.spark:SetShown(look.spark ~= false)
    self.spark:SetSize(10, h * 1.8)
    Looks.ApplyFont(self.name, look.text or {})
    self.name:SetShown(not look.text or look.text.show ~= false)
    Looks.ApplyFont(self.timer, look.timer or {})
    self.timer:SetShown(not look.timer or look.timer.show ~= false)
    Glow(self, look.glow and true or false)
    if self.ctxGlow then self.ctxGlow:SetSize(w * 1.1, h * 2.2) end
end

function BarMixin:SetTextureID(texture)
    if texture then self.icon:SetTexture(texture) end
end

function BarMixin:SetName(text) self.name:SetText(text or "") end

-- SetDuration(durationObject): the engine fills the bar from the remaining time; nil empties it.
function BarMixin:SetDuration(duration)
    if duration == nil then
        self.bar:SetMinMaxValues(0, 1)
        self.bar:SetValue(0)
        BindDuration(self.binding, self.timer, nil)
        return
    end
    local E = Enum or {}
    local interpolation = E.StatusBarInterpolation and E.StatusBarInterpolation.Immediate or 0
    local direction = E.StatusBarTimerDirection and E.StatusBarTimerDirection.RemainingTime or 1
    if not Try(self.bar.SetTimerDuration, self.bar, duration, interpolation, direction) then
        self.bar:SetMinMaxValues(0, 1)
        self.bar:SetValue(0)
    end
    BindDuration(self.binding, self.timer, duration)
end

-- SetPlainTime(remaining, total): the Lua fallback when there is no duration object.
function BarMixin:SetPlainTime(remaining, total)
    if remaining == nil or total == nil or total <= 0 then return self:SetDuration(nil) end
    self.bar:SetMinMaxValues(0, total)
    self.bar:SetValue(remaining)
    if not self.binding then self.timer:SetText(string.format("%.1f", remaining)) end
end

function BarMixin:SetColor(r, g, b, a)
    self.bar:SetStatusBarColor(r, g, b, a or 1)
end

-- SetColorFromCurve(duration, colorCurve): the engine picks the color from the remaining time
-- (Grid2's technique, reported): secret-safe. Returns false when the client refused.
function BarMixin:SetColorFromCurve(duration, curve)
    if not duration or not curve or not duration.EvaluateRemainingDuration then return false end
    local ok, color = Try(duration.EvaluateRemainingDuration, duration, curve)
    if not ok or color == nil then return false end
    if type(color) == "table" and color.GetRGBA then
        local okC, r, g, b, a = Try(color.GetRGBA, color)
        if okC then return Try(self.bar.SetStatusBarColor, self.bar, r, g, b, a) end
        return false
    end
    return false
end

function Widgets.Bar(parent, name)
    local f = CreateFrame("Frame", name, parent)
    for k, v in pairs(BarMixin) do f[k] = v end
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetMinMaxValues(0, 1)
    f.bar:SetValue(0)
    f.bg = f.bar:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    f.spark = f.bar:CreateTexture(nil, "OVERLAY")
    f.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    f.spark:SetBlendMode("ADD")
    f.spark:SetPoint("CENTER", f.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    f.name = f.bar:CreateFontString(nil, "OVERLAY")
    f.name:SetPoint("LEFT", 4, 0)
    f.timer = f.bar:CreateFontString(nil, "OVERLAY")
    f.timer:SetPoint("RIGHT", -4, 0)
    f.binding = MakeTimerBinding(f.timer)
    return f
end

Widgets.Glow = Glow
