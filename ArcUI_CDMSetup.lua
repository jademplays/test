-- ===================================================================
-- ArcUI_CDMSetup.lua
-- CDM Requirements Checker and Alert System
-- Ensures CDM is properly configured for ArcUI to function
-- ===================================================================

local ADDON_NAME, ns = ...

ns.CDMSetup = ns.CDMSetup or {}

-- ===================================================================
-- VERSION CHECK - MIDNIGHT ONLY
-- ===================================================================
local MIDNIGHT_INTERFACE = 120000  -- 12.0.0
local CURRENT_INTERFACE = select(4, GetBuildInfo())

--- Check if running on Midnight (12.0+)
function ns.CDMSetup.IsMidnight()
    return CURRENT_INTERFACE >= MIDNIGHT_INTERFACE
end

--- Get version info string
function ns.CDMSetup.GetVersionInfo()
    local major = math.floor(CURRENT_INTERFACE / 10000)
    local minor = math.floor((CURRENT_INTERFACE % 10000) / 100)
    local patch = CURRENT_INTERFACE % 100
    return string.format("%d.%d.%d", major, minor, patch)
end

-- ===================================================================
-- VERSION ALERT UI
-- ===================================================================
local versionAlertFrame = nil

local function CreateVersionAlert()
    if versionAlertFrame then return versionAlertFrame end
    
    local f = CreateFrame("Frame", "ArcUI_VersionAlert", UIParent, "BackdropTemplate")
    f:SetSize(400, 270)
    f:SetPoint("CENTER", 0, 100)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(500)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    -- Backdrop
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 11, top = 12, bottom = 11 }
    })
    f:SetBackdropColor(0.1, 0.05, 0.05, 1)
    
    -- Warning Icon
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", 20, -20)
    icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    
    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    title:SetText("|cffFF6666ArcUI - Version Warning|r")
    f.title = title
    
    -- Subtitle
    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetWidth(300)
    subtitle:SetJustifyH("LEFT")
    f.subtitle = subtitle
    
    -- Message
    local message = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    message:SetPoint("TOPLEFT", f, "TOPLEFT", 25, -80)
    message:SetPoint("RIGHT", f, "RIGHT", -25, 0)
    message:SetJustifyH("LEFT")
    message:SetSpacing(2)
    f.message = message
    
    -- Don't show again checkbox
    local dontShowCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    dontShowCheck:SetSize(24, 24)
    dontShowCheck:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 22, 42)
    dontShowCheck:SetChecked(false)
    f.dontShowCheck = dontShowCheck
    
    local dontShowLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dontShowLabel:SetPoint("LEFT", dontShowCheck, "RIGHT", 2, 0)
    dontShowLabel:SetText("|cffaaaaaaDon't show this again|r")
    dontShowLabel:SetScript("OnMouseDown", function() 
        dontShowCheck:Click() 
    end)
    -- Make label clickable
    local labelBtn = CreateFrame("Button", nil, f)
    labelBtn:SetAllPoints(dontShowLabel)
    labelBtn:SetScript("OnClick", function() dontShowCheck:Click() end)
    
    -- Understand Button (centered at bottom)
    local understandBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    understandBtn:SetSize(120, 24)
    understandBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 18)
    understandBtn:SetText("I Understand")
    f.understandBtn = understandBtn
    
    -- Close X button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        f:Hide()
    end)
    
    versionAlertFrame = f
    return f
end

