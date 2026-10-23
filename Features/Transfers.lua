--[[
IRS - Internal Transfers
Matches movement between owned storage so transfers are not recorded as income or spending.
]]

local _, IRS = ...

local COLORS = {
    panel = {0.190, 0.145, 0.098, 0.980},
    panelAlt = {0.225, 0.170, 0.112, 0.985},
    border = {0.46, 0.36, 0.22, 1},
    goldSoft = {0.79, 0.66, 0.39, 1},
    text = {0.88, 0.84, 0.75, 1},
    muted = {0.68, 0.62, 0.51, 1},
}

local MATCH_WINDOW = 1.25
local STORAGE_EXPIRY = 2.00
-- Blizzard can occasionally deliver GUILDBANK_UPDATE_MONEY after the normal
-- defer window. Keep ONLY wallet changes that were deferred while an owned
-- Guild Bank was open for a short grace period. If the matching bank delta
-- arrives, IRS reverses the already-filed ledger entry for both the account and
-- the character, then records the movement as an internal transfer.
local LATE_MATCH_WINDOW = 10.00

IRS.internalTransferRuntime = IRS.internalTransferRuntime or {
    pendingWallet = {},
    pendingStorage = {},
    recentRecordedWallet = {},
    nextWalletId = 0,
    guildActions = {},
    guildActionReceipts = {},
}
local runtime = IRS.internalTransferRuntime
runtime.pendingWallet = runtime.pendingWallet or {}
runtime.pendingStorage = runtime.pendingStorage or {}
runtime.recentRecordedWallet = runtime.recentRecordedWallet or {}

local function Now()
    if GetServerTime then return GetServerTime() end
    return time()
end

local function MakeText(parent, style, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetFont(
        STANDARD_TEXT_FONT,
        IRS:GetFontSize("main", style),
        ""
    )
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("MIDDLE")
    if color then
        IRS:SetLayoutColor(fs, "SetTextColor", color[1], color[2], color[3], color[4] or 1)
    end
    IRS:RegisterFontString("main", style, fs, STANDARD_TEXT_FONT, "")
    return fs
end

local function MakePanel(parent, color)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 2,
    })
    local c = color or COLORS.panelAlt
    IRS:SetLayoutColor(panel, "SetBackdropColor", c[1], c[2], c[3], c[4] or 1)
    IRS:SetLayoutColor(panel, "SetBackdropBorderColor", unpack(COLORS.border))
    return panel
end

function IRS:EnsureInternalTransferDB()
    if not IRS.db then IRS:EnsureDB() end

    IRS.db.internalTransfers = IRS.db.internalTransfers or {}
    local db = IRS.db.internalTransfers
    db.ownedGuildBanks = db.ownedGuildBanks or {}
    db.days = db.days or {}
    db.totalMoved = math.max(0, tonumber(db.totalMoved) or 0)

    return db
end

function IRS:IsInternalGuildBank(guildKey)
    if not guildKey then return false end
    local db = IRS:EnsureInternalTransferDB()
    local stored = db.ownedGuildBanks[guildKey]

    return stored == true
end

function IRS:SetInternalGuildBank(guildKey, enabled)
    if not guildKey then return end
    local db = IRS:EnsureInternalTransferDB()
    db.ownedGuildBanks[guildKey] = enabled == true

    if IRS.RefreshUI then
        IRS:RefreshUI()
    elseif IRS.RefreshInternalTransferSettingsSection then
        IRS:RefreshInternalTransferSettingsSection()
    end
end

function IRS:RecordInternalTransfer(amount)
    local db = IRS:EnsureInternalTransferDB()
    local dayKey = IRS:GetPeriodKeys()
    db.days[dayKey] = (db.days[dayKey] or 0) + amount
    db.totalMoved = db.totalMoved + amount
end

function IRS:GetInternalTransferSummary()
    local db = IRS:EnsureInternalTransferDB()
    local dayKey = select(1, IRS:GetPeriodKeys())
    return {
        today = tonumber(db.days[dayKey]) or 0,
        total = tonumber(db.totalMoved) or 0,
    }
