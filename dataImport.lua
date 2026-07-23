---@class wowutilsPrivate
---@field dataImport wowutils_dataImport

---@type string, wowutilsPrivate
local addon_name, ns = ...

---@class wowutilsData_import
---@field schemaVersion number
---@field rev number
---@field writtenAt number  # unix timestamp
---@field groups wowutilsData_import_group[]

---@class wowutilsData_import_group
---@field schemaVersion number
---@field groupId string
---@field characters wowutilsData_import_character[]

---@class wowutilsData_import_character
---@field characterId string lowercase slug
---@field characterName string
---@field characterClass string
---@field realm string
---@field realmId number
---@field region "eu"|"us" some others probably
---@field wishlist wowutilsData_import_wishlist[]
---@field droptimizers wowutilsData_import_droptimizer[]

---@class wowutilsData_import_droptimizer
---@field spec string
---@field specId? number
---@field simType "raidbots"|"qelive"
---@field profileKey string
---@field fightStyle? string raidbots only
---@field targets number
---@field simmedAt number unix
---@field baselineDps? number raidbots only
---@field items wowutilsData_import_droptimizer_item[]

---@class wowutilsData_import_droptimizer_item
---@field itemId number
---@field slot string
---@field ilvl number
---@field difficulty "normal"|"heroic"|"mythic"
---@field difficultyId number?
---@field dpsGain number? raidbots Only
---@field dpsGainPercent number? qelive only

---@class wowutilsData_import_wishlist
---@field itemId number
---@field slot string
---@field priority number
---@field difficulty "normal"|"heroic"|"mythic"|"mplus"
---@field difficultyId number?
---@field note? string
---@field updatedAt number unix

---@class wowutils_dataImport
ns.dataImport = {}
local sformat = string.format
local private = {}

---@param regionString string
---@return number
function private.GetRegionId(regionString)
  if regionString == "us" then return 1 end
  if regionString == "kr" then return 2 end
  if regionString == "eu" then return 3 end
  if regionString == "tw" then return 4 end
  if regionString == "cn" then return 5 end
  return -1
end

---@param simTypeString string
---@return wowutils_enums_simTypes, boolean
function private.GetSimType(simTypeString)
  if simTypeString == "raidbots" then return ns.enums.simTypes.raidbotDroptimizer, true end
  if simTypeString == "qelive" then return ns.enums.simTypes.qeLiveDroptimizer, true end
  return ns.enums.simTypes.unknown, false
end

---@param difficultyString string
---@return wowutils_enums_difficultyId
function private.GetDifficultyId(difficultyString)
  if difficultyString == "normal" then return ns.enums.difficultyId.RaidNormal end
  if difficultyString == "heroic" then return ns.enums.difficultyId.RaidHeroic end
  if difficultyString == "mythic" then return ns.enums.difficultyId.RaidMythic end
  if difficultyString == "mplus" then return ns.enums.difficultyId.DungeonKeystone end
  return ns.enums.difficultyId.Unknown
end

do
  local slotsToIds = {
    head = INVSLOT_HEAD,
    neck = INVSLOT_NECK,
    shoulder = INVSLOT_SHOULDER,
    chest = INVSLOT_CHEST,
    waist = INVSLOT_WAIST,
    legs = INVSLOT_LEGS,
    boots = INVSLOT_FEET,
    feet = INVSLOT_FEET,
    wrist = INVSLOT_WRIST,
    hands = INVSLOT_HAND,
    finger1 = INVSLOT_FINGER1,
    finger2 = INVSLOT_FINGER2,
    finger = INVSLOT_FINGER1,
    trinket1 = INVSLOT_TRINKET1,
    trinket2 = INVSLOT_TRINKET2,
    trinket = INVSLOT_TRINKET1,
    back = INVSLOT_BACK,
    main_hand = INVSLOT_MAINHAND,
    ranged = INVSLOT_MAINHAND,
    ["one-hand"] = INVSLOT_MAINHAND,
    ["two-hand"] = INVSLOT_MAINHAND,
    ["held in off-hand"] = INVSLOT_OFFHAND,
    off_hand = INVSLOT_OFFHAND,
  }
  ---@param slotString string
  ---@return number slotId
  function private.GetEquipmentSlotId(slotString)
    return slotString and slotsToIds[slotString:lower()] or 0
  end
end

do
  local classIds = {
    warrior = 1,
    paladin = 2,
    hunter = 3,
    rogue = 4,
    priest = 5,
    deathknight = 6,
    shaman = 7,
    mage = 8,
    warlock = 9,
    monk = 10,
    druid = 11,
    demonhunter = 12,
    evoker = 13,
  }
  ---@param classString string
  ---@return number classId
  function private.GetClassId(classString)
    return classString and classIds[classString:lower()] or 0
  end
