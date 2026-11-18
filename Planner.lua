local _, ns = ...

local Theme, W, Day = ns.Theme, ns.W, ns.Day

local Planner = {}
ns.Planner = Planner

local WIDTH, HEIGHT = 720, 540
local SIDEBAR = 140
local PAD = 16
local CONTENT_W = WIDTH - SIDEBAR - PAD * 2
local HISTORY_ROWS = 9

local window
local pages, tabs = {}, {}
local PAGE_ORDER = {
    { key = "overview", label = "Overview" },
    { key = "goal", label = "Goal & schedule" },
    { key = "history", label = "History" },
    { key = "characters", label = "Characters" },
    { key = "settings", label = "Settings" },
}

local function heading(parent, text, y)
    local fs = W.Text(parent, 13, Theme.accent)
    fs:SetPoint("TOPLEFT", 0, y)
    fs:SetText(text)
    return fs
end

-- Overview ----------------------------------------------------------------

-- Title and one value; details live in the card's tooltip (`describe`).
local function statCard(parent, title, describe)
    local card = W.Panel(parent, Theme.bgRaised)
    local width = (CONTENT_W - 3 * 8) / 4
    card:SetSize(width, 52)
    card.title = W.Text(card, 10, Theme.muted)
    card.title:SetPoint("TOPLEFT", 8, -7)
    card.title:SetText(title:upper())
    card.value = W.Text(card, 15)
    card.value:SetPoint("TOPLEFT", 8, -22)
    card.value:SetWidth(width - 16)
    card:EnableMouse(true)
    card:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(Theme.accent))
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        describe(GameTooltip, ns.status)
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(Theme.border))
        GameTooltip:Hide()
    end)
    return card
end

local function detail(tip, left, right)
    tip:AddDoubleLine(left, right, 0.7, 0.7, 0.7, 1, 1, 1)
end

local CARDS = {
    { "Today", function(tip, s)
        detail(tip, "Today", ns.FormatXP(s.gained) .. " / " .. ns.FormatXP(s.target) .. " XP")
        detail(tip, "Goal", string.format("Level %d by %s", s.goalLevel, Day.Short(s.deadline)))
    end },
    { "To go", function(tip, s)
        detail(tip, "Levels to " .. s.goalLevel, string.format("%.1f", s.remainingLevels))
    end },
    { "Deadline", function(tip, s)
        detail(tip, "Days left", tostring(s.daysLeft))
    end },
    { "Time needed", function(tip, s)
        detail(tip, "Of your hours", string.format("%s of %s", ns.FormatDuration(s.hoursNeeded * 3600), ns.FormatDuration(s.hoursAvailable * 3600)))
        detail(tip, "Pace", ns.FormatXP(s.xph) .. " XP/h" .. (s.paceMeasured and "" or " (guide)"))
    end },
}

-- Small editor that opens under the Deadline card. Edits apply right away.
local function deadlinePopup(page, card)
    local popup = W.Panel(page, Theme.bgRaised)
    popup:SetSize(320, 62)
    popup:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -4)
    popup:SetFrameLevel(page:GetFrameLevel() + 20)
    popup:SetBackdropBorderColor(unpack(Theme.accent))
    popup:EnableMouse(true)
    popup:Hide()
    local draft = ns.Editors.DraftFrom(ns.char)
    popup.editor = ns.Editors.Deadline(popup, draft, function()
        local ok, problem = ns.ApplyDraft(draft)
        popup.problem:SetText(ok and "" or (Theme.Hex(Theme.warn) .. problem .. "|r"))
    end)
    popup.editor:SetPoint("TOPLEFT", 10, -10)
    popup.problem = W.Text(popup, 10)
    popup.problem:SetPoint("BOTTOMLEFT", 10, 8)
    local done = W.Button(popup, "Done", 56, 22, function() popup:Hide() end)
    done:SetPoint("TOPRIGHT", -10, -10)
    function popup:Open()
        for k, v in pairs(ns.Editors.DraftFrom(ns.char)) do
            draft[k] = v
        end
        self.problem:SetText("")
        self.editor:Update()
        self:Show()
    end
    popup.draft = draft
    return popup
