-- Plain-Lua tests for pt60's non-UI modules. Run from the repo root:
--   lua5.1 tests/run.lua
date, time = os.date, os.time

local ns = {}
for _, file in ipairs({ "Init", "XPTable", "Curve", "Day", "JSON", "Plan", "Pace", "Export" }) do
    assert(loadfile(file .. ".lua"))("planTo60", ns)
end
local XP, Day, Plan, JSON, Export, Pace = ns.XP, ns.Day, ns.Plan, ns.JSON, ns.Export, ns.Pace
local DAY = ns.DAY

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end
local function eq(actual, expected, label)
    if actual ~= expected then
        error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

Day.offset = 4 * 3600 -- EU-style reset at 04:00 UTC
local today = Day.StartOfKey("2026-11-04")

local function newChar(level, xp)
    local c = { days = {}, pace = {}, schedule = Plan.DefaultSchedule(), name = "Tester", realm = "Realm", class = "MAGE" }
    Plan.Observe(c, today, level, xp)
    return c
end

test("XP curve totals 4,084,700 XP to level 60", function()
    eq(XP.Cum(60), 4084700, "cum 60")
    eq(XP.Cum(1), 0, "cum 1")
    eq(XP.LevelAt(XP.Cum(42)), 42, "level at cum 42")
    eq(XP.LevelAt(XP.Cum(60) + 5), 60, "capped")
end)

test("day keys round-trip and reject bad dates", function()
    eq(Day.Key(today), "2026-11-04")
    eq(Day.Key(Day.StartOfKey("2026-12-12")), "2026-12-12")
    eq(Day.Between(today, Day.StartOfKey("2026-12-12")), 38)
    eq(Day.ParseKey("2026-02-30"), nil, "Feb 30")
    eq(Day.StartOfKey("nope"), nil)
    eq(Day.Weekday(today), 3, "Wednesday")
end)

test("dates are shown and typed as dd/mm/yyyy", function()
    eq(Day.DisplayKey("2026-12-04"), "04/12/2026")
    eq(Day.Short(Day.StartOfKey("2026-12-04")), "04/12/2026")
    eq(Day.ParseInput("04/12/2026"), "2026-12-04")
    eq(Day.ParseInput(" 4/12/2026 "), "2026-12-04", "single digit, spaces")
    eq(Day.ParseInput("4-12-2026"), "2026-12-04")
    eq(Day.ParseInput("04.12.2026"), "2026-12-04")
    eq(Day.ParseInput("2026-12-04"), "2026-12-04", "ISO still works")
    eq(Day.ParseInput("31/02/2026"), nil, "no Feb 31")
    eq(Day.ParseInput("12/31/2026"), nil, "month 31 is not mm/dd")
end)

test("day boundary is the reset, not midnight", function()
    local beforeReset = today + DAY - 60 -- 03:59 UTC on Nov 5
    eq(Day.Key(Day.Start(beforeReset)), "2026-11-04")
    eq(Day.Key(Day.Start(today + DAY)), "2026-11-05")
end)

test("every-day plan splits remaining XP evenly", function()
    local c = newChar(10, 0)
    Plan.SetGoal(c, 60, "2026-12-03", today, "xp") -- 30 days inclusive
    local remaining = XP.Cum(60) - XP.Cum(10)
    eq(c.days["2026-11-04"].target, math.ceil(remaining / 30), "day 1 target")
end)

test("a missed day is spread over the remaining days", function()
    local c = newChar(10, 0)
    Plan.SetGoal(c, 60, "2026-12-03", today, "xp")
    local remaining = XP.Cum(60) - XP.Cum(10)
    -- No play on Nov 4 or 5; log in on Nov 6.
    local rec = Plan.Observe(c, today + 2 * DAY, 10, 0)
    eq(c.days["2026-11-05"].gained, 0, "backfilled day")
    eq(rec.target, math.ceil(remaining / 28), "28 days remain")
end)

