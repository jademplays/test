-- ===================================================================
-- ArcUI_CooldownBars.lua
-- v3.0.0: Spell Catalog + Bar Type Tracking
-- Step 1: Catalog system only - bar rendering added later
-- ===================================================================

local ADDON, ns = ...
ns.CooldownBars = ns.CooldownBars or {}

-- ===================================================================
-- DEBUG LOGGING
-- ===================================================================
ns.CooldownBars.debugLog = {}
ns.CooldownBars.maxLogLines = 100

local function SafeToString(val)
  if val == nil then return "nil" end
  if issecretvalue and issecretvalue(val) then return "** SECRET **" end
  local ok, str = pcall(tostring, val)
  return ok and str or "** ERROR **"
end

local function Log(msg)
  local safeMsg = SafeToString(msg)
  table.insert(ns.CooldownBars.debugLog, date("%H:%M:%S") .. " " .. safeMsg)
  if #ns.CooldownBars.debugLog > ns.CooldownBars.maxLogLines then
    table.remove(ns.CooldownBars.debugLog, 1)
  end
end
ns.CooldownBars.Log = Log

-- ===================================================================
-- DATABASE DEFAULTS (merged into ArcUI's defaults)
-- ===================================================================
ns.CooldownBars.dbDefaults = {
  -- Active bars (saved as lists of spellIDs)
  cooldownBars = {},      -- { spellID1, spellID2, ... } Duration bars
  chargeBars = {},        -- { spellID1, spellID2, ... } Charge bars
  resourceBars = {},      -- { [spellID] = true or customMax } Resource bars
  -- Manually added spells (not from scan)
  manualSpells = {},      -- { spellID1, spellID2, ... }
  -- Removed/hidden spells (excluded from scan)
  hiddenSpells = {},      -- { [spellID] = true }
  -- Per-bar settings
  barSettings = {},       -- { [spellID] = { color, thresholds, etc } }
}

-- ===================================================================
-- SPELL CATALOG (matches CDT.config.testSpells structure)
-- ===================================================================
ns.CooldownBars.spellCatalog = {}

-- Active bar tracking (spellID -> barIndex)
ns.CooldownBars.activeCooldowns = {}  -- Duration bars
ns.CooldownBars.activeCharges = {}    -- Charge bars
ns.CooldownBars.activeResources = {}  -- Resource bars

-- ===================================================================
-- DATABASE ACCESS HELPERS
-- ===================================================================
local function GetDB()
  -- ns.db is set by ArcUI_DB.lua after AceDB initializes
  -- Store our data in char.cooldownBarSetup (separate from existing cooldownBars structure)
  if ns.db and ns.db.char then
    if not ns.db.char.cooldownBarSetup then
      ns.db.char.cooldownBarSetup = {}
    end
    return ns.db.char.cooldownBarSetup
  end
  return nil
end

local function EnsureDBStructure()
  local db = GetDB()
  if not db then return end
  
  db.activeCooldowns = db.activeCooldowns or {}
  db.activeCharges = db.activeCharges or {}
  db.activeResources = db.activeResources or {}
  db.manualSpells = db.manualSpells or {}
  db.hiddenSpells = db.hiddenSpells or {}
end

-- ===================================================================
-- SPELL EXCLUSIONS (matches CDT)
-- ===================================================================
local EXCLUDED_SPELLS = {
  -- Dragonriding/Skyriding
  [372608] = true, [361584] = true, [372610] = true, [358267] = true,
  [361469] = true, [404468] = true,
  -- Generic/Utility
  [125439] = true, [6603] = true,
  -- DH Passive Talents
  [339924] = true, [320415] = true, [258881] = true, [206416] = true,
  [258876] = true, [258860] = true, [343311] = true, [347461] = true,
  [388114] = true, [389694] = true, [390163] = true, [442688] = true,
  [388116] = true, [382197] = true,
}

local RACIAL_SPELLS = {
  [58984] = true, [20594] = true, [20589] = true, [59752] = true,
  [7744] = true, [255654] = true, [312411] = true,
}

local function ShouldExclude(spellID, spellName)
  if EXCLUDED_SPELLS[spellID] then return true end
  if RACIAL_SPELLS[spellID] then return true end
  if not spellName then return true end
  
  -- Check user-hidden spells from database
  local db = GetDB()
  if db and db.hiddenSpells and db.hiddenSpells[spellID] then
    return true
  end
  
  local lowerName = spellName:lower()
  if lowerName:find("passive") then return true end
  if lowerName:find("dragonriding") or lowerName:find("skyriding") then return true end
  if lowerName:find("skyward") or lowerName:find("surge forward") then return true end
  if lowerName:find("whirling") or lowerName:find("bronze timelock") then return true end
  if lowerName:find("aerial halt") then return true end
  if lowerName:find("battle pet") or lowerName:find("revive pet") then return true end
  
  return false
end

-- ===================================================================
-- SCAN SPELLBOOK (matches CDT.ScanSpellbook)
-- ===================================================================
function ns.CooldownBars.ScanPlayerSpells()
  wipe(ns.CooldownBars.spellCatalog)
  
  if InCombatLockdown() then
    Log("Cannot scan during combat")
    return 0
  end
  
  Log("=== Starting Spell Scan ===")
  
  local seenSpellIDs = {}
  
  -- Helper to add a spell
  local function AddSpell(spellID, source)
    if not spellID or spellID == 0 then return end
    if seenSpellIDs[spellID] then return end
    
    local spellName = C_Spell.GetSpellName(spellID)
    if not spellName then return end
    
    -- Skip passives
    if C_Spell.IsSpellPassive(spellID) then
      Log("  PASSIVE: " .. spellName .. " (ID:" .. spellID .. ")")
      return
    end
    
    -- Check subtext for "Passive"
    local subtext = C_Spell.GetSpellSubtext(spellID)
    if subtext and subtext:lower():find("passive") then
      Log("  PASSIVE SUBTEXT: " .. spellName .. " (ID:" .. spellID .. ")")
      return
    end
    
    -- Skip excluded spells
    if ShouldExclude(spellID, spellName) then
      Log("  EXCLUDED: " .. spellName .. " (ID:" .. spellID .. ")")
      return
    end
    
    -- Check if spell has info
    local spellInfo = C_Spell.GetSpellInfo(spellID)
    if not spellInfo then
      Log("  NO INFO: " .. spellName .. " (ID:" .. spellID .. ")")
      return
    end
    
    -- Check for charges - chargeInfo being non-nil means it's a charge spell
    -- NOTE: chargeInfo.maxCharges can be SECRET in WoW 12.0, use nil check for hasCharges
    local chargeInfo = C_Spell.GetSpellCharges(spellID)
    local hasCharges = (chargeInfo ~= nil)  -- Table exists = charge spell
    local maxCharges = 0
    
    if hasCharges and chargeInfo.maxCharges then
      -- Only read actual value if NOT secret
      if not issecretvalue or not issecretvalue(chargeInfo.maxCharges) then
        maxCharges = chargeInfo.maxCharges
      else
        -- Secret value - still a charge spell, just can't get count yet
        Log("  SECRET maxCharges (still charge spell): " .. spellName .. " (ID:" .. spellID .. ")")
        maxCharges = 2  -- Default assumption for charge spells
      end
    end
    
    -- Check if it has cooldown API
    local hasCooldown = true
    if not hasCharges then
      local cdInfo = C_Spell.GetSpellCooldown(spellID)
      if not cdInfo then
        Log("  NO COOLDOWN API: " .. spellName .. " (ID:" .. spellID .. ")")
        hasCooldown = false
      end
    end
    
    -- Check if it's a talent spell
    local isTalent = false
    pcall(function()
      isTalent = C_Spell.IsClassTalentSpell(spellID) or C_Spell.IsPvPTalentSpell(spellID)
    end)
    
    -- Check for resource cost
    local costInfo = C_Spell.GetSpellPowerCost(spellID)
    local hasResourceCost = costInfo and #costInfo > 0
    local resourceCost = 0
    local resourceType = nil
    local resourceName = nil
    if hasResourceCost then
      resourceCost = costInfo[1].cost or costInfo[1].minCost or 0
      resourceType = costInfo[1].type
      resourceName = costInfo[1].name
    end
    
    -- Get texture
    local texture = C_Spell.GetSpellTexture(spellID) or 134400
    
    seenSpellIDs[spellID] = true
    
    table.insert(ns.CooldownBars.spellCatalog, {
      spellID = spellID,
      name = spellName,
      texture = texture,
      hasCharges = hasCharges,
      maxCharges = maxCharges,
      hasCooldown = hasCooldown,
      hasResourceCost = hasResourceCost,
      resourceCost = resourceCost,
      resourceType = resourceType,
      resourceName = resourceName,
      source = source,
      isTalent = isTalent,
    })
    
    local chargeStr = hasCharges and ("charges=" .. maxCharges) or ""
    local resStr = hasResourceCost and (" res=" .. resourceCost) or ""
    Log(string.format("  + %s (ID:%d) %s%s [%s]",
      spellName, spellID, chargeStr, resStr, source))
  end
  
  -- SOURCE 1: CDM Cooldown Categories (Essential + Utility)
  Log("-- Scanning CDM Categories --")
  if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet then
    for category = 0, 1 do
      local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(category, false)
      if cooldownIDs then
        for _, cdID in ipairs(cooldownIDs) do
          local cdInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
          if cdInfo and cdInfo.spellID then
            AddSpell(cdInfo.spellID, category == 0 and "Essential" or "Utility")
          end
        end
      end
    end
  end
  
  -- SOURCE 2: Action Bars
  Log("-- Scanning Action Bars --")
  for slot = 1, 180 do
    local actionType, id = GetActionInfo(slot)
    if actionType == "spell" and id then
      AddSpell(id, "ActionBar")
    elseif actionType == "macro" then
      local spellID = GetMacroSpell(id)
      if spellID then
        AddSpell(spellID, "Macro")
      end
    end
  end
  
  -- SOURCE 3: Talent Tree
  Log("-- Scanning Talent Tree --")
  if C_ClassTalents and C_Traits then
    local configID = C_ClassTalents.GetActiveConfigID()
    if configID then
      local specID = GetSpecializationInfo(GetSpecialization() or 1)
      local treeID = specID and C_ClassTalents.GetTraitTreeForSpec(specID)
      
      if treeID then
        local nodeIDs = C_Traits.GetTreeNodes(treeID)
        if nodeIDs then
          for _, nodeID in ipairs(nodeIDs) do
            local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
            if nodeInfo and nodeInfo.activeRank and nodeInfo.activeRank > 0 then
              local activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
              if activeEntryID then
                local entryInfo = C_Traits.GetEntryInfo(configID, activeEntryID)
                if entryInfo and entryInfo.definitionID then
                  local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                  if defInfo and defInfo.spellID then
                    AddSpell(defInfo.spellID, "Talent")
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  
  -- SOURCE 4: Spellbook
  Log("-- Scanning Spellbook --")
  local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines()
  
  for skillIndex = 1, numSkillLines do
    local skillInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillIndex)
    if skillInfo then
      local isGeneral = skillInfo.name == "General"
      if not skillInfo.isGuild and not skillInfo.shouldHide and not isGeneral then
        if skillInfo.specID ~= nil or skillInfo.offSpecID == nil then
          local startIndex = skillInfo.itemIndexOffset + 1
          local endIndex = startIndex + skillInfo.numSpellBookItems - 1
          
          for i = startIndex, endIndex do
            local spellBookItemInfo = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
            if spellBookItemInfo then
              local spellID = spellBookItemInfo.actionID or spellBookItemInfo.spellID
              if spellID and not spellBookItemInfo.isPassive and not spellBookItemInfo.isOffSpec then
                AddSpell(spellID, "Spellbook")
              end
            end
          end
        end
      end
    end
  end
  
  -- Sort: charges first, then talent spells, then alphabetically
  table.sort(ns.CooldownBars.spellCatalog, function(a, b)
    if a.hasCharges ~= b.hasCharges then
      return a.hasCharges
    end
    if a.isTalent ~= b.isTalent then
      return a.isTalent
    end
    return (a.name or "") < (b.name or "")
  end)
  
  Log("=== Scan Complete: " .. #ns.CooldownBars.spellCatalog .. " spells ===")
  
  return #ns.CooldownBars.spellCatalog
end

-- ===================================================================
-- CATALOG HELPERS (used by Options panel)
-- ===================================================================
function ns.CooldownBars.GetSpellData(spellID)
  for _, data in ipairs(ns.CooldownBars.spellCatalog) do
    if data.spellID == spellID then
      return data
    end
  end
  return nil
end

-- Add a spell by ID manually (user input)
function ns.CooldownBars.AddSpellByID(spellID)
  if not spellID then
    return false, "No spell ID provided"
  end
  
  -- Check if already in catalog
  for _, data in ipairs(ns.CooldownBars.spellCatalog) do
    if data.spellID == spellID then
      return true, data.name  -- Already exists, return success
    end
  end
  
  -- Validate spell exists
  local spellName = C_Spell.GetSpellName(spellID)
  if not spellName then
    return false, "Spell not found"
  end
  
  -- Get spell info
  local spellInfo = C_Spell.GetSpellInfo(spellID)
  if not spellInfo then
    return false, "Cannot get spell info"
  end
  
  -- Check for charges - chargeInfo being non-nil means it's a charge spell
  local chargeInfo = C_Spell.GetSpellCharges(spellID)
  local hasCharges = (chargeInfo ~= nil)
  local maxCharges = 0
  
  if hasCharges and chargeInfo.maxCharges then
    -- Only read actual value if NOT secret
    if not issecretvalue or not issecretvalue(chargeInfo.maxCharges) then
      maxCharges = chargeInfo.maxCharges
    else
      maxCharges = 2  -- Default assumption for charge spells
    end
  end
  
  -- Check for cooldown
  local hasCooldown = true
  if not hasCharges then
    local cdInfo = C_Spell.GetSpellCooldown(spellID)
    if not cdInfo then
      hasCooldown = false
    end
  end
  
  -- Check for resource cost
  local costInfo = C_Spell.GetSpellPowerCost(spellID)
  local hasResourceCost = costInfo and #costInfo > 0
  local resourceCost = 0
  local resourceType = nil
  local resourceName = nil
  if hasResourceCost then
    resourceCost = costInfo[1].cost or costInfo[1].minCost or 0
    resourceType = costInfo[1].type
    resourceName = costInfo[1].name
  end
  
  -- Check if talent
  local isTalent = false
  pcall(function()
    isTalent = C_Spell.IsClassTalentSpell(spellID) or C_Spell.IsPvPTalentSpell(spellID)
  end)
  
  -- Get texture
  local texture = C_Spell.GetSpellTexture(spellID) or 134400
  
  -- Add to catalog
  table.insert(ns.CooldownBars.spellCatalog, {
    spellID = spellID,
    name = spellName,
    texture = texture,
    hasCharges = hasCharges,
    maxCharges = maxCharges,
    hasCooldown = hasCooldown,
    hasResourceCost = hasResourceCost,
    resourceCost = resourceCost,
    resourceType = resourceType,
    resourceName = resourceName,
    source = "Manual",
    isTalent = isTalent,
  })
  
  Log("Manually added: " .. spellName .. " (ID:" .. spellID .. ")")
  
  -- Save to database
  ns.CooldownBars.SaveBarConfig()
  
  return true, spellName
end

-- Remove a spell from the catalog (and hide from future scans)
function ns.CooldownBars.RemoveSpellByID(spellID, permanent)
  if not spellID then
    return false, "No spell ID provided"
  end
  
  -- Find and remove from catalog
  local removed = false
  local removedName = nil
  for i = #ns.CooldownBars.spellCatalog, 1, -1 do
    if ns.CooldownBars.spellCatalog[i].spellID == spellID then
      removedName = ns.CooldownBars.spellCatalog[i].name
      table.remove(ns.CooldownBars.spellCatalog, i)
      removed = true
      break
    end
  end
  
  if not removed then
    return false, "Spell not in catalog"
  end
  
  -- Also remove any active bars for this spell
  if ns.CooldownBars.activeCooldowns[spellID] then
    ns.CooldownBars.activeCooldowns[spellID] = nil
    Log("Removed cooldown bar for: " .. (removedName or spellID))
  end
  if ns.CooldownBars.activeResources[spellID] then
    ns.CooldownBars.activeResources[spellID] = nil
    Log("Removed resource bar for: " .. (removedName or spellID))
  end
  if ns.CooldownBars.activeCharges[spellID] then
    ns.CooldownBars.activeCharges[spellID] = nil
    Log("Removed charge bar for: " .. (removedName or spellID))
  end
  
  -- Add to hidden spells so it won't come back on rescan (default behavior)
  if permanent ~= false then
    local db = GetDB()
    if db then
      EnsureDBStructure()
      db.hiddenSpells[spellID] = true
      Log("Added to hidden spells: " .. (removedName or spellID))
    end
  end
  
  Log("Removed from catalog: " .. (removedName or spellID) .. " (ID:" .. spellID .. ")")
  
  -- Save to database
  ns.CooldownBars.SaveBarConfig()
  
  return true, removedName
end

-- Unhide a spell (allow it to be scanned again)
function ns.CooldownBars.UnhideSpellByID(spellID)
  if not spellID then
    return false, "No spell ID provided"
  end
  
  local db = GetDB()
  if db and db.hiddenSpells then
    db.hiddenSpells[spellID] = nil
    Log("Unhid spell: " .. spellID)
    return true
  end
  return false, "No database"
end

-- Get list of hidden spells
function ns.CooldownBars.GetHiddenSpells()
  local result = {}
  local db = GetDB()
  if db and db.hiddenSpells then
    for spellID in pairs(db.hiddenSpells) do
      local name = C_Spell.GetSpellName(spellID) or "Unknown"
      table.insert(result, { spellID = spellID, name = name })
    end
  end
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

function ns.CooldownBars.FilterCatalog(searchText, filterType)
  local results = {}
  local lower = searchText and searchText:lower() or ""
  
  for _, data in ipairs(ns.CooldownBars.spellCatalog) do
    local matchesSearch = (lower == "" or (data.name and data.name:lower():find(lower, 1, true)))
    local matchesFilter = true
    
    if filterType == "cooldown" then
      matchesFilter = data.hasCooldown and not data.hasCharges
    elseif filterType == "charges" then
      matchesFilter = data.hasCharges
    elseif filterType == "resource" then
      matchesFilter = data.hasResourceCost
    end
    
    if matchesSearch and matchesFilter then
      table.insert(results, data)
    end
  end
  
  return results
end

-- ===================================================================
-- BAR STATE HELPERS
-- ===================================================================
function ns.CooldownBars.GetBarStates(spellID)
  return {
    hasCooldownBar = ns.CooldownBars.activeCooldowns[spellID] ~= nil,
    hasChargeBar = ns.CooldownBars.activeCharges[spellID] ~= nil,
    hasResourceBar = ns.CooldownBars.activeResources[spellID] ~= nil,
  }
end

-- ===================================================================
-- SAVE/RESTORE BAR CONFIGURATION
-- ===================================================================
function ns.CooldownBars.SaveBarConfig()
  local db = GetDB()
  if not db then
    Log("SaveBarConfig: No database available yet")
    return
  end
  
  EnsureDBStructure()
  
  -- Save cooldown bars (duration bars)
  db.activeCooldowns = {}
  for spellID in pairs(ns.CooldownBars.activeCooldowns) do
    table.insert(db.activeCooldowns, spellID)
  end
  
  -- Save charge bars
  db.activeCharges = {}
  for spellID in pairs(ns.CooldownBars.activeCharges) do
    table.insert(db.activeCharges, spellID)
  end
  
  -- Save resource bars
  db.activeResources = {}
  for spellID in pairs(ns.CooldownBars.activeResources) do
    db.activeResources[spellID] = true
  end
  
  -- Save manually added spells
  db.manualSpells = {}
  for _, data in ipairs(ns.CooldownBars.spellCatalog) do
    if data.source == "Manual" then
      table.insert(db.manualSpells, data.spellID)
    end
  end
  
  local cdCount = #db.activeCooldowns
  local chgCount = #db.activeCharges
  local resCount = 0
  for _ in pairs(db.activeResources) do resCount = resCount + 1 end
  
  Log(string.format("Saved: %d Duration, %d Charge, %d Resource bars, %d manual spells",
    cdCount, chgCount, resCount, #db.manualSpells))
end

function ns.CooldownBars.RestoreBarConfig()
  local db = GetDB()
  if not db then
    Log("RestoreBarConfig: No database available")
    return
  end
  
  EnsureDBStructure()
  
  local restored = { cd = 0, chg = 0, res = 0, manual = 0 }
  
  -- Restore manually added spells first (so they're in catalog)
  if db.manualSpells then
    for _, spellID in ipairs(db.manualSpells) do
      local success = ns.CooldownBars.AddSpellByID(spellID)
      if success then
        restored.manual = restored.manual + 1
      end
    end
  end
  
  -- Restore ALL cooldown bars (create them regardless of spec)
  if db.activeCooldowns then
    for _, spellID in ipairs(db.activeCooldowns) do
      local spellName = C_Spell.GetSpellName(spellID)
      if spellName then
        ns.CooldownBars.AddCooldownBar(spellID)
        restored.cd = restored.cd + 1
      end
    end
  end
  
  -- Restore ALL charge bars (create them regardless of spec)
  if db.activeCharges then
    for _, spellID in ipairs(db.activeCharges) do
      local spellName = C_Spell.GetSpellName(spellID)
      if spellName then
        ns.CooldownBars.AddChargeBar(spellID)
        restored.chg = restored.chg + 1
      end
    end
  end
  
  -- Restore ALL resource bars (create them regardless of spec)
  if db.activeResources then
    for spellID in pairs(db.activeResources) do
      local spellName = C_Spell.GetSpellName(spellID)
      if spellName then
        ns.CooldownBars.AddResourceBar(spellID)
        restored.res = restored.res + 1
      end
    end
  end
  
  -- Now apply spec visibility (hides bars that shouldn't show for current spec)
  ns.CooldownBars.UpdateBarVisibilityForSpec()
  
  if restored.cd > 0 or restored.chg > 0 or restored.res > 0 then
    Log(string.format("Restored: %d Duration, %d Charge, %d Resource bars",
      restored.cd, restored.chg, restored.res))
    if ns.devMode then
      print(string.format("|cff00ff00[ArcUI CooldownBars]|r Restored: %d Duration, %d Charge, %d Resource bars",
        restored.cd, restored.chg, restored.res))
    end
  end
  
  if restored.manual > 0 then
    Log("Restored " .. restored.manual .. " manual spells to catalog")
  end
end

-- ===================================================================
-- BAR FRAME CREATION
-- ===================================================================

-- Configuration for bar layout
local BAR_CONFIG = {
  barWidth = 200,      -- Default for cooldown duration bars (ArcUI style)
  barHeight = 26,
  barSpacing = 32,
  anchorPoint = "CENTER",
  anchorX = 0,
  anchorY = 100,
}

-- Frame pools
ns.CooldownBars.bars = {}          -- Duration bars
ns.CooldownBars.chargeBars = {}    -- Charge bars
ns.CooldownBars.resourceBars = {}  -- Resource bars

-- Curves for ready state detection
local readyAlphaCurve100, onCooldownAlphaCurve, outOfChargesCurve

local function InitCurves()
  if readyAlphaCurve100 then return end
  
  -- Shows at 0% (ready) and 100% (covers charge spell animation glitch)
  readyAlphaCurve100 = C_CurveUtil.CreateCurve()
  readyAlphaCurve100:SetType(Enum.LuaCurveType.Step)
  readyAlphaCurve100:AddPoint(0, 1)
  readyAlphaCurve100:AddPoint(0.005, 0)
  readyAlphaCurve100:AddPoint(0.995, 0)
  readyAlphaCurve100:AddPoint(1, 1)
  
  -- Inverse: returns 1 when on cooldown, 0 at ready
  onCooldownAlphaCurve = C_CurveUtil.CreateCurve()
  onCooldownAlphaCurve:SetType(Enum.LuaCurveType.Step)
  onCooldownAlphaCurve:AddPoint(0, 0)
  onCooldownAlphaCurve:AddPoint(0.005, 1)
  onCooldownAlphaCurve:AddPoint(0.995, 1)
  onCooldownAlphaCurve:AddPoint(1, 0)
  
  -- For progressive charge bars: 0% remaining → show, >0% → hide
  outOfChargesCurve = C_CurveUtil.CreateCurve()
  outOfChargesCurve:AddPoint(0.0, 1)
  outOfChargesCurve:AddPoint(0.01, 0)
  outOfChargesCurve:AddPoint(1.0, 0)
end

-- ===================================================================
-- ARC DETECTOR POOL (for secret charge value → boolean conversion)
-- Uses StatusBar fill texture IsShown() to detect charge thresholds
-- Key insight: IsShown() returns true/false (NOT secret!) - works in combat!
-- ===================================================================
local arcDetectors = {}
local arcDetectorCount = 0

local function CreateArcDetector(threshold)
  local bar = CreateFrame("StatusBar", "ArcUIChargeDetector" .. threshold, UIParent)
  bar:SetSize(100, 10)
  bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -500, 500)  -- Offscreen
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(1, 1, 1, 1)
  bar:SetAlpha(0)  -- Invisible but SHOWN
  bar:Show()       -- MUST be shown for fill IsShown() to work!
  bar:SetMinMaxValues(threshold - 1, threshold)  -- Range (N-1, N) fills when value >= N
  bar.threshold = threshold
  bar:SetValue(0)
  return bar
end

local function GetArcDetector(threshold)
  if not arcDetectors[threshold] then
    arcDetectors[threshold] = CreateArcDetector(threshold)
    arcDetectorCount = math.max(arcDetectorCount, threshold)
  end
  return arcDetectors[threshold]
end

local function FeedArcDetectors(secretCharges, maxCharges)
  for i = 1, maxCharges do
    local bar = GetArcDetector(i)
    bar:SetValue(secretCharges)
  end
end

local function IsChargeThresholdMet(threshold)
  local bar = arcDetectors[threshold]
  if not bar then return false end
  return bar:GetStatusBarTexture():IsShown()
end

local function GetExactChargeCount(maxCharges)
  local count = 0
  for i = 1, maxCharges do
    local bar = arcDetectors[i]
    if bar and bar:GetStatusBarTexture():IsShown() then
      count = i
    else
      break
    end
  end
  return count
end

-- ===================================================================
-- COOLDOWN DURATION BAR
-- ===================================================================
local function CreateCooldownBar(index)
  InitCurves()
  local config = BAR_CONFIG
  
  local frame = CreateFrame("Frame", "ArcUICooldownBar"..index, UIParent, "BackdropTemplate")
  frame:SetSize(config.barWidth, config.barHeight)
  frame:SetPoint(config.anchorPoint, UIParent, config.anchorPoint,
                 config.anchorX, config.anchorY - (index - 1) * config.barSpacing)
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  frame:SetBackdropColor(0, 0, 0, 0.8)
  frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  
  -- Drag start - only on left button without shift
  frame:SetScript("OnDragStart", function(self)
    if not InCombatLockdown() then
      self:StartMoving()
    end
  end)
  
  -- Drag stop / right-click handler
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Save position as CENTER-based so scaling grows from center
    local barData = self.barData
    if barData and barData.spellID then
      local cfg = ns.CooldownBars.GetBarConfig(barData.spellID, "cooldown")
      if cfg and cfg.display then
        local centerX, centerY = self:GetCenter()
        if centerX and centerY then
          local uiCenterX, uiCenterY = UIParent:GetCenter()
          cfg.display.barPosition = {
            point = "CENTER",
            relPoint = "CENTER",
            x = centerX - uiCenterX,
            y = centerY - uiCenterY,
          }
        else
          -- Fallback
          local point, _, relPoint, x, y = self:GetPoint()
          cfg.display.barPosition = {
            point = point,
            relPoint = relPoint,
            x = x,
            y = y,
          }
        end
      end
    end
  end)
  
  -- Right-click to open appearance options
  frame:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" or (button == "LeftButton" and IsShiftKeyDown()) then
      local barData = self.barData
      if barData and barData.spellID then
        -- Open appearance options for this cooldown bar
        if ns.CooldownBars.OpenOptionsForBar then
          ns.CooldownBars.OpenOptionsForBar("cooldown", barData.spellID)
        end
      end
    end
  end)
  
  -- Icon
  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetSize(config.barHeight - 4, config.barHeight - 4)
  icon:SetPoint("LEFT", frame, "LEFT", 2, 0)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  
  -- Status bar
  local bar = CreateFrame("StatusBar", nil, frame)
  bar:SetPoint("LEFT", icon, "RIGHT", 4, 0)
  bar:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
  bar:SetPoint("TOP", frame, "TOP", 0, -3)
  bar:SetPoint("BOTTOM", frame, "BOTTOM", 0, 3)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(1, 1, 1, 1)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(1)
  
  -- Bar background
  local barBg = bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
  barBg:SetVertexColor(0.15, 0.15, 0.15, 0.9)
  
  -- Ready fill (shows when cooldown ready)
  local readyFill = bar:CreateTexture(nil, "BORDER")
  readyFill:SetAllPoints()
  readyFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
  readyFill:SetVertexColor(1, 1, 1, 1)
  readyFill:SetAlpha(0)
  
  -- Name text container (allows independent frame level)
  local nameTextContainer = CreateFrame("Frame", nil, bar)
  nameTextContainer:SetSize(150, 20)
  nameTextContainer:SetPoint("LEFT", bar, "LEFT", 4, 0)
  local nameText = nameTextContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nameText:SetAllPoints()
  nameText:SetJustifyH("LEFT")
  nameText:SetTextColor(1, 1, 1, 1)
  nameText:SetShadowOffset(1, -1)
  
  -- Duration text container (allows independent frame level)
  local durationTextContainer = CreateFrame("Frame", nil, bar)
  durationTextContainer:SetSize(60, 20)
  durationTextContainer:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
  local text = durationTextContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetAllPoints()
  text:SetJustifyH("RIGHT")
  text:SetTextColor(1, 1, 0.5, 1)
  text:SetShadowOffset(1, -1)
  
  -- Ready text (shown when ready) - in same container as duration
  local readyText = durationTextContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  readyText:SetAllPoints()
  readyText:SetJustifyH("RIGHT")
  readyText:SetTextColor(1, 1, 1, 1)
  readyText:SetShadowOffset(1, -1)
  readyText:SetText("Ready")
  readyText:SetAlpha(0)
  
  local barData = {
    frame = frame,
    bar = bar,
    barBg = barBg,
    readyFill = readyFill,
    icon = icon,
    nameTextContainer = nameTextContainer,
    nameText = nameText,
    durationTextContainer = durationTextContainer,
    text = text,
    readyText = readyText,
    spellID = nil,
    barIndex = index,
    -- Optimization state
    hiddenBySpec = false,
    lastUsableState = nil,
    cachedIsReady = nil,
  }
  
  -- Store barData on frame for event handler access
  frame.barData = barData
  
  frame:Hide()
  ns.CooldownBars.bars[index] = barData
  return barData
end

-- ===================================================================
-- CHARGE BAR (shows charge count + recharge progress)
-- ===================================================================
local function CreateChargeBar(index)
  local frame = CreateFrame("Frame", "ArcUIChargeBar"..index, UIParent, "BackdropTemplate")
  frame:SetSize(280, 38)  -- Initial size, will be adjusted by ApplyAppearance
  frame:SetPoint("TOP", UIParent, "TOP", 300, -100 - (index-1) * 46)
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  frame:SetBackdropColor(0, 0, 0, 0.7)
  frame:SetBackdropBorderColor(0.8, 0.6, 0.2, 1)  -- Gold border
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  
  -- Drag start - only on left button without shift
  frame:SetScript("OnDragStart", function(self)
    if not InCombatLockdown() then
      self:StartMoving()
    end
  end)
  
  -- Drag stop / position saving
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Save position as CENTER-based so scaling grows from center
    local barData = self.barData
    if barData and barData.spellID then
      local cfg = ns.CooldownBars.GetBarConfig(barData.spellID, "charge")
      if cfg and cfg.display then
        local centerX, centerY = self:GetCenter()
        if centerX and centerY then
          local uiCenterX, uiCenterY = UIParent:GetCenter()
          cfg.display.barPosition = {
            point = "CENTER",
            relPoint = "CENTER",
            x = centerX - uiCenterX,
            y = centerY - uiCenterY,
          }
        else
          -- Fallback
          local point, _, relPoint, x, y = self:GetPoint()
          cfg.display.barPosition = {
            point = point,
            relPoint = relPoint,
            x = x,
            y = y,
          }
        end
      end
    end
  end)
  
  -- Right-click to open appearance options
  frame:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" or (button == "LeftButton" and IsShiftKeyDown()) then
      local barData = self.barData
      if barData and barData.spellID then
        -- Open appearance options for this charge bar
        if ns.CooldownBars.OpenOptionsForBar then
          ns.CooldownBars.OpenOptionsForBar("charge", barData.spellID)
        end
      end
    end
  end)
  
  -- Icon (left side, vertically centered)
  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetSize(30, 30)
  icon:SetPoint("LEFT", frame, "LEFT", 2, 0)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  
  -- Container for per-charge slots (left of icon, vertically centered)
  local slotsContainer = CreateFrame("Frame", nil, frame)
  slotsContainer:SetPoint("LEFT", icon, "RIGHT", 4, 0)
  slotsContainer:SetSize(180, 14)  -- Default slots area size
  
  -- Name text container (allows independent frame level)
  local nameTextContainer = CreateFrame("Frame", nil, frame)
  nameTextContainer:SetSize(150, 20)
  nameTextContainer:SetPoint("TOPLEFT", icon, "TOPRIGHT", 4, 0)
  local nameText = nameTextContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nameText:SetAllPoints()
  nameText:SetTextColor(1, 1, 1, 1)
  nameText:SetShadowOffset(1, -1)
  nameText:SetJustifyH("LEFT")
  
  -- Charge text container (for currentText and maxText together)
  local chargeTextContainer = CreateFrame("Frame", nil, frame)
  chargeTextContainer:SetSize(60, 25)
  chargeTextContainer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, 0)
  
  -- Max charges text (right side) - shows "/2"
  local maxText = chargeTextContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  maxText:SetPoint("RIGHT", chargeTextContainer, "RIGHT", 0, 0)
  maxText:SetJustifyH("RIGHT")
  maxText:SetTextColor(0.6, 0.6, 0.6, 1)
  maxText:SetShadowOffset(1, -1)
  
  -- Current charges text (left of max) - shows "2"
  local currentText = chargeTextContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  currentText:SetPoint("RIGHT", maxText, "LEFT", 0, 0)
  currentText:SetJustifyH("RIGHT")
  currentText:SetTextColor(0.5, 1, 0.8, 1)
  currentText:SetShadowOffset(1, -1)
  
  -- Timer text container (allows independent frame level)
  local timerTextContainer = CreateFrame("Frame", nil, frame)
  timerTextContainer:SetSize(60, 20)
  timerTextContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 2)
  local timerText = timerTextContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  timerText:SetAllPoints()
  timerText:SetJustifyH("RIGHT")
  timerText:SetTextColor(1, 1, 0.5, 1)
  timerText:SetShadowOffset(1, -1)
  
  local barData = {
    frame = frame,
    slotsContainer = slotsContainer,
    icon = icon,
    nameTextContainer = nameTextContainer,
    nameText = nameText,
    chargeTextContainer = chargeTextContainer,
    currentText = currentText,
    maxText = maxText,
    timerTextContainer = timerTextContainer,
    timerText = timerText,
    chargeSlots = {},
    spellID = nil,
    maxCharges = 0,
    -- Optimization state
    lastDetectedCharges = -1,
    cachedChargeDurObj = nil,
    lastUsableState = nil,
    cachedChargeInfo = nil,
    needsChargeRefresh = true,
    needsDurationRefresh = true,
  }
  
  -- Store barData on frame for event handler access
  frame.barData = barData
  
  -- Register for charge and cooldown update events
  frame:RegisterEvent("SPELL_UPDATE_CHARGES")
  frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
  frame:SetScript("OnEvent", function(self, event)
    local bd = self.barData
    if not bd or not bd.spellID then return end
    
    if event == "SPELL_UPDATE_CHARGES" then
      bd.needsChargeRefresh = true
      bd.needsDurationRefresh = true
    elseif event == "SPELL_UPDATE_COOLDOWN" then
      bd.needsDurationRefresh = true
    end
  end)
  
  frame:Hide()
  ns.CooldownBars.chargeBars[index] = barData
  return barData
