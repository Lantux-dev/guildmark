-- Resumen de la hermandad ya calculado con las reglas del addon (clasificación,
-- caza, eventos y desafíos), para complementos que lo quieran mostrar fuera del
-- juego sin repetir la lógica de puntos (API.lua: GuildmarkAPI.BuildSummary). Solo incluye a
-- miembros que comparten datos con el addon (los demás no envían nada).
local _, ns = ...
local LG = ns.LG

local function rankingSection(g)
	local list = {}
	for name, s in pairs(ns.Scores()) do
		local m = g.members[name]
		if m then
			list[#list + 1] = { name = name, class = m.class, rank = ns.MeritRank(name).label, rep = s.rep, insignias = s.merits }
		end
	end
	table.sort(list, function(a, b) return a.rep > b.rep end)
	for i = #list, 26, -1 do list[i] = nil end

	local gatherers, crafters = {}, {}
	for name, m in pairs(g.members) do
		local gathered, crafted = ns.MemberWeekStats(m)
		local total = (gathered.mining or 0) + (gathered.herb or 0) + (gathered.skinning or 0)
		if total > 0 then
			gatherers[#gatherers + 1] = { name = name, class = m.class, mining = gathered.mining or 0, herb = gathered.herb or 0,
				skinning = gathered.skinning or 0, total = total }
		end
		if crafted > 0 then crafters[#crafters + 1] = { name = name, class = m.class, crafted = crafted } end
	end
	table.sort(gatherers, function(a, b) return a.total > b.total end)
	table.sort(crafters, function(a, b) return a.crafted > b.crafted end)
	for i = #gatherers, 11, -1 do gatherers[i] = nil end
	for i = #crafters, 11, -1 do crafters[i] = nil end
	return { reputation = list, gatherers = gatherers, crafters = crafters }
end

local function huntSection(g)
	local s = ns.HuntStats(7)
	local targets = {}
	for guild, how in pairs(ns.TargetGuilds()) do
		targets[#targets + 1] = { guild = guild, manual = how == "manual", deaths = s.killedBy[guild] or 0, hunted = s.hunted[guild] or 0 }
	end
	table.sort(targets, function(a, b) return a.deaths > b.deaths end)

	local since = ns.Now() - 7 * 86400
	local hunters, revenges = {}, {}
	for _, k in ipairs(s.recent) do
		if k.kind == "kill" and k.t >= since then
			hunters[k.killerName] = (hunters[k.killerName] or 0) + 1
			if k.revenge then revenges[k.killerName] = (revenges[k.killerName] or 0) + 1 end
		end
	end
	local hunterList = {}
	for name, n in pairs(hunters) do
		local m = g.members[name]
		hunterList[#hunterList + 1] = { name = name, class = m and m.class, kills = n, revenges = revenges[name] or 0 }
	end
	table.sort(hunterList, function(a, b) return a.kills > b.kills end)
	for i = #hunterList, 11, -1 do hunterList[i] = nil end

	local killedBy = {}
	for guild, n in pairs(s.killedBy) do killedBy[#killedBy + 1] = { guild = guild, deaths = n, hunted = s.hunted[guild] or 0 } end
	table.sort(killedBy, function(a, b) return a.deaths > b.deaths end)
	for i = #killedBy, 11, -1 do killedBy[i] = nil end

	-- El rival más peligroso de cada hermandad objetivo (para los carteles de "SE BUSCA").
	local dangerous = {}
	for _, k in pairs(g.kills) do
		if k.kind == "death" and k.guild and not k.bg and k.t >= since and not ns.IsVoided(g, k.id) then
			local d = dangerous[k.guild] or {}
			d[k.killerName or "?"] = (d[k.killerName or "?"] or 0) + 1
			dangerous[k.guild] = d
		end
	end
	for _, t in ipairs(targets) do
		local best, bestN = nil, 0
		for name, n in pairs(dangerous[t.guild] or {}) do
			if n > bestN then best, bestN = name, n end
		end
		t.mostDangerous, t.mostDangerousKills = best, bestN
	end

	local recent = {}
	for i = 1, math.min(15, #s.recent) do
		local k = s.recent[i]
		local isKill = k.kind == "kill"
		recent[#recent + 1] = { t = k.t, kind = k.kind, opponent = isKill and k.victimName or k.killerName, class = k.class,
			guild = k.guild, ours = isKill and k.killerName or k.victimName, zone = k.zone, revenge = k.revenge or nil }
	end
	return { targets = targets, hunters = hunterList, killedBy = killedBy, recent = recent }
end

local function eventsSection(g)
	local upcoming, past = ns.EventLists()
	local function signups(e)
		local roles = { tank = {}, healer = {}, dps = {} }
		for member, s in pairs(g.signups[e.id] or {}) do
			if s.status == "yes" and roles[s.role] then table.insert(roles[s.role], member) end
		end
		return roles
	end
	local list = {}
	for _, e in ipairs(upcoming) do
		if e.status ~= "cancelled" then
			list[#list + 1] = { id = e.id, title = e.title, kind = e.kind, start = e.start, minLevel = e.minLevel, note = e.note,
				creator = e.creator, comp = e.comp, signups = signups(e) }
		end
	end
	local done = {}
	for i = 1, math.min(5, #past) do
		local e = past[i]
		local n = 0
		for _ in pairs(g.attendance[e.id] or {}) do n = n + 1 end
		done[#done + 1] = { title = e.title, kind = e.kind, start = e.start, attended = n }
	end
	return { upcoming = list, past = done }
end

local function achievementsSection()
	local state = ns.AchievementState()
	local title = ns.AchievementRewards()
	local done, close = {}, {}
	for _, entry in ipairs(state.list) do
		local def = entry.def
		if entry.done then
			done[#done + 1] = { id = def.id, name = def.name, desc = def.desc, category = def.cat, doneAt = entry.doneAt }
		elseif not def.hidden and entry.progress > 0 then
			close[#close + 1] = { id = def.id, name = def.name, progress = entry.progress, target = entry.target, category = def.cat }
		end
	end
	table.sort(done, function(a, b) return (a.doneAt or 0) > (b.doneAt or 0) end)
	table.sort(close, function(a, b) return a.progress / a.target > b.progress / b.target end)
	for i = #close, 6, -1 do close[i] = nil end
	return { points = state.points, total = state.total, title = title, done = done, close = close }
end

function ns.BuildExport()
	local g = LG:GuildData()
	if not g or not LG:HasConsent() then return nil end
	local members = 0
	for _ in pairs(g.members) do members = members + 1 end
	-- Cada apartado por separado: si uno falla, el resto se exporta igual.
	local function safe(fn, ...)
		local ok, result = pcall(fn, ...)
		if not ok then LG:Debug("export:", result) end
		return ok and result or nil
	end
	return {
		guild = LG:GuildName(),
		test = LG:InTestMode() or nil,
		generated = ns.Now(),
		addonVersion = LG.VERSION,
		exporter = ns.PlayerFullName(),
		members = members,
		ranking = safe(rankingSection, g),
		hunt = safe(huntSection, g),
		events = safe(eventsSection, g),
		achievements = safe(achievementsSection),
	}
end

-- Quien lo guarda o lo publica es un complemento (GuildmarkAPI.BuildSummary).
