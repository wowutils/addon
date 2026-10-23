---@class wowutilsPrivate
---@field mapping wowutils_mapping

---@type string, wowutilsPrivate
local addon_name, ns = ...
local tconcat, sformat, tinsert, floor, sbyte, strsplit, SerializeCBOR, DeserializeCBOR, EncodeBase64, DecodeBase64 = table.concat, string.format, table.insert, math.floor, string.byte, strsplit, C_EncodingUtil.SerializeCBOR, C_EncodingUtil.DeserializeCBOR, C_EncodingUtil.EncodeBase64, C_EncodingUtil.DecodeBase64
local _cache = {}
---@alias wowutils_mapping_toRealDataFunc fun(configVersion:number, dbVersion:number, str:string, db:wowutils_otherChar?, key:string?, channel:string, sender:string):...? -- non cbors get full guid as key, cbors only get partial

---@param guid string
---@param channel string
---@return wowutils_otherChar?
local function confirmAndReturnDBForChar(guid, channel)
  if not WowUtilsDB.others[guid] then
    ns.communication.RequestFullSync(ns.mapping.ConvertGuidToMsgFormat(guid), channel)
    return
  end
  return WowUtilsDB.others[guid]
end

---cbor payloads start with a length byte, the timestamp, and then the cbor itself
---@param str string
---@return number? timestamp nil when the header is missing or broken
---@return string? rest everything after the timestamp
local function readCborPayload(str)
  local timestampLength = str:byte(1)
  if not timestampLength then return end
  local timestamp = tonumber(str:sub(2, 1 + timestampLength))
  if not timestamp then return end
  return timestamp, str:sub(2 + timestampLength)
end

local alreadyCheckedAddonVersions = {}
local function checkVersionForUpdate(versionStr, sender)
  if not versionStr then return end
  if alreadyCheckedAddonVersions[versionStr] then return end
  alreadyCheckedAddonVersions[versionStr] = true
  if not ns.helpers.IsNewerAddonVersion(versionStr) then return end
  ns.print(sformat("Newer addon version - %s - detected from '%s'.", versionStr, sender))
end

---@enum CurrentMappingUsage
local currentUsage = {
  watermarks = "A",
  currency = "B",
  craftingItems = "C",
  characterInformation = "D",
  droptimizerData = "E",
  fullCharacterSync = "F",
  vaultData = "G",
  weeklyRewards = "H",
  quests = "I",
  whitelistCharSyncRequest = "J",
  fullCharacterSyncFromDB = "K",
  fullSynclist = "L",
  generalUpdateCheck = "M",
  syncListRequest = "N",
  bonusCoinUsage = "O",
  itemCache = "P",
  craftingOrders = "Q",
  lockouts = "R",
  dungeonsDone = "S",
  --["T"] = nil,
  --["U"] = nil,
  --["V"] = nil,
  --["W"] = nil,
  --["X"] = nil,
  --["Y"] = nil,
  --["Z"] = nil,
  --["a"] = nil,
  --["b"] = nil,
  --["c"] = nil,
  --["d"] = nil,
  --["e"] = nil,
  --["f"] = nil,
  --["g"] = nil,
  --["h"] = nil,
  --["i"] = nil,
  --["j"] = nil,
  --["k"] = nil,
  --["l"] = nil,
  --["m"] = nil,
  --["n"] = nil,
  --["o"] = nil,
  --["p"] = nil,
  --["q"] = nil,
  --["r"] = nil,
  --["s"] = nil,
  --["t"] = nil,
  --["u"] = nil,
  --["v"] = nil,
  --["w"] = nil,
  --["x"] = nil,
  --["y"] = nil,
  --["z"] = nil,
  --["1"] = nil,
  --["2"] = nil,
  --["3"] = nil,
  --["4"] = nil,
  --["5"] = nil,
  --["6"] = nil,
  --["7"] = nil,
  --["8"] = nil,
  --["9"] = nil,
}

---@class dataQueueData
---@field updated number
---@field data any

---@type table<CurrentMappingUsage, table<string, dataQueueData>>
local dataQueue = {}
for _,v in pairs(currentUsage) do -- we don't actually use this for everything, but this way we don't have to worry about it later, tabls arent that costly so cba
  dataQueue[v] = {}
end
local function updateRefreshTimeIfNeededForFullSync(currentData, incomingData, dataType, isNewer)
  if not currentData.dataRefreshTimes then
    currentData.dataRefreshTimes = {}
  end
  if not currentData.dataRefreshTimes[dataType] then
    currentData.dataRefreshTimes[dataType] = 0
  end
  if not (incomingData.dataRefreshTimes and incomingData.dataRefreshTimes[dataType]) then return end -- tecnically there might be some weird cases at start, but that doesn't really matter since its only when updating from old (0.0.7b) version to newer
  if isNewer then
    currentData.dataRefreshTimes[dataType] = incomingData.dataRefreshTimes[dataType]
    return
  end
  if incomingData.dataRefreshTimes[dataType] <= currentData.dataRefreshTimes[dataType] then return end
  currentData.dataRefreshTimes[dataType] = incomingData.dataRefreshTimes[dataType]
