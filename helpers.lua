---@class wowutilsPrivate
---@field helpers wowutils_helpers
---@field Debug wowutilsDebug

---@type string, wowutilsPrivate
local addon_name, ns = ...
local sformat = string.format
---@class wowutils_helpers
ns.helpers = {}

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
  print("Error from Debug.print:", error, "str :", str)
end
function ns.Debug.AddToDevTool(data, displayName)
  if not ns.debugMode then return end
  if not DevTool then return end
  DevTool:AddData(data, displayName)
end

do
  --local timeFormat  = sformat("%s%%s", CreateAtlasMarkup("questlog-questtypeicon-clockyellow"))
  local timeFormat = sformat("%s %%s%%s", CreateAtlasMarkup("clock-icon"))

  ---@param unixTimestamp number
  ---@return string
  function ns.helpers.GetFormatedLastUpdateTime(unixTimestamp)
    if not unixTimestamp or unixTimestamp == 0 then
      return timeFormat:format("Never", "")
    end
    local difSeconds = GetServerTime() - unixTimestamp
    if difSeconds > 86400 then
      return timeFormat:format(Round(difSeconds / 86400), "d")
    elseif difSeconds > 3600 then
      return timeFormat:format(Round(difSeconds / 3600), "h")
    elseif difSeconds > 60 then
      return timeFormat:format(Round(difSeconds / 60), "m")
    end
    return timeFormat:format(difSeconds, "s")
  end
end

