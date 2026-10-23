-- Lite settings and a manual import from the full addon.
local _, IRS = ...
local page = IRS.settingsPage
local function Text(parent, style, x, y, width, content)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    IRS:RegisterFontString("main", style, fs)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(0.88, 0.84, 0.75)
    fs:SetText(content)
    return fs
end
local function Button(parent, label, x, y, width, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(width, 28)
    button:SetText(label)
    IRS:RegisterFontString("main", "label", button:GetFontString())
    button:SetScript("OnClick", callback)
    return button
end
Text(page, "page", 4, -4, 800, "SETTINGS")
local sections = {}
for _, key in ipairs({"minimap", "transfers", "fonts", "import"}) do
    local section = CreateFrame("Frame", nil, page)
    section:SetPoint("TOPLEFT", 0, -84)
    section:SetPoint("BOTTOMRIGHT", 0, 0)
    section:Hide()
    sections[key] = section
end
function IRS:SelectSettingsSection(key)
    if not sections[key] then key = "minimap" end
    self.db.ui.settingsSection = key
    for name, section in pairs(sections) do section:SetShown(name == key) end
    self:RefreshSettingsPage()
end
for i, entry in ipairs({{"minimap", "MINIMAP BUTTON"}, {"transfers", "TRANSFERS"}, {"fonts", "FONTS"}, {"import", "IMPORT"}}) do
    local key = entry[1]
    Button(page, entry[2], 4 + (i-1)*186, -44, 176, function() IRS:SelectSettingsSection(key) end)
end
local check = CreateFrame("CheckButton", nil, sections.minimap, "UICheckButtonTemplate")
check:SetPoint("TOPLEFT", 12, -18)
check:SetSize(28, 28)
Text(sections.minimap, "label", 48, -22, 700, "Show minimap button")
Text(sections.minimap, "body", 16, -70, 780, "Left-click opens or closes IRS Lite. Right-click opens Settings.")
check:SetScript("OnClick", function(self)
    IRS.db.settings.showMinimapButton = self:GetChecked() == true
    IRS:RefreshMinimapButton()
end)
IRS:BuildInternalTransferSettingsSection(sections.transfers)
local fonts = sections.fonts
Text(fonts, "section", 16, -12, 800, "FONT FACE")
local faces = {}
for i, option in ipairs(IRS.FONT_FACE_OPTIONS) do
    local key = option.key
    faces[i] = Button(fonts, option.label, 16 + (i-1)*204, -44, 196, function() IRS:SetFontFace(key) end)
end
Text(fonts, "helper", 16, -84, 800, "Sizes apply immediately. Values are clamped to the supported range for each text style.")
local fields = {}
for i, style in ipairs(IRS.FONT_STYLE_ORDER.main) do
    local key = style
    local column, row = (i-1)%2, math.floor((i-1)/2)
    local x, y = 16 + column*410, -120 - row*44
    Text(fonts, "label", x, y-6, 180, IRS.FONT_STYLE_LABELS.main[key])
    local field = CreateFrame("EditBox", nil, fonts, "InputBoxTemplate")
    field:SetPoint("TOPLEFT", x+190, y)
    field:SetSize(60, 28)
    field:SetAutoFocus(false)
    field:SetNumeric(true)
    field:SetMaxLetters(2)
    IRS:RegisterFontString("main", "body", field)
    local function Commit(self)
        IRS:SetFontSize("main", key, self:GetText())
        self:ClearFocus()
    end
    field:SetScript("OnEnterPressed", Commit)
    field:SetScript("OnEditFocusLost", Commit)
    field:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(IRS:GetFontSize("main", key)))
        self:ClearFocus()
    end)
    fields[key] = field
end
Button(fonts, "RESET FONT SIZES", 16, -308, 220, function() IRS:ResetFontSizes("main") end)
local importPage = sections["import"]
Text(importPage, "section", 16, -12, 800, "IMPORT IRS FILES")
Text(importPage, "body", 16, -48, 800, "Copy IRS earnings history, character totals, transfer settings, and fonts into Lite. This replaces Lite's current history. Your original IRS records stay unchanged.")
local importSummary = Text(importPage, "body", 16, -110, 800, "")
local importStatus = Text(importPage, "helper", 16, -278, 800, "")
local confirmation = Text(importPage, "body", 16, -210, 800, "Replace Lite history with the IRS records shown above?")
local confirm, cancel
local function HideConfirmation()
    confirmation:Hide()
    confirm:Hide()
    cancel:Hide()
end
local importButton = Button(importPage, "Import IRS files", 16, -168, 200, function()
    local preview, reason = IRS:GetIRSImportPreview()
    if not preview then importStatus:SetText(reason); return end
    importStatus:SetText("")
    confirmation:Show()
    confirm:Show()
    cancel:Show()
end)
confirm = Button(importPage, "REPLACE LITE HISTORY", 16, -242, 230, function()
    local _, message = IRS:ImportIRSFiles()
    importStatus:SetText(message)
    HideConfirmation()
end)
cancel = Button(importPage, "CANCEL", 258, -242, 110, HideConfirmation)
HideConfirmation()
importPage:SetScript("OnHide", HideConfirmation)
local function RefreshImport()
    local snapshot, reason = IRS:GetIRSImportPreview()
    importButton:SetEnabled(snapshot ~= nil)
    if snapshot then
        importSummary:SetText(string.format("IRS records available: %d characters, %d recorded days.\nTotal Recorded: %s", snapshot.characterCount, snapshot.dayCount, IRS:FormatMoney(snapshot.tracking.total + snapshot.tracking.overallAdjustment, true)))
    else
        importSummary:SetText(reason)
    end
end
function IRS:RefreshSettingsPage()
    check:SetChecked(self.db.settings.showMinimapButton ~= false)
    for key, field in pairs(fields) do
        if not field:HasFocus() then field:SetText(tostring(self:GetFontSize("main", key))) end
    end
    local _, _, selected = self:GetFontFace()
    for i, button in ipairs(faces) do
        button:SetEnabled(self.FONT_FACE_OPTIONS[i].key ~= selected)
    end
    self:RefreshInternalTransferSettingsSection()
    RefreshImport()
end
IRS:SelectSettingsSection(IRS.db.ui.settingsSection or "minimap")
