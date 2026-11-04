local ADDON, ns = ...

local Day, Plan, Pace, XP, Quests = ns.Day, ns.Plan, ns.Pace, ns.XP, ns.Quests

local DEFAULT_SETTINGS = {
    showTracker = true,
    lockTracker = false,
    trackerScale = 1,
    loginSummary = true,
    targetToast = true,
    toastSound = true,
}

local function initDB()
    pt60DB = pt60DB or {}
    local db = pt60DB
    db.version = 1
    db.settings = db.settings or {}
    for key, value in pairs(DEFAULT_SETTINGS) do
        if db.settings[key] == nil then
            db.settings[key] = value
        end
    end
    db.chars = db.chars or {}
    -- v2: earlier versions could record a level's max XP mid level-up; start over.
    if db.xpTableVersion ~= 2 then
        db.xpTable, db.xpTableVersion = {}, 2
    end
    for level, maxXP in pairs(db.xpTable) do
        XP.Observe(level, maxXP)
    end
    ns.db = db
end

local function loadCharacter()
    local name, realm = UnitName("player"), GetRealmName()
    local key = name .. "-" .. realm
    local c = ns.db.chars[key] or { days = {}, schedule = Plan.DefaultSchedule() }
    ns.db.chars[key] = c
    -- Pace samples are ratios against the guide curve; older raw-XP samples are dropped.
    c.paceSamples = c.paceSamples or {}
    c.pace = nil
    c.name, c.realm = name, realm
    c.class = select(2, UnitClass("player"))
    ns.char = c
end

local function detectResetOffset()
    local offset = Day.DetectOffset()
    if offset then
        ns.db.resetOffset = offset
    end
    Day.offset = ns.db.resetOffset or Day.offset
end

-- Public helpers used by the UI ------------------------------------------

-- XP/hour at your current level, and whether it's measured (false = guide estimate).
function ns.XPPerHour()
    return Pace.XPPerHour(ns.char.paceSamples, ns.char.level)
end

function ns.StatusFor(c)
    if c == ns.char then
        return ns.status
    end
    local status = Plan.Status(c, Day.Today(), Pace.XPPerHour(c.paceSamples or {}, c.level))
    status.paceMeasured = Pace.Factor(c.paceSamples or {}) ~= nil
    return status
end

local function computeStatus()
    local c = ns.char
    if not c.goal then
        ns.status = nil
        return
    end
    local xph, measured = ns.XPPerHour()
    ns.status = Plan.Status(c, Day.Today(), xph, Quests.banked.xp)
    ns.status.paceMeasured = measured
end

