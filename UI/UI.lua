local _, IRS = ...

-- Central visual palette. Change colors here instead of hunting through the UI.
-- Values are RGBA (red, green, blue, alpha), each from 0.0 to 1.0.
local COLORS = {
    -- Warm report palette based on the original IRS scanner aesthetic.
    bg = {0.165, 0.125, 0.085, 0.92},
    panel = {0.190, 0.145, 0.098, 0.88},
    border = {0.52, 0.39, 0.22, 1},
    borderSoft = {0.36, 0.28, 0.18, 1},
    gold = {0.86, 0.71, 0.36, 1},
    goldSoft = {0.79, 0.66, 0.39, 1},
    text = {0.88, 0.84, 0.75, 1},
    muted = {0.68, 0.62, 0.51, 1},
    red = {0.63, 0.29, 0.25, 1},
    cyan = {0.40, 0.63, 0.65, 1},
}

-- Base folder for custom IRS artwork. Helper functions append filenames to this.
local MEDIA = [[Interface\AddOns\IRS Lite\Media\]]

-- Applies one COLORS entry to a FontString. Keeping this tiny helper avoids
-- repeating RGBA indexing everywhere.
local function SetColor(fontString, color)
    IRS:SetLayoutColor(fontString, "SetTextColor", color[1], color[2], color[3], color[4] or 1)
end

-- Creates a consistently styled FontString. Most visible text in IRS starts here.
local function MakeText(parent, size, color, justify, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local fontPath = font or STANDARD_TEXT_FONT
    local renderedSize = IRS:GetFontSize("main", size)

    fs:SetFont(fontPath, renderedSize, "")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("MIDDLE")
    if color then SetColor(fs, color) end

    if size then
        IRS:RegisterFontString("main", size, fs, fontPath, "")
    end

    return fs
end

-- Creates the dark bordered panel used throughout IRS cards and content boxes.
local function MakePanel(parent, bgColor)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    local c = bgColor or COLORS.panel
    IRS:SetLayoutColor(panel, "SetBackdropColor", c[1], c[2], c[3], c[4] or 1)
    IRS:SetLayoutColor(panel, "SetBackdropBorderColor", unpack(COLORS.borderSoft))
    return panel
end

-- Creates a custom IRS texture from the Media folder. "path" is the filename
-- without the file extension.
local function MakeTexture(parent, path, size, layer)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    tex:SetTexture(MEDIA .. path)
    tex:SetSize(size, size)
    return tex
end

-- UI-friendly money formatter. Unlike the Core formatter, this intentionally
-- favors compact dashboard text such as 12.4k or -250g.
local function FormatGold(copper, includeChange)
    copper = math.floor(tonumber(copper) or 0)
    local negative = copper < 0
    local absolute = math.abs(copper)
    local gold = math.floor(absolute / 10000)
    local silver = math.floor((absolute % 10000) / 100)
    local copperOnly = absolute % 100
    local goldText = IRS:FormatCount(gold)
    local sign = negative and "-" or ""

    if gold > 0 then
        if includeChange and (silver > 0 or copperOnly > 0) and gold < 1000 then
            return string.format("%s%sg %02ds %02dc", sign, goldText, silver, copperOnly)
        end
        return sign .. goldText .. "g"
    end
    if silver > 0 then return string.format("%s%ds %02dc", sign, silver, copperOnly) end
    if copperOnly > 0 then return sign .. tostring(copperOnly) .. "c" end
    return "0g"
end

-- Extra-short number formatter used only for graph axis labels.
local function FormatChartGold(copper)
    local value = tonumber(copper) or 0
    local sign = value < 0 and "-" or ""
    local gold = math.floor(math.abs(value) / 10000)
    if gold >= 1000000 then return string.format("%s%.1fm", sign, gold / 1000000) end
    if gold >= 1000 then return string.format("%s%.0fk", sign, gold / 1000) end
    return sign .. tostring(gold)
end

-- Color convention for NET values: losses red, gains gold, zero uses the supplied
-- neutral color.
local function SetNetColor(fontString, amount, zeroColor, positiveColor)
    amount = tonumber(amount) or 0
    if amount < 0 then
        SetColor(fontString, COLORS.red)
    elseif amount > 0 then
        SetColor(fontString, positiveColor or COLORS.gold)
    else
        SetColor(fontString, zeroColor or COLORS.gold)
    end
end



local frame = CreateFrame("Frame", "IRSLiteFrame", UIParent, "BackdropTemplate")
frame:SetSize(1080, 560)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint()
    IRS.db.ui.position = {point, relativePoint, x, y}
end)
frame:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
})
IRS:SetLayoutColor(frame, "SetBackdropColor", unpack(COLORS.bg))
IRS:SetLayoutColor(frame, "SetBackdropBorderColor", unpack(COLORS.border))
frame:Hide()
IRS.mainFrame = frame


