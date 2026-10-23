---@class wowutilsPrivate
---@field database wowutils_database
---@field eligibleSyncLists table<string, boolean>
---@field forceDroptimizerReimport boolean?

---@type string, wowutilsPrivate
local addon_name, ns = ...
ns.eligibleSyncLists = {}
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
---@field syncLists table<string, wowutilsSyncList>
---@field configVersion number
---@field options wowutils_options
---@field craftingOrderCache table<string, table<number, wowutils_craftingOrderProfession>> guild dbSlug -> Enum.Profession -> data

---@class wowutils_craftingOrderProfession
---@field lastScan number last time someone with the profession scanned guild orders
---@field lastUpdate number lastScan or last customer side edit, whichever is newer, used for syncing
---@field orders table<number, wowutils_craftingOrder> orderId -> order

---@class wowutils_craftingOrder
---@field customerGuid string short guid, without the "Player-" prefix
---@field expirationTime number
---@field itemId number
---@field isRecraft true? nil instead of false to keep transfers small
---@field isDone true? nil instead of false to keep transfers small
---@field updated number? only set on entries from a customer side scan, kept on merge while newer than lastScan
---@field tip number? gold, floored, nil when under 1g
---@field seen number? first seen, as whole minutes before expirationTime (smaller on the wire than a timestamp). nil for entries from before it was tracked

---@class wowutils_options
---@field characterFilters wowutils_options_characterFilters
---@field warboundOptions wowutils_options_warboundOptions
---@field notifications wowutils_options_notifications
---@field craftingOrders wowutils_options_craftingOrders

---@class wowutils_options_craftingOrders
---@field tipThreshold number minimum tip in gold for a notification
---@field printToChat boolean also print notifications to chat
---@field professions table<number, boolean> Enum.Profession -> notify for it

---@class wowutils_options_notifications
---@field x number offset from UIParent center
---@field y number offset from UIParent center
---@field font string LibSharedMedia font name
---@field fontSize number
---@field spacing number extra space between lines
---@field color {r:number, g:number, b:number} used when a message doesn't pass its own color
---@field justify "LEFT"|"CENTER"|"RIGHT"
---@field timeVisible number seconds before a message starts fading
---@field fadeDuration number

---@class wowutils_options_warboundOptions
---@field enabled boolean show warbound until equipped drops from loot messages
---@field selfOnly boolean only show own drops

---@class wowutils_options_characterFilters
---@field hideUntracked boolean? hide characters no synclist tracks
---@field hideLowIlvl boolean? hide characters whose watermark median is below ns.config.guiIlvlFilter

---@class wowutilsSyncList
---@field lastUpdate number
---@field characters table<number, string> id, slug

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
---@field dataRefreshTimes table<string, number>
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
---@field bonusCoinUsage wowutils_bonusCoinUsage[]
---@field bonusCoinUsageUpdated number
---@field bonusCoinScannedHistory table<number, wowutils_bonuscoinMissingItems[]> -- specID = missingItems[]
---@field bonusCoinScannedHistoryUpdated number
---@field addonVersion string
---@field itemCache table<wowutils_enums_itemCacheType, table<string, wowutils_itemcache>> -- string = itemGuid
---@field itemCacheUpdated number
---@field lockouts number? raid lockout mask, layout from ns.config.lockouts, a set bit means the boss is still available. nil = never scanned
---@field lockoutsUpdated number
---@field dungeonsDone table<number, number> -- keyLevel = keysDone
---@field dungeonsUpdated number

---@class wowutils_bonuscoinMissingItems
---@field itemId number
---@field difId number

---@class wowutils_bonusCoinUsage
---@field difId number
---@field itemLink string
---@field encounterId number
---@field receiveTime number
---@field specId number
---@field season number
---@field instanceId number

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
---@field groupId string? last import group this character belonged to

---@class wowutilsDroptimizerData_sims
---@field simType wowutils_enums_simTypes
---@field items table<number, wowutilsDroptimizerData_droptimizerItem[]> one array per itemId. a sim can report the same item more than once: rings/trinkets/weapons simmed into each slot they fit, and pieces reachable both as a drop and through the catalyst
---@field simmedAt number
---@field baseline number? raidbot only

