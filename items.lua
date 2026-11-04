---@class wowutilsPrivate
---@field items wowutils_items

---@type string, wowutilsPrivate
local addon_name, ns = ...

---@class wowutils_items
ns.items = {}
local private = {}
function ns.items.CacheWatermarks()
  local t = {}
  for slotName, slot in pairs(Enum.ItemRedundancySlot) do
    local crestDiscountItemLevel, valorstoneDiscountItemLevel = C_ItemUpgrade.GetHighWatermarkForSlot(slot)
    t[slot] = crestDiscountItemLevel
  end
  ns.database.SaveToCurrentCharacterDB(ns.enums.context.watermarks, nil, t)
end

function ns.items.CacheCraftingItems()
  local craftingItems = C_Item.GetItemCount(ns.config.items.craftingItems, true, nil, true) or 0
  ns.database.SaveToCurrentCharacterDB(ns.enums.context.craftingItems, nil, craftingItems)
end
local cachedPopup = {}
function ns.items.CacheBonusRollPopup(spellID, effectValue, message, duration, currencyTypesID, currencyCost, currentDifficulty, displayItemID, itemContext, treasureContextLevel)
  if currencyTypesID ~= 3418 then return end -- Nebulous Voidcore
  ns.Debug.print("Caching bonus roll popup data")
  local _, encounterId = GetJournalInfoForSpellConfirmation(spellID)
  local _, _, dif, _, _, _, _, instanceID, _, _, hasWorldTier = GetInstanceInfo()
  cachedPopup = {
    expirationTime = GetTime() + (duration or 5),
    startTime = GetTime(),
    encounterId = encounterId or 0,
    difId = dif,
    instanceId = instanceID,
  }
end
function ns.items.CacheBonusRollResult(typeIdentifier, itemLink, quantity, specID, sex, personalLootToast, currencyID, isSecondaryResult, corrupted)
  ns.Debug.print("Bonus coin used")
  if ns.currency.lastBonusCoinUsed + 1 <= GetTime() then return end -- not actual bonus coin
  local hasValidCacheData = (cachedPopup.expirationTime or 0) + 5 > GetTime()
  ns.Debug.print("Saving bonus coin - hasValidCacheData '%s'", hasValidCacheData)
  ns.database.SaveToCurrentCharacterDB(ns.enums.context.bonusCoin, nil, {
    difId = hasValidCacheData and cachedPopup.difId or 0,
    itemLink = itemLink or "",
    encounterId = hasValidCacheData and cachedPopup.encounterId or 0,
    receiveTime = GetServerTime(),
    specId = specID or 0,
    season = C_MythicPlus.GetCurrentSeason(),
    instanceId = hasValidCacheData and cachedPopup.instanceId or 0,
  })
end
do
  -- placeholders (%s or %1$s) out of the way before escaping
  local tradeTimeRemainingPattern = "^" .. BIND_TRADE_TIME_REMAINING:gsub("%%%d*%$?s", "\001"):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("\001", ".+")
  function ns.items.IsTradeableItem(guid)
    local d = C_TooltipInfo.GetItemByGUID(guid)
    if not d then return false end
    if not d.lines then return false end
    for _, lineData in pairs(d.lines) do
      if lineData.leftText then
        if lineData.leftText and lineData.leftText:match(tradeTimeRemainingPattern) then
          return true
        end
      end
    end
    return false
  end
end
---@class wowutils_scannedItem
---@field itemLink string
---@field equipped number?
---@field warbound boolean?

---@type table<wowutils_enums_itemCacheType, table<string, wowutils_scannedItem>> -- string = itemGuid, only kept while scanning, saved through saveItemsIfChanged
local tempItemCache = {
  [ns.enums.itemCacheType.equipped] = {},
  [ns.enums.itemCacheType.bags] = {},
  [ns.enums.itemCacheType.bank] = {},
  [ns.enums.itemCacheType.warbank] = {}
}
local function isLegitWarboundItem(itemLocation)
    return C_Item.IsBoundToAccountUntilEquip(itemLocation) and not C_Item.IsBound(itemLocation)
