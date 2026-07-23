---@class wowutilsPrivate
---@field config wowutils_config
---@field me wowutils_selfInfo
---@field region number
---@field logoFile string
---@field debugMode boolean
---@field hasDataAddon boolean

---@type string, wowutilsPrivate
local addon_name, ns = ...
ns.region = GetCurrentRegion()
ns.logoFile = [[Interface\AddOns\wowutils\media\logo.png]]
ns.debugMode = WowUtilsDB and WowUtilsDB.debug
---@diagnostic disable-next-line: undefined-global
ns.hasDataAddon = WowUtilsPublicDataAPI and true or false
---@class wowutils_config
ns.config = {
  timestampOffset = 1767225600, -- 	01/01/26 00:00:00 UTC
  currentDBVersion = 1,
  configVersion = 1,
  watermarks = {
    startingPoint = 250,
    multiplier = 50,
  },
  currencies = { -- Cached on login and CURRENCY_DISPLAY_UPDATE
    -- Crests
    [3341] = 1, -- Veteran
    [3343] = 2, -- Champion
    [3345] = 3, -- Hero
    [3347] = 4, -- Mythic

    -- Conversion
    [3378] = 5,
  },
  items = { -- Cached on login and BAG_UPDATE_DELAYED
    craftingItems = 232875, -- Spark of Radiance
  },
  quests = {
    --[93695] = {  -- for testing purposes, lw quest
      --isWeeklyQuest = true,
    --},
    [95155] = {}, -- Nulleus ??, could actually be 95154
    [92600] = {}, -- Cracked Keystone (Midnight S1?)
    [96410] = {}, -- Seeking Knowledge Week 1 of 5: The Omnium Folio
    [96441] = {}, -- Seeking Knowledge Week 2 of 5: Ritualized Arcana
    [96442] = {}, -- Seeking Knowledge Week 3 of 5: Ley Line Assaults
    [96443] = {}, -- Seeking Knowledge Week 4 of 5: Magical Primessence
    [96444] = {}, -- Seeking Knowledge Week 5 of 5: Off-World Magic
  }
}

local guid = UnitGUID('player')

---@class wowUtils_guildInfo
---@field name string
---@field realm string
---@field fullSlug string
---@field dbSlug string

---@class wowutils_selfInfo
---@field guildInfo wowUtils_guildInfo?
---@field serverSlug string?
---@field regionId number
---@field realmId number
---@field droptimizerKey string
ns.me = {
  guid = guid,
  name = UnitName('player'),
  ---@diagnostic disable-next-line: need-check-nil
  partialGuid = (guid:gsub("Player%-", "", 1)),
  regionId = GetCurrentRegion(),
  realmId = GetRealmID(),
  droptimizerKey = string.format("%s-%s", (UnitName('player'):lower()), GetRealmID()),
}