end

-- Create a single charge slot with background, recharge bar, and full bar
local function CreateChargeSlot(parent, slotIndex, slotWidth, slotHeight, offset, isVertical, displayCfg)
  local slot = {}
  
  -- Dimensions and positioning depend on orientation
  -- Horizontal: wide & short bars, arranged left-to-right, fill left-to-right
  -- Vertical: narrow & tall bars, arranged bottom-to-top, fill bottom-to-top
  local w, h, anchorPoint, xOff, yOff
  
  if isVertical then
    -- Vertical mode: bars are narrow and tall, stacked from bottom going up
    -- slotWidth is the thickness, slotHeight is the length
    w = slotWidth - 2   -- Bar thickness (narrow)
    h = slotHeight      -- Bar length (tall)
    anchorPoint = "BOTTOMLEFT"
    xOff = 0
    yOff = offset  -- Positive Y to go upward from bottom
  else
    -- Horizontal mode: bars are wide and short, stacked from left going right
    w = slotWidth - 2   -- Bar length (wide)
    h = slotHeight      -- Bar thickness (short)
    anchorPoint = "BOTTOMLEFT"
    xOff = offset
    yOff = 0
  end
  
  -- Get colors from display config or use defaults
  local slotBgColor = displayCfg and displayCfg.slotBackgroundColor or {r = 0.08, g = 0.08, b = 0.08, a = 1}
  local barColor = displayCfg and displayCfg.barColor or {r = 0.6, g = 0.5, b = 0.2, a = 1}
  local opacity = displayCfg and displayCfg.opacity or 1.0
  
  -- Full charge color: use different color if enabled, otherwise same as bar color
  local fullColor = barColor
  if displayCfg and displayCfg.useDifferentFullColor then
    fullColor = displayCfg.fullChargeColor or {r = 0.8, g = 0.6, b = 0.2, a = 1}
  end
  
  -- Background (dark, always visible)
  slot.background = parent:CreateTexture(nil, "BACKGROUND", nil, -1)
  slot.background:SetSize(w, h)
  slot.background:SetPoint(anchorPoint, parent, anchorPoint, xOff, yOff)
  slot.background:SetColorTexture(slotBgColor.r, slotBgColor.g, slotBgColor.b, (slotBgColor.a or 1) * opacity)
  
  -- Recharge progress bar (shows recharge animation - fills up)
  slot.rechargeBar = CreateFrame("StatusBar", nil, parent)
  slot.rechargeBar:SetSize(w, h)
  slot.rechargeBar:SetPoint(anchorPoint, parent, anchorPoint, xOff, yOff)
  slot.rechargeBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  slot.rechargeBar:SetStatusBarColor(barColor.r, barColor.g, barColor.b, (barColor.a or 1) * opacity)
  slot.rechargeBar:SetMinMaxValues(0, 1)
  slot.rechargeBar:SetValue(0)
  slot.rechargeBar:SetFrameLevel(parent:GetFrameLevel() + 1)
  -- Set fill orientation based on bar orientation
  slot.rechargeBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
  
  -- Full bar (shows when charge is complete)
  slot.fullBar = CreateFrame("StatusBar", nil, parent)
  slot.fullBar:SetSize(w, h)
  slot.fullBar:SetPoint(anchorPoint, parent, anchorPoint, xOff, yOff)
  slot.fullBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  slot.fullBar:SetStatusBarColor(fullColor.r, fullColor.g, fullColor.b, (fullColor.a or 1) * opacity)
  slot.fullBar:SetFrameLevel(parent:GetFrameLevel() + 2)
  -- Key trick: min/max range so it fills when charges >= slotIndex
  slot.fullBar:SetMinMaxValues(slotIndex - 0.01, slotIndex)
  slot.fullBar:SetValue(0)
  -- Set fill orientation based on bar orientation
  slot.fullBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
  
  slot.slotIndex = slotIndex
  return slot
