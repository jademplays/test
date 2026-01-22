-- ===================================================================
-- ArcUI_Options.lua  
-- Main Options registration for Arc UI
-- ===================================================================

local ADDON, ns = ...
ns.Options = ns.Options or {}

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDB = LibStub("AceDB-3.0")

-- ===================================================================
-- ADDON INFO
-- ===================================================================
-- Get version from TOC file (auto-updates when TOC changes)
local function GetAddonVersion()
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(ADDON, "Version") or "Unknown"
  elseif GetAddOnMetadata then
    return GetAddOnMetadata(ADDON, "Version") or "Unknown"
  end
  return "Unknown"
end

ns.AddonInfo = {
  Version = GetAddonVersion(),
  Discord = "https://discord.gg/yMZmnFjUTd",
  Author = "Arc",
}

-- ===================================================================
-- MAIN OPTIONS TABLE
-- ===================================================================
local function GetOptionsTable()
  local optionsTable = {
    type = "group",
    name = "Arc UI",
    childGroups = "tab",
    args = {
      icons = {
        type = "group",
        name = "Icons (CDM)",
        order = 1,
        childGroups = "tab",
        args = {
          groups = (function()
            local tbl = ns.GetCDMGroupsOptionsTable and ns.GetCDMGroupsOptionsTable() or {
              type = "group",
              name = "Groups",
              args = { loading = { type = "description", name = "Loading...", order = 1 } }
            }
            tbl.name = "Groups"
            tbl.order = 1
            return tbl
          end)(),
          
          cdmIcons = (function()
            local tbl = ns.GetCDMIconsOptionsTable and ns.GetCDMIconsOptionsTable() or {
              type = "group",
              name = "CDM Icons",
              args = { loading = { type = "description", name = "Loading...", order = 1 } }
            }
            tbl.name = "CDM Icons"
            tbl.order = 2
            return tbl
          end)(),
          
          defaults = {
            type = "group",
            name = "Defaults",
            order = 3,
            childGroups = "tab",
            args = {
              auraDefaults = (function()
                local tbl = ns.GetCDMGlobalAuraDefaultsOptionsTable and ns.GetCDMGlobalAuraDefaultsOptionsTable() or {
                  type = "group",
                  name = "Aura Defaults",
                  args = { loading = { type = "description", name = "Loading...", order = 1 } }
                }
                tbl.name = "Aura Defaults"
                tbl.order = 1
                return tbl
              end)(),
              
              cooldownDefaults = (function()
                local tbl = ns.GetCDMGlobalCooldownDefaultsOptionsTable and ns.GetCDMGlobalCooldownDefaultsOptionsTable() or {
                  type = "group",
                  name = "Cooldown Defaults",
                  args = { loading = { type = "description", name = "Loading...", order = 1 } }
                }
                tbl.name = "Cooldown Defaults"
                tbl.order = 2
                return tbl
              end)(),
            },
          },
          
          -- Profile Manager tab
          importExport = (function()
            local tbl = ns.GetCDMImportExportOptionsTable and ns.GetCDMImportExportOptionsTable() or {
              type = "group",
              name = "Profile Manager",
              args = { loading = { type = "description", name = "Loading...", order = 1 } }
            }
            tbl.name = "Profile Manager"
            tbl.order = 4
            return tbl
          end)(),
          
          -- Arc Auras tab (Custom Item Tracking)
          arcAuras = (function()
            local tbl = ns.GetArcAurasOptionsTable and ns.GetArcAurasOptionsTable() or {
              type = "group",
              name = "Arc Auras",
              args = { loading = { type = "description", name = "Loading...", order = 1 } }
            }
            tbl.name = "Arc Auras"
            tbl.order = 5
            return tbl
          end)(),
        },
      },
      
      bars = {
        type = "group",
        name = "Bars",
        order = 2,
        childGroups = "tab",
        args = {
          auraBars = ns.TrackingOptions and ns.TrackingOptions.GetBuffDebuffSetupTable() or {
            type = "group",
            name = "Aura Bars",
            order = 1,
            args = { loading = { type = "description", name = "Loading...", order = 1 } }
          },
          
          cooldownBars = (function()
            local tbl = ns.CooldownBarOptions and ns.CooldownBarOptions.GetOptionsTable() or {
              type = "group",
              name = "Cooldown Bars",
              args = { loading = { type = "description", name = "Loading...", order = 1 } }
            }
            tbl.name = "Cooldown Bars"
            tbl.order = 2
            return tbl
          end)(),
          
          appearance = (function()
            local tbl = ns.AppearanceOptions and ns.AppearanceOptions.GetOptionsTable() or {
              type = "group",
              name = "Appearance",
              args = { loading = { type = "description", name = "Loading...", order = 1 } }
            }
            tbl.name = "Appearance"
            tbl.order = 3
            return tbl
          end)(),
          
          importExport = (function()
            local tbl = ns.GetBarsImportExportOptionsTable and ns.GetBarsImportExportOptionsTable() or {
              type = "group",
              name = "Import/Export",
              args = { loading = { type = "description", name = "Loading...", order = 1 } }
            }
            tbl.name = "Import/Export"
            tbl.order = 4
            return tbl
          end)(),
        },
      },
      
      resources = (function()
        local tbl = ns.TrackingOptions and ns.TrackingOptions.GetResourceSetupTable() or {
          type = "group",
          name = "Resources",
          args = { loading = { type = "description", name = "Loading...", order = 1 } }
        }
        tbl.name = "Resources"
        tbl.order = 3
        return tbl
      end)(),
      
      settings = {
        type = "group",
        name = "Settings",
        order = 4,
        args = {
          menuHeader = {
            type = "header",
            name = "Background",
            order = 1
          },
          menuBackgroundAlpha = {
            type = "range",
            name = "Menu Background Solidity",
            desc = "Control how solid/opaque the options panel background is (0 = see-through, 1 = fully solid dark background)",
            order = 2,
            min = 0,
            max = 1,
            step = 0.05,
            isPercent = true,
            width = 1.5,
            get = function()
              local globalDB = ns.API.GetGlobalDB and ns.API.GetGlobalDB()
              return globalDB and globalDB.menuBackgroundAlpha or 1.0
            end,
            set = function(_, val)
              local globalDB = ns.API.GetGlobalDB and ns.API.GetGlobalDB()
              if globalDB then
                globalDB.menuBackgroundAlpha = val
                local widget = AceConfigDialog.OpenFrames["ArcUI"]
                if widget and widget.frame and widget.frame._arcUISolidBgFrame then
                  widget.frame._arcUISolidBgFrame:SetAlpha(val)
                end
              end
            end,
          },
          
          minimapHeader = {
            type = "header",
            name = "Minimap",
            order = 10
          },
          minimapButton = {
            type = "toggle",
            name = "Show Minimap Button",
            desc = "Toggle the minimap button visibility",
            order = 11,
            width = 1.5,
            get = function()
              local globalDB = ns.API.GetGlobalDB and ns.API.GetGlobalDB()
              return globalDB and not globalDB.minimap.hide
            end,
            set = function(_, val)
              local globalDB = ns.API.GetGlobalDB and ns.API.GetGlobalDB()
              if globalDB then
                globalDB.minimap.hide = not val
                if val then
                  ns.API.ShowMinimapButton()
                else
                  ns.API.HideMinimapButton()
                end
              end
            end,
          },
          
          aboutHeader = {
            type = "header",
            name = "About",
            order = 90
          },
          version = {
            type = "input",
            name = "Version",
            order = 91,
            width = 1.0,
            dialogControl = "SFX-Info",
            get = function() return ns.AddonInfo.Version end,
            set = function() end,
          },
          author = {
            type = "input",
            name = "Author",
            order = 92,
            width = 1.0,
            dialogControl = "SFX-Info",
            get = function() return ns.AddonInfo.Author end,
            set = function() end,
          },
        },
      },
    },
  }
  
  return optionsTable
