---@class wowutilsPrivate
---@field gui table

---@type string, wowutilsPrivate
local addon_name, ns = ...

local GetServerTime, sformat, floor, srep = GetServerTime, string.format, math.floor, string.rep

local FRAME_WIDTH, FRAME_HEIGHT = 760, 520
local ROW_HEIGHT = 30
local ROW_SPACING = 2
local HEADER_HEIGHT = 46

local COLORS = {
  window      = { 0.06, 0.06, 0.08, 0.97 },
  windowSolid = { 0.06, 0.06, 0.08, 1 },
  header      = { 0.10, 0.11, 0.13, 1 },
  panel       = { 0.09, 0.09, 0.11, 0.95 },
  row         = { 0.12, 0.12, 0.15, 0.85 },
  rowAlt      = { 0.14, 0.14, 0.17, 0.85 },
  rowHover    = { 0.19, 0.24, 0.31, 0.95 },
  border      = { 0.18, 0.19, 0.24, 1 },
  button      = { 0.14, 0.15, 0.18, 1 },
  buttonHover = { 0.20, 0.22, 0.27, 1 },
  buttonDown  = { 0.10, 0.11, 0.14, 1 },
  accent      = { 0.22, 0.70, 0.44, 1 },
  text        = { 0.93, 0.94, 0.96, 1.0 },
  muted       = { 0.60, 0.63, 0.70, 1.0 },
}

-- flat 1px bordered surfaces, the tiled tooltip textures look dated
local FLAT_BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Buttons\\WHITE8X8",
  edgeSize = 1,
}

local function GetAddonVersion()
  return C_AddOns.GetAddOnMetadata(addon_name, "Version")
end

---@param frame table backdrop frame
---@param bgColor table
---@param borderColor table?
local function ApplyFlatTheme(frame, bgColor, borderColor)
  frame:SetBackdrop(FLAT_BACKDROP)
  frame:SetBackdropColor(unpack(bgColor))
  frame:SetBackdropBorderColor(unpack(borderColor or COLORS.border))
end

local function ApplyPanelTheme(frame)
  ApplyFlatTheme(frame, COLORS.panel)
end

local function ApplyWindowTheme(frame)
  ApplyFlatTheme(frame, COLORS.window)
end

---@param parent Frame
---@param text string
---@param width number?
---@param height number?
local function CreateButton(parent, text, width, height)
  local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
  button:SetSize(width or 80, height or 22)
  ApplyFlatTheme(button, COLORS.button)

  local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("CENTER")
  label:SetTextColor(unpack(COLORS.text))
  button:SetFontString(label)
  button:SetText(text)
  button.label = label

  button:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(COLORS.buttonHover)) end)
  button:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(COLORS.button)) end)
  button:SetScript("OnMouseDown", function(self) self:SetBackdropColor(unpack(COLORS.buttonDown)) end)
  button:SetScript("OnMouseUp", function(self)
    self:SetBackdropColor(unpack(self:IsMouseOver() and COLORS.buttonHover or COLORS.button))
  end)

  return button
end

---Checkbox with a muted label to its right, matching the button/tab styling.
---@param parent Frame
---@param text string
---@param onClick fun(checked: boolean)
local function CreateCheckbox(parent, text, onClick)
  local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  check:SetSize(22, 22)

  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("LEFT", check, "RIGHT", 2, 1)
  label:SetText(text)
  label:SetTextColor(unpack(COLORS.muted))
  check.label = label

  check:SetScript("OnEnter", function() label:SetTextColor(unpack(COLORS.text)) end)
  check:SetScript("OnLeave", function() label:SetTextColor(unpack(COLORS.muted)) end)
  check:SetScript("OnClick", function(self)
    onClick(self:GetChecked() and true or false)
  end)

  return check
end

---Muted caption above an option control.
---@param parent Frame
---@param text string
local function CreateOptionLabel(parent, text)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetText(text)
  label:SetTextColor(unpack(COLORS.muted))
  return label
end

---@param parent Frame
---@param width number
---@param minValue number
---@param maxValue number
---@param step number
---@param value number
---@param format fun(value: number): string
---@param onChange fun(value: number)
local function CreateSlider(parent, width, minValue, maxValue, step, value, format, onChange)
  local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
  slider:SetWidth(width)
  local steps = floor((maxValue - minValue) / step + 0.5)
  ---@diagnostic disable-next-line: param-type-mismatch
  slider:Init(value, minValue, maxValue, steps, {
    [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(MinimalSliderWithSteppersMixin.Label.Right, format),
  })
  ---@diagnostic disable-next-line: param-type-mismatch
  slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, newValue)
    -- fractional steps drift (0.30000000000000004), snap back onto the step grid
    onChange(floor(newValue / step + 0.5) * step)
  end, slider)
  return slider
end

---@param parent Frame
---@param width number
---@param options {text:string, value:any}[]|fun(): {text:string, value:any}[] function gets called every time the menu opens
---@param getValue fun(): any
---@param onSelect fun(value: any)
---@param scrollHeight number? long lists scroll instead of running off screen
local function CreateDropdown(parent, width, options, getValue, onSelect, scrollHeight)
  local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  dropdown:SetWidth(width)
  dropdown:SetupMenu(function(_, rootDescription)
    if scrollHeight then
      rootDescription:SetScrollMode(scrollHeight)
    end
    for _, option in ipairs(type(options) == "function" and options() or options) do
      rootDescription:CreateRadio(option.text, function() return getValue() == option.value end, function() onSelect(option.value) end)
    end
  end)
  return dropdown
end

---Small bordered square showing a color, opens the color picker on click.
---@param parent Frame
---@param color {r:number, g:number, b:number} edited in place
---@param onChange fun()
local function CreateColorSwatch(parent, color, onChange)
  local swatch = CreateFrame("Button", nil, parent, "BackdropTemplate")
  swatch:SetSize(40, 20)
  ApplyFlatTheme(swatch, COLORS.button)
  local fill = swatch:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT", 2, -2)
  fill:SetPoint("BOTTOMRIGHT", -2, 2)

  local function setColor(r, g, b)
    color.r, color.g, color.b = r, g, b
    fill:SetColorTexture(r, g, b)
    onChange()
  end
  fill:SetColorTexture(color.r, color.g, color.b)

  swatch:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(COLORS.accent)) end)
  swatch:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(COLORS.border)) end)
  swatch:SetScript("OnClick", function()
    local oldR, oldG, oldB = color.r, color.g, color.b
    ColorPickerFrame:SetupColorPickerAndShow({
      r = oldR, g = oldG, b = oldB,
      hasOpacity = false,
      swatchFunc = function()
        setColor(ColorPickerFrame:GetColorRGB())
      end,
      cancelFunc = function()
        setColor(oldR, oldG, oldB)
      end,
    })
  end)
  return swatch
end

---Underline style tab, the active one gets an accent bar and brighter text.
---@param parent Frame
---@param text string
local function CreateTab(parent, text)
  local tab = CreateFrame("Button", nil, parent)
  tab:SetHeight(28)

  local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("CENTER", 0, 2)
  tab:SetFontString(label)
  tab:SetText(text)
  tab:SetWidth(math.max(90, label:GetStringWidth() + 30))

  local underline = tab:CreateTexture(nil, "ARTWORK")
  underline:SetColorTexture(unpack(COLORS.accent))
  underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 6, 0)
  underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -6, 0)
  underline:SetHeight(2)
  underline:Hide()

  function tab:SetSelected(selected)
    self.selected = selected and true or false
    underline:SetShown(self.selected)
    label:SetTextColor(unpack(self.selected and COLORS.text or COLORS.muted))
  end

  tab:SetScript("OnEnter", function(self)
    if not self.selected then label:SetTextColor(unpack(COLORS.text)) end
  end)
  tab:SetScript("OnLeave", function(self)
    if not self.selected then label:SetTextColor(unpack(COLORS.muted)) end
  end)

  tab:SetSelected(false)

  return tab
