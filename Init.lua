local ADDON, ns = ...

ns.name = ADDON
ns.TITLE = "planTo60"
ns.ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon" -- 64x64
ns.LOGO = "Interface\\AddOns\\" .. ADDON .. "\\Media\\logo" -- 256x256
ns.DAY = 86400

local listeners = {}

-- UI pieces subscribe here; Core calls ns.Refresh() whenever plan data changes.
function ns.OnRefresh(fn)
    listeners[#listeners + 1] = fn
end

function ns.Refresh()
    for _, fn in ipairs(listeners) do
        fn()
    end
end

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|T" .. ns.ICON .. ":14:14|t |cff1fd1a0" .. ns.TITLE .. "|r " .. msg)
end

-- 58000 -> "58.0k", 1234567 -> "1.23M"
function ns.FormatXP(n)
    n = math.floor(n + 0.5)
    if n >= 1000000 then
        return string.format("%.2fM", n / 1000000)
    elseif n >= 10000 then
        return string.format("%.1fk", n / 1000)
    elseif n >= 1000 then
        return string.format("%.2fk", n / 1000)
    end
    return tostring(n)
end

-- 2700 -> "45m", 3600 -> "1h", 12000 -> "3h 20m"
function ns.FormatDuration(seconds)
    local minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 60 then
        return minutes .. "m"
    elseif minutes % 60 == 0 then
        return (minutes / 60) .. "h"
    end
    return string.format("%dh %dm", math.floor(minutes / 60), minutes % 60)
end

function ns.Round(n, places)
    local m = 10 ^ (places or 0)
    return math.floor(n * m + 0.5) / m
end