end

local function PruneRuntime()
    local now = Now()

    for _, queue in ipairs({runtime.guildActions, runtime.guildActionReceipts}) do
        for i = #queue, 1, -1 do
            if now - queue[i].at > queue[i].expiry then table.remove(queue, i) end
        end
    end

    for i = #runtime.pendingStorage, 1, -1 do
        local item = runtime.pendingStorage[i]
        if now - (tonumber(item.at) or 0) > STORAGE_EXPIRY
            or (tonumber(item.amount) or 0) == 0 then
            table.remove(runtime.pendingStorage, i)
        end
    end

    for i = #runtime.pendingWallet, 1, -1 do
        local item = runtime.pendingWallet[i]
        if (tonumber(item.amount) or 0) == 0 then
            table.remove(runtime.pendingWallet, i)
        end
    end

    for i = #runtime.recentRecordedWallet, 1, -1 do
        local item = runtime.recentRecordedWallet[i]
        if (tonumber(item.amount) or 0) == 0
            or now - (tonumber(item.recordedAt) or 0) > LATE_MATCH_WINDOW then
            table.remove(runtime.recentRecordedWallet, i)
        end
    end
end

-- A confirmed wallet change can identify the player's requested guild transfer
-- even when the initial bank balance is unavailable. Do not treat a request alone
-- as movement, and consume its later bank update only once.
function IRS:TrackGuildBankAction(walletAmount)
    PruneRuntime()
    if not IRS.guildBankRuntime.isOpen then return end
    if type(walletAmount) ~= "number" or walletAmount ~= walletAmount
        or math.abs(walletAmount) == math.huge or walletAmount == 0 then return end
    local key = IRS:RegisterCurrentGuildBank()
    if not key or not IRS:IsInternalGuildBank(key) or IRS.walletBalance == nil then return end
    table.insert(runtime.guildActions, {
        storageType = "guild", storageKey = key,
        amount = math.floor(walletAmount), walletBefore = IRS.walletBalance,
        characterKey = IRS:CharacterKey(), at = Now(), expiry = 3,
    })
end
local function ConsumeGuildActions(walletAmount, characterKey, walletBefore, observedBankKey)
    PruneRuntime()
    local remaining = walletAmount
    for i = #runtime.guildActions, 1, -1 do
        local action = runtime.guildActions[i]
        local sameBank = not observedBankKey or action.storageKey == observedBankKey
        if sameBank and action.characterKey == characterKey
            and IRS:IsInternalGuildBank(action.storageKey)
            and (observedBankKey or action.walletBefore == walletBefore)
            and remaining * action.amount > 0 and math.abs(remaining) >= math.abs(action.amount) then
            remaining = remaining - action.amount
            table.remove(runtime.guildActions, i)
            if not observedBankKey then
                IRS:RecordInternalTransfer(math.abs(action.amount))
                table.insert(runtime.guildActionReceipts, {
                    storageType = "guild", storageKey = action.storageKey,
                    amount = -action.amount, at = Now(), expiry = 30,
                })
            end
        end
    end
    return remaining
end
local function ConsumeGuildReceipts(storageKey, amount)
    local remaining = amount
    for i = #runtime.guildActionReceipts, 1, -1 do
        local receipt = runtime.guildActionReceipts[i]
        if receipt.storageKey == storageKey and remaining * receipt.amount > 0 then
            local matched = math.min(math.abs(remaining), math.abs(receipt.amount))
            local signed = remaining < 0 and -matched or matched
            remaining, receipt.amount = remaining - signed, receipt.amount - signed
            if receipt.amount == 0 then table.remove(runtime.guildActionReceipts, i) end
        end
    end
    return remaining