end

local function EnableHyperlinks(editBox)
  editBox:SetHyperlinksEnabled(true)

  editBox:SetScript("OnHyperlinkEnter", function(self, link)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    if GameTooltip:SetHyperlink(link) then
      GameTooltip:Show()
    end
  end)

  editBox:SetScript("OnHyperlinkLeave", function()
    GameTooltip:Hide()
  end)

  editBox:SetScript("OnHyperlinkClick", function(self, link, text, button)
    SetItemRef(link, text, button)
  end)
end

local function CreateLinkText(parent, multiLine, fontObject)
  local box = CreateFrame("EditBox", nil, parent)
  box:SetMultiLine(multiLine)
  box:SetAutoFocus(false)
  box:SetFontObject(fontObject or GameFontHighlightSmall)
  box:SetTextColor(unpack(COLORS.text))
  box:EnableMouse(true)

  box.originalText = ""
  box.selectable = false

  box:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
      local cursor = self:GetCursorPosition()
      self:SetText(self.originalText)
      self:SetCursorPosition(math.min(cursor, #self.originalText))
    end
  end)

  box:SetScript("OnEditFocusGained", function(self)
    self:HighlightText()
  end)
  box:SetScript("OnEditFocusLost", function(self)
    self:HighlightText(0, 0)
  end)
  box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)

  EnableHyperlinks(box)

  function box:SetLockedText(text)
    self.originalText = text or ""
    self:SetText(self.originalText)
    self:SetCursorPosition(0)
  end

  function box:SetSelectable(enabled)
    self.selectable = enabled and true or false
    self:SetEnabled(self.selectable)
    if not self.selectable then
      self:ClearFocus()
    end
  end

  box:SetEnabled(false)

  return box
end
local function GetClassColorForValue(classValue)
  local classToken

  if type(classValue) == "number" then
    local _, classFilename = GetClassInfo(classValue)
    classToken = classFilename
  elseif type(classValue) == "string" and classValue ~= "" then
    classToken = classValue
  end

  if not classToken then
    return nil
  end

  local normalized = classToken:upper()

  if C_ClassColor and C_ClassColor.GetClassColor then
    local color = C_ClassColor.GetClassColor(normalized)
    if color then
      return color.r, color.g, color.b
    end
  end

  if RAID_CLASS_COLORS and RAID_CLASS_COLORS[normalized] then
    local color = RAID_CLASS_COLORS[normalized]
    return color.r, color.g, color.b
  end

  return nil
end

---Class color goes on the accent bar and the name only, a fully tinted row is too loud to read.
---@param row table
---@param classValue string|number?
---@param index number used for the zebra striping
local function ApplyRowStyle(row, classValue, index)
  row.baseColor = (index % 2 == 0) and COLORS.rowAlt or COLORS.row
  row:SetBackdropColor(unpack(row.baseColor))

  local r, g, b = GetClassColorForValue(classValue)
  if r then
    row.accent:SetColorTexture(r, g, b, 1)
    row.name:SetTextColor(r, g, b, 1)
  else
    row.accent:SetColorTexture(unpack(COLORS.accent))
    row.name:SetTextColor(unpack(COLORS.text))
  end