end

-- Create all charge slots for a bar
-- For horizontal: slotsTotalWidth = total width for all bars arranged side-by-side
-- For vertical: slotsTotalWidth = width of all bars, slotHeight = height of each bar
-- For both modes: slots are arranged LEFT TO RIGHT, but bar fill direction changes
-- Vertical mode: bars fill BOTTOM TO TOP (same as aura bars)
local function CreateChargeSlots(barData, maxCharges, slotsTotalWidth, slotHeight, slotSpacing, isVertical, displayCfg)
  -- Clean up old slots
  for _, slot in ipairs(barData.chargeSlots or {}) do
    if slot.background then slot.background:Hide() end
    if slot.rechargeBar then slot.rechargeBar:Hide() end
    if slot.fullBar then slot.fullBar:Hide() end
  end
  barData.chargeSlots = {}
  if maxCharges < 1 then return end
  
  local container = barData.slotsContainer
  local totalSize = slotsTotalWidth or 160
  local barThickness = slotHeight or 12
  local spacing = slotSpacing or 3
  
  -- For BOTH modes: slots arranged left-to-right
  -- The difference is:
  -- - Horizontal: bars fill left-to-right (horizontal fill)
  -- - Vertical: bars fill bottom-to-top (vertical fill)
  local barLength = (totalSize - (maxCharges - 1) * spacing) / maxCharges
  
  if isVertical then
    -- Vertical mode: container is TALL and NARROW (swapped from horizontal)
    -- Bars are arranged left-to-right but fill bottom-to-top
    container:SetSize(barThickness, totalSize)  -- Swap: width=thickness, height=totalSize
    
    for i = 1, maxCharges do
      local yOffset = (i - 1) * (barLength + spacing)
      -- Each slot is narrow and tall, positioned from bottom
      local slot = CreateChargeSlot(container, i, barThickness, barLength + 2, yOffset, true, displayCfg)
      barData.chargeSlots[i] = slot
    end
  else
    -- Horizontal mode: container is WIDE and SHORT
    -- Bars arranged left-to-right, fill left-to-right
    container:SetSize(totalSize, barThickness)
    
    for i = 1, maxCharges do
      local xOffset = (i - 1) * (barLength + spacing)
      local slot = CreateChargeSlot(container, i, barLength + 2, barThickness, xOffset, false, displayCfg)
      barData.chargeSlots[i] = slot
    end
  end
  
  -- Store orientation for later use
  barData.isVertical = isVertical
end


-- ===================================================================
-- RESOURCE BAR
-- ===================================================================
local function CreateResourceBar(index)
  local config = BAR_CONFIG
  
  local frame = CreateFrame("Frame", "ArcUIResourceBar"..index, UIParent, "BackdropTemplate")
  frame:SetSize(config.barWidth, config.barHeight)
  frame:SetPoint(config.anchorPoint, UIParent, config.anchorPoint,
                 config.anchorX + config.barWidth + 10, config.anchorY - (index - 1) * config.barSpacing)
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  frame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
  frame:SetBackdropBorderColor(0.6, 0.2, 0.6, 1)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  
  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetSize(config.barHeight - 6, config.barHeight - 6)
  icon:SetPoint("LEFT", frame, "LEFT", 3, 0)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  
  local bar = CreateFrame("StatusBar", nil, frame)
  bar:SetPoint("LEFT", icon, "RIGHT", 4, 0)
  bar:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
  bar:SetPoint("TOP", frame, "TOP", 0, -3)
  bar:SetPoint("BOTTOM", frame, "BOTTOM", 0, 3)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(0.8, 0.2, 0.8, 1)
  bar:SetMinMaxValues(0, 100)
  bar:SetValue(0)
  
  local barBg = bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
  barBg:SetVertexColor(0.15, 0.15, 0.15, 0.9)
  
  local nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
  nameText:SetJustifyH("LEFT")
  nameText:SetTextColor(1, 1, 1, 1)
  nameText:SetShadowOffset(1, -1)
  
  local costText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  costText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
  costText:SetJustifyH("RIGHT")
  costText:SetTextColor(0.7, 0.7, 0.7, 1)
  costText:SetShadowOffset(1, -1)
  
  local valueText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  valueText:SetPoint("RIGHT", costText, "LEFT", 0, 0)
  valueText:SetJustifyH("RIGHT")
  valueText:SetTextColor(1, 1, 0.5, 1)
  valueText:SetShadowOffset(1, -1)
  
  local barData = {
    frame = frame,
    bar = bar,
    barBg = barBg,
    icon = icon,
    nameText = nameText,
    valueText = valueText,
    costText = costText,
    spellID = nil,
    powerType = nil,
    cost = 0,
  }
  
  frame:Hide()
  ns.CooldownBars.resourceBars[index] = barData
  return barData
end