---@class wowutilsDroptimizerData_droptimizerItem
---@field equipmentSlot number
---@field ilvl number
---@field difficultyId number the difficulty the sim ran at, not the item's own track
---@field gain number? raidbots only
---@field gainPercent number? qelive only
---@field encounterId number? journal encounter the item drops from, negative for non-raid sources
---@field sourceItem wowutilsDroptimizerData_droptimizerItemSource? set when the item is not a direct drop

---@class wowutilsDroptimizerData_droptimizerItemSource what actually has to drop for the parent item to be obtainable
---@field itemId number the token/base item that converts into the parent item
---@field encounterId number?
---@field catalyst boolean? true for a catalyst charge rather than a tier token

---@class wowutilsDroptimizerData_wishlistItem
---@field equipmentSlot number
---@field priority string the group's display label for the tier, as picked on the site
---@field priorityId number? raw tier 1..5 (site identity, drives the tier color)
---@field updated number
---@field difficultyId number
---@field itemId number
---@field note? string

---@class wowutils_itemcache
---@field equipped number?
---@field itemLink string
---@field warbound boolean?

---@type wowutils_options_notifications
local notificationDefaults = {
  x = 0,
  y = 150,
  font = "IBM Plex Sans SemiBold", -- registered to LSM in notifications.lua
  fontSize = 18,
  spacing = 0,
  color = { r = 1, g = 1, b = 1 },
  justify = "CENTER",
  timeVisible = 3,
  fadeDuration = 0.5,
}

---@type wowutils_options_craftingOrders
local craftingOrderDefaults = {
  tipThreshold = 10,
  printToChat = true,
  professions = {}, -- everything off by default, same as the liquid addon
}

---@type wowutilsSavedVariables
WowUtilsDB = WowUtilsDB or {
  dbVersion = ns.config.currentDBVersion,
  lastCharacter = {},
  ownCharacters = {},
  others = {},
  droptimizerData = {},
  lastSeenWeeklyReset = C_DateAndTime.GetWeeklyResetStartTime(),
  syncLists = {},
  options = {
    characterFilters = {},
    warboundOptions = { enabled = false, selfOnly = false },
    notifications = CopyTable(notificationDefaults),
    craftingOrders = CopyTable(craftingOrderDefaults),
  },
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
    lockoutsUpdated = 0, -- lockouts itself stays nil until the first scan, 0 would read as everything killed
  }
else
  WowUtilsDB.ownCharacters[ns.me.guid].name = ns.me.name
  WowUtilsDB.ownCharacters[ns.me.guid].droptimizerKey = ns.me.droptimizerKey
  WowUtilsDB.ownCharacters[ns.me.guid].class = select(2, UnitClass('player'))
  WowUtilsDB.ownCharacters[ns.me.guid].region = ns.me.regionId
  WowUtilsDB.ownCharacters[ns.me.guid].lastWeeklyReset = C_DateAndTime.GetWeeklyResetStartTime()
end
if not WowUtilsDB.syncLists then
  WowUtilsDB.syncLists = {}
end
if not WowUtilsDB.options then -- added on 1.0.4, existing installs have no table yet
  WowUtilsDB.options = { characterFilters = {}, warboundOptions = { enabled = false, selfOnly = false }, notifications = CopyTable(notificationDefaults), craftingOrders = CopyTable(craftingOrderDefaults) }
end
if not WowUtilsDB.options.characterFilters then
  WowUtilsDB.options.characterFilters = {}
end
if not WowUtilsDB.options.warboundOptions then
  WowUtilsDB.options.warboundOptions = { enabled = false, selfOnly = false }
end
if not WowUtilsDB.options.notifications then
  WowUtilsDB.options.notifications = CopyTable(notificationDefaults)
end
-- fill per key, so options added later on get their default without resetting the rest
for k, v in pairs(notificationDefaults) do
  if WowUtilsDB.options.notifications[k] == nil then
    WowUtilsDB.options.notifications[k] = type(v) == "table" and CopyTable(v) or v
  end
