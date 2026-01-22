-- ===================================================================
-- ArcUI_Bars_ImportExport.lua
-- Import/Export functionality for ArcUI bar configurations
-- Supports all bar settings including alternateCooldownIDs for cross-spec
-- ===================================================================

local ADDON, ns = ...
ns.BarsImportExport = ns.BarsImportExport or {}

local LibDeflate = LibStub("LibDeflate")
local AceSerializer = LibStub("AceSerializer-3.0")

-- Constants
local EXPORT_VERSION = 1
local EXPORT_PREFIX = "ARCUI_BARS"

-- Module state
local selectedBarsForExport = {}
local importPreviewData = nil
local lastExportString = ""
local lastImportString = ""
local importMode = "add"  -- "add" or "replace"

-- ===================================================================
-- UTILITY FUNCTIONS
-- ===================================================================

local function DeepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[DeepCopy(k)] = DeepCopy(v)
        end
        setmetatable(copy, DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

local function GetEnabledBars()
    local db = ns.API.GetDB and ns.API.GetDB()
    if not db or not db.bars then return {} end
    
    local enabled = {}
    for i = 1, 30 do
        local bar = db.bars[i]
        if bar and bar.tracking and bar.tracking.enabled then
            table.insert(enabled, {
                slot = i,
                name = bar.tracking.buffName or "Unknown",
                spellID = bar.tracking.spellID or 0,
                cooldownID = bar.tracking.cooldownID or 0,
                trackType = bar.tracking.trackType or "buff",
                alternateCooldownIDs = bar.tracking.alternateCooldownIDs or {},
            })
        end
    end
    return enabled
end

local function FindFirstEmptySlot()
    local db = ns.API.GetDB and ns.API.GetDB()
    if not db or not db.bars then return nil end
    
    for i = 1, 30 do
        local bar = db.bars[i]
        if not bar or not bar.tracking or not bar.tracking.enabled then
            return i
        end
    end
    return nil
end

local function CountEmptySlots()
    local db = ns.API.GetDB and ns.API.GetDB()
    if not db or not db.bars then return 0 end
    
    local count = 0
    for i = 1, 30 do
        local bar = db.bars[i]
        if not bar or not bar.tracking or not bar.tracking.enabled then
            count = count + 1
        end
    end
    return count
end

-- ===================================================================
-- EXPORT FUNCTIONS
-- ===================================================================

local function ExportSelectedBars()
    local db = ns.API.GetDB and ns.API.GetDB()
    if not db or not db.bars then 
        return nil, "Database not available"
    end
    
    local barsToExport = {}
    local exportCount = 0
    
    for slot, isSelected in pairs(selectedBarsForExport) do
        if isSelected then
            local bar = db.bars[slot]
            if bar and bar.tracking and bar.tracking.enabled then
                -- Deep copy the bar config (strip slot index)
                local barCopy = DeepCopy(bar)
                table.insert(barsToExport, barCopy)
                exportCount = exportCount + 1
            end
        end
    end
    
    if exportCount == 0 then
        return nil, "No bars selected for export"
    end
    
    -- Build export data structure
    local exportData = {
        version = EXPORT_VERSION,
        prefix = EXPORT_PREFIX,
        timestamp = time(),
        exportedBy = UnitName("player") or "Unknown",
        realm = GetRealmName() or "Unknown",
        barCount = exportCount,
        bars = barsToExport,
    }
    
    -- Serialize → Compress → Encode
    local serialized = AceSerializer:Serialize(exportData)
    if not serialized then
        return nil, "Serialization failed"
    end
    
    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return nil, "Compression failed"
    end
    
    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil, "Encoding failed"
    end
    
    lastExportString = encoded
    return encoded, nil
end

-- ===================================================================
-- IMPORT FUNCTIONS
-- ===================================================================

local function ParseImportString(importString)
    if not importString or importString == "" then
        return nil, "Empty import string"
    end
    
    -- Clean up the string
    importString = importString:gsub("^%s+", ""):gsub("%s+$", "")
    
    -- Decode → Decompress → Deserialize
    local decoded = LibDeflate:DecodeForPrint(importString)
    if not decoded then
        return nil, "Invalid import string (decode failed)"
    end
    
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return nil, "Invalid import string (decompress failed)"
    end
    
    local success, data = AceSerializer:Deserialize(decompressed)
    if not success or not data then
        return nil, "Invalid import string (deserialize failed)"
    end
    
    -- Validate structure
    if data.prefix ~= EXPORT_PREFIX then
        return nil, "Invalid import string (wrong format)"
    end
    
    if not data.bars or #data.bars == 0 then
        return nil, "No bars found in import data"
    end
    
    return data, nil
end

local function GenerateImportPreview(data)
    if not data then return "No data" end
    
    local barNames = {}
    for i, bar in ipairs(data.bars) do
        local name = bar.tracking and bar.tracking.buffName or "Unknown"
        local altCount = bar.tracking and bar.tracking.alternateCooldownIDs and #bar.tracking.alternateCooldownIDs or 0
        if altCount > 0 then
            name = name .. " |cff00FF00(+" .. altCount .. " alt)|r"
        end
        table.insert(barNames, name)
    end
    
    local preview = string.format(
        "|cff00FF00Found %d bar(s)|r from %s @ %s:\n|cffFFFF00%s|r",
        data.barCount or #data.bars,
        data.exportedBy or "Unknown",
        data.realm or "Unknown",
        table.concat(barNames, ", ")
    )
    
    return preview
end

local function ImportBars(data, mode)
    local db = ns.API.GetDB and ns.API.GetDB()
    if not db then 
        return false, "Database not available"
    end
    
    -- Ensure bars table exists
    if not db.bars then
        db.bars = {}
    end
    
    local imported = 0
    local skipped = 0
    local messages = {}
    
    if mode == "replace" then
        -- Reset all bars to disabled first
        for i = 1, 30 do
            if db.bars[i] then
                db.bars[i].tracking = db.bars[i].tracking or {}
                db.bars[i].tracking.enabled = false
            end
        end
        
        -- Import from slot 1
        for i, importedBar in ipairs(data.bars) do
            if i <= 30 then
                db.bars[i] = DeepCopy(importedBar)
                imported = imported + 1
            else
                table.insert(messages, "Slot limit reached, skipped: " .. (importedBar.tracking and importedBar.tracking.buffName or "Unknown"))
                skipped = skipped + 1
            end
        end
    else
        -- Add mode: find empty slots
        for _, importedBar in ipairs(data.bars) do
            local emptySlot = FindFirstEmptySlot()
            if emptySlot then
                db.bars[emptySlot] = DeepCopy(importedBar)
                imported = imported + 1
            else
                local name = importedBar.tracking and importedBar.tracking.buffName or "Unknown"
                table.insert(messages, "No empty slots, skipped: " .. name)
                skipped = skipped + 1
            end
        end
    end
    
    -- Trigger validation for imported bars
    if ns.API.ValidateAllBarTracking then
        C_Timer.After(0.1, function()
            ns.API.ValidateAllBarTracking()
        end)
    end
    
    -- Refresh UI
    if ns.Display and ns.Display.RefreshAllBars then
        C_Timer.After(0.2, function()
            ns.Display.RefreshAllBars()
        end)
    end
    
    local result = string.format("Imported %d bar(s)", imported)
    if skipped > 0 then
        result = result .. string.format(", skipped %d", skipped)
    end
    
    if #messages > 0 then
        result = result .. "\n" .. table.concat(messages, "\n")
    end
    
    return true, result
end

-- ===================================================================
-- OPTIONS TABLE
-- ===================================================================

function ns.BarsImportExport.GetOptionsTable()
    local enabledBars = GetEnabledBars()
    
    -- Initialize selection state
    for _, bar in ipairs(enabledBars) do
        if selectedBarsForExport[bar.slot] == nil then
            selectedBarsForExport[bar.slot] = true  -- Default to selected
        end
    end
    
    local options = {
        type = "group",
        name = "Import/Export",
        order = 4,
        args = {
            -- ═══════════════════════════════════════════════════════════════
            -- EXPORT SECTION
            -- ═══════════════════════════════════════════════════════════════
            exportHeader = {
                type = "header",
                name = "Export Bars",
                order = 1,
            },
            
            exportDesc = {
                type = "description",
                name = "Select bars to export. The export string includes all settings including alternate cooldownIDs for cross-spec support.",
                order = 2,
            },
            
            selectAllBtn = {
                type = "execute",
                name = "Select All",
                order = 3,
                width = 0.6,
                func = function()
                    for _, bar in ipairs(GetEnabledBars()) do
                        selectedBarsForExport[bar.slot] = true
                    end
                end,
            },
            
            selectNoneBtn = {
                type = "execute",
                name = "Select None",
                order = 4,
                width = 0.6,
                func = function()
                    for k in pairs(selectedBarsForExport) do
                        selectedBarsForExport[k] = false
                    end
                end,
            },
            
            spacer1 = {
                type = "description",
                name = "",
                order = 5,
            },
            
            -- Bar selection checkboxes (dynamically generated)
            barSelectionGroup = {
                type = "group",
                name = "Select Bars",
                order = 6,
                inline = true,
                args = (function()
                    local args = {}
                    local bars = GetEnabledBars()
                    
                    if #bars == 0 then
                        args.noBars = {
                            type = "description",
                            name = "|cffFF6600No enabled bars found.|r",
                            order = 1,
                        }
                    else
                        for i, bar in ipairs(bars) do
                            local altText = ""
                            if bar.alternateCooldownIDs and #bar.alternateCooldownIDs > 0 then
                                altText = " |cff00FF00(+" .. #bar.alternateCooldownIDs .. " alt)|r"
                            end
                            
                            args["bar" .. bar.slot] = {
                                type = "toggle",
                                name = string.format("Bar %d: %s%s", bar.slot, bar.name, altText),
                                desc = string.format("Type: %s, CooldownID: %d", bar.trackType, bar.cooldownID),
                                order = i,
                                width = "full",
                                get = function() return selectedBarsForExport[bar.slot] end,
                                set = function(_, val) selectedBarsForExport[bar.slot] = val end,
                            }
                        end
                    end
                    
                    return args
                end)(),
            },
            
            exportBtn = {
                type = "execute",
                name = "Export Selected",
                order = 7,
                width = 1,
                func = function()
                    local result, err = ExportSelectedBars()
                    if err then
                        print("|cffFF0000[ArcUI]|r Export failed: " .. err)
                    else
                        print("|cff00FF00[ArcUI]|r Export successful! Copy the string from the box below.")
                    end
                end,
            },
            
            exportString = {
                type = "input",
                name = "Export String",
                order = 8,
                multiline = 6,
                width = "full",
                get = function() return lastExportString end,
                set = function() end,  -- Read-only
            },
            
            -- ═══════════════════════════════════════════════════════════════
            -- IMPORT SECTION
            -- ═══════════════════════════════════════════════════════════════
            importHeader = {
                type = "header",
                name = "Import Bars",
                order = 20,
            },
            
            importDesc = {
                type = "description",
                name = "Paste an export string below to import bar configurations.",
                order = 21,
            },
            
            importString = {
                type = "input",
                name = "Paste Export String",
                order = 22,
                multiline = 6,
                width = "full",
                get = function() return lastImportString end,
                set = function(_, val)
                    lastImportString = val
                    -- Auto-parse for preview
                    local data, err = ParseImportString(val)
                    if data then
                        importPreviewData = data
                    else
                        importPreviewData = nil
                    end
                end,
            },
            
            previewBtn = {
                type = "execute",
                name = "Preview",
                order = 23,
                width = 0.6,
                func = function()
                    local data, err = ParseImportString(lastImportString)
                    if err then
                        print("|cffFF0000[ArcUI]|r " .. err)
                        importPreviewData = nil
                    else
                        importPreviewData = data
                        print("|cff00FF00[ArcUI]|r " .. GenerateImportPreview(data))
                    end
                end,
            },
            
            importPreview = {
                type = "description",
                name = function()
                    if importPreviewData then
                        return GenerateImportPreview(importPreviewData)
                    else
                        return "|cff888888Paste a string and click Preview to see contents.|r"
                    end
                end,
                order = 24,
                fontSize = "medium",
            },
            
            importModeSelect = {
                type = "select",
                name = "Import Mode",
                order = 25,
                width = 1.2,
                values = {
                    add = "Add to existing bars",
                    replace = "Replace all bars",
                },
                get = function() return importMode end,
                set = function(_, val) importMode = val end,
            },
            
            importModeDesc = {
                type = "description",
                name = function()
                    local emptySlots = CountEmptySlots()
                    if importMode == "add" then
                        return string.format("|cff888888Bars will be added to empty slots (%d available).|r", emptySlots)
                    else
                        return "|cffFF6600WARNING: This will disable ALL existing bars and import from slot 1!|r"
                    end
                end,
                order = 26,
            },
            
            importBtn = {
                type = "execute",
                name = "Import",
                order = 27,
                width = 1,
                disabled = function() return importPreviewData == nil end,
                func = function()
                    if not importPreviewData then
                        print("|cffFF0000[ArcUI]|r No valid import data. Paste a string and Preview first.")
                        return
                    end
                    
                    local success, result = ImportBars(importPreviewData, importMode)
                    if success then
                        print("|cff00FF00[ArcUI]|r " .. result)
                        -- Clear import state
                        lastImportString = ""
                        importPreviewData = nil
                    else
                        print("|cffFF0000[ArcUI]|r Import failed: " .. result)
                    end
                end,
            },
        },
    }
    
    return options
end

-- Export the function for Options.lua to use
ns.GetBarsImportExportOptionsTable = function()
    return ns.BarsImportExport.GetOptionsTable()
end
