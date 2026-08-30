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
---@field syncList wowutilsData_import_syncList?
---@field wishlistMapping table<string, string>?

---@class wowutilsData_import_syncList
---@field listId string
---@field listVersion number update time
---@field characters wowutilsData_import_syncList_characters[]

---@class wowutilsData_import_syncList_characters
---@field id number
---@field name string
---@field realmId number
---@field realm string
---@field region string

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
---@field raidScope? string added in schema 4, "<expansion>-s<season>" e.g. "midnight-s2". NOT part of the droptimizer id, so two scopes sharing a profileKey collide
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
---@field difficultyId number? the difficulty the sim ran at, not the item's own track. negative encounterIds carry the raid difficulty anyway
---@field encounterId? number added in schema 4, journal encounter the item drops from. negative for non-raid sources (-97 seen on catalyst/other pieces)
---@field sourceItem? wowutilsData_import_droptimizer_item_source added in schema 4, set when the item isn't a direct drop (tier token or catalyst conversion)
---@field dpsGain number? raidbots Only
---@field dpsGainPercent number? qelive only

---@class wowutilsData_import_droptimizer_item_source what actually has to drop for the parent item to be obtainable
---@field itemId number the token/base item that converts into the parent item
---@field encounterId? number encounter the source item drops from
---@field catalyst? boolean true when the conversion is a catalyst charge rather than a tier token

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


---Two rows are the same entry only when every field that could tell them apart matches. A ring
---simmed into both finger slots, or a piece reachable both as a drop and through the catalyst,
---are genuinely different results for the same itemId and both have to survive.
---@param a wowutilsDroptimizerData_droptimizerItem
---@param b wowutilsDroptimizerData_droptimizerItem
---@return boolean
function private.IsSameDroptimizerEntry(a, b)
  if a.equipmentSlot ~= b.equipmentSlot then return false end
  if a.difficultyId ~= b.difficultyId then return false end
  if a.ilvl ~= b.ilvl then return false end
  local aSource, bSource = a.sourceItem, b.sourceItem
  if (aSource ~= nil) ~= (bSource ~= nil) then return false end
  if aSource and bSource then
    if aSource.itemId ~= bSource.itemId then return false end
    if (aSource.catalyst or false) ~= (bSource.catalyst or false) then return false end
  end
  return true
end

---@param d wowutilsData_import_droptimizer_item[]
---@return table<number, wowutilsDroptimizerData_droptimizerItem[]>
function private.ParseDroptimizerItems(d)
  ---@type table<number, wowutilsDroptimizerData_droptimizerItem[]>
  local t = {}
  for _,v in pairs(d) do
    ---@type wowutilsDroptimizerData_droptimizerItem
    local entry = {
      difficultyId = v.difficultyId or private.GetDifficultyId(v.difficulty),
      equipmentSlot = private.GetEquipmentSlotId(v.slot),
      ilvl = v.ilvl,
      gain = v.dpsGain,
      gainPercent = v.dpsGainPercent,
      encounterId = v.encounterId,
      -- copied field by field rather than kept by reference: the import table is transient and
      -- this ends up in saved variables
      sourceItem = v.sourceItem and {
        itemId = v.sourceItem.itemId,
        encounterId = v.sourceItem.encounterId,
        catalyst = v.sourceItem.catalyst,
      } or nil,
    }
    local entries = t[v.itemId]
    if not entries then
      t[v.itemId] = { entry }
    else
      local replaced = false
      for i = 1, #entries do
        if private.IsSameDroptimizerEntry(entries[i], entry) then
          entries[i] = entry
          replaced = true
          break
        end
      end
      if not replaced then
        entries[#entries + 1] = entry
      end
    end
  end
  return t
end

---@param d wowutilsData_import_wishlist[]
---@param wishlistMapping table<string, string>?
---@return table<string, wowutilsDroptimizerData_wishlistItem>
function private.ParseWishlistItems(d, wishlistMapping)
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
      priority = wishlistMapping and wishlistMapping[tostring(v.priority)] or tostring(v.priority),
      priorityId = tonumber(v.priority),
      updated = v.updatedAt,
      note = v.note
    }
  end
  return t
end

---@param simType wowutils_enums_simTypes
---@param d wowutilsData_import_droptimizer
---@return string
function private.GetDroptimizerId(simType, d)
  return sformat("%s-%s-%s-%s", simType, d.profileKey, d.fightStyle or 0, d.targets)
end

---@param charKey string charName-realmId
---@param charData wowutilsData_import_character
---@param fileUpdateTime number
---@param force boolean? re-read the file even though we already imported it once
---@return boolean
local function shouldUpdateDroptimizer(charKey, charData, fileUpdateTime, force)
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
  if force then -- still never clobber data a guildmate synced us from a newer file
    return WowUtilsDB.droptimizerData[charKey].lastUpdate <= fileUpdateTime
  end
  return WowUtilsDB.droptimizerData[charKey].lastUpdate < fileUpdateTime
end

