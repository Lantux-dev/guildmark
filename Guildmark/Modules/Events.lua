-- Eventos de hermandad: los oficiales los crean, los miembros se apuntan con
-- su rol y el addon confirma la asistencia real durante el evento.
--
-- Fase 1: eventos propios del addon (se pueden probar en modo prueba).
-- Fase 2, pendiente: enlazar con el calendario de hermandad de Blizzard
-- (C_Calendar existe en Forever; hay que probarlo dentro de una hermandad).
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Events = LG:NewModule("Events", "AceEvent-3.0", "AceTimer-3.0")

-- Rango máximo que cuenta como oficial (0 = maestro de hermandad). Por defecto
-- 0 y 1; el maestro de hermandad lo cambia en Oficial (ajuste "officerMaxRank").
local OFFICER_MAX_RANK = 1

function ns.OfficerMaxRank()
	local v = ns.GuildSetting and ns.GuildSetting("officerMaxRank", OFFICER_MAX_RANK) or OFFICER_MAX_RANK
	return type(v) == "number" and v or OFFICER_MAX_RANK
end
local EVENT_TTL = 30 * 86400        -- se borran 30 días después de empezar
local ATTEND_FROM = -10 * 60        -- la asistencia cuenta desde 10 min antes...
local ATTEND_UNTIL = 3 * 3600       -- ...hasta 3 h después de la hora de inicio
local REMIND_BEFORE = 15 * 60
local MIN_GUILD_IN_GROUP = 2        -- tú y al menos otro miembro de la hermandad
ns.ATTEND_FROM, ns.ATTEND_UNTIL = ATTEND_FROM, ATTEND_UNTIL -- para los avisos de Integrity.lua

ns.EVENT_KINDS = {
	{ key = "raid", label = L["Raid"], comp = { tank = 2, healer = 5, dps = 13 } },
	{ key = "dungeon", label = L["Mazmorra"], comp = { tank = 1, healer = 1, dps = 3 } },
	{ key = "pvp", label = L["PvP"], comp = { tank = 0, healer = 2, dps = 8 } },
	{ key = "social", label = L["Social"], comp = { tank = 0, healer = 0, dps = 0 } },
}
ns.EVENT_KIND_LABEL = {}
for _, k in ipairs(ns.EVENT_KINDS) do ns.EVENT_KIND_LABEL[k.key] = k.label end

ns.ROLES = {
	{ key = "tank", label = L["Tanque"] },
	{ key = "healer", label = L["Sanador"] },
	{ key = "dps", label = L["DPS"] },
}

-- Rango del juego de un miembro (0 = maestro de hermandad). En modo prueba no hay
-- rangos: todos son 0 salvo tú, que puedes simular uno en Ajustes para probar.
function ns.RankIndexOf(name)
	name = name or ns.PlayerFullName()
	if LG:InTestMode() then
		return name == ns.PlayerFullName() and (tonumber(LG.db.profile.testRank) or 0) or 0
	end
	local r = ns.roster[name]
	return r and r.rankIndex
end

-- Oficiales: los rangos hasta el que elija el maestro de hermandad.
function ns.CanManageEvents(name)
	local idx = ns.RankIndexOf(name)
	return idx ~= nil and idx <= ns.OfficerMaxRank()
end

-- Permisos: para cada cosa, el rango mínimo que la puede hacer (por defecto, los oficiales).
-- Los cambia el maestro de hermandad en Ajustes (ajustes "perm:<clave>").
ns.PERMISSIONS = {
	{ key = "events", label = L["Crear y gestionar eventos"] },
	{ key = "bankAuction", label = L["Subastar objetos del banco"] },
	{ key = "projects", label = L["Proyectos del cofre"] },
	{ key = "bankRequests", label = L["Pedidos del banco"] },
	{ key = "adjust", label = L["Ajustar puntos, anular registros y objetivos"] },
}

function ns.PermissionRank(perm)
	local v = ns.GuildSetting and ns.GuildSetting("perm:" .. perm)
	return type(v) == "number" and v or ns.OfficerMaxRank()
end

