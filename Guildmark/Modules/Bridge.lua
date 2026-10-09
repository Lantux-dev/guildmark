-- Puente entre facciones por Battle.net.
--
-- En Forever los canales no cruzan entre Horda y Alianza, así que la red de
-- hermandades (Network.lua) no llega a la otra facción. Lo que sí cruza son los
-- mensajes de addon entre amigos de Battle.net (BNSendGameData).
--
-- Funcionamiento (dos saltos como mucho):
--   1. Un mensaje de la red que interesa a la otra facción (HI, WAR, TICK) se
--      reenvía por Battle.net a amigos de la otra facción que tengan el addon.
--      Lo reenvía quien lo origina si tiene puentes; si no, otro de su facción
--      que los tenga, tras una espera al azar, y avisa en el canal (FWD) para
--      que los demás no lo repitan.
--   2. Quien lo recibe por Battle.net lo usa y lo repite en el canal de SU
--      facción como RLY, tras una espera al azar y solo si nadie lo ha hecho ya.
-- Los mensajes llevan un id para descartar repetidos, y lo que llega reenviado
-- se trata como un código pegado (via = "relay"): nunca puede hablar por tu
-- propia hermandad (Wars.lua lo comprueba).
-- En modo prueba va igual pero con otro prefijo: solo hablan entre sí los que
-- tienen el modo prueba (la red de pruebas de Network.lua).
local _, ns = ...
local LG = ns.LG

local Bridge = LG:NewModule("Bridge", "AceEvent-3.0", "AceTimer-3.0")

local REAL_PREFIX, TEST_PREFIX = "LantuxBr", "LantuxBrT"
local function prefix() return LG:InTestMode() and TEST_PREFIX or REAL_PREFIX end
local MAX_BRIDGES = 5        -- amigos de la otra facción a los que se envía cada mensaje
local PEER_TTL = 30 * 60     -- un amigo cuenta como puente si respondió en la última media hora
local PING_EVERY = 10 * 60
local MAX_SIZE = 4000        -- límite de BNSendGameData
local BUDGET = 1000          -- bytes por segundo
local SEEN_TTL = 120
local RELAYABLE = { HI = true, WAR = true, TICK = true, LAYER = true }

local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

local peers = {}    -- [gameAccountID] = { t, name, faction }
local seen = {}     -- [id] = GetTime(): ya tratado (recibido, reenviado o repetido)
local pending = {}  -- [id] = true: reenvío programado, se cancela si otro lo hace antes
local tokens, lastRefill = BUDGET, 0
local lastPing

local function now() return GetTime() end

local function myFaction() return UnitFactionGroup and UnitFactionGroup("player") or nil end

-- "Horde"/"Alliance" a partir de lo que dé Battle.net (puede venir traducido).
local function factionToken(name)
	if name == "Horde" or name == FACTION_HORDE then return "Horde" end
	if name == "Alliance" or name == FACTION_ALLIANCE then return "Alliance" end
	return nil
end

local function remember(id)
	seen[id] = now()
	for k, t in pairs(seen) do
		if now() - t > SEEN_TTL then seen[k] = nil end
	end
end

local function spend(bytes)
	local t = now()
	tokens = math.min(BUDGET, tokens + (t - lastRefill) * BUDGET)
	lastRefill = t
	if tokens < bytes then return false end
	tokens = tokens - bytes
	return true
end

local function pack(tbl)
	local ok, serialized = pcall(LibSerialize.Serialize, LibSerialize, tbl)
	if not ok then return nil end
	return LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(serialized))
end

local function unpackText(text)
	local compressed = LibDeflate:DecodeForWoWAddonChannel(text or "")
	local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
	if not serialized then return nil end
	local ok, tbl = LibSerialize:Deserialize(serialized)
	return ok and type(tbl) == "table" and tbl or nil
end

local function status()
	local net = ns.NetState()
	net.bridge = net.bridge or {}
	return net.bridge
end

---------------------------------------------------------------------------
-- Amigos de Battle.net
---------------------------------------------------------------------------

