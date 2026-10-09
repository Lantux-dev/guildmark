-- Guerras de hermandad: un maestro de hermandad declara la guerra a otra
-- hermandad con el addon, en una zona, a una hora y durante un tiempo; el
-- maestro de la otra la acepta o la rechaza.
--
-- Puntuación: cada bando registra sus PROPIAS muertes con el informe de muerte
-- del juego y se las cuenta al otro por la red (TICK). Los puntos de un bando
-- son las muertes que reconoce el rival, más sus kills sobre rivales que no
-- tienen el addon (esas no las puede confirmar nadie). Así nadie puede inflar
-- su marcador con muertes inventadas del rival.
--
-- Si el canal de la red no llega a la otra facción, todo se puede pasar con
-- códigos para copiar y pegar (declaración, respuesta y resultado).
--
-- La clasificación (tipo Elo) y la vitrina de trofeos se calculan en cada
-- cliente a partir de las guerras terminadas, como los puntos de Merits.lua.
--
-- Mensajes:
--   WAR     (hermandad y red) la guerra con su estado; cada cambio sube "rev"
--   WARREP  (hermandad) marcador del rival pegado con un código por un oficial
--   TICK    (red) marcador de un bando: sus muertes, su puntuación, quién está
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Wars = LG:NewModule("Wars", "AceEvent-3.0", "AceTimer-3.0")

local TICK_EVERY = 30
local RESULT_GRACE = 300     -- tras el final se siguen mandando y aceptando marcadores 5 min
local MIN_DURATION, MAX_DURATION = 15 * 60, 4 * 3600
local REMIND_BEFORE = 15 * 60
local SAME_KILL_WINDOW = 15  -- varias kills de la misma víctima en 15 s son la misma muerte
local START_RATING = 1000
local K_FACTOR = 32

-- Escudo de cada liga: por defecto el escudo de legado teñido de su color. Para
-- un diseño propio, poner art = ns.MEDIA .. "league_bronze" (TGA 128x128 con
-- transparencia en Media/) y se usará tal cual.
ns.WAR_LEAGUES = {
	{ min = 0, label = L["Bronce"], color = { 0.8, 0.5, 0.25 } },
	{ min = 1100, label = L["Plata"], color = { 0.75, 0.78, 0.85 } },
	{ min = 1250, label = L["Oro"], color = { 1, 0.82, 0.2 } },
}

function ns.WarLeague(rating)
	local league = ns.WAR_LEAGUES[1]
	for _, l in ipairs(ns.WAR_LEAGUES) do
		if (rating or START_RATING) >= l.min then league = l end
	end
	return league
end

function ns.FactionBanner(faction)
	if faction == "Alliance" then return "Interface\\Icons\\INV_BannerPVP_02" end
	if faction == "Horde" then return "Interface\\Icons\\INV_BannerPVP_01" end
	return "Interface\\Icons\\INV_Misc_QuestionMark"
end

function ns.FactionName(faction)
	if faction == "Alliance" then return FACTION_ALLIANCE or L["Alianza"] end
	if faction == "Horde" then return FACTION_HORDE or L["Horda"] end
	return "?"
end

function ns.IsGuildMaster(name)
	return ns.RankIndexOf(name) == 0
end

local function myFaction() return UnitFactionGroup and UnitFactionGroup("player") or nil end
local function opposite(faction) return faction == "Horde" and "Alliance" or (faction == "Alliance" and "Horde" or nil) end

function ns.CurrentMap()
	if C_Map and C_Map.GetBestMapForUnit then
		local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
		if ok then return map end
	end
	return nil
end

-- Nombre de la zona en el idioma de este cliente (los dos bandos pueden tener idiomas distintos).
function ns.MapName(map, fallback)
	if map and C_Map and C_Map.GetMapInfo then
		local ok, info = pcall(C_Map.GetMapInfo, map)
		if ok and info and info.name then return info.name end
	end
	return fallback or "?"
end

function ns.WarEnemy(w, guild)
	guild = guild or LG:GuildName()
	return w.from == guild and w.to or w.from
end

function ns.WarEnemyFaction(w, guild)
	guild = guild or LG:GuildName()
	return w.from == guild and w.toFaction or w.fromFaction
end

-- pending | expired | declined | cancelled | upcoming | active | finished
function ns.WarPhase(w, now)
	now = now or ns.Now()
	if w.status == "pending" then return now > w.start + w.duration and "expired" or "pending" end
	if w.status ~= "accepted" then return w.status end
	if now < w.start then return "upcoming" end
	if now <= w.start + w.duration then return "active" end
	return "finished"
end

---------------------------------------------------------------------------
-- Fusión
---------------------------------------------------------------------------

