---@class wowutilsPrivate
---@field gui table

---@type string, wowutilsPrivate
local addon_name, ns = ...

local GetServerTime, sformat, floor, srep = GetServerTime, string.format, math.floor, string.rep

local FRAME_WIDTH, FRAME_HEIGHT = 760, 520
local ROW_HEIGHT = 28

local COLORS = {
  bg = {0.07, 0.07, 0.09, .9},
  panel = { 0.13, 0.13, 0.16, 0.97 },
  border = { 0.28, 0.32, 0.42, 0.95 },
  accent = {0.09, 0.2, 0.12, 1},
  accentSoft = { 0.28, 0.38, 0.48, 0.55 },
  text = { 0.94, 0.95, 0.97, 1.0 },
  muted = { 0.72, 0.76, 0.82, 1.0 },
  rowAlt = { 0.17, 0.17, 0.20, 0.70 },
  hover = { 0.22, 0.30, 0.40, 0.40 },
  active = { 0.20, 0.28, 0.40, 0.95 },
}
local function GetAddonVersion()
  return C_AddOns.GetAddOnMetadata(addon_name, "Version")
end

local function ApplyPanelTheme(frame)
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(unpack(COLORS.panel))
  frame:SetBackdropBorderColor(unpack(COLORS.border))
end

local function ApplyWindowTheme(frame)
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(unpack(COLORS.bg))
  frame:SetBackdropBorderColor(unpack(COLORS.border))
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

local function ApplyRowClassBackdrop(row, classValue)
  local r, g, b = GetClassColorForValue(classValue)
  if r then
    row:SetBackdropColor(r, g, b, 0.50)
    row:SetBackdropBorderColor(r, g, b, 1)
  else
    row:SetBackdropColor(unpack(COLORS.rowAlt))
    row:SetBackdropBorderColor(0.22, 0.25, 0.32, 0.50)
  end
