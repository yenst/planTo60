local _, ns = ...

local Theme, W, Day, Plan, XP, Curve = ns.Theme, ns.W, ns.Day, ns.Plan, ns.XP, ns.Curve

-- Goal editing controls shared by the setup wizard and the Goal page. They
-- edit a draft { level, date, mode, weights } and call onChange after each
-- edit. `weights` are the hours you can play on each weekday (Sunday first).
local Editors = {}
ns.Editors = Editors

local DAY = ns.DAY
local MAX_HOURS = 24
local HOUR_STEP = 0.5
local WEEK_ORDER = { 2, 3, 4, 5, 6, 7, 1 } -- Monday first; weights[] is Sunday first
local PRESETS = {
    { "2h every day", { 2, 2, 2, 2, 2, 2, 2 } },
    { "Evenings + weekend", { 4, 1, 1, 1, 1, 1, 4 } },
    { "Weekends only", { 5, 0, 0, 0, 0, 0, 5 } },
}

function Editors.DraftFrom(c)
    local weights = {}
    for i = 1, 7 do
        weights[i] = c.schedule.weights[i]
    end
    local goal = c.goal
    return {
        level = goal and goal.level or XP.MAX_LEVEL,
        date = goal and goal.date or Day.Key(Day.Today() + 30 * DAY),
        mode = goal and Plan.Mode(ns.char) or "time",
        weights = weights,
        playedTo60 = c.playedTo60,
    }
end

-- Returns nil if the draft is usable, otherwise a message.
function Editors.Problem(c, draft)
    local deadline = Day.StartOfKey(draft.date)
    if draft.level <= c.level then
        return "Pick a level above your current level (" .. c.level .. ")."
    elseif not deadline then
        return "Enter the deadline as DD/MM/YYYY."
    elseif deadline < Day.Today() then
        return "The deadline is in the past."
    end
    local preview = { schedule = { weights = draft.weights, off = c.schedule.off } }
    if Plan.SumWeights(preview, Day.Today(), deadline) == 0 then
        return "There's no play time set before the deadline."
    end
end

-- A throwaway character record with the draft applied, for previews.
local function preview(c, draft)
    local today = Day.Today()
    return {
        goal = { level = draft.level, date = draft.date, mode = draft.mode, createdDay = Day.Key(today), createdTotal = c.total },
        schedule = { weights = draft.weights, off = c.schedule.off },
        days = {},
        total = c.total,
    }
end

-- Share of the time you set aside that the draft goal needs (1 = all of it),
-- or nil if the draft isn't usable.
function Editors.Usage(c, draft, xph)
    if Editors.Problem(c, draft) then
        return nil
    end
    local needed, available = Plan.TimeBudget(preview(c, draft), Day.Today(), c.total, xph / Curve.Rate(c.level))
    return needed / available
end

local function weeklyHours(weights)
    local sum = 0
    for i = 1, 7 do
        sum = sum + weights[i]
    end
    return sum
end

local function usageColor(usage)
    return usage > 1 and Theme.bad or Theme.accent
end

-- "Needs 9h 30m of your 14h a week (68%)"
function Editors.NeedLine(usage, weights)
    local week = weeklyHours(weights)
    return string.format("%sNeeds %s of your %s a week (%d%%)|r", Theme.Hex(usageColor(usage)),
        ns.FormatDuration(usage * week * 3600), ns.FormatDuration(week * 3600), math.floor(usage * 100 + 0.5))
end

