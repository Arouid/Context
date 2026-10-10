-- Headless test for Context, run by /wow-addon-dev:check without the game.
--
-- It loads the addon's files the way the .toc does, with the bits of the game API they touch
-- stubbed, then checks the /context command, the pure condition evaluator (spec criterion 6:
-- AND/OR/NOT, comparisons, nil propagation, the A-E classification) and the three-value answers of
-- the sources, with SECRET STAND-INS: a switch turns the stubbed game "restricted", and the values
-- that would be secret in a fight become stand-in tables that issecretvalue recognizes. Any
-- arithmetic or ordering on a stand-in raises, as it would in game.
local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) printed[#printed + 1] = text end }
-- A frame stub that accepts any method and remembers scripts, events, shown state and a few sizes.
local frames = {}
local function Stub(kind)
    local f = { scripts = {}, events = {}, kind = kind, shown = true, calls = {} }
    return setmetatable(f, { __index = function(self, k)
        if k == "RegisterEvent" or k == "RegisterUnitEvent" then return function(s, e) s.events[e] = true end end
        if k == "SetScript" or k == "HookScript" then return function(s, name, fn) s.scripts[name] = fn end end
        if k == "Show" then return function(s) s.shown = true end end
        if k == "Hide" then return function(s) s.shown = false end end
        if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
        if k == "IsShown" then return function(s) return s.shown end end
        if k == "SetSize" then return function(s, w, h) s.w, s.h = w, h end end
        if k == "GetSize" then return function(s) return s.w or 36, s.h or 36 end end
        if k == "GetFrameLevel" then return function() return 1 end end
        if k == "GetCenter" then return function() return 500, 400 end end
        if k == "CreateTexture" or k == "CreateFontString" or k == "GetStatusBarTexture" then return function() return Stub(k) end end
        if type(k) == "string" and k:match("^%u") then
            return function(s, ...) s.calls[k] = (s.calls[k] or 0) + 1; s.last = s.last or {}; s.last[k] = { ... } end
        end
    end })
end
CreateFrame = function(kind, name, parent, template)
    local f = Stub(kind)
    f.template = template
    frames[#frames + 1] = f
    return f
end
UIParent = Stub("UIParent")
SlashCmdList = {}
GetLocale = function() return "enUS" end
InCombatLockdown = function() return false end
UnitExists = function() return false end
UnitClass = function() return "Mage", "MAGE" end
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a, GetRGBA = function(c) return c.r, c.g, c.b, c.a end } end
local now = 1000
GetTime = function() return now end

-- Secret stand-ins. A stand-in is a table whose metatable blocks arithmetic and concatenation; Lua
-- 5.1 itself raises on `<` between a table and a number. issecretvalue knows them all.
local standIns = setmetatable({}, { __mode = "k" })
local function Boom() error("a secret value was used in arithmetic, concatenation or a comparison") end
local secretMeta = { __add = Boom, __sub = Boom, __mul = Boom, __div = Boom, __concat = Boom, __lt = Boom, __le = Boom }
local function Secret(label)
    local s = setmetatable({ label = label }, secretMeta)
    standIns[s] = true
    return s
end
issecretvalue = function(v) return standIns[v] == true end
canaccessvalue = function(v) return standIns[v] ~= true end

local ns = {}
for _, file in ipairs({ "Locales/enUS.lua", "Context.lua", "Conditions.lua", "Sources.lua", "Probe.lua",
                         "Looks.lua", "Widgets.lua", "Displays.lua", "Groups.lua", "Preset.lua", "CooldownManager.lua",
                         "TestGuideSteps.lua", "TestGuide.lua" }) do
    assert(loadfile(WORKSPACE_ROOT .. "/Context/" .. file))("Context", ns)
end

check(SLASH_CONTEXT1 == "/context", "the /context command is registered")
SlashCmdList["CONTEXT"]("version")
check(printed[1] ~= nil and printed[1]:find("version 0.1.0", 1, true) ~= nil, "/context version prints the version")

----------------------------------------------------------------------------------------------------
-- The pure evaluator
----------------------------------------------------------------------------------------------------
local E = ns.Conditions.Evaluate
local function Leaf(test, compare, value, way) return { test = test, compare = compare, value = value, way = way } end
local function And(...) return { op = "and", conditions = { ... } } end
local function Or(...) return { op = "or", conditions = { ... } } end
local function Not(c) return { op = "not", condition = c } end

local inputs = {
    ready = true,
    onCooldown = false,
    remaining = 4.5,
    stacks = 3,
    name = "Clearcasting",
    unknown = nil,
    hiddenRemaining = Secret("remaining"),
    answerPlain = { value = 2, way = "A", hidden = false, reason = "charges" },
    answerHidden = { value = nil, way = "D", hidden = true, reason = "hidden", secret = Secret("x") },
    answerUnknown = { value = nil, way = "E", hidden = false, reason = "asked-hidden" },
    answerEvent = { value = true, way = "B", hidden = false, reason = "range-event" },
}

-- Leaves and comparisons on plain values.
local r = E(Leaf("ready"), inputs)
check(r.state == true and r.visualOnly == false and r.way == "A", "a plain true input without a compare is true (way A by default)")
r = E(Leaf("onCooldown"), inputs)
check(r.state == false and r.visualOnly == false, "a plain false input is false")
check(E(Leaf("ready", "==", true), inputs).state == true, "== true")
check(E(Leaf("ready", "==", false), inputs).state == false, "== false on a true input is false")
check(E(Leaf("ready", "~=", false), inputs).state == true, "~=")
check(E(Leaf("remaining", "<", 5), inputs).state == true, "< on numbers")
check(E(Leaf("remaining", "<=", 4.5), inputs).state == true, "<=")
check(E(Leaf("remaining", ">", 5), inputs).state == false, ">")
check(E(Leaf("remaining", ">=", 4.5), inputs).state == true, ">=")
check(E(Leaf("stacks", ">=", 3), inputs).state == true, "stacks >= 3")
check(E(Leaf("name", "==", "Clearcasting"), inputs).state == true, "strings compare with ==")
r = E(Leaf("name", "<", 5), inputs)
check(r.state == nil and r.visualOnly == false and r.reason == "incomparable", "a string against a number can't be ordered: nil, not visual-only")
r = E(Leaf("ready", "<", true), inputs)
check(r.state == nil and r.reason == "incomparable", "booleans can't be ordered")
r = E(Leaf("remaining", "between", 1), inputs)
check(r.state == nil and r.reason == "bad-compare", "an unknown operator gives nil with a reason")
r = E(Leaf("remaining", nil, 4.5), inputs)
check(r.state == true, "a value without an operator means ==")

-- Nil propagation: an unknown input is nil but not visual-only.
r = E(Leaf("unknown", "==", true), inputs)
check(r.state == nil and r.visualOnly == false and r.reason == "unknown", "a missing input is nil, not visual-only")
r = E(Leaf("answerUnknown", "==", true), inputs)
check(r.state == nil and r.visualOnly == false and r.way == "E" and r.reason == "asked-hidden", "an unknown answer keeps its way (E) and reason")

-- Hidden inputs: visual-only, way D, never compared.
r = E(Leaf("hiddenRemaining", "<", 5), inputs)
check(r.state == nil and r.visualOnly == true and r.way == "D" and r.reason == "hidden", "a secret stand-in is visual-only (way D), with no comparison")
r = E(Leaf("answerHidden", ">=", 1), inputs)
check(r.state == nil and r.visualOnly == true and r.way == "D", "a hidden answer is visual-only (way D)")
r = E(Leaf("remaining", "<", Secret("threshold")), inputs)
check(r.state == nil and r.visualOnly == true, "a secret threshold is visual-only too")
r = E(Leaf("ready", nil, nil, "D"), inputs)
check(r.state == nil and r.visualOnly == true, "a condition declared way D is visual-only whatever the input")

-- Answers carry their way into the result.
r = E(Leaf("answerPlain", ">=", 2), inputs)
check(r.state == true and r.way == "A", "a plain answer compares and keeps way A")
r = E(Leaf("answerEvent"), inputs)
check(r.state == true and r.way == "B", "an event answer keeps way B")
r = E(Leaf("answerEvent", nil, nil, "C"), inputs)
check(r.way == "C", "the condition's own way wins over the input's")

-- AND / OR / NOT with three values.
check(E(And(Leaf("ready"), Leaf("remaining", "<", 5)), inputs).state == true, "AND of two trues")
r = E(And(Leaf("ready"), Leaf("onCooldown")), inputs)
check(r.state == false and r.visualOnly == false, "AND with a false is false")
r = E(And(Leaf("ready"), Leaf("hiddenRemaining", "<", 5)), inputs)
check(r.state == nil and r.visualOnly == true and r.way == "A,D", "AND of a true and a hidden is visual-only, ways joined")
r = E(And(Leaf("onCooldown"), Leaf("hiddenRemaining", "<", 5)), inputs)
check(r.state == false and r.visualOnly == false, "AND settled false by a plain child is Lua-decided even with a hidden sibling")
r = E(And(Leaf("ready"), Leaf("unknown")), inputs)
check(r.state == nil and r.visualOnly == false and r.reason == "unknown", "AND with an unknown is unknown, not visual-only")
check(E(Or(Leaf("onCooldown"), Leaf("ready")), inputs).state == true, "OR with a true is true")
check(E(Or(Leaf("onCooldown"), Leaf("remaining", ">", 10)), inputs).state == false, "OR of two falses is false")
r = E(Or(Leaf("ready"), Leaf("hiddenRemaining")), inputs)
check(r.state == true and r.visualOnly == false, "OR settled true by a plain child is Lua-decided even with a hidden sibling")
r = E(Or(Leaf("onCooldown"), Leaf("hiddenRemaining")), inputs)
check(r.state == nil and r.visualOnly == true, "OR of a false and a hidden is visual-only")
check(E(Not(Leaf("ready")), inputs).state == false, "NOT true")
check(E(Not(Leaf("onCooldown")), inputs).state == true, "NOT false")
r = E(Not(Leaf("hiddenRemaining")), inputs)
check(r.state == nil and r.visualOnly == true and r.way == "D", "NOT hidden stays hidden")
r = E(Not(Leaf("unknown")), inputs)
check(r.state == nil and r.visualOnly == false, "NOT unknown stays unknown")
r = E(Not(And(Leaf("ready"), Or(Leaf("onCooldown"), Leaf("stacks", ">=", 3)))), inputs)
check(r.state == false, "nested NOT(AND(true, OR(false, true))) is false")
check(E({ op = "not", conditions = { Leaf("ready") } }, inputs).state == false, "NOT accepts a one-element conditions list")

-- Degenerate shapes never raise.
check(E(And(), inputs).state == nil and E(And(), inputs).reason == "empty", "an empty AND is unknown")
check(E({ op = "xor", conditions = { Leaf("ready") } }, inputs).reason == "bad-op", "an unknown op is refused")
check(E({ compare = "==", value = 1 }, inputs).reason == "no-test", "a leaf without a test is refused")
check(E(nil, inputs).state == nil and E("x", inputs).reason == "no-condition", "a non-table condition is refused")
check(E(Leaf("ready"), nil).state == nil, "no inputs at all is unknown")

-- Validate and CanFireActions.
check(ns.Conditions.Validate(And(Leaf("ready"), Not(Leaf("stacks", ">=", 2, "A")))) == true, "a good tree validates")
local ok, why = ns.Conditions.Validate(Leaf("ready", "between", 1))
check(ok == false and why == "bad-compare", "a bad operator fails validation")
ok, why = ns.Conditions.Validate(Leaf("ready", "==", true, "Z"))
check(ok == false and why == "bad-way", "a bad way fails validation")
ok, why = ns.Conditions.Validate({ op = "not", conditions = { Leaf("a"), Leaf("b") } })
check(ok == false and why == "not-takes-one", "NOT with two children fails validation")
ok, why = ns.Conditions.Validate(And())
check(ok == false and why == "empty", "an empty AND fails validation")
check(ns.Conditions.CanFireActions(E(Leaf("ready"), inputs)) == true, "a Lua-decided result may fire actions")
check(ns.Conditions.CanFireActions(E(Leaf("hiddenRemaining"), inputs)) == false, "a visual-only result may not fire actions")
check(ns.Conditions.CanFireActions(E(Leaf("unknown"), inputs)) == false, "an unknown result may not fire actions")

----------------------------------------------------------------------------------------------------
-- The sources, against a stubbed game with a "restricted" switch
----------------------------------------------------------------------------------------------------
local S = ns.Sources
local restricted = false          -- the switch: true = in combat, cooldown and aura numbers secret
local neverSecretAuras = { [12536] = true }   -- Clearcasting: flagged never secret in this fake game
local function Hide(v) if restricted then return Secret(v) end return v end
local calls = {}
local function Count(name) calls[name] = (calls[name] or 0) + 1 end

local FROST_NOVA, BLINK, CLEARCASTING = 122, 1953, 12536
local cooldowns = { [FROST_NOVA] = { startTime = 990, duration = 25, isEnabled = true, isActive = true, isOnGCD = false },
                    [BLINK] = { startTime = 0, duration = 0, isEnabled = true, isActive = false } }
local names = { [FROST_NOVA] = "Frost Nova", [BLINK] = "Blink", [CLEARCASTING] = "Clearcasting" }
local ids = {}
for id, name in pairs(names) do ids[name] = id end
local function SpellID(spell) return type(spell) == "number" and spell or ids[spell] end
local durations = {}
C_Spell = {
    GetSpellCooldown = function(spell)
        local cd = cooldowns[SpellID(spell)]
        if not cd then return nil end
        return { startTime = Hide(cd.startTime), duration = Hide(cd.duration), isEnabled = cd.isEnabled,
                 isActive = cd.isActive, isOnGCD = cd.isOnGCD, modRate = 1 }
    end,
    GetSpellCooldownDuration = function(spell, ignoreGCD)
        local d = { spell = SpellID(spell), ignoreGCD = ignoreGCD, HasSecretValues = function() return restricted end }
        durations[#durations + 1] = d
        return d
    end,
    GetSpellCharges = function(spell)
        if SpellID(spell) ~= BLINK then return nil end
        return { currentCharges = Hide(1), maxCharges = 2, cooldownStartTime = Hide(995), cooldownDuration = Hide(15), isActive = true }
    end,
    GetSpellChargeDuration = function() return { charge = true } end,
    IsSpellUsable = function(spell)
        if not names[SpellID(spell)] then return nil end
        return SpellID(spell) ~= BLINK, SpellID(spell) == BLINK
    end,
    EnableSpellRangeCheck = function(spell, enable) Count("EnableSpellRangeCheck"); calls.lastEnable = enable end,
    IsSpellInRange = function(spell) if SpellID(spell) == FROST_NOVA then return false end return nil end,
    GetSpellInfo = function(spell) local id = SpellID(spell); if id then return { spellID = id, name = names[id] } end end,
    GetSpellName = function(spell) return names[SpellID(spell)] end,
}
C_Secrets = {
    ShouldSpellCooldownBeSecret = function() return restricted end,
    ShouldAurasBeSecret = function() return restricted end,
    ShouldSpellAuraBeSecret = function(id) return restricted and not neverSecretAuras[id] end,
    ShouldUnitAuraIndexBeSecret = function(unit, index) return restricted and index > 1 end,
    ShouldUnitAuraInstanceBeSecret = function() return false end,
}

-- Cooldowns out of combat: everything plain (way A), remaining computed with the clock.
local cd = S.SpellCooldown(FROST_NOVA, now)
check(cd and cd.onCooldown.value == true and cd.onCooldown.way == "A", "Frost Nova on cooldown: isActive, way A")
check(cd.remaining.value == 15 and cd.remaining.way == "A" and cd.remaining.hidden == false, "remaining = start + duration - now, plain")
check(cd.enabled.value == true, "enabled")
check(cd.onGCD.value == nil and cd.onGCD.reason == "gcd-outside-event", "isOnGCD is not trusted outside SPELL_UPDATE_COOLDOWN")
check(S.SpellCooldown(FROST_NOVA, now, true).onGCD.value == false, "isOnGCD is read inside the event")
check(cd.duration ~= nil and cd.duration.ignoreGCD == true, "the duration object ignores the GCD")
cd = S.SpellCooldown(BLINK, now)
check(cd.onCooldown.value == false and cd.remaining.value == 0, "Blink ready: not on cooldown, 0 remaining")
check(S.SpellCooldown(99999, now) == nil, "an unknown spell gives nil, no error")
check(S.SpellCooldown("Frost Nova", now).onCooldown.value == true, "a spell by name works")

-- Cooldowns in combat: isActive stays plain (A), the numbers go hidden (asked first: E).
restricted = true
cd = S.SpellCooldown(FROST_NOVA, now)
check(cd.onCooldown.value == true and cd.onCooldown.way == "A" and cd.onCooldown.hidden == false, "in combat isActive is still plain (A)")
check(cd.remaining.value == nil and cd.remaining.way == "E" and cd.remaining.hidden == true and cd.remaining.reason == "asked-hidden", "in combat the remaining time is not computed: asked first (E), hidden")
r = E(Leaf("remaining", "<", 5), { remaining = cd.remaining })
check(r.state == nil and r.visualOnly == true and r.way == "D", "an asked-hidden answer makes the condition visual-only (D)")
check(cd.duration ~= nil and cd.duration:HasSecretValues() == true, "the duration object is still there for the widget")
-- Without the predicate the secret stand-in itself is detected (D), never subtracted.
local pred = C_Secrets.ShouldSpellCooldownBeSecret
C_Secrets.ShouldSpellCooldownBeSecret = nil
C_Secrets.ShouldCooldownsBeSecret = nil
cd = S.SpellCooldown(FROST_NOVA, now)
check(cd.remaining.value == nil and cd.remaining.hidden == true and cd.remaining.way == "D" and issecretvalue(cd.remaining.secret), "without a predicate a secret number is detected: hidden (D), kept for the engine")
C_Secrets.ShouldSpellCooldownBeSecret = pred
r = E(Leaf("remaining", "<", 5), { remaining = cd.remaining })
check(r.state == nil and r.visualOnly == true, "a hidden source answer makes the condition visual-only")
restricted = false

-- Charges.
local ch = S.SpellCharges(BLINK)
check(ch and ch.max.value == 2 and ch.current.value == 1 and ch.recharging.value == true, "charges out of combat: max, current, recharging")
restricted = true
ch = S.SpellCharges(BLINK)
check(ch.max.value == 2 and ch.max.way == "A" and ch.recharging.value == true, "in combat maxCharges and isActive stay plain")
check(ch.current.value == nil and ch.current.hidden == true and ch.current.way == "D", "in combat currentCharges is hidden (D)")
check(ch.duration ~= nil and ch.duration.charge == true, "the recharge duration object is there")
restricted = false
check(S.SpellCharges(FROST_NOVA) == nil, "a spell without charges gives nil")

-- Usable.
local usable, noPower = S.SpellUsable(FROST_NOVA)
check(usable.value == true and noPower.value == false and usable.way == "A", "usable: plain booleans, way A")
usable, noPower = S.SpellUsable(BLINK)
check(usable.value == false and noPower.value == true, "not usable for lack of power")
usable = S.SpellUsable(99999)
check(usable.value == nil and usable.reason == "unknown-spell", "unknown spell: can't say")

-- Range: fallback first (A), then the event (B).
r = S.SpellInRange(FROST_NOVA)
check(r.value == false and r.way == "A" and r.reason == "IsSpellInRange", "with no watch IsSpellInRange answers (A)")
r = S.SpellInRange(BLINK)
check(r.value == nil and r.reason == "no-range-check", "a rangeless spell can't say")
check(S.WatchRange(FROST_NOVA) == true and calls.EnableSpellRangeCheck == 1 and calls.lastEnable == true, "WatchRange asks the game once")
local sourcesFrame
for _, f in ipairs(frames) do if f.events["SPELL_RANGE_CHECK_UPDATE"] then sourcesFrame = f end end
check(sourcesFrame ~= nil, "Sources registers SPELL_RANGE_CHECK_UPDATE")
sourcesFrame.scripts.OnEvent(sourcesFrame, "SPELL_RANGE_CHECK_UPDATE", FROST_NOVA, true, true)
r = S.SpellInRange(FROST_NOVA)
check(r.value == true and r.way == "B" and r.reason == "range-event", "after the event the answer is the event's (B)")
sourcesFrame.scripts.OnEvent(sourcesFrame, "SPELL_RANGE_CHECK_UPDATE", FROST_NOVA, false, false)
r = S.SpellInRange(FROST_NOVA)
check(r.value == false and r.way == "A", "checksRange = false forgets the event answer: back to the fallback")
sourcesFrame.scripts.OnEvent(sourcesFrame, "SPELL_RANGE_CHECK_UPDATE", FROST_NOVA, Secret("inRange"), true)
check(S.SpellInRange(FROST_NOVA).way == "A", "a secret isInRange is never stored")
sourcesFrame.scripts.OnEvent(sourcesFrame, "SPELL_RANGE_CHECK_UPDATE", "Frost Nova", true, true)
check(S.SpellInRange(FROST_NOVA).way == "B", "an event keyed by name reaches a watch by ID")
S.WatchRange(FROST_NOVA, false)
check(calls.lastEnable == false and S.SpellInRange(FROST_NOVA).way == "A", "unwatching disables the check and drops the answer")
check(S.WatchRange(nil) == false, "WatchRange without a spell does nothing")

-- Auras.
local auras = {}   -- unit -> list of AuraData
local function AuraData(id, stacks, expiration)
    return { auraInstanceID = 100 + id, spellId = id, name = names[id], applications = Hide(stacks),
             duration = Hide(15), expirationTime = Hide(expiration) }
end
C_UnitAuras = {
    GetUnitAuraBySpellID = function(unit, id)
        Count("GetUnitAuraBySpellID")
        for _, a in ipairs(auras[unit] or {}) do if a.spellId == id then return a end end
    end,
    GetAuraDataBySpellName = function(unit, name)
        Count("GetAuraDataBySpellName")
        if restricted then return nil end
        for _, a in ipairs(auras[unit] or {}) do if a.name == name then return a end end
    end,
    GetAuraDuration = function(unit, instanceID) Count("GetAuraDuration"); return { aura = instanceID } end,
    GetAuraDataByIndex = function(unit, index)
        Count("GetAuraDataByIndex")
        if restricted and index > 1 then error("Auras cannot be accessed when secret while tainted") end
        return (auras[unit] or {})[index]
    end,
}

-- Out of combat: present by ID, absent by name, remaining computed.
auras.player = { AuraData(CLEARCASTING, 1, 1010) }
local a = S.Aura("player", CLEARCASTING, "HELPFUL", now)
check(a.present.value == true and a.present.way == "A", "Clearcasting present by spell ID (A)")
check(a.stacks.value == 1 and a.remaining.value == 10 and a.remaining.way == "A", "stacks and remaining plain")
check(a.duration ~= nil and a.duration.aura == 100 + CLEARCASTING and a.auraInstanceID == 100 + CLEARCASTING, "the aura duration object is fetched by instance ID")
a = S.Aura("player", "Clearcasting", "HELPFUL", now)
check(a.present.value == true, "present by name")
a = S.Aura("player", FROST_NOVA, "HELPFUL", now)
check(a.present.value == false and a.present.way == "A" and a.present.reason == "absent-by-name", "absent: by NAME, not by ID alone")
a = S.Aura("player", { id = 99999 }, "HELPFUL", now)
check(a.present.value == nil and a.present.reason == "absent-by-id-only", "an ID with no name can't prove absence")
auras.player[1].duration = 0
a = S.Aura("player", CLEARCASTING, "HELPFUL", now)
check(a.remaining.value == nil and a.remaining.reason == "no-expiration", "a permanent aura has no remaining time")
auras.player[1].duration = 15

-- In combat: a never-secret spell is still read by ID; others are not even asked for by name.
restricted = true
calls.GetUnitAuraBySpellID, calls.GetAuraDataBySpellName = 0, 0
auras.player = { AuraData(CLEARCASTING, 2, 1012) }
a = S.Aura("player", CLEARCASTING, "HELPFUL", now)
check(a.present.value == true and a.present.way == "A" and calls.GetUnitAuraBySpellID == 1, "in combat a never-secret aura is still found by ID (A)")
check(a.stacks.value == nil and a.stacks.hidden == true and a.stacks.way == "D", "its stacks are hidden (D)")
check(a.remaining.value == nil and a.remaining.hidden == true and a.remaining.way == "D", "its remaining time is hidden (D), never subtracted")
check(a.duration ~= nil, "the duration object still comes")
a = S.Aura("player", FROST_NOVA, "HELPFUL", now)
check(a.present.value == nil and a.present.way == "E" and a.present.hidden == true and a.present.reason == "asked-hidden", "in combat a secret-flagged aura is asked about first (E): can't say, hidden")
check(calls.GetUnitAuraBySpellID == 1 and calls.GetAuraDataBySpellName == 0, "neither the by-ID nor the by-name read was made for it")
auras.player = {}
a = S.Aura("player", CLEARCASTING, "HELPFUL", now)
check(a.present.value == nil and a.present.way == "E" and a.present.reason == "restricted", "in combat a never-secret aura not found by ID is 'can't say', never 'absent'")
check(calls.GetAuraDataBySpellName == 0, "no by-name read while auras are restricted")
r = E(Leaf("present", "==", true), { present = a.present })
check(r.state == nil and r.visualOnly == true, "a restricted presence is visual-only: an engine aura container can still show it")

-- Index walks ask per index and stop before the first hidden one.
auras.player = { AuraData(CLEARCASTING, 1, 1010), AuraData(FROST_NOVA, 1, 1010) }
local seen = {}
local complete, count = S.ScanAuras("player", "HELPFUL", function(aura) seen[#seen + 1] = aura.spellId end)
check(complete == false and count == 1 and seen[1] == CLEARCASTING and #seen == 1, "in combat the walk stops at the first hidden index without reading it")
restricted = false
seen = {}
complete, count = S.ScanAuras("player", "HELPFUL", function(aura) seen[#seen + 1] = aura.spellId end)
check(complete == true and count == 2 and #seen == 2, "out of combat the walk reads every index")
local predIndex = C_Secrets.ShouldUnitAuraIndexBeSecret
C_Secrets.ShouldUnitAuraIndexBeSecret = nil
complete, count = S.ScanAuras("player", "HELPFUL", function() end)
check(complete == false and count == 0, "without the per-index predicate no index is read at all")
C_Secrets.ShouldUnitAuraIndexBeSecret = predIndex

-- Weapon enchants.
Enum = { WeaponSlot = { MainHand = 0, OffHand = 1, Ranged = 2 } }
local enchants = { [0] = { { hasEnchant = true, enchantType = 0, timeLeft = 90000, charges = 3, enchantID = 25, enchantIconID = 1 } }, [1] = {} }
C_Item = { GetWeaponEnchantInfo = function(slot) return enchants[slot] end }
local w = S.WeaponEnchant(Enum.WeaponSlot.MainHand)
check(w.present.value == true and w.remaining.value == 90 and w.charges.value == 3 and w.enchantID == 25, "main hand enchant: present, 90 s, 3 charges")
w = S.WeaponEnchant(Enum.WeaponSlot.OffHand)
check(w.present.value == false and w.present.way == "A", "an empty list is 'no enchant' (A)")
w = S.WeaponEnchant(Enum.WeaponSlot.Ranged)
check(w.present.value == nil and w.present.reason == "no-list", "no list at all: can't say")
C_Item = nil
check(S.WeaponEnchant(0).present.value == nil, "without C_Item: can't say, no error")

-- A condition tree over real source answers: Frost Nova ready AND Clearcasting present.
auras.player = { AuraData(CLEARCASTING, 1, 1010) }
cooldowns[FROST_NOVA].isActive = false
local function Inputs()
    local nova = S.SpellCooldown(FROST_NOVA, now)
    return { novaOnCooldown = nova.onCooldown, novaRemaining = nova.remaining,
             clearcasting = S.Aura("player", CLEARCASTING, "HELPFUL", now).present }
end
local tree = And(Not(Leaf("novaOnCooldown")), Leaf("clearcasting", "==", true))
r = E(tree, Inputs())
check(r.state == true and ns.Conditions.CanFireActions(r), "out of combat: Frost Nova ready AND Clearcasting up is Lua-decided true")
cooldowns[FROST_NOVA].isActive = true
r = E(And(Leaf("novaRemaining", "<", 5), Leaf("clearcasting", "==", true)), Inputs())
check(r.state == false, "out of combat: 15 s left is not < 5")
restricted = true
r = E(And(Leaf("novaRemaining", "<", 5), Leaf("clearcasting", "==", true)), Inputs())
check(r.state == nil and r.visualOnly == true, "in combat the same tree is visual-only: the remaining time is hidden")
r = E(And(Not(Leaf("novaOnCooldown")), Leaf("clearcasting", "==", true)), Inputs())
check(r.state == false and r.visualOnly == false, "in combat 'ready' still decides from the never-secret isActive")
restricted = false

-- /context probe prints without touching a secret.
printed = {}
restricted = true
C_Item = { GetWeaponEnchantInfo = function(slot) return enchants[slot] end }
local okProbe, err = pcall(SlashCmdList["CONTEXT"], "probe")
check(okProbe, "/context probe runs in combat without raising: " .. tostring(err))
local function printedHas(text)
    for _, line in ipairs(printed) do if line:find(text, 1, true) then return true end end
    return false
end
check(printedHas("Frost Nova") and printedHas("Clearcasting") and printedHas("hidden (way E)"), "the probe names both spells and says what is hidden")
restricted = false
printed = {}
pcall(SlashCmdList["CONTEXT"], "probe Blink")
check(printedHas("Blink") and printedHas("charges"), "/context probe <spell> probes that spell, charges included")
printed = {}
SlashCmdList["CONTEXT"]("")
check(printedHas("/context probe"), "the help lists the probe command")

----------------------------------------------------------------------------------------------------
-- Looks (pure)
----------------------------------------------------------------------------------------------------
local Looks = ns.Looks
local base = Looks.Default("icon")
check(base.size == 36 and base.swipe.show == true and Looks.Default("bar").width == 180, "defaults per type")
local merged = Looks.Merge(base, { size = 44, swipe = { reverse = true }, color = { 1, 0, 0 } })
check(merged.size == 44 and merged.swipe.reverse == true and merged.swipe.show == true, "Merge is deep: untouched keys stay")
check(merged.color[1] == 1 and merged.color[2] == 0 and merged.color[4] == nil and base.color[4] == 1, "a color is replaced whole, the base untouched")
local resolved = Looks.Resolve("bar", { width = 200 }, { { color = { 1, 0.2, 0.2, 1 } }, { alpha = 0.5 } })
check(resolved.width == 200 and resolved.color[1] == 1 and resolved.alpha == 0.5 and resolved.height == 18, "Resolve: defaults, then the display's look, then each state's look")
check(Looks.Media("font", "Friz Quadrata") == "Fonts\\FRIZQT__.TTF" and Looks.Media("border", "None") == nil, "media falls back to the game's own files")
check(select(4, Looks.Color(nil)) == 1 and Looks.Color({ 0.5, 0.5, 0.5 }) == 0.5, "Color unpacks with a default alpha")

----------------------------------------------------------------------------------------------------
-- Displays: the pure parts
----------------------------------------------------------------------------------------------------
local D = ns.Displays
local A = S.Answer
local spellDef = { id = "t.nova", type = "icon", source = { kind = "spell", spell = "Frost Nova" },
    states = { { name = "ready", when = Leaf("ready", "==", true), look = { glow = true } },
               { name = "soon", when = Leaf("remaining", "<", 5), look = { color = { 1, 1, 0, 1 } } } } }
local snaps = { cooldown = { onCooldown = A(true, "A"), remaining = A(12, "A"), enabled = A(true, "A") },
                charges = { current = A(1, "A"), max = A(2, "A") }, usable = A(true, "A"), noPower = A(false, "A"), inRange = A(false, "B") }
local inp = D.Inputs(spellDef, snaps, { combat = false, hasTarget = true })
check(inp.ready.value == false and inp.ready.way == "A" and inp.onCooldown.value == true, "Inputs: ready is the flip of onCooldown")
check(inp.charges.value == 1 and inp.maxCharges.value == 2 and inp.inRange.value == false and inp.hasTarget == true, "Inputs: charges, range, extras")
snaps.cooldown.onCooldown = { value = nil, way = "E", hidden = true, reason = "asked-hidden" }
check(D.Inputs(spellDef, snaps).ready.hidden == true, "a hidden onCooldown gives a hidden ready, never flipped")
local auraDef = { id = "t.cc", type = "icon", source = { kind = "aura", spell = "Clearcasting" }, visibility = "whenPresent", states = {} }
inp = D.Inputs(auraDef, { aura = { present = A(false, "A"), stacks = A(nil, "A") } })
check(inp.missing.value == true and inp.present.value == false, "Inputs: missing is the flip of present")
inp = D.Inputs({ source = { kind = "enchant" } }, { enchant = { present = A(true, "A"), remaining = A(90, "A"), charges = A(3, "A") } })
check(inp.present.value == true and inp.remaining.value == 90 and inp.charges.value == 3, "Inputs: enchant")

-- Resolve: states, looks, visibility, and keeping the last Lua-decided state.
snaps.cooldown.onCooldown = A(false, "A")
snaps.cooldown.remaining = A(0, "A")
local states, looks, visible = D.Resolve(spellDef, D.Inputs(spellDef, snaps), nil)
check(states[1].active == true and states[2].active == true and #looks == 2 and visible == true, "Resolve: both states active, two looks, visible (always)")
snaps.cooldown.remaining = { value = nil, way = "D", hidden = true, secret = Secret("rem") }
states, looks = D.Resolve(spellDef, D.Inputs(spellDef, snaps), { true, true })
check(states[2].active == true and states[2].visualOnly == true and #looks == 2, "an undecidable state keeps its last value and is flagged visual-only")
states, looks = D.Resolve(spellDef, D.Inputs(spellDef, snaps), { true, false })
check(states[2].active == false and #looks == 1, "an undecidable state keeps a last 'false' too")
states = D.Resolve(spellDef, D.Inputs(spellDef, snaps), nil)
check(states[2].active == false, "with no history an undecidable state is inactive")

check(D.Visible(auraDef, { present = A(true, "A") }) == true and D.Visible(auraDef, { present = A(false, "A") }) == false, "whenPresent follows present")
check(D.Visible(auraDef, { present = { value = nil, way = "E", hidden = true } }) == nil, "a hidden presence can't decide visibility")
check(D.Visible({ visibility = "whenReady" }, { onCooldown = A(false, "A") }) == true and D.Visible({ visibility = "whenOnCooldown" }, { onCooldown = A(false, "A") }) == false, "whenReady / whenOnCooldown")
check(D.Visible({}, {}) == true, "no visibility means always")

local seconds, color = D.EngineThreshold({ when = Leaf("remaining", "<", 5), look = { color = { 1, 0, 0, 1 } } })
check(seconds == 5 and color[1] == 1, "EngineThreshold: remaining < 5 with a color only")
check(D.EngineThreshold({ when = Leaf("remaining", "<", 5), look = { color = { 1, 0, 0, 1 }, glow = true } }) == nil, "a glow in the look is not engine-drawable")
check(D.EngineThreshold({ when = Leaf("remaining", ">", 5), look = { color = { 1, 0, 0, 1 } } }) == nil, "> is not a threshold the curve draws")
check(D.EngineThreshold({ when = And(Leaf("remaining", "<", 5)), look = { color = { 1, 0, 0, 1 } } }) == nil, "a combination is not engine-drawable")
check(D.EngineThreshold({ when = Leaf("stacks", "<", 5), look = { color = { 1, 0, 0, 1 } } }) == nil, "only remaining time has a duration object")

----------------------------------------------------------------------------------------------------
-- Groups: layout math
----------------------------------------------------------------------------------------------------
local G = ns.Groups
local sizes = { { w = 36, h = 36 }, { w = 36, h = 36 }, { w = 20, h = 50 } }
local off, w, h = G.Positions(sizes, "RIGHT", 4)
check(off[1].x == 0 and off[2].x == 40 and off[3].x == 80 and w == 100 and h == 50, "RIGHT: x advances by width + spacing, height is the tallest")
off, w, h = G.Positions(sizes, "LEFT", 4)
check(off[1].x == 64 and off[3].x == 0 and w == 100, "LEFT mirrors the row")
off, w, h = G.Positions(sizes, "DOWN", 2)
check(off[1].y == 0 and off[2].y == 38 and off[3].y == 76 and h == 126 and w == 36, "DOWN: y advances")
off, w, h = G.Positions(sizes, "UP", 2)
check(off[1].y == 90 and off[3].y == 0 and h == 126, "UP mirrors the column")
off, w, h = G.Positions({}, "RIGHT", 4)
check(#off == 0 and w == 0 and h == 0, "an empty group has no size")

----------------------------------------------------------------------------------------------------
-- The mage preset validates
----------------------------------------------------------------------------------------------------
local groups, displays = ns.Preset.Mage()
local count = 0
for id, def in pairs(displays) do
    count = count + 1
    check(def.id == id and (def.type == "icon" or def.type == "bar") and def.source and def.source.kind, "preset display " .. id .. " has an id, a type and a source")
    for _, state in ipairs(def.states) do
        check(ns.Conditions.Validate(state.when) == true, "preset state " .. id .. "/" .. tostring(state.name) .. " validates")
    end
    if def.group then check(groups[def.group] ~= nil, "preset display " .. id .. " names a group that exists") end
end
check(count == 7 and #groups["mage.cooldowns"].children == 5, "7 displays, 5 in the cooldown group")
check(D.EngineThreshold(displays["mage.icebarrier"].states[1]) == 5, "the Ice Barrier 'low' state is engine-drawable")

----------------------------------------------------------------------------------------------------
-- Lifecycle with the stubbed game: install, start, refresh in both modes, edit mode, list, reset
----------------------------------------------------------------------------------------------------
ns.db = { schemaVer = 1, displays = {}, groups = {} }
local curves = 0
C_CurveUtil = { CreateColorCurve = function() curves = curves + 1; return { SetType = function() end, AddPoint = function() end } end }
C_Item = { GetWeaponEnchantInfo = function(slot) return enchants[slot] end }
C_DurationUtil = { CreateDurationTextBinding = function()
    return { SetToDefaults = function() end, SetFormatter = function() end, SetZeroDurationText = function() end, SetExpiredText = function() end,
             SetFontString = function() end, SetDuration = function(b, d) b.duration = d end, SetEnabled = function(b, e) b.enabled = e end }
end }
C_StringUtil = { CreateSecondsFormatter = function() return { SetDefaultAbbreviation = function() end, SetDesiredUnitCount = function() end } end }
Enum = { WeaponSlot = { MainHand = 0, OffHand = 1, Ranged = 2 }, StatusBarInterpolation = { Immediate = 0 }, StatusBarTimerDirection = { RemainingTime = 1 }, LuaCurveType = { Linear = 0 },
         SecondsFormatterAbbreviation = { OneLetter = 1 } }
-- Duration objects now answer the curve question too.
C_Spell.GetSpellCooldownDuration = function(spell, ignoreGCD)
    return { spell = SpellID(spell), ignoreGCD = ignoreGCD, HasSecretValues = function() return restricted end,
             EvaluateRemainingDuration = function() return CreateColor(1, 0.2, 0.2, 1) end }
end
C_UnitAuras.GetAuraDuration = function(unit, id)
    return { aura = id, EvaluateRemainingDuration = function() return CreateColor(0.25, 0.78, 0.92, 1) end }
end
names[11426], ids["Ice Barrier"] = "Ice Barrier", 11426
for _, n in ipairs({ "Ice Block", "Counterspell", "Evocation" }) do local id = 5000 + #n; names[id], ids[n] = n, id; cooldowns[id] = { startTime = 0, duration = 0, isEnabled = true, isActive = false } end
C_Spell.GetSpellTexture = function() return 135848 end

-- LibEditMode stubbed through LibStub: registrations and callbacks are recorded, nothing is drawn.
local lem = { frames = {}, callbacks = {}, editing = false }
function lem:AddFrame(frame, callback, default, name) self.frames[frame] = { callback = callback, default = default, name = name } end
function lem:RegisterCallback(event, fn) self.callbacks[event] = self.callbacks[event] or {}; table.insert(self.callbacks[event], fn) end
function lem:IsInEditMode() return self.editing end
local function StubLibStub() LibStub = function(name, silent) if name == "LibEditMode" then return lem end; assert(silent, "unknown library " .. name) end end
StubLibStub()

check(ns.Preset.AutoInstall() == true and ns.db.presetInstalled == "mage", "a mage with no displays gets the preset at login")
check(ns.Preset.AutoInstall() == false, "the preset is installed once")
check(#D.Order() == 7 and D.Get("mage.frostnova") ~= nil and D.Get("mage.icebarrier").frame.kind == "Frame", "every preset display has a widget")
auras.player = { AuraData(CLEARCASTING, 1, 1010), { auraInstanceID = 900, spellId = 11426, name = "Ice Barrier", applications = 0, duration = 60, expirationTime = 1003 } }
local okStart, errStart = pcall(D.Start)
check(okStart, "Displays.Start runs with the stubbed game: " .. tostring(errStart))
local cc = D.Get("mage.clearcasting")
check(cc.frame.shown == true and cc.states[1].active == true and cc.frame.ctxGlow ~= nil and cc.frame.ctxGlow.shown == true, "Clearcasting up: icon shown, state active, glow created and shown")
local ib = D.Get("mage.icebarrier")
check(ib.frame.shown == true and ib.states[1].active == true and ib.curve ~= nil and ib.curve ~= false, "Ice Barrier at 3 s: shown, 'low' active, a color curve built for the engine")
check(ib.frame.bar.calls.SetTimerDuration == 1 and ib.frame.binding.duration ~= nil, "the bar and its timer text got the duration object")
local nova = D.Get("mage.frostnova")
check(nova.frame.cooldown.calls.SetCooldownFromDurationObject == 1 and nova.frame.shown == true, "Frost Nova: the swipe got its duration object")
auras.player = {}
D.RefreshAll()
check(cc.frame.shown == false and cc.frame.ctxGlow.shown == false and ib.frame.shown == false, "procs gone: Clearcasting and Ice Barrier hidden, glow stopped")
-- In combat: nothing read that is hidden, nothing raises, the shown state is kept.
auras.player = { AuraData(CLEARCASTING, 1, 1010) }
D.RefreshAll()
check(cc.frame.shown == true, "Clearcasting back out of combat")
restricted = true
local okRefresh, errRefresh = pcall(D.RefreshAll)
check(okRefresh, "a refresh in combat raises nothing: " .. tostring(errRefresh))
check(cc.frame.shown == true and cc.states[1].active == true, "in combat a never-secret proc is still found by ID and shown")
auras.player = {}
D.RefreshAll()
check(cc.frame.shown == true, "in combat a proc that can't be read keeps its last shown state (never 'missing')")
restricted = false
D.RefreshAll()
check(cc.frame.shown == false, "out of combat the by-name absence hides it again")

-- Blizzard's Edit Mode through the stubbed library: every group and standalone display registered.
local gf = G.Parent("mage.cooldowns")
local reg = lem.frames[gf]
check(reg ~= nil and reg.name == "Mage cooldowns" and reg.default.point == "CENTER" and reg.default.x == 0 and reg.default.y == -200,
      "the group frame is registered under its name with its saved position as the default")
check(lem.frames[cc.frame] ~= nil and lem.frames[ib.frame] ~= nil and lem.frames[nova.frame] == nil,
      "standalone displays are registered, a group's children are not")
check(#lem.callbacks.enter == 1 and #lem.callbacks.exit == 1 and #lem.callbacks.layout == 1, "enter, exit and layout callbacks hooked once")
-- A drag ends: the library anchored the frame somewhere; the saved pos is the center offset.
gf.GetCenter = function() return 620, 350 end
reg.callback(gf, "Modern", "TOPLEFT", 100, -200)
local gpos = ns.db.groups["mage.cooldowns"].pos
check(gpos.x == 120 and gpos.y == -50, "the position change callback saves offsets from the screen center")
check(gf.last.SetPoint[1] == "CENTER" and gf.last.SetPoint[2] == UIParent and gf.last.SetPoint[4] == 120 and gf.last.SetPoint[5] == -50,
      "and re-anchors the frame on them")
ns.db.groups["mage.cooldowns"].pos = { x = 5, y = 6 }
lem.callbacks.layout[1]("Modern", 1)
check(gf.last.SetPoint[4] == 5 and gf.last.SetPoint[5] == 6, "the layout callback (login) re-anchors on the saved position")
-- Entering Edit Mode shows a hidden display and the refresh leaves it shown; leaving hides it again.
check(cc.frame.shown == false, "Clearcasting is hidden before Edit Mode opens")
lem.editing = true
lem.callbacks.enter[1]()
check(cc.frame.shown == true and G.IsEditing() == true, "entering Edit Mode shows it")
D.RefreshAll()
check(cc.frame.shown == true, "a refresh during Edit Mode keeps it shown")
lem.editing = false
lem.callbacks.exit[1]()
D.RefreshAll()
check(cc.frame.shown == false, "after Edit Mode the states decide again")
printed = {}
check(G.SetEditMode(true) == false and G.IsEditing() == false and printedHas("Blizzard's Edit Mode"), "/context edit points to Blizzard's Edit Mode when the library is loaded")

-- The plain drag is the fallback without the library.
LibStub = nil
check(G.SetEditMode(true) == true and G.IsEditing() == true, "edit mode on out of combat")
check(G.Parent("mage.cooldowns").calls.SetMovable == 1, "the group frame became movable")
InCombatLockdown = function() return true end
G.SetEditMode(false)
check(G.SetEditMode(true) == false and G.IsEditing() == false, "edit mode refused in combat")
InCombatLockdown = function() return false end
StubLibStub()

-- /context list and /context reset.
printed = {}
SlashCmdList["CONTEXT"]("list")
check(printedHas("displays: 7, groups: 1") and printedHas("mage.frostnova"), "/context list counts and names the displays")
SlashCmdList["CONTEXT"]("preset nothing")
check(printedHas("Unknown preset"), "an unknown preset is refused")
SlashCmdList["CONTEXT"]("reset")
check(next(ns.db.displays) == nil and #D.Order() == 0 and nova.frame.shown == false, "/context reset removes every display")
SlashCmdList["CONTEXT"]("preset mage")
check(printedHas("Preset installed: mage") and #D.Order() == 7, "/context preset mage puts them back")

----------------------------------------------------------------------------------------------------
-- Blizzard's Cooldown Manager hooks (way B): pure parts, then a stubbed viewer
----------------------------------------------------------------------------------------------------
local CDM = ns.CooldownManager
check(CDM.EdgeName(1) == "available" and CDM.EdgeName(5) == "auraApplied" and CDM.EdgeName(6) == "auraRemoved" and CDM.EdgeName(9) == nil and CDM.EdgeName("x") == nil, "alert event numbers map to edge names")
local st = CDM.Transition({}, "auraApplied")
check(st.active == true and st.lastEdge == "auraApplied", "auraApplied -> active")
CDM.Transition(st, "pandemic")
check(st.pandemic == true, "pandemic -> pandemic")
CDM.Transition(st, "auraRemoved")
check(st.active == false and st.pandemic == false, "auraRemoved -> inactive, pandemic over")
CDM.Transition(st, "onCooldown")
check(st.onCooldown == true and st.ready == false, "onCooldown -> not ready")
CDM.Transition(st, "available")
check(st.onCooldown == false and st.ready == true, "available -> ready")
CDM.Transition(st, "glowShown"); check(st.glow == true, "glowShown -> glow")
CDM.Transition(st, "glowHidden"); check(st.glow == false, "glowHidden -> no glow")
local keys = CDM.Keys(11426, { 11426, 13031 }, function(id) return ({ [11426] = "Ice Barrier", [13031] = "Ice Barrier" })[id] end)
check(#keys == 3 and keys[1] == 11426 and keys[2] == "ice barrier" and keys[3] == 13031, "Keys: spell ID, lowercase name, linked IDs, no duplicates")
check(#CDM.Keys(Secret("id"), nil, nil) == 0, "a secret spell ID gives no key")
check(CDM.KeyOf("Ice Barrier") == "ice barrier" and CDM.KeyOf(122) == 122 and CDM.KeyOf({ id = 12536, name = "Clearcasting" }) == 12536 and CDM.KeyOf({ name = "Clearcasting" }) == "clearcasting", "KeyOf: names lowercased, tables by id then name")
check(CDM.Snapshot("Nothing") == nil, "an untracked spell has no snapshot")

-- MergeEdges: the edges replace a hidden presence or cooldown state, never a plain one.
local hiddenPresent = { value = nil, way = "E", hidden = true, reason = "restricted" }
local merged = D.MergeEdges({ present = hiddenPresent }, { active = A(true, "B") })
check(merged.present.value == true and merged.present.way == "B" and merged.missing.value == false and merged.cdmActive.value == true, "a hidden presence takes the Cooldown Manager's answer (B)")
merged = D.MergeEdges({ present = A(false, "A") }, { active = A(true, "B") })
check(merged.present.value == false and merged.present.way == "A" and merged.cdmActive.value == true, "a plain presence keeps the source's answer")
merged = D.MergeEdges({}, nil)
check(merged.cdmActive == nil, "no Cooldown Manager: nothing added")
merged = D.MergeEdges({ onCooldown = hiddenPresent }, { onCooldown = A(true, "B") })
check(merged.onCooldown.value == true and merged.ready.value == false, "a hidden cooldown state takes the edge too")

-- A stubbed viewer: hooksecurefunc wraps the method on the table, items have the mixin methods.
hooksecurefunc = function(tbl, name, fn)
    local orig = tbl[name]
    tbl[name] = function(...) local r = orig(...); fn(...); return r end
end
local cdInfos = { [1] = { cooldownID = 1, spellID = 11426, linkedSpellIDs = { 11426 } }, [2] = { cooldownID = 2, spellID = 122, linkedSpellIDs = {} }, [3] = { cooldownID = 3, spellID = 12536, linkedSpellIDs = {} } }
C_CooldownViewer = { IsCooldownViewerAvailable = function() return true, "" end, GetCooldownViewerCooldownInfo = function(id) return cdInfos[id] end }
names[11426] = "Ice Barrier"
local function Item(cooldownID)
    local it = { cooldownID = cooldownID, active = false }
    it.GetCooldownID = function(self) return self.cooldownID end
    it.IsActive = function(self) return self.active end
    it.TriggerAlertEvent = function() end
    it.OnActiveStateChanged = function() end
    it.OnSpellActivationOverlayGlowShowEvent = function() end
    it.OnSpellActivationOverlayGlowHideEvent = function() end
    return it
end
local barrierItem, novaItem = Item(1), Item(2)
local active = { barrierItem }
BuffBarCooldownViewer = { OnAcquireItemFrame = function() end, itemFramePool = { EnumerateActive = function() local i = 0; return function() i = i + 1; return active[i] end end } }
EssentialCooldownViewer = { OnAcquireItemFrame = function() end, itemFramePool = { EnumerateActive = function() return function() return nil end end } }
check(CDM.Start() == 2 and CDM.Start() == 0, "two viewers present are hooked, once")
local edges = {}
CDM.Listen(function(spellID, edge) edges[#edges + 1] = tostring(spellID) .. ":" .. edge end)
barrierItem:TriggerAlertEvent(5)
local snap = CDM.Snapshot("Ice Barrier")
check(snap and snap.active.value == true and snap.active.way == "B" and snap.lastEdge == "auraApplied" and edges[1] == "11426:auraApplied", "an aura-applied alert on an existing item becomes an edge for 'Ice Barrier' by name")
check(CDM.Snapshot(11426).active.value == true, "and by spell ID")
-- A new item acquired later is hooked through OnAcquireItemFrame.
EssentialCooldownViewer:OnAcquireItemFrame(novaItem)
novaItem:TriggerAlertEvent(3)
check(CDM.Snapshot("Frost Nova").onCooldown.value == true and CDM.Snapshot(122).ready.value == false, "a newly acquired item's on-cooldown alert is an edge")
novaItem:TriggerAlertEvent(1)
check(CDM.Snapshot(122).ready.value == true and CDM.Snapshot(122).onCooldown.value == false, "available -> ready")
novaItem:OnSpellActivationOverlayGlowShowEvent(122)
check(CDM.Snapshot(122).glow.value == true, "a proc glow event is an edge")
-- Active state changes on buff items.
barrierItem.active = true; barrierItem:OnActiveStateChanged()
barrierItem.active = false; barrierItem:OnActiveStateChanged()
check(CDM.Snapshot(11426).active.value == false and CDM.Snapshot(11426).lastEdge == "inactive", "OnActiveStateChanged gives active / inactive edges")
-- A pooled frame now shows another cooldown: re-resolved, the old spell untouched.
barrierItem.cooldownID = 3
barrierItem.active = true; barrierItem:OnActiveStateChanged()
check(CDM.Snapshot(12536).active.value == true and CDM.Snapshot(11426).active.value == false, "a reused pooled frame is re-resolved to its new spell")
check(#CDM.Tracked() == 3, "three tracked spell IDs")

-- The display engine uses the edges: in combat the Ice Barrier bar's presence comes from Blizzard.
restricted = true
auras.player = {}
ns.db = { schemaVer = 1, displays = {}, groups = {} }
ns.Preset.Install("mage")
local ibar = D.Get("mage.icebarrier")
barrierItem.cooldownID = 1; barrierItem.active = true; barrierItem:OnActiveStateChanged()
D.RefreshAll()
check(ibar.frame.shown == true and ibar.inputs.present.way == "B", "in combat the bar is shown from the Cooldown Manager's active edge")
barrierItem.active = false; barrierItem:OnActiveStateChanged()
D.RefreshAll()
check(ibar.frame.shown == false, "and hidden when Blizzard's item goes inactive: the known gap of step 3 is closed when the spell is tracked")
restricted = false
C_CooldownViewer.IsCooldownViewerAvailable = function() return false, "disabled" end
check(CDM.Available() == false, "Available follows the game's answer")
printed = {}
pcall(SlashCmdList["CONTEXT"], "probe")
check(printedHas("Cooldown Manager: off"), "the probe says when the Cooldown Manager is off")
C_CooldownViewer.IsCooldownViewerAvailable = function() return true, "" end
printed = {}
pcall(SlashCmdList["CONTEXT"], "probe Frost Nova")
check(printedHas("last edge glowShown"), "the probe prints the last edge for a tracked spell")
CDM.Reset()
check(CDM.Snapshot(122) == nil, "Reset forgets the states")

----------------------------------------------------------------------------------------------------
-- The in-game test guide (/context tests): one entry per table row of docs/verified-in-game.md in
-- the same order, every button exists, answers and skips are saved with the build, it moves on
----------------------------------------------------------------------------------------------------
do
    local rows = {}
    local fh = assert(io.open(WORKSPACE_ROOT .. "/Context/docs/verified-in-game.md", "rb"))
    for line in fh:lines() do
        local id = line:match("^| (%w+) |")
        if id and id ~= "#" then rows[#rows + 1] = id end
    end
    fh:close()
    local TG = ns.TestGuide
    local guideIds, badAct, noText, crits = {}, {}, {}, {}
    for _, step in ipairs(ns.TEST_STEPS) do
        guideIds[#guideIds + 1] = step[1]
        for _, a in ipairs(step.act or {}) do if not TG.ACTIONS[a] then badAct[#badAct + 1] = step[1] .. ":" .. a end end
        if step.act and #step.act > 4 then badAct[#badAct + 1] = step[1] .. ":more-than-four" end
        if not (step[3] and step.expect and step.control and step.wrong) then noText[#noText + 1] = step[1] end
        if step.crit then crits[step.crit] = true end
    end
    check(#rows == 13 and table.concat(rows, " ") == table.concat(guideIds, " "),
        "the guide has one entry per table row, same order (table: " .. table.concat(rows, " ") .. "; guide: " .. table.concat(guideIds, " ") .. ")")
    check(#badAct == 0, "every guide button exists, four at most per step: " .. table.concat(badAct, ", "))
    check(#noText == 0, "every entry has steps, what to see, a control and a wrong-outcome reading: " .. table.concat(noText, ", "))
    check((crits[1] and crits[2] and crits[3] and crits[4] and crits[5]) == true, "acceptance criteria 1-5 each have a step")

    -- Open, answer, skip, move on; the game build and the time are saved with the answer.
    GetBuildInfo = function() return "1.60.1", "70245", "Oct 1 2026", 16001 end
    date = function() return "2026-10-10 21:00" end
    ns.db.testGuide = nil
    TG.Open()
    check(TG.IsOpen() == true and TG.Current() ~= nil and TG.Current()[1] == "T0", "the guide opens on the first step left (T0)")
    TG.Answer("ok")
    local saved = ns.db.testGuide.results.T0
    check(saved ~= nil and saved.result == "ok" and saved.build == "70245" and saved.version == "1.60.1" and saved.at == "2026-10-10 21:00",
        "an answer is saved with the game build and the time")
    check(TG.Current()[1] == "T1", "and the next step is shown")
    TG.Answer("skip")
    check(ns.db.testGuide.results.T1.result == "skip" and TG.Current()[1] == "T2", "a skip is saved and the guide moves on")
    -- A button runs its /context command: chat gets it, the step keeps the lines, plain.
    printed = {}
    TG.Run("probe")
    local out = ns.db.testGuide.results.T2.output
    check(out ~= nil and out[1] ~= nil and out[1]:find("auras restricted now", 1, true) ~= nil and printedHas("auras restricted now"),
        "the Probe button runs /context probe, prints to chat and saves the lines with the step")
    check(TG.Plain("|cff33ccffContext|r x") == "Context x", "saved output lines carry no color codes")
    TG.ACTIONS.boom = { "Boom", function() error("kaboom") end }
    TG.Run("boom")
    check(ns.db.testGuide.results.T2.output[1]:find("That button failed", 1, true) ~= nil, "a failing button is reported in the output, not raised")
    TG.ACTIONS.boom = nil
    -- Showing a step of another group switches to that group.
    for _, step in ipairs(ns.TEST_STEPS) do if step[1] == "F3" then TG.Show(step) end end
    check(TG.Current()[1] == "F3" and ns.db.testGuide.group == "F", "a step shown from elsewhere pulls its group along")
    -- The command toggles the window, the help lists it, login opens it while steps are left.
    SlashCmdList["CONTEXT"]("tests")
    check(TG.IsOpen() == false, "/context tests closes the open guide")
    SlashCmdList["CONTEXT"]("tests")
    check(TG.IsOpen() == true, "and opens it again")
    printed = {}
    SlashCmdList["CONTEXT"]("")
    check(printedHas("/context tests"), "the help lists /context tests")
    local opened = 0
    C_Timer = { After = function(_, fn) opened = opened + 1; check(fn == TG.Open, "login opens through Guide.Open") end }
    check(TG.OnLogin() == true and opened == 1, "at login the guide opens while steps are left")
    ns.db.testGuide.showAtLogin = false
    check(TG.OnLogin() == false and opened == 1, "the login opening can be turned off")
    ns.db.testGuide.showAtLogin = true
    for _, step in ipairs(ns.TEST_STEPS) do TG.Show(step); TG.Answer("ok") end
    check(TG.OnLogin() == false and opened == 1, "once every step is answered the guide stays shut at login")
end
