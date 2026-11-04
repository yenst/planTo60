local _, ns = ...

local Theme, W, Day, XP = ns.Theme, ns.W, ns.Day, ns.XP

-- First-run setup: welcome -> goal -> time -> style -> tracker -> review.
local Wizard = {}
ns.Wizard = Wizard

local WIDTH, HEIGHT = 580, 450
local CONTENT_W = WIDTH - 48

local window
local draft = { weights = {} } -- filled in place on Open(); the step editors keep this reference
local steps = {}
local current = 1

local function paragraph(parent, text, y, color)
    local fs = W.Text(parent, 12, color)
    fs:SetPoint("TOPLEFT", 0, y)
    fs:SetWidth(CONTENT_W)
    fs:SetWordWrap(true)
    fs:SetSpacing(3)
    fs:SetText(text)
    return fs
end

local function usage()
    return ns.Editors.Usage(ns.char, draft, ns.XPPerHour())
end

local function heading(parent, text)
    local fs = W.Text(parent, 16, Theme.accent)
    fs:SetPoint("TOPLEFT")
    fs:SetText(text)
    return fs
end

local function summaryText(parent, y)
    local fs = paragraph(parent, "", y)
    W.SetFont(fs, 11)
    return fs
end

local STEPS = {
    {
        title = "Welcome",
        build = function(page)
            heading(page, "Plan your leveling")
            page.intro = paragraph(page, "", -32)
            paragraph(page, "Pick a target level and a deadline, then tell planTo60 how much you play on each day of the week. "
                .. "It works out how much XP you need every day and recalculates after each daily reset: a missed day is "
                .. "spread over the days that remain, and getting ahead makes later days lighter.", -78, Theme.muted)
        end,
        update = function(page)
            local c = ns.char
            page.intro:SetText(string.format("%s is level %d with %s XP into the level.", c.name, c.level, ns.FormatXP(c.xp)))
        end,
    },
    {
        title = "Goal",
        validate = true,
        build = function(page)
            heading(page, "What's the goal?")
            paragraph(page, "Target level", -36, Theme.muted)
            page.level = ns.Editors.Level(page, draft, function() Wizard.Update() end)
            page.level:SetPoint("TOPLEFT", 0, -56)
            paragraph(page, "Reach it by (the deadline day counts as a play day)", -96, Theme.muted)
            page.deadline = ns.Editors.Deadline(page, draft, function() Wizard.Update() end)
            page.deadline:SetPoint("TOPLEFT", 0, -116)
            page.summary = summaryText(page, -180)
        end,
        update = function(page)
            page.level:Update()
            page.deadline:Update()
            page.summary:SetText(ns.Editors.Summary(ns.char, draft, ns.XPPerHour()))
        end,
    },
    {
        title = "Time",
        validate = true,
        build = function(page)
            heading(page, "How much can you play?")
            paragraph(page, "Set the hours you can play on each weekday. The filled part of each bar is what "
                .. "your goal needs. Single days can be marked off later in the calendar.", -32, Theme.muted)
            page.weekly = ns.Editors.Weekly(page, draft, function() Wizard.Update() end, usage)
            page.weekly:SetPoint("TOPLEFT", 0, -76)
            page.summary = summaryText(page, -266)
        end,
        update = function(page)
            page.weekly:Update()
            local xph, measured = ns.XPPerHour()
            page.summary:SetText(ns.Editors.Summary(ns.char, draft, xph, measured, true))
        end,
    },
    {
        title = "Style",
        validate = true,
        build = function(page)
            heading(page, "How should days be planned?")
            page.mode = ns.Editors.Mode(page, draft, function() Wizard.Update() end)
            page.mode:SetPoint("TOPLEFT", 0, -36)
            paragraph(page, Theme.Hex(Theme.accent) .. "Same time every day|r (recommended): XP comes faster at "
                .. "higher levels, so targets start lower and grow as you level while each day takes about the same "
                .. "share of your time.\n\n" .. Theme.Hex(Theme.accent) .. "Same XP every day|r: one fixed XP "
                .. "number. Early days take noticeably longer than late ones.", -72, Theme.muted)
            page.summary = summaryText(page, -190)
        end,
        update = function(page)
            page.mode:Update()
            page.summary:SetText(ns.Editors.Summary(ns.char, draft, ns.XPPerHour()))
        end,
    },
    {
        title = "Tracker",
        build = function(page)
            local settings = ns.db.settings
            heading(page, "Keeping track")
            paragraph(page, "A small tracker shows today's progress. Drag it to move it, right-click to lock it. "
                .. "With EllesmereUI installed it also shows up in EllesmereUI's unlock mode.", -32, Theme.muted)
            page.toggles = {}
            local y = -90
            for _, entry in ipairs({
                { "Show the tracker", "showTracker" },
                { "Summary in chat at login", "loginSummary" },
                { "Toast and sound when today's target is reached", "targetToast" },
            }) do
                local t = W.Toggle(page, entry[1], function() return settings[entry[2]] end, function(v)
                    settings[entry[2]] = v
                    ns.Refresh()
                end)
                t:SetPoint("TOPLEFT", 0, y)
                y = y - 26
                page.toggles[#page.toggles + 1] = t
            end
        end,
        update = function(page)
            for _, t in ipairs(page.toggles) do
                t:Update()
            end
        end,
    },
    {
        title = "Review",
        build = function(page)
            heading(page, "Ready")
            page.goal = paragraph(page, "", -34)
            page.summary = summaryText(page, -60)
            paragraph(page, "Open the planner any time with /pt60 or by clicking the tracker.", -140, Theme.muted)
        end,
        update = function(page)
            local start = Day.StartOfKey(draft.date)
            page.goal:SetText(string.format("Level %d by %s.", draft.level, Day.Pretty(start)))
            page.summary:SetText(ns.Editors.Summary(ns.char, draft, ns.XPPerHour()))
        end,
    },
}

local function finish()
    if ns.ApplyDraft(draft) then
        ns.char.setupDone = true
        window:Hide()
        ns.Print(string.format("Goal set: level %d by %s. Today's target: %s XP.", draft.level, Day.DisplayKey(draft.date), ns.FormatXP(ns.status.target)))
        ns.Planner.Show("overview")
    end
end

local function build()
    window = W.Window("pt60Wizard", WIDTH, HEIGHT, "Setup")
    window:SetFrameStrata("FULLSCREEN_DIALOG")

    window.progress = W.Text(window, 11, Theme.muted)
    window.progress:SetPoint("BOTTOMLEFT", 24, 22)
    window.back = W.Button(window, "Back", 90, 26, function()
        current = math.max(1, current - 1)
        Wizard.Update()
    end)
    window.back:SetPoint("BOTTOMRIGHT", -120, 16)
    window.next = W.Button(window, "Next", 90, 26, function()
        if current == #STEPS then
            finish()
        else
            current = current + 1
            Wizard.Update()
        end
    end)
    window.next:SetPoint("BOTTOMRIGHT", -20, 16)

    for i, step in ipairs(STEPS) do
        local page = CreateFrame("Frame", nil, window)
        page:SetPoint("TOPLEFT", 24, -54)
        page:SetPoint("BOTTOMRIGHT", -24, 56)
        step.build(page)
        steps[i] = page
    end
end

function Wizard.Update()
    local step = STEPS[current]
    for i, page in ipairs(steps) do
        page:SetShown(i == current)
    end
    step.update(steps[current])

    local names = {}
    for i, s in ipairs(STEPS) do
        names[i] = i == current and (Theme.Hex(Theme.accent) .. s.title .. "|r") or s.title
    end
    window.progress:SetText(table.concat(names, "  ·  "))
    window.back:SetShown(current > 1)
    window.next:SetLabel(current == #STEPS and "Start" or "Next")

    local blocked = step.validate and ns.Editors.Problem(ns.char, draft)
    window.next:SetEnabled(not blocked)
    window.next:SetAlpha(blocked and 0.4 or 1)
end

function Wizard.Open()
    if ns.char.level >= XP.MAX_LEVEL then
        ns.Print("This character is already at the level cap.")
        return
    end
    for k, v in pairs(ns.Editors.DraftFrom(ns.char)) do
        draft[k] = v
    end
    if not window then
        build()
    end
    current = 1
    window:Show()
    Wizard.Update()
end
