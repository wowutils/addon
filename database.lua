---@class wowutilsPrivate
---@field database wowutils_database

---@type string, wowutilsPrivate
local addon_name, ns = ...
local GetServerTime, sformat = GetServerTime, string.format
---@class wowutilsSavedVariables
---@field lastCharacter wowutils_lastChar
---@field ownCharacters table<string, wowutils_ownChar>
---@field others table<string, wowutils_otherChar>
---@field droptimizerData table<string, wowutilsDroptimizerData>
---@field dbVersion number
---@field debug boolean?
---@field lastSeenWeeklyReset number
---@field lastDataImport number?

---@class wowutils_lastChar
---@field guid string
---@field lastLogout number
---@field region number

---@class wowutils_ownChar : wowutils_otherChar
---@field lastLogout number

---@class wowutils_currencyData
---@field current number
---@field totalEarned number

---@class wowutils_itemData
---@field itemId number
---@field quantity number
---@field itemLink string
---@field updated number

---@class wowutils_otherChar
---@field guid string
---@field name string
---@field class string
---@field currency table<number, wowutils_currencyData> -- currencyId = data
---@field currencyUpdated number
---@field items table<number, wowutils_itemData>
---@field watermarks table<number, number> -- slot = ilvl
---@field watermarksUpdated number
---@field lastUpdate number
---@field lastUpdateReceived number
---@field craftingItems number
---@field craftingItemsUpdated number
---@field region number
---@field guildSlug string?
---@field serverSlug string
---@field fullSlug string
---@field extra table<string, any>
---@field quests table<number, wowutils_quests> -- questId = data
---@field questsUpdated number
---@field lastWeeklyReset number
---@field vaultData wowutils_vaultData_items[]
---@field vaultDataLastUpdate number
---@field weeklyRewards table<string, number> -- "type-index" = level
---@field weeklyRewardsUpdate number
---@field droptimizerKey string

---@class wowutils_characterInformationForMapping
---@field guid string
---@field name string
---@field lastUpdate number
---@field lastUpdateReceived number
---@field class string
---@field region number

---@class wowutils_quests
---@field completed boolean
---@field isWeeklyQuest? boolean
---@field completedWarbound boolean

---@class wowutils_vaultData_items
---@field itemLink string
---@field itemLevel number
---@field itemLocationId number
---@field itemClassId number
---@field itemSubClassId number
---@field itemId number
---@field tertiary number -- mask
---@field picked boolean
---@field claimID number

---@class wowutilsDroptimizerData
---@field specs table<number, table<string, wowutilsDroptimizerData_sims>>
---@field characterName string
---@field lastUpdate number
---@field realmId number
---@field region number
---@field class number
---@field wishlist table<string, wowutilsDroptimizerData_wishlistItem>

---@class wowutilsDroptimizerData_sims
---@field simType wowutils_enums_simTypes
---@field items table<number, wowutilsDroptimizerData_droptimizerItem>
---@field simmedAt number
---@field baseline number? raidbot only

---@class wowutilsDroptimizerData_droptimizerItem
---@field equipmentSlot number
---@field ilvl number
---@field difficultyId number
---@field gain number? raidbots only
---@field gainPercent number? qelive only

---@class wowutilsDroptimizerData_wishlistItem
---@field equipmentSlot number
---@field priority number
---@field updated number
---@field difficultyId number
---@field itemId number
---@field note? string

---@type wowutilsSavedVariables
WowUtilsDB = WowUtilsDB or {
  dbVersion = ns.config.currentDBVersion,
  lastCharacter = {},
  ownCharacters = {},
  others = {},
  droptimizerData = {},
  lastSeenWeeklyReset = C_DateAndTime.GetWeeklyResetStartTime(),
}

if not WowUtilsDB.ownCharacters[ns.me.guid] then
  ---@type wowutils_ownChar
  WowUtilsDB.ownCharacters[ns.me.guid] = {
    guid = ns.me.guid,
    name = ns.me.name,
    class = select(2, UnitClass('player')),
    currency = {},
    items = {},
    extra = {},
    region = GetCurrentRegion(),
    craftingItems = 0,
    craftingItemsUpdated = 0,
    currencyUpdated = 0,
    lastLogout = 0,
    watermarks = {},
    watermarksUpdated = 0,
    lastUpdate = 0,
    quests = {},
    vaultData = {},
    weeklyRewards = {},
    lastUpdateReceived = GetServerTime(),
    droptimizerKey = ns.me.droptimizerKey,
    weeklyRewardsUpdate = 0,
    vaultDataLastUpdate = 0,
    lastWeeklyReset = C_DateAndTime.GetWeeklyResetStartTime(),
    questsUpdated = 0,
  }
else
  WowUtilsDB.ownCharacters[ns.me.guid].name = ns.me.name
  WowUtilsDB.ownCharacters[ns.me.guid].droptimizerKey = ns.me.droptimizerKey
  WowUtilsDB.ownCharacters[ns.me.guid].class = select(2, UnitClass('player'))
  WowUtilsDB.ownCharacters[ns.me.guid].region = ns.me.regionId
  WowUtilsDB.ownCharacters[ns.me.guid].lastWeeklyReset = C_DateAndTime.GetWeeklyResetStartTime()
end

---@type wowutils_ownChar
local charDB = WowUtilsDB.ownCharacters[ns.me.guid]
local db = WowUtilsDB
db.lastCharacter.guid = ns.me.guid
if db.dbVersion < ns.config.currentDBVersion then
  -- upgrade db based on version
end

