-- Perfil del jugador: estuche de medallas, ficha de rol e insignias del retrato.
--
-- Las medallas son personales (los logros son de la hermandad): cada una tiene
-- tres grados (bronce, plata y oro) y se calcula con los datos ya sincronizados,
-- así que cada addon ve las mismas medallas de cada miembro sin que viajen.
--
-- La ficha (título, papel, lema, historia y las insignias elegidas para el
-- retrato) va en el registro propio (ME), solo dentro de la hermandad. El texto
-- libre se limpia al leerlo, y un oficial puede ocultarlo (anulación
-- "profile|Nombre", Integrity.lua).
local _, ns = ...
local L = ns.L
local LG = ns.LG

local MOTTO_MAX, STORY_MAX = 60, 300

-- Arte propio de las medallas (Media/Medals/<clave>.tga, 128x128 con alfa): se
-- marca aquí cuando el archivo existe; sin él, el icono del juego en un círculo.
ns.MEDAL_ART = {}

ns.MEDAL_TIERS = {
	{ key = "bronze", label = L["bronce"], color = { 0.8, 0.5, 0.25 } },
	{ key = "silver", label = L["plata"], color = { 0.78, 0.8, 0.85 } },
	{ key = "gold", label = L["oro"], color = { 1, 0.82, 0.2 } },
}

-- tiers: cifras para bronce, plata y oro (una sola cifra = solo oro).
ns.MEDALS = {
	{ key = "hunter", label = L["Cazador"], icon = "Interface\\Icons\\Ability_DualWield", tiers = { 10, 50, 200 },
		desc = L["Muertes con honor registradas por el addon."], title = L["Cazador implacable"] },
	{ key = "avenger", label = L["Vengador"], icon = "Interface\\Icons\\Ability_Warrior_Revenge", tiers = { 3, 15, 50 },
		desc = L["Venganzas: matar a quien acaba de matar a un compañero."], title = L["Vengador de los suyos"] },
	{ key = "shield", label = L["Escudo de la facción"], icon = "Interface\\Icons\\Ability_Defend", tiers = { 1, 10, 30 },
		desc = L["Bajas ayudando en llamadas de auxilio y asaltos de otras hermandades."], title = L["Escudo de la facción"] },
	{ key = "assault", label = L["Asaltante"], icon = "Interface\\Icons\\INV_BannerPVP_01", tiers = { 1, 5, 15 },
		desc = L["Asaltos completados en los que participaste (con alguna baja en la ciudad)."], title = L["Asaltante de capitales"] },
	{ key = "regicide", label = L["Regicida"], icon = "Interface\\Icons\\INV_Crown_01", tiers = { 1 },
		desc = L["Estar en un asalto en el que cae el líder enemigo."], title = L["Regicida"] },
	{ key = "explorer", label = L["Explorador"], icon = "Interface\\Icons\\INV_Misc_Key_03", tiers = { 10, 50, 150 }, goldNeedsRaid = true,
		desc = L["Mazmorras con un grupo de hermandad. El oro pide además un jefe de banda con la hermandad."], title = L["Explorador de Azeroth"] },
	{ key = "artisan", label = L["Artesano"], icon = "Interface\\Icons\\Trade_BlackSmithing", tiers = { 5, 25, 100 },
		desc = L["Encargos entregados a la hermandad."], title = L["Maestro artesano"] },
	{ key = "companion", label = L["Compañero"], icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02", tiers = { 5, 25, 75 },
		desc = L["Eventos de la hermandad a los que asististe."], title = L["Alma de la hermandad"] },
}
local MEDAL = {}
for _, m in ipairs(ns.MEDALS) do MEDAL[m.key] = m end
function ns.Medal(key) return MEDAL[key] end

ns.PROFILE_ROLES = {
	{ key = "tank", label = L["Tanque"] }, { key = "healer", label = L["Sanador"] }, { key = "dps", label = L["Daño"] },
	{ key = "hunter", label = L["Cazador de cabezas"] }, { key = "crafter", label = L["Artesano"] },
	{ key = "gatherer", label = L["Recolector"] }, { key = "explorer", label = L["Explorador"] },
	{ key = "trader", label = L["Comerciante"] }, { key = "bard", label = L["Cronista"] },
}

---------------------------------------------------------------------------
-- Medallas
---------------------------------------------------------------------------

local cache, cacheScores

