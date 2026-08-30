---@class wowutilsPrivate
---@field tooltip wowutils_tooltip

---@type string, wowutilsPrivate
local addon_name, ns = ...
local sformat = string.format

-- The candidate card shown from the RCLC voting frame and the loot popup. A custom frame
-- rather than GameTooltip so it can lay out real columns, plated icons and the site's type.
-- Rendering only: rclc.lua builds the model (see wowutils_tooltip_model below).

---@class wowutils_tooltip
ns.tooltip = {}

---@class wowutils_tooltip_item
---@field itemId number
---@field name string
---@field icon number
---@field quality number?
---@field subtitle string slot · difficulty/track

---@class wowutils_tooltip_candidate
---@field name string
---@field realm string?
---@field classFile string?

---@class wowutils_tooltip_pick
---@field itemId number
---@field label string
---@field priorityId number?
---@field updated number
---@field note string?

---@class wowutils_tooltip_simRow
---@field specId number?
---@field source string "RB"|"QE"
---@field profile string
---@field targets string
---@field simmedAt number
---@field gainText string absolute gain, "" for percent-only sources
---@field pctText string
---@field pct number
---@field entryLabel string? what tells this result apart from the sim's other results for the same item ("Ring 2"), only when some sim produced more than one. a conversion carries its source marker instead
---@field catalyst boolean? the result is a catalyst conversion, drawn as the catalyst marker
---@field sourceItemId number? the token this result converts from, drawn as that item's icon

---@class wowutils_tooltip_otherRow
---@field itemId number
---@field simLabel string
---@field catalyst boolean? the item is a catalyst conversion, drawn as the catalyst marker before its name
---@field sourceItemId number? the token this item converts from, drawn as that item's icon before its name
---@field gainText string
---@field pctText string
---@field pct number

---@class wowutils_tooltip_crest
---@field icon number
---@field current number
---@field earned number

---@class wowutils_tooltip_model
---@field item wowutils_tooltip_item
---@field candidate wowutils_tooltip_candidate
---@field viewedPick wowutils_tooltip_pick?
---@field otherPicks wowutils_tooltip_pick[]
---@field sims wowutils_tooltip_simRow[] one row per result, so several rows can come from the same sim
---@field simCount number? distinct sims behind those rows, which is what the header counts
---@field others wowutils_tooltip_otherRow[]
---@field crests wowutils_tooltip_crest[]?
---@field crestsUpdated number?
---@field watermarks {label: string, value: number}[]?
---@field watermarksUpdated number?
---@field noPlayerData boolean

local MEDIA_PATH = sformat([[Interface\AddOns\%s\media\]], addon_name)
local WHITE = [[Interface\Buttons\WHITE8x8]]

-- Site tokens (viserio globals.css, dark theme), as 0..1 rgb.
local COLORS = {
  surface1 = { 0.066, 0.066, 0.094 }, -- --surface-1 / --card
  surface2 = { 0.102, 0.102, 0.137 }, -- --surface-2, plates
  base = { 0.035, 0.035, 0.055 },     -- --surface-base
  border = { 0.13, 0.13, 0.17 },      -- --sidebar-border
  fg = { 0.98, 0.98, 0.98 },
  muted = { 0.63, 0.63, 0.70 },       -- --muted-foreground
  dim = { 0.42, 0.42, 0.48 },
  cta = { 0.393, 0.393, 0.947 },      -- --color-cta
  gain = { 0.15, 0.85, 0.52 },        -- hsl(152 70% 50%)
  loss = { 0.893, 0.346, 0.346 },     -- hsl(0 72% 62%)
}
-- PRIORITY_CONFIG colors from viserio app/types/loot.ts, keyed by raw tier id.
local PRIORITY_COLORS = {
  [1] = { 0.90, 0.80, 0.50 },
  [2] = { 0.15, 0.85, 0.52 },
  [3] = { 0.278, 0.62, 0.962 },
  [4] = { 0.68, 0.482, 0.958 },
  [5] = { 0.893, 0.346, 0.346 },
}

local W, PAD, ROW, GAP, EYEBROW = 500, 14, 18, 10, 16
local ICON = 16
-- right-hand ledger columns, measured from the card's right padding inward
local PCT_W, GAIN_W, BAR_W, AGE_W, COL_GAP = 52, 52, 56, 26, 10
local LEDGER_W = PCT_W + COL_GAP + GAIN_W + COL_GAP + BAR_W + COL_GAP + AGE_W