end
local function GetCharacterList()
  local list = {}

  for _, data in pairs(WowUtilsDB.ownCharacters) do
    tinsert(list, {
      kind = "character",
      data = data,
      name = data.fullSlug or UNKNOWN,
      update = data.lastUpdateReceived or data.lastUpdate or 0,
      class = data.class
    })
  end

  for _, data in pairs(WowUtilsDB.others) do
    tinsert(list, {
      kind = "character",
      data = data,
      name = data.fullSlug or UNKNOWN,
      update = data.lastUpdateReceived or data.lastUpdate or 0,
      class = data.class
    })
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
  tinsert(lines, sformat("Sparks %s: %s", ns.helpers.GetFormatedLastUpdateTime(char.craftingItemsUpdated), char.craftingItems or 0))

  tinsert(lines, "Vault data " .. ns.helpers.GetFormatedLastUpdateTime(char.vaultDataLastUpdate))
  if type(char.vaultData) ~= "table" or not next(char.vaultData) then
    tinsert(lines, pad("none"))
  end
  for _, vaultData in ipairs(char.vaultData) do
    ---@cast vaultData wowutils_vaultData_items
    tinsert(lines, pad(sformat("%s (%s)%s", vaultData.itemId == 1 and "Currency" or vaultData.itemLink or UNKNOWN, vaultData.itemLevel > 0 and vaultData.itemLevel or "?", vaultData.picked and " |cff00ff00Picked|r" or "")))
  end
  tinsert(lines, "Weekly Rewards " .. ns.helpers.GetFormatedLastUpdateTime(char.weeklyRewardsUpdate))
  local weeklyRewardsFound = false
  for k,v in pairs(char.weeklyRewards) do
    weeklyRewardsFound = true
    tinsert(lines, pad(sformat("%s : %s", k, v)))
  end
  if not weeklyRewardsFound then
    tinsert(lines, pad("none"))
  end
  tinsert(lines, "Currency " .. ns.helpers.GetFormatedLastUpdateTime(char.currencyUpdated))
  local currencyFound =  false
  for currencyId, currencyData in pairs(char.currency) do
    currencyFound = true
    local current = currencyData and currencyData.current or "-"
    local totalEarned = currencyData and currencyData.totalEarned or "-"
    local ci = C_CurrencyInfo.GetCurrencyInfo(currencyId)
    tinsert(lines, pad(sformat("%s %s/%s", C_CurrencyInfo.GetCurrencyLink(currencyId) or ci.name or UNKNOWN, current, totalEarned)))
  end
    if not currencyFound then
    tinsert(lines, pad("none"))
  end

  tinsert(lines, "Quests " .. ns.helpers.GetFormatedLastUpdateTime(char.questsUpdated))
  for questId, questData in pairs(char.quests) do
    local questName = C_QuestLog.GetTitleForQuestID(questId) or questId
    tinsert(lines, pad(sformat("|Hquest:%s:90|h%s|h (%s)", questId, questName, questId)))
    tinsert(lines, pad(sformat("completed: %s", getColoredBoolean(questData.completed)), 2))
    tinsert(lines, pad(sformat("warboundCompleted: %s", getColoredBoolean(questData.completedWarbound)), 2))
    if questData.isWeeklyQuest ~= nil then
      tinsert(lines, pad(sformat("isWeeklyQuest: %s", getColoredBoolean(questData.isWeeklyQuest)), 2))
    end
  end
  tinsert(lines, "Watermarks " .. ns.helpers.GetFormatedLastUpdateTime(char.watermarksUpdated))
  local watermarksFound = false
  for slotId, ilvl in pairs(char.watermarks) do
    watermarksFound = true
    local slotName = watermarkNameCache[slotId]
    tinsert(lines, pad(sformat("%s: %s", slotName, ilvl)))
  end
  if not watermarksFound then
    tinsert(lines, pad("none"))
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
  tinsert(lines, "Server Slug:" .. ns.GetRealmSlug(data.region, data.realmId))
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
      for itemId, itemData in ns.helpers.spairs(simData.items, function(t,a,b) if simData.simType == 1 then return t[a].gain > t[b].gain else return (t[a].gainPercent or 0) > (t[b].gainPercent or 0) end end) do
        ---@cast itemData wowutilsDroptimizerData_droptimizerItem
        droptimizerItemsFound = true
        if itemData.gain then -- TODO calculate both
          tinsert(lines, pad(sformat("%s %s (%s)", itemData.gain, (select(2, C_Item.GetItemInfo(itemId))) or UNKNOWN, itemData.ilvl), 2))
        elseif itemData.gainPercent then
          tinsert(lines, pad(sformat("%s%% %s (%s)", itemData.gainPercent, (select(2, C_Item.GetItemInfo(itemId))) or UNKNOWN, itemData.ilvl), 2))
        else
          tinsert(lines, pad(sformat("NO VALUE? %s (%s)", (select(2, C_Item.GetItemInfo(itemId))) or UNKNOWN, itemData.ilvl), 2))
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

local function CreateListPanel(parent)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, 8)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(1)
  content:SetHeight(1)
  scroll:SetScrollChild(content)

  scroll:SetScript("OnSizeChanged", function(self)
    content:SetWidth(self:GetWidth())
  end)

  return scroll, content
end

