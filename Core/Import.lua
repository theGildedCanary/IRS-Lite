-- Copy the full addon's loaded SavedVariables into Lite's smaller ledger schema.
-- OptionalDeps loads IRS first when enabled; no IRS code or saved records are changed.
local _, IRS = ...
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end
local function Amount(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function Number(value)
    if value == nil then return 0 end
    assert(Amount(value), "IRS contains an invalid earnings amount.")
    return value
end
local function Periods(source, buckets)
    local result = {}
    if source == nil then return result end
    assert(type(source) == "table", "IRS period history is invalid.")
    for key, value in pairs(source) do
        assert(type(key) == "string", "IRS contains an invalid period key.")
        result[key] = Number(buckets and type(value) == "table" and value.earned or value)
    end
    return result
end
local function ValidateStorage(guildBanks, transfers)
    assert(type(guildBanks) == "table" and type(transfers) == "table", "IRS storage records are invalid.")
    for key, bank in pairs(guildBanks) do
        assert(type(key) == "string" and type(bank) == "table", "IRS guild-bank records are invalid.")
        assert(bank.money == nil or Amount(bank.money), "IRS bank balance is invalid.")
        assert(bank.realms == nil or type(bank.realms) == "table", "IRS bank realms are invalid.")
        for realm, included in pairs(bank.realms or {}) do
            assert(type(realm) == "string" and type(included) == "boolean", "IRS bank realms are invalid.")
        end
        for _, field in ipairs({"name", "realm"}) do
            assert(bank[field] == nil or type(bank[field]) == "string", "IRS bank identity is invalid.")
        end
    end
    assert(type(transfers.ownedGuildBanks or {}) == "table", "IRS bank settings are invalid.")
    for key, enabled in pairs(transfers.ownedGuildBanks or {}) do
        assert(type(key) == "string" and type(enabled) == "boolean", "IRS bank ownership is invalid.")
    end
    transfers.days = Periods(transfers.days)
    transfers.totalMoved = Number(transfers.totalMoved)
end
local function Build(source)
    assert(type(source.tracking) == "table", "IRS has no recorded earnings history to import.")
    local history = source.tracking
    assert(history.lastEarnedAt == nil or Amount(history.lastEarnedAt), "IRS earnings timestamp is invalid.")
    local snapshot = {
        tracking = {
            days = Periods(history.days, true),
            weeks = Periods(history.weeks, true),
            months = Periods(history.months, true),
            total = Number(history.totalEarned),
            overallAdjustment = Number(history.overallIncomeAdjustment),
            startedAt = history.startedAt,
            lastEarnedAt = history.lastEarnedAt,
        },
        characters = {},
        guildBanks = Copy(source.guildBanks or {}),
        internalTransfers = Copy(source.internalTransfers or {}),
        settings = {},
        characterCount = 0,
        dayCount = 0,
    }
    for key, record in pairs(source.characters or {}) do
        assert(type(record) == "table", "IRS contains an invalid character record.")
        local periods = record.periodEarnings or {}
        snapshot.characters[key] = {
            days = Periods(periods.days), weeks = Periods(periods.weeks), months = Periods(periods.months),
            total = Number(record.earnedSinceTracking),
        }
        snapshot.characterCount = snapshot.characterCount + 1
    end
    for _ in pairs(snapshot.tracking.days) do snapshot.dayCount = snapshot.dayCount + 1 end
    -- Import only settings and storage data that Lite actually uses.
    local settings = source.settings or {}
    snapshot.settings.showMinimapButton = settings.showMinimapButton ~= false
    snapshot.settings.fontFace = settings.fontFace or "default"
    snapshot.settings.layoutStyle = settings.layoutStyle == "elvui" and "elvui" or "default"
    snapshot.settings.fontSizes = {main = {}}
    for key, default in pairs(IRS.FONT_STYLE_DEFAULTS.main) do
        local value = settings.fontSizes and settings.fontSizes.main and settings.fontSizes.main[key]
        snapshot.settings.fontSizes.main[key] = Amount(value) and math.max(8, math.min(IRS.FONT_SIZE_LIMITS[key], value)) or default
    end
    local transfers = snapshot.internalTransfers
    snapshot.internalTransfers = {
        ownedGuildBanks = transfers.ownedGuildBanks or {},
        days = transfers.days or {},
        totalMoved = transfers.totalMoved or 0,
    }
    ValidateStorage(snapshot.guildBanks, snapshot.internalTransfers)
    return snapshot
end
function IRS:GetIRSImportPreview()
    if type(IncomeRecordsSystemDB) ~= "table" then
        return nil, "Enable Income Records System alongside Lite in the AddOns list, then reload. After importing, you can disable the full addon."
    end
    local source = IncomeRecordsSystemDB
    if type(source.tracking) ~= "table"
        or (source.characters ~= nil and type(source.characters) ~= "table")
        or (source.tracking.days ~= nil and type(source.tracking.days) ~= "table")
        or not Amount(source.tracking.totalEarned or 0)
        or not Amount(source.tracking.overallIncomeAdjustment or 0) then
        return nil, "IRS records could not be read. No Lite data was changed."
    end
    local characters, days = 0, 0
    for _ in pairs(source.characters or {}) do characters = characters + 1 end
    for _ in pairs(source.tracking.days or {}) do days = days + 1 end
    return {characterCount = characters, dayCount = days, tracking = {
        total = source.tracking.totalEarned or 0,
        overallAdjustment = source.tracking.overallIncomeAdjustment or 0,
    }}
end
function IRS:ImportIRSFiles()
    -- A pending money event must settle before replacing the history it belongs to.
    if #self.internalTransferRuntime.pendingWallet > 0 then
        return false, "A bank transfer is still settling. Wait a moment and try again."
    end
    local preview, reason = self:GetIRSImportPreview()
    if not preview then return false, reason end
    local ok, snapshot = pcall(Build, IncomeRecordsSystemDB)
    if not ok then return false, "IRS records could not be read. No Lite data was changed." end
    self.db.tracking = snapshot.tracking
    self.db.characters = snapshot.characters
    self.db.guildBanks = snapshot.guildBanks
    self.db.internalTransfers = snapshot.internalTransfers
    for key, value in pairs(snapshot.settings) do self.db.settings[key] = value end
    self.db.irsImport = {at = GetServerTime(), characters = snapshot.characterCount, days = snapshot.dayCount}
    -- Corrections for the previous Lite history must never touch the imported copy.
    self.internalTransferRuntime.recentRecordedWallet = {}
    self.internalTransferRuntime.pendingStorage = {}
    self:RegisterCurrentGuildBank()
    self:NormalizeGuildBanks()
    self:ApplySavedFontSizes()
    self:ApplySavedLayoutStyle()
    self:RefreshMinimapButton()
    self:RefreshUI()
    return true, string.format("Imported %d characters and %d days of IRS earnings. Lite now saves its own copy.", snapshot.characterCount, snapshot.dayCount)
end
