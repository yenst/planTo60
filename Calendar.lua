local _, ns = ...

local Theme, W, Day, Plan, XP = ns.Theme, ns.W, ns.Day, ns.Plan, ns.XP

-- Month grid: shows what was earned on past days and what is planned for
-- future ones. Clicking today or a future day toggles it as a day off.
local Calendar = {}
ns.Calendar = Calendar

local COLS, ROWS = 7, 6
local WEEKDAY_LABELS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

local function tint(color, alpha)
    return { color[1], color[2], color[3], alpha }
end

-- Background, border and label for one cell.
local function describeCell(c, start, today, deadline, inMonth)
    local rec = c.days[Day.Key(start)]
    local weight = Plan.Weight(c, start)
    local bg, border, label = Theme.bgRaised, Theme.border, ""

    if start < today then
        if rec and rec.target > 0 then
            bg = rec.gained >= rec.target and tint(Theme.accent, 0.28) or tint(Theme.bad, 0.22)
        end
    elseif start <= deadline then
        if weight == 0 then
            label, bg = "off", Theme.bg
        end
    else
        bg = Theme.bg
    end
    if start == deadline then
        border = Theme.warn
    end
    if start == today then
        border = Theme.accent
    end
    return bg, border, label, inMonth and 1 or 0.35
end

-- Past days: what you earned and the level you reached. Today and later:
-- the target and the level the plan has you at by the end of that day.
local function cellTooltip(cell, tip)
    local c, start, today = ns.char, cell.start, Day.Today()
    local key = Day.Key(start)
    tip:AddLine(Day.Pretty(start))
    local rec = c.days[key]
    if start <= today and rec then
        tip:AddDoubleLine("Earned", ns.FormatXP(rec.gained) .. " XP", 0.7, 0.7, 0.7, 1, 1, 1)
        tip:AddDoubleLine("Target", ns.FormatXP(rec.target) .. " XP", 0.7, 0.7, 0.7, 1, 1, 1)
    end
    if start < today and rec then
        tip:AddDoubleLine("Level reached", string.format("%.1f", XP.LevelAt(rec.start + rec.gained)), 0.7, 0.7, 0.7, 1, 1, 1)
    elseif start >= today and start <= Plan.Deadline(c) then
        local forecast, ends = Plan.Forecast(c, today)
        if start > today then
            tip:AddDoubleLine("Target", ns.FormatXP(forecast[key] or 0) .. " XP", 0.7, 0.7, 0.7, 1, 1, 1)
        end
        local level = XP.LevelAt(ends[key] or c.total)
        tip:AddDoubleLine("Level by end of day", string.format("%.1f", level), 0.7, 0.7, 0.7, unpack(Theme.accent))
    end
    if start == Plan.Deadline(c) then
        tip:AddLine("Deadline", unpack(Theme.warn))
    end
end

local function setDeadline(start)
    if start < Day.Today() then
        return
    end
    local draft = ns.Editors.DraftFrom(ns.char)
    draft.date = Day.Key(start)
    local ok, problem = ns.ApplyDraft(draft)
    if not ok then
        ns.Print(problem)
    end
end

local function toggleOffDay(start)
    local c = ns.char
    if start < Day.Today() or start > Plan.Deadline(c) then
        return
    end
    local key = Day.Key(start)
    c.schedule.off[key] = not c.schedule.off[key] or nil
    ns.PlanChanged()
end

-- Warcraft Logs parse colours, used for how far along to the goal a day is.
local PERCENTILE_COLORS = {
    { 100, { 0.90, 0.80, 0.50 } }, -- gold
    { 99, { 0.89, 0.41, 0.66 } }, -- pink
    { 95, { 1.00, 0.50, 0.00 } }, -- orange
    { 75, { 0.64, 0.21, 0.93 } }, -- purple
    { 50, { 0.00, 0.44, 1.00 } }, -- blue
    { 25, { 0.12, 1.00, 0.00 } }, -- green
    { 0, { 0.40, 0.40, 0.40 } }, -- grey
}