end
function IRS:InstallGuildTransferHooks()
    if not hooksecurefunc then return end
    self._guildTransferHooks = self._guildTransferHooks or {}
    local hooks = self._guildTransferHooks
    for _, option in ipairs({{"DepositGuildBankMoney", -1}, {"WithdrawGuildBankMoney", 1}}) do
        local name, sign = option[1], option[2]
        if type(_G[name]) == "function" and not hooks[name] then
            hooksecurefunc(name, function(amount)
                if type(amount) == "number" then IRS:TrackGuildBankAction(amount * sign) end
            end)
            hooks[name] = true
        end
    end
    for _, option in ipairs({{"DepositMoney", -1}, {"WithdrawMoney", 1}}) do
        local name, sign = option[1], option[2]
        if C_Bank and type(C_Bank[name]) == "function" and not hooks["C_Bank." .. name] then
            hooksecurefunc(C_Bank, name, function(bankType, amount)
                if Enum and Enum.BankType and bankType == Enum.BankType.Guild and type(amount) == "number" then
                    IRS:TrackGuildBankAction(amount * sign)
                end
            end)
            hooks["C_Bank." .. name] = true
        end
    end
end

local function ConsumeStorage(walletAmount, characterKey, expectedType, expectedKey)
    walletAmount = math.floor(tonumber(walletAmount) or 0)
    if walletAmount == 0 then return 0 end

    PruneRuntime()
    local remaining = walletAmount

    for i = #runtime.pendingStorage, 1, -1 do
        local storage = runtime.pendingStorage[i]
        local storageAmount = math.floor(tonumber(storage.amount) or 0)

        if (not expectedType or (expectedType == storage.storageType and expectedKey == storage.storageKey))
            and remaining ~= 0
            and storageAmount ~= 0
            and ((remaining < 0 and storageAmount > 0)
                or (remaining > 0 and storageAmount < 0)) then

            local matched = math.min(
                math.abs(remaining),
                math.abs(storageAmount)
            )

            IRS:RecordInternalTransfer(matched)
            if storage.storageType == "guild" then
                ConsumeGuildActions(remaining < 0 and -matched or matched, characterKey, nil, storage.storageKey)
            end

            if remaining < 0 then
                remaining = remaining + matched
                storage.amount = storageAmount - matched
            else
                remaining = remaining - matched
                storage.amount = storageAmount + matched
            end

            if storage.amount == 0 then
                table.remove(runtime.pendingStorage, i)
            end
        end
    end

    return remaining
end

-- If a deferred Guild Bank wallet change timed out and was already filed as
-- income/loss, a later bank event can still prove it was an internal transfer.
-- Reverse exactly the matched piece through RecordEarnings so ACCOUNT and
-- CHARACTER ledgers stay paired.
local function ConsumeLateRecordedStorage(storage)
    if not storage or (tonumber(storage.amount) or 0) == 0 then return end

    PruneRuntime()

    for i = #runtime.recentRecordedWallet, 1, -1 do
        local wallet = runtime.recentRecordedWallet[i]
        local walletAmount = math.floor(tonumber(wallet.amount) or 0)
        local storageAmount = math.floor(tonumber(storage.amount) or 0)

        local sameStorage =
            wallet.expectedStorageType == storage.storageType
            and wallet.expectedStorageKey == storage.storageKey

        if sameStorage
            and walletAmount ~= 0
            and storageAmount ~= 0
            and ((walletAmount < 0 and storageAmount > 0)
                or (walletAmount > 0 and storageAmount < 0)) then

            local matched = math.min(
                math.abs(walletAmount),
                math.abs(storageAmount)
            )

            -- The wallet entry was already written to both ledgers. Undo the
            -- matched transfer amount before logging it as internal movement.
            local correction = walletAmount < 0 and matched or -matched
            IRS:RecordEarnings(correction, wallet.characterKey, wallet.periodKeys)
            IRS:RecordInternalTransfer(matched)
            if storage.storageType == "guild" then
                ConsumeGuildActions(walletAmount < 0 and -matched or matched, wallet.characterKey, nil, storage.storageKey)
            end

            if walletAmount < 0 then
                wallet.amount = walletAmount + matched
                storage.amount = storageAmount - matched
            else
                wallet.amount = walletAmount - matched
                storage.amount = storageAmount + matched
            end

            if wallet.amount == 0 then
                table.remove(runtime.recentRecordedWallet, i)
            end
        end
    end