--- Show the version warning alert
function ns.CDMSetup.ShowVersionAlert()
    local f = CreateVersionAlert()
    
    local isMidnight = ns.CDMSetup.IsMidnight()
    local versionStr = ns.CDMSetup.GetVersionInfo()
    
    if isMidnight then
        -- Shouldn't normally show, but just in case
        f:Hide()
        return
    end
    
    -- Reset checkbox state
    f.dontShowCheck:SetChecked(false)
    
    -- Not on Midnight - show warning
    f.title:SetText("|cffFF6666ArcUI - Midnight Required|r")
    f.subtitle:SetText("You are running WoW version |cffFFD100" .. versionStr .. "|r")
    f.message:SetText(
        "ArcUI is designed exclusively for |cff00ccffWorld of Warcraft:\nMidnight|r (12.0+).\n\n" ..
        "This addon uses Midnight-specific APIs including:\n" ..
        "|cffaaaaaa•|r Cooldown Manager (CDM) integration\n" ..
        "|cffaaaaaa•|r Secret Value handling\n" ..
        "|cffaaaaaa•|r New UI systems\n\n" ..
        "The addon |cffFF6666will not function|r on earlier versions."
    )
    
    f.understandBtn:SetText("I Understand")
    f.understandBtn:SetScript("OnClick", function()
        -- Only save "don't show again" if checkbox is checked
        if f.dontShowCheck:GetChecked() then
            if ns.db and ns.db.global then
                ns.db.global.versionAlertShown = CURRENT_INTERFACE
            elseif ArcUI_DB then
                ArcUI_DB.versionAlertShown = CURRENT_INTERFACE
            end
        end
        f:Hide()
    end)
    
    f:Show()
    f:Raise()
end

--- Check if version alert should be shown
function ns.CDMSetup.ShouldShowVersionAlert()
    -- Only show if NOT on Midnight
    if ns.CDMSetup.IsMidnight() then
        return false
    end
    
    -- Check if already shown for this version
    local shownVersion
    if ns.db and ns.db.global then
        shownVersion = ns.db.global.versionAlertShown
    elseif ArcUI_DB then
        shownVersion = ArcUI_DB.versionAlertShown
    end
    
    -- Show if never shown or shown for different version
    return shownVersion ~= CURRENT_INTERFACE
end

--- Run version check on load
function ns.CDMSetup.CheckVersion()
    if ns.CDMSetup.ShouldShowVersionAlert() then
        ns.CDMSetup.ShowVersionAlert()
        return false
    end
    return ns.CDMSetup.IsMidnight()
end

-- ===================================================================
-- CONSTANTS
-- ===================================================================
local CDM_SETTING_VISIBILITY = 6
local VIS_ALWAYS = 0

local CDM_VIEWERS = {
    { frame = "EssentialCooldownViewer", name = "Essential Cooldowns", systemIndex = 1 },
    { frame = "UtilityCooldownViewer", name = "Utility Cooldowns", systemIndex = 2 },
    { frame = "BuffIconCooldownViewer", name = "Tracked Buffs", systemIndex = 3 },
}

-- ===================================================================
-- CHECK FUNCTIONS
-- ===================================================================

--- Check if the user is on a Preset Edit Mode layout (Modern/Classic)
--- Preset layouts cannot have settings changed - user must create a custom layout first
function ns.CDMSetup.IsOnPresetLayout()
    if not EditModeManagerFrame then return false end
    
    if EditModeManagerFrame.GetActiveLayoutInfo then
        local layoutInfo = EditModeManagerFrame:GetActiveLayoutInfo()
        if layoutInfo and layoutInfo.layoutType ~= nil then
            -- Enum.EditModeLayoutType.Preset = 0
            if layoutInfo.layoutType == 0 or 
               (Enum and Enum.EditModeLayoutType and layoutInfo.layoutType == Enum.EditModeLayoutType.Preset) then
                return true, layoutInfo.layoutName or "Preset"
            end
        end
    end
    
    return false, nil
end

--- Check if CDM is enabled via CVar
function ns.CDMSetup.IsCDMEnabled()
    return GetCVarBool("cooldownViewerEnabled")
end

