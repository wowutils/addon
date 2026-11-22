---@type string, wowutilsPrivate
local addon_name, ns = ...
---@class wowutilsPrivate
---@field randomThings table
ns.randomThings = {}
if ns.IsRetail then -- crafting orders
  ns.randomThings.craftingOrders = {}
  local lastOrder = {}
  EventRegistry:RegisterCallback("ProfessionsCustomerOrders.RecipeSelected", function(_, itemID)
    if itemID then
      lastOrder.itemID = itemID
    end
  end)
  hooksecurefunc(C_CraftingOrders, "PlaceNewOrder", function(order)
    if not order.skillLineAbilityID then
      return
    end
    local professionName = C_TradeSkillUI.GetProfessionNameForSkillLineAbility(order.skillLineAbilityID)
    if not professionName then
      return
    end
    local targetProfession = Enum.Profession[professionName]
    if not targetProfession then
      return
    end
    if order.recraftItem then
      local itemID = C_Item.GetItemIDByGUID(order.recraftItem)
      lastOrder.itemID = itemID
    end
    if not lastOrder.itemID then
      return
    end
    lastOrder.placed = GetTime()
    lastOrder.data = order
    lastOrder.profession = targetProfession
  end)
  local activeStates = {
    [Enum.CraftingOrderState.Creating] = true,
    [Enum.CraftingOrderState.Created] = true,
    [Enum.CraftingOrderState.Claiming] = true,
    [Enum.CraftingOrderState.Claimed] = true,
  }
  ---@param tipAmount number copper
  ---@return number? gold, nil under 1g to keep transfers small
  local function toTipGold(tipAmount)
    local gold = math.floor((tipAmount or 0) / 1e4)
    return gold > 0 and gold or nil
  end

  -- used by the options gui for the toggles, and for the icons in notifications
  ns.randomThings.craftingOrders.notifyProfessions = {
    { id = Enum.Profession.Alchemy, name = "Alchemy", atlas = "Mobile-Alchemy" },
    { id = Enum.Profession.Blacksmithing, name = "Blacksmithing", atlas = "Mobile-Blacksmithing" },
    { id = Enum.Profession.Enchanting, name = "Enchanting", atlas = "Mobile-Enchanting" },
    { id = Enum.Profession.Engineering, name = "Engineering", atlas = "Mobile-Enginnering" }, -- blizzard typo
    { id = Enum.Profession.Inscription, name = "Inscription", atlas = "Mobile-Inscription" },
    { id = Enum.Profession.Jewelcrafting, name = "Jewelcrafting", atlas = "Mobile-Jewelcrafting" },
    { id = Enum.Profession.Leatherworking, name = "Leatherworking", atlas = "Mobile-Leatherworking" },
    { id = Enum.Profession.Tailoring, name = "Tailoring", atlas = "Mobile-Tailoring" },
  }
  local professionIcons, professionAtlases = {}, {}
  for _, profession in ipairs(ns.randomThings.craftingOrders.notifyProfessions) do
    profession.icon = CreateAtlasMarkup(profession.atlas, 0, 0)
    professionIcons[profession.id] = profession.icon
    professionAtlases[profession.id] = profession.atlas
  end
  ns.randomThings.craftingOrders.professionAtlases = professionAtlases

  local clockIcon = CreateSimpleTextureMarkup(string.format([[Interface\AddOns\%s\media\icons\clock.tga]], addon_name), 0, 0)

  ---orders carry no creation time, so this is when someone first saw it: the customer's own client right after
  ---placing it, or a crafter's scan. "seen" so it doesn't read as the exact placement time
  ---@param seenAt number?
  ---@return string
  local function formatSeen(seenAt)
    if not seenAt or seenAt <= 0 then return "" end
    local elapsed = GetServerTime() - seenAt
    if elapsed < 60 then
      return string.format(" %s seen just now", clockIcon)
    end
    local hours, minutes = math.floor(elapsed / 3600), math.floor(elapsed % 3600 / 60)
    if hours > 0 then
      return string.format(" %s seen %dh %dm ago", clockIcon, hours, minutes)
    end
    return string.format(" %s seen %dm ago", clockIcon, minutes)
  end
  ns.randomThings.craftingOrders.FormatSeen = formatSeen

  ---placed by any character on this account, not just the one we're logged in on
  ---@param order wowutils_craftingOrder
  ---@return boolean
  local function isOwnOrder(order)
    return WowUtilsDB.ownCharacters[ns.mapping.ConvertPartialGuidToGuid(order.customerGuid)] ~= nil
  end
  ns.randomThings.craftingOrders.IsOwnOrder = isOwnOrder

  ---same filter the notifications use, the work orders tab groups by it too
  ---@param professionId number
  ---@param order wowutils_craftingOrder
  ---@return boolean
  function ns.randomThings.craftingOrders.MatchesNotifySettings(professionId, order)
    local o = WowUtilsDB.options.craftingOrders
    return o.professions[professionId] and not order.isDone and not isOwnOrder(order) and (order.tip or 0) >= o.tipThreshold or false
  end

  ---@param professionId number
  ---@param itemId number
  ---@param customerName string
  ---@param isRecraft boolean?
  ---@param tip number? gold
  ---@param seenAt number? server time the order was first seen
  local function showNotification(professionId, itemId, customerName, isRecraft, tip, seenAt)
    -- itemId comes from other players, unknown ids have no icon
    local text = string.format("%sGuild %s %s %s%s%s", professionIcons[professionId] or "",
      CreateSimpleTextureMarkup(C_Item.GetItemIconByID(itemId) or 134400, 0, 0), customerName, C_CurrencyInfo.GetCoinTextureString((tip or 0) * 1e4, 0),
      isRecraft and " (Recraft)" or "", formatSeen(seenAt))
    ns.notifications.AddMessage(text)
    if WowUtilsDB.options.craftingOrders.printToChat then
      print(text)
    end
  end

  -- first seen travels as whole minutes before expiry, at most 2880 for a 48h order. cbor fits that in 3 bytes,
  -- a full timestamp (or a delta in seconds) would take 5
  ---@param order wowutils_craftingOrder
  ---@return number? firstSeen server time
  local function getFirstSeen(order)
    return order.seen and order.expirationTime - order.seen * 60 or nil
  end
  ---@param order wowutils_craftingOrder
  ---@param firstSeen number server time
  local function setFirstSeen(order, firstSeen)
    order.seen = math.max(0, math.ceil((order.expirationTime - firstSeen) / 60))
  end

  ---notifies about every open order we didn't have cached yet, however old it is. a profession we had no data
  ---for at all counts as everything being new, so the first sync on a fresh client announces all open orders
  ---@param professionId number
  ---@param previous wowutils_craftingOrderProfession?
  ---@param current wowutils_craftingOrderProfession
  local function notifyNewOrders(professionId, previous, current)
    local o = WowUtilsDB.options.craftingOrders
    if not o.professions[professionId] then return end
    local known = previous and previous.orders or {}
    for orderId, order in pairs(current.orders) do
      if not known[orderId] and ns.randomThings.craftingOrders.MatchesNotifySettings(professionId, order) then
        local _, classFile, _, _, _, customerName = GetPlayerInfoByGUID(ns.mapping.ConvertPartialGuidToGuid(order.customerGuid))
        customerName = customerName or "?"
        -- class only comes back when the client has seen that player, so this stays uncolored for strangers
        local classColor = classFile and C_ClassColor.GetClassColor(classFile)
        if classColor then
          customerName = classColor:WrapTextInColorCode(customerName)
        end
        -- entries from before firstSeen was tracked fall back to the customer side stamp or the scan time
        showNotification(professionId, order.itemId, customerName, order.isRecraft, order.tip, getFirstSeen(order) or order.updated or current.lastScan)
      end
    end
  end

  function ns.randomThings.craftingOrders.ShowTestNotification()
    local professions = ns.randomThings.craftingOrders.notifyProfessions
    local itemId
    while not itemId do
      local randomItemId = math.random(1, 300000)
      if C_Item.GetItemInfoInstant(randomItemId) then
        itemId = randomItemId
      end
    end
    showNotification(professions[math.random(1, #professions)].id, itemId, UnitName("player"), math.random(0, 1) == 1, math.random(1, 9999),
      GetServerTime() - math.random(0, 3 * 3600))
  end

  ---@param skillLineAbilityID number
  ---@return number?
  local function getProfessionForSkillLineAbility(skillLineAbilityID)
    local professionName = C_TradeSkillUI.GetProfessionNameForSkillLineAbility(skillLineAbilityID)
    return professionName and Enum.Profession[professionName]
  end

  ---@param create boolean?
  ---@return table<number, wowutils_craftingOrderProfession>?
  function ns.randomThings.craftingOrders.GetGuildCache(create)
    local guildSlug = ns.me.guildInfo and ns.me.guildInfo.dbSlug
    if not guildSlug then return end
    if not WowUtilsDB.craftingOrderCache[guildSlug] and create then
      WowUtilsDB.craftingOrderCache[guildSlug] = {}
    end
    return WowUtilsDB.craftingOrderCache[guildSlug]
  end

  ---every guild we have orders cached for, not just the current one
  function ns.randomThings.craftingOrders.PruneAllExpired()
    for _, guildCache in pairs(WowUtilsDB.craftingOrderCache) do
      ns.randomThings.craftingOrders.PruneExpired(guildCache)
    end
  end

  local knownProfessions = {}
  for _, profession in ipairs(ns.randomThings.craftingOrders.notifyProfessions) do
    knownProfessions[profession.id] = true
  end
  local maxOrdersPerProfession = 200
  local maxOrderDuration = 48 * 60 * 60 -- longest a guild order can last
  local maxClockSkew = 300 -- anything further in the future is bogus and would win every merge

  ---@return boolean
  local function isInt(v) -- v == v drops NaN, % 1 drops fractions and inf
    return type(v) == "number" and v == v and v % 1 == 0
  end

  ---why an order would be rejected, nil when it's fine. used on incoming data and on our own cache alike: an
  ---entry the other side throws away would otherwise make every merge think they're missing it, and we'd keep
  ---resending it to each other
  ---@param orderId any
  ---@param order any
  ---@param now number
  ---@return string? reason
  local function getInvalidReason(orderId, order, now)
    if type(order) ~= "table" then return "not a table" end
    if not isInt(orderId) then return "bad orderId " .. tostring(orderId) end
    if not isInt(order.itemId) then return "bad itemId " .. tostring(order.itemId) end
    if not isInt(order.expirationTime) then return "bad expirationTime " .. tostring(order.expirationTime) end
    if order.expirationTime <= now then return "expired" end
    if order.expirationTime > now + maxOrderDuration then
      return string.format("expires in %.1fh, over the 48h max", (order.expirationTime - now) / 3600)
    end
    if type(order.customerGuid) ~= "string" or not order.customerGuid:find("^%d+%-%x+$") then
      return string.format("bad customerGuid '%s'", tostring(order.customerGuid))
    end
    if order.updated ~= nil and not (isInt(order.updated) and order.updated <= now + maxClockSkew) then
      return "bad updated " .. tostring(order.updated)
    end
    if order.tip ~= nil and not isInt(order.tip) then return "bad tip " .. tostring(order.tip) end
    return nil
  end

  ---drops expired orders, and anything in our own cache that a receiver would reject anyway
  ---@param guildCache table<number, wowutils_craftingOrderProfession>
  function ns.randomThings.craftingOrders.PruneExpired(guildCache)
    local now = GetServerTime()
    for professionId, professionData in pairs(guildCache) do
      local orders = professionData.orders
      for orderId, order in pairs(orders) do
        local reason = getInvalidReason(orderId, order, now)
        if reason then
          if reason ~= "expired" then
            ns.Debug.print("crafting orders: removing cached order %s (prof %s): %s", tostring(orderId), tostring(professionId), reason)
          end
          orders[orderId] = nil -- clearing the current key is fine mid pairs
        end
      end
    end
  end

  ---incoming data is from other players, so only the fields we know get copied over and anything off is dropped
  ---@param professionData any
  ---@return wowutils_craftingOrderProfession?
  local function sanitizeProfessionData(professionData)
    if not (type(professionData) == "table" and type(professionData.orders) == "table") then return nil end
    local now = GetServerTime()
    local latest = now + maxClockSkew
    if not (isInt(professionData.lastScan) and isInt(professionData.lastUpdate))
        or professionData.lastScan > latest or professionData.lastUpdate > latest then
      return nil
    end
    local clean = { lastScan = professionData.lastScan, lastUpdate = professionData.lastUpdate, orders = {} }
    local count = 0
    for key, order in pairs(professionData.orders) do
      if count >= maxOrdersPerProfession then break end
      -- early 1.0.8 builds still send an array with orderId inside each entry
      local orderId = type(order) == "table" and order.orderId or key
      local reason = getInvalidReason(orderId, order, now)
      if reason then
        ns.Debug.print("crafting orders: dropping incoming order %s: %s", tostring(orderId), reason)
      else
        -- a bad first seen only loses that field, not the order. it can't be longer than an order lasts or in the future
        local seen = order.seen
        if not (isInt(seen) and seen >= 0 and seen * 60 <= maxOrderDuration and order.expirationTime - seen * 60 <= latest) then
          seen = nil
        end
        clean.orders[orderId] = {
          customerGuid = order.customerGuid,
          expirationTime = order.expirationTime,
          itemId = order.itemId,
          isRecraft = order.isRecraft == true or nil,
          isDone = order.isDone == true or nil,
          updated = order.updated,
          tip = order.tip,
          seen = seen,
        }
        count = count + 1
      end
    end
    return clean
  end

  -- orders with .updated came from a customer side scan, they only survive if they are newer than the winning full scan
  ---@param ours wowutils_craftingOrderProfession
  ---@param theirs wowutils_craftingOrderProfession
  ---@return wowutils_craftingOrderProfession merged
  ---@return boolean oursHadExtra merged has something theirs didn't, so they should get ours back
  local function mergeProfession(ours, theirs)
    local base = theirs.lastScan > ours.lastScan and theirs or ours
    local oursHadExtra = ours.lastScan > theirs.lastScan
    -- newest customer entry per orderId from both sides, only if newer than the base scan
    local customerEntries = {}
    for _, side in ipairs({ ours, theirs }) do
      for orderId, order in pairs(side.orders) do
        if order.updated and order.updated > base.lastScan then
          local current = customerEntries[orderId]
          if not current or current.updated < order.updated then
            customerEntries[orderId] = order
          end
        end
      end
    end
    -- lastUpdate never goes down through a merge. a customer entry that raised it can get pruned later,
    -- rebuilding it from what's left would leave us behind the sender forever and they'd keep resending
    local merged = { lastScan = base.lastScan, lastUpdate = math.max(base.lastScan, ours.lastUpdate, theirs.lastUpdate), orders = {} }
    for orderId, order in pairs(base.orders) do
      if not order.updated and not customerEntries[orderId] then
        merged.orders[orderId] = order
      end
    end
    for orderId, order in pairs(customerEntries) do
      merged.orders[orderId] = order
      merged.lastUpdate = math.max(merged.lastUpdate, order.updated)
      local theirOrder = theirs.orders[orderId]
      if (theirOrder and theirOrder.updated or 0) < order.updated then
        oursHadExtra = true
      end
    end
    -- first seen is the earliest either side knows of, whichever side the entry itself came from. more minutes
    -- before expiry = seen earlier
    for orderId, order in pairs(merged.orders) do
      local ourOrder, theirOrder = ours.orders[orderId], theirs.orders[orderId]
      local ourSeen, theirSeen = ourOrder and ourOrder.seen or -1, theirOrder and theirOrder.seen or -1
      local seen = math.max(ourSeen, theirSeen)
      if seen >= 0 then
        order.seen = seen
      end
      if ourSeen > theirSeen then
        oursHadExtra = true -- they saw it later than we did, or not at all
      end
    end
    return merged, oursHadExtra
  end

  ---@param guildSlug string
  ---@param incoming table
  ---@return boolean sendBack we had data the sender didn't
  function ns.randomThings.craftingOrders.MergeIncoming(guildSlug, incoming)
    if not (ns.me.guildInfo and ns.me.guildInfo.dbSlug == guildSlug) then return false end -- changed guilds mid flight
    local guildCache = ns.randomThings.craftingOrders.GetGuildCache(true)
    ---@cast guildCache -nil
    local sendBack = false
    for professionId, incomingData in pairs(incoming) do
      local professionData = knownProfessions[professionId] and sanitizeProfessionData(incomingData)
      if not professionData then
        ns.Debug.print("crafting orders: dropped incoming prof %s (%s), unknown profession or invalid data", tostring(professionId), type(professionId))
      elseif type(incomingData.orders) == "table" and CountTable(professionData.orders) < CountTable(incomingData.orders) then
        ns.Debug.print("crafting orders: prof %s, %d of %d incoming orders dropped as invalid", professionId,
          CountTable(incomingData.orders) - CountTable(professionData.orders), CountTable(incomingData.orders))
      end
      if professionData then
        local current = guildCache[professionId]
        if not current then
          notifyNewOrders(professionId, nil, professionData)
          guildCache[professionId] = professionData
          ns.Debug.print("crafting orders merged: prof %s, %s orders (new)", professionId, CountTable(professionData.orders))
        else
          local merged, oursHadExtra = mergeProfession(current, professionData)
          notifyNewOrders(professionId, current, merged)
          guildCache[professionId] = merged
          sendBack = sendBack or oursHadExtra
          ns.Debug.print("crafting orders merged: prof %s, %s orders, ours had extra: %s", professionId, CountTable(merged.orders), tostring(oursHadExtra))
        end
      end
    end
    -- professions they don't have at all
    for professionId in pairs(guildCache) do
      if incoming[professionId] == nil then
        sendBack = true
        break
      end
    end
    ns.randomThings.craftingOrders.PruneExpired(guildCache)
    if ns.gui and ns.gui.OnCraftingOrdersChanged then
      ns.gui:OnCraftingOrdersChanged()
    end
    return sendBack
  end

  ---@param professionTimestamps table<number, number> professionId -> lastUpdate from another client
  ---@return boolean
  function ns.randomThings.craftingOrders.HasNewerDataThan(professionTimestamps)
    local guildCache = ns.randomThings.craftingOrders.GetGuildCache()
    if not guildCache then return false end
    for professionId, professionData in pairs(guildCache) do
      if (professionTimestamps[professionId] or 0) < professionData.lastUpdate then
        return true
      end
    end
    return false
  end

  ---@class wowutils_activeCraftingOrder
  ---@field professionId number
  ---@field orderId number
  ---@field order wowutils_craftingOrder
  ---@field isOwn boolean
  ---@field matches boolean passes the notification settings
  ---@field seenAt number server time, best guess at when the order went up

  ---open orders of the current guild, expired and done ones left out
  ---@return wowutils_activeCraftingOrder[]? nil when not in a guild
  function ns.randomThings.craftingOrders.GetActiveOrders()
    if not (ns.me.guildInfo and ns.me.guildInfo.dbSlug) then return nil end
    local list = {}
    local guildCache = ns.randomThings.craftingOrders.GetGuildCache()
    if not guildCache then return list end
    ns.randomThings.craftingOrders.PruneExpired(guildCache)
    for professionId, professionData in pairs(guildCache) do
      for orderId, order in pairs(professionData.orders) do
        if not order.isDone then
          tinsert(list, {
            professionId = professionId,
            orderId = orderId,
            order = order,
            isOwn = isOwnOrder(order),
            matches = ns.randomThings.craftingOrders.MatchesNotifySettings(professionId, order),
            -- same fallback the notifications use for entries from before first seen was tracked
            seenAt = getFirstSeen(order) or order.updated or professionData.lastScan or 0,
          })
        end
      end
    end
    return list
  end

  local function onCacheChanged()
    if ns.gui and ns.gui.OnCraftingOrdersChanged then
      ns.gui:OnCraftingOrdersChanged()
    end
  end

  -- customer side: adds our own active guild orders to the cache, inactive ones get tagged as done
  ---@param orders CraftingOrderInfo[]
  local function addMyOrdersToCache(orders)
    local guildCache = ns.randomThings.craftingOrders.GetGuildCache(true)
    if not guildCache then return end
    local now = GetServerTime()
    local changed = false
    local added, tagged = 0, 0
    for _, order in ipairs(orders) do
      local professionId = order.orderType == Enum.CraftingOrderType.Guild and order.expirationTime > now and getProfessionForSkillLineAbility(order.skillLineAbilityID)
      if professionId then
        if not guildCache[professionId] then
          guildCache[professionId] = { lastScan = 0, lastUpdate = 0, orders = {} }
        end
        local isDone = not activeStates[order.orderState] or nil
        local existing = guildCache[professionId].orders[order.orderID]
        if existing and not existing.seen then
          setFirstSeen(existing, now)
        end
        if not existing and isDone then
          -- a finished order stays in our list for ~14 days and expirationTime is then when it leaves that
          -- history, not when the order expired. nothing to announce for one we never had, so leave it out
        elseif not existing then
          local entry = {
            -- every order in our own list is ours, don't trust the field: it can come back empty
            customerGuid = ns.mapping.ConvertGuidToMsgFormat(ns.me.guid),
            expirationTime = order.expirationTime,
            itemId = order.itemID,
            isRecraft = order.isRecraft or nil,
            isDone = isDone,
            updated = now,
            tip = toTipGold(order.tipAmount),
          }
          setFirstSeen(entry, now) -- we scan right after placing, so this is about when it went up
          guildCache[professionId].orders[order.orderID] = entry
          guildCache[professionId].lastUpdate = now
          changed = true
          added = added + 1
        elseif existing.isDone ~= isDone then
          existing.isDone = isDone
          existing.updated = now -- also turns a full scan entry into a customer entry
          guildCache[professionId].lastUpdate = now
          changed = true
          tagged = tagged + 1
        end
      end
    end
    ns.Debug.print("my orders scan: %s total, %s added, %s done changed", #orders, added, tagged)
    if changed then
      ns.communication.SendCraftingOrders()
      onCacheChanged()
    end
  end

  local function requestMyOrders(offset)
    C_CraftingOrders.ListMyOrders({
      primarySort   = { sortType = Enum.CraftingOrderSortType.TimeRemaining, reversed = false },
      secondarySort = { sortType = Enum.CraftingOrderSortType.ItemName,      reversed = false },
      offset = offset,
      callback = C_FunctionContainers.CreateCallback(function(result, expectMoreRows)
        if result ~= Enum.CraftingOrderResult.Ok then return end
        -- GetMyOrders returns everything loaded so far, next page starts at its length (same as blizz MyOrders page)
        local orders = C_CraftingOrders.GetMyOrders()
        if expectMoreRows then
          requestMyOrders(#orders)
          return
        end
        addMyOrdersToCache(orders)
      end),
    })
  end
  local function scanMyOrders()
    if not IsInGuild() then return end
    ns.Debug.print("my orders scan: started")
    requestMyOrders(0)
  end
  function ns.randomThings.craftingOrders.CRAFTINGORDERS_SHOW_CUSTOMER()
    scanMyOrders()
  end
  function ns.randomThings.craftingOrders.CRAFTINGORDERS_ORDER_CANCEL_RESPONSE(result)
    if result ~= Enum.CraftingOrderResult.Ok then return end
    scanMyOrders()
  end
  function ns.randomThings.craftingOrders.CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE(result)
    if not IsInGuild() then return end
    if result ~= Enum.CraftingOrderResult.Ok then return end -- 0 == Success
    scanMyOrders()
    if not lastOrder then return end
    if (lastOrder.placed or 0) + 5 < GetTime() then return end
    if lastOrder.data.orderType == Enum.CraftingOrderType.Public then return end
  end
  local professionsWeCareAbout = {
    Enum.Profession.Alchemy,
    Enum.Profession.Blacksmithing,
    Enum.Profession.Enchanting,
    Enum.Profession.Engineering,
    Enum.Profession.Inscription,
    Enum.Profession.Jewelcrafting,
    Enum.Profession.Leatherworking,
    Enum.Profession.Tailoring,
  }
  -- crafter side: a full scan replaces the profession's orders, anything missing got fulfilled/cancelled/expired
  ---@param professionId number
  ---@param orders CraftingOrderInfo[]
  local function storeCrafterScan(professionId, orders)
    local guildCache = ns.randomThings.craftingOrders.GetGuildCache(true)
    if not guildCache then return end
    local now = GetServerTime()
    local t = {}
    local stored, done = 0, 0
    local previousOrders = guildCache[professionId] and guildCache[professionId].orders or {}
    for _, order in ipairs(orders) do
      if order.orderType == Enum.CraftingOrderType.Guild and order.customerGuid and order.expirationTime > now then
        local entry = {
          customerGuid = ns.mapping.ConvertGuidToMsgFormat(order.customerGuid),
          expirationTime = order.expirationTime,
          itemId = order.itemID,
          isRecraft = order.isRecraft or nil,
          isDone = not activeStates[order.orderState] or nil,
          tip = toTipGold(order.tipAmount),
        }
        -- a rescan replaces the entries, keep when the order was first seen
        local previous = previousOrders[order.orderID]
        if previous and previous.seen then
          entry.seen = previous.seen
        else
          setFirstSeen(entry, now)
        end
        t[order.orderID] = entry
        stored = stored + 1
        if not activeStates[order.orderState] then done = done + 1 end
      end
    end
    ns.Debug.print("crafter scan: prof %s, %s returned, %s stored, %s done", professionId, #orders, stored, done)
    local scanned = { lastScan = now, lastUpdate = now, orders = t }
    notifyNewOrders(professionId, guildCache[professionId], scanned)
    guildCache[professionId] = scanned
    ns.communication.SendCraftingOrders()
    onCacheChanged()
  end

  ---@param professionId number
  ---@param offset number
  local function requestGuildCrafterOrders(professionId, offset)
    C_CraftingOrders.RequestCrafterOrders({
      orderType = Enum.CraftingOrderType.Guild,
      searchFavorites = false,
      initialNonPublicSearch = false,
      primarySort = { sortType = Enum.CraftingOrderSortType.TimeRemaining, reversed = false },
      secondarySort = { sortType = Enum.CraftingOrderSortType.ItemName, reversed = false },
      forCrafter = true,
      offset = offset,
      profession = professionId,
      callback = C_FunctionContainers.CreateCallback(function(result, orderType, displayBuckets, expectMoreRows)
        if result ~= Enum.CraftingOrderResult.Ok then return end
        if orderType ~= Enum.CraftingOrderType.Guild or displayBuckets then return end
        -- same as blizz crafter page, GetCrafterOrders returns everything loaded so far
        local orders = C_CraftingOrders.GetCrafterOrders()
        if expectMoreRows then
          requestGuildCrafterOrders(professionId, #orders)
          return
        end
        storeCrafterScan(professionId, orders)
      end),
    })
  end

  ---only primary professions matter here, guild orders don't exist for the secondary ones
  ---@return table<number, boolean> Enum.Profession -> true
  local function getKnownProfessions()
    local known = {}
    local prof1, prof2 = GetProfessions()
    for _, index in pairs({ prof1, prof2 }) do -- pairs, either one can be nil
      local skillLine = select(7, GetProfessionInfo(index))
      local info = skillLine and C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLine)
      if info and info.profession then
        known[info.profession] = true
      end
    end
    return known
  end

  local lastCrafterScan = {}
  function ns.randomThings.craftingOrders.CRAFTINGORDERS_UPDATE_ORDER_COUNT(orderType, orderCount)
    if orderType ~= Enum.CraftingOrderType.Guild then return end
    if not IsInGuild() then return end
    -- several crafting tables can be in range in a hub, only scan one we can actually craft at. a scan for a
    -- profession we don't have could come back empty and wipe that profession's orders for the whole guild
    local known = getKnownProfessions()
    local professionId
    for _,pId in pairs(professionsWeCareAbout) do
      if known[pId] and C_TradeSkillUI.IsNearProfessionSpellFocus(pId) then
        professionId = pId
        break
      end
    end
    if not professionId then return end
    -- our own request can fire UPDATE_ORDER_COUNT again, throttle so it can't loop
    if GetTime() - (lastCrafterScan[professionId] or 0) < 30 then return end
    lastCrafterScan[professionId] = GetTime()
    ns.Debug.print("crafter scan: started, prof %s", professionId)
    requestGuildCrafterOrders(professionId, 0)
  end
end

if ns.IsRetail then -- dungeons done
  ns.randomThings.dungeonsDone = {}
  function ns.randomThings.dungeonsDone.CHALLENGE_MODE_MAPS_UPDATE(...)
    local t = C_MythicPlus.GetRunHistory(true, true)
    local temp = {}
    for _, v in pairs(t) do
        temp[v.level] = (temp[v.level] or 0) + 1
    end
    ns.Debug.AddToDevTool(temp, "WowUtils:DungeonsDone")
    ns.database.SaveToCurrentCharacterDB(ns.enums.context.dungeonsDone, nil, temp)
  end
end

if ns.IsForever then -- loot tracking
  ns.randomThings.lootWindows = {}
  function ns.randomThings.lootWindows.LOOT_READY(autoLoot)
    local newGuids = {}
    for slot = 1, GetNumLootItems() do
      local sourceData = { GetLootSourceInfo(slot) }
      local lootIcon, lootName, lootQuantity, currencyID, lootQuality, locked, isQuestItem, questID, isActive, isCoin = GetLootSlotInfo(slot)
      if not isCoin then
        local lootData = {
          currencyId = currencyID,
          questId = questID,
          itemLink = GetLootSlotLink(slot)
        }
        for j = 1, #sourceData, 2 do
          local _t = CopyTable(lootData)
          _t.count = sourceData[j + 1] or 1
          local sourceGuid = sourceData[j]
          if not issecretvalue(sourceGuid) then
            if not WowUtilsDB.localData.lootWindows[sourceGuid] then
              newGuids[sourceGuid] = true
              WowUtilsDB.localData.lootWindows[sourceGuid] = {
                seen = GetServerTime(),
                characterGuid = ns.me.guid,
                items = {}
              }
            end
            if newGuids[sourceGuid] then
              tinsert(WowUtilsDB.localData.lootWindows[sourceGuid].items, _t)
            end
          else
            ns.Debug.print("Loot source guid was secret.")
          end
        end
      end
    end
  end
end