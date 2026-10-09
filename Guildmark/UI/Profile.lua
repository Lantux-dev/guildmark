-- Ventana del perfil: panel pegado a la derecha de la ventana principal (o
-- suelto si está cerrada) con la ficha de rol, el estuche de medallas, las
-- insignias del retrato y unas cifras. Se abre con el botón del retrato de la
-- cabecera, desde la ficha de un miembro o con /gmk perfil.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local GOLD = "|cffffd100"
local GREY = "|cff9d9d9d"
local R = "|r"

local W, H = 360, 640
local SLOT = 46          -- medalla
local PICK = 26          -- insignia del selector
local MAX_PICK = 12

local ART = {
	ring = "Interface\\Minimap\\MiniMap-TrackingBorder",
	mask = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
	classes = "Interface\\TargetingFrame\\UI-Classes-Circles",
}

local panel
local shown -- nombre del perfil que se ve
local arrowPair -- flechas de marco y terciopelo (se define con la edición)

local function grey(text) return GREY .. text .. R end

local function roundIcon(parent, size, layer)
	local icon = parent:CreateTexture(nil, layer or "ARTWORK")
	icon:SetSize(size, size)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local mask = parent.CreateMaskTexture and parent:CreateMaskTexture() or nil
	if mask and icon.AddMaskTexture then
		mask:SetTexture(ART.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(icon)
		icon:AddMaskTexture(mask)
	end
	return icon
end

local function ring(parent, size)
	local r = parent:CreateTexture(nil, "OVERLAY")
	r:SetTexture(ART.ring)
	r:SetSize(size * 1.7, size * 1.7)
	r:SetPoint("TOPLEFT", -1, 1)
	return r
end

local function showTip(self)
	if not self.tip then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	for i, text in ipairs(self.tip) do
		if i == 1 then GameTooltip:SetText(text) else GameTooltip:AddLine(text, 1, 1, 1, true) end
	end
	GameTooltip:Show()
end

local function fontString(parent, font, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetJustifyH("LEFT")
	if width then fs:SetWidth(width) end
	return fs
end

-- Línea fina dorada (bordes del estuche).
local function edge(parent, a1, a2, horizontal)
	local t = parent:CreateTexture(nil, "BORDER")
	t:SetColorTexture(0.85, 0.65, 0.2, 0.9)
	t:SetPoint(a1)
	t:SetPoint(a2)
	if horizontal then t:SetHeight(2) else t:SetWidth(2) end
	return t
end

---------------------------------------------------------------------------
-- Construcción
---------------------------------------------------------------------------

local function medalSlot(parent)
	local b = CreateFrame("Frame", nil, parent)
	b:SetSize(SLOT, SLOT)
	b.icon = roundIcon(b, SLOT - 8)
	b.icon:SetPoint("CENTER")
	b.ring = ring(b, SLOT)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.label:SetPoint("TOP", b, "BOTTOM", 0, -6)
	b.label:SetWidth(78)
	b.tier = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.tier:SetPoint("TOP", b.label, "BOTTOM", 0, -1)
	b:EnableMouse(true)
	b:SetScript("OnEnter", showTip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function pickButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(PICK, PICK)
	b.icon = roundIcon(b, PICK - 4)
	b.icon:SetPoint("CENTER")
	b.ring = ring(b, PICK)
	b.order = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.order:SetPoint("BOTTOMRIGHT", 4, -2)
	b:SetScript("OnEnter", showTip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function create()
	local ok, f = pcall(CreateFrame, "Frame", "GuildmarkProfileFrame", UIParent, "BasicFrameTemplateWithInset")
	if not ok or not f then f = CreateFrame("Frame", "GuildmarkProfileFrame", UIParent) end
	panel = f
	f:SetSize(W, H)
	f:SetFrameStrata("HIGH")
	-- Toplevel: al pulsarla o arrastrarla pasa entera por delante de las otras ventanas del addon.
	if f.SetToplevel then f:SetToplevel(true) end
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:Raise(); self:StartMoving() end)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	if type(f.TitleText) == "table" then f.TitleText:SetText(L["Perfil"]) end
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "GuildmarkProfileFrame") end -- se cierra con Escape

	-- Cabecera: clase, nombre, título, rango y papel.
	f.portrait = f:CreateTexture(nil, "ARTWORK")
	f.portrait:SetSize(56, 56)
	f.portrait:SetPoint("TOPLEFT", 16, -34)
	f.portrait:SetTexture(ART.classes)
	-- Marco de la tienda: aro alrededor del retrato.
	f.portraitRing = f:CreateTexture(nil, "OVERLAY")
	f.portraitRing:SetTexture(ART.ring)
	-- Misma proporción que las medallas del estuche (el aro de esta textura va arriba a la izquierda).
	f.portraitRing:SetSize(114, 114)
	f.portraitRing:SetPoint("TOPLEFT", f.portrait, "TOPLEFT", -7, 7)
	f.name = fontString(f, "GameFontNormalLarge", 210)
	f.name:SetPoint("TOPLEFT", f.portrait, "TOPRIGHT", 10, -4)
	f.title = fontString(f, "GameFontNormal", 210)
	f.title:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
	f.rank = fontString(f, "GameFontHighlightSmall", 210)
	f.rank:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)

	-- Lema e historia.
	f.motto = fontString(f, "GameFontNormal", W - 32)
	f.motto:SetPoint("TOPLEFT", 16, -100)
	f.motto:SetTextColor(1, 0.9, 0.6)
	f.story = fontString(f, "GameFontHighlightSmall", W - 32)
	f.story:SetPoint("TOPLEFT", f.motto, "BOTTOMLEFT", 0, -4)
	if f.story.SetMaxLines then f.story:SetMaxLines(6) end
	f.story:SetHeight(76)
	f.story:SetJustifyV("TOP")

	-- Estuche de medallas: terciopelo con borde dorado, dos filas de cuatro.
	f.caseTitle = fontString(f, "GameFontNormal")
	f.caseTitle:SetPoint("TOPLEFT", 16, -210)
	f.caseTitle:SetText(L["Estuche de medallas"])
	f.case = CreateFrame("Frame", nil, f)
	f.case:SetSize(W - 32, 196)
	f.case:SetPoint("TOPLEFT", f.caseTitle, "BOTTOMLEFT", 0, -6)
	f.caseBg = f.case:CreateTexture(nil, "BACKGROUND")
	f.caseBg:SetAllPoints()
	f.caseShade = f.case:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.caseShade:SetPoint("TOPLEFT", 6, -6)
	f.caseShade:SetPoint("BOTTOMRIGHT", -6, 6)
	f.edges = {
		edge(f.case, "TOPLEFT", "TOPRIGHT", true), edge(f.case, "BOTTOMLEFT", "BOTTOMRIGHT", true),
		edge(f.case, "TOPLEFT", "BOTTOMLEFT", false), edge(f.case, "TOPRIGHT", "BOTTOMRIGHT", false),
	}
	f.slots = {}
	for i = 1, #ns.MEDALS do
		local s = medalSlot(f.case)
		local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
		s:SetPoint("TOPLEFT", 18 + col * 80, -16 - row * 92)
		f.slots[i] = s
	end

	-- Insignias del retrato: las que puedes llevar; clic para elegir el orden.
	f.pickTitle = fontString(f, "GameFontNormal")
	f.pickTitle:SetPoint("TOPLEFT", f.case, "BOTTOMLEFT", 0, -12)
	f.pickTitle:SetText(L["Junto al retrato"])
	f.pickHint = fontString(f, "GameFontDisableSmall", W - 32)
	f.pickHint:SetPoint("TOPLEFT", f.pickTitle, "BOTTOMLEFT", 0, -2)
	f.picks = {}
	for i = 1, MAX_PICK do
		local b = pickButton(f)
		b:SetPoint("TOPLEFT", f.pickHint, "BOTTOMLEFT", 2 + (i - 1) * (PICK + 2), -8)
		f.picks[i] = b
	end
	f.auto = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.auto:SetSize(96, 20)
	f.auto:SetPoint("BOTTOMRIGHT", f.pickHint, "TOPRIGHT", 0, 0)
	f.auto:SetText(L["Automático"])
	f.auto:SetScript("OnClick", function() ns.SaveProfile({ badges = false }) end)

	-- Cifras.
	f.stats = fontString(f, "GameFontHighlightSmall", W - 32)
	f.stats:SetPoint("TOPLEFT", 16, -530)
	f.stats:SetSpacing(3)

	-- Botón de abajo: editar (el tuyo) u ocultar el texto (oficiales, en el de otro).
	f.edit = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.edit:SetSize(140, 22)
	f.edit:SetPoint("BOTTOM", 0, 12)
	-- Flechas para cambiar el terciopelo (junto al título del estuche) y el marco (bajo el
	-- retrato) entre los comprados en la tienda. Solo en tu perfil.
	f.velvetPrev, f.velvetNext = arrowPair(f, "velvet")
	f.velvetNext:SetPoint("BOTTOMRIGHT", f.case, "TOPRIGHT", 2, 0)
	f.velvetPrev:SetPoint("RIGHT", f.velvetNext, "LEFT", -2, 0)
	f.framePrev, f.frameNext = arrowPair(f, "frame")
	f.frameNext:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -50)
	f.framePrev:SetPoint("RIGHT", f.frameNext, "LEFT", -2, 0)
	return f
