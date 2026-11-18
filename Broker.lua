local _, ns = ...

local Theme = ns.Theme

-- LibDataBroker feed for Titan Panel, ElvUI, EllesmereUI data bars and the
-- like, plus a LibDBIcon minimap button built from the same object (the
-- button minimap button bags and UI suites know how to collect). The release
-- zip embeds the libraries (.pkgmeta externals); a copy loaded by another
-- addon works too.
local Broker = {}
ns.Broker = Broker

local dataObject, icon

-- LibDBIcon names the button "LibDBIcon10_" .. this. It must not end in a
-- digit: EllesmereUI's minimap flyout skips such names as map pins, and
-- strips the "MinimapButton" suffix for its label.
local ICON_NAME = ns.TITLE .. "MinimapButton"

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
            tip:AddLine(" ")
            tip:AddLine(Theme.Hex(Theme.muted) .. "Click|r to open the planner")
            tip:AddLine(Theme.Hex(Theme.muted) .. "Right-click|r to show / hide the tracker")
        end,
    })
    icon = LibStub("LibDBIcon-1.0", true)
    if icon then
        -- LibDBIcon keeps the button's angle in this table (account-wide).
        ns.db.minimap = ns.db.minimap or {}
        ns.db.minimap.hide = not ns.db.settings.minimapButton
        icon:Register(ICON_NAME, dataObject, ns.db.minimap)
    end
    ns.OnRefresh(Broker.Update)
    Broker.Update()
end

-- False when no LibDBIcon is loaded, so the setting has nothing to drive.
function Broker.HasMinimapButton()
    return icon ~= nil
end

function Broker.Update()
    if not dataObject then
        return
    end
    dataObject.text = brokerText(ns.status)
    if icon then
        local show = ns.db.settings.minimapButton
        if show == ns.db.minimap.hide then
            ns.db.minimap.hide = not show
            if show then
                icon:Show(ICON_NAME)
            else
                icon:Hide(ICON_NAME)
            end
        end
    end
end