end
---Median over every slot we have a watermark for. Slots the character can't fill (offhand on a
---two-hander, and anything at or below ns.config.watermarks.startingPoint once it has been through
---the wire encoding) are stored as 0, and they belong in the median - a character who is only geared
---in a handful of slots should read as low, not as the average of the slots they did upgrade.
---@param watermarks table<number, number>?
---@return number? median nil when the character has no watermark data at all
local function GetWatermarkMedian(watermarks)
  if type(watermarks) ~= "table" then
    return nil
  end

  local values = {}
  for _, ilvl in pairs(watermarks) do
    values[#values + 1] = ilvl or 0
  end
  if #values == 0 then
    return nil
  end

  table.sort(values)
  local half = #values / 2
  if #values % 2 == 1 then
    return values[floor(half) + 1]
  end
  return (values[half] + values[half + 1]) / 2
end

---Roster filters, both stored on WowUtilsDB.options.characterFilters so they survive a reload. They
---stack: a character is dropped as soon as any enabled filter matches it.
---@param entry table
---@return boolean
local function IsFilteredOut(entry)
  local filters = WowUtilsDB.options and WowUtilsDB.options.characterFilters or {}

  if filters.hideUntracked and not (entry.syncLists and #entry.syncLists > 0) then
    return true
  end

  if filters.hideLowIlvl then
    local median = GetWatermarkMedian(entry.data and entry.data.watermarks)
    -- no watermarks at all means we can't tell, so those stay visible rather than silently vanish
    if median and median < ns.config.guiIlvlFilter then
      return true
    end
  end

  return false
end

local function GetCharacterList()
  local list = {}
  local droptimizerKeysToSynclist = {}
  for listId,listData in pairs(WowUtilsDB.syncLists) do
    for _, droptimizerKey in pairs(listData.characters) do
      if not droptimizerKeysToSynclist[droptimizerKey] then
        droptimizerKeysToSynclist[droptimizerKey] = {}
      end
      tinsert(droptimizerKeysToSynclist[droptimizerKey], listId)
    end
  end

  local function AddCharacter(data, update)
    local entry = {
      kind = "character",
      data = data,
      name = data.fullSlug or UNKNOWN,
      update = update,
      class = data.class,
      version = data.addonVersion or "?", -- only synced since 1.0.0, older characters never sent one
      syncLists = droptimizerKeysToSynclist[data.droptimizerKey]
    }
    if IsFilteredOut(entry) then return end
    tinsert(list, entry)
  end

  for _, data in pairs(WowUtilsDB.ownCharacters) do
    AddCharacter(data, data.lastUpdate or data.lastUpdateReceived or 0)
  end

  for _, data in pairs(WowUtilsDB.others) do
    AddCharacter(data, data.lastUpdateReceived or data.lastUpdate or 0)
  end

  table.sort(list, function(a, b)
    return (a.name or "") < (b.name or "")
  end)

  return list
end

local function GetDroptimizerList()
  local list = {}

  for key, data in pairs(WowUtilsDB and WowUtilsDB.droptimizerData or {}) do
    list[#list + 1] = {
      kind = "droptimizer",
      key = key,
      data = data,
      name = data.characterName or key,
      update = data.lastUpdate or 0,
      class = data.class
    }
  end

  table.sort(list, function(a, b)
    return (a.name or "") < (b.name or "")
  end)

  return list
end

---@param str any
---@param indentLevel number? defaults to 1
---@return any
local function pad(str, indentLevel)
  if indentLevel == 0 then return str end
  return srep("    ", indentLevel or 1) .. str
end

local function getColoredBoolean(val)
  if val == true then
    return "|cff00ff00true|r"
  elseif val == false then
    return "|cffff0000false|r"
  end
  return tostring(val)
end

-- characters synced from older addon versions can lack whole data tables
local function safeTable(t)
  return type(t) == "table" and t or {}
end

local watermarkNameCache = {}
for name, value in pairs(Enum.ItemRedundancySlot) do
  watermarkNameCache[value] = name
end
local function BuildDetailTextForCharacter(char)
  local lines = {}
  ---@cast char wowutils_ownChar|wowutils_otherChar
  tinsert(lines, "Character details")
  tinsert(lines, "-----------------")
  tinsert(lines, "Name: " .. (char.fullSlug or "-"))
  tinsert(lines, "GUID: " .. (char.guid or "-"))
  tinsert(lines, "Region: " .. (char.region or "-"))
  tinsert(lines, "Last update " .. ns.helpers.GetFormatedLastUpdateTime(char.lastUpdate))
  tinsert(lines, "Last update received " .. ns.helpers.GetFormatedLastUpdateTime(char.lastUpdateReceived))
  tinsert(lines, "Last logout " .. ns.helpers.GetFormatedLastUpdateTime(char.lastLogout))
  tinsert(lines, "Droptimizer key: " .. tostring(char.droptimizerKey or "-"))
  if ns.IsRetail then -- sparks, vault and weekly rewards aren't tracked on forever
    tinsert(lines, sformat("Sparks %s: %s", ns.helpers.GetFormatedLastUpdateTime(char.craftingItemsUpdated), char.craftingItems or 0))

    tinsert(lines, "Vault data " .. ns.helpers.GetFormatedLastUpdateTime(char.vaultDataLastUpdate))
    if type(char.vaultData) ~= "table" or not next(char.vaultData) then
      tinsert(lines, pad("none"))
    end
    for _, vaultData in ipairs(safeTable(char.vaultData)) do
      ---@cast vaultData wowutils_vaultData_items
      tinsert(lines, pad(sformat("%s (%s)%s", vaultData.itemId == 1 and "Currency" or vaultData.itemId == 2 and "Coin" or vaultData.itemLink or UNKNOWN, (vaultData.itemLevel or 0) > 0 and vaultData.itemLevel or "?", vaultData.picked and " |cff00ff00Picked|r" or "")))
    end
    tinsert(lines, "Weekly Rewards " .. ns.helpers.GetFormatedLastUpdateTime(char.weeklyRewardsUpdate))
    local weeklyRewardsFound = false
    for k,v in pairs(safeTable(char.weeklyRewards)) do
      weeklyRewardsFound = true
      tinsert(lines, pad(sformat("%s : %s", k, v)))
    end
    if not weeklyRewardsFound then
      tinsert(lines, pad("none"))
    end
  end
  tinsert(lines, "Currency " .. ns.helpers.GetFormatedLastUpdateTime(char.currencyUpdated))
  local currencyFound =  false
  for currencyId, currencyData in pairs(safeTable(char.currency)) do
    currencyFound = true
    local current = currencyData and currencyData.current or "-"
    local totalEarned = currencyData and currencyData.totalEarned or "-"
    local ci = C_CurrencyInfo.GetCurrencyInfo(currencyId)
    tinsert(lines, pad(sformat("%s %s/%s", C_CurrencyInfo.GetCurrencyLink(currencyId) or ci and ci.name or UNKNOWN, current, totalEarned)))
  end
    if not currencyFound then
    tinsert(lines, pad("none"))
  end

  tinsert(lines, "Quests " .. ns.helpers.GetFormatedLastUpdateTime(char.questsUpdated))
  for questId, questData in pairs(safeTable(char.quests)) do
    local questName = C_QuestLog.GetTitleForQuestID(questId) or questId
    tinsert(lines, pad(sformat("|Hquest:%s:90|h%s|h (%s)", questId, questName, questId)))
    tinsert(lines, pad(sformat("completed: %s", getColoredBoolean(questData.completed)), 2))
    tinsert(lines, pad(sformat("warboundCompleted: %s", getColoredBoolean(questData.completedWarbound)), 2))
    if questData.isWeeklyQuest ~= nil then
      tinsert(lines, pad(sformat("isWeeklyQuest: %s", getColoredBoolean(questData.isWeeklyQuest)), 2))
    end
  end
  if ns.IsRetail then -- watermarks and bonus coins aren't tracked on forever
    tinsert(lines, "Free updagre up to " .. ns.helpers.GetFormatedLastUpdateTime(char.watermarksUpdated))
    local watermarksFound = false
    for slotId, ilvl in pairs(safeTable(char.watermarks)) do
      watermarksFound = true
      local slotName = watermarkNameCache[slotId]
      tinsert(lines, pad(sformat("%s: %s", slotName, ilvl)))
    end
    if not watermarksFound then
      tinsert(lines, pad("none"))
    end
    tinsert(lines, "Bonus coin usage: " .. ns.helpers.GetFormatedLastUpdateTime(char.bonusCoinUsageUpdated))
    if char.bonusCoinUsage and #char.bonusCoinUsage > 0 then
      for _, v in ipairs(char.bonusCoinUsage) do
        tinsert(lines, pad(sformat("%s %s %s", ns.helpers.GetIconTextureStringForSpecId(v.specId), v.itemLink, ns.helpers.GetFormatedLastUpdateTime(v.receiveTime))))
      end
    else
      tinsert(lines, pad("none"))
    end
  end
  return table.concat(lines, "\n")
end

local function BuildDetailTextForDroptimizer(entry)
  local lines = {}
  ---@type wowutilsDroptimizerData
  local data = entry.data
  tinsert(lines, "Droptimizer details")
  tinsert(lines, "-------------------")
  tinsert(lines, "Key: " .. tostring(entry.key or "-"))
  tinsert(lines, "Character: " .. tostring(data.characterName or "-"))
  tinsert(lines, "Realm ID: " .. tostring(data.realmId or "-"))
  if ns.IsRetail then -- realm data isn't loaded on forever
    tinsert(lines, "Server Slug:" .. ns.GetRealmSlug(data.region, data.realmId))
  end
  tinsert(lines, "Region: " .. tostring(data.region or "-"))
  tinsert(lines, "Last update: " .. ns.helpers.GetFormatedLastUpdateTime(data.lastUpdate or 0))

  tinsert(lines, "Wishlist")
  local wishlistItemsFound = false
  for _, v in ns.helpers.spairs(data.wishlist) do
    wishlistItemsFound = true
    ---@cast v wowutilsDroptimizerData_wishlistItem
    tinsert(lines, pad(sformat("%s %s", (select(2, C_Item.GetItemInfo(v.itemId))) or UNKNOWN, ns.helpers.GetFormatedLastUpdateTime(v.updated or 0))))
    tinsert(lines, pad(GetDifficultyInfo(v.difficultyId) or UNKNOWN, 2))
    tinsert(lines, pad("Note: " .. (v.note or "N/A"), 2))
    tinsert(lines, pad("Priority: " .. (v.priority or "N/A"), 2))
  end
  if not wishlistItemsFound then
    tinsert(lines, pad("none"))
  end

  tinsert(lines, "Sims")
  local droptimizerItemsFound = false
  for specId, specSims in pairs(data.specs) do
    for simId, simData in pairs(specSims) do
      tinsert(lines, pad(sformat("%s%s %s", ns.helpers.GetIconTextureStringForSpecId(specId), simId, ns.helpers.GetFormatedLastUpdateTime(simData.simmedAt))))
      tinsert(lines, pad(sformat("Source: %s", simData.simType == 1 and "RaidBots" or simData.simType == 2 and "QeLive" or UNKNOWN), 2))
      -- items are keyed itemId -> array of results, flatten before sorting so every result for an
      -- item shows up rather than just one of them
      local simItems = {}
      for itemId, entries in pairs(simData.items) do
        for i = 1, #entries do
          tinsert(simItems, { itemId = itemId, data = entries[i] })
        end
      end
      table.sort(simItems, function(a, b)
        if simData.simType == 1 then return (a.data.gain or 0) > (b.data.gain or 0) end
        return (a.data.gainPercent or 0) > (b.data.gainPercent or 0)
      end)
      for _, simItem in ipairs(simItems) do
        local itemId = simItem.itemId
        ---@type wowutilsDroptimizerData_droptimizerItem
        local itemData = simItem.data
        droptimizerItemsFound = true
        -- slot and source are what tell two results for the same item apart
        local suffix = ns.helpers.GetEquipmentSlotName(itemData.equipmentSlot) or tostring(itemData.equipmentSlot)
        if itemData.sourceItem then
          suffix = sformat("%s, %s %s", suffix, itemData.sourceItem.catalyst and "catalyst from" or "from",
            (select(2, C_Item.GetItemInfo(itemData.sourceItem.itemId))) or itemData.sourceItem.itemId)
        end
        if itemData.gain then -- TODO calculate both
          tinsert(lines, pad(sformat("%s %s (%s, %s)", itemData.gain, (select(2, C_Item.GetItemInfo(itemId))) or UNKNOWN, itemData.ilvl, suffix), 2))
        elseif itemData.gainPercent then
          tinsert(lines, pad(sformat("%s%% %s (%s, %s)", itemData.gainPercent, (select(2, C_Item.GetItemInfo(itemId))) or UNKNOWN, itemData.ilvl, suffix), 2))
        else
          tinsert(lines, pad(sformat("NO VALUE? %s (%s, %s)", (select(2, C_Item.GetItemInfo(itemId))) or UNKNOWN, itemData.ilvl, suffix), 2))
        end
      end
    end
  end
  if not droptimizerItemsFound then
    tinsert(lines, pad("none"))
  end
  return table.concat(lines, "\n")
end

local GUI = {
  activeTab = 1,
  frame = nil,
  detailFrame = nil,
  detailText = nil,
}

ns.gui = GUI

---Scrollable area with the thin blizzard scrollbar instead of the chunky UIPanelScrollFrameTemplate one.
---@param parent Frame
---@param insetX number?
---@param insetY number?
local function CreateListPanel(parent, insetX, insetY)
  insetX, insetY = insetX or 8, insetY or 8

  local scroll = CreateFrame("ScrollFrame", nil, parent)
  scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", insetX, -insetY)
  scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(insetX + 14), insetY)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(1)
  content:SetHeight(1)
  scroll:SetScrollChild(content)

  scroll:SetScript("OnSizeChanged", function(self)
    content:SetWidth(self:GetWidth())
  end)

  if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
    local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)
  end
  if not scroll:GetScript("OnMouseWheel") then -- only if the scrollbar didnt bring its own wheel handling
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      self:SetVerticalScroll(Clamp(self:GetVerticalScroll() - delta * 40, 0, self:GetVerticalScrollRange()))
    end)
  end

  return scroll, content