end

-- ===================================================================
-- DISCORD LINK BUTTON
-- ===================================================================
local function CreateDiscordLink(parentFrame)
  if parentFrame._arcUIDiscordLink then return end
  
  local container = CreateFrame("Frame", nil, parentFrame)
  container:SetSize(200, 20)
  container:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -10, -8)
  
  local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("RIGHT", container, "RIGHT", 0, 0)
  label:SetText("|cff5865F2Discord:|r |cff7289DA" .. ns.AddonInfo.Discord .. "|r")
  
  local link = CreateFrame("EditBox", nil, container)
  link:SetSize(200, 20)
  link:SetPoint("RIGHT", container, "RIGHT", 0, 0)
  link:SetFontObject(GameFontNormal)
  link:SetAutoFocus(false)
  link:EnableMouse(true)
  link:SetText(ns.AddonInfo.Discord)
  link:SetCursorPosition(0)
  link:Hide()
  
  container:EnableMouse(true)
  container:SetScript("OnEnter", function(self)
    label:SetText("|cff5865F2Discord:|r |cffffffffClick to copy|r")
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Click to copy Discord link", 1, 1, 1)
    GameTooltip:Show()
  end)
  container:SetScript("OnLeave", function(self)
    label:SetText("|cff5865F2Discord:|r |cff7289DA" .. ns.AddonInfo.Discord .. "|r")
    GameTooltip:Hide()
  end)
  container:SetScript("OnMouseDown", function(self)
    link:Show()
    link:SetFocus()
    link:HighlightText()
    label:Hide()
  end)
  
  link:SetScript("OnEditFocusLost", function(self)
    self:Hide()
    label:Show()
  end)
  link:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  link:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
  end)
  
  parentFrame._arcUIDiscordLink = container