end
if not WowUtilsDB.options.craftingOrders then -- added on 1.0.8
  WowUtilsDB.options.craftingOrders = CopyTable(craftingOrderDefaults)
end
for k, v in pairs(craftingOrderDefaults) do
  if WowUtilsDB.options.craftingOrders[k] == nil then
    WowUtilsDB.options.craftingOrders[k] = type(v) == "table" and CopyTable(v) or v
  end
end
if not WowUtilsDB.droptimizerData then -- the cleanup sweep below walks this on every client now
  WowUtilsDB.droptimizerData = {}
end
if not WowUtilsDB.craftingOrderCache then -- added on 1.0.8
  WowUtilsDB.craftingOrderCache = {}
end
-- early 1.0.8 builds kept orders as an array with orderId inside each entry, rekey those by orderId
--[=[
for _, guildCache in pairs(WowUtilsDB.craftingOrderCache) do
  for _, professionData in pairs(guildCache) do
    local orders = professionData.orders --[[@as table]]
    if type(orders) == "table" and orders[1] and orders[1].orderId then
      local keyed = {}
      for _, order in ipairs(orders) do
        keyed[order.orderId] = order
        order.orderId = nil
      end
      professionData.orders = keyed
    end
  end
end
--]=]
---@type wowutils_ownChar
local charDB = WowUtilsDB.ownCharacters[ns.me.guid]
local db = WowUtilsDB
db.lastCharacter.guid = ns.me.guid
db.lastCharacter.region = ns.me.regionId
---db 2 stored a single entry per itemId (`items[itemId] = entry`), which silently dropped every
---duplicate a sim reported for the same item. db 3 stores an array instead. Shared with the sync
---path in mapping.lua: a guildmate still on db 2 can hand us their droptimizer data, and
---normalizing it on arrival keeps them useful mid-upgrade instead of dropping the message.
---@param record wowutilsDroptimizerData?
local function normalizeDroptimizerRecord(record)
  if not (record and record.specs) then return end
  for _, sims in pairs(record.specs) do
    for _, simData in pairs(sims) do
      local items = simData.items
      if items then
        for itemId, entry in pairs(items) do
          -- an array has [1] set, the old single entry never does. replacing an existing key
          -- mid-pairs() is fine, only adding new ones is undefined
          if entry[1] == nil and next(entry) ~= nil then
            items[itemId] = { entry }
          end
        end
      end
    end
  end
end

if db.dbVersion < ns.config.currentDBVersion then
  -- upgrade db based on version
  if db.dbVersion < 3 then
    for _, record in pairs(db.droptimizerData) do
      normalizeDroptimizerRecord(record)
    end
    -- normalizing only reshapes what we already stored, and db 2 never kept encounterId or
    -- sourceItem at all. without a re-read nothing would know a piece comes from the catalyst
    -- until the source file next happens to change
    ns.forceDroptimizerReimport = true
  end
end
charDB.addonVersion = C_AddOns.GetAddOnMetadata(addon_name, "Version")

---@class wowutils_database
ns.database = {}
ns.database.NormalizeDroptimizerRecord = normalizeDroptimizerRecord
ns.database.ownSlugs = {}
do
  local timestampFields = {
    "lastUpdate", "currencyUpdated", "watermarksUpdated", "craftingItemsUpdated", "questsUpdated", "vaultDataLastUpdate",
    "weeklyRewardsUpdate", "bonusCoinUsageUpdated", "lockoutsUpdated", "dungeonsUpdated",
  }
  local tableFields = { "currency", "watermarks", "quests", "vaultData", "weeklyRewards", "bonusCoinUsage", "dungeonsDone" }
  ---fills in what older versions (or a broken sender) left out or got wrong, so readers don't have to check every field
  ---@param char table
  function ns.database.NormalizeCharRecord(char)
    for _, key in ipairs(timestampFields) do
      if type(char[key]) ~= "number" then char[key] = 0 end
    end
    for _, key in ipairs(tableFields) do
      if type(char[key]) ~= "table" then char[key] = {} end
    end
    if type(char.craftingItems) ~= "number" then char.craftingItems = 0 end
    -- these two mean something when nil (never scanned / never refreshed), so only drop wrong types
    if char.lockouts ~= nil and type(char.lockouts) ~= "number" then char.lockouts = nil end
    if char.dataRefreshTimes ~= nil and type(char.dataRefreshTimes) ~= "table" then char.dataRefreshTimes = nil end
  end
