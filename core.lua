---@class wowutilsPrivate : table
---@field GreatVaultUpdate fun(...)
---@field CheckQuests fun(...)
---@field CheckLockouts fun(...)
---@field lockouts wowutils_lockouts

---@type string, wowutilsPrivate
local addon_name, ns = ...

if ns.IsRetail then -- Weekly vault rewards
  local alreadyHookedWeeklyRewards = false
  local alreadyPicked = false
  local scanTime
  local function scanVault()
    if ns.InLoadingScreen then
      ns.Debug.print(">>> tring to scan vault during loading screen - GetTime: %s <<<", GetTime())
      C_Timer.After(0.5, scanVault)
      return
    end
    if C_WeeklyRewards then
      if not alreadyHookedWeeklyRewards then
        hooksecurefunc(C_WeeklyRewards, "ClaimReward", function(claimID)
          ---@type wowutils_ownChar
          local db = ns.database.GetCurrentCharDB()
          if db.vaultData then
            local found = false
            for k, v in pairs(db.vaultData) do
              if v.claimID == claimID then
                v.picked = true
                found = true
                break
              end
            end
            if not found then  -- assume we picked currency
              local bonusCoin = false
              for _, activityInfo in ipairs(C_WeeklyRewards.GetActivities()) do
                if activityInfo.claimID == claimID then
                  for _, rewardInfo in ipairs(activityInfo.rewards) do
                    if rewardInfo.id == 3513 then
                      bonusCoin = true
                    end
                  end
                  break
                end
              end
              table.insert(db.vaultData, {
                picked = true,
                claimID = claimID,
                itemClassId = 0,
                itemSubClassId = 0,
                itemId = bonusCoin and 2 or 1,
                itemLink = "",
                itemLevel = 0,
                itemLocationId = 0,
                tertiary = 0, -- TODO check tertiary stats
              })
            end
            alreadyPicked = true
            db.lastUpdate = GetServerTime()
            db.vaultDataLastUpdate = GetServerTime()
            ns.communication.SendVaultDataUpdate()
          end
        end)
        alreadyHookedWeeklyRewards = true
      end
      if C_WeeklyRewards.HasAvailableRewards() and not alreadyPicked then
        ---@type wowutils_ownChar
        local db = ns.database.GetCurrentCharDB()
        local vaultData = {}
        ns.Debug.print( ">>> RESETING VAULT ITEMS - GetTime: %s - db.lastWeeklyReset: %s - ns.InLoadingScreen: %s <<<", GetTime(), db.lastWeeklyReset, ns.InLoadingScreen)
        local activities = C_WeeklyRewards.GetActivities()
        for _, activityInfo in ipairs(activities) do
          for _, rewardInfo in ipairs(activityInfo.rewards) do
            local itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(rewardInfo.id)
            if itemEquipLoc and itemEquipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
              local itemLink = C_WeeklyRewards.GetItemHyperlink(rewardInfo.itemDBID)
              local itemLevel, _, _ = C_Item.GetDetailedItemLevelInfo(itemLink)
              local invType =  C_Item.GetItemInventoryTypeByID(itemID)
              ---@type wowutils_vaultData_items
              local item = {
                claimID = activityInfo.claimID,
                itemClassId = classID,
                itemSubClassId = subClassID,
                itemId = itemID,
                itemLink = itemLink,
                itemLevel = itemLevel,
                itemLocationId = invType or 0,
                picked = false,
                tertiary = 0, -- TODO check tertiary stats
              }
              table.insert(vaultData, item)
            end
          end
        end
        ns.database.SaveToCurrentCharacterDB(ns.enums.context.vaultData, nil, vaultData)
      end
    end
  end
  function ns.GreatVaultUpdate(...)
    local t = {}
    local activities = C_WeeklyRewards.GetActivities()
    for _, activityInfo in ipairs(activities) do
      if activityInfo.threshold and activityInfo.threshold ~= 0 and (activityInfo.progress or 0) >= activityInfo.threshold then
        t[string.format("%s-%s", activityInfo.type, activityInfo.index)] = activityInfo.level
      end
    end
    ns.database.SaveToCurrentCharacterDB(ns.enums.context.weeklyRewards, nil, t)
    C_Timer.After(0.5, scanVault)
  end
end
function ns.CheckQuests(...)
  local t = {}
  for questId,v in pairs(ns.config.quests) do
    t[questId] = {
      isWeeklyQuest = v.isWeeklyQuest,
      completed = C_QuestLog.IsQuestFlaggedCompleted(questId),
      completedWarbound = C_QuestLog.IsQuestFlaggedCompletedOnAccount(questId)
    }
  end
  ns.database.SaveToCurrentCharacterDB(ns.enums.context.quests, nil, t)
end

do -- Raid lockouts
  -- one bit per boss per difficulty, bosses in config order, difficulties in config order within a boss.
  -- plain arithmetic instead of bit.*, those are 32 bit only while doubles stay exact up to 2^53
  local config = ns.config.lockouts
  local difsPerBoss = #config.difficulties
  local bossCount = 0
  for _, raid in ipairs(config.raids) do
    bossCount = bossCount + #raid.encounters
  end
  local bitCount = bossCount * difsPerBoss
  assert(bitCount <= 53, "ns.config.lockouts has too many bosses to fit into a single number")

  ---@class wowutils_lockouts
  ns.lockouts = {
    bitCount = bitCount,
    fullMask = 2^bitCount - 1, -- every boss available, what a fresh week looks like
  }

  ---@param encounter wowutils_config_lockoutEncounter
  ---@param difId wowutils_enums_difficultyId
  ---@return wowutils_enums_difficultyId
  local function getRealDifficulty(encounter, difId)
    if encounter.mythicFlex and difId == ns.enums.difficultyId.RaidMythic then
      return ns.enums.difficultyId.RaidMythicFlex
    end
    return difId
  end

  ---@param value number
  ---@param bit number 0 based
  ---@return boolean
  function ns.lockouts.IsBitSet(value, bit)
    local b = 2^bit
    return value % (b * 2) >= b
  end

  ---@param value number lockout mask
  ---@return table<number, table<number, boolean>> available encounterId = { difficultyId = available }, mythic flex encounters are keyed under RaidMythicFlex
  function ns.lockouts.Decode(value)
    local t = {}
    local bit = 0
    for _, raid in ipairs(config.raids) do
      for _, encounter in ipairs(raid.encounters) do
        t[encounter.id] = {}
        for _, difId in ipairs(config.difficulties) do
          t[encounter.id][getRealDifficulty(encounter, difId)] = ns.lockouts.IsBitSet(value, bit)
          bit = bit + 1
        end
      end
    end
    return t
  end

  -- only call from UPDATE_INSTANCE_INFO, before the first one C_RaidLocks has nothing and everything would read as available
  function ns.CheckLockouts()
    if ns.config.lockoutsDisabled then return end
    local value = 0
    local bit = 0
    for _, raid in ipairs(config.raids) do
      for _, encounter in ipairs(raid.encounters) do
        for _, difId in ipairs(config.difficulties) do
          if not C_RaidLocks.IsEncounterComplete(raid.instanceId, encounter.id, getRealDifficulty(encounter, difId)) then
            value = value + 2^bit
          end
          bit = bit + 1
        end
      end
    end
    ns.database.SaveToCurrentCharacterDB(ns.enums.context.lockouts, nil, value)
  end
end