-- Contadores por miembro: { [nombre] = { hunter = n, ..., raid = true } }, en una pasada.
local function medalFacts()
	local scores = ns.Scores()
	if cache and cacheScores == scores then return cache end
	local g = LG:GuildData()
	local facts = {}
	cache, cacheScores = facts, scores
	if not g then return facts end
	local function f(name)
		local x = facts[name]
		if not x then
			x = { hunter = 0, avenger = 0, shield = 0, assault = 0, regicide = 0, explorer = 0, artisan = 0, companion = 0 }
			facts[name] = x
		end
		return x
	end
	-- Muertes con honor y venganzas.
	for _, k in pairs(g.kills) do
		if k.kind == "kill" and k.honorable and k.killerName and not ns.IsVoided(g, k.id) then
			local x = f(k.killerName)
			x.hunter = x.hunter + 1
			if k.revenge then x.avenger = x.avenger + 1 end
		end
	end
	-- Auxilio a otras hermandades.
	local myGuild = LG:GuildName()
	for _, h in pairs(g.aidHelps or {}) do
		if h.guild ~= myGuild and ns.AidHelpKills then
			local x = f(h.member)
			x.shield = x.shield + #ns.AidHelpKills(g, h)
		end
	end
	-- Asaltos completados y regicidios: quien tuvo alguna baja en la ciudad durante el asalto.
	for _, c in pairs(g.calls or {}) do
		if c.kind == "assault" and ns.AssaultCompleted and ns.AssaultCompleted(g, c) and ns.AssaultParticipants then
			local regicide = false
			for _, r in pairs(g.regicides or {}) do
				if r.call == c.id then regicide = r end
			end
			local who = ns.AssaultParticipants(g, c)
			if regicide and regicide.by then who[regicide.by] = true end
			for name in pairs(who) do
				local x = f(name)
				x.assault = x.assault + 1
				if regicide then x.regicide = x.regicide + 1 end
			end
		end
	end
	-- Mazmorras con la hermandad (como en los puntos: 4+ de la guild y 2+ testigos), una por día y mazmorra; bandas.
	local seen = {}
	for _, r in pairs(g.runs) do
		local witnesses = 0
		for _ in pairs(r.witnesses or {}) do witnesses = witnesses + 1 end
		if witnesses >= 2 then
			local raid = r.raid and r.size >= 10 and r.guildCount >= r.size * 0.8
			local dungeon = not r.raid and r.size == 5 and r.guildCount >= 4
			for _, member in ipairs(r.guildMembers or r.members or {}) do
				if raid then f(member).raid = true end
				if dungeon then
					local key = ("%s|%s|%d"):format(member, tostring(r.instanceID or r.instance), math.floor(r.t / 86400))
					if not seen[key] then
						seen[key] = true
						local x = f(member)
						x.explorer = x.explorer + 1
					end
				end
			end
		end
	end
	-- Encargos entregados (el artesano) y asistencia a eventos.
	for _, o in pairs(g.orders) do
		if o.status == "done" and o.crafter and not ns.IsVoided(g, o.id) then
			local x = f(o.crafter)
			x.artisan = x.artisan + 1
		end
	end
	for id, list in pairs(g.attendance) do
		local e = g.events[id]
		if e and e.status ~= "cancelled" then
			for member in pairs(list) do
				if not ns.IsVoided(g, ns.AttendanceVoidID(id, member)) then
					local x = f(member)
					x.companion = x.companion + 1
				end
			end
		end
	end
	return facts
end

-- Medallas de un miembro: lista en el orden del estuche con
-- { def, value, tier (0 = sin ella, 1-3), nextTarget, nextTier }.
function ns.MemberMedals(name)
	local x = medalFacts()[name] or {}
	local list = {}
	for _, def in ipairs(ns.MEDALS) do
		local value = x[def.key] or 0
		local tier, nextTarget, nextTier = 0, nil, nil
		local single = #def.tiers == 1
		for i, target in ipairs(def.tiers) do
			local t = single and 3 or i
			local ok = value >= target and not (t == 3 and def.goldNeedsRaid and not x.raid)
			if ok then
				tier = t
			elseif not nextTarget then
				nextTarget, nextTier = target, t
			end
		end
		list[#list + 1] = { def = def, value = value, tier = tier, nextTarget = nextTarget, nextTier = nextTier,
			needsRaid = def.goldNeedsRaid and not x.raid and value >= def.tiers[3] or nil }
	end
	return list
end

