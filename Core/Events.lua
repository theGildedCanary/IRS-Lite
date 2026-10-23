-- Only the events needed for earnings and bank-transfer matching are registered.
local ADDON_NAME, IRS = ...
IRS:EnsureDB()
local function WarbandGold()
    if not C_Bank or not C_Bank.FetchDepositedMoney or not Enum or not Enum.BankType then return nil end
    local ok, value = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Account)
    if ok and type(value) == "number" and value >= 0 then return value end
end
function IRS:ScanWarbandGold(baseline)
    local current = WarbandGold()
    if current == nil then return end
    local previous = self.warbandBalance
    self.warbandBalance = current
    if not baseline and previous ~= nil and previous ~= current then
        self:ObserveInternalStorageDelta("warband", nil, current - previous)
    end
end
function IRS:HandleMoneyChange()
    local current = GetMoney()
    local previous = self.walletBalance
    self.walletBalance = current
    if previous == nil or previous == current then return end
    self:ScanWarbandGold()
    local remaining = self:FilterInternalWalletChange(current - previous, self:CharacterKey())
    self:RecordEarnings(remaining, self:CharacterKey())
end
local function RescanBanks()
    for _, delay in ipairs({0.2, 1.0}) do
        C_Timer.After(delay, function()
            IRS:ScanWarbandGold()
            if IRS.guildBankRuntime.isOpen then IRS:ScanGuildBankGold(true) end
            if IRS.RefreshUI then IRS:RefreshUI() end
        end)
    end
end
local events = CreateFrame("Frame")
for _, name in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_MONEY", "ACCOUNT_MONEY",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED",
    "GUILDBANK_UPDATE_MONEY", "PLAYER_GUILD_UPDATE", "PLAYER_LOGOUT"}) do
    events:RegisterEvent(name)
end
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        IRS:EnsureDB()
        IRS:ApplySavedFontSizes()
        IRS:ApplySavedLayoutStyle()
        IRS:RestoreWindow()
        IRS:RefreshMinimapButton()
    elseif event == "PLAYER_LOGIN" then
        IRS.walletBalance = GetMoney()
        IRS:ScanWarbandGold(true)
        IRS:RegisterCurrentGuildBank()
        IRS:RefreshUI()
    elseif event == "PLAYER_MONEY" then
        IRS:HandleMoneyChange()
        if IRS.warbandBankRuntime.isOpen or IRS.guildBankRuntime.isOpen then RescanBanks() end
    elseif event == "ACCOUNT_MONEY" then
        IRS:ScanWarbandGold()
    elseif event == "BANKFRAME_OPENED" then
        IRS.warbandBankRuntime.isOpen = true
        IRS:ScanWarbandGold(true)
    elseif event == "BANKFRAME_CLOSED" then
        IRS.warbandBankRuntime.isOpen = false
    elseif event == "GUILDBANKFRAME_OPENED" then
        IRS.guildBankRuntime.isOpen = true
        IRS.guildBankRuntime.hasMoneyUpdate = false
        IRS.guildBankRuntime.balance = nil
        IRS:ScanGuildBankGold(false)
        RescanBanks()
    elseif event == "GUILDBANKFRAME_CLOSED" then
        IRS.guildBankRuntime.isOpen = false
        IRS.guildBankRuntime.hasMoneyUpdate = false
    elseif event == "GUILDBANK_UPDATE_MONEY" then
        IRS.guildBankRuntime.hasMoneyUpdate = true
        IRS:ScanGuildBankGold(true)
        RescanBanks()
    elseif event == "PLAYER_GUILD_UPDATE" then
        IRS:RegisterCurrentGuildBank()
        IRS:RefreshUI()
    elseif event == "PLAYER_LOGOUT" then
        -- Timers may not run during logout; commit unmatched pending wallet changes.
        for i = #IRS.internalTransferRuntime.pendingWallet, 1, -1 do
            IRS:FinalizePendingInternalWallet(IRS.internalTransferRuntime.pendingWallet[i].id)
        end
    end
end)
SLASH_IRSLITE1 = "/irslite"
SLASH_IRSLITE2 = "/irsl"
SlashCmdList.IRSLITE = function(message)
    local command = strtrim(message or ""):lower()
    if command == "tools" or command == "settings" or command == "dashboard" then
        IRS:ShowUI(command)
    elseif command == "help" then
        IRS:ShowUI("tools")
    else
        IRS:ToggleUI()
    end
end