end

---a guid change (race/faction change, delete + recreate) keeps the droptimizerKey, so the same key can
---turn up under two guids. the stale one never updates itself again, but whoever still holds it keeps
---relaying it around the guild and resetting its expiry. keep only the freshest record per key.
---lastUpdate is written by the character itself, so it's comparable across guids (summed timestamps aren't)
---@param guid string guid the incoming record is about to be stored under
---@param key string? droptimizerKey of the incoming record
---@param lastUpdate number? lastUpdate of the incoming record
---@return boolean accept false when a record under another guid with the same key is at least as fresh
function ns.database.ResolveKeyConflict(guid, key, lastUpdate)
  if type(key) ~= "string" then return true end
  lastUpdate = type(lastUpdate) == "number" and lastUpdate or 0
  -- own characters count as competitors too, so a relayed copy of our own old guid is rejected, but they
  -- are never deleted from here: if someone else took a deleted character's name, their newer data wins
  for _, chars in ipairs({ WowUtilsDB.ownCharacters, WowUtilsDB.others }) do
    for otherGuid, char in pairs(chars) do
      if otherGuid ~= guid and char.droptimizerKey == key and (char.lastUpdate or 0) >= lastUpdate then
        WowUtilsDB.others[guid] = nil -- our copy under the incoming guid is just as stale
        ns.Debug.print("dropping '%s' for key '%s', '%s' is fresher", guid, key, otherGuid)
        return false
      end
    end
  end
  for otherGuid, char in pairs(WowUtilsDB.others) do
    if otherGuid ~= guid and char.droptimizerKey == key then
      ns.Debug.print("removing stale guid '%s' for key '%s', replaced by '%s'", otherGuid, key, guid)
      WowUtilsDB.others[otherGuid] = nil -- clearing an existing field mid pairs() is fine
    end
  end
  return true
end
for _, char in pairs(WowUtilsDB.others) do
  ns.database.NormalizeCharRecord(char)
end
local clearOldConfigData = (db.configVersion or 0) < ns.config.configVersion
local resetCraftingItems = (db.configVersion or 0) < 4
if clearOldConfigData then
  -- the import only re-reads a character when the source file is newer than what we already
  -- stored, so an existing install would never run the droptimizer prune until the next time
  -- that file happens to change. flag one forced pass rather than zeroing lastUpdate, which
  -- the cleanup sweep at the bottom of this file reads.
  ns.forceDroptimizerReimport = true
end
for k,v in pairs(WowUtilsDB.ownCharacters) do
  ns.database.ownSlugs[v.droptimizerKey] = true
  if db.others[k] then -- 1.0.0 accepted own messages which added own characters to .others, might as well keep this clean up since its cheap
    db.others[k] = nil
  end
  if clearOldConfigData then
    local toDelete = {}
    for currencyId in pairs(v.currency) do
      if not ns.config.currencies[currencyId] then
        toDelete[currencyId] = true
      end
    end
    for del in pairs(toDelete) do
      v.currency[del] = nil
    end
    wipe(toDelete)
    for questId in pairs(v.quests) do
      if not ns.config.quests[questId] then
        toDelete[questId] = true
      end
    end
    for del in pairs(toDelete) do
      v.quests[del] = nil
    end
    if resetCraftingItems then
      v.craftingItems = 0
    end
  end
end
db.configVersion = ns.config.configVersion
local cacheTimers = {}
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
  elseif context == ns.enums.context.bonusCoin then
    charDB.bonusCoinUsageUpdated = serverTime
    ns.communication.SendBonusCoinUsageUpdate()
  elseif context == ns.enums.context.lockouts then
    charDB.lockoutsUpdated = serverTime
    ns.communication.SendLockoutUpdate()
  elseif context == ns.enums.context.itemCache then
    charDB.itemCacheUpdated = serverTime
    if cacheTimers.itemCache then cacheTimers.itemCache:Cancel() end
    cacheTimers.itemCache = C_Timer.NewTimer(3, function()
      ns.communication.SendItemsFromSpecificCharacter(charDB)
    end)
  elseif context == ns.enums.context.dungeonsDone then
    charDB.dungeonsUpdated = serverTime
    ns.communication.SendDungeonsDoneUpdate()
  end
  charDB.lastUpdate = serverTime
