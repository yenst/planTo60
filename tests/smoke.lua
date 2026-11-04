-- Loads the whole addon against a mocked WoW API and clicks through every
-- screen, to catch nil errors and typos without the game. Run from the repo root:
--   lua5.1 tests/smoke.lua
date, time = os.date, os.time

-- Mock frames: any unknown method is a no-op returning nil; a few return
-- plausible values. Scripts are stored so tests can fire them.
local Frame = {}
local function newFrame(kind)
    local f = setmetatable({ scripts = {}, shown = true, text = "", kind = kind }, Frame)
    return f
end
local returns = {
    GetWidth = 500, GetHeight = 300, GetVerticalScroll = 0, GetVerticalScrollRange = 100,
    GetFont = "Fonts\\FRIZQT__.TTF", GetBottom = 100, GetEffectiveScale = 1, GetFrameLevel = 1,
}
Frame.__index = function(_, key)
    if returns[key] ~= nil then
        return function() return returns[key] end
    end
    return rawget(Frame, key) or function() end
end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = function(...)
        if old then old(...) end
        fn(...)
    end
end
function Frame:Fire(name, ...) if self.scripts[name] then self.scripts[name](self, ...) end end
function Frame:Show() self.shown = true; self:Fire("OnShow") end
function Frame:Hide() self.shown = false end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:HasFocus() return false end
function Frame:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Frame:CreateTexture() return newFrame("Texture") end
function Frame:CreateFontString() return newFrame("FontString") end
function Frame:CreateLine() return newFrame("Line") end
function Frame:RegisterEvent(e) local ev = rawget(self, "events") or {}; rawset(self, "events", ev); ev[e] = true end

