-- Capas: en Forever no hay reinos y cada zona se reparte en varias copias.
-- Dos hermandades en capas distintas no se ven, y una guerra entre ellas se
-- queda en nada.
--
-- La capa se lee del GUID de cualquier PNJ: Creature-0-servidor-instancia-
-- CAPA-pnj-aparición. Ese número cambia de una capa a otra (comprobado en
-- Forever: 206 frente a 307 en la misma zona). Cada uno manda la suya con su
-- actividad (ACT, Activity.lua) y, durante una guerra y los 15 minutos de
-- antes, cada hermandad anuncia por la red en qué capas están los suyos
-- (LAYER). Si no coincide con la del rival, se avisa.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Layer = LG:NewModule("Layer", "AceEvent-3.0", "AceTimer-3.0")

local SEND_EVERY = 60
local FRESH = 15 * 60  -- una lectura vale 15 minutos (se renueva sola con las placas de nombre)
local BEFORE = 15 * 60 -- se anuncia desde 15 minutos antes de la guerra

local mine            -- { id, map, t }: mi última lectura
local heard = {}      -- [idGuerra] = GetTime() del último anuncio de mi hermandad
local warned = {}     -- [idGuerra:nuestra:suya] = true

-- Número de capa de un GUID de PNJ, o nil (jugadores, mascotas...).
function ns.ParseLayer(guid)
	if type(guid) ~= "string" then return nil end
	local kind, id = guid:match("^(%a+)%-0%-%d+%-%d+%-(%d+)%-%d+%-")
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end

---------------------------------------------------------------------------
-- Número de capa (1, 2, 3...), como NovaWorldBuffs: el id del servidor (206,
-- 17292...) no dice nada, así que se apuntan los ids vistos en cada continente
-- (míos, de los compañeros y de las llamadas) y se numeran de menor a mayor.
-- Se olvidan a las 6 horas (los reinicios rehacen las capas). Con pocos vistos,
-- el número puede recolocarse al descubrir otra capa.
---------------------------------------------------------------------------

local KNOWN_TTL = 6 * 3600

function ns.ContinentOf(map)
	local guard = 0
	while map and C_Map and C_Map.GetMapInfo and guard < 10 do
		local ok, info = pcall(C_Map.GetMapInfo, map)
		if not ok or not info then return nil end
		if info.mapType == 2 then return info.mapID end -- continente
		map = info.parentMapID
		guard = guard + 1
	end
	return nil
end

-- Apunta un id de capa visto en ese mapa.
function ns.NoteLayer(id, map)
	id = tonumber(id)
	if not id or not LG.db then return end
	local key = tostring(ns.ContinentOf(map) or map or "?")
	local known = LG.db.global.layerKnown
	known[key] = known[key] or {}
	known[key][id] = ns.Now()
end

