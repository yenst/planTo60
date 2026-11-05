local _, ns = ...

local Theme, W, XP = ns.Theme, ns.W, ns.XP

local Tracker = {}
ns.Tracker = Tracker

local DEFAULT_POS = { point = "TOP", relPoint = "TOP", x = 0, y = -90 }
local frame

local function settings()
    return ns.db.settings
end

local function applyPosition()
    local pos = settings().trackerPos or DEFAULT_POS
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

local function savePosition(point, relPoint, x, y)
    settings().trackerPos = { point = point, relPoint = relPoint, x = x, y = y }
end

-- Lets EllesmereUI's unlock mode move and snap the tracker with the rest of the UI.
local function registerWithEllesmere()
    local eui = _G.EllesmereUI
    if not (Theme.ellesmere and type(eui.RegisterUnlockElements) == "function") then
        return
    end
    pcall(eui.RegisterUnlockElements, eui, { {
        key = "pt60_Tracker",
        label = ns.TITLE,
        order = 900,
        noResize = true,
        getFrame = function() return frame end,
        getSize = function() return frame:GetWidth(), frame:GetHeight() end,
        savePosition = function(_, point, relPoint, x, y) savePosition(point, relPoint, x, y) end,
        loadPosition = function() return settings().trackerPos end,
        clearPosition = function()
            settings().trackerPos = nil
            applyPosition()
        end,
    } })
end

-- Hovering the bar only shows something when there is XP waiting: finished
-- quests to hand in and rested XP, as a share of a level.
local function levelsWorth(xp)
    local total = ns.char.total
    return XP.LevelAt(total + xp) - XP.LevelAt(total)
end

-- Returns false when there is nothing to show.
function Tracker.ShowWaitingXP(tip)
    local banked, rested = ns.Quests.banked, ns.restedXP or 0
    if banked.xp == 0 and rested == 0 then
        return false
    end
    if banked.xp > 0 then
        tip:AddDoubleLine(Theme.Icon("quest", 14) .. " Completed quests", string.format("%.2f levels", levelsWorth(banked.xp)), 1, 0.65, 0, 1, 1, 1)
    end
    if rested > 0 then
        tip:AddDoubleLine(Theme.Icon("rested", 14) .. " Rested", string.format("%.2f levels", levelsWorth(rested)), 0.35, 0.62, 1, 1, 1, 1)
    end
    return true
end

-- Colours from the classic XP-bar look: blue-to-purple fill, orange for
-- finished quests, blue for rested XP.
local FILL_FROM, FILL_TO = { 0.39, 0.39, 1 }, { 0.78, 0.39, 1 }
local QUEST_COLOR = { 1, 0.65, 0 }
local RESTED_COLOR = { 0.35, 0.62, 1 }
-- The thin bar on top shows progress through the current level.
local BAR_W, BAR_H, LEVEL_H, LEVEL_GAP = 540, 24, 8, 2

local function setGradient(texture, from, to)
    texture:SetTexture(W.FLAT)
    if CreateColor and pcall(texture.SetGradient, texture, "HORIZONTAL", CreateColor(from[1], from[2], from[3], 1), CreateColor(to[1], to[2], to[3], 1)) then
        return
    end
    if texture.SetGradientAlpha then
        texture:SetGradientAlpha("HORIZONTAL", from[1], from[2], from[3], 1, to[1], to[2], to[3], 1)
    else
        texture:SetVertexColor(to[1], to[2], to[3], 1)
    end
end

local function segment(parent, layer)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetPoint("TOP")
    texture:SetPoint("BOTTOM")
    return texture
end

local function outlined(parent, size, color, justify)
    local fs = W.Text(parent, size, color, justify)
    W.SetFont(fs, size, "OUTLINE")
    return fs
end

function Tracker.Build()
    frame = CreateFrame("Button", "pt60Tracker", UIParent)
    frame:SetSize(BAR_W, LEVEL_H + LEVEL_GAP + BAR_H + 22)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:RegisterForDrag("LeftButton")

    local levelBar = W.Panel(frame, { 0.06, 0.07, 0.10, 0.85 })
    levelBar:SetPoint("TOPLEFT")
    levelBar:SetSize(BAR_W, LEVEL_H)
    local levelInner = CreateFrame("Frame", nil, levelBar)
    levelInner:SetPoint("TOPLEFT", 1, -1)
    levelInner:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.levelFill = segment(levelInner, "BORDER")
    frame.levelFill:SetPoint("LEFT")
    setGradient(frame.levelFill, FILL_FROM, FILL_TO)
    frame.levelInner = levelInner

    local bar = W.Panel(frame, { 0.06, 0.07, 0.10, 0.85 })
    bar:SetPoint("TOPLEFT", levelBar, "BOTTOMLEFT", 0, -LEVEL_GAP)
    bar:SetSize(BAR_W, BAR_H)
    local inner = CreateFrame("Frame", nil, bar)
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.fill = segment(inner, "BORDER")
    frame.fill:SetPoint("LEFT")
    setGradient(frame.fill, FILL_FROM, FILL_TO)
    frame.quests = segment(inner, "BORDER")
    frame.quests:SetPoint("LEFT", frame.fill, "RIGHT")
    frame.quests:SetColorTexture(unpack(QUEST_COLOR))
    frame.rested = segment(inner, "BORDER")
    frame.rested:SetPoint("LEFT", frame.quests, "RIGHT")
    frame.rested:SetColorTexture(unpack(RESTED_COLOR))
    frame.inner = inner

    frame.levelText = outlined(inner, 14)
    frame.levelText:SetPoint("LEFT", 8, 0)
    frame.xpText = outlined(inner, 14, Theme.text, "CENTER")
    frame.xpText:SetPoint("CENTER")
    frame.pctText = outlined(inner, 14, Theme.text, "RIGHT")
    frame.pctText:SetPoint("RIGHT", -8, 0)

    frame.sub = outlined(frame, 12, Theme.text, "CENTER")
    frame.sub:SetPoint("TOP", bar, "BOTTOM", 0, -5)

    frame:SetScript("OnDragStart", function(self)
        if not settings().lockTracker then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        savePosition(point, relPoint, x, y)
    end)
    frame:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            Tracker.ToggleLock()
        else
            ns.OpenMain()
        end
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if Tracker.ShowWaitingXP(GameTooltip) then
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    applyPosition()
    registerWithEllesmere()
    ns.OnRefresh(Tracker.Update)
    Tracker.Update()
