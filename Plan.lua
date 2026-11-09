local _, ns = ...

-- Plan math. A character record looks like:
--   goal     = { level, date, createdDay, createdTotal }
--   schedule = { weights = {Sun..Sat} (hours you can play), off = { ["YYYY-MM-DD"] = true },
--                dayHours = { ["YYYY-MM-DD"] = hours } (one-off changes, e.g. after going AFK) }
--   days     = { ["YYYY-MM-DD"] = { start, gained, target, level, hit } }
--   total, level, xp, lastDay
-- Everything is counted in total XP, so later levels weigh more than early ones.
local Plan = {}
ns.Plan = Plan

local XP, Day, Curve = ns.XP, ns.Day, ns.Curve
local DAY = ns.DAY
local MAX_BACKFILL_DAYS = 90
local MAX_PROJECTION_DAYS = 730

Plan.WEEKDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

function Plan.DefaultSchedule()
    return { weights = { 2, 2, 2, 2, 2, 2, 2 }, off = {} }
end

function Plan.WeekdayHours(c, start)
    return c.schedule.weights[Day.Weekday(start) + 1] or 0
end

function Plan.Weight(c, start)
    local key = Day.Key(start)
    if c.schedule.off[key] then
        return 0
    end
    local override = c.schedule.dayHours and c.schedule.dayHours[key]
    return override or Plan.WeekdayHours(c, start)
end

-- Changes the play time of one day only; nil (or the weekday's usual hours)
-- removes the change. Re-targets today if it's today.
function Plan.SetDayHours(c, start, hours, today)
    c.schedule.dayHours = c.schedule.dayHours or {}
    local key = Day.Key(start)
    if hours and hours ~= Plan.WeekdayHours(c, start) then
        c.schedule.dayHours[key] = math.max(0, hours)
    else
        c.schedule.dayHours[key] = nil
    end
    c.schedule.off[key] = nil
    if start == today then
        Plan.RetargetToday(c, today)
    end
end

function Plan.SumWeights(c, fromStart, toStart)
    local sum = 0
    for d = fromStart, toStart, DAY do
        sum = sum + Plan.Weight(c, d)
    end
    return sum
end

function Plan.GoalTotal(c)
    return XP.Cum(c.goal.level)
end

function Plan.Deadline(c)
    return Day.StartOfKey(c.goal.date)
end

-- Plans are made in "effort" units that are split evenly per weight-1 play day:
--   time mode (default): guide hours, so every play day takes the same time
--   xp mode:             XP, so every play day asks for the same XP
-- Effort(from, to) measures a stretch of XP; Advance(total, effort) walks it.
local MODES = {
    time = {
        Effort = Curve.Hours,
        Advance = Curve.Advance,
    },
    xp = {
        Effort = function(from, to) return math.max(0, to - from) end,
        Advance = function(total, effort) return total + effort end,
    },
}

function Plan.Mode(c)
    return MODES[c.goal.mode] and c.goal.mode or "time"
end

local function mode(c)
    return MODES[Plan.Mode(c)]
end

-- Signed effort from `from` to `to`.
local function signedEffort(c, from, to)
    if to >= from then
        return mode(c).Effort(from, to)
    end
    return -mode(c).Effort(to, from)
end

-- Effort the original plan gives one hour of play time.
local function baselineUnit(c)
    local g = c.goal
    local weight = Plan.SumWeights(c, Day.StartOfKey(g.createdDay), Plan.Deadline(c))
    if weight == 0 then
        return 0
    end
    return mode(c).Effort(g.createdTotal, Plan.GoalTotal(c)) / weight
end

-- Effort the original plan gives an average play day, so "1 day ahead"
-- means one typical play day whatever hours the days have.
local function baselineDay(c)
    local created, deadline = Day.StartOfKey(c.goal.createdDay), Plan.Deadline(c)
    local playDays = 0
    for d = created, deadline, DAY do
        if Plan.Weight(c, d) > 0 then
            playDays = playDays + 1
        end
    end
    if playDays == 0 then
        return 0
    end
    return baselineUnit(c) * Plan.SumWeights(c, created, deadline) / playDays
end

-- XP to earn on day `start`, given the total at the start of that day.
-- The remaining effort is split over the remaining play days by weight.
function Plan.TargetFor(c, start, startTotal)
    local remaining = Plan.GoalTotal(c) - startTotal
    if remaining <= 0 then
        return 0
    end
    local deadline = Plan.Deadline(c)
    if start > deadline then
        return remaining -- overdue: everything is due now
    end
    local weight = Plan.Weight(c, start)
    if weight == 0 then
        return 0
    end
    local m = mode(c)
    local share = m.Effort(startTotal, Plan.GoalTotal(c)) * weight / Plan.SumWeights(c, start, deadline)
    return math.ceil(m.Advance(startTotal, share) - startTotal)
end

local function newDay(c, start, total)
    return {
        start = total,
        gained = 0,
        target = c.goal and Plan.TargetFor(c, start, total) or 0,
        level = ns.Round(XP.LevelAt(total), 2),
    }
end

-- Returns today's record, creating it (and zero-XP records for days that were
-- skipped) at the first observation after a reset. Each new day is targeted
-- from the XP still missing, which is what spreads a shortfall forward.
function Plan.EnsureToday(c, today)
    local key = Day.Key(today)
    if c.days[key] then
        return c.days[key]
    end
    local last = c.lastDay and Day.StartOfKey(c.lastDay)
    if last then
        local from = math.max(last + DAY, today - MAX_BACKFILL_DAYS * DAY)
        for d = from, today - DAY, DAY do
            c.days[Day.Key(d)] = c.days[Day.Key(d)] or newDay(c, d, c.total)
        end
    end
    c.days[key] = newDay(c, today, c.total)
    c.lastDay = key
    return c.days[key]
