---@class wowutilsPrivate
---@field events wowutils_events
---@field restrictedAddonMessages boolean
---@field InLoadingScreen boolean
---@field currentGuildSlugs table<string, boolean>

---@type string, wowutilsPrivate
local addon_name, ns = ...
ns.restrictedAddonMessages = false
ns.InLoadingScreen = true
---@class wowutils_events : table
ns.events = {
  eventFrame = CreateFrame("frame")
}
ns.currentGuildSlugs = {}
local private = {}
ns.events.eventFrame:SetScript("OnEvent", function(self, event, ...)
  ns.events[event](...)
end)

ns.events.eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
function ns.events.CURRENCY_DISPLAY_UPDATE(...)
  ns.currency.CURRENCY_DISPLAY_UPDATE(...)
end

ns.events.eventFrame:RegisterEvent("BONUS_ROLL_RESULT")
function ns.events.BONUS_ROLL_RESULT(...)
  ns.items.CacheBonusRollResult(...)
end
ns.events.eventFrame:RegisterEvent("SPELL_CONFIRMATION_PROMPT")
function ns.events.SPELL_CONFIRMATION_PROMPT(...)
  ns.items.CacheBonusRollPopup(...)
end
ns.events.eventFrame:RegisterEvent("PLAYER_LOGIN")
function ns.events.PLAYER_LOGIN(...)
  ns.items.CacheWatermarks()
  for currencyId, mapId in pairs(ns.config.currencies) do
    ns.currency.CacheCurrency(currencyId)
  end
  C_Timer.After(10, ns.items.CacheCraftingItems)
  ns.me.serverSlug = GetNormalizedRealmName()
  ns.events.PLAYER_GUILD_UPDATE("player")
  private.checkForWeeklyReset()
  if not C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards") then
    C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
  end
  ns.database.SaveToCurrentCharacterDB(ns.enums.context.serverSlugUpdate, ns.me.serverSlug)
end

ns.events.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
function ns.events.BAG_UPDATE_DELAYED(...)
  ns.items.CacheCraftingItems()
end

ns.events.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
function ns.events.PLAYER_EQUIPMENT_CHANGED(...)
  ns.items.CacheWatermarks()
end

ns.events.eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
function ns.events.QUEST_LOG_UPDATE(...)
  ns.CheckQuests(...)
end

ns.events.eventFrame:RegisterUnitEvent("PLAYER_GUILD_UPDATE", "player")
function ns.events.PLAYER_GUILD_UPDATE(unitId)
  local guildName, _, _, guildRealm = GetGuildInfo("player")
  wipe(ns.currentGuildSlugs)
  C_GuildInfo.GuildRoster() -- requests update to roster
  C_Timer.After(0.2, function()
      local name, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote, isOnline, status, class, achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid
      for i = 1, 1000 do
          name, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote, isOnline, status, class, achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid = GetGuildRosterInfo(i)
          if not name then
              break
          end
          local charName, server = strsplit("-", name)
          ns.currentGuildSlugs[string.format("%s-%d", charName, ns.GetRealmId(nil, server)):lower()] = true
      end
      ns.database.CheckEligibleSyncLists()
  end)
  if not guildName then
    ns.Debug.print("Currently not in a guild")
    ns.me.guildInfo = nil
    ns.database.SaveToCurrentCharacterDB(ns.enums.context.guildInfo, nil, nil)
    return
  else
    ns.Debug.print("Is in a guild %s-%s", tostring(guildName), tostring(guildRealm))
  end
  if not ns.me.serverSlug then
    local serverSlug = GetNormalizedRealmName()
    ns.me.serverSlug = serverSlug
    if not serverSlug then
      ns.Debug.print("Could not get server slug for player")
      return false
    end
  end
  ns.me.guildInfo = {
    name = guildName,
    realm = guildRealm or ns.me.serverSlug,
    fullSlug = guildName .. "-" .. (guildRealm or ns.me.serverSlug),
    ---@diagnostic disable-next-line: param-type-mismatch
    dbSlug = guildName.. "-" .. ns.GetRealmId(nil, guildRealm or ns.me.serverSlug)
  }
  ns.database.SaveToCurrentCharacterDB(ns.enums.context.guildInfo, nil, ns.me.guildInfo.dbSlug)
