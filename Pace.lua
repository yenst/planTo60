local _, ns = ...

-- Your pace = the guide XP/hour curve (Curve.lua) times a personal factor.
--
-- Each *active* minute (XP gained or in combat) is stored as a ratio against
-- the guide rate for the level you were at: 1.0 is guide pace, 1.3 is 30%
-- faster. Ratios from different levels average fairly, and the result is
-- correct right after a level-up. Until enough minutes are recorded, the
-- guide rate itself is used and marked as an estimate.
local Pace = {}
ns.Pace = Pace

local Curve, XP = ns.Curve, ns.XP

local MAX_MINUTES = 300 -- 5 hours of active play
local MIN_MINUTES = 10

local minuteXP, minuteActive = 0, false

function Pace.AddXP(amount)
    if amount > 0 then
        minuteXP = minuteXP + amount
        minuteActive = true
    end
end

function Pace.MarkActive()
    minuteActive = true
end

-- Called once a minute. `samples` is the character's saved ratio list.
function Pace.Tick(samples, inCombat, level)
    if minuteActive or inCombat then
        samples[#samples + 1] = minuteXP / (Curve.Rate(level) / 60)
        while #samples > MAX_MINUTES do
            table.remove(samples, 1)
        end
    end
    minuteXP, minuteActive = 0, false
end

-- Personal factor vs the guide, or nil until enough minutes are recorded.
function Pace.Factor(samples)
    if #samples < MIN_MINUTES then
        return nil
    end
    local sum = 0
    for _, ratio in ipairs(samples) do
        sum = sum + ratio
    end
    return sum / #samples
end

-- Factor for someone whose /played from 1 to max level is `hours`.
function Pace.FactorFromPlayed(hours)
    return Curve.Hours(0, XP.Cum(XP.MAX_LEVEL)) / hours
end

-- XP/hour at `level`, and whether it is measured or set (false = guide
-- estimate). `playedHours` (optional) overrides the measured pace.
function Pace.XPPerHour(samples, level, playedHours)
    local factor = playedHours and Pace.FactorFromPlayed(playedHours) or Pace.Factor(samples)
    return (factor or 1) * Curve.Rate(level), factor ~= nil
end