-- ===================================================================
-- BAR UPDATE FUNCTIONS
-- ===================================================================
local function UpdateCooldownBar(barData)
  if not barData or not barData.spellID then
    barData.frame:Hide()
    return
  end
  
  -- CRITICAL: Don't show if hidden by spec
  if barData.hiddenBySpec then
    barData.frame:Hide()
    -- Hide FREE text frames (parented to UIParent, won't auto-hide)
    if barData.durationTextFrame then
      barData.durationTextFrame:Hide()
    end
    if barData.readyTextFrame then
      barData.readyTextFrame:Hide()
    end
    return
  end
  
  local spellID = barData.spellID
  local baseColor = barData.customColor or { r = 1, g = 0.5, b = 0.2, a = 1 }
  
  -- Get spell info
  local spellName = C_Spell.GetSpellName(spellID)
  local spellTexture = C_Spell.GetSpellTexture(spellID)
  
  -- Get config
  local cfg = ns.CooldownBars.GetBarConfig and ns.CooldownBars.GetBarConfig(spellID, "cooldown")
  local hideWhenReady = cfg and cfg.behavior and cfg.behavior.hideWhenReady
  local hideOutOfCombat = cfg and cfg.behavior and cfg.behavior.hideOutOfCombat
  
  -- Get duration objects (EXACT COPY FROM CDT)
  local chargeDurObj = C_Spell.GetSpellChargeDuration(spellID)
  local cooldownDurObj = C_Spell.GetSpellCooldownDuration(spellID)
  local cdInfo = C_Spell.GetSpellCooldown(spellID)
  
  -- Determine which duration object to use (EXACT COPY FROM CDT)
  local durObj = nil
  
  -- CHARGE SPELLS: If chargeDurObj exists, use it
  if chargeDurObj then
    durObj = chargeDurObj
  else
    -- NORMAL COOLDOWN: Filter out GCD-only
    if cdInfo and cdInfo.isOnGCD ~= true then
      durObj = cooldownDurObj
    end
  end
  
  -- Visibility check
  local isReady = (durObj == nil)
  local shouldShow = true
  if hideWhenReady and isReady then shouldShow = false end
  if hideOutOfCombat and not UnitAffectingCombat("player") then shouldShow = false end
  
  if not shouldShow then
    barData.frame:Hide()
    return
  end
  
  barData.frame:Show()
  
  if spellTexture then
    barData.icon:SetTexture(spellTexture)
  end
  
  barData.nameText:SetText(spellName or ("Spell " .. spellID))
  
  if durObj then
    -- (EXACT COPY FROM CDT.UpdateBar)
    local interpolation = Enum.StatusBarInterpolation.ExponentialEaseOut
    
    -- Get fill direction setting (default Drain = RemainingTime)
    local direction = Enum.StatusBarTimerDirection.RemainingTime
    local fillMode = cfg and cfg.display and cfg.display.durationBarFillMode
    if fillMode == "fill" then
      direction = Enum.StatusBarTimerDirection.ElapsedTime
    end
    
    -- Set bar color
    local barTexture = barData.bar:GetStatusBarTexture()
    barTexture:SetVertexColor(baseColor.r, baseColor.g, baseColor.b, 1)
    
    -- Use SetTimerDuration for automatic smooth bar updates (EXACT COPY FROM CDT)
    barData.bar:SetMinMaxValues(0, 1)
    barData.bar:SetTimerDuration(durObj, interpolation, direction)
    
    -- CRITICAL FIX: Snap to target value to avoid 0→100% animation on charge spells (EXACT COPY FROM CDT)
    barData.bar:SetToTargetValue()
    
    -- Duration text with decimals formatting (same pattern as charge bars)
    local durationDecimals = cfg and cfg.display and cfg.display.durationDecimals or 1
    local remaining = durObj:GetRemainingDuration()
    local ok, result = pcall(function()
      local num = tonumber(remaining)
      if num then
        if durationDecimals == 0 then
          return string.format("%.0f", num)
        elseif durationDecimals == 1 then
          return string.format("%.1f", num)
        else
          return string.format("%.2f", num)
        end
      end
      return remaining  -- Return as-is if can't convert
    end)
    
    if ok then
      barData.text:SetText(result)
      if barData.freeDurationText then
        barData.freeDurationText:SetText(result)
      end
    else
      -- Secret value - pass through (SetText handles it)
      barData.text:SetText(remaining)
      if barData.freeDurationText then
        barData.freeDurationText:SetText(remaining)
      end
    end
    
    -- Use 0%+100% curve for ready fill (covers charge spell animation glitch) (EXACT COPY FROM CDT)
    local readyAlpha = durObj:EvaluateRemainingPercent(readyAlphaCurve100)
    local onCDAlpha = durObj:EvaluateRemainingPercent(onCooldownAlphaCurve)
    
    barData.text:SetAlpha(onCDAlpha)
    if barData.freeDurationText then
      barData.freeDurationText:SetAlpha(onCDAlpha)
    end
    -- Use stored readyColor (set by ApplyAppearance), don't override with baseColor
    barData.readyText:SetAlpha(readyAlpha)
    if barData.freeReadyText then
      barData.freeReadyText:SetAlpha(readyAlpha)
    end
    barData.readyFill:SetVertexColor(baseColor.r, baseColor.g, baseColor.b, 1)
    barData.readyFill:SetAlpha(readyAlpha)
  else
    -- No duration (ready state) (EXACT COPY FROM CDT)
    local barTexture = barData.bar:GetStatusBarTexture()
    barTexture:SetVertexColor(baseColor.r, baseColor.g, baseColor.b, 1)
    barData.bar:SetMinMaxValues(0, 1)
    barData.bar:SetValue(1)
    barData.text:SetAlpha(0)
    if barData.freeDurationText then
      barData.freeDurationText:SetAlpha(0)
    end
    -- Use stored readyColor (set by ApplyAppearance), don't override with baseColor
    barData.readyText:SetAlpha(1)
    if barData.freeReadyText then
      barData.freeReadyText:SetAlpha(1)
    end
    barData.readyFill:SetVertexColor(baseColor.r, baseColor.g, baseColor.b, 1)
    barData.readyFill:SetAlpha(1)
  end
end

local function UpdateChargeBar(barData)
  if not barData or not barData.spellID then return end
  if not barData.chargeSlots or #barData.chargeSlots == 0 then return end
  
  -- CRITICAL: Don't show if hidden by spec
  if barData.hiddenBySpec then
    barData.frame:Hide()
    -- Hide FREE text frames (parented to UIParent, won't auto-hide)
    if barData.stackTextFrame then barData.stackTextFrame:Hide() end
    if barData.timerTextFrame then barData.timerTextFrame:Hide() end
    return
  end
  
  local spellID = barData.spellID
  local maxCharges = barData.maxCharges
  
  -- Event-based: Only fetch chargeInfo when SPELL_UPDATE_CHARGES fires
  if barData.needsChargeRefresh then
    barData.cachedChargeInfo = C_Spell.GetSpellCharges(spellID)
    barData.needsChargeRefresh = false
  end
  
  local chargeInfo = barData.cachedChargeInfo
  if not chargeInfo then return end
  local secretCurrentCharges = chargeInfo.currentCharges
  
  -- Feed Arc detectors with SECRET charge count (secret→bool conversion)
  FeedArcDetectors(secretCurrentCharges, maxCharges)
  
  -- Get exact charge count via IsShown() - NOT secret!
  local detectedCharges = GetExactChargeCount(maxCharges)
  
  -- Check hide when full charges behavior
  local cfg = ns.CooldownBars.GetBarConfig and ns.CooldownBars.GetBarConfig(spellID, "charge")
  local hideWhenFull = cfg and cfg.behavior and cfg.behavior.hideWhenFullCharges
  local hideOutOfCombat = cfg and cfg.behavior and cfg.behavior.hideOutOfCombat
  
  -- Determine visibility
  local shouldShow = true
  if hideWhenFull and detectedCharges >= maxCharges then
    shouldShow = false
  end
  if hideOutOfCombat and not UnitAffectingCombat("player") then
    shouldShow = false
  end
  
  if shouldShow then
    barData.frame:Show()
    -- Show FREE text frames if they exist and are in use
    if barData.stackTextFrame and barData.useStackTextFrame then
      barData.stackTextFrame:Show()
    end
    if barData.timerTextFrame and barData.useFreeTimerText then
      barData.timerTextFrame:Show()
    end
  else
    barData.frame:Hide()
    -- Hide FREE text frames (parented to UIParent, won't auto-hide)
    if barData.stackTextFrame then
      barData.stackTextFrame:Hide()
    end
    if barData.timerTextFrame then
      barData.timerTextFrame:Hide()
    end
    return  -- Don't update hidden bars
  end
  
  -- Event-based: Update duration on SPELL_UPDATE_CHARGES or SPELL_UPDATE_COOLDOWN
  if barData.needsDurationRefresh then
    barData.lastDetectedCharges = detectedCharges
    barData.needsDurationRefresh = false
    
    -- Re-fetch duration object (CDR may have changed it)
    barData.cachedChargeDurObj = C_Spell.GetSpellChargeDuration(spellID)
    
    -- Set timer on all recharge bars - auto-animates until next refresh
    -- No comparison needed - just pass the duration object to SetTimerDuration
    if barData.cachedChargeDurObj then
      local interpolation = Enum.StatusBarInterpolation.ExponentialEaseOut
      for _, slot in ipairs(barData.chargeSlots) do
        -- SetMinMaxValues and SetTimerDuration accept secret values
        slot.rechargeBar:SetMinMaxValues(0, barData.cachedChargeInfo.cooldownDuration)
        slot.rechargeBar:SetTimerDuration(barData.cachedChargeDurObj, interpolation, Enum.StatusBarTimerDirection.ElapsedTime)
        slot.rechargeBar:SetToTargetValue()  -- Snap to avoid 0→100% animation glitch
      end
    end
  end
  
  -- Update display text (both normal and FREE mode if exists)
  barData.currentText:SetText(detectedCharges)
  if barData.stackCurrentText then
    barData.stackCurrentText:SetText(detectedCharges)
  end
  
  -- Timer text uses cached duration object with decimals formatting
  -- Use same pattern as CooldownDurationTest.FormatDuration
  local durationDecimals = cfg and cfg.display and cfg.display.durationDecimals or 1
  if barData.cachedChargeDurObj then
    local remaining = barData.cachedChargeDurObj:GetRemainingDuration()
    local ok, result = pcall(function()
      local num = tonumber(remaining)
      if num then
        if durationDecimals == 0 then
          return string.format("%.0f", num)
        elseif durationDecimals == 1 then
          return string.format("%.1f", num)
        else
          return string.format("%.2f", num)
        end
      end
      return remaining  -- Return as-is if can't convert
    end)
    
    if ok then
      barData.timerText:SetText(result)
      if barData.freeTimerText then
        barData.freeTimerText:SetText(result)
      end
    else
      -- Secret value - pass through (SetText handles it)
      barData.timerText:SetText(remaining)
      if barData.freeTimerText then
        barData.freeTimerText:SetText(remaining)
      end
    end
  else
    barData.timerText:SetText("")
    if barData.freeTimerText then
      barData.freeTimerText:SetText("")
    end
  end
  
  -- Get colors for this bar
  local barColor = barData.customColor or {r = 0.6, g = 0.5, b = 0.2}
  local fullColor = barData.fullColor or barColor  -- Use fullColor if set, otherwise same as barColor
  
  -- Update each slot
  for i, slot in ipairs(barData.chargeSlots) do
    -- Feed full bar with secret charge value (fills when >= slotIndex)
    slot.fullBar:SetValue(secretCurrentCharges)
    slot.fullBar:SetStatusBarColor(fullColor.r, fullColor.g, fullColor.b, 1)
    slot.rechargeBar:SetStatusBarColor(barColor.r, barColor.g, barColor.b, 1)
    
    -- Slot visibility: slot 1 always visible, others only if previous is full
    slot.background:SetAlpha(1)
    
    if i == 1 then
      slot.rechargeBar:SetAlpha(1)
      slot.fullBar:SetAlpha(1)
    else
      local thresholdMet = IsChargeThresholdMet(i - 1)
      local alpha = thresholdMet and 1 or 0
      slot.rechargeBar:SetAlpha(alpha)
      slot.fullBar:SetAlpha(alpha)
    end
  end
  
  -- Update border color when usable state changes (gold when usable)
  local usable = C_Spell.IsSpellUsable(spellID)
  if usable ~= barData.lastUsableState then
    barData.lastUsableState = usable
    if usable then
      barData.frame:SetBackdropBorderColor(0.8, 0.7, 0.2, 1)  -- Gold border
      barData.currentText:SetTextColor(0.5, 1, 0.8, 1)
      if barData.stackCurrentText then
        barData.stackCurrentText:SetTextColor(0.5, 1, 0.8, 1)
      end
    else
      barData.frame:SetBackdropBorderColor(0.5, 0.3, 0.3, 1)
      barData.currentText:SetTextColor(1, 0.4, 0.4, 1)
      if barData.stackCurrentText then
        barData.stackCurrentText:SetTextColor(1, 0.4, 0.4, 1)
      end
    end
  end
end


local function UpdateResourceBar(barData)
  if not barData or not barData.spellID then return end
  
  -- CRITICAL: Don't update if hidden by spec
  if barData.hiddenBySpec then
    barData.frame:Hide()
    return
  end
  
  local currentPower = UnitPower("player", barData.powerType)
  
  barData.bar:SetValue(currentPower)
  barData.valueText:SetText(currentPower)
  
  local usable, insufficientPower = C_Spell.IsSpellUsable(barData.spellID)
  
  -- Use custom color if set
  if barData.customColor then
    if usable then
      barData.bar:SetStatusBarColor(barData.customColor.r, barData.customColor.g, barData.customColor.b, 1)
      barData.frame:SetBackdropBorderColor(0.2, 0.8, 0.2, 1)
      barData.valueText:SetTextColor(0.5, 1, 0.5, 1)
    elseif insufficientPower then
      barData.bar:SetStatusBarColor(barData.customColor.r * 0.6, barData.customColor.g * 0.6, barData.customColor.b * 0.6, 1)
      barData.frame:SetBackdropBorderColor(0.6, 0.2, 0.6, 1)
      barData.valueText:SetTextColor(1, 0.8, 0.2, 1)
    else
      barData.bar:SetStatusBarColor(barData.customColor.r * 0.4, barData.customColor.g * 0.4, barData.customColor.b * 0.4, 1)
      barData.frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
      barData.valueText:SetTextColor(0.7, 0.7, 0.7, 1)
    end
  else
    -- Default colors
    if usable then
      barData.bar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
      barData.frame:SetBackdropBorderColor(0.2, 0.8, 0.2, 1)
      barData.valueText:SetTextColor(0.5, 1, 0.5, 1)
    elseif insufficientPower then
      barData.bar:SetStatusBarColor(0.8, 0.2, 0.8, 1)
      barData.frame:SetBackdropBorderColor(0.6, 0.2, 0.6, 1)
      barData.valueText:SetTextColor(1, 0.8, 0.2, 1)
    else
      barData.bar:SetStatusBarColor(0.5, 0.5, 0.5, 1)
      barData.frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
      barData.valueText:SetTextColor(0.7, 0.7, 0.7, 1)
    end
  end
end

-- ===================================================================
-- ADD/REMOVE BAR FUNCTIONS
-- ===================================================================
function ns.CooldownBars.AddCooldownBar(spellID)
  if ns.CooldownBars.activeCooldowns[spellID] then return end
  
  local barIndex = 1
  for i = 1, 10 do
    local inUse = false
    for sid, idx in pairs(ns.CooldownBars.activeCooldowns) do
      if idx == i then inUse = true break end
    end
    if not inUse then barIndex = i break end
  end
  
  if not ns.CooldownBars.bars[barIndex] then
    CreateCooldownBar(barIndex)
  end
  
  ns.CooldownBars.bars[barIndex].spellID = spellID
  ns.CooldownBars.activeCooldowns[spellID] = barIndex
  UpdateCooldownBar(ns.CooldownBars.bars[barIndex])
  
  -- Apply saved settings
  C_Timer.After(0.01, function()
    ns.CooldownBars.ApplyBarSettings(spellID, "cooldown")
  end)
  
  Log("Added cooldown bar: " .. (C_Spell.GetSpellName(spellID) or spellID))
end

function ns.CooldownBars.RemoveCooldownBar(spellID)
  local barIndex = ns.CooldownBars.activeCooldowns[spellID]
  if not barIndex then return end
  
  local barData = ns.CooldownBars.bars[barIndex]
  if barData then
    barData.frame:Hide()
    barData.spellID = nil
  end
  
  ns.CooldownBars.activeCooldowns[spellID] = nil
  Log("Removed cooldown bar: " .. spellID)
end

function ns.CooldownBars.AddChargeBar(spellID)
  if ns.CooldownBars.activeCharges[spellID] then return end
  
  local spellName = C_Spell.GetSpellName(spellID)
  local spellTexture = C_Spell.GetSpellTexture(spellID)
  local chargeInfo = C_Spell.GetSpellCharges(spellID)
  
  -- chargeInfo being nil means not a charge spell
  if not chargeInfo then
    Log("No charge info for: " .. (spellName or spellID))
    return
  end
  
  -- Get maxCharges safely (could be secret in combat)
  local maxCharges = 2  -- Default for charge spells
  if chargeInfo.maxCharges then
    if not issecretvalue or not issecretvalue(chargeInfo.maxCharges) then
      maxCharges = chargeInfo.maxCharges
    end
  end
  
  local barIndex = 1
  for i = 1, 10 do
    local inUse = false
    for sid, idx in pairs(ns.CooldownBars.activeCharges) do
      if idx == i then inUse = true break end
    end
    if not inUse then barIndex = i break end
  end
  
  if not ns.CooldownBars.chargeBars[barIndex] then
    CreateChargeBar(barIndex)
  end
  
  local barData = ns.CooldownBars.chargeBars[barIndex]
  barData.spellID = spellID
  barData.maxCharges = maxCharges
  -- Note: cooldownDuration is secret, stored in cachedChargeInfo instead
  
  -- Reset optimization state for new spell
  barData.lastDetectedCharges = -1
  barData.cachedChargeDurObj = nil
  barData.lastUsableState = nil
  barData.cachedChargeInfo = nil
  barData.needsChargeRefresh = true
  barData.needsDurationRefresh = true
  
  barData.icon:SetTexture(spellTexture)
  barData.nameText:SetText(spellName)
  barData.maxText:SetText("/" .. barData.maxCharges)
  
  barData.frame:Show()
  ns.CooldownBars.activeCharges[spellID] = barIndex
  
  C_Timer.After(0.01, function()
    -- Create per-charge slots with default dimensions (160 wide, 12 tall)
    CreateChargeSlots(barData, barData.maxCharges, 160, 12)
    -- Apply saved settings (will recreate slots with proper dimensions)
    ns.CooldownBars.ApplyBarSettings(spellID, "charge")
  end)
  
  Log("Added charge bar: " .. spellName)
end

function ns.CooldownBars.RemoveChargeBar(spellID)
  local barIndex = ns.CooldownBars.activeCharges[spellID]
  if not barIndex then return end
  
  local barData = ns.CooldownBars.chargeBars[barIndex]
  if barData then
    barData.frame:Hide()
    -- Hide FREE text frames (parented to UIParent, won't auto-hide)
    if barData.stackTextFrame then barData.stackTextFrame:Hide() end
    if barData.timerTextFrame then barData.timerTextFrame:Hide() end
    barData.spellID = nil
  end
  
  ns.CooldownBars.activeCharges[spellID] = nil
  Log("Removed charge bar: " .. spellID)
end


function ns.CooldownBars.AddResourceBar(spellID)
  if ns.CooldownBars.activeResources[spellID] then return end
  
  local spellName = C_Spell.GetSpellName(spellID)
  local spellTexture = C_Spell.GetSpellTexture(spellID)
  local costInfo = C_Spell.GetSpellPowerCost(spellID)
  
  if not costInfo or #costInfo == 0 then
    Log("No resource cost for: " .. (spellName or spellID))
    return
  end
  
  local barIndex = 1
  for i = 1, 10 do
    local inUse = false
    for sid, idx in pairs(ns.CooldownBars.activeResources) do
      if idx == i then inUse = true break end
    end
    if not inUse then barIndex = i break end
  end
  
  if not ns.CooldownBars.resourceBars[barIndex] then
    CreateResourceBar(barIndex)
  end
  
  local barData = ns.CooldownBars.resourceBars[barIndex]
  barData.spellID = spellID
  barData.powerType = costInfo[1].type
  barData.powerName = costInfo[1].name
  
  local cost = costInfo[1].cost
  if not cost or cost <= 0 then
    cost = costInfo[1].minCost or 0
  end
  if not cost or cost <= 0 then
    cost = UnitPowerMax("player", barData.powerType) or 100
  end
  barData.cost = cost
  
  barData.icon:SetTexture(spellTexture)
  barData.nameText:SetText(spellName)
  barData.costText:SetText("/ " .. barData.cost)
  barData.bar:SetMinMaxValues(0, barData.cost)
  
  barData.frame:Show()
  ns.CooldownBars.activeResources[spellID] = barIndex
  
  -- Apply saved settings
  C_Timer.After(0.01, function()
    ns.CooldownBars.ApplyBarSettings(spellID, "resource")
  end)
  
  Log("Added resource bar: " .. spellName .. " max=" .. barData.cost)
end

function ns.CooldownBars.RemoveResourceBar(spellID)
  local barIndex = ns.CooldownBars.activeResources[spellID]
  if not barIndex then return end
  
  local barData = ns.CooldownBars.resourceBars[barIndex]
  if barData then
    barData.frame:Hide()
    barData.spellID = nil
  end
  
  ns.CooldownBars.activeResources[spellID] = nil
  Log("Removed resource bar: " .. spellID)
end

-- ===================================================================
-- UPDATE LOOP
-- ===================================================================
local updateFrame = CreateFrame("Frame")
local updateInterval = 0.1
local timeSinceUpdate = 0

updateFrame:SetScript("OnUpdate", function(self, elapsed)
  timeSinceUpdate = timeSinceUpdate + elapsed
  if timeSinceUpdate < updateInterval then return end
  timeSinceUpdate = 0
  
  -- Update cooldown bars
  for spellID, barIndex in pairs(ns.CooldownBars.activeCooldowns) do
    local barData = ns.CooldownBars.bars[barIndex]
    if barData then
      UpdateCooldownBar(barData)
    end
  end
  
  -- Update charge bars
  for spellID, barIndex in pairs(ns.CooldownBars.activeCharges) do
    local barData = ns.CooldownBars.chargeBars[barIndex]
    if barData then
      UpdateChargeBar(barData)
    end
  end
  
  -- Update resource bars
  for spellID, barIndex in pairs(ns.CooldownBars.activeResources) do
    local barData = ns.CooldownBars.resourceBars[barIndex]
    if barData then
      UpdateResourceBar(barData)
    end
  end
end)

-- ===================================================================
-- SETTINGS STRUCTURE (matches DB.lua bars[] format)
-- ===================================================================
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Default display settings (matches DB.lua bars[].display)
local DISPLAY_DEFAULTS = {
  enabled = true,
  -- For cooldown/resource bars: width/height = frame size
  -- For charge bars: frameWidth/frameHeight = outer frame, width = slots fill width (independent)
  width = 178,                        -- Cooldown bar width / Slots Width for charge bars
  height = 26,                        -- Cooldown bar height
  frameWidth = 250,                   -- Charge bar outer frame width
  frameHeight = 33,                   -- Charge bar outer frame height
  barScale = 1.0,                    -- Multiplies dimensions (not SetScale)
  opacity = 1.0,
  barPadding = 2,
  
  -- Charge bar specific
  chargeDisplayMode = "slots",       -- "slots" = progressive slots, "unified" = single bar (noprog style)
  slotHeight = 25,                   -- Height of charge slot bars
  slotSpacing = 3,                   -- Gap between slots
  
  -- Fill/Orientation (matches aura bars)
  texture = "Blizzard",
  barOrientation = "horizontal",    -- "horizontal" or "vertical"
  barReverseFill = false,           -- Reverse fill direction
  durationBarFillMode = "drain",    -- "drain" (shrinks) or "fill" (grows) - for duration bars only
  useGradient = false,
  
  -- Colors
  barColor = {r = 0.2, g = 0.6, b = 0.2, a = 1},              -- Green bar color
  useDifferentFullColor = false,                               -- No different full color
  fullChargeColor = {r = 0.3, g = 0.8, b = 0.3, a = 1},       -- Brighter green for full charges
  showSlotBackground = false,                                  -- Slot background disabled
  slotBackgroundColor = {r = 0.08, g = 0.08, b = 0.08, a = 1}, -- Charge bar slot background
  
  -- Background
  showBackground = true,
  backgroundTexture = "Solid",
  backgroundColor = {r = 0.07, g = 0.07, b = 0.07, a = 1},  -- #121212
  
  -- Border
  showBorder = true,
  useClassColorBorder = true,                -- Use class colors for border
  borderColor = {r = 0.8, g = 0.6, b = 0.2, a = 1},
  drawnBorderThickness = 1,
  
  -- Tick marks (for charge bars = dividers)
  showTickMarks = false,
  tickThickness = 2,
  tickColor = {r = 0, g = 0, b = 0, a = 0.8},
  
  -- Stack/Charge text (shows charge count)
  showText = true,
  showMaxText = false,                 -- Don't show "/2" max value
  font = "2002 Bold",
  fontSize = 24,
  textColor = {r = 1, g = 1, b = 1, a = 1},  -- White for charge count
  textOutline = "THICKOUTLINE",
  textShadow = false,
  chargeTextAnchor = "CENTER",         -- Anchor for charge count text
  chargeTextOffsetX = -22,
  chargeTextOffsetY = 25,
  
  -- Duration/Timer text (shows recharge time)
  showDuration = true,
  durationFont = "2002 Bold",
  durationFontSize = 15,
  durationColor = {r = 1, g = 1, b = 1, a = 1},  -- White for timer
  durationOutline = "THICKOUTLINE",
  durationShadow = false,
  durationDecimals = 1,
  showDurationWhenReady = false,       -- Don't show timer when ready
  timerTextAnchor = "BOTTOMRIGHT",     -- Anchor for timer text
  timerTextOffsetX = -4,
  timerTextOffsetY = 7,
  
  -- Ready text (cooldown bars only - shows when ready)
  showReadyText = false,
  readyText = "Ready",
  readyColor = {r = 0.3, g = 1, b = 0.3, a = 1},  -- Green for ready
  
  -- Name text
  showName = true,
  nameFont = "2002 Bold",
  nameFontSize = 14,
  nameColor = {r = 1, g = 1, b = 1, a = 1},
  nameOutline = "THICKOUTLINE",
  nameShadow = false,
  nameAnchor = "TOP",
  nameOffsetX = -35,
  nameOffsetY = 4,
  
  -- Bar icon
  showBarIcon = true,
  barIconSize = 29,
  iconBarSpacing = 0,               -- Gap between icon and fill texture (Bar Gap)
  barIconAnchor = "LEFT",           -- Left (Start) position
  barIconShowBorder = false,
  barIconBorderColor = {r = 0, g = 0, b = 0, a = 1},
  
  -- Frame Strata options
  -- Valid values: BACKGROUND, LOW, MEDIUM, HIGH, DIALOG, FULLSCREEN, FULLSCREEN_DIALOG, TOOLTIP
  barFrameStrata = "HIGH",         -- Frame strata for the main bar frame (HIGH so it's above most UI)
  barFrameLevel = 10,              -- Frame level within the strata
  -- Per-text strata (all default to same strata, but 3 levels higher than bar textures)
  stackTextStrata = "HIGH",        -- Strata for charge count text
  stackTextLevel = 13,             -- Level for stack text (bar level + 3)
  durationTextStrata = "HIGH",     -- Strata for duration/timer text
  durationTextLevel = 13,          -- Level for duration text (bar level + 3)
  nameTextStrata = "HIGH",         -- Strata for name text
  nameTextLevel = 13,              -- Level for name text (bar level + 3)
  -- Lock toggles for FREE mode dragging
  stackTextLocked = false,         -- When true, FREE text can't be dragged
  durationTextLocked = false,
  nameTextLocked = false,
  -- Frame widths for FREE mode text frames
  stackTextFrameWidth = 80,        -- Width of draggable stack text frame
  durationTextFrameWidth = 60,     -- Width of draggable duration text frame
  
  -- Position
  barMovable = true,
  barPosition = {
    point = "CENTER",
    relPoint = "CENTER",
    x = 0,
    y = 100,
  },
}

-- Preset variations
local PRESETS = {
  simple = {
    -- Simple style: Clean, minimal, no icon
    width = 180,
    height = 22,
    frameWidth = 200,
    frameHeight = 32,
    showBorder = true,
    drawnBorderThickness = 1,
    borderColor = {r = 0.3, g = 0.3, b = 0.3, a = 1},
    useGradient = false,
    showBarIcon = false,
    barColor = {r = 0.3, g = 0.6, b = 0.9, a = 1},  -- Blue
    backgroundColor = {r = 0, g = 0, b = 0, a = 0.7},
    showName = true,
    nameFontSize = 11,
    nameColor = {r = 1, g = 1, b = 1, a = 1},
    showDuration = true,
    durationFontSize = 11,
    durationColor = {r = 1, g = 1, b = 1, a = 1},  -- White timer
    showReadyText = true,
    readyText = "Ready",
    readyColor = {r = 0.3, g = 1, b = 0.3, a = 1},  -- Green
    -- Charge bar specifics
    chargeDisplayMode = "slots",     -- Progressive slot-based display
    slotHeight = 12,
    slotSpacing = 2,
    showTickMarks = false,
    showText = true,
    textColor = {r = 1, g = 1, b = 1, a = 1},
  },
  arcui = {
    -- ArcUI style: CD Charges default settings
    -- Frame dimensions
    width = 178,                         -- Slots Width
    height = 26,
    frameWidth = 250,
    frameHeight = 33,
    barScale = 1.0,
    opacity = 1.0,
    
    -- Border
    showBorder = true,
    useClassColorBorder = true,              -- Use class colors
    drawnBorderThickness = 1,
    borderColor = {r = 0.8, g = 0.6, b = 0.2, a = 1},
    
    -- Fill
    texture = "Blizzard",
    useGradient = false,
    
    -- Colors
    barColor = {r = 0.2, g = 0.6, b = 0.2, a = 1},      -- Green bar color
    useDifferentFullColor = false,
    fullChargeColor = {r = 0.3, g = 0.8, b = 0.3, a = 1},
    showSlotBackground = false,
    slotBackgroundColor = {r = 0.08, g = 0.08, b = 0.08, a = 1},
    
    -- Background
    showBackground = true,
    backgroundTexture = "Solid",
    backgroundColor = {r = 0.07, g = 0.07, b = 0.07, a = 1},  -- #121212
    
    -- Bar Icon
    showBarIcon = true,
    barIconSize = 29,
    iconBarSpacing = 0,                  -- Bar Gap = 0
    barIconAnchor = "LEFT",              -- Left (Start)
    barIconShowBorder = false,
    
    -- Stack/Charge text
    showText = true,
    showMaxText = false,
    font = "2002 Bold",
    fontSize = 24,
    textColor = {r = 1, g = 1, b = 1, a = 1},       -- White
    textOutline = "THICKOUTLINE",
    textShadow = false,
    chargeTextAnchor = "CENTER",
    chargeTextOffsetX = -22,
    chargeTextOffsetY = 25,
    stackTextStrata = "HIGH",
    stackTextLevel = 13,
    
    -- Duration text
    showDuration = true,
    durationFont = "2002 Bold",
    durationFontSize = 15,
    durationColor = {r = 1, g = 1, b = 1, a = 1},   -- White
    durationOutline = "THICKOUTLINE",
    durationShadow = false,
    durationDecimals = 1,
    showDurationWhenReady = false,
    timerTextAnchor = "BOTTOMRIGHT",
    timerTextOffsetX = -4,
    timerTextOffsetY = 7,
    durationTextStrata = "HIGH",
    durationTextLevel = 13,
    
    -- Ready text
    showReadyText = false,
    readyText = "Ready",
    readyColor = {r = 0.3, g = 1, b = 0.3, a = 1},
    
    -- Name text
    showName = true,
    nameFont = "2002 Bold",
    nameFontSize = 14,
    nameColor = {r = 1, g = 1, b = 1, a = 1},
    nameOutline = "THICKOUTLINE",
    nameShadow = false,
    nameAnchor = "TOP",
    nameOffsetX = -35,
    nameOffsetY = 4,
    nameTextStrata = "HIGH",
    nameTextLevel = 13,
    
    -- Charge bar specifics
    chargeDisplayMode = "slots",         -- Progressive slot-based display
    slotHeight = 25,
    slotSpacing = 3,
    showTickMarks = false,
  },
  noprog = {
    -- No Prog style: Classic ArcUI aura bar style (like legacy cooldownBars)
    -- Single solid bar with tick marks for charge divisions
    -- This style mimics the original cooldownBars from ArcUI_Display
    width = 200,
    height = 20,
    frameWidth = 200,
    frameHeight = 20,
    showBorder = true,
    drawnBorderThickness = 2,
    borderColor = {r = 0, g = 0, b = 0, a = 1},
    useGradient = false,
    showBarIcon = true,
    barIconSize = 20,
    barIconAnchor = "LEFT",
    barIconShowBorder = true,
    barIconBorderColor = {r = 0, g = 0, b = 0, a = 1},
    barColor = {r = 0.2, g = 0.8, b = 1, a = 1},      -- Cyan (classic ArcUI)
    useDifferentFullColor = false,
    backgroundColor = {r = 0.2, g = 0.2, b = 0.2, a = 0.8},
    showName = false,
    showDuration = false,
    showReadyText = false,
    -- Charge bar specifics - unified bar with tick marks
    chargeDisplayMode = "unified",   -- Single bar, not progressive slots
    slotHeight = 20,
    slotSpacing = 0,
    showTickMarks = true,
    tickThickness = 1,
    tickColor = {r = 0, g = 0, b = 0, a = 1},
    showText = true,
    fontSize = 18,
    textColor = {r = 1, g = 1, b = 1, a = 1},
    textAnchor = "CENTER",
  },
}

-- Helper to deep copy a table
local function DeepCopy(orig)
  if type(orig) ~= "table" then return orig end
  local copy = {}
  for k, v in pairs(orig) do
    if type(v) == "table" then
      copy[k] = DeepCopy(v)
    else
      copy[k] = v
    end
  end
  return copy
end

-- Get or create cooldown bar config (matches ns.API.GetBarConfig pattern)
function ns.CooldownBars.GetBarConfig(spellID, barType)
  if not ns.db or not ns.db.char then return nil end
  
  -- Ensure structure exists
  ns.db.char.cooldownBarConfigs = ns.db.char.cooldownBarConfigs or {}
  ns.db.char.cooldownBarConfigs[spellID] = ns.db.char.cooldownBarConfigs[spellID] or {}
  
  local configs = ns.db.char.cooldownBarConfigs[spellID]
  
  if not configs[barType] then
    -- Create default config structure matching DB.lua format
    configs[barType] = {
      tracking = {
        enabled = true,
        spellID = spellID,
        barType = barType,  -- "cooldown", "charge", "resource"
        preset = "arcui",   -- "simple" or "arcui"
      },
      display = DeepCopy(DISPLAY_DEFAULTS),
      behavior = {
        hideOutOfCombat = false,
        hideWhenReady = false,
        showOnSpecs = { GetSpecialization() or 1 },  -- Default to current spec only
      },
    }
    
    -- Apply preset defaults
    local preset = PRESETS.arcui
    for k, v in pairs(preset) do
      if type(v) == "table" then
        configs[barType].display[k] = DeepCopy(v)
      else
        configs[barType].display[k] = v
      end
    end
    
    -- Adjust defaults based on bar type
    if barType == "charge" then
      -- Charge bar defaults are now in PRESETS.arcui
      -- No additional overrides needed
    elseif barType == "resource" then
      configs[barType].display.barColor = {r = 0.8, g = 0.2, b = 0.8, a = 1}
    end
  end
  
  -- Ensure behavior.showOnSpecs exists for older configs
  if not configs[barType].behavior then
    configs[barType].behavior = {}
  end
  if not configs[barType].behavior.showOnSpecs then
    configs[barType].behavior.showOnSpecs = {}
  end
  
  return configs[barType]
end

-- Apply preset to a bar
function ns.CooldownBars.ApplyPreset(spellID, barType, presetName)
  local cfg = ns.CooldownBars.GetBarConfig(spellID, barType)
  if not cfg then return end
  
  local preset = PRESETS[presetName]
  if not preset then return end
  
  cfg.tracking.preset = presetName
  
  for k, v in pairs(preset) do
    if type(v) == "table" then
      cfg.display[k] = DeepCopy(v)
    else
      cfg.display[k] = v
    end
  end
  
  ns.CooldownBars.ApplyAppearance(spellID, barType)
end

-- Check if bar should show for current spec (matches TrackingOptions pattern)
function ns.CooldownBars.ShouldShowForCurrentSpec(spellID, barType)
  local cfg = ns.CooldownBars.GetBarConfig(spellID, barType)
  if not cfg then return true end  -- No config = show
  
  local showOnSpecs = cfg.behavior and cfg.behavior.showOnSpecs
  if not showOnSpecs or #showOnSpecs == 0 then
    return true  -- Empty = show on all specs
  end
  
  local currentSpec = GetSpecialization() or 1
  for _, spec in ipairs(showOnSpecs) do
    if spec == currentSpec then
      return true
    end
  end
  
  return false
end

-- Update bar visibility when spec changes - just shows/hides, doesn't destroy
function ns.CooldownBars.UpdateBarVisibilityForSpec()
  local currentSpec = GetSpecialization() or 1
  Log("UpdateBarVisibilityForSpec: spec " .. currentSpec)
  
  -- Update cooldown bars
  for spellID, barIndex in pairs(ns.CooldownBars.activeCooldowns) do
    local barData = ns.CooldownBars.bars[barIndex]
    if barData and barData.frame then
      local shouldShow = ns.CooldownBars.ShouldShowForCurrentSpec(spellID, "cooldown")
      barData.hiddenBySpec = not shouldShow  -- Flag for update functions
      if shouldShow then
        barData.frame:Show()
        -- Show FREE text frames if they exist and are in use
        if barData.durationTextFrame and barData.useFreeDurationText then
          barData.durationTextFrame:Show()
        end
        if barData.readyTextFrame and barData.useFreeReadyText then
          barData.readyTextFrame:Show()
        end
      else
        barData.frame:Hide()
        -- Hide FREE text frames (parented to UIParent, won't auto-hide)
        if barData.durationTextFrame then
          barData.durationTextFrame:Hide()
        end
        if barData.readyTextFrame then
          barData.readyTextFrame:Hide()
        end
      end
    end
  end
  
  -- Update charge bars
  for spellID, barIndex in pairs(ns.CooldownBars.activeCharges) do
    local barData = ns.CooldownBars.chargeBars[barIndex]
    if barData and barData.frame then
      local shouldShow = ns.CooldownBars.ShouldShowForCurrentSpec(spellID, "charge")
      barData.hiddenBySpec = not shouldShow  -- Flag for update functions
      if shouldShow then
        -- Re-query charge info when showing (may have changed with spec)
        local chargeInfo = C_Spell.GetSpellCharges(spellID)
        if chargeInfo then
          -- Get maxCharges safely (could be secret)
          local newMax = barData.maxCharges or 2
          if chargeInfo.maxCharges then
            if not issecretvalue or not issecretvalue(chargeInfo.maxCharges) then
              newMax = chargeInfo.maxCharges
            end
          end
          
          local oldMax = barData.maxCharges
          barData.maxCharges = newMax
          -- Note: cooldownDuration is secret, accessed via cachedChargeInfo
          barData.maxText:SetText("/" .. barData.maxCharges)
          
          -- If max charges changed, recreate slots (only compare non-secret values)
          if oldMax and oldMax ~= newMax then
            Log("Charge count changed for " .. spellID .. ": " .. (oldMax or 0) .. " -> " .. barData.maxCharges)
            -- Apply settings will recreate slots with correct count
            C_Timer.After(0.01, function()
              ns.CooldownBars.ApplyAppearance(spellID, "charge")
            end)
          end
        end
        barData.frame:Show()
        -- Show FREE text frames if they exist and are in use
        if barData.stackTextFrame and barData.useStackTextFrame then
          barData.stackTextFrame:Show()
        end
        if barData.timerTextFrame and barData.useFreeTimerText then
          barData.timerTextFrame:Show()
        end
      else
        barData.frame:Hide()
        -- Hide FREE text frames (parented to UIParent, won't auto-hide)
        if barData.stackTextFrame then
          barData.stackTextFrame:Hide()
        end
        if barData.timerTextFrame then
          barData.timerTextFrame:Hide()
        end
      end
    end
  end
  
  -- Update resource bars
  for spellID, barIndex in pairs(ns.CooldownBars.activeResources) do
    local barData = ns.CooldownBars.resourceBars[barIndex]
    if barData and barData.frame then
      local shouldShow = ns.CooldownBars.ShouldShowForCurrentSpec(spellID, "resource")
      barData.hiddenBySpec = not shouldShow  -- Flag for update functions
      if shouldShow then
        barData.frame:Show()
      else
        barData.frame:Hide()
      end
    end
  end
  
  Log("UpdateBarVisibilityForSpec complete")
end

-- Alias for compatibility
ns.CooldownBars.RefreshBarsForSpec = ns.CooldownBars.UpdateBarVisibilityForSpec

-- Helper for outline flags (matches Display.lua)
local function GetOutlineFlag(outlineSetting)
  if outlineSetting == "NONE" or outlineSetting == "" then
    return ""
  elseif outlineSetting == "OUTLINE" then
    return "OUTLINE"
  elseif outlineSetting == "THICKOUTLINE" then
    return "THICKOUTLINE"
  elseif outlineSetting == "MONOCHROME" then
    return "MONOCHROME"
  else
    return "THICKOUTLINE"
  end
end

-- Helper for text shadow (matches Display.lua)
local function ApplyTextShadow(fontString, enabled)
  if enabled then
    fontString:SetShadowColor(0, 0, 0, 1)
    fontString:SetShadowOffset(1, -1)
  else
    fontString:SetShadowOffset(0, 0)
  end
end

-- Helper to get texture path
local function GetTexturePath(textureName)
  if LSM then
    local path = LSM:Fetch("statusbar", textureName)
    if path then return path end
  end
  if textureName == "Blizzard" then
    return "Interface\\TargetingFrame\\UI-StatusBar"
  elseif textureName == "Smooth" then
    return "Interface\\Buttons\\WHITE8x8"
  end
  return "Interface\\TargetingFrame\\UI-StatusBar"
end

-- Helper to convert custom anchor names to valid WoW anchor points
local function GetValidAnchor(anchor)
  local anchorMap = {
    -- Custom names to valid WoW anchors
    ["CENTERLEFT"] = "LEFT",
    ["CENTERRIGHT"] = "RIGHT",
    ["OUTERTOP"] = "TOP",
    ["OUTERBOTTOM"] = "BOTTOM",
    ["OUTERLEFT"] = "LEFT",
    ["OUTERRIGHT"] = "RIGHT",
    ["OUTERCENTERLEFT"] = "LEFT",
    ["OUTERCENTERRIGHT"] = "RIGHT",
    ["OUTERTOPLEFT"] = "TOPLEFT",
    ["OUTERTOPRIGHT"] = "TOPRIGHT",
    ["OUTERBOTTOMLEFT"] = "BOTTOMLEFT",
    ["OUTERBOTTOMRIGHT"] = "BOTTOMRIGHT",
    -- FREE is handled specially - don't pass to SetPoint
    ["FREE"] = nil,
  }
  return anchorMap[anchor] or anchor
end

-- ===================================================================
-- APPLY APPEARANCE (matches Display.lua pattern)
-- ===================================================================
function ns.CooldownBars.ApplyAppearance(spellID, barType)
  local cfg = ns.CooldownBars.GetBarConfig(spellID, barType)
  if not cfg then return end
  
  local display = cfg.display
  local barData = nil
  
  -- Get the bar frame data
  if barType == "cooldown" then
    local barIndex = ns.CooldownBars.activeCooldowns[spellID]
    if barIndex then barData = ns.CooldownBars.bars[barIndex] end
  elseif barType == "charge" then
    local barIndex = ns.CooldownBars.activeCharges[spellID]
    if barIndex then barData = ns.CooldownBars.chargeBars[barIndex] end
  elseif barType == "resource" then
    local barIndex = ns.CooldownBars.activeResources[spellID]
    if barIndex then barData = ns.CooldownBars.resourceBars[barIndex] end
  end
  
  if not barData or not barData.frame then return end
  
  local frame = barData.frame
  local isVertical = (display.barOrientation == "vertical")
  
  -- ═══════════════════════════════════════════════════════════════
  -- SCALE - Apply to SIZE instead of SetScale() to prevent position drift
  -- (Same pattern as ArcUI_Display.lua aura bars)
  -- ═══════════════════════════════════════════════════════════════
  local scale = display.barScale or 1.0
  -- NOTE: We do NOT use SetScale() - it causes position drift when scale changes
  -- Instead, we multiply all dimensions by scale below
  
  -- ═══════════════════════════════════════════════════════════════
  -- FRAME STRATA - Set bar frame strata (default HIGH)
  -- ═══════════════════════════════════════════════════════════════
  local barStrata = display.barFrameStrata or "HIGH"
  frame:SetFrameStrata(barStrata)
  local barLevel = display.barFrameLevel or 10
  frame:SetFrameLevel(barLevel)
  
  if barType == "charge" then
    -- CRITICAL: Always refresh maxCharges from API (may have changed with spec/talents)
    local chargeInfo = C_Spell.GetSpellCharges(barData.spellID)
    if chargeInfo then
      -- Get maxCharges safely (could be secret in combat)
      if chargeInfo.maxCharges then
        if not issecretvalue or not issecretvalue(chargeInfo.maxCharges) then
          barData.maxCharges = chargeInfo.maxCharges
        end
        -- If secret, keep existing barData.maxCharges value
      end
      -- Note: cooldownDuration is secret, accessed via cachedChargeInfo in UpdateChargeBar
      if barData.maxText and barData.maxCharges then
        barData.maxText:SetText("/" .. barData.maxCharges)
      end
      if barData.stackMaxText and barData.maxCharges then
        barData.stackMaxText:SetText("/" .. barData.maxCharges)
      end
    end
    
    -- Base dimensions (before scale)
    local iconSize = (display.barIconSize or 30) * scale
    local padding = (display.barPadding or 2) * scale
    local slotHeight = (display.slotHeight or 14) * scale  -- Thickness of each slot bar
    local slotSpacing = (display.slotSpacing or 3) * scale
    local slotsWidth = (display.width or 100) * scale      -- Width of the slot fills (independent)
    
    -- Frame dimensions are independent of slots (like frameHeight)
    local frameWidth = (display.frameWidth or 200) * scale
    local frameHeight = (display.frameHeight or 38) * scale
    
    -- Size - SWAP width and height for vertical bars (SAME AS AURA BARS)
    if isVertical then
      frame:SetSize(frameHeight, frameWidth)  -- Swap dimensions!
    else
      frame:SetSize(frameWidth, frameHeight)  -- Normal horizontal
    end
    
    -- Icon positioning - supports LEFT (start) or RIGHT (end) anchor
    local iconAnchor = display.barIconAnchor or "LEFT"
    local iconBarSpacing = (display.iconBarSpacing or 0) * scale  -- Bar Gap
    
    if barData.icon then
      barData.icon:SetSize(iconSize, iconSize)
      barData.icon:ClearAllPoints()
      if isVertical then
        -- For vertical: icon at top or bottom
        if iconAnchor == "RIGHT" then
          -- Icon at bottom
          barData.icon:SetPoint("BOTTOM", frame, "BOTTOM", 0, padding)
        else
          -- Icon at top (default)
          barData.icon:SetPoint("TOP", frame, "TOP", 0, -padding)
        end
      else
        -- For horizontal: icon at left or right
        if iconAnchor == "RIGHT" then
          -- Icon at right (end)
          barData.icon:SetPoint("RIGHT", frame, "RIGHT", -padding, 0)
        else
          -- Icon at left (start, default)
          barData.icon:SetPoint("LEFT", frame, "LEFT", padding, 0)
        end
      end
    end
    
    -- Slots container positioning - relative to icon with Bar Gap support
    if barData.slotsContainer then
      barData.slotsContainer:ClearAllPoints()
      if isVertical then
        -- Vertical: container centered horizontally, positioned vertically
        if display.showBarIcon ~= false and barData.icon then
          if iconAnchor == "RIGHT" then
            -- Icon at bottom, slots above it
            barData.slotsContainer:SetPoint("BOTTOM", barData.icon, "TOP", 0, iconBarSpacing)
          else
            -- Icon at top, slots below it
            barData.slotsContainer:SetPoint("TOP", barData.icon, "BOTTOM", 0, -iconBarSpacing)
          end
        else
          barData.slotsContainer:SetPoint("CENTER", frame, "CENTER", 0, 0)
        end
        -- Container is narrow and tall for vertical (swapped)
        barData.slotsContainer:SetSize(slotHeight, slotsWidth)
      else
        -- Horizontal: container to left or right of icon, centered vertically
        if display.showBarIcon ~= false and barData.icon then
          if iconAnchor == "RIGHT" then
            -- Icon at right, slots to left of it
            barData.slotsContainer:SetPoint("RIGHT", barData.icon, "LEFT", -iconBarSpacing, 0)
          else
            -- Icon at left, slots to right of it (default)
            barData.slotsContainer:SetPoint("LEFT", barData.icon, "RIGHT", iconBarSpacing, 0)
          end
        else
          barData.slotsContainer:SetPoint("CENTER", frame, "CENTER", 0, 0)
        end
        barData.slotsContainer:SetSize(slotsWidth, slotHeight)
      end
    end
    
    -- Position name text (using container frame for independent frame level)
    local nameContainer = barData.nameTextContainer
    if nameContainer and barData.nameText then
      nameContainer:ClearAllPoints()
      local nameOffsetX = display.nameOffsetX or 0
      local nameOffsetY = display.nameOffsetY or 0
      local nameAnchor = display.nameAnchor or (isVertical and "TOP" or "BOTTOMLEFT")
      local validAnchor = GetValidAnchor(nameAnchor)
      
      if validAnchor then
        if isVertical then
          -- Vertical: name at top (was at bottom when horizontal)
          nameContainer:SetPoint("BOTTOM", frame, "TOP", nameOffsetX, 2 + nameOffsetY)
          nameContainer:SetSize(frameHeight - 4, 20)  -- Use swapped width
          barData.nameText:SetJustifyH("CENTER")
        else
          -- Map anchor to appropriate point on slots container
          if nameAnchor == "TOPLEFT" or nameAnchor == "TOP" or nameAnchor == "TOPRIGHT" then
            if barData.slotsContainer then
              nameContainer:SetPoint("BOTTOMLEFT", barData.slotsContainer, "TOPLEFT", nameOffsetX, 2 + nameOffsetY)
            else
              nameContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", padding + nameOffsetX, -2 + nameOffsetY)
            end
          elseif nameAnchor == "BOTTOMLEFT" or nameAnchor == "BOTTOM" or nameAnchor == "BOTTOMRIGHT" then
            if barData.slotsContainer then
              nameContainer:SetPoint("TOPLEFT", barData.slotsContainer, "BOTTOMLEFT", nameOffsetX, -2 + nameOffsetY)
            else
              nameContainer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", padding + nameOffsetX, 2 + nameOffsetY)
            end
          else
            -- Default: above slots
            if barData.slotsContainer then
              nameContainer:SetPoint("BOTTOMLEFT", barData.slotsContainer, "TOPLEFT", nameOffsetX, 2 + nameOffsetY)
            else
              nameContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", padding + nameOffsetX, -2 + nameOffsetY)
            end
          end
          nameContainer:SetSize(slotsWidth - 10, 20)
          barData.nameText:SetJustifyH("LEFT")
        end
        nameContainer:Show()
      end
    end
    
    -- Recreate slots with appropriate dimensions and orientation
    if barData.maxCharges and barData.maxCharges > 0 then
      CreateChargeSlots(barData, barData.maxCharges, slotsWidth, slotHeight, slotSpacing, isVertical, display)
    end
    
    -- Position charge count text using settings (works for both orientations)
    local chargeAnchor = display.chargeTextAnchor or "TOPRIGHT"
    local chargeOffsetX = display.chargeTextOffsetX or -4
    local chargeOffsetY = display.chargeTextOffsetY or -2
    
    -- Get strata settings for stack text
    local stackStrata = display.stackTextStrata or display.barFrameStrata or "HIGH"
    local stackLevel = display.stackTextLevel or (display.barFrameLevel or 10) + 3
    
    -- maxText shows "/2", currentText shows "2"
    -- showText controls both, showMaxText controls just the "/2" part
    
    -- Check if FREE mode - handle separately
    if chargeAnchor == "FREE" then
      -- Create or use container frame for dragging both texts together
      if not barData.stackTextFrame then
        barData.stackTextFrame = CreateFrame("Frame", nil, UIParent)  -- Parent to UIParent for independent movement
        barData.stackTextFrame:SetMovable(true)
        barData.stackTextFrame:SetClampedToScreen(true)
        barData.stackTextFrame:RegisterForDrag("LeftButton")
        
        -- Create new FontStrings parented to this frame
        barData.stackCurrentText = barData.stackTextFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        barData.stackMaxText = barData.stackTextFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      end
      
      -- Apply configurable frame width
      local stackFrameWidth = display.stackTextFrameWidth or 80
      barData.stackTextFrame:SetSize(stackFrameWidth, 30)
      
      -- Store display reference for drag scripts to access lock state dynamically
      barData.stackTextFrame.displayRef = display
      barData.stackTextFrame:SetScript("OnDragStart", function(self)
        local locked = self.displayRef and self.displayRef.stackTextLocked
        if not locked then
          self:StartMoving()
        end
      end)
      barData.stackTextFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if self.displayRef then
          self.displayRef.chargeTextPosition = { point = point, relPoint = relPoint, x = x, y = y }
        end
      end)
      
      -- Enable mouse (lock state checked in OnDragStart)
      barData.stackTextFrame:EnableMouse(true)
      
      -- Position from saved or default
      barData.stackTextFrame:ClearAllPoints()
      if display.chargeTextPosition then
        barData.stackTextFrame:SetPoint(display.chargeTextPosition.point, UIParent, display.chargeTextPosition.relPoint, display.chargeTextPosition.x, display.chargeTextPosition.y)
      else
        -- Default: position relative to frame
        local fX, fY = frame:GetCenter()
        if fX and fY then
          local fW = frame:GetWidth() / 2
          barData.stackTextFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", fX + fW - 20, fY + 10)
        else
          barData.stackTextFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", chargeOffsetX, chargeOffsetY)
        end
      end
      
      barData.stackTextFrame:SetFrameStrata(stackStrata)
      barData.stackTextFrame:SetFrameLevel(stackLevel)
      barData.stackTextFrame:Show()
      
      -- Position text within the draggable frame
      barData.stackMaxText:ClearAllPoints()
      barData.stackMaxText:SetPoint("RIGHT", barData.stackTextFrame, "RIGHT", 0, 0)
      barData.stackCurrentText:ClearAllPoints()
      if display.showMaxText == false then
        barData.stackCurrentText:SetPoint("RIGHT", barData.stackTextFrame, "RIGHT", 0, 0)
      else
        barData.stackCurrentText:SetPoint("RIGHT", barData.stackMaxText, "LEFT", 0, 0)
      end
      
      -- Hide original texts, use stack frame texts instead
      if barData.maxText then barData.maxText:Hide() end
      if barData.currentText then barData.currentText:Hide() end
      if barData.chargeTextContainer then barData.chargeTextContainer:Hide() end
      
      -- Flag to use stack frame texts in update
      barData.useStackTextFrame = true
    else
      -- Normal anchored mode - hide stack frame if it exists
      if barData.stackTextFrame then 
        barData.stackTextFrame:Hide()
        barData.useStackTextFrame = false
      end
      
      -- Show original texts via their container
      if barData.chargeTextContainer then
        barData.chargeTextContainer:Show()
      end
      if barData.maxText then barData.maxText:Show() end
      if barData.currentText then barData.currentText:Show() end
      
      -- Get valid WoW anchor point
      local validChargeAnchor = GetValidAnchor(chargeAnchor) or "TOPRIGHT"
      
      -- Position the chargeTextContainer (contains both currentText and maxText)
      if barData.chargeTextContainer then
        barData.chargeTextContainer:ClearAllPoints()
        barData.chargeTextContainer:SetPoint(validChargeAnchor, frame, validChargeAnchor, chargeOffsetX, chargeOffsetY)
        
        -- Update internal text positioning based on showMaxText
        if barData.maxText then
          barData.maxText:ClearAllPoints()
          barData.maxText:SetPoint("RIGHT", barData.chargeTextContainer, "RIGHT", 0, 0)
        end
        if barData.currentText then
          barData.currentText:ClearAllPoints()
          if display.showMaxText == false or display.showText == false then
            -- When max is hidden, current text takes right position
            barData.currentText:SetPoint("RIGHT", barData.chargeTextContainer, "RIGHT", 0, 0)
          else
            -- Normal: current text to left of max text
            barData.currentText:SetPoint("RIGHT", barData.maxText, "LEFT", 0, 0)
          end
        end
      else
        -- Fallback: direct positioning (legacy bars without container)
        if barData.maxText then
          barData.maxText:ClearAllPoints()
          barData.maxText:SetPoint(validChargeAnchor, frame, validChargeAnchor, chargeOffsetX, chargeOffsetY)
        end
        if barData.currentText then
          barData.currentText:ClearAllPoints()
          if display.showMaxText == false or display.showText == false then
            barData.currentText:SetPoint(validChargeAnchor, frame, validChargeAnchor, chargeOffsetX, chargeOffsetY)
          else
            barData.currentText:SetPoint("RIGHT", barData.maxText, "LEFT", 0, 0)
          end
        end
      end
    end
    
    -- Position timer text using settings
    local timerAnchor = display.timerTextAnchor or "BOTTOMRIGHT"
    local timerOffsetX = display.timerTextOffsetX or -4
    local timerOffsetY = display.timerTextOffsetY or 2
    
    -- Get strata settings for duration text
    local durationStrata = display.durationTextStrata or display.barFrameStrata or "HIGH"
    local durationLevel = display.durationTextLevel or (display.barFrameLevel or 10) + 3
    
    if barData.timerText then
      -- Set up FREE mode dragging for timer text
      if timerAnchor == "FREE" then
        -- Create wrapper frame if needed
        if not barData.timerTextFrame then
          barData.timerTextFrame = CreateFrame("Frame", nil, UIParent)  -- Parent to UIParent
          barData.timerTextFrame:SetMovable(true)
          barData.timerTextFrame:SetClampedToScreen(true)
          barData.timerTextFrame:RegisterForDrag("LeftButton")
          
          -- Create new FontString for this frame
          barData.freeTimerText = barData.timerTextFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          barData.freeTimerText:SetPoint("CENTER", barData.timerTextFrame, "CENTER", 0, 0)
        end
        
        -- Apply configurable frame width
        local durationFrameWidth = display.durationTextFrameWidth or 60
        barData.timerTextFrame:SetSize(durationFrameWidth, 25)
        
        -- Store display reference for drag scripts to access lock state dynamically
        barData.timerTextFrame.displayRef = display
        barData.timerTextFrame:SetScript("OnDragStart", function(self)
          local locked = self.displayRef and self.displayRef.durationTextLocked
          if not locked then
            self:StartMoving()
          end
        end)
        barData.timerTextFrame:SetScript("OnDragStop", function(self)
          self:StopMovingOrSizing()
          local point, _, relPoint, x, y = self:GetPoint()
          if self.displayRef then
            self.displayRef.timerTextPosition = { point = point, relPoint = relPoint, x = x, y = y }
          end
        end)
        
        -- Enable mouse (lock state checked in OnDragStart)
        barData.timerTextFrame:EnableMouse(true)
        
        barData.timerTextFrame:ClearAllPoints()
        if display.timerTextPosition then
          barData.timerTextFrame:SetPoint(display.timerTextPosition.point, UIParent, display.timerTextPosition.relPoint, display.timerTextPosition.x, display.timerTextPosition.y)
        else
          -- Default: position relative to frame
          local fX, fY = frame:GetCenter()
          if fX and fY then
            local fW = frame:GetWidth() / 2
            barData.timerTextFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", fX + fW - 20, fY - 10)
          else
            barData.timerTextFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", timerOffsetX, timerOffsetY)
          end
        end
        barData.timerTextFrame:SetFrameStrata(durationStrata)
        barData.timerTextFrame:SetFrameLevel(durationLevel)
        barData.timerTextFrame:Show()
        
        -- Hide original timer text and container, use free timer text
        barData.timerText:Hide()
        if barData.timerTextContainer then barData.timerTextContainer:Hide() end
        barData.useFreeTimerText = true
      else
        -- Hide timer frame if it exists
        if barData.timerTextFrame then 
          barData.timerTextFrame:Hide()
          barData.useFreeTimerText = false
        end
        -- Show original timer text
        barData.timerText:Show()
        -- Get valid anchor
        local validTimerAnchor = GetValidAnchor(timerAnchor) or "BOTTOMRIGHT"
        -- Position the container frame (which contains the timerText)
        if barData.timerTextContainer then
          barData.timerTextContainer:ClearAllPoints()
          barData.timerTextContainer:SetPoint(validTimerAnchor, frame, validTimerAnchor, timerOffsetX, timerOffsetY)
          barData.timerTextContainer:Show()
        else
          barData.timerText:ClearAllPoints()
          barData.timerText:SetPoint(validTimerAnchor, frame, validTimerAnchor, timerOffsetX, timerOffsetY)
        end
      end
    end
    
    -- Get strata settings for name text  
    local nameStrata = display.nameTextStrata or display.barFrameStrata or "HIGH"
    local nameLevel = display.nameTextLevel or (display.barFrameLevel or 10) + 3
    
    -- ═══════════════════════════════════════════════════════════════
    -- SET FRAME STRATA/LEVEL for text container frames
    -- Container frames allow independent frame level even when anchored
    -- ═══════════════════════════════════════════════════════════════
    
    -- Duration/timer text - use container frame for level control
    if barData.timerTextContainer then
      barData.timerTextContainer:SetFrameStrata(durationStrata)
      barData.timerTextContainer:SetFrameLevel(durationLevel)
    end
    if barData.timerText then
      barData.timerText:SetDrawLayer("OVERLAY", 7)
    end
    -- FREE mode timer frame (separate from timerTextContainer)
    if barData.timerTextFrame then
      barData.timerTextFrame:SetFrameStrata(durationStrata)
      barData.timerTextFrame:SetFrameLevel(durationLevel)
    end
    if barData.freeTimerText then
      barData.freeTimerText:SetDrawLayer("OVERLAY", 7)
    end
    
    -- Name text - use container frame for level control
    if barData.nameTextContainer then
      barData.nameTextContainer:SetFrameStrata(nameStrata)
      barData.nameTextContainer:SetFrameLevel(nameLevel)
    end
    if barData.nameText then 
      barData.nameText:SetDrawLayer("OVERLAY", 7)
    end
    
    -- Charge text (currentText + maxText) - use container frame for level control
    if barData.chargeTextContainer then
      barData.chargeTextContainer:SetFrameStrata(stackStrata)
      barData.chargeTextContainer:SetFrameLevel(stackLevel)
    end
    if barData.currentText then barData.currentText:SetDrawLayer("OVERLAY", 7) end
    if barData.maxText then barData.maxText:SetDrawLayer("OVERLAY", 7) end
    -- FREE mode stack text frame
    if barData.stackTextFrame then
      barData.stackTextFrame:SetFrameStrata(stackStrata)
      barData.stackTextFrame:SetFrameLevel(stackLevel)
    end
    if barData.stackCurrentText then barData.stackCurrentText:SetDrawLayer("OVERLAY", 7) end
    if barData.stackMaxText then barData.stackMaxText:SetDrawLayer("OVERLAY", 7) end
    
  else
    -- For cooldown/resource bars: use scale multiplier on dimensions (existing behavior)
    local scaledWidth = (display.width or 200) * scale
    local scaledHeight = (display.height or 20) * scale
    
    -- For cooldown/resource bars: width/height controls the frame directly
    if isVertical then
      frame:SetSize(scaledHeight, scaledWidth)  -- Swap for vertical
    else
      frame:SetSize(scaledWidth, scaledHeight)  -- Normal horizontal
    end
  end
  
  frame:SetAlpha(display.opacity or 1.0)
  
  -- ═══════════════════════════════════════════════════════════════
  -- POSITION
  -- ═══════════════════════════════════════════════════════════════
  if display.barPosition then
    frame:ClearAllPoints()
    frame:SetPoint(
      display.barPosition.point or "CENTER",
      UIParent,
      display.barPosition.relPoint or "CENTER",
      display.barPosition.x or 0,
      display.barPosition.y or 100
    )
  end
  
  -- Movable
  frame:EnableMouse(true)
  frame:SetMovable(display.barMovable ~= false)
  if display.barMovable ~= false then
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
      if not InCombatLockdown() then
        self:StartMoving()
      end
    end)
    frame:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      -- Save position as CENTER-based so scaling grows from center
      local centerX, centerY = self:GetCenter()
      if centerX and centerY then
        local uiCenterX, uiCenterY = UIParent:GetCenter()
        display.barPosition = {
          point = "CENTER",
          relPoint = "CENTER",
          x = centerX - uiCenterX,
          y = centerY - uiCenterY,
        }
      else
        -- Fallback to direct GetPoint if GetCenter fails
        local point, _, relPoint, x, y = self:GetPoint()
        display.barPosition = {
          point = point,
          relPoint = relPoint,
          x = x,
          y = y,
        }
      end
    end)
  end
  
  -- ═══════════════════════════════════════════════════════════════
  -- BACKGROUND
  -- ═══════════════════════════════════════════════════════════════
  if display.showBackground then
    local bgColor = display.backgroundColor or {r = 0.1, g = 0.1, b = 0.1, a = 0.8}
    -- Ensure color values exist
    local r = bgColor.r or 0.1
    local g = bgColor.g or 0.1
    local b = bgColor.b or 0.1
    local a = bgColor.a or 0.8
    
    frame:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = display.showBorder and "Interface\\Buttons\\WHITE8x8" or nil,
      edgeSize = display.drawnBorderThickness or 2,
    })
    frame:SetBackdropColor(r, g, b, a)
    
    if display.showBorder then
      local br, bg, bb, ba
      
      -- Check for class color border
      if display.useClassColorBorder then
        local _, playerClass = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[playerClass]
        if classColor then
          br = classColor.r
          bg = classColor.g
          bb = classColor.b
          ba = 1
        else
          -- Fallback to default
          br, bg, bb, ba = 0.3, 0.3, 0.3, 1
        end
      else
        local borderColor = display.borderColor or {r = 0.3, g = 0.3, b = 0.3, a = 1}
        br = borderColor.r or 0.3
        bg = borderColor.g or 0.3
        bb = borderColor.b or 0.3
        ba = borderColor.a or 1
      end
      
      frame:SetBackdropBorderColor(br, bg, bb, ba)
    end
  else
    frame:SetBackdrop(nil)
  end
  
  -- ═══════════════════════════════════════════════════════════════
  -- BAR TEXTURE, COLOR, AND ORIENTATION
  -- ═══════════════════════════════════════════════════════════════
  if barData.bar then
    local texturePath = GetTexturePath(display.texture or "Blizzard")
    barData.bar:SetStatusBarTexture(texturePath)
    
    local barColor = display.barColor or {r = 1, g = 0.5, b = 0.2, a = 1}
    local r = barColor.r or 1
    local g = barColor.g or 0.5
    local b = barColor.b or 0.2
    local a = barColor.a or 1
    barData.bar:SetStatusBarColor(r, g, b, a)
    barData.customColor = {r = r, g = g, b = b, a = a}  -- Store for update functions
    
    -- Set orientation (matches Display.lua pattern)
    local barOrientation = isVertical and "VERTICAL" or "HORIZONTAL"
    barData.bar:SetOrientation(barOrientation)
    
    -- Set reverse fill
    barData.bar:SetReverseFill(display.barReverseFill or false)
    
    -- Store fill mode for duration bars (used by update function)
    barData.fillMode = display.durationBarFillMode or "drain"
    
    -- Background texture
    if barData.barBg then
      barData.barBg:SetTexture(texturePath)
      barData.barBg:SetVertexColor(0.15, 0.15, 0.15, 0.9)
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════
  -- BAR ICON
  -- ═══════════════════════════════════════════════════════════════
  if barData.icon then
    local iconSize = display.barIconSize or 30
    barData.icon:SetSize(iconSize, iconSize)
    
    if display.showBarIcon then
      barData.icon:Show()
      
      if barType == "charge" then
        -- Charge bars: positioning already handled in SIZE section
        -- Just ensure icon is visible
      elseif barData.bar then
        -- Cooldown/Resource bars: position bar relative to icon
        local padding = display.barPadding or 2
        local iconBarSpacing = display.iconBarSpacing or 4
        local iconAnchor = display.barIconAnchor or "LEFT"
        
        barData.bar:ClearAllPoints()
        barData.icon:ClearAllPoints()
        
        if isVertical then
          -- Vertical: icon at top or bottom
          if iconAnchor == "RIGHT" then
            -- Icon at bottom
            barData.icon:SetPoint("BOTTOM", frame, "BOTTOM", 0, padding)
            barData.bar:SetPoint("BOTTOM", barData.icon, "TOP", 0, iconBarSpacing)
            barData.bar:SetPoint("TOP", frame, "TOP", 0, -padding)
          else
            -- Icon at top (default)
            barData.icon:SetPoint("TOP", frame, "TOP", 0, -padding)
            barData.bar:SetPoint("TOP", barData.icon, "BOTTOM", 0, -iconBarSpacing)
            barData.bar:SetPoint("BOTTOM", frame, "BOTTOM", 0, padding)
          end
          barData.bar:SetPoint("LEFT", frame, "LEFT", padding, 0)
          barData.bar:SetPoint("RIGHT", frame, "RIGHT", -padding, 0)
        else
          -- Horizontal: icon at left or right
          if iconAnchor == "RIGHT" then
            -- Icon at right (end)
            barData.icon:SetPoint("RIGHT", frame, "RIGHT", -padding, 0)
            barData.bar:SetPoint("RIGHT", barData.icon, "LEFT", -iconBarSpacing, 0)
            barData.bar:SetPoint("LEFT", frame, "LEFT", padding, 0)
          else
            -- Icon at left (start, default)
            barData.icon:SetPoint("LEFT", frame, "LEFT", padding, 0)
            barData.bar:SetPoint("LEFT", barData.icon, "RIGHT", iconBarSpacing, 0)
            barData.bar:SetPoint("RIGHT", frame, "RIGHT", -padding, 0)
          end
          barData.bar:SetPoint("TOP", frame, "TOP", 0, -padding)
          barData.bar:SetPoint("BOTTOM", frame, "BOTTOM", 0, padding)
        end
      end
    else
      barData.icon:Hide()
      
      if barType == "charge" then
        -- Charge bars: reposition slots to start at frame edge when icon hidden
        local padding = display.barPadding or 2
        if barData.slotsContainer then
          barData.slotsContainer:ClearAllPoints()
          barData.slotsContainer:SetPoint("LEFT", frame, "LEFT", padding, 0)
        end
        -- Reposition name text container when icon hidden (with offsets)
        local nameContainer = barData.nameTextContainer
        if nameContainer then
          local nameOffsetX = display.nameOffsetX or 0
          local nameOffsetY = display.nameOffsetY or 0
          nameContainer:ClearAllPoints()
          if barData.slotsContainer then
            nameContainer:SetPoint("BOTTOMLEFT", barData.slotsContainer, "TOPLEFT", nameOffsetX, 2 + nameOffsetY)
          else
            nameContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", padding + nameOffsetX, -2 + nameOffsetY)
          end
        elseif barData.nameText then
          -- Fallback for legacy bars without container
          local nameOffsetX = display.nameOffsetX or 0
          local nameOffsetY = display.nameOffsetY or 0
          barData.nameText:ClearAllPoints()
          if barData.slotsContainer then
            barData.nameText:SetPoint("BOTTOMLEFT", barData.slotsContainer, "TOPLEFT", nameOffsetX, 2 + nameOffsetY)
          else
            barData.nameText:SetPoint("TOPLEFT", frame, "TOPLEFT", padding + nameOffsetX, -2 + nameOffsetY)
          end
        end
      elseif barData.bar then
        -- Cooldown/Resource bars: bar fills frame
        local padding = display.barPadding or 2
        barData.bar:ClearAllPoints()
        barData.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -padding)
        barData.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -padding, padding)
      end
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════
  -- NAME TEXT
  -- ═══════════════════════════════════════════════════════════════
  if barData.nameText then
    if display.showName then
      barData.nameText:Show()
      if barData.nameTextContainer then barData.nameTextContainer:Show() end
      
      local fontPath = "Fonts\\FRIZQT__.TTF"
      if LSM and display.nameFont then
        local f = LSM:Fetch("font", display.nameFont)
        if f then fontPath = f end
      end
      
      pcall(function()
        barData.nameText:SetFont(fontPath, display.nameFontSize or 12, GetOutlineFlag(display.nameOutline))
      end)
      
      local nameColor = display.nameColor or {r = 1, g = 1, b = 1, a = 1}
      local nr = nameColor.r or 1
      local ng = nameColor.g or 1
      local nb = nameColor.b or 1
      local na = nameColor.a or 1
      barData.nameText:SetTextColor(nr, ng, nb, na)
      ApplyTextShadow(barData.nameText, display.nameShadow)
    else
      barData.nameText:Hide()
      if barData.nameTextContainer then barData.nameTextContainer:Hide() end
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════
  -- DURATION TEXT
  -- ═══════════════════════════════════════════════════════════════
  if barData.text then
    if display.showDuration then
      local fontPath = "Fonts\\FRIZQT__.TTF"
      if LSM and display.durationFont then
        local f = LSM:Fetch("font", display.durationFont)
        if f then fontPath = f end
      end
      
      local outlineFlag = GetOutlineFlag(display.durationOutline)
      pcall(function()
        barData.text:SetFont(fontPath, display.durationFontSize or 14, outlineFlag)
      end)
      
      local durColor = display.durationColor or {r = 1, g = 1, b = 0.5, a = 1}
      local dr = durColor.r or 1
      local dg = durColor.g or 1
      local db = durColor.b or 0.5
      local da = durColor.a or 1
      barData.text:SetTextColor(dr, dg, db, da)
      ApplyTextShadow(barData.text, display.durationShadow)
      
      -- Style FREE mode duration text if it exists (for cooldown bars)
      if barData.freeDurationText then
        pcall(function()
          barData.freeDurationText:SetFont(fontPath, display.durationFontSize or 14, outlineFlag)
        end)
        barData.freeDurationText:SetTextColor(dr, dg, db, da)
        ApplyTextShadow(barData.freeDurationText, display.durationShadow)
      end
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════
  -- CHARGE BAR SPECIFIC: Per-slot styling
  -- ═══════════════════════════════════════════════════════════════
  if barType == "charge" and barData.chargeSlots then
    local barColor = display.barColor or {r = 0.6, g = 0.5, b = 0.2, a = 1}  -- Base bar color
    local slotBgColor = display.slotBackgroundColor or {r = 0.08, g = 0.08, b = 0.08, a = 1}
    
    -- Full charge color: use different color if enabled, otherwise same as bar color
    local fullColor = barColor
    if display.useDifferentFullColor then
      fullColor = display.fullChargeColor or {r = 0.8, g = 0.6, b = 0.2, a = 1}
    end
    
    -- Store colors for UpdateChargeBar to use
    barData.customColor = barColor
    barData.fullColor = fullColor  -- Store full color (may be same as barColor)
    
    -- Apply texture and colors to each slot (with opacity)
    local texturePath = GetTexturePath(display.texture or "Blizzard")
    local opacity = display.opacity or 1.0
    for _, slot in ipairs(barData.chargeSlots) do
      if slot.fullBar then
        slot.fullBar:SetStatusBarTexture(texturePath)
        slot.fullBar:SetStatusBarColor(fullColor.r, fullColor.g, fullColor.b, (fullColor.a or 1) * opacity)
      end
      if slot.rechargeBar then
        slot.rechargeBar:SetStatusBarTexture(texturePath)
        slot.rechargeBar:SetStatusBarColor(barColor.r, barColor.g, barColor.b, (barColor.a or 1) * opacity)
      end
      if slot.background then
        slot.background:SetColorTexture(slotBgColor.r, slotBgColor.g, slotBgColor.b, (slotBgColor.a or 1) * opacity)
      end
    end
    
    -- Timer text styling
    if barData.timerText then
      if display.showDuration then
        local fontPath = "Fonts\\FRIZQT__.TTF"
        if LSM and display.durationFont then
          local f = LSM:Fetch("font", display.durationFont)
          if f then fontPath = f end
        end
        local durColor = display.durationColor or {r = 1, g = 1, b = 0.5, a = 1}
        local outlineFlag = GetOutlineFlag(display.durationOutline)
        
        -- Style original timer text
        pcall(function()
          barData.timerText:SetFont(fontPath, display.durationFontSize or 14, outlineFlag)
        end)
        barData.timerText:SetTextColor(durColor.r, durColor.g, durColor.b, durColor.a or 1)
        ApplyTextShadow(barData.timerText, display.durationShadow)
        
        -- Style FREE mode timer text if it exists
        if barData.freeTimerText then
          pcall(function()
            barData.freeTimerText:SetFont(fontPath, display.durationFontSize or 14, outlineFlag)
          end)
          barData.freeTimerText:SetTextColor(durColor.r, durColor.g, durColor.b, durColor.a or 1)
          ApplyTextShadow(barData.freeTimerText, display.durationShadow)
        end
        
        -- Show appropriate text based on mode
        if barData.useFreeTimerText then
          barData.timerText:Hide()
          if barData.timerTextContainer then barData.timerTextContainer:Hide() end
          if barData.timerTextFrame then barData.timerTextFrame:Show() end
        else
          barData.timerText:Show()
          if barData.timerTextContainer then barData.timerTextContainer:Show() end
          if barData.timerTextFrame then barData.timerTextFrame:Hide() end
        end
      else
        barData.timerText:Hide()
        if barData.timerTextContainer then barData.timerTextContainer:Hide() end
        if barData.timerTextFrame then barData.timerTextFrame:Hide() end
      end
    end
    
    -- Current charge count text styling
    if display.showText then
      local fontPath = "Fonts\\FRIZQT__.TTF"
      if LSM and display.font then
        local f = LSM:Fetch("font", display.font)
        if f then fontPath = f end
      end
      local textColor = display.textColor or {r = 0.5, g = 1, b = 0.8, a = 1}
      local outlineFlag = GetOutlineFlag(display.textOutline)
      
      -- Style original current text
      if barData.currentText then
        pcall(function()
          barData.currentText:SetFont(fontPath, display.fontSize or 14, outlineFlag)
        end)
        barData.currentText:SetTextColor(textColor.r, textColor.g, textColor.b, textColor.a or 1)
        ApplyTextShadow(barData.currentText, display.textShadow)
      end
      
      -- Style FREE mode current text if it exists
      if barData.stackCurrentText then
        pcall(function()
          barData.stackCurrentText:SetFont(fontPath, display.fontSize or 14, outlineFlag)
        end)
        barData.stackCurrentText:SetTextColor(textColor.r, textColor.g, textColor.b, textColor.a or 1)
        ApplyTextShadow(barData.stackCurrentText, display.textShadow)
      end
      
      -- Style original max text
      if barData.maxText then
        pcall(function()
          barData.maxText:SetFont(fontPath, display.fontSize or 14, outlineFlag)
        end)
        barData.maxText:SetTextColor(0.6, 0.6, 0.6, 1)  -- Dimmer
        ApplyTextShadow(barData.maxText, display.textShadow)
      end
      
      -- Style FREE mode max text if it exists
      if barData.stackMaxText then
        pcall(function()
          barData.stackMaxText:SetFont(fontPath, display.fontSize or 14, outlineFlag)
        end)
        barData.stackMaxText:SetTextColor(0.6, 0.6, 0.6, 1)  -- Dimmer
        ApplyTextShadow(barData.stackMaxText, display.textShadow)
      end
      
      -- Show/hide based on mode and showMaxText setting
      if barData.useStackTextFrame then
        -- FREE mode - use stack frame texts
        if barData.currentText then barData.currentText:Hide() end
        if barData.maxText then barData.maxText:Hide() end
        if barData.chargeTextContainer then barData.chargeTextContainer:Hide() end
        if barData.stackTextFrame then barData.stackTextFrame:Show() end
        if display.showMaxText == false then
          if barData.stackMaxText then barData.stackMaxText:Hide() end
        else
          if barData.stackMaxText then barData.stackMaxText:Show() end
        end
      else
        -- Normal anchored mode
        if barData.stackTextFrame then barData.stackTextFrame:Hide() end
        if barData.chargeTextContainer then barData.chargeTextContainer:Show() end
        if barData.currentText then barData.currentText:Show() end
        if display.showMaxText == false then
          if barData.maxText then barData.maxText:Hide() end
        else
          if barData.maxText then barData.maxText:Show() end
        end
      end
    else
      -- Hide all stack text
      if barData.currentText then barData.currentText:Hide() end
      if barData.maxText then barData.maxText:Hide() end
      if barData.chargeTextContainer then barData.chargeTextContainer:Hide() end
      if barData.stackTextFrame then barData.stackTextFrame:Hide() end
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════
  -- COOLDOWN BAR SPECIFIC: Text positioning, strata/level and ready text
  -- ═══════════════════════════════════════════════════════════════
  if barType == "cooldown" then
    -- Get strata settings for text containers
    local nameStrata = display.nameTextStrata or display.barFrameStrata or "HIGH"
    local nameLevel = display.nameTextLevel or (display.barFrameLevel or 10) + 3
    local durationStrata = display.durationTextStrata or display.barFrameStrata or "HIGH"
    local durationLevel = display.durationTextLevel or (display.barFrameLevel or 10) + 3
    
    -- Name text container strata/level
    if barData.nameTextContainer then
      barData.nameTextContainer:SetFrameStrata(nameStrata)
      barData.nameTextContainer:SetFrameLevel(nameLevel)
    end
    if barData.nameText then
      barData.nameText:SetDrawLayer("OVERLAY", 7)
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- DURATION TEXT POSITIONING (same pattern as charge bar timer text)
    -- ═══════════════════════════════════════════════════════════════
    local durationAnchor = display.durationAnchor or "RIGHT"
    local durationOffsetX = display.durationAnchorOffsetX or -4
    local durationOffsetY = display.durationAnchorOffsetY or 0
    
    if barData.text then
      if durationAnchor == "FREE" then
        -- Create wrapper frame for FREE mode if needed
        if not barData.durationTextFrame then
          barData.durationTextFrame = CreateFrame("Frame", nil, UIParent)
          barData.durationTextFrame:SetMovable(true)
          barData.durationTextFrame:SetClampedToScreen(true)
          barData.durationTextFrame:RegisterForDrag("LeftButton")
          
          -- Create new FontString for this frame
          barData.freeDurationText = barData.durationTextFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
          barData.freeDurationText:SetPoint("CENTER", barData.durationTextFrame, "CENTER", 0, 0)
        end
        
        -- Apply configurable frame width
        local durationFrameWidth = display.durationTextFrameWidth or 60
        barData.durationTextFrame:SetSize(durationFrameWidth, 25)
        
        -- Store display reference for drag scripts
        barData.durationTextFrame.displayRef = display
        barData.durationTextFrame:SetScript("OnDragStart", function(self)
          local locked = self.displayRef and self.displayRef.durationTextLocked
          if not locked then
            self:StartMoving()
          end
        end)
        barData.durationTextFrame:SetScript("OnDragStop", function(self)
          self:StopMovingOrSizing()
          local point, _, relPoint, x, y = self:GetPoint()
          if self.displayRef then
            self.displayRef.durationTextPosition = { point = point, relPoint = relPoint, x = x, y = y }
          end
        end)
        
        -- Enable mouse
        barData.durationTextFrame:EnableMouse(true)
        
        barData.durationTextFrame:ClearAllPoints()
        if display.durationTextPosition then
          barData.durationTextFrame:SetPoint(display.durationTextPosition.point, UIParent, display.durationTextPosition.relPoint, display.durationTextPosition.x, display.durationTextPosition.y)
        else
          -- Default: position relative to frame
          local fX, fY = frame:GetCenter()
          if fX and fY then
            local fW = frame:GetWidth() / 2
            barData.durationTextFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", fX + fW - 20, fY)
          else
            barData.durationTextFrame:SetPoint("RIGHT", frame, "RIGHT", durationOffsetX, durationOffsetY)
          end
        end
        barData.durationTextFrame:SetFrameStrata(durationStrata)
        barData.durationTextFrame:SetFrameLevel(durationLevel)
        barData.durationTextFrame:Show()
        
        -- Hide original duration text and container, use free text
        barData.text:Hide()
        if barData.durationTextContainer then barData.durationTextContainer:Hide() end
        barData.useFreeDurationText = true
      else
        -- Hide free text frame if it exists
        if barData.durationTextFrame then
          barData.durationTextFrame:Hide()
          barData.useFreeDurationText = false
        end
        -- Show original duration text
        barData.text:Show()
        -- Get valid anchor
        local validAnchor = GetValidAnchor(durationAnchor) or "RIGHT"
        -- Position the container frame
        if barData.durationTextContainer then
          barData.durationTextContainer:ClearAllPoints()
          barData.durationTextContainer:SetPoint(validAnchor, barData.bar, validAnchor, durationOffsetX, durationOffsetY)
          barData.durationTextContainer:Show()
        else
          barData.text:ClearAllPoints()
          barData.text:SetPoint(validAnchor, barData.bar, validAnchor, durationOffsetX, durationOffsetY)
        end
      end
    end
    
    -- Duration text container strata/level
    if barData.durationTextContainer then
      barData.durationTextContainer:SetFrameStrata(durationStrata)
      barData.durationTextContainer:SetFrameLevel(durationLevel)
    end
    if barData.text then
      barData.text:SetDrawLayer("OVERLAY", 7)
    end
    if barData.readyText then
      barData.readyText:SetDrawLayer("OVERLAY", 7)
    end
    -- FREE mode duration frame
    if barData.durationTextFrame then
      barData.durationTextFrame:SetFrameStrata(durationStrata)
      barData.durationTextFrame:SetFrameLevel(durationLevel)
    end
    if barData.freeDurationText then
      barData.freeDurationText:SetDrawLayer("OVERLAY", 7)
    end
    
    -- Ready text styling (same font as duration but can have different color)
    if barData.readyText then
      local fontPath = "Fonts\\FRIZQT__.TTF"
      if LSM and display.durationFont then
        local f = LSM:Fetch("font", display.durationFont)
        if f then fontPath = f end
      end
      pcall(function()
        barData.readyText:SetFont(fontPath, display.durationFontSize or 14, GetOutlineFlag(display.durationOutline))
      end)
      -- Ready text color: use readyColor if set, otherwise use bar color
      local readyColor = display.readyColor or display.barColor or {r = 0.3, g = 1, b = 0.3, a = 1}
      barData.readyText:SetTextColor(readyColor.r or 0.3, readyColor.g or 1, readyColor.b or 0.3, readyColor.a or 1)
      ApplyTextShadow(barData.readyText, display.durationShadow)
      
      -- Show/hide ready text based on setting
      if display.showReadyText == false then
        barData.readyText:SetText("")  -- Clear text instead of hiding (alpha is controlled by curves)
      else
        barData.readyText:SetText(display.readyText or "Ready")
      end
      
      -- ═══════════════════════════════════════════════════════════════
      -- READY TEXT POSITIONING
      -- ═══════════════════════════════════════════════════════════════
      local readyAnchor = display.readyTextAnchor or "RIGHT"
      local readyOffsetX = display.readyTextOffsetX or 0
      local readyOffsetY = display.readyTextOffsetY or 0
      
      if readyAnchor == "FREE" then
        -- Create wrapper frame for FREE mode if needed
        if not barData.readyTextFrame then
          barData.readyTextFrame = CreateFrame("Frame", nil, UIParent)
          barData.readyTextFrame:SetMovable(true)
          barData.readyTextFrame:SetClampedToScreen(true)
          barData.readyTextFrame:RegisterForDrag("LeftButton")
          
          -- Create new FontString for this frame
          barData.freeReadyText = barData.readyTextFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
          barData.freeReadyText:SetPoint("CENTER", barData.readyTextFrame, "CENTER", 0, 0)
        end
        
        -- Apply size
        barData.readyTextFrame:SetSize(80, 25)
        
        -- Store display reference for drag scripts
        barData.readyTextFrame.displayRef = display
        barData.readyTextFrame:SetScript("OnDragStart", function(self)
          local locked = self.displayRef and self.displayRef.readyTextLocked
          if not locked then
            self:StartMoving()
          end
        end)
        barData.readyTextFrame:SetScript("OnDragStop", function(self)
          self:StopMovingOrSizing()
          local point, _, relPoint, x, y = self:GetPoint()
          if self.displayRef then
            self.displayRef.readyTextPosition = { point = point, relPoint = relPoint, x = x, y = y }
          end
        end)
        
        -- Enable mouse
        barData.readyTextFrame:EnableMouse(true)
        
        barData.readyTextFrame:ClearAllPoints()
        if display.readyTextPosition then
          barData.readyTextFrame:SetPoint(display.readyTextPosition.point, UIParent, display.readyTextPosition.relPoint, display.readyTextPosition.x, display.readyTextPosition.y)
        else
          -- Default: position relative to bar
          local fX, fY = barData.bar:GetCenter()
          if fX and fY then
            barData.readyTextFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", fX, fY)
          else
            barData.readyTextFrame:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
          end
        end
        barData.readyTextFrame:SetFrameStrata(durationStrata)
        barData.readyTextFrame:SetFrameLevel(durationLevel)
        barData.readyTextFrame:Show()
        
        -- Style and setup free ready text
        pcall(function()
          barData.freeReadyText:SetFont(fontPath, display.durationFontSize or 14, GetOutlineFlag(display.durationOutline))
        end)
        barData.freeReadyText:SetTextColor(readyColor.r or 0.3, readyColor.g or 1, readyColor.b or 0.3, readyColor.a or 1)
        ApplyTextShadow(barData.freeReadyText, display.durationShadow)
        if display.showReadyText == false then
          barData.freeReadyText:SetText("")
        else
          barData.freeReadyText:SetText(display.readyText or "Ready")
        end
        
        -- Hide original ready text, use free
        barData.readyText:Hide()
        barData.useFreeReadyText = true
      else
        -- Hide free ready text frame if it exists
        if barData.readyTextFrame then
          barData.readyTextFrame:Hide()
          barData.useFreeReadyText = false
        end
        -- Show original ready text and position it
        barData.readyText:Show()
        barData.readyText:ClearAllPoints()
        local validAnchor = GetValidAnchor(readyAnchor) or "RIGHT"
        if barData.durationTextContainer then
          barData.readyText:SetPoint(validAnchor, barData.durationTextContainer, validAnchor, readyOffsetX, readyOffsetY)
        else
          barData.readyText:SetPoint(validAnchor, barData.bar, validAnchor, readyOffsetX, readyOffsetY)
        end
      end
    end
    
    -- Ready fill color (matches bar color when ready)
    if barData.readyFill then
      local barColor = display.barColor or {r = 1, g = 0.5, b = 0.2, a = 1}
      barData.readyFill:SetVertexColor(barColor.r or 1, barColor.g or 0.5, barColor.b or 0.2, barColor.a or 1)
    end
  end
  
  -- Show frame if tracking enabled
  if cfg.tracking.enabled then
    frame:Show()
  else
    frame:Hide()
  end
