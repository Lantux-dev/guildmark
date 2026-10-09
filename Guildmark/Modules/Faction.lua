-- Clasificación de la facción: cada hermandad anuncia en la red de hermandades
-- (HI, Network.lua) sus datos de la temporada JcJ, y con los de todas se hace
-- la clasificación de la Horda o la Alianza, los récords y el Horda contra
-- Alianza (lo de la otra facción llega por el puente de Battle.net).
--
-- La temporada empieza, para cada addon, la primera vez que ve su número
-- (GetCurrentArenaSeason): lo de antes no cuenta. Son datos que manda cada
-- hermandad de sí misma: dan prestigio, no se pueden verificar entre hermandades.
local _, ns = ...
local LG = ns.LG

local MAX_DUNGEONS = 12

-- Inicio de la temporada actual (la primera vez que este addon vio su número).
function ns.SeasonStart()
	local season = ns.PvPSeason()
	local starts = LG.db.global.seasonStarts
	starts[season] = starts[season] or ns.Now()
	return starts[season], season
end

-- Mejor tiempo de asalto por ciudad: de la declaración a la caída del líder.
function ns.AssaultTimes(g, since)
	local best = {}
	for _, r in pairs(g.regicides or {}) do
		local c = r.call and g.calls[r.call]
		if c and c.kind == "assault" and r.t >= (since or 0) and r.t > c.t then
			local secs = r.t - c.t
			if not best[r.city] or secs < best[r.city] then best[r.city] = secs end
		end
	end
	return best
end

-- Lo que la hermandad cuenta de sí misma esta temporada.
function ns.GuildSeasonStats()
	local g = LG:GuildData()
	if not g then return nil end
	local start, season = ns.SeasonStart()
	local guild = LG:GuildName()
	local s = { season = season, kills = 0, deaths = 0, assaults = 0, regicides = 0, helps = 0, defended = 0, gmKills = 0 }
	for _, k in pairs(g.kills) do
		if k.t >= start and not ns.IsVoided(g, k.id) then
			if k.kind == "kill" and k.victimGM and not k.bg then s.gmKills = s.gmKills + 1 end
			if k.kind == "kill" and k.honorable then s.kills = s.kills + 1
			elseif k.kind == "death" then s.deaths = s.deaths + 1 end
		end
	end
	for _, c in pairs(g.calls or {}) do
		if c.t >= start then
			if c.kind == "assault" then
				if ns.AssaultCompleted and ns.AssaultCompleted(g, c) then s.assaults = s.assaults + 1 end
			elseif (c.external or 0) >= 1 then s.defended = s.defended + 1 end
		end
	end
	for _, r in pairs(g.regicides or {}) do
		if r.t >= start then s.regicides = s.regicides + 1 end
	end
	local helped = {}
	for _, h in pairs(g.aidHelps or {}) do
		if h.t >= start and h.guild ~= guild and not helped[h.id] and ns.AidHelpKills and ns.AidHelpKills(g, h)[1] then
			helped[h.id] = true
			s.helps = s.helps + 1
		end
	end
	s.assaultTimes = ns.AssaultTimes(g, start)
	s.dungeonClears = ns.GuildDungeonClears and ns.GuildDungeonClears(g, start) or 0
	s.raids = {}
	for _, r in ipairs(ns.RaidProgress and ns.RaidProgress(g, start) or {}) do
		s.raids[#s.raids + 1] = { key = r.key, done = r.done, total = r.total }
	end
	s.points = ns.AchievementState and ns.AchievementState().points or 0
	-- Mejores tiempos de mazmorra de la temporada (los 12 más rápidos).
	local times = {}
	for _, d in ipairs(ns.DungeonTimes and ns.DungeonTimes() or {}) do
		for _, run in ipairs(d.runs) do
			if run.t >= start then
				times[#times + 1] = { d.dungeon, run.duration }
				break
			end
		end
	end
	table.sort(times, function(a, b) return a[2] < b[2] end)
	s.dungeons = {}
	for i = 1, math.min(MAX_DUNGEONS, #times) do s.dungeons[times[i][1]] = times[i][2] end
	return s
end

local function num(v, max)
	v = tonumber(v)
	if not v or v ~= v then return 0 end
	return math.max(0, math.min(max or 1000000, math.floor(v)))
end

-- Lo que llega de otra hermandad, limpio.
function ns.SanitizeSeasonStats(d)
	if type(d) ~= "table" then return nil end
	local s = { season = num(d.season, 1000), kills = num(d.kills), deaths = num(d.deaths), assaults = num(d.assaults, 10000),
		regicides = num(d.regicides, 10000), helps = num(d.helps, 10000), defended = num(d.defended, 10000), points = num(d.points, 1000),
		gmKills = num(d.gmKills, 10000), dungeonClears = num(d.dungeonClears, 100000), assaultTimes = {}, dungeons = {}, raids = {} }
	for i, r in ipairs(type(d.raids) == "table" and d.raids or {}) do
		if i > 6 then break end
		if type(r) == "table" and type(r.key) == "string" then
			local total = num(r.total, 50)
			s.raids[#s.raids + 1] = { key = r.key:sub(1, 12), done = math.min(num(r.done, 50), total), total = total }
		end
	end
	for key, secs in pairs(type(d.assaultTimes) == "table" and d.assaultTimes or {}) do
		if ns.CITY and ns.CITY[key] then s.assaultTimes[key] = num(secs, 86400) end
	end
	local n = 0
	for name, secs in pairs(type(d.dungeons) == "table" and d.dungeons or {}) do
		n = n + 1
		if n > MAX_DUNGEONS then break end
		if type(name) == "string" and name ~= "" then s.dungeons[name:gsub("|", ""):sub(1, 40)] = num(secs, 6 * 3600) end
	end
	return s
end

-- Avance en bandas en texto: "Cima Hyjal 6/13 · Cavernas del Túmulo 2/8".
local RAID_NAMES = { ["62034"] = ns.L["Cima Hyjal"], ["62035"] = ns.L["Cavernas del Túmulo"] }
function ns.RaidProgressText(raids)
	local parts = {}
	for _, r in ipairs(raids or {}) do
		parts[#parts + 1] = ("%s %d/%d"):format(RAID_NAMES[r.key] or r.key, r.done, r.total)
	end
	return table.concat(parts, "  ·  ")
end
function ns.RaidBosses(raids)
	local n = 0
	for _, r in ipairs(raids or {}) do n = n + (r.done or 0) end
	return n
end

-- Todas las hermandades conocidas con sus datos de la temporada (la mía incluida, en directo).
function ns.FactionGuilds()
	local list = {}
	local _, season = ns.SeasonStart()
	local own = ns.GuildAnnouncement and ns.GuildAnnouncement()
	if own and not own.hidden then
		own.stats, own.own = ns.GuildSeasonStats(), true
		list[#list + 1] = own
	end
	for _, e in ipairs(ns.Directory()) do
		if not (own and e.guild == own.guild) then
			local copy = {}
			for k, v in pairs(e) do copy[k] = v end
			-- De otra temporada: cuenta como vacía.
			if not copy.stats or copy.stats.season ~= season then copy.stats = nil end
			list[#list + 1] = copy
		end
	end
	return list, season
end