end
local function handleItemOnLoad(item, target, itemLink, instantItemData)
  -- the slot can change while the item loads (sorted, sold, swapped), there's nothing left to read then
  if item:IsItemEmpty() then return end
  --if item:GetItemQuality() ~= Enum.ItemQuality.Epic and target ~= "equipment" then
  --some sections only care about epic items
  local isEpicItem = item:GetItemQuality() == Enum.ItemQuality.Epic
  local itemLevel = item:GetCurrentItemLevel()
  local isLowItemLevel = (itemLevel or 0) < ns.config.itemCacheMinIlvl
  local potentialIgnore = isLowItemLevel or not isEpicItem
  local cache = tempItemCache[target]
  if target == ns.enums.itemCacheType.warbank then
    if true then return end -- left here so its easy to enable once we want it
    if potentialIgnore then return end
    if not C_Item.IsBoundToAccountUntilEquip(item:GetItemLocation()) then return end
    cache[item:GetItemGUID()] = {
      itemLink = itemLink,
      warbound = true,
    }
    return
  end
  if target == ns.enums.itemCacheType.bank then
    local warbound = isLegitWarboundItem(item:GetItemLocation())
    if potentialIgnore then return end
    if not (warbound or (C_Item.IsBound(item:GetItemLocation()) and not ns.items.IsTradeableItem(item:GetItemGUID()))) then return end
    cache[item:GetItemGUID()] = {
      itemLink = itemLink,
      warbound = warbound == true or nil,
    }
    return
  end
  if target == ns.enums.itemCacheType.equipped then
    local slot = itemLink
    local itemlevel = item:GetCurrentItemLevel()
    local itemID, _, _, equipLoc, _, itemTypeID, itemSubTypeID = C_Item.GetItemInfoInstant(item:GetItemID())
    if equipLoc == "INVTYPE_PROFESSION_GEAR" or equipLoc == "INVTYPE_PROFESSION_TOOL" then return end
    cache[item:GetItemGUID()] = {
      itemLink = item:GetItemLink(),
      equipped = slot,
    }
    return
  end
  if target == ns.enums.itemCacheType.bags then
    local warbound = isLegitWarboundItem(item:GetItemLocation())
    if potentialIgnore then return end
    if not (warbound or (C_Item.IsBound(item:GetItemLocation()) and not ns.items.IsTradeableItem(item:GetItemGUID()))) then return end
    cache[item:GetItemGUID()] = {
      itemLink = itemLink,
      warbound = warbound == true or nil,
    }
    return
  end
