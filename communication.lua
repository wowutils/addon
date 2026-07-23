---@class wowutilsPrivate
---@field communication wowutils_communication

---@type string, wowutilsPrivate
local addon_name, ns = ...
local tinsert, tconcat, sformat, CompressString, DecompressString, SerializeCBOR, DeserializeCBOR, EncodeBase64, DecodeBase64 = table.insert, table.concat, string.format, C_EncodingUtil.CompressString, C_EncodingUtil.DecompressString, C_EncodingUtil.SerializeCBOR, C_EncodingUtil.DeserializeCBOR, C_EncodingUtil.EncodeBase64, C_EncodingUtil.DecodeBase64

local prefixes = {
  normal = "wowutilsS",
  updateChecker = "wowutilsDU",
}
local aceComms = LibStub("AceComm-3.0")
local selfPartialGuids = {
  source = "S" .. ns.me.partialGuid,
  target = "T" .. ns.me.partialGuid,
}
local private = {}

---@class wowutils_communication
---@field msgHandlers table<string, fun(...)>
---@field SendInfoForLoot fun()
---@field SendCurrencyUpdate fun()
---@field SendFullSync fun()
---@field AddonMessageRestrictionsLifted fun()
ns.communication = {
  msgHandlers = {}
}
local charDB = ns.database.GetCurrentCharDB()
local allCharsDB = ns.database.GetAllCharsDB()

ns.communication.msgHandlers[prefixes.normal] = function(prefix, msg, channel, sender)
  if UnitIsUnit("player", sender) then return end
  local uncompressedData, compressedData = strsplit("@", msg, 2)
  local msgType, dbVersion, configVersion, isCbor, idType, id = uncompressedData:match("^(.)(...)(...)(.)(.)(.-)$")
  dbVersion = tonumber(dbVersion)
  configVersion = tonumber(configVersion)
  if not (dbVersion and configVersion and idType and id) then
    geterrorhandler()("Invalid message format: " .. msg)
    return
  end
  dbVersion = tonumber(dbVersion)
  configVersion = tonumber(configVersion)
  if not (dbVersion and configVersion) then -- recheck after tonumber call
    geterrorhandler()("Invalid message format: " .. msg)
    return
  end
  if msgType == ns.enums.addonMessagesTypes.fullCharacterSyncRequest then
    ns.Debug.AddToDevTool({
      msgType = msgType,
      dbVesion = dbVersion,
      configVersion = configVersion,
      idType = idType,
      id = id,
      myPartialGuid = ns.me.partialGuid,
      uncompressedData = uncompressedData,
    }, "syncRequest")
    if id ~= ns.me.partialGuid then
      ns.Debug.print("not for me")
      return
    end
    if dbVersion < ns.config.currentDBVersion then
      ns.Debug.print("dbversion is too old")
      return
    end                                                                                              -- no point in sending newer data to older addon
    ns.communication.SendFullSyncFromCurrentCharacter(channel)
    return
  end
  if isCbor == "1" then                                               -- we dont wanna do any extra splitting for these strings, instead let specficic handler handle them
    if msgType == ns.enums.addonMessagesTypes.droptimizerData then
      if idType == "T" and id ~= ns.me.droptimizerKey then return end -- targeted droptimizerData sync, but not for me, could probably just catch these in the future?
    end
    local dataString = private.prepString(compressedData, false)
    local dataType = dataString:sub(1, 1)
    if ns.mapping.toRealData[dataType] then
      ns.mapping.toRealData[dataType](configVersion, dbVersion, dataString:sub(2), nil, id, channel)
    else
      geterrorhandler()("No handler found for data type: " .. dataType)
    end
    return
  end
  --[[
  if msgType == ns.enums.addonMessagesTypes.droptimizerData then -- uses keys, and cbors
    --if idType == "S" and id == ns.me.droptimizerKey then return end -- filter these out before they even reach here
    --if idType == "T" and id ~= ns.me.droptimizerKey then return end -- not for me, ignore
    local dataString = private.prepString(compressedData, false)
    ns.mapping.toRealData.E(configVersion, dbVersion, dataString:sub(2), nil, id, channel)
    return
  elseif msgType == ns.enums.addonMessagesTypes.fullCharacterSync then -- uses cbor
    local dataString = private.prepString(compressedData, false)
    local fullGuid = ns.mapping.ConvertPartialGuidToGuid(id)
    ns.mapping.toRealData.F(configVersion, dbVersion, dataString:sub(2), nil, fullGuid, channel)
    return
  else
  --]]
  --if idType == "S" and id == ns.me.partialGuid then return end -- filter these out before they even reach here
  if idType == "T" and id ~= ns.me.partialGuid then return end
  --end
  local fullGuid = ns.mapping.ConvertPartialGuidToGuid(id)
  local dataString = private.prepString(compressedData, false)
  for _, dataStr in pairs({ strsplit("@", dataString) }) do
    local dataType = dataStr:sub(1, 1)
    if ns.mapping.toRealData[dataType] then
      ns.mapping.toRealData[dataType](configVersion, dbVersion, dataStr:sub(2), nil, fullGuid, channel)
    else
      geterrorhandler()("No handler found for data type: " .. dataType)
    end
  end