end

function GUI:CreateDetailWindow()
  if self.detailFrame then
    return
  end

  local frame = CreateFrame("Frame", "WowUtilsDetailWindow", UIParent, "BackdropTemplate")
  frame:SetSize(540, 460)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  ApplyWindowTheme(frame)
  -- keep the popup above the main window (HIGH), with a solid background so it doesnt bleed through
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetBackdropColor(unpack(COLORS.windowSolid))
  frame:Hide()

  local header = frame:CreateTexture(nil, "ARTWORK")
  header:SetColorTexture(unpack(COLORS.header))
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  header:SetHeight(34)

  local headerLine = frame:CreateTexture(nil, "OVERLAY")
  headerLine:SetColorTexture(unpack(COLORS.accent))
  headerLine:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  headerLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  headerLine:SetHeight(1)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("LEFT", header, "LEFT", 12, 0)
  title:SetText("WowUtils")
  title:SetTextColor(unpack(COLORS.text))

  local closeBtn = CreateButton(frame, "X", 24, 22)
  closeBtn:SetPoint("RIGHT", header, "RIGHT", -8, 0)
  closeBtn:SetScript("OnClick", function() frame:Hide() end)

  local selectToggle = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  selectToggle:SetSize(22, 22)
  selectToggle:SetPoint("RIGHT", closeBtn, "LEFT", -78, 0)
  selectToggle:SetChecked(false)

  local selectToggleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  selectToggleLabel:SetPoint("LEFT", selectToggle, "RIGHT", 2, 1)
  selectToggleLabel:SetText("Select text")
  selectToggleLabel:SetTextColor(unpack(COLORS.muted))

  local body = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 8, -8)
  body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
  ApplyPanelTheme(body)

  local scroll, content = CreateListPanel(body, 10, 8)
  content:SetHeight(300)

  -- Use a hyperlink-enabled, read-only EditBox instead of a FontString so
  -- item/spell/etc links show tooltips on hover, respond to clicks (dressing
  -- room, chat linking, etc.). Free text selection/copy is off by default
  -- (see selectToggle above) and only enabled when the user opts in, so
  -- hyperlink clicks don't fight with click-drag selection.
  local text = CreateLinkText(content, true, GameFontHighlightSmall)
  text:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  text:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
  text:SetHeight(300)

  selectToggle:SetScript("OnClick", function(self)
    text:SetSelectable(self:GetChecked())
  end)

  -- When selection is enabled, clicking the body focuses the EditBox so
  -- click-drag selection and Ctrl+A / Ctrl+C work normally.
  content:EnableMouse(true)
  content:SetScript("OnMouseDown", function()
    if text.selectable then
      text:SetFocus()
    end
  end)

  frame.scroll = scroll
  frame.content = content
  frame.text = text
  frame.title = title
  frame.selectToggle = selectToggle

  tinsert(UISpecialFrames, "WowUtilsDetailWindow") -- close on escape

  self.detailFrame = frame
  self.detailText = text
end

function GUI:ShowDetail(title, body)
  self:CreateDetailWindow()

  local textBody = body or ""
  self.detailFrame.title:SetText(title)
  self.detailText:SetLockedText(textBody)

  local lineCount = 1 + select(2, textBody:gsub("\n", "\n"))
  local height = math.max(300, lineCount * 14 + 20)
  self.detailFrame.content:SetHeight(height)
  self.detailText:SetHeight(height)
  self.detailFrame.scroll:UpdateScrollChildRect()
  self.detailFrame:Show()
end

function GUI:ShowCharacterDetail(entry)
  self:ShowDetail(sformat("%s %s", ns.helpers.GetIconTextureStringForClass(entry.data.class), entry.name), BuildDetailTextForCharacter(entry.data))
end

function GUI:ShowDroptimizerDetail(entry)
  self:ShowDetail(sformat("%s %s", ns.helpers.GetIconTextureStringForClass(entry.data.class), entry.name), BuildDetailTextForDroptimizer(entry))
end

