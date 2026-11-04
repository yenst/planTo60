local _, ns = ...

-- "Banked" XP: quests in the log that are complete but not handed in yet.
-- Shown next to today's progress; it only counts as gained once handed in.
local Quests = {}
ns.Quests = Quests

Quests.banked = { count = 0, xp = 0, unknown = 0 }

local function rewardXP(questID)
    if not GetQuestLogRewardXP then
        return nil
    end
    local ok, xp = pcall(GetQuestLogRewardXP, questID)
    if ok and type(xp) == "number" and xp > 0 then
        return xp
    end
end

local function hasModernLog()
    return C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.IsComplete and C_QuestLog.GetNumQuestLogEntries
end

-- Quest IDs (modern) or log indexes (classic) of finished quests, plus a
-- signature string so the XP lookup only reruns when this list changes.
local function finishedQuests()
    local list = {}
    if hasModernLog() then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID and C_QuestLog.IsComplete(info.questID) then
                list[#list + 1] = { id = info.questID, index = i }
            end
        end
    else
        for i = 1, GetNumQuestLogEntries() do
            local _, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
            if not isHeader and isComplete == 1 then
                list[#list + 1] = { id = questID, index = i }
            end
        end
    end
    -- Quest XP shrinks as quests go gray, so a level-up also counts as a change.
    local ids = { UnitLevel("player") }
    for _, quest in ipairs(list) do
        ids[#ids + 1] = quest.id .. ":" .. quest.index
    end
    return list, table.concat(ids, ",")
end

-- Some clients' reward call reads the selected quest and ignores the
-- questID argument, so select each quest first and restore the selection.
local function getSelection()
    if GetQuestLogSelection then
        return GetQuestLogSelection()
    end
    return C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
end

local function setSelection(quest, restore)
    if SelectQuestLogEntry then
        SelectQuestLogEntry(restore or quest.index)
    elseif C_QuestLog and C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(restore or quest.id)
    end
end

local function lookupXP(list)
    local selected = getSelection()
    for _, quest in ipairs(list) do
        setSelection(quest)
        quest.xp = rewardXP(quest.id)
    end
    if selected then
        setSelection(nil, selected)
    end
end

local lastSignature

-- Returns true if the banked total changed.
function Quests.Scan()
    local list, signature = finishedQuests()
    if signature == lastSignature then
        return false
    end
    lastSignature = signature
    lookupXP(list)
    local banked = { count = #list, xp = 0, unknown = 0 }
    for _, quest in ipairs(list) do
        if quest.xp then
            banked.xp = banked.xp + quest.xp
        else
            banked.unknown = banked.unknown + 1
        end
    end
    Quests.banked = banked
    return true
end

-- "+12.4k ready", "+3 quests ready" (XP not reported) or "".
function Quests.Label(banked)
    if banked.count == 0 then
        return ""
    elseif banked.xp > 0 then
        return "+" .. ns.FormatXP(banked.xp) .. " ready"
    end
    return "+" .. banked.count .. (banked.count == 1 and " quest" or " quests") .. " ready"
end

-- QUEST_LOG_UPDATE fires in bursts; scan once things settle.
local pending = false
function Quests.QueueScan(onDone)
    if pending then
        return
    end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        if Quests.Scan() then
            onDone()
        end
    end)
end