end
if ns.hasDataAddon then
  local mapToTimestampVars = {
    [2] = "currencyUpdated",
    [3] = "questsUpdated",
    [4] = "watermarksUpdated",
    [5] = "craftingItemsUpdated",
    [6] = "vaultDataLastUpdate",
    [7] = "weeklyRewardsUpdate",
  }
  ns.communication.msgHandlers[prefixes.updateChecker] = function(prefix, msg, channel, sender)
    if UnitIsUnit("player", sender) then return end
    local msgType, dbVersion, configVersion, isCbor, guidType, partialGuid, dataStr = msg:match("^(.)(...)(...)(.)(.)(.-)@(.*)$")
    ns.Debug.print("update check from: '%s'", partialGuid)
    dbVersion = tonumber(dbVersion)
    configVersion = tonumber(configVersion)
    if not (dbVersion and configVersion and guidType and partialGuid) then
      geterrorhandler()("Invalid message format: " .. msg)
      return
    end
    if dbVersion > ns.config.currentDBVersion or configVersion > ns.config.configVersion then return end -- our version is older, just ignore
    local data = { strsplit("^", dataStr) }
    local fixedPoint = ns.mapping.timestamp.FromValue(data[1])
    for i = 2, 8 do
      data[i] = fixedPoint - (tonumber(data[i]) or 0)
    end
    if data[9] and WowUtilsDB.droptimizerData[data[9]] then -- droptimizerKey
      if WowUtilsDB.droptimizerData[data[9]].lastUpdate > data[8] then
        ns.communication.SendDroptimizerData(data[9])
      end
    end
    local targetGuid = ns.mapping.ConvertPartialGuidToGuid(partialGuid)
    if not WowUtilsDB.others[targetGuid] then
      ns.communication.RequestFullSync(partialGuid, channel)
      return
    end
    -- check if any of the data types is older, if its just request full sync since there is some data that we are missing, highly likely that we are missing more than just a single data point
    for k, v in pairs(mapToTimestampVars) do
      if (not data[k]) or data[k] > (WowUtilsDB.others[targetGuid][v] or 0) then
        ns.communication.RequestFullSync(partialGuid, channel)
        return
      end
    end
  end
end
private.queue = {}
private.groupChannels = {
  [ns.enums.chatChannels.instance] = true,
  [ns.enums.chatChannels.party] = true,
  [ns.enums.chatChannels.raid] = true,
}
function private.confimChannel(prefChannel)
  if prefChannel == ns.enums.chatChannels.guild then
    return IsInGuild() and prefChannel or nil
  end
  if private.groupChannels[prefChannel] then
    if not IsInGroup() then return nil end
    return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "instance_chat" or IsInRaid() and "raid" or "party"
  end
  geterrorhandler()("No channel found for" .. prefChannel)
end

function private.updateCheck()
  if not IsInGuild() then return end
  ---@diagnostic disable-next-line: param-type-mismatch
  private.sendAddonMessage(ns.enums.addonMessagesTypes.updateCheckForDesktopAppUsers, ns.mapping.GetMsgData(ns.enums.context.updateCheck, charDB), ns.enums.chatChannels.guild, "NORMAL", nil, false)
