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

local MODE_INFO = {
    time = "Same time every day (recommended)\nTargets start lower and grow as you level; each day takes about the same share of your time.",
    xp = "Same XP every day\nOne fixed XP number per day. Early days take much longer than late ones.",
}

local function warning()
    return ns.Editors.Warning(ns.char, draft, ns.XPPerHour())
end

local function label(parent, text, y)
    local fs = W.Text(parent, 11, Theme.muted)
    fs:SetPoint("TOPLEFT", 0, y)
    fs:SetText(text)
    return fs
end

local STEPS = {
    {
        title = "Welcome",
        build = function(page)
            heading(page, "Plan your leveling")
            label(page, "Set a goal, a deadline and your play time.", -32)
            local logo = page:CreateTexture(nil, "ARTWORK")
            logo:SetTexture(ns.LOGO)
            logo:SetSize(150, 150)
            logo:SetPoint("CENTER", 0, -20)
        end,
        update = function() end,
    },
    {
        title = "Goal",
        validate = true,
        build = function(page)
            heading(page, "What's the goal?")
            label(page, "Target level", -40)
            page.level = ns.Editors.Level(page, draft, function() Wizard.Update() end)
            page.level:SetPoint("TOPLEFT", 0, -58)
            label(page, "Deadline", -100)
            page.deadline = ns.Editors.Deadline(page, draft, function() Wizard.Update() end)
            page.deadline:SetPoint("TOPLEFT", 0, -118)
            page.warning = paragraph(page, "", -160)
        end,
        update = function(page)
            page.level:Update()
            page.deadline:Update()
            local problem = ns.Editors.Problem(ns.char, draft)
            page.warning:SetText(problem and (Theme.Hex(Theme.warn) .. problem .. "|r") or "")
        end,
    },
    {
        title = "Time",
        validate = true,
        build = function(page)
            heading(page, "How much can you play?")
            page.weekly = ns.Editors.Weekly(page, draft, function() Wizard.Update() end, usage)
            page.weekly:SetPoint("TOPLEFT", 0, -36)
            page.warning = paragraph(page, "", -224)
        end,
        update = function(page)
            page.weekly:Update()
            page.warning:SetText(warning())
        end,
    },
    {
        title = "Style",
        validate = true,
        build = function(page)
            heading(page, "How should days be planned?")
            page.mode = ns.Editors.Mode(page, draft, function() Wizard.Update() end, function(key) return MODE_INFO[key] end)
            page.mode:SetPoint("TOPLEFT", 0, -40)
            page.warning = paragraph(page, "", -80)
        end,
        update = function(page)
            page.mode:Update()
            page.warning:SetText(warning())
        end,
    },
    {
        title = "Tracker",
        build = function(page)
            local settings = ns.db.settings
            heading(page, "Keeping track")
            page.toggles = {}
            local y = -40
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
            page.goal = paragraph(page, "", -36)
            page.need = paragraph(page, "", -58)
            label(page, "/pt60 opens the planner", -96)
        end,
        update = function(page)
            page.goal:SetText(string.format("Level %d by %s", draft.level, Day.Pretty(Day.StartOfKey(draft.date))))
            local share = usage()
            page.need:SetText(share and ns.Editors.NeedLine(share, draft.weights) or warning())
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