if UISpecialFrames then
    local found = false
    for _, name in ipairs(UISpecialFrames) do
        if name == "IRSLiteFrame" then found = true break end
    end
    if not found then table.insert(UISpecialFrames, "IRSLiteFrame") end
end

-- ============================================================================
-- SECTION 1 - MAIN WINDOW HEADER
-- IRS title, logo, Last Updated text, and close button.
-- ============================================================================
local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
header:SetPoint("TOPLEFT", 12, -12)
header:SetPoint("TOPRIGHT", -12, -12)
header:SetHeight(64)
header:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
IRS:SetLayoutColor(header, "SetBackdropColor", unpack(COLORS.bg))

local headerLine = header:CreateTexture(nil, "BORDER")
headerLine:SetTexture("Interface/Buttons/WHITE8X8")
IRS:SetLayoutColor(headerLine, "SetVertexColor", unpack(COLORS.border))
headerLine:SetHeight(1)
headerLine:SetPoint("BOTTOMLEFT", 0, 0)
headerLine:SetPoint("BOTTOMRIGHT", 0, 0)

local titleIcon = MakeTexture(header, "IRSTitleIcon", 54)
titleIcon:SetPoint("LEFT", 8, 0)

local irsText = MakeText(header, "brand", COLORS.gold, "LEFT")
irsText:SetPoint("LEFT", titleIcon, "RIGHT", 8, 7)
irsText:SetText("IRS")

local title = MakeText(header, "section", COLORS.text, "LEFT")
title:SetPoint("LEFT", irsText, "RIGHT", 15, 9)
title:SetText("INCOME RECORDS SYSTEM")

local titleSub = MakeText(header, "body", COLORS.goldSoft, "LEFT")
titleSub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
titleSub:SetText("LITE | ACCOUNT GOLD TRACKER")

local lastUpdated = MakeText(header, "helper", COLORS.muted, "RIGHT")
lastUpdated:SetPoint("RIGHT", -44, 3)
lastUpdated:SetWidth(150)
lastUpdated:SetText("Last Updated\n-")

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
IRS:StyleButtonFeedback(close)
close:SetPoint("TOPRIGHT", -8, -8)

-- ============================================================================
-- SECTION 2 - SIDEBAR NAVIGATION
-- Dashboard / Tools / Settings.
-- ============================================================================
local rail = MakePanel(frame, COLORS.bg)
rail:SetPoint("TOPLEFT", 14, -84)
rail:SetPoint("BOTTOMLEFT", 14, 14)
rail:SetWidth(144)
IRS:SetLayoutColor(rail, "SetBackdropBorderColor", 0, 0, 0, 0)
rail.divider = rail:CreateTexture(nil, "BORDER")
rail.divider:SetTexture("Interface/Buttons/WHITE8X8")
IRS:SetLayoutColor(rail.divider, "SetVertexColor", unpack(COLORS.borderSoft))
rail.divider:SetWidth(1)
rail.divider:SetPoint("TOPRIGHT", -1, 0)
rail.divider:SetPoint("BOTTOMRIGHT", -1, 0)

local content = CreateFrame("Frame", nil, frame)
content:SetPoint("TOPLEFT", rail, "TOPRIGHT", 12, 0)
content:SetPoint("BOTTOMRIGHT", -16, 16)

local pages, tabs = {}, {}
local activeTab = "dashboard"