end

local function CurrentInternalGuildOpen()
    if not IRS.guildBankRuntime
        or IRS.guildBankRuntime.isOpen ~= true then
        return nil
    end

    local guildKey = IRS:GetCurrentGuildKey()
    if guildKey and IRS:IsInternalGuildBank(guildKey) then
        return guildKey
    end

    return nil
end

function IRS:FinalizePendingInternalWallet(walletId)
    PruneRuntime()

    local index, entry
    for i, pending in ipairs(runtime.pendingWallet) do
        if pending.id == walletId then
            index, entry = i, pending
            break
        end
    end

    if not entry then return end
    table.remove(runtime.pendingWallet, index)

    local remaining = ConsumeStorage(
        entry.amount,
        entry.characterKey,
        entry.expectedStorageType,
        entry.expectedStorageKey
    )
    if remaining ~= 0 then
        IRS:RecordEarnings(remaining, entry.characterKey, entry.periodKeys)

        -- Do not forget this immediately. The owned Guild Bank money event can
        -- arrive after MATCH_WINDOW on some clients. A matching late event will
        -- reverse this exact ledger amount for both account and character.
        table.insert(runtime.recentRecordedWallet, {
            amount = remaining,
            characterKey = entry.characterKey,
            expectedStorageType = entry.expectedStorageType,
            expectedStorageKey = entry.expectedStorageKey,
            recordedAt = Now(),
            periodKeys = entry.periodKeys,
        })
    end

    if IRS.RefreshUI then IRS:RefreshUI() end
end

local function QueueWallet(
    walletAmount,
    characterKey,
    storageKey,
    storageType
)
    storageType = storageType or "guild"
    runtime.nextWalletId = (tonumber(runtime.nextWalletId) or 0) + 1
    local id = runtime.nextWalletId

    table.insert(runtime.pendingWallet, {
        id = id,
        amount = walletAmount,
        characterKey = characterKey,
        expectedStorageType = storageType,
        expectedStorageKey = storageKey,
        at = Now(),
        periodKeys = {IRS:GetPeriodKeys()},
    })

    C_Timer.After(MATCH_WINDOW, function()
        if IRS.db then
            IRS:FinalizePendingInternalWallet(id)
        end
    end)
end

