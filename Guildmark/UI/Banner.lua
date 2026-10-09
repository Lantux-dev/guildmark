-- Insignias encima del marco de jugador y del de objetivo.
--
-- Una fila de iconos sin fondo, después del retrato: el tabardo de la hermandad (solo con el
-- Estandarte activo, un proyecto del cofre), la tribu, los honores
-- conseguidos (solo los que impresionan, por orden de prestigio: proezas de
-- fuerza, título de hermandad, liga de guerra y trofeos de guerra destacados) y
-- la corona si eres el maestro de hermandad (el rango, en el tooltip del tabardo).
--
-- Va pegada a los marcos de Blizzard sin tocarlos. Las del objetivo salen si
-- tiene el addon: de tu hermandad con sus datos; de otra, preguntándole por la
-- red de hermandades (BDQ/BDA). Los honores viajan como claves, que cada addon
-- traduce a icono y texto: nadie puede colar otra cosa.
--
-- Arte: texturas del juego. Los dibujos propios irán en Media/ (ART).
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Banner = LG:NewModule("Banner", "AceEvent-3.0", "AceTimer-3.0")
ns.BannerModule = Banner -- para las pruebas

local GOLD = "|cffffd100"
local R = "|r"

local STRIP_W, STRIP_H = 190, 28
local BADGE = 22
local MAX_HONORS = 5
local CACHE_TTL = 10 * 60
local ASK_EVERY = 2

local ART = {
	ring = "Interface\\Minimap\\MiniMap-TrackingBorder",
	mask = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
	crown = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
}

local RANK_COLORS = {
	recruit = { 0.6, 0.6, 0.6 },
	member = { 0.3, 0.75, 0.3 },
	veteran = { 0.35, 0.6, 1 },
	elite = { 1, 0.75, 0.2 },
}

-- Trofeos de guerra que se lucen (los más difíciles primero).
local WAR_SHOWN = { "streak5", "giant", "wall", "crush", "streak3" }

local function setting(key, default)
	local b = LG.db and LG.db.profile.banner
	if not b or b[key] == nil then return default end
	return b[key]
end

---------------------------------------------------------------------------
-- Honores: claves que se traducen aquí a icono, color y texto
---------------------------------------------------------------------------

-- "feat:league:1:3", "feat:unbeaten:1", "title:3", "league:2", "war:giant"
local function resolveHonor(key)
	if type(key) ~= "string" then return nil end
	local season, tier = key:match("^feat:league:(%d+):(%d)$")
	if season then
		local league = ns.WAR_LEAGUES[tonumber(tier)]
		if not league then return nil end
		return { icon = tonumber(tier) >= 3 and "Interface\\Icons\\INV_Misc_Trophy_03" or "Interface\\Icons\\INV_Misc_Trophy_02",
			color = league.color, title = (L["Liga de %s en la temporada %d"]):format(league.label, tonumber(season)), sub = L["Proezas de fuerza"] }
	end
	season = key:match("^feat:unbeaten:(%d+)$")
	if season then
		return { icon = "Interface\\Icons\\INV_Shield_05", color = { 1, 0.82, 0.2 },
			title = (L["Invictos en la temporada %d"]):format(tonumber(season)), sub = L["Proezas de fuerza"] }
	end
	local n = key:match("^title:(%d)$")
	if n then
		local r = ns.ACH_REWARDS[tonumber(n)]
		return r and r.title and { icon = r.icon, title = r.title, sub = L["Logros de hermandad"] } or nil
	end
	tier = key:match("^league:(%d)$")
	if tier then
		local league = ns.WAR_LEAGUES[tonumber(tier)]
		return league and { icon = "Interface\\Icons\\INV_Shield_05", tint = league.color, color = league.color,
			title = (L["Liga de %s"]):format(league.label), sub = L["Guerras de esta temporada"] } or nil
	end
	-- Medalla del perfil (Profile.lua): "medal:cazador:3".
	local medal, mtier = key:match("^medal:(%a+):(%d)$")
	if medal then
		local def, tier = ns.Medal and ns.Medal(medal), ns.MEDAL_TIERS and ns.MEDAL_TIERS[tonumber(mtier)]
		return def and tier and { icon = def.icon, color = tier.color, keepColor = true,
			title = ("%s (%s)"):format(def.label, tier.label), sub = L["Medalla"] } or nil
	end
	if key == "elite" then
		return { icon = "Interface\\Icons\\Ability_Warrior_RallyingCry", color = { 1, 0.82, 0.2 }, title = L["Hermandad de élite"], sub = L["Nivel de hermandad 6 o más"] }
	end
	local fac, lvl = key:match("^pvp:([AH]):(%d+)$")
	if fac then
		local level = tonumber(lvl)
		if level < 1 or level > 14 then return nil end
		return { icon = ns.PvPRankIcon(level, fac == "A" and "Alliance" or "Horde"), title = (L["Rango JcJ %d"]):format(level), sub = L["Temporada JcJ"] }
	end
	local kind = key:match("^war:(%a+%d?)$")
	if kind then
		for _, sp in ipairs(ns.WAR_SPECIALS or {}) do
			if sp.kind == kind then return { icon = sp.icon, title = sp.title, sub = sp.desc } end
		end
	end
	return nil
