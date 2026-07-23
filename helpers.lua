---@class wowutilsPrivate
---@field helpers wowutils_helpers

---@type string, wowutilsPrivate
local addon_name, ns = ...
local sformat = string.format
---@class wowutils_helpers
ns.helpers = {}

do
  --local timeFormat  = sformat("%s%%s", CreateAtlasMarkup("questlog-questtypeicon-clockyellow"))
  local timeFormat = sformat("%s %%s%%s", CreateAtlasMarkup("clock-icon"))

  ---@param unixTimestamp number
  ---@return string
  function ns.helpers.GetFormatedLastUpdateTime(unixTimestamp)
    if not unixTimestamp or unixTimestamp == 0 then
      return timeFormat:format("Never", "")
    end
    local difSeconds = GetServerTime() - unixTimestamp
    if difSeconds > 86400 then
      return timeFormat:format(Round(difSeconds / 86400), "d")
    elseif difSeconds > 3600 then
      return timeFormat:format(Round(difSeconds / 3600), "h")
    elseif difSeconds > 60 then
      return timeFormat:format(Round(difSeconds / 60), "m")
    end
    return timeFormat:format(difSeconds, "s")
  end
end

do
  local map = {
    ["12769"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_1
    ["12770"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_2
    ["12771"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_3
    ["12772"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_4
    ["12773"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_5
    ["12774"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_6
    ["12775"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_7
    ["12776"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_8

    ["12777"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_1
    ["12778"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_2
    ["12779"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_3
    ["12780"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_4
    ["12781"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_5
    ["12782"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_6
    ["12783"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_7
    ["12784"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_8

    ["12785"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_1
    ["12786"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_2
    ["12787"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_3
    ["12788"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_4
    ["12789"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_5
    ["12790"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_6
    ["12791"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_7
    ["12792"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_8

    ["12793"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_1
    ["12794"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_2
    ["12795"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_3
    ["12796"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_4
    ["12797"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_5
    ["12798"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_6
    ["12799"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_7
    ["12800"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_8
    ["13787"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_9 sporefused
    ["13653"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_10 voidforged

    ["12801"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_1
    ["12802"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_2
    ["12803"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_3
    ["12804"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_4
    ["12805"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_5
    ["12806"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_6
    ["12807"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_7
    ["12808"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_8
    ["13654"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_10 voidforged
    ["13786"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_9 sporefused
  }
  local contextToItemTrack = {
    ["raid-finder"] = ns.enums.itemTrack.veteran,
    ["raid-normal"] = ns.enums.itemTrack.champion,
    ["raid-heroic"] = ns.enums.itemTrack.hero,
    ["raid-mythic"] = ns.enums.itemTrack.myth,
    --challenge-mode-jackpot
    --challenge-mode
  }
  ---@param itemLink string
  ---@return wowutils_enums_itemTrack itemTrack
  function ns.helpers.GetItemTrack(itemLink) -- just use bonus ids so we don't have to worry about any weirdness between localizations and items that cannot be upgraded
    -- TODO optimize? probably cba
    local t = { strsplit(":", itemLink) }
    for k, v in pairs(t) do -- this should find all real drops
      if map[v] then
        return map[v]
      end
    end
    -- this should catch tooltips from encounter journal etc
    local _, context = C_Item.GetItemCreationContext(itemLink)
    -- just ignore the rest for now TODO maybe do something about it?
    return context and contextToItemTrack[context] or ns.enums.itemTrack.none
  end
end

function ns.helpers.spairs(t, order)
  -- collect the keys
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end

  -- if order function given, sort by it by passing the table and keys a, b,
  -- otherwise just sort the keys
  if order then
    table.sort(keys, function(a, b) return order(t, a, b) end)
  else
    table.sort(keys)
  end

  -- return the iterator function
  local i = 0
  return function()
    i = i + 1
    if keys[i] then
      return keys[i], t[keys[i]]
    end
  end
end

do
  local cache = {
    [""] = "|T134400:0|t"
  }
  ---@param specId number
  ---@return string textureStr
  function ns.helpers.GetIconTextureStringForSpecId(specId)
    if not specId then
      return cache[""]
    end
    if cache[specId] then return cache[specId] end
    local specIcon = select(4, GetSpecializationInfoForSpecID(specId))
    if not specIcon then return cache[""] end
    cache[specId] = sformat("|T%s:0|t", specIcon)
    return cache[specId]
  end
end
do
  local cache = {
    [""] = "|T134400:0|t"
  }

  ---@param class string|number
  ---@return string textureStr
  function ns.helpers.GetIconTextureStringForClass(class)
    if not class then
      return cache[""]
    end
    if cache[class] then return cache[class] end
    if type(class) == "number" then
      local _, classFileName = GetClassInfo(class)
      if not classFileName then
        cache[class] = cache[""]
        return cache[""]
      end
      cache[class] = sformat("|A:%s:0:0|a", "classicon-"..classFileName:lower())
      return cache[class]
    end
    cache[class] = sformat("|A:%s:0:0|a", "classicon-"..class:lower())
    return cache[class]
  end
end
do
  local needsConverting = {

    [INVSLOT_FINGER2] = INVSLOT_FINGER1,
    [INVSLOT_TRINKET2] = INVSLOT_TRINKET1,
  }
  ---@param slot number
  ---@return number universalSlot
  function ns.helpers.GetUniversalSlot(slot)
    return needsConverting[slot] or slot
  end
end