end

-- Shifts the deadline by `days` (7x with Shift), e.g. from the mouse wheel.
local function shiftDeadline(days)
    if IsShiftKeyDown() then
        days = days * 7
    end
    local draft = ns.Editors.DraftFrom(ns.char)
    local start = Day.StartOfKey(draft.date) + days * ns.DAY
    draft.date = Day.Key(math.max(start, Day.Today()))
    ns.ApplyDraft(draft)
end

local function buildOverview(page)
    page.cards = {}
    for i, entry in ipairs(CARDS) do
        local card = statCard(page, entry[1], entry[2])
        card:SetPoint("TOPLEFT", (i - 1) * (card:GetWidth() + 8), 0)
        page.cards[entry[1]] = card
    end
    page.todayBar = W.Bar(page.cards.Today, 4)
    page.todayBar:SetPoint("BOTTOMLEFT", 8, 7)
    page.todayBar:SetPoint("BOTTOMRIGHT", -8, 7)

    -- The Deadline card also opens the deadline editor and takes the wheel.
    local deadlineCard = page.cards.Deadline
    page.deadlinePopup = deadlinePopup(page, deadlineCard)
    deadlineCard:EnableMouseWheel(true)
    deadlineCard:SetScript("OnMouseUp", function()
        if page.deadlinePopup:IsShown() then
            page.deadlinePopup:Hide()
        else
            page.deadlinePopup:Open()
        end
    end)
    deadlineCard:SetScript("OnMouseWheel", function(_, delta) shiftDeadline(delta) end)
    page:SetScript("OnHide", function() page.deadlinePopup:Hide() end)

    -- Today's time: [-30m] [+30m] [Reset], for AFK breaks or extra time.
    local reset = W.Button(page, "Reset", 52, 20, function() ns.SetTodayHours(nil) end)
    reset:SetPoint("TOPRIGHT", 0, -64)
    local plus = W.Button(page, "+30m", 48, 20, function() ns.AdjustTodayHours(0.5) end)
    plus:SetPoint("RIGHT", reset, "LEFT", -4, 0)
    local minus = W.Button(page, "-30m", 48, 20, function() ns.AdjustTodayHours(-0.5) end)
    minus:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    local label = W.Text(page, 11, Theme.muted, "RIGHT")
    label:SetPoint("RIGHT", minus, "LEFT", -8, 0)
    label:SetText("Today's time")
    page.todayControls = { reset, plus, minus, label }

    page.calendar = ns.Calendar.Create(page, CONTENT_W)
    page.calendar:SetPoint("TOPLEFT", 0, -94)

    page.empty = W.Text(page, 13, Theme.muted, "CENTER")
    page.empty:SetPoint("CENTER", 0, 40)
    page.empty:SetText("No goal yet.")
    page.setup = W.Button(page, "Set up a goal", 140, 26, function() ns.Wizard.Open() end)
    page.setup:SetPoint("TOP", page.empty, "BOTTOM", 0, -12)

    function page:Update()
        local s = ns.status
        self.calendar:SetShown(s ~= nil)
        for _, child in ipairs(self.todayControls) do
            child:SetShown(s ~= nil)
        end
        for _, card in pairs(self.cards) do
            card:SetShown(s ~= nil)
        end
        self.empty:SetShown(s == nil)
        self.setup:SetShown(s == nil)
        if not s then
            return
        end

        local cards = self.cards
        cards.Today.value:SetText(s.offToday and "Rest day" or string.format("%.2f levels", s.targetLevels))
        self.todayBar:SetProgress(s.target > 0 and s.gained / s.target or 1, nil, s.target > 0 and s.banked / s.target or 0)
        cards["To go"].value:SetText(ns.FormatXP(s.remaining) .. " XP")
        cards.Deadline.value:SetText(Day.Short(s.deadline))
        cards["Time needed"].value:SetText(Theme.Hex(s.usage > 1 and Theme.bad or Theme.text) .. math.floor(s.usage * 100 + 0.5) .. "%|r")
        self.calendar:Update()
        if self.deadlinePopup:IsShown() then
            self.deadlinePopup.editor:Update()
        end
    end