end

---@param context wowutils_enums_context
---@param targetDB wowutils_otherChar|wowutils_ownChar
function ns.database.DataRefreshed(context, targetDB)
  if not (context and targetDB) then
    ns.Debug.print("Trying to call ns.database.DataRefreshed with incorrect data - context '%s', targetDB '%s'", tostring(context), tostring(targetDB))
    return
  end
  local _type
  if context == ns.enums.context.currency then
    _type = "currency"
  elseif context == ns.enums.context.watermarks then
    _type = "watermarks"
  elseif context == ns.enums.context.craftingItems then
    _type = "craftingItems"
  elseif context == ns.enums.context.vaultData then
    _type = "vaultData"
  elseif context == ns.enums.context.weeklyRewards then
    _type = "weeklyRewards"
  elseif context == ns.enums.context.quests then
    _type = "quests"
  elseif context == ns.enums.context.bonusCoin then
    _type ="bonusCoinUsage"
  elseif context == ns.enums.context.lockouts then
    _type = "lockouts"
  elseif context == ns.enums.context.itemCache then
    _type ="itemCache"
  elseif context == ns.enums.context.dungeonsDone then
    _type = "dungeonsDone"
  end
  if not _type then return end
  if not targetDB.dataRefreshTimes then
    targetDB.dataRefreshTimes = {}
  end
  targetDB.dataRefreshTimes[_type] = GetServerTime()
end
---@param context string
---@param id string|number?
---@param data any
function ns.database.SaveToCurrentCharacterDB(context, id, data)
  ns.database.DataRefreshed(context, charDB)
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
        charDB.quests = data
        contextUpdated(context)
        return
      end
      for _k, _v in pairs(d) do
        if charDB.quests[questId][_k] ~= _v then
          charDB.quests = data
          contextUpdated(context)
          return
        end
      end
    end
    return
  end

  if context == ns.enums.context.bonusCoin then
    ---@cast data wowutils_bonusCoinUsage
    if not charDB.bonusCoinUsage then
      charDB.bonusCoinUsage = {}
    end
    tinsert(charDB.bonusCoinUsage, data)
    contextUpdated(context)
    return
  end

  if context == ns.enums.context.lockouts then
    ---@cast data number
    if charDB.lockouts == data then return end
    charDB.lockouts = data
    contextUpdated(context)
    return
  end

  if context == ns.enums.context.itemCache then
    ---@cast data wowutils_itemcache
    ---@cast id wowutils_enums_itemCacheType
    -- data is also used as cache in the source functions, so we need to copy it to SV instead of using as is
    if not charDB.itemCache then
      charDB.itemCache = {[id] = CopyTable(data)}
      contextUpdated(context)
      return
    end
    if not charDB.itemCache[id] then
      charDB.itemCache[id] = CopyTable(data)
      contextUpdated(context)
      return
    end
    local changed = false
    -- check if some of the old items is missing from new data first
    for ig, v in pairs(charDB.itemCache[id]) do
      if not data[ig] then
        changed = true
        break
      end
    end
    -- check if there are new items, or one of the old items was changed
    if not changed then
      for ig,v in pairs(data) do
        if not charDB.itemCache[id][ig] then
          changed = true
          break
        end
        if charDB.itemCache[id][ig].equipped ~= v.equipped or charDB.itemCache[id][ig].itemLink ~= v.itemLink then
          changed = true
          break
        end
      end
    end
    if not changed then return end
    charDB.itemCache[id] = CopyTable(data)
    contextUpdated(context)
    return
  end

  if context == ns.enums.context.dungeonsDone then
    ---@cast data table<number, number>
    if not charDB.dungeonsDone then
      charDB.dungeonsDone = data
      contextUpdated(context)
      return
    end
    for k,v in pairs(data) do
      if charDB.dungeonsDone[k] ~= v then
        charDB.dungeonsDone = data
        contextUpdated(context)
        return
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
function ns.database.CheckEligibleSyncLists()
  wipe(ns.eligibleSyncLists)
  for listId, charList in pairs(WowUtilsDB.syncLists) do
    local counter = 0
    for k,v in pairs(charList.characters) do
      if ns.currentGuildSlugs[v] then
        counter = counter + 1
      end
      if counter >= 5 then
        ns.eligibleSyncLists[listId] = true
        ns.Debug.print("Setting '%s' to eligible list", listId)
        break
      end
    end
  end
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
    -- unknown stays unknown. timestamp is left alone, others treat anything older than the reset as all available anyway
    if charData.lockouts then
      charData.lockouts = ns.lockouts.fullMask
    end
  end