end

C_Timer.NewTicker(60, private.updateCheck)
C_Timer.After(15, private.updateCheck)

---@param addonMessagesType string
---@return string?
function private.getCorrectPrefixForType(addonMessagesType)
  if addonMessagesType == ns.enums.addonMessagesTypes.updateCheckForDesktopAppUsers then
    return prefixes.updateChecker
  end
  return prefixes.normal
end

local versionStrings = {
  db = sformat("%03d", ns.config.currentDBVersion),
  config = sformat("%03d", ns.config.configVersion),
}
versionStrings.full = versionStrings.db .. versionStrings.config

---@param msgType wowutils_enums_addonMessageTypes
---@param str string
---@param target string?
---@param isCbor boolean
---@return string
function private.addVersionsToCompressedString(msgType, str, target, isCbor)
  return sformat("%s%s%s%s@%s", msgType, versionStrings.full, isCbor and 1 or 0, target or selfPartialGuids.source, str)
end

---@param str string
---@param sending boolean
---@return string
function private.prepString(str, sending)
  if sending then
    local compressed = CompressString(str, Enum.CompressionMethod.Deflate, Enum.CompressionLevel.OptimizeForSize)
    local encoded = EncodeBase64(compressed)
    ns.Debug.print("Results: Uncompressed #%s - Compressed #%s - Encoded #%s", str:len(), compressed:len(), encoded:len())
    return encoded
  end
  local compressed = DecodeBase64(str)
  local decompressed = DecompressString(compressed, Enum.CompressionMethod.Deflate)
  ns.Debug.print("Results (D): Encoded #%s - Compressed #%s - Uncompressed #%s", str:len(), compressed:len(), decompressed:len())
  return decompressed
end

---@param addonMessagesType wowutils_enums_addonMessageTypes
---@param uncompressedMsg string
---@param prefChannel "instance_chat"|"raid"|"party"|"guild"
---@param prio "BULK"|"NORMAL"|"ALERT"
---@param target string? if nil, assume source guid instead
---@param isCbor boolean
function private.sendAddonMessage(addonMessagesType, uncompressedMsg, prefChannel, prio, target, isCbor)
  assert(type(addonMessagesType) ~= "nil", "not nill")
  if ns.restrictedAddonMessages then
    for _, v in pairs(private.queue) do
      if v.addonMessageType == addonMessagesType and v.prefChannel == prefChannel and v.uncompressedMsg == uncompressedMsg then return end
      if addonMessagesType == ns.enums.addonMessagesTypes.updateCheckForDesktopAppUsers and v.addonMessageType == addonMessagesType and prefChannel == v.prefChannel then -- updateChecker, just replace the string with new data
        v.uncompressedMsg = uncompressedMsg
        return
      end
    end
    tinsert(private.queue, {
      addonMessageType = addonMessagesType,
      uncompressedMsg = uncompressedMsg,
      prefChannel = prefChannel,
      prio = prio,
      target = target,
      isCbor = isCbor
    })
    return
  end
  local prefix = private.getCorrectPrefixForType(addonMessagesType)
  if not prefix then return end
  if prefix == prefixes.updateChecker then
    aceComms:SendCommMessage(prefix, private.addVersionsToCompressedString(addonMessagesType, uncompressedMsg, target, isCbor), prefChannel, nil, prio)
    return
  end
  aceComms:SendCommMessage(prefix, private.addVersionsToCompressedString(addonMessagesType, private.prepString(uncompressedMsg, true), target, isCbor), prefChannel, nil, prio)
end

function ns.communication.AddonMessageRestrictionsLifted()
  -- TODO actually check if all of the messages go through
  for _, data in pairs(private.queue) do
    local prefix = private.getCorrectPrefixForType(data.addonMessageType)
    local channel = private.confimChannel(data.prefChannel)
    if prefix and channel then
      if prefix == prefixes.updateChecker then
        aceComms:SendCommMessage(prefix, private.addVersionsToCompressedString(data.addonMessageType, data.uncompressedMsg, data.target, data.isCbor), channel, nil, data.prio)
      else
        aceComms:SendCommMessage(prefix, private.addVersionsToCompressedString(data.addonMessageType, private.prepString(data.uncompressedMsg, true), data.target, data.isCbor), channel, nil, data.prio)
      end
    end
  end
  wipe(private.queue)