test("getting ahead lowers later targets", function()
    local c = newChar(10, 0)
    Plan.SetGoal(c, 60, "2026-12-03", today, "xp")
    local planned = c.days["2026-11-04"].target
    Plan.Observe(c, today, 10, 0)
    local total = XP.Cum(10) + planned * 2 -- double today's target
    local level = math.floor(XP.LevelAt(total))
    Plan.Observe(c, today, level, total - XP.Cum(level))
    local s = Plan.Status(c, today, nil)
    eq(s.state, "ahead")
    assert(s.deltaDays > 0.9 and s.deltaDays < 1.1, "about a day ahead, got " .. s.deltaDays)
    local tomorrow = Plan.Observe(c, today + DAY, level, total - XP.Cum(level))
    local expected = math.ceil((XP.Cum(60) - total) / 29)
    eq(tomorrow.target, expected, "tomorrow target")
    assert(tomorrow.target < planned, "target went down")
end)

test("behind shows after a missed day", function()
    local c = newChar(10, 0)
    Plan.SetGoal(c, 60, "2026-12-03", today, "xp")
    Plan.Observe(c, today + DAY, 10, 0)
    local s = Plan.Status(c, today + DAY, nil)
    eq(s.state, "behind")
    assert(s.deltaDays < -0.9, "about a day behind")
end)

test("weights and off days shape the targets", function()
    local c = newChar(30, 0)
    c.schedule.weights = { 2, 1, 1, 0, 1, 1, 2 } -- Sun x2, Wed off, Sat x2
    Plan.SetGoal(c, 40, "2026-11-10", today, "xp") -- Wed 4 .. Tue 10
    eq(c.days["2026-11-04"].target, 0, "Wednesday is off")
    local remaining = XP.Cum(40) - XP.Cum(30)
    -- Thu1 Fri1 Sat2 Sun2 Mon1 Tue1 = 8 weight units from Thursday
    eq(Plan.TargetFor(c, today + DAY, c.total), math.ceil(remaining / 8), "Thursday")
    -- From Saturday with nothing earned yet: Sat2 Sun2 Mon1 Tue1 = 6
    eq(Plan.TargetFor(c, today + 3 * DAY, c.total), math.ceil(remaining * 2 / 6), "Saturday")
    c.schedule.off["2026-11-07"] = true
    eq(Plan.TargetFor(c, today + 3 * DAY, c.total), 0, "Saturday marked off")
    eq(Plan.TargetFor(c, today + DAY, c.total), math.ceil(remaining / 6), "Thursday after Sat off")
end)

test("overdue goal asks for everything that remains", function()
    local c = newChar(20, 0)
    Plan.SetGoal(c, 25, "2026-11-05", today, "xp")
    local rec = Plan.Observe(c, today + 3 * DAY, 20, 0)
    eq(rec.target, XP.Cum(25) - XP.Cum(20))
    eq(Plan.Status(c, today + 3 * DAY, nil).state, "overdue")
end)

test("goal reached reports done", function()
    local c = newChar(24, 31000)
    Plan.SetGoal(c, 25, "2026-11-20", today, "xp")
    Plan.Observe(c, today, 25, 10)
    local s = Plan.Status(c, today, nil)
    eq(s.state, "done")
    eq(s.remaining, 0)
end)

test("XP readings that go down are ignored", function()
    local c = newChar(20, 23000)
    Plan.Observe(c, today, 20, 100) -- new level not reported yet
    eq(c.total, XP.Cum(20) + 23000)
    Plan.Observe(c, today, 21, 100)
    eq(c.level, 21)
end)

test("at risk when the goal needs more time than you set aside", function()
    local Curve = ns.Curve
    local c = newChar(10, 0)
    Plan.SetGoal(c, 60, "2026-11-10", today) -- 7 days x 2h = 14h set aside
    local s = Plan.Status(c, today, Curve.Rate(10)) -- guide pace: ~110h needed
    assert(s.atRisk and s.usage > 1, "should be at risk")
    s = Plan.Status(c, today, Curve.Rate(10) * 20)
    assert(not s.atRisk and s.usage < 1, "not at risk at 20x guide pace")
end)

test("projection uses the recent hours played", function()
    local c = newChar(10, 0)
    Plan.SetGoal(c, 12, "2026-12-30", today, "xp")
    local perDay = 300
    for i = 0, 6 do
        local total = XP.Cum(10) + perDay * (i + 1)
        local level = math.floor(XP.LevelAt(total))
        Plan.Observe(c, today + i * DAY, level, total - XP.Cum(level))
    end
    local d = today + 7 * DAY
    Plan.Observe(c, d, c.level, c.xp)
    local s = Plan.Status(c, d, nil)
    -- Levels 10-12 have nearly the same guide rate, so hours ~ XP here.
    local remaining = XP.Cum(12) - c.total
    local days = Day.Between(d, s.projected)
    assert(math.abs(days - (math.ceil(remaining / perDay) - 1)) <= 1, "days to finish, got " .. days)
end)