function IRS:ObserveInternalStorageDelta(storageType, storageKey, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 then return false end

    if storageType == "guild"
        and not IRS:IsInternalGuildBank(storageKey) then
        return false
    end

    if storageType ~= "warband" and storageType ~= "guild" then
        return false
    end

    PruneRuntime()
    if storageType == "guild" then
        amount = ConsumeGuildReceipts(storageKey, amount)
        if amount == 0 then return true end
    end

    local storage = {
        storageType = storageType,
        storageKey = storageKey,
        amount = amount,
        at = Now(),
    }

    -- Bank event arrived after PLAYER_MONEY: consume deferred wallet changes.
    for i = #runtime.pendingWallet, 1, -1 do
        local wallet = runtime.pendingWallet[i]
        local walletAmount = math.floor(tonumber(wallet.amount) or 0)
        local storageAmount = math.floor(tonumber(storage.amount) or 0)

        if wallet.expectedStorageType == storage.storageType
            and wallet.expectedStorageKey == storage.storageKey
            and walletAmount ~= 0
            and storageAmount ~= 0
            and ((walletAmount < 0 and storageAmount > 0)
                or (walletAmount > 0 and storageAmount < 0)) then

            local matched = math.min(
                math.abs(walletAmount),
                math.abs(storageAmount)
            )

            IRS:RecordInternalTransfer(matched)
            if storage.storageType == "guild" then
                ConsumeGuildActions(walletAmount < 0 and -matched or matched, wallet.characterKey, nil, storage.storageKey)
            end

            if walletAmount < 0 then
                wallet.amount = walletAmount + matched
                storage.amount = storageAmount - matched
            else
                wallet.amount = walletAmount - matched
                storage.amount = storageAmount + matched
            end

            if wallet.amount == 0 then
                table.remove(runtime.pendingWallet, i)
            end
        end
    end

    if storage.amount ~= 0 then
        ConsumeLateRecordedStorage(storage)
    end

    if storage.amount ~= 0 then
        table.insert(runtime.pendingStorage, storage)
    end

    if IRS.RefreshInternalTransferSettingsSection then
        IRS:RefreshInternalTransferSettingsSection()
    end

    return true
end

function IRS:FilterInternalWalletChange(
    walletDelta,
    characterKey,
    previousWallet
)
    walletDelta = math.floor(tonumber(walletDelta) or 0)
    if walletDelta == 0 then return 0 end

    IRS:EnsureInternalTransferDB()
    PruneRuntime()

    local remaining = walletDelta

    -- If a bank event arrived first, consume its pending balance change now.
    remaining = ConsumeStorage(
        remaining,
        characterKey
    )

    remaining = ConsumeGuildActions(remaining, characterKey, previousWallet)

    -- Guild Bank money often updates a fraction after PLAYER_MONEY. Defer the
    -- unmatched wallet change only while an OWNED Guild Bank is actually open.
    local openGuildKey = remaining ~= 0 and CurrentInternalGuildOpen() or nil
    if remaining ~= 0 and openGuildKey then
        QueueWallet(
            remaining,
            characterKey,
            openGuildKey
        )
        return 0
    end

    -- The Warband balance can lag PLAYER_MONEY too. Defer while a bank is open;
    -- the follow-up Warband rescans will supply the matching balance change.
    if remaining ~= 0
        and IRS.warbandBankRuntime
        and IRS.warbandBankRuntime.isOpen == true then
        QueueWallet(
            remaining,
            characterKey,
            nil,
            "warband"
        )
        return 0
    end

    return remaining
end

-- ============================================================================
-- SETTINGS UI
-- ============================================================================
local settingsUI

function IRS:BuildInternalTransferSettingsSection(parent)
    if settingsUI then return settingsUI.frame end
    IRS:EnsureInternalTransferDB()

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()

    local title = MakeText(frame, "section", COLORS.goldSoft, "LEFT")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("INTERNAL TRANSFERS")

    local desc = MakeText(frame, "helper", COLORS.muted, "LEFT")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    desc:SetPoint("RIGHT", -16, 0)
    desc:SetText(
        "Money moved between your own storage locations is ignored by the IRS income/loss ledger."
    )

    local info = MakePanel(frame, COLORS.panelAlt)
    info:SetPoint("TOPLEFT", 14, -68)
    info:SetPoint("TOPRIGHT", -14, -68)
    info:SetHeight(92)

    local infoTitle = MakeText(info, "label", COLORS.goldSoft, "LEFT")
    infoTitle:SetPoint("TOPLEFT", 12, -11)
    infoTitle:SetText("ALWAYS INTERNAL")

    local infoText = MakeText(info, "body", COLORS.text, "LEFT")
    infoText:SetPoint("TOPLEFT", 12, -36)
    infoText:SetPoint("RIGHT", -12, 0)
    infoText:SetText(
        "Character wallets and Warband Bank transfers are always excluded from net income. Mark your own Guild Banks below to extend that protection to savings transfers."
    )

    local summary = MakeText(info, "helper", COLORS.muted, "LEFT")
    summary:SetPoint("BOTTOMLEFT", 12, 10)

    local guildPanel = MakePanel(frame, COLORS.panelAlt)
    guildPanel:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -12)
    guildPanel:SetPoint("BOTTOMRIGHT", -14, 14)

    local guildTitle = MakeText(guildPanel, "label", COLORS.goldSoft, "LEFT")
    guildTitle:SetPoint("TOPLEFT", 12, -11)
    guildTitle:SetText("PERSONAL GUILD BANKS")

    local guildDesc = MakeText(guildPanel, "helper", COLORS.muted, "LEFT")
    guildDesc:SetPoint("TOPLEFT", 12, -34)
    guildDesc:SetPoint("RIGHT", -12, 0)
    guildDesc:SetText(
        "Guilds are registered as you log in to each character. Check a bank to tag it as personal and exclude its transfers from earnings. Open each bank to refresh its balance."
    )

    local scroll = CreateFrame(
        "ScrollFrame",
        "IRSLiteInternalTransferScroll",
        guildPanel,
        "UIPanelScrollFrameTemplate"
    )
    scroll:SetPoint("TOPLEFT", guildDesc, "BOTTOMLEFT", -2, -12)
    scroll:SetPoint("BOTTOMRIGHT", -28, 10)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(570, 1)
    scroll:SetScrollChild(child)

    local empty = MakeText(child, "body", COLORS.muted, "CENTER")
    empty:SetPoint("TOPLEFT", 8, -18)
    empty:SetWidth(550)
    empty:SetText(
        "No Guild Banks are known yet. Log in to a character in a guild and IRS will add it here."
    )

    settingsUI = {
        frame = frame,
        summary = summary,
        scroll = scroll,
        child = child,
        empty = empty,
        rows = {},
    }

    return frame