function ns.Can(perm, name)
	local idx = ns.RankIndexOf(name)
	if idx == nil then return false end
	return idx == 0 or idx <= ns.PermissionRank(perm)
end

-- Rangos del juego: cuántos hay y cómo se llaman (en modo prueba, unos de ejemplo).
local TEST_RANKS = { L["Maestro"], L["Oficial"], L["Veterano"], L["Miembro"], L["Recluta"] }
function ns.GuildRankCount()
	if LG:InTestMode() then return #TEST_RANKS end
	local ok, n = pcall(GuildControlGetNumRanks)
	return ok and tonumber(n) or 10
end
function ns.GuildRankName(index)
	if LG:InTestMode() then return TEST_RANKS[index + 1] or (L["rango %d"]):format(index) end
	if GuildControlGetRankName then
		local ok, name = pcall(GuildControlGetRankName, index + 1)
		if ok and name and name ~= "" then return name end
	end
	for _, r in pairs(ns.roster) do
		if r.rankIndex == index and r.rank then return r.rank end
	end
	return (L["rango %d"]):format(index)
end

---------------------------------------------------------------------------
-- Datos y fusión
---------------------------------------------------------------------------

function ns.MergeEvent(g, rec, sender)
	if type(rec.id) ~= "string" or type(rec.rev) ~= "number" or type(rec.start) ~= "number" then return false end
	if sender and rec.by ~= sender then return false end
	-- Crear y cancelar es cosa de oficiales (según su rango en el roster).
	if not ns.Can("events", rec.by) then return false end
	local old = g.events[rec.id]
	if old and old.rev >= rec.rev then return false end
	g.events[rec.id] = rec
	return true, old
end

-- Inscripción: cada miembro solo puede cambiar la suya.
function ns.MergeSignup(g, rec, sender)
	if type(rec.event) ~= "string" or type(rec.member) ~= "string" then return false end
	if sender and rec.member ~= sender then return false end
	local list = g.signups[rec.event]
	if not list then
		list = {}
		g.signups[rec.event] = list
	end
	local old = list[rec.member]
	if old and (old.t or 0) >= (rec.t or 0) then return false end
	list[rec.member] = { status = rec.status, role = rec.role, t = rec.t }
	return true
end

function ns.MergeAttendance(g, rec, sender)
	if type(rec.event) ~= "string" or type(rec.member) ~= "string" then return false end
	if sender and rec.member ~= sender then return false end
	local list = g.attendance[rec.event]
	if not list then
		list = {}
		g.attendance[rec.event] = list
	end
	if list[rec.member] then return false end
	list[rec.member] = rec.t
	return true
end

local function withGuild(merge, after)
	return function(sender, rec)
		local g = LG:GuildData()
		if not g then return end
		local changed, old = merge(g, rec, sender)
		if changed then
			if after then after(rec, old) end
			LG:DataChanged()
		end
	end
end

ns.handlers.EVENT = withGuild(ns.MergeEvent, function(rec, old)
	if not old and rec.status == "active" then
		LG:Print((L["Nuevo evento: %s, %s. Apúntate en /gmk > Eventos."]):format(rec.title, date("%d/%m %H:%M", rec.start)))
	elseif old and rec.status == "cancelled" and old.status ~= "cancelled" then
		LG:Print((L["Evento cancelado: %s."]):format(rec.title))
	end
end)
ns.handlers.SIGNUP = withGuild(ns.MergeSignup)
ns.handlers.ATTEND = withGuild(ns.MergeAttendance)

function ns.PruneEvents(g)
	local now = ns.Now()
	for id, e in pairs(g.events) do
		if now - (e.start or 0) > EVENT_TTL then
			g.events[id] = nil
			g.signups[id] = nil
			g.attendance[id] = nil
		end
	end
end

---------------------------------------------------------------------------
-- Acciones del jugador
---------------------------------------------------------------------------

