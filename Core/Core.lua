-- IRS Lite: account and character net ledgers, stored in copper.
local _, IRS = ...
local function ServerNow() return GetServerTime and GetServerTime() or time() end
-- Migrate only aliases verified by a login to that guild; names alone are not unique.
local function MergeGuildBank(db, oldKey, key)
    if oldKey == key then return end
    local old, current = db.guildBanks[oldKey], db.guildBanks[key]
    if old then
        current = current or {key = key, name = old.name}
        current.realms = current.realms or {}
        if old.realm then current.realms[old.realm] = true end
        for realm in pairs(old.realms or {}) do current.realms[realm] = true end
        if old.money ~= nil and (current.money == nil
            or (tonumber(old.lastSeen) or 0) > (tonumber(current.lastSeen) or 0)) then
            current.money, current.lastSeen = old.money, old.lastSeen
        end
        db.guildBanks[key] = current
        db.guildBanks[oldKey] = nil
    end
    local owned = db.internalTransfers and db.internalTransfers.ownedGuildBanks
    if owned then
        if owned[key] == nil then owned[key] = owned[oldKey] end
        owned[oldKey] = nil
    end
    -- Pending matches must keep the same bank identity when its old key is adopted.
    local runtime = IRS.internalTransferRuntime
    if runtime then
        for _, queue in ipairs({runtime.pendingWallet, runtime.pendingStorage, runtime.recentRecordedWallet, runtime.guildActions, runtime.guildActionReceipts}) do
            for _, entry in ipairs(queue) do
                if entry.storageType == "guild" and entry.storageKey == oldKey then entry.storageKey = key end
                if entry.expectedStorageType == "guild" and entry.expectedStorageKey == oldKey then entry.expectedStorageKey = key end
            end
        end
    end
end
function IRS:NormalizeGuildBanks()
    for oldKey, key in pairs(self.db.guildBankAliases or {}) do
        if oldKey ~= key then MergeGuildBank(self.db, oldKey, key) end
    end
end
local function Ledger()
    return {days = {}, weeks = {}, months = {}, total = 0}
end
function IRS:EnsureDB()
    IRSLiteDB = IRSLiteDB or {}
    self.db = IRSLiteDB
    local db = self.db
    db.schemaVersion = 2
    db.tracking = db.tracking or Ledger()
    db.characters = db.characters or {}
    db.guildBanks = db.guildBanks or {}
    db.guildBankAliases = db.guildBankAliases or {}
    db.settings = db.settings or {showMinimapButton = true}
    db.settings.fontSizes = db.settings.fontSizes or {main = {}}
    db.settings.fontSizes.main = db.settings.fontSizes.main or {}
    db.ui = db.ui or {}
end
function IRS:CharacterKey()
    local legacyKey = (UnitName("player") or "Unknown") .. "@" .. (GetRealmName() or "Unknown")
    local guid = UnitGUID and UnitGUID("player")
    local key = guid and guid ~= "" and guid or legacyKey
    -- Keep history from the initial Lite build when upgrading its character keys.
    if self.db and key ~= legacyKey and self.db.characters[legacyKey] then
        if not self.db.characters[key] then self.db.characters[key] = self.db.characters[legacyKey] end
        self.db.characters[legacyKey] = nil
    end
    return key
end
function IRS:CharacterLabel() return UnitName("player") or "Character" end
local function Add(ledger, amount, keys)
    ledger.total = (ledger.total or 0) + amount
    for i, period in ipairs({"days", "weeks", "months"}) do
        ledger[period][keys[i]] = (ledger[period][keys[i]] or 0) + amount
    end
end
-- Optional period keys preserve the original date when a deferred transfer is corrected.
function IRS:RecordEarnings(amount, characterKey, periodKeys)
    if amount == 0 then return end
    local keys = periodKeys or {self:GetPeriodKeys()}
    local key = characterKey or self:CharacterKey()
    self.db.characters[key] = self.db.characters[key] or Ledger()
    Add(self.db.tracking, amount, keys)
    Add(self.db.characters[key], amount, keys)
    self.db.tracking.lastEarnedAt = ServerNow()
    if self.RefreshUI then self:RefreshUI() end
