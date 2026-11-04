local _, ns = ...

-- Builds and reads the pt60 JSON export format:
-- {
--   "format": "planto60-export", "version": 1, "exportedAt": "...Z",
--   "characters": [ { name, realm, class, level, xp, totalXP, lastSeen,
--       goal: { level, deadline, mode ("time" | "xp"), setOn, startTotalXP },
--       schedule: { hoursPerWeekday: { sunday..saturday }, offDays: [dates], dayHours: { date: hours } },
--       history: [ { date, level, startTotalXP, gained, target, hit } ] } ]
-- }
local Export = {}
ns.Export = Export

local JSON, Plan = ns.JSON, ns.Plan

Export.FORMAT = "planto60-export"
Export.VERSION = 1

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

local function exportSchedule(schedule)
    local hours = {}
    for i, day in ipairs(Plan.WEEKDAYS) do
        hours[day:lower()] = schedule.weights[i]
    end
    return { hoursPerWeekday = hours, offDays = JSON.Array(sortedKeys(schedule.off)), dayHours = schedule.dayHours or {} }
end

local function exportHistory(days)
    local history = JSON.Array()
    for _, key in ipairs(sortedKeys(days)) do
        local rec = days[key]
        history[#history + 1] = {
            date = key,
            level = rec.level,
            startTotalXP = rec.start,
            gained = rec.gained,
            target = rec.target,
            hit = rec.target > 0 and rec.gained >= rec.target,
        }
    end
    return history
end

function Export.Character(c)
    return {
        name = c.name,
        realm = c.realm,
        class = c.class,
        level = c.level,
        xp = c.xp,
        totalXP = c.total,
        lastSeen = c.lastSeen and date("!%Y-%m-%dT%H:%M:%SZ", c.lastSeen),
        goal = c.goal and {
            level = c.goal.level,
            deadline = c.goal.date,
            mode = Plan.Mode(c),
            setOn = c.goal.createdDay,
            startTotalXP = c.goal.createdTotal,
        },
        schedule = exportSchedule(c.schedule),
        history = exportHistory(c.days),
    }
end

-- `chars` is a list of character records.
function Export.Document(chars)
    local list = JSON.Array()
    for _, c in ipairs(chars) do
        list[#list + 1] = Export.Character(c)
    end
    return {
        format = Export.FORMAT,
        version = Export.VERSION,
        exportedAt = date("!%Y-%m-%dT%H:%M:%SZ"),
        characters = list,
    }
end

function Export.ToJSON(chars, pretty)
    return JSON.Encode(Export.Document(chars), pretty)
end

local function readSchedule(data)
    local schedule = Plan.DefaultSchedule()
    if type(data) ~= "table" then
        return schedule
    end
    local hours = data.hoursPerWeekday
    if type(hours) == "table" then
        for i, day in ipairs(Plan.WEEKDAYS) do
            local h = tonumber(hours[day:lower()])
            if h and h >= 0 and h <= 24 then
                schedule.weights[i] = h
            end
        end
    end
    if type(data.dayHours) == "table" then
        schedule.dayHours = {}
        for key, h in pairs(data.dayHours) do
            h = tonumber(h)
            if ns.Day.ParseKey(key) and h and h >= 0 and h <= 24 then
                schedule.dayHours[key] = h
            end
        end
    end
    if type(data.offDays) == "table" then
        for _, key in ipairs(data.offDays) do
            if ns.Day.ParseKey(key) then
                schedule.off[key] = true
            end
        end
    end
    return schedule
end

-- Picks the entry for (name, realm) from an export, or the only entry if
-- there is just one. Returns the parsed goal and schedule, or nil + error.
function Export.ReadPlan(text, name, realm)
    local doc, err = JSON.Decode(text)
    if not doc then
        return nil, err
    end
    local knownFormat = doc and (doc.format == Export.FORMAT or doc.format == "pt60-export")
    if type(doc) ~= "table" or not knownFormat or type(doc.characters) ~= "table" then
        return nil, "This is not a planTo60 export."
    end
    local entry = #doc.characters == 1 and doc.characters[1] or nil
    for _, ch in ipairs(doc.characters) do
        if ch.name == name and ch.realm == realm then
            entry = ch
        end
    end
    if not entry then
        return nil, "No entry for " .. name .. " in this export, and it holds more than one character."
    end
    local goal = entry.goal
    if type(goal) ~= "table" or not tonumber(goal.level) or not ns.Day.ParseKey(goal.deadline) then
        return nil, "The export has no valid goal."
    end
    return {
        level = math.max(2, math.min(ns.XP.MAX_LEVEL, math.floor(tonumber(goal.level)))),
        deadline = goal.deadline,
        mode = goal.mode == "xp" and "xp" or "time",
        schedule = readSchedule(entry.schedule),
        source = entry.name and (entry.name .. "-" .. (entry.realm or "?")) or "export",
    }
end
