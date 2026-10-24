-- Account-wide appearance for IRS-owned regions. Keep original colors so
-- switching back restores the default exactly, including hover/selected states.
local _, IRS = ...
IRS.LAYOUT_STYLE_OPTIONS = {
    { key = "default", label = "IRS Default" },
    { key = "elvui", label = "ElvUI Inspired" },
    { key = "forever", label = "WoW Forever" },
}

local function ColorKey(r, g, b)
    return string.format("%.3f/%.3f/%.3f", r, g, b)
end

local replacements = {}
local function Map(r, g, b, nr, ng, nb)
    replacements[ColorKey(r, g, b)] = {nr, ng, nb}
end
-- Panel fills, borders, selected rows, and dividers used by IRS modules.
Map(0.165, 0.125, 0.085, 0.025, 0.030, 0.035)
Map(0.190, 0.145, 0.098, 0.035, 0.040, 0.045)
Map(0.225, 0.170, 0.112, 0.055, 0.060, 0.065)
Map(0.52, 0.39, 0.22, 0.10, 0.11, 0.12)
Map(0.36, 0.28, 0.18, 0.14, 0.15, 0.16)
Map(0.46, 0.36, 0.22, 0.14, 0.15, 0.16)
Map(0.27, 0.23, 0.17, 0.16, 0.17, 0.18)
Map(0.88, 0.84, 0.75, 0.90, 0.90, 0.90)
Map(0.68, 0.62, 0.51, 0.65, 0.67, 0.69)

-- Match Alt Tracking Assistant's Forever palette. Alerts keep their IRS colors.
local forever = {}
local function Forever(r, g, b, nr, ng, nb)
    forever[ColorKey(r, g, b)] = {nr, ng, nb}
end
Forever(0.165, 0.125, 0.085, 0.024, 0.204, 0.251)
Forever(0.190, 0.145, 0.098, 0.024, 0.17, 0.21)
Forever(0.225, 0.170, 0.112, 0.024, 0.17, 0.21)
Forever(0.52, 0.39, 0.22, 0.737, 0.643, 0.486)
Forever(0.36, 0.28, 0.18, 0.208, 0.353, 0.380)
Forever(0.46, 0.36, 0.22, 0.549, 0.510, 0.408)
Forever(0.27, 0.23, 0.17, 0.208, 0.353, 0.380)
Forever(0.86, 0.71, 0.36, 0.816, 0.718, 0.537)
Forever(0.79, 0.66, 0.39, 0.816, 0.718, 0.537)
Forever(0.88, 0.84, 0.75, 0.933, 0.894, 0.808)
Forever(0.68, 0.62, 0.51, 0.718, 0.769, 0.741)
Forever(0.40, 0.63, 0.65, 0.816, 0.718, 0.537)

local regions = setmetatable({}, {__mode = "k"})

function IRS:GetLayoutStyle()
    local key = self.db and self.db.settings and self.db.settings.layoutStyle
    for _, option in ipairs(self.LAYOUT_STYLE_OPTIONS) do
        if option.key == key then return key end
    end
    return "default"
end

function IRS:GetLayoutStyleLabel()
    local selected = self:GetLayoutStyle()
    for _, option in ipairs(self.LAYOUT_STYLE_OPTIONS) do
        if option.key == selected then return option.label end
    end
end

local function Apply(region, method, color)
    local style = IRS:GetLayoutStyle()
    local palette = style == "forever" and forever or style == "elvui" and replacements
    local replacement = palette and palette[ColorKey(color[1], color[2], color[3])]
    local alpha = color[4]
    if replacement then
        -- Layered panels remain readable while letting the world show through.
        if style == "elvui" and method == "SetBackdropColor" and alpha > 0.80 then alpha = 0.72 end
        -- Table/card fills share one opacity; keep text, borders and artwork opaque.
        if style == "forever" and method == "SetBackdropColor"
            and (ColorKey(color[1], color[2], color[3]) == ColorKey(0.165, 0.125, 0.085)
                or ColorKey(color[1], color[2], color[3]) == ColorKey(0.190, 0.145, 0.098)
                or ColorKey(color[1], color[2], color[3]) == ColorKey(0.225, 0.170, 0.112)) then
            alpha = 0.75
        end
        region[method](region, replacement[1], replacement[2], replacement[3], alpha)
    else
        region[method](region, unpack(color))
    end
end

function IRS:SetLayoutColor(region, method, r, g, b, a)
    local color = {r, g, b, a or 1}
    if replacements[ColorKey(r, g, b)] or forever[ColorKey(r, g, b)] then
        regions[region] = regions[region] or {}
        regions[region][method] = color
    elseif regions[region] then
        -- A reused row may change from a themed color to an alert color.
        regions[region][method] = nil
    end
    Apply(region, method, color)
end

function IRS:ApplySavedLayoutStyle()
    for region, methods in pairs(regions) do
        for method, color in pairs(methods) do Apply(region, method, color) end
    end
    if self.RefreshLayoutArtwork then self:RefreshLayoutArtwork() end
    for button, refresh in pairs(self._layoutButtons or {}) do refresh(button) end
end

