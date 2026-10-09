-- Red de hermandades: un canal oculto común a todos los que tienen el addon.
--
-- Va completamente aparte de la hermandad: prefijo propio, solo por canal y con
-- sus propios manejadores (ns.netHandlers). Lo que llega por aquí nunca toca los
-- datos de la hermandad, salvo las guerras en las que participa la tuya, que
-- Modules/Wars.lua valida una a una.
--
--   HI    anuncio de una hermandad: facción, miembros, guerras y vitrina
--   ASK   "acabo de entrar": las hermandades conectadas se anuncian
--   WAR   declaración o respuesta a una guerra (Wars.lua)
--   TICK  marcador de un bando durante una guerra (Wars.lua)
--   LAYER en qué capas están los de un bando antes y durante una guerra (Layer.lua)
--
-- Cada hermandad se anuncia como mucho cada ANNOUNCE_EVERY: al primer miembro
-- conectado al que le toca lo envía y los demás, al oírlo, esperan otra vuelta.
-- En modo prueba todo funciona igual pero por un canal y un prefijo aparte
-- (red de pruebas): solo se oyen entre sí los que tienen el modo prueba, y las
-- hermandades reales no reciben nada. Lo que llega por ahí se marca como de
-- prueba y deja de verse al salir del modo prueba.
--
-- El canal no cruza entre facciones en Forever (lo confirma el código de otros
-- addons): lo de la otra facción llega por el puente de Battle.net (Bridge.lua).
-- El addon lo detecta solo (net.crossFaction) en cuanto oye a la otra facción.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Network = LG:NewModule("Network", "AceEvent-3.0", "AceTimer-3.0")

local NET_PREFIX, TEST_PREFIX = "LantuxNet", "LantuxNetT"
ns.NET_CHANNEL = "GuildmarkNet" -- canal oculto común a todos los que tienen el addon
ns.NET_TEST_CHANNEL = "GuildmarkTest" -- el de la red de pruebas

-- Canal y prefijo de la red en la que estoy (la real o la de pruebas).
local function netChannel() return LG:InTestMode() and ns.NET_TEST_CHANNEL or ns.NET_CHANNEL end
local function netPrefix() return LG:InTestMode() and TEST_PREFIX or NET_PREFIX end
local PROTOCOL = 1
local JOIN_DELAY = 20        -- después de los canales del juego, para no quitarles su número
local ANNOUNCE_EVERY = 600
local ENTRY_TTL = 14 * 86400 -- las hermandades que no se anuncian en 2 semanas desaparecen
local MAX_JOIN_TRIES = 3

local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

ns.netHandlers = {}
local heard = {}  -- [hermandad] = GetTime() del último anuncio oído
local joinTries = 0

---------------------------------------------------------------------------
-- Ajustes de la hermandad (los cambia un oficial y se comparten con la guild)
---------------------------------------------------------------------------

function ns.GuildSetting(key, default)
	local g = LG:GuildData()
	local s = g and g.settings[key]
	if s == nil then return default end
	return s.value
end

