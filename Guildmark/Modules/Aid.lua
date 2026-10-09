-- Llamada de auxilio: cuando una hermandad enemiga caza a los nuestros, se pide
-- ayuda a toda la facción y los que acuden entran en una banda en la capa buena.
--
--   1. Detección: una misma hermandad enemiga mata a los nuestros 3 veces en 10
--      minutos en la misma zona (contando a toda la hermandad). A la víctima le
--      sale "¿Pedir ayuda?".
--   2. Aprobación: la aprueba un oficial conectado (AIDREQ por la hermandad); si
--      no hay ninguno conectado, la víctima la envía directamente.
--   3. Aviso a la facción (HELP por la red de hermandades): solo por el canal de
--      tu facción, nunca por el puente de Battle.net (no se avisa al enemigo).
--   4. Acudir (GOING): a los de la hermandad que pidió ayuda que están en la capa
--      de la llamada les sale "¿Invitarle?". Con un clic le invitan; si el grupo
--      ya es de 5, se convierte en banda. Quien acude se queda en la banda: al
--      salir del grupo el juego puede devolverle a su capa de antes.
--   5. La llamada dura 30 minutos; en ese tiempo se cuentan las bajas de la
--      hermandad enemiga en esa zona. Al terminar, quien la lanzó manda el
--      resumen a la facción (AIDEND).
--
-- Asaltos (la parte ofensiva): un oficial declara un asalto a una capital
-- enemiga, abierto a la facción (HELP con kind = "assault") o solo para la
-- hermandad. No tiene hora de fin: acaba al caer el líder (y su tiempo cuenta
-- para los récords de la facción), cuando un oficial lo termina o tras 2 horas
-- sin bajas en la ciudad. Si alguien tiene al líder de la ciudad seleccionado
-- cuando muere, el addon lo detecta (por el número de PNJ de su GUID; el
-- registro de combate está prohibido en Forever) y lo anuncia (REGICIDE, FALLEN).
-- Comprobado en Forever: Thrall es Creature-0-4615-1-30591-4949-... (el 4949 de Classic).
--
-- Datos de la hermandad (se sincronizan y dan insignias y logros):
--   calls      llamadas y asaltos de la hermandad, con su resultado (CALL)
--   aidHelps   miembros que llegaron a ayudar a otra hermandad (AIDHELP)
--   regicides  líderes enemigos derribados (REGICIDE)
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Aid = LG:NewModule("Aid", "AceEvent-3.0", "AceTimer-3.0")

local TRIGGER_DEATHS = 3
local TRIGGER_WINDOW = 10 * 60
local ASK_AGAIN = 10 * 60      -- a la misma víctima no se le vuelve a preguntar por el mismo enemigo
local CALL_EVERY = 15 * 60     -- una llamada por hermandad cada 15 minutos
local CALL_LENGTH = 30 * 60
local POPUP_EVERY = 5 * 60   -- como mucho una ventana de llamada cada 5 minutos (las demás, al chat)
-- Un asalto no tiene hora de fin: acaba al caer el líder, cuando un oficial lo
-- termina o tras 2 horas sin bajas en la ciudad. Como mucho dura 8 horas.
local ASSAULT_LENGTH = 8 * 60 * 60
local ASSAULT_IDLE = 2 * 60 * 60
local TICK_EVERY = 15
local MAX_LENGTH = { help = CALL_LENGTH, assault = ASSAULT_LENGTH }

-- Capitales que se pueden asaltar y su líder (números de PNJ de Classic; el
-- nombre sirve de respaldo si Forever usa otros números).
ns.CITIES = {
	{ key = "stormwind", faction = "Alliance", map = 1453, npc = 1748, leader = L["Alto señor Bolvar Fordragon"], names = { "Highlord Bolvar Fordragon", "Alto señor Bolvar Fordragon" } },
	{ key = "ironforge", faction = "Alliance", map = 1455, npc = 2784, leader = L["Rey Magni Barbabronce"], names = { "King Magni Bronzebeard", "Rey Magni Barbabronce" } },
	{ key = "darnassus", faction = "Alliance", map = 1457, npc = 7999, leader = L["Tyrande Susurravientos"], names = { "Tyrande Whisperwind", "Tyrande Susurravientos" } },
	{ key = "orgrimmar", faction = "Horde", map = 1454, npc = 4949, leader = L["Thrall"], names = { "Thrall" } },
	{ key = "undercity", faction = "Horde", map = 1458, npc = 10181, leader = L["Lady Sylvanas Brisaveloz"], names = { "Lady Sylvanas Windrunner", "Lady Sylvanas Brisaveloz" } },
	{ key = "thunderbluff", faction = "Horde", map = 1456, npc = 3057, leader = L["Cairne Pezuña de Sangre"], names = { "Cairne Bloodhoof", "Cairne Pezuña de Sangre" } },
}
local CITY = {}
for _, c in ipairs(ns.CITIES) do CITY[c.key] = c end
ns.CITY = CITY

function ns.CityName(key)
	local c = CITY[key]
	return c and ns.MapName(c.map, key) or "?"
end

