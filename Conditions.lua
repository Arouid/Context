-- Conditions.lua: the pure condition evaluator. No game API is called here: every input is passed
-- in, so the same code runs in the headless tests and in the game.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
--
-- A condition is either a LEAF
--     { test = "spell.ready", compare = "==", value = true, way = "A" }
-- or a COMBINATION
--     { op = "and" | "or", conditions = { ... } }     { op = "not", condition = { ... } }
--
-- The inputs are a table keyed by test name. A value may be plain (boolean, number, string), nil
-- (nothing known) or an ANSWER from Sources.lua: { value = ..., way = "A".."E", hidden = bool,
-- reason = "..." }. A hidden input (a secret value, or an answer with hidden = true) is never
-- compared: the result then says visualOnly = true (way D): only the engine can draw it.
--
-- Every evaluation returns { state = true | false | nil, visualOnly = bool, way = "A".."E" or a
-- sorted list of letters joined by ",", reason = token }. Reasons are code tokens, not user text:
-- the editor turns them into sentences.
--
-- Three-valued logic (Kleene): AND is false as soon as one side is false, true when all are true,
-- otherwise nil; OR mirrors it; NOT keeps nil. A hidden child never decides a result by itself:
-- when a plain child settles an AND or an OR, the result is Lua-decided and may fire sounds.
local _, ns = ...

local Conditions = {}
ns.Conditions = Conditions

local isSecret = issecretvalue or function() return false end

Conditions.WAYS = { A = "A", B = "B", C = "C", D = "D", E = "E" }
Conditions.OPS = { ["and"] = true, ["or"] = true, ["not"] = true }
Conditions.COMPARES = { ["=="] = true, ["~="] = true, ["<"] = true, ["<="] = true, [">"] = true, [">="] = true }

local function Result(state, visualOnly, way, reason)
    return { state = state, visualOnly = visualOnly or false, way = way, reason = reason }
end

-- Unwraps an input: returns the plain value, its way, whether it is hidden, and its own reason.
local function Unwrap(input, secretTest)
    if type(input) == "table" and input.way ~= nil and not isSecret(input) then
        local hidden = input.hidden == true or secretTest(input.value)
        return input.value, input.way, hidden, input.reason
    end
    return input, nil, secretTest(input), nil
end

-- Compares two plain values. Returns true/false, or nil with a reason when they can't be compared.
local function Compare(op, a, b)
    if op == "==" then return a == b end
    if op == "~=" then return a ~= b end
    local ta, tb = type(a), type(b)
    if ta ~= tb or (ta ~= "number" and ta ~= "string") then return nil, "incomparable" end
    if op == "<" then return a < b end
    if op == "<=" then return a <= b end
    if op == ">" then return a > b end
    if op == ">=" then return a >= b end
    return nil, "bad-compare"
end

local function EvaluateLeaf(cond, inputs, secretTest)
    if type(cond.test) ~= "string" then return Result(nil, false, cond.way, "no-test") end
    local value, inputWay, hidden, inputReason = Unwrap(inputs[cond.test], secretTest)
    local way = cond.way or inputWay or "A"
    if hidden or way == "D" then
        return Result(nil, true, "D", "hidden")
    end
    if value == nil then
        return Result(nil, false, way, inputReason or "unknown")
    end
    if cond.compare == nil and cond.value == nil then
        return Result(value ~= false, false, way, "truthy")
    end
    if cond.value ~= nil and secretTest(cond.value) then
        return Result(nil, true, "D", "hidden")
    end
    local op = cond.compare or "=="
    if not Conditions.COMPARES[op] then return Result(nil, false, way, "bad-compare") end
    local state, reason = Compare(op, value, cond.value)
    return Result(state, false, way, reason or "compared")
end

-- Joins the ways of several results into one tag: a single letter, or letters sorted and joined.
local function JoinWays(results)
    local seen, list = {}, {}
    for _, r in ipairs(results) do
        for letter in tostring(r.way or ""):gmatch("%a") do
            if not seen[letter] then seen[letter] = true; list[#list + 1] = letter end
        end
    end
    table.sort(list)
    return #list > 0 and table.concat(list, ",") or nil
end

local Evaluate

-- AND / OR share one walk: `decider` is the plain state that settles the combination early.
local function EvaluateMany(cond, inputs, secretTest, decider)
    local list = cond.conditions or {}
    if #list == 0 then return Result(nil, false, nil, "empty") end
    local results, undecided, hiddenSeen = {}, false, false
    for i, child in ipairs(list) do
        local r = Evaluate(child, inputs, secretTest)
        results[i] = r
        if r.state == decider then
            return Result(decider, false, r.way, cond.op .. "-decided")
        elseif r.state == nil then
            undecided = true
            if r.visualOnly then hiddenSeen = true end
        end
    end
    if undecided then
        return Result(nil, hiddenSeen, JoinWays(results), hiddenSeen and "hidden" or "unknown")
    end
    return Result(not decider, false, JoinWays(results), cond.op .. "-all")
end

local function EvaluateNot(cond, inputs, secretTest)
    local child = cond.condition or (cond.conditions and cond.conditions[1])
    if child == nil then return Result(nil, false, nil, "empty") end
    local r = Evaluate(child, inputs, secretTest)
    local state
    if r.state ~= nil then state = not r.state end
    return Result(state, r.visualOnly, r.way, r.reason)
end

-- Evaluate(condition, inputs[, secretTest]) -> result. `secretTest` replaces issecretvalue; the
-- tests pass a stand-in detector, the game uses the real one.
function Evaluate(cond, inputs, secretTest)
    secretTest = secretTest or isSecret
    inputs = inputs or {}
    if type(cond) ~= "table" then return Result(nil, false, nil, "no-condition") end
    local op = cond.op
    if op == nil then return EvaluateLeaf(cond, inputs, secretTest) end
    if op == "and" then return EvaluateMany(cond, inputs, secretTest, false) end
    if op == "or" then return EvaluateMany(cond, inputs, secretTest, true) end
    if op == "not" then return EvaluateNot(cond, inputs, secretTest) end
    return Result(nil, false, nil, "bad-op")
end
Conditions.Evaluate = Evaluate

-- Validate(condition) -> ok, problem. Checks the shape (op, compare, way) without evaluating, for
-- the editor and for imports.
function Conditions.Validate(cond)
    if type(cond) ~= "table" then return false, "no-condition" end
    if cond.op == nil then
        if type(cond.test) ~= "string" or cond.test == "" then return false, "no-test" end
        if cond.compare ~= nil and not Conditions.COMPARES[cond.compare] then return false, "bad-compare" end
        if cond.way ~= nil and not Conditions.WAYS[cond.way] then return false, "bad-way" end
        return true
    end
    if not Conditions.OPS[cond.op] then return false, "bad-op" end
    local children = cond.conditions or (cond.condition and { cond.condition }) or {}
    if #children == 0 then return false, "empty" end
    if cond.op == "not" and #children > 1 then return false, "not-takes-one" end
    for _, child in ipairs(children) do
        local ok, problem = Conditions.Validate(child)
        if not ok then return false, problem end
    end
    return true
end

-- CanFireActions(result): sounds and reminders need a Lua-decided state; a visual-only result
-- (way D) may only drive looks, and an unknown one nothing at all.
function Conditions.CanFireActions(result)
    return result ~= nil and result.state ~= nil and not result.visualOnly
end
