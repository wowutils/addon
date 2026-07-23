---@class wowutilsPrivate
---@field enums wowutils_enums

---@type string, wowutilsPrivate
local addon_name, ns = ...

---@class wowutils_enums
ns.enums = {
  ---@enum wowutils_enums_context
  context = {
    currency = "currency",
    item = "item",
    lastLogout = "lastLogout",
    watermarks = "watermarks",
    craftingItems = "craftingItems",
    characterInformation = "characterInformation",
    guildInfo = "guildInfo",
    serverSlugUpdate = "serverSlugUpdate",
    droptimizerData = "droptimizerData",
    updateCheck = "updateCheck",
    fullCharacterSync = "fullCharacterSync",
    fullCharacterSyncRequest = "fullCharacterSyncRequest",
    vaultData = "vaultData",
    weeklyRewards = "weeklyRewards",
    quests = "quests",
  },
  ---@enum wowutils_enums_addonMessageTypes
  addonMessagesTypes = {
    forLoot = "A",
    partialCharacterUpdate = "B",
    fullSync = "C",
    targetedSync = "D",
    updateCheckForDesktopAppUsers = "E",
    droptimizerData = "F",
    fullSyncRequest = "G",
    fullCharacterSyncRequest = "H",
    fullCharacterSync = "I",
    currencyUpdate = "J",
    watermarkUpdate = "K",
    craftingItemUpdate = "L",
  },
  ---@class wowutils_enums_chatChannels
  chatChannels = {
    guild = "guild",
    instance = "instance_chat",
    party = "party",
    raid = "raid",
  },
  ---@enum wowutils_enums_simTypes
  simTypes = {
    unknown = 0,
    raidbotDroptimizer = 1,
    qeLiveDroptimizer = 2,
  },
  ---@enum wowutils_enums_difficultyId
  difficultyId = {
    Unknown = 0,
    RaidMythic = 16,
    RaidHeroic = 15,
    RaidNormal = 14,
    RaidLFR = 17,
    RaidStory = 220,
    RaidTimewalking = 33,
    RaidTimewalkingLFR = 151,
    RaidMythicFlex = 233,
    DungeonMythic = 23,
    DungeonKeystone = 8,
    DungeonNormal = 1,
    DungeonHeroic = 2,
    DungeonTimewalking = 24,
    DungeonFollower = 205,
    Delves = 208,
    PvP = 34,
  },
  ---@enum wowutils_enums_itemTrack
  itemTrack = {
    none = 0,
    adventurer = 2,
    veteran = 3,
    champion = 4,
    hero = 5,
    myth = 6,
  }
}