test("banked XP shortens time left but not the target", function()
    local c = newChar(10, 0)
    Plan.SetGoal(c, 60, "2026-12-03", today, "xp")
    local s = Plan.Status(c, today, 60000, 20000)
    eq(s.left, s.target, "nothing earned yet")
    eq(s.leftAfterBanked, s.target - 20000)
    eq(math.floor(s.leftSeconds), math.floor((s.target - 20000) / 60000 * 3600))
    s = Plan.Status(c, today, 60000, s.target * 2)
    eq(s.leftAfterBanked, 0, "banked covers the rest of today")
end)

test("curve: hours and advance are inverse", function()
    local Curve = ns.Curve
    local from = XP.Cum(12) + 500
    local to = Curve.Advance(from, 7.5)
    assert(math.abs(Curve.Hours(from, to) - 7.5) < 1e-6, "round trip")
    assert(Curve.Rate(55) > Curve.Rate(10) * 3, "XP/hour rises with level")
    eq(Curve.Advance(XP.Cum(60), 5), XP.Cum(60), "capped at 60")
end)

test("time mode gives every play day the same hours", function()
    local Curve = ns.Curve
    local c = newChar(10, 0)
    Plan.SetGoal(c, 60, "2026-12-03", today) -- default mode: time
    eq(Plan.Mode(c), "time")
    local hoursPerDay = Curve.Hours(XP.Cum(10), XP.Cum(60)) / 30
    local rec = c.days["2026-11-04"]
    assert(math.abs(Curve.Hours(rec.start, rec.start + rec.target) - hoursPerDay) < 0.01, "day 1 = average hours")
    assert(rec.target < (XP.Cum(60) - XP.Cum(10)) / 30, "less XP than an even split early on")
    local forecast = Plan.Forecast(c, today)
    local total, previous = rec.start + rec.target, rec.target
    for i = 1, 29 do
        local xp = forecast[Day.Key(today + i * DAY)]
        assert(xp >= previous - 1, "XP targets grow as levels go up")
        assert(math.abs(Curve.Hours(total, total + xp) - hoursPerDay) < 0.01, "same hours on day " .. i)
        total, previous = total + xp, xp
    end
    assert(math.abs(total - XP.Cum(60)) < 1, "forecast ends at the goal")
    local _, ends = Plan.Forecast(c, today)
    eq(ends["2026-11-04"], rec.start + rec.target, "today ends at today's target")
    assert(math.abs(XP.LevelAt(ends["2026-12-03"]) - 60) < 0.001, "level 60 on the deadline")
    assert(XP.LevelAt(ends["2026-11-20"]) > XP.LevelAt(ends["2026-11-10"]), "planned level rises")
end)

test("time mode: a missed day spreads its hours forward", function()
    local Curve = ns.Curve
    local c = newChar(10, 0)
    Plan.SetGoal(c, 60, "2026-12-03", today)
    local rec = Plan.Observe(c, today + DAY, 10, 0)
    local expected = Curve.Hours(XP.Cum(10), XP.Cum(60)) / 29
    assert(math.abs(Curve.Hours(rec.start, rec.start + rec.target) - expected) < 0.01, "29 days of hours")
    local s = Plan.Status(c, today + DAY, nil)
    eq(s.state, "behind")
    assert(math.abs(s.deltaDays + 1) < 0.01, "exactly one play day behind, got " .. s.deltaDays)
end)

test("time mode hours use your pace relative to the guide", function()
    local Curve = ns.Curve
    local c = newChar(30, 0)
    Plan.SetGoal(c, 40, "2026-11-13", today) -- 10 days
    local guideTotal = Curve.Hours(XP.Cum(30), XP.Cum(40))
    local s = Plan.Status(c, today, Curve.Rate(30) * 2) -- twice the guide pace
    assert(math.abs(s.hoursNeeded - guideTotal / 2) < 0.01, "half the guide hours")
    eq(s.hoursAvailable, 20, "10 days x 2h")
    assert(math.abs(s.hoursToday - s.usage * 2) < 0.01, "today uses the same share of its 2h")
    eq(s.deltaDays, 0, "on track has no delta")
end)