function IRS:SetLayoutStyle(key)
    local valid = false
    for _, option in ipairs(self.LAYOUT_STYLE_OPTIONS) do
        if option.key == key then valid = true; break end
    end
    if not valid then return false end
    self:EnsureDB()
    self.db.settings.layoutStyle = key
    self:ApplySavedLayoutStyle()
    if self.RefreshSettingsPage then self:RefreshSettingsPage() end
    return true
end

-- ATA's exact nine-slice artwork keeps corners at eight pixels at every size.
-- Native backdrops are suppressed only in Forever; their original setters and
-- saved colors continue to restore the other presets.
function IRS:StyleLayoutPanel(frame, onlyForever)
    if frame.roundedLayers then return end
    local coords = {0, 8 / 64, 56 / 64, 1}
    local layers = {}
    for _, kind in ipairs({"Fill", "Border"}) do
        local textures = {}
        for row = 1, 3 do
            for column = 1, 3 do
                local texture = frame:CreateTexture(nil, kind == "Fill" and "BACKGROUND" or "BORDER")
                texture:SetTexture("Interface\\AddOns\\IRS Lite\\Media\\ForeverRounded" .. kind .. ".tga")
                texture:SetTexCoord(coords[column], coords[column + 1], coords[row], coords[row + 1])
                if row ~= 2 and column ~= 2 then
                    local point = (row == 1 and "TOP" or "BOTTOM") .. (column == 1 and "LEFT" or "RIGHT")
                    texture:SetSize(8, 8)
                    texture:SetPoint(point, frame, point, 0, 0)
                elseif row ~= 2 then
                    local side = row == 1 and "TOP" or "BOTTOM"
                    texture:SetHeight(8)
                    texture:SetPoint(side .. "LEFT", frame, side .. "LEFT", 8, 0)
                    texture:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", -8, 0)
                elseif column ~= 2 then
                    local side = column == 1 and "LEFT" or "RIGHT"
                    texture:SetWidth(8)
                    texture:SetPoint("TOP" .. side, frame, "TOP" .. side, 0, -8)
                    texture:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, 0, 8)
                else
                    texture:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
                    texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
                end
                texture:Hide()
                textures[#textures + 1] = texture
            end
        end
        layers[kind] = textures
        local method = kind == "Fill" and "SetBackdropColor" or "SetBackdropBorderColor"
        local original = frame[method]
        frame[method] = function(panel, r, g, b, a)
            local active = IRS:GetLayoutStyle() == "forever"
            if active or onlyForever then original(panel, 0, 0, 0, 0)
            else original(panel, r, g, b, a) end
            for _, texture in ipairs(textures) do
                texture:SetVertexColor(r, g, b, a or 1)
                texture:SetShown(active)
            end
        end
    end
    frame.roundedLayers = layers
end

function IRS:AddLayoutSectionBackground(frame)
    frame:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1})
    self:StyleLayoutPanel(frame, true)
    self:SetLayoutColor(frame, "SetBackdropColor", 0.190, 0.145, 0.098, 0.75)
    self:SetLayoutColor(frame, "SetBackdropBorderColor", 0.52, 0.39, 0.22, 0.42)
end

-- Keep stock controls in the existing presets; layer Forever controls over their
-- textures so switching away restores the template without changing its scripts.
function IRS:StyleLayoutButton(button)
    self._layoutButtons = self._layoutButtons or setmetatable({}, {__mode = "k"})
    local skin = CreateFrame("Frame", nil, button, "BackdropTemplate")
    skin:SetAllPoints(button)
    skin:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1})
    self:StyleLayoutPanel(skin)
    local templateTextures = {}
    for _, method in ipairs({"GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture"}) do
        local texture = button[method](button)
        if texture then templateTextures[#templateTextures + 1] = {texture, texture:GetAlpha()} end
    end
    -- The button's FontString is on its parent layer, so draw the label on top.
    local label = skin:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER")
    label:SetPoint("LEFT", 6, 0)
    label:SetPoint("RIGHT", -6, 0)
    self:RegisterFontString("main", "label", label)
    local hovered = false
    local function Refresh()
        local enabled = button:IsEnabled()
        local active = IRS:GetLayoutStyle() == "forever"
        skin:SetShown(active)
        for _, entry in ipairs(templateTextures) do entry[1]:SetAlpha(active and 0 or entry[2]) end
        button:GetFontString():SetAlpha(active and 0 or 1)
        label:SetText(button:GetText())
        label:SetTextColor(unpack(enabled and {0.816, 0.718, 0.537, 1} or {0.718, 0.769, 0.741, 1}))
        skin:SetBackdropColor(unpack(hovered and enabled and {0.082, 0.325, 0.388, 0.80} or {0.024, 0.216, 0.275, 0.80}))
        skin:SetBackdropBorderColor(unpack(hovered and enabled and {0.816, 0.718, 0.537, 1} or {0.549, 0.510, 0.408, 1}))
    end
    button:HookScript("OnEnter", function() hovered = true; Refresh() end)
    button:HookScript("OnLeave", function() hovered = false; Refresh() end)
    button:HookScript("OnEnable", Refresh)
    button:HookScript("OnDisable", Refresh)
    self._layoutButtons[button] = Refresh
    Refresh()
end
