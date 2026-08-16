---@type string, wowutilsPrivate
local addon_name, ns = ...

local sformat, strsplit = string.format, strsplit
-- secret values blow up on compares, string ops and table indexing, so anything secret is rejected outright
local issecretvalue = issecretvalue or function() return false end

--[[----------------------------------------------------------------------------
  WowUtilsAPI - read only public API for other addons.

  Every getter takes a single identifier which may be any of:
    * a unitId          "player", "target", "raid7", "party2", ...
    * a player GUID     "Player-1234-0A1B2C3D"
    * a name/full slug  "Ironi", "Ironi-Stormreaver" (case insensitive)

  Everything returned is a deep COPY of our data, mutating it does nothing to
  the addons database.

  Getters return three values:
    1. the data
    2. refreshed - server time we last received that data point
    3. updated   - server time that data point last actually changed

  Both timestamps are 0 when we never got that far, and everything is nil when
  we have no data for the requested character or a secret value was passed in.
------------------------------------------------------------------------------]]

---@class WowUtilsPublicAPI
WowUtilsAPI = {}

---@param unit string
---@param toDroptimizerKey boolean? default to guids
---@return string?
local function convertToCorrectUnit(unit, toDroptimizerKey)
  if not unit or issecretvalue(unit) or type(unit) ~= "string" or unit == "" then return nil end
  local isGuid = unit:find("^Player%-")
  if toDroptimizerKey then
    if isGuid then
      -- try to fetch droptimizerKey from our db first
      local charInDB = WowUtilsDB.ownCharacters[unit] or WowUtilsDB.others[unit]
      if charInDB then
        return charInDB.droptimizerKey
      end
      local name, realm = select(6, GetPlayerInfoByGUID(unit))
      if not name then return nil end
      return sformat("%s-%s", name:lower(), (realm == nil or realm == "") and ns.me.realmId or ns.GetRealmId(nil, realm))
    end
    local name, realm = strsplit("-", unit)
    if realm then -- its in Name-Realm format
      return sformat("%s-%s", name:lower(), ns.GetRealmId(nil, realm))
    end
    -- its either unitId or name without realm, so this should work just fine
    name, realm = UnitNameUnmodified(Ambiguate(unit, "none"))
    if not name then return nil end -- assume its an unitid that we cant currently get data from (or someone supplied a name without realm that cannot be used as unitId)
    return sformat("%s-%s", name:lower(), (realm == nil or realm == "") and ns.me.realmId or ns.GetRealmId(nil, realm))
  end
  if isGuid then return unit end
  local guid = UnitGUID(Ambiguate(unit, "none"))
  if not guid or issecretvalue(guid) then return nil end
  return guid
end

---@param unit string unitId, guid, name or name-realm
---@return (wowutils_ownChar|wowutils_otherChar)? char reference, never hand this out directly
---@return string? guid
local function findChar(unit)
  local guid = convertToCorrectUnit(unit)
  if guid then
    local char = WowUtilsDB.ownCharacters[guid] or WowUtilsDB.others[guid]
    if char then return char, guid end
  end
  -- fall back to matching a name / name-realm against what we have stored
  local droptimizerKey = convertToCorrectUnit(unit, true)
  if not droptimizerKey then return nil end
  ---@type wowutils_ownChar|wowutils_otherChar?
  local best
  for _, db in ipairs({ WowUtilsDB.ownCharacters, WowUtilsDB.others }) do
    for charGuid, char in pairs(db) do
      if char.droptimizerKey == droptimizerKey then
        -- the same character can exist under several guids (rerolls/renames), keep the freshest
        if not best or (char.lastUpdate or 0) > (best.lastUpdate or 0) then
          best, guid = char, charGuid
        end
      end
    end
  end
  if best then return best, guid end
  return nil
end

---@param unit string unitId, guid, name, name-realm or a raw droptimizer key
---@return string? droptimizerKey the "name-realmId" key sims are stored under
local function findDroptimizerKey(unit)
  if not unit or issecretvalue(unit) or type(unit) ~= "string" then return nil end
  if WowUtilsDB.droptimizerData[unit] then return unit end -- already a key
  local char = findChar(unit)
  if char and char.droptimizerKey then return char.droptimizerKey end
  return convertToCorrectUnit(unit, true)
end

--#endregion

--#region data points

---Everything we have on a character, use the getters below for a single data point.
---@param unit string
---@return (wowutils_ownChar|wowutils_otherChar)? character copy
---@return number? refreshed lastUpdateReceived
---@return number? updated lastUpdate
function WowUtilsAPI.GetCharacterData(unit)
  if not unit or issecretvalue(unit) then return nil end
  local char = findChar(unit)
  if not char then return nil end
  return CopyTable(char), char.lastUpdateReceived or 0, char.lastUpdate or 0
end