end

-- Goal --------------------------------------------------------------------

local function summaryFor(draft)
    local xph, measured = ns.XPPerHour(draft)
    return ns.Editors.Summary(ns.char, draft, xph, measured, true)
end

local function warningFor(draft)
    return ns.Editors.Warning(ns.char, draft, ns.XPPerHour(draft))
end

local function buildGoal(page)
    -- A valid edit is applied straight away (which refreshes this page); an
    -- invalid one only updates the summary so the warning stays visible.
    local function changed()
        if not ns.ApplyDraft(page.draft) then
            page.summary:SetText(warningFor(page.draft))
            page.weekly:Update()
        end
    end
    page.draft = ns.Editors.DraftFrom(ns.char)

    heading(page, "Target", 0)
    page.level = ns.Editors.Level(page, page.draft, changed)
    page.level:SetPoint("TOPLEFT", 0, -22)
    local deadlineHeading = heading(page, "Deadline", 0)
    deadlineHeading:SetPoint("TOPLEFT", 180, 0)
    page.deadline = ns.Editors.Deadline(page, page.draft, changed)
    page.deadline:SetPoint("TOPLEFT", 180, -22)
    local playedHeading = heading(page, "/played to 60", 0)
    playedHeading:SetPoint("TOPLEFT", 380, 0)
    page.played = ns.Editors.Played(page, page.draft, changed)
    page.played:SetPoint("TOPLEFT", 380, -22)

    heading(page, "Time you can play", -84)
    page.weekly = ns.Editors.Weekly(page, page.draft, changed, function()
        return ns.Editors.Usage(ns.char, page.draft, ns.XPPerHour(page.draft))
    end)
    page.weekly:SetPoint("TOPLEFT", 0, -106)

    heading(page, "Plan style", -324)
    page.mode = ns.Editors.Mode(page, page.draft, changed, function() return summaryFor(page.draft) end)
    page.mode:SetPoint("TOPLEFT", 0, -346)
    page.summary = W.Text(page, 11)
    page.summary:SetPoint("TOPLEFT", 0, -378)
    page.summary:SetWidth(CONTENT_W)
    page.summary:SetWordWrap(true)
    page.summary:SetSpacing(3)

    local wizard = W.Button(page, "Run setup wizard again", 170, 24, function() ns.Wizard.Open() end)
    wizard:SetPoint("BOTTOMLEFT", 0, 0)

    function page:Update()
        local fresh = ns.Editors.DraftFrom(ns.char)
        for k, v in pairs(fresh) do
            self.draft[k] = v
        end
        self.level:Update()
        self.mode:Update()
        self.deadline:Update()
        self.played:Update()
        self.weekly:Update()
        self.summary:SetText(warningFor(self.draft))
    end
end

-- History -----------------------------------------------------------------