-- Capitales de la otra facción (las que puedo asaltar).
function ns.EnemyCities()
	local mine = UnitFactionGroup and UnitFactionGroup("player")
	local list = {}
	for _, c in ipairs(ns.CITIES) do
		if c.faction ~= mine then list[#list + 1] = c end
	end
	return list
end

ns.aidCalls = {}   -- [id] = { id, guild, enemy, zone, map, subzone, layer, deaths, by, approvedBy, t, ends }
ns.aidGoers = {}   -- [id] = { [nombre] = { guild, t } }
local asked = {}   -- [enemigo|zona] = ns.Now() de la última pregunta a la víctima
local pendingReq = {} -- [id] = petición de una víctima esperando a un oficial
local going = {}      -- [id] = true: llamadas a las que he respondido y aún no he llegado (al llegar, cuenta como ayuda)
local answered = {}   -- [id] = true: llamadas a las que he respondido (para recibir su resumen)
local lastPopup = -POPUP_EVERY

-- Continente de un mapa (el antepasado de tipo continente), o nil.
local function continentOf(map) return ns.ContinentOf(map) end

-- ¿Ventana o solo chat? Ventana si estoy en su continente, fuera de instancias y
-- de combate, y no ha salido otra en los últimos 5 minutos.
function ns.AidResetPopup() lastPopup = -POPUP_EVERY end -- para las pruebas

local function popupAllowed(call)
	if IsInInstance and select(1, IsInInstance()) then return false end
	if InCombatLockdown and InCombatLockdown() then return false end
	if GetTime() - lastPopup < POPUP_EVERY then return false end
	local mine, theirs = continentOf(ns.CurrentMap()), continentOf(call.map)
	if mine and theirs and mine ~= theirs then return false end
	lastPopup = GetTime()
	return true
end

local function setting()
	return not (LG.db and LG.db.profile.aidCalls == false)
end
function ns.AidSetting() return setting() end
function ns.ToggleAidSetting()
	LG.db.profile.aidCalls = not setting()
	LG:DataChanged()
end

local function factionName()
	return ns.FactionName(UnitFactionGroup and UnitFactionGroup("player"))
end

local function str(v, max)
	return type(v) == "string" and v ~= "" and v:gsub("|", ""):sub(1, max or 60) or nil
end

-- Misma zona: por el id de mapa (igual en todos los idiomas) o, si falta, por el nombre.
local function sameZone(k, map, zone)
	if map and k.map then return k.map == map end
	return k.zone == zone
end

-- Bajas de los nuestros a manos de esa hermandad en esa zona en los últimos 10 minutos.
-- Enemigos sin hermandad: por la red viaja esta marca (igual en todos los idiomas) y cada
-- addon la muestra traducida. Así también se pide auxilio cuando os masacran jugadores sueltos.
local GUILDLESS = "*"
ns.AID_GUILDLESS = GUILDLESS
function ns.AidEnemyName(enemy)
	if enemy == GUILDLESS then return L["sin hermandad"] end
	return enemy or "?"
end

local function recentDeaths(g, enemy, zone, now, map)
	local n = 0
	for _, k in pairs(g.kills) do
		if k.kind == "death" and not k.bg and (k.guild or GUILDLESS) == enemy and sameZone(k, map, zone) and now - k.t <= TRIGGER_WINDOW and now >= k.t
			and not ns.IsVoided(g, k.id) then
			n = n + 1
		end
	end
	return n
end
ns.AidRecentDeaths = recentDeaths -- para las pruebas

-- Kills de los nuestros contra la hermandad enemiga en la zona durante la llamada.
function ns.AidKills(call)
	local g = LG:GuildData()
	local n = 0
	local assault = call.kind == "assault"
	for _, k in pairs(g and g.kills or {}) do
		local where = sameZone(k, call.map, call.zone)
		if k.kind == "kill" and not k.bg and (assault or (k.guild or GUILDLESS) == call.enemy) and where and k.t >= call.t and k.t <= call.ends
			and not ns.IsVoided(g, k.id) then
			n = n + 1
		end
	end
	return n
end

local function officerOnline()
	local me = ns.PlayerFullName()
	for name, r in pairs(ns.roster) do
		if r.online and name ~= me and ns.CanManageEvents(name) then return true end
	end
	return false
end

-- La llamada en curso de una hermandad de ese tipo (una de auxilio y un asalto a la vez).
local function myCall(guild, kind)
	kind = kind or "help"
	for _, c in pairs(ns.aidCalls) do
		if c.guild == guild and (c.kind or "help") == kind and ns.Now() < c.ends then return c end
	end
	return nil
end

-- ¿Estoy ya en la capa de la llamada?
local function onLayer(call)
	return call.layer ~= nil and call.map ~= nil and ns.CurrentMap() == call.map and ns.CurrentLayer and ns.CurrentLayer() == call.layer
end

---------------------------------------------------------------------------
-- Diálogos
---------------------------------------------------------------------------

StaticPopupDialogs["LANTUX_AID_ASK"] = {
	text = "%s", button1 = L["Pedir ayuda"], button2 = L["No"],
	OnAccept = function(_, data) if data then ns.ProposeAid(data.enemy, data.zone, data.deaths) end end,
	timeout = 60, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
StaticPopupDialogs["LANTUX_AID_APPROVE"] = {
	text = "%s", button1 = L["Enviar"], button2 = L["No"],
	OnAccept = function(_, data) if data then ns.SendAid(data, ns.PlayerFullName()) end end,
	timeout = 120, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
StaticPopupDialogs["LANTUX_AID_HELP"] = {
	text = "%s", button1 = L["Acudir"], button2 = L["Ignorar"],
	OnAccept = function(_, data) if data then ns.GoToAid(data) end end,
	timeout = 90, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
StaticPopupDialogs["LANTUX_AID_INVITE"] = {
	text = "%s", button1 = L["Invitar"], button2 = L["No"],
	OnAccept = function(_, data) if data then ns.InviteAidGoer(data.id, data.name) end end,
	timeout = 120, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

---------------------------------------------------------------------------
-- 1. Detección
---------------------------------------------------------------------------

-- Cada muerte de los nuestros (propia o de otro miembro): si es mía y ya van 3, pregunto.
function ns.CheckAid(rec)
	if rec.kind ~= "death" or rec.bg or not rec.zone or not (rec.killer or rec.killerName) then return end
	if rec.victimName ~= ns.PlayerFullName() then return end
	local enemy = rec.guild or GUILDLESS
	local g = LG:GuildData()
	if not g or not LG:HasConsent() then return end
	local now = ns.Now()
	local deaths = recentDeaths(g, enemy, rec.zone, now, rec.map)
	if deaths < TRIGGER_DEATHS then return end
	if myCall(LG:GuildName(), "help") then return end
	local key = enemy .. "|" .. rec.zone
	if asked[key] and now - asked[key] < ASK_AGAIN then return end
	asked[key] = now
	local text = (L["<%s> os ha matado %d veces en %s en 10 minutos.\n¿Pedir ayuda a la %s?"]):format(ns.AidEnemyName(enemy), deaths, rec.zone, factionName())
	StaticPopup_Show("LANTUX_AID_ASK", text, nil, { enemy = enemy, zone = rec.zone, deaths = deaths })
end

---------------------------------------------------------------------------
-- 2. Aprobación
---------------------------------------------------------------------------

function ns.ProposeAid(enemy, zone, deaths)
	local g = LG:GuildData()
	local guild = LG:GuildName()
	if not g or not guild then return end
	local me = ns.PlayerFullName()
	local now = ns.Now()
	local rec = {
		id = ("%s:%d"):format(guild, now), guild = guild, enemy = enemy, zone = zone,
		map = ns.CurrentMap(), subzone = GetSubZoneText and GetSubZoneText() or nil,
		layer = ns.CurrentLayer and ns.CurrentLayer() or nil, deaths = deaths, by = me, t = now,
	}
	if ns.CanManageEvents(me) or not officerOnline() then
		ns.SendAid(rec, ns.CanManageEvents(me) and me or nil)
	else
		LG:Send("AIDREQ", rec)
		LG:Print(L["Petición de ayuda enviada a los oficiales conectados."])
	end
end

ns.handlers.AIDREQ = function(sender, rec)
	if type(rec) ~= "table" or rec.by ~= sender or not str(rec.id) or not str(rec.enemy, 48) or not str(rec.zone) then return end
	if rec.guild ~= LG:GuildName() or not ns.CanManageEvents(ns.PlayerFullName()) or not setting() then return end
	pendingReq[rec.id] = rec
	local text = (L["%s pide ayuda: <%s> os ha matado %d veces en %s.\n¿Enviar la llamada de auxilio a la %s?"]):format(
		ns.ShortName(sender), ns.AidEnemyName(rec.enemy), tonumber(rec.deaths) or 0, rec.zone, factionName())
	StaticPopup_Show("LANTUX_AID_APPROVE", text, nil, rec)
	if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
end

---------------------------------------------------------------------------
-- 3. Aviso a la facción
---------------------------------------------------------------------------

function ns.SendAid(rec, approvedBy)
	local guild = LG:GuildName()
	if not guild or rec.guild ~= guild then return end
	if myCall(guild, rec.kind) then
		LG:Print(rec.kind == "assault" and L["Ya hay un asalto en curso."] or L["Ya hay una llamada de auxilio en curso."])
		return
	end
	local call = {}
	for k, v in pairs(rec) do call[k] = v end
	call.approvedBy = approvedBy
	call.kind = call.kind or "help"
	call.ends = ns.Now() + MAX_LENGTH[call.kind]
	ns.aidCalls[call.id] = call
	pendingReq[call.id] = nil
	ns.RecordCall(call)
	-- Un asalto solo de la hermandad no sale a la red.
	local sent = (call.kind ~= "assault" or call.open) and ns.NetSend("HELP", call)
	-- Los de mi hermandad también se enteran por su canal (por si alguno no está en la red).
	LG:Send("AIDSENT", call)
	if call.kind == "assault" then
		LG:Print((call.open and L["Asalto a %s declarado y anunciado a la %s."] or L["Asalto a %s declarado (solo tu hermandad)."]):format(call.zone, factionName()))
	elseif sent then
		LG:Print((L["Llamada de auxilio enviada a la %s: %s, contra <%s>."]):format(factionName(), call.zone, ns.AidEnemyName(call.enemy)))
	else
		LG:Print(L["No se ha podido enviar la llamada por la red de hermandades; solo se ha enterado tu hermandad."])
	end
	LG:DataChanged()
end

-- Valida y guarda una llamada recibida. Devuelve la llamada o nil.
local function acceptCall(d)
	if type(d) ~= "table" then return nil end
	local id, guild, enemy, zone = str(d.id, 80), str(d.guild, 48), str(d.enemy, 48), str(d.zone)
	local t, ends = tonumber(d.t), tonumber(d.ends)
	local kind = d.kind == "assault" and "assault" or "help"
	if kind == "assault" and not CITY[d.city] then return nil end
	if not (id and guild and enemy and zone and t and ends) or ends - t > MAX_LENGTH[kind] or ends < ns.Now() or t > ns.Now() + 300 then return nil end
	if ns.aidCalls[id] then return ns.aidCalls[id], true end
	-- Una por hermandad a la vez: si llega otra más reciente, sustituye a la anterior
	-- (así una llamada falsa con otro nombre no puede bloquear la de verdad).
	local old = myCall(guild, kind)
	if old then
		if old.t >= t then return nil end
		old.ends, old.closed = math.min(old.ends, ns.Now() - 1), true
	end
	local call = { id = id, guild = guild, enemy = enemy, zone = zone, map = tonumber(d.map), subzone = str(d.subzone),
		layer = tonumber(d.layer), deaths = tonumber(d.deaths), by = str(d.by), approvedBy = str(d.approvedBy), t = t, ends = ends,
		kind = kind, city = kind == "assault" and d.city or nil, open = d.open and true or nil }
	ns.aidCalls[id] = call
	if call.layer then ns.NoteLayer(call.layer, call.map) end
	return call, false
end

local function announce(call)
	if call.kind == "assault" then
		local layer = call.layer and (" (" .. ns.LayerLabel(call.layer, call.map) .. ")") or ""
		if call.guild == LG:GuildName() then
			LG:Print((L["¡Tu hermandad asalta %s%s!"]):format(call.zone, layer))
			if call.by ~= ns.PlayerFullName() and not onLayer(call) then
				StaticPopup_Show("LANTUX_AID_HELP", (L["Tu hermandad asalta %s%s.\n¿Unirte? Te invitarán a su banda."]):format(call.zone, layer), nil, call.id)
			end
		elseif setting() then
			local msg = (L["<%s> lanza un asalto a %s%s."]):format(call.guild, call.zone, layer)
			LG:Print("|cffff6b5a" .. msg .. "|r " .. L["Únete desde /gmk > JcJ > Asaltos."])
			if popupAllowed(call) then
				StaticPopup_Show("LANTUX_AID_HELP", msg .. "\n" .. L["¿Unirte? Te invitarán a su banda para llevarte a su capa."], nil, call.id)
				if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
			end
		end
		LG:DataChanged()
		return
	end
	if call.guild == LG:GuildName() then
		pendingReq[call.id] = nil
		if StaticPopup_Hide then StaticPopup_Hide("LANTUX_AID_APPROVE") end
		LG:Print((L["Llamada de auxilio enviada a la %s: %s, contra <%s>."]):format(factionName(), call.zone, ns.AidEnemyName(call.enemy)))
		-- Los nuestros que están en otra capa también pueden ir.
		if call.by ~= ns.PlayerFullName() and not onLayer(call) then
			StaticPopup_Show("LANTUX_AID_HELP", (L["Tu hermandad pide ayuda en %s contra <%s>.\n¿Ir a su capa? Te invitarán a su banda."]):format(call.zone, ns.AidEnemyName(call.enemy)), nil, call.id)
		end
	elseif setting() then
		local layer = call.layer and (" (" .. ns.LayerLabel(call.layer, call.map) .. ")") or ""
		local msg = (L["<%s> pide ayuda en %s%s: <%s> les está cazando."]):format(call.guild, call.zone, layer, ns.AidEnemyName(call.enemy))
		-- Sin aviso de banda: la ventana de Acudir sale en el mismo sitio y lo taparía.
		LG:Print("|cffff6b5a" .. msg .. "|r " .. L["Acude desde /gmk > JcJ > Auxilio."])
		if popupAllowed(call) then
			StaticPopup_Show("LANTUX_AID_HELP", msg .. "\n" .. L["¿Acudir? Te invitarán a su banda para llevarte a su capa."], nil, call.id)
			if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
		end
	end
	LG:DataChanged()
end

ns.netHandlers.HELP = function(_, d)
	local call, known = acceptCall(d)
	if call and not known then announce(call) end
end

ns.handlers.AIDSENT = function(_, d)
	local call, known = acceptCall(d)
	if call and not known then announce(call) end
end

---------------------------------------------------------------------------
-- 4. Acudir
---------------------------------------------------------------------------


function ns.GoToAid(id)
	local call = ns.aidCalls[id]
	if not call or ns.Now() > call.ends then return end
	if onLayer(call) then
		LG:Print((L["Ya estás en su capa: ve a %s."]):format(call.subzone or call.zone))
		return
	end
	local me = ns.PlayerFullName()
	ns.NetSend("GOING", { id = id, name = me, guild = LG:GuildName(), t = ns.Now() })
	-- Si es de mi hermandad, también por la hermandad (los de la llamada pueden no oír el canal).
	if call.guild == LG:GuildName() then LG:Send("AIDGOING", { id = id, name = me, guild = LG:GuildName(), t = ns.Now() }) end
	ns.aidGoers[id] = ns.aidGoers[id] or {}
	ns.aidGoers[id][me] = { guild = LG:GuildName(), t = ns.Now() }
	going[id] = true
	answered[id] = true
	local g = LG:GuildData()
	if g and call.guild ~= LG:GuildName() then
		local rec = { id = id, member = me, guild = call.guild, kind = call.kind, zone = call.zone, map = call.map,
			callT = call.t, ends = call.ends, t = ns.Now() }
		if ns.MergeAidHelp(g, rec) then LG:Send("AIDHELP", rec) end
	end
	LG:Print((L["Has respondido a <%s>. Te invitarán a su banda: quédate en ella mientras dure (al salir puedes volver a tu capa)."]):format(call.guild))
	if call.guild ~= LG:GuildName() then
		LG:Print((L["Cada kill en %s mientras dure la llamada: +10 insignias (hasta %d)."]):format(call.zone, ns.AID_KILL_CAP))
	end
	if IsInGroup() then LG:Print(L["Estás en un grupo: sal de él para que puedan invitarte."]) end
	LG:DataChanged()
end

local function onGoing(sender, d)
	if type(d) ~= "table" or d.name ~= sender or not str(d.id, 80) then return end
	local call = ns.aidCalls[d.id]
	if not call or ns.Now() > call.ends then return end
	ns.aidGoers[d.id] = ns.aidGoers[d.id] or {}
	if ns.aidGoers[d.id][sender] then return end
	ns.aidGoers[d.id][sender] = { guild = str(d.guild, 48), t = ns.Now() }
	LG:DataChanged()
	-- Solo invitan los de la hermandad que pidió ayuda que están en la capa buena y
	-- pueden invitar (solos, o líderes/ayudantes de su grupo).
	if call.guild ~= LG:GuildName() or not onLayer(call) then return end
	if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then return end
	local who = ns.ShortName(sender) .. (d.guild and d.guild ~= call.guild and (" <%s>"):format(d.guild) or "")
	LG:Print((L["%s acude a la llamada."]):format(who))
	StaticPopup_Show("LANTUX_AID_INVITE", (L["%s acude a la llamada.\n¿Invitarle a tu banda para traerle a tu capa?"]):format(who), nil, { id = d.id, name = sender })
end
ns.netHandlers.GOING = onGoing
ns.handlers.AIDGOING = onGoing

-- Invitar a quien acude: si el grupo ya es de 5, primero se convierte en banda.
function ns.InviteAidGoer(id, name)
	if IsInGroup() and not IsInRaid() and GetNumGroupMembers() >= 5 then
		if not UnitIsGroupLeader("player") then
			LG:Print(L["El grupo está lleno: el líder tiene que convertirlo en banda."])
			return
		end
		local convert = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid
		if convert then pcall(convert) end
	end
	local target = (LG.lastRawSenders and LG.lastRawSenders[name]) or name
	local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
	if invite then pcall(invite, target) end
	local goers = ns.aidGoers[id]
	if goers and goers[name] then goers[name].invited = ns.Now() end
	LG:DataChanged()
end

-- Llamadas en curso, la mía primero y luego las más recientes.
function ns.ActiveAidCalls()
	local list = {}
	local now = ns.Now()
	local mine = LG:GuildName()
	for id, c in pairs(ns.aidCalls) do
		if now <= c.ends then list[#list + 1] = c
		elseif now - c.ends > 3600 then ns.aidCalls[id], ns.aidGoers[id] = nil, nil end
	end
	table.sort(list, function(a, b)
		if (a.guild == mine) ~= (b.guild == mine) then return a.guild == mine end
		return a.t > b.t
	end)
	return list
end

function ns.AidOnLayer(call) return onLayer(call) end

-- Modo prueba: una llamada de otra hermandad de ejemplo, en tu zona y tu capa.
function ns.SimulateAidCall()
	if not LG:InTestMode() then return end
	local now = ns.Now()
	local zone = GetZoneText and GetZoneText() or "?"
	acceptCall({ id = "test:aid:" .. now, guild = "Sombras de Lordaeron", enemy = "Guardia de Ventormenta", zone = zone,
		map = ns.CurrentMap(), layer = ns.CurrentLayer and ns.CurrentLayer() or nil, deaths = 4, by = "Ejemplo", t = now, ends = now + CALL_LENGTH })
	announce(ns.aidCalls["test:aid:" .. now])
end

---------------------------------------------------------------------------
-- Asaltos
---------------------------------------------------------------------------

-- Solo oficiales. open: anunciarlo a la facción.
function ns.DeclareAssault(cityKey, open)
	local city = CITY[cityKey]
	local guild = LG:GuildName()
	local me = ns.PlayerFullName()
	if not city or not guild then return end
	if not ns.CanManageEvents(me) then
		LG:Print(L["Solo los oficiales pueden declarar asaltos."])
		return
	end
	local now = ns.Now()
	local here = ns.CurrentMap() == city.map
	ns.SendAid({
		id = ("%s:%d"):format(guild, now), kind = "assault", city = cityKey, guild = guild,
		enemy = ns.FactionName(city.faction), zone = ns.CityName(cityKey), map = city.map,
		layer = here and ns.CurrentLayer and ns.CurrentLayer() or nil, open = open and true or nil, by = me, t = now,
	}, me)
end

---------------------------------------------------------------------------
-- Datos de la hermandad: llamadas, ayudas y regicidios
---------------------------------------------------------------------------

local CALL_FIELDS = { "id", "kind", "city", "enemy", "zone", "map", "layer", "open", "by", "approvedBy", "t", "ends",
	"goers", "guilds", "external", "kills", "time", "rev" }

function ns.MergeCall(g, rec, sender)
	if type(rec) ~= "table" or type(rec.id) ~= "string" or type(rec.t) ~= "number" or type(rec.by) ~= "string" then return false end
	if sender and sender ~= rec.by and not ns.CanManageEvents(sender) then return false end
	local old = g.calls[rec.id]
	if old and (old.rev or 0) >= (rec.rev or 0) then return false end
	local c = {}
	for _, k in ipairs(CALL_FIELDS) do c[k] = rec[k] end
	c.kind = c.kind == "assault" and "assault" or "help"
	g.calls[rec.id] = c
	return true
end
ns.handlers.CALL = function(sender, rec)
	local g = LG:GuildData()
	if g and ns.MergeCall(g, rec, sender) then LG:DataChanged() end
end

function ns.RecordCall(call, stats)
	local g = LG:GuildData()
	if not g then return end
	local old = g.calls[call.id]
	local rec = {}
	for _, k in ipairs(CALL_FIELDS) do rec[k] = call[k] end
	for k, v in pairs(stats or {}) do rec[k] = v end
	rec.rev = (old and old.rev or 0) + 1
	if ns.MergeCall(g, rec) then LG:Send("CALL", rec) end
end

-- Llegada a la llamada de otra hermandad (o a un asalto ajeno): cuenta como ayuda.
function ns.MergeAidHelp(g, rec, sender)
	if type(rec) ~= "table" or type(rec.id) ~= "string" or type(rec.member) ~= "string" or type(rec.t) ~= "number" then return false end
	if sender and rec.member ~= sender then return false end
	local key = rec.id .. "|" .. rec.member
	if g.aidHelps[key] then return false end
	local callT, ends = tonumber(rec.callT) or rec.t, tonumber(rec.ends)
	if not ends or ends - callT > MAX_LENGTH.assault then ends = callT + CALL_LENGTH end
	g.aidHelps[key] = { id = rec.id, member = rec.member, guild = str(rec.guild, 48), kind = rec.kind == "assault" and "assault" or "help",
		zone = str(rec.zone), map = tonumber(rec.map), callT = callT, ends = ends, t = rec.t }
	return true
end

-- Kills que dan premio por ayudar: las del miembro en la zona de la llamada mientras
-- dura, como mucho AID_KILL_CAP por llamada. Las calculan igual todos los addons.
local AID_KILL_CAP = 5
ns.AID_KILL_CAP = AID_KILL_CAP
function ns.AidHelpKills(g, h)
	local list = {}
	for _, k in pairs(g.kills) do
		if k.kind == "kill" and not k.bg and k.killerName == h.member and k.t >= (h.callT or h.t) and k.t <= (h.ends or h.t + CALL_LENGTH)
			and sameZone(k, h.map, h.zone) and not ns.IsVoided(g, k.id) then
			list[#list + 1] = k
		end
	end
	table.sort(list, function(a, b) return a.t < b.t end)
	local boost = ns.BoostAt and ns.BoostAt(g, "aid", h.callT or h.t)
	local cap = math.floor(AID_KILL_CAP * (type(boost) == "number" and boost or 1))
	for i = #list, cap + 1, -1 do list[i] = nil end
	return list
end

-- Una kill mía: si cuenta para una llamada a la que he respondido, lo digo.
function ns.CheckAidKill(rec)
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	if not g or rec.kind ~= "kill" or rec.killerName ~= me then return end
	for _, h in pairs(g.aidHelps) do
		if h.member == me and h.guild ~= LG:GuildName() then
			local kills = ns.AidHelpKills(g, h)
			for i, k in ipairs(kills) do
				if k.id == rec.id then
					LG:Print((L["+10 insignias por ayudar a <%s> (%d/%d)."]):format(h.guild or "?", i, AID_KILL_CAP))
				end
			end
		end
	end
end
ns.handlers.AIDHELP = function(sender, rec)
	local g = LG:GuildData()
	if g and ns.MergeAidHelp(g, rec, sender) then LG:DataChanged() end
end

function ns.MergeRegicide(g, rec, sender)
	if type(rec) ~= "table" or type(rec.id) ~= "string" or not CITY[rec.city] or type(rec.t) ~= "number" or type(rec.by) ~= "string" then return false end
	if sender and rec.by ~= sender then return false end
	if g.regicides[rec.id] then return false end
	g.regicides[rec.id] = { city = rec.city, t = rec.t, by = rec.by, call = str(rec.call, 80), solo = rec.solo and true or nil }
	return true
end
ns.handlers.REGICIDE = function(sender, rec)
	local g = LG:GuildData()
	if g and ns.MergeRegicide(g, rec, sender) then
		local call = rec.call and ns.aidCalls[rec.call]
		if call and call.kind == "assault" then ns.AssaultWon(call, rec.t) end
		LG:Print((L["|cffffd100¡%s ha caído!|r Lo ha visto %s."]):format(CITY[rec.city].leader, ns.ShortName(rec.by)))
		LG:DataChanged()
	end
end

---------------------------------------------------------------------------
-- El líder de una capital: se detecta su muerte al tenerlo seleccionado
---------------------------------------------------------------------------

local lastRegicide = {} -- [ciudad] = ns.Now()

-- Valores secretos (dentro de instancias, el juego oculta nombres y GUID de los
-- PNJ a los addons): no se pueden comparar, así que se ignoran.
local function secret(v) return issecretvalue and issecretvalue(v) end

local function leaderCity(unit)
	-- Los líderes están en sus capitales: en mazmorras, bandas y campos de batalla ni se mira.
	if IsInInstance and select(1, IsInInstance()) then return nil end
	if not UnitExists(unit) or (UnitIsPlayer and UnitIsPlayer(unit)) then return nil end
	local ok, guid = pcall(UnitGUID, unit)
	if ok and type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) then
		local id = tonumber(guid:match("^Creature%-0%-%d+%-%d+%-%d+%-(%d+)%-"))
		for _, c in ipairs(ns.CITIES) do
			if c.npc == id then return c end
		end
	end
	local okName, name = pcall(UnitName, unit)
	if okName and type(name) == "string" and not secret(name) then
		for _, c in ipairs(ns.CITIES) do
			for _, n in ipairs(c.names) do
				if n == name then return c end
			end
		end
	end
	return nil
end

function ns.CheckLeader(unit)
	local city = leaderCity(unit)
	if not city then return end
	local ok, dead = pcall(UnitIsDead, unit)
	if not ok or secret(dead) or not dead then return end
	local now = ns.Now()
	if lastRegicide[city.key] and now - lastRegicide[city.key] < 1800 then return end
	lastRegicide[city.key] = now
	local g = LG:GuildData()
	local guild = LG:GuildName()
	if not g or not guild then return end
	-- ¿Durante un asalto de mi hermandad a esa ciudad?
	local call
	for _, c in pairs(ns.aidCalls) do
		if c.kind == "assault" and c.city == city.key and c.guild == guild and now <= c.ends + 300 then call = c end
	end
	-- Mismo id para todos los que lo vean en los mismos 10 minutos.
	local rec = { id = ("%s:%d"):format(city.key, math.floor(now / 600)), city = city.key, t = now, by = ns.PlayerFullName(),
		call = call and call.id or nil, solo = call and not call.open or nil }
	if ns.MergeRegicide(g, rec) then
		if call then ns.AssaultWon(call, now) end
		LG:Send("REGICIDE", rec)
		ns.NetSend("FALLEN", { city = city.key, guild = guild, t = now })
		local msg = (L["¡%s ha caído a manos de <%s>!"]):format(city.leader, guild)
		if RaidNotice_AddMessage and RaidWarningFrame then RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"]) end
		LG:Print("|cffffd100" .. msg .. "|r")
		LG:DataChanged()
	end
end

-- Otra hermandad de mi facción ha derribado a un líder enemigo.
ns.netHandlers.FALLEN = function(_, d)
	local city = type(d) == "table" and CITY[d.city]
	local guild = city and str(d.guild, 48)
	if not guild or guild == LG:GuildName() then return end
	LG:Print("|cffffd100" .. (L["¡%s ha caído a manos de <%s>!"]):format(city.leader, guild) .. "|r")
end

---------------------------------------------------------------------------
-- Resumen al terminar
---------------------------------------------------------------------------

local function summaryText(d)
	local text
	if d.kind == "assault" then
		text = (L["Asalto de <%s> a %s terminado: %d bajas; acudieron %d jugadores de %d hermandades."]):format(
			d.guild, d.zone, d.kills or 0, d.goers or 0, d.guilds or 0)
		if d.leader then
			text = text .. " " .. (d.time and (L["¡%s cayó en %s!"]):format(d.leader, ns.FormatDuration(d.time)) or (L["¡%s cayó!"]):format(d.leader))
		end
	else
		text = (L["Auxilio a <%s> en %s terminado: abatieron a %d de <%s>; acudieron %d jugadores de %d hermandades."]):format(
			d.guild, d.zone, d.kills or 0, ns.AidEnemyName(d.enemy), d.goers or 0, d.guilds or 0)
	end
	return text
end

ns.netHandlers.AIDEND = function(_, d)
	if type(d) ~= "table" or not str(d.guild, 48) or not str(d.zone) then return end
	local call = ns.aidCalls[d.id]
	-- Terminada (antes de tiempo, si un oficial la ha cerrado): fuera de la lista.
	if call and call.guild == d.guild and not call.closed then
		call.ends = math.min(call.ends, ns.Now() - 1)
		call.closed = true
		LG:DataChanged()
	end
	if not setting() and d.guild ~= LG:GuildName() then return end
	local mine = answered[d.id] or (call and call.guild == LG:GuildName())
	-- Solo a quien estuvo o a los de la hermandad que la lanzó; al resto, nada.
	if mine then LG:Print(summaryText({ kind = d.kind, guild = str(d.guild, 48), zone = str(d.zone), kills = tonumber(d.kills),
		goers = tonumber(d.goers), guilds = tonumber(d.guilds), enemy = str(d.enemy, 48), leader = str(d.leader, 60), time = tonumber(d.time) })) end
end

local function finish(c)
	c.closed = true
	c.ends = math.min(c.ends, ns.Now() - 1)
	if c.guild ~= LG:GuildName() then return end
	-- Lo cierra quien la lanzó (o el oficial que la aprobó).
	local me = ns.PlayerFullName()
	if c.by ~= me and c.approvedBy ~= me then return end
	local goers, guilds, external = 0, {}, 0
	for _, info in pairs(ns.aidGoers[c.id] or {}) do
		goers = goers + 1
		if info.guild then guilds[info.guild] = true end
		if info.guild ~= c.guild then external = external + 1 end
	end
	local nGuilds = 0
	for _ in pairs(guilds) do nGuilds = nGuilds + 1 end
	local kills = ns.AidKills(c)
	local leader
	local g = LG:GuildData()
	for _, r in pairs(g and g.regicides or {}) do
		if r.call == c.id then leader = CITY[r.city].leader end
	end
	ns.RecordCall(c, { goers = goers, guilds = nGuilds, external = external, kills = kills, time = c.time })
	local d = { id = c.id, kind = c.kind, guild = c.guild, zone = c.zone, enemy = c.enemy, kills = kills, goers = goers, guilds = nGuilds,
		leader = leader, time = c.time }
	if c.kind ~= "assault" or c.open then ns.NetSend("AIDEND", d) end
	LG:Print(summaryText(d))
end

-- Un asalto completado: cayó el líder durante él o la hermandad hizo al menos
-- ASSAULT_MIN_KILLS kills en la ciudad (lo que cuenta para logros y clasificación).
local ASSAULT_MIN_KILLS = 10
ns.ASSAULT_MIN_KILLS = ASSAULT_MIN_KILLS
-- Miembros que tuvieron alguna baja en la ciudad durante el asalto (para las medallas del perfil).
function ns.AssaultParticipants(g, c)
	local who = {}
	local ends = c.ends or (c.t + 8 * 3600)
	for _, k in pairs(g.kills) do
		if k.kind == "kill" and not k.bg and k.killerName and k.t >= c.t and k.t <= ends and sameZone(k, c.map, c.zone)
			and not ns.IsVoided(g, k.id) then
			who[k.killerName] = true
		end
	end
	return who
end

function ns.AssaultCompleted(g, c)
	if c.kind ~= "assault" then return false end
	for _, r in pairs(g.regicides or {}) do
		if r.call == c.id then return true end
	end
	-- En curso: las kills de ahora; terminado: las que se guardaron al cerrarlo.
	local kills = c.kills
	if ns.aidCalls[c.id] and not ns.aidCalls[c.id].closed then kills = ns.AidKills(ns.aidCalls[c.id]) end
	return (kills or 0) >= ASSAULT_MIN_KILLS
end

-- El líder ha caído durante el asalto: termina, con su tiempo.
function ns.AssaultWon(call, t)
	if call.closed then return end
	call.ends = math.min(call.ends, ns.Now() - 1)
	call.time = t - call.t
	LG:Print((L["|cffffd100¡Asalto a %s completado en %s!|r"]):format(call.zone, ns.FormatDuration(call.time)))
	finish(call)
	LG:DataChanged()
end

-- Un oficial de la hermandad que la lanzó la termina ahora (manda el resumen).
function ns.EndCall(id)
	local c = ns.aidCalls[id]
	local me = ns.PlayerFullName()
	if not c or c.closed or c.guild ~= LG:GuildName() then return end
	if not ns.CanManageEvents(me) and c.by ~= me then return end
	c.ends = ns.Now() - 1
	-- El resumen lo manda quien termina (aunque no la lanzara él).
	local by, approvedBy = c.by, c.approvedBy
	c.approvedBy = me
	finish(c)
	c.by, c.approvedBy = by, approvedBy
	LG:Send("AIDCLOSE", { id = id, guild = c.guild, by = me })
	LG:DataChanged()
end

-- Los de mi hermandad se enteran de que se ha terminado (el resumen va por la red).
ns.handlers.AIDCLOSE = function(sender, d)
	local c = type(d) == "table" and ns.aidCalls[d.id]
	if not c or c.closed or c.guild ~= LG:GuildName() or d.by ~= sender then return end
	if not ns.CanManageEvents(sender) and c.by ~= sender then return end
	c.ends = math.min(c.ends, ns.Now() - 1)
	c.closed = true
	LG:DataChanged()
end

-- Cada poco: llegada a las llamadas a las que he respondido y cierre de las terminadas.
function Aid:Tick()
	local now = ns.Now()
	local g = LG:GuildData()
	for id in pairs(going) do
		local c = ns.aidCalls[id]
		if not c or now > c.ends then
			going[id] = nil
		end
	end
	for _, c in pairs(ns.aidCalls) do
		-- Asalto sin bajas en la ciudad en 2 horas: se da por terminado.
		if c.kind == "assault" and not c.closed and c.guild == LG:GuildName() and now - ns.AssaultActivity(c) > ASSAULT_IDLE then
			c.ends = now - 1
		end
		if now > c.ends and not c.closed then
			finish(c)
			LG:DataChanged()
		end
	end
end

-- Última actividad de un asalto: la última baja en la ciudad o, si no hay, su inicio.
function ns.AssaultActivity(c)
	local g = LG:GuildData()
	local last = c.t
	for _, k in pairs(g and g.kills or {}) do
		if k.t >= c.t and k.t > last and ((c.map and k.map == c.map) or k.zone == c.zone) then last = k.t end
	end
	return last
end

function Aid:OnEnable()
	self:ScheduleRepeatingTimer("Tick", TICK_EVERY)
	-- El líder de una capital: al seleccionarlo, al pasar el ratón y al cambiar su vida.
	ns.RegisterEvent(self, "PLAYER_TARGET_CHANGED", function() ns.CheckLeader("target") end)
	ns.RegisterEvent(self, "UPDATE_MOUSEOVER_UNIT", function() ns.CheckLeader("mouseover") end)
	ns.RegisterEvent(self, "UNIT_HEALTH", function(_, unit)
		if unit == "target" or unit == "focus" or unit == "mouseover" then ns.CheckLeader(unit) end
	end)
end
