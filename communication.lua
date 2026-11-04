---@class wowutilsPrivate
---@field communication wowutils_communication

---@type string, wowutilsPrivate
local addon_name, ns = ...
local tinsert, tconcat, sformat, CompressString, DecompressString, SerializeCBOR, DeserializeCBOR, EncodeBase64, DecodeBase64 = table.insert, table.concat, string.format, C_EncodingUtil.CompressString, C_EncodingUtil.DecompressString, C_EncodingUtil.SerializeCBOR, C_EncodingUtil.DeserializeCBOR, C_EncodingUtil.EncodeBase64, C_EncodingUtil.DecodeBase64

local prefixes = {
  normal = "wowutilsS",
  updateChecker = "wowutilsDU",
  lowPrio = "wowutilsLP",
}
local msgPrioForPrexies = {
  [prefixes.normal] = "NORMAL",
  [prefixes.updateChecker] = "NORMAL",
  [prefixes.lowPrio] = "BULK",
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
---@field SendCraftingOrders fun()
ns.communication = {
  msgHandlers = {}
}
local charDB = ns.database.GetCurrentCharDB()
local allCharsDB = ns.database.GetAllCharsDB()
ns.communication.msgHandlers[prefixes.normal] = function(prefix, msg, channel, sender)
  if channel ~= "GUILD" then return end -- only accept messages from guild chat for now
  if UnitIsUnit("player", sender) then return end
  local uncompressedData, compressedData = strsplit("@", msg, 2)
  local msgType, dbVersion, configVersion, isCbor, idType, id = uncompressedData:match("^(.)(...)(...)(.)(.)(.-)$")
  -- idType S == source guid, T == targetGuid, A meant for all, data from db and not from the character itself
  dbVersion = tonumber(dbVersion)
  configVersion = tonumber(configVersion)
  if not (dbVersion and configVersion and idType and id) then
    -- debug only, otherwise anyone in the guild could pop errors for everyone with a broken message
    ns.Debug.print("Invalid message format from '%s': %s", sender, msg)
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
    -- no point in sending newer data to an older addon, it wont read it. configVersion counts as
    -- much as dbVersion now that 5 moved the wire format to zlib: a client on an older config drops
    -- our reply outright, so answering it only burns chat bandwidth.
    if dbVersion < ns.config.currentDBVersion or configVersion < ns.config.configVersion then
      ns.Debug.print("requester is on an older version (db '%s', config '%s'), not replying", dbVersion, configVersion)
      return
    end
    ns.communication.SendFullSyncFromCurrentCharacter(channel)
    return
  end
  if isCbor == "1" then                                               -- we dont wanna do any extra splitting for these strings, instead let specficic handler handle them
    if msgType == ns.enums.addonMessagesTypes.droptimizerData then
      if idType == "T" and id ~= ns.me.droptimizerKey then -- targeted droptimizerData sync, but not for me
        -- someone else answered the same update check we might have an answer queued for, only decode when we do
        if private.hasSupersedeFor(ns.enums.context.droptimizerData, id) then
          local dataString = private.prepString(compressedData, false)
          local timestamp = dataString and ns.mapping.ReadCborPayload(dataString:sub(2))
          if timestamp then
            ns.communication.DropSupersededFromQueue(ns.enums.context.droptimizerData, id, timestamp)
          end
        end
        return
      end
    end
    local dataString = private.prepString(compressedData, false)
    if not dataString then return end
    local dataType = dataString:sub(1, 1)
    if ns.mapping.toRealData[dataType] then
      ns.mapping.toRealData[dataType](configVersion, dbVersion, dataString:sub(2), nil, id, channel, sender)
    elseif ns.debugMode then
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
  if not dataString then return end
  for _, dataStr in pairs({ strsplit("@", dataString) }) do
    local dataType = dataStr:sub(1, 1)
    if ns.mapping.toRealData[dataType] then
      ns.mapping.toRealData[dataType](configVersion, dbVersion, dataStr:sub(2), nil, fullGuid, channel, sender)
    else -- most likely a data type added in a newer version, don't throw at users who haven't updated yet
      ns.Debug.print("No handler found for data type: '%s'", dataType)
    end
  end
end
ns.communication.msgHandlers[prefixes.lowPrio] = ns.communication.msgHandlers[prefixes.normal] -- just use same handler, functionality is the same (at least for now)
if ns.hasDataAddon then
  local mapToTimestampVars = {
    [2] = "currencyUpdated",
    [3] = "questsUpdated",
    [4] = "watermarksUpdated",
    [5] = "craftingItemsUpdated",
    [6] = "vaultDataLastUpdate",
    [7] = "weeklyRewardsUpdate",
    -- 8 is used for lastUpdate, dont wanna change that
    -- 9 is used for droptimizerKey
    [10] = "dungeonsUpdated",
  }
  local minConfigVersionsToCare = {
    [10] = 6,
  }
  ns.communication.msgHandlers[prefixes.updateChecker] = function(prefix, msg, channel, sender)
    if channel ~= "GUILD" then return end -- only accept messages from guild chat for now
    if UnitIsUnit("player", sender) then return end
    local msgType, dbVersion, configVersion, isCbor, guidType, partialGuid, dataStr = msg:match("^(.)(...)(...)(.)(.)(.-)@(.*)$")
    ns.Debug.print("update check from: '%s'", partialGuid)
    dbVersion = tonumber(dbVersion)
    configVersion = tonumber(configVersion)
    if not (dbVersion and configVersion and guidType and partialGuid) then
      ns.Debug.print("Invalid update check format from '%s': %s", sender, msg)
      return
    end
    if dbVersion > ns.config.currentDBVersion or configVersion > ns.config.configVersion then return end -- our version is older, just ignore
    local data = { strsplit("^", dataStr) }
    if not tonumber(data[1]) then return end
    local fixedPoint = ns.mapping.timestamp.FromValue(data[1])
    for k,v in pairs(mapToTimestampVars) do
      data[k] = fixedPoint - (tonumber(data[k]) or 0)
    end
    -- only answer a sender on our own config: since 5 the payload is zlib wrapped, so an older client
    -- would just drop the droptimizer data. the RequestFullSync calls further down stay unconditional
    -- though, those still pay off: the request rides in the uncompressed header so an older client
    -- reads it fine and answers in deflate, which prepString falls back to.
    if data[9] and WowUtilsDB.droptimizerData[data[9]] and configVersion >= ns.config.configVersion then -- droptimizerKey
      if WowUtilsDB.droptimizerData[data[9]].lastUpdate > fixedPoint - (tonumber(data[8]) or 0) then
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
        if (not minConfigVersionsToCare[k]) or (minConfigVersionsToCare[k] <= configVersion) then
          ns.communication.RequestFullSync(partialGuid, channel)
          return
        end
      end
    end
  end
end
---@type table<string, wowutils_queueEntry>
private.queue = {}
private.groupChannels = {
  --[ns.enums.chatChannels.instance] = true,
  --[ns.enums.chatChannels.party] = true,
  --[ns.enums.chatChannels.raid] = true,
}
function private.confimChannel(prefChannel)
  prefChannel = prefChannel:lower()
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
  -- built on send, the payload is relative to server time
  private.sendAddonMessage(ns.enums.addonMessagesTypes.updateCheckForDesktopAppUsers, function()
    ---@diagnostic disable-next-line: param-type-mismatch
    return ns.mapping.GetMsgData(ns.enums.context.updateCheck, charDB)
  end, ns.enums.chatChannels.guild, nil, false)
end

C_Timer.After(15, function()
  private.updateCheck()
  C_Timer.NewTicker(60, private.updateCheck)
end)

function private.whitelistDataUpdateCheck()
  if ns.restrictedAddonMessages then return end -- unlike private.updateCheck, this actually takes resources to run, so skip checks during restrictions
  for listId in pairs(ns.eligibleSyncLists) do
  --for listId, charList in pairs(WowUtilsDB.syncLists) do
    local charList = WowUtilsDB.syncLists[listId]
    if charList then
      local slugToId = {}
      local found = {}
      for k,v in pairs(charList.characters) do -- TODO do this on data update, but good enough for now (beta)
        slugToId[v] = k
      end
      local temp = {}
      -- 0 means "send everything" to the receiver, so with item sync off claim a far future timestamp instead
      local noItemsTimestamp = not ns.config.itemCacheSync and 999999999 or nil
      -- one entry per id: a key under two guids would otherwise go out twice, and the stale entry gets
      -- answered with a full sync every time. ResolveKeyConflict should keep that from happening, this is the backstop
      local freshest = {} -- id -> charData
      for _, charData in pairs(WowUtilsDB.others) do -- TODO build slug to guid list somewhere thats kept up to date when new data is getting in
        local id = charData.droptimizerKey and slugToId[charData.droptimizerKey]
        if id and (not freshest[id] or (charData.lastUpdate or 0) > (freshest[id].lastUpdate or 0)) then
          freshest[id] = charData
        end
      end
      for id, charData in pairs(freshest) do
        found[id] = true
        table.insert(temp, {id = id, timestamp = ns.mapping.GetCharacterTimestampsForWideSync(charData), itemTimestamp = noItemsTimestamp or ns.mapping.timestamp.ToValue(charData.itemCacheUpdated or 0)})
      end
      for k,v in pairs(slugToId) do
        if not found[v] and not ns.database.ownSlugs[k] then
          table.insert(temp, {id = v, timestamp = 0, itemTimestamp = noItemsTimestamp or 0})
        end
      end
      local str = ns.mapping.GetMsgData(ns.enums.context.whitelistCharSyncRequest, temp, nil, listId)
      if str ~= "" then
        ns.Debug.print("sending whitelistCharSyncRequest for list: '%s', total characters found: '%s'", listId, #temp)
        private.sendAddonMessage(ns.enums.addonMessagesTypes.whitelistCharSyncRequest, str, ns.enums.chatChannels.guild, nil, false, { subKey = listId })
      end
    end
  end
end
C_Timer.After(30, function()
  private.whitelistDataUpdateCheck()
  C_Timer.NewTicker(60*5, private.whitelistDataUpdateCheck)
  --C_Timer.NewTicker(30, private.whitelistDataUpdateCheck)
end)

function private.generalUpdateCheck()
  if ns.restrictedAddonMessages then return end -- unlike private.updateCheck, this actually takes resources to run, so skip checks during restrictions
  -- runs every couple of minutes anyway, keeps the cache from holding on to expired orders between syncs
  local guildCache = ns.randomThings.craftingOrders.GetGuildCache()
  if guildCache then
    ns.randomThings.craftingOrders.PruneExpired(guildCache)
  end
  local str = ns.mapping.GetMsgData(ns.enums.context.generalUpdatedCheck)
  if str == "" then return end
  ns.Debug.print("sending generalUpdateCheck")
  private.sendAddonMessage(ns.enums.addonMessagesTypes.generalUpdatedCheck, str, ns.enums.chatChannels.guild, nil, false)
end

C_Timer.After(20, function()
  private.generalUpdateCheck()
  C_Timer.NewTicker(60*2, private.generalUpdateCheck)
end)

---@param addonMessagesType string
---@return string?
function private.getCorrectPrefixForType(addonMessagesType)
  if addonMessagesType == ns.enums.addonMessagesTypes.updateCheckForDesktopAppUsers then
    return prefixes.updateChecker
  end
  if addonMessagesType == ns.enums.addonMessagesTypes.itemCache or addonMessagesType == ns.enums.addonMessagesTypes.craftingOrders then
    return prefixes.lowPrio
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
---@param sending true
---@return string
---@overload fun(str:string?, sending:false):string? -- nil when the payload could not be decoded (corrupted/incomplete transfer)
function private.prepString(str, sending)
  if sending then
    -- zlib rather than raw deflate: the wrapper carries an adler-32 that DecompressString verifies
    -- down in C, so a payload garbled in transit errors out instead of inflating into plausible
    -- looking garbage that we would happily write to the db. raw deflate has no trailer at all, so
    -- nothing catches that. costs 8 bytes on the wire and never an extra AceComm chunk in practice.
    -- clients older than 1.0.6 can't read these and will just drop them, which is fine.
    local compressed = CompressString(str, Enum.CompressionMethod.Zlib, Enum.CompressionLevel.OptimizeForSize)
    local encoded = EncodeBase64(compressed)
    ns.Debug.print("Results: Uncompressed #%s - Compressed #%s - Encoded #%s", str:len(), compressed:len(), encoded:len())
    return encoded
  end
  -- AceComm has no integrity check on reassembled multipart messages, so a dropped or interleaved
  -- chunk lands here as garbage. decode defensively and drop the message instead of erroring out.
  if type(str) ~= "string" or str == "" then return end
  local ok, compressed = pcall(DecodeBase64, str)
  if not ok or type(compressed) ~= "string" then
    ns.Debug.print("failed to base64 decode incoming message (#%s)", str:len())
    return
  end
  -- zlib first (1.0.6+), then raw deflate for anyone still on an older version. the two can't be
  -- confused: raw deflate fails zlib's header check, so it falls through to the second attempt.
  -- note the checksum only catches accidental corruption. it is no defence against someone
  -- deliberately sending a crafted payload on our prefix, since they can compute a valid checksum
  -- just as easily. that is what the structural walk in ns.mapping.SafeDeserializeCBOR is for, and
  -- why it has to keep running on every payload no matter how this decompressed.
  local decompressed
  ok, decompressed = pcall(DecompressString, compressed, Enum.CompressionMethod.Zlib)
  if not ok or type(decompressed) ~= "string" then
    -- TODO remove this deflate fallback once nobody is on a pre-1.0.6 version any more. it only
    -- exists to keep reading their data during the changeover (they still send raw deflate, and the
    -- handlers accept older configVersions, so this runs before any version check can spare us).
    -- once it's gone it stops being a second chance for a corrupt payload to be read as deflate.
    ok, decompressed = pcall(DecompressString, compressed, Enum.CompressionMethod.Deflate)
  end
  if not ok or type(decompressed) ~= "string" then
    ns.Debug.print("failed to decompress incoming message (#%s)", str:len())
    return
  end
  ns.Debug.print("Results (D): Encoded #%s - Compressed #%s - Uncompressed #%s", str:len(), compressed:len(), decompressed:len())
  return decompressed
end

-- send queue: one message per tick, picked by type prio (aged by wait time) then by age.
-- keyed so the same data can't sit in the queue twice, payloads are built when they actually go out
local msgTypes = ns.enums.addonMessagesTypes
local typePrio = { -- lower goes first
  [msgTypes.fullCharacterSyncRequest] = 1,
  [msgTypes.syncListRequest] = 1,
  [msgTypes.forLoot] = 2,
  [msgTypes.droptimizerData] = 2,
  [msgTypes.partialCharacterUpdate] = 2,
  [msgTypes.updateCheckForDesktopAppUsers] = 3,
  [msgTypes.generalUpdatedCheck] = 3,
  [msgTypes.whitelistCharSyncRequest] = 3,
  [msgTypes.fullCharacterSync] = 4,
  [msgTypes.fullSynclistInformation] = 4,
  [msgTypes.itemCache] = 5,
  [msgTypes.craftingOrders] = 5,
}
local defaultPrio = 3
local agingStep = 30 -- seconds waited per prio level gained, keeps low prio from starving
local tickInterval = 0.5
local laneTimeout = 10 -- in case the ctl callback never fires for a message
local replyJitter = 10 -- relays get a random delay so whoever goes first can supersede everyone else's copy
---one lane per prefix, so a big BULK transfer can't hold back NORMAL messages
---@type table<string, {current: wowutils_queueEntry?, since: number}>
local lanes = {}
for _, prefix in pairs(prefixes) do
  lanes[prefix] = { since = 0 }
end
local ticker

---@class wowutils_queueSupersede
---@field context wowutils_enums_context
---@field id string
---@field getTimestamp fun():number same value GetMsgData writes into the payload header

---@class wowutils_queueEntry
---@field addonMessageType wowutils_enums_addonMessageTypes
---@field build string|fun():string?
---@field prefChannel string
---@field target string?
---@field isCbor boolean
---@field prefix string
---@field queuedAt number first enqueue, kept when the entry gets replaced
---@field notBefore number
---@field supersede wowutils_queueSupersede?

---@class wowutils_queueOpts
---@field subKey string? needed when one message type carries different payloads (contexts, list ids)
---@field jitter boolean? for relays that several guild members might send at the same time
---@field supersede wowutils_queueSupersede? drop the queued message when someone else sends the same or newer data

---@param prefix string
---@param now number
---@return boolean
function private.isLaneBusy(prefix, now)
  local lane = lanes[prefix]
  if lane.current and now - lane.since < laneTimeout then return true end
  -- shared with every other addon, so other traffic counts too. internals, guard everything
  local ctl = _G.ChatThrottleLib
  ---@diagnostic disable-next-line: undefined-field
  local p = ctl and ctl.Prio and ctl.Prio[msgPrioForPrexies[prefix]]
  if not p then return false end
  return (p.Ring and p.Ring.pos or p.Blocked and p.Blocked.pos) and true or false
end

---@param entry wowutils_queueEntry
---@param sent number
---@param total number
function private.onChunkSent(entry, sent, total)
  if sent < total then return end
  local lane = lanes[entry.prefix]
  if lane.current == entry then
    lane.current = nil
  end
end

---@param now number
---@return string? key
---@return wowutils_queueEntry? entry
---@return number? prio
function private.pickNext(now)
  local bestKey, best, bestPrio
  for key, entry in pairs(private.queue) do
    if now >= entry.notBefore and not private.isLaneBusy(entry.prefix, now) then
      local prio = (typePrio[entry.addonMessageType] or defaultPrio) - math.floor((now - entry.queuedAt) / agingStep)
      if not best or prio < bestPrio or (prio == bestPrio and entry.queuedAt < best.queuedAt) then
        bestKey, best, bestPrio = key, entry, prio
      end
    end
  end
  return bestKey, best, bestPrio
end

---@param entry wowutils_queueEntry
---@param payload string
---@param channel string
function private.sendNow(entry, payload, channel)
  local lane = lanes[entry.prefix]
  lane.current = entry
  lane.since = GetTime()
  if entry.prefix ~= prefixes.updateChecker then
    payload = private.prepString(payload, true)
  end
  aceComms:SendCommMessage(entry.prefix, private.addVersionsToCompressedString(entry.addonMessageType, payload, entry.target, entry.isCbor), channel, nil, msgPrioForPrexies[entry.prefix], private.onChunkSent, entry)
end

function private.tick()
  if ns.restrictedAddonMessages or not next(private.queue) then
    if ticker then
      ticker:Cancel()
      ticker = nil
    end
    return
  end
  local now = GetTime()
  while true do
    local key, entry, prio = private.pickNext(now)
    if not (key and entry) then return end -- everything is waiting on jitter or a busy lane
    private.queue[key] = nil
    local channel = private.confimChannel(entry.prefChannel)
    local payload = channel and entry.build
    if type(payload) == "function" then
      payload = payload()
    end
    if payload and payload ~= "" then
      ns.Debug.print("sending '%s' - prio '%s', waited '%.1f's, lane '%s', left in queue '%s'", key, prio, now - entry.queuedAt, entry.prefix, CountTable(private.queue))
      private.sendNow(entry, payload, channel)
      return
    end
  end
end

function private.ensureTicker()
  if ticker or ns.restrictedAddonMessages or not next(private.queue) then return end
  ticker = C_Timer.NewTicker(tickInterval, private.tick)
  private.tick() -- don't make a lone message wait for the first tick
end

---@param addonMessagesType wowutils_enums_addonMessageTypes
---@param msgOrBuilder string|fun():string? builders run when the message goes out, so the data is as fresh as it gets. nil/"" drops it
---@param prefChannel "instance_chat"|"raid"|"party"|"guild"
---@param target string? if nil, assume source guid instead
---@param isCbor boolean
---@param opts wowutils_queueOpts?
function private.sendAddonMessage(addonMessagesType, msgOrBuilder, prefChannel, target, isCbor, opts)
  assert(type(addonMessagesType) ~= "nil", "not nill")
  local prefix = private.getCorrectPrefixForType(addonMessagesType)
  if not prefix then return end
  local key = addonMessagesType .. (target or "") .. (opts and opts.subKey or "")
  local entry = private.queue[key]
  if entry then
    -- keep queuedAt and notBefore, constant updates shouldn't push it back or reroll the jitter
    entry.build = msgOrBuilder
    entry.prefChannel = prefChannel
    entry.supersede = opts and opts.supersede
  else
    local now = GetTime()
    private.queue[key] = {
      addonMessageType = addonMessagesType,
      build = msgOrBuilder,
      prefChannel = prefChannel,
      target = target,
      isCbor = isCbor,
      prefix = prefix,
      queuedAt = now,
      notBefore = now + (opts and opts.jitter and math.random() * replyJitter or 0),
      supersede = opts and opts.supersede,
    }
  end
  private.ensureTicker()
end

---@param context wowutils_enums_context
---@param id string
---@return boolean
function private.hasSupersedeFor(context, id)
  for _, entry in pairs(private.queue) do
    if entry.supersede and entry.supersede.context == context and entry.supersede.id == id then
      return true
    end
  end
  return false
end

---someone else sent this data, so our queued copy is pointless if theirs is at least as new
---@param context wowutils_enums_context
---@param id string
---@param incomingTimestamp number
function ns.communication.DropSupersededFromQueue(context, id, incomingTimestamp)
  for key, entry in pairs(private.queue) do
    local supersede = entry.supersede
    if supersede and supersede.context == context and supersede.id == id and incomingTimestamp >= supersede.getTimestamp() then
      ns.Debug.print("dropping queued '%s', someone else sent same or newer data", key)
      private.queue[key] = nil
    end
  end
end

function ns.communication.AddonMessageRestrictionsLifted()
  private.ensureTicker()
end

do
  local lastSentTime = 0
  function ns.communication.SendInfoForLoot()
    if GetTime() - lastSentTime < 5 then return end
    if not IsInGroup() then return end -- even with guild sync only, we dont wanna send messages when we are not in a group
    ns.Debug.print("sending info for loot")
    --local currentGroupType = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "instance_chat" or IsInRaid() and "raid" or "party"
    --if currentGroupType == "party" then return end -- ignore party at least for now

    private.sendAddonMessage(ns.enums.addonMessagesTypes.forLoot, function()
      local t = {}
      tinsert(t, ns.mapping.GetMsgData(ns.enums.context.currency, charDB.currency, charDB.currencyUpdated))
      tinsert(t, ns.mapping.GetMsgData(ns.enums.context.craftingItems, charDB.craftingItems, charDB.craftingItemsUpdated))
      tinsert(t, ns.mapping.GetMsgData(ns.enums.context.watermarks, charDB.watermarks, charDB.watermarksUpdated))
      return tconcat(t, "@")
    end, ns.enums.chatChannels.guild, nil, false)
    -- don't combine messages
    ns.communication.SendDroptimizerData()
    lastSentTime = GetTime()
  end
end
do
  local lastSentTime = 0
  ---@param listId string
  function ns.communication.SendSyncList(listId)
    if not ns.eligibleSyncLists[listId] then return end
    if not WowUtilsDB.syncLists[listId] then return end
    if GetTime() - lastSentTime < 5 then return end
    if not IsInGuild() then return end
    ns.Debug.print("sending full synclist information")
    -- answers someone's request, anyone else with the list answers too
    private.sendAddonMessage(ns.enums.addonMessagesTypes.fullSynclistInformation, function()
      local list = WowUtilsDB.syncLists[listId]
      return list and ns.mapping.GetMsgData(ns.enums.context.fullSynclistInformation, list, nil, listId)
    end, ns.enums.chatChannels.guild, nil, true, {
      subKey = listId,
      jitter = true,
      supersede = {
        context = ns.enums.context.fullSynclistInformation,
        id = listId,
        getTimestamp = function()
          local list = WowUtilsDB.syncLists[listId]
          return list and list.lastUpdate or 0
        end,
      },
    })
    lastSentTime = GetTime()
  end
end
do
  local cache = {}
  ---@param listId string
  ---@param currentTimestamp number?
  function ns.communication.RequestSyncList(listId, currentTimestamp)
    currentTimestamp = currentTimestamp or 0
    if GetTime() - (cache[listId] or 0) < 5 then return end
    if not IsInGuild() then return end
    ns.Debug.print("requesting synclist information '%s'", listId)
    local str = ns.mapping.GetMsgData(ns.enums.context.syncListRequest, listId, currentTimestamp)
    if str == "" then return end
    private.sendAddonMessage(ns.enums.addonMessagesTypes.syncListRequest, str, ns.enums.chatChannels.guild, nil, true, { subKey = listId })
    cache[listId] = GetTime()
  end
end
do
  local lastSentTime = 0
  function ns.communication.SendCurrencyUpdate()
    if GetTime() - lastSentTime < .5 then return end
    ns.Debug.print("sending currency update")
    private.sendAddonMessage(ns.enums.addonMessagesTypes.partialCharacterUpdate, function()
      local dataStr = ns.mapping.GetMsgData(ns.enums.context.currency, charDB.currency, charDB.currencyUpdated)
      if not dataStr then
        geterrorhandler()("dataStr is nil")
      end
      return dataStr
    end, ns.enums.chatChannels.guild, nil, false, { subKey = ns.enums.context.currency })
    lastSentTime = GetTime()
  end
end
do
  local lastSentTime = 0
  function ns.communication.SendWatermarkUpdate()
    if GetTime() - lastSentTime < 1 then return end
    ns.Debug.print("sending watermarks")
    private.sendAddonMessage(ns.enums.addonMessagesTypes.partialCharacterUpdate, function()
      return ns.mapping.GetMsgData(ns.enums.context.watermarks, charDB.watermarks, charDB.watermarksUpdated)
    end, ns.enums.chatChannels.guild, nil, false, { subKey = ns.enums.context.watermarks })
    lastSentTime = GetTime()
  end
end
do
  local lastSentTime = 0
  function ns.communication.SendBonusCoinUsageUpdate()
    if GetTime() - lastSentTime < 1 then return end
    ns.Debug.print("sending bonus coin usages")
    private.sendAddonMessage(ns.enums.addonMessagesTypes.partialCharacterUpdate, function()
      return ns.mapping.GetMsgData(ns.enums.context.bonusCoin, charDB.bonusCoinUsage, charDB.bonusCoinUsageUpdated)
    end, ns.enums.chatChannels.guild, nil, true, { subKey = ns.enums.context.bonusCoin })
    lastSentTime = GetTime()
  end
end
do
  local lastSentTime = 0
  function ns.communication.SendCraftingItemUpdate()
    if GetTime() - lastSentTime < 1 then return end
    ns.Debug.print("sending craft item update")
    private.sendAddonMessage(ns.enums.addonMessagesTypes.partialCharacterUpdate, function()
      return ns.mapping.GetMsgData(ns.enums.context.craftingItems, charDB.craftingItems, charDB.craftingItemsUpdated)
    end, ns.enums.chatChannels.guild, nil, false, { subKey = ns.enums.context.craftingItems })
    lastSentTime = GetTime()
  end
end
do
  local lastSentTime = 0
  function ns.communication.SendLockoutUpdate()
    if GetTime() - lastSentTime < 1 then return end
    if not charDB.lockouts then return end
    ns.Debug.print("sending lockout update")
    private.sendAddonMessage(ns.enums.addonMessagesTypes.partialCharacterUpdate, function()
      return ns.mapping.GetMsgData(ns.enums.context.lockouts, charDB.lockouts, charDB.lockoutsUpdated)
    end, ns.enums.chatChannels.guild, nil, false, { subKey = ns.enums.context.lockouts })
    lastSentTime = GetTime()
  end
end
do
  local lastSentTime = 0
  function ns.communication.SendDungeonsDoneUpdate()
    if GetTime() - lastSentTime < 1 then return end
    if not charDB.dungeonsDone then return end
    ns.Debug.print("sending dungeonsDone update")
    private.sendAddonMessage(ns.enums.addonMessagesTypes.partialCharacterUpdate, function()
      return ns.mapping.GetMsgData(ns.enums.context.dungeonsDone, charDB.dungeonsDone, charDB.dungeonsUpdated)
    end, ns.enums.chatChannels.guild, nil, false, { subKey = ns.enums.context.dungeonsDone })
    lastSentTime = GetTime()
  end
end
do
  local lastSentTime = 0
  ---@param targetChannel string
  function ns.communication.SendFullSyncFromCurrentCharacter(targetChannel)
    if GetTime() - lastSentTime < 5 then return end
    ns.Debug.print("sending current full char")
    private.sendAddonMessage(ns.enums.addonMessagesTypes.fullCharacterSync, function()
      return ns.mapping.GetMsgData(ns.enums.context.fullCharacterSync, charDB)
    end, targetChannel, nil, true)
    lastSentTime = GetTime()
  end
end
do
  local cache = {}
  ---@param data wowutils_ownChar|wowutils_otherChar
  function ns.communication.SendFullSyncFromSpecificCharacter(data)
    if GetTime() - (cache[data.guid] or 0) < 5 then return end
    ns.Debug.print("sending full char '%s'", data.droptimizerKey)
    -- relay out of the db, anyone else holding this character answers the same request
    private.sendAddonMessage(ns.enums.addonMessagesTypes.fullCharacterSync, function()
      return ns.mapping.GetMsgData(ns.enums.context.fullCharacterSyncFromDB, data)
    end, ns.enums.chatChannels.guild, "A"..ns.mapping.ConvertGuidToMsgFormat(data.guid), true, {
      jitter = data.guid ~= ns.me.guid,
      supersede = {
        context = ns.enums.context.fullCharacterSyncFromDB,
        id = data.guid,
        getTimestamp = function() return ns.mapping.GetCharacterTimestampsForWideSync(data) end,
      },
    })
    cache[data.guid] = GetTime()
  end
end
do
  local cache = {}
  local delayedSends = {}
  ---@param data wowutils_ownChar|wowutils_otherChar
  function ns.communication.SendItemsFromSpecificCharacter(data)
    if not ns.config.itemCacheSync then return end
    local sinceLast = GetTime() - (cache[data.guid] or 0)
    if sinceLast < 5 then
      -- don't drop it, a change right after a send would otherwise never go out. data is the live db
      -- table, so the delayed send picks up whatever changed in the meantime
      if not delayedSends[data.guid] then
        delayedSends[data.guid] = C_Timer.NewTimer(5 - sinceLast, function()
          delayedSends[data.guid] = nil
          ns.communication.SendItemsFromSpecificCharacter(data)
        end)
      end
      return
    end
    ns.Debug.print("sending items for char '%s'", data.droptimizerKey)
    if not data.itemCache2 then return end
    private.sendAddonMessage(ns.enums.addonMessagesTypes.itemCache, function()
      return data.itemCache2 and ns.mapping.GetMsgData(ns.enums.context.itemCache, data)
    end, ns.enums.chatChannels.guild, "A"..ns.mapping.ConvertGuidToMsgFormat(data.guid), true, {
      jitter = data.guid ~= ns.me.guid, -- own items come from us, anything else is a relay
      supersede = {
        context = ns.enums.context.itemCache,
        id = data.guid,
        getTimestamp = function() return data.itemCacheUpdated or 0 end,
      },
    })
    cache[data.guid] = GetTime()
  end
end
do
  local cache = {}
  ---@param partialGuid string
  ---@param targetChannel string
  function ns.communication.RequestFullSync(partialGuid, targetChannel)
    if GetTime() - (cache[partialGuid] or 0) < 5 then return end
    ns.Debug.print("requesting full sync for '%s'", partialGuid)
    private.sendAddonMessage(ns.enums.addonMessagesTypes.fullCharacterSyncRequest, "F", targetChannel, "T" .. partialGuid, false)
    cache[partialGuid] = GetTime()
  end
end
do
  local lastSentTime = 0
  function ns.communication.SendVaultDataUpdate()
    if GetTime() - lastSentTime < 1 then return end
    private.sendAddonMessage(ns.enums.addonMessagesTypes.partialCharacterUpdate, function()
      return ns.mapping.GetMsgData(ns.enums.context.vaultData, charDB.vaultData, charDB.vaultDataLastUpdate or 0)
    end, ns.enums.chatChannels.guild, nil, true, { subKey = ns.enums.context.vaultData })
    lastSentTime = GetTime()
  end
end
do
  local lastSentTime = 0
  function ns.communication.SendWeeklyRewardsUpdate()
    if GetTime() - lastSentTime < 1 then return end
    private.sendAddonMessage(ns.enums.addonMessagesTypes.partialCharacterUpdate, function()
      return ns.mapping.GetMsgData(ns.enums.context.weeklyRewards, charDB.weeklyRewards, charDB.weeklyRewardsUpdate or 0)
    end, ns.enums.chatChannels.guild, nil, true, { subKey = ns.enums.context.weeklyRewards })
    lastSentTime = GetTime()
  end
end
do
  local lastSentTime = 0
  function ns.communication.SendQuestUpdate()
    if GetTime() - lastSentTime < 1 then return end
    private.sendAddonMessage(ns.enums.addonMessagesTypes.partialCharacterUpdate, function()
      return ns.mapping.GetMsgData(ns.enums.context.quests, charDB.quests, charDB.questsUpdated or 0)
    end, ns.enums.chatChannels.guild, nil, false, { subKey = ns.enums.context.quests })
    lastSentTime = GetTime()
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
    local dataKey = key == "own" and ns.me.droptimizerKey or key
    local target = sformat("%s%s", key == "own" and "S" or "T", dataKey)
    --local channel = ns.enums.chatChannels.guild
    --if key == "own" then
      --channel = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "instance_chat" or IsInRaid() and "raid" or "party"
    --end
    ---@type wowutils_queueOpts?
    local opts
    if key ~= "own" then -- answering someone's update check, others with the same data answer too
      opts = {
        jitter = true,
        supersede = {
          context = ns.enums.context.droptimizerData,
          id = key,
          getTimestamp = function()
            local data = WowUtilsDB.droptimizerData[key]
            return data and data.lastUpdate or 0
          end,
        },
      }
    end
    private.sendAddonMessage(ns.enums.addonMessagesTypes.droptimizerData, function()
      local data = WowUtilsDB.droptimizerData[dataKey]
      return data and ns.mapping.GetMsgData(ns.enums.context.droptimizerData, data)
    end, ns.enums.chatChannels.guild, target, true, opts)
    cache[key] = GetTime()
  end
end
do
  local lastSentTime = 0
  local delayedSend
  ---sends every profession of the current guild in one message
  function ns.communication.SendCraftingOrders()
    local sinceLast = GetTime() - lastSentTime
    if sinceLast < 10 then
      -- don't drop it, merges rely on the send back to converge
      if not delayedSend then
        delayedSend = C_Timer.NewTimer(10 - sinceLast, function()
          delayedSend = nil
          ns.communication.SendCraftingOrders()
        end)
      end
      return
    end
    if not IsInGuild() then return end
    local guildCache = ns.randomThings.craftingOrders.GetGuildCache()
    if not (guildCache and next(guildCache)) then return end
    ns.randomThings.craftingOrders.PruneExpired(guildCache)
    ns.Debug.print("sending crafting orders")
    private.sendAddonMessage(ns.enums.addonMessagesTypes.craftingOrders, function()
      local cache = ns.randomThings.craftingOrders.GetGuildCache()
      if not (cache and next(cache)) then return end
      ns.randomThings.craftingOrders.PruneExpired(cache)
      return ns.mapping.GetMsgData(ns.enums.context.craftingOrders, cache, nil, ns.me.guildInfo.dbSlug)
    end, ns.enums.chatChannels.guild, nil, true)
    lastSentTime = GetTime()
  end
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