end
local fullSyncChecks = {
  currency = {updateKey = "currencyUpdated", refreshKey = "currency"},
  watermarks = {updateKey = "watermarksUpdated", refreshKey = "watermarks"},
  craftingItems = {updateKey = "craftingItemsUpdated", refreshKey = "craftingItems"},
  quests = {updateKey = "questsUpdated", refreshKey = "quests"},
  vaultData = {updateKey = "vaultDataLastUpdate", refreshKey = "vaultData"},
  weeklyRewards = {updateKey = "weeklyRewardsUpdate", refreshKey = "weeklyRewards"},
  bonusCoinUsage = {updateKey = "bonusCoinUsageUpdated", refreshKey = "bonusCoinUsage"},
  lockouts = {updateKey = "lockoutsUpdated", refreshKey = "lockouts"},
  dungeonsDone = {updateKey = "dungeonsUpdated", refreshKey = "dungeonsDone"},
}
---@class wowutils_mapping
---@field toRealData table<string, wowutils_mapping_toRealDataFunc>
---@field ConvertGuidToMsgFormat fun(guid:string):string
---@field ConvertPartialGuidToGuid fun(partialGuid:string):string
---@field SafeDeserializeCBOR fun(cborStr:string?):table?
ns.mapping = {
  toRealData = {
    [currentUsage.watermarks] = function(configVersion, dbVersion, str, db, targetGuid, channel) -- A
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      if not db then
        db = confirmAndReturnDBForChar(targetGuid, channel)
        if not db then return end
      end
      ns.Debug.print("receiving watermaks for '%s'", targetGuid)
      local timestamp, watermarkStr = str:match("^(%-?%d+)%?(.*)$") -- negative when the sender never had data (0 - offset)
      if not timestamp then return end
      timestamp = ns.mapping.timestamp.FromValue(timestamp)
      if db and db.watermarksUpdated then
        if db.watermarksUpdated >= timestamp then
          if db.watermarksUpdated == timestamp then
            ns.database.DataRefreshed(ns.enums.context.watermarks, db)
          end
          ns.Debug.print("already has newer data")
          return
        end                                                                                           -- Current data is newer, discard
      end
      local splits = { strsplit("^", watermarkStr) }
      local converted = {}
      for _, v in pairs(splits) do
        local _slot, _mult, _rem = v:match("^(.)(.)(.)$") -- TODO switch to :subs? (benchmark)
        if _slot then -- an empty watermark table still sends one empty entry
          local offset = ns.mapping.int.FromValue(_mult) * ns.config.watermarks.multiplier + ns.mapping.int.FromValue(_rem)
          converted[ns.mapping.int.FromValue(_slot)] = offset > 0 and (offset + ns.config.watermarks.startingPoint) or 0
        end
      end
      ns.database.DataRefreshed(ns.enums.context.watermarks, db)
      db.watermarksUpdated = timestamp
      db.watermarks = converted
      db.lastUpdateReceived = GetServerTime()
    end,
    [currentUsage.currency] = function(configVersion, dbVersion, str, db, targetGuid, channel) -- B
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      if not db then
        db = confirmAndReturnDBForChar(targetGuid, channel)
        if not db then return end
      end
      if not _cache[configVersion] then
        _cache[configVersion] = {}
      end
      ns.Debug.print("receiving currency for '%s'", targetGuid)
      local timestamp, currencyStr = str:match("^(%-?%d+)%?(.*)$") -- negative when the sender never had data (0 - offset)
      if not timestamp then return end
      timestamp = ns.mapping.timestamp.FromValue(timestamp)
      if db.currencyUpdated >= timestamp then  -- Current data is newer, discard
        if db.currencyUpdated == timestamp then
          ns.database.DataRefreshed(ns.enums.context.currency, db)
        end
        return
      end
      local splits = { strsplit("^", currencyStr) }
      for _, v in pairs(splits) do
        local _currencyMapId, _current, _total = v:match("^(.)(%d+)%?(%d+)$")
        _currencyMapId = tonumber(_currencyMapId)
        _current = tonumber(_current)
        _total = tonumber(_total)
        if _currencyMapId and _current and _total then
          local currencyId = _cache[configVersion][_currencyMapId]
          if not currencyId then
            for cId, mapId in pairs(ns.config.currencies) do
              if mapId == _currencyMapId then
                _cache[configVersion][_currencyMapId] = cId
                currencyId = cId
                break
              end
            end
          end
          if currencyId then
            db.currency[currencyId] = {
              current = _current,
              totalEarned = _total
            }
          end
        end
      end
      ns.database.DataRefreshed(ns.enums.context.currency, db)
      db.currencyUpdated = timestamp
      db.lastUpdateReceived = GetServerTime()
    end,
    [currentUsage.craftingItems] = function(configVersion, dbVersion, str, db, targetGuid, channel) -- C
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      if not db then
        db = confirmAndReturnDBForChar(targetGuid, channel)
        if not db then return end
      end
      ns.Debug.print("receiving crafting items for '%s'", targetGuid)
      local timestamp, itemCount = str:match("^(.-)%?(.+)$")
      timestamp = ns.mapping.timestamp.FromValue(timestamp)
      if db.craftingItemsUpdated >= timestamp then -- Current data is newer, discard
        if db.craftingItemsUpdated == timestamp then
          ns.database.DataRefreshed(ns.enums.context.craftingItems, db)
        end
        return
      end
      ns.database.DataRefreshed(ns.enums.context.craftingItems, db)
      db.craftingItems = ns.mapping.int.FromValue(itemCount)
      db.craftingItemsUpdated = timestamp
      db.lastUpdateReceived = GetServerTime()
    end,
    [currentUsage.characterInformation] = function(configVersion, dbVersion, str, db, targetGuid, channel) -- D
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      if not db then
        db = confirmAndReturnDBForChar(targetGuid, channel)
        if not db then return end
      end
      local guid, charName, class, lastUpdate, lastUpdateReceived, region = strsplit("^", str)
      --return sformat("Player-%s", guid), charName, ns.mapping.class.FromValue(class), ns.mapping.timestamp.FromValue(lastUpdate), ns.mapping.timestamp.FromValue(lastUpdateReceived), tonumber(region) or -1
    end,
    [currentUsage.droptimizerData] = function(configVersion, dbVersion, str, db, key, channel) -- E
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      local timestamp, cborStr = readCborPayload(str)
      if not timestamp then return end
      ns.Debug.print("receiving droptimizer data for '%s'", key)
      if WowUtilsDB.droptimizerData[key] and WowUtilsDB.droptimizerData[key].lastUpdate >= timestamp then return end -- already have newer data
      local t = ns.mapping.SafeDeserializeCBOR(cborStr)
      if not t then return end
      -- the guard above only rejects senders on a *newer* db, so a client still on db 2 gets
      -- through here with the pre-array item shape. normalize rather than drop them
      ns.database.NormalizeDroptimizerRecord(t)
      WowUtilsDB.droptimizerData[key] = t
      ns.rclc.DataUpdated()
    end,
    [currentUsage.fullCharacterSync] = function(configVersion, dbVersion, str, db, partialGuid, channel) -- F
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      local timestamp, cborStr = readCborPayload(str)
      if not timestamp then return end
      local targetGuid = ns.mapping.ConvertPartialGuidToGuid(partialGuid)
      ns.Debug.print("receiving full character sync for '%s'", targetGuid)
      if WowUtilsDB.others[targetGuid] and (WowUtilsDB.others[targetGuid].lastUpdate or 0) >= timestamp then return end -- already have newer data
      -- might as well update since someone is sending it
      local t = ns.mapping.SafeDeserializeCBOR(cborStr)
      if type(t) ~= "table" then return end
      if not ns.database.ResolveKeyConflict(targetGuid, t.droptimizerKey, t.lastUpdate) then return end
      if not WowUtilsDB.others[targetGuid] then
        ---@diagnostic disable-next-line: missing-fields
        WowUtilsDB.others[targetGuid] = {}
        if dataQueue[currentUsage.itemCache][targetGuid] then
          WowUtilsDB.others[targetGuid].itemCache = dataQueue[currentUsage.itemCache][targetGuid].data
          WowUtilsDB.others[targetGuid].itemCacheUpdated = dataQueue[currentUsage.itemCache][targetGuid].updated
          dataQueue[currentUsage.itemCache][targetGuid] = nil
        end
      end
      for k,v in pairs(t) do -- not everything is sent through this, so we can't replace the whole table anymore
        WowUtilsDB.others[targetGuid][k] = v
      end
      ns.database.NormalizeCharRecord(WowUtilsDB.others[targetGuid])
      WowUtilsDB.others[targetGuid].lastUpdateReceived = GetServerTime()
    end,
    [currentUsage.vaultData] = function(configVersion, dbVersion, str, db, partialGuid, channel) -- G
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      local targetGuid = ns.mapping.ConvertPartialGuidToGuid(partialGuid)
      if not db then
        db = confirmAndReturnDBForChar(targetGuid, channel)
        if not db then return end
      end
      local timestamp, cborStr = readCborPayload(str)
      if not timestamp then return end
      ns.Debug.print("receiving vault data update for '%s'", targetGuid)
      if db and (db.vaultDataLastUpdate or 0) >= timestamp then -- already have newer data
        if db and db.vaultDataLastUpdate == timestamp then
          ns.database.DataRefreshed(ns.enums.context.vaultData, db)
        end
        return
      end
      -- might as well update since someone is sending it
      local t = ns.mapping.SafeDeserializeCBOR(cborStr)
      if not t then return end
      ns.database.DataRefreshed(ns.enums.context.vaultData, db)
      db.vaultDataLastUpdate = timestamp
      db.vaultData = t
      db.lastUpdateReceived = GetServerTime()
    end,
    [currentUsage.weeklyRewards] = function(configVersion, dbVersion, str, db, partialGuid, channel) -- H
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      local targetGuid = ns.mapping.ConvertPartialGuidToGuid(partialGuid)
      if not db then
        db = confirmAndReturnDBForChar(targetGuid, channel)
        if not db then return end
      end
      local timestamp, cborStr = readCborPayload(str)
      if not timestamp then return end
      ns.Debug.print("receiving weekly rewards data update for '%s'", targetGuid)
      if (db.weeklyRewardsUpdate or 0) >= timestamp then -- already have newer data
        if db.weeklyRewardsUpdate == timestamp then
          ns.database.DataRefreshed(ns.enums.context.weeklyRewards, db)
        end
        return
      end
      -- might as well update since someone is sending it
      local t = ns.mapping.SafeDeserializeCBOR(cborStr)
      if not t then return end
      ns.database.DataRefreshed(ns.enums.context.weeklyRewards, db)
      db.weeklyRewardsUpdate = timestamp
      db.weeklyRewards = t
      db.lastUpdateReceived = GetServerTime()
    end,
    [currentUsage.quests] = function(configVersion, dbVersion, str, db, targetGuid, channel) -- I
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      if not db then
        db = confirmAndReturnDBForChar(targetGuid, channel)
        if not db then return end
      end
      local timestamp, questDataStr = str:match("^(%-?%d+)%?(.*)$") -- negative when the sender never had data (0 - offset)
      if not timestamp then return end
      timestamp = ns.mapping.timestamp.FromValue(timestamp)
      if db.questsUpdated >= timestamp then -- we already have newer data, discard
        ns.database.DataRefreshed(ns.enums.context.quests, db)
        return
      end
      ns.Debug.print("receiving quest update for '%s'", targetGuid)
      for _, v in pairs({ strsplit("^", questDataStr) }) do
        local completed, completedWarbound, questId = v:match("^(.)(.)(.*)$")
        questId = tonumber(questId)
        if questId and ns.config.quests[questId] then
          db.quests[questId] = {
            completed = ns.mapping.boolean.MapValueToBoolean(completed),
            completedWarbound = ns.mapping.boolean.MapValueToBoolean(completedWarbound),
            isWeeklyQuest = ns.config.quests[questId].isWeeklyQuest,
          }
        end
      end
      ns.database.DataRefreshed(ns.enums.context.quests, db)
      db.questsUpdated = timestamp
      db.lastUpdateReceived = GetServerTime()
    end,
    [currentUsage.whitelistCharSyncRequest] = function(configVersion, dbVersion, str, db, partialGuid, channel) -- J
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      -- this one answers with data, so don't bother for a requester on an older config: every handler
      -- drops messages from a newer config, so they would just throw away whatever we sent back.
      -- 6 also added lockoutsUpdated to the timestamp sums, so older sums can't be compared anyway
      if configVersion < 6 then return end
      --[[
       for _,v in pairs(data) do
        tinsert(temp, sformat("%s?%s", v.id, v.timestamp))
      end
      return sformat("%s%s?%s", currentUsage.whitelistCharSyncRequest, key, tconcat(temp, "^"))
      --]]
      local listId, dataStr = strsplit("?", str, 2)
      if not listId then return end
      local targetList = WowUtilsDB.syncLists[listId] and WowUtilsDB.syncLists[listId].characters
      if not targetList then return end
      local cache -- TODO cache these on data update instead of here, good enough for now (beta)
      if configVersion < 6 then -- 6 added a seperate timestamp for items
        for _, v in pairs({ strsplit("^", dataStr) }) do
          local id, timestamp = strsplit("?", v)
          ---@diagnostic disable-next-line: cast-local-type
          id = tonumber(id)
          ---@diagnostic disable-next-line: cast-local-type
          timestamp = tonumber(timestamp)
          if id and timestamp then
            if targetList[id] then
              if not cache then
                cache = {}
                -- use guids so we dont overwrite anything by accident
                for _, charDB in ipairs({ WowUtilsDB.others, WowUtilsDB.ownCharacters }) do
                  for guid, charData in pairs(charDB) do
                    if charData.droptimizerKey then
                      local cachedGuid = cache[charData.droptimizerKey]
                      -- the same key can live in both dbs, so always look the cached guid up in both
                      local cachedChar = cachedGuid and (WowUtilsDB.ownCharacters[cachedGuid] or WowUtilsDB.others[cachedGuid])
                      if not cachedChar or (cachedChar.lastUpdate or 0) < (charData.lastUpdate or 0) then -- we have multiple data points for same key (guid has changed)
                        cache[charData.droptimizerKey] = guid
                      end
                    end
                  end
                end
              end
              if cache[targetList[id]] then
                local d = WowUtilsDB.ownCharacters[cache[targetList[id]]] or WowUtilsDB.others[cache[targetList[id]]]
                if timestamp == 0 or ns.mapping.GetCharacterTimestampsForWideSync(d) > timestamp then
                  ns.communication.SendFullSyncFromSpecificCharacter(d)
                end
              end
            end
          end
        end
        return
      end
      for _, v in pairs({ strsplit("^", dataStr) }) do
        local id, timestamp, itemTimestamp = strsplit("?", v)
        ---@diagnostic disable-next-line: cast-local-type
        id = tonumber(id)
        ---@diagnostic disable-next-line: cast-local-type
        timestamp = tonumber(timestamp)
        ---@diagnostic disable-next-line: cast-local-type
        itemTimestamp = tonumber(itemTimestamp)
        if id and timestamp and itemTimestamp then
          if targetList[id] then
            if not cache then
              cache = {}
              -- use guids so we dont overwrite anything by accident
              for _, charDB in ipairs({ WowUtilsDB.others, WowUtilsDB.ownCharacters }) do
                for guid, charData in pairs(charDB) do
                  if charData.droptimizerKey then
                    local cachedGuid = cache[charData.droptimizerKey]
                    -- the same key can live in both dbs, so always look the cached guid up in both
                    local cachedChar = cachedGuid and (WowUtilsDB.ownCharacters[cachedGuid] or WowUtilsDB.others[cachedGuid])
                    if not cachedChar or (cachedChar.lastUpdate or 0) < (charData.lastUpdate or 0) then -- we have multiple data points for same key (guid has changed)
                      cache[charData.droptimizerKey] = guid
                    end
                  end
                end
              end
            end
            if cache[targetList[id]] then
              local d = WowUtilsDB.ownCharacters[cache[targetList[id]]] or WowUtilsDB.others[cache[targetList[id]]]
              if timestamp == 0 or ns.mapping.GetCharacterTimestampsForWideSync(d) > timestamp then
                ns.communication.SendFullSyncFromSpecificCharacter(d)
              end
              if itemTimestamp == 0 or (d.itemCacheUpdated or 0) > ns.mapping.timestamp.FromValue(itemTimestamp) then
                ns.communication.SendItemsFromSpecificCharacter(d)
              end
            end
          end
        end
      end
    end,
    [currentUsage.fullCharacterSyncFromDB] = function(configVersion, dbVersion, str, db, partialGuid, channel, sender) -- K
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      -- 6 added lockoutsUpdated and dungeonsUpdated to the timestamp sums, older sums can't be compared with ours.
      -- same cutoff as J, which doesn't answer anything older either
      if configVersion < 6 then return end
      local targetGuid = ns.mapping.ConvertPartialGuidToGuid(partialGuid)
      ns.Debug.print("receiving full character sync From DB '%s' - sender '%s'", targetGuid, sender)
      if WowUtilsDB.ownCharacters[targetGuid] then return end -- don't accept syncs about own chars
      local timestamp, cborStr = readCborPayload(str)
      if not timestamp then return end
      local c = WowUtilsDB.others[targetGuid]
      if c then
        if ns.mapping.GetCharacterTimestampsForWideSync(c) >= timestamp then
          return
        end
      end
      local t = ns.mapping.SafeDeserializeCBOR(cborStr)
      if type(t) ~= "table" then return end
      ---@cast t wowutils_otherChar
      -- the merge below compares and copies these fields, so they need the right types before anything reads them
      ns.database.NormalizeCharRecord(t)
      -- relays are how a stale guid kept coming back, see ns.database.ResolveKeyConflict
      if not ns.database.ResolveKeyConflict(targetGuid, t.droptimizerKey, t.lastUpdate) then return end
      if not c then
        WowUtilsDB.others[targetGuid] = t
        if dataQueue[currentUsage.itemCache][targetGuid] then
          WowUtilsDB.others[targetGuid].itemCache = dataQueue[currentUsage.itemCache][targetGuid].data
          WowUtilsDB.others[targetGuid].itemCacheUpdated = dataQueue[currentUsage.itemCache][targetGuid].updated
          dataQueue[currentUsage.itemCache][targetGuid] = nil
        end
        t.lastUpdateReceived = GetServerTime()
        return
      end
      local updated = false
      -- only catch whats new, just in case
      for dataKey,v in pairs(fullSyncChecks) do
        if (t[v.updateKey] or 0) > (c[v.updateKey] or 0) then
          updated = true
          c[dataKey] = t[dataKey]
          c[v.updateKey] = t[v.updateKey]
          updateRefreshTimeIfNeededForFullSync(c, t, v.refreshKey, true)
        elseif t[v.updateKey] and t[v.updateKey] > 0 and t[v.updateKey] == (c[v.updateKey] or 0) then
          updateRefreshTimeIfNeededForFullSync(c, t, v.refreshKey, false)
        end
      end
      c.addonVersion = t.addonVersion -- in theory incoming data should be coming from newer point
      if not updated then return end
      c.lastUpdateReceived = GetServerTime()
    end,
    [currentUsage.fullSynclist] = function(configVersion, dbVersion, str, db, partialGuid, channel) -- L
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      local timestamp, rest = readCborPayload(str)
      if not timestamp then return end
      local listId, cborStr = strsplit("^", rest, 2)
      ns.Debug.print("receiving syncList '%s' - from '%s'", listId, partialGuid)
      if WowUtilsDB.syncLists[listId] and WowUtilsDB.syncLists[listId].lastUpdate >= timestamp then
        ns.Debug.print("already have newer data from synclist '%s'", listId)
        return
      end
      local t = ns.mapping.SafeDeserializeCBOR(cborStr)
      if not t then return end
      ---@cast t wowutilsSyncList
      WowUtilsDB.syncLists[listId] = t
      ns.database.CheckEligibleSyncLists()
      ns.Debug.print("Updated syncList '%s' - from '%s'", listId, partialGuid)
    end,
    [currentUsage.generalUpdateCheck] = function(configVersion, dbVersion, str, db, sourceGuid, channel, sender) -- M
      local tooNew = configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion
      for _, dataStr in pairs({ strsplit("^", str) }) do
        local dataType = dataStr:sub(1, 1)
        if dataType == "A" then
          if not tooNew then
            local listId, timestamp = strsplit("?", dataStr:sub(2))
            if listId and timestamp then
              if not WowUtilsDB.syncLists[listId] or WowUtilsDB.syncLists[listId].lastUpdate < ns.mapping.timestamp.FromValue(timestamp) then
                ns.communication.RequestSyncList(listId, (WowUtilsDB.syncLists[listId] and WowUtilsDB.syncLists[listId].lastUpdate or 0))
              end
            end
          end
        elseif dataType == "C" then -- crafting orders, professionId:lastUpdate pairs for their current guild
          if not tooNew then
            local professionTimestamps = {}
            for _, pair in pairs({ strsplit(",", dataStr:sub(2)) }) do
              local professionIdStr, timestampStr = strsplit(":", pair)
              local professionId, timestamp = tonumber(professionIdStr), tonumber(timestampStr)
              if professionId and timestamp then
                professionTimestamps[professionId] = ns.mapping.timestamp.FromValue(timestamp)
              end
            end
            local newer = ns.randomThings.craftingOrders.HasNewerDataThan(professionTimestamps)
            ns.Debug.print("crafting orders check from '%s': %d professions, we have newer: %s", sender, CountTable(professionTimestamps), tostring(newer))
            if newer then
              ns.communication.SendCraftingOrders()
            end
          end
        elseif dataType == "B" then -- version
          local versionStr = dataStr:sub(2)
          checkVersionForUpdate(versionStr, sender)
          if versionStr and not tooNew then
            db = db or confirmAndReturnDBForChar(sourceGuid, channel)
            if db then
              db.addonVersion = versionStr
            end
          end
        end
      end
    end,
    [currentUsage.syncListRequest] = function(configVersion, dbVersion, str, db, targetGuid, channel) -- N
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      -- answers with data too, same reasoning as J: an older config can't read our reply
      if configVersion < 6 then return end
      local listId, timestamp = strsplit("?", str)
      ---@diagnostic disable-next-line: cast-local-type
      timestamp = tonumber(timestamp)
      if not (listId and timestamp) then return end
      if not WowUtilsDB.syncLists[listId] or WowUtilsDB.syncLists[listId].lastUpdate <= timestamp then return end
      ns.communication.SendSyncList(listId)
    end,
    [currentUsage.bonusCoinUsage] = function(configVersion, dbVersion, str, db, partialGuid, channel) -- O
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      local targetGuid = ns.mapping.ConvertPartialGuidToGuid(partialGuid)
      if not db then
        db = confirmAndReturnDBForChar(targetGuid, channel)
        if not db then return end
      end
      local timestamp, cborStr = readCborPayload(str)
      if not timestamp then return end
      ns.Debug.print("receiving bonus coin usage update for '%s'", targetGuid)
      if db and (db.bonusCoinUsageUpdated or 0) >= timestamp then -- already have newer data
        if db and db.bonusCoinUsageUpdated == timestamp then
          ns.database.DataRefreshed(ns.enums.context.bonusCoin, db)
        end
        return
      end
      -- might as well update since someone is sending it
      local t = ns.mapping.SafeDeserializeCBOR(cborStr)
      if not t then return end
      ns.database.DataRefreshed(ns.enums.context.bonusCoin, db)
      db.bonusCoinUsageUpdated = timestamp
      db.bonusCoinUsage = t
      db.lastUpdateReceived = GetServerTime()
    end,
    [currentUsage.itemCache] = function(configVersion, dbVersion, str, db, partialGuid, channel, sender) -- P
      if not ns.config.itemCacheSync then return end
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      local targetGuid = ns.mapping.ConvertPartialGuidToGuid(partialGuid)
      ns.Debug.print("receiving item sync From DB '%s' - sender '%s'", targetGuid, sender)
      if WowUtilsDB.ownCharacters[targetGuid] then return end -- don't accept syncs about own chars
      local timestamp, cborStr = readCborPayload(str)
      if not timestamp then return end
      if not db then
        db = confirmAndReturnDBForChar(targetGuid, channel)
        if not db then
          if (dataQueue[currentUsage.itemCache][targetGuid] and dataQueue[currentUsage.itemCache][targetGuid].updated or 0) > timestamp then return end
          local t = ns.mapping.SafeDeserializeCBOR(cborStr)
          if not t then return end
          dataQueue[currentUsage.itemCache][targetGuid] = {
            updated = timestamp,
            data = t,
          }
          return
        end
      end
      ---@cast db wowutils_otherChar
      if (db.itemCacheUpdated or 0) >= timestamp then
        return
      end
      local t = ns.mapping.SafeDeserializeCBOR(cborStr)
      if not t then return end
      ---@cast t wowutils_itemcache
      db.itemCache = t
      db.itemCacheUpdated = timestamp
      -- missing .lastUpdateReveived for a reason, itemCache is not important enough to set that, we get what we get and thats it
    end,
    [currentUsage.craftingOrders] = function(configVersion, dbVersion, str, db, partialGuid, channel, sender) -- Q
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      local timestamp, cborStr = readCborPayload(str)
      if not timestamp then return end
      ns.Debug.print("receiving crafting orders from '%s'", sender)
      local t = ns.mapping.SafeDeserializeCBOR(cborStr)
      if not (t and type(t.g) == "string" and type(t.d) == "table") then
        ns.Debug.print("crafting orders from '%s' dropped, payload didn't decode", sender)
        return
      end
      if not (ns.me.guildInfo and ns.me.guildInfo.dbSlug == t.g) then -- changed guilds mid flight
        ns.Debug.print("crafting orders from '%s' dropped, their guild '%s' ours '%s'", sender, t.g, tostring(ns.me.guildInfo and ns.me.guildInfo.dbSlug))
        return
      end
      if ns.randomThings.craftingOrders.MergeIncoming(t.g, t.d) then
        ns.communication.SendCraftingOrders() -- we had something they didn't
      end
    end,
    [currentUsage.lockouts] = function(configVersion, dbVersion, str, db, targetGuid, channel) -- R
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      if not db then
        db = confirmAndReturnDBForChar(targetGuid, channel)
        if not db then return end
      end
      ns.Debug.print("receiving lockouts for '%s'", targetGuid)
      local timestamp, value = str:match("^(%d+)%?(%d+)$")
      if not timestamp then return end
      timestamp = ns.mapping.timestamp.FromValue(timestamp)
      if (db.lockoutsUpdated or 0) >= timestamp then -- Current data is newer, discard
        if db.lockoutsUpdated == timestamp then
          ns.database.DataRefreshed(ns.enums.context.lockouts, db)
        end
        return
      end
      ns.database.DataRefreshed(ns.enums.context.lockouts, db)
      db.lockouts = tonumber(value)
      db.lockoutsUpdated = timestamp
      db.lastUpdateReceived = GetServerTime()
    end,
    [currentUsage.dungeonsDone] = function (configVersion, dbVersion, str, db, targetGuid, channel, sender) -- S
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      if not db then
        db = confirmAndReturnDBForChar(targetGuid, channel)
        if not db then return end
      end
      ns.Debug.print("receiving dungeonsDone for '%s'", targetGuid)
      local timestamp, dungeonStr = str:match("^(%d+)%?(.*)$")
      if not timestamp then return end
      timestamp = ns.mapping.timestamp.FromValue(timestamp)
      if (db.dungeonsUpdated or 0) >= timestamp then  -- Current data is newer, discard
        if db.dungeonsUpdated == timestamp then
          ns.database.DataRefreshed(ns.enums.context.dungeonsDone, db)
        end
        return
      end
      if db.dungeonsDone then
        wipe(db.dungeonsDone)
      else
        db.dungeonsDone = {}
      end
      local splits = { strsplit("^", dungeonStr) }
      for _, v in pairs(splits) do
        local _keyLevel, _done = v:match("^(%d%d)(%d+)$")
        _keyLevel = tonumber(_keyLevel)
        _done = tonumber(_done)
        if _keyLevel and _done then
          db.dungeonsDone[_keyLevel] = _done
        end
      end
      ns.database.DataRefreshed(ns.enums.context.dungeonsDone, db)
      db.dungeonsUpdated = timestamp
      db.lastUpdateReceived = GetServerTime()
    end
    --["T"] = nil,
    --["U"] = nil,
    --["V"] = nil,
    --["W"] = nil,
    --["X"] = nil,
    --["Y"] = nil,
    --["Z"] = nil,
    --["a"] = nil,
    --["b"] = nil,
    --["c"] = nil,
    --["d"] = nil,
    --["e"] = nil,
    --["f"] = nil,
    --["g"] = nil,
    --["h"] = nil,
    --["i"] = nil,
    --["j"] = nil,
    --["k"] = nil,
    --["l"] = nil,
    --["m"] = nil,
    --["n"] = nil,
    --["o"] = nil,
    --["p"] = nil,
    --["q"] = nil,
    --["r"] = nil,
    --["s"] = nil,
    --["t"] = nil,
    --["u"] = nil,
    --["v"] = nil,
    --["w"] = nil,
    --["x"] = nil,
    --["y"] = nil,
    --["z"] = nil,
    --["1"] = nil,
    --["2"] = nil,
    --["3"] = nil,
    --["4"] = nil,
    --["5"] = nil,
    --["6"] = nil,
    --["7"] = nil,
    --["8"] = nil,
    --["9"] = nil,
  },
}