-- Characters, most recently played first.
function ns.CharacterList()
    local list = {}
    for _, c in pairs(ns.db.chars) do
        if c.total then
            list[#list + 1] = c
        end
    end
    table.sort(list, function(a, b) return (a.lastSeen or 0) > (b.lastSeen or 0) end)
    return list
end

-- After goal or schedule edits: re-target today and redraw.
function ns.PlanChanged()
    Plan.RetargetToday(ns.char, Day.Today())
    computeStatus()
    ns.Refresh()
end

-- Applies an editor draft { level, date, weights }. Returns true, or false
-- and the reason it can't be used.
function ns.ApplyDraft(draft)
    local c = ns.char
    local problem = ns.Editors.Problem(c, draft)
    if problem then
        return false, problem
    end
    for i = 1, 7 do
        c.schedule.weights[i] = draft.weights[i]
    end
    if not c.goal or c.goal.level ~= draft.level or c.goal.date ~= draft.date or Plan.Mode(c) ~= draft.mode then
        Plan.SetGoal(c, draft.level, draft.date, Day.Today(), draft.mode)
    end
    ns.PlanChanged()
    return true
end

-- Today's play time, e.g. after losing 30 minutes to AFK. nil = back to normal.
function ns.SetTodayHours(hours)
    local c, today = ns.char, Day.Today()
    Plan.SetDayHours(c, today, hours, today)
    computeStatus()
    ns.Refresh()
    local s = ns.status
    if s then
        ns.Print(string.format("Today's time: %s. Target now %s XP; the rest moves to later days.",
            ns.FormatDuration(Plan.Weight(c, today) * 3600), ns.FormatXP(s.target)))
    end
end

function ns.AdjustTodayHours(delta)
    local today = Day.Today()
    ns.SetTodayHours(math.max(0, Plan.Weight(ns.char, today) + delta))
end

function ns.ResetCharacter()
    local c = ns.char
    c.goal, c.lastDay, c.setupDone = nil, nil, nil
    c.days, c.paceSamples, c.schedule = {}, {}, Plan.DefaultSchedule()
    ns.Update()
    ns.Print("Character data reset.")
end

function ns.OpenMain()
    if not ns.char.goal and ns.char.level < XP.MAX_LEVEL then
        ns.Wizard.Open()
    else
        ns.Planner.Toggle()
    end
end

-- Observation ---------------------------------------------------------------

local function checkTargetReached(rec)
    if not ns.char.goal or rec.target == 0 or rec.hit or rec.gained < rec.target then
        return
    end
    rec.hit = true
    if ns.db.settings.targetToast then
        ns.Toast.Show("Daily target reached", string.format("%s XP today · level %.1f", ns.FormatXP(rec.gained), XP.LevelAt(ns.char.total)))
    end
end

-- Set by PLAYER_LEVEL_UP. Until UnitLevel() reports it, the client may mix the
-- old level with the new XP (or the reverse), so readings wait for it.
local pendingLevel, settleTries = nil, 0
local SETTLE_DELAY, MAX_SETTLE_TRIES = 0.2, 25

function ns.Update()
    local c = ns.char
    if not c then
        return -- an event arrived before PLAYER_LOGIN
    end
    local level, xp = UnitLevel("player"), UnitXP("player")
    if pendingLevel then
        if level < pendingLevel and settleTries < MAX_SETTLE_TRIES then
            settleTries = settleTries + 1
            C_Timer.After(SETTLE_DELAY, ns.Update)
            return
        end
        pendingLevel = nil
    end
    local maxXP = UnitXPMax("player")
    if level < XP.MAX_LEVEL and maxXP > 0 and XP.perLevel[level] ~= maxXP then
        XP.Observe(level, maxXP)
        ns.db.xpTable[level] = maxXP
    end
    ns.restedXP = GetXPExhaustion and GetXPExhaustion() or 0
    local before = c.total
    local rec = Plan.Observe(c, Day.Today(), level, xp)
    if before then
        Pace.AddXP(c.total - before)
    end
    c.lastSeen = time()
    checkTargetReached(rec)
    computeStatus()
    ns.Refresh()
end

local function loginSummary()
    local s = ns.status
    if not s then
        ns.Print("No leveling goal yet. Type /pt60 to set one up.")
        return
    end
    local label = ns.Theme.StateOf(s)
    if s.state == "done" then
        ns.Print("Goal reached: level " .. s.goalLevel .. ".")
    elseif s.offToday then
        ns.Print(string.format("Rest day. %s · level %d by %s.", label, s.goalLevel, Day.Short(s.deadline)))
    else
        local time = s.leftSeconds and (" (" .. ns.FormatDuration(s.leftSeconds) .. ")") or ""
        ns.Print(string.format("Today: %s XP%s, %.2f levels. %s · level %d by %s.",
            ns.FormatXP(s.left), time, s.levelsLeftToday, label, s.goalLevel, Day.Short(s.deadline)))
    end
end

-- Events ------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {}

function handlers.ADDON_LOADED(name)
    if name == ADDON then
        initDB()
        events:UnregisterEvent("ADDON_LOADED")
    end
end

function handlers.PLAYER_LOGIN()
    detectResetOffset()
    loadCharacter()
    ns.Theme.Load()
    ns.Update()
    ns.Tracker.Build()
    ns.Broker.Build()

    C_Timer.NewTicker(60, function()
        Pace.Tick(ns.char.paceSamples, UnitAffectingCombat("player"), UnitLevel("player"))
        ns.Update()
    end)

    local c = ns.char
    if not c.goal and not c.setupSeen and c.level < XP.MAX_LEVEL then
        c.setupSeen = true
        C_Timer.After(3, ns.Wizard.Open)
    elseif ns.db.settings.loginSummary then
        C_Timer.After(4, loginSummary)
    end
end

function handlers.PLAYER_ENTERING_WORLD()
    detectResetOffset()
    ns.Update()
end

handlers.PLAYER_XP_UPDATE = ns.Update
handlers.UPDATE_EXHAUSTION = ns.Update

function handlers.QUEST_LOG_UPDATE()
    Quests.QueueScan(function()
        computeStatus()
        ns.Refresh()
    end)
end
function handlers.PLAYER_LEVEL_UP(newLevel)
    pendingLevel, settleTries = newLevel, 0
    ns.Update()
end

function handlers.PLAYER_REGEN_DISABLED()
    Pace.MarkActive()
end

for event in pairs(handlers) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)

-- Slash command -------------------------------------------------------------

local HELP = {
    "/pt60 - open the planner (or the setup wizard if there is no goal)",
    "/pt60 setup - run the setup wizard",
    "/pt60 goal <level> <DD/MM/YYYY> - set a goal directly",
    "/pt60 status - print today's target",
    "/pt60 afk <minutes> - take time off today (e.g. /pt60 afk 30)",
    "/pt60 time <hours> - set today's play time (e.g. /pt60 time 1.5)",
    "/pt60 tracker - show / hide the tracker",
    "/pt60 lock - lock / unlock the tracker",
    "/pt60 export | import - JSON export and import",
}

local COMMANDS = {
    [""] = ns.OpenMain,
    setup = function() ns.Wizard.Open() end,
    status = loginSummary,
    tracker = function()
        ns.db.settings.showTracker = not ns.db.settings.showTracker
        ns.Refresh()
    end,
    lock = function() ns.Tracker.ToggleLock() end,
    afk = function(args)
        local minutes = tonumber(args)
        if not minutes or not ns.char.goal then
            ns.Print("Usage: /pt60 afk 30  (needs a goal)")
            return
        end
        ns.AdjustTodayHours(-minutes / 60)
    end,
    time = function(args)
        local hours = tonumber(args)
        if not hours or not ns.char.goal then
            ns.Print("Usage: /pt60 time 1.5  (needs a goal)")
            return
        end
        ns.SetTodayHours(hours)
    end,
    export = function() ns.ExportWindow.Open("export") end,
    import = function() ns.ExportWindow.Open("import") end,
    goal = function(args)
        local level, typed = args:match("^(%d+)%s+(%S+)$")
        local dateKey = Day.ParseInput(typed)
        if not (level and dateKey) then
            ns.Print("Usage: /pt60 goal 60 12/12/2026")
            return
        end
        local draft = ns.Editors.DraftFrom(ns.char)
        draft.level, draft.date = tonumber(level), dateKey
        local ok, problem = ns.ApplyDraft(draft)
        ns.Print(ok and string.format("Goal set: level %s by %s.", level, Day.DisplayKey(dateKey)) or problem)
    end,
}

SLASH_PT601 = "/pt60"
SlashCmdList.PT60 = function(input)
    local command, args = input:match("^%s*(%S*)%s*(.-)%s*$")
    local handler = COMMANDS[command:lower()]
    if handler then
        handler(args)
    else
        for _, line in ipairs(HELP) do
            ns.Print(line)
        end
    end
end