function GUI:CreateDetailWindow()
  if self.detailFrame then
    return
  end

  local frame = CreateFrame("Frame", "WowUtilsDetailWindow", UIParent, "BackdropTemplate")
  frame:SetSize(500, 420)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  ApplyWindowTheme(frame)
  frame:Hide()

  local header = frame:CreateTexture(nil, "ARTWORK")
  header:SetColorTexture(unpack(COLORS.accent))
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
  header:SetHeight(28)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("LEFT", header, "LEFT", 10, 0)
  title:SetText("WowUtils")
  title:SetTextColor(unpack(COLORS.text))

  local closeBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
  closeBtn:SetSize(80, 22)
  closeBtn:SetPoint("TOPRIGHT", header, "TOPRIGHT", -6, -3)
  closeBtn:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 12,
    edgeSize = 8,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  closeBtn:SetBackdropColor(0.18, 0.18, 0.20, 0.95)
  closeBtn:SetBackdropBorderColor(0.35, 0.40, 0.50, 0.95)
  closeBtn:SetText("Close")
  closeBtn:SetNormalFontObject("GameFontHighlightSmall")
  closeBtn:SetHighlightFontObject("GameFontHighlightSmall")
  closeBtn:SetScript("OnClick", function() frame:Hide() end)

  local selectToggle = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  selectToggle:SetSize(24, 24)
  selectToggle:SetPoint("RIGHT", closeBtn, "LEFT", -70, 0)
  selectToggle:SetChecked(false)

  local selectToggleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  selectToggleLabel:SetPoint("LEFT", selectToggle, "RIGHT", 2, 1)
  selectToggleLabel:SetText("Select text")
  selectToggleLabel:SetTextColor(unpack(COLORS.muted))

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -42)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(450)
  content:SetHeight(300)
  scroll:SetScrollChild(content)

  -- Use a hyperlink-enabled, read-only EditBox instead of a FontString so
  -- item/spell/etc links show tooltips on hover, respond to clicks (dressing
  -- room, chat linking, etc.). Free text selection/copy is off by default
  -- (see selectToggle above) and only enabled when the user opts in, so
  -- hyperlink clicks don't fight with click-drag selection.
  local text = CreateLinkText(content, true, GameFontHighlightSmall)
  text:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  text:SetWidth(430)
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
        row:SetPoint("LEFT", content, "LEFT", 8, 0)
        row:SetPoint("RIGHT", content, "RIGHT", -8, 0)
        row:SetBackdrop({
          bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
          edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
          tile = true,
          tileSize = 12,
          edgeSize = 8,
          insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        row:SetBackdropColor(unpack(COLORS.rowAlt))
        row:SetBackdropBorderColor(0.22, 0.25, 0.32, 0.50)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 10, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetTextColor(unpack(COLORS.text))

        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints(row)
        row.highlight:SetColorTexture(unpack(COLORS.hover))
        row.highlight:Hide()

        row.accent = row:CreateTexture(nil, "ARTWORK")
        row.accent:SetColorTexture(unpack(COLORS.accentSoft))
        row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
        row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
        row.accent:SetWidth(3)

        row:SetScript("OnEnter", function(self)
          self.highlight:Show()
        end)

        row:SetScript("OnLeave", function(self)
          self.highlight:Hide()
        end)

        rows[i] = row
      end

      row:SetPoint("TOP", content, "TOP", 0, -(i - 1) * ROW_HEIGHT - 8)
      row:Show()

      local label = entry.name or "?"
      if entry.kind == "character" then
        label = label .. " " .. ns.helpers.GetFormatedLastUpdateTime(entry.update or 0)
      else
        label = label .. " - " .. tostring(entry.key or "Unknown")
        label = label .. " " .. ns.helpers.GetFormatedLastUpdateTime(entry.update or 0)
      end
      row.text:SetText(label)

      row:SetScript("OnClick", function()
        onSelect(entry)
      end)
      ApplyRowClassBackdrop(row, entry.class)
    end

    content:SetHeight(math.max(1, #entries * ROW_HEIGHT + 8))
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
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  ApplyWindowTheme(frame)
  frame:Hide()

  local header = frame:CreateTexture(nil, "ARTWORK")
  header:SetColorTexture(unpack(COLORS.accent))
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
  header:SetHeight(36)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("LEFT", header, "LEFT", 10, 0)

  local addonVersion = GetAddonVersion()
  local dbVersion = ns.config and ns.config.currentDBVersion or "?"
  local configVersion = ns.config and ns.config.configVersion or "?"

  title:SetText(sformat("|T%s:0:0|t WowUtils v%s | db:%s | cfg:%s", ns.logoFile, addonVersion, dbVersion, configVersion))
  title:SetTextColor(unpack(COLORS.text))

  local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("LEFT", title, "RIGHT", 10, 0)
  subtitle:SetText("Database explorer")
  subtitle:SetTextColor(unpack(COLORS.muted))

  local closeBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
  closeBtn:SetSize(70, 22)
  closeBtn:SetPoint("TOPRIGHT", header, "TOPRIGHT", -6, -7)
  closeBtn:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 12,
    edgeSize = 8,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  closeBtn:SetBackdropColor(0.18, 0.18, 0.20, 0.95)
  closeBtn:SetBackdropBorderColor(0.35, 0.40, 0.50, 0.95)
  closeBtn:SetText("Close")
  closeBtn:SetNormalFontObject("GameFontHighlightSmall")
  closeBtn:SetHighlightFontObject("GameFontHighlightSmall")
  closeBtn:SetScript("OnClick", function()
    frame:Hide()
  end)

  local refreshBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
  refreshBtn:SetSize(85, 22)
  refreshBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -6, 0)
  refreshBtn:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 12,
    edgeSize = 8,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  refreshBtn:SetBackdropColor(0.18, 0.18, 0.20, 0.95)
  refreshBtn:SetBackdropBorderColor(0.35, 0.40, 0.50, 0.95)
  refreshBtn:SetText("Refresh")
  refreshBtn:SetNormalFontObject("GameFontHighlightSmall")
  refreshBtn:SetHighlightFontObject("GameFontHighlightSmall")
  refreshBtn:SetScript("OnClick", function()
    self:RefreshData()
  end)


  self.frame = frame

  local tabHolder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  tabHolder:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
  tabHolder:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -10)
  tabHolder:SetHeight(34)

  local rosterBtn = CreateFrame("Button", nil, tabHolder, "BackdropTemplate")
  rosterBtn:SetSize(110, 26)
  rosterBtn:SetPoint("LEFT", tabHolder, "LEFT", 0, 0)
  rosterBtn:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 12,
    edgeSize = 8,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  rosterBtn:SetBackdropColor(0.16, 0.16, 0.18, 0.95)
  rosterBtn:SetBackdropBorderColor(0.28, 0.32, 0.42, 0.95)
  rosterBtn:SetText("Roster")
  rosterBtn:SetNormalFontObject("GameFontHighlightSmall")
  rosterBtn:SetHighlightFontObject("GameFontHighlightSmall")
  rosterBtn:SetScript("OnClick", function()
    self:SetTab(1)
  end)

  local droptimizerBtn = CreateFrame("Button", nil, tabHolder, "BackdropTemplate")
  droptimizerBtn:SetSize(120, 26)
  droptimizerBtn:SetPoint("LEFT", rosterBtn, "RIGHT", 8, 0)
  droptimizerBtn:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 12,
    edgeSize = 8,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  droptimizerBtn:SetBackdropColor(0.16, 0.16, 0.18, 0.95)
  droptimizerBtn:SetBackdropBorderColor(0.28, 0.32, 0.42, 0.95)
  droptimizerBtn:SetText("Droptimizer")
  droptimizerBtn:SetNormalFontObject("GameFontHighlightSmall")
  droptimizerBtn:SetHighlightFontObject("GameFontHighlightSmall")
  droptimizerBtn:SetScript("OnClick", function()
    self:SetTab(2)
  end)

  self.tabButtons = { rosterBtn, droptimizerBtn }

  local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  panel:SetPoint("TOPLEFT", tabHolder, "BOTTOMLEFT", 0, -8)
  panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
  ApplyPanelTheme(panel)

  self.panel = panel

  local rosterPanel = CreateFrame("Frame", nil, panel)
  rosterPanel:SetAllPoints(panel)
  rosterPanel:Show()

  local droptimizerPanel = CreateFrame("Frame", nil, panel)
  droptimizerPanel:SetAllPoints(panel)
  droptimizerPanel:Hide()

  self.rosterPanel = rosterPanel
  self.droptimizerPanel = droptimizerPanel

  local rosterRefresh = SetupList(rosterPanel, function()
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

  self:SetTab(1)
end

function GUI:SetTab(index)
  self:Create()

  if index == 2 then
    self.activeTab = 2
    self.rosterPanel:Hide()
    self.droptimizerPanel:Show()
    self.panel:Show()
    self.droptimizerRefresh()
  else
    self.activeTab = 1
    self.droptimizerPanel:Hide()
    self.rosterPanel:Show()
    self.panel:Show()
    self.rosterRefresh()
  end

  for i, btn in ipairs(self.tabButtons) do
    if i == self.activeTab then
      btn:SetBackdropColor(unpack(COLORS.active))
      btn:SetBackdropBorderColor(unpack(COLORS.accent))
    else
      btn:SetBackdropColor(0.16, 0.16, 0.18, 0.95)
      btn:SetBackdropBorderColor(0.28, 0.32, 0.42, 0.95)
    end
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