-- Número de capa (1, 2...) de un id en el continente de ese mapa, o nil.
function ns.LayerNumber(id, map)
	id = tonumber(id)
	if not id or not LG.db then return nil end
	local key = tostring(ns.ContinentOf(map) or map or "?")
	local list = LG.db.global.layerKnown[key]
	if not list then return nil end
	local now, ids = ns.Now(), {}
	for known, t in pairs(list) do
		if now - t > KNOWN_TTL then list[known] = nil else ids[#ids + 1] = known end
	end
	table.sort(ids)
	for i, known in ipairs(ids) do
		if known == id then return i end
	end
	return nil
end

-- "capa 2" (o "capa ?" si aún no se puede numerar).
function ns.LayerLabel(id, map)
	local n = ns.LayerNumber(id, map)
	return n and (L["capa %d"]):format(n) or L["capa ?"]
end

local function read(unit)
	if not UnitGUID or not UnitExists or not UnitExists(unit) or (UnitIsPlayer and UnitIsPlayer(unit)) then return end
	local ok, guid = pcall(UnitGUID, unit)
	if not ok or (issecretvalue and issecretvalue(guid)) then return end
	local id = ns.ParseLayer(guid)
	if not id then return end
	local map = ns.CurrentMap()
	local changed = not mine or mine.id ~= id or mine.map ~= map
	mine = { id = id, map = map, t = ns.Now() }
	ns.NoteLayer(id, map)
	if changed then
		LG:Debug("capa", id)
		if ns.OnLayerChanged then ns.OnLayerChanged() end
		LG:DataChanged()
	end
end
ns.ReadLayer = read -- para las pruebas

-- Mi capa en la zona en la que estoy, si la he leído hace poco.
function ns.CurrentLayer()
	if not mine or ns.Now() - mine.t > FRESH or mine.map ~= ns.CurrentMap() then return nil end
	return mine.id
end

-- Capa de un miembro (la mía o la que manda con su actividad) y la zona en la que la leyó.
function ns.MemberLayer(name)
	if name == ns.PlayerFullName() then
		return ns.CurrentLayer(), GetZoneText and GetZoneText() or nil, ns.CurrentMap()
	end
	local a = ns.activity[name]
	if a and a.layer and ns.Now() - (a.t or 0) <= FRESH then return a.layer, a.zone, a.map end
	return nil
end

-- El número de capa es un id interno del servidor (206, 17292...), no "capa 1, 2":
-- no se enseña. Lo que importa es si es la tuya.
-- Texto de la columna Capa: "tuya" (verde) u "otra" (rojo) si está en tu zona; si no, "-".
function ns.MemberLayerText(name)
	local id, zone, map = ns.MemberLayer(name)
	if not id then return "|cff9d9d9d-|r" end
	local n = ns.LayerNumber(id, map) or "?"
	local mine, myZone = ns.CurrentLayer(), GetZoneText and GetZoneText() or nil
	if name == ns.PlayerFullName() or (mine and zone == myZone and id == mine) then return "|cff5ad55a" .. n .. "|r" end
	if mine and zone == myZone then return "|cffff6b5a" .. n .. "|r" end
	return tostring(n)
end

-- Capa de una llamada respecto a la mía: "en tu capa" / "en otra capa" / "capa sin leer".
function ns.CallLayerText(call)
	if not call.layer then return L["capa sin leer"] end
	local label = ns.LayerLabel(call.layer, call.map)
	local mine = ns.CurrentLayer()
	if not mine or not call.map or ns.CurrentMap() ~= call.map then return label end
	return mine == call.layer and ("|cff5ad55a" .. label .. " " .. L["(la tuya)"] .. "|r") or ("|cffff6b5a" .. label .. " " .. L["(otra)"] .. "|r")
end

local function top(counts)
	local best, n = nil, 0
	for id, c in pairs(counts or {}) do
		if c > n or (c == n and best and id < best) then best, n = id, c end
	end
	return best
end

-- Capas de los nuestros en la zona de la guerra: { [capa] = jugadores }, y la de más gente.
function ns.WarLayers(w)
	local zoneName = ns.MapName(w.map, w.zone)
	local counts = {}
	local me = ns.PlayerFullName()
	local now = ns.Now()
	local function add(id) counts[id] = (counts[id] or 0) + 1 end
	if w.map and ns.CurrentMap() == w.map and ns.CurrentLayer() then add(ns.CurrentLayer()) end
	for name, a in pairs(ns.activity) do
		if name ~= me and a.layer and (a.zone == zoneName or a.zone == w.zone) and now - (a.t or 0) <= FRESH then add(a.layer) end
	end
	return counts, top(counts)
end

-- { ours, theirs, mismatch } con lo que se sabe de cada bando.
function ns.WarLayerStatus(w)
	local _, ours = ns.WarLayers(w)
	local e = w.enemyLayers
	local theirs = e and ns.Now() - (e.t or 0) <= FRESH and top(e.layers) or nil
	return { ours = ours, theirs = theirs, mismatch = ours ~= nil and theirs ~= nil and ours ~= theirs }
end

-- Línea para la tarjeta de la guerra (short: versión corta para el marcador en pantalla).
function ns.WarLayerText(w, short)
	local s = ns.WarLayerStatus(w)
	if short then
		if s.mismatch then return ("|cffff6b5a" .. L["Capas distintas: %d / %d"] .. "|r"):format(s.ours, s.theirs) end
		if s.ours and s.theirs then return ("|cff5ad55a" .. L["Misma capa (%d)"] .. "|r"):format(s.ours) end
		if s.ours then return "|cff9d9d9d" .. L["Capa del rival: ?"] .. "|r" end
		return "|cff9d9d9d" .. L["Capa: pasa el ratón por un PNJ"] .. "|r"
	end
	if s.mismatch then
		return ("|cffff6b5a" .. L["Capas distintas: vosotros en la %d, ellos en la %d. Así no os veréis."] .. "|r"):format(s.ours, s.theirs)
	elseif s.ours and s.theirs then
		return ("|cff5ad55a" .. L["Misma capa que el rival (%d)."] .. "|r"):format(s.ours)
	elseif s.ours then
		return ("|cff9d9d9d" .. L["Vuestra capa: %d · la del rival aún no se sabe."] .. "|r"):format(s.ours)
	end
	return "|cff9d9d9d" .. L["Capa sin leer: pasad el ratón por un PNJ de la zona."] .. "|r"
end

ns.netHandlers.LAYER = function(sender, d)
	local g = LG:GuildData()
	local guild = LG:GuildName()
	if not g or not guild or type(d.id) ~= "string" or type(d.layers) ~= "table" then return end
	local w = g.wars[d.id]
	if not w then return end
	if d.guild == guild then
		heard[d.id] = GetTime()
		return
	end
	-- Solo el rival de esa guerra, y nunca alguien de mi hermandad.
	if d.guild ~= ns.WarEnemy(w, guild) or ns.roster[sender] then return end
	local layers, n = {}, 0
	for id, c in pairs(d.layers) do
		n = n + 1
		if n > 20 then break end
		id, c = tonumber(id), tonumber(c)
		if id and c then layers[id] = math.max(0, math.min(1000, math.floor(c))) end
	end
	w.enemyLayers = { layers = layers, t = ns.Now() }
	LG:DataChanged()
end

function Layer:Tick()
	local g = LG:GuildData()
	if not g or not LG:HasConsent() or ns.WARS_PAUSED then return end
	local now = ns.Now()
	for id, w in pairs(g.wars) do
		local phase = ns.WarPhase(w, now)
		if phase == "active" or (phase == "upcoming" and w.start - now <= BEFORE) then
			local counts, ours = ns.WarLayers(w)
			-- Lo anuncia un solo miembro: si otro lo ha hecho hace poco, se espera.
			if ours and (not heard[id] or GetTime() - heard[id] > SEND_EVERY - 5) then
				if ns.NetSend("LAYER", { id = id, guild = LG:GuildName(), layers = counts, t = now }) then heard[id] = GetTime() end
			end
			local s = ns.WarLayerStatus(w)
			local key = id .. ":" .. tostring(s.ours) .. ":" .. tostring(s.theirs)
			if s.mismatch and not warned[key] then
				warned[key] = true
				LG:Print((L["|cffff6b5aGuerra contra <%s>: estáis en capas distintas|r (vosotros %d, ellos %d). Para cambiar, entrad en el grupo de alguien de vuestra facción que esté en la suya; la banda sigue la capa del líder."]):format(
					ns.WarEnemy(w), s.ours, s.theirs))
				if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
			end
		end
	end
end

function Layer:OnEnable()
	ns.RegisterEvent(self, "PLAYER_TARGET_CHANGED", function() read("target") end)
	ns.RegisterEvent(self, "UPDATE_MOUSEOVER_UNIT", function() read("mouseover") end)
	ns.RegisterEvent(self, "NAME_PLATE_UNIT_ADDED", function(_, unit) if unit then read(unit) end end)
	-- Al cambiar de zona o de grupo la capa puede cambiar: hay que volver a leerla.
	for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
		ns.RegisterEvent(self, event, function() mine = nil end)
	end
	self:ScheduleRepeatingTimer("Tick", 30)
end