local function SetupList(parent, getEntries, onSelect)
  if not parent then
    return
  end

  local rows = {}
  local scroll, content = CreateListPanel(parent)

  local function Refresh()
    local entries = getEntries() or {}

    for _, row in ipairs(rows) do
      row:Hide()
    end

    for i, entry in ipairs(entries) do
      local row = rows[i]
      if not row then
        row = CreateFrame("Button", nil, content, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("LEFT", content, "LEFT", 4, 0)
        row:SetPoint("RIGHT", content, "RIGHT", -4, 0)
        ApplyFlatTheme(row, COLORS.row, COLORS.border)

        row.accent = row:CreateTexture(nil, "ARTWORK")
        row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
        row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
        row.accent:SetWidth(3)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 12, 0)
        row.name:SetJustifyH("LEFT")

        -- secondary info is right aligned and muted so the names stay scannable
        row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.info:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        row.info:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
        row.info:SetJustifyH("RIGHT")
        row.info:SetTextColor(unpack(COLORS.muted))

        row:SetScript("OnEnter", function(self)
          self:SetBackdropColor(unpack(COLORS.rowHover))
        end)

        row:SetScript("OnLeave", function(self)
          self:SetBackdropColor(unpack(self.baseColor or COLORS.row))
        end)

        rows[i] = row
      end

      row:SetPoint("TOP", content, "TOP", 0, -(i - 1) * (ROW_HEIGHT + ROW_SPACING) - 4)
      row:Show()

      row.name:SetText(sformat("%s %s", ns.helpers.GetIconTextureStringForClass(entry.class), entry.name or "?"))
      if entry.kind == "character" then
        row.info:SetText(sformat("%sv%s   %s", entry.syncLists and sformat("%s   ", table.concat(entry.syncLists, ", ")) or "",
          entry.version or "?", ns.helpers.GetFormatedLastUpdateTime(entry.update or 0)))
      else
        row.info:SetText(sformat("%s  %s", tostring(entry.key or "Unknown"),
          ns.helpers.GetFormatedLastUpdateTime(entry.update or 0)))
      end

      row:SetScript("OnClick", function()
        onSelect(entry)
      end)
      ApplyRowStyle(row, entry.class, i)
    end

    content:SetHeight(math.max(1, #entries * (ROW_HEIGHT + ROW_SPACING) + 8))
  end

  return Refresh
end

---Settings for the notification MessageFrame (notifications.lua), everything applies live.
---@param parent Frame
function GUI:CreateNotificationsOptions(parent)
  local o = WowUtilsDB.options.notifications
  local ROW = 48
  local function apply()
    ns.notifications.ApplySettings()
  end
  -- label above, control below, columns grow downwards
  local columns = { { x = 12, y = -10 }, { x = 380, y = -10 } }
  local function place(columnIndex, labelText, control, controlOffsetX)
    local column = columns[columnIndex]
    local label = CreateOptionLabel(parent, labelText)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", column.x, column.y)
    control:SetPoint("TOPLEFT", label, "BOTTOMLEFT", controlOffsetX or 0, -6)
    column.y = column.y - ROW
  end

  -- left column
  local unlock = CreateCheckbox(parent, "Unlock (drag to move)", function(checked)
    ns.notifications.SetUnlocked(checked)
  end)
  unlock:SetPoint("TOPLEFT", parent, "TOPLEFT", columns[1].x - 4, columns[1].y)
  columns[1].y = columns[1].y - 34
  -- leaving it unlocked after closing the window would just leave a green box on screen
  self.frame:HookScript("OnHide", function()
    unlock:SetChecked(false)
    ns.notifications.SetUnlocked(false)
  end)

  local test = CreateButton(parent, "Test", 60, 20)
  test:SetPoint("LEFT", unlock.label, "RIGHT", 12, -1)
  test:SetScript("OnClick", function()
    ns.notifications.AddMessage("WowUtils test notification")
  end)

  -- built on open, other addons can keep registering fonts to LSM after we load
  local function getFontOptions()
    local fontOptions = {}
    for _, name in ipairs(ns.notifications.LSM:List("font")) do
      tinsert(fontOptions, { text = name, value = name })
    end
    return fontOptions
  end
  place(1, "Font", CreateDropdown(parent, 200, getFontOptions, function() return o.font end, function(value)
    o.font = value
    apply()
  end, 400))

  place(1, "Alignment", CreateDropdown(parent, 200, {
    { text = "Left", value = "LEFT" },
    { text = "Center", value = "CENTER" },
    { text = "Right", value = "RIGHT" },
  }, function() return o.justify end, function(value)
    o.justify = value
    apply()
  end))
  -- only affects new messages, ones already on screen keep their color
  place(1, "Default text color", CreateColorSwatch(parent, o.color, function() end))

  -- right column
  local SLIDER_WIDTH = 250
  local function formatNumber(value) return tostring(value) end
  local function formatSeconds(value) return sformat("%.1fs", value) end

  place(2, "Font size", CreateSlider(parent, SLIDER_WIDTH, 8, 40, 1, o.fontSize, formatNumber, function(value)
    o.fontSize = value
    apply()
  end))

  place(2, "Line spacing", CreateSlider(parent, SLIDER_WIDTH, -10, 20, 1, o.spacing, formatNumber, function(value)
    o.spacing = value
    apply()
  end))

  place(2, "Display time", CreateSlider(parent, SLIDER_WIDTH, 0.5, 10, 0.5, o.timeVisible, formatSeconds, function(value)
    o.timeVisible = value
    apply()
  end))

  place(2, "Fade duration", CreateSlider(parent, SLIDER_WIDTH, 0, 3, 0.1, o.fadeDuration, formatSeconds, function(value)
    o.fadeDuration = value
    apply()
  end))

  local maxX = floor(UIParent:GetWidth() / 2)
  local maxY = floor(UIParent:GetHeight() / 2)
  local xSlider = CreateSlider(parent, SLIDER_WIDTH, -maxX, maxX, 1, o.x, formatNumber, function(value)
    o.x = value
    apply()
  end)
  place(2, "X offset", xSlider)

  local ySlider = CreateSlider(parent, SLIDER_WIDTH, -maxY, maxY, 1, o.y, formatNumber, function(value)
    o.y = value
    apply()
  end)
  place(2, "Y offset", ySlider)

  -- dragging the frame moves it outside of the sliders, keep them in sync
  ns.notifications.OnPositionChanged = function()
    xSlider:SetValue(o.x)
    ySlider:SetValue(o.y)
  end
end

---Crafting order notification settings, the notification itself uses the frame from notifications.lua
---@param parent Frame
function GUI:CreateCraftingOrdersOptions(parent)
  local o = WowUtilsDB.options.craftingOrders

  local printToChat = CreateCheckbox(parent, "Print to chat", function(checked)
    o.printToChat = checked
  end)
  printToChat:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -10)
  printToChat:SetChecked(o.printToChat)

  local test = CreateButton(parent, "Test", 60, 20)
  test:SetPoint("LEFT", printToChat.label, "RIGHT", 12, -1)
  test:SetScript("OnClick", function()
    ns.randomThings.craftingOrders.ShowTestNotification()
  end)

  local thresholdLabel = CreateOptionLabel(parent, "Minimum tip")
  thresholdLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -50)
  local threshold = CreateSlider(parent, 250, 0, 5000, 1, o.tipThreshold, function(value) return sformat("%dg", value) end, function(value)
    o.tipThreshold = value
  end)
  threshold:SetPoint("TOPLEFT", thresholdLabel, "BOTTOMLEFT", 0, -6)

  local professionsLabel = CreateOptionLabel(parent, "Notify for")
  professionsLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -110)
  local previous
  for _, profession in ipairs(ns.randomThings.craftingOrders.notifyProfessions) do
    local professionId = profession.id
    local toggle = CreateCheckbox(parent, profession.icon .. " " .. profession.name, function(checked)
      o.professions[professionId] = checked or nil
    end)
    if previous then
      toggle:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2)
    else
      toggle:SetPoint("TOPLEFT", professionsLabel, "BOTTOMLEFT", -4, -4)
    end
    toggle:SetChecked(o.professions[professionId] and true or false)
    previous = toggle
  end

  -- work orders tab options, second column
  local workOrdersLabel = CreateOptionLabel(parent, "Work Orders")
  workOrdersLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 380, -14)

  local ownFirst = CreateCheckbox(parent, "Show own orders first in Work Orders page", function(checked)
    o.ownFirst = checked
  end)
  ownFirst:SetPoint("TOPLEFT", workOrdersLabel, "BOTTOMLEFT", -4, -4)
  ownFirst:SetChecked(o.ownFirst)

  local workOrdersFirst = CreateCheckbox(parent, "Set Work Orders page first", function(checked)
    o.workOrdersFirst = checked
    self:LayoutTabs()
  end)
  workOrdersFirst:SetPoint("TOPLEFT", ownFirst, "BOTTOMLEFT", 0, -2)
  workOrdersFirst:SetChecked(o.workOrdersFirst)
end

local WORKORDER_HEADER_HEIGHT = 22
local WORKORDER_ICON_SIZE = 22 -- rows are 30 high, font sized (0) icons were tiny

---@param expirationTime number
---@return string
local function FormatTimeLeft(expirationTime)
  local left = math.max(0, expirationTime - GetServerTime())
  local hours, minutes = floor(left / 3600), floor(left % 3600 / 60)
  if hours > 0 then
    return sformat("%dh %dm left", hours, minutes)
  end
  return sformat("%dm left", minutes)
end