-- per initial byte: the cbor major type, the inline value, and how many argument bytes follow
-- (-1 indefinite length, nil not valid cbor). a lookup beats a floor() call plus a division and a
-- modulo on every item, which is worth it since this runs once per item of every incoming payload.
local cborMajor, cborInline, cborArgBytes = {}, {}, {}
for ib = 0, 255 do
  local ai = ib % 32
  cborMajor[ib] = floor(ib / 32)
  cborInline[ib] = ai
  if ai < 24 then cborArgBytes[ib] = 0
  elseif ai == 24 then cborArgBytes[ib] = 1
  elseif ai == 25 then cborArgBytes[ib] = 2
  elseif ai == 26 then cborArgBytes[ib] = 4
  elseif ai == 27 then cborArgBytes[ib] = 8
  elseif ai == 31 then cborArgBytes[ib] = -1
  end -- 28..30 stay nil, they are not valid cbor
end

local MAX_CBOR_DEPTH = 32
-- reused across calls so validating a payload allocates nothing at all and adds no gc pressure.
-- safe to share: lua is single threaded here, the walk never yields, and every read of a slot is
-- of a value the same call wrote on its way down, so leftovers from a previous payload are dead.
local cborStack = {}
-- C_EncodingUtil.DeserializeCBOR sizes its allocations straight from the length/count header of each
-- item it reads, so a corrupted header doesn't error, it kills the client: one truncated payload
-- decoded into an array header claiming 1914713654 entries and wow tried to allocate 45.9GB and died
-- on OOM inside lmemPool.cpp. that happens in the C allocator below lua, where a pcall can't reach it.
-- so walk the payload first and confirm every length and count actually fits in the bytes we received,
-- that nesting stays sane, and that the whole string is exactly one item with nothing trailing.
--
-- a length or checksum on the wire is NOT a substitute. it can't be: it only covers senders running a
-- version that sends one, and corruption keeps the length intact often enough to matter (a garbled
-- byte inflates to a same-length payload about two thirds of the time, and ~1 in 6 of the payloads
-- that would crash us survive a length check). it also does nothing about someone deliberately
-- sending a crafted header on our prefix to drop the whole guild. this walk covers all of that.
-- cost is 0.02ms for a payload the size of the one that crashed and 1.3ms for a 138kb one, against
-- ~1.1ms just for the tables the deserializer has to allocate for that same payload regardless.
---@param s string
---@return boolean
local function isWellFormedCBOR(s)
  local len = #s
  local pos = 1
  local stack, depth = cborStack, 0 -- enclosing levels' counts; the current level's stays in a local
  local expected = 1                -- items still expected at this level, -1 while inside an indefinite length item
  while true do
    if expected == 0 then
      if depth == 0 then break end                -- the one top level item is complete
      expected = stack[depth]
      depth = depth - 1
    elseif pos > len then
      return false                                -- ran out of bytes mid item
    else
      local ib = sbyte(s, pos)
      pos = pos + 1
      if ib == 0xFF then                          -- break, only ever closes an indefinite length item
        if expected ~= -1 then return false end
        if depth == 0 then
          expected = 0
        else
          expected = stack[depth]
          depth = depth - 1
        end
      else
        if expected ~= -1 then expected = expected - 1 end
        local argBytes = cborArgBytes[ib]
        if not argBytes then return false end
        local major = cborMajor[ib]
        if argBytes == -1 then                    -- indefinite length, only strings, arrays and maps may use it
          if major < 2 or major > 5 then return false end
          depth = depth + 1
          if depth > MAX_CBOR_DEPTH then return false end
          stack[depth] = expected
          expected = -1
        elseif major >= 2 and major <= 5 then     -- byte string, text string, array or map: the argument is a size
          if argBytes == 8 then return false end  -- nothing arriving over a chat channel needs a 64 bit size
          if pos + argBytes - 1 > len then return false end
          local value = cborInline[ib]
          if argBytes == 1 then
            value = sbyte(s, pos)
          elseif argBytes == 2 then
            local a, b = sbyte(s, pos, pos + 1)
            value = a * 256 + b
          elseif argBytes == 4 then
            local a, b, c, d = sbyte(s, pos, pos + 3)
            value = ((a * 256 + b) * 256 + c) * 256 + d
          end
          pos = pos + argBytes
          local left = len - pos + 1
          if major > 3 then                       -- every array entry needs at least one more byte, every map entry at least two
            if value > (major == 4 and left or left / 2) then return false end
            if value > 0 then
              depth = depth + 1
              if depth > MAX_CBOR_DEPTH then return false end
              stack[depth] = expected
              expected = major == 4 and value or value * 2
            end
          else
            if value > left then return false end
            pos = pos + value
          end
        else
          if pos + argBytes - 1 > len then return false end
          pos = pos + argBytes                    -- integer, tag or simple value: no size to bound
          if major == 6 then                      -- a tag is followed by exactly one more item
            depth = depth + 1
            if depth > MAX_CBOR_DEPTH then return false end
            stack[depth] = expected
            expected = 1
          end
        end
      end
    end
  end
  return pos > len -- exactly one item, nothing trailing