end

do
  local lastSentTime = 0
  function ns.communication.SendInfoForLoot()
    if GetTime() - lastSentTime < 5 then return end
    if not IsInGroup() then return end
    ns.Debug.print("sending info for loot")
    local currentGroupType = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "instance_chat" or IsInRaid() and "raid" or "party"
    --if currentGroupType == "party" then return end -- ignore party at least for now

    local t = {}
    tinsert(t, ns.mapping.GetMsgData(ns.enums.context.currency, charDB.currency, charDB.currencyUpdated))
    tinsert(t, ns.mapping.GetMsgData(ns.enums.context.craftingItems, charDB.craftingItems, charDB.craftingItemsUpdated))
    tinsert(t, ns.mapping.GetMsgData(ns.enums.context.watermarks, charDB.watermarks, charDB.watermarksUpdated))
    local str = tconcat(t, "@")
    private.sendAddonMessage(ns.enums.addonMessagesTypes.forLoot, str, currentGroupType, "NORMAL", nil, false)
    -- don't combine messages
    ns.communication.SendDroptimizerData()
    lastSentTime = GetTime()
  end
end
do
  local lastSentTime = 0
  function ns.communication.SendCurrencyUpdate()
    if GetTime() - lastSentTime < .5 then return end
    ns.Debug.print("sending currency update")
    local dataStr = ns.mapping.GetMsgData(ns.enums.context.currency, charDB.currency, charDB.currencyUpdated)
    if not dataStr then
      geterrorhandler()("dataStr is nil")
    end
    private.sendAddonMessage(ns.enums.addonMessagesTypes.partialCharacterUpdate, dataStr, ns.enums.chatChannels.guild, "NORMAL", nil, false)
    lastSentTime = GetTime()
  end
end
do
  local lastSentTime = 0
  function ns.communication.SendWatermarkUpdate()
    if GetTime() - lastSentTime < 1 then return end
    ns.Debug.print("sending watermarks")
    private.sendAddonMessage(ns.enums.addonMessagesTypes.partialCharacterUpdate, ns.mapping.GetMsgData(ns.enums.context.watermarks, charDB.watermarks, charDB.watermarksUpdated), ns.enums.chatChannels.guild, "NORMAL", nil, false)
    lastSentTime = GetTime()
  end
end
do
  local lastSentTime = 0
  function ns.communication.SendCraftingItemUpdate()
    if GetTime() - lastSentTime < 1 then return end
    ns.Debug.print("sending craft item update")
    private.sendAddonMessage(ns.enums.addonMessagesTypes.partialCharacterUpdate, ns.mapping.GetMsgData(ns.enums.context.craftingItems, charDB.craftingItems, charDB.craftingItemsUpdated), ns.enums.chatChannels.guild, "NORMAL", nil, false)
    lastSentTime = GetTime()
  end
end
do
  local lastSentTime = 0
  ---@param targetChannel string
  function ns.communication.SendFullSyncFromCurrentCharacter(targetChannel)
    if GetTime() - lastSentTime < 5 then return end
    ns.Debug.print("sending current full char")
    private.sendAddonMessage(ns.enums.addonMessagesTypes.fullCharacterSync, ns.mapping.GetMsgData(ns.enums.context.fullCharacterSync, charDB), targetChannel, "NORMAL", nil, true)
    lastSentTime = GetTime()
  end
end
do
  local cache = {}
  ---@param partialGuid string
  ---@param targetChannel string
  function ns.communication.RequestFullSync(partialGuid, targetChannel)
    if GetTime() - (cache[partialGuid] or 0) < 5 then return end
    ns.Debug.print("requesting full sync for '%s'", partialGuid)
    private.sendAddonMessage(ns.enums.addonMessagesTypes.fullCharacterSyncRequest, "F", targetChannel, "NORMAL", "T" .. partialGuid, false)
    cache[partialGuid] = GetTime()
  end