-- Grado de una medalla de un miembro (0 si no la tiene).
function ns.MedalTier(name, key)
	for _, m in ipairs(ns.MemberMedals(name)) do
		if m.def.key == key then return m.tier end
	end
	return 0
end

---------------------------------------------------------------------------
-- Ficha de rol
---------------------------------------------------------------------------

-- Texto libre seguro: sin códigos de escape (|), sin saltos de línea de más y con su límite.
local function clean(text, max)
	if type(text) ~= "string" then return nil end
	text = text:gsub("|", ""):gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil end
	return text:sub(1, max)
end
ns.CleanProfileText = clean

local function roleLabel(key)
	for _, r in ipairs(ns.PROFILE_ROLES) do
		if r.key == key then return r.label end
	end
	return nil
end
ns.ProfileRoleLabel = roleLabel

-- Títulos que puede llevar un miembro: el de cada medalla de oro, su rango y el título de la hermandad.
function ns.AvailableTitles(name)
	local list = {}
	local rank = ns.MeritRank(name)
	if rank and rank.key ~= "recruit" then list[#list + 1] = { key = "rank", label = rank.label } end
	local perks = ns.GuildPerks and ns.GuildPerks() or {}
	if perks.title then list[#list + 1] = { key = "guild", label = perks.title } end
	for _, m in ipairs(ns.MemberMedals(name)) do
		if m.tier == 3 then list[#list + 1] = { key = "medal:" .. m.def.key, label = m.def.title } end
	end
	return list
end

local function titleLabel(name, key)
	for _, t in ipairs(ns.AvailableTitles(name)) do
		if t.key == key then return t.label end
	end
	return nil
end

-- Ficha de un miembro, ya limpia y comprobada: { title, role, motto, story, hidden, badges }.
function ns.MemberProfile(name)
	local g = LG:GuildData()
	local raw = name == ns.PlayerFullName() and LG.db.char.profile or (g and g.members[name] and g.members[name].profile)
	raw = type(raw) == "table" and raw or {}
	local hidden = g and ns.IsVoided(g, "profile|" .. name)
	return {
		title = type(raw.title) == "string" and titleLabel(name, raw.title) or nil,
		titleKey = raw.title,
		role = type(raw.role) == "string" and roleLabel(raw.role) or nil,
		roleKey = raw.role,
		motto = not hidden and clean(raw.motto, MOTTO_MAX) or nil,
		story = not hidden and clean(raw.story, STORY_MAX) or nil,
		hidden = hidden or nil,
		badges = type(raw.badges) == "table" and raw.badges or nil,
		-- Cosméticos de la tienda (Shop.lua), solo si de verdad los compró.
		frame = type(raw.frame) == "string" and ns.Owns and ns.Owns(name, raw.frame) and ns.ShopItem(raw.frame) or nil,
		velvet = type(raw.velvet) == "string" and ns.Owns and ns.Owns(name, raw.velvet) and ns.ShopItem(raw.velvet) or nil,
	}
end

function ns.SaveProfile(fields)
	local p = LG.db.char.profile
	for _, k in ipairs({ "title", "role", "frame", "velvet" }) do
		if fields[k] ~= nil then p[k] = fields[k] ~= "" and fields[k] or nil end
	end
	if fields.motto ~= nil then p.motto = clean(fields.motto, MOTTO_MAX) end
	if fields.story ~= nil then p.story = clean(fields.story, STORY_MAX) end
	if fields.badges ~= nil then p.badges = fields.badges ~= false and fields.badges or nil end
	LG:MarkDirty()
end

-- Oficiales: ocultar o volver a mostrar el texto de la ficha de alguien.
function ns.SetProfileHidden(name, hidden)
	ns.SetVoided({ { id = "profile|" .. name, kind = "profile", member = name, label = L["Texto de la ficha"] } }, hidden)
end

-- La ficha viaja en el registro propio, solo con lo que se puede enseñar.
table.insert(ns.recordProviders, function(rec)
	local p = LG.db.char.profile or {}
	local badges
	if type(p.badges) == "table" then
		badges = {}
		for i = 1, math.min(#p.badges, 5) do
			if type(p.badges[i]) == "string" then badges[#badges + 1] = p.badges[i]:sub(1, 40) end
		end
	end
	if p.title or p.role or p.motto or p.story or badges or p.frame or p.velvet then
		rec.profile = { title = p.title, role = p.role, motto = clean(p.motto, MOTTO_MAX), story = clean(p.story, STORY_MAX), badges = badges,
			frame = p.frame, velvet = p.velvet }
	end
end)