end
ns.ResolveHonor = resolveHonor

-- Honores de mi hermandad (y míos), por orden de prestigio.
local function guildHonors()
	local keys = {}
	local record = ns.WarRecord()
	for _, f in ipairs(record.feats or {}) do
		if f.tier then keys[#keys + 1] = ("feat:league:%d:%d"):format(f.season, f.tier)
		elseif f.season then keys[#keys + 1] = ("feat:unbeaten:%d"):format(f.season) end
	end
	local points = ns.AchievementState().points
	local best
	for i, r in ipairs(ns.ACH_REWARDS) do
		if r.title and points >= r.points then best = i end
	end
	if best then keys[#keys + 1] = "title:" .. best end
	-- Liga y trofeos de guerra: no mientras las guerras estén en pausa.
	if not ns.WARS_PAUSED and record.wins + record.losses + record.draws > 0 then
		local league = ns.WarLeague(record.rating)
		for i, l in ipairs(ns.WAR_LEAGUES) do
			if l == league then keys[#keys + 1] = "league:" .. i end
		end
	end
	for _, kind in ipairs(ns.WARS_PAUSED and {} or WAR_SHOWN) do
		if record.specials[kind] then keys[#keys + 1] = "war:" .. kind end
	end
	while #keys > MAX_HONORS do table.remove(keys) end
	return keys
end

-- Insignias que puede llevar alguien junto al retrato: las automáticas (rango JcJ,
-- élite y honores de la hermandad) y sus medallas. Las medallas se eligen por su
-- clave ("medal:cazador") y salen con el grado que tengan en ese momento.
local function medalKeys(name)
	local list = {}
	for _, m in ipairs(ns.MemberMedals and ns.MemberMedals(name) or {}) do
		if m.tier > 0 then list[#list + 1] = { pick = "medal:" .. m.def.key, key = ("medal:%s:%d"):format(m.def.key, m.tier) } end
	end
	return list
end

function ns.BadgeCandidates(name)
	local list = {}
	local data = ns.BadgeData(name, true)
	for _, key in ipairs(data and data.auto or {}) do list[#list + 1] = { pick = key, key = key } end
	for _, m in ipairs(medalKeys(name)) do list[#list + 1] = m end
	return list
end

-- Las elegidas en la ficha (si las hay), comprobadas contra lo que de verdad tiene.
local function chosenHonors(name, auto)
	local profile = ns.MemberProfile and ns.MemberProfile(name)
	if not profile or not profile.badges then return nil end
	local valid = {}
	for _, key in ipairs(auto) do valid[key] = key end
	for _, m in ipairs(medalKeys(name)) do valid[m.pick] = m.key end
	local list = {}
	for _, pick in ipairs(profile.badges) do
		if valid[pick] and #list < MAX_HONORS then
			list[#list + 1] = valid[pick]
			valid[pick] = nil
		end
	end
	return list
end

-- Insignias de alguien de mi hermandad (o las mías).
function ns.BadgeData(name, rawAuto)
	local guild = LG:GuildName()
	if not LG:GuildData() or not guild then return nil end
	local rank = ns.MeritRank(name)
	local r = ns.roster[name]
	-- Su rango JcJ va delante de los honores de la hermandad (es lo único personal).
	local honors = guildHonors()
	local perks = ns.GuildPerks and ns.GuildPerks() or {}
	if perks.elite then table.insert(honors, 1, "elite") end
	local pr = ns.MemberPvPRank and ns.MemberPvPRank(name)
	if pr and pr.level >= 1 then
		table.insert(honors, 1, ("pvp:%s:%d"):format(UnitFactionGroup and UnitFactionGroup("player") == "Alliance" and "A" or "H", pr.level))
		while #honors > MAX_HONORS do table.remove(honors) end
	end
	local auto = honors
	if not rawAuto then honors = chosenHonors(name, auto) or auto end
	return {
		auto = auto,
		guild = guild, faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
		honors = honors,
		level = perks.level,
		tribe = ns.TribeOf and ns.TribeOf(name) and ns.TribeOf(name).name or nil,
		tribeIcon = ns.TribeOf and ns.TribeOf(name) and ns.TribeIcon(ns.TribeOf(name)) or nil,
		rank = rank and rank.key, rankLabel = rank and rank.label,
		standard = (ns.ActiveProjects and ns.ActiveProjects().standard) and true or nil, -- emblema solo con el Estandarte
		gm = (r and r.rankIndex == 0) or (LG:InTestMode() and name == ns.PlayerFullName()) or nil,
	}
end

---------------------------------------------------------------------------
-- Insignias de otras hermandades, por la red
---------------------------------------------------------------------------

local remote = {} -- [nombre] = { t, data }
local lastAsk = 0

ns.netHandlers.BDQ = function(_, d)
	if d.name ~= ns.PlayerFullName() or not setting("share", true) then return end
	local data = ns.BadgeData(ns.PlayerFullName())
	if data then
		data.name = ns.PlayerFullName()
		data.auto = nil -- solo para el selector del perfil
		ns.NetSend("BDA", data)
	end
end

ns.netHandlers.BDA = function(sender, d)
	if d.name ~= sender or type(d.guild) ~= "string" then return end
	local honors = {}
	for _, key in ipairs(type(d.honors) == "table" and d.honors or {}) do
		if #honors >= MAX_HONORS then break end
		if resolveHonor(key) then honors[#honors + 1] = key end
	end
	remote[sender] = { t = GetTime(), data = {
		guild = d.guild:sub(1, 48), faction = (d.faction == "Horde" or d.faction == "Alliance") and d.faction or nil,
		honors = honors, rank = RANK_COLORS[d.rank] and d.rank or nil,
		tribe = type(d.tribe) == "string" and d.tribe:gsub("|", ""):sub(1, 24) or nil,
		tribeIcon = ns.ValidTribeIcon and ns.ValidTribeIcon(d.tribeIcon) and d.tribeIcon or nil,
		level = tonumber(d.level) and math.max(1, math.min(10, math.floor(tonumber(d.level)))) or nil,
		rankLabel = type(d.rankLabel) == "string" and d.rankLabel:sub(1, 24) or nil, gm = d.gm and true or nil,
		standard = d.standard and true or nil,
	} }
	if Banner.targetName == sender then Banner:UpdateTarget() end
end

local function unitBadges(unit)
	if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
	local name = ns.UnitFullName(unit)
	if not name then return nil end
	if UnitIsUnit(unit, "player") then return ns.BadgeData(name) end
	local g = LG:GuildData()
	if g and g.members[name] and ns.IsGuildUnit(unit) then return ns.BadgeData(name) end
	local cached = remote[name]
	if cached and GetTime() - cached.t < CACHE_TTL then return cached.data end
	if GetTime() - lastAsk >= ASK_EVERY and UnitIsFriend("player", unit) then
		lastAsk = GetTime()
		ns.NetSend("BDQ", { name = name })
	end
	return nil
end

---------------------------------------------------------------------------
-- Dibujo
---------------------------------------------------------------------------

local function hasAtlas(name) return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil end

local function tooltip(self)
	if not self.tip then return end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	for i, text in ipairs(self.tip) do
		if i == 1 then GameTooltip:SetText(text) else GameTooltip:AddLine(text, 1, 1, 1, true) end
	end
	GameTooltip:Show()
end

local function badgeButton(parent)
	local b = CreateFrame("Frame", nil, parent)
	b:SetSize(BADGE, BADGE)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(BADGE - 6, BADGE - 6)
	b.icon:SetPoint("CENTER")
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	-- Icono redondo (máscara circular), si el cliente lo permite.
	b.mask = b.CreateMaskTexture and b:CreateMaskTexture() or nil
	if b.mask and b.icon.AddMaskTexture then
		b.mask:SetTexture(ART.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		b.mask:SetAllPoints(b.icon)
		b.icon:AddMaskTexture(b.mask)
	end
	b.ring = b:CreateTexture(nil, "OVERLAY")
	b.ring:SetTexture(ART.ring)
	b.ring:SetSize(BADGE * 1.7, BADGE * 1.7)
	b.ring:SetPoint("TOPLEFT", -1, 1)
	b:EnableMouse(true)
	b:SetScript("OnEnter", tooltip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local STEP = BADGE + 3

local function createStrip(name, rightToLeft)
	-- Sin fondo: solo los iconos, para no tapar nada de lo que hay detrás.
	local f = CreateFrame("Frame", name, UIParent)
	f:SetSize(STRIP_W, STRIP_H)
	f:SetFrameStrata("LOW")
	f.rightToLeft = rightToLeft

	-- Tabardo (o estandarte de la facción), con la hermandad y tu rango al pasar el ratón.
	f.tabard = CreateFrame("Frame", nil, f)
	f.tabard:SetSize(BADGE, BADGE + 2)
	f.tabard:EnableMouse(true)
	f.tabard:SetScript("OnEnter", tooltip)
	f.tabard:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.tabardBg = f.tabard:CreateTexture(nil, "BORDER")
	f.tabardBg:SetAllPoints()
	f.tabardBg:SetTexture("Interface\\GuildFrame\\GuildFrame")
	f.tabardBg:SetTexCoord(0.63183594, 0.69238281, 0.61914063, 0.74023438)
	f.tabardBorder = f.tabard:CreateTexture(nil, "OVERLAY")
	f.tabardBorder:SetAllPoints()
	f.tabardBorder:SetTexture("Interface\\GuildFrame\\GuildFrame")
	f.tabardBorder:SetTexCoord(0.63183594, 0.69238281, 0.74414063, 0.86523438)
	f.tabardEmblem = f.tabard:CreateTexture(nil, "ARTWORK")
	f.tabardEmblem:SetPoint("CENTER")

	f.badges = {}
	for i = 1, MAX_HONORS do f.badges[i] = badgeButton(f) end
	-- Tribu (va justo después del tabardo).
	f.tribeBadge = badgeButton(f)

	-- Corona de líder (solo para el maestro de hermandad).
	f.crownFrame = CreateFrame("Frame", nil, f)
	f.crownFrame:SetSize(BADGE, BADGE)
	f.crownFrame:EnableMouse(true)
	f.crownFrame:SetScript("OnEnter", tooltip)
	f.crownFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.crown = f.crownFrame:CreateTexture(nil, "ARTWORK")
	f.crown:SetAllPoints()
	f.crown:SetTexture(ART.crown)
	f:Hide()
	return f
end

local function paintTabard(f, unit, data)
	local mine = unit == "player" or (data and data.guild == LG:GuildName() and not LG:InTestMode())
	if mine and IsInGuild() and SetLargeGuildTabardTextures then
		local info
		if C_GuildInfo and C_GuildInfo.GetGuildTabardInfo then
			local ok, d = pcall(C_GuildInfo.GetGuildTabardInfo, "player")
			info = ok and d or nil
		end
		f.tabardEmblem:SetSize(BADGE * 0.8, BADGE + 2)
		if pcall(SetLargeGuildTabardTextures, "player", f.tabardEmblem, f.tabardBg, f.tabardBorder, info) then
			f.tabardBg:Show(); f.tabardBorder:Show()
			return
		end
	end
	f.tabardBg:Hide(); f.tabardBorder:Hide()
	f.tabardEmblem:SetSize(BADGE, BADGE)
	f.tabardEmblem:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.tabardEmblem:SetVertexColor(1, 1, 1, 1)
	f.tabardEmblem:SetTexture(ns.FactionBanner and ns.FactionBanner(data and data.faction) or "Interface\\Icons\\INV_BannerPVP_01")
end

local function fill(f, unit, data)
	-- El emblema de la hermandad solo sale con el Estandarte activo (proyecto del cofre, Chest.lua).
	local items = {}
	f.tabard:SetShown(data.standard and true or false)
	if data.standard then
		paintTabard(f, unit, data)
		f.tabard.tip = { "<" .. data.guild .. ">", data.rankLabel and ((L["Rango en la hermandad: %s"]):format(data.rankLabel)) or nil,
			GOLD .. L["Estandarte de hermandad"] .. R }
		items[1] = f.tabard
	end

	-- En fila: emblema, tribu, honores y corona (en el objetivo, de derecha a izquierda).
	f.tribeBadge:SetShown(data.tribe ~= nil)
	if data.tribe then
		local tex, custom = ns.TribeIconTexture(data.tribeIcon)
		local b = f.tribeBadge
		b.icon:SetTexture(tex)
		b.icon:SetVertexColor(1, 1, 1)
		b.ring:SetVertexColor(1, 0.85, 0.4)
		-- Los iconos propios traen su marco: sin aro, sin recorte redondo y algo más grandes.
		b.ring:SetShown(not custom)
		b.icon:SetTexCoord(custom and 0 or 0.07, custom and 1 or 0.93, custom and 0 or 0.07, custom and 1 or 0.93)
		b.icon:SetSize(custom and BADGE + 2 or BADGE - 6, custom and BADGE + 2 or BADGE - 6)
		if b.mask and b.icon.RemoveMaskTexture and b.icon.AddMaskTexture then
			if custom and not b.unmasked then
				b.icon:RemoveMaskTexture(b.mask)
				b.unmasked = true
			elseif not custom and b.unmasked then
				b.icon:AddMaskTexture(b.mask)
				b.unmasked = nil
			end
		end
		f.tribeBadge.tip = { ("%s «%s»"):format(ns.TribeWords().One, data.tribe) }
		items[#items + 1] = f.tribeBadge
	end
	for i, b in ipairs(f.badges) do
		local h = resolveHonor(data.honors and data.honors[i])
		b:SetShown(h ~= nil)
		if h then
			b.icon:SetTexture(h.icon)
			local t = h.tint
			b.icon:SetVertexColor(t and t[1] or 1, t and t[2] or 1, t and t[3] or 1)
			local c = h.color
			if (data.level or 0) >= 4 and not h.keepColor then c = { 1, 0.82, 0.15 } end -- nivel 4: borde dorado (las medallas, su metal)
			b.ring:SetVertexColor(c and c[1] or 1, c and c[2] or 0.85, c and c[3] or 0.4)
			b.tip = { h.title, h.sub }
			items[#items + 1] = b
		end
	end
	f.crownFrame:SetShown(data.gm and true or false)
	if data.gm then
		f.crownFrame.tip = { GOLD .. L["Líder de la hermandad"] .. R }
		items[#items + 1] = f.crownFrame
	end
	for i, item in ipairs(items) do
		item:ClearAllPoints()
		if f.rightToLeft then
			item:SetPoint("RIGHT", f, "RIGHT", -(i - 1) * STEP, 0)
		else
			item:SetPoint("LEFT", f, "LEFT", (i - 1) * STEP, 0)
		end
	end
	f:SetWidth(#items * STEP)
	f:Show()
end

---------------------------------------------------------------------------
-- Colocación y actualización
---------------------------------------------------------------------------

local playerStrip, targetStrip

-- Encima de la barra del nombre, empezando después del retrato (no lo tapa).
local function place()
	if PlayerFrame and playerStrip then
		playerStrip:ClearAllPoints()
		playerStrip:SetPoint("BOTTOMLEFT", PlayerFrame, "TOPLEFT", 72, -24)
	end
	if TargetFrame and targetStrip then
		targetStrip:ClearAllPoints()
		targetStrip:SetPoint("BOTTOMRIGHT", TargetFrame, "TOPRIGHT", -72, -24)
	end
end

function Banner:UpdatePlayer()
	if not playerStrip then return end
	local data = setting("player", true) and LG:HasConsent() and ns.BadgeData(ns.PlayerFullName())
	if data and PlayerFrame and PlayerFrame:IsShown() then fill(playerStrip, "player", data) else playerStrip:Hide() end
end

function Banner:UpdateTarget()
	if not targetStrip then return end
	self.targetName = UnitExists("target") and ns.UnitFullName("target") or nil
	local data = setting("target", true) and LG:HasConsent() and unitBadges("target")
	if data and TargetFrame and TargetFrame:IsShown() then fill(targetStrip, "target", data) else targetStrip:Hide() end
end

-- Ajustes (pestaña Ajustes): "player", "target" o "share".
function ns.BannerSetting(key) return setting(key, true) end
function ns.SetBannerSetting(key, value)
	LG.db.profile.banner[key] = value and true or false
	Banner:UpdatePlayer()
	Banner:UpdateTarget()
end

function ns.ToggleBanner()
	local b = LG.db.profile.banner
	local on = not setting("player", true)
	b.player, b.target = on, on
	LG:Print(on and L["Insignias sobre el marco: activadas."] or L["Insignias sobre el marco: desactivadas."])
	Banner:UpdatePlayer()
	Banner:UpdateTarget()
end

function Banner:OnEnable()
	playerStrip = createStrip("LantuxGuildPlayerBanner")
	targetStrip = createStrip("LantuxGuildTargetBanner", true)
	place()
	ns.RegisterEvent(self, "PLAYER_TARGET_CHANGED", "UpdateTarget")
	ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
		place()
		self:UpdatePlayer()
	end)
	ns.OnDataChanged(function()
		self:UpdatePlayer()
		if UnitExists("target") then self:UpdateTarget() end
	end)
	if EventRegistry and EventRegistry.RegisterCallback then
		pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", function() place() end, self)
	end
	self:ScheduleTimer("UpdatePlayer", 5)
end