end
do
  local lastSentTime = 0
  function ns.communication.SendVaultDataUpdate()
    if GetTime() - lastSentTime < 1 then return end
    private.sendAddonMessage(ns.enums.addonMessagesTypes.partialCharacterUpdate, ns.mapping.GetMsgData(ns.enums.context.vaultData, charDB.vaultData, charDB.vaultDataLastUpdate or 0), ns.enums.chatChannels.guild, "NORMAL", nil, true)
    lastSentTime = GetTime()
  end
end
do
  local lastSentTime = 0
  function ns.communication.SendWeeklyRewardsUpdate()
    if GetTime() - lastSentTime < 1 then return end
    private.sendAddonMessage(ns.enums.addonMessagesTypes.partialCharacterUpdate, ns.mapping.GetMsgData(ns.enums.context.weeklyRewards, charDB.weeklyRewards, charDB.weeklyRewardsUpdate or 0), ns.enums.chatChannels.guild, "NORMAL", nil, true)
    lastSentTime = GetTime()
  end
end
do
  local lastSentTime = 0
  function ns.communication.SendQuestUpdate()
    function ns.communication.SendWeeklyRewardsUpdate()
      if GetTime() - lastSentTime < 1 then return end
      private.sendAddonMessage(ns.enums.addonMessagesTypes.partialCharacterUpdate, ns.mapping.GetMsgData(ns.enums.context.quests, charDB.quests, charDB.questsUpdated or 0), ns.enums.chatChannels.guild, "NORMAL", nil, false)
      lastSentTime = GetTime()
    end
  end
end
do
  local cache = {}
  function ns.communication.SendDroptimizerData(key)
    if not key then
      key = "own"
    end
    if GetTime() - (cache[key] or 0) < 5 then return end
    ns.Debug.print("sending droptimizerdata")
    ns.Debug.AddToDevTool(ns.me, "wowutils-ns.me")
    local t
    if key == "own" then
      t = WowUtilsDB.droptimizerData[ns.me.droptimizerKey]
    else
      t = WowUtilsDB.droptimizerData[key]
    end
    if not t then return end
    local dataStr = ns.mapping.GetMsgData(ns.enums.context.droptimizerData, t)
    if not dataStr then return end
    local target = sformat("%s%s", key == "own" and "S" or "T", key == "own" and ns.me.droptimizerKey or key)
    local channel = ns.enums.chatChannels.guild
    if key == "own" then
      channel = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "instance_chat" or IsInRaid() and "raid" or "party"
    end
    private.sendAddonMessage(ns.enums.addonMessagesTypes.droptimizerData, dataStr, channel, "NORMAL", target, true)
    cache[key] = GetTime()
  end
end
function ns.communication.SendFullDBSync()
  if true then return end
  local allChars = {}
  for k, v in pairs(allCharsDB) do
    if v.region == ns.region then
      local char = {}
      ---@type wowutils_characterInformationForMapping
      local _mappingInfoForChar = {
        class = v.class,
        guid = v.guid,
        lastUpdate = v.lastUpdate,
        lastUpdateReceived = v.lastUpdateReceived,
        name = v.name,
        region = v.region,
      }
      tinsert(char, ns.mapping.GetMsgData(ns.enums.context.characterInformation, _mappingInfoForChar))
      tinsert(char, ns.mapping.GetMsgData(ns.enums.context.currency, v.currency, v.currencyUpdated))
      tinsert(char, ns.mapping.GetMsgData(ns.enums.context.craftingItems, v.craftingItems, v.craftingItemsUpdated))
      tinsert(char, ns.mapping.GetMsgData(ns.enums.context.watermarks, v.watermarks, v.watermarksUpdated))
      tinsert(allChars, tconcat(char, ";"))
    end
  end
  local str = tconcat(allChars, "@")
  local compressed = CompressString(str, Enum.CompressionMethod.Deflate, Enum.CompressionLevel.OptimizeForSize)
  ns.Debug.print("Compressed length: %s - FullStr: %s", compressed:len(), str:len())
end

function ns.communication.guildStatusUpdate()

end

for k, v in pairs(prefixes) do
  if k == "updateChecker" then
    if ns.hasDataAddon then
      aceComms:RegisterComm(v, ns.communication.msgHandlers[v])
    end
  else
    aceComms:RegisterComm(v, ns.communication.msgHandlers[v])
  end
end
