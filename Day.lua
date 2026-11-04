local _, ns = ...

-- A "day" runs from one server daily reset to the next. Days are identified by
-- the local calendar date of the reset that starts them ("2026-12-12") and
-- handled internally as the epoch second of that reset.
local Day = {}
ns.Day = Day

local DAY = ns.DAY

-- Seconds after 00:00 UTC at which the daily reset happens. Detected at login.
Day.offset = 4 * 3600

function Day.Now()
    return GetServerTime and GetServerTime() or time()
end

function Day.DetectOffset()
    local secs
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        secs = C_DateAndTime.GetSecondsUntilDailyReset()
    end
    if (not secs or secs <= 0) and GetQuestResetTime then
        secs = GetQuestResetTime()
    end
    if not secs or secs <= 0 or secs > DAY then
        return nil
    end
    local nextReset = Day.Now() + secs
    -- Round to the minute; the API reports a value that drifts by a few seconds.
    return (math.floor((nextReset % DAY) / 60 + 0.5) * 60) % DAY
end

function Day.Start(t)
    return t - ((t - Day.offset) % DAY)
end

function Day.Today()
    return Day.Start(Day.Now())
end

function Day.Key(start)
    return date("%Y-%m-%d", start)
end

function Day.Weekday(start)
    return tonumber(date("%w", start)) -- 0 = Sunday
end

-- Returns year, month, day for a valid "YYYY-MM-DD" key, nil otherwise.
function Day.ParseKey(key)
    if type(key) ~= "string" then
        return nil
    end
    local y, m, d = key:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or m < 1 or m > 12 or d < 1 or d > 31 then
        return nil
    end
    local t = time({ year = y, month = m, day = d, hour = 12 })
    if date("%Y-%m-%d", t) ~= key then
        return nil -- e.g. 2026-02-30
    end
    return y, m, d
end

function Day.StartOfKey(key)
    local y, m, d = Day.ParseKey(key)
    if not y then
        return nil
    end
    local guess = Day.Start(time({ year = y, month = m, day = d, hour = 12 }))
    for _, candidate in ipairs({ guess, guess + DAY, guess - DAY }) do
        if Day.Key(candidate) == key then
            return candidate
        end
    end
    return guess
end

function Day.Between(fromStart, toStart)
    return math.floor((toStart - fromStart) / DAY + 0.5)
end

-- Dates are shown and typed as dd/mm/yyyy; keys stay YYYY-MM-DD internally
-- and in exports.
function Day.Pretty(start)
    return date("%a %d/%m/%Y", start)
end

function Day.Short(start)
    return date("%d/%m/%Y", start)
end

function Day.DisplayKey(key)
    local y, m, d = Day.ParseKey(key)
    if not y then
        return key or ""
    end
    return string.format("%02d/%02d/%04d", d, m, y)
end

-- Typed date -> key. Accepts dd/mm/yyyy (also with - or . and single digits)
-- and YYYY-MM-DD. Returns nil if it isn't a real date.
function Day.ParseInput(text)
    text = (text or ""):match("^%s*(.-)%s*$")
    if Day.ParseKey(text) then
        return text
    end
    local d, m, y = text:match("^(%d%d?)[/%-%.](%d%d?)[/%-%.](%d%d%d%d)$")
    if not d then
        return nil
    end
    local key = string.format("%04d-%02d-%02d", tonumber(y), tonumber(m), tonumber(d))
    return Day.ParseKey(key) and key or nil
end