-- Quién puede dejar la guerra en cada estado: el que declara o el declarado.
local STATUS_SIDE = { pending = "from", accepted = "to", declined = "to", cancelled = "any" }
local FIXED = { "from", "to", "start", "duration", "map" }

-- via: "net" (canal), "relay" (reenviado desde la otra facción por Battle.net),
--      "guild" (hermandad o sincronización), "code" (pegado), nil (yo mismo)
function ns.MergeWar(g, guild, rec, sender, via)
	if type(rec) ~= "table" or type(rec.id) ~= "string" or type(rec.rev) ~= "number" then return false end
	if type(rec.from) ~= "string" or type(rec.to) ~= "string" or rec.from == rec.to then return false end
	if rec.from ~= guild and rec.to ~= guild then return false end
	if type(rec.start) ~= "number" or type(rec.duration) ~= "number" then return false end
	if rec.duration < MIN_DURATION or rec.duration > MAX_DURATION then return false end
	local side = STATUS_SIDE[rec.status]
	if not side or (rec.side ~= rec.from and rec.side ~= rec.to) then return false end
	if side ~= "any" and rec.side ~= rec[side] then return false end

	if rec.side == guild then
		-- Lo que hace mi hermandad solo lo decide su maestro, y no puede venir en un código.
		if via == "code" or via == "relay" or not ns.IsGuildMaster(rec.by) then return false end
		if via == "net" and sender ~= rec.by then return false end
	elseif via == "net" and (sender ~= rec.by or ns.roster[sender]) then
		-- Lo del otro bando lo firma quien lo envía, y no puede ser de mi hermandad.
		return false
	elseif via == "relay" and ns.roster[sender] then
		-- Reenviado: el autor original no puede ser de mi hermandad.
		return false
	end

	local old = g.wars[rec.id]
	if old then
		if old.rev >= rec.rev then return false end
		for _, key in ipairs(FIXED) do
			if old[key] ~= rec[key] then return false end
		end
		-- Aceptar y rechazar es definitivo; cancelar, solo antes de empezar.
		if old.status ~= "pending" and rec.status ~= "cancelled" then return false end
		if old.status == "declined" or old.status == "cancelled" then return false end
		if rec.status == "cancelled" and ns.Now() >= old.start then return false end
	end
	local w = old or {}
	for _, key in ipairs({ "id", "from", "fromFaction", "to", "toFaction", "map", "zone", "start", "duration", "status", "rev", "by", "side", "t", "season" }) do
		w[key] = rec[key]
	end
	if type(rec.ratingFrom) == "number" then w.ratingFrom = rec.ratingFrom end
	if type(rec.ratingTo) == "number" then w.ratingTo = rec.ratingTo end
	w.test = w.test or rec.test
	g.wars[rec.id] = w
	return true, old
end

