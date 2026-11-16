-- Grupos de hermandad en mazmorras: cuántos del grupo son de la guild
-- y registro de cada jefe derrotado con esa composición.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Dungeon = LG:NewModule("Dungeon", "AceEvent-3.0")

-- Los registros de distintos testigos del mismo jefe caen en la misma clave
-- si coinciden jefe, grupo y franja de 5 minutos.
local RUN_WINDOW = 300

function Dungeon:OnEnable()
	ns.RegisterEvent(self, "GROUP_ROSTER_UPDATE", "CheckGroup")
	ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", "CheckGroup")
	ns.RegisterEvent(self, "ENCOUNTER_END")
	-- Respaldo: el propio cartel de "jefe derrotado" de Blizzard usa BOSS_KILL.
	ns.RegisterEvent(self, "BOSS_KILL")
	-- El reloj de la partida arranca con la primera baja (no al entrar): sirve cualquier aviso
	-- de muerte de un enemigo, sin mirar sus datos (dentro de las instancias pueden ser secretos).
	for _, event in ipairs({ "PARTY_KILL", "CHAT_MSG_COMBAT_HOSTILE_DEATH", "CHAT_MSG_COMBAT_XP_GAIN" }) do
		pcall(ns.RegisterEvent, self, event, function() ns.MarkFirstKill() end)
	end
	-- Datos de la partida (1.3): botín del grupo, oro propio y muertes propias.
	pcall(ns.RegisterEvent, self, "CHAT_MSG_LOOT", function(_, text) pcall(ns.OnRunLoot, text) end)
	pcall(ns.RegisterEvent, self, "PLAYER_MONEY", function() ns.OnRunMoney() end)
	pcall(ns.RegisterEvent, self, "PLAYER_DEAD", function() ns.OnRunDeath() end)
	if ns.OnRunMoney then ns.OnRunMoney() end
end

-- Grupo de hermandad para logros, desafíos y medallas (1.2.1): más de la mitad del grupo es
-- de la guild (3/5, 6/10, 13/25, 21/40). Los récords piden el grupo entero de la hermandad y un
-- intento oficial (más abajo); las insignias por mazmorra, 4 o 5 (Merits.lua).
function ns.GuildMajority(r)
	local size, n = r.size or 0, r.guildCount or 0
	if r.raid then return size >= 10 and n > size / 2 end
	return size == 5 and n >= 3
end

local function inDungeon()
	local _, instanceType = GetInstanceInfo()
	return instanceType == "party" and not IsInRaid()
end

local function inRaidInstance()
	local _, instanceType = GetInstanceInfo()
	return instanceType == "raid" and IsInRaid()
end