local function makeFont(name, file, size, flags)
  local f = CreateFont(name)
  f:SetFont(MEDIA_PATH .. "fonts\\" .. file, size, flags or "")
  f:SetTextColor(1, 1, 1)
  f:SetShadowOffset(0, 0)
  return f
end
local FONTS = {
  title = makeFont("WowUtilsCardTitle", "CalSans-SemiBold.ttf", 15),
  name = makeFont("WowUtilsCardName", "CalSans-SemiBold.ttf", 13),
  body = makeFont("WowUtilsCardBody", "IBMPlexSans-Medium.ttf", 12),
  small = makeFont("WowUtilsCardSmall", "IBMPlexSans-Regular.ttf", 11),
  eyebrow = makeFont("WowUtilsCardEyebrow", "IBMPlexSans-SemiBold.ttf", 10),
  mono = makeFont("WowUtilsCardMono", "IBMPlexMono-Medium.ttf", 12),
  monoSmall = makeFont("WowUtilsCardMonoSmall", "IBMPlexMono-Regular.ttf", 11),
}

---@param unixTimestamp number?
---@return string
local function age(unixTimestamp)
  if not unixTimestamp or unixTimestamp == 0 then return "never" end
  local d = GetServerTime() - unixTimestamp
  if d >= 86400 then return sformat("%dd", Round(d / 86400)) end
  if d >= 3600 then return sformat("%dh", Round(d / 3600)) end
  if d >= 60 then return sformat("%dm", Round(d / 60)) end
  return sformat("%ds", d)
end

local function rgb(c, a) return c[1], c[2], c[3], a or 1 end

--#region frame + pools
local card = CreateFrame("Frame", "WowUtilsCandidateCard", UIParent, "BackdropTemplate")
card:SetFrameStrata("TOOLTIP")
card:SetClampedToScreen(true)
card:SetWidth(W)
card:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
card:SetBackdropColor(COLORS.surface1[1], COLORS.surface1[2], COLORS.surface1[3], 0.97)
card:SetBackdropBorderColor(rgb(COLORS.border))
card:Hide()
-- one lamp, from above: a top-edge highlight inside the keyline
local topLight = card:CreateTexture(nil, "BORDER")
topLight:SetColorTexture(1, 1, 1, 0.06)
topLight:SetPoint("TOPLEFT", 1, -1)
topLight:SetPoint("TOPRIGHT", -1, -1)
topLight:SetHeight(1)

local pools = { fs = {}, tex = {}, frame = {} }
local used = { fs = 0, tex = 0, frame = 0 }

local function resetPools()
  for kind, pool in pairs(pools) do
    for i = 1, used[kind] do
      pool[i]:Hide()
      pool[i]:ClearAllPoints()
    end
    used[kind] = 0
  end
end

---@return FontString
local function text(font, str, r, g, b)
  used.fs = used.fs + 1
  local fs = pools.fs[used.fs]
  if not fs then
    fs = card:CreateFontString(nil, "OVERLAY")
    pools.fs[used.fs] = fs
  end
  fs:SetParent(card)
  fs:SetDrawLayer("OVERLAY")
  fs:SetFontObject(font)
  fs:SetWordWrap(false)
  fs:SetNonSpaceWrap(false)
  fs:SetJustifyH("LEFT")
  fs:SetWidth(0)
  fs:SetText(str)
  fs:SetTextColor(r or 1, g or 1, b or 1)
  fs:SetAlpha(1)
  fs:Show()
  return fs
end

---@return Texture
local function tex(layer)
  used.tex = used.tex + 1
  local t = pools.tex[used.tex]
  if not t then
    t = card:CreateTexture(nil, layer or "ARTWORK")
    pools.tex[used.tex] = t
  end
  t:SetParent(card)
  t:SetDrawLayer(layer or "ARTWORK")
  t:SetTexCoord(0, 1, 0, 1)
  t:SetVertexColor(1, 1, 1, 1)
  t:SetAlpha(1)
  t:Show()
  return t
end

