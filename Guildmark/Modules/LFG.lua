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

-- { { dungeon, runs = { { duration, t, members, guildCount } } } }, mejor tiempo primero.
function ns.DungeonTimes()
	local g = LG:GuildData()
	local byDungeon = {}
	if not g then return {} end
	for _, r in pairs(g.runs) do
		-- La mazmorra: por el jefe final entre los muertos o, en Forever (donde el aviso del jefe
		-- llega sin criatura), por la estadística de jefe final que subió (Legacy.lua).
		local stat = r.finalStat and ns.FINAL_BOSS_STATS and ns.FINAL_BOSS_STATS[r.finalStat]
		local name = not r.raid and r.entered and (finalBossDungeon(r) or (stat and stat.dungeon))
		local duration = name and (r.t - r.entered)
		if duration and duration > 60 and duration < 6 * 3600 then
			byDungeon[name] = byDungeon[name] or {}
			table.insert(byDungeon[name], { duration = duration, t = r.t, members = r.members or {}, guildCount = r.guildCount or 0 })
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

function ns.FormatRunTime(seconds)
	if seconds >= 3600 then
		return ("%d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), math.floor(seconds % 60))
	end
	return ("%d:%02d"):format(math.floor(seconds / 60), math.floor(seconds % 60))
end