local allFrames = {}
function CreateFrame(kind, name, parent, template)
    local f = newFrame(kind)
    rawset(f, "parent", parent)
    allFrames[#allFrames + 1] = f
    if name then _G[name] = f end
    return f
end
UIParent = newFrame("Frame")
GameTooltip = newFrame("GameTooltip")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) print("[chat] " .. msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end }
UISpecialFrames, SlashCmdList = {}, {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
RAID_CLASS_COLORS = { MAGE = { colorStr = "ff3fc7eb" } }
tinsert = table.insert
C_AddOns = { IsAddOnLoaded = function() return false end }
C_DateAndTime = { GetSecondsUntilDailyReset = function() return 3600 end }
GetServerTime = os.time
local timers = {}
C_Timer = {
    After = function(_, fn) timers[#timers + 1] = fn end,
    NewTicker = function(_, fn) C_Timer.tick = fn end,
}
PlaySound = function() end
local cursorY = 0
local shiftDown = false
IsShiftKeyDown = function() return shiftDown end
GetCursorPosition = function() return 0, cursorY end
UnitName = function() return "Tester" end
GetRealmName = function() return "Mirage" end
UnitClass = function() return "Mage", "MAGE" end
local player = { level = 12, xp = 1500 }
UnitLevel = function() return player.level end
UnitXP = function() return player.xp end
UnitXPMax = function() return 10100 end
UnitAffectingCombat = function() return true end
GetXPExhaustion = function() return 3000 end
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
-- Classic-style quest log: entry 1 is a header, 2 and 4 are complete.
local questLog = {
    { "Elwynn", true, nil, 0 }, { "Wolves", false, 1, 101 }, { "Kobolds", false, nil, 102 }, { "Bandits", false, 1, 103 },
}
local questXP = { [2] = 450, [4] = 0 } -- 0: the client doesn't report this one
local selectedQuest = 3
GetNumQuestLogEntries = function() return #questLog end
GetQuestLogTitle = function(i)
    local q = questLog[i]
    return q[1], 10, 0, q[2], false, q[3], 0, q[4]
end
GetQuestLogSelection = function() return selectedQuest end
SelectQuestLogEntry = function(i) selectedQuest = i end
GetQuestLogRewardXP = function() return questXP[selectedQuest] end

local ns = {}
for line in io.lines("planTo60.toc") do
    if line:match("%.lua$") then
        assert(loadfile(line))("planTo60", ns)
    end
end
local eventFrame
for _, f in ipairs(allFrames) do
    if rawget(f, "events") and f.events.PLAYER_LOGIN then eventFrame = f end
end
local function fire(event, ...) eventFrame.scripts.OnEvent(eventFrame, event, ...) end
local function runTimers()
    local pending = timers
    timers = {}
    for _, fn in ipairs(pending) do fn() end
end

fire("ADDON_LOADED", "planTo60")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")
runTimers() -- opens the wizard on first login
assert(_G.pt60Wizard and _G.pt60Wizard.shown, "wizard opens on first login")

-- Buttons keep their label on a child font string at .text.
local function visible(f)
    while f do
        if not f.shown then return false end
        f = rawget(f, "parent")
    end
    return true
end
local function clickLabel(label)
    for _, f in ipairs(allFrames) do
        if f.kind == "Button" and type(f.text) == "table" and f.text.text == label and visible(f) then
            f:Fire("OnClick", "LeftButton")
            return true
        end
    end
    error("no visible button: " .. label)
end
-- Walk the wizard to the end.
clickLabel("Next") -- welcome -> goal
shiftDown = true
for _ = 1, 4 do clickLabel(">") end -- +4 weeks
shiftDown = false
clickLabel(">") -- +1 day
clickLabel("Next") -- goal -> time
-- Time step: click the Monday bar 1/4 of the way up = 6h of 24h; right-click Tuesday = off.
local bars = {}
for _, f in ipairs(allFrames) do
    if f.kind == "Button" and rawget(f, "index") and visible(f) then bars[#bars + 1] = f end
end
cursorY = 100 + 120 * 0.25
bars[1]:Fire("OnClick", "LeftButton")
bars[2]:Fire("OnClick", "RightButton")
bars[3]:Fire("OnMouseWheel", 1)
for _ = 1, 3 do clickLabel("Next") end -- time -> style -> tracker -> review
clickLabel("Start")
assert(ns.char.goal, "wizard sets the goal")
local w = ns.char.schedule.weights
assert(w[2] == 6 and w[3] == 0 and w[4] == 2.5, "bars set Mon 6h, Tue off, Wed 2.5h")
print("goal:", ns.char.goal.level, ns.char.goal.date, "today's target:", ns.status.target)

-- Gain XP, tick, open every page.
player.xp = 9000
fire("PLAYER_XP_UPDATE", "player")
for _ = 1, 12 do C_Timer.tick() end
assert(ns.XPPerHour(), "pace measured")
for _, page in ipairs({ "overview", "goal", "history", "characters", "settings" }) do
    ns.Planner.Show(page)
end
ns.Planner.Show("goal")
clickLabel("Evenings + weekend")
clickLabel(">")
assert(ns.char.schedule.weights[3] == 1, "goal page preset applied")
-- A faster /played means the goal needs fewer hours.
local played = ns.Editors.DraftFrom(ns.char)
played.playedTo60 = 300
assert(ns.ApplyDraft(played))
local slowNeed = ns.status.hoursNeeded
played.playedTo60 = 48
assert(ns.ApplyDraft(played))
assert(ns.char.playedTo60 == 48 and ns.status.hoursNeeded < slowNeed, "/played override applied")
played.playedTo60 = nil
assert(ns.ApplyDraft(played))
assert(ns.char.playedTo60 == nil, "/played back to auto")
ns.ExportWindow.Open("export")
assert(_G.pt60Export.shown)
ns.ExportWindow.Open("import")
SlashCmdList.PT60("goal 40 24/12/2026")
assert(ns.char.goal.date == "2026-12-24", "dd/mm/yyyy goal command")
ns.Planner.Show("overview")
-- Deadline card: click opens the editor, ">" moves the deadline a day, wheel moves it back.
local deadlineCard
for _, f in ipairs(allFrames) do
    if f.scripts.OnMouseUp and f.scripts.OnMouseWheel and visible(f) then deadlineCard = f end
end
deadlineCard:Fire("OnMouseUp")
clickLabel(">")
assert(ns.char.goal.date == "2026-12-25", "popup moved the deadline, got " .. ns.char.goal.date)
deadlineCard:Fire("OnMouseWheel", -1)
assert(ns.char.goal.date == "2026-12-24", "wheel moved it back")
clickLabel("Done")
-- Hover calendar days: past, today and future tooltips all build.
local hovered = 0
for _, f in ipairs(allFrames) do
    local start = rawget(f, "start")
    if start and visible(f) and f.scripts.OnEnter then
        f:Fire("OnEnter")
        hovered = hovered + 1
    end
end
assert(hovered >= 28, "hovered calendar cells: " .. hovered)
local beforeAfk = ns.status.target
clickLabel("-30m")
SlashCmdList.PT60("afk 30")
assert(ns.Plan.Weight(ns.char, ns.Day.Today()) == ns.Plan.WeekdayHours(ns.char, ns.Day.Today()) - 1 or ns.status.offToday, "afk took an hour off today")
clickLabel("Reset")
assert(ns.status.target == beforeAfk, "reset restores today's target")
SlashCmdList.PT60("status")
SlashCmdList.PT60("tracker")
SlashCmdList.PT60("help")
-- Finished quests show up as banked XP; the selection is restored.
fire("QUEST_LOG_UPDATE")
runTimers()
assert(ns.Quests.banked.count == 2 and ns.Quests.banked.xp == 450 and ns.Quests.banked.unknown == 1, "banked quests")
assert(selectedQuest == 3, "quest log selection restored")
assert(ns.status.banked == 450, "status carries banked XP")
print("tracker footer:", ns.Quests.Label(ns.Quests.banked))
-- Level-up where UnitLevel lags: XP already reset, level not yet updated.
local before = ns.char.total
player.xp = 50
fire("PLAYER_LEVEL_UP", 13)
assert(ns.char.total == before, "waits while the level is stale")
player.level = 13
runTimers()
assert(ns.char.level == 13 and ns.char.total == ns.XP.Cum(13) + 50, "picks up the new level")
-- Reach today's target to trigger the toast.
player.level, player.xp = 20, 0
fire("PLAYER_XP_UPDATE", "player")
assert(ns.char.days[ns.Day.Key(ns.Day.Today())].hit, "target marked as hit")
_G.pt60Tracker:Fire("OnEnter") -- tooltip only with waiting XP (3000 rested in the mock)
assert(ns.Tracker.ShowWaitingXP(GameTooltip), "rested XP shows in the tooltip")
ns.Planner.Show("overview")
for _, f in ipairs(allFrames) do
    if rawget(f, "value") and f.scripts.OnEnter and visible(f) then f:Fire("OnEnter") end -- stat cards
end
ns.Planner.Show("goal")
ns.Planner.Show("characters")
print("tracker:", _G.pt60Tracker.levelText.text, "|", _G.pt60Tracker.xpText.text, "|", _G.pt60Tracker.pctText.text)
print("tracker sub:", (_G.pt60Tracker.sub.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
-- The export box holds the JSON the player copies.
ns.ExportWindow.Open("export")
local doc = assert(ns.JSON.Decode(_G.pt60Export.edit:GetText()))
assert(doc.characters[1].goal.level == 40)
print("smoke test passed")