-- Builds one left-sidebar navigation button and wires its hover/click behavior.
local function MakeTab(key, label, y)
    local button = CreateFrame("Button", nil, rail, "BackdropTemplate")
    IRS:StyleButtonFeedback(button)
    button:SetPoint("TOPLEFT", 4, y)
    button:SetPoint("TOPRIGHT", -4, y)
    button:SetHeight(34)
    button:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
    IRS:SetLayoutColor(button, "SetBackdropColor", 0, 0, 0, 0)
    IRS:SetLayoutColor(button, "SetBackdropBorderColor", 0, 0, 0, 0)

    button.activeBar = button:CreateTexture(nil, "ARTWORK")
    button.activeBar:SetTexture("Interface/Buttons/WHITE8X8")
    IRS:SetLayoutColor(button.activeBar, "SetVertexColor", unpack(COLORS.gold))
    button.activeBar:SetWidth(2)
    button.activeBar:SetPoint("TOPLEFT", 0, -5)
    button.activeBar:SetPoint("BOTTOMLEFT", 0, 5)
    button.activeBar:Hide()

    button.label = MakeText(button, "body", COLORS.text, "LEFT")
    button.label:SetPoint("LEFT", 10, 0)
    button.label:SetPoint("RIGHT", -4, 0)
    button.label:SetText(label)

    button:SetScript("OnEnter", function(self)
        if activeTab ~= key then
            SetColor(self.label, COLORS.goldSoft)
        end
    end)

    button:SetScript("OnLeave", function(self)
        if activeTab ~= key then
            SetColor(self.label, COLORS.text)
        end
    end)

    button:SetScript("OnClick", function()
        IRS:SelectTab(key)
    end)

    tabs[key] = button
end

MakeTab("dashboard", "Dashboard", -8)
MakeTab("tools", "Tools", -46)
MakeTab("settings", "Settings", -84)
for _, key in ipairs({"dashboard", "tools", "settings"}) do
    local page = CreateFrame("Frame", nil, content)
    page:SetAllPoints()
    page:Hide()
    pages[key] = page
end
IRS.toolsPage = pages.tools
IRS.settingsPage = pages.settings
local dashboard = pages.dashboard
local periodContainer = CreateFrame("Frame", nil, dashboard)
periodContainer:SetPoint("TOPLEFT", 0, -8)
periodContainer:SetPoint("TOPRIGHT", 0, -8)
periodContainer:SetHeight(84)

local function MakePeriodCard(parent, x, width, heading)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", x, 0)
    card:SetSize(width, 84)

    if x > 0 then
        card.separator = card:CreateTexture(nil, "BORDER")
        card.separator:SetTexture("Interface/Buttons/WHITE8X8")
        IRS:SetLayoutColor(card.separator, "SetVertexColor", unpack(COLORS.borderSoft))
        card.separator:SetWidth(1)
        card.separator:SetPoint("TOPLEFT", 0, -7)
        card.separator:SetPoint("BOTTOMLEFT", 0, 7)
    end

    card.heading = MakeText(card, "helper", COLORS.goldSoft, "CENTER")
    card.heading:SetPoint("TOPLEFT", 5, -6)
    card.heading:SetPoint("TOPRIGHT", -5, -6)
    card.heading:SetText(heading)

    card.value = MakeText(card, "value", COLORS.gold, "CENTER")
    card.value:SetPoint("TOPLEFT", 5, -27)
    card.value:SetPoint("TOPRIGHT", -5, -27)
    card.value:SetText("0g")

    card.characterValue = MakeText(card, "helper", COLORS.muted, "CENTER")
    card.characterValue:SetPoint("BOTTOMLEFT", 5, 7)
    card.characterValue:SetPoint("BOTTOMRIGHT", -5, 7)
    card.characterValue:SetText("0g")

    return card
end

local cardGap = 8
local cardWidth = 209
local todayCard = MakePeriodCard(periodContainer, 0, cardWidth, "TODAY")
local weekCard = MakePeriodCard(periodContainer, cardWidth + cardGap, cardWidth, "THIS RESET")
local monthCard = MakePeriodCard(periodContainer, (cardWidth + cardGap) * 2, cardWidth, "THIS MONTH")
local totalCard = MakePeriodCard(periodContainer, (cardWidth + cardGap) * 3, cardWidth, "TOTAL RECORDED")

local chartTitle = MakeText(dashboard, "section", COLORS.text, "LEFT")
chartTitle:SetPoint("TOPLEFT", 0, -120)
chartTitle:SetText("DAILY EARNINGS (LAST 7 DAYS)")

local titleUnderline = chartTitle:GetParent():CreateTexture(nil, "BORDER")
titleUnderline:SetTexture("Interface/Buttons/WHITE8X8")
IRS:SetLayoutColor(titleUnderline, "SetVertexColor", unpack(COLORS.border))
titleUnderline:SetHeight(1)
titleUnderline:SetPoint("TOPLEFT", dashboard, "TOPLEFT", 0, -146)
titleUnderline:SetPoint("TOPRIGHT", dashboard, "TOPRIGHT", -2, -146)

local chart = CreateFrame("Frame", nil, dashboard)
chart:SetPoint("TOPLEFT", 0, -155)
chart:SetPoint("TOPRIGHT", 0, -155)
chart:SetHeight(178)
chart.bars = {}
chart.grid = {}

