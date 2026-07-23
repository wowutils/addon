---@class wowutilsPrivate : table
---@field PrintDebug fun(str: string, ...: any)
---@field GreatVaultUpdate fun(...)
---@field CheckQuests fun(...)
---@field Debug wowutilsDebug

---@type string, wowutilsPrivate
local addon_name, ns = ...

---@class wowutilsDebug
---@field print fun(formatStr:string, ...:any)
---@field AddToDevTool fun(data:any, displayName:string?)
ns.Debug = {}

function ns.Debug.print(str, ...)
  if not ns.debugMode then return end
  local args = { ... }
  for k, v in ipairs(args) do
    args[k] = tostring(v)
  end
  local success, error = pcall(function()
    print(string.format("%s WowUtilsDebug - %s", GetTime(), (#args > 0 and str:format(unpack(args))) or str))
    return true
  end)
  if success then return end
  print("Error from PrintDebug:", error, "str :", str)
end
function ns.Debug.AddToDevTool(data, displayName)
  if not ns.debugMode then return end
  if not DevTool then return end
  DevTool:AddData(data, displayName)
end

do -- Weekly vault rewards
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
              table.insert(db.vaultData, {
                picked = true,
                claimID = claimID,
                itemClassId = 0,
                itemSubClassId = 0,
                itemId = 1,
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
      if (activityInfo.progress or 0) >= activityInfo.threshold and activityInfo.level > 0 then
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