end
local scannedItems = {} -- reused between scans, only copied when something changed
---converts the guid keyed scan cache to the saved format and passes it forward only if something changed
---@param target wowutils_enums_itemCacheType
local function saveItemsIfChanged(target)
  local isEquipped = target == ns.enums.itemCacheType.equipped
  wipe(scannedItems)
  for _, v in pairs(tempItemCache[target]) do
    if isEquipped then
      scannedItems[v.equipped] = ns.mapping.itemLink.ToValue(v.itemLink)
    else
      scannedItems[#scannedItems + 1] = (v.warbound and "W" or "") .. ns.mapping.itemLink.ToValue(v.itemLink)
    end
  end
  if not isEquipped then table.sort(scannedItems) end -- items load in random order, sort so the same items always compare equal
  local charDB = ns.database.GetCurrentCharDB()
  local saved = charDB.itemCache2 and charDB.itemCache2[target]
  if saved then
    local changed = false
    if isEquipped then -- slots are a fixed range, so one pass covers items added, removed and changed
      for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        if scannedItems[slot] ~= saved[slot] then
          changed = true
          break
        end
      end
    elseif #scannedItems ~= #saved then
      changed = true
    else -- both sorted and same length
      for i = 1, #scannedItems do
        if scannedItems[i] ~= saved[i] then
          changed = true
          break
        end
      end
    end
    if not changed then return end
  end
  ns.database.SaveToCurrentCharacterDB(ns.enums.context.itemCache, target, CopyTable(scannedItems))
end

do
  local function clearSlot(slot)
    for k,v in pairs(tempItemCache[ns.enums.itemCacheType.equipped]) do
      if v.equipped == slot then
        tempItemCache[ns.enums.itemCacheType.equipped][k] = nil
        saveItemsIfChanged(ns.enums.itemCacheType.equipped)
        return
      end
    end
  end
  function ns.items.PLAYER_EQUIPMENT_CHANGED(slot, isEmpty)
    if ns.InLoadingScreen then -- equipment slots can report as empty mid loading screen, rescan everything once it ends
      ns.DealAfterLoadingScreen("ns.items.PLAYER_EQUIPMENT_CHANGED", function()
        ns.items.PLAYER_EQUIPMENT_CHANGED(slot, isEmpty)
      end)
      return
    end
    clearSlot(slot)
    if isEmpty then return end
    local item = Item:CreateFromEquipmentSlot(slot)
    if item:IsItemEmpty() then return end
    item:ContinueOnItemLoad(function()
      handleItemOnLoad(item, ns.enums.itemCacheType.equipped, slot)
      saveItemsIfChanged(ns.enums.itemCacheType.equipped)
    end)
    ns.items.CacheWatermarks()
  end
end
do
  --local warbankTabs = {Enum.BagIndex.AccountBankTab_1, Enum.BagIndex.AccountBankTab_2, Enum.BagIndex.AccountBankTab_3, Enum.BagIndex.AccountBankTab_4, Enum.BagIndex.AccountBankTab_5}
  local bankTabs = { Enum.BagIndex.CharacterBankTab_1, Enum.BagIndex.CharacterBankTab_2, Enum.BagIndex.CharacterBankTab_3, Enum.BagIndex.CharacterBankTab_4, Enum.BagIndex.CharacterBankTab_5, Enum.BagIndex.CharacterBankTab_6 }
  local bankTimer
  function private.ScanBank()
    if not C_Bank.CanViewBank(Enum.BankType.Character) then return end
    wipe(tempItemCache[ns.enums.itemCacheType.bank])
    for _, bagID in pairs(bankTabs) do
      for invID = 1, C_Container.GetContainerNumSlots(bagID) do
        -- this is faster than creating item
        local itemLink = C_Container.GetContainerItemLink(bagID, invID)
        if itemLink then
          local instantItemData = { C_Item.GetItemInfoInstant(itemLink) }
          if instantItemData[6] == Enum.ItemClass.Weapon or instantItemData[6] == Enum.ItemClass.Armor then
            local item = Item:CreateFromBagAndSlot(bagID, invID)
            if not item:IsItemEmpty() then
              item:ContinueOnItemLoad(function() handleItemOnLoad(item, ns.enums.itemCacheType.bank, itemLink, instantItemData) end)
            end
          end
        end
      end
    end
    if bankTimer then bankTimer:Cancel() end
    -- give 2s leeway to caching items before redirecting it forward
    bankTimer = C_Timer.NewTimer(2, function()
      saveItemsIfChanged(ns.enums.itemCacheType.bank)
    end)
  end
end
do
  local normalBags = { Enum.BagIndex.Backpack, Enum.BagIndex.Bag_1, Enum.BagIndex.Bag_2, Enum.BagIndex.Bag_3, Enum.BagIndex.Bag_4, Enum.BagIndex.ReagentBag }
  local bagTimer
  function private.ScanBags()
    if InCombatLockdown() then -- we don't wanna do any caching during combat, just do it after combat ends
      private.scanBagsAfterCombat = true
      return
    end
    if ns.InLoadingScreen then
      ns.DealAfterLoadingScreen("private.ScanBags", private.ScanBags)
      return
    end
    private.scanBagsAfterCombat = false
    wipe(tempItemCache[ns.enums.itemCacheType.bags])
    for _, bagID in pairs(normalBags) do
      for invID = 1, C_Container.GetContainerNumSlots(bagID) do
        -- this is faster than creating item
        local itemLink = C_Container.GetContainerItemLink(bagID, invID)
        if itemLink then
          local instantItemData = { C_Item.GetItemInfoInstant(itemLink) }
          if instantItemData[6] == Enum.ItemClass.Weapon or instantItemData[6] == Enum.ItemClass.Armor then
            local item = Item:CreateFromBagAndSlot(bagID, invID)
            if not item:IsItemEmpty() then
              item:ContinueOnItemLoad(function() handleItemOnLoad(item, ns.enums.itemCacheType.bags, itemLink, instantItemData) end)
            end
          end
        end
      end
    end
    if bagTimer then bagTimer:Cancel() end
    -- give 2s leeway to caching items before redirecting it forward
    bagTimer = C_Timer.NewTimer(2, function()
      saveItemsIfChanged(ns.enums.itemCacheType.bags)
    end)
    -- in case we changed bank items, this function is checking if we can actually view bank or not
    private.ScanBank()
  end
end
do
  local scanTimer
  function ns.items.BAG_UPDATE_DELAYED(...)
    ns.items.CacheCraftingItems()
    if scanTimer then scanTimer:Cancel() end
    scanTimer = C_Timer.NewTimer(0.2, function()
      private.ScanBags()
    end)
  end
end
function ns.items.PLAYER_REGEN_ENABLED(...)
  if not private.scanBagsAfterCombat then return end
  private.ScanBags()
end
do
  local fullscanTimer
  function private.ScanAllEquippedItems()
    if ns.InLoadingScreen then
      ns.DealAfterLoadingScreen("private.ScanAllEquippedItems()", private.ScanAllEquippedItems)
      return
    end
    wipe(tempItemCache[ns.enums.itemCacheType.equipped])
    for _, slot in pairs({ INVSLOT_HEAD, INVSLOT_NECK, INVSLOT_SHOULDER, INVSLOT_CHEST, INVSLOT_WAIST, INVSLOT_LEGS, INVSLOT_FEET, INVSLOT_WRIST, INVSLOT_HAND, INVSLOT_FINGER1, INVSLOT_FINGER2, INVSLOT_TRINKET1, INVSLOT_TRINKET2, INVSLOT_BACK, INVSLOT_MAINHAND, INVSLOT_OFFHAND }) do
      local item = Item:CreateFromEquipmentSlot(slot)
      if not item:IsItemEmpty() then
        item:ContinueOnItemLoad(function() handleItemOnLoad(item, ns.enums.itemCacheType.equipped, slot) end)
      end
    end
    if fullscanTimer then fullscanTimer:Cancel() end
    -- give 2s leeway to caching items before redirecting it forward
    fullscanTimer = C_Timer.NewTimer(2, function()
      saveItemsIfChanged(ns.enums.itemCacheType.equipped)
    end)
    ns.items.CacheWatermarks()
  end
end

function ns.items.InitialCaching()
  if ns.InLoadingScreen then
    ns.DealAfterLoadingScreen("ns.items.InitialCaching()", ns.items.InitialCaching)
    return
  end
  private.ScanBags()
  private.ScanAllEquippedItems()
  ns.items.CacheCraftingItems()
end

do
  ---@diagnostic disable-next-line: undefined-global
  local warboundUntilEquipText = ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP -- "Binds to Warband until equipped" still shows Binds to Warband on itemtooltip itself??
  ---@param itemlink string
  ---@return boolean
  function ns.items.IsWarboundItem(itemlink)
    if not (itemlink and warboundUntilEquipText) then return false end
    local d = C_TooltipInfo.GetHyperlink(itemlink)
    if not (d and d.lines) then return false end
    for _, lineData in ipairs(d.lines) do
      if lineData.type == Enum.TooltipDataLineType.ItemBinding then
        return lineData.leftText == warboundUntilEquipText
      end
    end
    return false
  end
  function ns.items.CHAT_MSG_LOOT(text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, suppressRaidIcons)
    if issecretvalue(text) then return end
    local isSelf = guid == ns.me.guid
    if WowUtilsDB.options.warboundOptions.selfOnly and not isSelf then return end
    -- color part can be either old style hex (|cffa335ee) or quality name (|cnIQ4:), so just grab whatever is before |H
    local itemlink = text:match("|c[^|]*|Hitem:.-|h|r") or text:match("|Hitem:.-|h.-|h")
    if not itemlink then return end
    if not ns.items.IsWarboundItem(itemlink) then return end
    local name = isSelf and "YOU" or Ambiguate(playerName or UNKNOWN, "short")
    local _, classFile = GetPlayerInfoByGUID(guid or "")
    local classColor = classFile and C_ClassColor.GetClassColor(classFile)
    if classColor then
      name = classColor:WrapTextInColorCode(name)
    end
    local item = Item:CreateFromItemLink(itemlink)
    -- quality and name need item data, usually cached already since it was just in chat
    item:ContinueOnItemLoad(function()
      local _, _, _, qualityHex = C_Item.GetItemQualityColor(item:GetItemQuality() or Enum.ItemQuality.Common)
      ns.notifications.AddMessage(string.format("Warbound: %s - |T%s:0|t |c%s[%s]|r", name, item:GetItemIcon() or 134400, qualityHex, item:GetItemName() or UNKNOWN))
    end)
  end
end

-- TODO bonus coin history based on tooltips (tooltips are not working atm ingame at all)

do -- item -> journal encounter lookup, scanned from the encounter journal after login
  -- journal selection and loot filters are global state the EJ ui reads too, so every step selects what it needs,
  -- reads a few items and puts everything back before yielding. steps are skipped while the journal is open or in combat
  local itemsPerStep = 10
  ---@type table<number, number> itemId = journal encounterId, same id space as wowutils_bonusCoinUsage.encounterId
  local itemEncounters = {}
  local scanDone = false

  local function saveJournalState()
    local classId, specId = EJ_GetLootFilter()
    return {
      tier = EJ_GetCurrentTier(),
      classId = classId,
      specId = specId,
      slotFilter = C_EncounterJournal.GetSlotFilter(),
      difficultyId = EJ_GetDifficulty(),
    }
  end

  local function restoreJournalState(state)
    EJ_SelectTier(state.tier)
    EJ_SetLootFilter(state.classId, state.specId)
    C_EncounterJournal.SetSlotFilter(state.slotFilter)
    -- the EJ ui remembers what it was showing, select that back so it doesn't open into our raid
    local ej = EncounterJournal
    if ej and ej.instanceID then
      EJ_SelectInstance(ej.instanceID)
      if ej.encounterID then
        EJ_SelectEncounter(ej.encounterID)
      end
    end
    if state.difficultyId and EJ_IsValidInstanceDifficulty(state.difficultyId) then
      EJ_SetDifficulty(state.difficultyId)
    end
  end

  -- config raids are keyed by instance map id, the journal wants its own instance id
  ---@return number[] journalInstanceIds
  local function getJournalInstances()
    local wanted, missing = {}, 0
    for _, raid in ipairs(ns.config.lockouts.raids) do
      wanted[raid.instanceId] = true
      missing = missing + 1
    end
    local found = {}
    local state = saveJournalState()
    for tier = EJ_GetNumTiers(), 1, -1 do
      EJ_SelectTier(tier)
      local index = 1
      local journalInstanceId = EJ_GetInstanceByIndex(index, true)
      while journalInstanceId do
        local mapId = select(11, EJ_GetInstanceByIndex(index, true))
        if wanted[mapId] then
          wanted[mapId] = nil
          missing = missing - 1
          tinsert(found, journalInstanceId)
        end
        index = index + 1
        journalInstanceId = EJ_GetInstanceByIndex(index, true)
      end
      if missing == 0 then break end
    end
    restoreJournalState(state)
    if missing > 0 then
      ns.Debug.print("encounter loot scan: %d raid(s) from config not found in the journal", missing)
    end
    return found
  end

  ---@param journalInstanceId number
  ---@return boolean gotLoot
  local function scanInstance(journalInstanceId)
    local index, numLoot = 1, 0
    repeat
      local state = saveJournalState()
      EJ_SelectInstance(journalInstanceId) -- no encounter selected = loot for the whole instance, each entry tagged with its encounter
      EJ_SetDifficulty(ns.enums.difficultyId.RaidMythic) -- item ids are shared across difficulties, mythic lists the most
      EJ_SetLootFilter(0, 0)
      C_EncounterJournal.SetSlotFilter(Enum.ItemSlotFilterType.NoFilter)
      numLoot = EJ_GetNumLoot()
      local last = math.min(index + itemsPerStep - 1, numLoot)
      for i = index, last do
        local info = C_EncounterJournal.GetLootInfoByIndex(i)
        if info and info.itemID and info.encounterID then
          itemEncounters[info.itemID] = itemEncounters[info.itemID] or info.encounterID
        end
      end
      index = last + 1
      restoreJournalState(state)
      coroutine.yield()
    until index > numLoot
    return numLoot > 0
  end

  local function scan()
    local pending = getJournalInstances()
    -- the journal can come back empty for a raid early on, give those a few more tries before calling it done
    for _ = 1, 3 do
      local retry = {}
      for _, journalInstanceId in ipairs(pending) do
        coroutine.yield()
        if not scanInstance(journalInstanceId) then
          tinsert(retry, journalInstanceId)
        end
      end
      if #retry == 0 then return end
      pending = retry
      for _ = 1, 50 do coroutine.yield() end -- ~5s at the 0.1s ticker
    end
    ns.Debug.print("encounter loot scan: %d raid(s) never returned any loot", #pending)
  end

  function ns.items.StartEncounterLootScan()
    if scanDone then return end
    local co = coroutine.create(scan)
    local ticker
    ticker = C_Timer.NewTicker(0.1, function()
      if InCombatLockdown() or (EncounterJournal and EncounterJournal:IsShown()) then return end
      local ok, err = coroutine.resume(co)
      if not ok then
        ticker:Cancel()
        geterrorhandler()(err)
      elseif coroutine.status(co) == "dead" then
        ticker:Cancel()
        scanDone = true
        ns.Debug.print("encounter loot scan done, %d items", CountTable(itemEncounters))
      end
    end)
  end

  ---@param itemId number
  ---@return number? journalEncounterId nil when the item isn't from a scanned raid or the scan hasn't finished yet
  function ns.items.GetItemEncounterId(itemId)
    return itemEncounters[itemId]
  end
end