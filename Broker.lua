local _, ns = ...

local Theme = ns.Theme

-- LibDataBroker feed for Titan Panel, ElvUI, EllesmereUI data bars and the like.
-- pt60 does not ship the library; display addons that use LDB include it.
local Broker = {}
ns.Broker = Broker

local dataObject

local function brokerText(s)
    if not s then
        return "No goal"
    end
    local label, color = Theme.StateOf(s)
    if s.state == "done" then
        return Theme.Hex(color) .. label .. "|r"
    end
    local pct = s.target > 0 and math.floor(s.gained / s.target * 100) or 100
    return string.format("%d%% %s· %s%s|r", pct, Theme.Hex(Theme.muted), Theme.Hex(color), label)
end

function Broker.Build()
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    if not ldb then
        return
    end
    dataObject = ldb:NewDataObject(ns.TITLE, {
        type = "data source",
        label = ns.TITLE,
        text = ns.TITLE,
        icon = ns.ICON,
        OnClick = function(_, button)
            if button == "RightButton" then
                ns.db.settings.showTracker = not ns.db.settings.showTracker
                ns.Refresh()
            else
                ns.OpenMain()
            end
        end,
        OnTooltipShow = function(tip)
            tip:AddLine(ns.TITLE)
            if ns.status then
                tip:AddLine(Theme.StateText(ns.status))
            end
            ns.Tracker.ShowWaitingXP(tip)
        end,
    })
    ns.OnRefresh(Broker.Update)
    Broker.Update()
end

function Broker.Update()
    dataObject.text = brokerText(ns.status)
end