end

function Tracker.ToggleLock()
    settings().lockTracker = not settings().lockTracker
    ns.Print(settings().lockTracker and "Tracker locked." or "Tracker unlocked. Drag it to move.")
end

function Tracker.ResetPosition()
    settings().trackerPos = nil
    applyPosition()
end

local function percent(fraction)
    return string.format("%.1f%%", fraction * 100)
end

-- Width of the bar's segments: progress, then finished quests, then rested
-- XP, together capped at the full bar.
local function setSegments(gained, banked, rested)
    local width = frame.inner:GetWidth()
    local used = 0
    for _, entry in ipairs({ { frame.fill, gained }, { frame.quests, banked }, { frame.rested, rested } }) do
        local part = math.max(0, math.min(1 - used, entry[2]))
        entry[1]:SetWidth(math.max(0.01, width * part))
        entry[1]:SetShown(part > 0)
        used = used + part
    end
end

-- "[clock] 45m left", "Done today" or "Hand in to finish".
local function timeText(s)
    if s.target > 0 and s.left == 0 then
        return "Done today"
    elseif s.target > 0 and s.leftAfterBanked == 0 then
        return "Hand in to finish"
    elseif s.leftSeconds then
        return Theme.Icon("clock", 13) .. " " .. ns.FormatDuration(s.leftSeconds) .. " left"
    end
end

-- Line under the bar: "[quest] 4.8%   [rested] 6.4%   [clock] 45m left   [ok] On track"
local function subText(s, rested)
    local parts = {}
    local banked = ns.Quests.banked
    if banked.xp > 0 then
        parts[#parts + 1] = Theme.Icon("quest", 13) .. " " .. Theme.Hex(QUEST_COLOR) .. percent(banked.xp / s.target) .. "|r"
    elseif banked.count > 0 then
        parts[#parts + 1] = Theme.Icon("quest", 13) .. " " .. Theme.Hex(QUEST_COLOR) .. banked.count .. "|r"
    end
    if rested > 0 then
        parts[#parts + 1] = Theme.Icon("rested", 13) .. " " .. Theme.Hex(RESTED_COLOR) .. percent(rested / s.target) .. "|r"
    end
    parts[#parts + 1] = timeText(s)
    parts[#parts + 1] = Theme.StateText(s, 13)
    return table.concat(parts, "     ")
end

-- Thin top bar: XP through the current level (empty at max level).
local function setLevelProgress()
    local max = UnitXPMax("player")
    local part = max > 0 and math.max(0, math.min(1, UnitXP("player") / max)) or 0
    frame.levelFill:SetWidth(math.max(0.01, frame.levelInner:GetWidth() * part))
    frame.levelFill:SetShown(part > 0)
end

local function showEmpty(level, center, right, sub)
    frame.levelText:SetText("Level " .. level)
    frame.xpText:SetText(center)
    frame.pctText:SetText(right)
    frame.sub:SetText(sub)
    setSegments(0, 0, 0)
end

function Tracker.Update()
    if not frame then
        return
    end
    frame:SetShown(settings().showTracker)
    frame:SetScale(settings().trackerScale)
    setLevelProgress()
    local s = ns.status
    local level = ns.char.level
    if not s then
        showEmpty(level, "No goal yet", "Set up", "Click to plan your leveling")
        return
    elseif s.state == "done" then
        showEmpty(level, "Goal reached", "100%", Theme.Hex(Theme.accent) .. "Level " .. s.goalLevel .. " reached. Congratulations!|r")
        setSegments(1, 0, 0)
        return
    elseif s.offToday then
        showEmpty(level, s.gained .. " XP", "Rest day", Theme.Hex(Theme.muted) .. "Rest day - no target today|r")
        return
    end

    local rested = math.min(ns.restedXP or 0, s.leftAfterBanked)
    frame.levelText:SetText("Level " .. level)
    frame.xpText:SetText(s.gained .. " / " .. s.target)
    local withQuests = s.banked > 0 and string.format(" (%s)", percent((s.gained + s.banked) / s.target)) or ""
    frame.pctText:SetText(percent(s.gained / s.target) .. withQuests)
    setSegments(s.gained / s.target, s.banked / s.target, rested / s.target)
    frame.sub:SetText(subText(s, rested))
end