---@return Frame
local function plateFrame()
  used.frame = used.frame + 1
  local f = pools.frame[used.frame]
  if not f then
    f = CreateFrame("Frame", nil, card, "BackdropTemplate")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    pools.frame[used.frame] = f
  end
  f:Show()
  return f
end
--#endregion

--#region primitives
---Seated inset with a 1px keyline that accepts a semantic color (the site's IconPlate).
local function plate(x, y, size, iconFile, keyColor)
  local f = plateFrame()
  f:SetSize(size, size)
  f:SetPoint("TOPLEFT", card, "TOPLEFT", x, y)
  f:SetBackdropColor(rgb(COLORS.base))
  f:SetBackdropBorderColor(rgb(keyColor or COLORS.border))
  local icon = tex("ARTWORK")
  icon:SetParent(f)
  icon:SetTexture(iconFile or 134400)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  return f
end

local function lucide(x, y, size, name, color)
  local t = tex("OVERLAY")
  t:SetTexture(MEDIA_PATH .. "icons\\" .. name .. ".tga")
  t:SetSize(size, size)
  t:SetPoint("TOPLEFT", card, "TOPLEFT", x, y)
  t:SetVertexColor(rgb(color or COLORS.muted))
  return t
end

---Muted small-caps section label with a lucide icon, optional right-side stamp.
local function eyebrow(y, iconName, label, right)
  lucide(PAD, y - 2, 12, iconName, COLORS.muted)
  text(FONTS.eyebrow, label:upper(), rgb(COLORS.muted)):SetPoint("TOPLEFT", card, "TOPLEFT", PAD + 17, y - 3)
  if right then
    local fs = text(FONTS.monoSmall, right, rgb(COLORS.dim))
    fs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD, y - 3)
  end
  return y - EYEBROW
end

---Lit chip: tinted background, ring, matching text (BossReadinessStrip ReadinessChip).
---Anchored by its right edge; returns its width.
local function chipRight(rightX, y, label, color)
  local fs = text(FONTS.small, label, rgb(color))
  local w = fs:GetStringWidth() + 14
  local f = plateFrame()
  f:SetSize(w, 16)
  f:SetPoint("TOPRIGHT", card, "TOPRIGHT", rightX, y - 1)
  f:SetBackdropColor(color[1], color[2], color[3], 0.16)
  f:SetBackdropBorderColor(color[1], color[2], color[3], 0.45)
  fs:SetParent(f)
  fs:SetPoint("CENTER", f, "CENTER", 0, 0)
  return w
end

---The ledger's right-hand columns: age | gain bar | absolute gain | percent, all right-aligned.
---@param y number
---@param ageText string?
---@param gainText string
---@param pctText string
---@param pct number
---@param maxAbs number largest |pct| in the section, scales the bar
local function ledgerColumns(y, ageText, gainText, pctText, pct, maxAbs)
  local col = pct >= 0 and COLORS.gain or COLORS.loss
  local right = -PAD
  local pctFs = text(FONTS.mono, pctText, rgb(col))
  pctFs:SetJustifyH("RIGHT")
  pctFs:SetWidth(PCT_W)
  pctFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", right, y - 2)
  right = right - PCT_W - COL_GAP
  local gainFs = text(FONTS.mono, gainText, rgb(COLORS.fg))
  gainFs:SetJustifyH("RIGHT")
  gainFs:SetWidth(GAIN_W)
  gainFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", right, y - 2)
  right = right - GAIN_W - COL_GAP
  -- lit fill on a dim track, growing from the left like the site's ledgers
  local track = tex("BORDER")
  track:SetColorTexture(1, 1, 1, 0.06)
  track:SetSize(BAR_W, 4)
  track:SetPoint("RIGHT", card, "TOPRIGHT", right, y - ROW / 2)
  if maxAbs > 0 and pct ~= 0 then
    local fill = tex("ARTWORK")
    fill:SetColorTexture(col[1], col[2], col[3], 0.85)
    fill:SetSize(math.max(2, BAR_W * math.min(1, math.abs(pct) / maxAbs)), 4)
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
  end
  right = right - BAR_W - COL_GAP
  if ageText then
    local ageFs = text(FONTS.monoSmall, ageText, rgb(COLORS.dim))
    ageFs:SetJustifyH("RIGHT")
    ageFs:SetWidth(AGE_W)
    ageFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", right, y - 3)
  end