for i = 1, 4 do
    local line = chart:CreateTexture(nil, "BORDER")
    line:SetTexture("Interface/Buttons/WHITE8X8")
    IRS:SetLayoutColor(line, "SetVertexColor", 0.27, 0.23, 0.17, 0.75)
    line:SetHeight(1)
    line:SetPoint("LEFT", 52, 0)
    line:SetPoint("RIGHT", -12, 0)
    line:SetPoint("BOTTOM", 0, 28 + ((i - 1) * 35))
    chart.grid[i] = line
end

chart.yLabels = {}
for i = 1, 4 do
    local label = MakeText(chart, "helper", COLORS.muted, "RIGHT")
    label:SetPoint("RIGHT", chart.grid[i], "LEFT", -6, 0)
    label:SetWidth(42)
    chart.yLabels[i] = label
end

for i = 1, 7 do
    local slot = CreateFrame("Frame", nil, chart)
    slot:SetSize(106, 154)
    slot:SetPoint("BOTTOMLEFT", 63 + ((i - 1) * 112), 8)

    local amount = MakeText(slot, "helper", COLORS.goldSoft, "CENTER")
    amount:SetPoint("TOP", 0, -2)
    amount:SetWidth(104)

    local bar = slot:CreateTexture(nil, "ARTWORK")
    bar:SetTexture("Interface/Buttons/WHITE8X8")
    bar:SetWidth(52)
    bar:SetPoint("BOTTOM", 0, 25)
    IRS:SetLayoutColor(bar, "SetVertexColor", unpack(COLORS.cyan))

    local day = MakeText(slot, "helper", COLORS.text, "CENTER")
    day:SetPoint("BOTTOM", 0, 3)
    day:SetWidth(104)

    chart.bars[i] = { slot = slot, bar = bar, amount = amount, day = day }
end

local function RefreshChart()
    local days = IRS:GetRecentDailyEarnings(7)
    local minAmount = 0
    local maxAmount = 0

    for _, day in ipairs(days) do
        local amount = tonumber(day.amount) or 0
        minAmount = math.min(minAmount, amount)
        maxAmount = math.max(maxAmount, amount)
    end

    -- Keep a tiny non-zero range when every displayed day is exactly zero so
    -- positioning math remains valid. Labels still render as 0g.
    local displayMin = minAmount
    local displayMax = maxAmount
    if displayMin == 0 and displayMax == 0 then
        displayMax = 1
    end

    local range = math.max(1, displayMax - displayMin)
    local plotBottom = 28
    local plotTop = 133
    local plotHeight = plotTop - plotBottom
    local slotBottom = 8

    local function ValueToChartY(value)
        return plotBottom
            + (((value - displayMin) / range) * plotHeight)
    end

    -- Four useful grid/tick values. Mixed gain/loss weeks always include the
    -- real minimum, zero, a positive midpoint, and the real maximum. Weeks that
    -- are entirely positive or negative use evenly spaced ticks across the real
    -- range with zero as the appropriate edge.
    local ticks
    if minAmount < 0 and maxAmount > 0 then
        ticks = {
            minAmount,
            0,
            maxAmount * 0.5,
            maxAmount,
        }
    elseif maxAmount > 0 then
        ticks = {
            0,
            maxAmount / 3,
            (maxAmount * 2) / 3,
            maxAmount,
        }
    elseif minAmount < 0 then
        ticks = {
            minAmount,
            (minAmount * 2) / 3,
            minAmount / 3,
            0,
        }
    else
        ticks = {0, 0, 0, 0}
    end

    for i = 1, 4 do
        local value = ticks[i] or 0
        local y = ValueToChartY(value)
        local line = chart.grid[i]

        line:ClearAllPoints()
        line:SetPoint("LEFT", chart, "LEFT", 52, 0)
        line:SetPoint("RIGHT", chart, "RIGHT", -12, 0)
        line:SetPoint("BOTTOM", chart, "BOTTOM", 0, y)

        if math.abs(value) < 1 then
            chart.yLabels[i]:SetText("0")
        else
            chart.yLabels[i]:SetText(FormatChartGold(value))
        end
    end

    local zeroY = ValueToChartY(0)
    local zeroInSlot = zeroY - slotBottom

    for i = 1, 7 do
        local data = days[i] or { label = "-", amount = 0 }
        local ui = chart.bars[i]
        local amount = tonumber(data.amount) or 0
        local h

        if amount == 0 then
            h = 2
        else
            h = math.max(
                3,
                math.min(
                    plotHeight,
                    math.floor((math.abs(amount) / range) * plotHeight)
                )
            )
        end

        ui.bar:ClearAllPoints()
        ui.bar:SetHeight(h)

        if amount < 0 then
            ui.bar:SetPoint("TOP", ui.slot, "BOTTOM", 0, zeroInSlot)
            IRS:SetLayoutColor(ui.bar, "SetVertexColor", unpack(COLORS.red))
        else
            ui.bar:SetPoint("BOTTOM", ui.slot, "BOTTOM", 0, zeroInSlot)
            IRS:SetLayoutColor(ui.bar, "SetVertexColor", unpack(COLORS.cyan))
        end

        ui.amount:SetText(FormatGold(amount))
        SetNetColor(ui.amount, amount, COLORS.goldSoft)
        ui.day:SetText(data.dateLabel or data.label or "-")
    end
