-- Tribus: grupos estables dentro de la hermandad (3 a 10 jugadores que suelen
-- jugar juntos), con nombre propio.
--
--   1. Alguien propone la tribu: nombre y miembros (él incluido).
--   2. Cada miembro acepta (nadie entra en una tribu sin querer).
--   3. Un oficial la aprueba o la rechaza; también puede disolverla.
--   Cualquiera puede salirse. Solo se puede estar en una tribu.
--   El líder (quien la propuso; si se sale, el siguiente) invita a más miembros
--   sin oficial: el invitado acepta y entra.
--
-- Se llama "tribu" en la Horda y "clan" en la Alianza (ns.TribeWords).
--
-- La tribu "juega junta" cuando hay 3 o más de sus miembros en el mismo grupo:
-- se ve en Ahora, en los tiempos de mazmorra, en las guerras y en su clasificación.
-- Es solo prestigio: no da insignias ni reputación.
--
--   TRIBE      la tribu (propuesta y decisiones de oficial), con "rev"
--   TRIBEACC   un miembro acepta
--   TRIBELEFT  un miembro se sale
--   TRIBEINV   el líder invita a alguien más
local _, ns = ...
local L = ns.L
local LG = ns.LG

local MIN_MEMBERS, MAX_MEMBERS = 3, 10

---------------------------------------------------------------------------
-- Iconos: los de Guildmark (Media/Tribes, 12 por facción) o uno del juego (su
-- número de archivo, elegido en el selector). Al crear la tribu le toca uno de
-- su facción al azar; el líder (o un oficial) lo puede cambiar.
---------------------------------------------------------------------------

ns.TRIBE_ICONS = { Horde = {}, Alliance = {} }
for i = 1, 12 do
	table.insert(ns.TRIBE_ICONS.Horde, ("horde_%02d"):format(i))
	table.insert(ns.TRIBE_ICONS.Alliance, ("alliance_%02d"):format(i))
end
local CUSTOM = {}
for _, list in pairs(ns.TRIBE_ICONS) do
	for _, key in ipairs(list) do CUSTOM[key] = true end
end

-- Un icono válido: uno de los nuestros o un número de archivo del juego.
function ns.ValidTribeIcon(icon)
	if type(icon) == "string" then return CUSTOM[icon] == true end
	return type(icon) == "number" and icon > 0 and icon < 100000000 and icon == math.floor(icon)
end

-- Textura para pintarlo y si es de los nuestros (sin marco ni recorte: ya trae el suyo).
function ns.TribeIconTexture(icon)
	if type(icon) == "string" and CUSTOM[icon] then return ns.MEDIA .. "Tribes\\" .. icon, true end
	if type(icon) == "number" then return icon, false end
	return "Interface\\Icons\\Spell_Nature_Bloodlust", false
end

local function myFaction()
	return (UnitFactionGroup and UnitFactionGroup("player") == "Alliance") and "Alliance" or "Horde"
end