end

local function EnsureGuildSettingRow(index)
    local ui = settingsUI
    if ui.rows[index] then return ui.rows[index] end

    local row = MakePanel(ui.child, COLORS.panel)
    row:SetHeight(54)

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(28, 28)
    row.check:SetPoint("LEFT", 8, 0)

    row.name = MakeText(row, "body", COLORS.text, "LEFT")
    row.name:SetPoint("TOPLEFT", 45, -8)
    row.name:SetPoint("RIGHT", -85, 0)

    row.personal = MakeText(row, "helper", COLORS.goldSoft, "RIGHT")
    row.personal:SetPoint("TOPRIGHT", -12, -8)

    row.meta = MakeText(row, "helper", COLORS.muted, "LEFT")
    row.meta:SetPoint("TOPLEFT", 45, -29)
    row.meta:SetPoint("RIGHT", -12, 0)

    row.check:SetScript("OnClick", function(self)
        if row.guildKey then
            IRS:SetInternalGuildBank(row.guildKey, self:GetChecked())
        end
    end)

    ui.rows[index] = row
    return row
end

function IRS:RefreshInternalTransferSettingsSection()
    if not settingsUI or not IRS.db then return end
    local ui = settingsUI
    local rows = IRS:GetSortedGuildBanks()
    local summary = IRS:GetInternalTransferSummary()

    ui.summary:SetText(string.format(
        "Internal transfers ignored today: %s   |   Since tracking: %s",
        IRS:FormatMoney(summary.today, true),
        IRS:FormatMoney(summary.total, true)
    ))

    ui.empty:SetShown(#rows == 0)
    local width = math.max(520, (ui.scroll:GetWidth() or 560) - 5)

    for i, entry in ipairs(rows) do
        local row = EnsureGuildSettingRow(i)
        local record = entry.record or {}
        row.guildKey = entry.key
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((i - 1) * 58))
        row:SetWidth(width)
        row.check:SetChecked(IRS:IsInternalGuildBank(entry.key))
        row.personal:SetText(IRS:IsInternalGuildBank(entry.key) and "Personal" or "Shared")
        row.name:SetText(record.name or entry.key or "Guild Bank")

        local parts = {}
        local realms = {}
        for realm in pairs(record.realms or {}) do realms[#realms + 1] = realm end
        table.sort(realms)
        if #realms > 0 then table.insert(parts, table.concat(realms, ", "))
        elseif record.realm then table.insert(parts, record.realm) end
        if record.money ~= nil then
            table.insert(parts, IRS:FormatMoney(record.money, true))
        else
            table.insert(parts, "balance not cached")
        end
        row.meta:SetText(table.concat(parts, "  |  "))
        row:Show()
    end

    for i = #rows + 1, #ui.rows do
        ui.rows[i]:Hide()
    end

    ui.child:SetHeight(math.max(1, #rows * 58))
end