function ns.MergeSetting(g, rec, sender)
	if type(rec.key) ~= "string" or type(rec.t) ~= "number" then return false end
	if sender and rec.by ~= sender then return false end
	if not ns.CanManageEvents(rec.by) then return false end
	-- Quién es oficial, los permisos por rango y los nombres de los rangos del addon
	-- solo los decide el maestro de hermandad.
	if rec.key == "officerMaxRank" or rec.key:match("^perm:") then
		if not ns.IsGuildMaster(rec.by) then return false end
		if rec.value ~= nil and (type(rec.value) ~= "number" or rec.value < 0 or rec.value > 9) then return false end
		if rec.key == "officerMaxRank" and rec.value == nil then return false end
	elseif rec.key:match("^rankName:") then
		if not ns.IsGuildMaster(rec.by) then return false end
		if rec.value ~= nil and (type(rec.value) ~= "string" or #rec.value > 24 or rec.value:find("|", 1, true)) then return false end
	end
	local old = g.settings[rec.key]
	if old and (old.t or 0) >= rec.t then return false end
	g.settings[rec.key] = { value = rec.value, by = rec.by, t = rec.t }
	return true
end

ns.handlers.SETTING = function(sender, rec)
	local g = LG:GuildData()
	if g and ns.MergeSetting(g, rec, sender) then LG:DataChanged() end
end

function ns.SetGuildSetting(key, value)
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	if not g or not ns.CanManageEvents(me) then return end
	local old = g.settings[key]
	local rec = { key = key, value = value, by = me, t = math.max(ns.Now(), old and (old.t or 0) + 1 or 0) }
	if not ns.MergeSetting(g, rec) then return end
	LG:Send("SETTING", rec)
	LG:DataChanged()
	if key == "listed" then Network:Announce(true) end
end

---------------------------------------------------------------------------
-- Envío y recepción
---------------------------------------------------------------------------

local function channelIndex()
	if not GetChannelName then return nil end
	local id = GetChannelName(netChannel())
	return (type(id) == "number" and id > 0) and id or nil
end

local function pack(kind, data)
	local ok, serialized = pcall(LibSerialize.Serialize, LibSerialize, { p = PROTOCOL, k = kind, v = LG.VERSION, d = data })
	if not ok then return nil end
	return LibDeflate:CompressDeflate(serialized)
end

local function unpackMessage(compressed)
	local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
	if not serialized then return nil end
	local ok, msg = LibSerialize:Deserialize(serialized)
	if not ok or type(msg) ~= "table" or type(msg.d) ~= "table" or msg.p ~= PROTOCOL then return nil end
	return msg
end

-- Solo por el canal de mi facción. Devuelve el texto enviado, o nil.
local function sendChannel(kind, data, prio)
	if not LG:HasConsent() then return nil end
	local index = channelIndex()
	local compressed = index and pack(kind, data)
	if not compressed then return nil end
	local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)
	local ok = pcall(LG.SendCommMessage, LG, netPrefix(), encoded, "CHANNEL", tostring(index), prio or "NORMAL")
	LG:Debug("red ->", kind, ok and "" or "(error)")
	return ok and encoded or nil
end
function ns.NetSendRaw(kind, data) return sendChannel(kind, data, "NORMAL") ~= nil end

-- Por el canal y, si interesa a la otra facción, por Battle.net (Bridge.lua).
-- Devuelve true si ha salido por alguno.
function ns.NetSend(kind, data, prio)
	if not LG:HasConsent() then return false end
	local encoded = sendChannel(kind, data, prio)
	-- El id del mensaje es el mismo para todos los que lo oyen: el hash del texto.
	local id = ns.Hash(encoded or (pack(kind, data) or ""))
	local bridged = ns.BridgeOriginate and ns.BridgeOriginate(kind, data, id) or 0
	return encoded ~= nil or bridged > 0
end

local function onNetMessage(prefix, encoded, distribution, sender)
	if prefix ~= netPrefix() or distribution ~= "CHANNEL" or not LG.db or not LG:HasConsent() then return end
	sender = ns.FullName(sender)
	if not sender or sender == ns.PlayerFullName() then return end
	local msg = unpackMessage(LibDeflate:DecodeForWoWAddonChannel(encoded))
	local handler = msg and ns.netHandlers[msg.k]
	if handler then
		LG:Debug("red <-", msg.k, sender)
		handler(sender, msg.d, "net")
		-- Si interesa a la otra facción y su autor no tiene puentes, puede pasarlo otro.
		if ns.BridgeConsider and msg.k ~= "RLY" and msg.k ~= "FWD" then ns.BridgeConsider(sender, msg.k, msg.d, ns.Hash(encoded)) end
	end
end
ns.OnNetMessage = onNetMessage -- para las pruebas

-- Códigos para copiar y pegar (plan B si el canal no llega a la otra facción).
local CODE_TAG = "LG1:"

