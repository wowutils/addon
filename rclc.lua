---@class wowutilsPrivate
---@field rclc wowutils_rclc

---@type string, wowutilsPrivate
local addon_name, ns = ...
local sformat, tconcat = string.format, table.concat
local moduleName = "WowUtilsRCLC"
local columnName = "wowutils"
local wishlistColumnName = "wishlist"
---@class wowutils_rclc
ns.rclc = {}
local private = {}
local rclcMod
if C_AddOns.IsAddOnLoaded("RCLootCouncil") then
  ns.rclc.actualAddon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil", true)
  if ns.rclc.actualAddon then
    rclcMod = ns.rclc.actualAddon:NewModule(moduleName, "AceHook-3.0")
  end
end
local session = 0

function ns.rclc.OnLootTableReceived()
  if not ns.rclc.votingWindow then return end
  ns.rclc.currentLootTable = ns.rclc.actualAddon:GetLootTable()
  ns.rclc.votingWindow:Update()
  ns.communication.SendInfoForLoot()
end

function ns.rclc.DataUpdated()
  if not ns.rclc.votingWindow then return end
  ns.rclc.votingWindow:Update()
end

function RCLCT()
  ns.rclc.DataUpdated()
end

do
  local currencyData = {}
  for i, mapIdToFind in pairs({
    { 4, ns.enums.itemTrack.myth },
    { 3, ns.enums.itemTrack.hero },
    { 2, ns.enums.itemTrack.champion },
    { 1, ns.enums.itemTrack.veteran },
    { 5, "convert" },
    { 6, "bonusCoin"}, }) do
    for currencyId, mapId in pairs(ns.config.currencies) do
      if mapIdToFind[1] == mapId then
        local ci = C_CurrencyInfo.GetCurrencyInfo(currencyId)
        currencyData[mapIdToFind[2]] = {
          currencyId = currencyId,
          format = sformat("%s Current: %%s - Earned: %%s", CreateSimpleTextureMarkup(ci and ci.iconFileID or 134400)),
        }
        break
      end
    end
  end
  local itemLinkDataCache = {}
  ---@class CurrentItemInfo
  ---@field itemLink string
  ---@field itemTrack wowutils_enums_itemTrack
  ---@field itemId number
  ---@field invSlotId number
  ---@field itemClassId number
  ---@field itemSubClassId number
  ---@field watermarkSlot number?

  ---fetches item that is currently being viewed
  ---@param item table?
  ---@return CurrentItemInfo?
  local function getItemInfo(item)
    if not item then
      if not ns.rclc.currentLootTable then return nil end
      if not ns.rclc.currentLootTable[session] then return nil end
    end
    local _item = item or ns.rclc.currentLootTable[session]
    if itemLinkDataCache[_item.link] then return itemLinkDataCache[_item.link] end
    local itemId = _item.itemID
    if not itemId then -- roll windows dont have that?
      itemId = C_Item.GetItemInfoInstant(_item.link)
    end
    ---@type CurrentItemInfo
    itemLinkDataCache[_item.link] = {
      itemLink = _item.link,
      itemTrack = ns.helpers.GetItemTrack(_item.link),
      itemId = itemId,
      itemClassId = _item.typeID,
      itemSubClassId = _item.subTypeID,
      invSlotId = ns.helpers.GetInventorySlotByEquipLoc(_item.equipLoc),
      watermarkSlot = C_ItemUpgrade.GetHighWatermarkSlotForItem(_item.link)
    }
    return itemLinkDataCache[_item.link]
  end
  local weaponSlots = {
    [Enum.ItemRedundancySlot.MainhandWeapon] = true,
    [Enum.ItemRedundancySlot.Offhand] = true,
    [Enum.ItemRedundancySlot.OnehandWeapon] = true,
    [Enum.ItemRedundancySlot.OnehandWeaponSecond] = true,
    [Enum.ItemRedundancySlot.Twohand] = true,
  }
  local instanceDifToItemTrack = {
    [ns.enums.difficultyId.RaidNormal] = ns.enums.itemTrack.champion,
    [ns.enums.difficultyId.RaidLFR] = ns.enums.itemTrack.veteran,
    [ns.enums.difficultyId.DungeonKeystone] = ns.enums.itemTrack.hero, -- TODO add support for mythic items, but that requires to actually know the tracks of sim items
    [ns.enums.difficultyId.RaidHeroic] = ns.enums.itemTrack.hero,
    [ns.enums.difficultyId.RaidMythic] = ns.enums.itemTrack.myth,
    [ns.enums.difficultyId.RaidMythicFlex] = ns.enums.itemTrack.myth,
  }
  ---@param instanceDif number
  ---@param itemTrack number
  local function isCorrectDif(instanceDif, itemTrack)
    return instanceDifToItemTrack[instanceDif] == itemTrack
  end

  local simlineColors = {
    neutral = { 1, 1, 1 },
    loss = { .92, .5, 0 },
    bad = { 1, 0, 0 },
    upgrade = { .75, .75, 0 },
    good = { 0, 1, .25 }
  }
  local function getSimLineColor(dif)
    if not dif then return simlineColors.neutral end
    if dif > .5 then return simlineColors.good end
    if dif > 0 then return simlineColors.upgrade end
    if dif < -.5 then return simlineColors.bad end
    return simlineColors.loss
  end

  ---@param itemTrack any
  ---@param data table<number, wowutils_currencyData>
  ---@return table
  local function formatCurrencyLine(itemTrack, data)
    if not currencyData[itemTrack] then return { "Error", 1, 0, 0 } end
    if not data then ns.Debug.print("no 'data'") return { "No Data/No Data", .92, .5, 0 } end
    local playerCurrency = data[currencyData[itemTrack].currencyId]
    if not playerCurrency then
      ns.Debug.print("no 'playercurrency'")
      return { currencyData[itemTrack].format:format("No Data", "No Data"), .92, .5, 0 }
    end
    ---@cast playerCurrency wowutils_currencyData
    return { currencyData[itemTrack].format:format(playerCurrency.current or 0, playerCurrency.totalEarned or 0), 1, 1, 1 }
  end

  local exactColor = { 0, 1, .25 }
  local mutedColor = { .7, .7, .7 }
  local sectionColor = { 1, .82, 0 }

  ---@param itemId number
  ---@return string
  local function itemLabel(itemId)
    -- name lookups miss on the first hover of an uncached item; the next hover has it
    local itemName = C_Item.GetItemNameByID(itemId) or UNKNOWN
    local itemIcon = select(5, GetItemInfoInstant(itemId))
    return sformat("|T%d:0|t %s", itemIcon or 134400, itemName)
  end

  ---Header line with a rule above it, so the tooltip reads as stacked sections.
  ---@param tooltip GameTooltip
  ---@param left string
  ---@param right string?
  local function addSection(tooltip, left, right)
    if right then
      tooltip:AddDoubleLine(left, right, sectionColor[1], sectionColor[2], sectionColor[3], 1, 1, 1)
    else
      tooltip:AddLine(left, sectionColor[1], sectionColor[2], sectionColor[3])
    end
    ns.helpers.AddTooltipSeparator(tooltip)
  end

  ---One wishlist pick: item on the left, what the player picked on the site plus its age on the right.
  ---@param wlItem wowutilsDroptimizerData_wishlistItem
  ---@param isViewedItem boolean
  ---@param tooltip GameTooltip
  local function addWishlistLine(wlItem, isViewedItem, tooltip)
    local c = isViewedItem and exactColor or mutedColor
    tooltip:AddDoubleLine(sformat("%s%s", isViewedItem and ">>> " or "", itemLabel(wlItem.itemId)),
      sformat("%s  %s", wlItem.priority, ns.helpers.GetFormatedLastUpdateTime(wlItem.updated)),
      c[1], c[2], c[3], c[1], c[2], c[3])
    if wlItem.note and wlItem.note ~= "" then
      tooltip:AddLine(sformat("      %s", wlItem.note), mutedColor[1], mutedColor[2], mutedColor[3], true)
    end
  end

  ---"mythic-max" -> "Mythic max", "raid-vault-mythic" -> "Raid vault mythic"
  ---@param key string
  ---@return string
  local function prettyKey(key)
    local words = key:gsub("[-_]", " ")
    return words:sub(1, 1):upper() .. words:sub(2)
  end

  ---Compact sim label: "|Tspec|t RB · Mythic max · Patchwerk x2". simKey is
  ---"<simType>-<profileKey>-<fightStyle or 0>-<targets>" as written by dataImport.
  ---@param specId number
  ---@param simKey string
  ---@return string
  local function formatSimName(specId, simKey)
    local simType, rest = simKey:match("^(%d+)%-(.*)$")
    local source = tonumber(simType) == ns.enums.simTypes.qeLiveDroptimizer and "QE" or
      tonumber(simType) == ns.enums.simTypes.raidbotDroptimizer and "RB" or "?"
    local icon = ns.helpers.GetIconTextureStringForSpecId(specId)
    local profile, fightStyle, targets = (rest or simKey):match("^(.-)%-([^-]*)%-(%d+)$")
    if not profile then return sformat("%s%s · %s", icon, source, rest or simKey) end
    return sformat("%s%s · %s · %sx%s", icon, source, prettyKey(profile),
      fightStyle ~= "0" and (prettyKey(fightStyle) .. " ") or "", targets)
  end

  ---Gain text + percentile for one simmed item, whichever sim source produced it.
  ---@param simData wowutilsDroptimizerData_sims
  ---@param itemData wowutilsDroptimizerData_droptimizerItem
  ---@return string text
  ---@return number percentile
  local function formatGain(simData, itemData)
    if not simData.baseline then -- qelive only carries a percentage
      local pct = itemData.gainPercent or 0
      return sformat("%+.2f%%", pct), pct
    end
    local pct = ((itemData.gain or 0) / simData.baseline) * 100
    return sformat("%+.0f  (%.2f%%)", itemData.gain or 0, pct), pct
  end
  do
    local qeLiveMatchStr = "0%-1$"
    local raidbotsMatchStr = "patchwerk%-1$"

    ---@param droptimizerKey string
    ---@param entryItem table? rclc item entry
    ---@return string?
    ---@return table?
    function private.findSimValueForWindow(droptimizerKey, entryItem)
      local itemInfo = getItemInfo(entryItem)
      if not itemInfo then return "---" end
      local droptimizerData = WowUtilsDB.droptimizerData[droptimizerKey]
      if not droptimizerData then return "---" end
      local bestItem
      local bestDif
      for specId, sims in pairs(droptimizerData.specs) do
        for simKey, simData in pairs(sims) do
          if simData.items[itemInfo.itemId] then
            if isCorrectDif(simData.items[itemInfo.itemId].difficultyId, itemInfo.itemTrack) then
              if simData.simType == ns.enums.simTypes.raidbotDroptimizer then
                local dif = ((simData.items[itemInfo.itemId].gain or 0)/(simData.baseline or 1)) * 100
                local val = sformat("%s (%.2f%%)", simData.items[itemInfo.itemId].gain or 0, dif)
                if simKey:lower():match(raidbotsMatchStr) then -- patchwork 1 target sim, not gonna find a better match (?) TODO maybe figure out something better, in theory there could be multiple
                  return val, getSimLineColor(dif)
                end
                bestItem = val
                bestDif = dif
              elseif simData.simType == ns.enums.simTypes.qeLiveDroptimizer then
                local val = sformat("%.2f%%", simData.items[itemInfo.itemId].gainPercent)
                if simKey:lower():match(qeLiveMatchStr) then -- patchwork 1 target sim, not gonna find a better match (?) TODO maybe figure out something better, in theory there could be multiple
                  return val, getSimLineColor(simData.items[itemInfo.itemId].gainPercent)
                end
                bestItem = val
                bestDif = simData.items[itemInfo.itemId].gainPercent
              else
                bestItem = simData.items[itemInfo.itemId].gain
              end
            end
          end
        end
      end
      ---@diagnostic disable-next-line: return-type-mismatch
      return bestItem, bestDif and getSimLineColor(bestDif) or nil
    end
  end
  ---What the player picked for the viewed item on the website: the group's own tier label
  ---(already resolved from `wishlistMapping` at import), matched on the exact item at the
  ---difficulty being looted. Same-slot-but-other-item picks stay in the tooltip only.
  ---@param droptimizerKey string
  ---@param entryItem table? rclc item entry
  ---@return string? label
  ---@return wowutilsDroptimizerData_wishlistItem? pick
  function private.findWishlistPickForWindow(droptimizerKey, entryItem)
    local itemInfo = getItemInfo(entryItem)
    if not itemInfo then return nil end
    local droptimizerData = WowUtilsDB.droptimizerData[droptimizerKey]
    if not droptimizerData then return nil end
    for _, wlItem in pairs(droptimizerData.wishlist) do
      if wlItem.itemId == itemInfo.itemId and isCorrectDif(wlItem.difficultyId, itemInfo.itemTrack) then
        return wlItem.priority, wlItem
      end
    end
    return nil
  end
  local function isMatchingSlot(slot1, slot2)
    if slot1 == slot2 then return true end
    return ns.helpers.GetUniversalSlot(slot1) == ns.helpers.GetUniversalSlot(slot2)
  end
  ---@param guid string
  ---@param droptimizerKey string
  ---@param tooltip GameTooltip
  ---@param entryItem table? entry item  from rclc
  function ns.rclc.AddDataToTooltip(guid, droptimizerKey, tooltip, entryItem)
    local itemInfo = getItemInfo(entryItem)
    if not itemInfo then return end
    local droptimizerData = WowUtilsDB.droptimizerData[droptimizerKey]
    ns.Debug.AddToDevTool({ itemInfo = itemInfo, droptimizerData = droptimizerData }, "ns.rclc.AddDataToTooltip")
    if droptimizerData then
      -- Wishlist: the viewed item first, then other picks in the same slot at this difficulty.
      local viewedPick, otherPicks = nil, {}
      for _, wlItem in pairs(droptimizerData.wishlist) do
        if isMatchingSlot(wlItem.equipmentSlot, itemInfo.invSlotId) and isCorrectDif(wlItem.difficultyId, itemInfo.itemTrack) then
          if wlItem.itemId == itemInfo.itemId then
            viewedPick = wlItem
          else
            tinsert(otherPicks, wlItem)
          end
        end
      end
      if viewedPick or #otherPicks > 0 then
        addSection(tooltip, "Wishlist")
        if viewedPick then addWishlistLine(viewedPick, true, tooltip) end
        for _, wlItem in ipairs(otherPicks) do addWishlistLine(wlItem, false, tooltip) end
      end

      -- Droptimizers: one line per sim for the viewed item; every other same-slot item
      -- collapses to its single best result across all sims.
      ---@type {name: string, text: string, pct: number, simmedAt: number}[]
      local viewedLines = {}
      ---@type table<number, {text: string, pct: number, simName: string}>
      local bestOther = {}
      for specId, sims in pairs(droptimizerData.specs) do
        for simKey, simData in pairs(sims) do
          local simName
          for itemId, itemData in pairs(simData.items) do
            ---@cast itemData wowutilsDroptimizerData_droptimizerItem
            if isMatchingSlot(itemInfo.invSlotId, itemData.equipmentSlot) and isCorrectDif(itemData.difficultyId, itemInfo.itemTrack) then
              simName = simName or formatSimName(specId, simKey)
              local text, pct = formatGain(simData, itemData)
              if itemId == itemInfo.itemId then
                tinsert(viewedLines, { name = simName, text = text, pct = pct, simmedAt = simData.simmedAt })
              elseif not bestOther[itemId] or bestOther[itemId].pct < pct then
                bestOther[itemId] = { text = text, pct = pct, simName = simName }
              end
            end
          end
        end
      end
      if #viewedLines > 0 then
        table.sort(viewedLines, function(x, y) return x.pct > y.pct end)
        addSection(tooltip, sformat("Droptimizer  %s", itemLabel(itemInfo.itemId)))
        for _, line in ipairs(viewedLines) do
          local c = getSimLineColor(line.pct)
          tooltip:AddDoubleLine(sformat("%s  |cff9d9d9d%s|r", line.name, ns.helpers.GetFormatedLastUpdateTime(line.simmedAt)),
            line.text, 1, 1, 1, c[1], c[2], c[3])
        end
      end
      local otherIds = {}
      for itemId in pairs(bestOther) do tinsert(otherIds, itemId) end
      if #otherIds > 0 then
        table.sort(otherIds, function(x, y) return bestOther[x].pct > bestOther[y].pct end)
        addSection(tooltip, "Other options in slot", "best sim")
        local maxOther = 6
        for i = 1, math.min(#otherIds, maxOther) do
          local itemId = otherIds[i]
          local o = bestOther[itemId]
          local c = getSimLineColor(o.pct)
          tooltip:AddDoubleLine(sformat("%s  |cff9d9d9d%s|r", itemLabel(itemId), o.simName), o.text,
            1, 1, 1, c[1], c[2], c[3])
        end
        if #otherIds > maxOther then
          tooltip:AddLine(sformat("      +%d more", #otherIds - maxOther), mutedColor[1], mutedColor[2], mutedColor[3])
        end
      end
    end

    local playerData
    if guid == ns.me.guid then
      playerData = WowUtilsDB.ownCharacters[guid]
    else
      playerData = WowUtilsDB.others[guid]
    end
    if playerData then
      --local itemUpgradeInfo  = C_Item.GetItemUpgradeInfo(itemInfo.itemLink)
      addSection(tooltip, "Currency", ns.helpers.GetFormatedLastUpdateTime(playerData.dataRefreshTimes and playerData.dataRefreshTimes.currency or playerData.currencyUpdated))
      if itemInfo.itemTrack == ns.enums.itemTrack.none then
        tooltip:AddLine(unpack(formatCurrencyLine(ns.enums.itemTrack.myth, playerData.currency)))
        tooltip:AddLine(unpack(formatCurrencyLine(ns.enums.itemTrack.hero, playerData.currency)))
        tooltip:AddLine(unpack(formatCurrencyLine(ns.enums.itemTrack.champion, playerData.currency)))
        tooltip:AddLine(unpack(formatCurrencyLine(ns.enums.itemTrack.veteran, playerData.currency)))
        tooltip:AddLine(unpack(formatCurrencyLine("convert", playerData.currency)))
        tooltip:AddLine(unpack(formatCurrencyLine("bonusCoin", playerData.currency)))
      else
        tooltip:AddLine(unpack(formatCurrencyLine(itemInfo.itemTrack, playerData.currency)))
        tooltip:AddLine(unpack(formatCurrencyLine("convert", playerData.currency)))
        tooltip:AddLine(unpack(formatCurrencyLine("bonusCoin", playerData.currency)))
      end
      if itemInfo.watermarkSlot then
        addSection(tooltip, "Free upgrade up to", ns.helpers.GetFormatedLastUpdateTime(playerData.dataRefreshTimes and playerData.dataRefreshTimes.watermarks or playerData.watermarksUpdated or 0))
        if playerData.watermarks then
          if weaponSlots[itemInfo.watermarkSlot] then
            tooltip:AddLine(
              sformat("MainhandWeapon %s", playerData.watermarks[Enum.ItemRedundancySlot.MainhandWeapon] or 0), 1, 1, 1)
            tooltip:AddLine(sformat("Offhand %s", playerData.watermarks[Enum.ItemRedundancySlot.Offhand] or 0), 1, 1, 1)
            tooltip:AddLine(
              sformat("OnehandWeapon %s", playerData.watermarks[Enum.ItemRedundancySlot.OnehandWeapon] or 0), 1, 1, 1)
            tooltip:AddLine(
              sformat("OnehandWeaponSecond %s", playerData.watermarks[Enum.ItemRedundancySlot.OnehandWeaponSecond] or 0),
              1,
              1, 1)
            tooltip:AddLine(sformat("Twohand %s", playerData.watermarks[Enum.ItemRedundancySlot.Twohand] or 0), 1, 1, 1)
          else
            ---@diagnostic disable-next-line: param-type-mismatch
            tooltip:AddLine(playerData.watermarks[itemInfo.watermarkSlot] or 0, 1, 1, 1)
          end
        else
          tooltip:AddLine("No watermark data", .92, .5, 0)
        end
      end
    else
      tooltip:AddLine("No player data", .92, .5, 0)
    end
  end
end

if not rclcMod then return end
--#region voting window
function rclcMod:OnInitialize()
  C_Timer.After(1, function() rclcMod:InitialSetup() end)
end

function rclcMod:InitialSetup()
  ns.rclc.votingWindow = ns.rclc.actualAddon:GetActiveModule("votingframe")
  ns.rclc.originalColumns = { unpack(ns.rclc.votingWindow.scrollCols) }
  self:Hook(ns.rclc.votingWindow, "SwitchSession", function(_, _sessionId) session = _sessionId end)
  self:SecureHook(ns.rclc.actualAddon, "OnLootTableReceived", ns.rclc.OnLootTableReceived)
  --self.sortNext = {}
  -- Response (what they picked on the site) sits left of the number (sim gain).
  table.insert(ns.rclc.votingWindow.scrollCols, {
    name = "Wishlist",
    align = "CENTER",
    width = 110,
    pos = #ns.rclc.votingWindow.scrollCols + 1,
    DoCellUpdate = self.UpdateWishlistCell,
    colName = wishlistColumnName,
  })
  table.insert(ns.rclc.votingWindow.scrollCols, {
    name = "WowUtils",
    align = "CENTER",
    width = 100,
    pos = #ns.rclc.votingWindow.scrollCols + 1,
    DoCellUpdate = self.UpdateMainModCell,
    colName = columnName,
  })
  for _, v in ipairs(ns.rclc.votingWindow.scrollCols) do
    if v.sortNext then
      ns.Debug.print("%s - %s", v.colName, v.sortNext)
      self.sortNext[v.colName] = ns.rclc.votingWindow.scrollCols[v.sortNext].colName
    end
  end
  --self:SetupColumns()
  self:UpdateVotingFrameColumns()
end

function rclcMod:OnDisable()
  ns.rclc.votingWindow.scrollCols = ns.rclc.originalColumns
  self:UnhookAll()
  self:UnregisterAllEvents()
end
--[[
function rclcMod:UpdateColumn(name, add)
  ns.Debug.print("rclcMod:UpdateColumn(name, add)")
end
--]]
--[[
function rclcMod:SetupColumns()
  ns.Debug.print("rclcMod:SetupColumns()")
  self:UpdateVotingFrameColumns()
end
--]]
function rclcMod:UpdateSortNext()
  local cols = ns.rclc.votingWindow.scrollCols
  for i in ipairs(cols) do
    if cols[i].sortNext then
      local exists = self:GetScrollColIndexFromName(self.sortNext[cols[i].colName])
      cols[i].sortNext = exists
    end
  end
  self:UpdateVotingFrameColumns()
end

function rclcMod:UpdateVotingFrameColumns()
  if ns.rclc.votingWindow.frame then
    ns.rclc.votingWindow.frame.st:SetDisplayCols(ns.rclc.votingWindow.scrollCols)
    ns.rclc.votingWindow.frame:SetWidth(ns.rclc.votingWindow.frame.st.frame:GetWidth() + 20)
  end
end

function rclcMod:UpdateColumnPosition(name, pos)
  local i = self:GetScrollColIndexFromName(name)
  if pos < 0 then
    pos = #ns.rclc.votingWindow.scrollCols + pos
  end
  if pos > #ns.rclc.votingWindow.scrollCols then
    pos = #ns.rclc.votingWindow.scrollCols
  end
  if pos == 0 then pos = 1 end
  -- Move the column and update
  tinsert(ns.rclc.votingWindow.scrollCols, pos, tremove(ns.rclc.votingWindow.scrollCols, i))
  self:UpdateSortNext()
  if ns.rclc.votingWindow.frame then -- Frame might not be created
    ns.rclc.votingWindow.frame.st:SetDisplayCols(ns.rclc.votingWindow.scrollCols)
    ns.rclc.votingWindow.frame.st:SortData()
  end
end

function rclcMod:GetScrollColIndexFromName(name)
  return ns.rclc.votingWindow:GetColumnIndexFromName(name)
end

---@param name string candidate name as rclc stores it (name-realm)
---@return string? guid
---@return string droptimizerKey
local function getRowKeys(name)
  local guid = UnitGUID(Ambiguate(name, "none"))
  local n, s = strsplit("-", name)
  return guid, sformat("%s-%s", n:lower(), ns.GetRealmId(nil, s))
end

---Hover on any of our cells shows the full per-candidate breakdown for the viewed item.
local function attachRowTooltip(frame, name, guid, droptimizerKey)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    local unitClassBase = UnitClassBase(Ambiguate(name, "none"))
    local classColor = C_ClassColor.GetClassColor(unitClassBase)
    GameTooltip:AddLine(classColor and classColor:WrapTextInColorCode(name) or name)
    if guid and droptimizerKey then
      ns.rclc.AddDataToTooltip(guid, droptimizerKey, GameTooltip)
    else
      GameTooltip:AddLine("Error.", 1, 0, 0)
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
end

function rclcMod.UpdateWishlistCell(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
  local name = data[realrow].name
  local guid, droptimizerKey = getRowKeys(name)
  attachRowTooltip(frame, name, guid, droptimizerKey)
  local label = private.findWishlistPickForWindow(droptimizerKey)
  -- lib-st sizes the cell text to the column width; with wrapping off the client
  -- ellipsizes anything wider, which covers arbitrary site labels safely.
  frame.text:SetWordWrap(false)
  frame.text:SetNonSpaceWrap(false)
  frame.text:SetText(label or "---")
  frame.text:SetTextColor(1, 1, 1)
end

function rclcMod.UpdateMainModCell(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
  local name = data[realrow].name
  local guid, droptimizerKey = getRowKeys(name)
  attachRowTooltip(frame, name, guid, droptimizerKey)
  --[[
  local f = frame.wowutilsButton
  if not f then
    f = CreateFrame("Button", nil, frame)
    f:SetSize(table.rowHeight, table.rowHeight)
    ns.Debug.print(f:GetWidth(), f:GetHeight())
    f:SetPoint("CENTER", frame, "CENTER")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(table.rowHeight-2, table.rowHeight-2)
    f.icon:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    f.icon:SetTexture(ns.logoFile)
    --f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    --f.text:SetPoint("LEFT", f.icon, "LEFT", -2, 0)
    --f.text:SetText("+123465")
    f:SetScript("OnEnter", function(self)
      local txt = ns.rclc.GetDataLinesForGuid(guid)
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
      GameTooltip:AddLine(name)
      GameTooltip:AddLine(txt)
      GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    f:SetScript("OnClick", function()
      ns.Debug.print("OnClick")
    end)
    frame.wowutilsButton = f
  end
  --]]
  local text, color = private.findSimValueForWindow(droptimizerKey)
  frame.text:SetText(text or "---")
  frame.text:SetTextColor(unpack(color or {1,1,1}))
end

--#endregion
--#region own selection popup
-- if we got this far, RCLootCouncil is installed so we don't have to check that again
ns.rclc.lootFrame = ns.rclc.actualAddon:GetModule("RCLootFrame")
local lootPopup = ns.rclc.actualAddon:NewModule(moduleName .. "LootPopup", "AceHook-3.0")

function lootPopup:OnInitialize()
  C_Timer.After(0, function()
    lootPopup:SecureHook(ns.rclc.lootFrame.EntryManager, "GetEntry", lootPopup.OnGetEntry)
  end)
end
--[[
function lootPopup:OnEnable()
  ns.Debug.print("lootPopup:OnEnable()")
  --self:SecureHook("GetEntry", self.OnGetEntry)
end
--]]
function lootPopup:OnGetEntry(item, isDuplicateCall)
  if isDuplicateCall then return end
  local entry = ns.rclc.lootFrame.EntryManager:GetEntry(item, true)
  if not entry.wowUtilsHook then
    entry.wowUtilsHook = true
    lootPopup:SecureHook(entry, "Update", lootPopup.HandleEntry)
    lootPopup.HandleEntry(entry) -- update is not called initially
  end
end

function lootPopup.HandleEntry(entry)
  if not (entry and entry.frame) then return end
  if not entry.frame.wowutilsButton then
    entry.timeoutBarText:SetPoint("TOPRIGHT", entry.frame, "TOPRIGHT", -25, -10)
    local b = CreateFrame("Button", nil, entry.frame)
    b:SetSize(16, 16)
    b:SetPoint("TOPRIGHT", entry.frame, "TOPRIGHT", -5, -5)
    b:SetNormalTexture(ns.logoFile)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
      ns.rclc.AddDataToTooltip(ns.me.guid, ns.me.droptimizerKey, GameTooltip, entry.item)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    --[[
    b:SetScript("OnClick", function()
      ns.Debug.print("OnClick")
    end)
    --]]
    b.previewText = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.previewText:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -5)
    b.previewText:SetJustifyH("RIGHT")
    entry.frame.wowutilsButton = b
  else
    ns.Debug.print("button already exists")
  end
  local text, color = private.findSimValueForWindow(ns.me.droptimizerKey, entry.item)
  entry.frame.wowutilsButton.previewText:SetText(text or "---")
  entry.frame.wowutilsButton.previewText:SetTextColor(unpack(color or {1,1,1}))
end