function ns.dataImport.ImportDroptimizers()
  if not ns.hasDataAddon then return end
  ---@diagnostic disable-next-line: undefined-global
  local t = WowUtilsPublicDataAPI.GetFullData()
  ---@cast t wowutilsData_import
  local force = ns.forceDroptimizerReimport
  if not force and WowUtilsDB.lastDataImport and WowUtilsDB.lastDataImport >= t.writtenAt then return end
  --if t.schemaVersion == 2 then end

  -- collect what the file actually contains before deleting anything. this has to be unioned
  -- over every group first: a character can appear in more than one of them, and pruning
  -- inside the loop below would let whichever group is processed last drop the sims the
  -- earlier ones listed
  ---@type table<string, table<number, table<string, boolean>>> charKey -> specId -> droptimizerId
  local incomingSims = {}
  ---@type table<string, boolean> charKey
  local incomingChars = {}
  ---@type table<string, boolean> groupId
  local incomingGroups = {}
  -- the cleanup sweep in database.lua drops sims past this age. apply it here too, otherwise a
  -- character who is still in the file but hasn't re-simmed would have their old sims swept at
  -- login and then written straight back the next time the file changes
  local simKeepThreshold = GetServerTime() - ns.config.droptimizerKeepTime
  for _, groupData in pairs(t.groups) do
    incomingGroups[groupData.groupId] = true
    for _, charData in pairs(groupData.characters) do
      local charKey = sformat("%s-%s", charData.characterName:lower(), charData.realmId)
      incomingChars[charKey] = true
      if not incomingSims[charKey] then
        incomingSims[charKey] = {}
      end
      for _, droptimizerData in pairs(charData.droptimizers) do
        local simType, validSim = private.GetSimType(droptimizerData.simType)
        if validSim and droptimizerData.specId and (droptimizerData.simmedAt or 0) >= simKeepThreshold then
          if not incomingSims[charKey][droptimizerData.specId] then
            incomingSims[charKey][droptimizerData.specId] = {}
          end
          incomingSims[charKey][droptimizerData.specId][private.GetDroptimizerId(simType, droptimizerData)] = true
        end
      end
    end
  end

  ---@type table<string, boolean> characters we read from this file, and may therefore prune
  local refreshed = {}
  for _, groupData in pairs(t.groups) do
    for _, charData in pairs(groupData.characters) do
      local charKey = sformat("%s-%s", charData.characterName:lower(), charData.realmId)
      if shouldUpdateDroptimizer(charKey, charData, t.writtenAt, force) then
        refreshed[charKey] = true
        local targetDB = WowUtilsDB.droptimizerData[charKey]
        targetDB.groupId = groupData.groupId
        -- droptimizers first
        for _, droptimizerData in pairs(charData.droptimizers) do
          local simType, validSim = private.GetSimType(droptimizerData.simType)
          if validSim and (droptimizerData.simmedAt or 0) >= simKeepThreshold then
            local droptimizerId = private.GetDroptimizerId(simType, droptimizerData)
            if droptimizerData.specId then
              if not targetDB.specs[droptimizerData.specId] then
                targetDB.specs[droptimizerData.specId] = {}
              end
              -- a forced pass rewrites the sim even when it has not been re-simmed. the timestamp
              -- only tells us the sim is the same one, not that we stored everything it carries:
              -- a db upgrade that starts keeping new fields has to re-read what is already there
              local storedSim = targetDB.specs[droptimizerData.specId][droptimizerId]
              if force or not storedSim or storedSim.simmedAt < droptimizerData.simmedAt then
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
        targetDB.wishlist = private.ParseWishlistItems(charData.wishlist, groupData.wishlistMapping)
        targetDB.lastUpdate = t.writtenAt
      end
    end
    if groupData.syncList then
      if not WowUtilsDB.syncLists[groupData.syncList.listId] or WowUtilsDB.syncLists[groupData.syncList.listId].lastUpdate < groupData.syncList.listVersion then
        if WowUtilsDB.syncLists[groupData.syncList.listId] then
          wipe(WowUtilsDB.syncLists[groupData.syncList.listId].characters)
        else
          ---@diagnostic disable-next-line: missing-fields
          WowUtilsDB.syncLists[groupData.syncList.listId] = {
            characters = {}
          }
        end
        local targetList = WowUtilsDB.syncLists[groupData.syncList.listId]
        targetList.lastUpdate = groupData.syncList.listVersion
        for _, charData in pairs(groupData.syncList.characters) do
          targetList.characters[charData.id] = sformat("%s-%s", charData.name:lower(), charData.realmId)
        end
      end
    end
  end

  -- drop sims the file no longer lists. only for characters we just read: anything else may
  -- be holding newer data synced from a guildmate, which legitimately contains sims this file
  -- doesn't know about yet
  for charKey in pairs(refreshed) do
    local specs = WowUtilsDB.droptimizerData[charKey].specs
    local keep = incomingSims[charKey]
    for specId, sims in pairs(specs) do
      local keepForSpec = keep and keep[specId]
      for simId in pairs(sims) do
        if not (keepForSpec and keepForSpec[simId]) then
          ns.Debug.print("removing droptimizer '%s' (spec %s) from '%s'", simId, tostring(specId), charKey)
          sims[simId] = nil
        end
      end
      if not next(sims) then
        specs[specId] = nil
      end
    end
  end

  -- characters whose group is still in the file but who are no longer part of it. clear the
  -- entry rather than removing it: mapping.lua only rejects incoming droptimizer data when it
  -- already holds a newer entry, so a nil entry would let that character sync their stale copy
  -- straight back to us. the cleanup sweep in database.lua reaps the empty shell later.
  for charKey, charDB in pairs(WowUtilsDB.droptimizerData) do
    if charDB.groupId and incomingGroups[charDB.groupId] and not incomingChars[charKey] then
      if (charDB.specs and next(charDB.specs)) or (charDB.wishlist and next(charDB.wishlist)) then
        ns.Debug.print("clearing droptimizer data for '%s', no longer part of group '%s'", charKey, charDB.groupId)
        if charDB.specs then wipe(charDB.specs) end
        if charDB.wishlist then wipe(charDB.wishlist) end
        if (charDB.lastUpdate or 0) < t.writtenAt then
          charDB.lastUpdate = t.writtenAt
        end
      end
    end
  end

  WowUtilsDB.lastDataImport = t.writtenAt
  ns.forceDroptimizerReimport = nil
end
ns.dataImport.ImportDroptimizers()