end

ns.events.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
function ns.events.PLAYER_ENTERING_WORLD(...)

end

ns.events.eventFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
function ns.events.WEEKLY_REWARDS_UPDATE(...)
  ns.GreatVaultUpdate(...)
end
ns.events.eventFrame:RegisterEvent("LOADING_SCREEN_ENABLED")
function ns.events.LOADING_SCREEN_ENABLED()
    ns.InLoadingScreen = true
end

ns.events.eventFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
function ns.events.LOADING_SCREEN_DISABLED()
    ns.InLoadingScreen = false
    --dealAfterLoadingScreen()
end
ns.events.eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
function ns.events.PLAYER_LEAVING_WORLD(...)
  ns.database.SaveToCurrentCharacterDB(ns.enums.context.lastLogout, nil, GetServerTime())
end

ns.events.eventFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
function ns.events.ADDON_RESTRICTION_STATE_CHANGED(type, state)
  ---@diagnostic disable-next-line: undefined-field
  if type ~= Enum.AddOnRestrictionType.Chat then return end
  ns.restrictedAddonMessages = state ~= Enum.AddOnRestrictionState.Inactive
  if not ns.restrictedAddonMessages then
    ns.communication.AddonMessageRestrictionsLifted()
  end
  ns.Debug.print("ns.restrictedAddonMessages changed: '%s'", ns.restrictedAddonMessages)
end

do
  local whitelistedDifs = {
    [16] = true, -- Mythic
    [15] = true, -- Heroic
    [14] = true, -- Normal
    [233] = true, -- Mythic - Flex
  }
  ns.events.eventFrame:RegisterEvent("ENCOUNTER_END")
  function ns.events.ENCOUNTER_END(encounterID, encounterName, difficultyID, groupSize, success, npcs, ...)
    if not (whitelistedDifs[difficultyID] and success == 1) then return end
    ns.communication.SendInfoForLoot()
  end
end

-- Weekly reset stuff
do
  local _f = CreateFrame("frame")
  local checkForWeeklyReset = true
  local previousWeeklyResetTime
  local function handleWeeklyReset(resetTime)
    WowUtilsDB.lastSeenWeeklyReset = resetTime
    ns.Debug.print("Wowutilsdebug: weekly reset detected.")
    _f:UnregisterAllEvents()
    ns.database.ResetWeeklyData(resetTime)
  end
  function private.checkForWeeklyReset()
    if not checkForWeeklyReset then
      _f:UnregisterAllEvents()
      return
    end
    local currentResetTime = C_DateAndTime.GetWeeklyResetStartTime()
    local timeSinceReset = GetServerTime() - currentResetTime
    if not previousWeeklyResetTime then
      previousWeeklyResetTime = currentResetTime
      if not WowUtilsDB.lastSeenWeeklyReset then
        if timeSinceReset < 561600 then -- 6.5days
          checkForWeeklyReset = false
          return
        else
          return
        end
      end
      if WowUtilsDB.lastSeenWeeklyReset < currentResetTime then
        checkForWeeklyReset = false
        handleWeeklyReset(currentResetTime)
      end
      previousWeeklyResetTime = currentResetTime
      if timeSinceReset < 561600 then -- 6.5 days, only care about reset if its gonna be in the next 12 hours
          checkForWeeklyReset = false
      end
      return
    end
    if previousWeeklyResetTime >= currentResetTime then return end
    -- weekly reset
    handleWeeklyReset(currentResetTime)
    previousWeeklyResetTime = currentResetTime
    checkForWeeklyReset = false
  end
  for _, event in pairs({ -- all of these are just here for checking weekly reset, so they work exactly the same
    "QUEST_LOG_UPDATE",
    "WEEKLY_REWARDS_UPDATE",
    "UPDATE_INSTANCE_INFO",
    "CHALLENGE_MODE_MAPS_UPDATE"
    }) do
    _f:RegisterEvent(event)
  end
  _f:SetScript("OnEvent", private.checkForWeeklyReset)
end