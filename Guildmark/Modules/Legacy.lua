-- Desafíos de hermandad por mazmorra y por banda, sacados de los desafíos de
-- legado de Forever (que son personales).
--
-- Cada desafío de legado de mazmorras tiene un criterio por mazmorra: matar a su
-- jefe final (criterio de tipo 0, asset = ID de criatura). Los de banda tienen un
-- criterio por jefe. Aquí se convierten en desafíos de hermandad con su lista:
-- "completadlas con un grupo de hermandad".
--
-- Sin registro de combate (prohibido), pero ENCOUNTER_END en Forever trae los jefes
-- del encuentro con su ID de criatura (encounterUnitStatus), que es el mismo que el
-- de los criterios: así se sabe directamente si cayó el jefe final. Para el criterio
-- sin criatura ("Sima Ígnea o Salón de los Feudales") el addon lo APRENDE: si justo después de un
-- ENCOUNTER_END se completa el criterio de legado de esa mazmorra, ese encuentro
-- era el final. Lo aprendido va en la ficha de cada miembro y se comparte.
--
-- Además (comprobado el 06/10): Forever tiene las estadísticas de Blizzard de
-- "Asesinatos de jefes", una por jefe final de cada mazmorra. Si dentro de una
-- instancia sube una de ellas, esa mazmorra se acaba de completar: se registra
-- como partida con su criterio de legado (rec.criterion). Es la vía fiable;
-- ENCOUNTER_END queda de respaldo para las mazmorras sin estadística.
-- Los avisos de ENCOUNTER_END se siguen guardando en global.diag.encounters.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Legacy = LG:NewModule("Legacy", "AceEvent-3.0", "AceTimer-3.0")

ns.LEGACY_CHALLENGES = true

local LEARN_DELAY = 2 -- segundos tras el jefe para mirar si se completó el criterio

-- Estadísticas de jefe final de Forever (categoría 14821 "Asesinatos de jefes")
-- y el criterio de legado de su mazmorra (nil si no hay o no se sabe).
ns.FINAL_BOSS_STATS = {
	[15027] = { criterion = 19213, dungeon = "Sima Ígnea" },
	[63573] = { criterion = 19213, dungeon = "Salón de los Feudales" },
	[63571] = { criterion = 116049, dungeon = "Ruinas de Lordaeron" },
	[15028] = { criterion = 18524, dungeon = "Cuevas de los Lamentos" },
	[63570] = { criterion = 3262, dungeon = "Las Minas de la Muerte" },
	[1092] = { criterion = 3263, dungeon = "Castillo de Colmillo Oscuro" },
	[63572] = { criterion = 116050, dungeon = "Ciudad de Dalaran" },
	[63589] = { criterion = 116050, dungeon = "Ciudad de Dalaran" },
	[6137] = { criterion = 18526, dungeon = "Cavernas de Brazanegra" },
	[6140] = { criterion = 18529, dungeon = "Gnomeregan" },
	[1093] = { criterion = 3264, dungeon = "Monasterio Escarlata: Catedral" },
	[6786] = { dungeon = "Cámaras Escarlata" },
	[6139] = { criterion = 18528, dungeon = "Horado Rajacieno" },
	[6141] = { criterion = 18530, dungeon = "Zahúrda Rajacieno" },
	[6142] = { criterion = 18531, dungeon = "Uldaman" },
	[1094] = { criterion = 3265, dungeon = "Zul'Farrak" },
	[6143] = { criterion = 18532, dungeon = "Maraudon" },
	[63575] = { criterion = 116057, dungeon = "Prisión de Alcaz" },
	[6144] = { criterion = 18533, dungeon = "El Templo de Atal'Hakkar" },
	[1095] = { criterion = 3266, dungeon = "Profundidades de Roca Negra" },
	[6145] = { criterion = 18534, dungeon = "Cumbre de Roca Negra Inferior" },
	[1096] = { criterion = 3268, dungeon = "Cumbre de Roca Negra Superior" },
	[15030] = { criterion = 19263, dungeon = "Scholomance" },
	[15031] = { criterion = 18471, dungeon = "Stratholme: muerto" },
	[6146] = { criterion = 18535, dungeon = "Dire Maul: North" },
	[63574] = { criterion = 116056, dungeon = "El Bancal del Creador" },
	-- Bandas (el último jefe; los desafíos de banda van por jefes)
	[63580] = { raid = true, dungeon = "Cima Hyjal" },
	[63581] = { raid = true, dungeon = "Cavernas del Túmulo" },
	[1098] = { raid = true, dungeon = "Guarida de Onyxia" },
}

