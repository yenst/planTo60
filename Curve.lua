local _, ns = ...

-- How fast XP comes in at each level, for planning by time instead of XP.
--
-- Guide XP/hour per 10-level bracket = the bracket's XP (from the XP table)
-- divided by the hours players report for it on the Blizzard forums
-- ("Estimating 1-60 time"): 1-10 3.5h, 10-20 11h, 20-30 19h, 30-40 26h,
-- 40-50 31h, 50-60 39h (~130h total). This agrees with grinding guides
-- (10-18k XP/h around 11-14, 35-55k in the late 50s), and Blizzard's level-20
-- figures show Forever levels at the same speed as Classic (20.5h vs 20.4h).
--
-- Only the *shape* of this curve affects XP targets: scaling every rate by
-- the same factor scales hours but leaves "equal time per day" unchanged.
-- Your measured pace sets the scale when pt60 converts the plan to hours.
local Curve = {}
ns.Curve = Curve

local XP = ns.XP

-- Guide XP/hour at the middle of each bracket; linear in between.
local POINTS = {
    { 5, 7900 },
    { 15, 12700 },
    { 25, 17500 },
    { 35, 25200 },
    { 45, 37200 },
    { 55, 45600 },
}

function Curve.Rate(level)
    if level <= POINTS[1][1] then
        return POINTS[1][2]
    end
    for i = 2, #POINTS do
        local a, b = POINTS[i - 1], POINTS[i]
        if level <= b[1] then
            return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
        end
    end
    return POINTS[#POINTS][2]
end

-- Guide hours to go from one total XP to another (0 if `to` <= `from`).
function Curve.Hours(from, to)
    local hours = 0
    while from < to do
        local level = math.floor(XP.LevelAt(from))
        if level >= XP.MAX_LEVEL then
            break
        end
        local stop = math.min(to, XP.Cum(level + 1))
        hours = hours + (stop - from) / Curve.Rate(level)
        from = stop
    end
    return hours
end

-- Total XP after playing `hours` guide hours starting from `total`.
function Curve.Advance(total, hours)
    local cap = XP.Cum(XP.MAX_LEVEL)
    while hours > 0 and total < cap do
        local level = math.floor(XP.LevelAt(total))
        local rate = Curve.Rate(level)
        local toNext = XP.Cum(level + 1) - total
        if toNext / rate >= hours then
            return total + hours * rate
        end
        total = total + toNext
        hours = hours - toNext / rate
    end
    return math.min(total, cap)
end