end

-- Legacy compatibility wrapper
function ns.CooldownBars.ApplyBarSettings(spellID, barType)
  ns.CooldownBars.ApplyAppearance(spellID, barType)
end

-- ===================================================================
-- OPEN OPTIONS FOR BAR (right-click to edit)
-- Opens the options panel and selects the Appearance tab with this bar selected
-- ===================================================================
function ns.CooldownBars.OpenOptionsForBar(barType, spellID)
  local AceConfigDialog = LibStub("AceConfigDialog-3.0")
  
  -- Check if options panel is already open - if not, do nothing
  local panelIsOpen = AceConfigDialog.OpenFrames and AceConfigDialog.OpenFrames["ArcUI"]
  if not panelIsOpen then
    return  -- Don't open panel, just ignore the click
  end
  
  -- Set the selected bar in AppearanceOptions
  -- Format: "cd_barType_spellID" e.g. "cd_cooldown_12345" or "cd_charge_67890"
  if ns.AppearanceOptions and ns.AppearanceOptions.SetSelectedBar then
    ns.AppearanceOptions.SetSelectedBar("cd_" .. barType, spellID)
  end
  
  -- Refresh the options to show updated selection
  local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
  AceConfigRegistry:NotifyChange("ArcUI")
  
  -- Select the appearance tab (now under bars)
  AceConfigDialog:SelectGroup("ArcUI", "bars", "appearance")
  
  if ns.devMode then
    print(string.format("|cff00FFFF[ArcUI Debug]|r CooldownBars.OpenOptionsForBar: %s %d", barType, spellID))
  end
