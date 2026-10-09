-- Cazarrecompensas: kills y muertes en PvP con la hermandad del rival.
--
-- El registro de combate no trae la hermandad, así que se guarda una caché
-- GUID -> hermandad cada vez que un jugador aparece como placa de nombre,
-- bajo el ratón o como objetivo. La caché se comparte con la guild.
--
-- v0.1 solo registra (modo "registro" del documento de diseño); las insignias se calculan en Merits.lua.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Hunt = LG:NewModule("Hunt", "AceEvent-3.0", "AceTimer-3.0")
ns.HuntModule = Hunt -- para las pruebas

-- Etiqueta con la que se agrupan los jugadores sin hermandad en los rankings.
ns.NO_GUILD = L["(sin hermandad)"]

local bband = bit.band
local TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400
local REACTION_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40

local REVENGE_WINDOW = 600     -- segundos para que una kill cuente como venganza
local ATTACKER_WINDOW = 10     -- segundos: último golpe de un jugador antes de morir
local HONOR_WAIT = 2           -- espera al mensaje de muerte honorable antes de publicar
local CACHE_REFRESH = 86400    -- se vuelve a compartir una entrada si tiene más de un día
local CACHE_SHARE_EVERY = 60

local myGUID
local pendingKills = {}   -- [nombreCorto] = kill esperando el mensaje de honor
local newCache = {}       -- entradas nuevas por compartir en el próximo lote
local honorPatterns -- una por cada variante del mensaje de honor del juego

function Hunt:OnEnable()
	myGUID = UnitGUID("player")
	honorPatterns = self:BuildHonorPatterns()
	ns.RegisterEvent(self, "NAME_PLATE_UNIT_ADDED", function(_, unit) self:CacheUnit(unit) end)
	ns.RegisterEvent(self, "UPDATE_MOUSEOVER_UNIT", function() self:CacheUnit("mouseover") end)
	ns.RegisterEvent(self, "PLAYER_TARGET_CHANGED", function() self:CacheUnit("target"); self:NoteEnemy("target") end)
	self.hasCombatLog = ns.RegisterEvent(self, "COMBAT_LOG_EVENT_UNFILTERED")
	ns.RegisterEvent(self, "CHAT_MSG_COMBAT_HONOR_GAIN")
	ns.RegisterEvent(self, "PLAYER_DEAD")
	self:ScheduleRepeatingTimer("ShareCache", CACHE_SHARE_EVERY)
	-- En Forever la muerte con honor llega como «Has recibido N p. de honor.», sin la víctima:
	-- se apunta qué jugador enemigo acaba de morir a la vista para atribuírsela.
	-- RegisterUnitEvent admite como mucho dos unidades por marco: objetivo y foco en uno y el
	-- ratón en otro. Además, al cambiar de objetivo se mira el anterior (por si acaba de morir).
	if not self.healthWatch and CreateFrame then
		self.healthWatch, self.mouseWatch = CreateFrame("Frame"), CreateFrame("Frame")
		if self.healthWatch.RegisterUnitEvent then
			pcall(self.healthWatch.RegisterUnitEvent, self.healthWatch, "UNIT_HEALTH", "target", "focus")
			pcall(self.mouseWatch.RegisterUnitEvent, self.mouseWatch, "UNIT_HEALTH", "mouseover")
		end
		self.healthWatch:SetScript("OnEvent", function(_, _, unit) self:NoteEnemy(unit) end)
		self.mouseWatch:SetScript("OnEvent", function(_, _, unit) self:NoteEnemy(unit) end)
	end
end

-- En Forever, al morir el enemigo el objetivo se vacía y no llega su muerte: se apunta el último
-- jugador enemigo con el que se luchaba (objetivo, foco o ratón, cada vez que cambia su vida o
-- se selecciona). Si en unos segundos llega el honor, la baja es suya.
local VICTIM_WINDOW = 15
local lastDeadEnemy -- el último enemigo visto (de nombre histórico: antes solo se apuntaban los muertos)
function Hunt:NoteEnemy(unit)
	if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
	if UnitIsFriend and UnitIsFriend("player", unit) then return end
	local ok, guid = pcall(UnitGUID, unit)
	if not ok or (issecretvalue and issecretvalue(guid)) then guid = nil end
	local name = ns.UnitFullName(unit)
	if not guid and not name then return end
	if guid then self:CacheUnit(unit) end
	local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
	if issecretvalue and issecretvalue(dead) then dead = nil end
	lastDeadEnemy = { guid = guid, name = name, at = GetTime(), dead = dead and true or nil }
