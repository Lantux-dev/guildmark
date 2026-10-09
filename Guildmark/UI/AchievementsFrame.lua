-- Ventana de Desafíos de hermandad, con el aspecto de los desafíos de legado
-- de Forever (mismas texturas de Blizzard: tarjetas, escudo con corona, barra
-- de puntos y pista de recompensas). Si alguna textura no existe se usa un color.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local GOLD = "|cffffd100"
local GREY = "|cff9d9d9d"
local GREEN = "|cff1eff00"
local R = "|r"

local SHIELD = "UI-Legacy-Points-icon-c60"
local CARD_W, CARD_H = 540, 84
local CELL_H = 26

local frame, currentCategory, currentTab = nil, "general", "challenges"
local expanded = {}
local cards, catButtons, rewardCards = {}, {}, {}

local function hasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- Pone la primera textura (atlas) que exista de la lista; si ninguna, un color.
local function setArt(texture, candidates, r, g, b, a)
	for _, name in ipairs(candidates) do
		if hasAtlas(name) then
			texture:SetAtlas(name)
			texture:SetVertexColor(1, 1, 1, 1)
			return true
		end
	end
	texture:SetColorTexture(r or 0.1, g or 0.09, b or 0.07, a or 0.9)
	return false
end

local function fontString(parent, template, ...)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	if ... then fs:SetPoint(...) end
	fs:SetJustifyH("LEFT")
	return fs
end