end

-- ===================================================================
-- OPTIONS REGISTRATION
-- ===================================================================
local function RegisterOptions()
  AceConfig:RegisterOptionsTable("ArcUI", GetOptionsTable)
  AceConfigDialog:SetDefaultSize("ArcUI", 900, 700)
  
  ns.API.OpenOptions = function()
    -- Prevent opening options during combat, but queue for when combat ends
    if InCombatLockdown() then
      ns._arcPendingOptionsOpen = true
      print("|cff00ccffArc UI|r Options will open when combat ends.")
      return
    end
    
    -- Clear any pending flag
    ns._arcPendingOptionsOpen = nil
    
    AceConfigDialog:Open("ArcUI")
    
    C_Timer.After(0.05, function()
      local widget = AceConfigDialog.OpenFrames["ArcUI"]
      if widget and widget.frame then
        local actualFrame = widget.frame
        local globalDB = ns.API.GetGlobalDB and ns.API.GetGlobalDB()
        local alpha = globalDB and globalDB.menuBackgroundAlpha or 1.0
        
        -- Create solid background
        if not actualFrame._arcUISolidBgFrame then
          actualFrame._arcUISolidBgFrame = CreateFrame("Frame", nil, actualFrame)
          actualFrame._arcUISolidBgFrame:SetPoint("TOPLEFT", actualFrame, "TOPLEFT", 8, -8)
          actualFrame._arcUISolidBgFrame:SetPoint("BOTTOMRIGHT", actualFrame, "BOTTOMRIGHT", -8, 8)
          actualFrame._arcUISolidBgFrame:SetFrameLevel(math.max(1, actualFrame:GetFrameLevel() - 1))
          
          actualFrame._arcUISolidBgFrame.tex = actualFrame._arcUISolidBgFrame:CreateTexture(nil, "BACKGROUND")
          actualFrame._arcUISolidBgFrame.tex:SetAllPoints()
          actualFrame._arcUISolidBgFrame.tex:SetColorTexture(0.02, 0.02, 0.02, 1)
        end
        
        actualFrame._arcUISolidBgFrame:SetAlpha(alpha)
        actualFrame._arcUISolidBgFrame:Show()
        
        -- Create Discord link at top right (or show existing one)
        CreateDiscordLink(actualFrame)
        if actualFrame._arcUIDiscordLink then
          actualFrame._arcUIDiscordLink:Show()
        end
        
        -- Hook OnHide
        if not actualFrame._arcUIOnHideHooked then
          actualFrame._arcUIOnHideHooked = true
          local originalOnHide = actualFrame:GetScript("OnHide")
          actualFrame:SetScript("OnHide", function(self, ...)
            if originalOnHide then originalOnHide(self, ...) end
            
            -- CRITICAL: Hide Discord link when panel closes
            -- AceConfigDialog reuses frame objects, so our Discord link would
            -- appear on other addons' config panels if we don't hide it
            if self._arcUIDiscordLink then
              self._arcUIDiscordLink:Hide()
            end
            if self._arcUISolidBgFrame then
              self._arcUISolidBgFrame:Hide()
            end
            
            if ns.Display and ns.Display.HideDeleteButtons then
              ns.Display.HideDeleteButtons()
            end
            if ns.Resources and ns.Resources.HideDeleteButtons then
              ns.Resources.HideDeleteButtons()
            end
            if ns.CDMEnhance and ns.CDMEnhance.SetUnlocked then
              ns.CDMEnhance.SetUnlocked(false)
            end
            if ns.CDMGroups and ns.CDMGroups.SetDragMode then
              ns.CDMGroups.SetDragMode(false)
            end
            
            C_Timer.After(0.1, function()
              if ns.API.ValidateAllBarTracking then
                ns.API.ValidateAllBarTracking()
              end
            end)
          end)
        end
      end
      
      if ns.API.ValidateAllBarTracking then
        ns.API.ValidateAllBarTracking()
      end
    end)
  end