-- Marcador del rival (TICK). Solo el del otro bando y siempre el más reciente.
function ns.MergeWarReport(g, guild, rep, sender, via)
	local w = type(rep) == "table" and type(rep.id) == "string" and g.wars[rep.id]
	if not w or rep.guild ~= ns.WarEnemy(w, guild) then return false end
	if (via == "net" or via == "relay") and ns.roster[sender] then return false end
	if type(rep.t) ~= "number" or (w.report and (w.report.t or 0) >= rep.t) then return false end
	local names = {}
	for i, name in ipairs(type(rep.addon) == "table" and rep.addon or {}) do
		if i > 100 then break end
		if type(name) == "string" then names[#names + 1] = name:sub(1, 60) end
	end
	w.report = {
		t = rep.t,
		deaths = math.max(0, math.floor(tonumber(rep.deaths) or 0)),
		score = math.max(0, math.floor(tonumber(rep.score) or 0)),
		present = math.max(0, math.floor(tonumber(rep.present) or 0)),
		addon = names,
		final = rep.final and true or nil,
	}
	return true
end

local function notify(w, old)
	local guild = LG:GuildName()
	local enemy = ns.WarEnemy(w, guild)
	local when = date("%d/%m %H:%M", w.start)
	local zone = ns.MapName(w.map, w.zone)
	if not old and w.status == "pending" and w.to == guild then
		LG:Print((L["|cffff6b5a<%s> os declara la guerra|r: %s, %s, %d min. Decide vuestro maestro de hermandad en /gmk > JcJ > Guerras."]):format(
			enemy, zone, when, math.floor(w.duration / 60)))
		if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
	elseif w.status == "accepted" and (not old or old.status ~= "accepted") then
		LG:Print((L["Guerra confirmada contra <%s>: %s, %s."]):format(enemy, zone, when))
	elseif w.status == "declined" and old and old.status ~= "declined" then
		LG:Print((L["<%s> ha rechazado la guerra."]):format(enemy))
	elseif w.status == "cancelled" and old and old.status ~= "cancelled" then
		LG:Print((L["Guerra contra <%s> cancelada."]):format(enemy))
	end
end

local function handleWar(defaultVia)
	return function(sender, rec, via)
		via = via or defaultVia
		local g = LG:GuildData()
		local guild = LG:GuildName()
		if not g or not guild then return end
		local changed, old = ns.MergeWar(g, guild, rec, sender, via)
		if changed then
			notify(g.wars[rec.id], old)
			LG:DataChanged()
		end
		if type(rec.report) == "table" and ns.MergeWarReport(g, guild, rec.report, sender, via) then LG:DataChanged() end
	end
end

ns.handlers.WAR = handleWar("guild")
ns.netHandlers.WAR = handleWar("net")

local heardTick = {} -- [idGuerra] = GetTime() del último marcador de mi hermandad

ns.netHandlers.TICK = function(sender, rep, via)
	local g = LG:GuildData()
	local guild = LG:GuildName()
	if not g or not guild or type(rep.id) ~= "string" then return end
	if rep.guild == guild then
		heardTick[rep.id] = GetTime()
		return
	end
	if ns.MergeWarReport(g, guild, rep, sender, via or "net") then LG:DataChanged() end
end

-- Marcador del rival pegado con un código por un oficial y reenviado a la hermandad.
ns.handlers.WARREP = function(sender, rep)
	local g = LG:GuildData()
	if not g or not ns.CanManageEvents(sender) then return end
	if ns.MergeWarReport(g, LG:GuildName(), rep, sender, "guild") then LG:DataChanged() end
end

---------------------------------------------------------------------------
-- Marcador y estadísticas
---------------------------------------------------------------------------

local function inWar(w, k, zoneName)
	if k.t < w.start or k.t > w.start + w.duration then return false end
	if k.map and w.map then return k.map == w.map end
	return k.zone ~= nil and (k.zone == zoneName or k.zone == w.zone)
end

-- Kills y muertes de la guerra desde el punto de vista de mi hermandad.
--   kills   créditos de kill de los nuestros (varios por muerte si iban en grupo)
--   unique  muertes distintas de rivales
--   deaths  muertes nuestras a manos del rival
function ns.WarScore(w)
	local g = LG:GuildData()
	local guild = LG:GuildName()
	local s = { kills = {}, unique = {}, deaths = {}, ours = 0, theirs = 0, confirmed = false }
	if not g or not guild then return s end
	local enemy = ns.WarEnemy(w, guild)
	local zoneName = ns.MapName(w.map, w.zone)
	-- Guerra en la red de pruebas: el rival juega con su hermandad real, así que
	-- cuenta cualquier jugador enemigo en la zona y la hora de la guerra.
	local anyone = LG:InTestMode() and ns.IsTestGuild(enemy)
	for _, k in pairs(g.kills) do
		if (k.guild == enemy or anyone) and not k.bg and inWar(w, k, zoneName) and not ns.IsVoided(g, k.id) then
			if k.kind == "kill" then s.kills[#s.kills + 1] = k
			elseif k.kind == "death" then s.deaths[#s.deaths + 1] = k end
		end
	end
	local byTime = function(a, b) return a.t < b.t end
	table.sort(s.kills, byTime)
	table.sort(s.deaths, byTime)
	local last = {}
	for _, k in ipairs(s.kills) do
		local who = k.victim or k.victimName or "?"
		if not last[who] or k.t - last[who] > SAME_KILL_WINDOW then s.unique[#s.unique + 1] = k end
		last[who] = k.t
	end

	local rep = w.report
	if rep then
		local withAddon = {}
		for _, name in ipairs(rep.addon or {}) do withAddon[name] = true end
		local unverifiable = 0
		for _, k in ipairs(s.unique) do
			if not withAddon[k.victimName or ""] then unverifiable = unverifiable + 1 end
		end
		s.ours = (rep.deaths or 0) + unverifiable
		s.theirs = math.max(rep.score or 0, #s.deaths)
		s.confirmed = true
	else
		s.ours = #s.unique
		s.theirs = #s.deaths
	end
	return s
end

-- Miembros con el addon que han estado en la guerra (vistos en la zona o con kills/muertes).
local function participants(g, w, s)
	local list = {}
	for name in pairs(g.warSeen[w.id] or {}) do list[name] = true end
	for _, k in ipairs(s.kills) do list[k.killerName or "?"] = true end
	for _, k in ipairs(s.deaths) do list[k.victimName or "?"] = true end
	return list
end

function ns.WarStats(w)
	local g = LG:GuildData()
	local s = ns.WarScore(w)
	local st = { score = s, players = {} }
	if not g then return st end
	local per = {}
	local function P(name)
		per[name] = per[name] or { name = name, kills = 0, deaths = 0, streak = 0, best = 0, revenges = 0 }
		return per[name]
	end
	for name in pairs(participants(g, w, s)) do P(name) end
	local events = {}
	for _, k in ipairs(s.kills) do events[#events + 1] = k end
	for _, k in ipairs(s.deaths) do events[#events + 1] = k end
	table.sort(events, function(a, b) return a.t < b.t end)
	local theirKillers = {}
	for _, k in ipairs(events) do
		if k.kind == "kill" then
			local p = P(k.killerName or "?")
			p.kills = p.kills + 1
			p.streak = p.streak + 1
			p.best = math.max(p.best, p.streak)
			if k.revenge then p.revenges = p.revenges + 1 end
		else
			local p = P(k.victimName or "?")
			p.deaths = p.deaths + 1
			p.streak = 0
			theirKillers[k.killerName or "?"] = (theirKillers[k.killerName or "?"] or 0) + 1
		end
	end
	local first = events[1]
	if first then
		st.firstBlood = first.kind == "kill" and { ours = true, name = first.killerName, victim = first.victimName }
			or { ours = false, name = first.killerName, victim = first.victimName }
	end
	for _, p in pairs(per) do
		st.players[#st.players + 1] = p
		if p.kills > 0 and (not st.topKiller or p.kills > st.topKiller.kills
			or (p.kills == st.topKiller.kills and p.deaths < st.topKiller.deaths)) then st.topKiller = p end
		if p.deaths == 0 and (not st.unbeaten or p.kills > st.unbeaten.kills) then st.unbeaten = p end
		if p.best >= 2 and (not st.streak or p.best > st.streak.best) then st.streak = p end
	end
	table.sort(st.players, function(a, b) return a.kills > b.kills end)
	for name, n in pairs(theirKillers) do
		if not st.theirTop or n > st.theirTop.kills then st.theirTop = { name = name, kills = n } end
	end
	return st
end

-- Cuántos de los nuestros están ahora en la zona de la guerra (según el roster).
function ns.WarPresence(w)
	local zoneName = ns.MapName(w.map, w.zone)
	local n, names = 0, {}
	for name, r in pairs(ns.roster) do
		if r.online and (r.zone == zoneName or r.zone == w.zone) then
			n = n + 1
			names[#names + 1] = name
		end
	end
	return n, names
end

---------------------------------------------------------------------------
-- Clasificación por temporadas, desafíos de guerra y proezas de fuerza
--
-- La clasificación se reinicia con cada temporada JcJ de Forever. Los trofeos
-- especiales (primera victoria, rachas...) son desafíos de hermandad de la
-- categoría "Guerras". Lo logrado en temporadas pasadas queda como "Proezas
-- de fuerza": permanentes y sin puntos, como en retail.
---------------------------------------------------------------------------

-- Temporada JcJ actual del juego (1 si no se sabe).
function ns.PvPSeason()
	local ok, season = pcall(GetCurrentArenaSeason)
	if ok and type(season) == "number" and season > 0 then return season end
	return 1
end

local function warSeason(w)
	return w.season or ns.PvPSeason() -- las guerras de antes de las temporadas cuentan en la actual
end

local function guildMasterName()
	for name, r in pairs(ns.roster) do
		if r.rankIndex == 0 then return name end
	end
	return nil
end

-- Trofeos especiales: la primera vez que se consiguió cada uno.
ns.WAR_SPECIALS = {
	{ kind = "first", title = L["Primera victoria"], desc = L["Ganad vuestra primera guerra."], icon = "Interface\\Icons\\INV_Sword_04" },
	{ kind = "streak3", title = L["Tres victorias seguidas"], desc = L["Ganad tres guerras seguidas."], icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
	{ kind = "streak5", title = L["Cinco victorias seguidas"], desc = L["Ganad cinco guerras seguidas."], icon = "Interface\\Icons\\Ability_Warrior_InnerRage" },
	{ kind = "giant", title = L["Matagigantes"], desc = L["Ganad a una hermandad con 100 puntos de guerra más que vosotros."], icon = "Interface\\Icons\\Ability_Warrior_Decisivestrike" },
	{ kind = "crush", title = L["Victoria aplastante"], desc = L["Ganad una guerra con al menos 10 bajas y el doble que el rival."], icon = "Interface\\Icons\\Ability_Warrior_Rampage" },
	{ kind = "wall", title = L["Muro infranqueable"], desc = L["Victoria sin que caiga el maestro de hermandad"], icon = "Interface\\Icons\\INV_Shield_06" },
}

local function emptySeason(season)
	return { season = season, rating = START_RATING, wins = 0, losses = 0, draws = 0, history = {} }
end

-- Historial de guerras terminadas por temporada, trofeos especiales y proezas.
-- Devuelve la temporada pedida (la actual por defecto) con:
--   rating, wins, losses, draws, history, season
--   specials = { [kind] = { t, sub } }, feats = { { key, title, desc, t, icon } }
--   showcase = lo que se enseña a otras hermandades en el directorio
function ns.WarRecord(season)
	season = season or ns.PvPSeason()
	local g = LG:GuildData()
	local guild = LG:GuildName()
	local seasons = {}
	local specials, feats = {}, {}
	local function result(rec)
		rec.specials, rec.feats, rec.seasons = specials, feats, seasons
		rec.showcase = {}
		for _, f in ipairs(feats) do
			if #rec.showcase < 5 then rec.showcase[#rec.showcase + 1] = { title = f.title, t = f.t } end
		end
		for _, sp in ipairs(ns.WAR_SPECIALS) do
			if specials[sp.kind] and #rec.showcase < 5 then rec.showcase[#rec.showcase + 1] = { title = sp.title, sub = specials[sp.kind].sub, t = specials[sp.kind].t } end
		end
		return rec
	end
	if not g or not guild then return result(emptySeason(season)) end

	local finished = {}
	for _, w in pairs(g.wars) do
		if ns.WarPhase(w) == "finished" then finished[#finished + 1] = w end
	end
	table.sort(finished, function(a, b) return a.start < b.start end)

	local gm = guildMasterName()
	local streak, totalWins = 0, 0
	local function special(kind, t, sub)
		if not specials[kind] then specials[kind] = { t = t, sub = sub } end
	end
	for _, w in ipairs(finished) do
		local s = ns.WarScore(w)
		-- Sin una sola baja en ningún bando no cuenta (nadie se presentó).
		if s.ours + s.theirs > 0 then
			local ws = warSeason(w)
			local rec = seasons[ws] or emptySeason(ws)
			seasons[ws] = rec
			local opp = (w.from == guild and w.ratingTo or w.ratingFrom) or START_RATING
			local res = s.ours > s.theirs and 1 or (s.ours < s.theirs and 0 or 0.5)
			local expected = 1 / (1 + 10 ^ ((opp - rec.rating) / 400))
			local before = rec.rating
			rec.rating = math.floor(rec.rating + K_FACTOR * (res - expected) + 0.5)
			rec.best = math.max(rec.best or START_RATING, rec.rating)
			table.insert(rec.history, 1, { war = w, ours = s.ours, theirs = s.theirs, result = res, delta = rec.rating - before,
				rating = rec.rating, confirmed = s.confirmed })
			local sub = ("%s · %d–%d · %s"):format(ns.MapName(w.map, w.zone), s.ours, s.theirs, date("%d/%m/%Y", w.start))
			if res == 1 then
				rec.wins = rec.wins + 1
				totalWins = totalWins + 1
				streak = streak + 1
				if totalWins == 1 then special("first", w.start, sub) end
				if streak == 3 then special("streak3", w.start, sub) end
				if streak == 5 then special("streak5", w.start, sub) end
				if opp - before >= 100 then special("giant", w.start, sub) end
				if s.ours >= 10 and s.ours >= 2 * s.theirs then special("crush", w.start, sub) end
				if gm then
					local gmDied = false
					for _, k in ipairs(s.deaths) do if k.victimName == gm then gmDied = true end end
					if not gmDied and (g.warSeen[w.id] or {})[gm] then special("wall", w.start, sub) end
				end
			elseif res == 0 then
				rec.losses = rec.losses + 1
				streak = 0
			else
				rec.draws = rec.draws + 1
			end
			rec.last = w.start + w.duration
		end
	end

	-- Proezas de fuerza: lo que quedó de cada temporada ya terminada.
	local current = ns.PvPSeason()
	local past = {}
	for s in pairs(seasons) do
		if s < current then past[#past + 1] = s end
	end
	table.sort(past)
	for _, s in ipairs(past) do
		local rec = seasons[s]
		local league = ns.WarLeague(rec.rating)
		if league.min > 0 then
			feats[#feats + 1] = { key = ("league:%d"):format(s), season = s, tier = league.min >= ns.WAR_LEAGUES[3].min and 3 or 2, title = (L["Liga de %s en la temporada %d"]):format(league.label, s),
				desc = (L["Terminasteis la temporada %d con %d puntos de guerra."]):format(s, rec.rating), t = rec.last,
				icon = league.min >= ns.WAR_LEAGUES[3].min and "Interface\\Icons\\INV_Misc_Trophy_03" or "Interface\\Icons\\INV_Misc_Trophy_02" }
		end
		if rec.wins >= 3 and rec.losses == 0 then
			feats[#feats + 1] = { key = ("unbeaten:%d"):format(s), season = s, title = (L["Invictos en la temporada %d"]):format(s),
				desc = (L["%d guerras ganadas y ninguna perdida en la temporada %d."]):format(rec.wins, s), t = rec.last,
				icon = "Interface\\Icons\\INV_Shield_05" }
		end
	end
	table.sort(feats, function(a, b) return (a.t or 0) > (b.t or 0) end)

	return result(seasons[season] or emptySeason(season))
end

-- Desafíos de la categoría "Guerras" y proezas, para Achievements.lua.
function ns.WarChallengeDefs()
	if ns.WARS_PAUSED then return {} end -- en pausa: sus logros no se ven ni cuentan
	local defs = {}
	local function record() return ns.WarRecord() end
	for _, sp in ipairs(ns.WAR_SPECIALS) do
		local kind = sp.kind
		defs[#defs + 1] = {
			id = "war:" .. kind, cat = "wars", name = sp.title, icon = sp.icon, desc = sp.desc,
			eval = function()
				local got = record().specials[kind]
				return got and 1 or 0, 1, got and got.t or nil
			end,
		}
	end
	-- Proezas: solo las conseguidas (no se ven antes ni dan puntos).
	for _, f in ipairs(record().feats) do
		defs[#defs + 1] = {
			id = "feat:" .. f.key, cat = "feats", feat = true, name = f.title, icon = f.icon, desc = f.desc,
			eval = function() return 1, 1, f.t end,
		}
	end
	return defs
end

---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Acciones del maestro de hermandad
---------------------------------------------------------------------------

local function publish(rec)
	LG:Send("WAR", rec)
	return ns.NetSend("WAR", rec)
end

---------------------------------------------------------------------------
-- Zonas: se elige por nombre, sin tener que estar allí
---------------------------------------------------------------------------

local AZEROTH = 947 -- mapa raíz de Classic (Kalimdor y Reinos del Este cuelgan de él)
local ZONE_TYPE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
local zoneList

local function plain(s)
	s = (s or ""):lower()
	for from, to in pairs({ ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ü"] = "u", ["ñ"] = "n",
		["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ú"] = "u", ["Ñ"] = "n" }) do
		s = s:gsub(from, to)
	end
	return strtrim(s)
end

-- Todas las zonas del juego con su nombre en el idioma del cliente.
function ns.WarZones()
	if zoneList then return zoneList end
	zoneList = {}
	if C_Map and C_Map.GetMapChildrenInfo then
		local root = AZEROTH
		if C_Map.GetFallbackWorldMapID then
			local ok, id = pcall(C_Map.GetFallbackWorldMapID)
			if ok and id then root = id end
		end
		local ok, children = pcall(C_Map.GetMapChildrenInfo, root, ZONE_TYPE, true)
		if ok and type(children) == "table" then
			local seen = {}
			for _, info in ipairs(children) do
				if info.mapID and info.name and not seen[info.name] then
					seen[info.name] = true
					zoneList[#zoneList + 1] = { map = info.mapID, name = info.name }
				end
			end
		end
	end
	table.sort(zoneList, function(a, b) return a.name < b.name end)
	return zoneList
end

-- Busca una zona por nombre (sin tildes ni mayúsculas; vale un trozo si solo
-- encaja con una). Devuelve mapID y nombre, o nil y un texto de error.
function ns.FindZone(text)
	local wanted = plain(text)
	if wanted == "" then return nil, L["Escribe la zona de la batalla."] end
	local partial = {}
	for _, z in ipairs(ns.WarZones()) do
		local name = plain(z.name)
		if name == wanted then return z.map, z.name end
		if name:find(wanted, 1, true) then partial[#partial + 1] = z end
	end
	-- La zona en la que estás, aunque no salga en la lista.
	if plain(GetZoneText and GetZoneText()) == wanted and ns.CurrentMap() then return ns.CurrentMap(), GetZoneText() end
	if #partial == 1 then return partial[1].map, partial[1].name end
	if #partial == 0 then return nil, (L["No conozco la zona \"%s\"."]):format(text) end
	local names = {}
	for i = 1, math.min(4, #partial) do names[i] = partial[i].name end
	return nil, (L["¿Cuál de estas? %s"]):format(table.concat(names, ", ") .. (#partial > 4 and ", ..." or ""))
end

-- Devuelve un texto de error, o nil si se ha declarado.
-- zoneText: nombre de la zona (por defecto, la tuya).
function ns.DeclareWar(enemy, start, durationMin, zoneText)
	local g = LG:GuildData()
	local guild = LG:GuildName()
	local me = ns.PlayerFullName()
	if not g or not guild then return L["No estás en una hermandad."] end
	if not ns.IsGuildMaster(me) then return L["Solo el maestro de hermandad puede declarar guerras."] end
	enemy = enemy and strtrim(enemy) or ""
	if enemy == "" then return L["Escribe el nombre de la hermandad."] end
	if enemy == guild then return L["No puedes declararte la guerra a ti mismo."] end
	local duration = math.floor((tonumber(durationMin) or 0) * 60)
	if duration < MIN_DURATION or duration > MAX_DURATION then return L["La duración tiene que estar entre 15 y 240 minutos."] end
	if not start or start + duration < ns.Now() then return L["Fecha u hora no válidas."] end
	local map, zoneName = ns.FindZone(zoneText or (GetZoneText and GetZoneText()) or "")
	if not map then return zoneName end
	for _, w in pairs(g.wars) do
		local phase = ns.WarPhase(w)
		if ns.WarEnemy(w, guild) == enemy and (phase == "pending" or phase == "upcoming" or phase == "active") then
			return L["Ya hay una guerra pendiente o en curso con esa hermandad."]
		end
	end
	local entry = ns.DirectoryEntry(enemy)
	local now = ns.Now()
	local rec = {
		id = ("%s>%s:%d"):format(guild, enemy, now),
		from = guild, fromFaction = myFaction(),
		to = enemy, toFaction = entry and entry.faction or opposite(myFaction()),
		map = map, zone = zoneName,
		start = start, duration = duration,
		status = "pending", rev = 1, by = me, side = guild, t = now,
		ratingFrom = ns.WarRecord().rating,
		season = ns.PvPSeason(),
	}
	ns.MergeWar(g, guild, rec)
	local sent = publish(rec)
	LG:DataChanged()
	LG:Print((L["Guerra declarada a <%s>: %s, %s, %d min."]):format(enemy, rec.zone, date("%d/%m %H:%M", start), math.floor(duration / 60)))
	if not sent and not (entry and entry.test and not entry.live) then
		LG:Print(L["No se ha podido enviar por la red: pásale el código de la guerra a su maestro (JcJ > Guerras > Código)."])
	end
	-- Modo prueba: la hermandad de ejemplo acepta sola a los pocos segundos.
	if LG:InTestMode() and entry and entry.test and not entry.live then
		Wars:ScheduleTimer(function() ns.SimulateWarAnswer(rec.id, "accepted") end, 3)
	end
	return nil
end

-- status: "accepted" | "declined" | "cancelled"
function ns.AnswerWar(id, status)
	local g = LG:GuildData()
	local guild = LG:GuildName()
	local me = ns.PlayerFullName()
	local w = g and g.wars[id]
	if not w or not ns.IsGuildMaster(me) then return end
	local rec = {}
	for k, v in pairs(w) do rec[k] = v end
	rec.report = nil
	rec.status, rec.rev, rec.by, rec.side, rec.t = status, w.rev + 1, me, guild, ns.Now()
	if status == "accepted" and w.to == guild then rec.ratingTo = ns.WarRecord().rating end
	local changed, old = ns.MergeWar(g, guild, rec)
	if not changed then return end
	notify(g.wars[id], old)
	publish(rec)
	LG:DataChanged()
end

-- Modo prueba: la otra hermandad responde.
function ns.SimulateWarAnswer(id, status)
	local g = LG:GuildData()
	local w = g and g.wars[id]
	if not w or not LG:InTestMode() then return end
	local enemy = ns.WarEnemy(w)
	local rec = {}
	for k, v in pairs(w) do rec[k] = v end
	rec.report = nil
	rec.status, rec.rev, rec.by, rec.side, rec.t = status, w.rev + 1, "GM " .. enemy, enemy, ns.Now()
	local entry = ns.DirectoryEntry(enemy)
	rec.ratingTo = entry and entry.rating or START_RATING
	local changed, old = ns.MergeWar(g, LG:GuildName(), rec, nil, "guild")
	if changed then
		notify(g.wars[id], old)
		LG:DataChanged()
	end
end

---------------------------------------------------------------------------
-- Marcador en directo
---------------------------------------------------------------------------

local function myReport(g, w, final)
	local s = ns.WarScore(w)
	local names = {}
	for name in pairs(participants(g, w, s)) do
		if g.members[name] then names[#names + 1] = name end
	end
	return {
		id = w.id, guild = LG:GuildName(),
		deaths = #s.deaths, score = s.ours, present = (ns.WarPresence(w)),
		addon = names, final = final or nil, t = ns.Now(),
	}
end

-- Código para pasar a mano: la guerra (para declararla o responderla) o, si
-- ya ha terminado, nuestro marcador final.
function ns.WarCode(id)
	local g = LG:GuildData()
	local w = g and g.wars[id]
	if not w then return nil end
	if ns.WarPhase(w) == "finished" or ns.WarPhase(w) == "active" then
		return ns.EncodeCode("TICK", myReport(g, w, ns.WarPhase(w) == "finished"))
	end
	local rec = {}
	for k, v in pairs(w) do rec[k] = v end
	rec.report = nil
	return ns.EncodeCode("WAR", rec)
end

-- Aplica un código pegado. Devuelve un texto de error, o nil.
function ns.ApplyWarCode(text)
	local g = LG:GuildData()
	local guild = LG:GuildName()
	if not g or not guild then return L["No estás en una hermandad."] end
	if not ns.CanManageEvents(ns.PlayerFullName()) then return L["Solo los oficiales pueden pegar códigos de guerra."] end
	local kind, data = ns.DecodeCode(text)
	if kind == "WAR" then
		local changed, old = ns.MergeWar(g, guild, data, nil, "code")
		if not changed then return L["Ese código no cambia nada (ya estaba aplicado o no es para tu hermandad)."] end
		notify(g.wars[data.id], old)
		LG:Send("WAR", data)
	elseif kind == "TICK" then
		if not ns.MergeWarReport(g, guild, data, nil, "code") then
			return L["Ese código no cambia nada (ya estaba aplicado o no es para tu hermandad)."]
		end
		LG:Send("WARREP", data)
		LG:Print((L["Marcador de <%s> aplicado."]):format(data.guild or "?"))
	else
		return L["Código no válido."]
	end
	LG:DataChanged()
	return nil
end

local reminded = {}

function Wars:OnEnable()
	self:ScheduleRepeatingTimer("Tick", TICK_EVERY)
end

-- Guerras en pausa (06/10): con las capas de Forever dos hermandades pueden no
-- verse aunque estén en la misma zona. Las sustituye la llamada de auxilio
-- (Aid.lua). El código se queda para retomarlas.
ns.WARS_PAUSED = true

-- En pausa, fuera también la subcategoría Guerras de los logros.
for _, cat in ipairs(ns.ACH_CATEGORIES or {}) do
	for i = #(cat.sub or {}), 1, -1 do
		if cat.sub[i].key == "wars" then table.remove(cat.sub, i) end
	end
end

function Wars:Tick()
	if ns.WARS_PAUSED then return end
	local g = LG:GuildData()
	if not g or not LG:HasConsent() then return end
	local now = ns.Now()
	for id, w in pairs(g.wars) do
		local phase = ns.WarPhase(w, now)
		local enemy = ns.WarEnemy(w)
		if phase == "upcoming" and w.start - now <= REMIND_BEFORE and not reminded[id .. "soon"] then
			reminded[id .. "soon"] = true
			LG:Print((L["La guerra contra <%s> empieza en %d minutos en %s."]):format(enemy, math.ceil((w.start - now) / 60), ns.MapName(w.map, w.zone)))
		elseif phase == "active" then
			if not reminded[id .. "start"] then
				reminded[id .. "start"] = true
				local msg = (L["¡Empieza la guerra contra <%s> en %s!"]):format(enemy, ns.MapName(w.map, w.zone))
				if RaidNotice_AddMessage and RaidWarningFrame then RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"]) end
				LG:Print(msg)
			end
			-- Quién de los nuestros con el addon está en la zona.
			local _, names = ns.WarPresence(w)
			g.warSeen[id] = g.warSeen[id] or {}
			for _, name in ipairs(names) do
				if g.members[name] then g.warSeen[id][name] = true end
			end
		end
		local closing = phase == "finished" and now <= w.start + w.duration + RESULT_GRACE
		if phase == "active" or (closing and not w.sentFinal) then
			-- Manda el marcador un solo miembro: si otro lo ha hecho hace poco, se espera.
			if not heardTick[id] or GetTime() - heardTick[id] > TICK_EVERY - 5 then
				if ns.NetSend("TICK", myReport(g, w, closing)) then
					heardTick[id] = GetTime()
					if closing then w.sentFinal = true end
				end
			end
		end
		if phase == "finished" and not reminded[id .. "end"] and now - (w.start + w.duration) < 3600 then
			reminded[id .. "end"] = true
			local s = ns.WarScore(w)
			local result = s.ours > s.theirs and L["VICTORIA"] or (s.ours < s.theirs and L["DERROTA"] or L["EMPATE"])
			LG:Print((L["Guerra contra <%s> terminada: %s %d–%d."]):format(enemy, result, s.ours, s.theirs))
		end
	end
end