-- fields: title, kind, start (timestamp), minLevel, comp = { tank, healer, dps }, note
function ns.CreateEvent(fields)
	local g = LG:GuildData()
	if not g or not LG:HasConsent() then return false end
	local me = ns.PlayerFullName()
	if not ns.Can("events", me) then
		LG:Print(L["Solo los oficiales pueden crear eventos."])
		return false
	end
	local now = ns.Now()
	local rec = {
		id = ("%s:%d"):format(me, now),
		t = now,
		creator = me,
		title = fields.title,
		kind = fields.kind,
		start = fields.start,
		minLevel = fields.minLevel,
		comp = fields.comp,
		note = fields.note,
		status = "active",
		rev = 1,
		by = me,
		updated = now,
	}
	g.events[rec.id] = rec
	LG:Send("EVENT", rec)
	LG:DataChanged()
	LG:Print((L["Evento creado: %s, %s."]):format(rec.title, date("%d/%m %H:%M", rec.start)))
	ns.GuildAnnounce((L["Nuevo evento: %s, %s. Apúntate en /gmk > Eventos."]):format(rec.title, date("%d/%m %H:%M", rec.start)))
	return true
end

function ns.CancelEvent(id)
	local g = LG:GuildData()
	local old = g and g.events[id]
	local me = ns.PlayerFullName()
	if not old or not ns.Can("events", me) then return end
	local rec = {}
	for k, v in pairs(old) do rec[k] = v end
	rec.status = "cancelled"
	rec.rev = old.rev + 1
	rec.by = me
	rec.updated = ns.Now()
	g.events[id] = rec
	LG:Send("EVENT", rec)
	LG:DataChanged()
end

-- status: "yes" (con role) o "no"
function ns.SignUp(eventID, status, role)
	local g = LG:GuildData()
	if not g or not g.events[eventID] or not LG:HasConsent() then return end
	local rec = { event = eventID, member = ns.PlayerFullName(), status = status, role = role, t = ns.Now() }
	ns.MergeSignup(g, rec)
	LG:Send("SIGNUP", rec)
	LG:DataChanged()
end

-- Eventos ordenados por fecha: próximos (incluido el que está en curso) y pasados.
function ns.EventLists()
	local g = LG:GuildData()
	local upcoming, past = {}, {}
	if not g then return upcoming, past end
	local now = ns.Now()
	for _, e in pairs(g.events) do
		if e.status ~= "cancelled" or now - (e.updated or 0) < 86400 then
			if (e.start or 0) + ATTEND_UNTIL >= now then upcoming[#upcoming + 1] = e else past[#past + 1] = e end
		end
	end
	table.sort(upcoming, function(a, b) return a.start < b.start end)
	table.sort(past, function(a, b) return a.start > b.start end)
	return upcoming, past
end

---------------------------------------------------------------------------
-- Asistencia y recordatorios
---------------------------------------------------------------------------

local reminded = {}

function Events:OnEnable()
	self:ScheduleRepeatingTimer("Tick", 60)
end

local function guildMatesInGroup()
	if not IsInGroup() then return 0 end
	local count = 1
	local prefix = IsInRaid() and "raid" or "party"
	local n = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
	for i = 1, n do
		local unit = prefix .. i
		if not UnitIsUnit(unit, "player") and ns.IsGuildUnit(unit) then count = count + 1 end
	end
	return count
end

function Events:Tick()
	local g = LG:GuildData()
	if not g or not LG:HasConsent() then return end
	local now = ns.Now()
	local me = ns.PlayerFullName()
	for id, e in pairs(g.events) do
		if e.status == "active" then
			local mine = g.signups[id] and g.signups[id][me]
			local untilStart = e.start - now

			if mine and mine.status == "yes" and untilStart > 0 and untilStart <= REMIND_BEFORE and not reminded[id] then
				reminded[id] = true
				local msg = (L["%s empieza en %d minutos."]):format(e.title, math.ceil(untilStart / 60))
				RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
				LG:Print(msg)
			end

			local attended = g.attendance[id] and g.attendance[id][me]
			if not attended and untilStart <= -ATTEND_FROM and -untilStart <= ATTEND_UNTIL
				and guildMatesInGroup() >= MIN_GUILD_IN_GROUP then
				local rec = { event = id, member = me, t = now }
				ns.MergeAttendance(g, rec)
				LG:Send("ATTEND", rec)
				LG:Print((L["Asistencia confirmada: %s."]):format(e.title))
				LG:DataChanged()
			end
		end
	end
end
