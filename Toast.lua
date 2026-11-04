local _, ns = ...

local Theme, W = ns.Theme, ns.W

local Toast = {}
ns.Toast = Toast

local HOLD, FADE = 4, 1
local READY_CHECK_SOUND = 8960
local frame

local function build()
    frame = W.Panel(UIParent)
    frame:SetSize(280, 52)
    frame:SetPoint("TOP", 0, -120)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdropBorderColor(unpack(Theme.accent))
    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(ns.ICON)
    logo:SetSize(34, 34)
    logo:SetPoint("LEFT", 10, 0)
    frame.title = W.Text(frame, 14, Theme.accent, "CENTER")
    frame.title:SetPoint("TOP", 0, -10)
    frame.body = W.Text(frame, 11, Theme.text, "CENTER")
    frame.body:SetPoint("BOTTOM", 0, 10)
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.age = self.age + elapsed
        if self.age > HOLD + FADE then
            self:Hide()
        elseif self.age > HOLD then
            self:SetAlpha(1 - (self.age - HOLD) / FADE)
        end
    end)
end

function Toast.Show(title, body)
    if not frame then
        build()
    end
    frame.title:SetText(title)
    frame.body:SetText(body)
    frame.age = 0
    frame:SetAlpha(1)
    frame:Show()
    if ns.db.settings.toastSound then
        PlaySound(READY_CHECK_SOUND, "Master")
    end
end
