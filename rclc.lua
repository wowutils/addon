---@class wowutilsPrivate
---@field rclc wowutils_rclc

---@type string, wowutilsPrivate
local addon_name, ns = ...
local sformat, tconcat = string.format, table.concat
local moduleName = "WowUtilsRCLC"
local columnName = "wowutils"
---@class wowutils_rclc
ns.rclc = {}
local private = {}
local rclcMod
if C_AddOns.IsAddOnLoaded("RCLootCouncil") then
  ns.rclc.actualAddon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
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
    { 5, "convert" } }) do
    for currencyId, mapId in pairs(ns.config.currencies) do
      if mapIdToFind[1] == mapId then
        local ci = C_CurrencyInfo.GetCurrencyInfo(currencyId)
        currencyData[mapIdToFind[2]] = {
          currencyId = currencyId,
          format = sformat("%s Current: %%s - Earned: %%s", CreateSimpleTextureMarkup(ci.iconFileID)),
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
  ---@field equipmentSlot number
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
      equipmentSlot = C_Item.GetItemInventoryTypeByID(itemId) or 0,
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

  ---@class DroptimizerLine
  ---@field tooltipLine string
  ---@field percentileDif number

  ---@class DroptimizerFormated
  ---@field simmedAt number
  ---@field displayName string
  ---@field items DroptimizerLine[]

  ---@param simData wowutilsDroptimizerData_sims
  ---@param itemInfo CurrentItemInfo
  ---@param itemData wowutilsDroptimizerData_droptimizerItem
  ---@param itemId number
  ---@return DroptimizerLine?
  local function getDroptimizerLine(simData, itemInfo, itemData, itemId)
    local isSame = itemInfo.itemId == itemId
    local itemName = C_Item.GetItemNameByID(itemId) or UNKNOWN -- just force user to mouseover it again, cba to do caching, at least for now TODO maybe do it later on?
    local itemIcon = select(5, GetItemInfoInstant(itemId))
    if not simData.baseline then                               -- qelive
      return {
        tooltipLine = sformat("%s%.2f%% |T%d:0|t%s", isSame and ">>> " or "", itemData.gainPercent, itemIcon, itemName),
        percentileDif = itemData.gainPercent,
      }
    else
      local percentile = (itemData.gain / simData.baseline) * 100
      return {
        tooltipLine = sformat("%s%s (%.2f%%) |T%d:0|t%s", isSame and ">>> " or "", itemData.gain or UNKNOWN, percentile,
          itemIcon, itemName),
        percentileDif = percentile,
      }
    end
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
    if not data then return ns.Debug.print("no 'data'") { "No Data/No Data", .92, .5, 0 } end
    local playerCurrency = data[currencyData[itemTrack].currencyId]
    if not playerCurrency then
      ns.Debug.print("no 'playercurrency'")
      return { currencyData[itemTrack].format:format("No Data", "No Data"), .92, .5, 0 }
    end
    ---@cast playerCurrency wowutils_currencyData
    return { currencyData[itemTrack].format:format(playerCurrency.current or 0, playerCurrency.totalEarned or 0), 1, 1, 1 }
  end

  ---@param wlItem wowutilsDroptimizerData_wishlistItem
  ---@param itemId number
  ---@param tooltip GameTooltip
  local function addWishlistLine(wlItem, itemId, tooltip)
    local itemName = C_Item.GetItemNameByID(wlItem.itemId) or UNKNOWN -- just force user to mouseover it again, cba to do caching, at least for now TODO maybe do it later on?
    local itemIcon = select(5, GetItemInfoInstant(wlItem.itemId))
    if wlItem.itemId == itemId then
      tooltip:AddDoubleLine(sformat(">>>|T%d:0|t%s", itemIcon, itemName),
        ns.helpers.GetFormatedLastUpdateTime(wlItem.updated), 0, 1, .25)
    else
      tooltip:AddDoubleLine(sformat("|T%d:0|t%s", itemIcon, itemName),
        ns.helpers.GetFormatedLastUpdateTime(wlItem.updated), 1, 1, 1)
    end
    tooltip:AddLine(sformat("    Priotity: %s - Note: %s", wlItem.priority, wlItem.note or "N/A"), 1, 1, 1, true)
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
      -- wishlist
      local alreadyAddedTitle = false
      for _, wlItem in pairs(droptimizerData.wishlist) do
        --print(wlItem.equipmentSlot, itemInfo.equipmentSlot, isMatchingSlot(wlItem.equipmentSlot, itemInfo.equipmentSlot),  isCorrectDif(Item.difficultyId, itemInfo.itemTrack))
        if isMatchingSlot(wlItem.equipmentSlot, itemInfo.equipmentSlot) and isCorrectDif(wlItem.difficultyId, itemInfo.itemTrack) then
        --if isCorrectDif(wlItem.difficultyId, itemInfo.itemTrack) then
          if not alreadyAddedTitle then
            tooltip:AddLine("Wishlist")
            alreadyAddedTitle = true
          end
          addWishlistLine(wlItem, itemInfo.itemId, tooltip)
        end
      end
      ---@type DroptimizerFormated[]
      local allSims = {}
      for specId, sims in pairs(droptimizerData.specs) do
        for simKey, simData in pairs(sims) do
          local items = {}
          local foundItem = false
          for itemId, itemData in ns.helpers.spairs(simData.items, function(t, a, b)
            ---@cast t table<number, wowutilsDroptimizerData_droptimizerItem>
            if simData.baseline then
              return t[a].gain > t[b].gain
            else -- qelive
              return (t[a].gainPercent or 0) > (t[b].gainPercent or 0)
            end
          end) do
            ---@cast itemData wowutilsDroptimizerData_droptimizerItem
            if isMatchingSlot(itemInfo.equipmentSlot, itemData.equipmentSlot) and isCorrectDif(itemData.difficultyId, itemInfo.itemTrack) then
              --[[ if itemInfo.itemId == itemId then
                foundItem = true
              end --]]
              local itemLine = getDroptimizerLine(simData, itemInfo, itemData, itemId)
              if itemLine then
                tinsert(items, itemLine)
              end
            end
          end
          if #items > 0 then
            --if foundItem and #items > 0 then
            local substring = simKey:sub(3)
            local simType = simKey:sub(1, 1)
            ---@diagnostic disable-next-line: cast-local-type
            simType = tonumber(simType)
            local simDisplayName = sformat("%s%s-%s", ns.helpers.GetIconTextureStringForSpecId(specId),
              simType == ns.enums.simTypes.qeLiveDroptimizer and "QeLive" or
              simType == ns.enums.simTypes.raidbotDroptimizer and "RaidBots" or UNKNOWN, substring)
            tinsert(allSims, {
              displayName = simDisplayName,
              items = items,
              simmedAt = simData.simmedAt,
            })
          end
        end
      end
      if #allSims > 0 then
        for _, sim in ns.helpers.spairs(allSims, function(t, a, b) return t[a].simmedAt > t[b].simmedAt end) do
          ---@cast sim DroptimizerFormated
          tooltip:AddDoubleLine(sim.displayName, ns.helpers.GetFormatedLastUpdateTime(sim.simmedAt))
          for _, simItem in ns.helpers.spairs(sim.items, function(t, a, b)
            return t[a].percentileDif > t[b].percentileDif
          end) do
            ---@cast simItem DroptimizerLine
            tooltip:AddLine(simItem.tooltipLine, unpack(getSimLineColor(simItem.percentileDif)))
          end
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
      tooltip:AddDoubleLine("Currency", ns.helpers.GetFormatedLastUpdateTime(playerData.currencyUpdated))
      if itemInfo.itemTrack == ns.enums.itemTrack.none then
        tooltip:AddLine(unpack(formatCurrencyLine(ns.enums.itemTrack.myth, playerData.currency)))
        tooltip:AddLine(unpack(formatCurrencyLine(ns.enums.itemTrack.hero, playerData.currency)))
        tooltip:AddLine(unpack(formatCurrencyLine(ns.enums.itemTrack.champion, playerData.currency)))
        tooltip:AddLine(unpack(formatCurrencyLine(ns.enums.itemTrack.veteran, playerData.currency)))
        tooltip:AddLine(unpack(formatCurrencyLine("convert", playerData.currency)))
      else
        tooltip:AddLine(unpack(formatCurrencyLine(itemInfo.itemTrack, playerData.currency)))
        tooltip:AddLine(unpack(formatCurrencyLine("convert", playerData.currency)))
      end
      if itemInfo.watermarkSlot then
        tooltip:AddDoubleLine("Watermarks", ns.helpers.GetFormatedLastUpdateTime(playerData.watermarksUpdated or 0))
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
  table.insert(ns.rclc.votingWindow.scrollCols, {
    name = columnName,
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

function rclcMod.UpdateMainModCell(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
  ASDF = { rowFrame, frame, data, cols, row, realrow, column, fShow, table }
  local name = data[realrow].name
  local guid = UnitGUID(Ambiguate(name, "short"))
  local n, s = strsplit("-", name)
  local droptimizerKey = sformat("%s-%s", n:lower(), ns.GetRealmId(nil, s))
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:AddLine(name)
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
      GameTooltip:AddLine("Player")
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