function Calendar.PercentileColor(percent)
    for _, entry in ipairs(PERCENTILE_COLORS) do
        if percent >= entry[1] then
            return entry[2]
        end
    end
    return PERCENTILE_COLORS[#PERCENTILE_COLORS][2]
end

-- Level at the end of a day (reached for past days, planned for today and
-- later) and the colour for how far along the goal that is.
local function dayLevel(c, start, today, deadline, ends)
    local total
    if start < today then
        local rec = c.days[Day.Key(start)]
        total = rec and (rec.start + rec.gained)
    elseif start <= deadline then
        total = ends[Day.Key(start)]
    end
    if not total then
        return nil
    end
    local level = XP.LevelAt(total)
    local from = XP.LevelAt(c.goal.createdTotal)
    local span = c.goal.level - from
    local percent = span > 0 and math.floor((level - from) / span * 100 + 0.5) or 100
    return level, Calendar.PercentileColor(percent)
end

function Calendar.Create(parent, width)
    local cal = CreateFrame("Frame", nil, parent)
    local cellW = math.floor(width / COLS)
    local cellH = 48
    cal:SetSize(cellW * COLS, 44 + cellH * ROWS + 20)
    local hint = W.Text(cal, 10, Theme.muted, "CENTER")
    hint:SetPoint("BOTTOM", 0, 0)
    hint:SetText("Click a day: day off  ·  Shift-click a day: make it the deadline  ·  Click the deadline card to change it")
    cal.monthOffset = 0

    cal.title = W.Text(cal, 13, Theme.text, "CENTER")
    cal.title:SetPoint("TOP", 0, -4)
    local prev = W.Button(cal, "<", 22, 20, function()
        cal.monthOffset = cal.monthOffset - 1
        cal:Update()
    end)
    prev:SetPoint("TOPLEFT")
    local nextButton = W.Button(cal, ">", 22, 20, function()
        cal.monthOffset = cal.monthOffset + 1
        cal:Update()
    end)
    nextButton:SetPoint("TOPRIGHT")

    for i, name in ipairs(WEEKDAY_LABELS) do
        local label = W.Text(cal, 10, Theme.muted, "CENTER")
        label:SetPoint("TOPLEFT", (i - 1) * cellW, -28)
        label:SetWidth(cellW)
        label:SetText(name)
    end

    cal.cells = {}
    for i = 1, COLS * ROWS do
        local cell = CreateFrame("Button", nil, cal, "BackdropTemplate")
        cell:SetSize(cellW - 2, cellH - 2)
        cell:SetPoint("TOPLEFT", ((i - 1) % COLS) * cellW, -44 - math.floor((i - 1) / COLS) * cellH)
        W.Skin(cell, Theme.bgRaised)
        cell.day = W.Text(cell, 10, Theme.muted)
        cell.day:SetPoint("TOPLEFT", 4, -3)
        cell.level = W.Text(cell, 16, Theme.text, "CENTER")
        W.SetFont(cell.level, 16, "OUTLINE")
        cell.level:SetPoint("CENTER", 0, -2)
        cell.value = W.Text(cell, 10, Theme.text, "RIGHT")
        cell.value:SetPoint("BOTTOMRIGHT", -4, 4)
        cell:SetScript("OnClick", function(self)
            if IsShiftKeyDown() then
                setDeadline(self.start)
            else
                toggleOffDay(self.start)
            end
        end)
        W.Tooltip(cell, function(tip) cellTooltip(cell, tip) end)
        cal.cells[i] = cell
    end

    function cal:Update()
        local c = ns.char
        local now = date("*t", Day.Today())
        local first = time({ year = now.year, month = now.month + self.monthOffset, day = 1, hour = 12 })
        local month = date("*t", first)
        self.title:SetText(date("%B %Y", first))
        local mondayIndex = (tonumber(date("%w", first)) + 6) % 7 -- days since Monday
        local today, deadline = Day.Today(), Plan.Deadline(c)
        local _, ends = Plan.Forecast(c, today)
        for i, cell in ipairs(self.cells) do
            local t = time({ year = month.year, month = month.month, day = i - mondayIndex, hour = 12 })
            local key = date("%Y-%m-%d", t)
            cell.start = Day.StartOfKey(key)
            local bg, border, label, alpha = describeCell(c, cell.start, today, deadline, date("*t", t).month == month.month)
            cell:SetBackdropColor(unpack(bg))
            cell:SetBackdropBorderColor(unpack(border))
            cell:SetAlpha(alpha)
            cell.day:SetText(date("*t", t).day)
            cell.value:SetText(label)
            local level, color = dayLevel(c, cell.start, today, deadline, ends)
            cell.level:SetText(level and string.format("%.1f", level) or "")
            if color then
                cell.level:SetTextColor(color[1], color[2], color[3])
            end
        end
    end
    return cal
end