end

-- incoming payloads can arrive corrupted (AceComm has no integrity check, so a dropped or interleaved
-- multipart chunk still gets reassembled and fired at us, and DecompressString happily returns garbage
-- for a broken deflate stream). never let that through, just drop the message.
---@param cborStr string?
---@return table?
function ns.mapping.SafeDeserializeCBOR(cborStr)
  if type(cborStr) ~= "string" or cborStr == "" then return end
  if not isWellFormedCBOR(cborStr) then
    ns.Debug.print("malformed cbor payload (#%s bytes), dropping message", #cborStr)
    return
  end
  local ok, t = pcall(DeserializeCBOR, cborStr)
  if not ok or type(t) ~= "table" then
    ns.Debug.print("corrupted cbor payload (#%s bytes), dropping message", #cborStr)
    return
  end
  return t
end

local numberConverts = {
  fromInt = {
    [0] = "0",
  },
  toInt = {
    ["0"] = 0,
  },
}
do
  local t = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z" }
  for k, v in ipairs(t) do
    numberConverts.fromInt[k] = v
    numberConverts.toInt[v] = k
  end
end
ns.mapping.int = {
  ---@param val string
  ---@return number
  FromValue = function(val)
    assert(numberConverts.toInt[val], "No matching value found for '" .. tostring(val) .. "'")
    return numberConverts.toInt[val]
  end,

  ---@param val number
  ---@return string
  ToValue = function(val)
    assert(numberConverts.fromInt[val], "No matching value found for '" .. tostring(val) .. "'")
    return numberConverts.fromInt[val]
  end
}

do
  local c = {
    to = {
      DEATHKNIGHT = "A",
      DEMONHUNTER = "B",
      DRUID = "C",
      EVOKER = "D",
      HUNTER = "E",
      MAGE = "F",
      MONK = "G",
      PALADIN = "H",
      PRIEST = "I",
      ROGUE = "J",
      SHAMAN = "K",
      WARLOCK = "L",
      WARRIOR = "M",
    },
    from = {
      A = "DEATHKNIGHT",
      B = "DEMONHUNTER",
      C = "DRUID",
      D = "EVOKER",
      E = "HUNTER",
      F = "MAGE",
      G = "MONK",
      H = "PALADIN",
      I = "PRIEST",
      J = "ROGUE",
      K = "SHAMAN",
      L = "WARLOCK",
      M = "WARRIOR",
    }
  }
  ns.mapping.class = {

    FromValue = function(val)
      return c.from[val]
    end,
    ToValue = function(val)
      return c.to[val]
    end,
  }
end
ns.mapping.timestamp = {
  ---convert to msg format
  ---@param timestamp number
  ---@return number
  ToValue = function(timestamp)
    return timestamp - ns.config.timestampOffset
  end,
  ---convert to real value
  ---@param value number|string
  ---@return number
  FromValue = function(value)
    return tonumber(value) + ns.config.timestampOffset
  end
}
do
  local mapTo = {
    -- nil = "0"
    [true] = "1",
    [false] = "2",
  }
  local mapFrom = {
    --["0"] = nil,
    ["1"] = true,
    ["2"] = false,
  }
  ns.mapping.boolean = {
    ---@param value boolean?
    ---@return string
    ConvertToTriState = function(value)
      if value == nil then return "0" end
      if type(value) ~= "boolean" then
        geterrorhandler()
        return "2"
      end                                                               -- should be the least meaningful fallback
      return mapTo[value]
    end,
    ---@param value string
    ---@return boolean?
    MapValueToTriState = function(value)
      return mapFrom[value]
    end,
    ---@param value boolean
    ---@return string
    ConvertBooleanToMappingValue = function(value)
      if value then return "1" else return "2" end
    end,

    ---@param value string
    ---@return boolean
    MapValueToBoolean = function(value)
      return value == "1"
    end,
  }
end
do
  local timestamps = {
    "currencyUpdated", "watermarksUpdated", "craftingItemsUpdated", "questsUpdated", "vaultDataLastUpdate", "weeklyRewardsUpdate",
    "lockoutsUpdated", -- config 6, J doesn't answer anything older so sums from before this never get compared
    "dungeonsUpdated", -- config 6
  }
  local sumOffset = #timestamps * ns.config.timestampOffset
  ---@param char wowutils_otherChar
  ---@return number summedTimestamps
  function ns.mapping.GetCharacterTimestampsForWideSync(char)
    local sum = 0
    for i = 1, #timestamps do
      sum = sum + (char[timestamps[i]] or 0)
    end
    return sum - sumOffset
  end
end

local addonVersion = C_AddOns.GetAddOnMetadata(addon_name, "Version")

---copies table provided and removes data that we dont wanna send with character sync
---@param data wowutils_ownChar|wowutils_otherChar
---@return wowutils_otherChar
local function cleanUpCharacterDBBeforeSending(data)
  local t = CopyTable(data)
  if data.lastLogout then -- own characters
    t.lastUpdateReceived = nil
    t.lastLogout = nil
  end
  t.itemCache = nil -- we don't want to send item cache through this, it will be sent through different (low prio) channel
  t.itemCacheUpdated = nil
  return t
end

---@param context wowutils_enums_context
---@param data any
---@param timestamp number?
---@param key string?
---@return string
function ns.mapping.GetMsgData(context, data, timestamp, key)
  if context == ns.enums.context.watermarks then
    ---@cast timestamp number
    local t = {}
    for slotId, discountItemLevel in pairs(data) do
      local dif = discountItemLevel - ns.config.watermarks.startingPoint
      if dif > 0 then
        tinsert(t, sformat("%s%s%s",
          ns.mapping.int.ToValue(slotId),
          ns.mapping.int.ToValue(floor(dif / ns.config.watermarks.multiplier)),
          ns.mapping.int.ToValue(dif % ns.config.watermarks.multiplier))
        )
      else
        tinsert(t, sformat("%s00", ns.mapping.int.ToValue(slotId)))
      end
    end
    return sformat("%s%s?%s", currentUsage.watermarks, ns.mapping.timestamp.ToValue(timestamp or 0), tconcat(t, "^"))
  end
  if context == ns.enums.context.currency then
    ---@cast timestamp number
    local t = {}
    for currencyId, currencyData in pairs(data) do
      ---@cast currencyData wowutils_currencyData
      if ns.config.currencies[currencyId] then -- should kinda be useless, but might as well keep it to filter out old currencies just in case
        tinsert(t, sformat("%s%s?%s", ns.config.currencies[currencyId], currencyData.current, currencyData.totalEarned))
      end
    end
    if #t > 0 then
      return sformat("%s%s?%s", currentUsage.currency, ns.mapping.timestamp.ToValue(timestamp or 0), tconcat(t, "^"))
    else
      return ""
    end
  end
  if context == ns.enums.context.craftingItems then
    return sformat("%s%s?%s", currentUsage.craftingItems, ns.mapping.timestamp.ToValue(timestamp), ns.mapping.int.ToValue(data or 0))
  end
  if context == ns.enums.context.characterInformation then
    ---@cast data wowutils_characterInformationForMapping
    return sformat("%s%s", currentUsage.characterInformation, tconcat({
      (data.guid:gsub("Player%-", "", 1)),
      data.name,
      ns.mapping.class.ToValue(data.class),
      ns.mapping.timestamp.ToValue(data.lastUpdate),
      ns.mapping.timestamp.ToValue(data.lastUpdateReceived),
      data.region
    }, "^"))
  end
  if context == ns.enums.context.droptimizerData then
    -- TODO optimize tranmission data
    ---@cast data wowutilsDroptimizerData
    local lastUpdate = tostring(data.lastUpdate or 0)
    return sformat("%s%s%s%s", currentUsage.droptimizerData, string.char(#lastUpdate), lastUpdate, SerializeCBOR(data))
  end
  if context == ns.enums.context.fullCharacterSync then
    -- TODO optimize tranmission data
    -- make a copy of the data so we can modify it before sending
    ---@cast data wowutils_ownChar
    local t = cleanUpCharacterDBBeforeSending(data)
    ns.Debug.print("trying to send fullsync: last update '%s'", t.lastUpdate or "nil")
    local lastUpdate = tostring(t.lastUpdate or 0)
    return sformat("%s%s%s%s", currentUsage.fullCharacterSync, string.char(#lastUpdate), lastUpdate, SerializeCBOR(t))
  end
  if context == ns.enums.context.fullCharacterSyncFromDB then
    ---@cast data wowutils_ownChar|wowutils_otherChar
    local t = cleanUpCharacterDBBeforeSending(data)
    local summedTimestamps = tostring(ns.mapping.GetCharacterTimestampsForWideSync(t))
    return sformat("%s%s%s%s", currentUsage.fullCharacterSyncFromDB, string.char(#summedTimestamps), summedTimestamps, SerializeCBOR(t))
  end
  if context == ns.enums.context.updateCheck then
    ---@cast data wowutils_ownChar
    local serverTime = GetServerTime()
    local t = {
      ns.mapping.timestamp.ToValue(serverTime),                                                                                                       -- 1
      math.abs(serverTime - (data.currencyUpdated or 0)),                                                                                             -- 2
      math.abs(serverTime - (data.questsUpdated or 0)),                                                                                               -- 3
      math.abs(serverTime - (data.watermarksUpdated or 0)),                                                                                           -- 4
      math.abs(serverTime - (data.craftingItemsUpdated or 0)),                                                                                        -- 5
      math.abs(serverTime - (data.vaultDataLastUpdate or 0)),                                                                                         -- 6
      math.abs(serverTime - (data.weeklyRewardsUpdate or 0)),                                                                                         -- 7
      math.abs(serverTime - (WowUtilsDB.droptimizerData[ns.me.droptimizerKey] and WowUtilsDB.droptimizerData[ns.me.droptimizerKey].lastUpdate or 0)), -- 8
      ns.me.droptimizerKey,                                                                                                                           -- 9
      math.abs(serverTime - (data.dungeonsUpdated or 0)),                                                                                             -- 10
    }
    return tconcat(t, "^")
  end
  if context == ns.enums.context.vaultData then
    ---@cast data wowutils_vaultData_items
    local lastUpdate = tostring(timestamp or 0)
    return sformat("%s%s%s%s", currentUsage.vaultData, string.char(#lastUpdate), lastUpdate, SerializeCBOR(data))
  end
  if context == ns.enums.context.weeklyRewards then
    ---@cast data table<string, number>
    local lastUpdate = tostring(timestamp or 0)
    return sformat("%s%s%s%s", currentUsage.weeklyRewards, string.char(#lastUpdate), lastUpdate, SerializeCBOR(data))
  end
  if context == ns.enums.context.quests then
    ---@cast data table<number, wowutils_quests>
    local t = {}
    for questId, questData in pairs(data) do
      tinsert(t, sformat("%s%s%s", ns.mapping.boolean.ConvertBooleanToMappingValue(questData.completed), ns.mapping.boolean.ConvertBooleanToMappingValue(questData.completedWarbound), questId))
    end
    return sformat("%s%s?%s", currentUsage.quests, ns.mapping.timestamp.ToValue(timestamp or 0), tconcat(t, "^"))
  end
  if context == ns.enums.context.whitelistCharSyncRequest then
    ---@cast data table
    local temp = {}
    for _, v in pairs(data) do
      tinsert(temp, sformat("%s?%s?%s", v.id, v.timestamp or 0, v.itemTimestamp or 0))
    end
    if #temp == 0 then return "" end
    return sformat("%s%s?%s", currentUsage.whitelistCharSyncRequest, key, tconcat(temp, "^"))
  end
  if context == ns.enums.context.fullSynclistInformation then
    ---@cast data wowutilsSyncList
    return sformat("%s%s%s%s^%s", currentUsage.fullSynclist, string.char(#tostring(data.lastUpdate or 0)), (data.lastUpdate or 0), key, SerializeCBOR(data))
  end
  if context == ns.enums.context.generalUpdatedCheck then
    local temp = {}
    for listId, listData in pairs(WowUtilsDB.syncLists) do
      tinsert(temp, sformat("A%s?%s", listId, ns.mapping.timestamp.ToValue(listData.lastUpdate or 0)))
    end
    local guildCache = ns.randomThings.craftingOrders.GetGuildCache(true)
    if guildCache then -- sent even when empty, so others know we can read crafting orders and send us theirs
      local professionPairs = {}
      for professionId, professionData in pairs(guildCache) do
        tinsert(professionPairs, sformat("%d:%d", professionId, ns.mapping.timestamp.ToValue(professionData.lastUpdate)))
      end
      tinsert(temp, "C" .. tconcat(professionPairs, ","))
    end
    tinsert(temp, sformat("B%s", addonVersion))
    return sformat("%s%s", currentUsage.generalUpdateCheck, tconcat(temp, "^"))
  end
  if context == ns.enums.context.syncListRequest then
    return sformat("%s%s?%s", currentUsage.syncListRequest, data, timestamp)
  end
  if context == ns.enums.context.bonusCoin then
    local lastUpdate = tostring(timestamp or 0)
    return sformat("%s%s%s%s", currentUsage.bonusCoinUsage, string.char(#lastUpdate), lastUpdate, SerializeCBOR(data))
  end
  if context == ns.enums.context.itemCache then
    ---@cast data wowutils_ownChar|wowutils_otherChar
    local lastUpdate = tostring(data.itemCacheUpdated or 0)
    return sformat("%s%s%s%s", currentUsage.itemCache, string.char(#lastUpdate), lastUpdate, SerializeCBOR(data.itemCache))
  end
  if context == ns.enums.context.craftingOrders then
    ---@cast data table<number, wowutils_craftingOrderProfession>
    ---@cast key string guild dbSlug
    local newest = 0
    for _, professionData in pairs(data) do
      newest = math.max(newest, professionData.lastUpdate)
    end
    local lastUpdate = tostring(newest)
    return sformat("%s%s%s%s", currentUsage.craftingOrders, string.char(#lastUpdate), lastUpdate, SerializeCBOR({ g = key, d = data }))
  end
  if context == ns.enums.context.lockouts then
    ---@cast data number
    -- %.0f rather than tostring, tostring only keeps 14 significant digits and the mask can go up to 2^53
    return sformat("%s%s?%.0f", currentUsage.lockouts, ns.mapping.timestamp.ToValue(timestamp or 0), data)
  end
  if context == ns.enums.context.dungeonsDone then
    ---@cast data table<number, number>
    local temp = {}
    for k,v in pairs(data) do
      tinsert(temp, sformat("%02d%d", k, v))
    end
    return sformat("%s%s?%s", currentUsage.dungeonsDone, ns.mapping.timestamp.ToValue(timestamp or 0), tconcat(temp, "^"))
  end
  geterrorhandler()("Unknown context: " .. tostring(context))
  return ""
end

function ns.mapping.ConvertGuidToMsgFormat(guid)
  return (guid:gsub("Player%-", "", 1))
end

function ns.mapping.ConvertPartialGuidToGuid(partialGuid)
  return "Player-" .. partialGuid
end