end


---@param d wowutilsData_import_droptimizer_item[]
---@return table<number, wowutilsDroptimizerData_droptimizerItem>
function private.ParseDroptimizerItems(d)
  ---@type table<number, wowutilsDroptimizerData_droptimizerItem>
  local t = {}
  for _,v in pairs(d) do
    t[v.itemId] = {
      difficultyId = v.difficultyId or private.GetDifficultyId(v.difficulty),
      equipmentSlot = private.GetEquipmentSlotId(v.slot),
      ilvl = v.ilvl,
      gain = v.dpsGain,
      gainPercent = v.dpsGainPercent,
    }
  end
  return t
end

---@param d wowutilsData_import_wishlist[]
---@return table<string, wowutilsDroptimizerData_wishlistItem>
function private.ParseWishlistItems(d)
  ---@type table<string, wowutilsDroptimizerData_wishlistItem>
  local t = {}
  for _,v in pairs(d) do
    local difId = v.difficultyId or private.GetDifficultyId(v.difficulty)
    if not (difId and v.itemId) then
      ns.Debug.print("nil check %s %s", tostring(difId), tostring(v.itemId))
    end
    local key = sformat("%s-%s", difId, v.itemId)
    t[key] = {
      difficultyId = difId,
      equipmentSlot = private.GetEquipmentSlotId(v.slot),
      itemId = v.itemId,
      priority = v.priority,
      updated = v.updatedAt,
      note = v.note
    }
  end
  return t
end

---@param charKey string charName-realmId
---@param charData wowutilsData_import_character
---@param fileUpdateTime number
---@return boolean
local function shouldUpdateDroptimizer(charKey, charData, fileUpdateTime)
  if not WowUtilsDB.droptimizerData[charKey] then
    WowUtilsDB.droptimizerData[charKey] = {
      wishlist = {},
      specs = {},
      region = private.GetRegionId(charData.region),
      characterName = charData.characterName,
      realmId = charData.realmId,
      lastUpdate = 0,
      class = private.GetClassId(charData.characterClass)
    }
    return true
  end
  return WowUtilsDB.droptimizerData[charKey].lastUpdate < fileUpdateTime
end

function ns.dataImport.ImportDroptimizers()
  if not ns.hasDataAddon then return end
  ---@diagnostic disable-next-line: undefined-global
  local t = WowUtilsPublicDataAPI.GetFullData()
  ---@cast t wowutilsData_import
  if WowUtilsDB.lastDataImport and WowUtilsDB.lastDataImport >= t.writtenAt then return end
  --if t.schemaVersion == 2 then end
  for _, groupData in pairs(t.groups) do
    for _, charData in pairs(groupData.characters) do
      local charKey = sformat("%s-%s", charData.characterName:lower(), charData.realmId)
      if shouldUpdateDroptimizer(charKey, charData, t.writtenAt) then
        local targetDB = WowUtilsDB.droptimizerData[charKey]
        -- droptimizers first
        for _, droptimizerData in pairs(charData.droptimizers) do
          local simType, validSim = private.GetSimType(droptimizerData.simType)
          if validSim then
            local droptimizerId = sformat("%s-%s-%s-%s", simType, droptimizerData.profileKey, droptimizerData.fightStyle or 0, droptimizerData.targets)
            if droptimizerData.specId then
              if not targetDB.specs[droptimizerData.specId] then
                targetDB.specs[droptimizerData.specId] = {}
              end
              if not targetDB.specs[droptimizerData.specId][droptimizerId] or targetDB.specs[droptimizerData.specId][droptimizerId].simmedAt < droptimizerData.simmedAt then
                ---@type wowutilsDroptimizerData_sims
                targetDB.specs[droptimizerData.specId][droptimizerId] = {
                  items = private.ParseDroptimizerItems(droptimizerData.items),
                  simType = simType,
                  baseline = droptimizerData.baselineDps,
                  simmedAt  = droptimizerData.simmedAt
                }
              end
            else
              print("WOWUTILS ERROR: NO SPECID", charData.characterId, droptimizerData.profileKey)
            end
          end
        end
        -- just replace the whole thing if our data is newer
        targetDB.wishlist = private.ParseWishlistItems(charData.wishlist)
        targetDB.lastUpdate = t.writtenAt
      end
    end
  end

  WowUtilsDB.lastDataImport = t.writtenAt
end
ns.dataImport.ImportDroptimizers()