-- Barra de progreso con las piezas de la barra de puntos de legado.
local function progressBar(parent, width, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(width, height)
	local fill = bar:CreateTexture(nil, "ARTWORK")
	setArt(fill, { "Legacy-Progressbar-Fill" }, 0.85, 0.65, 0.1, 1)
	bar:SetStatusBarTexture(fill)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	setArt(bar.bg, { "Legacy-Progressbar-BG" }, 0, 0, 0, 0.6)
	bar.border = bar:CreateTexture(nil, "OVERLAY")
	bar.border:SetPoint("TOPLEFT", -4, 4)
	bar.border:SetPoint("BOTTOMRIGHT", 4, -4)
	if not setArt(bar.border, { "Legacy-Progressbar-Frame" }) then bar.border:Hide() end
	bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.text:SetPoint("CENTER")
	bar.text:SetDrawLayer("OVERLAY", 7)
	return bar
end

-- Escudo con corona y el número de puntos.
local function shield(parent, size)
	local s = CreateFrame("Frame", nil, parent)
	s:SetSize(size, size)
	s.tex = s:CreateTexture(nil, "ARTWORK")
	s.tex:SetAllPoints()
	if not setArt(s.tex, { SHIELD }) then
		s.tex:SetTexture("Interface\\Icons\\INV_Shield_06")
	end
	s.text = s:CreateFontString(nil, "OVERLAY", size > 40 and "GameFontHighlightLarge" or "GameFontHighlight")
	s.text:SetPoint("CENTER", 0, -size * 0.08)
	return s
end

---------------------------------------------------------------------------
-- Tarjetas de desafío
---------------------------------------------------------------------------

local function getCard(i, parent)
	local c = cards[i]
	if c then return c end
	c = CreateFrame("Button", nil, parent)
	c:SetWidth(CARD_W)
	c.bg = c:CreateTexture(nil, "BACKGROUND")
	c.bg:SetAllPoints()

	c.iconBorder = c:CreateTexture(nil, "BORDER")
	c.iconBorder:SetSize(48, 48)
	c.iconBorder:SetPoint("TOPLEFT", 14, -16)
	c.iconBorder:SetColorTexture(0.55, 0.45, 0.2, 1)
	c.icon = c:CreateTexture(nil, "ARTWORK")
	c.icon:SetSize(44, 44)
	c.icon:SetPoint("CENTER", c.iconBorder, "CENTER")
	c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	c.title = fontString(c, "GameFontNormalLarge", "TOPLEFT", 74, -16)
	c.toggle = c:CreateTexture(nil, "ARTWORK")
	c.toggle:SetSize(14, 14)
	c.toggle:SetPoint("TOPLEFT", 74, -42)
	c.desc = fontString(c, "GameFontHighlight", "LEFT", c.toggle, "RIGHT", 6, 0)
	c.desc:SetWidth(380)
	c.desc:SetWordWrap(false)

	c.bar = progressBar(c, 300, 12)
	c.bar:SetPoint("TOPLEFT", 74, -62)

	c.shield = shield(c, 38)
	c.shield:SetPoint("TOPRIGHT", -14, -14)

	c.date = fontString(c, "GameFontHighlightSmall", "BOTTOMRIGHT", -16, 10)
	c.date:SetJustifyH("RIGHT")

	c.cells = {}
	c:SetScript("OnClick", function(self)
		expanded[self.id] = not expanded[self.id]
		ns.RefreshAchievements()
	end)
	cards[i] = c
	return c
end

local function getCell(card, j)
	local cell = card.cells[j]
	if cell then return cell end
	cell = CreateFrame("Frame", nil, card)
	cell:SetSize((CARD_W - 60) / 2 - 4, CELL_H - 4)
	cell.bg = cell:CreateTexture(nil, "BACKGROUND")
	cell.bg:SetAllPoints()
	cell.bg:SetColorTexture(0, 0, 0, 0.35)
	cell.check = cell:CreateTexture(nil, "ARTWORK")
	cell.check:SetSize(14, 14)
	cell.check:SetPoint("LEFT", 6, 0)
	setArt(cell.check, { "worldquest-tracker-checkmark" }, 0.1, 0.9, 0.1, 1)
	cell.text = fontString(cell, "GameFontHighlightSmall", "LEFT", 24, 0)
	cell.text:SetWidth(cell:GetWidth() - 30)
	cell.text:SetWordWrap(false)
	card.cells[j] = cell
	return cell
end

local function layoutCard(c, entry, y)
	local def = entry.def
	c.id = def.id
	local open = expanded[def.id] or false
	local criteria = entry.criteria or {}
	local rows = open and math.ceil(#criteria / 2) or 0
	local height = CARD_H + (open and #criteria > 0 and (rows * CELL_H + 8) or 0)
	c:SetHeight(height)
	c:ClearAllPoints()
	c:SetPoint("TOPLEFT", 0, -y)

	-- Fondo: completado (normal), abierto (borde dorado) o pendiente (apagado).
	if open then
		setArt(c.bg, { "Legacy-Challenge-Cards-selected", "Legacy-Challenge-Cards" }, 0.18, 0.15, 0.08, 0.95)
	elseif entry.done then
		setArt(c.bg, { "Legacy-Challenge-Cards", "Legacy-Challenge-Cards-selected" }, 0.16, 0.13, 0.07, 0.95)
	else
		setArt(c.bg, { "Legacy-Challenge-Cards-Disable" }, 0.09, 0.08, 0.06, 0.95)
	end

	-- Desafío oculto sin completar: no se desvela nada.
	local secret = def.hidden and not entry.done
	c.icon:SetTexture(secret and "Interface\\Icons\\INV_Misc_QuestionMark" or def.icon)
	c.icon:SetDesaturated(not entry.done)
	c.iconBorder:SetColorTexture(entry.done and 0.85 or 0.35, entry.done and 0.7 or 0.32, entry.done and 0.25 or 0.28, 1)
	c.title:SetText((entry.done and "|cffffffff" or GREY) .. (secret and L["Logro oculto"] or def.name) .. R)
	c.desc:SetText((entry.done and "" or GREY) .. (secret and L["Sigue jugando para descubrirlo."] or def.desc) .. (entry.done and "" or R))

	c.toggle:SetShown(#criteria > 0)
	if #criteria > 0 then
		local atlas = open and "128-RedButton-Minus" or "128-RedButton-Plus"
		if not setArt(c.toggle, { atlas, "128-RedButton-Plus" }) then c.toggle:Hide() end
	end

	-- Barra de progreso para los contadores (no para los ya completados).
	local showBar = not entry.done and not secret and entry.target > 1 and #criteria == 0
	c.bar:SetShown(showBar)
	if showBar then
		c.bar:SetMinMaxValues(0, entry.target)
		c.bar:SetValue(entry.progress)
		c.bar.text:SetText(("%d / %d"):format(entry.progress, entry.target))
	end
	if not entry.done and #criteria > 0 then
		c.desc:SetText(GREY .. def.desc .. ("  (%d/%d)"):format(entry.progress, entry.target) .. R)
	end

	c.shield:SetShown(not def.feat) -- las proezas no dan puntos
	c.shield.text:SetText("1")
	c.shield.tex:SetDesaturated(not entry.done)
	c.date:SetText(entry.done and entry.doneAt and (GOLD .. date("%d/%m/%y", entry.doneAt) .. R) or "")

	for j, cell in ipairs(c.cells) do cell:Hide() end
	if open then
		for j, crit in ipairs(criteria) do
			local cell = getCell(c, j)
			local col = (j - 1) % 2
			local row = math.floor((j - 1) / 2)
			cell:ClearAllPoints()
			cell:SetPoint("TOPLEFT", 30 + col * ((CARD_W - 60) / 2), -(CARD_H + row * CELL_H))
			cell.text:SetText((crit.done and "|cffffffff" or GREY) .. crit.label .. R)
			cell.check:SetShown(crit.done)
			cell:Show()
		end
	end
	c:Show()
	return height
end

---------------------------------------------------------------------------
-- Pestaña de recompensas
---------------------------------------------------------------------------

local function layoutRewards(points)
	local f = frame
	f.rewardsShield.text:SetText(tostring(ns.GuildLevel(points)))
	f.rewardsLabel:SetText((L["Nivel de hermandad %d · %d puntos"]):format(ns.GuildLevel(points), points))
	for i, r in ipairs(ns.ACH_REWARDS) do
		local card = rewardCards[i]
		if not card then
			card = CreateFrame("Frame", nil, f.rewards)
			card:SetSize(146, 150)
			local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
			card:SetPoint("TOPLEFT", 26 + col * 160 + (row == 1 and 80 or 0), -152 - row * 172)
			card.bg = card:CreateTexture(nil, "BACKGROUND")
			card.bg:SetAllPoints()
			card.diamond = card:CreateTexture(nil, "ARTWORK")
			card.diamond:SetSize(44, 44)
			card.diamond:SetPoint("TOP", 0, 20)
			card.diamondText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			card.diamondText:SetPoint("CENTER", card.diamond, "CENTER")
			card.iconFrame = card:CreateTexture(nil, "BORDER")
			card.iconFrame:SetSize(60, 60)
			card.iconFrame:SetPoint("CENTER", 0, 18)
			card.icon = card:CreateTexture(nil, "ARTWORK")
			card.icon:SetSize(46, 46)
			card.icon:SetPoint("CENTER", card.iconFrame, "CENTER")
			card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			card.label = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			card.label:SetPoint("TOP", card.iconFrame, "BOTTOM", 0, -8)
			card.label:SetWidth(132)
			rewardCards[i] = card
		end
		local unlocked = points >= r.points
		setArt(card.bg, unlocked and { "Legacy-Rewards-Tracker-Cards", "Legacy-Rewards-Tracker-Cards-Disable" } or { "Legacy-Rewards-Tracker-Cards-Disable" },
			0.1, 0.09, 0.07, 0.95)
		setArt(card.diamond, unlocked and { "Legacy-Rewards-Tracker-Diamond", "Legacy-Rewards-Tracker-Diamond-Disable" } or { "Legacy-Rewards-Tracker-Diamond-Disable" },
			0.3, 0.3, 0.3, 1)
		setArt(card.iconFrame, unlocked and { "Legacy-Rewards-Tracker-Icons-Frame", "Legacy-Rewards-Tracker-Icons-Frame-Disable" } or { "Legacy-Rewards-Tracker-Icons-Frame-Disable" },
			0.3, 0.3, 0.3, 1)
		card.diamondText:SetText(tostring(i + 1)) -- el nivel
		card.icon:SetTexture(r.icon)
		card.icon:SetDesaturated(not unlocked)
		card.label:SetText((unlocked and "|cffffffff" or GREY) .. r.label .. R)
	end
	-- Barra: lo que falta para el siguiente nivel.
	local level = ns.GuildLevel(points)
	local from, to = (level - 1) * 10, level * 10
	if level > #ns.ACH_REWARDS then from, to = #ns.ACH_REWARDS * 10, #ns.ACH_REWARDS * 10 end
	f.rewardsBar:SetMinMaxValues(from, math.max(to, from + 1))
	f.rewardsBar:SetValue(math.min(points, to))
	f.rewardsBar.text:SetText(level > #ns.ACH_REWARDS and L["Nivel máximo"] or (L["%d / %d puntos para el nivel %d"]):format(points, to, level + 1))
end

---------------------------------------------------------------------------
-- Ventana
---------------------------------------------------------------------------

local function render()
	if not frame or not frame:IsShown() then return end
	local state = ns.AchievementState()
	frame.points.text:SetText(tostring(state.points))
	frame.pointsBar:SetMinMaxValues(0, state.total)
	frame.pointsBar:SetValue(state.points)
	frame.pointsBar.text:SetText((L["Puntos de hermandad %d/%d"]):format(state.points, state.total))

	-- Solo con un complemento que publique (API.lua) y siendo maestro de hermandad.
	local canPublish = ns.PublishButton("achievements") ~= nil
	frame.publish:SetShown(canPublish)
	-- Ventana de 860: escudo en 250 + 46 + 10, barra y, si sale, botón de 150 con margen.
	frame.pointsBar:SetWidth(canPublish and 370 or 520)
	frame.challenges:SetShown(currentTab == "challenges")
	frame.rewards:SetShown(currentTab == "rewards")
	for key, tab in pairs(frame.sideTabs) do
		setArt(tab.bg, { key == currentTab and "common-sidetab-selected" or "common-sidetab" }, 0.15, 0.13, 0.1, 1)
	end
	if currentTab == "rewards" then
		layoutRewards(state.points)
		return
	end

	-- Categorías con su recuento; las que tienen subcategorías las despliegan debajo al elegirlas.
	local function counts(keys)
		local done, total = 0, 0
		for _, entry in ipairs(state.list) do
			if keys[entry.def.cat] then
				total = total + 1
				if entry.done then done = done + 1 end
			end
		end
		return done, total
	end
	local function countText(done, total, feats)
		if feats then return done > 0 and (GOLD .. done .. R) or "" end
		return (done == total and GREEN or GREY) .. done .. "/" .. total .. R
	end
	local y = -4
	for i, cat in ipairs(ns.ACH_CATEGORIES) do
		local b = catButtons[i]
		local keys = { [cat.key] = true }
		local open = cat.key == currentCategory
		for _, s in ipairs(cat.sub or {}) do
			keys[s.key] = true
			if s.key == currentCategory then open = true end
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 4, y)
		y = y - 38
		setArt(b.bg, { open and "Legacy-Challenge-Left-Sub-Tab-selected" or "Legacy-Challenge-Left-Sub-Tab" },
			open and 0.3 or 0.12, open and 0.25 or 0.1, 0.08, 0.9)
		b.label:SetText((open and "|cffffffff" or GOLD) .. cat.label .. R)
		local done, total = counts(keys)
		b.count:SetText(countText(done, total, cat.feats))
		for j, s in ipairs(cat.sub or {}) do
			local sb = b.subs[j]
			sb:SetShown(open)
			if open then
				local selected = s.key == currentCategory
				sb:ClearAllPoints()
				sb:SetPoint("TOPLEFT", 24, y + 2)
				setArt(sb.bg, { selected and "Legacy-Challenge-Left-Sub-Tab-selected" or "Legacy-Challenge-Left-Sub-Tab" }, 0.1, 0.08, 0.06, 0.9)
				sb.bg:SetAlpha(selected and 1 or 0.55)
				sb.label:SetText((selected and "|cffffffff" or "|cffd8c8a0") .. s.label .. R)
				sb.count:SetText(countText(counts({ [s.key] = true })))
				y = y - 28
			end
		end
	end

	-- Tarjetas de la categoría: primero las completadas (la más reciente arriba) y luego las
	-- pendientes, las de más progreso primero; a igualdad, el orden del catálogo.
	local list, order = {}, {}
	for i, entry in ipairs(state.list) do
		if entry.def.cat == currentCategory then
			list[#list + 1] = entry
			order[entry] = i
		end
	end
	local function ratio(e) return (e.target or 0) > 0 and (e.progress or 0) / e.target or 0 end
	table.sort(list, function(a, b)
		if (a.done and true) ~= (b.done and true) then return a.done and true or false end
		if a.done and (a.doneAt or 0) ~= (b.doneAt or 0) then return (a.doneAt or 0) > (b.doneAt or 0) end
		if not a.done and ratio(a) ~= ratio(b) then return ratio(a) > ratio(b) end
		return order[a] < order[b]
	end)
	local y = 0
	for i, entry in ipairs(list) do
		y = y + layoutCard(getCard(i, frame.cardsChild), entry, y) + 6
	end
	if not frame.emptyText then
		frame.emptyText = frame.cardsChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		frame.emptyText:SetPoint("TOPLEFT", 16, -16)
		frame.emptyText:SetWidth(CARD_W - 32)
		frame.emptyText:SetJustifyH("LEFT")
	end
	-- Texto para una categoría vacía (proezas aún sin conseguir, subcategorías por activar).
	local emptyText = ""
	for _, cat in ipairs(ns.ACH_CATEGORIES) do
		if cat.key == currentCategory and cat.feats then
			emptyText = L["Aún no hay proezas. Al terminar cada temporada JcJ, lo que hayáis logrado en las guerras (liga alcanzada, temporada invicta) queda aquí para siempre."]
		end
		for _, s in ipairs(cat.sub or {}) do
			if s.key == currentCategory and s.empty then emptyText = s.empty end
		end
	end
	frame.emptyText:SetText(emptyText)
	frame.emptyText:SetShown(#list == 0)
	for i = #list + 1, #cards do cards[i]:Hide() end
	frame.cardsChild:SetHeight(y + 10)
end
ns.RefreshAchievements = render

local function create()
	local ok, f = pcall(CreateFrame, "Frame", "LantuxGuildAchievementsFrame", UIParent, "PortraitFrameTemplate")
	if not ok or not f then
		f = CreateFrame("Frame", "LantuxGuildAchievementsFrame", UIParent, "BasicFrameTemplateWithInset")
	end
	frame = f
	f:SetSize(860, 560)
	f:SetPoint("CENTER", 40, 0)
	f:SetFrameStrata("HIGH")
	-- Toplevel: al pulsarla o arrastrarla pasa entera por delante de las otras ventanas del addon.
	if f.SetToplevel then f:SetToplevel(true) end
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:Raise(); self:StartMoving() end)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetScript("OnShow", function(self) self:Raise(); render() end)

	-- Título y retrato con el escudo de legado (si la plantilla tiene retrato).
	if f.SetTitle then
		f:SetTitle(L["Logros de hermandad"])
	else
		local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		title:SetPoint("TOP", 0, -5)
		title:SetText(L["Logros de hermandad"])
	end
	if f.SetPortraitAtlasRaw then
		pcall(f.SetPortraitAtlasRaw, f, "Legacy-up-c60")
	elseif f.SetPortraitToAsset then
		pcall(f.SetPortraitToAsset, f, ns.MEDIA .. "emblem_small")
	end

	-- Puntos: escudo y barra, como "Puntos de legado".
	f.points = shield(f, 46)
	f.points:SetPoint("TOPLEFT", 250, -26)
	f.pointsBar = progressBar(f, 480, 18)
	f.pointsBar:SetPoint("LEFT", f.points, "RIGHT", 10, 0)

	-- Publicar (solo con un complemento que lo haga; ver API.lua).
	f.publish = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.publish:SetSize(150, 22)
	-- A la derecha de la barra de puntos, en la misma línea (la barra se acorta al verse).
	f.publish:SetPoint("LEFT", f.pointsBar, "RIGHT", 18, 0)
	f.publish:SetText(L["Publicar"])
	f.publish:SetScript("OnClick", function() ns.Publish("achievements") end)
	f.publish:SetScript("OnEnter", function(self)
		local def = ns.PublishButton("achievements")
		if not def then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		for i, text in ipairs(def.tooltip) do
			if i == 1 then GameTooltip:SetText(text) else GameTooltip:AddLine(text, 1, 1, 1, true) end
		end
		GameTooltip:Show()
	end)
	f.publish:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Pestaña de desafíos: categorías a la izquierda y tarjetas a la derecha.
	f.challenges = CreateFrame("Frame", nil, f)
	f.challenges:SetPoint("TOPLEFT", 8, -80)
	f.challenges:SetPoint("BOTTOMRIGHT", -8, 8)

	local left = CreateFrame("Frame", nil, f.challenges)
	left:SetPoint("TOPLEFT", 4, 0)
	left:SetPoint("BOTTOMLEFT", 4, 0)
	left:SetWidth(250)
	for i, cat in ipairs(ns.ACH_CATEGORIES) do
		local b = CreateFrame("Button", nil, left)
		b:SetSize(240, 34)
		b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 38)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(24, 24)
		b.icon:SetPoint("LEFT", 8, 0)
		b.icon:SetTexture(cat.icon)
		b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		b.label = fontString(b, "GameFontNormal", "LEFT", 40, 0)
		b.count = fontString(b, "GameFontHighlightSmall", "RIGHT", -10, 0)
		b.count:SetJustifyH("RIGHT")
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		b:SetScript("OnClick", function()
			-- Con subcategorías y sin desafíos propios, se abre la primera.
			currentCategory = (cat.sub and not cat.own) and cat.sub[1].key or cat.key
			f.cardsScroll:SetVerticalScroll(0)
			render()
		end)
		-- Subcategorías: se colocan y se muestran en render, debajo de su categoría.
		b.subs = {}
		for j, s in ipairs(cat.sub or {}) do
			local sb = CreateFrame("Button", nil, left)
			sb:SetSize(220, 24)
			sb.bg = sb:CreateTexture(nil, "BACKGROUND")
			sb.bg:SetAllPoints()
			sb.label = fontString(sb, "GameFontHighlightSmall", "LEFT", 14, 0)
			sb.count = fontString(sb, "GameFontHighlightSmall", "RIGHT", -10, 0)
			sb.count:SetJustifyH("RIGHT")
			sb:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			sb:SetScript("OnClick", function()
				currentCategory = s.key
				f.cardsScroll:SetVerticalScroll(0)
				render()
			end)
			sb:Hide()
			b.subs[j] = sb
		end
		catButtons[i] = b
	end

	local right = CreateFrame("Frame", nil, f.challenges)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	right:SetPoint("BOTTOMRIGHT", 0, 0)
	right.bg = right:CreateTexture(nil, "BACKGROUND")
	right.bg:SetAllPoints()
	setArt(right.bg, { "Legacy-Challenge-BG" }, 0.06, 0.05, 0.04, 0.9)

	f.cardsScroll = CreateFrame("ScrollFrame", "LantuxGuildAchievementsScroll", right, "UIPanelScrollFrameTemplate")
	ns.StyleScrollBar(f.cardsScroll)
	f.cardsScroll:SetPoint("TOPLEFT", 10, -8)
	f.cardsScroll:SetPoint("BOTTOMRIGHT", -28, 8)
	f.cardsChild = CreateFrame("Frame", nil, f.cardsScroll)
	f.cardsChild:SetSize(CARD_W, 400)
	f.cardsScroll:SetScrollChild(f.cardsChild)

	-- Pestaña de recompensas: escudo grande, barra y pista de cartas.
	f.rewards = CreateFrame("Frame", nil, f)
	f.rewards:SetPoint("TOPLEFT", 8, -80)
	f.rewards:SetPoint("BOTTOMRIGHT", -8, 8)
	f.rewards.bg = f.rewards:CreateTexture(nil, "BACKGROUND")
	f.rewards.bg:SetAllPoints()
	setArt(f.rewards.bg, { "Legacy-Rewards-Tracker-background" }, 0.07, 0.06, 0.05, 0.9)
	f.rewardsShield = shield(f.rewards, 80)
	f.rewardsShield:SetPoint("TOP", 0, -10)
	f.rewardsLabel = f.rewards:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	f.rewardsLabel:SetPoint("TOP", f.rewardsShield, "BOTTOM", 0, -4)
	f.rewardsBar = progressBar(f.rewards, 760, 10)
	f.rewardsBar:SetPoint("TOP", 0, -126)

	-- Pestañas laterales, como en la ventana de legado.
	f.sideTabs = {}
	local tabs = {
		{ key = "challenges", icon = "Interface\\Icons\\INV_Misc_Book_09", tip = L["Logros"] },
		{ key = "rewards", icon = "Interface\\Icons\\INV_Misc_Gift_02", tip = L["Recompensas"] },
	}
	for i, t in ipairs(tabs) do
		local tab = CreateFrame("Button", nil, f)
		tab:SetSize(44, 44)
		tab:SetPoint("TOPLEFT", f, "TOPRIGHT", -2, -60 - (i - 1) * 50)
		tab.bg = tab:CreateTexture(nil, "BACKGROUND")
		tab.bg:SetAllPoints()
		tab.icon = tab:CreateTexture(nil, "ARTWORK")
		tab.icon:SetSize(30, 30)
		tab.icon:SetPoint("CENTER")
		tab.icon:SetTexture(t.icon)
		tab:SetScript("OnClick", function()
			currentTab = t.key
			render()
		end)
		tab:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(t.tip)
			GameTooltip:Show()
		end)
		tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f.sideTabs[t.key] = tab
	end

	ns.OnDataChanged(function() render() end)
end

-- Abre la ventana en una categoría (p. ej. "wars" desde JcJ › Guerras).
function ns.ShowAchievementsCategory(key)
	currentCategory = key
	currentTab = "challenges"
	if not frame then
		create()
	else
		frame:Show()
	end
	render()
end

function ns.ToggleAchievements()
	if not frame then
		create()
		render()
		return
	end
	frame:SetShown(not frame:IsShown())
end

---------------------------------------------------------------------------
-- Aviso de "¡Logro de hermandad completado!"
---------------------------------------------------------------------------

local toasts = {}

function ns.ShowAchievementToast(entry)
	local slot = #toasts + 1
	local t = CreateFrame("Button", nil, UIParent)
	t:SetSize(380, 84)
	t:SetFrameStrata("DIALOG")
	t:SetPoint("TOP", 0, -140 - (slot - 1) * 90)
	t.bg = t:CreateTexture(nil, "BACKGROUND")
	t.bg:SetAllPoints()
	setArt(t.bg, { "Legacy-Challenge-Cards-selected", "Legacy-Challenge-Cards" }, 0.18, 0.15, 0.08, 0.95)
	local icon = t:CreateTexture(nil, "ARTWORK")
	icon:SetSize(48, 48)
	icon:SetPoint("LEFT", 16, 0)
	icon:SetTexture(entry.def.icon)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local head = fontString(t, "GameFontNormal", "TOPLEFT", 76, -16)
	head:SetText(L["¡Logro de hermandad completado!"])
	local name = fontString(t, "GameFontHighlightLarge", "TOPLEFT", 76, -36)
	name:SetText(entry.def.name)
	local s = shield(t, 40)
	s:SetPoint("RIGHT", -14, 0)
	s.text:SetText("1")
	t:SetScript("OnClick", function()
		t:Hide()
		ns.ToggleAchievements()
	end)
	toasts[slot] = t
	-- Nivel 3 de hermandad: aviso dorado con su sonido.
	if ns.GuildPerks().goldToast then
		t.bg:SetVertexColor(1, 0.85, 0.45)
		head:SetText("|cffffd100" .. L["¡Logro de hermandad completado!"] .. "|r")
		pcall(PlaySound, (SOUNDKIT and SOUNDKIT.UI_LEGENDARY_LOOT_TOAST) or 63971)
	else
		pcall(PlaySound, (SOUNDKIT and SOUNDKIT.UI_70_CHALLENGE_MODE_COMPLETE_NO_UPGRADE) or 12891)
	end

	-- Se desvanece a los 7 segundos.
	local elapsed = 0
	t:SetScript("OnUpdate", function(self, dt)
		elapsed = elapsed + dt
		if elapsed > 7 then
			self:SetAlpha(math.max(0, 1 - (elapsed - 7)))
			if elapsed > 8 then
				self:Hide()
				self:SetScript("OnUpdate", nil)
				toasts[slot] = nil
			end
		end
	end)
end