end

-- ===================================================================
-- UPDATE TOGGLEBARTYPE TO USE NEW FUNCTIONS
-- ===================================================================
function ns.CooldownBars.ToggleBarType(spellID, barType, enable)
  if not spellID then return end
  
  if barType == "cooldown" then
    if enable then
      ns.CooldownBars.AddCooldownBar(spellID)
    else
      ns.CooldownBars.RemoveCooldownBar(spellID)
    end
  elseif barType == "charge" then
    if enable then
      ns.CooldownBars.AddChargeBar(spellID)
    else
      ns.CooldownBars.RemoveChargeBar(spellID)
    end
  elseif barType == "resource" then
    if enable then
      ns.CooldownBars.AddResourceBar(spellID)
    else
      ns.CooldownBars.RemoveResourceBar(spellID)
    end
  end
  
  ns.CooldownBars.SaveBarConfig()
end

-- ===================================================================
-- INITIALIZATION
-- ===================================================================
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_LOGOUT")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
initFrame:RegisterEvent("SPELLS_CHANGED")
initFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
initFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
initFrame:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    C_Timer.After(1.5, function()
      if not InCombatLockdown() then
        local count = ns.CooldownBars.ScanPlayerSpells()
        -- Restore saved bars after scan
        ns.CooldownBars.RestoreBarConfig()
        if ns.devMode then
          print("|cff00ff00[ArcUI CooldownBars]|r Found " .. count .. " spells. Use /cdbar to test.")
        end
      end
    end)
  elseif event == "PLAYER_LOGOUT" then
    ns.CooldownBars.SaveBarConfig()
  elseif event == "PLAYER_REGEN_ENABLED" then
    -- Rescan after combat ends (but don't clear active bars)
    C_Timer.After(0.5, function()
      ns.CooldownBars.ScanPlayerSpells()
    end)
  elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
    if not InCombatLockdown() then
      C_Timer.After(1, function()
        ns.CooldownBars.ScanPlayerSpells()
      end)
    end
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
    -- Update bar visibility based on new spec
    if not InCombatLockdown() then
      C_Timer.After(0.5, function()
        -- Rescan spells for new spec (some spells change between specs)
        ns.CooldownBars.ScanPlayerSpells()
        -- Update bar visibility (show/hide based on spec)
        ns.CooldownBars.UpdateBarVisibilityForSpec()
      end)
    end
  end
end)