end

---------------------------------------------------------------------------
-- Edición
---------------------------------------------------------------------------

-- Lo que tienes de un tipo ("frame" o "velvet"), empezando por el de siempre (nil).
local function ownedOf(kind)
	local me = ns.PlayerFullName()
	local list = { false }
	for _, item in ipairs(ns.SHOP_ITEMS) do
		if item.kind == kind and ns.Owns(me, item.key) then list[#list + 1] = item.key end
	end
	return list
end

local function goShop()
	if not ns.SelectSubview then return end
	if not (_G.LantuxGuildFrame and _G.LantuxGuildFrame:IsShown()) then ns.ToggleMainFrame() end
	ns.SelectSubview("market", "shop")
end

-- Pasa al anterior (-1) o al siguiente (1) de lo que tienes; sin nada comprado, a la tienda.
local function cycle(kind, step)
	local list = ownedOf(kind)
	if #list == 1 then
		LG:Print(kind == "frame" and L["Todavía no tienes marcos: se compran con insignias en Mercado › Tienda."]
			or L["Todavía no tienes terciopelos: se compran con insignias en Mercado › Tienda."])
		goShop()
		return
	end
	local profile = ns.MemberProfile(ns.PlayerFullName())
	local current = profile[kind] and profile[kind].key or false
	local index = 1
	for i, key in ipairs(list) do
		if key == current then index = i end
	end
	index = (index - 1 + step) % #list + 1
	ns.UseCosmetic(kind, list[index] or nil)
end

arrowPair = function(parent, kind)
	local function arrow(step)
		local b = CreateFrame("Button", nil, parent)
		b:SetSize(24, 24)
		local page = step < 0 and "PrevPage" or "NextPage"
		b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. page .. "-Up")
		b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. page .. "-Down")
		b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. page .. "-Disabled")
		b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		b:SetScript("OnClick", function() cycle(kind, step) end)
		b.tip = { kind == "frame" and L["Cambiar el marco"] or L["Cambiar el terciopelo"],
			L["Entre los que has comprado en la tienda. Los demás lo ven al abrir tu perfil."] }
		b:SetScript("OnEnter", showTip)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return b
	end
	return arrow(-1), arrow(1)
