-- JcE: buscador de grupo de la hermandad y tiempos de mazmorra.
--
-- Buscar grupo: un miembro publica un grupo (destino, tamaño, su rol) y el addon
-- reparte las plazas por rol. Los demás piden invitación con su rol; al líder le
-- llega la petición y decide (invitar o rechazar). Los grupos caducan solos.
--
--   LFG     el grupo, con "rev": solo su líder lo cambia
--   LFGREQ  petición de invitación (para el líder)
--   LFGANS  respuesta del líder (para quien pidió)
--
-- Tiempos: Dungeon.lua apunta cuándo entró el grupo en la instancia; cuando cae
-- el jefe final de la mazmorra (por su ID de criatura, Legacy.lua) el tiempo
-- queda en la partida y aquí se hace la clasificación.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local LFG = LG:NewModule("LFG", "AceEvent-3.0", "AceTimer-3.0")

local GROUP_TTL = 2 * 3600
local ROLE_KEYS = { "tank", "healer", "dps" }

-- Plazas por rol según el tamaño (mazmorra de 5: 1 tanque, 1 sanador y 3 DPS).
local SIZES = {
	[5] = { tank = 1, healer = 1, dps = 3 },
	[10] = { tank = 2, healer = 3, dps = 5 },
	[20] = { tank = 2, healer = 5, dps = 13 },
	[40] = { tank = 4, healer = 10, dps = 26 },
}
ns.LFG_SIZES = SIZES

-- Peticiones que me han llegado como líder: [idGrupo][nombre] = { role, t }.
ns.lfgRequests = {}
-- Mis peticiones: [idGrupo] = "pending" | "accepted" | "declined".
ns.lfgMine = {}

---------------------------------------------------------------------------
-- Grupos
---------------------------------------------------------------------------

local function validCounts(t)
	if type(t) ~= "table" then return false end
	for _, r in ipairs(ROLE_KEYS) do
		local n = t[r]
		if type(n) ~= "number" or n < 0 or n > 40 then return false end
	end
	return true
end

function ns.MergeLFG(g, rec, sender)
	if type(rec) ~= "table" or type(rec.id) ~= "string" or type(rec.rev) ~= "number" then return false end
	if type(rec.leader) ~= "string" or (sender and rec.leader ~= sender) then return false end
	if not validCounts(rec.need) or not validCounts(rec.have) then return false end
	local old = g.lfg[rec.id]
	if old and (old.leader ~= rec.leader or old.rev >= rec.rev) then return false end
	g.lfg[rec.id] = rec
	return true, old
end

ns.handlers.LFG = function(sender, rec)
	local g = LG:GuildData()
	if g and ns.MergeLFG(g, rec, sender) then LG:DataChanged() end
end

local function isOpen(grp, now)
	return grp.status == "open" and (now or ns.Now()) - (grp.t or 0) < GROUP_TTL
end

