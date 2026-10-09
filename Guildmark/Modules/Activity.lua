-- Ahora: qué está haciendo la hermandad.
--
-- Cada addon avisa a la hermandad (ACT) cuando cambia lo que está haciendo:
-- mazmorra, banda, campo de batalla, guerra o mundo, la zona y con quién va en
-- grupo. Solo se envía al cambiar (y un recordatorio cada 5 minutos), y no se
-- guarda: es lo que pasa ahora mismo. Quien no tiene el addon aparece igual,
-- con la zona que da la lista de la hermandad del juego.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Activity = LG:NewModule("Activity", "AceEvent-3.0", "AceTimer-3.0")

local HEARTBEAT = 5 * 60
local STALE = 11 * 60  -- sin noticias en 11 minutos, se da por desconectado
local MIN_GAP = 5      -- como mucho un aviso cada 5 segundos

ns.activity = {}       -- [nombre] = { kind, zone, instance, group = { nombres }, layer, since, t }

local last, lastSent, pending = nil, 0, false

local function kindNow()
	local _, instanceType = GetInstanceInfo()
	if instanceType == "party" then return "dungeon" end
	if instanceType == "raid" then return "raid" end
	if instanceType == "pvp" or instanceType == "arena" then return "bg" end
	-- En la zona de una guerra en curso.
	local g = LG:GuildData()
	local map = ns.CurrentMap and ns.CurrentMap()
	for _, w in pairs(g and g.wars or {}) do
		if ns.WarPhase(w) == "active" and w.map and w.map == map then return "war" end
	end
	return "world"
end

