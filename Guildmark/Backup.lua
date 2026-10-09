-- Protección de los datos guardados.
--
-- En la beta de Forever a veces los datos guardados de un addon no se cargan al
-- entrar (fallo conocido de Blizzard). El addon arrancaría vacío y al salir el
-- juego escribiría ese estado vacío encima de los datos buenos.
--
-- Dos defensas:
--   1. Copia de seguridad en otro archivo (GuildmarkBackup, por personaje): se
--      escribe al salir y, si al entrar falta GuildmarkDB, se restaura desde ella.
--   2. Si no hay ni datos ni copia, lo personal (recolección, fabricación, contador
--      de honor de partida, antigüedad, jefes aprendidos) se recupera de la ficha
--      que la hermandad tiene de ti, quedándose siempre con el valor mayor o más
--      antiguo (ns.AdoptOwnRecord, desde la sincronización).
local _, ns = ...

-- Lo que no hace falta copiar: diagnóstico y lo que se regenera solo.
local SKIP_GLOBAL = { diag = true, recapDebug = true, castDebug = true, export = true, blocked = true }

local function copy(value, skip)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do
		if not (skip and skip[k]) then out[k] = copy(v) end
	end
	return out
end

local function looksLoaded(db)
	return type(db) == "table" and type(db.global) == "table" and db.global.schema ~= nil
end

-- Se llama al principio de OnEnable, antes de crear la base de datos.
-- Devuelve true si se ha restaurado desde la copia.
function ns.RestoreSavedVariables()
	if looksLoaded(GuildmarkDB) then return false end
	local backup = GuildmarkBackup
	if type(backup) ~= "table" or not looksLoaded(backup.db) then return false end
	GuildmarkDB = copy(backup.db)
	GuildmarkDB.global.restoredAt = { t = time(), backupT = backup.t }
	return true
end

local function writeBackup()
	if not looksLoaded(GuildmarkDB) then return end
	local db = {}
	for k, v in pairs(GuildmarkDB) do
		db[k] = copy(v, k == "global" and SKIP_GLOBAL or nil)
	end
	GuildmarkBackup = { t = time(), db = db }
end
ns.WriteBackup = writeBackup -- para las pruebas

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGOUT")
watcher:SetScript("OnEvent", writeBackup)

-- Tu ficha tal como la tiene la hermandad: si guarda cuentas mayores (o fechas
-- más antiguas) que las tuyas, es que perdiste datos; se recuperan.
function ns.AdoptOwnRecord(rec)
	local LG = ns.LG
	if type(rec) ~= "table" or not LG.db then return false end
	local char = LG.db.char
	local changed = false
	local function maxInto(t, key, value)
		if type(value) == "number" and value > (t[key] or 0) then
			t[key] = value
			changed = true
		end
	end

	local s, theirs = char.stats, rec.stats
	if type(theirs) == "table" then
		for kind, n in pairs(type(theirs.gathered) == "table" and theirs.gathered or {}) do maxInto(s.gathered, kind, n) end
		maxInto(s, "crafted", theirs.crafted)
		maxInto(s, "crafts", theirs.crafts)
		maxInto(s, "bestDay", theirs.bestDay)
		if theirs.week and theirs.week == s.week then
			s.weekGathered = s.weekGathered or {}
			for kind, n in pairs(type(theirs.weekGathered) == "table" and theirs.weekGathered or {}) do maxInto(s.weekGathered, kind, n) end
			maxInto(s, "weekCrafted", theirs.weekCrafted)
		end
	end

	local guild = LG:GuildName()
	if guild then
		-- Antigüedad: la fecha más antigua.
		if type(rec.joined) == "number" and (not char.joined[guild] or rec.joined < char.joined[guild]) then
			char.joined[guild] = rec.joined
			changed = true
		end
		-- Contador de honor de partida: el más antiguo (si no, las kills de antes no cuadrarían).
		local base = type(rec.pvp) == "table" and rec.pvp.base
		local mine = char.hkBase[guild]
		if type(base) == "table" and type(base.t) == "number" and type(base.hk) == "number"
			and (not mine or base.t < (mine.t or math.huge)) then
			char.hkBase[guild] = { t = base.t, hk = base.hk }
			changed = true
		end
	end

	-- Jefes finales aprendidos: se juntan.
	for criteriaID, finals in pairs(type(rec.legacy) == "table" and rec.legacy or {}) do
		if type(finals) == "table" then
			local learned = LG.db.global.legacyLearned
			for encounterID, v in pairs(finals) do
				learned[criteriaID] = learned[criteriaID] or {}
				if not learned[criteriaID][encounterID] then
					learned[criteriaID][encounterID] = v
					changed = true
				end
			end
		end
	end

	if changed then
		LG:Print(ns.L["Se han recuperado datos tuyos que tenía la hermandad (los guardados no se cargaron bien)."])
		LG:MarkDirty()
	end
	return changed
end