end

local function itemNameOf(itemId)
  return C_Item.GetItemNameByID(itemId) or UNKNOWN
end
---the catalyst marker, built once. the rows these go in have ~50px of slack, so a source has to
---be shown as an inline icon rather than named
local catalystMarkup
local function catalystIcon()
  if catalystMarkup == nil then
    catalystMarkup = CreateAtlasMarkup("CreationCatalyst-32x32") or false
  end
  return catalystMarkup or ""
end
local sourceIconCache = {}
---@param itemId number the token or base item a result converts from
---@return string
local function sourceItemIcon(itemId)
  local cached = sourceIconCache[itemId]
  if cached then return cached end
  local icon = select(5, GetItemInfoInstant(itemId))
  -- not in the client's cache yet. return nothing rather than caching the fallback icon forever,
  -- the next draw picks it up
  if not icon then return "" end
  sourceIconCache[itemId] = CreateSimpleTextureMarkup(icon, ICON, ICON)
  return sourceIconCache[itemId]
end
---How a result is obtained when it is not a drop: the catalyst atlas, or the source item's own
---icon. Empty for anything that simply drops.
---Falls back to words when an icon cannot be built -- a missing atlas or an item the client has
---not cached yet would otherwise drop the fact that this is a conversion without a trace.
---@param catalyst boolean?
---@param sourceItemId number?
---@return string
local function sourceMarker(catalyst, sourceItemId)
  if catalyst then
    local icon = catalystIcon()
    return icon ~= "" and icon or "Catalyst"
  end
  if sourceItemId then
    local icon = sourceItemIcon(sourceItemId)
    if icon ~= "" then return icon end
    return C_Item.GetItemNameByID(sourceItemId) or "Token"
  end
  return ""
end
---@param itemId number
---@param catalyst boolean?
---@param sourceItemId number?
local function itemNameWithSource(itemId, catalyst, sourceItemId)
  local marker = sourceMarker(catalyst, sourceItemId)
  if marker == "" then return itemNameOf(itemId) end
  return sformat("%s %s", marker, itemNameOf(itemId))
end
local function itemIconOf(itemId)
  return select(5, GetItemInfoInstant(itemId)) or 134400
end
local function qualityColor(itemId)
  local q = C_Item.GetItemQualityByID(itemId)
  local col = q and ITEM_QUALITY_COLORS[q]
  if col then return { col.r, col.g, col.b } end
  return COLORS.border
end
--#endregion

--#region sections
---@param m wowutils_tooltip_model
local function header(m, y)
  local q = qualityColor(m.item.itemId)
  -- identity color rides the subject: quality keyline on the plate + a hairline down the header
  local hair = tex("ARTWORK")
  hair:SetColorTexture(q[1], q[2], q[3], 0.9)
  hair:SetSize(2, 36)
  hair:SetPoint("TOPLEFT", card, "TOPLEFT", 0, y)
  plate(PAD, y, 36, m.item.icon, q)
  local title = text(FONTS.title, m.item.name, q[1], q[2], q[3])
  title:SetPoint("TOPLEFT", card, "TOPLEFT", PAD + 44, y - 1)
  title:SetWidth(W - PAD * 2 - 44 - 150)
  text(FONTS.small, m.item.subtitle, rgb(COLORS.muted)):SetPoint("TOPLEFT", card, "TOPLEFT", PAD + 44, y - 20)

  local classColor = m.candidate.classFile and C_ClassColor.GetClassColor(m.candidate.classFile)
  local cr, cg, cb = 1, 1, 1
  if classColor then cr, cg, cb = classColor.r, classColor.g, classColor.b end
  local nameFs = text(FONTS.name, m.candidate.name, cr, cg, cb)
  nameFs:SetJustifyH("RIGHT")
  nameFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD, y - 2)
  if m.candidate.realm then
    local realmFs = text(FONTS.small, m.candidate.realm, rgb(COLORS.muted))
    realmFs:SetJustifyH("RIGHT")
    realmFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD, y - 20)
  end
  return y - 36 - GAP
end

