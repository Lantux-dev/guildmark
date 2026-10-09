-- Estadísticas de honor propias. Cada cliente solo puede leer las suyas,
-- así que cada miembro las publica en su registro.
--
-- Comprobado en la beta de Forever (1.60.1): GetPVPLifetimeStats, GetPVPSessionStats
-- y GetPVPYesterdayStats existen y devuelven 2 valores. No existen el rango PvP de
-- Classic (UnitPVPRank, GetPVPRankInfo) ni GetPVPThisWeekStats.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local PvP = LG:NewModule("PvP", "AceEvent-3.0")

-- Rango JcJ de Forever: el renombre de la facción 2800 (comprobado en la beta:
-- 14 rangos de 750 puntos, por temporadas). Solo se puede leer el propio, así que
-- cada uno lo manda en su ficha (pvp.rank). Nadie más puede comprobarlo.
local RANK_FACTION = 2800
ns.PVP_RANK_MAX = 14

function ns.MyPvPRank()
	if not (C_MajorFactions and C_MajorFactions.GetMajorFactionProgressionInfo) then return nil end
	local ok, info = pcall(C_MajorFactions.GetMajorFactionProgressionInfo, RANK_FACTION)
	if not ok or type(info) ~= "table" or type(info.renownLevel) ~= "number" then return nil end
	return { level = info.renownLevel, max = info.maxLevel, earned = info.renownReputationEarned,
		need = info.renownLevelThreshold, season = ns.PvPSeason and ns.PvPSeason() or nil }
end

-- Rango JcJ de un miembro (el mío, en directo): { level, max, earned, need } saneado, o nil.
function ns.MemberPvPRank(name)
	local r
	if name == ns.PlayerFullName() then
		r = ns.MyPvPRank()
	else
		local g = LG:GuildData()
		local m = g and g.members[name]
		r = m and m.pvp and type(m.pvp.rank) == "table" and m.pvp.rank or nil
	end
	local level = r and tonumber(r.level)
	if not level then return nil end
	local max = math.max(1, math.min(30, math.floor(tonumber(r.max) or ns.PVP_RANK_MAX)))
	return { level = math.max(0, math.min(max, math.floor(level))), max = max,
		earned = math.max(0, math.floor(tonumber(r.earned) or 0)), need = math.max(0, math.floor(tonumber(r.need) or 0)) }
end

-- Icono del rango (los de los logros de rango JcJ del juego, por facción).
function ns.PvPRankIcon(level, faction)
	if not level or level < 1 then return nil end
	faction = faction or (UnitFactionGroup and UnitFactionGroup("player"))
	return ("Interface\\Icons\\Achievement_PVP_%s_%02d"):format(faction == "Alliance" and "A" or "H", math.min(level, 14))
end

local function firstValue(fn)
	if not fn then return nil end
	local ok, value = pcall(fn)
	return ok and value or nil
end

