local _, ns = ...

local XP = {}
ns.XP = XP

XP.MAX_LEVEL = 60

-- perLevel[L] = XP needed to go from level L to L + 1 (Classic 1-60 curve).
-- Core overwrites entries with UnitXPMax() as levels are observed, so a client
-- with a different curve corrects itself.
XP.perLevel = {
    400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
    8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
    25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
    50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
    95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
    153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,
}

function XP.Observe(level, maxXP)
    if level >= 1 and level < XP.MAX_LEVEL and maxXP and maxXP > 0 then
        XP.perLevel[level] = maxXP
    end
end

-- Total XP earned at the very start of `level`.
function XP.Cum(level)
    local sum = 0
    for l = 1, math.min(level, XP.MAX_LEVEL) - 1 do
        sum = sum + XP.perLevel[l]
    end
    return sum
end

function XP.Total(level, xp)
    return XP.Cum(level) + (xp or 0)
end

-- Fractional level for a total, e.g. 42.37.
function XP.LevelAt(total)
    local level = 1
    while level < XP.MAX_LEVEL and total >= XP.perLevel[level] do
        total = total - XP.perLevel[level]
        level = level + 1
    end
    if level >= XP.MAX_LEVEL then
        return XP.MAX_LEVEL
    end
    return level + total / XP.perLevel[level]
end
