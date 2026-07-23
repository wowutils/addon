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
  ns.Debug.print("checking crafting items")
  local craftingItems = C_Item.GetItemCount(ns.config.items.craftingItems, true, nil, true) or 0
  ns.database.SaveToCurrentCharacterDB(ns.enums.context.craftingItems, nil, craftingItems)
end