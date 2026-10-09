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
		entered = ns.InstanceEnteredAt(), -- para el tiempo de la mazmorra (LFG.lua)
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
	LG:DataChanged()
end