-- Desafíos de legado (categorías 15593 Mazmorras y 15594 Bandas de Forever 1.60.1).
local LEGACY = {
	{ id = 62031, kind = "dungeon", key = "legacy_dg1", icon = "Interface\\Icons\\INV_Misc_Key_03" },
	{ id = 62032, kind = "dungeon", key = "legacy_dg2", icon = "Interface\\Icons\\INV_Misc_Key_04" },
	{ id = 62033, kind = "dungeon", key = "legacy_dg3", icon = "Interface\\Icons\\INV_Misc_Key_13" },
	{ id = 62034, kind = "raid", key = "legacy_raid1", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
	{ id = 62035, kind = "raid", key = "legacy_raid2", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Black" },
}

-- Copia de lo que devolvió el juego (2 de octubre de 2026), por si la API de
-- logros no responde y para las pruebas: { criterio, nombre, criatura }.
ns.LEGACY_FALLBACK = {
	[62031] = { name = "Espeleólogo novicio", criteria = {
		{ 19213, "Sima Ígnea o Salón de los Feudales", 0 }, { 116049, "Ruinas de Lordaeron", 250657 },
		{ 18524, "Cuevas de los Lamentos", 3654 }, { 3262, "Las Minas de la Muerte", 639 },
		{ 3263, "Castillo de Colmillo Oscuro", 4275 }, { 116054, "Excavación: Los Humedales", 260326 } } },
	[62032] = { name = "Espeleólogo veterano", criteria = {
		{ 116050, "Ciudad de Dalaran", 246020 }, { 18526, "Cavernas de Brazanegra", 4829 }, { 18529, "Gnomeregan", 7800 },
		{ 116053, "La Ciudad Sumergida", 260274 }, { 116058, "Monasterio Escarlata: Cementerio", 4543 },
		{ 116059, "Monasterio Escarlata: Biblioteca", 6487 }, { 116060, "Monasterio Escarlata: Armería", 3975 },
		{ 3264, "Monasterio Escarlata: Catedral", 3976 }, { 18528, "Horado Rajacieno", 4421 },
		{ 116052, "Bastión Krol'dok", 258968 } } },
	[62033] = { name = "Maestro espeleólogo", criteria = {
		{ 18530, "Zahúrda Rajacieno", 7358 }, { 18531, "Uldaman", 2748 }, { 3265, "Zul'Farrak", 7267 },
		{ 18532, "Maraudon", 12201 }, { 116057, "Prisión de Alcaz", 255702 }, { 18533, "El Templo de Atal'Hakkar", 5709 },
		{ 3266, "Profundidades de Roca Negra", 9019 }, { 116055, "Bastión Faucenegra", 247234 },
		{ 18534, "Cumbre de Roca Negra Inferior", 9568 }, { 3268, "Cumbre de Roca Negra Superior", 10363 },
		{ 19263, "Scholomance", 1853 }, { 550, "Stratholme: vivo", 10813 }, { 18471, "Stratholme: muerto", 10440 },
		{ 545, "Dire Maul: East", 11492 }, { 18535, "Dire Maul: North", 11501 }, { 546, "Dire Maul: West", 11496 },
		{ 116056, "El Bancal del Creador", 261809 } } },
	[62034] = { name = "Conqueror of the Wilds", criteria = {
		{ 116081, "Bandalar", 249790 }, { 116079, "Anciano de la Descomposición", 250076 },
		{ 116084, "Batallón Tiempo Perdido", 3339 }, { 116082, "Sylvestris Cantocaso", 257638 },
		{ 116076, "Viejo Acechapenumbras", 250070 }, { 116083, "Gharalis el Abisal", 250075 },
		{ 116073, "Kathris el Embrujado", 250077 }, { 116078, "Anara Viento Gélido", 249787 },
		{ 116077, "Anciano Minderel", 253861 }, { 116080, "Rastreador Ventoleve", 250074 },
		{ 116072, "Consejo de las Espinas", 250082 }, { 116071, "Nythus el Vinculasueño", 250078 },
		{ 116070, "El Rey Salvaje", 250079 } } },
	[62035] = { name = "Conqueror of the Deeps", criteria = {
		{ 116067, "Chillhowl", 259867 }, { 116062, "Anciano Garranudo", 259904 }, { 116063, "Khalith la Tejepavor", 259902 },
		{ 116065, "Pozo de las Penas", 259866 }, { 116064, "Amethrax", 259907 }, { 116066, "Del'lynar Melomadera", 259911 },
		{ 116068, "Ravus y Darlissa", 259905 }, { 116061, "Sonya Sombrasanto", 259912 } } },
}

local function plain(s)
	s = (s or ""):lower()
	for from, to in pairs({ ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ü"] = "u", ["ñ"] = "n" }) do
		s = s:gsub(from, to)
	end
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local cache
-- Desafíos de legado con sus criterios, en el idioma del cliente si la API responde.
-- { id, kind, key, icon, name, criteria = { { id, name, npc, completed } } }
function ns.LegacyList()
	if cache then return cache end
	local list = {}
	for _, def in ipairs(LEGACY) do
		local entry = { id = def.id, kind = def.kind, key = def.key, icon = def.icon, criteria = {} }
		local ok, _, name = pcall(GetAchievementInfo, def.id)
		entry.name = ok and name or ns.LEGACY_FALLBACK[def.id].name
		local count = GetAchievementNumCriteria and select(2, pcall(GetAchievementNumCriteria, def.id))
		if type(count) == "number" and count > 0 then
			for i = 1, count do
				local okc, text, ctype, completed, _, _, _, _, assetID, _, criteriaID = pcall(GetAchievementCriteriaInfo, def.id, i)
				if okc and text then
					entry.criteria[#entry.criteria + 1] = { id = criteriaID, name = text, npc = assetID, completed = completed and true or false }
				end
			end
		end
		if #entry.criteria == 0 then
			for _, c in ipairs(ns.LEGACY_FALLBACK[def.id].criteria) do
				entry.criteria[#entry.criteria + 1] = { id = c[1], name = c[2], npc = c[3], completed = false }
			end
		end
		list[#list + 1] = entry
	end
	cache = list
	return list
end

---------------------------------------------------------------------------
-- Aprender el jefe final de cada mazmorra
---------------------------------------------------------------------------

-- Criterios de mazmorra ya completados por este personaje: [criterio] = true.
local function completedCriteria()
	local done = {}
	for _, def in ipairs(LEGACY) do
		if def.kind == "dungeon" and GetAchievementNumCriteria then
			local ok, count = pcall(GetAchievementNumCriteria, def.id)
			for i = 1, (ok and count or 0) do
				local okc, _, _, completed, _, _, _, _, _, _, criteriaID = pcall(GetAchievementCriteriaInfo, def.id, i)
				if okc and completed and criteriaID then done[criteriaID] = true end
			end
		end
	end
	return done
end

-- Aviso de jefe derrotado: se guarda para diagnóstico y, si se completa a la vez
-- un criterio de legado, se aprende qué encuentro es el jefe final.
function ns.OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success, units, fromBossKill)
	local instanceName, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	local log = LG.db.global.diag.encounters or {}
	LG.db.global.diag.encounters = log
	table.insert(log, { t = date("%Y-%m-%d %H:%M:%S"), id = encounterID, name = encounterName, difficulty = difficultyID,
		size = groupSize, success = success, instance = instanceName, instanceType = instanceType, instanceID = instanceID,
		units = type(units) == "table" and units or nil, bossKill = fromBossKill or nil })
	while #log > 30 do table.remove(log, 1) end
	if success ~= 1 or instanceType ~= "party" then return end
	local before = completedCriteria()
	Legacy:ScheduleTimer(function()
		for criteriaID in pairs(completedCriteria()) do
			if not before[criteriaID] then
				local learned = LG.db.global.legacyLearned
				learned[criteriaID] = learned[criteriaID] or {}
				learned[criteriaID][encounterID] = { boss = encounterName, instanceID = instanceID, instance = instanceName }
				LG:Debug("jefe final aprendido:", criteriaID, encounterName, encounterID)
				LG:MarkDirty()
			end
		end
	end, LEARN_DELAY)
end

-- Lo aprendido viaja en la ficha de cada miembro.
table.insert(ns.recordProviders, function(rec)
	if next(LG.db.global.legacyLearned) then rec.legacy = LG.db.global.legacyLearned end
end)

-- Lo aprendido por toda la hermandad: [criterio][encounterID] = { instanceID, boss, instance }.
-- Un criterio puede tener varios jefes finales ("Sima Ígnea o Salón de los Feudales").
local function learnedByGuild(g)
	local all = {}
	local function add(source)
		for criteriaID, finals in pairs(type(source) == "table" and source or {}) do
			if type(finals) == "table" then
				all[criteriaID] = all[criteriaID] or {}
				for encounterID, v in pairs(finals) do
					if type(encounterID) == "number" and type(v) == "table" then all[criteriaID][encounterID] = v end
				end
			end
		end
	end
	add(LG.db.global.legacyLearned)
	for _, m in pairs(g.members) do add(m.legacy) end
	return all
end

---------------------------------------------------------------------------
-- Desafíos de hermandad
---------------------------------------------------------------------------

-- Grupos de hermandad que cuentan: 5 jugadores con 4+ de la guild en mazmorra;
-- 80 % de la guild en banda; siempre con 2 testigos.
local function guildRuns(g)
	local dungeons, raids = {}, {}
	for _, r in pairs(g.runs) do
		local witnesses = 0
		for _ in pairs(r.witnesses or {}) do witnesses = witnesses + 1 end
		if witnesses >= 2 then
			if r.raid then
				if (r.size or 0) >= 10 and (r.guildCount or 0) >= r.size * 0.8 then raids[#raids + 1] = r end
			elseif r.size == 5 and (r.guildCount or 0) >= 4 then
				dungeons[#dungeons + 1] = r
			end
		end
	end
	return dungeons, raids
end

-- Una mazmorra cuenta solo si un grupo de hermandad mató a su jefe final.
-- Devuelve done, cuándo, y si el jefe final aún no se conoce.
local function killedCreature(r, npc)
	for _, id in ipairs(type(r.creatures) == "table" and r.creatures or {}) do
		if id == npc then return true end
	end
	return false
end

-- Una mazmorra cuenta solo si un grupo de hermandad mató a su jefe final:
--   1. Directo: el ID de criatura del criterio de legado entre los jefes muertos
--      que trae ENCOUNTER_END (Forever lo da en encounterUnitStatus).
--   2. Si el criterio no tiene criatura ("Sima Ígnea o Salón de los Feudales"),
--      por el encuentro aprendido.
-- Devuelve done, cuándo, y si el jefe final aún no se conoce.
local function dungeonDone(criterion, runs, learned)
	local npc = tonumber(criterion.npc) or 0
	local finals = learned[criterion.id]
	local hasFinals = finals and next(finals) ~= nil
	local byStat = false
	for _, s in pairs(ns.FINAL_BOSS_STATS) do
		if s.criterion == criterion.id then byStat = true end
	end
	if npc == 0 and not hasFinals and not byStat then return false, nil, true end
	local first
	for _, r in ipairs(runs) do
		local final = hasFinals and r.encounterID and finals[r.encounterID]
		local ok = (r.criterion == criterion.id)
			or (npc ~= 0 and killedCreature(r, npc))
			or (final and (not final.instanceID or not r.instanceID or r.instanceID == final.instanceID))
		if ok and (not first or r.t < first) then first = r.t end
	end
	return first ~= nil, first, false
end

local function raidBossDone(criterion, runs)
	for _, r in ipairs(runs) do
		if plain(r.boss) == plain(criterion.name) then return true, r.t end
	end
	return false
end

-- Avance de la hermandad en bandas: { { name, done, total }, ... } (desde since).
function ns.RaidProgress(g, since)
	local _, raids = guildRuns(g)
	local recent = {}
	for _, r in ipairs(raids) do
		if r.t >= (since or 0) then recent[#recent + 1] = r end
	end
	local out = {}
	for _, entry in ipairs(ns.LegacyList()) do
		if entry.kind == "raid" then
			local done = 0
			for _, c in ipairs(entry.criteria) do
				if raidBossDone(c, recent) then done = done + 1 end
			end
			out[#out + 1] = { key = tostring(entry.id), name = entry.name, done = done, total = #entry.criteria }
		end
	end
	return out
end

-- Mazmorras completadas por grupos de hermandad (jefe final por su estadística o criatura) desde since.
function ns.GuildDungeonClears(g, since)
	local dungeons = guildRuns(g)
	local n = 0
	for _, r in ipairs(dungeons) do
		if r.t >= (since or 0) and (r.criterion or r.finalStat) then n = n + 1 end
	end
	return n
end

-- Definiciones para el catálogo de Achievements.lua (vacío si está apagado):
-- por cada desafío de legado, uno agrupado con su lista y, en las mazmorras,
-- además uno por mazmorra ("Sima Ígnea": derrotad a su jefe final).
function ns.LegacyChallengeDefs()
	if not ns.LEGACY_CHALLENGES then return {} end
	-- Partidas y jefes aprendidos se calculan una vez para todo el catálogo.
	local facts
	local function getFacts()
		if facts then return facts end
		local g = LG:GuildData()
		if not g then return nil end
		local dungeons, raids = guildRuns(g)
		facts = { dungeons = dungeons, raids = raids, learned = learnedByGuild(g) }
		return facts
	end

	local defs = {}
	for _, entry in ipairs(ns.LegacyList()) do
		local isRaid = entry.kind == "raid"
		defs[#defs + 1] = {
			id = entry.key,
			cat = isRaid and "raids" or "dungeons",
			name = (L["%s (hermandad)"]):format(entry.name),
			icon = entry.icon,
			desc = isRaid and L["Derrotad a todos estos jefes con una banda de hermandad (80 % de la guild)."]
				or L["Completad todas estas mazmorras con un grupo de hermandad (4 o 5 de la guild)."],
			eval = function()
				local f = getFacts()
				if not f then return 0, #entry.criteria end
				local criteria, done, last = {}, 0, nil
				for _, c in ipairs(entry.criteria) do
					local ok, t, unknown
					if isRaid then ok, t = raidBossDone(c, f.raids) else ok, t, unknown = dungeonDone(c, f.dungeons, f.learned) end
					if ok then
						done = done + 1
						if not last or t > last then last = t end
					end
					criteria[#criteria + 1] = { label = c.name .. (unknown and (" " .. L["(jefe final por identificar)"]) or ""), done = ok }
				end
				return done, #entry.criteria, done == #entry.criteria and last or nil, criteria
			end,
		}
		if not isRaid then
			for _, c in ipairs(entry.criteria) do
				defs[#defs + 1] = {
					id = "dg:" .. tostring(c.id),
					cat = "dungeons",
					name = c.name,
					icon = entry.icon,
					desc = (L["Derrotad al jefe final de %s con un grupo de hermandad (4 o 5 de la guild)."]):format(c.name),
					eval = function()
						local f = getFacts()
						if not f then return 0, 1 end
						local ok, t, unknown = dungeonDone(c, f.dungeons, f.learned)
						local criteria = unknown and { { label = L["Jefe final por identificar: se aprende la primera vez que alguien con el addon completa esta mazmorra."], done = false } } or nil
						return ok and 1 or 0, 1, t, criteria
					end,
				}
			end
		end
	end
	return defs
end

---------------------------------------------------------------------------
-- Estadísticas de jefe final: si una sube dentro de una instancia, mazmorra completada
---------------------------------------------------------------------------

local statSnapshot -- [estadística] = valor la última vez que se miró

local function readStat(id)
	if not GetStatistic then return nil end
	local ok, value = pcall(GetStatistic, id)
	if not ok then return nil end
	return tonumber(value) or 0 -- "--" = nunca
end

-- Mis contadores de jefes finales (van en la ficha: mazmorras completadas de cada uno).
function ns.MyBossStats()
	local out = {}
	for id in pairs(ns.FINAL_BOSS_STATS) do
		local v = readStat(id)
		if v and v > 0 then out[id] = v end
	end
	return out
end

table.insert(ns.recordProviders, function(rec)
	local stats = ns.MyBossStats()
	if next(stats) then rec.bossStats = stats end
end)

-- Mira los contadores; devuelve las estadísticas que han subido desde la última vez.
function ns.CheckBossStats()
	local now, risen = {}, {}
	for id in pairs(ns.FINAL_BOSS_STATS) do now[id] = readStat(id) end
	if statSnapshot then
		for id, v in pairs(now) do
			if v and statSnapshot[id] and v > statSnapshot[id] then risen[#risen + 1] = id end
		end
	end
	statSnapshot = now
	for _, id in ipairs(risen) do ns.OnFinalBossStat(id) end
	return risen
end

-- Un jefe final acaba de caer (ha subido su estadística): partida con su criterio.
function ns.OnFinalBossStat(statID)
	local info = ns.FINAL_BOSS_STATS[statID]
	if not info then return end
	local log = LG.db.global.diag.bossStats or {}
	LG.db.global.diag.bossStats = log
	table.insert(log, { t = date("%Y-%m-%d %H:%M:%S"), stat = statID, dungeon = info.dungeon, inGroup = IsInGroup() })
	while #log > 30 do table.remove(log, 1) end
	if ns.RecordFinalBoss then ns.RecordFinalBoss(statID, info) end
end

function Legacy:OnEnable()
	-- Los nombres de los criterios pueden no estar listos al entrar: se vuelven a leer.
	self:ScheduleTimer(function() cache = nil end, 30)
	-- Foto inicial de los contadores y vigilancia dentro de instancias.
	self:ScheduleTimer(function() ns.CheckBossStats() end, 5)
	self:ScheduleRepeatingTimer(function()
		local _, instanceType = GetInstanceInfo()
		if instanceType == "party" or instanceType == "raid" then ns.CheckBossStats() end
	end, 5)
	ns.RegisterEvent(self, "CRITERIA_UPDATE", function()
		if self.statSoon then return end
		self.statSoon = self:ScheduleTimer(function() self.statSoon = nil; ns.CheckBossStats() end, 1)
	end)
end