test("losing time today lowers today's target and spreads the rest", function()
    local Curve = ns.Curve
    local c = newChar(20, 0)
    Plan.SetGoal(c, 30, "2026-11-13", today) -- 10 days x 2h
    local before = c.days["2026-11-04"].target
    Plan.SetDayHours(c, today, 1.5, today) -- AFK for 30 minutes
    local rec = c.days["2026-11-04"]
    assert(rec.target < before, "today's target went down")
    local hours = Curve.Hours(rec.start, rec.start + rec.target)
    local expected = Curve.Hours(XP.Cum(20), XP.Cum(30)) * 1.5 / 19.5
    assert(math.abs(hours - expected) < 0.01, "today gets 1.5 of 19.5 hours")
    eq(Plan.Weight(c, today), 1.5)
    eq(Plan.Weight(c, today + DAY), 2, "other days unchanged")
    Plan.SetDayHours(c, today, nil, today)
    eq(c.days["2026-11-04"].target, before, "reset restores the target")
    eq(c.schedule.dayHours["2026-11-04"], nil)
    -- survives export/import
    Plan.SetDayHours(c, today, 1, today)
    local plan = assert(Export.ReadPlan(Export.ToJSON({ c }), "Tester", "Realm"))
    eq(plan.schedule.dayHours["2026-11-04"], 1)
end)

test("pace: guide estimate first, then your factor at any level", function()
    local Curve = ns.Curve
    local samples = {}
    local xph, measured = Pace.XPPerHour(samples, 20)
    eq(measured, false, "no data yet")
    eq(xph, Curve.Rate(20), "guide rate as the estimate")
    -- 12 active minutes at level 20, playing at 1.5x the guide rate; idle minutes don't count.
    for _ = 1, 12 do
        Pace.AddXP(Curve.Rate(20) / 60 * 1.5)
        Pace.Tick(samples, false, 20)
        Pace.Tick(samples, false, 20)
    end
    eq(#samples, 12)
    assert(math.abs(Pace.Factor(samples) - 1.5) < 1e-9, "factor 1.5")
    -- Right after leveling to 30 the pace already reflects level 30.
    xph, measured = Pace.XPPerHour(samples, 30)
    eq(measured, true)
    assert(math.abs(xph - Curve.Rate(30) * 1.5) < 1e-6, "scaled to the new level")
    Pace.Tick(samples, true, 30) -- combat without XP counts as active
    eq(#samples, 13)
end)

test("JSON round-trips values and escapes strings", function()
    local value = { a = 1, b = "x\"y\n", c = JSON.Array({ true, false, 1.5 }), d = JSON.Array(), e = {} }
    local text = JSON.Encode(value)
    eq(text, '{"a":1,"b":"x\\"y\\n","c":[true,false,1.5],"d":[],"e":{}}')
    local back = assert(JSON.Decode(text))
    eq(back.b, "x\"y\n")
    eq(back.c[3], 1.5)
    local pretty = JSON.Encode(value, true)
    eq(JSON.Encode(assert(JSON.Decode(pretty))), text, "pretty re-encodes the same")
    local _, err = JSON.Decode("{\"a\":}")
    assert(err and err:find("JSON error"), "reports errors")
end)

test("export document and import of goal and schedule", function()
    local c = newChar(30, 500)
    c.schedule.weights[1] = 3.5
    c.schedule.off["2026-11-20"] = true
    Plan.SetGoal(c, 50, "2026-12-12", today, "xp")
    local text = Export.ToJSON({ c }, true)
    local doc = assert(JSON.Decode(text))
    eq(doc.format, "planto60-export")
    local entry = doc.characters[1]
    eq(entry.goal.deadline, "2026-12-12")
    eq(entry.schedule.hoursPerWeekday.sunday, 3.5)
    eq(entry.schedule.offDays[1], "2026-11-20")
    eq(entry.history[1].date, "2026-11-04")
    local plan = assert(Export.ReadPlan(text, "Someone", "Else"))
    eq(plan.level, 50)
    eq(plan.deadline, "2026-12-12")
    eq(plan.schedule.weights[1], 3.5)
    assert(plan.schedule.off["2026-11-20"])
    local _, err = Export.ReadPlan('{"format":"other"}', "x", "y")
    assert(err, "rejects foreign JSON")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
