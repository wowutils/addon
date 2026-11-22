---@class wowutilsPrivate
---@field events wowutils_events
---@field restrictedAddonMessages boolean
---@field InLoadingScreen boolean
---@field currentGuildSlugs table<string, boolean>
---@field DealAfterLoadingScreen fun(id:string, func:fun(...), args:any[]?)

---@type string, wowutilsPrivate
local addon_name, ns = ...
ns.restrictedAddonMessages = false
ns.InLoadingScreen = true
---@class wowutils_events : table
---@field RegisterEvent fun(event:string, ...:string?)
---@field UnregisterEvent fun(event:string)
ns.events = {
  eventFrame = CreateFrame("frame")
}
ns.currentGuildSlugs = {}
local private = {}
ns.events.eventFrame:SetScript("OnEvent", function(self, event, ...)
  ns.events[event](...)
end)

do
  local temp = {}
  function private.dealAfterLoadingScreen()
    for id,d in pairs(temp) do
      d.func(unpack(d.args))
    end
    wipe(temp)
  end
  function ns.DealAfterLoadingScreen(id, func, args)
    temp[id] = {func = func, args = args or {}}
  end
end

-- addon wide event toggling (eg. based on option toggles), handler still lives in ns.events[event]
---@param event string
---@param ... string? units, if given the event is registered as an unit event
function ns.events.RegisterEvent(event, ...)
  if not ns.events[event] then
    geterrorhandler()("No handler found for event: " .. tostring(event))
    return
  end
  if ... then
    ns.events.eventFrame:RegisterUnitEvent(event, ...)
  else
    ns.events.eventFrame:RegisterEvent(event)
  end
end

---@param event string
function ns.events.UnregisterEvent(event)
  ns.events.eventFrame:UnregisterEvent(event)
end

ns.events.eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
function ns.events.CURRENCY_DISPLAY_UPDATE(...)
  ns.currency.CURRENCY_DISPLAY_UPDATE(...)
end

if ns.IsRetail then
  ns.events.eventFrame:RegisterEvent("BONUS_ROLL_RESULT")
  function ns.events.BONUS_ROLL_RESULT(...)
    ns.items.CacheBonusRollResult(...)
  end
  ns.events.eventFrame:RegisterEvent("SPELL_CONFIRMATION_PROMPT")
  function ns.events.SPELL_CONFIRMATION_PROMPT(...)
    ns.items.CacheBonusRollPopup(...)
  end
end
ns.events.eventFrame:RegisterEvent("PLAYER_LOGIN")
function ns.events.PLAYER_LOGIN(...)
  for currencyId, mapId in pairs(ns.config.currencies) do
    ns.currency.CacheCurrency(currencyId)
  end
  private.checkForWeeklyReset()
  ns.events.PLAYER_GUILD_UPDATE("player")
  if ns.IsRetail then
    ns.me.serverSlug = GetNormalizedRealmName()
    if not C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards") then
      C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
    end
    ns.database.SaveToCurrentCharacterDB(ns.enums.context.serverSlugUpdate, nil, ns.me.serverSlug)
    ns.randomThings.craftingOrders.PruneAllExpired() -- whatever expired while we were offline
    C_Timer.After(5, ns.items.StartEncounterLootScan)
  end
  C_Timer.After(10, ns.items.InitialCaching)
  if not ns.config.lockoutsDisabled then
    RequestRaidInfo() -- lockouts get scanned from the UPDATE_INSTANCE_INFO this fires
  end
end

ns.events.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
function ns.events.BAG_UPDATE_DELAYED(...)
  ns.items.BAG_UPDATE_DELAYED(...)
end

ns.events.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
function ns.events.PLAYER_EQUIPMENT_CHANGED(...)
  ns.items.PLAYER_EQUIPMENT_CHANGED(...)
end

ns.events.eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
function ns.events.QUEST_LOG_UPDATE(...)
  ns.CheckQuests(...)
end
if ns.IsRetail then
  if WowUtilsDB.options.warboundOptions.enabled then -- toggled from gui
    ns.events.eventFrame:RegisterEvent("CHAT_MSG_LOOT")
  end
  function ns.events.CHAT_MSG_LOOT(...)
    ns.items.CHAT_MSG_LOOT(...)
  end
end

if ns.IsRetail then
  ns.events.eventFrame:RegisterEvent("CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE")
  function ns.events.CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE(...)
    ns.randomThings.craftingOrders.CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE(...)
  end

  --[[
  ns.events.eventFrame:RegisterEvent("CRAFTINGORDERS_CAN_REQUEST")
  function ns.events.CRAFTINGORDERS_CAN_REQUEST(...)
    ns.randomThings.craftingOrders.CRAFTINGORDERS_CAN_REQUEST(...)
  end
  --]]
  ns.events.eventFrame:RegisterEvent("CRAFTINGORDERS_UPDATE_ORDER_COUNT")
  function ns.events.CRAFTINGORDERS_UPDATE_ORDER_COUNT(...)
    ns.randomThings.craftingOrders.CRAFTINGORDERS_UPDATE_ORDER_COUNT(...)
  end
  ns.events.eventFrame:RegisterEvent("CRAFTINGORDERS_SHOW_CUSTOMER")
  function ns.events.CRAFTINGORDERS_SHOW_CUSTOMER(...)
    ns.randomThings.craftingOrders.CRAFTINGORDERS_SHOW_CUSTOMER(...)
  end
  ns.events.eventFrame:RegisterEvent("CRAFTINGORDERS_ORDER_CANCEL_RESPONSE")
  function ns.events.CRAFTINGORDERS_ORDER_CANCEL_RESPONSE(...)
    ns.randomThings.craftingOrders.CRAFTINGORDERS_ORDER_CANCEL_RESPONSE(...)
  end
  --CRAFTINGORDERS_HIDE_CUSTOMER
