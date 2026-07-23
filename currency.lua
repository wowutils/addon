---@class wowutilsPrivate
---@field currency wowutils_currency

---@type string, wowutilsPrivate
local addon_name, ns = ...

---@class wowutils_currency
ns.currency = {}
function ns.currency.CacheCurrency(currencyId)
  local ci = C_CurrencyInfo.GetCurrencyInfo(currencyId)
  local quantity = ci and ci.quantity or 0
  local totalEarned = ci and ci.totalEarned or 0
  ns.database.SaveToCurrentCharacterDB(ns.enums.context.currency, currencyId, {
    quantity = quantity,
    totalEarned = totalEarned,
  })
end
function ns.currency.CURRENCY_DISPLAY_UPDATE(currencyType, quantity, quantityChange, quantityGainSource, destroyReason)
  if not ns.config.currencies[currencyType] then return end
  ns.currency.CacheCurrency(currencyType)
end