--- Check all CDM requirements
-- @return table issues - Array of issue objects
function ns.CDMSetup.CheckRequirements()
    local issues = {}
    
    -- Check 0: Preset Layout (can't fix settings on preset)
    local isPreset, presetName = ns.CDMSetup.IsOnPresetLayout()
    if isPreset then
        table.insert(issues, {
            id = "preset_layout",
            text = "Using '" .. (presetName or "Preset") .. "' Edit Mode layout",
            priority = 0,  -- Highest priority - show first
            requiresReload = false,
            isPresetWarning = true,
        })
    end
    
    -- Check 1: CDM Enabled
    if not ns.CDMSetup.IsCDMEnabled() then
        table.insert(issues, {
            id = "cdm_disabled",
            text = "Cooldown Manager is disabled",
            priority = 1,
            requiresReload = true,
        })
    end
    
    -- Only check viewer settings if CDM is enabled (frames exist)
    if ns.CDMSetup.IsCDMEnabled() then
        -- Check 2: Viewer Visibility
        for _, viewerInfo in ipairs(CDM_VIEWERS) do
            local viewer = _G[viewerInfo.frame]
            if viewer and viewer.visibleSetting ~= VIS_ALWAYS then
                local visNames = {[0]="Always", [1]="In Combat", [2]="Hidden"}
                table.insert(issues, {
                    id = "visibility_" .. viewerInfo.frame,
                    text = viewerInfo.name .. " is set to '" .. (visNames[viewer.visibleSetting] or "Unknown") .. "'",
                    priority = 2,
                    requiresReload = false,
                    viewer = viewer,
                    setting = CDM_SETTING_VISIBILITY,
                    targetValue = VIS_ALWAYS,
                })
            end
        end
    end
    
    -- Sort by priority
    table.sort(issues, function(a, b) return a.priority < b.priority end)
    
    return issues
end

--- Check if ArcUI CDM styling is enabled
function ns.CDMSetup.IsCDMStylingEnabled()
    -- Use Shared's function if available (authoritative source)
    local Shared = ns.CDMShared
    if Shared and Shared.IsCDMStylingEnabled then
        return Shared.IsCDMStylingEnabled()
    end
    
    -- Fallback: Check global setting (source of truth)
    if ns.db and ns.db.global then
        return ns.db.global.cdmStylingEnabled ~= false
    end
    
    -- Fallback: Check char storage
    if ns.db and ns.db.char and ns.db.char.cdmGroups then
        return ns.db.char.cdmGroups.enabled ~= false
    end
    
    -- Default to enabled if no DB available yet
    return true
end

-- ===================================================================
-- FIX FUNCTIONS
-- ===================================================================

--- Enable CDM via CVar (requires reload to take effect)
function ns.CDMSetup.EnableCDM()
    SetCVar("cooldownViewerEnabled", "1")
end

--- Fix a single viewer setting using EditModeManagerFrame
local function FixViewerSetting(viewer, settingID, value)
    if not viewer then return false end
    
    local mgr = EditModeManagerFrame
    if not mgr or not mgr.OnSystemSettingChange then
        return false
    end
    
    local ok = pcall(mgr.OnSystemSettingChange, mgr, viewer, settingID, value)
    return ok
end

--- Fix all viewer settings (visibility)
function ns.CDMSetup.FixViewerSettings()
    local mgr = EditModeManagerFrame
    if not mgr or not mgr.OnSystemSettingChange then
        return false, "EditModeManagerFrame not available"
    end
    
    local changesMade = false
    
    -- Fix visibility for all viewers
    for _, viewerInfo in ipairs(CDM_VIEWERS) do
        local viewer = _G[viewerInfo.frame]
        if viewer and viewer.visibleSetting ~= VIS_ALWAYS then
            if FixViewerSetting(viewer, CDM_SETTING_VISIBILITY, VIS_ALWAYS) then
                changesMade = true
            end
        end
    end
    
    -- Save changes
    if changesMade and mgr.SaveLayouts then
        pcall(mgr.SaveLayouts, mgr)
    end
    
    return changesMade
end

--- Fix all issues that can be fixed without reload
function ns.CDMSetup.FixAllIssues(issues)
    local needsReload = false
    local fixedCount = 0
    
    for _, issue in ipairs(issues) do
        if issue.requiresReload then
            -- CDM disabled - enable it
            ns.CDMSetup.EnableCDM()
            needsReload = true
        elseif issue.viewer and issue.setting and issue.targetValue then
            -- Viewer setting issue - fix it
            if FixViewerSetting(issue.viewer, issue.setting, issue.targetValue) then
                fixedCount = fixedCount + 1
            end
        end
    end
    
    -- Save if we made changes
    if fixedCount > 0 then
        local mgr = EditModeManagerFrame
        if mgr and mgr.SaveLayouts then
            pcall(mgr.SaveLayouts, mgr)
        end
    end
    
    return needsReload, fixedCount
end

-- ===================================================================
-- ALERT UI
-- ===================================================================
local alertFrame = nil

local function CreateAlertFrame()
    if alertFrame then return alertFrame end
    
    local f = CreateFrame("Frame", "ArcUI_CDMSetupAlert", UIParent, "BackdropTemplate")
    f:SetSize(400, 260)
    f:SetPoint("CENTER", 0, 100)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(500)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    -- Backdrop
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 11, top = 12, bottom = 11 }
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 1)
    
    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -16)
    title:SetText("|cffFFD100ArcUI - CDM Setup Required|r")
    f.title = title
    
    -- Subtitle
    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -8)
    subtitle:SetWidth(360)
    f.subtitle = subtitle
    
    -- Issues list frame
    local issuesFrame = CreateFrame("Frame", nil, f)
    issuesFrame:SetPoint("TOP", subtitle, "BOTTOM", 0, -10)
    issuesFrame:SetPoint("LEFT", f, "LEFT", 20, 0)
    issuesFrame:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    issuesFrame:SetHeight(100)
    f.issuesFrame = issuesFrame
    
    -- Note text
    local noteText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteText:SetPoint("BOTTOM", f, "BOTTOM", 0, 85)
    noteText:SetWidth(360)
    noteText:SetJustifyH("CENTER")
    f.noteText = noteText
    
    -- Fix Button
    local fixButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    fixButton:SetSize(120, 28)
    fixButton:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -5, 50)
    fixButton:SetText("Fix Settings")
    f.fixButton = fixButton
    
    -- Later Button (just closes, will show again next login)
    local laterButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    laterButton:SetSize(120, 28)
    laterButton:SetPoint("BOTTOMLEFT", f, "BOTTOM", 5, 50)
    laterButton:SetText("Later")
    laterButton:SetScript("OnClick", function()
        f:Hide()
    end)
    f.laterButton = laterButton
    
    -- Don't Show Again checkbox
    local dontShowCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    dontShowCheck:SetSize(24, 24)
    dontShowCheck:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 18)
    dontShowCheck:SetChecked(ns.db and ns.db.profile and ns.db.profile.cdmSetupDismissed or false)
    dontShowCheck:SetScript("OnClick", function(self)
        if ns.db and ns.db.profile then
            ns.db.profile.cdmSetupDismissed = self:GetChecked()
        end
    end)
    f.dontShowCheck = dontShowCheck
    
    local dontShowLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dontShowLabel:SetPoint("LEFT", dontShowCheck, "RIGHT", 2, 0)
    dontShowLabel:SetText("Don't show this again")
    dontShowLabel:SetTextColor(0.7, 0.7, 0.7)
    f.dontShowLabel = dontShowLabel
    
    -- Status text
    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("BOTTOM", f, "BOTTOM", 40, 20)
    statusText:SetWidth(200)
    f.statusText = statusText
    
    -- Close X button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        f:Hide()
    end)
    
    alertFrame = f
    return f