-- Icono de una tribu: el elegido o, si no tiene, uno fijo de su facción sacado de su id.
function ns.TribeIcon(tribe)
	local g = LG:GuildData()
	local chosen = g and g.tribeIcons and g.tribeIcons[tribe.id]
	if chosen and ns.ValidTribeIcon(chosen.icon) then return chosen.icon end
	if ns.ValidTribeIcon(tribe.icon) then return tribe.icon end
	local list = ns.TRIBE_ICONS[myFaction()]
	local h = 0
	for i = 1, #tribe.id do h = (h * 31 + tribe.id:byte(i)) % 1000003 end
	return list[h % #list + 1]
end

function ns.MergeTribeIcon(g, rec, sender)
	if type(rec) ~= "table" or type(rec.tribe) ~= "string" or type(rec.by) ~= "string" or type(rec.t) ~= "number" then return false end
	if sender and rec.by ~= sender then return false end
	local tribe = g.tribes[rec.tribe]
	if not tribe or not ns.ValidTribeIcon(rec.icon) then return false end
	if ns.TribeLeader(g, tribe) ~= rec.by and not ns.CanManageEvents(rec.by) then return false end
	local old = g.tribeIcons[rec.tribe]
	if old and (old.t or 0) >= rec.t then return false end
	g.tribeIcons[rec.tribe] = { icon = rec.icon, by = rec.by, t = rec.t }
	return true
end

function ns.SetTribeIcon(id, icon)
	local g = LG:GuildData()
	if not g or not g.tribes[id] then return end
	local old = g.tribeIcons[id]
	local rec = { tribe = id, icon = icon, by = ns.PlayerFullName(), t = math.max(ns.Now(), old and (old.t or 0) + 1 or 0) }
	if ns.MergeTribeIcon(g, rec) then
		LG:Send("TRIBEICON", rec)
		LG:DataChanged()
	end
end
local TOGETHER = 3
ns.TRIBE_MIN, ns.TRIBE_MAX, ns.TRIBE_TOGETHER = MIN_MEMBERS, MAX_MEMBERS, TOGETHER

-- Máximo de miembros: 10, o 12 desde el nivel 7 de hermandad.
local function maxMembers()
	local perks = ns.GuildPerks and ns.GuildPerks()
	return (perks and perks.tribe12) and 12 or MAX_MEMBERS
end
ns.TribeMax = maxMembers

local function count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

local function plain(s)
	s = (s or ""):lower()
	for from, to in pairs({ ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ü"] = "u", ["ñ"] = "n" }) do s = s:gsub(from, to) end
	return strtrim(s)
end

local function cleanName(name)
	name = type(name) == "string" and strtrim(name:gsub("|", "")) or ""
	return name:sub(1, 24)
end

-- Palabras según la facción: "tribu" en la Horda, "clan" en la Alianza.
-- { one, One, the, The, many, Many }
function ns.TribeWords()
	if UnitFactionGroup and UnitFactionGroup("player") == "Alliance" then
		return { one = L["clan"], One = L["Clan"], the = L["el clan"], The = L["El clan"], many = L["clanes"], Many = L["Clanes"] }
	end
	return { one = L["tribu"], One = L["Tribu"], the = L["la tribu"], The = L["La tribu"], many = L["tribus"], Many = L["Tribus"] }
end

---------------------------------------------------------------------------
-- Estado de cada tribu y de cada miembro
---------------------------------------------------------------------------

-- Miembros efectivos: en la lista o invitados, que aceptaron después de su
-- última salida (así quien se fue puede volver si le invitan otra vez).
function ns.TribeMembers(g, tribe)
	local list = {}
	local acc = g.tribeAccepts[tribe.id] or {}
	local left = g.tribeLeft[tribe.id] or {}
	local candidates = {}
	for name in pairs(tribe.members or {}) do candidates[name] = true end
	for name in pairs(g.tribeInvites[tribe.id] or {}) do candidates[name] = true end
	for name in pairs(candidates) do
		local accepted = acc[name] or (name == tribe.creator and (tribe.t or 0)) or nil
		if accepted and accepted >= (left[name] or -1) then list[#list + 1] = name end
	end
	table.sort(list)
	return list
end

-- Líder: quien la propuso; si ya no está, el primer miembro por orden.
function ns.TribeLeader(g, tribe)
	local members = ns.TribeMembers(g, tribe)
	for _, m in ipairs(members) do
		if m == tribe.creator then return m end
	end
	return members[1]
end

-- Una tribu cuenta si está aprobada y le quedan al menos 3 miembros.
local function isActive(g, tribe)
	return tribe.status == "approved" and #ns.TribeMembers(g, tribe) >= MIN_MEMBERS
end

function ns.ActiveTribes()
	local g = LG:GuildData()
	local list = {}
	if not g then return list end
	for _, tribe in pairs(g.tribes) do
		if isActive(g, tribe) then list[#list + 1] = tribe end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

-- Tribu (aprobada) de un jugador, o nil.
function ns.TribeOf(name)
	local g = LG:GuildData()
	if not g then return nil end
	for _, tribe in pairs(g.tribes) do
		if isActive(g, tribe) then
			for _, m in ipairs(ns.TribeMembers(g, tribe)) do
				if m == name then return tribe end
			end
		end
	end
	return nil
end

-- Tribu que juega junta en una lista de jugadores (3 o más de sus miembros).
function ns.TribeTogether(names)
	local g = LG:GuildData()
	if not g or type(names) ~= "table" then return nil end
	local present = {}
	for _, n in ipairs(names) do present[n] = true end
	for _, tribe in ipairs(ns.ActiveTribes()) do
		local n = 0
		for _, m in ipairs(ns.TribeMembers(g, tribe)) do
			if present[m] then n = n + 1 end
		end
		if n >= TOGETHER then return tribe, n end
	end
	return nil
end

---------------------------------------------------------------------------
-- Fusión
---------------------------------------------------------------------------

function ns.MergeTribe(g, rec, sender)
	if type(rec) ~= "table" or type(rec.id) ~= "string" or type(rec.rev) ~= "number" or type(rec.by) ~= "string" then return false end
	if sender and rec.by ~= sender then return false end
	local old = g.tribes[rec.id]
	if old and old.rev >= rec.rev then return false end
	if old then
		-- Solo cambia el estado, y solo un oficial.
		if rec.name ~= old.name or rec.creator ~= old.creator then return false end
		if not ns.CanManageEvents(rec.by) then return false end
		if rec.status ~= "approved" and rec.status ~= "rejected" and rec.status ~= "dissolved" then return false end
		local new = {}
		for k, v in pairs(old) do new[k] = v end
		new.status, new.rev, new.by, new.decidedBy, new.decidedAt = rec.status, rec.rev, rec.by, rec.by, rec.t
		g.tribes[rec.id] = new
		return true, old
	end
	-- Tribu que no conocía: una propuesta nueva (la hace uno de sus miembros) o,
	-- por la sincronización, una ya decidida (la decidió un oficial).
	local name = cleanName(rec.name)
	if name == "" or type(rec.members) ~= "table" or type(rec.creator) ~= "string" or not rec.members[rec.creator] then return false end
	local n = count(rec.members)
	if n < MIN_MEMBERS or n > maxMembers() then return false end
	if rec.status == "pending" then
		if rec.rev ~= 1 or rec.creator ~= rec.by then return false end
	elseif rec.status == "approved" or rec.status == "rejected" or rec.status == "dissolved" then
		if not ns.CanManageEvents(rec.decidedBy or rec.by) then return false end
	else
		return false
	end
	g.tribes[rec.id] = { id = rec.id, name = name, members = rec.members, creator = rec.creator, status = rec.status,
		rev = rec.rev, by = rec.by, decidedBy = rec.decidedBy, decidedAt = rec.decidedAt, t = rec.t, test = rec.test,
		icon = ns.ValidTribeIcon(rec.icon) and rec.icon or nil }
	return true, nil
end

-- Modo prueba: un miembro de los datos de ejemplo (no es un jugador de verdad).
local function sampleMember(g, name)
	local m = LG:InTestMode() and g.members[name]
	return m and m.test and not ns.roster[name] and true or false
end

function ns.MergeTribeAccept(g, rec, sender)
	if type(rec) ~= "table" or type(rec.tribe) ~= "string" or type(rec.member) ~= "string" then return false end
	-- Cada uno acepta lo suyo; en modo prueba, los de ejemplo aceptan por boca de quien les propone.
	if sender and rec.member ~= sender and not (rec.sim and sampleMember(g, rec.member)) then return false end
	local tribe = g.tribes[rec.tribe]
	if not tribe then return false end
	if not tribe.members[rec.member] and not (g.tribeInvites[rec.tribe] or {})[rec.member] then return false end
	g.tribeAccepts[rec.tribe] = g.tribeAccepts[rec.tribe] or {}
	local t = rec.t or ns.Now()
	if (g.tribeAccepts[rec.tribe][rec.member] or -1) >= t then return false end
	g.tribeAccepts[rec.tribe][rec.member] = t
	return true
end

function ns.MergeTribeLeft(g, rec, sender)
	if type(rec) ~= "table" or type(rec.tribe) ~= "string" or type(rec.member) ~= "string" then return false end
	if sender and rec.member ~= sender then return false end
	local tribe = g.tribes[rec.tribe]
	if not tribe then return false end
	if not tribe.members[rec.member] and not (g.tribeInvites[rec.tribe] or {})[rec.member] then return false end
	g.tribeLeft[rec.tribe] = g.tribeLeft[rec.tribe] or {}
	local t = rec.t or ns.Now()
	if (g.tribeLeft[rec.tribe][rec.member] or -1) >= t then return false end
	g.tribeLeft[rec.tribe][rec.member] = t
	return true
end

-- Invitación del líder a una tribu aprobada: hasta 10, una tribu por jugador.
function ns.MergeTribeInvite(g, rec, sender)
	if type(rec) ~= "table" or type(rec.tribe) ~= "string" or type(rec.member) ~= "string" or type(rec.by) ~= "string" then return false end
	if sender and rec.by ~= sender then return false end
	local tribe = g.tribes[rec.tribe]
	if not tribe or tribe.status ~= "approved" or ns.TribeLeader(g, tribe) ~= rec.by then return false end
	if #ns.TribeMembers(g, tribe) >= maxMembers() then return false end
	local other = ns.TribeOf(rec.member)
	if other and other.id ~= rec.tribe then return false end
	g.tribeInvites[rec.tribe] = g.tribeInvites[rec.tribe] or {}
	local t = rec.t or ns.Now()
	local old = g.tribeInvites[rec.tribe][rec.member]
	if old and (old.t or 0) >= t then return false end
	g.tribeInvites[rec.tribe][rec.member] = { t = t, by = rec.by }
	return true
end

local function notify(tribe, old)
	local me = ns.PlayerFullName()
	if not tribe.members[me] then return end
	local W = ns.TribeWords()
	if not old and tribe.creator ~= me then
		LG:Print((L["%s te propone para %s «%s». Acepta en /gmk > Hermandad > %s."]):format(ns.ShortName(tribe.creator), W.the, tribe.name, W.Many))
	elseif old and tribe.status == "approved" and old.status ~= "approved" then
		LG:Print((L["Un oficial ha aprobado %s «%s»."]):format(W.the, tribe.name))
	elseif old and tribe.status == "rejected" and old.status ~= "rejected" then
		LG:Print((L["Un oficial ha rechazado %s «%s»."]):format(W.the, tribe.name))
	elseif old and tribe.status == "dissolved" and old.status ~= "dissolved" then
		LG:Print((L["Un oficial ha disuelto %s «%s»."]):format(W.the, tribe.name))
	end
end

local function handler(merge, after)
	return function(sender, rec)
		local g = LG:GuildData()
		if not g then return end
		local changed, old = merge(g, rec, sender)
		if changed then
			if after then after(g.tribes[rec.id], old) end
			LG:DataChanged()
		end
	end
end
ns.handlers.TRIBE = handler(ns.MergeTribe, notify)
ns.handlers.TRIBEACC = handler(ns.MergeTribeAccept)
ns.handlers.TRIBEICON = handler(ns.MergeTribeIcon)
ns.handlers.TRIBELEFT = handler(ns.MergeTribeLeft)
ns.handlers.TRIBEINV = function(sender, rec)
	local g = LG:GuildData()
	if g and ns.MergeTribeInvite(g, rec, sender) then
		if rec.member == ns.PlayerFullName() then
			LG:Print((L["%s te invita a «%s». Acepta en /gmk > Hermandad > %s."]):format(ns.ShortName(rec.by), g.tribes[rec.tribe].name, ns.TribeWords().Many))
		end
		LG:DataChanged()
	end
end

---------------------------------------------------------------------------
-- Acciones
---------------------------------------------------------------------------

-- Modo prueba: los miembros de ejemplo aceptan solos a los pocos segundos.
local Tribes = LG:NewModule("Tribes", "AceTimer-3.0")
local function simulateAccepts(id, names)
	if not LG:InTestMode() then return end
	Tribes:ScheduleTimer(function()
		local g = LG:GuildData()
		if not g or not g.tribes[id] then return end
		for name in pairs(names) do
			if sampleMember(g, name) then
				local rec = { tribe = id, member = name, t = ns.Now(), sim = true }
				if ns.MergeTribeAccept(g, rec) then LG:Send("TRIBEACC", rec) end
			end
		end
		LG:DataChanged()
	end, 3)
end

-- members: lista de nombres (sin contar al que propone). Devuelve un error o nil.
function ns.ProposeTribe(name, members)
	local g = LG:GuildData()
	if not g then return L["No estás en una hermandad."] end
	local me = ns.PlayerFullName()
	name = cleanName(name)
	if name == "" then return L["Ponle un nombre."] end
	for _, tribe in pairs(g.tribes) do
		if tribe.status ~= "rejected" and tribe.status ~= "dissolved" and plain(tribe.name) == plain(name) then
			return L["Ese nombre ya está cogido en la hermandad."]
		end
	end
	local set = { [me] = true }
	for _, m in ipairs(members or {}) do
		local full = ns.FindMember(m)
		if not full then return (L["No encuentro a %s en la hermandad."]):format(m) end
		set[full] = true
	end
	local n = count(set)
	if n < MIN_MEMBERS or n > maxMembers() then return (L["Tienen que ser de %d a %d miembros, contándote a ti."]):format(MIN_MEMBERS, maxMembers()) end
	for m in pairs(set) do
		local other = ns.TribeOf(m)
		if other then return (L["%s ya pertenece a «%s»."]):format(ns.ShortName(m), other.name) end
	end
	-- Tasa de fundación (Shop.lua): se cobra al proponerla; si un oficial la rechaza, no.
	local fee = ns.ShopItem and ns.ShopItem("tribeCreate")
	if fee and ns.AvailableInsignias(nil) < fee.price then
		return (L["Fundar una tribu cuesta %d insignias y tienes %d libres."]):format(fee.price, ns.AvailableInsignias(nil))
	end
	local icons = ns.TRIBE_ICONS[myFaction()]
	local rec = { id = ("%s:%d"):format(me, ns.Now()), name = name, members = set, creator = me, status = "pending",
		rev = 1, by = me, t = ns.Now(), icon = icons[math.random(#icons)] }
	ns.MergeTribe(g, rec)
	LG:Send("TRIBE", rec)
	if fee then ns.Buy("tribeCreate", rec.id) end
	LG:DataChanged()
	simulateAccepts(rec.id, set)
	LG:Print((L["«%s» propuesta: falta que acepten sus miembros y la aprobación de un oficial."]):format(name))
	return nil
end

function ns.AcceptTribe(id)
	local g = LG:GuildData()
	local rec = { tribe = id, member = ns.PlayerFullName(), t = ns.Now() }
	if g and ns.MergeTribeAccept(g, rec) then
		LG:Send("TRIBEACC", rec)
		LG:DataChanged()
	end
end

-- El líder invita a alguien de la hermandad. Devuelve un error o nil.
function ns.InviteTribe(id, name)
	local g = LG:GuildData()
	local tribe = g and g.tribes[id]
	if not tribe then return nil end
	local me = ns.PlayerFullName()
	if ns.TribeLeader(g, tribe) ~= me then return L["Solo el líder puede invitar."] end
	local full = ns.FindMember(name or "")
	if not full then return (L["No encuentro a %s en la hermandad."]):format(name or "?") end
	if #ns.TribeMembers(g, tribe) >= maxMembers() then return (L["Ya sois %d, el máximo."]):format(maxMembers()) end
	local other = ns.TribeOf(full)
	if other then return (L["%s ya pertenece a «%s»."]):format(ns.ShortName(full), other.name) end
	local rec = { tribe = id, member = full, by = me, t = ns.Now() }
	if ns.MergeTribeInvite(g, rec) then
		LG:Send("TRIBEINV", rec)
		LG:DataChanged()
		simulateAccepts(id, { [full] = true })
		LG:Print((L["Has invitado a %s a «%s»."]):format(ns.ShortName(full), tribe.name))
	end
	return nil
end

-- Invitaciones a tribus aprobadas que tengo pendientes de aceptar.
function ns.MyTribeInvites()
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	local list = {}
	if not g then return list end
	for id, invites in pairs(g.tribeInvites) do
		local inv = invites[me]
		local tribe = g.tribes[id]
		if inv and tribe and tribe.status == "approved" then
			local acc = (g.tribeAccepts[id] or {})[me] or -1
			local left = (g.tribeLeft[id] or {})[me] or -1
			if acc < inv.t and left < inv.t then list[#list + 1] = { tribe = tribe, by = inv.by, t = inv.t } end
		end
	end
	return list
end

function ns.LeaveTribe(id)
	local g = LG:GuildData()
	local rec = { tribe = id, member = ns.PlayerFullName(), t = ns.Now() }
	if g and ns.MergeTribeLeft(g, rec) then
		LG:Send("TRIBELEFT", rec)
		LG:DataChanged()
	end
end

-- status: "approved" | "rejected" | "dissolved" (oficiales).
function ns.DecideTribe(id, status)
	local g = LG:GuildData()
	local tribe = g and g.tribes[id]
	if not tribe then return end
	local rec = { id = id, name = tribe.name, creator = tribe.creator, status = status, rev = tribe.rev + 1, by = ns.PlayerFullName(), t = ns.Now() }
	local changed, old = ns.MergeTribe(g, rec)
	if changed then
		LG:Send("TRIBE", rec)
		notify(g.tribes[id], old)
		LG:DataChanged()
		if status == "approved" then ns.GuildAnnounce((L["Nueva tribu en la hermandad: «%s»."]):format(tribe.name)) end
	end
end

---------------------------------------------------------------------------
-- Clasificación de tribus
---------------------------------------------------------------------------

-- { tribe, members, dungeons, best (segundos), events, kills }, de más a menos mazmorras.
function ns.TribeStats()
	local g = LG:GuildData()
	local list = {}
	if not g then return list end
	for _, tribe in ipairs(ns.ActiveTribes()) do
		local members = ns.TribeMembers(g, tribe)
		local set = {}
		for _, m in ipairs(members) do set[m] = true end
		local function together(names)
			local n = 0
			for _, m in ipairs(names or {}) do if set[m] then n = n + 1 end end
			return n >= TOGETHER
		end
		local s = { tribe = tribe, members = members, dungeons = 0, events = 0, kills = 0 }
		local days = {}
		for _, r in pairs(g.runs) do
			if together(r.members) then
				local key = ("%s|%d"):format(tostring(r.instanceID or r.instance), math.floor(r.t / 86400))
				if not days[key] then days[key] = true; s.dungeons = s.dungeons + 1 end
			end
		end
		for _, d in ipairs(ns.DungeonTimes and ns.DungeonTimes() or {}) do
			for _, run in ipairs(d.runs) do
				if together(run.members) and (not s.best or run.duration < s.best) then s.best = run.duration end
			end
		end
		for eventID, list2 in pairs(g.attendance) do
			local names = {}
			for m in pairs(list2) do names[#names + 1] = m end
			if together(names) then s.events = s.events + 1 end
		end
		for _, k in pairs(g.kills) do
			if k.kind == "kill" and k.honorable and set[k.killerName or ""] and not ns.IsVoided(g, k.id) then s.kills = s.kills + 1 end
		end
		list[#list + 1] = s
	end
	table.sort(list, function(a, b)
		if a.dungeons ~= b.dungeons then return a.dungeons > b.dungeons end
		return a.kills > b.kills
	end)
	return list
end