end

-- Records the player's current level/XP. Returns today's record.
function Plan.Observe(c, today, level, xp)
    local total = XP.Total(level, xp)
    c.total = c.total or total
    local rec = Plan.EnsureToday(c, today)
    -- XP never goes down; a lower reading is the client reporting the new
    -- level a frame late, so ignore it until it settles.
    if total >= c.total then
        c.total, c.level, c.xp = total, level, xp
    end
    rec.gained = math.max(0, c.total - rec.start)
    return rec
end

function Plan.RetargetToday(c, today)
    local rec = c.days[Day.Key(today)]
    if rec and c.goal then
        rec.target = Plan.TargetFor(c, today, rec.start)
        rec.hit = rec.target > 0 and rec.gained >= rec.target
    end
end

-- A new goal starts a new baseline from the start of today.
function Plan.SetGoal(c, level, dateKey, today, planMode)
    local rec = c.days[Day.Key(today)]
    c.goal = {
        level = level,
        date = dateKey,
        mode = planMode or "time",
        createdDay = Day.Key(today),
        createdTotal = rec and rec.start or c.total,
    }
    Plan.RetargetToday(c, today)
end

-- Expected total at the end of day `start` if the goal's plan were followed
-- exactly from the day it was set.
function Plan.BaselineEnd(c, start)
    local g = c.goal
    local created = Day.StartOfKey(g.createdDay)
    local deadline = Plan.Deadline(c)
    local goalTotal = Plan.GoalTotal(c)
    if start < created then
        return g.createdTotal
    end
    if start >= deadline or Plan.SumWeights(c, created, deadline) == 0 then
        return goalTotal
    end
    return Plan.BaselineAfter(c, Plan.SumWeights(c, created, start))
end

-- Planned total once `weight` worth of play days have passed since the goal
-- was set, following the goal's mode (even hours or even XP per day).
function Plan.BaselineAfter(c, weight)
    return mode(c).Advance(c.goal.createdTotal, baselineUnit(c) * weight)
end

-- Guide hours of play per weight-1 day over the last `count` logged play
-- days before today. Measured in hours, so a recent day at level 20 and a
-- future day at level 50 compare fairly.
function Plan.RecentHours(c, today, count)
    local hours, weight, seen = 0, 0, 0
    for i = 1, 28 do
        local d = today - i * DAY
        local rec = c.days[Day.Key(d)]
        local w = Plan.Weight(c, d)
        if rec and w > 0 then
            hours = hours + Curve.Hours(rec.start, rec.start + rec.gained)
            weight, seen = weight + w, seen + 1
            if seen >= count then
                break
            end
        end
    end
    if weight == 0 then
        return nil
    end
    return hours / weight
end

-- Day on which the goal is reached if you keep playing as much as recently.
function Plan.ProjectFinish(c, today, rec)
    local remaining = Curve.Hours(c.total, Plan.GoalTotal(c))
    if remaining <= 0 then
        return today
    end
    local rate = Plan.RecentHours(c, today, 7)
    if not rate or rate <= 0 then
        return nil
    end
    remaining = remaining - math.max(0, rate * Plan.Weight(c, today) - Curve.Hours(rec.start, c.total))
    for i = 0, MAX_PROJECTION_DAYS do
        local d = today + i * DAY
        if i > 0 then
            remaining = remaining - rate * Plan.Weight(c, d)
        end
        if remaining <= 0 then
            return d
        end
    end
    return nil