end

--- Show the CDM setup alert
function ns.CDMSetup.ShowAlert(issues)
    local f = CreateAlertFrame()
    
    -- Update checkbox state
    if f.dontShowCheck then
        f.dontShowCheck:SetChecked(ns.db and ns.db.profile and ns.db.profile.cdmSetupDismissed or false)
    end
    
    -- Clear previous issue lines
    for i = 1, 10 do
        if f.issuesFrame["line" .. i] then
            f.issuesFrame["line" .. i]:Hide()
        end
    end
    
    -- Display issues
    local lastLine = nil
    local hasPresetWarning = false
    local needsReload = false
    
    for i, issue in ipairs(issues) do
        if i <= 6 then
            local line = f.issuesFrame["line" .. i]
            if not line then
                line = f.issuesFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                if lastLine then
                    line:SetPoint("TOPLEFT", lastLine, "BOTTOMLEFT", 0, -4)
                else
                    line:SetPoint("TOPLEFT", f.issuesFrame, "TOPLEFT", 0, 0)
                end
                line:SetWidth(360)
                line:SetJustifyH("LEFT")
                f.issuesFrame["line" .. i] = line
            end
            
            local color = issue.isPresetWarning and "|cffFF8800" or "|cffFF6666"
            line:SetText(color .. "• " .. issue.text .. "|r")
            line:Show()
            lastLine = line
            
            if issue.isPresetWarning then
                hasPresetWarning = true
            end
            if issue.requiresReload then
                needsReload = true
            end
        end
    end
    
    f.statusText:SetText("")
    
    -- Adjust button behavior based on issues
    if hasPresetWarning then
        -- Can't auto-fix on preset layout
        f.title:SetText("|cffFF8800ArcUI - Custom Layout Required|r")
        f.subtitle:SetText("ArcUI cannot modify CDM settings on a Preset layout:")
        f.noteText:SetText("|cffaaaaaaYou must create a |cffFFD100custom Edit Mode layout|r |cffaaaaaafirst.\nPress ESC → Edit Mode → Layout dropdown → '+ New Layout'|r")
        
        f.fixButton:SetText("Open Edit Mode")
        f.fixButton:SetScript("OnClick", function()
            f:Hide()
            
            if EditModeManagerFrame then
                if EditModeManagerFrame.Show then
                    EditModeManagerFrame:Show()
                elseif ToggleEditModeManager then
                    ToggleEditModeManager()
                end
                
                -- Monitor for layout change
                f.layoutMonitor = C_Timer.NewTicker(1, function()
                    local isPreset = ns.CDMSetup.IsOnPresetLayout()
                    if not isPreset then
                        f.layoutMonitor:Cancel()
                        f.layoutMonitor = nil
                        -- Re-check after switching to custom layout
                        C_Timer.After(0.5, function()
                            ns.CDMSetup.RunCheck(false, true)
                        end)
                    end
                end)
            else
                -- Fallback: tell user how to do it manually
                print("|cff00ccffArcUI|r: Press |cffFFD100ESC|r and click |cffFFD100Edit Mode|r to open the editor.")
            end
        end)
    elseif needsReload then
        -- Standard reload needed flow
        f.title:SetText("|cffFFD100ArcUI - CDM Setup Required|r")
        f.subtitle:SetText("ArcUI requires these CDM settings to be changed:")
        f.noteText:SetText("|cffaaaaaaRequired: CDM Enabled, All viewers 'Always Visible'|r")
        
        f.fixButton:SetText("Fix Settings & Reload")
        f.fixButton:SetScript("OnClick", function()
            local needReload, fixedCount = ns.CDMSetup.FixAllIssues(issues)
            if needReload then
                ReloadUI()
            else
                -- Settings fixed but no reload needed
                f.statusText:SetText("|cff00FF00Settings fixed!|r")
                C_Timer.After(1.5, function()
                    f:Hide()
                end)
            end
        end)
    else
        -- Only settings issues, no CDM enable needed
        f.title:SetText("|cffFFD100ArcUI - CDM Setup Required|r")
        f.subtitle:SetText("ArcUI requires these CDM settings to be changed:")
        f.noteText:SetText("|cffaaaaaaRequired: CDM Enabled, All viewers 'Always Visible'|r")
        
        f.fixButton:SetText("Fix Settings")
        f.fixButton:SetScript("OnClick", function()
            local _, fixedCount = ns.CDMSetup.FixAllIssues(issues)
            if fixedCount > 0 then
                f.statusText:SetText("|cff00FF00Settings fixed! Reload recommended.|r")
                f.fixButton:SetText("Reload UI")
                f.fixButton:SetScript("OnClick", function()
                    ReloadUI()
                end)
            else
                f.statusText:SetText("|cffFF6666Could not fix settings|r")
            end
        end)
    end
    
    f:Show()
    f:Raise()