end
Hunt.NoteDeadEnemy = Hunt.NoteEnemy

-- Cómo estaban el objetivo, el foco y el ratón (para el diagnóstico de las muertes con honor).
function Hunt:DescribeUnitsForDiag()
	local parts = {}
	for _, unit in ipairs({ "target", "focus", "mouseover" }) do
		if UnitExists(unit) then
			local name = ns.UnitFullName(unit) or "?"
			parts[#parts + 1] = ("%s=%s jugador:%s amigo:%s muerto:%s"):format(unit, name, tostring(UnitIsPlayer(unit)),
				tostring(UnitIsFriend and UnitIsFriend("player", unit)), tostring(UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)))
		end
	end
	if lastDeadEnemy then parts[#parts + 1] = ("ultimoEnemigo=%s hace %.1fs%s"):format(lastDeadEnemy.name or "?", GetTime() - lastDeadEnemy.at, lastDeadEnemy.dead and " (muerto)" or "") end
	return #parts > 0 and table.concat(parts, " | ") or "nada a la vista"
end

-- La víctima más probable de una muerte con honor que llega sin nombre: un enemigo muerto
-- ahora mismo a la vista o, si no, el último enemigo con el que se luchaba hace poco.
function Hunt:RecentVictim()
	for _, unit in ipairs({ "target", "focus", "mouseover" }) do
		if UnitExists(unit) and UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then self:NoteEnemy(unit) end
	end
	if lastDeadEnemy and GetTime() - lastDeadEnemy.at <= VICTIM_WINDOW then
		local v = lastDeadEnemy
		lastDeadEnemy = nil
		return v
	end
	return nil
end

---------------------------------------------------------------------------
-- Caché de hermandades
---------------------------------------------------------------------------

-- Dentro de instancias el juego puede dar valores secretos: no se pueden comparar ni usar de clave.
local function secret(v) return issecretvalue and issecretvalue(v) end

function Hunt:CacheUnit(unit)
	if not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
	if ns.IsGuildUnit(unit) then return end
	local g = LG:GuildData()
	if not g then return end

	local guid = UnitGUID(unit)
	local guildName, _, rankIndex = GetGuildInfo(unit)
	if not guid or secret(guid) or secret(guildName) then return end
	if secret(rankIndex) then rankIndex = nil end
	local old = g.guildCache[guid]
	local now = ns.Now()
	local level = UnitLevel(unit)
	if secret(level) then level = nil end -- un valor secreto no se puede guardar ni enviar
	local entry = {
		n = ns.UnitFullName(unit),
		g = guildName or false,
		gm = (guildName and rankIndex == 0) or nil, -- maestro de su hermandad
		l = level,
		r = UnitPVPRank and UnitPVPRank(unit) or 0,
		t = now,
	}
	g.guildCache[guid] = entry
	if not old or old.g ~= entry.g or now - (old.t or 0) > CACHE_REFRESH then
		newCache[guid] = entry
	end
end

function Hunt:ShareCache()
	if not next(newCache) then return end
	local batch, n = {}, 0
	for guid, entry in pairs(newCache) do
		batch[guid] = entry
		newCache[guid] = nil
		n = n + 1
		if n >= 50 then break end
	end
	LG:Send("CACHE", batch, "GUILD", nil, "BULK")
end

-- Si la víctima sigue visible justo al morir, refresca su entrada de la caché.
function Hunt:RefreshFromVisibleUnits(guid)
	local function same(unit)
		local g = UnitGUID(unit)
		return g ~= nil and not secret(g) and g == guid
	end
	for _, unit in ipairs({ "target", "mouseover" }) do
		if same(unit) then self:CacheUnit(unit) return end
	end
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if same(unit) then self:CacheUnit(unit) return end
	end
end

---------------------------------------------------------------------------
-- Registro de combate
---------------------------------------------------------------------------

-- Campos de batalla (y arenas): sus bajas y muertes se guardan marcadas con bg = true.
-- Cuentan como muertes con honor, pero no para objetivos, venganzas, auxilio ni puntos de caza.
function ns.InBattleground()
	if not IsInInstance then return false end
	local _, instanceType = IsInInstance()
	return instanceType == "pvp" or instanceType == "arena"
end

-- ¿Cuenta para la caza (objetivos, venganzas, auxilio, «Nos cazan»)? Todo lo que no sea de un campo de batalla.
function ns.IsHuntRecord(k)
	return not k.bg
end

function Hunt:COMBAT_LOG_EVENT_UNFILTERED()
	local _, sub, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags = CombatLogGetCurrentEventInfo()
	if sub == "PARTY_KILL" then
		if srcGUID == myGUID and bband(dstFlags, TYPE_PLAYER) > 0 then
			self:OnKill(dstGUID)
		end
	elseif dstGUID == myGUID and sub:sub(-7) == "_DAMAGE"
		and bband(srcFlags, TYPE_PLAYER) > 0 and bband(srcFlags, REACTION_HOSTILE) > 0 then
		self.lastAttacker = { guid = srcGUID, at = GetTime() }
	end
end

-- Busca en la caché el GUID visto más recientemente con ese nombre.
local function guidByName(g, name)
	local wanted = name
	local best, bestT
	for guid, c in pairs(g.guildCache) do
		if ns.SameName(c.n, wanted) and (c.t or 0) > (bestT or -1) then
			best, bestT = guid, c.t
		end
	end
	return best
end

-- Datos de un jugador a partir de su GUID y de la caché.
local function describe(g, guid)
	local _, classFile, _, raceFile, _, name, realm
	if guid then _, classFile, _, raceFile, _, name, realm = GetPlayerInfoByGUID(guid) end
	local c = guid and g.guildCache[guid]
	return {
		name = ns.FullName(name, realm) or (c and c.n),
		class = classFile,
		race = raceFile,
		level = c and c.l,
		rank = c and c.r,
		guild = c and c.g or nil,
		gm = c and c.gm or nil,
	}
end

-- victimGUID viene del registro de combate. Sin registro de combate (prohibido en
-- la beta) la kill sale del mensaje de muerte honorable: solo hay nombre y honor,
-- y cuenta el crédito de honor, no necesariamente el golpe final.
function Hunt:OnKill(victimGUID, victimName, honor)
	local g = LG:GuildData()
	if not g or not LG:HasConsent() then return end
	victimGUID = victimGUID or guidByName(g, victimName)
	if victimGUID then self:RefreshFromVisibleUnits(victimGUID) end

	local now = ns.Now()
	local v = describe(g, victimGUID)
	v.name = v.name or ns.FullName(victimName)
	local me = ns.PlayerFullName()
	local rec = {
		id = ("%s:%s:%d"):format(myGUID, victimGUID or v.name or "?", now),
		credit = honor and true or nil,
		kind = "kill",
		t = now,
		killer = myGUID,
		killerName = me,
		victim = victimGUID,
		victimName = v.name,
		class = v.class,
		race = v.race,
		level = v.level,
		rank = v.rank,
		guild = v.guild,
		victimGM = (v.guild and v.gm) or nil, -- era el maestro de su hermandad
		zone = GetZoneText(),
		map = ns.CurrentMap(), -- id de mapa: igual en todos los idiomas (guerras)
		subzone = GetSubZoneText(),
		honorable = honor and true or false,
		honor = honor,
		bg = ns.InBattleground() or nil,
		reporter = me,
	}
	-- Venganza: la víctima mató a alguien de la guild hace poco (nunca dentro de un campo de batalla).
	for _, k in pairs(rec.bg and {} or g.kills) do
		if k.kind == "death" and not k.bg and now - k.t <= REVENGE_WINDOW
			and ((victimGUID and k.killer == victimGUID) or ns.SameName(k.killerName, v.name)) then
			rec.revenge = true
			rec.avenged = k.victimName
			break
		end
	end

	if honor then
		self:Publish(rec)
		return
	end
	local short = ns.FirstName(v.name)
	if short then pendingKills[short] = rec end
	self:ScheduleTimer(function()
		if short then pendingKills[short] = nil end
		self:Publish(rec)
	end, HONOR_WAIT)
end

function Hunt:PLAYER_DEAD()
	local att = self.lastAttacker
	self.lastAttacker = nil
	if att and GetTime() - att.at <= ATTACKER_WINDOW then
		self:RecordDeath(att.guid)
		return
	end
	-- Sin registro de combate: se mira el informe de muerte de Blizzard, que tarda un instante en rellenarse.
	self:ScheduleTimer("CaptureRecap", 1)
end

-- Busca el ID del informe de muerte más reciente.
local function latestRecapID(api)
	local latest
	for id = 1, 200 do
		local ok, has = pcall(api.HasRecapEvents, id)
		if ok and has then latest = id end
	end
	return latest
end

-- Lee el informe de muerte. v0.1 guarda además un volcado completo en
-- GuildmarkDB.global.recapDebug para ver qué campos trae en Forever.
function Hunt:CaptureRecap()
	local api = C_DeathRecap
	if not api or not api.GetRecapEvents then return end

	local how, recapID, events = "sin id", nil, nil
	local ok, result = pcall(api.GetRecapEvents)
	if ok and type(result) == "table" and #result > 0 then
		events = result
	else
		recapID = latestRecapID(api)
		if recapID then
			ok, result = pcall(api.GetRecapEvents, recapID)
			if ok and type(result) == "table" then events, how = result, "id " .. recapID end
		end
	end

	local log = LG.db.global.recapDebug
	local okHas, has = pcall(api.HasRecapEvents)
	table.insert(log, {
		t = date("%Y-%m-%d %H:%M:%S"),
		how = how,
		hasRecapEvents = okHas and tostring(has) or "error",
		count = events and #events or 0,
		dump = events and ns.DeepDescribe(events, 3) or tostring(result),
	})
	while #log > 5 do table.remove(log, 1) end
	if not events then return end

	-- Comprobado en la beta: events[1] es el golpe final (overkill >= 0) y el resto
	-- va hacia atrás en el tiempo. sourceName llega corrupto (restos de otros
	-- nombres), así que solo se usa sourceGUID.
	local killerGUID, assists = nil, {}
	local okScan = pcall(function()
		local final = events[1]
		for _, e in ipairs(events) do
			if type(e.overkill) == "number" and e.overkill >= 0 then final = e break end
		end
		local function isPlayer(guid)
			return type(guid) == "string" and guid:find("^Player%-") and guid ~= myGUID
		end
		if final and isPlayer(final.sourceGUID) then killerGUID = final.sourceGUID end
		for _, e in ipairs(events) do
			local guid = e.sourceGUID
			if isPlayer(guid) and guid ~= killerGUID and not tContains(assists, guid) then
				assists[#assists + 1] = guid
			end
		end
	end)
	LG:Debug("informe de muerte:", #events, "eventos, asesino:", killerGUID or "ninguno",
		"participantes:", #assists, okScan and "" or "(error al leer)")
	-- Si el golpe final fue de un monstruo pero participaron jugadores, cuenta el último que pegó.
	if not killerGUID and #assists > 0 then killerGUID = table.remove(assists, 1) end
	if killerGUID then self:RecordDeath(killerGUID, assists) end
end

function Hunt:RecordDeath(killerGUID, assistGUIDs)
	local g = LG:GuildData()
	if not g or not LG:HasConsent() then return end

	local now = ns.Now()
	local k = describe(g, killerGUID)
	local me = ns.PlayerFullName()
	-- Otros jugadores que te pegaron antes de morir, con su hermandad si se conoce.
	local assists
	for _, guid in ipairs(assistGUIDs or {}) do
		local a = describe(g, guid)
		assists = assists or {}
		assists[#assists + 1] = { guid = guid, name = a.name, class = a.class, guild = a.guild }
	end
	self:Publish({
		assists = assists,
		id = ("%s:death:%d"):format(myGUID, now),
		kind = "death",
		t = now,
		killer = killerGUID,
		killerName = k.name,
		class = k.class,
		race = k.race,
		level = k.level,
		rank = k.rank,
		guild = k.guild,
		victim = myGUID,
		victimName = me,
		bg = ns.InBattleground() or nil,
		zone = GetZoneText(),
		map = ns.CurrentMap(), -- id de mapa: igual en todos los idiomas (guerras)
		subzone = GetSubZoneText(),
		reporter = me,
	})
end

function Hunt:Publish(rec)
	local g = LG:GuildData()
	if not g then return end
	ns.MergeKill(g, rec)
	LG:Send("KILL", rec)
	ns.OnKillReceived(rec)
	LG:DataChanged()
end

-- Avisos en el chat, para kills propias y para las que llegan de otros miembros.
function ns.OnKillReceived(rec)
	if ns.BountyNotify then ns.BountyNotify(rec) end
	if rec.kind == "death" then
		if rec.bg then return end
		if ns.CallToArms then ns.CallToArms(rec) end
		if ns.CheckAid then ns.CheckAid(rec) end
		return
	end
	if rec.kind ~= "kill" then return end
	if rec.bg then return end
	if ns.CheckAidKill then ns.CheckAidKill(rec) end
	local victim = ns.ShortName(rec.victimName) or "?"
	local guild = rec.guild and (" <%s>"):format(rec.guild) or ""
	if rec.revenge then
		LG:Print((L["|cffff9d3b¡Venganza!|r %s ha cazado a %s%s, que había matado a %s."]):format(
			ns.ShortName(rec.killerName), victim, guild, ns.ShortName(rec.avenged) or "?"))
	elseif rec.reporter == ns.PlayerFullName() then
		LG:Print((L["Has matado a %s%s en %s."]):format(victim, guild, rec.zone or "?"))
	end
end

---------------------------------------------------------------------------
-- Mensaje de muerte honorable
---------------------------------------------------------------------------

-- Convierte una cadena localizada del juego (p. ej. "%s dies, honorable kill Rank: %s
-- (Estimated Honor Points: %d)") en un patrón que captura el nombre y el honor.
local function toPattern(fmt)
	local p = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
	-- Primero se marcan los huecos (%s, %d y los posicionales %1$s) y luego se
	-- sustituyen, para no volver a tocar el "%d" de las capturas ya insertadas.
	p = p:gsub("%%%d%%%$s", "\1"):gsub("%%%d%%%$d", "\2"):gsub("%%s", "\1"):gsub("%%d", "\2")
	p = p:gsub("\1", "(.-)"):gsub("\2", "(%%d+)")
	return "^" .. p .. "$"
end

-- El cliente moderno tiene varias variantes del mensaje (con rango, sin rango, con
-- agotamiento por matar varias veces al mismo...): se reconocen todas las que existan.
function Hunt:BuildHonorPatterns()
	local list = {}
	for key, fmt in pairs(_G) do
		if type(key) == "string" and key:find("^COMBATLOG_HONORGAIN") and type(fmt) == "string" and fmt:find("%%s") then
			-- Qué captura es el honor: el primer %d (los huecos van en orden; sin posicionales en el juego).
			local index, honorIndex = 0, nil
			for conv in fmt:gsub("%%%%", ""):gmatch("%%%d*%$?(%a)") do
				index = index + 1
				if conv == "d" and not honorIndex then honorIndex = index end
			end
			list[#list + 1] = { key = key, pattern = toPattern(fmt), len = #fmt, honorIndex = honorIndex }
		end
	end
	-- Los más largos (más concretos) primero.
	table.sort(list, function(x, y) return x.len > y.len end)
	return list
end

function Hunt:CHAT_MSG_COMBAT_HONOR_GAIN(_, text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
	local name, honor
	for _, hp in ipairs(honorPatterns or {}) do
		local captures = { text:match(hp.pattern) }
		if captures[1] then
			name = captures[1]
			honor = hp.honorIndex and tonumber(captures[hp.honorIndex]) or nil
			break
		end
	end
	if not name and COMBATLOG_HONORAWARD then
		-- «Has recibido N p. de honor.»: sin víctima. Solo cuenta si acaba de morir un enemigo a la
		-- vista (si no, es honor de una misión o de un objetivo de campo de batalla).
		local awarded = text:match(toPattern(COMBATLOG_HONORAWARD))
		if awarded then
			local seen = self:DescribeUnitsForDiag()
			local v = self:RecentVictim()
			-- Diagnóstico (global.diag.honorAwards, los 5 últimos): qué había a la vista y a quién se atribuyó.
			local diag = LG.db.global.diag
			diag.honorAwards = diag.honorAwards or {}
			table.insert(diag.honorAwards, 1, { t = date("%Y-%m-%d %H:%M:%S"), honor = tonumber(awarded), seen = seen,
				victim = v and (v.name or v.guid) or nil, combatLog = self.hasCombatLog and true or nil })
			for i = #diag.honorAwards, 6, -1 do diag.honorAwards[i] = nil end
			if v and not self.hasCombatLog then self:OnKill(v.guid, v.name, tonumber(awarded) or 0) end
			return
		end
	end
	if not name then
		-- Un formato que no conocemos: se guarda para poder añadirlo (global.diag.honorMsgs).
		local diag = LG.db.global.diag
		diag.honorMsgs = diag.honorMsgs or {}
		table.insert(diag.honorMsgs, 1, { t = date("%Y-%m-%d %H:%M:%S"), text = text:sub(1, 200) })
		for i = #diag.honorMsgs, 6, -1 do diag.honorMsgs[i] = nil end
		return
	end
	honor = honor or 0
	local rec = pendingKills[ns.FirstName(name)]
	if rec then
		rec.honorable = true
		rec.honor = honor
	elseif not self.hasCombatLog then
		self:OnKill(nil, name, honor)
	end
end

---------------------------------------------------------------------------
-- Rankings para la interfaz
---------------------------------------------------------------------------

function ns.HuntStats(days)
	local g = LG:GuildData()
	local stats = { killedBy = {}, hunted = {}, hunters = {}, recent = {}, dangerous = {} }
	local byKiller = {} -- [hermandad][asesino] = muertes
	if not g then return stats end
	local since = ns.Now() - days * 86400
	for _, k in pairs(g.kills) do
		-- Las kills anuladas por un oficial no cuentan ni aparecen; las de campos de batalla, tampoco.
		if not ns.IsVoided(g, k.id) and not k.bg then
			if k.t >= since then
				local guild = k.guild or ns.NO_GUILD
				if k.kind == "death" then
					stats.killedBy[guild] = (stats.killedBy[guild] or 0) + 1
					if k.killerName then
						byKiller[guild] = byKiller[guild] or {}
						byKiller[guild][k.killerName] = (byKiller[guild][k.killerName] or 0) + 1
					end
				else
					stats.hunted[guild] = (stats.hunted[guild] or 0) + 1
					stats.hunters[k.killerName] = (stats.hunters[k.killerName] or 0) + 1
				end
			end
			stats.recent[#stats.recent + 1] = k
		end
	end
	table.sort(stats.recent, function(a, b) return a.t > b.t end)
	for guild, list in pairs(byKiller) do
		local best, n = nil, 0
		for name, c in pairs(list) do
			if c > n or (c == n and best and name < best) then best, n = name, c end
		end
		stats.dangerous[guild] = { name = best, n = n }
	end
	return stats
end

-- Diagnóstico: las variantes del mensaje de honor de este cliente y los mensajes que no se
-- reconocieron. Uso: /gmk dump LantuxGuild_Honor()
function LantuxGuild_Honor()
	local parts = {}
	for key, fmt in pairs(_G) do
		if type(key) == "string" and key:find("^COMBATLOG_HONOR") and type(fmt) == "string" then parts[#parts + 1] = key .. "=" .. fmt end
	end
	table.sort(parts)
	local seen = LG.db.global.diag.honorMsgs
	parts[#parts + 1] = "sin reconocer=" .. (seen and #seen or 0)
	return table.concat(parts, " || ")
end