---@param m wowutils_tooltip_model
local function wishlist(m, y)
  if not m.viewedPick and #m.otherPicks == 0 then return y end
  y = eyebrow(y, "heart", "Wishlist")
  local function row(pick, lit)
    local q = qualityColor(pick.itemId)
    plate(PAD, y - 1, ICON, itemIconOf(pick.itemId), lit and q or COLORS.border)
    local fs = text(FONTS.body, itemNameOf(pick.itemId), rgb(lit and COLORS.fg or COLORS.muted))
    fs:SetPoint("TOPLEFT", card, "TOPLEFT", PAD + ICON + 6, y - 2)
    fs:SetWidth(W - PAD * 2 - ICON - 6 - 190)
    local ageFs = text(FONTS.monoSmall, age(pick.updated), rgb(COLORS.dim))
    ageFs:SetJustifyH("RIGHT")
    ageFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD, y - 3)
    local color = PRIORITY_COLORS[pick.priorityId or 0] or COLORS.muted
    if lit then
      chipRight(-PAD - AGE_W - 4, y, pick.label, color)
    else
      local lab = text(FONTS.small, pick.label, rgb(color))
      lab:SetJustifyH("RIGHT")
      lab:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD - AGE_W - 4, y - 3)
    end
    y = y - ROW
    if pick.note and pick.note ~= "" then
      lucide(PAD + ICON + 6, y - 3, 11, "sticky_note", COLORS.dim)
      local note = text(FONTS.small, pick.note, rgb(COLORS.muted))
      note:SetPoint("TOPLEFT", card, "TOPLEFT", PAD + ICON + 21, y - 2)
      note:SetWidth(W - PAD * 2 - ICON - 21)
      y = y - ROW
    end
  end
  if m.viewedPick then row(m.viewedPick, true) end
  for _, pick in ipairs(m.otherPicks) do row(pick, false) end
  return y - GAP
end

---@param m wowutils_tooltip_model
local function droptimizer(m, y)
  if #m.sims == 0 then return y end
  -- rows are per result, the header counts the sims they came from
  local simCount = m.simCount or #m.sims
  y = eyebrow(y, "chart_no_axes_column", "Droptimizer", simCount == 1 and "1 sim" or sformat("%d sims", simCount))
  local maxAbs = 0
  local mixedSource = false
  for _, s in ipairs(m.sims) do
    maxAbs = math.max(maxAbs, math.abs(s.pct))
    if s.source ~= m.sims[1].source then mixedSource = true end
  end
  for _, s in ipairs(m.sims) do
    local x = PAD
    -- icon-first identity: the spec is the subject of the row, so it is always plated
    local specIcon = s.specId and select(4, GetSpecializationInfoForSpecID(s.specId))
    plate(x, y - 1, ICON, specIcon, COLORS.border)
    x = x + ICON + 6
    local label = s.profile
    if mixedSource then label = sformat("%s  %s", s.source, label) end
    local labelW = W - PAD * 2 - (x - PAD) - LEDGER_W - COL_GAP
    local fs = text(FONTS.body, label, rgb(COLORS.fg))
    fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, y - 2)
    local profileW = math.min(fs:GetStringWidth(), labelW)
    fs:SetWidth(profileW)
    -- a conversion shows its source icon, with no word for it. a slot label has no icon.
    -- the marker leads: this text is width-clipped, and a marker on the tail is the first thing
    -- to disappear on a long profile, which is exactly when the row still needs it
    local marker = sourceMarker(s.catalyst, s.sourceItemId)
    local sub = s.entryLabel and sformat("%s · %s", s.targets, s.entryLabel) or s.targets
    if marker ~= "" then sub = sformat("%s %s", marker, sub) end
    local tg = text(FONTS.small, sub, rgb(COLORS.muted))
    tg:SetPoint("TOPLEFT", card, "TOPLEFT", x + profileW + 6, y - 3)
    tg:SetWidth(math.max(0, labelW - profileW - 6))
    ledgerColumns(y, age(s.simmedAt), s.gainText, s.pctText, s.pct, maxAbs)
    y = y - ROW
  end
  return y - GAP
end