end

--- Hide the alert
function ns.CDMSetup.HideAlert()
    if alertFrame then
        -- Cancel layout monitor if running
        if alertFrame.layoutMonitor then
            alertFrame.layoutMonitor:Cancel()
            alertFrame.layoutMonitor = nil
        end
        alertFrame:Hide()
    end
end

-- ===================================================================
-- MAIN CHECK FUNCTION
-- ===================================================================

--- Run the CDM requirements check and show alert if needed
-- @param silent boolean - If true, don't show alert (just return result)
-- @return boolean allGood, table issues
function ns.CDMSetup.RunCheck(silent, forceShow)
    -- Only check if CDM styling is enabled
    if not ns.CDMSetup.IsCDMStylingEnabled() then
        return true, {}
    end
    
    -- Check if user dismissed the alert (unless forceShow is true)
    if not forceShow and not silent and ns.db and ns.db.profile and ns.db.profile.cdmSetupDismissed then
        return true, {}  -- Pretend all is good if dismissed
    end
    
    local issues = ns.CDMSetup.CheckRequirements()
    
    if #issues > 0 and not silent then
        ns.CDMSetup.ShowAlert(issues)
    end
    
    return #issues == 0, issues
end

--- Reset the dismissed flag (allow alert to show again)
function ns.CDMSetup.ResetDismissed()
    if ns.db and ns.db.profile then
        ns.db.profile.cdmSetupDismissed = nil
    end