function PvP:OnEnable()
	ns.RegisterEvent(self, "PLAYER_PVP_KILLS_CHANGED", "Changed")
	ns.RegisterEvent(self, "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "Changed")
	-- Campos de batalla: la tabla de puntuaciones es secreta mientras dura la
	-- partida (SecretInActivePvPMatch) y se puede leer al terminar.
	ns.RegisterEvent(self, "PVP_MATCH_COMPLETE", function(_, winner, duration)
		C_Timer.After(2, function() PvP:CaptureMatch(winner, duration) end)
	end)
end

-- Al acabar un campo de batalla: la tabla de puntuaciones (diagnóstico) y el
-- resultado propio, que se comparte con la hermandad (BGMATCH).
function PvP:CaptureMatch(winner, duration)
	local rows = {}
	local mine
	local count = GetNumBattlefieldScores and select(2, pcall(GetNumBattlefieldScores)) or 0
	for i = 1, (type(count) == "number" and count or 0) do
		local ok, info = pcall(C_PvP.GetScoreInfo, i)
		if ok and type(info) == "table" then
			rows[#rows + 1] = { name = info.name, guid = info.guid, faction = info.faction, class = info.classToken,
				kb = info.killingBlows, hk = info.honorableKills, deaths = info.deaths, honor = info.honorGained }
			if info.guid and info.guid == UnitGUID("player") then mine = rows[#rows] end
		end
		if #rows >= 40 then break end
	end
	local map = select(1, GetInstanceInfo())
	LG.db.global.diag.lastMatch = { t = date("%Y-%m-%d %H:%M:%S"), map = map, winner = winner, duration = duration,
		myFaction = UnitFactionGroup("player"), count = count, rows = rows }
	if type(winner) ~= "number" and GetBattlefieldWinner then winner = GetBattlefieldWinner() end
	ns.RecordBGMatch(map, winner, duration, mine)
end

-- Resultado: el ganador es el índice del bando (0 = Horda, 1 = Alianza); otro valor, empate.
local function num(v, max)
	v = tonumber(v)
	return v and v >= 0 and v <= max and math.floor(v) or nil
end

function ns.MergeBGMatch(g, rec, sender)
	if type(rec.id) ~= "string" or type(rec.member) ~= "string" or type(rec.t) ~= "number" then return false end
	if rec.result ~= "win" and rec.result ~= "loss" and rec.result ~= "draw" then return false end
	if sender and rec.member ~= sender then return false end
	if g.bgMatches[rec.id] then return false end
	g.bgMatches[rec.id] = {
		id = rec.id, member = rec.member, t = rec.t, result = rec.result,
		map = type(rec.map) == "string" and rec.map:sub(1, 40) or nil,
		kb = num(rec.kb, 500), hk = num(rec.hk, 500), deaths = num(rec.deaths, 500), duration = num(rec.duration, 6 * 3600),
	}
	return true
end

ns.handlers.BGMATCH = function(sender, rec)
	local g = LG:GuildData()
	if g and ns.MergeBGMatch(g, rec, sender) then LG:DataChanged() end
end

function ns.RecordBGMatch(map, winner, duration, mine)
	local g = LG:GuildData()
	if not g or not LG:HasConsent() then return end
	local me = ns.PlayerFullName()
	local myTeam = UnitFactionGroup("player") == "Alliance" and 1 or 0
	local result = (winner == 0 or winner == 1) and (winner == myTeam and "win" or "loss") or "draw"
	local now = ns.Now()
	local rec = { id = ("%s:bg:%d"):format(me, now), member = me, t = now, result = result, map = map,
		kb = mine and mine.kb, hk = mine and mine.hk, deaths = mine and mine.deaths, duration = duration }
	if not ns.MergeBGMatch(g, rec) then return end
	LG:Send("BGMATCH", g.bgMatches[rec.id])
	LG:DataChanged()
	LG:Print((result == "win" and L["Victoria en %s registrada."] or L["Derrota en %s registrada."]):format(map or "?"))
end

-- Victorias y derrotas de un miembro (o de todos si name es nil): { wins, losses, kb, hk }.
function ns.BGRecord(name)
	local g = LG:GuildData()
	local r = { wins = 0, losses = 0, kb = 0, hk = 0 }
	for id, m in pairs(g and g.bgMatches or {}) do
		if (not name or m.member == name) and not ns.IsVoided(g, id) then
			if m.result == "win" then r.wins = r.wins + 1 else r.losses = r.losses + 1 end
			r.kb, r.hk = r.kb + (m.kb or 0), r.hk + (m.hk or 0)
		end
	end
	return r
end

function PvP:Changed()
	LG:MarkDirty()
end

-- "base" es el contador cuando el addon empezó a contar en esta hermandad: los
-- oficiales comparan lo que ha subido desde entonces con las kills registradas.
table.insert(ns.recordProviders, function(rec)
	local hk = firstValue(GetPVPLifetimeStats)
	local guild = LG:GuildName()
	local base
	if type(hk) == "number" and guild then
		local bases = LG.db.char.hkBase
		bases[guild] = bases[guild] or { t = ns.Now(), hk = hk }
		base = bases[guild]
	end
	rec.pvp = {
		base = base,
		hk = hk,
		today = firstValue(GetPVPSessionStats),
		yesterday = firstValue(GetPVPYesterdayStats),
		week = firstValue(GetPVPThisWeekStats),
		rank = ns.MyPvPRank(),
	}
end)