end
local function Earnings(ledger, keys)
    ledger = ledger or Ledger()
    return {today = ledger.days[keys[1]] or 0, week = ledger.weeks[keys[2]] or 0,
        month = ledger.months[keys[3]] or 0, total = ledger.total or 0}
end
function IRS:GetCurrentEarnings()
    local result = Earnings(self.db.tracking, {self:GetPeriodKeys()})
    result.total = result.total + (self.db.tracking.overallAdjustment or 0)
    return result
end
function IRS:GetCharacterEarnings(key)
    return Earnings(self.db.characters[key or self:CharacterKey()], {self:GetPeriodKeys()})
end
local function ValidAmount(amount)
    return type(amount) == "number" and amount == amount and math.abs(amount) < math.huge and amount ~= 0
end
function IRS:AdjustCurrentCharacterEarnings(amount)
    if not ValidAmount(amount) then return false, "Enter a finite, non-zero amount." end
    self:RecordEarnings(math.floor(amount), self:CharacterKey())
    return true
end
function IRS:AdjustAccountTotalEarnings(amount)
    if not ValidAmount(amount) then return false, "Enter a finite, non-zero amount." end
    self.db.tracking.overallAdjustment = (self.db.tracking.overallAdjustment or 0) + math.floor(amount)
    return true