---@class wowutils_database
ns.database = {}


local function contextUpdated(context)
  local serverTime = GetServerTime()
  if context == ns.enums.context.currency then
    charDB.currencyUpdated = serverTime
    ns.communication.SendCurrencyUpdate()
  elseif context == ns.enums.context.watermarks then
    charDB.watermarksUpdated = serverTime
    ns.communication.SendWatermarkUpdate()
  elseif context == ns.enums.context.craftingItems then
    charDB.craftingItemsUpdated = serverTime
    ns.communication.SendCraftingItemUpdate()
  elseif context == ns.enums.context.vaultData then
    charDB.vaultDataLastUpdate = serverTime
    ns.communication.SendVaultDataUpdate()
  elseif context == ns.enums.context.weeklyRewards then
    charDB.weeklyRewardsUpdate = serverTime
    ns.communication.SendWeeklyRewardsUpdate()
  elseif context == ns.enums.context.quests then
    charDB.questsUpdated = serverTime
    ns.communication.SendQuestUpdate()
  end
  charDB.lastUpdate = serverTime
end

---@param context string
---@param id string|number?
---@param data any
function ns.database.SaveToCurrentCharacterDB(context, id, data)
  if context == ns.enums.context.currency then
    ---@cast id number
    if not charDB.currency[id] then
      charDB.currency[id] = {
        current = data.quantity or 0,
        totalEarned = data.totalEarned or 0,
      }
      contextUpdated(context)
      return
    end
    if charDB.currency[id].current ~= (data.quantity or 0) or charDB.currency[id].totalEarned ~= (data.totalEarned or 0) then
      charDB.currency[id].current = data.quantity or 0
      charDB.currency[id].totalEarned = data.totalEarned or 0
      contextUpdated(context)
    end
    return
  end

  if context == ns.enums.context.lastLogout then
    charDB.lastLogout = data
    db.lastCharacter.lastLogout = data
    return
  end

  if context == ns.enums.context.watermarks then
    local updated = false
    for slotId, discountItemLevel in pairs(data) do
      if charDB.watermarks[slotId] ~= discountItemLevel then
        updated = true
        charDB.watermarks[slotId] = discountItemLevel
      end
    end
    if updated then
      contextUpdated(context)
    end
    return
  end

  if context == ns.enums.context.craftingItems then
    if charDB.craftingItems == data then return end
    charDB.craftingItems = data
    contextUpdated(context)
    return
  end

  if context == ns.enums.context.guildInfo then
    if charDB.guildSlug == data then return end
    charDB.guildSlug = data
    contextUpdated(context)
    ns.communication.guildStatusUpdate()
    return
  end

  if context == ns.enums.context.serverSlugUpdate then
    charDB.serverSlug = data
    charDB.fullSlug = ns.me.name .. "-" .. ns.me.serverSlug
    contextUpdated(context)
    return
  end

  if context == ns.enums.context.vaultData then
    if #charDB.vaultData ~= #data then
      charDB.vaultData = data
      contextUpdated(context)
      return
    end
    local temp = {}
    local isChanged = false
    for k,v in pairs(charDB.vaultData) do
      temp[v.claimID] = v
    end
    for k,v in pairs(data) do
      if not temp[v.claimID] then
        isChanged = true
        break
      end
      for a,b in pairs(v) do
        if temp[v.claimID][a] ~= b then
          isChanged = true
          break
        end
      end
      if isChanged then break end
    end
    if isChanged then
      charDB.vaultData = data
      contextUpdated(context)
    end
    return
  end

  if context == ns.enums.context.weeklyRewards then
    for k,v in pairs(data) do
      if charDB.weeklyRewards[k] ~= v then
        charDB.weeklyRewards = data
        contextUpdated(context)
        return
      end
    end
    return
  end

  if context == ns.enums.context.quests then
    ---@cast data table<number, wowutils_quests>
    if not charDB.quests then
      charDB.quests = data
      contextUpdated(context)
      return
    end
    for questId,d in pairs(data) do
      if not charDB.quests[questId] then
        if not charDB.quests[questId] then
          charDB.quests = data
          contextUpdated(context)
          return
        end
        for _k, _v in pairs(d) do
          if charDB[questId][_k] ~= _v then
            charDB.quests = data
            contextUpdated(context)
            return
          end
        end
      end
    end
    return
  end
  geterrorhandler()("Unknown context: " .. tostring(context))
end

function ns.database.GetCurrentCharDB()
  return charDB
end

function ns.database.GetAllCharsDB()
  return db.others
end

function ns.database.ResetWeeklyData(currentResetStart)
  charDB.lastWeeklyReset = currentResetStart
  for guid, charData in pairs(db.ownCharacters) do
    wipe(charData.weeklyRewards)
    wipe(charData.vaultData)
    do
      local toDelete = {}
      for questId, questData in pairs(charData.quests) do
        if questData.isWeeklyQuest then
          toDelete[questId] = true
        end
      end
      for k,v in pairs(toDelete) do
        charData.quests[k] = nil
      end
    end
  end
end

--#region Clean up
do
  local characterKeepThreshold = GetServerTime() - 30*24*60*60 -- 30 days
  --local droptimizerKeepTime = GetServerTime() - 30*24*60*60 -- 30 days
  local toDelete = {}
  for k,v in pairs(WowUtilsDB.others) do
    if v.lastUpdateReceived < characterKeepThreshold then
      toDelete[k] = true
    end
  end
  for k,v in pairs(toDelete) do
    WowUtilsDB.others[k] = nil
  end
end
--#end region