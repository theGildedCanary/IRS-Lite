-- Tools is deliberately limited to the manual and the two earnings corrections.
local _, IRS = ...
local page = IRS.toolsPage
local function Text(parent, style, x, y, width, content)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    IRS:RegisterFontString("main", style, text)
    text:SetPoint("TOPLEFT", x, y)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    IRS:SetLayoutColor(text, "SetTextColor", 0.88, 0.84, 0.75)
    text:SetText(content)
    return text
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
Text(page, "page", 4, -4, 800, "TOOLS")
local manual = CreateFrame("ScrollFrame", "IRSLiteManualScroll", page, "UIPanelScrollFrameTemplate")
manual:SetPoint("TOPLEFT", 4, -88)
manual:SetPoint("BOTTOMRIGHT", -28, 8)
local child = CreateFrame("Frame", nil, manual)
child:SetSize(820, 1)
manual:SetScrollChild(child)
local manualText = Text(child, "body", 0, 0, 800, [[IRS LITE USER'S MANUAL

EARNINGS
Today, This Reset, This Month, and Total Recorded show account-wide net earnings observed while Lite is enabled. The smaller values show the current character. Positive wallet changes add earnings; spending subtracts them. These figures are not your current gold balance or Blizzard lifetime statistics. Offline activity and characters without Lite enabled are not tracked.

DAILY GRAPH
The graph shows the last seven calendar days, including today. Gains rise above zero; losses extend below zero. Empty days show zero. Today and This Month follow the local calendar; This Reset follows the game's weekly reset.

TRANSFERS
Wallet movements to and from the Warband Bank are excluded from earnings. In Settings > Transfers, mark personal Guild Banks to exclude their transfers too. Log in to a guild character to discover its bank, then open the bank before moving gold. Shared guild-bank movements remain earnings or spending. Matching may briefly defer a wallet change while a bank is open. Unmatched changes become normal earnings or spending. Mailed or traded gold between characters is not automatically identified as internal.

ADJUSTMENTS
Daily Income Adjustment adds a signed correction to the current character and account Today, This Reset, This Month, and Total Recorded, including today's graph bar. Overall Income Adjustment changes only account Total Recorded. Neither moves actual gold. Enter +500g or -500g; k and m suffixes are accepted.

SETTINGS AND WINDOW
Settings contains the minimap toggle, transfer settings, font controls, appearance presets, and Import IRS files. Choose IRS Default or ElvUI Inspired under Profiles; ElvUI is not required. Drag the window to move it. Escape closes it. The minimap button opens Lite; right-click opens Settings.

COMMANDS
/irslite or /irsl — toggle Lite
/irslite dashboard — open Dashboard
/irslite tools — open Tools
/irslite settings — open Settings

STORAGE
Lite uses its own account-wide IRSLiteDB. To copy your existing IRS history, enable both addons, reload, and use Settings > Import > Import IRS files. Confirm to replace Lite's history with a separate copy of IRS earnings, character totals, transfer settings, fonts, and appearance. Importing never changes the full addon's records. You can disable the full addon afterward; it keeps /irs when enabled.]])
local adjustments = CreateFrame("Frame", nil, page)
adjustments:SetPoint("TOPLEFT", 4, -88)
adjustments:SetPoint("BOTTOMRIGHT", -4, 8)
local function ShowSection(section)
    IRS.db.ui.toolsSection = section
    manual:SetShown(section == "manual")
    adjustments:SetShown(section == "adjustments")
end
Button(page, "USER MANUAL", 4, -44, 150, function() ShowSection("manual") end)
Button(page, "ADJUSTMENTS", 166, -44, 160, function() ShowSection("adjustments") end)
function IRS:ParseAdjustment(value)
    local cleaned = strtrim(value or ""):lower():gsub(",", ""):gsub("%s+", "")
    local sign, number, suffix = cleaned:match("^([+-]?)(%d+%.?%d*)([km]?)g?$")
    if not number then return nil end
    local gold = tonumber(number) * (suffix == "m" and 1000000 or suffix == "k" and 1000 or 1)
    if gold ~= gold or gold >= math.huge or gold > 100000000000 then return nil end
    local copper = math.floor(gold * 10000 + 0.5)
    if copper == 0 then return nil end
    return sign == "-" and -copper or copper
end
local summaries = {}
local function Adjustment(y, heading, explanation, method, summaryKey)
    Text(adjustments, "section", 8, y, 800, heading)
    Text(adjustments, "body", 8, y - 32, 800, explanation)
    summaries[summaryKey] = Text(adjustments, "helper", 8, y - 78, 460, "")
    local input = CreateFrame("EditBox", nil, adjustments, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", 500, y - 76)
    input:SetSize(150, 28)
    input:SetAutoFocus(false)
    input:SetMaxLetters(22)
    IRS:RegisterFontString("main", "body", input)
    local status = Text(adjustments, "helper", 8, y - 116, 800, "")
    local function Apply()
        local amount = IRS:ParseAdjustment(input:GetText())
        if not amount then status:SetText("Enter a non-zero amount, such as +500g or -500g."); return end
        local ok, errorText = IRS[method](IRS, amount)
        status:SetText(ok and ("Applied " .. IRS:FormatMoney(amount, true) .. ".") or errorText)
        if ok then input:SetText(""); IRS:RefreshUI() end
        input:ClearFocus()
    end
    Button(adjustments, "APPLY", 670, y - 76, 110, Apply)
    input:SetScript("OnEnterPressed", Apply)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
end
Adjustment(-4, "DAILY INCOME ADJUSTMENT", "Correct current character and account earnings for today, this reset, this month, and total.", "AdjustCurrentCharacterEarnings", "daily")
Adjustment(-182, "OVERALL INCOME ADJUSTMENT", "Correct account Total Recorded. Period totals, graph history, and character earnings stay unchanged.", "AdjustAccountTotalEarnings", "overall")
function IRS:RefreshToolsPage()
    summaries.daily:SetText(self:CharacterLabel() .. " today: " .. self:FormatMoney(self:GetCharacterEarnings().today, true))
    summaries.overall:SetText("Account total: " .. self:FormatMoney(self:GetCurrentEarnings().total, true))
    child:SetWidth(math.max(1, manual:GetWidth() - 6))
    manualText:SetWidth(math.max(1, child:GetWidth() - 8))
    child:SetHeight(manualText:GetStringHeight() + 20)
end
ShowSection(IRS.db.ui.toolsSection == "adjustments" and "adjustments" or "manual")
