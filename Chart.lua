local _, ns = ...

local Theme, W, Day, Plan, XP = ns.Theme, ns.W, ns.Day, ns.Plan, ns.XP

-- Plan-vs-actual line chart of total XP over the goal's lifetime, with
-- horizontal gridlines at level boundaries. The plan line follows the goal's
-- mode: even XP per day (straight) or even hours per day (curved).
local Chart = {}
ns.Chart = Chart

local DAY = ns.DAY
local MAX_POINTS = 120

local function poolGet(pool, create)
    pool.used = pool.used + 1
    pool[pool.used] = pool[pool.used] or create()
    pool[pool.used]:Show()
    return pool[pool.used]
end

local function poolReset(pool)
    for i = 1, #pool do
        pool[i]:Hide()
    end
    pool.used = 0
end

-- Days from the earlier of goal start / first log, to the later of deadline / today.
local function timeRange(c, today)
    local first = Day.StartOfKey(c.goal.createdDay)
    for key in pairs(c.days) do
        first = math.min(first, Day.StartOfKey(key))
    end
    return first, math.max(Plan.Deadline(c), today)
end

-- Planned end-of-day totals in the goal's mode, walking cumulative weights once.
local function baselineSeries(c, first, last, step)
    local created = Day.StartOfKey(c.goal.createdDay)
    local deadline = Plan.Deadline(c)
    local goalTotal = Plan.GoalTotal(c)
    local planWeight = Plan.SumWeights(c, created, deadline)
    local points, cumulative = {}, 0
    local i = 0
    for d = created, math.min(deadline, last), DAY do
        cumulative = cumulative + Plan.Weight(c, d)
        if i % step == 0 or d == deadline then
            local total = goalTotal
            if planWeight > 0 and d < deadline then
                total = math.min(goalTotal, Plan.BaselineAfter(c, cumulative))
            end
            points[#points + 1] = { d, total }
        end
        i = i + 1
    end
    table.insert(points, 1, { created - DAY, c.goal.createdTotal })
    return points
end

local function actualSeries(c, first, today)
    local points = {}
    for d = first, today, DAY do
        local rec = c.days[Day.Key(d)]
        if rec then
            if #points == 0 then
                points[1] = { d - DAY, rec.start }
            end
            points[#points + 1] = { d, rec.start + rec.gained }
        end
    end
    return points
end

function Chart.Create(parent, width, height)
    local chart = W.Panel(parent, Theme.bgRaised)
    chart:SetSize(width, height)
    local plot = CreateFrame("Frame", nil, chart)
    plot:SetPoint("TOPLEFT", 40, -10)
    plot:SetPoint("BOTTOMRIGHT", -10, 20)
    local lines, grid, labels = { used = 0 }, { used = 0 }, { used = 0 }

    local legend = W.Text(chart, 10, Theme.muted, "RIGHT")
    legend:SetPoint("TOPRIGHT", -10, -6)
    legend:SetText(Theme.Hex(Theme.muted) .. "plan|r   " .. Theme.Hex(Theme.accent) .. "actual|r")
    local startLabel = W.Text(chart, 10, Theme.muted)
    startLabel:SetPoint("BOTTOMLEFT", 40, 5)
    local endLabel = W.Text(chart, 10, Theme.muted, "RIGHT")
    endLabel:SetPoint("BOTTOMRIGHT", -10, 5)

    local function newLine()
        local line = plot:CreateLine(nil, "OVERLAY")
        line:SetThickness(2)
        return line
    end
    local function newGrid()
        return W.Line(plot)
    end
    local function newLabel()
        return W.Text(chart, 9, Theme.muted, "RIGHT")
    end

    function chart:Update()
        poolReset(lines)
        poolReset(grid)
        poolReset(labels)
        local c = ns.char
        if not c.goal then
            return
        end
        local today = Day.Today()
        local first, last = timeRange(c, today)
        local w, h = plot:GetWidth(), plot:GetHeight()
        local span = math.max(1, last - first + DAY)
        local yMin = math.min(c.goal.createdTotal, c.days[Day.Key(first)] and c.days[Day.Key(first)].start or c.goal.createdTotal)
        local yMax = math.max(Plan.GoalTotal(c), c.total)
        local yRange = math.max(1, yMax - yMin)
        local function point(d, total)
            return (d + DAY - first) / span * w, (total - yMin) / yRange * h
        end

        local fromLevel, toLevel = math.floor(XP.LevelAt(yMin)), math.ceil(XP.LevelAt(yMax))
        local every = math.max(1, math.ceil((toLevel - fromLevel) / 6))
        for level = fromLevel + 1, toLevel, every do
            local _, y = point(first, XP.Cum(level))
            if y >= 0 and y <= h then
                local g = poolGet(grid, newGrid)
                g:ClearAllPoints()
                g:SetPoint("BOTTOMLEFT", 0, y)
                g:SetPoint("BOTTOMRIGHT", 0, y)
                local label = poolGet(labels, newLabel)
                label:ClearAllPoints()
                label:SetPoint("RIGHT", plot, "BOTTOMLEFT", -4, y)
                label:SetText("Lv " .. level)
            end
        end

        local step = math.max(1, math.ceil(span / DAY / MAX_POINTS))
        local function drawSeries(points, color)
            for i = 2, #points do
                local x1, y1 = point(points[i - 1][1], points[i - 1][2])
                local x2, y2 = point(points[i][1], points[i][2])
                local line = poolGet(lines, newLine)
                line:SetColorTexture(unpack(color))
                line:SetStartPoint("BOTTOMLEFT", plot, x1, y1)
                line:SetEndPoint("BOTTOMLEFT", plot, x2, y2)
            end
        end
        drawSeries(baselineSeries(c, first, last, step), Theme.muted)
        drawSeries(actualSeries(c, first, today), Theme.accent)

        startLabel:SetText(Day.Short(first))
        endLabel:SetText(Day.Short(last))
    end
    return chart
end