-- Grupos abiertos, los más recientes primero; el mío delante.
function ns.LFGGroups()
	local g = LG:GuildData()
	local list = {}
	if not g then return list end
	local now, me = ns.Now(), ns.PlayerFullName()
	for _, grp in pairs(g.lfg) do
		if isOpen(grp, now) then list[#list + 1] = grp end
	end
	table.sort(list, function(a, b)
		if (a.leader == me) ~= (b.leader == me) then return a.leader == me end
		return (a.t or 0) > (b.t or 0)
	end)
	return list
end

function ns.MyLFGGroup()
	local me = ns.PlayerFullName()
	for _, grp in ipairs(ns.LFGGroups()) do
		if grp.leader == me then return grp end
	end
	return nil
end

-- Roles que aún faltan: { "healer", "dps" }.
function ns.LFGMissing(grp)
	local missing = {}
	for _, r in ipairs(ROLE_KEYS) do
		if (grp.have[r] or 0) < (grp.need[r] or 0) then missing[#missing + 1] = r end
	end
	return missing
end

local function publish(rec)
	local g = LG:GuildData()
	if not g then return end
	g.lfg[rec.id] = rec
	LG:Send("LFG", rec)
	LG:DataChanged()
end

local function update(grp, fn)
	local rec = {}
	for k, v in pairs(grp) do rec[k] = v end
	rec.have = { tank = grp.have.tank, healer = grp.have.healer, dps = grp.have.dps }
	rec.members = {}
	for k, v in pairs(grp.members or {}) do rec.members[k] = v end
	fn(rec)
	rec.rev = grp.rev + 1
	publish(rec)
end

-- Devuelve un texto de error, o nil.
function ns.CreateLFG(dest, size, role, note)
	local g = LG:GuildData()
	if not g then return L["No estás en una hermandad."] end
	dest = dest and strtrim(dest) or ""
	if dest == "" then return L["Escribe la mazmorra o banda."] end
	size = tonumber(size) or 5
	local need = SIZES[size]
	if not need then return L["El tamaño tiene que ser 5, 10, 20 o 40."] end
	if not tContains(ROLE_KEYS, role) then return L["Elige tu rol: T (tanque), S (sanador) o D (DPS)."] end
	if ns.MyLFGGroup() then return L["Ya tienes un grupo publicado: ciérralo antes."] end
	local me, now = ns.PlayerFullName(), ns.Now()
	local have = { tank = 0, healer = 0, dps = 0 }
	have[role] = 1
	publish({
		id = ("%s:%d"):format(me, now), leader = me, dest = ns.FindDestination(dest),
		kind = size == 5 and "dungeon" or "raid", size = size,
		need = { tank = need.tank, healer = need.healer, dps = need.dps }, have = have,
		members = { [me] = role }, note = note and note ~= "" and note:sub(1, 60) or nil,
		status = "open", rev = 1, t = now,
	})
	return nil
end

function ns.CloseLFG(id)
	local g = LG:GuildData()
	local grp = g and g.lfg[id]
	if not grp or grp.leader ~= ns.PlayerFullName() then return end
	update(grp, function(rec) rec.status = "closed" end)
	ns.lfgRequests[id] = nil
end

-- Busca el nombre oficial de una mazmorra (sin tildes, vale un trozo); si no, el texto tal cual.
function ns.FindDestination(text)
	local function plain(s)
		s = (s or ""):lower()
		for from, to in pairs({ ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ñ"] = "n" }) do s = s:gsub(from, to) end
		return s
	end
	local wanted = plain(text)
	local found
	for _, entry in ipairs(ns.LegacyList and ns.LegacyList() or {}) do
		if entry.kind == "dungeon" then
			for _, c in ipairs(entry.criteria) do
				-- "Sima Ígnea o Salón de los Feudales" son dos mazmorras.
				local a, b = c.name:match("^(.-) o (.+)$")
				for _, real in ipairs(a and { a, b } or { c.name }) do
					local name = plain(real)
					if name == wanted then return real end
					if name:find(wanted, 1, true) then found = found and true or real end
				end
			end
		end
	end
	return type(found) == "string" and found or text
end

---------------------------------------------------------------------------
-- Peticiones de invitación
---------------------------------------------------------------------------

function ns.RequestLFG(id, role)
	local g = LG:GuildData()
	local grp = g and g.lfg[id]
	if not grp or not isOpen(grp) or not tContains(ns.LFGMissing(grp), role) then return end
	ns.lfgMine[id] = "pending"
	LG:Send("LFGREQ", { group = id, to = grp.leader, role = role, t = ns.Now() })
	LG:Print((L["Has pedido unirte al grupo de %s para %s."]):format(ns.ShortName(grp.leader), grp.dest))
	LG:DataChanged()
end

ns.handlers.LFGREQ = function(sender, req)
	local g = LG:GuildData()
	if not g or req.to ~= ns.PlayerFullName() or type(req.group) ~= "string" then return end
	local grp = g.lfg[req.group]
	if not grp or grp.leader ~= req.to or not tContains(ROLE_KEYS, req.role) then return end
	ns.lfgRequests[req.group] = ns.lfgRequests[req.group] or {}
	ns.lfgRequests[req.group][sender] = { role = req.role, t = ns.Now() }
	LG:Print((L["%s pide unirse a tu grupo como %s. Decide en /gmk > JcE."]):format(ns.ShortName(sender), ns.RoleLabel(req.role)))
	if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK) end
	LG:DataChanged()
end

ns.handlers.LFGANS = function(sender, ans)
	local g = LG:GuildData()
	local grp = g and type(ans.group) == "string" and g.lfg[ans.group]
	if ans.to ~= ns.PlayerFullName() or not grp or grp.leader ~= sender then return end
	ns.lfgMine[ans.group] = ans.ok and "accepted" or "declined"
	LG:Print(ans.ok and (L["%s te invita a su grupo para %s."]):format(ns.ShortName(sender), grp.dest)
		or (L["%s no tiene sitio en su grupo para %s."]):format(ns.ShortName(sender), grp.dest))
	LG:DataChanged()
end

-- El líder responde: invitar (ocupa la plaza) o rechazar.
function ns.AnswerLFG(id, name, accept)
	local g = LG:GuildData()
	local grp = g and g.lfg[id]
	local req = ns.lfgRequests[id] and ns.lfgRequests[id][name]
	if not grp or not req or grp.leader ~= ns.PlayerFullName() then return end
	ns.lfgRequests[id][name] = nil
	LG:Send("LFGANS", { group = id, to = name, ok = accept or nil })
	if accept then
		local target = (LG.lastRawSenders and LG.lastRawSenders[name]) or name
		local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
		if invite then pcall(invite, target) end
		update(grp, function(rec)
			rec.have[req.role] = (rec.have[req.role] or 0) + 1
			rec.members[name] = req.role
		end)
	else
		LG:DataChanged()
	end
end

function ns.RoleLabel(role)
	for _, r in ipairs(ns.ROLES or {}) do
		if r.key == role then return r.label end
	end
	return role
end

function ns.PruneLFG(g)
	local now = ns.Now()
	for id, grp in pairs(g.lfg) do
		if now - (grp.t or 0) > GROUP_TTL * 2 then g.lfg[id] = nil end
	end
end

---------------------------------------------------------------------------
-- Tiempos de mazmorra
---------------------------------------------------------------------------

-- Mazmorra (criterio de legado) cuyo jefe final está entre los muertos de la partida.
local function finalBossDungeon(r)
	if type(r.creatures) ~= "table" then return nil end
	for _, entry in ipairs(ns.LegacyList and ns.LegacyList() or {}) do
		if entry.kind == "dungeon" then
			for _, c in ipairs(entry.criteria) do
				if (c.npc or 0) ~= 0 and tContains(r.creatures, c.npc) then return c.name end
			end
		end
	end
	return nil
end

-- Tiempos de mazmorra (1.2.1)
--
-- Cada jefe es un registro (Dungeon.lua); los de la misma entrada en la misma instancia con el
-- mismo grupo forman una PARTIDA: jefes en orden, parciales y, si cayó el jefe final, el tiempo.
-- El tiempo va de la primera baja (started) al jefe final; los registros de antes de la 1.2.1
-- solo tienen la entrada (entered).
--   · Historial: todas las partidas con al menos TIMES_MIN_GUILD de la hermandad (los de fuera,
--     en gris).
--   · Récords (y los de la facción): solo partidas oficiales, con el grupo entero de la
--     hermandad y un intento oficial pagado por todos (Dungeon.lua).
ns.TIMES_MIN_GUILD = 3

-- Nombre de la mazmorra de un registro de jefe final (nil si no es el jefe final): por la
-- criatura, por la estadística de jefe final o por el encuentro que la hermandad aprendió como
-- final (Legacy.lua; las mazmorras nuevas de Forever no tienen estadística).
function ns.RunDungeonName(r, learned)
	local stat = r.finalStat and ns.FINAL_BOSS_STATS and ns.FINAL_BOSS_STATS[r.finalStat]
	if finalBossDungeon(r) then return finalBossDungeon(r) end
	if stat then return stat.dungeon end
	if r.encounterID then
		learned = learned or (ns.LearnedFinalBosses and ns.LearnedFinalBosses(LG:GuildData()) or {})
		return learned[r.encounterID]
	end
	return nil
end

local function sortedMembers(r)
	local members = {}
	for _, m in ipairs(r.members or {}) do members[#members + 1] = m end
	table.sort(members)
	return members
end

-- ¿Es oficial la partida? Intento de los mismos miembros, declarado antes de la primera baja
-- (con un minuto de margen) y como mucho ATTEMPT_TTL antes, y pagado por todos.
local function officialAttempt(g, run)
	if run.raid then
		if run.guildCount < run.size or run.size < 10 then return nil end
	elseif run.size ~= 5 or run.guildCount < 5 then
		return nil
	end
	for _, a in pairs(g.attempts or {}) do
		if a.t <= run.start + 60 and run.start - a.t < (ns.ATTEMPT_TTL or 4 * 3600) and ns.SameMembers(a.members, run.members) then
			local _, allPaid = ns.AttemptPaid(g, a)
			if allPaid then return a end
		end
	end
	return nil
end

local RUN_GAP = 3600 -- más de una hora entre dos jefes: otra partida

-- Todas las partidas, de la más reciente a la más antigua:
-- { key, recKeys, dungeon, instance, instanceID, start, t, duration (si terminó), finished,
--   bosses = { { boss, t, split, encounterID, final } }, members, guildCount, size, raid, witnesses, official }
-- Cada addon apunta su propia hora de entrada (difiere unos segundos, o más si alguien volvió a
-- entrar), así que una partida son los jefes de la misma instancia con el mismo grupo, en orden,
-- hasta que cae el jefe final o pasa más de RUN_GAP sin jefes.
local function computeRuns(g)
	local learned = ns.LearnedFinalBosses and ns.LearnedFinalBosses(g) or {}
	local groups = {}
	for _, r in pairs(g.runs) do
		ns.BackgroundYield() -- trozos en segundo plano (Core.lua)
		if r.entered then
			local members = sortedMembers(r)
			local gk = ("%s|%s"):format(tostring(r.instanceID or r.instance), table.concat(members, ","))
			groups[gk] = groups[gk] or { members = members, recs = {} }
			table.insert(groups[gk].recs, r)
		end
	end
	local list = {}
	for gk, grp in pairs(groups) do
		ns.BackgroundYield() -- trozos en segundo plano (Core.lua)
		table.sort(grp.recs, function(a, b) return a.t < b.t end)
		local run
		for _, r in ipairs(grp.recs) do
			local entered = r.entered or r.t
			if not run or r.t - run.t > RUN_GAP or (run.finished and entered > run.finalT) then
				run = { instance = r.instance, instanceID = r.instanceID, start = r.started or entered, t = r.t, bosses = {}, recKeys = {},
					members = grp.members, guildMembers = r.guildMembers or {}, guildCount = r.guildCount or 0, size = r.size or #grp.members, raid = r.raid, witnesses = 0,
					gold = 0, deaths = 0, loot = {}, reporters = {} }
				run.key = gk .. "|" .. r.t
				list[#list + 1] = run
			end
			run.recKeys[r.key] = true
			local start = r.started or entered
			if start < run.start then run.start = start end
			if r.t > run.t then run.t = r.t end
			local w = 0
			for _ in pairs(r.witnesses or {}) do w = w + 1 end
			if w > run.witnesses then run.witnesses = w end
			local dungeon = not r.raid and ns.RunDungeonName(r, learned)
			if dungeon then
				run.dungeon, run.finished = dungeon, true
				if not run.finalT or r.t < run.finalT then run.finalT = r.t end
			end
			run.bosses[#run.bosses + 1] = { boss = r.boss, t = r.t, encounterID = r.encounterID, final = dungeon and true or nil }
		end
	end
	-- Resumen de cada miembro (oro, muertes, botín; Dungeon.lua): a la partida de la misma
	-- instancia y grupo en la que encaja su hora de entrada.
	for _, st in pairs(g.runStats or {}) do
		ns.BackgroundYield() -- trozos en segundo plano (Core.lua)
		local members = {}
		for _, m in ipairs(st.members or {}) do members[#members + 1] = m end
		table.sort(members)
		for _, run in ipairs(list) do
			if run.instanceID == st.instanceID and st.entered >= run.start - RUN_GAP and st.entered <= run.t and ns.SameMembers(run.members, members) then
				if not run.reporters[st.reporter] then
					run.reporters[st.reporter] = true
					run.gold, run.deaths = run.gold + (st.gold or 0), run.deaths + (st.deaths or 0)
					for _, x in ipairs(st.loot or {}) do
						local dup = false
						for _, y in ipairs(run.loot) do if y.id == x.id and y.who == x.who then dup = true end end
						if not dup then run.loot[#run.loot + 1] = x end
					end
				end
				break
			end
		end
	end
	for _, run in ipairs(list) do
		-- El mismo jefe visto por el aviso de encuentro y por la estadística: uno solo.
		local seen, bosses = {}, {}
		for _, b in ipairs(run.bosses) do
			local id = b.final and "final" or tostring(b.encounterID or b.boss)
			if not seen[id] then
				seen[id] = true
				b.split = b.t - run.start
				bosses[#bosses + 1] = b
			elseif b.final then
				for _, x in ipairs(bosses) do if x.final then x.boss = x.boss or b.boss end end
			end
		end
		run.bosses = bosses
		if run.finished then
			run.duration = run.finalT - run.start
			if run.duration <= 60 or run.duration >= 6 * 3600 then run.finished, run.duration = false, nil end
		end
		run.dungeon = run.dungeon or run.instance or "?"
		run.official = officialAttempt(g, run)
		-- Sin muertes: terminada, ninguna muerte, y han mandado su resumen todos los de la hermandad.
		local all = #run.guildMembers > 0
		for _, m in ipairs(run.guildMembers) do if not run.reporters[m] then all = false end end
		run.allReported = all
		run.flawless = run.finished and all and run.deaths == 0 or false
		table.sort(run.loot, function(a, b) if a.q ~= b.q then return a.q > b.q end return a.id < b.id end)
	end
	table.sort(list, function(a, b) return a.t > b.t end)
	return list
end

-- Rendimiento: la vista de Récords, los logros, la temporada y las tribus la piden varias veces
-- por refresco; se calcula una vez y vale hasta que cambian los datos (LG:DataChanged) o, como
-- red de seguridad, pasan RUNS_TTL segundos.
local RUNS_TTL = 30
local runsCache = {}
function ns.InvalidateRuns() runsCache.dirty = true end
function ns.DungeonRuns()
	local g = LG:GuildData()
	if not g then return {} end
	local now = GetTime and GetTime() or 0
	if runsCache.g == g and runsCache.list and not runsCache.dirty and now - runsCache.at < RUNS_TTL then return runsCache.list end
	local list = computeRuns(g)
	runsCache = { g = g, list = list, at = now }
	return list
end

-- Historial: partidas con al menos TIMES_MIN_GUILD de la hermandad, la más reciente primero.
function ns.DungeonHistory(max)
	local list = {}
	for _, run in ipairs(ns.DungeonRuns()) do
		if not run.raid and run.guildCount >= ns.TIMES_MIN_GUILD then
			list[#list + 1] = run
			if max and #list >= max then break end
		end
	end
	return list
end

-- Récords: { { dungeon, runs = { partidas oficiales terminadas, la más rápida primero } } },
-- la mazmorra con el récord más rápido primero. (Faction.lua usa guildGroup = oficial.)
function ns.DungeonTimes()
	local byDungeon = {}
	for _, run in ipairs(ns.DungeonRuns()) do
		if run.official and run.finished and not run.raid then
			run.guildGroup = run.witnesses >= 2
			byDungeon[run.dungeon] = byDungeon[run.dungeon] or {}
			table.insert(byDungeon[run.dungeon], run)
		end
	end
	local list = {}
	for name, runs in pairs(byDungeon) do
		table.sort(runs, function(a, b) return a.duration < b.duration end)
		list[#list + 1] = { dungeon = name, runs = runs }
	end
	table.sort(list, function(a, b) return a.runs[1].duration < b.runs[1].duration end)
	return list
end

-- Récord oficial de una instancia (por su ID, igual en todos los idiomas), sin contar la partida
-- que contiene el registro exceptRec (la que está en curso), o nil.
function ns.DungeonRecordByInstance(instanceID, exceptRec)
	local best
	for _, d in ipairs(ns.DungeonTimes()) do
		for _, run in ipairs(d.runs) do
			if run.instanceID == instanceID and not run.recKeys[exceptRec or ""] and (not best or run.duration < best.duration) then best = run end
		end
	end
	return best
end

-- Parcial del récord en el jefe de este registro (mismo encuentro o mismo nombre), o nil.
function ns.RunSplit(record, rec)
	for _, b in ipairs(record.bosses or {}) do
		if (rec.encounterID and b.encounterID == rec.encounterID) or (b.boss and b.boss == rec.boss) then return b.split end
	end
	return nil
end

-- Arte de cada mazmorra para las tarjetas de JcE: las pantallas de carga del propio juego (nada
-- de otros addons), por ID de instancia (igual en todos los idiomas). { ruta(s) o fileID, aspecto }.
-- Las de Forever son panorámicas; las clásicas, 4:3. Si el cliente no tiene ninguna, sin arte.
local LS = "Interface\\Glues\\LoadingScreens\\"
local DUNGEON_ART = {
	[389] = { LS .. "LoadScreenRagefireChasm", 4 / 3 },
	[43] = { LS .. "LoadScreenWailingCaverns", 4 / 3 },
	[33] = { LS .. "LoadScreenShadowFangKeep", 4 / 3 },
	[36] = { LS .. "LoadScreenDeadmines", 4 / 3 },
	[48] = { LS .. "LoadScreenBlackFathomDeeps", 4 / 3 },
	[34] = { 131870, 4 / 3 },  -- Las Mazmorras de Ventormenta
	[90] = { LS .. "LoadScreenGnomeregan", 4 / 3 },
	[47] = { 131865, 4 / 3 },  -- Horado Rajacieno
	[129] = { { LS .. "LoadScreenRazorfenDowns", LS .. "LoadScreenRazorfenDown", 131865 }, 4 / 3 },
	[189] = { { LS .. "LoadScreenScarletMonastery", LS .. "LoadScreenMonastery", LS .. "LoadScreenScarletMonastery2" }, 4 / 3 },
	[70] = { LS .. "LoadScreenUldaman", 4 / 3 },
	[209] = { { LS .. "LoadScreenZulFarrak", LS .. "LoadScreenZulfarrak" }, 4 / 3 },
	[2998] = { 7963777, 16 / 9 }, -- Excavación: Los Humedales (Forever)
	[2959] = { 7963775, 16 / 9 }, -- Ciudad de Dalaran (Forever)
}
local artCache = {}
local function fileExists(p)
	if type(p) == "number" then return true end
	if not GetFileIDFromPath then return true end
	local ok, id = pcall(GetFileIDFromPath, p)
	return ok and id ~= nil
end
-- { texture, aspect } del arte de una instancia, o nil.
function ns.DungeonArt(instanceID)
	if not instanceID then return nil end
	if artCache[instanceID] ~= nil then return artCache[instanceID] or nil end
	local def = DUNGEON_ART[instanceID]
	local found = false
	if def then
		local list = type(def[1]) == "table" and def[1] or { def[1] }
		for _, p in ipairs(list) do
			if fileExists(p) then found = { texture = p, aspect = def[2] } break end
		end
	end
	artCache[instanceID] = found
	return found or nil
end

function ns.FormatRunTime(seconds)
	if seconds >= 3600 then
		return ("%d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), math.floor(seconds % 60))
	end
	return ("%d:%02d"):format(math.floor(seconds / 60), math.floor(seconds % 60))
end