-- Devuelve todos los miembros del grupo (o banda), los que son de la guild y el tamaño.
function ns.GroupComposition()
	local me = ns.PlayerFullName()
	local all = { me }
	local guild = LG:GuildName() and { me } or {}
	local raid = IsInRaid()
	local count = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
	for i = 1, count do
		local unit = (raid and "raid" or "party") .. i
		local name = ns.UnitFullName(unit)
		if name and name ~= me then
			all[#all + 1] = name
			if ns.IsGuildUnit(unit) then guild[#guild + 1] = name end
		end
	end
	return all, guild
end

-- Cuándo entró el grupo en la instancia actual, para los tiempos de mazmorra.
-- Volver a entrar en la misma instancia en menos de 30 min (p. ej. tras morir)
-- no reinicia el reloj.
local REENTER_WINDOW = 30 * 60
local entry -- { instanceID, t, left }

function ns.InstanceEnteredAt()
	local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	if instanceType ~= "party" and instanceType ~= "raid" then return nil end
	return entry and entry.instanceID == instanceID and entry.t or nil
end

-- Primera baja dentro de la instancia: el inicio del tiempo (1.2.1). Esperar en la puerta o
-- bufarse no cuenta. Salir y volver (morir y correr, ir a vender) sigue siendo la misma partida.
function ns.MarkFirstKill()
	if not entry or entry.left or entry.firstKill then return end
	local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	if (instanceType == "party" or instanceType == "raid") and entry.instanceID == instanceID then
		entry.firstKill = ns.Now()
	end
end

-- Inicio del tiempo de la partida actual: la primera baja, o la entrada si aún no la hay.
function ns.InstanceStartedAt()
	local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	if instanceType ~= "party" and instanceType ~= "raid" then return nil end
	return entry and entry.instanceID == instanceID and (entry.firstKill or entry.t) or nil
end

local function trackEntry()
	local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	local now = ns.Now()
	if instanceType == "party" or instanceType == "raid" then
		local back = entry and entry.instanceID == instanceID and entry.left and now - entry.left < REENTER_WINDOW
		if not entry or entry.instanceID ~= instanceID or (entry.left and not back) then
			entry = { instanceID = instanceID, t = now }
		end
		entry.left = nil
	elseif entry and not entry.left then
		entry.left = now
	end
end
ns.TrackInstanceEntry = trackEntry -- para las pruebas

function Dungeon:CheckGroup(event)
	if event == "PLAYER_ENTERING_WORLD" then trackEntry() end
	if not inDungeon() or not IsInGroup() then
		self.lastState = nil
		return
	end
	local all, guild = ns.GroupComposition()
	local state = #guild .. "/" .. #all
	if state == self.lastState then return end
	self.lastState = state
	ns.currentGroup = { all = all, guild = guild }

	if #all == 5 and #guild == 5 then
		RaidNotice_AddMessage(RaidWarningFrame, L["Grupo de hermandad completo (5/5): bonus activo"], ChatTypeInfo["RAID_WARNING"])
		LG:Print(L["Tu grupo es 5/5 de hermandad. Bonus activo."])
	elseif #all == 5 and #guild == 4 then
		LG:Print(L["Tu grupo es 4/5 de hermandad: bonus parcial."])
	end
	LG:DataChanged()
end

-- En Forever ENCOUNTER_END trae además la lista de jefes del encuentro con su
-- ID de criatura y la vida que les queda (encounterUnitStatus). Es el mismo ID que
-- usan los criterios de los desafíos de legado, así que se sabe qué jefe cayó.
local function deadCreatures(units)
	local ids = {}
	for _, u in ipairs(type(units) == "table" and units or {}) do
		if type(u) == "table" and u.creatureID and (u.remainingHealthPercent or 0) <= 0 then ids[#ids + 1] = u.creatureID end
	end
	return #ids > 0 and ids or nil
end

local lastKill = {} -- [encounterID] = GetTime(): ENCOUNTER_END y BOSS_KILL llegan los dos

-- BOSS_KILL solo cuenta si ENCOUNTER_END (que trae más datos) no llega en unos segundos.
function Dungeon:BOSS_KILL(_, encounterID, encounterName)
	local function fallback()
		if lastKill[encounterID] and GetTime() - lastKill[encounterID] < 30 then return end
		self:ENCOUNTER_END(nil, encounterID, encounterName, nil, nil, 1, nil, true)
	end
	if C_Timer and C_Timer.After then C_Timer.After(3, fallback) else fallback() end
end

-- Jefe final detectado por su estadística (Legacy.lua): partida con el criterio de
-- legado de la mazmorra. Misma clave para todos los del grupo (son testigos).
function ns.RecordFinalBoss(statID, info)
	if not LG:HasConsent() then return end
	local g = LG:GuildData()
	if not g then return end
	local isRaid = inRaidInstance()
	if not (inDungeon() or isRaid) then return end
	local all, guild = ns.GroupComposition()
	local instanceName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	local now = ns.Now()
	if #guild < 2 then
		LG:Print((L["%s completada."]):format(info.dungeon))
		return
	end
	table.sort(all)
	local me = ns.PlayerFullName()
	local rec = {
		key = ("stat%d:%s:%d"):format(statID, ns.Hash(table.concat(all, ",")), math.floor(now / RUN_WINDOW)),
		t = now,
		instance = instanceName,
		instanceID = instanceID,
		boss = info.dungeon,
		finalStat = statID,
		criterion = info.criterion, -- criterio de legado de la mazmorra (Legacy.lua)
		entered = ns.InstanceEnteredAt(),
		started = ns.InstanceStartedAt(), -- primera baja: inicio del tiempo (1.2.1)
		members = all,
		guildMembers = guild,
		guildCount = #guild,
		size = #all,
		raid = isRaid or nil,
		reporter = me,
		witnesses = { [me] = true },
	}
	ns.MergeRun(g, rec)
	LG:Send("RUN", rec)
	LG:Print((L["%s completada con un grupo %d/%d de hermandad."]):format(info.dungeon, #guild, #all))
	if ns.OnOfficialBoss then pcall(ns.OnOfficialBoss, rec, true) end
	if ns.SendRunStats then pcall(ns.SendRunStats) end
	LG:DataChanged()
end

function Dungeon:ENCOUNTER_END(_, encounterID, encounterName, difficultyID, groupSize, success, units, fromBossKill)
	if success == 1 then
		if lastKill[encounterID] and GetTime() - lastKill[encounterID] < 30 then return end
		lastKill[encounterID] = GetTime()
	end
	local creatures = deadCreatures(units)
	-- Diagnóstico y aprendizaje de jefes finales (Legacy.lua), con o sin grupo de hermandad.
	if ns.OnEncounterEnd then pcall(ns.OnEncounterEnd, encounterID, encounterName, difficultyID, groupSize, success, units, fromBossKill) end
	-- Mazmorras y, desde los desafíos de hermandad, también bandas.
	local isRaid = inRaidInstance()
	if success ~= 1 or not (inDungeon() or isRaid) or not LG:HasConsent() then return end
	local g = LG:GuildData()
	if not g then return end

	local all, guild = ns.GroupComposition()
	if #guild < 2 then return end -- solo interesan grupos con más de un miembro de la guild
	table.sort(all)
	local now = ns.Now()
	local instanceName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	local me = ns.PlayerFullName()
	local rec = {
		key = ("%d:%s:%d"):format(encounterID, ns.Hash(table.concat(all, ",")), math.floor(now / RUN_WINDOW)),
		t = now,
		instance = instanceName,
		instanceID = instanceID,
		encounterID = encounterID,
		boss = encounterName,
		creatures = creatures, -- ID de criatura de los jefes muertos (Forever)
		entered = ns.InstanceEnteredAt(), -- para agrupar los jefes de una partida (LFG.lua)
		started = ns.InstanceStartedAt(), -- primera baja: inicio del tiempo (1.2.1)
		members = all,
		guildMembers = guild, -- quiénes cobran los puntos de mazmorra
		guildCount = #guild,
		size = #all,
		raid = isRaid or nil,
		reporter = me,
		witnesses = { [me] = true },
	}
	ns.MergeRun(g, rec)
	LG:Send("RUN", rec)
	LG:Print((L["%s derrotado con un grupo %d/%d de hermandad."]):format(encounterName, #guild, #all))
	if ns.OnOfficialBoss then pcall(ns.OnOfficialBoss, rec, false) end
	if ns.SendRunStats then pcall(ns.SendRunStats) end
	LG:DataChanged()
end

---------------------------------------------------------------------------
-- Intento oficial (1.2.1): solo cuenta para los récords de la hermandad
--
-- Con el grupo entero de la hermandad (5/5 en mazmorra; en banda, todos de la guild y al
-- menos 10), alguien lo declara antes de la primera baja y cada miembro paga OFFICIAL_FEE
-- insignias (Shop.lua, tasa «officialRun»). La partida es oficial si pagan todos: entonces
-- entra en los récords y, durante la partida, cada jefe avisa del ritmo contra el récord. Si
-- no se completa, lo pagado se pierde. Cada pago lo firma su miembro (BUY), como en la tienda.
---------------------------------------------------------------------------

ns.OFFICIAL_FEE = 15
local ATTEMPT_TTL = 4 * 3600 -- un intento vale para una partida empezada en las 4 h siguientes
ns.ATTEMPT_TTL = ATTEMPT_TTL

function ns.MergeAttempt(g, rec, sender)
	if type(rec) ~= "table" or type(rec.id) ~= "string" or type(rec.by) ~= "string" or type(rec.t) ~= "number" then return false end
	if type(rec.members) ~= "table" or #rec.members < 5 or #rec.members > 40 then return false end
	if sender and rec.by ~= sender then return false end
	g.attempts = g.attempts or {}
	if g.attempts[rec.id] then return false end
	local members = {}
	for _, m in ipairs(rec.members) do if type(m) == "string" then members[#members + 1] = m end end
	table.sort(members)
	g.attempts[rec.id] = { id = rec.id, by = rec.by, t = rec.t, members = members, raid = rec.raid and true or nil,
		instance = type(rec.instance) == "string" and rec.instance:sub(1, 60) or nil }
	return true
end

-- Grupo entero de la hermandad ahora mismo: los miembros (ordenados), o nil y el motivo.
function ns.FullGuildGroup()
	if not IsInGroup() then return nil, L["Necesitas un grupo."] end
	local all, guild = ns.GroupComposition()
	if #guild < #all then return nil, (L["Solo con el grupo entero de la hermandad (%d/%d)."]):format(#guild, #all) end
	if IsInRaid() then
		if #all < 10 then return nil, L["En banda, al menos 10 de la hermandad."] end
	elseif #all ~= 5 then
		return nil, (L["Hace falta un grupo de 5 (sois %d)."]):format(#all)
	end
	table.sort(all)
	return all
end

local function sameMembers(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do if a[i] ~= b[i] then return false end end
	return true
end
ns.SameMembers = sameMembers

-- Quién ha pagado ya el intento ({ [miembro] = true }), si están todos y cuántos.
function ns.AttemptPaid(g, a)
	local paid, n = {}, 0
	for id, p in pairs(g.purchases or {}) do
		if p.item == "officialRun" and p.ref == a.id and not paid[p.member] and ns.FeePaid and ns.FeePaid(id) then
			paid[p.member] = true
			n = n + 1
		end
	end
	local all = true
	for _, m in ipairs(a.members) do if not paid[m] then all = false end end
	return paid, all, n
end

-- El intento de este grupo (los mismos miembros, declarado hace menos de ATTEMPT_TTL), si lo hay.
function ns.CurrentAttempt()
	local g = LG:GuildData()
	if not g or not IsInGroup() then return nil end
	local all = ns.GroupComposition()
	table.sort(all)
	local best
	for _, a in pairs(g.attempts or {}) do
		if ns.Now() - a.t < ATTEMPT_TTL and sameMembers(a.members, all) and (not best or a.t > best.t) then best = a end
	end
	return best
end

function ns.DeclareAttempt()
	local g = LG:GuildData()
	if not g then return false, L["No estás en una hermandad."] end
	local members, why = ns.FullGuildGroup()
	if not members then return false, why end
	if ns.CurrentAttempt() then return false, L["Este grupo ya tiene un intento oficial en marcha."] end
	local started = ns.InstanceStartedAt()
	if started and ns.InstanceEnteredAt() ~= started then return false, L["La partida ya ha empezado: decláralo antes de la primera baja."] end
	local free = ns.AvailableInsignias(nil)
	if free < ns.OFFICIAL_FEE then return false, (L["Cuesta %d insignias y tienes %d libres."]):format(ns.OFFICIAL_FEE, free) end
	local me, now = ns.PlayerFullName(), ns.Now()
	local name, instanceType = GetInstanceInfo()
	local rec = { id = ("%s:att:%d"):format(me, now), by = me, t = now, members = members, raid = IsInRaid() or nil,
		instance = (instanceType == "party" or instanceType == "raid") and name or nil }
	ns.MergeAttempt(g, rec)
	LG:Send("ATTEMPT", rec)
	ns.Buy("officialRun", rec.id)
	LG:Print((L["Intento oficial declarado: cada uno paga %d insignias. Cuenta para los récords cuando paguéis todos."]):format(ns.OFFICIAL_FEE))
	LG:DataChanged()
	return true
end

-- Pagar mi parte de un intento (desde el aviso o desde JcE).
function ns.PayAttempt(id)
	local g = LG:GuildData()
	local a = g and g.attempts and g.attempts[id]
	if not a then return false end
	if ns.AttemptPaid(g, a)[ns.PlayerFullName()] then return true end
	local ok, err = ns.Buy("officialRun", id)
	if not ok and err then LG:Print(err) end
	return ok
end

StaticPopupDialogs["LANTUX_ATTEMPT"] = {
	text = "%s", button1 = L["Pagar"], button2 = L["No"],
	OnAccept = function(_, data) if data then ns.PayAttempt(data) end end,
	timeout = 120, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

ns.handlers.ATTEMPT = function(sender, rec)
	local g = LG:GuildData()
	if not g or not ns.MergeAttempt(g, rec, sender) then return end
	LG:DataChanged()
	local me = ns.PlayerFullName()
	local a = g.attempts[rec.id]
	if a.by == me or ns.Now() - a.t > 600 then return end
	for _, m in ipairs(a.members) do
		if m == me then
			local text = (L["%s declara un intento oficial: %d insignias cada uno. Solo los intentos oficiales cuentan para los récords de la hermandad."])
				:format(ns.ShortName(a.by), ns.OFFICIAL_FEE)
			local dialog = StaticPopup_Show("LANTUX_ATTEMPT", text)
			if dialog then dialog.data = a.id end
		end
	end
end

-- Ritmo en directo: al caer cada jefe de un intento oficial pagado, la diferencia con el récord.
function ns.OnOfficialBoss(rec, final)
	local g = LG:GuildData()
	local a = ns.CurrentAttempt()
	if not g or not a or not rec.started then return end
	local _, allPaid = ns.AttemptPaid(g, a)
	if not allPaid then return end
	local split = rec.t - rec.started
	local record = ns.DungeonRecordByInstance and ns.DungeonRecordByInstance(rec.instanceID, rec.key)
	local dungeon = (record and record.dungeon) or (ns.RunDungeonName and ns.RunDungeonName(rec)) or rec.instance
	local text
	if record then
		local theirs = final and record.duration or (ns.RunSplit and ns.RunSplit(record, rec))
		if theirs then
			local diff = split - theirs
			if final and diff < 0 then
				text = (L["¡Nuevo récord de la hermandad en %s: %s!"]):format(dungeon, ns.FormatRunTime(split))
				if ns.GuildAnnounce then ns.GuildAnnounce(text) end
			else
				text = (diff <= 0 and L["%s: %s · %s por delante del récord"] or L["%s: %s · %s por detrás del récord"])
					:format(rec.boss or "?", ns.FormatRunTime(split), ns.FormatRunTime(math.abs(diff)))
			end
		end
	elseif final and dungeon then
		text = (L["¡Primer récord oficial de la hermandad en %s: %s!"]):format(dungeon, ns.FormatRunTime(split))
		if ns.GuildAnnounce then ns.GuildAnnounce(text) end
	end
	if text then
		LG:Print(text)
		if RaidNotice_AddMessage and RaidWarningFrame then RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"]) end
	end
end

---------------------------------------------------------------------------
-- Datos de la partida (1.3): oro, muertes y botín
--
-- Cada addon apunta, mientras está dentro de la instancia:
--   · oro: lo que sube su dinero (botín y su parte del reparto; los gastos no restan);
--   · muertes: las suyas;
--   · botín: lo raro o mejor que recibe cualquiera del grupo (mensajes de botín del chat).
-- Tras cada jefe manda su resumen (RUNSTAT, firmado: solo el suyo) y en JcE se juntan los de
-- todos en la partida (LFG.lua). Del oro y las muertes solo cuenta quien lleva el addon.
---------------------------------------------------------------------------

local LOOT_MIN_QUALITY = 3 -- raro (azul) o mejor
local LOOT_MAX = 20

local function insideEntry()
	if not entry or entry.left then return false end
	local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	return (instanceType == "party" or instanceType == "raid") and entry.instanceID == instanceID
end

local function runStats()
	entry.stats = entry.stats or { gold = 0, deaths = 0, loot = {} }
	return entry.stats
end

-- Patrón de Lua a partir de un texto del juego ("%s recibe botín: %s.").
local function globalPattern(name)
	local fmt = _G[name]
	if type(fmt) ~= "string" then return nil end
	local p = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
	p = p:gsub("%%%d%%%$s", "\1"):gsub("%%%d%%%$d", "\2"):gsub("%%s", "\1"):gsub("%%d", "\2")
	p = p:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
	return "^" .. p .. "$"
end

local lootPatterns
local function lootWho(text)
	if not lootPatterns then
		lootPatterns = {}
		for _, def in ipairs({ { "LOOT_ITEM_SELF_MULTIPLE", true }, { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", true }, { "LOOT_ITEM_SELF", true },
			{ "LOOT_ITEM_PUSHED_SELF", true }, { "LOOT_ITEM_MULTIPLE", false }, { "LOOT_ITEM_PUSHED_MULTIPLE", false },
			{ "LOOT_ITEM", false }, { "LOOT_ITEM_PUSHED", false } }) do
			local p = globalPattern(def[1])
			if p then lootPatterns[#lootPatterns + 1] = { pattern = p, self = def[2] } end
		end
	end
	for _, p in ipairs(lootPatterns) do
		local a, b = text:match(p.pattern)
		if a then
			if p.self then return ns.PlayerFullName(), a end
			return a, b
		end
	end
	return nil
end
ns.ParseGroupLoot = lootWho -- para las pruebas

function ns.OnRunLoot(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or not insideEntry() then return end
	local who, link = lootWho(text)
	if not who or type(link) ~= "string" then return end
	local itemID = tonumber(link:match("item:(%d+)"))
	if not itemID then return end
	local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
	if not quality then quality = select(3, ns.GetItemInfo(itemID)) end
	if not quality or quality < LOOT_MIN_QUALITY then return end
	local loot = runStats().loot
	if #loot >= LOOT_MAX then return end
	loot[#loot + 1] = { id = itemID, q = quality, who = who, t = ns.Now() }
end

local lastMoney
function ns.OnRunMoney()
	local money = GetMoney and GetMoney() or 0
	if lastMoney and money > lastMoney and insideEntry() then
		local s = runStats()
		s.gold = s.gold + (money - lastMoney)
	end
	lastMoney = money
end

function ns.OnRunDeath()
	if insideEntry() then
		local s = runStats()
		s.deaths = s.deaths + 1
	end
end

-- Mi resumen de la partida actual, tras cada jefe (se reemplaza por el más reciente).
function ns.SendRunStats()
	local g = LG:GuildData()
	if not g or not entry or not LG:HasConsent() then return end
	local s = runStats()
	local me = ns.PlayerFullName()
	local all = ns.GroupComposition()
	table.sort(all)
	local rec = { key = ("%s:rs:%s:%d"):format(me, tostring(entry.instanceID), entry.t), reporter = me, t = ns.Now(),
		instanceID = entry.instanceID, entered = entry.t, members = all, gold = s.gold, deaths = s.deaths, loot = s.loot }
	ns.MergeRunStats(g, rec)
	LG:Send("RUNSTAT", rec)
end

function ns.MergeRunStats(g, rec, sender)
	if type(rec) ~= "table" or type(rec.key) ~= "string" or type(rec.reporter) ~= "string" or type(rec.t) ~= "number" then return false end
	if sender and rec.reporter ~= sender then return false end
	if type(rec.members) ~= "table" or type(rec.entered) ~= "number" then return false end
	g.runStats = g.runStats or {}
	local old = g.runStats[rec.key]
	if old and (old.t or 0) >= rec.t then return false end
	local loot = {}
	for i, x in ipairs(type(rec.loot) == "table" and rec.loot or {}) do
		if i > LOOT_MAX then break end
		if type(x) == "table" and tonumber(x.id) and type(x.who) == "string" then
			loot[#loot + 1] = { id = tonumber(x.id), q = math.min(7, math.max(0, tonumber(x.q) or 0)), who = x.who:sub(1, 48), t = tonumber(x.t) }
		end
	end
	local members = {}
	for _, m in ipairs(rec.members) do if type(m) == "string" then members[#members + 1] = m end end
	g.runStats[rec.key] = { key = rec.key, reporter = rec.reporter, t = rec.t, instanceID = rec.instanceID, entered = rec.entered,
		members = members, gold = math.max(0, math.floor(tonumber(rec.gold) or 0)), deaths = math.max(0, math.floor(tonumber(rec.deaths) or 0)), loot = loot }
	return true
end

ns.handlers.RUNSTAT = function(sender, rec)
	local g = LG:GuildData()
	if g and ns.MergeRunStats(g, rec, sender) then LG:DataChanged() end
end
