-- Datos de ejemplo para ver el aspecto de la interfaz en modo prueba.
-- Solo funcionan con /gmk prueba activo y solo tocan la hermandad ficticia
-- "~Pruebas". Todo lo que crean lleva test = true para poder borrarlo.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local MEMBERS = {
	{ "Draknar Puñohierro", "WARRIOR", "Orc" },
	{ "Grumhal Truenonegro", "SHAMAN", "Orc" },
	{ "Vexa Sombrafría", "WARLOCK", "Undead" },
	{ "Oskell Filonegro", "ROGUE", "Undead" },
	{ "Kaelthorn Ojoagudo", "HUNTER", "Troll" },
	{ "Mirelle Hojaverde", "DRUID", "Tauren" },
	{ "Thorvi Martillo", "PRIEST", "Troll" },
}

-- Rivales de la Alianza: nombre, clase y hermandad (las primeras salen más).
local ENEMIES = {
	{ "Aldric Escudoalto", "PALADIN", "Guardia de Ventormenta" },
	{ "Brenna Vientoclaro", "MAGE", "Guardia de Ventormenta" },
	{ "Corwin Daganegra", "ROGUE", "Guardia de Ventormenta" },
	{ "Dalia Rayoluna", "DRUID", "Escudo de Plata" },
	{ "Edric Martillorojo", "WARRIOR", "Escudo de Plata" },
	{ "Fiona Ojodehalcón", "HUNTER", "Hijos de Forjaz" },
	{ "Galen Luzserena", "PRIEST", "Hijos de Forjaz" },
	{ "Hilda Brasaoscura", "WARLOCK", "Los Errantes" },
	{ "Ivo Sinclan", "MAGE", nil },
}

-- Sin la Vega de Tuercespina: es la zona de las guerras de ejemplo y una kill al
-- azar dentro de su hora cambiaría el marcador.
local ZONES = { "Los Baldíos", "Tierras Altas de Arathi", "Montañas de Alterac", "Desolace", "Pantano de las Penas" }