-- ===================================================================
-- SLASH COMMAND
-- ===================================================================
SLASH_ARCUICDB1 = "/cdbar"
SlashCmdList["ARCUICDB"] = function(msg)
  msg = msg and msg:lower():trim() or ""
  
  if msg == "scan" then
    local count = ns.CooldownBars.ScanPlayerSpells()
    print("|cff00ff00[ArcUI]|r Scanned " .. count .. " spells")
    
  elseif msg == "list" then
    print("|cff00ff00[ArcUI]|r Spell Catalog (" .. #ns.CooldownBars.spellCatalog .. " spells):")
    for i, data in ipairs(ns.CooldownBars.spellCatalog) do
      if i <= 25 then
        local tags = ""
        if data.hasCharges then tags = tags .. " |cff00ccff[C" .. data.maxCharges .. "]|r" end
        if data.isTalent then tags = tags .. " |cff00ff00[T]|r" end
        if data.hasResourceCost then tags = tags .. " |cffcc33cc[R]|r" end
        print(string.format("  %d. %s (ID:%d)%s", i, data.name, data.spellID, tags))
      elseif i == 26 then
        print("  ... and " .. (#ns.CooldownBars.spellCatalog - 25) .. " more")
      end
    end
    
  elseif msg == "active" then
    print("|cff00ff00[ArcUI]|r Active Bars:")
    local count = 0
    for spellID in pairs(ns.CooldownBars.activeCooldowns) do
      local name = C_Spell.GetSpellName(spellID) or "?"
      print("  |cffff8000CD:|r " .. name .. " (" .. spellID .. ")")
      count = count + 1
    end
    for spellID in pairs(ns.CooldownBars.activeResources) do
      local name = C_Spell.GetSpellName(spellID) or "?"
      print("  |cffcc33ccRES:|r " .. name .. " (" .. spellID .. ")")
      count = count + 1
    end
    for spellID in pairs(ns.CooldownBars.activeCharges) do
      local name = C_Spell.GetSpellName(spellID) or "?"
      print("  |cff00ccccCHG:|r " .. name .. " (" .. spellID .. ")")
      count = count + 1
    end
    if count == 0 then
      print("  (none)")
    end
    
  elseif msg == "debug" then
    print("|cff00ff00[ArcUI]|r Debug Log (last 15):")
    local start = math.max(1, #ns.CooldownBars.debugLog - 14)
    for i = start, #ns.CooldownBars.debugLog do
      print("  " .. (ns.CooldownBars.debugLog[i] or ""))
    end
    
  elseif msg == "save" then
    ns.CooldownBars.SaveBarConfig()
    print("|cff00ff00[ArcUI]|r Saved cooldown bar configuration")
    
  elseif msg:find("^add%s+") then
    -- Add spell by ID: /cdbar add 12345
    local spellID = tonumber(msg:match("^add%s+(%d+)"))
    if spellID then
      local success, result = ns.CooldownBars.AddSpellByID(spellID)
      if success then
        print("|cff00ff00[ArcUI]|r Added to catalog: " .. result .. " (ID: " .. spellID .. ")")
      else
        print("|cffff0000[ArcUI]|r Failed: " .. (result or "Unknown error"))
      end
    else
      print("|cffff0000[ArcUI]|r Usage: /cdbar add <spellID>")
    end
    
  elseif msg:find("^remove%s+") or msg:find("^rm%s+") then
    -- Remove spell by ID: /cdbar remove 12345
    local spellID = tonumber(msg:match("^r[em]+ove?%s+(%d+)"))
    if spellID then
      local success, result = ns.CooldownBars.RemoveSpellByID(spellID)
      if success then
        print("|cff00ff00[ArcUI]|r Removed from catalog: " .. result .. " (ID: " .. spellID .. ")")
        print("|cff888888(Spell will not reappear on rescan. Use /cdbar unhide " .. spellID .. " to restore)|r")
      else
        print("|cffff0000[ArcUI]|r Failed: " .. (result or "Unknown error"))
      end
    else
      print("|cffff0000[ArcUI]|r Usage: /cdbar remove <spellID>")
    end
    
  elseif msg:find("^unhide%s+") then
    -- Unhide spell by ID: /cdbar unhide 12345
    local spellID = tonumber(msg:match("^unhide%s+(%d+)"))
    if spellID then
      local success = ns.CooldownBars.UnhideSpellByID(spellID)
      if success then
        local spellName = C_Spell.GetSpellName(spellID) or "Unknown"
        print("|cff00ff00[ArcUI]|r Unhid spell: " .. spellName .. " (ID: " .. spellID .. ")")
        print("|cff888888Use /cdbar scan to add it back to the catalog|r")
      else
        print("|cffff0000[ArcUI]|r Failed to unhide spell")
      end
    else
      print("|cffff0000[ArcUI]|r Usage: /cdbar unhide <spellID>")
    end
    
  elseif msg == "hidden" then
    local hidden = ns.CooldownBars.GetHiddenSpells()
    if #hidden == 0 then
      print("|cff00ff00[ArcUI]|r No hidden spells")
    else
      print("|cff00ff00[ArcUI]|r Hidden spells (" .. #hidden .. "):")
      for _, data in ipairs(hidden) do
        print("  " .. data.name .. " (ID: " .. data.spellID .. ")")
      end
      print("|cff888888Use /cdbar unhide <spellID> to restore|r")
    end
    
  elseif tonumber(msg) then
    -- Toggle cooldown bar by spell ID
    local spellID = tonumber(msg)
    local spellName = C_Spell.GetSpellName(spellID)
    if spellName then
      local states = ns.CooldownBars.GetBarStates(spellID)
      ns.CooldownBars.ToggleBarType(spellID, "cooldown", not states.hasCooldownBar)
    else
      print("|cffff0000[ArcUI]|r Invalid spell ID: " .. spellID)
    end
    
  else
    print("|cff00ff00[ArcUI CooldownBars]|r Commands:")
    print("  /cdbar scan - Rescan spellbook")
    print("  /cdbar list - Show spell catalog")
    print("  /cdbar active - Show active bars")
    print("  /cdbar add <spellID> - Add spell to catalog")
    print("  /cdbar remove <spellID> - Remove and hide spell")
    print("  /cdbar hidden - Show hidden spells")
    print("  /cdbar unhide <spellID> - Unhide a spell")
    print("  /cdbar save - Force save configuration")
    print("  /cdbar debug - Show debug log")
    print("  /cdbar <spellID> - Toggle cooldown bar")
  end
end

-- ===================================================================
-- INIT FUNCTION (called by ArcUI_Options.lua)
-- ===================================================================
function ns.CooldownBars.Init()
  -- Initialization is handled by event-based system above
  -- This function exists for consistency with other modules
  Log("CooldownBars.Init() called")
end

-- ===================================================================
-- END OF ArcUI_CooldownBars.lua
-- ===================================================================