end

-- Your hours needed to reach the goal from `fromTotal`, and the hours you
-- set aside from `today` to the deadline. `paceFactor` is your speed vs the
-- guide curve (1 = guide pace).
function Plan.TimeBudget(c, today, fromTotal, paceFactor)
    local needed = Curve.Hours(fromTotal, Plan.GoalTotal(c)) / paceFactor
    return needed, Plan.SumWeights(c, today, Plan.Deadline(c))
end

-- Everything the UI shows, in one table. `xph` may be nil (pace unknown);
-- `bankedXP` is XP from finished quests not handed in yet (0 if unknown).
function Plan.Status(c, today, xph, bankedXP)
    local rec = Plan.EnsureToday(c, today)
    local goalTotal = Plan.GoalTotal(c)
    local deadline = Plan.Deadline(c)
    local s = {
        level = XP.LevelAt(c.total),
        goalLevel = c.goal.level,
        deadline = deadline,
        remaining = math.max(0, goalTotal - c.total),
        target = rec.target,
        gained = rec.gained,
        left = math.max(0, rec.target - rec.gained),
        banked = bankedXP or 0,
        offToday = Plan.Weight(c, today) == 0,
        daysLeft = math.max(0, Day.Between(today, deadline) + 1),
        xph = xph,
        mode = Plan.Mode(c),
    }
    s.targetLevels = XP.LevelAt(rec.start + rec.target) - XP.LevelAt(rec.start)
    s.levelsLeftToday = math.max(0, XP.LevelAt(rec.start + rec.target) - s.level)
    s.remainingLevels = c.goal.level - s.level

    local endToday = Plan.BaselineEnd(c, today)
    local endYesterday = Plan.BaselineEnd(c, today - DAY)

    if s.remaining == 0 then
        s.state = "done"
    elseif today > deadline then
        s.state = "overdue"
    elseif c.total > endToday then
        s.state, s.deltaXP = "ahead", c.total - endToday
    elseif c.total >= endYesterday then
        s.state, s.deltaXP = "ontrack", 0
    else
        s.state, s.deltaXP = "behind", c.total - endYesterday
    end
    s.deltaDays = 0
    local playDay = baselineDay(c)
    if (s.state == "ahead" or s.state == "behind") and playDay > 0 then
        local baseline = s.state == "ahead" and endToday or endYesterday
        s.deltaDays = signedEffort(c, baseline, c.total) / playDay
    end

    s.playDaysLeft = 0
    for d = today, deadline, DAY do
        if Plan.Weight(c, d) > 0 then
            s.playDaysLeft = s.playDaysLeft + 1
        end
    end
    s.neededPerDay = s.remaining / math.max(1, s.playDaysLeft)
    -- Banked XP shortens the time still needed today, but not the target.
    s.leftAfterBanked = math.max(0, s.left - s.banked)
    if xph and xph > 0 then
        s.leftSeconds = s.leftAfterBanked / xph * 3600
        -- Measured from the start of today so the numbers hold still while you play.
        local factor = xph / Curve.Rate(math.floor(s.level))
        s.hoursNeeded, s.hoursAvailable = Plan.TimeBudget(c, today, rec.start, factor)
        s.usage = s.hoursAvailable > 0 and s.hoursNeeded / s.hoursAvailable or math.huge
        s.atRisk = s.state ~= "done" and s.state ~= "overdue" and s.usage > 1
        s.hoursToday = Curve.Hours(rec.start, rec.start + rec.target) / factor
        s.hoursSetToday = Plan.Weight(c, today)
    end
    s.projected = Plan.ProjectFinish(c, today, rec)
    return s
end

-- Planned XP per future day (key -> XP) and the planned total at the end of
-- each day from today on (key -> total XP), assuming today's target is met
-- and the plan is followed from tomorrow on.
function Plan.Forecast(c, today)
    local forecast, ends = {}, {}
    local rec = c.days[Day.Key(today)]
    local deadline = Plan.Deadline(c)
    local total = math.max(c.total, rec.start + rec.target)
    ends[Day.Key(today)] = total
    local weight = Plan.SumWeights(c, today + DAY, deadline)
    if weight == 0 then
        return forecast, ends
    end
    local m = mode(c)
    local unit = m.Effort(total, Plan.GoalTotal(c)) / weight
    for d = today + DAY, deadline, DAY do
        local after = m.Advance(total, unit * Plan.Weight(c, d))
        forecast[Day.Key(d)] = after - total
        ends[Day.Key(d)] = after
        total = after
    end
    return forecast, ends
end