---@param m wowutils_tooltip_model
local function otherOptions(m, y)
  if #m.others == 0 then return y end
  y = eyebrow(y, "arrow_left_right", "Other options in slot", "best sim")
  local maxAbs = 0
  for _, o in ipairs(m.others) do maxAbs = math.max(maxAbs, math.abs(o.pct)) end
  for _, o in ipairs(m.others) do
    plate(PAD, y - 1, ICON, itemIconOf(o.itemId), COLORS.border)
    local labelW = W - PAD * 2 - ICON - 6 - LEDGER_W - COL_GAP
    local fs = text(FONTS.body, itemNameWithSource(o.itemId, o.catalyst, o.sourceItemId), rgb(COLORS.fg))
    fs:SetPoint("TOPLEFT", card, "TOPLEFT", PAD + ICON + 6, y - 2)
    local nameW = math.min(fs:GetStringWidth(), labelW - 60)
    fs:SetWidth(nameW)
    local sim = text(FONTS.small, o.simLabel, rgb(COLORS.muted))
    sim:SetPoint("TOPLEFT", card, "TOPLEFT", PAD + ICON + 6 + nameW + 8, y - 3)
    sim:SetWidth(math.max(0, labelW - nameW - 8))
    ledgerColumns(y, nil, o.gainText, o.pctText, o.pct, maxAbs)
    y = y - ROW
  end
  return y - GAP
end

---@param m wowutils_tooltip_model
local function crests(m, y)
  if m.noPlayerData then
    y = eyebrow(y, "coins", "Crests")
    text(FONTS.small, "No data from this player yet", rgb(COLORS.muted)):SetPoint("TOPLEFT", card, "TOPLEFT", PAD, y - 2)
    return y - ROW - GAP
  end
  if m.crests and #m.crests > 0 then
    y = eyebrow(y, "coins", "Crests", age(m.crestsUpdated))
    local x = PAD
    for _, c in ipairs(m.crests) do
      plate(x, y - 1, ICON, c.icon, COLORS.border)
      local fs = text(FONTS.mono, sformat("%d", c.current), rgb(COLORS.fg))
      fs:SetPoint("TOPLEFT", card, "TOPLEFT", x + ICON + 5, y - 2)
      local w1 = fs:GetStringWidth()
      local earned = text(FONTS.monoSmall, sformat("/ %d", c.earned), rgb(COLORS.dim))
      earned:SetPoint("TOPLEFT", card, "TOPLEFT", x + ICON + 5 + w1 + 3, y - 3)
      x = x + ICON + 5 + w1 + 3 + earned:GetStringWidth() + 16
    end
    y = y - ROW - GAP
  end
  if m.watermarks and #m.watermarks > 0 then
    y = eyebrow(y, "arrow_up_to_line", "Free upgrade up to", age(m.watermarksUpdated))
    for _, wm in ipairs(m.watermarks) do
      text(FONTS.small, wm.label, rgb(COLORS.muted)):SetPoint("TOPLEFT", card, "TOPLEFT", PAD, y - 3)
      local v = text(FONTS.mono, tostring(wm.value), rgb(COLORS.fg))
      v:SetJustifyH("RIGHT")
      v:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD, y - 2)
      y = y - ROW
    end
    y = y - GAP
  end
  return y
end
--#endregion

---@param owner Frame
---@param m wowutils_tooltip_model
function ns.tooltip.Show(owner, m)
  resetPools()
  local y = -PAD
  y = header(m, y)
  y = wishlist(m, y)
  y = droptimizer(m, y)
  y = otherOptions(m, y)
  y = crests(m, y)
  card:SetHeight(-y + PAD - GAP)
  ns.tooltip.PlaceAtCursor()
  card.owner = owner
  card:Show()
end

---Anchors the card beside the cursor without ever covering what is being hovered:
---above and to the right by default, flipping below / to the left when the screen runs out.
function ns.tooltip.PlaceAtCursor()
  local scale = UIParent:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
  local w, h = card:GetWidth(), card:GetHeight()
  local dx, dy = 18, 14 -- keeps the cursor's own row (and the cell under it) clear
  local side, edge = "LEFT", "BOTTOM"
  local x, y = cx + dx, cy + dy
  if cx + dx + w > screenW then side = "RIGHT"; x = cx - dx end
  if cy + dy + h > screenH then edge = "TOP"; y = cy - dy end
  card:ClearAllPoints()
  card:SetPoint(edge .. side, UIParent, "BOTTOMLEFT", x, y)
end

function ns.tooltip.Hide()
  card.owner = nil
  card:Hide()
end