-- Amigos conectados al mismo juego (Forever), con su facción.
function ns.BridgeFriends()
	local list = {}
	if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo) then
		return list, "sin API de Battle.net"
	end
	local okN, numFriends = pcall(BNGetNumFriends)
	for i = 1, (okN and numFriends or 0) do
		local okA, accounts = pcall(C_BattleNet.GetFriendNumGameAccounts, i)
		for j = 1, (okA and accounts or 0) do
			local ok, info = pcall(C_BattleNet.GetFriendGameAccountInfo, i, j)
			if ok and type(info) == "table" and info.isOnline and info.gameAccountID
				and info.clientProgram == (BNET_CLIENT_WOW or "WoW")
				and (not info.wowProjectID or not WOW_PROJECT_ID or info.wowProjectID == WOW_PROJECT_ID) then
				list[#list + 1] = { id = info.gameAccountID, name = info.characterName, faction = factionToken(info.factionName) }
			end
		end
	end
	return list
end

local function sendTo(id, tbl)
	local text = pack(tbl)
	if not text or #text > MAX_SIZE or not spend(#text) then return false end
	return pcall(BNSendGameData, id, prefix(), text)
end

function Bridge:Ping()
	if not LG:HasConsent() or not BNSendGameData then return end
	local s = status()
	if lastPing and now() - lastPing < 60 then return end -- como mucho una vez por minuto (GetTime: no se guarda)
	lastPing = now()
	local friends, err = ns.BridgeFriends()
	s.lastScan, s.friends, s.error = ns.Now(), #friends, err
	for _, f in ipairs(friends) do sendTo(f.id, { k = "BQ", f = myFaction() }) end
end

-- Amigos de la otra facción que tienen el addon (respondieron hace poco).
function ns.BridgePeers()
	local list = {}
	local mine = myFaction()
	for id, p in pairs(peers) do
		if now() - p.t <= PEER_TTL and p.faction and p.faction ~= mine then list[#list + 1] = { id = id, name = p.name, faction = p.faction } end
	end
	table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
	return list
end

---------------------------------------------------------------------------
-- Envío
---------------------------------------------------------------------------

-- Reenvía a la otra facción. Devuelve cuántos puentes lo recibieron.
local function forward(env)
	if not LG:HasConsent() or not BNSendGameData then return 0 end
	local n = 0
	for _, p in ipairs(ns.BridgePeers()) do
		if n >= MAX_BRIDGES then break end
		if sendTo(p.id, { k = "ENV", e = env }) then n = n + 1 end
	end
	if n > 0 then status().lastForward = ns.Now() end
	return n
end
ns.BridgeForward = forward -- para las pruebas

-- Mensaje propio que acaba de salir por el canal (Network.lua lo llama).
function ns.BridgeOriginate(kind, data, id)
	if not RELAYABLE[kind] then return 0 end
	remember(id)
	local n = forward({ o = ns.PlayerFullName(), of = myFaction(), id = id, k = kind, d = data })
	if n > 0 and ns.NetSendRaw then ns.NetSendRaw("FWD", { id = id }) end
	return n
end

-- Mensaje de otro de mi facción oído en el canal: si nadie lo ha pasado aún y
-- tengo puentes, lo paso yo tras una espera al azar.
function ns.BridgeConsider(sender, kind, data, id)
	if not RELAYABLE[kind] or seen[id] or pending[id] or #ns.BridgePeers() == 0 then return end
	pending[id] = true
	Bridge:ScheduleTimer(function()
		pending[id] = nil
		if seen[id] then return end
		remember(id)
		if forward({ o = sender, of = myFaction(), id = id, k = kind, d = data }) > 0 and ns.NetSendRaw then
			ns.NetSendRaw("FWD", { id = id })
		end
	end, 1 + math.random() * 3)
end

---------------------------------------------------------------------------
-- Recepción
---------------------------------------------------------------------------

local function deliver(env)
	local handler = ns.netHandlers[env.k]
	if handler and type(env.d) == "table" then handler(env.o, env.d, "relay") end
end

-- Llega por Battle.net desde la otra facción.
function ns.OnBridgeMessage(msgPrefix, text, _, senderID)
	if not LG.db or msgPrefix ~= prefix() or not LG:HasConsent() then return end
	local msg = unpackText(text)
	if not msg then return end
	if msg.k == "BQ" or msg.k == "BA" then
		local f = factionToken(msg.f)
		peers[senderID] = { t = now(), name = peers[senderID] and peers[senderID].name, faction = f }
		for _, fr in ipairs(ns.BridgeFriends()) do
			if fr.id == senderID then peers[senderID].name = fr.name end
		end
		if msg.k == "BQ" then sendTo(senderID, { k = "BA", f = myFaction() }) end
		return
	end
	local env = msg.k == "ENV" and msg.e
	if type(env) ~= "table" or type(env.id) ~= "string" or not RELAYABLE[env.k] or type(env.o) ~= "string" then return end
	if env.of and env.of == myFaction() then return end -- solo de la otra facción
	if seen[env.id] then return end
	remember(env.id)
	status().lastReceived = ns.Now()
	deliver(env)
	-- Repetirlo en el canal de mi facción, salvo que otro puente lo haga antes.
	if ns.NetSendRaw then
		pending[env.id] = true
		Bridge:ScheduleTimer(function()
			if not pending[env.id] then return end
			pending[env.id] = nil
			ns.NetSendRaw("RLY", env)
		end, 0.3 + math.random() * 2)
	end
end

-- Llegan por el canal de mi facción (Network.lua las entrega aquí).
ns.netHandlers.RLY = function(_, env)
	if type(env) ~= "table" or type(env.id) ~= "string" or not RELAYABLE[env.k] or type(env.o) ~= "string" then return end
	pending[env.id] = nil -- ya lo ha repetido otro
	if seen[env.id] then return end
	remember(env.id)
	deliver(env)
end

ns.netHandlers.FWD = function(_, d)
	if type(d.id) == "string" then
		pending[d.id] = nil
		remember(d.id)
	end
end

-- Al cambiar entre la red real y la de pruebas: los puentes se vuelven a buscar.
function ns.BridgeReset()
	wipe(peers); wipe(seen); wipe(pending)
	lastPing = nil
	Bridge:ScheduleTimer("Ping", 5)
end

function ns.BridgeStatus()
	local s = LG.db and ns.NetState().bridge or {}
	return { peers = #ns.BridgePeers(), friends = s.friends, error = s.error, lastReceived = s.lastReceived, available = BNSendGameData ~= nil }
end

function Bridge:OnEnable()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, REAL_PREFIX)
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, TEST_PREFIX)
	end
	ns.RegisterEvent(self, "BN_CHAT_MSG_ADDON", function(_, ...) ns.OnBridgeMessage(...) end)
	ns.RegisterEvent(self, "BN_FRIEND_INFO_CHANGED", function()
		-- Un amigo entra o sale: se le pregunta enseguida, sin esperar a la vuelta.
		if not self.pingSoon then
			self.pingSoon = self:ScheduleTimer(function() self.pingSoon = nil; self:Ping() end, 15)
		end
	end)
	self:ScheduleTimer("Ping", 25)
	self:ScheduleRepeatingTimer("Ping", PING_EVERY)
end