end

--#region Clean up
do
  local characterKeepThreshold = GetServerTime() - ns.config.droptimizerKeepTime -- 14 days
  local droptimizerKeepThreshold = GetServerTime() - ns.config.droptimizerKeepTime
  local toDelete = {}
  for k,v in pairs(WowUtilsDB.others) do
    if (v.lastUpdateReceived or 0) < characterKeepThreshold then
      toDelete[k] = true
    end
  end
  for k,v in pairs(toDelete) do
    WowUtilsDB.others[k] = nil
  end
  wipe(toDelete)
  -- same character under several guids (see ns.database.ResolveKeyConflict), sweep up whatever got stored
  -- before that check existed. the guid we're logged in on is the live one for our own key
  for guid, char in pairs(WowUtilsDB.ownCharacters) do
    if guid ~= ns.me.guid and char.droptimizerKey == ns.me.droptimizerKey then
      WowUtilsDB.ownCharacters[guid] = nil
    end
  end
  local freshest = {} -- droptimizerKey -> char
  for _, chars in ipairs({ WowUtilsDB.ownCharacters, WowUtilsDB.others }) do
    for _, char in pairs(chars) do
      local key = char.droptimizerKey
      if key and (not freshest[key] or (char.lastUpdate or 0) > (freshest[key].lastUpdate or 0)) then
        freshest[key] = char
      end
    end
  end
  for guid, char in pairs(WowUtilsDB.others) do
    if char.droptimizerKey and freshest[char.droptimizerKey] ~= char then
      toDelete[guid] = true
    end
  end
  for k in pairs(toDelete) do
    ns.Debug.print("removing duplicate guid '%s' for key '%s'", k, WowUtilsDB.others[k].droptimizerKey)
    WowUtilsDB.others[k] = nil
  end
  wipe(toDelete)
  -- only the character running the data addon ever imports, so everyone else depends on this
  -- sweep to shed droptimizers that stopped being updated. every client runs the same rule
  -- against the same timestamps, so they converge without any extra messages.
  for key, data in pairs(WowUtilsDB.droptimizerData) do
    if data.specs then
      for specId, sims in pairs(data.specs) do
        for simId, simData in pairs(sims) do
          if (simData.simmedAt or 0) < droptimizerKeepThreshold then
            sims[simId] = nil
          end
        end
        if not next(sims) then
          data.specs[specId] = nil
        end
      end
    end
    if (data.lastUpdate or 0) < droptimizerKeepThreshold then
      toDelete[key] = true
    end
  end
  for k in pairs(toDelete) do
    ns.Debug.print("removing stale droptimizer data for '%s'", k)
    WowUtilsDB.droptimizerData[k] = nil
  end
  C_MythicPlus.RequestMapInfo()
  local currentSeason = C_MythicPlus.GetCurrentSeason()
  ns.Debug.print("Current M+ season: %s", currentSeason)
  if currentSeason and currentSeason > 0 then -- returns -1 until the RequestMapInfo response arrives
    for k,v in pairs(WowUtilsDB.ownCharacters) do
      if v.bonusCoinUsage then
        for i = #v.bonusCoinUsage, 1, -1 do
          if v.bonusCoinUsage[i].season < currentSeason then
            tremove(v.bonusCoinUsage, i)
          end
        end
      end
    end
  end
end
--#end region
db.dbVersion = ns.config.currentDBVersion