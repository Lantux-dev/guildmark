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
--   SYNC    respuesta a un HELLO, por susurro
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
local SYNC_MAX_KILLS = 300
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
	local encoded = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(serialized))
	self:SendCommMessage(PREFIX, encoded, channel, target, prio or "NORMAL")
	self:Debug("->", kind, channel, target or "", #encoded .. "b")
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

	local compressed = LibDeflate:DecodeForWoWAddonChannel(encoded)
	local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
	if not serialized then return end
	local ok, msg = LibSerialize:Deserialize(serialized)
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
		handler(sender, msg.d, distribution, rawSender)
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

ns.handlers.ME = withGuild(function(g, sender, rec)
	if rec.name ~= sender then return false end
	return ns.MergeMember(g, rec)
end)

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

ns.handlers.CACHE = withGuild(function(g, sender, entries)
	return ns.MergeCache(g, entries)
end)

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
	LG.lastSync = { from = sender, t = ns.Now() }
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

-- Los registros más recientes de tbl posteriores a since, como mucho max.
local function newerThan(tbl, since, max)
	local list = {}
	for _, rec in pairs(tbl) do
		if (rec.t or 0) > since then list[#list + 1] = rec end
	end
	table.sort(list, function(a, b) return a.t > b.t end)
	for i = #list, max + 1, -1 do list[i] = nil end
	return list
end

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
	self:Send("HELLO", { kills = newest(g.kills), runs = newest(g.runs) })
end

-- Responde un solo miembro: cada uno espera un tiempo aleatorio y el primero
-- que se adelanta anuncia un CLAIM para que los demás no repitan el envío.
ns.handlers.HELLO = function(sender, data, _, rawSender)
	if ns.OnHelloActivity then ns.OnHelloActivity() end -- quien llega ve enseguida qué hace cada uno
	LG:ScheduleTimer(function()
		local g = LG:GuildData()
		if not g then return end
		LG.syncClaims = LG.syncClaims or {}
		if ns.Now() - (LG.syncClaims[sender] or 0) < 60 then return end
		LG.syncClaims[sender] = ns.Now()
		LG:Send("CLAIM", { target = sender })

		local members = {}
		for _, rec in pairs(g.members) do members[#members + 1] = rec end
		LG:Send("SYNC", {
			members = members,
			kills = newerThan(g.kills, tonumber(data.kills) or 0, SYNC_MAX_KILLS),
			runs = newerThan(g.runs, tonumber(data.runs) or 0, SYNC_MAX_RUNS),
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
