---@class wowutilsPrivate
---@field items wowutils_items

---@type string, wowutilsPrivate
local addon_name, ns = ...

---@class wowutils_items
ns.items = {}
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
  local hasValidCacheData = (cachedPopup.expirationTime or 0) + 5 > GetTime() and (cachedPopup.startTime) > GetTime()
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

-- TODO bonus coin history based on tooltips