end

local function showEditDialog()
	local me = ns.PlayerFullName()
	local profile = ns.MemberProfile(me)
	local titles = ns.AvailableTitles(me)
	local titleItems, roleItems = { L["(sin título)"] }, { L["(sin papel)"] }
	for _, t in ipairs(titles) do titleItems[#titleItems + 1] = t.label end
	for _, r in ipairs(ns.PROFILE_ROLES) do roleItems[#roleItems + 1] = r.label end
	ns.ShowInputDialog({
		title = L["Editar ficha"],
		text = L["Lo verá tu hermandad. Los oficiales pueden ocultar el texto si no es apropiado."],
		submit = L["Guardar"],
		fields = {
			{ key = "title", label = L["Título"], width = 260, default = profile.title or "",
				options = function() return { { items = titleItems } } end },
			{ key = "role", label = L["Papel"], width = 260, default = profile.role or "",
				options = function() return { { items = roleItems } } end },
			{ key = "motto", label = L["Lema"], width = 286, maxLetters = 60, default = profile.motto or "" },
			{ key = "story", label = L["Historia"], width = 286, height = 120, multiline = true, maxLetters = 300, default = profile.story or "" },
		},
		onSubmit = function(v)
			local titleKey, roleKey = "", ""
			for _, t in ipairs(titles) do
				if t.label == v.title then titleKey = t.key end
			end
			for _, r in ipairs(ns.PROFILE_ROLES) do
				if r.label == v.role then roleKey = r.key end
			end
			if v.title ~= "" and v.title ~= L["(sin título)"] and titleKey == "" then return L["Elige un título de la lista."] end
			if v.role ~= "" and v.role ~= L["(sin papel)"] and roleKey == "" then return L["Elige un papel de la lista."] end
			ns.SaveProfile({ title = titleKey, role = roleKey, motto = v.motto or "", story = v.story or "" })
		end,
	})
end

-- Pone o quita una insignia del retrato (la lista guarda el orden de elección).
local function togglePick(pick)
	local profile = ns.MemberProfile(ns.PlayerFullName())
	local current = {}
	if profile.badges then
		for _, k in ipairs(profile.badges) do current[#current + 1] = k end
	else
		-- Primera elección: se parte de las que salen ahora.
		for _, key in ipairs(ns.BadgeData(ns.PlayerFullName()) and ns.BadgeData(ns.PlayerFullName()).honors or {}) do
			current[#current + 1] = key
		end
	end
	for i, k in ipairs(current) do
		if k == pick then
			table.remove(current, i)
			ns.SaveProfile({ badges = current })
			return
		end
	end
	if #current >= 5 then
		LG:Print(L["Como mucho 5 insignias junto al retrato."])
		return
	end
	current[#current + 1] = pick
	ns.SaveProfile({ badges = current })
end

---------------------------------------------------------------------------
-- Pintar
---------------------------------------------------------------------------

-- Lo donado al cofre, si ha donado algo.
local function donatedText(name)
	for _, d in ipairs(ns.ChestDonors()) do
		if d.name == name then return (L["Ha donado %d insignias al cofre"]):format(d.total) end
	end
	return ""
end

-- Lo aportado al banco de la hermandad del juego.
local function bankText(name)
	for _, d in ipairs(ns.BankDonors()) do
		if d.name == name then
			return (L["Al banco de la hermandad: %s y %d objetos"]):format(ns.MoneyText(d.gold), d.items)
		end
	end
	return ""
end

-- Unidad del juego de un miembro, si la hay ahora mismo (para su retrato).
local function portraitUnit(name)
	if name == ns.PlayerFullName() then return "player" end
	local units = { "target", "focus", "mouseover" }
	for i = 1, 4 do units[#units + 1] = "party" .. i end
	for i = 1, 40 do units[#units + 1] = "raid" .. i end
	for _, unit in ipairs(units) do
		if UnitExists(unit) and UnitIsPlayer(unit) and ns.UnitFullName(unit) == name then return unit end
	end
	return nil
end

local function classCoords(class)
	local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class or ""]
	if c then return c[1], c[2], c[3], c[4] end
	return 0, 1, 0, 1
end

local function render()
	if not panel or not panel:IsShown() or not shown then return end
	local f, name = panel, shown
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	local mine = name == me
	local m = g and (g.members[name] or ns.roster[name]) or {}
	local profile = ns.MemberProfile(name)
	local rank = ns.MeritRank(name)

	-- Retrato de verdad si el personaje está a mano (tú, tu objetivo o tu grupo); si no, su clase.
	local unit = portraitUnit(name)
	if unit and SetPortraitTexture then
		SetPortraitTexture(f.portrait, unit)
		f.portrait:SetTexCoord(0, 1, 0, 1)
	else
		f.portrait:SetTexture(ART.classes)
		f.portrait:SetTexCoord(classCoords(m.class))
	end
	-- Cosméticos de la tienda: marco (aro y borde del estuche) y terciopelo.
	local frameColor = profile.frame and profile.frame.color or { 0.85, 0.65, 0.2 }
	f.portraitRing:SetShown(profile.frame ~= nil)
	f.portraitRing:SetVertexColor(frameColor[1], frameColor[2], frameColor[3])
	for _, e in ipairs(f.edges) do e:SetColorTexture(frameColor[1], frameColor[2], frameColor[3], 0.95) end
	local v = profile.velvet and profile.velvet.color or ns.DEFAULT_VELVET
	f.caseBg:SetColorTexture(v[1], v[2], v[3], 0.95)
	f.caseShade:SetColorTexture(v[1] * 0.6, v[2] * 0.6, v[3] * 0.6, 0.9)
	f.name:SetText(ns.ClassColorName(name, m.class))
	f.title:SetText(profile.title and (GOLD .. profile.title .. R) or grey(mine and L["Sin título: elige uno al editar la ficha."] or ""))
	f.rank:SetText(((rank and rank.label) or "") .. (profile.role and ("  ·  " .. profile.role) or ""))
	if profile.hidden then
		f.motto:SetText(grey(L["Un oficial ha ocultado el texto de esta ficha."]))
		f.story:SetText("")
	else
		f.motto:SetText(profile.motto and ("«" .. profile.motto .. "»") or grey(mine and L["Sin lema todavía."] or ""))
		f.story:SetText(profile.story or grey(mine and L["Cuenta algo de tu personaje: «Editar ficha»."] or ""))
	end

	-- Medallas: las ganadas brillan con su metal; las que faltan, en silueta.
	for i, md in ipairs(ns.MemberMedals(name)) do
		local s = f.slots[i]
		local def = md.def
		s.icon:SetTexture(ns.MEDAL_ART[def.key] and (ns.MEDIA .. "Medals\\" .. def.key) or def.icon)
		local tier = ns.MEDAL_TIERS[md.tier]
		if tier then
			s.icon:SetDesaturated(false)
			s.icon:SetVertexColor(1, 1, 1)
			s.ring:SetVertexColor(tier.color[1], tier.color[2], tier.color[3])
			s.tier:SetText(("|cff%02x%02x%02x%s|r"):format(math.floor(tier.color[1] * 255), math.floor(tier.color[2] * 255), math.floor(tier.color[3] * 255), tier.label))
		else
			s.icon:SetDesaturated(true)
			s.icon:SetVertexColor(0.12, 0.1, 0.1)
			s.ring:SetVertexColor(0.35, 0.33, 0.3)
			s.tier:SetText(grey(L["sin ella"]))
		end
		s.label:SetText(def.label)
		local tip = { def.label, def.desc }
		if tier then tip[#tip + 1] = (L["Grado: %s"]):format(tier.label) end
		if md.nextTarget then
			tip[#tip + 1] = grey((L["%d / %d para %s"]):format(md.value, md.nextTarget, ns.MEDAL_TIERS[md.nextTier].label))
		elseif md.needsRaid then
			tip[#tip + 1] = grey(L["Para el oro falta un jefe de banda con la hermandad."])
		end
		if def.title then tip[#tip + 1] = grey((L["El oro da el título «%s»."]):format(def.title)) end
		s.tip = tip
	end

	-- Insignias del retrato: en el tuyo, para elegir; en el de otro, las que lleva.
	local candidates, chosen = {}, {}
	if mine then
		candidates = ns.BadgeCandidates(me)
		for i, k in ipairs(profile.badges or {}) do chosen[k] = i end
		f.pickHint:SetText(profile.badges and L["Clic para quitar o añadir (máx. 5, en ese orden)."] or L["Ahora salen solas. Clic para elegir las tuyas (máx. 5)."])
	else
		local data = ns.BadgeData(name)
		for i, key in ipairs(data and data.honors or {}) do
			candidates[#candidates + 1] = { pick = key, key = key }
			chosen[key] = i
		end
		f.pickHint:SetText(#candidates > 0 and L["Las que lleva junto al retrato."] or grey(L["No lleva ninguna."]))
	end
	f.auto:SetShown(mine and profile.badges ~= nil)
	for i, b in ipairs(f.picks) do
		local c = candidates[i]
		local h = c and ns.ResolveHonor(c.key)
		b:SetShown(h ~= nil)
		if h then
			b.icon:SetTexture(h.icon)
			local on = chosen[c.pick] ~= nil or (mine and not profile.badges)
			b.icon:SetDesaturated(not on)
			b.icon:SetAlpha(on and 1 or 0.45)
			local col = h.color or { 1, 0.85, 0.4 }
			b.ring:SetVertexColor(col[1], col[2], col[3])
			b.order:SetText(chosen[c.pick] and profile.badges and tostring(chosen[c.pick]) or "")
			b.tip = { h.title, h.sub }
			b:SetScript("OnClick", mine and function() togglePick(c.pick) end or nil)
		end
	end

	-- Cifras.
	local s = ns.Scores()[name] or { merits = 0, rep = 0 }
	local bg = ns.BGRecord(name)
	local medals = 0
	for _, md in ipairs(ns.MemberMedals(name)) do
		if md.tier > 0 then medals = medals + 1 end
	end
	f.stats:SetText(table.concat({
		(L["%s%d|r insignias  ·  %d de reputación  ·  %d/%d medallas"]):format(GOLD, s.merits or 0, s.rep or 0, medals, #ns.MEDALS),
		(L["Campos de batalla: %d victorias, %d derrotas"]):format(bg.wins, bg.losses),
		m.pvp and m.pvp.hk and (L["Muertes con honor (en total): %d"]):format(m.pvp.hk) or "",
		donatedText(name),
		bankText(name),
		ns.InWager(name, ns.Now()) and ("|cffff6b5a" .. L["Botín de guerra activado"] .. R) or "",
	}, "\n"))

	-- Botón de abajo.
	local canHide = not mine and ns.CanManageEvents(me) and g and g.members[name] ~= nil
	f.edit:SetShown(mine or canHide)
	for _, b in ipairs({ f.velvetPrev, f.velvetNext, f.framePrev, f.frameNext }) do b:SetShown(mine) end
	if mine then
		f.edit:SetText(L["Editar ficha"])
		f.edit:SetScript("OnClick", showEditDialog)
	elseif canHide then
		f.edit:SetText(profile.hidden and L["Mostrar texto"] or L["Ocultar texto"])
		f.edit:SetScript("OnClick", function() ns.SetProfileHidden(name, not profile.hidden) end)
	end
end
ns.RefreshProfile = render

local function place()
	panel:ClearAllPoints()
	local main = _G.LantuxGuildFrame
	if main and main:IsShown() then
		panel:SetPoint("TOPLEFT", main, "TOPRIGHT", 4, 0)
	else
		panel:SetPoint("CENTER")
	end
end

-- Abre el perfil de alguien (el tuyo si name es nil); si ya se ve ese, lo cierra.
function ns.ToggleProfile(name)
	name = name or ns.PlayerFullName()
	if not LG:GuildData() then
		LG:Print(L["No estás en una hermandad. Con /gmk prueba tu grupo cuenta como hermandad para probar el addon."])
		return
	end
	if not panel then create() end
	if panel:IsShown() and shown == name then
		panel:Hide()
		return
	end
	shown = name
	place()
	panel:Show()
	panel:Raise()
	render()
end

function ns.ProfileShown() return panel and panel:IsShown() and shown or nil end

ns.OnDataChanged(function() render() end)