local function buildHistory(page)
    page.chart = ns.Chart.Create(page, CONTENT_W, 200)
    page.chart:SetPoint("TOPLEFT")

    local columns = { { "Date", 0, "LEFT" }, { "Level", 150, "RIGHT" }, { "Earned", 250, "RIGHT" }, { "Target", 350, "RIGHT" }, { "Result", CONTENT_W - 8, "RIGHT" } }
    local function rowTexts(parent, y, color)
        local texts = {}
        for i, col in ipairs(columns) do
            local fs = W.Text(parent, 11, color, col[3])
            if col[3] == "LEFT" then
                fs:SetPoint("TOPLEFT", col[2] + 8, y)
            else
                fs:SetPoint("TOPRIGHT", parent, "TOPLEFT", col[2], y)
            end
            texts[i] = fs
        end
        return texts
    end
    local header = rowTexts(page, -212, Theme.muted)
    for i, col in ipairs(columns) do
        header[i]:SetText(col[1]:upper())
    end
    page.rows = {}
    for r = 1, HISTORY_ROWS do
        page.rows[r] = rowTexts(page, -212 - r * 18)
    end
    page.offset = 0
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, math.min(#self.keys - HISTORY_ROWS, self.offset - delta * 3))
        self:Update()
    end)

    function page:Update()
        self.chart:Update()
        local days = ns.char.days
        self.keys = {}
        for key in pairs(days) do
            self.keys[#self.keys + 1] = key
        end
        table.sort(self.keys, function(a, b) return a > b end)
        for r, texts in ipairs(self.rows) do
            local key = self.keys[r + self.offset]
            local rec = key and days[key]
            for _, fs in ipairs(texts) do
                fs:SetText("")
            end
            if rec then
                texts[1]:SetText(Day.Pretty(Day.StartOfKey(key)))
                texts[2]:SetText(string.format("%.2f", rec.level))
                texts[3]:SetText(ns.FormatXP(rec.gained))
                texts[4]:SetText(rec.target > 0 and ns.FormatXP(rec.target) or "off")
                if rec.target > 0 then
                    local pct = rec.gained / rec.target
                    texts[5]:SetText(Theme.Hex(pct >= 1 and Theme.accent or Theme.warn) .. math.floor(pct * 100) .. "%|r")
                end
            end
        end
    end
end

-- Characters --------------------------------------------------------------

local CHARACTER_ROWS = 14

-- ✓ when on track, ahead or done; ✗ when behind, at risk or overdue.
local function statusIcon(s)
    local _, _, icon = Theme.StateOf(s)
    return Theme.Icon(icon == "ok" and "ok" or "bad", 14)
end

local function characterLine(c)
    local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
    local name = classColor and string.format("|c%s%s|r", classColor.colorStr, c.name) or c.name
    if not c.goal then
        return name, tostring(c.level), "-", ""
    end
    local s = ns.StatusFor(c)
    return name, string.format("%.1f", s.level), tostring(s.goalLevel), statusIcon(s)
end

local function buildCharacters(page)
    local columns = { { "Character", 0 }, { "Level", 180 }, { "Goal", 260 }, { "Status", 340 } }
    for _, col in ipairs(columns) do
        local fs = W.Text(page, 10, Theme.muted)
        fs:SetPoint("TOPLEFT", col[2], 0)
        fs:SetText(col[1]:upper())
    end
    page.rows = {}
    for r = 1, CHARACTER_ROWS do
        local row = {}
        for i, col in ipairs(columns) do
            row[i] = W.Text(page, 12)
            row[i]:SetPoint("TOPLEFT", col[2], -r * 24)
        end
        page.rows[r] = row
    end

    function page:Update()
        local list = ns.CharacterList()
        for r, row in ipairs(self.rows) do
            local c = list[r]
            local values = c and { characterLine(c) } or {}
            for i, fs in ipairs(row) do
                fs:SetText(values[i] or "")
            end
        end
    end
end

-- Settings ----------------------------------------------------------------

local ROW_H = 30
local ROW_PAD = 12

-- One card per section: rows with the label on the left and the control on
-- the right edge, so every control sits on the same axis.
local function settingsCard(page, title, y, rows, border)
    heading(page, title, y)
    local card = W.Panel(page, Theme.bgRaised)
    card:SetPoint("TOPLEFT", 0, y - 20)
    card:SetSize(CONTENT_W, #rows * ROW_H)
    if border then
        card:SetBackdropBorderColor(unpack(border))
    end
    for i, build in ipairs(rows) do
        local row = CreateFrame("Frame", nil, card)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetSize(CONTENT_W, ROW_H)
        if i > 1 then
            local line = W.Line(row)
            line:SetPoint("TOPLEFT", ROW_PAD, 0)
            line:SetPoint("TOPRIGHT", -ROW_PAD, 0)
        end
        build(row)
    end
    return y - 20 - #rows * ROW_H - 18
end

local function rowLabel(row, text)
    row.label = W.Text(row, 12)
    row.label:SetPoint("LEFT", ROW_PAD, 0)
    row.label:SetText(text)
end

-- Rows that depend on another setting dim while it is off; a cover over the
-- control swallows clicks and the wheel.
local covers = {}
local function setRowEnabled(row, on)
    row.label:SetTextColor(unpack(on and Theme.text or Theme.muted))
    local control = row.control
    local cover = covers[control]
    if not cover then
        cover = CreateFrame("Frame", nil, control)
        cover:SetAllPoints()
        cover:SetFrameLevel(control:GetFrameLevel() + 10)
        cover:EnableMouse(true)
        cover:EnableMouseWheel(true)
        covers[control] = cover
    end
    cover:SetShown(not on)
    control:SetAlpha(on and 1 or 0.35)
end

local function buildSettings(page)
    local settings = ns.db.settings
    local toggles, dependents = {}, {}

    local function set(key, v)
        settings[key] = v
        ns.Refresh()
    end

    -- The whole row is the click target; the box sits on the right edge.
    local function toggleRow(label, key, parentKey)
        return function(row)
            rowLabel(row, label)
            local hit = CreateFrame("Button", nil, row)
            hit:SetAllPoints()
            local box = W.Panel(hit, Theme.bg)
            box:SetSize(16, 16)
            box:SetPoint("RIGHT", -ROW_PAD, 0)
            local check = box:CreateTexture(nil, "OVERLAY")
            check:SetPoint("TOPLEFT", 3, -3)
            check:SetPoint("BOTTOMRIGHT", -3, 3)
            check:SetColorTexture(unpack(Theme.accent))
            hit:SetScript("OnClick", function() set(key, not settings[key]) end)
            hit:SetScript("OnEnter", function() box:SetBackdropBorderColor(unpack(Theme.accent)) end)
            hit:SetScript("OnLeave", function() box:SetBackdropBorderColor(unpack(Theme.border)) end)
            row.control = hit
            function row:Update()
                check:SetShown(settings[key])
            end
            toggles[#toggles + 1] = row
            if parentKey then
                dependents[#dependents + 1] = { row, parentKey }
            end
        end
    end

    local function controlRow(label, parentKey, makeControl)
        return function(row)
            rowLabel(row, label)
            row.control = makeControl(row)
            row.control:SetPoint("RIGHT", -ROW_PAD, 0)
            if parentKey then
                dependents[#dependents + 1] = { row, parentKey }
            end
        end
    end

    local scale
    local y = settingsCard(page, "Tracker", 0, {
        toggleRow("Show tracker", "showTracker"),
        toggleRow("Lock position", "lockTracker", "showTracker"),
        controlRow("Scale", "showTracker", function(row)
            scale = W.Stepper(row, 110, W.Range(0.6, 1.61, 0.1), function(v) return string.format("%d%%", v * 100 + 0.5) end,
                function() return settings.trackerScale end,
                function(v) set("trackerScale", v) end)
            return scale
        end),
        controlRow("Position", "showTracker", function(row)
            return W.Button(row, "Reset", 110, 22, function() ns.Tracker.ResetPosition() end)
        end),
    })

    if ns.Broker.HasMinimapButton() then
        y = settingsCard(page, "Minimap", y, {
            toggleRow("Show minimap button", "minimapButton"),
        })
    end

    y = settingsCard(page, "Notifications", y, {
        toggleRow("Summary in chat at login", "loginSummary"),
        toggleRow("Toast when today's target is reached", "targetToast"),
        toggleRow("Sound with the toast", "toastSound", "targetToast"),
    })

    y = settingsCard(page, "Data", y, {
        controlRow("JSON", nil, function(row)
            local holder = CreateFrame("Frame", nil, row)
            holder:SetSize(110 * 2 + 6, 22)
            local import = W.Button(holder, "Import", 110, 22, function() ns.ExportWindow.Open("import") end)
            import:SetPoint("RIGHT")
            local export = W.Button(holder, "Export", 110, 22, function() ns.ExportWindow.Open("export") end)
            export:SetPoint("RIGHT", import, "LEFT", -6, 0)
            return holder
        end),
    })

    -- Kept in its own card, away from the other buttons. The first click arms
    -- it; it disarms by itself after a few seconds or when the page closes.
    local wipe
    local function disarm()
        wipe.armed = false
        wipe:SetLabel(Theme.Hex(Theme.bad) .. "Reset|r")
    end
    settingsCard(page, "Reset", y, {
        controlRow("Reset " .. ns.char.name, nil, function(row)
            wipe = W.Button(row, "", 110, 22, function()
                if wipe.armed then
                    disarm()
                    ns.ResetCharacter()
                else
                    wipe.armed = true
                    wipe:SetLabel(Theme.Hex(Theme.bad) .. "Confirm reset|r")
                    local token = {}
                    wipe.token = token
                    C_Timer.After(4, function()
                        if wipe.token == token and wipe.armed then
                            disarm()
                        end
                    end)
                end
            end)
            disarm()
            return wipe
        end),
    }, { Theme.bad[1], Theme.bad[2], Theme.bad[3], 0.5 })
    page:SetScript("OnHide", disarm)

    function page:Update()
        for _, row in ipairs(toggles) do
            row:Update()
        end
        scale:Update()
        for _, entry in ipairs(dependents) do
            setRowEnabled(entry[1], settings[entry[2]])
        end
    end
end

local BUILDERS = {
    overview = buildOverview,
    goal = buildGoal,
    history = buildHistory,
    characters = buildCharacters,
    settings = buildSettings,
}

-- Window ------------------------------------------------------------------

local function build()
    window = W.Window("pt60Planner", WIDTH, HEIGHT)
    local sidebar = W.Panel(window, { 0, 0, 0, 0.25 })
    sidebar:SetPoint("TOPLEFT", 1, -31)
    sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(SIDEBAR)
    sidebar:SetBackdropBorderColor(0, 0, 0, 0)

    for i, entry in ipairs(PAGE_ORDER) do
        local tab = W.Button(sidebar, entry.label, SIDEBAR - 16, 26, function() Planner.Show(entry.key) end)
        tab:SetPoint("TOP", 0, -10 - (i - 1) * 30)
        tabs[entry.key] = tab

        local page = CreateFrame("Frame", nil, window)
        page:SetPoint("TOPLEFT", SIDEBAR + PAD, -31 - PAD)
        page:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        page:Hide()
        BUILDERS[entry.key](page)
        pages[entry.key] = page
    end

    window:SetScript("OnShow", Planner.Update)
    ns.OnRefresh(Planner.Update)
end

function Planner.Show(key)
    if not window then
        build()
    end
    Planner.current = key or Planner.current or "overview"
    for k, page in pairs(pages) do
        page:SetShown(k == Planner.current)
        tabs[k]:SetSelected(k == Planner.current)
    end
    window:Show()
    Planner.Update()
end

function Planner.Toggle()
    if window and window:IsShown() then
        window:Hide()
    else
        Planner.Show()
    end
end

function Planner.Update()
    if not (window and window:IsShown()) then
        return
    end
    window.subtitle:SetText(ns.char.name .. " - " .. ns.char.realm)
    pages[Planner.current]:Update()
end
