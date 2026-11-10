-- Comunicación entre addons por el canal de la guild.
--
-- Cada mensaje es { p = protocolo, k = tipo, v = versión del addon, d = datos },
-- serializado con LibSerialize, comprimido con LibDeflate y troceado por AceComm.
--
-- Tipos:
--   ME      registro propio de un miembro (solo lo envía su dueño)
--   KILL    kill o muerte en PvP (la envía quien la vivió)
--   RUN     jefe derrotado en mazmorra (cada miembro del grupo es testigo)
--   CACHE   lote de hermandades vistas de otros jugadores
--   HELLO   "acabo de entrar; esto es lo último que tengo"
--   CLAIM   "yo respondo a ese HELLO", para que no respondan todos
--   SYNC    respuesta a un HELLO, por susurro (con resumen por informante y día)
--   FILL    lo que a quien respondió le faltaba según ese resumen, por susurro
--   FUNDS   la colecta del banco, del tesorero a quien entra sin ella (Modules/BankFund.lua)
--   FORGET  un miembro pide que se borren sus datos
-- Los de cada módulo (ORDER, EVENT, SIGNUP, ATTEND, ADJUST, TARGET, AUCTION,
-- BID, SPEND, VOID, SETTING, WAR, WARREP) están descritos en su archivo.
-- La red entre hermandades usa otro prefijo (Modules/Network.lua).
local _, ns = ...
local L = ns.L
local LG = ns.LG

local PREFIX = "LantuxGuild"
ns.COMM_PREFIX = PREFIX
local PROTOCOL = 1
local SYNC_MAX_KILLS = 500
local SYNC_MAX_RUNS = 200
local SYNC_MAX_CACHE = 500

local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

ns.handlers = {}

-- Aviso en el chat de hermandad (lo ven también los que no tienen el addon). Lo escribe
-- solo quien hace la acción, para que no salga repetido. En modo prueba, al grupo.
-- Los oficiales lo apagan en Ajustes (ajuste de hermandad "guildChat").
function ns.GuildAnnounce(text)
	if not LG:HasConsent() or not text or not (ns.GuildSetting and ns.GuildSetting("guildChat", true)) then return end
	local channel = "GUILD"
	if LG:InTestMode() then
		channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or nil
		if not channel then return end
	elseif not IsInGuild() then
		return
	end
	-- El servidor no admite texturas en el chat; los enlaces de objetos sí.
	text = ("[Guildmark] " .. text):gsub("|T.-|t", "")
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	if send then pcall(send, text:sub(1, 255), channel) end
end

