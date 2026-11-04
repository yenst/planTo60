local _, ns = ...

-- Flat dark panels, 1px black borders and one accent colour, in the style of
-- EllesmereUI. When EllesmereUI is loaded, its accent, font and panel colour
-- are used instead of the defaults below.
local Theme = {
    bg = { 0.05, 0.07, 0.09, 0.94 },
    bgRaised = { 0.09, 0.11, 0.14, 1 },
    bgHover = { 0.13, 0.16, 0.20, 1 },
    border = { 0, 0, 0, 1 },
    hairline = { 1, 1, 1, 0.06 },
    text = { 0.92, 0.93, 0.95, 1 },
    muted = { 0.55, 0.58, 0.63, 1 },
    accent = { 0.12, 0.82, 0.63, 1 },
    warn = { 1, 0.71, 0.25, 1 },
    bad = { 1, 0.36, 0.36, 1 },
    font = STANDARD_TEXT_FONT,
    ellesmere = false,
}
ns.Theme = Theme

local function readColor(c)
    if type(c) ~= "table" then
        return nil
    end
    local r, g, b = c.r or c[1], c.g or c[2], c.b or c[3]
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        return r, g, b
    end
end

function Theme.Load()
    local eui = _G.EllesmereUI
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUI")
    if not (loaded and type(eui) == "table") then
        return
    end
    Theme.ellesmere = true
    local r, g, b = readColor(eui.ELLESMERE_GREEN)
    if r then
        Theme.accent = { r, g, b, 1 }
    end
    r, g, b = readColor(eui.DARK_BG)
    if r then
        Theme.bg = { r, g, b, 0.94 }
    end
    if type(eui.GetFontPath) == "function" then
        local ok, path = pcall(eui.GetFontPath, "pt60")
        if ok and type(path) == "string" and path ~= "" then
            Theme.font = path
        end
    end
end

-- Inline icons for text (|T escapes). Game icons are cropped to hide their border.
local ICONS = {
    clock = { "Interface\\Icons\\INV_Misc_PocketWatch_01", "64:64:6:58:6:58" },
    quest = { "Interface\\GossipFrame\\ActiveQuestIcon" },
    rested = { "Interface\\CharacterFrame\\UI-StateIcon", "64:64:0:32:0:27" },
    ok = { "Interface\\RaidFrame\\ReadyCheck-Ready" },
    wait = { "Interface\\RaidFrame\\ReadyCheck-Waiting" },
    bad = { "Interface\\RaidFrame\\ReadyCheck-NotReady" },
}

function Theme.Icon(key, size)
    local icon = ICONS[key]
    size = size or 14
    local coords = icon[2] and (":0:0:" .. icon[2]) or ""
    return string.format("|T%s:%d:%d%s|t", icon[1], size, size, coords)
end

function Theme.Hex(color)
    return string.format("|cff%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
end

Theme.STATE = {
    done = { label = "Goal reached", color = "accent", icon = "ok" },
    ahead = { label = "Ahead", color = "accent", icon = "ok" },
    ontrack = { label = "On track", color = "accent", icon = "ok" },
    behind = { label = "Behind", color = "warn", icon = "wait" },
    overdue = { label = "Overdue", color = "bad", icon = "bad" },
    risk = { label = "At risk", color = "bad", icon = "bad" },
}

-- Label, colour and icon key for a Plan.Status() result.
function Theme.StateOf(status)
    local key = status.state
    if status.atRisk and (key == "behind" or key == "ontrack") then
        key = "risk"
    end
    local state = Theme.STATE[key]
    return state.label, Theme[state.color], state.icon
end

-- "[icon] On track +0.4d", coloured.
function Theme.StateText(status, size)
    local label, color, icon = Theme.StateOf(status)
    if status.state == "ahead" or status.state == "behind" then
        label = string.format("%s %+.1fd", label, status.deltaDays)
    end
    return Theme.Icon(icon, size) .. " " .. Theme.Hex(color) .. label .. "|r"
end