end


function IRS:RefreshUI()
    if not IRS.db then return end
    local account, character = IRS:GetCurrentEarnings(), IRS:GetCharacterEarnings()
    local keys = {"today", "week", "month", "total"}
    for i, card in ipairs({todayCard, weekCard, monthCard, totalCard}) do
        local key = keys[i]
        card.value:SetText(FormatGold(account[key], true))
        SetNetColor(card.value, account[key])
        card.characterValue:SetText((UnitName("player") or "Character") .. ": " .. FormatGold(character[key], true))
    end
    lastUpdated:SetText("Last Updated\n" .. date("%H:%M", IRS.db.tracking.lastEarnedAt or GetServerTime()))
    RefreshChart()
    if IRS.RefreshToolsPage then IRS:RefreshToolsPage() end
    if IRS.RefreshSettingsPage then IRS:RefreshSettingsPage() end
end
function IRS:SelectTab(key)
    if not pages[key] then key = "dashboard" end
    activeTab = key
    for name, page in pairs(pages) do
        page:SetShown(name == key)
        tabs[name].activeBar:SetShown(name == key)
        SetColor(tabs[name].label, name == key and COLORS.gold or COLORS.text)
    end
    IRS:RefreshUI()
end
function IRS:ShowUI(key)
    IRS:SelectTab(key or "dashboard")
    frame:Show()
end
function IRS:ToggleUI() frame:SetShown(not frame:IsShown()) end
frame:SetScript("OnShow", function()
    -- Fit smaller displays without changing the saved font sizes.
    frame:SetScale(math.min(1, UIParent:GetWidth() / 1100, UIParent:GetHeight() / 580))
    IRS:RefreshUI()
end)
function IRS:RestoreWindow()
    local p = IRS.db.ui.position
    if p then
        frame:ClearAllPoints()
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
end
local minimapButton = CreateFrame("Button", "IRSLiteMinimapButton", Minimap)
IRS:StyleButtonFeedback(minimapButton)
minimapButton:SetSize(34, 34)
minimapButton:SetPoint("CENTER", Minimap, "CENTER", -56, -56)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

local mapIcon = minimapButton:CreateTexture(nil, "BACKGROUND")
mapIcon:SetTexture(MEDIA .. "IRSButton")
mapIcon:SetSize(34, 34)
mapIcon:SetPoint("CENTER", 0, 0)

local mapHighlight = minimapButton:CreateTexture(nil, "HIGHLIGHT")
mapHighlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
mapHighlight:SetBlendMode("ADD")
mapHighlight:SetSize(36, 36)
mapHighlight:SetPoint("CENTER", 0, 0)

minimapButton:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
        IRS:ShowUI("settings")
    else
        IRS:ToggleUI()
    end
end)
minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("IRS Lite - Income Records System", 1.0, 0.76, 0.28)
    GameTooltip:AddLine("Left-click: open or close IRS.", 0.9, 0.88, 0.81)
    GameTooltip:AddLine("Right-click: open Settings.", 0.9, 0.88, 0.81)
    GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Shows or hides the minimap button according to the saved Settings checkbox.
function IRS:RefreshMinimapButton()
    if not IRS.db then IRS:EnsureDB() end
    minimapButton:SetShown(IRS.db.settings.showMinimapButton ~= false)
end


IRS:SelectTab("dashboard")

-- Re-evaluate displayed periods while the window stays open through a reset.
local elapsedSinceRefresh = 0
frame:HookScript("OnUpdate", function(_, elapsed)
    elapsedSinceRefresh = elapsedSinceRefresh + elapsed
    if elapsedSinceRefresh >= 30 then
        elapsedSinceRefresh = 0
        IRS:RefreshUI()
    end
end)