do
  local map = {
    -- Midnight S1
    ["12769"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_1
    ["12770"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_2
    ["12771"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_3
    ["12772"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_4
    ["12773"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_5
    ["12774"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_6
    ["12775"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_7
    ["12776"] = ns.enums.itemTrack.adventurer, -- UpgradeTrack_Adventurer_8

    ["12777"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_1
    ["12778"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_2
    ["12779"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_3
    ["12780"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_4
    ["12781"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_5
    ["12782"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_6
    ["12783"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_7
    ["12784"] = ns.enums.itemTrack.veteran,    -- UpgradeTrack_Veteran_8

    ["12785"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_1
    ["12786"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_2
    ["12787"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_3
    ["12788"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_4
    ["12789"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_5
    ["12790"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_6
    ["12791"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_7
    ["12792"] = ns.enums.itemTrack.champion,   -- UpgradeTrack_Champion_8

    ["12793"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_1
    ["12794"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_2
    ["12795"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_3
    ["12796"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_4
    ["12797"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_5
    ["12798"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_6
    ["12799"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_7
    ["12800"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_8
    ["13787"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_9 sporefused
    ["13653"] = ns.enums.itemTrack.hero,       -- UpgradeTrack_Hero_10 voidforged

    ["12801"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_1
    ["12802"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_2
    ["12803"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_3
    ["12804"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_4
    ["12805"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_5
    ["12806"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_6
    ["12807"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_7
    ["12808"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_8
    ["13654"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_10 voidforged
    ["13786"] = ns.enums.itemTrack.myth,       -- UpgradeTrack_Myth_9 sporefused

    -- Midnight S2
    
    ["12817"] = ns.enums.itemTrack.adventurer,-- UpgradeTrack_Adventurer_1
    ["12818"] = ns.enums.itemTrack.adventurer,-- UpgradeTrack_Adventurer_2
    ["12819"] = ns.enums.itemTrack.adventurer,-- UpgradeTrack_Adventurer_3
    ["12820"] = ns.enums.itemTrack.adventurer,-- UpgradeTrack_Adventurer_4
    ["12821"] = ns.enums.itemTrack.adventurer,-- UpgradeTrack_Adventurer_5
    ["12822"] = ns.enums.itemTrack.adventurer,-- UpgradeTrack_Adventurer_6
    ["12823"] = ns.enums.itemTrack.adventurer,-- UpgradeTrack_Adventurer_7
    ["12824"] = ns.enums.itemTrack.adventurer,-- UpgradeTrack_Adventurer_8

    ["12825"] = ns.enums.itemTrack.veteran,-- UpgradeTrack_Veteran_1
    ["12826"] = ns.enums.itemTrack.veteran,-- UpgradeTrack_Veteran_2
    ["12827"] = ns.enums.itemTrack.veteran,-- UpgradeTrack_Veteran_3
    ["12828"] = ns.enums.itemTrack.veteran,-- UpgradeTrack_Veteran_4
    ["12829"] = ns.enums.itemTrack.veteran,-- UpgradeTrack_Veteran_5
    ["12830"] = ns.enums.itemTrack.veteran,-- UpgradeTrack_Veteran_6
    ["12831"] = ns.enums.itemTrack.veteran,-- UpgradeTrack_Veteran_7
    ["12832"] = ns.enums.itemTrack.veteran,-- UpgradeTrack_Veteran_8

    ["12833"] = ns.enums.itemTrack.champion,-- UpgradeTrack_Champion_1
    ["12834"] = ns.enums.itemTrack.champion,-- UpgradeTrack_Champion_2
    ["12835"] = ns.enums.itemTrack.champion,-- UpgradeTrack_Champion_3
    ["12836"] = ns.enums.itemTrack.champion,-- UpgradeTrack_Champion_4
    ["12837"] = ns.enums.itemTrack.champion,-- UpgradeTrack_Champion_5
    ["12838"] = ns.enums.itemTrack.champion,-- UpgradeTrack_Champion_6
    ["12839"] = ns.enums.itemTrack.champion,-- UpgradeTrack_Champion_7
    ["12840"] = ns.enums.itemTrack.champion,-- UpgradeTrack_Champion_8

    ["12841"] = ns.enums.itemTrack.hero,-- UpgradeTrack_Hero_1
    ["12842"] = ns.enums.itemTrack.hero,-- UpgradeTrack_Hero_2
    ["12843"] = ns.enums.itemTrack.hero,-- UpgradeTrack_Hero_3
    ["12844"] = ns.enums.itemTrack.hero,-- UpgradeTrack_Hero_4
    ["12845"] = ns.enums.itemTrack.hero,-- UpgradeTrack_Hero_5
    ["12846"] = ns.enums.itemTrack.hero,-- UpgradeTrack_Hero_6
    ["12847"] = ns.enums.itemTrack.hero,-- UpgradeTrack_Hero_7
    ["12848"] = ns.enums.itemTrack.hero,-- UpgradeTrack_Hero_8
    --["123456789"] = ,-- UpgradeTrack_Hero_9 NYI
    --["123456789"] = ,-- UpgradeTrack_Hero_10 NYI

    ["12849"] = ns.enums.itemTrack.myth,-- UpgradeTrack_Myth_1
    ["12850"] = ns.enums.itemTrack.myth,-- UpgradeTrack_Myth_2
    ["12851"] = ns.enums.itemTrack.myth,-- UpgradeTrack_Myth_3
    ["12852"] = ns.enums.itemTrack.myth,-- UpgradeTrack_Myth_4
    ["12853"] = ns.enums.itemTrack.myth,-- UpgradeTrack_Myth_5
    ["12854"] = ns.enums.itemTrack.myth,-- UpgradeTrack_Myth_6
    ["12855"] = ns.enums.itemTrack.myth,-- UpgradeTrack_Myth_7
    ["12856"] = ns.enums.itemTrack.myth,-- UpgradeTrack_Myth_8
    ["13848"] = ns.enums.itemTrack.myth,-- UpgradeTrack_Myth_9 very rare?
    --["123456879"] = ns.enums.itemTrack.myth,-- UpgradeTrack_Myth_10 NYI

  }
  local contextToItemTrack = {
    ["raid-finder"] = ns.enums.itemTrack.veteran,
    ["raid-normal"] = ns.enums.itemTrack.champion,
    ["raid-heroic"] = ns.enums.itemTrack.hero,
    ["raid-mythic"] = ns.enums.itemTrack.myth,
    --challenge-mode-jackpot
    --challenge-mode
  }
  ---@param itemLink string
  ---@return wowutils_enums_itemTrack itemTrack
  function ns.helpers.GetItemTrack(itemLink) -- just use bonus ids so we don't have to worry about any weirdness between localizations and items that cannot be upgraded
    -- TODO optimize? probably cba
    local t = { strsplit(":", itemLink) }
    for k, v in pairs(t) do -- this should find all real drops
      if map[v] then
        return map[v]
      end
    end
    -- this should catch tooltips from encounter journal etc
    local _, context = C_Item.GetItemCreationContext(itemLink)
    -- just ignore the rest for now TODO maybe do something about it?
    return context and contextToItemTrack[context] or ns.enums.itemTrack.none
  end
end

function ns.helpers.spairs(t, order)
  -- collect the keys
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end

  -- if order function given, sort by it by passing the table and keys a, b,
  -- otherwise just sort the keys
  if order then
    table.sort(keys, function(a, b) return order(t, a, b) end)
  else
    table.sort(keys)
  end

  -- return the iterator function
  local i = 0
  return function()
    i = i + 1
    if keys[i] then
      return keys[i], t[keys[i]]
    end
  end
end

do
  local cache = {
    [""] = "|T134400:0|t"
  }
  ---@param specId number
  ---@return string textureStr
  function ns.helpers.GetIconTextureStringForSpecId(specId)
    if not specId then
      return cache[""]
    end
    if cache[specId] then return cache[specId] end
    local specIcon = select(4, GetSpecializationInfoForSpecID(specId))
    if not specIcon then return cache[""] end
    cache[specId] = sformat("|T%s:0|t", specIcon)
    return cache[specId]
  end
end
do
  local cache = {
    [""] = "|T134400:0|t"
  }

  ---@param class string|number
  ---@return string textureStr
  function ns.helpers.GetIconTextureStringForClass(class)
    if not class then
      return cache[""]
    end
    if cache[class] then return cache[class] end
    if type(class) == "number" then
      local _, classFileName = GetClassInfo(class)
      if not classFileName then
        cache[class] = cache[""]
        return cache[""]
      end
      cache[class] = sformat("|A:%s:0:0|a", "classicon-"..classFileName:lower())
      return cache[class]
    end
    cache[class] = sformat("|A:%s:0:0|a", "classicon-"..class:lower())
    return cache[class]
  end
end
do
  local needsConverting = {

    [INVSLOT_FINGER2] = INVSLOT_FINGER1,
    [INVSLOT_TRINKET2] = INVSLOT_TRINKET1,
  }
  ---@param slot number
  ---@return number universalSlot
  function ns.helpers.GetUniversalSlot(slot)
    return needsConverting[slot] or slot
  end
end
do
  -- rings, trinkets and one hand weapons resolve to their first slot
  -- INVTYPE_BAG, INVTYPE_PROFESSION_TOOL, INVTYPE_PROFESSION_GEAR and INVTYPE_EQUIPABLESPELL_* have no single slot
  local equipLocToInvSlotId = {
    ["INVTYPE_HEAD"] = INVSLOT_HEAD,
    ["INVTYPE_NECK"] = INVSLOT_NECK,
    ["INVTYPE_SHOULDER"] = INVSLOT_SHOULDER,
    ["INVTYPE_BODY"] = INVSLOT_BODY,
    ["INVTYPE_CHEST"] = INVSLOT_CHEST,
    ["INVTYPE_ROBE"] = INVSLOT_CHEST,
    ["INVTYPE_WAIST"] = INVSLOT_WAIST,
    ["INVTYPE_LEGS"] = INVSLOT_LEGS,
    ["INVTYPE_FEET"] = INVSLOT_FEET,
    ["INVTYPE_WRIST"] = INVSLOT_WRIST,
    ["INVTYPE_HAND"] = INVSLOT_HAND,
    ["INVTYPE_FINGER"] = INVSLOT_FINGER1,
    ["INVTYPE_TRINKET"] = INVSLOT_TRINKET1,
    ["INVTYPE_CLOAK"] = INVSLOT_BACK,
    ["INVTYPE_WEAPON"] = INVSLOT_MAINHAND,
    ["INVTYPE_2HWEAPON"] = INVSLOT_MAINHAND,
    ["INVTYPE_WEAPONMAINHAND"] = INVSLOT_MAINHAND,
    ["INVTYPE_RANGED"] = INVSLOT_MAINHAND, -- ranged weapons go to the main hand on retail
    ["INVTYPE_RANGEDRIGHT"] = INVSLOT_MAINHAND,
    ["INVTYPE_THROWN"] = INVSLOT_MAINHAND,
    ["INVTYPE_WEAPONOFFHAND"] = INVSLOT_OFFHAND,
    ["INVTYPE_SHIELD"] = INVSLOT_OFFHAND,
    ["INVTYPE_HOLDABLE"] = INVSLOT_OFFHAND,
  }
  ---@param equipLoc string
  ---@return number
  function ns.helpers.GetInventorySlotByEquipLoc(equipLoc)
    if not equipLoc then return 0 end
    return equipLocToInvSlotId[equipLoc] or 0
  end
end
do
  local padding = 10
  ---@type table<table, table<number, Texture>>
  local separators = {}

  local function hideSeparators(tooltip)
    local textures = separators[tooltip]
    if not textures then return end
    for _, tex in ipairs(textures) do
      tex:Hide()
    end
  end

  -- the tooltip has no final width until its shown, so the width is (re)applied on every resize
  local function resizeSeparators(tooltip)
    local textures = separators[tooltip]
    if not textures then return end
    local width = tooltip:GetWidth() - (padding * 2)
    if width <= 0 then return end
    for _, tex in ipairs(textures) do
      if tex:IsShown() then
        tex:SetSize(width, 1)
      end
    end
  end

  ---Draws a separator texture above a tooltip line, stretched to the tooltips width.
  ---Call it right after adding the line, does nothing on a tooltip without a name.
  ---@param tooltip GameTooltip
  ---@param lineIndex number? defaults to the line that was added last
  function ns.helpers.AddTooltipSeparator(tooltip, lineIndex)
    local tooltipName = tooltip.GetName and tooltip:GetName()
    local fontString = tooltipName and _G[sformat("%sTextLeft%d", tooltipName, lineIndex or tooltip:NumLines())]
    if not fontString then return end
    local textures = separators[tooltip]
    if not textures then
      textures = {}
      separators[tooltip] = textures
      tooltip:HookScript("OnHide", hideSeparators)
      tooltip:HookScript("OnSizeChanged", resizeSeparators)
      if tooltip:HasScript("OnTooltipCleared") then
        tooltip:HookScript("OnTooltipCleared", hideSeparators)
      end
    end
    local separator
    for _, tex in ipairs(textures) do
      if not tex:IsShown() then
        separator = tex
        break
      end
    end
    if not separator then
      separator = tooltip:CreateTexture(nil, "OVERLAY")
      separator:SetColorTexture(1, 1, 1, 1)
      tinsert(textures, separator)
    end
    separator:ClearAllPoints()
    -- TOPLEFT gives us the left and top edge of the line, the rest comes from SetSize
    separator:SetPoint("TOPLEFT", fontString, "TOPLEFT", 0, 2)
    separator:SetSize(math.max(tooltip:GetWidth() - (padding * 2), 1), 1)
    separator:Show()
  end
end