-- Lo que hago ahora mismo.
function ns.MyActivity()
	local instanceName, instanceType = GetInstanceInfo()
	local group = {}
	if IsInGroup() then
		local all = ns.GroupComposition()
		for _, name in ipairs(all) do group[#group + 1] = name end
		table.sort(group)
	end
	return {
		kind = kindNow(),
		zone = GetZoneText and GetZoneText() or nil,
		instance = (instanceType == "party" or instanceType == "raid" or instanceType == "pvp") and instanceName or nil,
		group = #group > 1 and group or nil,
		layer = ns.CurrentLayer and ns.CurrentLayer() or nil, -- capa de la zona (Layer.lua)
		map = ns.CurrentMap and ns.CurrentMap() or nil,
	}
end

local function sameActivity(a, b)
	if not a or not b then return false end
	if a.kind ~= b.kind or a.zone ~= b.zone or a.instance ~= b.instance or a.layer ~= b.layer then return false end
	return table.concat(a.group or {}, ",") == table.concat(b.group or {}, ",")
end

function Activity:Report(force)
	if not LG:HasConsent() or not LG:GuildData() then return end
	local now = ns.MyActivity()
	local changed = not sameActivity(now, last)
	if not changed and not force then return end
	if GetTime() - lastSent < MIN_GAP then
		-- Varios cambios seguidos (entrar en grupo, cambiar de zona...): uno solo.
		if not pending then
			pending = true
			self:ScheduleTimer(function() pending = false; self:Report(true) end, MIN_GAP)
		end
		return
	end
	now.since = changed and ns.Now() or (last and last.since) or ns.Now()
	-- Aviso cuando tu tribu se junta en un grupo (3 o más de sus miembros).
	local tribe = now.group and ns.TribeTogether and ns.TribeTogether(now.group)
	local tribeID = tribe and tribe.id or nil
	if tribeID and tribeID ~= (last and last.tribe) then
		local msg = (L["¡%s «%s» está en grupo!"]):format(ns.TribeWords().The, tribe.name)
		if RaidNotice_AddMessage and RaidWarningFrame then RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"]) end
		LG:Print(msg)
	end
	now.tribe = tribeID
	last = now
	lastSent = GetTime()
	local me = ns.PlayerFullName()
	ns.activity[me] = { kind = now.kind, zone = now.zone, instance = now.instance, group = now.group, layer = now.layer, map = now.map, since = now.since, t = ns.Now() }
	LG:Send("ACT", ns.activity[me])
	LG:DataChanged()
end

local KINDS = { dungeon = true, raid = true, bg = true, war = true, world = true }

ns.handlers.ACT = function(sender, d)
	if type(d) ~= "table" or not KINDS[d.kind] then return end
	local group
	if type(d.group) == "table" then
		group = {}
		for i, n in ipairs(d.group) do
			if i > 40 then break end
			if type(n) == "string" then group[#group + 1] = n:sub(1, 60) end
		end
	end
	ns.activity[sender] = {
		kind = d.kind, zone = type(d.zone) == "string" and d.zone:sub(1, 60) or nil,
		instance = type(d.instance) == "string" and d.instance:sub(1, 60) or nil,
		group = group, layer = tonumber(d.layer), map = tonumber(d.map), since = tonumber(d.since) or ns.Now(), t = ns.Now(),
	}
	if d.layer and ns.NoteLayer then ns.NoteLayer(d.layer, tonumber(d.map)) end
	LG:DataChanged()
end

-- Al leer otra capa (Layer.lua) se avisa como cualquier otro cambio.
ns.OnLayerChanged = function() Activity:Report(false) end

-- Quien acaba de entrar pregunta (HELLO); los demás repiten su actividad al rato.
ns.OnHelloActivity = function()
	Activity:ScheduleTimer(function() Activity:Report(true) end, 1 + math.random() * 4)
end

-- Actividad vigente de la hermandad: grupos (con su tribu si juega junta) y gente suelta por zona.
function ns.GuildActivity()
	local now = ns.Now()
	local groups, loose = {}, {}
	local seen = {}
	-- Modo prueba: la actividad de ejemplo (guardada) junto a la real.
	local all = {}
	local g = LG:GuildData()
	if LG:InTestMode() and g and g.testActivity then
		for name, a in pairs(g.testActivity) do
			all[name] = { kind = a.kind, zone = a.zone, instance = a.instance, group = a.group, since = now - (a.ago or 0), t = now }
		end
	end
	for name, a in pairs(ns.activity) do all[name] = a end
	for name, a in pairs(all) do
		local r = ns.roster[name]
		local online = (r == nil and LG:InTestMode()) or (r and r.online) or name == ns.PlayerFullName()
		if online and now - (a.t or 0) <= STALE then
			if a.group then
				local key = table.concat(a.group, ",")
				local grp = groups[key]
				if not grp then
					grp = { members = a.group, kind = a.kind, zone = a.zone, instance = a.instance, since = a.since, withAddon = {} }
					groups[key] = grp
				end
				grp.withAddon[name] = true
				if a.since and a.since < grp.since then grp.since = a.since end
				for _, m in ipairs(a.group) do seen[m] = true end
			else
				seen[name] = true
				loose[#loose + 1] = { name = name, kind = a.kind, zone = a.zone, instance = a.instance, since = a.since }
			end
		end
	end
	-- Conectados de la lista del juego sin el addon (o sin noticias): por su zona.
	for name, r in pairs(ns.roster) do
		if r.online and not seen[name] then
			loose[#loose + 1] = { name = name, zone = r.zone, kind = "world", noAddon = not all[name] }
		end
	end
	local list = {}
	for _, grp in pairs(groups) do
		local guildCount = 0
		for _, m in ipairs(grp.members) do
			if ns.roster[m] or (LG:GuildData() and LG:GuildData().members[m]) then guildCount = guildCount + 1 end
		end
		grp.guildCount = guildCount
		grp.tribe = ns.TribeTogether and ns.TribeTogether(grp.members) or nil
		list[#list + 1] = grp
	end
	table.sort(list, function(a, b) return #a.members > #b.members end)
	table.sort(loose, function(a, b) return (a.zone or "") < (b.zone or "") end)
	return list, loose
end

-- Resumen para la cabecera de Ahora: conectados y lo que ha pasado hoy.
function ns.ActivitySummary()
	local g = LG:GuildData()
	local s = { online = 0, members = 0, addon = 0, grouped = 0, instance = 0,
		runs = 0, bosses = 0, kills = 0, deaths = 0, events = 0, achievements = 0 }
	if not g then return s end
	local groups, loose = ns.GuildActivity()
	for _, r in pairs(ns.roster) do
		s.members = s.members + 1
		if r.online then s.online = s.online + 1 end
	end
	for _, grp in ipairs(groups) do
		s.grouped = s.grouped + #grp.members
		if grp.kind ~= "world" then s.instance = s.instance + #grp.members end
		for n in pairs(grp.withAddon) do s.addon = s.addon + 1 end
	end
	for _, p in ipairs(loose) do
		if not p.noAddon then s.addon = s.addon + 1 end
	end
	-- Modo prueba: el grupo hace de hermandad; cuenta a los que salen en Ahora.
	if LG:InTestMode() then
		s.online = math.max(s.online, s.grouped + #loose)
		local n = 0
		for _ in pairs(g.members) do n = n + 1 end
		s.members = math.max(s.members, n)
	end
	-- Nunca más conectados que miembros.
	s.members = math.max(s.members, s.online)
	local dayStart = ns.Now() - (ns.Now() % 86400)
	local days = {}
	for _, r in pairs(g.runs) do
		if r.t >= dayStart then
			s.bosses = s.bosses + 1
			local key = tostring(r.instanceID or r.instance)
			if not days[key] then days[key] = true; s.runs = s.runs + 1 end
		end
	end
	for _, k in pairs(g.kills) do
		if k.t >= dayStart and not ns.IsVoided(g, k.id) then
			if k.kind == "kill" then s.kills = s.kills + 1 else s.deaths = s.deaths + 1 end
		end
	end
	for _, e in pairs(g.events) do
		if e.status ~= "cancelled" and e.start >= dayStart and e.start < dayStart + 86400 then s.events = s.events + 1 end
	end
	for _, a in pairs(g.achievements) do
		if (a.t or 0) >= dayStart then s.achievements = s.achievements + 1 end
	end
	return s
end

function Activity:OnEnable()
	for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
		ns.RegisterEvent(self, event, function() self:Report(false) end)
	end
	self:ScheduleRepeatingTimer(function() self:Report(true) end, HEARTBEAT)
	self:ScheduleTimer(function() self:Report(true) end, 10)
end