end

-- ===================================================================
-- SLASH COMMANDS
-- ===================================================================
SLASH_ARCBARS1 = "/arcbars"
SLASH_ARCBARS2 = "/ab"
SLASH_ARCBARS3 = "/arcui"
SLASH_ARCBARS4 = "/aui"
SlashCmdList["ARCBARS"] = function(msg)
  msg = msg:lower():trim()
  
  if msg == "" or msg == "options" or msg == "config" then
    ns.API.OpenOptions()
  elseif msg == "scan" then
    local buffs, err = ns.API.ScanAvailableBuffs()
    if buffs then
      print("|cff00ccffArc UI|r Found " .. #buffs .. " buff(s)/debuff(s). Open options to configure.")
    else
      print("|cff00ccffArc UI|r Error: " .. (err or "Unknown"))
    end
  elseif msg == "unlock" or msg == "drag" then
    if ns.CDMGroups and ns.CDMGroups.ToggleDragMode then
      ns.CDMGroups.ToggleDragMode()
      if ns.CDMGroups.dragModeEnabled then
        print("|cff00ccffArc UI|r Edit mode |cff00ff00ENABLED|r - drag icons to reposition")
      else
        print("|cff00ccffArc UI|r Edit mode |cffff0000DISABLED|r")
      end
    elseif ns.CDMEnhance and ns.CDMEnhance.ToggleUnlock then
      ns.CDMEnhance.ToggleUnlock()
    else
      print("|cff00ccffArc UI|r CDM module not loaded yet")
    end
  elseif msg == "layout" then
    if ns.LayoutEditor and ns.LayoutEditor.Toggle then
      ns.LayoutEditor.Toggle()
    end
  elseif msg == "reset" then
    local db = ns.API.GetDB()
    if db then
      for i = 1, 30 do
        if db.bars and db.bars[i] then
          db.bars[i].display.barPosition = {point="CENTER", relPoint="CENTER", x=0, y=200-(i-1)*30}
          db.bars[i].display.textPosition = {point="CENTER", relPoint="CENTER", x=0, y=230-(i-1)*30}
        end
        if db.resourceBars and db.resourceBars[i] then
          db.resourceBars[i].display.barPosition = {point="CENTER", relPoint="CENTER", x=0, y=-100-(i-1)*35}
          db.resourceBars[i].display.textPosition = {point="CENTER", relPoint="CENTER", x=0, y=-70-(i-1)*35}
        end
      end
      for i = 1, 30 do
        if ns.Display and ns.Display.ApplyAppearance then
          ns.Display.ApplyAppearance(i)
        end
        if ns.Resources and ns.Resources.ApplyAppearance then
          ns.Resources.ApplyAppearance(i)
        end
      end
      print("|cff00ccffArc UI|r Positions reset")
    end
  elseif msg == "minimap" then
    local globalDB = ns.API.GetGlobalDB()
    if globalDB then
      globalDB.minimap.hide = not globalDB.minimap.hide
      if globalDB.minimap.hide then
        ns.API.HideMinimapButton()
        print("|cff00ccffArc UI|r Minimap button hidden")
      else
        ns.API.ShowMinimapButton()
        print("|cff00ccffArc UI|r Minimap button shown")
      end
    end
  elseif msg == "export" then
    -- Quick export shortcut
    if ns.API and ns.API.OpenOptions then
      ns.API.OpenOptions()
      C_Timer.After(0.1, function()
        AceConfigDialog:SelectGroup("ArcUI", "icons", "importExport")
      end)
    end
  elseif msg == "import" then
    -- Quick import shortcut
    if ns.API and ns.API.OpenOptions then
      ns.API.OpenOptions()
      C_Timer.After(0.1, function()
        AceConfigDialog:SelectGroup("ArcUI", "icons", "importExport")
      end)
    end
  elseif msg == "help" then
    print("|cff00ccffArc UI|r Commands:")
    print("  /arcui - Open options")
    print("  /arcui scan - Scan for buffs/debuffs")
    print("  /arcui drag - Toggle icon group editing")
    print("  /arcui reset - Reset bar positions")
    print("  /arcui minimap - Toggle minimap button")
    print("  /arcui export - Open import/export panel")
    print("  /arcui import - Open import/export panel")
  else
    print("|cff00ccffArc UI|r Unknown command. Use /arcui help")
  end
end

-- ===================================================================
-- MAIN INITIALIZATION
-- ===================================================================
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

initFrame:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_REGEN_DISABLED" then
    -- Close options panel when entering combat
    local widget = AceConfigDialog.OpenFrames["ArcUI"]
    if widget then
      AceConfigDialog:Close("ArcUI")
      print("|cff00ccffArc UI|r Options closed - entering combat.")
    end
    return
  end
  
  if event == "PLAYER_REGEN_ENABLED" then
    -- Open options panel if user tried to open during combat
    if ns._arcPendingOptionsOpen then
      ns._arcPendingOptionsOpen = nil
      C_Timer.After(0.1, function()
        if not InCombatLockdown() and ns.API.OpenOptions then
          ns.API.OpenOptions()
        end
      end)
    end
    return
  end
  
  if event == "PLAYER_LOGIN" then
    ns.db = AceDB:New("ArcUIDB", ns.DB_DEFAULTS, true)
    
    -- ═══════════════════════════════════════════════════════════════════
    -- FIX SPARSE ARRAYS: Fill holes in resourceBars/cooldownBars after DB load
    -- Prevents ipairs() from stopping early due to nil at index 1
    -- ═══════════════════════════════════════════════════════════════════
    if ns.db and ns.db.char then
      -- Fix resourceBars
      if ns.db.char.resourceBars then
        local resourceBars = ns.db.char.resourceBars
        local maxIndex = 0
        for k, v in pairs(resourceBars) do
          if type(k) == "number" and k >= 1 and math.floor(k) == k then
            if k > maxIndex then maxIndex = k end
          end
        end
        for i = 1, maxIndex do
          if resourceBars[i] == nil then
            resourceBars[i] = CopyTable(ns.DB_DEFAULTS.char.resourceBars[1])
            resourceBars[i].tracking.enabled = false
            resourceBars[i].display.enabled = false
            local yOffset = -100 - ((i - 1) * 35)
            resourceBars[i].display.barPosition.y = yOffset
            resourceBars[i].display.textPosition.y = yOffset + 30
          end
        end
      end
      
      -- Fix cooldownBars
      if ns.db.char.cooldownBars then
        local cooldownBars = ns.db.char.cooldownBars
        local maxIndex = 0
        for k, v in pairs(cooldownBars) do
          if type(k) == "number" and k >= 1 and math.floor(k) == k then
            if k > maxIndex then maxIndex = k end
          end
        end
        for i = 1, maxIndex do
          if cooldownBars[i] == nil then
            cooldownBars[i] = CopyTable(ns.DB_DEFAULTS.char.cooldownBars[1])
            cooldownBars[i].tracking.enabled = false
            cooldownBars[i].display.enabled = false
            local yOffset = -200 - ((i - 1) * 30)
            cooldownBars[i].display.barPosition.y = yOffset
            cooldownBars[i].display.textPosition.y = yOffset + 30
            cooldownBars[i].display.iconPosition.y = yOffset
          end
        end
      end
    end
    
    C_Timer.After(0.1, function()
      RegisterOptions()
      
      if ns.Options.InitMinimapButton then
        ns.Options.InitMinimapButton()
      end
      if ns.Display and ns.Display.Init then
        ns.Display.Init()
      end
      if ns.Resources and ns.Resources.Init then
        ns.Resources.Init()
      end
      if ns.CooldownBars and ns.CooldownBars.Init then
        ns.CooldownBars.Init()
      end
      if ns.CustomTracking and ns.CustomTracking.Init then
        ns.CustomTracking.Init()
      end
      
      print("|cff00ccffArc UI|r v" .. ns.AddonInfo.Version .. " loaded. Type /arcui for options.")
    end)
  end
end)