-- What the draft would mean, as a few lines of text.
-- `xph` is your XP/hour now; `measured` is false while it's still the guide estimate.
-- `nextToBars` drops the "Needs ..." line when the weekly bars already show it.
function Editors.Summary(c, draft, xph, measured, nextToBars)
    local problem = Editors.Problem(c, draft)
    if problem then
        return Theme.Hex(Theme.warn) .. problem .. "|r"
    end
    local p = preview(c, draft)
    local today = Day.Today()
    local remaining = Plan.GoalTotal(p) - c.total
    local playDays = 0
    for d = today, Plan.Deadline(p), DAY do
        playDays = playDays + (Plan.Weight(p, d) > 0 and 1 or 0)
    end
    local usage = Editors.Usage(c, draft, xph)

    local lines = {
        string.format("%s XP to go (%.1f levels) over %d play days.", ns.FormatXP(remaining), draft.level - XP.LevelAt(c.total), playDays),
    }
    if not nextToBars then
        lines[2] = Editors.NeedLine(usage, draft.weights) .. (measured and "" or Theme.Hex(Theme.muted) .. " (guide pace)|r")
    end
    if usage > 1 then
        lines[#lines + 1] = Theme.Hex(Theme.bad) .. "That's more than you set aside: add hours or move the deadline.|r"
    elseif draft.mode == "time" then
        lines[#lines + 1] = "XP targets grow as you level; the time per day stays the same."
    else
        lines[#lines + 1] = string.format("About %s XP every play day. Early days take longer than late ones.", ns.FormatXP(remaining / playDays))
    end
    return table.concat(lines, "\n")
end

-- Only what needs attention: an invalid draft or a goal that doesn't fit.
function Editors.Warning(c, draft, xph)
    local problem = Editors.Problem(c, draft)
    if problem then
        return Theme.Hex(Theme.warn) .. problem .. "|r"
    end
    if Editors.Usage(c, draft, xph) > 1 then
        return Theme.Hex(Theme.bad) .. "The goal needs more time than you set aside: add hours or move the deadline.|r"
    end
    return ""
end

function Editors.Level(parent, draft, onChange)
    return W.Stepper(parent, 130, W.Range(2, XP.MAX_LEVEL), function(v)
        return "Level " .. v
    end, function()
        return draft.level
    end, function(v)
        draft.level = v
        onChange()
    end)
end

-- "Same time every day" (default) vs "Same XP every day". `describe(mode)`
-- (optional) returns text for that button's tooltip, one line per "\n".
function Editors.Mode(parent, draft, onChange, describe)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(400, 22)
    local buttons = {}
    for i, option in ipairs({ { "time", "Same time every day" }, { "xp", "Same XP every day" } }) do
        local button = W.Button(frame, option[2], 160, 22, function()
            draft.mode = option[1]
            onChange()
            frame:Update()
        end)
        button:SetPoint("LEFT", (i - 1) * 168, 0)
        if describe then
            W.Tooltip(button, function(tip)
                for line in describe(option[1]):gmatch("[^\n]+") do
                    tip:AddLine(line, 1, 1, 1, true)
                end
            end)
        end
        buttons[option[1]] = button
    end
    function frame:Update()
        for key, button in pairs(buttons) do
            button:SetSelected(draft.mode == key)
        end
    end
    frame:Update()
    return frame
end

-- [<] 2026-12-04 [>]: click or scroll for one day, hold Shift for a week.
function Editors.Deadline(parent, draft, onChange)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(300, 22)
    local function shift(days)
        if IsShiftKeyDown() then
            days = days * 7
        end
        local start = (Day.StartOfKey(draft.date) or Day.Today()) + days * DAY
        draft.date = Day.Key(math.max(start, Day.Today()))
        onChange()
        frame:Update()
    end
    local back = W.Button(frame, "<", 22, 22, function() shift(-1) end)
    back:SetPoint("TOPLEFT")
    local box = W.EditBox(frame, 100, function(text)
        local key = Day.ParseInput(text)
        if key and key ~= draft.date then
            draft.date = key
            onChange()
        end
        frame:Update()
    end)
    box:SetPoint("LEFT", back, "RIGHT", 4, 0)
    box:SetJustifyH("CENTER")
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, delta) shift(delta) end)
    local forward = W.Button(frame, ">", 22, 22, function() shift(1) end)
    forward:SetPoint("LEFT", box, "RIGHT", 4, 0)
    for _, control in ipairs({ back, box, forward }) do
        W.Tooltip(control, function(tip)
            local start = Day.StartOfKey(draft.date)
            if start then
                tip:AddLine(string.format("%s · %d days", Day.Pretty(start), Day.Between(Day.Today(), start) + 1))
            else
                tip:AddLine("Use DD/MM/YYYY")
            end
            tip:AddLine("Shift: 1 week", 0.6, 0.6, 0.6)
        end)
    end

    function frame:Update()
        if not box:HasFocus() then
            box:SetText(Day.DisplayKey(draft.date))
        end
    end
    frame:Update()
    return frame
end

-- Weekly hours as bars on a fixed 0-24h scale: each bar is the time you can
-- play that weekday, so changing one leaves the others as they are. Bars turn
-- red when the goal needs more than you set aside. Click a bar to set its
-- height, scroll for +/- 30m, right-click for a day off. `getUsage` returns
-- the current share or nil.
local function hoursLabel(hours)
    if hours == 0 then
        return "off"
    elseif hours == math.floor(hours) then
        return hours .. "h"
    end
    return ns.FormatDuration(hours * 3600)
end

local function snap(hours)
    return math.max(0, math.min(MAX_HOURS, math.floor(hours / HOUR_STEP + 0.5) * HOUR_STEP))
end

function Editors.Weekly(parent, draft, onChange, getUsage)
    local WIDTH, BAR_H, BAR_W = 520, 120, 30
    local colW = WIDTH / 7
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(WIDTH, 200)

    local need = W.Text(frame, 12)
    need:SetPoint("TOPLEFT")

    local columns = {}
    local function set(index, hours)
        draft.weights[index] = snap(hours)
        onChange()
        frame:Update()
    end

    for slot, index in ipairs(WEEK_ORDER) do
        local col = CreateFrame("Button", nil, frame)
        col:SetSize(colW, BAR_H)
        col:SetPoint("TOPLEFT", (slot - 1) * colW, -24)
        col:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local track = col:CreateTexture(nil, "BACKGROUND")
        track:SetColorTexture(0, 0, 0, 0.45)
        track:SetPoint("BOTTOM")
        track:SetSize(BAR_W, BAR_H)
        col.available = col:CreateTexture(nil, "ARTWORK")
        col.available:SetPoint("BOTTOM")
        col.available:SetWidth(BAR_W)

        col.day = W.Text(frame, 11, Theme.muted, "CENTER")
        col.day:SetPoint("TOP", col, "BOTTOM", 0, -4)
        col.day:SetText(Plan.WEEKDAYS[index]:sub(1, 3))
        col.value = W.Text(frame, 12, Theme.text, "CENTER")
        col.value:SetPoint("TOP", col.day, "BOTTOM", 0, -2)

        col:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                set(index, 0)
                return
            end
            local _, y = GetCursorPosition()
            local height = y / self:GetEffectiveScale() - self:GetBottom()
            set(index, math.max(HOUR_STEP, height / BAR_H * MAX_HOURS))
        end)
        col:EnableMouseWheel(true)
        col:SetScript("OnMouseWheel", function(_, delta)
            set(index, draft.weights[index] + delta * HOUR_STEP)
        end)
        col:SetScript("OnEnter", function(self)
            track:SetColorTexture(1, 1, 1, 0.08)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(Plan.WEEKDAYS[index] .. ": " .. hoursLabel(draft.weights[index]))
            GameTooltip:AddLine("Click to set · Scroll: 30m · Right-click: off", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        col:SetScript("OnLeave", function()
            track:SetColorTexture(0, 0, 0, 0.45)
            GameTooltip:Hide()
        end)
        col.index = index
        columns[#columns + 1] = col
    end

    local previous
    for _, preset in ipairs(PRESETS) do
        local button = W.Button(frame, preset[1], 130, 20, function()
            for i = 1, 7 do
                draft.weights[i] = preset[2][i]
            end
            onChange()
            frame:Update()
        end)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            button:SetPoint("BOTTOMLEFT")
        end
        previous = button
    end

    function frame:Update()
        local usage = getUsage()
        need:SetText(usage and Editors.NeedLine(usage, draft.weights) or "")
        for _, col in ipairs(columns) do
            local hours = draft.weights[col.index]
            col.available:SetHeight(math.max(1, hours / MAX_HOURS * BAR_H))
            col.available:SetShown(hours > 0)
            col.available:SetColorTexture(unpack(usageColor(usage or 0)))
            col.value:SetText(hoursLabel(hours))
            col.value:SetTextColor(unpack(hours > 0 and Theme.text or Theme.muted))
        end
    end
    return frame
end

-- Your /played from 1 to max level, to plan with instead of the measured pace.
-- The first value is "Auto": the measured pace, or the guide until there is one.
function Editors.Played(parent, draft, onChange)
    local values = { 0 }
    for h = 24, 300, 4 do
        values[#values + 1] = h
    end
    return W.Stepper(parent, 130, values, function(v)
        return v == 0 and "Auto" or (v .. "h")
    end, function()
        return draft.playedTo60 or 0
    end, function(v)
        draft.playedTo60 = v > 0 and v or nil
        onChange()
    end)
end
