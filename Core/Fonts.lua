local _, IRS = ...
IRS.FONT_STYLE_DEFAULTS = {
    main = {
        helper = 10,
        body = 11,
        label = 12,
        section = 15,
        page = 19,
        value = 18,
        brand = 32,
    },
}

IRS.FONT_SIZE_LIMITS = {helper = 14, body = 14, label = 14, section = 18, page = 24, value = 22, brand = 36}

IRS.FONT_STYLE_ORDER = {
    main = {"helper", "body", "label", "section", "page", "value", "brand"},
}

IRS.FONT_STYLE_LABELS = {main = {
    helper = "Helper Text", body = "Body Text", label = "Labels & Controls",
    section = "Section Headings", page = "Page Headings", value = "Large Values",
    brand = "IRS Brand",
}}

-- Runtime references to FontStrings. This is not SavedVariables data.
IRS.DEFAULT_FONT_FACE = [[Interface\AddOns\IRS Lite\Media\fonts\2002b.ttf]]
IRS.FONT_FACE_OPTIONS = {
    {key = "default", label = "Default (2002 Bold)", path = IRS.DEFAULT_FONT_FACE},
    {key = "2002", label = "2002", path = [[Interface\AddOns\IRS Lite\Media\fonts\2002.ttf]]},
    {key = "arial", label = "Arial Narrow", path = [[Fonts\ARIALN.TTF]]},
    {key = "morpheus", label = "Morpheus", path = [[Fonts\MORPHEUS.TTF]]},
}

IRS._fontRegistry = IRS._fontRegistry or {
    main = {},
}
function IRS:ResolveFontStyle(scope, styleKey)
    scope = "main"
    local raw = tostring(styleKey)
    local defaults = IRS.FONT_STYLE_DEFAULTS[scope] or {}

    if defaults[raw] ~= nil then
        return raw
    end

    return nil
end

-- Returns the rendered size for one semantic font style.
function IRS:GetFontSize(scope, styleKey)
    scope = "main"
    local key = IRS:ResolveFontStyle(scope, styleKey)

    if not key then
        return 10
    end

    if not IRS.db then IRS:EnsureDB() end

    local defaults = IRS.FONT_STYLE_DEFAULTS[scope] or {}
    local saved = IRS.db.settings.fontSizes
        and IRS.db.settings.fontSizes[scope]
        and tonumber(IRS.db.settings.fontSizes[scope][key])

    return math.max(8, math.min(IRS.FONT_SIZE_LIMITS[key], saved or tonumber(defaults[key]) or 10))
end

-- Registers a FontString so a style change updates every matching text element.
function IRS:GetFontFace()
    if not IRS.db then IRS:EnsureDB() end
    local selected = IRS.db.settings.fontFace or "default"
    for _, option in ipairs(IRS.FONT_FACE_OPTIONS) do
        if option.key == selected then return option.path, option.label, option.key end
    end
    return IRS.DEFAULT_FONT_FACE, "Default (2002 Bold)", "default"
end

local function ApplyFontFace(fontString, fallbackPath, size, flags)
    local path = IRS:GetFontFace()
    -- FontStrings do not return success from SetFont (EditBoxes do). Checking
    -- its return value would immediately replace a successfully applied face.
    fontString:SetFont(path, size, flags or "")
    local appliedPath = fontString:GetFont()
    local function NormalizeFontPath(value)
        return tostring(value or ""):lower():gsub("/", "\\")
    end
    if NormalizeFontPath(appliedPath) ~= NormalizeFontPath(path) then
        fontString:SetFont(fallbackPath or STANDARD_TEXT_FONT, size, flags or "")
    end
end

function IRS:RegisterFontString(scope, styleKey, fontString, fontPath, flags)
    if not fontString then return end

    scope = "main"
    local key = IRS:ResolveFontStyle(scope, styleKey)
    if not key then return end
    IRS._registeredFontObjects = IRS._registeredFontObjects or setmetatable({}, {__mode = "k"})
    if IRS._registeredFontObjects[fontString] then return end
    IRS._registeredFontObjects[fontString] = {scope = scope, style = key}

    IRS._fontRegistry[scope] = IRS._fontRegistry[scope] or {}
    IRS._fontRegistry[scope][key] = IRS._fontRegistry[scope][key] or {}

    table.insert(IRS._fontRegistry[scope][key], {
        fontString = fontString,
        fontPath = fontPath or STANDARD_TEXT_FONT,
        flags = flags or "",
    })

    ApplyFontFace(fontString, fontPath, IRS:GetFontSize(scope, key), flags)
end

local function ApplyRegisteredFontStyle(scope, styleKey)
    scope = "main"
    local key = IRS:ResolveFontStyle(scope, styleKey)
    if not key then return end

    local size = IRS:GetFontSize(scope, key)

    for _, entry in ipairs(
        IRS._fontRegistry[scope]
        and IRS._fontRegistry[scope][key]
        or {}
    ) do
        if entry.fontString then
            ApplyFontFace(entry.fontString, entry.fontPath, size, entry.flags)
        end
    end
end

-- UI files can create text before SavedVariables are restored. Reapply the
-- loaded preferences to those existing FontStrings before measuring layout.
function IRS:ApplySavedFontSizes()
    for scope, defaults in pairs(IRS.FONT_STYLE_DEFAULTS) do
        for styleKey in pairs(defaults) do
            ApplyRegisteredFontStyle(scope, styleKey)
        end
    end
end

function IRS:SetFontFace(selected)
    local valid = false
    for _, option in ipairs(IRS.FONT_FACE_OPTIONS) do
        if option.key == selected then valid = true; break end
    end
    if not valid then return false end
    if not IRS.db then IRS:EnsureDB() end
    IRS.db.settings.fontFace = selected
    IRS:ApplySavedFontSizes()
    if IRS.RefreshUI then IRS:RefreshUI() end
    return true
end

-- Changes one shared semantic style.
function IRS:SetFontSize(scope, styleKey, value)
    if not IRS.db then IRS:EnsureDB() end

    scope = "main"
    local key = IRS:ResolveFontStyle(scope, styleKey)
    local defaults = IRS.FONT_STYLE_DEFAULTS[scope] or {}

    if not key or defaults[key] == nil then return false end

    value = math.floor((tonumber(value) or tonumber(defaults[key]) or 10) + 0.5)
    value = math.max(8, math.min(IRS.FONT_SIZE_LIMITS[key], value))

    IRS.db.settings.fontSizes[scope][key] = value
    ApplyRegisteredFontStyle(scope, key)

    if IRS.RefreshUI then IRS:RefreshUI() end

    return true
end

-- Restores all semantic styles for one interface scope.
function IRS:ResetFontSizes(scope)
    if not IRS.db then IRS:EnsureDB() end

    scope = "main"
    local defaults = IRS.FONT_STYLE_DEFAULTS[scope] or {}

    for key, defaultSize in pairs(defaults) do
        IRS.db.settings.fontSizes[scope][key] = defaultSize
        ApplyRegisteredFontStyle(scope, key)
    end

    if IRS.RefreshUI then IRS:RefreshUI() end
end