---@param unit string
---@return table<number, wowutils_currencyData>? currency currencyId = { current, totalEarned }
---@return number? refreshed
---@return number? updated
function WowUtilsAPI.GetCurrency(unit)
  if not unit or issecretvalue(unit) then return nil end
  local char = findChar(unit)
  if not (char and char.currency) then return nil end
  return CopyTable(char.currency), ((char.dataRefreshTimes and char.dataRefreshTimes.currency) or 0), char.currencyUpdated or 0
end

---Crest discount item levels.
---@param unit string
---@return table<number, number>? watermarks Enum.ItemRedundancySlot = itemLevel
---@return number? refreshed
---@return number? updated
function WowUtilsAPI.GetWatermarks(unit)
  if not unit or issecretvalue(unit) then return nil end
  local char = findChar(unit)
  if not (char and char.watermarks) then return nil end
  return CopyTable(char.watermarks), ((char.dataRefreshTimes and char.dataRefreshTimes.watermarks) or 0), char.watermarksUpdated or 0
end

---Rewards currently sitting in the great vault, use GetWeeklyRewards for the unlocked slots.
---@param unit string
---@return wowutils_vaultData_items[]? vaultData
---@return number? refreshed
---@return number? updated
function WowUtilsAPI.GetVault(unit)
  if not unit or issecretvalue(unit) then return nil end
  local char = findChar(unit)
  if not (char and char.vaultData) then return nil end
  local refreshed = (char.dataRefreshTimes and char.dataRefreshTimes.vaultData) or 0
  return CopyTable(char.vaultData), refreshed, char.vaultDataLastUpdate or 0
end

---Unlocked vault slots only, "activityType-index" = itemLevel.
---@param unit string
---@return table<string, number>? weeklyRewards
---@return number? refreshed
---@return number? updated
function WowUtilsAPI.GetWeeklyRewards(unit)
  if not unit or issecretvalue(unit) then return nil end
  local char = findChar(unit)
  if not (char and char.weeklyRewards) then return nil end
  local refreshed = (char.dataRefreshTimes and char.dataRefreshTimes.weeklyRewards) or 0
  return CopyTable(char.weeklyRewards), refreshed, char.weeklyRewardsUpdate or 0
end

---@param unit string
---@return table<number, wowutils_quests>? quests questId = data
---@return number? refreshed
---@return number? updated
function WowUtilsAPI.GetQuests(unit)
  if not unit or issecretvalue(unit) then return nil end
  local char = findChar(unit)
  if not (char and char.quests) then return nil end
  local refreshed = (char.dataRefreshTimes and char.dataRefreshTimes.quests) or 0
  return CopyTable(char.quests), refreshed, char.questsUpdated or 0
end

---Amount of the tracked crafting item (spark) the character owns.
---@param unit string
---@return number? craftingItems
---@return number? refreshed
---@return number? updated
function WowUtilsAPI.GetCraftingItems(unit)
  if not unit or issecretvalue(unit) then return nil end
  local char = findChar(unit)
  if not char then return nil end
  local refreshed = (char.dataRefreshTimes and char.dataRefreshTimes.craftingItems) or 0
  return char.craftingItems or 0, refreshed, char.craftingItemsUpdated or 0
end

---Bonus rolls used this season.
---@param unit string
---@return wowutils_bonusCoinUsage[]? bonusCoinUsage
---@return number? refreshed always 0, bonus coin usage is not refresh tracked
---@return number? updated
function WowUtilsAPI.GetBonusCoinUsage(unit)
  if not unit or issecretvalue(unit) then return nil end
  local char = findChar(unit)
  if not char then return nil end
  return CopyTable(char.bonusCoinUsage or {}), 0, char.bonusCoinUsageUpdated or 0
end
---Imported droptimizer/sim data. Also accepts a raw droptimizer key ("name-realmId").
---@param unit string
---@return wowutilsDroptimizerData? droptimizerData
---@return number? refreshed always 0, imported data is not refresh tracked
---@return number? updated
function WowUtilsAPI.GetDroptimizers(unit)
  if not unit or issecretvalue(unit) then return nil end
  local key = findDroptimizerKey(unit)
  local data = key and WowUtilsDB.droptimizerData[key]
  if not data then return nil end
  return CopyTable(data), 0, data.lastUpdate or 0
end

---Imported wishlist. Also accepts a raw droptimizer key ("name-realmId").
---@param unit string
---@return table<string, wowutilsDroptimizerData_wishlistItem>? wishlist
---@return number? refreshed always 0, imported data is not refresh tracked
---@return number? updated
function WowUtilsAPI.GetWishlist(unit)
  if not unit or issecretvalue(unit) then return nil end
  local key = findDroptimizerKey(unit)
  local data = key and WowUtilsDB.droptimizerData[key]
  if not (data and data.wishlist) then return nil end
  return CopyTable(data.wishlist), 0, data.lastUpdate or 0
end

--#endregion
