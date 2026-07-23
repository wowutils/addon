---@class wowutilsPrivate
---@field mapping wowutils_mapping

---@type string, wowutilsPrivate
local addon_name, ns = ...
local tconcat, sformat, tinsert, floor, strsplit, SerializeCBOR, DeserializeCBOR, EncodeBase64, DecodeBase64 = table.concat, string.format, table.insert, math.floor, strsplit, C_EncodingUtil.SerializeCBOR, C_EncodingUtil.DeserializeCBOR, C_EncodingUtil.EncodeBase64, C_EncodingUtil.DecodeBase64
local _cache = {}

---@alias wowutils_mapping_toRealDataFunc fun(configVersion:number, dbVersion:number, str:string, db:wowutils_otherChar?, key:string?, channel:string):...?

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
  --["J"] = nil,
  --["K"] = nil,
  --["L"] = nil,
  --["M"] = nil,
  --["N"] = nil,
  --["O"] = nil,
  --["P"] = nil,
  --["Q"] = nil,
  --["R"] = nil,
  --["S"] = nil,
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

---@class wowutils_mapping
---@field toRealData table<string, wowutils_mapping_toRealDataFunc>
---@field ConvertGuidToMsgFormat fun(guid:string):string
---@field ConvertPartialGuidToGuid fun(partialGuid:string):string
ns.mapping = {
  toRealData = {
    [currentUsage.watermarks] = function(configVersion, dbVersion, str, db, targetGuid, channel) -- A
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      if not db then
        db = confirmAndReturnDBForChar(targetGuid, channel)
        if not db then return end
      end
      ns.Debug.print("receiving watermaks for '%s'", targetGuid)
      local timestamp, watermarkStr = str:match("^(%d+)%?(.*)$")
      timestamp = ns.mapping.timestamp.FromValue(timestamp)
      if db and db.watermarksUpdated then
        if db.watermarksUpdated >= timestamp then ns.Debug.print("already has newer data") return end -- Current data is newer, discard
      end
      local splits = {strsplit("^", watermarkStr)}
      local converted = {}
      for _,v in pairs(splits) do
        local _slot, _mult, _rem = v:match("^(.)(.)(.)$") -- TODO switch to :subs? (benchmark)
        local offset = ns.mapping.int.FromValue(_mult)*ns.config.watermarks.multiplier + ns.mapping.int.FromValue(_rem)
        converted[ns.mapping.int.FromValue(_slot)] = offset > 0 and (offset + ns.config.watermarks.startingPoint) or 0
      end
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
      ns.Debug.print("receiving watermarks for '%s'", targetGuid)
      local timestamp, currencyStr = str:match("^(%d+)%?(.*)$")
      timestamp = ns.mapping.timestamp.FromValue(timestamp)
      if db.currencyUpdated >= timestamp then return end -- Current data is newer, discard
      local splits = {strsplit("^", currencyStr)}
      for _, v in pairs(splits) do
        local _currencyMapId, _current, _total = v:match("^(.)(%d+)%?(%d+)$")
        _currencyMapId = tonumber(_currencyMapId)
        _current = tonumber(_current)
        _total = tonumber(_total)
        if _currencyMapId and _current and _total then
          local currencyId = _cache[configVersion][_currencyMapId]
          if not currencyId then
            for cId,mapId in pairs(ns.config.currencies) do
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
      if db.craftingItemsUpdated >= timestamp then return end -- Current data is newer, discard
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
      local timestampLength = str:byte(1)
      local timestamp = str:sub(2, 1 + timestampLength)
      local cborStr = str:sub(2 + timestampLength)
      ---@diagnostic disable-next-line: cast-local-type
      timestamp = tonumber(timestamp)
      if not timestamp then return end
      ns.Debug.print("receiving droptimizer data for '%s'", key)
      if WowUtilsDB.droptimizerData[key] and WowUtilsDB.droptimizerData[key].lastUpdate >= timestamp then return end -- already have newer data
      WowUtilsDB.droptimizerData[key] = DeserializeCBOR(cborStr)
    end,
    [currentUsage.fullCharacterSync] = function(configVersion, dbVersion, str, db, partialGuid, channel) -- F
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      local timestampLength = str:byte(1)
      local timestamp = str:sub(2, 1 + timestampLength)
      local cborStr = str:sub(2 + timestampLength)
      ---@diagnostic disable-next-line: cast-local-type
      timestamp = tonumber(timestamp)
      if not timestamp then return end
      local targetGuid = ns.mapping.ConvertPartialGuidToGuid(partialGuid)
      ns.Debug.print("receiving full character sync for '%s'", targetGuid)
      if WowUtilsDB.others[targetGuid] and WowUtilsDB.others[targetGuid].lastUpdate >= timestamp then return end -- already have newer data
      -- might as well update since someone is sending it
      WowUtilsDB.others[targetGuid] = DeserializeCBOR(cborStr)
      WowUtilsDB.others[targetGuid].lastUpdateReceived = GetServerTime()
    end,
    [currentUsage.vaultData] = function(configVersion, dbVersion, str, db, partialGuid, channel) -- G
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      local targetGuid = ns.mapping.ConvertPartialGuidToGuid(partialGuid)
      if not db then
        db = confirmAndReturnDBForChar(targetGuid, channel)
        if not db then return end
      end
      local timestampLength = str:byte(1)
      local timestamp = str:sub(2, 1 + timestampLength)
      local cborStr = str:sub(2 + timestampLength)
      ---@diagnostic disable-next-line: cast-local-type
      timestamp = tonumber(timestamp)
      if not timestamp then return end
      ns.Debug.print("receiving vault data update for '%s'", targetGuid)
      if db and (db.vaultDataLastUpdate or 0) >= timestamp then return end -- already have newer data
      -- might as well update since someone is sending it
      db.vaultDataLastUpdate = timestamp
      db.vaultData = DeserializeCBOR(cborStr)
      db.lastUpdateReceived = GetServerTime()
    end,
    [currentUsage.weeklyRewards] = function(configVersion, dbVersion, str, db, partialGuid, channel) -- H
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      local targetGuid = ns.mapping.ConvertPartialGuidToGuid(partialGuid)
      if not db then
        db = confirmAndReturnDBForChar(targetGuid, channel)
        if not db then return end
      end
      local timestampLength = str:byte(1)
      local timestamp = str:sub(2, 1 + timestampLength)
      local cborStr = str:sub(2 + timestampLength)
      ---@diagnostic disable-next-line: cast-local-type
      timestamp = tonumber(timestamp)
      if not timestamp then return end
      ns.Debug.print("receiving weekly rewards data update for '%s'", targetGuid)
      if (db.weeklyRewardsUpdate or 0) >= timestamp then return end -- already have newer data
      -- might as well update since someone is sending it
      db.weeklyRewardsUpdate = timestamp
      db.weeklyRewards = DeserializeCBOR(cborStr)
      db.lastUpdateReceived = GetServerTime()
    end,
    [currentUsage.quests] = function(configVersion, dbVersion, str, db, partialGuid, channel) -- I
      if configVersion > ns.config.configVersion or dbVersion > ns.config.currentDBVersion then return end
      local targetGuid = ns.mapping.ConvertPartialGuidToGuid(partialGuid)
      if not db then
        db = confirmAndReturnDBForChar(targetGuid, channel)
        if not db then return end
      end
      local timestamp, questDataStr = str:match("^(%d+)%?(.*)$")
      timestamp = ns.mapping.timestamp.FromValue(timestamp)
      if not timestamp then return end
      if db.questsUpdated >= timestamp then return end -- we already have newer data, discard
      ns.Debug.print("receiving quest update for '%s'", targetGuid)

      for _, v in pairs({strsplit("^", questDataStr)}) do
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
      db.questsUpdated = timestamp
      db.lastUpdateReceived = GetServerTime()
    end,
    --["J"] = nil,
    --["K"] = nil,
    --["L"] = nil,
    --["M"] = nil,
    --["N"] = nil,
    --["O"] = nil,
    --["P"] = nil,
    --["Q"] = nil,
    --["R"] = nil,
    --["S"] = nil,
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
local numberConverts = {
  fromInt = {
    [0] = "0",
  },
  toInt = {
    ["0"] = 0,
  },
}
do
  local t = {"1","2","3","4","5","6","7","8","9","A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z","a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"}
  for k,v in ipairs(t) do
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
  ---@param timestamp number
  ---@return number
  ToValue = function(timestamp)
    return timestamp - ns.config.timestampOffset
  end,
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
      if type(value) ~= "boolean" then geterrorhandler() return "2" end -- should be the least meaningful fallback
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

---@param context wowutils_enums_context
---@param data any
---@param timestamp number?
---@param key string?
---@return string
function ns.mapping.GetMsgData(context, data, timestamp, key)
  if context == ns.enums.context.watermarks then
    ---@cast timestamp number
    local t = {}
    for slotId,discountItemLevel in pairs(data) do
      local dif = discountItemLevel - ns.config.watermarks.startingPoint
      if dif > 0 then
        tinsert(t, sformat("%s%s%s",
          ns.mapping.int.ToValue(slotId),
          ns.mapping.int.ToValue(floor(dif/ns.config.watermarks.multiplier)),
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
      return sformat("%s%s?%s", currentUsage.currency, ns.mapping.timestamp.ToValue(timestamp or 0) ,tconcat(t, "^"))
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
    local t = CopyTable(data)
    t.lastLogout = nil
    ---@cast t wowutils_otherChar
    t.lastUpdateReceived = nil
    ns.Debug.print("trying to send fullsync: last update '%s'", t.lastUpdate or "nil")
    local lastUpdate = tostring(t.lastUpdate or 0)
    return sformat("%s%s%s%s", currentUsage.fullCharacterSync, string.char(#lastUpdate), lastUpdate, SerializeCBOR(t))
  end
  if context == ns.enums.context.updateCheck then
    ---@cast data wowutils_ownChar
    local serverTime = GetServerTime()
    local t = {
      ns.mapping.timestamp.ToValue(serverTime), -- 1
      math.abs(serverTime-(data.currencyUpdated or 0)), -- 2
      math.abs(serverTime-(data.questsUpdated or 0)), -- 3
      math.abs(serverTime-(data.watermarksUpdated or 0)), -- 4
      math.abs(serverTime-(data.craftingItemsUpdated or 0)), -- 5
      math.abs(serverTime-(data.vaultDataLastUpdate or 0)), -- 6
      math.abs(serverTime-(data.weeklyRewardsUpdate or 0)), -- 7
      math.abs(serverTime-(WowUtilsDB.droptimizerData[ns.me.droptimizerKey] and WowUtilsDB.droptimizerData[ns.me.droptimizerKey].lastUpdate or 0)), -- 8
      ns.me.droptimizerKey,
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
  geterrorhandler()("Unknown context: " .. tostring(context))
  return ""
end
function ns.mapping.ConvertGuidToMsgFormat(guid)
  return (guid:gsub("Player%-", "", 1))
end
function ns.mapping.ConvertPartialGuidToGuid(partialGuid)
  return "Player-"..partialGuid
end