end

-- ===================================================================
-- HOOK INTO CDM STYLING ENABLE
-- ===================================================================

--- Called when CDM Styling is enabled
-- Check requirements and show alert if needed
function ns.CDMSetup.OnCDMStylingEnabled()
    -- Delay slightly to ensure CDM frames are ready
    C_Timer.After(0.5, function()
        ns.CDMSetup.RunCheck(false)
    end)
end

-- ===================================================================
-- INITIALIZATION
-- ===================================================================

-- Version for one-time migrations (increment to re-run migrations)
local SETUP_MIGRATION_VERSION = 1

local function RunMigrations()
    if not ns.db or not ns.db.profile then return end
    
    local lastMigration = ns.db.profile.cdmSetupMigrationVersion or 0
    
    -- Migration 1: Reset dismissed flag (v3.3.2 - fix for broken alert)
    if lastMigration < 1 then
        ns.db.profile.cdmSetupDismissed = nil
    end
    
    -- Update migration version
    ns.db.profile.cdmSetupMigrationVersion = SETUP_MIGRATION_VERSION
end

local function Initialize()
    -- Run one-time migrations
    RunMigrations()
    
    -- First, check version - show warning if not on Midnight
    if ns.CDMSetup.ShouldShowVersionAlert() then
        ns.CDMSetup.ShowVersionAlert()
        -- Don't proceed with CDM checks if not on Midnight
        if not ns.CDMSetup.IsMidnight() then
            return
        end
    end
    
    -- Run CDM check on login if CDM styling is enabled
    C_Timer.After(2, function()
        if ns.CDMSetup.IsCDMStylingEnabled() then
            ns.CDMSetup.RunCheck(false)
        end
    end)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        Initialize()
    end
end)