function ns.EncodeCode(kind, data)
	local compressed = pack(kind, data)
	return compressed and (CODE_TAG .. LibDeflate:EncodeForPrint(compressed)) or nil
end

function ns.DecodeCode(text)
	local body = type(text) == "string" and text:match(CODE_TAG .. "(%S+)")
	local compressed = body and LibDeflate:DecodeForPrint(body)
	local msg = compressed and unpackMessage(compressed)
	if not msg then return nil end
	return msg.k, msg.d
end

---------------------------------------------------------------------------
-- Canal
---------------------------------------------------------------------------

function Network:OnEnable()
	LG:RegisterComm(NET_PREFIX, onNetMessage)
	LG:RegisterComm(TEST_PREFIX, onNetMessage)
	self:ScheduleTimer("Join", JOIN_DELAY)
	self:ScheduleRepeatingTimer("Tick", 60)
	-- Al entrar o salir del modo prueba se cambia de canal.
	self:RegisterMessage("LANTUX_GUILD_CHANGED", "SwitchNetwork")
end

-- Estado de la red en la que estoy: la de pruebas lleva el suyo aparte.
local function status()
	local global = LG.db.global
	if not LG:InTestMode() then return global.net end
	global.netTest = global.netTest or {}
	return global.netTest
end
ns.NetState = status

function Network:SwitchNetwork()
	local other = LG:InTestMode() and ns.NET_CHANNEL or ns.NET_TEST_CHANNEL
	if GetChannelName and LeaveChannelByName then
		local id = GetChannelName(other)
		if type(id) == "number" and id > 0 then pcall(LeaveChannelByName, other) end
	end
	wipe(heard)
	joinTries = 0
	if ns.BridgeReset then ns.BridgeReset() end
	self:ScheduleTimer("Join", 2)
end

function Network:Join()
	if not LG:HasConsent() then return end
	if channelIndex() then
		status().channel = channelIndex()
		return
	end
	if joinTries >= MAX_JOIN_TRIES then return end
	joinTries = joinTries + 1
	local join = JoinTemporaryChannel or JoinChannelByName
	if not join then
		status().error = "JoinTemporaryChannel no existe"
		return
	end
	local ok, err = pcall(join, netChannel())
	if not ok then
		status().error = tostring(err)
		return
	end
	-- Canal oculto: fuera de todas las ventanas de chat.
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local frame = _G["ChatFrame" .. i]
		if frame and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, frame, netChannel()) end
	end
	self:ScheduleTimer(function()
		local index = channelIndex()
		status().channel = index
		status().joined = index and ns.Now() or nil
		status().error = not index and "sin número de canal" or nil
		if index then
			ns.NetSend("ASK", {})
			self:Announce(true)
		end
	end, 3)
end

function Network:Tick()
	if not channelIndex() then return self:Join() end
	self:Announce(false)
end

---------------------------------------------------------------------------
-- Directorio
---------------------------------------------------------------------------

local function count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

-- Lo que la hermandad cuenta de sí misma en la red.
function ns.GuildAnnouncement()
	local guild = LG:GuildName()
	local g = LG:GuildData()
	if not guild or not g then return nil end
	if not ns.GuildSetting("listed", true) then return { guild = guild, hidden = true } end
	local members, online = 0, 0
	for _, r in pairs(ns.roster) do
		members = members + 1
		if r.online then online = online + 1 end
	end
	local record = ns.WarRecord and ns.WarRecord() or {}
	return {
		guild = guild,
		faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
		members = members,
		online = online,
		addon = count(g.members),
		rating = record.rating,
		wins = record.wins,
		losses = record.losses,
		draws = record.draws,
		trophies = record.showcase,
		stats = ns.GuildSeasonStats and ns.GuildSeasonStats() or nil, -- clasificación de la facción (Faction.lua)
	}
end

