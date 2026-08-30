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

  ---@param entry wowutilsDroptimizerData_droptimizerItem
  ---@param simType wowutils_enums_simTypes
  ---@return number
  local function entryValue(entry, simType)
    if simType == ns.enums.simTypes.qeLiveDroptimizer then return entry.gainPercent or 0 end
    return entry.gain or 0
  end

  ---A tier token is not equippable, so it has no slot to match on and never appears in `items`
  ---under its own id. What it is worth is whatever it converts into, which the sims record the
  ---other way round: each piece carries `sourceItem.itemId` pointing back at the token.
  ---@param itemInfo CurrentItemInfo
  ---@return boolean
  local function isConvertedItem(itemInfo)
    return (itemInfo.invSlotId or 0) == 0
  end

  ---@param entry wowutilsDroptimizerData_droptimizerItem
  ---@param itemId number the item being looted
  ---@return boolean
  local function convertsFrom(entry, itemId)
    return entry.sourceItem ~= nil and entry.sourceItem.itemId == itemId
  end

  ---Every result in this sim that the looted item accounts for: normally the entries stored under
  ---its own id, but for a token the entries of every piece it turns into.
  ---@param simData wowutilsDroptimizerData_sims
  ---@param itemInfo CurrentItemInfo
  ---@return wowutilsDroptimizerData_droptimizerItem[]?
  local function entriesForViewedItem(simData, itemInfo)
    if not isConvertedItem(itemInfo) then return simData.items[itemInfo.itemId] end
    local found
    for _, entries in pairs(simData.items) do
      for i = 1, #entries do
        if convertsFrom(entries[i], itemInfo.itemId) then
          found = found or {}
          found[#found + 1] = entries[i]
        end
      end
    end
    return found
  end

  ---A sim can hold several results for one itemId: a ring simmed into both finger slots, or a
  ---piece reachable both as a drop and through the catalyst. For a single-value display we take
  ---whichever placement gains the most, since that is where the player would actually equip it.
  ---@param entries wowutilsDroptimizerData_droptimizerItem[]?
  ---@param itemTrack number
  ---@param simType wowutils_enums_simTypes
  ---@return wowutilsDroptimizerData_droptimizerItem?
  local function bestEntryFor(entries, itemTrack, simType)
    if not entries then return nil end
    local best
    for i = 1, #entries do
      local entry = entries[i]
      if isCorrectDif(entry.difficultyId, itemTrack) then
        if not best or entryValue(entry, simType) > entryValue(best, simType) then
          best = entry
        end
      end
    end
    return best
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
          local entry = bestEntryFor(entriesForViewedItem(simData, itemInfo), itemInfo.itemTrack, simData.simType)
          if entry then
            if simData.simType == ns.enums.simTypes.raidbotDroptimizer then
              local dif = ((entry.gain or 0)/(simData.baseline or 1)) * 100
              local val = sformat("%s (%.2f%%)", entry.gain or 0, dif)
              if simKey:lower():match(raidbotsMatchStr) then -- patchwork 1 target sim, not gonna find a better match (?) TODO maybe figure out something better, in theory there could be multiple
                return val, getSimLineColor(dif)
              end
              bestItem = val
              bestDif = dif
            elseif simData.simType == ns.enums.simTypes.qeLiveDroptimizer then
              local pct = entry.gainPercent or 0
              local val = sformat("%.2f%%", pct)
              if simKey:lower():match(qeLiveMatchStr) then -- patchwork 1 target sim, not gonna find a better match (?) TODO maybe figure out something better, in theory there could be multiple
                return val, getSimLineColor(pct)
              end
              bestItem = val
              bestDif = pct
            else
              bestItem = entry.gain
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
  ---0 means "no slot", both for items that have none (tier tokens) and for slot strings the import
  ---could not parse. Comparing those as a value makes every unknown match every other unknown, so
  ---a token would pull in whatever item happened to fail parsing.
  local function isMatchingSlot(slot1, slot2)
    if not slot1 or not slot2 or slot1 == 0 or slot2 == 0 then return false end
    if slot1 == slot2 then return true end
    return ns.helpers.GetUniversalSlot(slot1) == ns.helpers.GetUniversalSlot(slot2)
  end
  local trackNames = {
    [ns.enums.itemTrack.adventurer] = "Adventurer",
    [ns.enums.itemTrack.veteran] = "Veteran",
    [ns.enums.itemTrack.champion] = "Champion",
    [ns.enums.itemTrack.hero] = "Hero",
    [ns.enums.itemTrack.myth] = "Myth",
  }
  local sourceNames = {
    [ns.enums.simTypes.raidbotDroptimizer] = "RB",
    [ns.enums.simTypes.qeLiveDroptimizer] = "QE",
  }

  ---"mythic-max" -> "Mythic max", "raid-vault-mythic" -> "Raid vault mythic"
  ---@param key string
  ---@return string
  local function prettyKey(key)
    local words = key:gsub("[-_]", " ")
    return words:sub(1, 1):upper() .. words:sub(2)
  end

  ---simKey is "<simType>-<profileKey>-<fightStyle or 0>-<targets>" as written by dataImport.
  ---@param simKey string
  ---@return string source
  ---@return string profile
  ---@return string targets
  local function parseSimKey(simKey)
    local simType, rest = simKey:match("^(%d+)%-(.*)$")
    local source = sourceNames[tonumber(simType)] or "?"
    local profile, fightStyle, targets = (rest or simKey):match("^(.-)%-([^-]*)%-(%d+)$")
    if not profile then return source, rest or simKey, "" end
    local style = fightStyle ~= "0" and prettyKey(fightStyle) or nil
    local targetText = targets == "1" and "1 target" or (targets .. " targets")
    return source, prettyKey(profile), style and sformat("%s · %s", style, targetText) or targetText
  end

  ---Gain text + percentile for one simmed item, whichever sim source produced it.
  ---@param simData wowutilsDroptimizerData_sims
  ---@param itemData wowutilsDroptimizerData_droptimizerItem
  ---@return string gainText absolute gain, "" when the source only carries a percentage
  ---@return string pctText
  ---@return number percentile
  local function formatGain(simData, itemData)
    if not simData.baseline then -- qelive
      local pct = itemData.gainPercent or 0
      return "", sformat("%+.2f%%", pct), pct
    end
    local pct = ((itemData.gain or 0) / simData.baseline) * 100
    return sformat("%+.0f", itemData.gain or 0), sformat("%+.2f%%", pct), pct
  end

  ---How a piece is obtained when it is not a straight drop, nil when it is one. The card shows
  ---this as the source's icon rather than words, so this is only used to tell results apart.
  ---@param entry wowutilsDroptimizerData_droptimizerItem
  ---@return string?
  local function conversionKeyOf(entry)
    local source = entry.sourceItem
    if not source then return nil end
    if source.catalyst then return "catalyst" end
    return "source:" .. tostring(source.itemId)
  end

  ---What tells one result for an item apart from another within the same sim: how it is reached
  ---(catalyst charge, tier token) when that differs, otherwise the slot it was simmed into.
  ---@param entry wowutilsDroptimizerData_droptimizerItem
  ---@return string?
  local function entryLabelOf(entry)
    return conversionKeyOf(entry) or ns.helpers.GetEquipmentSlotName(entry.equipmentSlot)
  end

  ---Marks a result the viewer cannot simply loot. Carried as ids, the tooltip turns them into
  ---icons: the catalyst atlas, or the icon of the token the piece converts from.
  ---@param row wowutils_tooltip_simRow|wowutils_tooltip_otherRow
  ---@param entry wowutilsDroptimizerData_droptimizerItem
  local function markSource(row, entry)
    local source = entry.sourceItem
    if not source then return end
    if source.catalyst then
      row.catalyst = true
    else
      row.sourceItemId = source.itemId
    end
  end

  ---@param wlItem wowutilsDroptimizerData_wishlistItem
  ---@return wowutils_tooltip_pick
  local function pickOf(wlItem)
    return {
      itemId = wlItem.itemId,
      label = wlItem.priority,
      priorityId = wlItem.priorityId,
      updated = wlItem.updated,
      note = wlItem.note,
    }
  end

  ---Everything the candidate card shows for one candidate and the item being viewed.
  ---@param guid string?
  ---@param droptimizerKey string
  ---@param candidateName string name-realm as rclc stores it
  ---@param entryItem table? rclc item entry, defaults to the current voting session's item
  ---@return wowutils_tooltip_model?
  function ns.rclc.BuildCandidateModel(guid, droptimizerKey, candidateName, entryItem)
    local itemInfo = getItemInfo(entryItem)
    if not itemInfo then return nil end
    local droptimizerData = WowUtilsDB.droptimizerData[droptimizerKey]
    ns.Debug.AddToDevTool({ itemInfo = itemInfo, droptimizerData = droptimizerData }, "ns.rclc.BuildCandidateModel")

    local shortName, realm = ns.helpers.SplitFullName(candidateName)
    local classFile = UnitClassBase(Ambiguate(candidateName, "none"))
    if not classFile and droptimizerData and droptimizerData.class and droptimizerData.class > 0 then
      classFile = select(2, GetClassInfo(droptimizerData.class))
    end
    local _, _, _, equipLoc, icon = GetItemInfoInstant(itemInfo.itemLink)
    local ilvl = C_Item.GetDetailedItemLevelInfo(itemInfo.itemLink)
    local subtitle = {}
    if equipLoc and _G[equipLoc] then tinsert(subtitle, _G[equipLoc]) end
    if ilvl then tinsert(subtitle, tostring(ilvl)) end
    if trackNames[itemInfo.itemTrack] then tinsert(subtitle, trackNames[itemInfo.itemTrack]) end

    ---@type wowutils_tooltip_model
    local m = {
      item = {
        itemId = itemInfo.itemId,
        name = C_Item.GetItemNameByID(itemInfo.itemId) or UNKNOWN,
        icon = icon or 134400,
        subtitle = tconcat(subtitle, "  ·  "),
      },
      candidate = { name = shortName or candidateName, realm = realm, classFile = classFile },
      otherPicks = {},
      sims = {},
      others = {},
      noPlayerData = false,
    }

    ---@type table<number, boolean>? pieces this character's sims reach through the looted item,
    ---whether it is a token that becomes them or a base item the catalyst turns into one
    local convertsInto
    if droptimizerData then
      -- collected before the wishlist runs, both sections key off the same set
      convertsInto = {}
      for _, sims in pairs(droptimizerData.specs) do
        for _, simData in pairs(sims) do
          for itemId, entries in pairs(simData.items) do
            for i = 1, #entries do
              if convertsFrom(entries[i], itemInfo.itemId) then convertsInto[itemId] = true end
            end
          end
        end
      end
    end

    if droptimizerData then
      -- Wishlist: the viewed item first, then other picks at this difficulty -- in the same slot,
      -- or on anything the looted item converts into.
      for _, wlItem in pairs(droptimizerData.wishlist) do
        if isCorrectDif(wlItem.difficultyId, itemInfo.itemTrack) then
          if wlItem.itemId == itemInfo.itemId then
            -- matched on the item itself, no slot involved. the rclc column does the same, and
            -- filtering this through the slot as well used to hide a token's own pick from the card
            m.viewedPick = pickOf(wlItem)
          elseif convertsInto and convertsInto[wlItem.itemId] then
            tinsert(m.otherPicks, pickOf(wlItem))
          elseif isMatchingSlot(wlItem.equipmentSlot, itemInfo.invSlotId) then
            tinsert(m.otherPicks, pickOf(wlItem))
          end
        end
      end

      -- Droptimizers: one row per sim for the viewed item; every other same-slot item
      -- collapses to its single best result across all sims.
      ---@type table<number, wowutils_tooltip_otherRow>
      local bestOther = {}
      -- one row per result rather than per sim: a sim can report the viewed item more than once
      -- (both finger slots, catalyst as well as direct drop) and each is a real, different number.
      -- rows stay grouped by the sim that produced them, best sim first.
      ---a row paired with the sim result it was built from, which is what its label comes from
      ---@class wowutils_rclc_simGroupRow
      ---@field row wowutils_tooltip_simRow
      ---@field entry wowutilsDroptimizerData_droptimizerItem
      ---@field itemId number the item the result is for, which is not the looted one for a conversion
      ---@field converts boolean? the result is something the looted item turns into, not the item itself

      ---@type {rank: number, rows: wowutils_rclc_simGroupRow[]}[]
      local simGroups = {}
      local labelRows = false
      for specId, sims in pairs(droptimizerData.specs) do
        for simKey, simData in pairs(sims) do
          local source, profile, targets
          ---@type wowutils_rclc_simGroupRow[]
          local rows = {}
          -- only results for the item itself decide whether rows need telling apart. a conversion
          -- is always named after what it produces, so it never makes the plain rows ambiguous
          local plainRows = 0
          for itemId, itemEntries in pairs(simData.items) do
            for i = 1, #itemEntries do
              local itemData = itemEntries[i]
              if isCorrectDif(itemData.difficultyId, itemInfo.itemTrack) then
                -- what the looted item turns into is a result *of* that item, not an alternative
                -- to it: a token becoming a piece, or a base item the catalyst converts
                local converts = convertsFrom(itemData, itemInfo.itemId)
                local sameSlot = isMatchingSlot(itemInfo.invSlotId, itemData.equipmentSlot)
                if converts or sameSlot then
                  if not source then source, profile, targets = parseSimKey(simKey) end
                  local gainText, pctText, pct = formatGain(simData, itemData)
                  if converts or itemId == itemInfo.itemId then
                    if not converts then plainRows = plainRows + 1 end
                    tinsert(rows, {
                      row = {
                        specId = specId,
                        source = source,
                        profile = profile,
                        targets = targets,
                        simmedAt = simData.simmedAt,
                        gainText = gainText,
                        pctText = pctText,
                        pct = pct,
                      },
                      entry = itemData,
                      itemId = itemId,
                      converts = converts or nil,
                    })
                  elseif not bestOther[itemId] or bestOther[itemId].pct < pct then
                    local other = { itemId = itemId, simLabel = profile, gainText = gainText, pctText = pctText, pct = pct }
                    markSource(other, itemData)
                    bestOther[itemId] = other
                  end
                end
              end
            end
          end
          if #rows > 0 then
            -- once any sim splits into several rows every row gets labelled, the same way a mixed
            -- source turns the source prefix on for all of them. one labelled row next to a bare
            -- one reads like the bare one is missing something
            if plainRows > 1 then labelRows = true end
            table.sort(rows, function(x, y) return x.row.pct > y.row.pct end)
            tinsert(simGroups, { rank = rows[1].row.pct, rows = rows })
          end
        end
      end
      table.sort(simGroups, function(x, y) return x.rank > y.rank end)
      for _, group in ipairs(simGroups) do
        for i = 1, #group.rows do
          local paired = group.rows[i]
          local conversion = conversionKeyOf(paired.entry)
          -- a conversion is marked whether or not anything is ambiguous, an unmarked row reads as
          -- "this just drops"
          if labelRows or conversion then
            local label
            if paired.converts then
              -- this row is what the looted item becomes, so name that rather than the slot. it
              -- converts from the item being looted, so repeating its icon would say nothing --
              -- only whether the catalyst is involved adds anything
              label = C_Item.GetItemNameByID(paired.itemId)
                or ns.helpers.GetEquipmentSlotName(paired.entry.equipmentSlot)
                or tostring(paired.itemId)
              if paired.entry.sourceItem and paired.entry.sourceItem.catalyst then
                paired.row.catalyst = true
              end
            else
              -- a conversion carries its source icon instead of a word, so it needs no text label
              markSource(paired.row, paired.entry)
              label = not conversion and ns.helpers.GetEquipmentSlotName(paired.entry.equipmentSlot) or nil
              -- two results that label the same (same slot, same source) are only told apart by
              -- their item level, so fall back to it rather than showing two identical rows
              for j = 1, #group.rows do
                if j ~= i and label and label == entryLabelOf(group.rows[j].entry) then
                  label = sformat("%s %s", label, paired.entry.ilvl)
                  break
                end
              end
            end
            paired.row.entryLabel = label
          end
          tinsert(m.sims, paired.row)
        end
        m.simCount = (m.simCount or 0) + 1
      end
      for _, row in pairs(bestOther) do tinsert(m.others, row) end
      table.sort(m.others, function(x, y) return x.pct > y.pct end)
      local maxOther = 6
      while #m.others > maxOther do tremove(m.others) end
    end

    local playerData
    if guid and guid == ns.me.guid then
      playerData = WowUtilsDB.ownCharacters[guid]
    elseif guid then
      playerData = WowUtilsDB.others[guid]
    end
    if not playerData then
      m.noPlayerData = true
      return m
    end

    m.crestsUpdated = playerData.dataRefreshTimes and playerData.dataRefreshTimes.currency or playerData.currencyUpdated
    m.crests = {}
    local tracks
    if itemInfo.itemTrack == ns.enums.itemTrack.none then
      tracks = { ns.enums.itemTrack.myth, ns.enums.itemTrack.hero, ns.enums.itemTrack.champion, ns.enums.itemTrack.veteran, "convert", "bonusCoin" }
    else
      tracks = { itemInfo.itemTrack, "convert", "bonusCoin" }
    end
    for _, track in ipairs(tracks) do
      local cd = currencyData[track]
      if cd then
        local ci = C_CurrencyInfo.GetCurrencyInfo(cd.currencyId)
        local pc = playerData.currency and playerData.currency[cd.currencyId]
        tinsert(m.crests, {
          icon = ci and ci.iconFileID or 134400,
          current = pc and pc.current or 0,
          earned = pc and pc.totalEarned or 0,
        })
      end
    end

    if itemInfo.watermarkSlot then
      m.watermarksUpdated = playerData.dataRefreshTimes and playerData.dataRefreshTimes.watermarks or playerData.watermarksUpdated or 0
      m.watermarks = {}
      local wm = playerData.watermarks or {}
      if weaponSlots[itemInfo.watermarkSlot] then
        tinsert(m.watermarks, { label = "Main hand", value = wm[Enum.ItemRedundancySlot.MainhandWeapon] or 0 })
        tinsert(m.watermarks, { label = "Off hand", value = wm[Enum.ItemRedundancySlot.Offhand] or 0 })
        tinsert(m.watermarks, { label = "One-hand", value = wm[Enum.ItemRedundancySlot.OnehandWeapon] or 0 })
        tinsert(m.watermarks, { label = "One-hand (second)", value = wm[Enum.ItemRedundancySlot.OnehandWeaponSecond] or 0 })
        tinsert(m.watermarks, { label = "Two-hand", value = wm[Enum.ItemRedundancySlot.Twohand] or 0 })
      else
        tinsert(m.watermarks, { label = "This slot", value = wm[itemInfo.watermarkSlot] or 0 })
      end
    end
    return m
  end

  ---Shows the candidate card at the cursor for the owner widget being hovered.
  ---@param owner Frame
  ---@param guid string?
  ---@param droptimizerKey string
  ---@param candidateName string
  ---@param entryItem table?
  function ns.rclc.ShowCandidateCard(owner, guid, droptimizerKey, candidateName, entryItem)
    local model = ns.rclc.BuildCandidateModel(guid, droptimizerKey, candidateName, entryItem)
    if not model then return end
    ns.tooltip.Show(owner, model)
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
  -- A character we already hold data for built its own key from its own GetRealmID(), so take that
  -- over rebuilding one from the realm name rclc hands us. Same thing publicAPI does with a guid.
  local stored = guid and (WowUtilsDB.ownCharacters[guid] or WowUtilsDB.others[guid])
  if stored and stored.droptimizerKey then
    return guid, stored.droptimizerKey
  end
  local n, s = ns.helpers.SplitFullName(name)
  local realmId = s and ns.GetRealmId(nil, s) or ns.me.realmId
  return guid, sformat("%s-%s", n:lower(), realmId)
end

---Hover on any of our cells shows the full per-candidate breakdown for the viewed item.
local function attachRowTooltip(frame, name, guid, droptimizerKey)
  frame:SetScript("OnEnter", function(self)
    ns.rclc.ShowCandidateCard(self, guid, droptimizerKey, name)
  end)
  frame:SetScript("OnLeave", ns.tooltip.Hide)
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
      ns.rclc.ShowCandidateCard(self, ns.me.guid, ns.me.droptimizerKey, ns.me.name, entry.item)
    end)
    b:SetScript("OnLeave", ns.tooltip.Hide)
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