-- ===================================================================
-- SLASH COMMAND FOR TESTING
-- ===================================================================
SLASH_ARCUICDMSETUP1 = "/arcsetup"
SLASH_ARCUICDMSETUP2 = "/arcuisetup"
SlashCmdList["ARCUICDMSETUP"] = function(msg)
    if msg == "check" or msg == "" then
        -- Force show alert even if dismissed
        local allGood, issues = ns.CDMSetup.RunCheck(false, true)
        if allGood then
            print("|cff00ccffArcUI|r: All CDM settings are correct!")
        end
    elseif msg == "fix" then
        local issues = ns.CDMSetup.CheckRequirements()
        if #issues == 0 then
            print("|cff00ccffArcUI|r: All CDM settings are correct!")
        else
            -- Check for preset warning
            local hasPreset = false
            for _, issue in ipairs(issues) do
                if issue.isPresetWarning then
                    hasPreset = true
                    break
                end
            end
            
            if hasPreset then
                print("|cff00ccffArcUI|r: |cffFFD100Cannot auto-fix on Preset layout.|r")
                print("  Please create a custom Edit Mode layout first.")
                print("  Press ESC → Edit Mode → Layout dropdown → '+ New Layout'")
            else
                local needsReload, fixedCount = ns.CDMSetup.FixAllIssues(issues)
                if needsReload then
                    print("|cff00ccffArcUI|r: CDM enabled. |cffFF6666Reload required!|r Type /reload")
                elseif fixedCount > 0 then
                    print("|cff00ccffArcUI|r: Fixed " .. fixedCount .. " settings. Reload recommended.")
                end
            end
        end
    elseif msg == "status" then
        print("|cff00ccffArcUI CDM Status:|r")
        print("  WoW Version: |cffFFD100" .. ns.CDMSetup.GetVersionInfo() .. "|r (Midnight: " .. (ns.CDMSetup.IsMidnight() and "|cff00FF00Yes|r" or "|cffFF0000No|r") .. ")")
        print("  CDM Enabled: " .. (ns.CDMSetup.IsCDMEnabled() and "|cff00FF00Yes|r" or "|cffFF0000No|r"))
        print("  CDM Styling: " .. (ns.CDMSetup.IsCDMStylingEnabled() and "|cff00FF00Enabled|r" or "|cffaaaaaa Disabled|r"))
        
        -- Check layout type
        local isPreset, presetName = ns.CDMSetup.IsOnPresetLayout()
        if isPreset then
            print("  Edit Mode Layout: |cffFF8800" .. (presetName or "Preset") .. " (Preset)|r")
        else
            print("  Edit Mode Layout: |cff00FF00Custom|r")
        end
        
        -- Check dismissed state
        local dismissed = ns.db and ns.db.profile and ns.db.profile.cdmSetupDismissed
        print("  Alert Dismissed: " .. (dismissed and "|cffFFFF00Yes|r" or "No"))
        
        if ns.CDMSetup.IsCDMEnabled() then
            local visNames = {[0]="|cff00FF00Always|r", [1]="|cffFFFF00In Combat|r", [2]="|cffFF0000Hidden|r"}
            for _, viewerInfo in ipairs(CDM_VIEWERS) do
                local viewer = _G[viewerInfo.frame]
                if viewer then
                    print("  " .. viewerInfo.name .. ": " .. (visNames[viewer.visibleSetting] or "?"))
                end
            end
        end
    elseif msg == "1" then
        -- Quick reset of alert dismissed state
        ns.CDMSetup.ResetDismissed()
        print("|cff00ccffArcUI|r: Alert reset. Checking...")
        ns.CDMSetup.RunCheck(false, true)
    else
        print("|cff00ccffArcUI CDM Setup:|r")
        print("  /arcsetup - Check CDM requirements (shows alert)")
        print("  /arcsetup fix - Fix CDM settings")
        print("  /arcsetup status - Show current status")
        print("  /arcsetup 1 - Reset alert and show again")
    end
end