---@param partialGuid string
---@return string name
---@return number? r
---@return number? g
---@return number? b
local function GetCustomerDisplay(partialGuid)
  local guid = ns.mapping.ConvertPartialGuidToGuid(partialGuid)
  -- our db knows alts and synced characters even when the client hasn't seen them this session
  local char = WowUtilsDB.ownCharacters[guid] or WowUtilsDB.others[guid]
  local name, class = char and char.name, char and char.class
  if not name then
    local _, classFile, _, _, _, playerName = GetPlayerInfoByGUID(guid)
    name, class = playerName, classFile
  end
  return name or "?", GetClassColorForValue(class)
end

---Open guild crafting orders from the synced cache, grouped into own / matching the notify settings / the rest.
---@param parent Frame
---@return fun() refresh
function GUI:CreateWorkOrdersPanel(parent)
  local o = WowUtilsDB.options.craftingOrders
  local Refresh

  -- the options for this tab live on the crafting orders page
  local listHolder = parent
  local _, content = CreateListPanel(listHolder)

  local empty = listHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  empty:SetPoint("TOPLEFT", listHolder, "TOPLEFT", 14, -10)
  empty:SetTextColor(unpack(COLORS.muted))

  local rows, headers = {}, {}

  -- names of uncached items come in later, one refresh for a whole batch of them
  local pendingItems, refreshQueued = {}, false
  local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.2, function()
      refreshQueued = false
      if parent:IsVisible() then Refresh() end
    end)
  end

  ---@param itemId number
  ---@return string
  local function GetItemText(itemId)
    local name = C_Item.GetItemNameByID(itemId)
    if not name then
      if not pendingItems[itemId] and C_Item.DoesItemExistByID(itemId) then
        pendingItems[itemId] = true
        Item:CreateFromItemID(itemId):ContinueOnItemLoad(function()
          pendingItems[itemId] = nil
          QueueRefresh()
        end)
      end
      return sformat("item:%d", itemId)
    end
    local quality = C_Item.GetItemQualityByID(itemId)
    local qualityColor = quality and ITEM_QUALITY_COLORS[quality]
    return qualityColor and qualityColor.color:WrapTextInColorCode(name) or name
  end

  local function GetHeader(index)
    local header = headers[index]
    if not header then
      header = CreateFrame("Frame", nil, content)
      header:SetHeight(WORKORDER_HEADER_HEIGHT)
      header:SetPoint("LEFT", content, "LEFT", 4, 0)
      header:SetPoint("RIGHT", content, "RIGHT", -4, 0)

      header.label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      header.label:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 4, 4)
      header.label:SetTextColor(unpack(COLORS.text))

      header.line = header:CreateTexture(nil, "ARTWORK")
      header.line:SetColorTexture(unpack(COLORS.accent))
      header.line:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
      header.line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
      header.line:SetHeight(1)
      headers[index] = header
    end
    return header
  end

  local function GetRow(index)
    local row = rows[index]
    if not row then
      row = CreateFrame("Frame", nil, content, "BackdropTemplate")
      row:SetHeight(ROW_HEIGHT)
      row:SetPoint("LEFT", content, "LEFT", 4, 0)
      row:SetPoint("RIGHT", content, "RIGHT", -4, 0)
      ApplyFlatTheme(row, COLORS.row, COLORS.border)
      row:EnableMouse(true)

      row.accent = row:CreateTexture(nil, "ARTWORK")
      row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
      row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
      row.accent:SetWidth(3)

      row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.name:SetPoint("LEFT", row, "LEFT", 12, 0)
      row.name:SetJustifyH("LEFT")
      row.name:SetWordWrap(false)

      row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.info:SetPoint("RIGHT", row, "RIGHT", -10, 0)
      row.info:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
      row.info:SetJustifyH("RIGHT")
      row.info:SetWordWrap(false)
      row.info:SetTextColor(unpack(COLORS.muted))

      row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(COLORS.rowHover))
        if self.itemId then
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:SetItemByID(self.itemId)
          GameTooltip:Show()
        end
      end)
      row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(self.baseColor or COLORS.row))
        GameTooltip_Hide()
      end)
      rows[index] = row
    end
    return row
  end

  local function sortNewestFirst(a, b)
    if a.seenAt ~= b.seenAt then return a.seenAt > b.seenAt end
    if a.order.expirationTime ~= b.order.expirationTime then return a.order.expirationTime < b.order.expirationTime end
    return a.orderId < b.orderId
  end

  Refresh = function()
    for _, row in ipairs(rows) do row:Hide() end
    for _, header in ipairs(headers) do header:Hide() end

    local orders = ns.randomThings.craftingOrders.GetActiveOrders()
    if not orders then
      empty:SetText("Not in a guild")
    elseif #orders == 0 then
      empty:SetText("No open guild orders cached yet")
    end
    empty:SetShown(not orders or #orders == 0)
    orders = orders or {}

    local own, matching, other = {}, {}, {}
    for _, entry in ipairs(orders) do
      tinsert(entry.isOwn and own or entry.matches and matching or other, entry)
    end
    for _, group in ipairs({ own, matching, other }) do
      table.sort(group, sortNewestFirst)
    end

    local ownGroup = { title = "Your orders", entries = own, color = COLORS.accent }
    local groups = {
      { title = "Matching notification settings", entries = matching, color = { 1, 0.82, 0, 1 } },
      { title = "Other orders", entries = other, color = COLORS.muted },
    }
    tinsert(groups, o.ownFirst and 1 or #groups + 1, ownGroup)

    local professionAtlases = ns.randomThings.craftingOrders.professionAtlases
    local formatSeen = ns.randomThings.craftingOrders.FormatSeen
    local y, rowIndex, headerIndex = -4, 0, 0
    for _, group in ipairs(groups) do
      if #group.entries > 0 then
        headerIndex = headerIndex + 1
        local header = GetHeader(headerIndex)
        header:SetPoint("TOP", content, "TOP", 0, y)
        header.label:SetText(sformat("%s (%d)", group.title, #group.entries))
        header.line:SetColorTexture(unpack(group.color))
        header:Show()
        y = y - WORKORDER_HEADER_HEIGHT - ROW_SPACING - 2

        for i, entry in ipairs(group.entries) do
          rowIndex = rowIndex + 1
          local row = GetRow(rowIndex)
          local order = entry.order
          row.itemId = order.itemId
          row:SetPoint("TOP", content, "TOP", 0, y)

          local atlas = professionAtlases[entry.professionId]
          row.name:SetText(sformat("%s %s %s%s", atlas and CreateAtlasMarkup(atlas, WORKORDER_ICON_SIZE, WORKORDER_ICON_SIZE) or "",
            CreateSimpleTextureMarkup(C_Item.GetItemIconByID(order.itemId) or 134400, WORKORDER_ICON_SIZE, WORKORDER_ICON_SIZE),
            GetItemText(order.itemId), order.isRecraft and " (Recraft)" or ""))

          local customer, r, g, b = GetCustomerDisplay(order.customerGuid)
          if r then
            customer = CreateColor(r, g, b):WrapTextInColorCode(customer)
          end
          local tip = (order.tip or 0) > 0 and C_CurrencyInfo.GetCoinTextureString(order.tip * 1e4, 0) or ""
          row.info:SetText(sformat("%s   %s   %s  %s", customer, tip, FormatTimeLeft(order.expirationTime),
            strtrim(formatSeen(entry.seenAt))))

          row.baseColor = (i % 2 == 0) and COLORS.rowAlt or COLORS.row
          row:SetBackdropColor(unpack(row.baseColor))
          row.accent:SetColorTexture(unpack(group.color))
          row:Show()
          y = y - ROW_HEIGHT - ROW_SPACING
        end
        y = y - 6
      end
    end

    content:SetHeight(math.max(1, -y + 4))
  end

  return Refresh
end

---called by randomThings whenever the crafting order cache changes
function GUI:OnCraftingOrdersChanged()
  if not (self.frame and self.frame:IsShown() and self.workOrdersRefresh) then return end
  local active = self.tabs and self.tabs[self.activeTab]
  if active and active.panel == self.workOrdersPanel then
    self.workOrdersRefresh()
  end
end

StaticPopupDialogs["WOWUTILS_DELETE_SYNCLIST"] = {
  text = "Delete sync list '%s'?\n\nGuild members who still have it can send it back.",
  button1 = DELETE,
  button2 = CANCEL,
  OnAccept = function(_, listId)
    WowUtilsDB.syncLists[listId] = nil
    ns.database.CheckEligibleSyncLists()
    if GUI.syncListsRefresh then
      GUI.syncListsRefresh()
    end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local SYNCLIST_TOOLTIP_SLUGS = 20

---Every sync list with its character count and last update, hover for the slugs, delete on the right.
---@param parent Frame
---@return fun() refresh
function GUI:CreateSyncListsOptions(parent)
  local rows = {}
  local _, content = CreateListPanel(parent)

  local empty = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  empty:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -14)
  empty:SetTextColor(unpack(COLORS.muted))
  empty:SetText("No sync lists")

  local function ShowSlugs(row)
    local list = WowUtilsDB.syncLists[row.listId]
    if not list then return end
    local slugs = {}
    for _, slug in pairs(safeTable(list.characters)) do
      tinsert(slugs, tostring(slug))
    end
    table.sort(slugs)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.listId, 1, 1, 1)
    local muted = COLORS.muted
    for i = 1, math.min(#slugs, SYNCLIST_TOOLTIP_SLUGS) do
      GameTooltip:AddLine(slugs[i], muted[1], muted[2], muted[3])
    end
    if #slugs > SYNCLIST_TOOLTIP_SLUGS then
      GameTooltip:AddLine(sformat("+%d more", #slugs - SYNCLIST_TOOLTIP_SLUGS), muted[1], muted[2], muted[3])
    elseif #slugs == 0 then
      GameTooltip:AddLine("No characters", muted[1], muted[2], muted[3])
    end
    GameTooltip:Show()
  end

  local function Refresh()
    local listIds = {}
    for listId in pairs(WowUtilsDB.syncLists) do
      tinsert(listIds, listId)
    end
    table.sort(listIds, function(a, b) return tostring(a) < tostring(b) end)

    for _, row in ipairs(rows) do
      row:Hide()
    end
    empty:SetShown(#listIds == 0)

    for i, listId in ipairs(listIds) do
      local row = rows[i]
      if not row then
        row = CreateFrame("Frame", nil, content, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("LEFT", content, "LEFT", 4, 0)
        row:SetPoint("RIGHT", content, "RIGHT", -4, 0)
        ApplyFlatTheme(row, COLORS.row, COLORS.border)
        row:EnableMouse(true)

        row.accent = row:CreateTexture(nil, "ARTWORK")
        row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
        row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
        row.accent:SetWidth(3)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 12, 0)
        row.name:SetJustifyH("LEFT")

        row.delete = CreateButton(row, DELETE, 60, 20)
        row.delete:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.delete:SetScript("OnClick", function()
          StaticPopup_Show("WOWUTILS_DELETE_SYNCLIST", tostring(row.listId), nil, row.listId)
        end)

        row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.info:SetPoint("RIGHT", row.delete, "LEFT", -10, 0)
        row.info:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
        row.info:SetJustifyH("RIGHT")
        row.info:SetTextColor(unpack(COLORS.muted))

        row:SetScript("OnEnter", function(self)
          self:SetBackdropColor(unpack(COLORS.rowHover))
          ShowSlugs(self)
        end)
        row:SetScript("OnLeave", function(self)
          self:SetBackdropColor(unpack(self.baseColor or COLORS.row))
          GameTooltip_Hide()
        end)

        rows[i] = row
      end

      local list = WowUtilsDB.syncLists[listId]
      row.listId = listId
      row:SetPoint("TOP", content, "TOP", 0, -(i - 1) * (ROW_HEIGHT + ROW_SPACING) - 4)
      row:Show()
      row.name:SetText(tostring(listId))
      local count = CountTable(safeTable(list.characters))
      row.info:SetText(sformat("%d character%s   %s", count, count == 1 and "" or "s",
        ns.helpers.GetFormatedLastUpdateTime(list.lastUpdate or 0)))
      ApplyRowStyle(row, nil, i)
    end

    content:SetHeight(math.max(1, #listIds * (ROW_HEIGHT + ROW_SPACING) + 8))
  end

  return Refresh
end

function GUI:Create()
  if self.frame then
    return
  end

  local frame = CreateFrame("Frame", "WowUtilsGUIFrame", UIParent, "BackdropTemplate")
  frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  ApplyWindowTheme(frame)
  frame:SetFrameStrata("HIGH")
  frame:Hide()

  tinsert(UISpecialFrames, "WowUtilsGUIFrame") -- close on escape

  frame:SetScript("OnHide", function()
    if self.detailFrame then -- the popup has no reason to stick around without the window it was opened from
      self.detailFrame:Hide()
    end
  end)

  local header = frame:CreateTexture(nil, "ARTWORK")
  header:SetColorTexture(unpack(COLORS.header))
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  header:SetHeight(HEADER_HEIGHT)

  local headerLine = frame:CreateTexture(nil, "OVERLAY")
  headerLine:SetColorTexture(unpack(COLORS.accent))
  headerLine:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  headerLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  headerLine:SetHeight(1)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", header, "TOPLEFT", 12, -7)
  title:SetText(sformat("|T%s:0:0|t WowUtils", ns.logoFile))
  title:SetTextColor(unpack(COLORS.text))

  local addonVersion = GetAddonVersion()
  local dbVersion = ns.config and ns.config.currentDBVersion or "?"
  local configVersion = ns.config and ns.config.configVersion or "?"

  local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -3)
  subtitle:SetText(sformat("v%s | db:%s | cfg:%s | database explorer", addonVersion, dbVersion, configVersion))
  subtitle:SetTextColor(unpack(COLORS.muted))

  local closeBtn = CreateButton(frame, "X", 24, 22)
  closeBtn:SetPoint("TOPRIGHT", header, "TOPRIGHT", -8, -11)
  closeBtn:SetScript("OnClick", function()
    frame:Hide()
  end)

  local refreshBtn = CreateButton(frame, "Refresh", 80, 22)
  refreshBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -6, 0)
  refreshBtn:SetScript("OnClick", function()
    self:RefreshData()
  end)

  self.frame = frame

  local tabHolder = CreateFrame("Frame", nil, frame)
  tabHolder:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 7, 0)
  tabHolder:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -7, 0)
  tabHolder:SetHeight(30)

  local tabLine = tabHolder:CreateTexture(nil, "ARTWORK")
  tabLine:SetColorTexture(unpack(COLORS.border))
  tabLine:SetPoint("BOTTOMLEFT", tabHolder, "BOTTOMLEFT", 0, 0)
  tabLine:SetPoint("BOTTOMRIGHT", tabHolder, "BOTTOMRIGHT", 0, 0)
  tabLine:SetHeight(1)

  local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  panel:SetPoint("TOPLEFT", tabHolder, "BOTTOMLEFT", 0, -8)
  panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
  ApplyPanelTheme(panel)

  self.panel = panel

  local function CreatePanel()
    local p = CreateFrame("Frame", nil, panel)
    p:SetAllPoints(panel)
    p:Hide()
    return p
  end

  -- general only holds warbound options and crafting orders are retail only, both are left out on forever
  local generalPanel = ns.IsRetail and CreatePanel() or nil
  local rosterPanel = CreatePanel()
  local droptimizerPanel = CreatePanel()

  local notificationsPanel = CreatePanel()
  self:CreateNotificationsOptions(notificationsPanel)

  local craftingOrdersPanel
  if ns.IsRetail then
    craftingOrdersPanel = CreatePanel()
    self:CreateCraftingOrdersOptions(craftingOrdersPanel)
  end

  local workOrdersPanel
  if ns.IsRetail then
    workOrdersPanel = CreatePanel()
    self.workOrdersPanel = workOrdersPanel
    self.workOrdersRefresh = self:CreateWorkOrdersPanel(workOrdersPanel)
  end

  local syncListsPanel = CreatePanel()
  self.syncListsRefresh = self:CreateSyncListsOptions(syncListsPanel)

  self.generalPanel = generalPanel
  self.rosterPanel = rosterPanel
  self.droptimizerPanel = droptimizerPanel
  self.notificationsPanel = notificationsPanel

  if generalPanel then
    local warboundOptions = WowUtilsDB.options.warboundOptions

    local warboundSelfOnly
    local function UpdateWarboundSelfOnlyState()
      warboundSelfOnly:SetEnabled(warboundOptions.enabled)
      warboundSelfOnly.label:SetAlpha(warboundOptions.enabled and 1 or 0.4)
    end

    local warboundEnabled = CreateCheckbox(generalPanel, "Show warbound drops", function(checked)
      warboundOptions.enabled = checked
      if checked then
        ns.events.RegisterEvent("CHAT_MSG_LOOT")
      else
        ns.events.UnregisterEvent("CHAT_MSG_LOOT")
      end
      UpdateWarboundSelfOnlyState()
    end)
    warboundEnabled:SetPoint("TOPLEFT", generalPanel, "TOPLEFT", 10, -6)
    warboundEnabled:SetChecked(warboundOptions.enabled)
    warboundEnabled:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Show warbound drops", 1, 1, 1)
      GameTooltip:AddLine("Tracks looted warbound items by parsing the chat. (Shows them in notifications)", nil, nil, nil, true)
      GameTooltip:Show()
    end)
    warboundEnabled:HookScript("OnLeave", GameTooltip_Hide)

    warboundSelfOnly = CreateCheckbox(generalPanel, "Own only", function(checked)
      warboundOptions.selfOnly = checked
    end)
    warboundSelfOnly:SetPoint("TOPLEFT", warboundEnabled, "BOTTOMLEFT", 18, -2)
    warboundSelfOnly:SetChecked(warboundOptions.selfOnly)
    UpdateWarboundSelfOnlyState()
  end

  -- these only apply to the roster, so the bar lives inside that panel instead of the window header
  local filterBar = CreateFrame("Frame", nil, rosterPanel)
  filterBar:SetPoint("TOPLEFT", rosterPanel, "TOPLEFT", 10, -6)
  filterBar:SetPoint("TOPRIGHT", rosterPanel, "TOPRIGHT", -10, -6)
  filterBar:SetHeight(24)

  local filters = WowUtilsDB.options.characterFilters

  local function SetFilter(key, checked)
    filters[key] = checked or nil
    if self.rosterRefresh then
      self.rosterRefresh()
    end
  end

  local hideUntracked = CreateCheckbox(filterBar, "Hide untracked", function(checked)
    SetFilter("hideUntracked", checked)
  end)
  hideUntracked:SetPoint("LEFT", filterBar, "LEFT", 0, 0)
  hideUntracked:SetChecked(filters.hideUntracked and true or false)

  if ns.IsRetail then -- filters on watermarks, which forever doesn't have
    local hideLowIlvl = CreateCheckbox(filterBar, "Hide Low ilvl characters", function(checked)
      SetFilter("hideLowIlvl", checked)
    end)
    hideLowIlvl:SetPoint("LEFT", hideUntracked.label, "RIGHT", 14, -1)
    hideLowIlvl:SetChecked(filters.hideLowIlvl and true or false)
  end

  local rosterList = CreateFrame("Frame", nil, rosterPanel)
  rosterList:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", -10, -2)
  rosterList:SetPoint("BOTTOMRIGHT", rosterPanel, "BOTTOMRIGHT", 0, 0)

  local rosterRefresh = SetupList(rosterList, function()
    return GetCharacterList()
  end, function(entry)
    self:ShowCharacterDetail(entry)
  end)

  local droptimizerRefresh = SetupList(droptimizerPanel, function()
    return GetDroptimizerList()
  end, function(entry)
    self:ShowDroptimizerDetail(entry)
  end)

  self.rosterRefresh = rosterRefresh
  self.droptimizerRefresh = droptimizerRefresh

  -- buttons and tabs come from one list, so client specific tabs (nil panel) drop out without leaving gaps.
  -- refresh is optional for tabs without list data
  local tabDefs = {
    { name = "General", panel = generalPanel },
    { name = "Roster", panel = rosterPanel, refresh = rosterRefresh },
    { name = "Droptimizer", panel = droptimizerPanel, refresh = droptimizerRefresh },
    { name = "Notifications", panel = notificationsPanel },
    { name = "Crafting Orders", panel = craftingOrdersPanel },
    { name = "Work Orders", panel = workOrdersPanel, refresh = self.workOrdersRefresh },
    { name = "Sync Lists", panel = syncListsPanel, refresh = self.syncListsRefresh },
  }
  self.tabHolder = tabHolder
  self.tabDefs = {}
  for _, def in ipairs(tabDefs) do
    if def.panel then
      def.button = CreateTab(tabHolder, def.name)
      tinsert(self.tabDefs, def)
    end
  end
  self:LayoutTabs()

  self:SetTab(1)
end

---(re)builds the tab order from tabDefs, the work orders tab can be moved to the front from the crafting orders options
function GUI:LayoutTabs()
  if not self.tabDefs then return end
  local activePanel = self.tabs and self.tabs[self.activeTab] and self.tabs[self.activeTab].panel

  local ordered = {}
  local workOrdersFirst = ns.IsRetail and WowUtilsDB.options.craftingOrders.workOrdersFirst
  for _, def in ipairs(self.tabDefs) do
    if workOrdersFirst and def.panel == self.workOrdersPanel then
      tinsert(ordered, 1, def)
    else
      tinsert(ordered, def)
    end
  end

  self.tabs = {}
  self.tabButtons = {}
  local previousBtn
  for index, def in ipairs(ordered) do
    local btn = def.button
    btn:ClearAllPoints()
    if previousBtn then
      btn:SetPoint("BOTTOMLEFT", previousBtn, "BOTTOMRIGHT", 4, 0)
    else
      btn:SetPoint("BOTTOMLEFT", self.tabHolder, "BOTTOMLEFT", 0, 0)
    end
    btn:SetScript("OnClick", function()
      self:SetTab(index)
    end)
    self.tabs[index] = { panel = def.panel, refresh = def.refresh }
    self.tabButtons[index] = btn
    previousBtn = btn
    if def.panel == activePanel then
      self.activeTab = index -- stay on the same page when the order changes under it
    end
  end

  for i, btn in ipairs(self.tabButtons) do
    btn:SetSelected(i == self.activeTab)
  end
end

function GUI:SetTab(index)
  self:Create()

  if not self.tabs[index] then
    index = 1
  end
  self.activeTab = index

  for i, tab in ipairs(self.tabs) do
    tab.panel:SetShown(i == index)
  end
  self.panel:Show()
  if self.tabs[index].refresh then
    self.tabs[index].refresh()
  end

  for i, btn in ipairs(self.tabButtons) do
    btn:SetSelected(i == self.activeTab)
  end
end
function GUI:RefreshData()
  self:Create()
  self:SetTab(self.activeTab or 1)
end
function GUI:Toggle()
  self:Create()
  if self.frame:IsShown() then
    self.frame:Hide()
  else
    self.frame:Show()
    self:RefreshData()
  end
end

SLASH_WOWUTILS1 = "/wowutils"
SLASH_WOWUTILS2 = "/wu"
SlashCmdList.WOWUTILS = function()
  GUI:Toggle()
end