end
function IRS:GetRecentDailyEarnings(count)
    local results = {}
    -- Use local noon and calendar arithmetic to avoid repeating a day at DST changes.
    local today = date("*t", ServerNow())
    for offset = (count or 7) - 1, 0, -1 do
        local stamp = time({year = today.year, month = today.month, day = today.day - offset, hour = 12})
        local key = date("%Y-%m-%d", stamp)
        results[#results + 1] = {key = key, dateLabel = date("%b %d", stamp), amount = self.db.tracking.days[key] or 0}
    end
    return results
end
function IRS:GetSortedGuildBanks()
    self:NormalizeGuildBanks()
    local rows = {}
    for key, record in pairs(self.db.guildBanks) do rows[#rows + 1] = {key = key, record = record} end
    table.sort(rows, function(a,b) return (a.record.name or a.key) < (b.record.name or b.key) end)
    return rows
end
IRS.guildBankRuntime = {isOpen = false}
IRS.warbandBankRuntime = {isOpen = false}
function IRS:StyleButtonFeedback(button)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    highlight:SetColorTexture(0.86, 0.71, 0.36, 0.12)
    highlight:SetBlendMode("ADD")
end
function IRS:GetPeriodKeys()
    local now = ServerNow()

    -- Use one local-calendar basis for day and month ledgers.
    local year = tonumber(date("%Y", now))
    local month = tonumber(date("%m", now))
    local day = tonumber(date("%d", now))

    local dayKey = string.format("%04d-%02d-%02d", year, month, day)
    local monthKey = string.format("%04d-%02d", year, month)

    local weekStart
    if C_DateAndTime and C_DateAndTime.GetWeeklyResetStartTime then
        local ok, value = pcall(C_DateAndTime.GetWeeklyResetStartTime)
        if ok and type(value) == "number" and value > 0 then weekStart = value end
    end
    if not weekStart and C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local ok, untilReset = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
        if ok and type(untilReset) == "number" and untilReset >= 0 then
            weekStart = math.floor(now + untilReset - (7 * 86400))
        end
    end
    weekStart = weekStart or math.floor(now / (7 * 86400)) * (7 * 86400)
    local weekKey = tostring(math.floor(weekStart))

    return dayKey, weekKey, monthKey
end


function IRS:GetCurrentGuildKey()
    if not IsInGuild or not IsInGuild() then return nil end
    local name, _, _, realm = GetGuildInfo("player")
    if not name or name == "" then return nil end
    -- Club IDs identify a guild across realms and survive guild renames.
    local ok, id
    if C_Club and C_Club.GetGuildClubId then ok, id = pcall(C_Club.GetGuildClubId) end
    if not ok or id == nil or id == "" or id == 0 then return nil end
    return "guild:" .. tostring(id), name, realm, tostring(id)
end

-- Old realm keys are adopted only on a character whose live guild ID proves the alias.
function IRS:RegisterCurrentGuildBank()
    if not self.db then self:EnsureDB() end
    local key, name, realm, id = self:GetCurrentGuildKey()
    if not key then return nil end
    local db = self.db
    local playerRealm = GetRealmName()
    for _, knownRealm in ipairs({playerRealm, realm}) do
        if knownRealm and knownRealm ~= "" then
            local oldKey = name .. "@" .. knownRealm
            local previousAlias = db.guildBankAliases[oldKey]
            -- Another guild with the same name must retain its own identity/settings.
            if not previousAlias or previousAlias == key then
                db.guildBankAliases[oldKey] = key
                MergeGuildBank(db, oldKey, key)
            end
        end
    end
    local record = db.guildBanks[key] or {}
    db.guildBanks[key] = record
    record.key, record.name, record.guildClubId = key, name, id
    record.realm = realm or record.realm
    record.realms = record.realms or {}
    if playerRealm then record.realms[playerRealm] = true end
    if realm then record.realms[realm] = true end
    self:NormalizeGuildBanks()
    return key, record
end

-- Reads guild-bank money from BOTH APIs currently available on Retail.
--
-- Why both?
--   C_Bank.FetchDepositedMoney(Enum.BankType.Guild) is the modern Bank API.
--   GetGuildBankMoney() is the older guild-bank-frame API.
--
-- In practice one can briefly report 0 while the other already has the live
-- balance. IRS therefore compares both rather than accepting the first 0 it sees.
local function FetchGuildBankGold()
    local legacyAmount
    local modernAmount

    if GetGuildBankMoney then
        local ok, value = pcall(GetGuildBankMoney)
        if ok and type(value) == "number" and value >= 0 then
            legacyAmount = value
        end
    end

    if C_Bank
        and C_Bank.FetchDepositedMoney
        and Enum
        and Enum.BankType
        and Enum.BankType.Guild ~= nil then

        local ok, value = pcall(
            C_Bank.FetchDepositedMoney,
            Enum.BankType.Guild
        )

        if ok and type(value) == "number" and value >= 0 then
            modernAmount = value
        end
    end

    -- GetGuildBankMoney is tied directly to the guild-bank frame and is the
    -- preferred live value while the bank is open.
    if legacyAmount and legacyAmount > 0 then
        return legacyAmount
    end

    if modernAmount and modernAmount > 0 then
        return modernAmount
    end

    -- The caller accepts zero only after the bank money update confirms it.
    if legacyAmount ~= nil then
        return legacyAmount
    end

    if modernAmount ~= nil then
        return modernAmount
    end

    return nil
end

function IRS:ScanGuildBankGold(confirmedUpdate)
    local runtime = self.guildBankRuntime
    if not runtime.isOpen then return end
    local key, record = self:RegisterCurrentGuildBank()
    if not key then return end
    local amount = FetchGuildBankGold()
    if amount == nil then return end
    -- Opening can briefly report zero before the bank's money update arrives.
    if amount == 0 and not runtime.hasMoneyUpdate then return end
    -- Match only observations from this bank visit, never a stale saved balance.
    local previous = runtime.key == key and runtime.balance or nil
    runtime.key, runtime.balance = key, amount
    record.money = amount
    record.lastSeen = ServerNow()
    if confirmedUpdate and previous ~= nil and previous ~= amount then
        self:ObserveInternalStorageDelta("guild", key, amount - previous)
    end
end

function IRS:FormatMoney(copper, compact)
    copper = math.floor(tonumber(copper) or 0)
    local negative = copper < 0
    local absolute = math.abs(copper)
    local gold = math.floor(absolute / 10000)
    local silver = math.floor((absolute % 10000) / 100)
    local copperOnly = absolute % 100
    local sign = negative and "-" or ""

    local formattedGold = IRS:FormatCount(gold)
    if compact then
        return string.format("%s%sg %02ds %02dc", sign, formattedGold, silver, copperOnly)
    end
    return string.format("%s%s g %02d s %02d c", sign, formattedGold, silver, copperOnly)
end

-- Adds normal large-number formatting to a simple count.
function IRS:FormatCount(number)
    number = math.floor(tonumber(number) or 0)
    local digits = string.format("%.0f", math.abs(number))
    local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (number < 0 and "-" or "") .. grouped
end