function LG:Send(kind, data, channel, target, prio)
	if not self:HasConsent() then return end
	channel = channel or "GUILD"
	if channel == "GUILD" then
		if self:InTestMode() then
			-- Modo prueba: nunca por el canal de la hermandad real; el grupo hace de
			-- hermandad. Solo, no se envía nada.
			channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or nil
			if not channel then return end
		elseif not IsInGuild() then
			return
		end
	end
	-- Un fallo al empaquetar no debe romper la acción que lo provocó (una kill, el
	-- grupo...): se pierde ese mensaje y queda constancia en el modo debug.
	local ok, serialized = pcall(LibSerialize.Serialize, LibSerialize, { p = PROTOCOL, k = kind, v = self.VERSION, d = data })
	if not ok then
		self:Debug("no se pudo empaquetar", kind, serialized)
		return
	end
	local t0 = ns.PerfStart()
	local encoded = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(serialized))
	ns.PerfStop("enviar: comprimir", t0)
	self:SendCommMessage(PREFIX, encoded, channel, target, prio or "NORMAL")
	self:Debug("->", kind, channel, target or "", #encoded .. "b")
end

-- Envíos grandes (SYNC, FILL) en trozos. Comprimir de una vez todo el estado de una
-- hermandad grande (cientos de bajas, la caché, el banco...) pasaba del tiempo que el
-- juego deja a un script ("script ran too long" en LibDeflate). Cada trozo se comprime
-- y se envía en su propio momento. Los manejadores fusionan registro a registro, así
-- que da igual en cuántos mensajes llegue.
local PART_SIZE = 12000 -- tamaño aproximado (sin comprimir) de cada trozo
local NO_SPLIT = { bankSnap = true, killDigest = true, runDigest = true } -- se leen enteras

local function sizeOf(v, depth)
	local tv = type(v)
	if tv == "string" then return #v + 2 end
	if tv ~= "table" then return 9 end
	if (depth or 0) > 6 then return 64 end
	local n = 2
	for k, x in pairs(v) do n = n + sizeOf(k, 7) + sizeOf(x, (depth or 0) + 1) end
	return n
end

local function splitPayload(data)
	local parts, cur, curSize = {}, {}, 0
	local function flush()
		if next(cur) then parts[#parts + 1] = cur end
		cur, curSize = {}, 0
	end
	for key, value in pairs(data) do
		local size = sizeOf(value)
		if size <= PART_SIZE or type(value) ~= "table" or NO_SPLIT[key] then
			if curSize + size > PART_SIZE then flush() end
			cur[key] = value
			curSize = curSize + size
		else
			-- Colección grande: en trozos, como lista o con sus claves según venga.
			local isList = #value > 0
			local chunk, chunkSize = {}, 0
			for k, v in pairs(value) do
				local s = sizeOf(v) + sizeOf(k, 7)
				if chunkSize + s > PART_SIZE and next(chunk) then
					parts[#parts + 1] = { [key] = chunk }
					chunk, chunkSize = {}, 0
				end
				if isList then chunk[#chunk + 1] = v else chunk[k] = v end
				chunkSize = chunkSize + s
			end
			if next(chunk) then parts[#parts + 1] = { [key] = chunk } end
		end
	end
	flush()
	return parts
end
ns.SplitPayload = splitPayload

function LG:SendParts(kind, data, channel, target, prio)
	local parts = splitPayload(data)
	for i, part in ipairs(parts) do
		-- Numerados: quien recibe sabe cuándo ha llegado el último.
		part._part, part._parts = i, #parts
		if i == 1 then
			self:Send(kind, part, channel, target, prio)
		else
			self:ScheduleTimer(function() self:Send(kind, part, channel, target, prio) end, (i - 1) * 0.3)
		end
	end
	return #parts
end

function LG:OnCommReceived(prefix, encoded, distribution, sender)
	if prefix ~= PREFIX or not self:HasConsent() then return end
	-- rawSender, tal cual lo da el juego, se usa como destino de los susurros: el
	-- formato que acepta Forever (con o sin apellido o reino) está por confirmar.
	local rawSender = sender
	sender = ns.FullName(sender)
	if sender == ns.PlayerFullName() then return end
	-- Los datos de la hermandad solo llegan por la hermandad, el grupo (modo prueba)
	-- o susurro de un miembro. Nunca por un canal: la red entre hermandades usa
	-- otro prefijo y sus propios manejadores (Modules/Network.lua).
	if distribution ~= "GUILD" and distribution ~= "PARTY" and distribution ~= "RAID" and distribution ~= "WHISPER" then return end
	if distribution == "WHISPER" and not ns.IsGuildMember(sender) then return end

	local t0 = ns.PerfStart()
	local compressed = LibDeflate:DecodeForWoWAddonChannel(encoded)
	local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
	if not serialized then return end
	local ok, msg = LibSerialize:Deserialize(serialized)
	ns.PerfStop("recibir: descomprimir", t0)
	if not ok or type(msg) ~= "table" or type(msg.d) ~= "table" then return end
	-- El canal del grupo solo se usa en modo prueba, donde el grupo hace de hermandad;
	-- y en modo prueba se ignora todo lo que llegue de la hermandad real.
	local fromGroup = distribution == "PARTY" or distribution == "RAID"
	if fromGroup and not self:InTestMode() then return end
	if distribution == "GUILD" and self:InTestMode() then return end

	if msg.v and not self.warnedVersion and ns.CompareVersions(msg.v, self.VERSION) > 0 then
		self.warnedVersion = true
		self:Print(L["Hay una versión nueva del addon:"], msg.v)
	end
	if msg.p ~= PROTOCOL then return end

	local handler = ns.handlers[msg.k]
	if handler then
		self:Debug("<-", msg.k, sender, rawSender ~= sender and ("(" .. rawSender .. ")") or "")
		self.lastRawSenders = self.lastRawSenders or {}
		self.lastRawSenders[sender] = rawSender
		-- Para "Sincronizado hace X con Fulano" en Inicio.
		self.lastHeard = { from = sender, t = ns.Now() }
		local t1 = ns.PerfStart()
		handler(sender, msg.d, distribution, rawSender)
		ns.PerfStop("recibir: " .. tostring(msg.k), t1)
	end
end

---------------------------------------------------------------------------
-- Fusión de datos recibidos
---------------------------------------------------------------------------

function ns.MergeMember(g, rec)
	if type(rec.name) ~= "string" then return false end
	local old = g.members[rec.name]
	if old and (old.t or 0) >= (rec.t or 0) then return false end
	g.members[rec.name] = rec
	return true
end

function ns.MergeKill(g, rec)
	if type(rec.id) ~= "string" or g.kills[rec.id] then return false end
	g.kills[rec.id] = rec
	return true
end

function ns.MergeRun(g, rec)
	if type(rec.key) ~= "string" then return false end
	local old = g.runs[rec.key]
	if not old then
		g.runs[rec.key] = rec
		return true
	end
	local changed = false
	for name in pairs(rec.witnesses or {}) do
		if not old.witnesses[name] then
			old.witnesses[name] = true
			changed = true
		end
	end
	return changed
end

function ns.MergeCache(g, entries)
	local changed = false
	for guid, c in pairs(entries) do
		local old = g.guildCache[guid]
		if not old or (old.t or 0) < (c.t or 0) then
			g.guildCache[guid] = c
			changed = true
		end
	end
	return changed
end

function ns.ForgetMember(g, name, guid)
	g.members[name] = nil
	for id, k in pairs(g.kills) do
		if k.reporter == name or k.killer == guid or k.victim == guid then g.kills[id] = nil end
	end
	for id, o in pairs(g.orders or {}) do
		if o.requester == name or o.crafter == name then g.orders[id] = nil end
	end
	for _, list in pairs(g.signups or {}) do list[name] = nil end
	for _, list in pairs(g.attendance or {}) do list[name] = nil end
	for id, a in pairs(g.adjustments or {}) do
		if a.member == name then g.adjustments[id] = nil end
	end
	for id, s in pairs(g.spends or {}) do
		if s.member == name then g.spends[id] = nil end
	end
	for id, d in pairs(g.donations or {}) do
		if d.member == name then g.donations[id] = nil end
	end
	for id, m in pairs(g.bgMatches or {}) do
		if m.member == name then g.bgMatches[id] = nil end
	end
	for id, b in pairs(g.bounties or {}) do
		if b.member == name then g.bounties[id] = nil end
	end
	for id, p in pairs(g.purchases or {}) do
		if p.member == name then g.purchases[id] = nil end
	end
	for id, f in pairs(g.fundGifts or {}) do
		if f.member == name then g.fundGifts[id] = nil end
	end
	for id, a in pairs(g.bankAsks or {}) do
		if a.requester == name then g.bankAsks[id] = nil end
	end
	for key, d in pairs(g.bankLog or {}) do
		if d.member == name then g.bankLog[key] = nil end
	end
	for _, list in pairs(g.bids or {}) do list[name] = nil end
	for key, r in pairs(g.runs) do
		r.witnesses[name] = nil
		if r.reporter == name and not next(r.witnesses) then g.runs[key] = nil end
	end
end

---------------------------------------------------------------------------
-- Manejadores
---------------------------------------------------------------------------

local function withGuild(fn)
	return function(sender, data, distribution)
		local g = LG:GuildData()
		if g and fn(g, sender, data, distribution) then LG:DataChanged() end
	end
end

-- La ficha llega cada pocos minutos. Para los puntos solo cuenta el nivel (y los niveles
-- subidos): si no cambian, solo se recalculan los logros, que es mucho más barato.
ns.handlers.ME = function(sender, rec)
	local g = LG:GuildData()
	if not g or type(rec) ~= "table" or rec.name ~= sender then return end
	local old = g.members[rec.name]
	local function nLevels(m) return type(m.levels) == "table" and #m.levels or 0 end
	local sameForPoints = old and old.level == rec.level and nLevels(old) == nLevels(rec)
	if ns.MergeMember(g, rec) then LG:DataChanged(sameForPoints and "achievements" or nil) end
end

ns.handlers.KILL = withGuild(function(g, sender, rec)
	if rec.reporter ~= sender then return false end
	local added = ns.MergeKill(g, rec)
	if added then ns.OnKillReceived(rec) end
	return added
end)

ns.handlers.RUN = withGuild(function(g, sender, rec)
	if type(rec.witnesses) ~= "table" or not rec.witnesses[sender] then return false end
	return ns.MergeRun(g, rec)
end)

-- La caché de hermandades vistas no cuenta para puntos ni logros: refresco ligero.
ns.handlers.CACHE = function(sender, entries)
	local g = LG:GuildData()
	if g and type(entries) == "table" and ns.MergeCache(g, entries) then LG:DataChanged(true) end
end

ns.handlers.FORGET = withGuild(function(g, sender, data)
	if data.name ~= sender then return false end
	ns.ForgetMember(g, data.name, data.guid)
	return true
end)

ns.handlers.CLAIM = function(sender, data)
	LG.syncClaims = LG.syncClaims or {}
	LG.syncClaims[data.target] = ns.Now()
end

ns.handlers.SYNC = withGuild(function(g, sender, data, distribution)
	if distribution ~= "WHISPER" then return false end
	local changed = false
	local me = ns.PlayerFullName()
	for _, rec in pairs(data.members or {}) do
		-- Tu propia ficha: sirve para recuperar lo que se hubiera perdido; la tuya manda.
		if type(rec) == "table" and rec.name == me then
			changed = ns.AdoptOwnRecord(rec) or changed
		else
			changed = ns.MergeMember(g, rec) or changed
		end
	end
	for _, rec in pairs(data.kills or {}) do changed = ns.MergeKill(g, rec) or changed end
	for _, rec in pairs(data.runs or {}) do changed = ns.MergeRun(g, rec) or changed end
	for _, rec in pairs(data.orders or {}) do changed = ns.MergeOrder(g, rec) or changed end
	for _, rec in pairs(data.events or {}) do changed = ns.MergeEvent(g, rec) or changed end
	for eventID, list in pairs(data.signups or {}) do
		for member, s in pairs(list) do
			changed = ns.MergeSignup(g, { event = eventID, member = member, status = s.status, role = s.role, t = s.t }) or changed
		end
	end
	for _, rec in pairs(data.adjustments or {}) do changed = ns.MergeAdjustment(g, rec) or changed end
	for auctionID, list in pairs(data.bids or {}) do
		for member, b in pairs(list) do
			changed = ns.MergeBid(g, { auction = auctionID, member = member, amount = b.amount, t = b.t }) or changed
		end
	end
	for _, rec in pairs(data.spends or {}) do changed = ns.MergeSpend(g, rec) or changed end
	for _, rec in pairs(data.projects or {}) do
		if type(rec) == "table" then changed = ns.MergeProject(g, rec) or changed end
	end
	for _, rec in pairs(data.donations or {}) do
		if type(rec) == "table" then changed = ns.MergeDonation(g, rec) or changed end
	end
	for _, rec in pairs(data.chestMoves or {}) do
		if type(rec) == "table" then changed = ns.MergeChestMove(g, rec) or changed end
	end
	for _, rec in pairs(data.bgMatches or {}) do
		if type(rec) == "table" then changed = ns.MergeBGMatch(g, rec) or changed end
	end
	for _, rec in pairs(data.bounties or {}) do
		if type(rec) == "table" then changed = ns.MergeBounty(g, rec) or changed end
	end
	for _, rec in pairs(data.purchases or {}) do
		if type(rec) == "table" then changed = ns.MergePurchase(g, rec) or changed end
	end
	for _, rec in pairs(data.bankRequests or {}) do
		if type(rec) == "table" then changed = ns.MergeBankRequest(g, rec) or changed end
	end
	for _, rec in pairs(data.fundGifts or {}) do
		if type(rec) == "table" then changed = ns.MergeFundGift(g, rec) or changed end
	end
	for _, rec in pairs(data.bankAsks or {}) do
		if type(rec) == "table" then changed = ns.MergeBankAsk(g, rec) or changed end
	end
	if type(data.bankSnap) == "table" then changed = ns.MergeBankSnapshot(g, data.bankSnap) or changed end
	if type(data.bankLog) == "table" then
		local list = {}
		for _, rec in pairs(data.bankLog) do list[#list + 1] = rec end
		changed = ns.AbsorbBankDeposits(g, list) > 0 or changed
	end
	for _, rec in pairs(data.lfg or {}) do changed = ns.MergeLFG(g, rec) or changed end
	for _, rec in pairs(data.tribes or {}) do changed = ns.MergeTribe(g, rec) or changed end
	for id, list in pairs(data.tribeAccepts or {}) do
		for member, t in pairs(list) do changed = ns.MergeTribeAccept(g, { tribe = id, member = member, t = t }) or changed end
	end
	for id, list in pairs(data.tribeLeft or {}) do
		for member, t in pairs(list) do changed = ns.MergeTribeLeft(g, { tribe = id, member = member, t = t }) or changed end
	end
	for id, rec in pairs(data.tribeIcons or {}) do
		if type(rec) == "table" then changed = ns.MergeTribeIcon(g, { tribe = id, icon = rec.icon, by = rec.by, t = rec.t }) or changed end
	end
	for _, rec in pairs(data.calls or {}) do changed = ns.MergeCall(g, rec) or changed end
	for _, rec in pairs(data.aidHelps or {}) do changed = ns.MergeAidHelp(g, rec) or changed end
	for _, rec in pairs(data.regicides or {}) do
		if type(rec) == "table" then changed = ns.MergeRegicide(g, rec) or changed end
	end
	for member, h in pairs(data.honorSeen or {}) do
		if type(h) == "table" then changed = ns.MergeHonorSeen(g, { member = member, hk = h.hk, today = h.today, t = h.t, by = h.by }) or changed end
	end
	for id, list in pairs(data.tribeInvites or {}) do
		for member, inv in pairs(list) do
			if type(inv) == "table" then changed = ns.MergeTribeInvite(g, { tribe = id, member = member, by = inv.by, t = inv.t }) or changed end
		end
	end
	for _, rec in pairs(data.auctions or {}) do changed = ns.MergeAuction(g, rec) or changed end
	for id, a in pairs(data.achievements or {}) do
		changed = ns.MergeAchievement(g, { id = id, t = a.t }) or changed
	end
	for guild, t in pairs(data.targets or {}) do
		changed = ns.MergeTarget(g, { guild = guild, active = t.active, by = t.by, t = t.t }) or changed
	end
	for eventID, list in pairs(data.attendance or {}) do
		for member, t in pairs(list) do
			changed = ns.MergeAttendance(g, { event = eventID, member = member, t = t }) or changed
		end
	end
	local guild = LG:GuildName()
	for _, rec in pairs(data.wars or {}) do
		if type(rec) == "table" then
			changed = ns.MergeWar(g, guild, rec, sender, "guild") or changed
			if type(rec.report) == "table" then
				local rep = { id = rec.id, guild = ns.WarEnemy(rec, guild) }
				for k, v in pairs(rec.report) do rep[k] = v end
				changed = ns.MergeWarReport(g, guild, rep, sender, "guild") or changed
			end
		end
	end
	for key, s in pairs(data.settings or {}) do
		changed = ns.MergeSetting(g, { key = key, value = s.value, by = s.by, t = s.t }) or changed
	end
	for id, v in pairs(data.voids or {}) do
		changed = ns.MergeVoid(g, { id = id, active = v.active, by = v.by, t = v.t, kind = v.kind, member = v.member, label = v.label }) or changed
	end
	changed = ns.MergeCache(g, data.cache or {}) or changed
	LG:Debug("sync de", sender, "aplicado")
	-- La sincronización cuenta como hecha cuando llega el último trozo (los logros
	-- esperan a tenerla entera para no anunciar como nuevos los que ya había).
	if type(data._parts) ~= "number" or data._part == data._parts then
		LG.lastSync = { from = sender, t = ns.Now() }
	end
	-- Lo que tengo yo y a quien me contesta le falta, se lo devuelvo.
	if type(data.killDigest) == "table" or type(data.runDigest) == "table" then
		local kills = type(data.killDigest) == "table" and ns.SyncMissing(g.kills, data.killDigest, nil, SYNC_MAX_KILLS) or {}
		local runs = type(data.runDigest) == "table" and ns.SyncMissing(g.runs, data.runDigest, nil, SYNC_MAX_RUNS) or {}
		if #kills > 0 or #runs > 0 then
			local target = LG.lastRawSenders and LG.lastRawSenders[sender] or sender
			LG:SendParts("FILL", { kills = kills, runs = runs }, "WHISPER", target, "BULK")
		end
	end
	return changed
end)

-- FILL: registros que me faltaban, devueltos por quien acaba de entrar tras mi SYNC.
ns.handlers.FILL = withGuild(function(g, sender, data, distribution)
	if distribution ~= "WHISPER" or type(data) ~= "table" then return false end
	local changed = false
	for _, rec in pairs(data.kills or {}) do changed = ns.MergeKill(g, rec) or changed end
	for _, rec in pairs(data.runs or {}) do changed = ns.MergeRun(g, rec) or changed end
	LG:Debug("fill de", sender, "aplicado")
	return changed
end)

---------------------------------------------------------------------------
-- Sincronización al entrar
---------------------------------------------------------------------------

local function newest(tbl)
	local t = 0
	for _, rec in pairs(tbl) do
		if (rec.t or 0) > t then t = rec.t end
	end
	return t
end

-- Lo más reciente de cada informante: así quien entra pide lo que le falta de cada uno.
-- (Con una sola fecha, una baja propia reciente tapaba las de los demás de antes.)
local function newestBy(tbl)
	local by = {}
	for _, rec in pairs(tbl) do
		local who = rec.reporter or "?"
		if (rec.t or 0) > (by[who] or 0) then by[who] = rec.t end
	end
	return by
end

-- Los registros más recientes de tbl posteriores a since (una fecha, o una por informante), como mucho max.
local function newerThan(tbl, since, max)
	local list = {}
	for _, rec in pairs(tbl) do
		local from = since
		if type(since) == "table" then from = tonumber(since[rec.reporter or "?"]) or 0 end
		if (rec.t or 0) > from then list[#list + 1] = rec end
	end
	table.sort(list, function(a, b) return a.t > b.t end)
	for i = #list, max + 1, -1 do list[i] = nil end
	return list
end

-- Resumen por informante y día (los últimos DIGEST_DAYS): cuántos registros tengo de cada uno.
-- Comparando resúmenes se ven los huecos de cualquier fecha, no solo lo posterior al último.
local DIGEST_DAYS = 21
local function digest(tbl)
	local by, since = {}, ns.Now() - DIGEST_DAYS * 86400
	for _, rec in pairs(tbl) do
		local t = rec.t or 0
		if t >= since then
			local who, day = rec.reporter or "?", math.floor(t / 86400)
			by[who] = by[who] or {}
			by[who][day] = (by[who][day] or 0) + 1
		end
	end
	return by
end
ns.SyncDigest = digest

-- Los registros de los días (por informante) en los que tengo más que el otro según su resumen,
-- más los posteriores a su último de cada uno; los más recientes primero, como mucho max.
local function missingFor(tbl, theirs, newestBy, max)
	local mine, since = digest(tbl), ns.Now() - DIGEST_DAYS * 86400
	local list = {}
	for _, rec in pairs(tbl) do
		local t, who = rec.t or 0, rec.reporter or "?"
		local add
		if t >= since then
			local day = math.floor(t / 86400)
			local other = type(theirs[who]) == "table" and tonumber(theirs[who][day]) or 0
			add = mine[who][day] > other
		end
		if not add and type(newestBy) == "table" then add = t > (tonumber(newestBy[who]) or 0) end
		if add then list[#list + 1] = rec end
	end
	table.sort(list, function(a, b) return a.t > b.t end)
	for i = #list, max + 1, -1 do list[i] = nil end
	return list
end
ns.SyncMissing = missingFor

local function recentCache(cache, max)
	local list = {}
	for guid, c in pairs(cache) do list[#list + 1] = { guid = guid, t = c.t or 0 } end
	table.sort(list, function(a, b) return a.t > b.t end)
	local out = {}
	for i = 1, math.min(max, #list) do out[list[i].guid] = cache[list[i].guid] end
	return out
end

function LG:StartSync()
	local g = self:GuildData()
	if not g then return end
	self:SendMyRecord()
	self:Send("HELLO", { kills = newest(g.kills), runs = newest(g.runs), killsBy = newestBy(g.kills), runsBy = newestBy(g.runs),
		killDigest = digest(g.kills), runDigest = digest(g.runs), fundCount = ns.CountFundGifts and ns.CountFundGifts(g) or nil,
		fundSet = g.settings and g.settings.bankFund and g.settings.bankFund.t or 0 })
end

-- Responde un solo miembro: cada uno espera un tiempo aleatorio y el primero
-- que se adelanta anuncia un CLAIM para que los demás no repitan el envío.
ns.handlers.HELLO = function(sender, data, _, rawSender)
	if ns.OnHelloActivity then ns.OnHelloActivity() end -- quien llega ve enseguida qué hace cada uno
	if ns.OnFundHello then ns.OnFundHello(sender, data, rawSender) end -- el tesorero le pasa la colecta
	LG:ScheduleTimer(function()
		local g = LG:GuildData()
		if not g then return end
		LG.syncClaims = LG.syncClaims or {}
		if ns.Now() - (LG.syncClaims[sender] or 0) < 60 then return end
		LG.syncClaims[sender] = ns.Now()
		LG:Send("CLAIM", { target = sender })

		local members = {}
		for _, rec in pairs(g.members) do members[#members + 1] = rec end
		-- Con resumen (1.1.2+): los días que le faltan. Sin él (versiones antiguas): lo posterior a lo último.
		local kills, runs
		if type(data.killDigest) == "table" then
			kills = missingFor(g.kills, data.killDigest, data.killsBy, SYNC_MAX_KILLS)
		else
			kills = newerThan(g.kills, type(data.killsBy) == "table" and data.killsBy or tonumber(data.kills) or 0, SYNC_MAX_KILLS)
		end
		if type(data.runDigest) == "table" then
			runs = missingFor(g.runs, data.runDigest, data.runsBy, SYNC_MAX_RUNS)
		else
			runs = newerThan(g.runs, type(data.runsBy) == "table" and data.runsBy or tonumber(data.runs) or 0, SYNC_MAX_RUNS)
		end
		LG:SendParts("SYNC", {
			members = members,
			kills = kills,
			runs = runs,
			-- Mi resumen, para que quien entra me devuelva lo que a mí me falta (FILL).
			killDigest = digest(g.kills),
			runDigest = digest(g.runs),
			cache = recentCache(g.guildCache, SYNC_MAX_CACHE),
			orders = g.orders,
			events = g.events,
			signups = g.signups,
			attendance = g.attendance,
			adjustments = g.adjustments,
			spends = g.spends,
			projects = g.projects,
			donations = g.donations,
			chestMoves = g.chestMoves,
			bgMatches = g.bgMatches,
			bounties = g.bounties,
			purchases = g.purchases,
			bankLog = g.bankLog,
			bankRequests = g.bankRequests,
			bankAsks = g.bankAsks,
			fundGifts = g.fundGifts,
			bankSnap = g.bankSnap,
			lfg = g.lfg,
			tribes = g.tribes,
			tribeAccepts = g.tribeAccepts,
			tribeLeft = g.tribeLeft,
			tribeInvites = g.tribeInvites,
			honorSeen = g.honorSeen,
			calls = g.calls,
			tribeIcons = g.tribeIcons,
			aidHelps = g.aidHelps,
			regicides = g.regicides,
			auctions = g.auctions,
			achievements = g.achievements,
			bids = g.bids,
			targets = g.targets,
			voids = g.voids,
			wars = g.wars,
			settings = g.settings,
		}, "WHISPER", rawSender or sender, "BULK")
	end, 2 + math.random() * 6)
end