end
ns.events.eventFrame:RegisterUnitEvent("PLAYER_GUILD_UPDATE", "player")
function ns.events.PLAYER_GUILD_UPDATE(unitId)
  local guildName, _, _, guildRealm = GetGuildInfo("player")
  wipe(ns.currentGuildSlugs)
  C_GuildInfo.GuildRoster() -- requests update to roster
  C_Timer.After(0.2, ns.IsRetail and function()
    local name, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote, isOnline, status, class, achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid
    for i = 1, 1000 do
      name, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote, isOnline, status, class, achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid = GetGuildRosterInfo(i)
      if not name then
        break
      end
      local charName, server = ns.helpers.SplitFullName(name)
      -- a guildmate on our own realm comes back without one, and GetRealmId answers 0 for a
      -- realm it cannot place, which would collapse all of them onto the same bogus slug. an
      -- unresolvable realm still has to stay 0 though, guessing our own would be worse
      local realmId = server and ns.GetRealmId(nil, server) or ns.me.realmId
      ns.currentGuildSlugs[string.format("%s-%d", charName, realmId):lower()] = true
    end
    ns.database.CheckEligibleSyncLists()
  end or function()
    local name
    for i = 1, 1000 do
      name = GetGuildRosterInfo(i)
      if not name then
        break
      end
      ns.currentGuildSlugs[name:gsub(" ", "-"):lower()] = true
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
  if ns.IsRetail then
    if not ns.me.serverSlug then
      local serverSlug = GetNormalizedRealmName()
      ns.me.serverSlug = serverSlug
      if not serverSlug then
        ns.Debug.print("Could not get server slug for player")
        return false
      end
    end
  end
  ns.me.guildInfo = {
    name = guildName,
    realm = ns.IsRetail and (guildRealm or ns.me.serverSlug),
    fullSlug = ns.IsRetail and (guildName .. "-" .. (guildRealm or ns.me.serverSlug)) or guildName,
    ---@diagnostic disable-next-line: param-type-mismatch
    dbSlug = ns.IsRetail and (guildName.. "-" .. ns.GetRealmId(nil, guildRealm or ns.me.serverSlug)) or guildName
  }
  ns.database.SaveToCurrentCharacterDB(ns.enums.context.guildInfo, nil, ns.me.guildInfo.dbSlug)
end

ns.events.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
function ns.events.PLAYER_ENTERING_WORLD(...)

end

ns.events.eventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
function ns.events.UPDATE_INSTANCE_INFO(...)
  ns.CheckLockouts(...)
end

if ns.IsRetail then
  ns.events.eventFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
  function ns.events.WEEKLY_REWARDS_UPDATE(...)
    ns.GreatVaultUpdate(...)
  end
end

ns.events.eventFrame:RegisterEvent("LOADING_SCREEN_ENABLED")
function ns.events.LOADING_SCREEN_ENABLED()
    ns.InLoadingScreen = true
end

ns.events.eventFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
function ns.events.LOADING_SCREEN_DISABLED()
    ns.InLoadingScreen = false
    private.dealAfterLoadingScreen()
end

ns.events.eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
function ns.events.PLAYER_LEAVING_WORLD(...)
  ns.database.SaveToCurrentCharacterDB(ns.enums.context.lastLogout, nil, GetServerTime())
end

if ns.IsRetail then
  ns.events.eventFrame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
  function ns.events.CHALLENGE_MODE_MAPS_UPDATE(...)
    ns.randomThings.dungeonsDone.CHALLENGE_MODE_MAPS_UPDATE(...)
  end
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

ns.events.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
function ns.events.PLAYER_REGEN_ENABLED(...)
  ns.items.PLAYER_REGEN_ENABLED(...)
end

do
  local whitelistedDifs = ns.IsRetail and {
    [16] = true, -- Mythic
    [15] = true, -- Heroic
    [14] = true, -- Normal
    [233] = true, -- Mythic - Flex
  } or {}
  ns.events.eventFrame:RegisterEvent("ENCOUNTER_END")
  function ns.events.ENCOUNTER_END(encounterID, encounterName, difficultyID, groupSize, success, npcs, ...)
    if not (whitelistedDifs[difficultyID] and success == 1) then return end
    ns.communication.SendInfoForLoot()
    if not ns.config.lockoutsDisabled then
      RequestRaidInfo() -- refresh lockouts
    end
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

if ns.IsForever then -- loot drop tracking
  ns.events.eventFrame:RegisterEvent("LOOT_READY")
  function ns.events.LOOT_READY(...)
    ns.randomThings.lootWindows.LOOT_READY(...)
  end
end