local function pick(list) return list[math.random(#list)] end

-- Rival al azar, con más peso para los primeros (la hermandad que más nos caza).
local function pickEnemy()
	local i = math.min(#ENEMIES, math.floor(math.random() ^ 1.8 * #ENEMIES) + 1)
	return ENEMIES[i]
end

function ns.ClearTestData(g)
	for _, tableName in ipairs({ "members", "kills", "runs", "orders", "events", "spends", "adjustments", "lfg", "tribes", "projects", "donations", "chestMoves", "bgMatches" }) do
		for key, rec in pairs(g[tableName]) do
			if type(rec) == "table" and rec.test then
				g[tableName][key] = nil
				if tableName == "events" then g.attendance[key] = nil end
			end
		end
	end
	for guild, t in pairs(g.targets) do
		if t.test then g.targets[guild] = nil end
	end
	for id, w in pairs(g.wars) do
		if w.test then
			g.wars[id] = nil
			g.warSeen[id] = nil
		end
	end
	local dir = LG.db.global.directory
	for guild, e in pairs(dir) do
		if e.test then dir[guild] = nil end
	end
	-- Los desafíos, anulaciones y avisos vistos de "~Pruebas" empiezan de cero.
	wipe(g.achievements)
	wipe(g.voids)
	wipe(g.dismissed)
	if ns.lfgRequests then wipe(ns.lfgRequests) end
	for id in pairs(g.tribeAccepts) do if id:find("^test:") then g.tribeAccepts[id] = nil end end
	for id in pairs(g.tribeLeft) do if id:find("^test:") then g.tribeLeft[id] = nil end end
	for id in pairs(g.tribeInvites) do if id:find("^test:") then g.tribeInvites[id] = nil end end
	g.testActivity = nil
end

local DUNGEONS = { "Sima Ígnea", "Cuevas de los Lamentos", "Minas de la Muerte", "Castillo de Colmillo Oscuro", "Monasterio Escarlata", "Uldaman" }
local RAID_BOSSES = { "Lucifron", "Magmadar" }

-- Mazmorras y bandas de hermandad, encargos, eventos y subastas: para que los
-- Desafíos de hermandad enseñen progreso.
local function fillActivity(g, hunters, now, me)
	for i = 1, 14 do
		local t = now - math.random(3600, 12 * 86400)
		local members = { hunters[1], hunters[2], hunters[3], hunters[4], hunters[5] }
		local key = ("test:run:%d"):format(i)
		g.runs[key] = { key = key, test = true, t = t, instance = DUNGEONS[(i - 1) % #DUNGEONS + 1], instanceID = 900 + (i - 1) % #DUNGEONS,
			encounterID = 9000 + i, boss = L["Jefe final"], members = members, guildMembers = members, guildCount = 5, size = 5,
			reporter = me, witnesses = { [members[1]] = true, [members[2]] = true } }
	end
	for i, boss in ipairs(RAID_BOSSES) do
		local key = ("test:raid:%d"):format(i)
		g.runs[key] = { key = key, test = true, t = now - i * 86400, instance = "Núcleo de Magma", instanceID = 409, encounterID = 660 + i,
			boss = boss, members = hunters, guildMembers = hunters, guildCount = 18, size = 20, raid = true,
			reporter = me, witnesses = { [hunters[1]] = true, [hunters[2]] = true } }
	end
	for i = 1, 6 do
		local id = ("test:order:%d"):format(i)
		g.orders[id] = { id = id, test = true, t = now - i * 7200, requester = hunters[(i % #hunters) + 1], crafter = hunters[((i + 2) % #hunters) + 1],
			recipe = 2657, qty = 5, status = "done", rev = 3, by = me, updated = now - i * 7000 }
	end
	for i = 1, 2 do
		local id = ("test:event:%d"):format(i)
		g.events[id] = { id = id, test = true, t = now - i * 3 * 86400, creator = me, title = i == 1 and "Núcleo de Magma" or "Caza en la Vega",
			kind = i == 1 and "raid" or "pvp", start = now - i * 3 * 86400, comp = { tank = 2, healer = 5, dps = 13 },
			status = "active", rev = 1, by = me, updated = now - i * 3 * 86400 }
		g.attendance[id] = {}
		for j = 1, 6 do g.attendance[id][hunters[j]] = now - i * 3 * 86400 end
	end
	for i = 1, 3 do
		local id = ("test:spend:%d"):format(i)
		g.spends[id] = { id = id, test = true, member = hunters[i + 1], merits = 20 + i * 5, link = "[Objeto de prueba]", t = now - i * 86400, by = me }
	end
	-- Campos de batalla: unas cuantas partidas.
	for i = 1, 6 do
		local id = ("test:bg:%d"):format(i)
		g.bgMatches[id] = { id = id, test = true, member = hunters[(i % 4) + 1], t = now - i * 7200, result = i % 3 == 0 and "loss" or "win",
			map = i % 2 == 0 and "Garganta Grito de Guerra" or "Valle de Alterac", kb = i * 2, hk = 10 + i * 3, deaths = i, duration = 1200 }
	end
	-- Cofre: un estandarte ya completado, un proyecto a medias y alguna donación suelta.
	g.projects["test:project:1"] = { id = "test:project:1", test = true, rev = 2, kind = "standard", goal = 100,
		status = "open", created = now - 5 * 86400, creator = me, by = me, activatedAt = now - 3600 }
	g.projects["test:project:2"] = { id = "test:project:2", test = true, rev = 1, kind = "dungeons", goal = 400, status = "open",
		created = now - 2 * 86400, creator = me, by = me }
	for i = 1, 5 do
		local id = ("test:donation:%d"):format(i)
		g.donations[id] = { id = id, test = true, member = hunters[i], merits = 25, t = now - (6 - i) * 3600,
			project = i <= 4 and "test:project:1" or "chest" }
	end
	for i = 6, 8 do
		local id = ("test:donation:%d"):format(i)
		g.donations[id] = { id = id, test = true, member = hunters[i - 5], merits = 30, t = now - (9 - i) * 1800, project = "test:project:2" }
	end
end

-- Directorio de la red y guerras: una ganada, una perdida, una en curso y una
-- declaración pendiente de aceptar. Las kills de guerra llevan war = true.
local DIRECTORY = {
	{ "Guardia de Ventormenta", "Alliance", 84, 23, 1064, 3, 2, 0, { { title = "Victoria contra <Hijos del Trueno>", sub = "Arathi · 21–9" } } },
	{ "Escudo de Plata", "Alliance", 41, 12, 1012, 1, 1, 0 },
	{ "Hijos de Forjaz", "Alliance", 25, 6, 1000, 0, 0, 0 },
	{ "Los Errantes", "Alliance", 12, 4, 984, 0, 1, 0 },
	{ "Sombras de Lordaeron", "Horde", 60, 18, 1132, 5, 1, 1, { { title = "Primera victoria" }, { title = "Tres victorias seguidas" } } },
	{ "Colmillo Sangriento", "Horde", 33, 9, 992, 1, 2, 0 },
}
local WAR_MAP, WAR_ZONE = 1434, "Vega de Tuercespina"

local function fillWars(g, hunters, now, me)
	local dir = LG.db.global.directory
	for _, d in ipairs(DIRECTORY) do
		dir[d[1]] = { guild = d[1], faction = d[2], members = d[3], addon = d[4], rating = d[5], wins = d[6], losses = d[7],
			draws = d[8], trophies = d[9] or {}, t = now - math.random(60, 3000), test = true,
			stats = { season = ns.PvPSeason(), kills = math.random(5, 220), deaths = math.random(5, 150), assaults = math.random(0, 6),
				regicides = math.random(0, 2), helps = math.random(0, 12), defended = math.random(0, 3), points = math.random(3, 30),
				gmKills = math.random(0, 9), dungeonClears = math.random(2, 40),
				raids = { { key = "62034", done = math.random(0, 13), total = 13 }, { key = "62035", done = math.random(0, 8), total = 8 } },
				assaultTimes = d[2] == "Horde" and { stormwind = math.random(1500, 5400) } or { orgrimmar = math.random(1500, 5400) },
				dungeons = { ["Las Minas de la Muerte"] = math.random(1500, 2600), ["Cuevas de los Lamentos"] = math.random(2400, 3600) } } }
	end
	local guild = LG:GuildName()
	local faction = UnitFactionGroup and UnitFactionGroup("player") or "Horde"
	local n = 0
	local function war(enemy, start, duration, status, rating, report)
		n = n + 1
		local id = ("test:war:%d"):format(n)
		local incoming = status == "incoming"
		g.wars[id] = { id = id, test = true, from = incoming and enemy or guild, to = incoming and guild or enemy,
			fromFaction = incoming and "Alliance" or faction, toFaction = incoming and faction or "Alliance",
			map = WAR_MAP, zone = WAR_ZONE, start = start, duration = duration,
			status = incoming and "pending" or status, rev = incoming and 1 or 2, by = incoming and ("GM " .. enemy) or me,
			side = incoming and enemy or (status == "accepted" and enemy or guild),
			ratingFrom = 1000, ratingTo = rating, t = start - 86400, report = report }
		g.warSeen[id] = {}
		return id, g.wars[id]
	end
	local function fight(id, w, enemyNames, kills, deaths)
		for i = 1, kills do
			local e = enemyNames[(i % #enemyNames) + 1]
			local killer = hunters[(i % #hunters) + 1]
			local kid = ("test:warkill:%s:%d"):format(id, i)
			g.kills[kid] = { id = kid, test = true, war = true, kind = "kill", t = w.start + i * 90, killer = "Player-test-" .. killer,
				killerName = killer, victim = "Player-test-" .. e, victimName = e, guild = ns.WarEnemy(w, guild), zone = WAR_ZONE,
				map = WAR_MAP, honorable = true, honor = 40, reporter = killer, revenge = i % 5 == 0 or nil }
			g.warSeen[id][killer] = true
		end
		for i = 1, deaths do
			local victim = hunters[((i + 3) % #hunters) + 1]
			local e = enemyNames[(i % #enemyNames) + 1]
			local did = ("test:wardeath:%s:%d"):format(id, i)
			g.kills[did] = { id = did, test = true, war = true, kind = "death", t = w.start + i * 130 + 45, killer = "Player-test-" .. e,
				killerName = e, guild = ns.WarEnemy(w, guild), victim = "Player-test-" .. victim, victimName = victim,
				zone = WAR_ZONE, map = WAR_MAP, reporter = victim }
		end
		g.warSeen[id][me] = true
	end
	local guardia = { "Aldric Escudoalto", "Brenna Vientoclaro", "Corwin Daganegra", "Soldado Raso" }
	-- Ganada: 14 kills nuestras (3 rivales con addon confirman 10 muertes), 6 bajas nuestras.
	local id, w = war("Guardia de Ventormenta", now - 3 * 86400, 3600, "accepted", 1064,
		{ t = now - 3 * 86400 + 3700, deaths = 10, score = 6, present = 9, addon = { "Aldric Escudoalto", "Brenna Vientoclaro", "Corwin Daganegra" }, final = true })
	fight(id, w, guardia, 14, 6)
	-- Perdida por poco.
	id, w = war("Escudo de Plata", now - 86400, 3600, "accepted", 1012,
		{ t = now - 86400 + 3700, deaths = 5, score = 8, present = 7, addon = { "Dalia Rayoluna", "Edric Martillorojo" }, final = true })
	fight(id, w, { "Dalia Rayoluna", "Edric Martillorojo" }, 5, 8)
	-- En curso desde hace 20 minutos.
	id, w = war("Los Errantes", now - 20 * 60, 3600, "accepted", 984,
		{ t = now - 30, deaths = 4, score = 2, present = 5, addon = { "Hilda Brasaoscura" } })
	fight(id, w, { "Hilda Brasaoscura", "Ivo Sinclan" }, 5, 2)
	-- Declaración que te llega: para probar Aceptar y Rechazar.
	war("Hijos de Forjaz", now + 86400, 5400, "incoming", 1000)
end

-- JcE: grupos en el buscador (uno tuyo con una petición) y partidas con tiempo.
local function fillPvE(g, hunters, now, me)
	local function group(leader, dest, size, have, note, minutesAgo)
		local id = ("test:lfg:%s"):format(leader)
		local need = ns.LFG_SIZES[size]
		local members = { [leader] = "dps" }
		g.lfg[id] = { id = id, test = true, leader = leader, dest = dest, kind = size == 5 and "dungeon" or "raid", size = size,
			need = { tank = need.tank, healer = need.healer, dps = need.dps }, have = have, members = members, note = note,
			status = "open", rev = 1, t = now - minutesAgo * 60 }
		return id
	end
	group("Vexa Sombrafría", "Cuevas de los Lamentos", 5, { tank = 1, healer = 0, dps = 2 }, "Vamos ya", 12)
	group("Draknar Puñohierro", "Cavernas del Túmulo", 10, { tank = 2, healer = 1, dps = 4 }, nil, 40)
	local mine = group(me, "Las Minas de la Muerte", 5, { tank = 0, healer = 1, dps = 1 }, nil, 3)
	ns.lfgRequests[mine] = { ["Mirelle Hojaverde"] = { role = "tank", t = now - 60 } }

	-- Partidas con tiempo: entrada en la instancia y jefe final (ID de criatura).
	local function timed(i, dest, npc, minutes, team)
		local key = ("test:timed:%d"):format(i)
		local t = now - i * 86400
		g.runs[key] = { key = key, test = true, t = t, entered = t - minutes * 60, instance = dest, creatures = { npc },
			encounterID = 9000 + i, boss = "Jefe final", members = team, guildMembers = team, guildCount = #team, size = 5,
			witnesses = { [team[1]] = true, [team[2]] = true }, reporter = team[1] }
	end
	timed(1, "Las Minas de la Muerte", 639, 41.5, { me, hunters[2], hunters[3], hunters[4], hunters[5] })
	timed(2, "Las Minas de la Muerte", 639, 52.2, { hunters[2], hunters[6], hunters[7], hunters[8], me })
	timed(3, "Cuevas de los Lamentos", 3654, 63.8, { hunters[3], hunters[4], hunters[5], hunters[6], hunters[7] })
end

-- Tribus y actividad: la tuya aprobada (con Draknar, Grumhal y Vexa), otra
-- pendiente de aprobar, y un grupo de la tribu en una mazmorra ahora mismo.
local function fillTribes(g, hunters, now, me)
	local function tribe(id, name, creator, members, status, accepted)
		local set = {}
		for _, m in ipairs(members) do set[m] = true end
		g.tribes[id] = { id = id, test = true, name = name, members = set, creator = creator, status = status,
			rev = status == "pending" and 1 or 2, by = creator, decidedBy = status ~= "pending" and me or nil, t = now - 86400 }
		g.tribeAccepts[id] = {}
		for _, m in ipairs(accepted) do g.tribeAccepts[id][m] = now - 80000 end
	end
	tribe("test:tribe:1", "Colmillos de Hierro", hunters[2], { me, hunters[2], hunters[3], hunters[4] }, "approved", { me, hunters[3], hunters[4] })
	tribe("test:tribe:2", "Sombras del Pantano", hunters[5], { hunters[5], hunters[6], hunters[7], hunters[8] }, "pending", { hunters[6], hunters[7] })
	-- Se guarda en la hermandad de pruebas para que siga tras /reload (la real no se guarda).
	g.testActivity = {}
	local group = { hunters[2], hunters[3], hunters[4], hunters[5], hunters[6] }
	table.sort(group)
	for _, m in ipairs(group) do
		g.testActivity[m] = { kind = "dungeon", zone = "Los Baldíos", instance = "Cuevas de los Lamentos", group = group, ago = 12 * 60 }
	end
	g.testActivity[hunters[7]] = { kind = "world", zone = "Los Baldíos", ago = 600 }
	g.testActivity[hunters[8]] = { kind = "world", zone = "Orgrimmar", ago = 600 }
end

function ns.FillTestData()
	if not LG:InTestMode() then
		LG:Print(L["Los datos de ejemplo solo existen en modo prueba (/gmk prueba)."])
		return
	end
	local g = LG:GuildData()
	ns.ClearTestData(g)
	local now = ns.Now()
	local me = ns.PlayerFullName()

	for _, m in ipairs(MEMBERS) do
		local week = { mining = math.random(0, 220), herb = math.random(0, 180), skinning = math.random(0, 90) }
		g.members[m[1]] = { name = m[1], class = m[2], race = m[3], level = math.random(20, 30), locale = "esES",
			joined = now - math.random(8, 30) * 86400, t = now, test = true, pvp = { hk = math.random(5, 60), today = math.random(0, 6) },
			stats = { gathered = { mining = week.mining * 4, herb = week.herb * 4, skinning = week.skinning * 4 },
				crafted = math.random(20, 400), crafts = math.random(20, 300), week = ns.WeekStart(), weekGathered = week,
				weekCrafted = math.random(0, 80), bestDay = math.random(10, 90) } }
	end
	local hunters = { me }
	for _, m in ipairs(MEMBERS) do hunters[#hunters + 1] = m[1] end

	-- Muertes nuestras (quién nos mata).
	local deaths = {}
	for i = 1, 22 do
		local e = pickEnemy()
		local victim = pick(hunters)
		local t = now - math.random(600, 6 * 86400)
		local id = ("test:death:%d"):format(i)
		local rec = { id = id, test = true, kind = "death", t = t, killer = "Player-test-" .. e[1], killerName = e[1],
			class = e[2], guild = e[3], victim = "Player-test-" .. victim, victimName = victim, zone = pick(ZONES), reporter = victim }
		if math.random() < 0.4 then
			local a = pickEnemy()
			rec.assists = { { name = a[1], class = a[2], guild = a[3] } }
		end
		g.kills[id] = rec
		deaths[#deaths + 1] = rec
	end

	-- Kills nuestras: honorables, alguna venganza.
	for i = 1, 30 do
		local e = pickEnemy()
		local killer = pick(hunters)
		local t = now - math.random(300, 6 * 86400)
		local id = ("test:kill:%d"):format(i)
		local rec = { id = id, test = true, kind = "kill", t = t, killer = "Player-test-" .. killer, killerName = killer,
			victim = "Player-test-" .. e[1], victimName = e[1], class = e[2], guild = e[3], zone = pick(ZONES),
			honorable = math.random() < 0.9, honor = math.random(35, 85), reporter = killer }
		for _, d in ipairs(deaths) do
			if d.killerName == e[1] and t > d.t and t - d.t <= 600 then
				rec.revenge, rec.avenged = true, d.victimName
				break
			end
		end
		if not rec.revenge and math.random() < 0.15 then rec.revenge, rec.avenged = true, pick(hunters) end
		g.kills[id] = rec
	end

	-- Datos sospechosos para ver los avisos de la pestaña Oficial: Oskell tiene
	-- más kills que muertes honorables en su contador y ha matado 6 veces a la
	-- misma víctima en una hora; otro oficial ha hecho un ajuste grande.
	local cheater = "Oskell Filonegro"
	g.members[cheater].pvp = { hk = 41, today = 6, base = { t = now - 7 * 86400, hk = 40 } }
	for i = 1, 6 do
		local id = ("test:farm:%d"):format(i)
		g.kills[id] = { id = id, test = true, kind = "kill", t = now - 3600 + i * 300, killer = "Player-test-" .. cheater,
			killerName = cheater, victim = "Player-test-Ivo Sinclan", victimName = "Ivo Sinclan", class = "MAGE",
			zone = "Los Baldíos", honorable = true, honor = 40, reporter = cheater }
	end
	g.adjustments["test:adjust:1"] = { id = "test:adjust:1", test = true, t = now - 7200, member = "Thorvi Martillo",
		merits = 150, rep = 0, reason = "Donación al banco", by = "Draknar Puñohierro" }

	-- Una hermandad objetivo puesta "a mano" por un oficial.
	g.targets["Los Errantes"] = { active = true, by = me, t = now, test = true }

	fillActivity(g, hunters, now, me)
	fillWars(g, hunters, now, me)
	fillPvE(g, hunters, now, me)
	fillTribes(g, hunters, now, me)
	LG:DataChanged()
	LG:Print(L["Datos de ejemplo cargados en ~Pruebas: miembros, kills, mazmorras, bandas, encargos, eventos y subastas. Bórralos desde Oficial."])
end

function ns.RemoveTestData()
	local g = LG:GuildData()
	if not g or not LG:InTestMode() then return end
	ns.ClearTestData(g)
	LG:DataChanged()
	LG:Print(L["Datos de ejemplo borrados."])
end
