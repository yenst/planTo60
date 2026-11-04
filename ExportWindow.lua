local _, ns = ...

local Theme, W = ns.Theme, ns.W

-- Copy/paste window for the JSON export and import.
local ExportWindow = {}
ns.ExportWindow = ExportWindow

local WIDTH, HEIGHT = 620, 460
local window
local mode, scope = "export", "character"

local function exportText()
    local chars = scope == "all" and ns.CharacterList() or { ns.char }
    return ns.Export.ToJSON(chars, true)
end

local function runImport()
    local text = window.edit:GetText()
    local plan, err = ns.Export.ReadPlan(text, ns.char.name, ns.char.realm)
    if not plan then
        window.status:SetText(Theme.Hex(Theme.bad) .. err .. "|r")
        return
    end
    for key in pairs(plan.schedule.off) do
        ns.char.schedule.off[key] = true
    end
    ns.char.schedule.dayHours = ns.char.schedule.dayHours or {}
    for key, hours in pairs(plan.schedule.dayHours or {}) do
        ns.char.schedule.dayHours[key] = hours
    end
    local applied, problem = ns.ApplyDraft({ level = plan.level, date = plan.deadline, mode = plan.mode, weights = plan.schedule.weights })
    if applied then
        window.status:SetText(Theme.Hex(Theme.accent) .. "Imported goal and schedule from " .. plan.source .. ".|r")
    else
        window.status:SetText(Theme.Hex(Theme.bad) .. problem .. "|r")
    end
end

local function build()
    window = W.Window("pt60Export", WIDTH, HEIGHT, "Export / import")
    window:SetFrameStrata("FULLSCREEN_DIALOG")

    window.hint = W.Text(window, 11, Theme.muted)
    window.hint:SetPoint("TOPLEFT", 16, -42)

    window.scopeCharacter = W.Button(window, "This character", 120, 22, function()
        scope = "character"
        ExportWindow.Update()
    end)
    window.scopeCharacter:SetPoint("TOPRIGHT", -144, -38)
    window.scopeAll = W.Button(window, "All characters", 120, 22, function()
        scope = "all"
        ExportWindow.Update()
    end)
    window.scopeAll:SetPoint("TOPRIGHT", -16, -38)

    local box = W.Panel(window, { 0, 0, 0, 0.5 })
    box:SetPoint("TOPLEFT", 16, -70)
    box:SetPoint("BOTTOMRIGHT", -16, 52)
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFont("Fonts\\ARIALN.TTF", 12, "")
    edit:SetTextColor(unpack(Theme.text))
    edit:SetWidth(WIDTH - 50)
    edit:SetScript("OnEscapePressed", function() window:Hide() end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        -- The export view is read-only; typing restores the export.
        if userInput and mode == "export" then
            self:SetText(window.exported)
            self:HighlightText()
        end
    end)
    edit:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local top, visible = scroll:GetVerticalScroll(), scroll:GetHeight()
        y = -y
        if y < top then
            scroll:SetVerticalScroll(y)
        elseif y + height > top + visible then
            scroll:SetVerticalScroll(y + height - visible)
        end
    end)
    scroll:SetScrollChild(edit)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * 48
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), target)))
    end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    window.edit = edit

    window.status = W.Text(window, 11)
    window.status:SetPoint("BOTTOMLEFT", 16, 22)
    window.action = W.Button(window, "", 120, 26, function()
        if mode == "import" then
            runImport()
        else
            edit:SetFocus()
            edit:HighlightText()
        end
    end)
    window.action:SetPoint("BOTTOMRIGHT", -16, 14)
end

function ExportWindow.Update()
    local exporting = mode == "export"
    window.scopeCharacter:SetShown(exporting)
    window.scopeAll:SetShown(exporting)
    window.scopeCharacter:SetSelected(scope == "character")
    window.scopeAll:SetSelected(scope == "all")
    window.status:SetText("")
    if exporting then
        window.hint:SetText("Already selected: press Ctrl+C to copy, then paste it anywhere.")
        window.exported = exportText()
        window.edit:SetText(window.exported)
        window.edit:SetFocus()
        window.edit:HighlightText()
        window.action:SetLabel("Select all")
    else
        window.hint:SetText("Paste a planTo60 export (Ctrl+V). Its goal and schedule replace this character's.")
        window.edit:SetText("")
        window.edit:SetFocus()
        window.action:SetLabel("Import")
    end
end

function ExportWindow.Open(newMode)
    if not window then
        build()
    end
    mode = newMode
    window:Show()
    ExportWindow.Update()
end