function Network:Announce(force)
	if not LG:HasConsent() or not channelIndex() then return end
	local guild = LG:GuildName()
	if not guild then return end
	local last = heard[guild]
	if not force and last and GetTime() - last < ANNOUNCE_EVERY then return end
	-- Un pequeño margen al azar para que no se anuncien varios miembros a la vez.
	self:ScheduleTimer(function()
		if not force and heard[guild] and GetTime() - heard[guild] < ANNOUNCE_EVERY then return end
		local data = ns.GuildAnnouncement()
		if data and ns.NetSend("HI", data, "BULK") then heard[guild] = GetTime() end
	end, force and 0 or math.random() * 30)
end

local function num(v, max)
	v = tonumber(v)
	if not v or v ~= v then return nil end
	return math.max(0, math.min(max or 100000, math.floor(v)))
end

local function str(v, max)
	return type(v) == "string" and v ~= "" and v:sub(1, max or 60) or nil
end

ns.netHandlers.HI = function(sender, d)
	local guild = str(d.guild, 48)
	if not guild then return end
	heard[guild] = GetTime()
	if guild == LG:GuildName() then return end
	local dir = LG.db.global.directory
	if d.hidden then
		if dir[guild] then
			dir[guild] = nil
			LG:DataChanged()
		end
		return
	end
	if d.faction ~= "Horde" and d.faction ~= "Alliance" then return end
	local mine = UnitFactionGroup and UnitFactionGroup("player")
	if mine and d.faction ~= mine then status().crossFaction = ns.Now() end
	local trophies = {}
	for i, tr in ipairs(type(d.trophies) == "table" and d.trophies or {}) do
		if i > 5 then break end
		if type(tr) == "table" and str(tr.title, 80) then
			trophies[#trophies + 1] = { title = str(tr.title, 80), sub = str(tr.sub, 80), t = num(tr.t, 4102444800) }
		end
	end
	dir[guild] = {
		guild = guild, faction = d.faction,
		members = num(d.members, 1000), online = num(d.online, 1000), addon = num(d.addon, 1000),
		rating = num(d.rating, 5000), wins = num(d.wins), losses = num(d.losses), draws = num(d.draws),
		trophies = trophies, t = ns.Now(), by = sender,
		stats = ns.SanitizeSeasonStats and ns.SanitizeSeasonStats(d.stats) or nil,
		-- De la red de pruebas: solo se ve en modo prueba (y caduca como las demás).
		test = LG:InTestMode() or nil, live = LG:InTestMode() or nil,
	}
	LG:DataChanged()
end

-- Alguien acaba de entrar: se anuncia un miembro de cada hermandad, no todos.
ns.netHandlers.ASK = function()
	local guild = LG:GuildName()
	if not guild then return end
	Network:ScheduleTimer(function()
		if heard[guild] and GetTime() - heard[guild] < 60 then return end
		Network:Announce(true)
	end, 2 + math.random() * 8)
end

-- Hermandades del directorio, más recientes primero. En modo prueba solo las
-- de prueba (las de ejemplo y las de la red de pruebas); fuera, solo las reales.
function ns.Directory()
	local list = {}
	local dir = LG.db.global.directory
	local now = ns.Now()
	local test = LG:InTestMode()
	for guild, e in pairs(dir) do
		if (not e.test or e.live) and now - (e.t or 0) > ENTRY_TTL then
			dir[guild] = nil
		elseif (e.test and true or false) == test then
			list[#list + 1] = e
		end
	end
	table.sort(list, function(a, b) return (a.rating or 1000) > (b.rating or 1000) end)
	return list
end

function ns.DirectoryEntry(guild)
	local e = LG.db.global.directory[guild]
	if e and (e.test and true or false) == LG:InTestMode() then return e end
	return nil
end

function ns.NetStatus()
	local s = status()
	return {
		connected = channelIndex() ~= nil,
		error = s.error,
		crossFaction = s.crossFaction,
		testMode = LG:InTestMode(),
		bridge = ns.BridgeStatus and ns.BridgeStatus() or nil,
	}
end
