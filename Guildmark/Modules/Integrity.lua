-- Integridad de los datos: avisos para los oficiales y anulaciones.
--
-- Los avisos no quitan puntos por sí solos: el addon señala lo raro y un oficial
-- decide. Lo que sí se comparte son las anulaciones (VOID): una kill, un encargo,
-- una asistencia o un ajuste anulados dejan de dar puntos y de contar para los
-- desafíos en el addon de todos.
--
-- Comprobaciones (se calculan en cada cliente con los datos ya sincronizados):
--   honor       kills honorables registradas desde que el addon empezó a contar,
--               frente a lo que ha subido el contador de muertes honorables del juego
--   inspección  el contador que manda su addon frente al que ve otro al inspeccionarle
--               (GetInspectHonorData: un dato que no sale de su propio addon)
--   contador    el contador de un miembro ha bajado (solo pasa con el addon tocado)
--   víctima     la misma víctima muchas veces el mismo día (intercambio de kills)
--   asistencia  confirmada fuera del horario del evento
--   encargos    varias entregas dadas por buenas por el artesano sin intercambio
--   ajustes     ajustes grandes hechos por otro oficial
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Integrity = LG:NewModule("Integrity", "AceEvent-3.0", "AceTimer-3.0")

local HK_TOLERANCE = 2        -- el contador puede ir un instante por detrás del registro
local SAME_VICTIM_ALERT = 5   -- kills a la misma víctima el mismo día
local BIG_ADJUST = 100
local SELF_MARKED_ALERT = 3   -- entregas sin intercambio del mismo artesano en la ventana
local ATTEND_SLACK = 300
local WINDOW = 7 * 86400      -- los avisos miran los últimos 7 días
local DAY = 86400

-- Inspección de honor de compañeros cercanos (para verificar el contador con
-- un dato que no viene de su propio addon). GetInspectHonorData en Forever
-- (comprobado): hoy, honor de hoy, ayer, honor de ayer, TOTALES, rango, temporada.
local INSPECT_EVERY = 120
local INSPECT_AGAIN = 1800

---------------------------------------------------------------------------
-- Anulaciones
---------------------------------------------------------------------------

function ns.IsVoided(g, id)
	local v = g and g.voids and g.voids[id]
	return v ~= nil and v.active == true
end

function ns.AttendanceVoidID(eventID, member)
	return ("att|%s|%s"):format(eventID, member)
end

-- Contador de muertes honorables de un miembro visto por otro al inspeccionarle.
function ns.MergeHonorSeen(g, rec, sender)
	if type(rec.member) ~= "string" or type(rec.by) ~= "string" or type(rec.t) ~= "number" or type(rec.hk) ~= "number" then return false end
	if sender and rec.by ~= sender then return false end
	if rec.by == rec.member then return false end -- nadie se inspecciona a sí mismo
	local old = g.honorSeen[rec.member]
	if old and (old.t or 0) >= rec.t then return false end
	g.honorSeen[rec.member] = { hk = math.max(0, math.floor(rec.hk)), today = tonumber(rec.today), t = rec.t, by = rec.by }
	return true
end

ns.handlers.HONOR = function(sender, rec)
	local g = LG:GuildData()
	if g and type(rec) == "table" and ns.MergeHonorSeen(g, rec, sender) then LG:DataChanged() end
end

function ns.MergeVoid(g, rec, sender)
	if type(rec.id) ~= "string" or type(rec.t) ~= "number" then return false end
	if sender and rec.by ~= sender then return false end
	if not ns.Can("adjust", rec.by) then return false end
	local old = g.voids[rec.id]
	if old and (old.t or 0) >= rec.t then return false end
	g.voids[rec.id] = { active = rec.active and true or false, by = rec.by, t = rec.t, kind = rec.kind, member = rec.member, label = rec.label }
	return true
end

-- Llega una lista de anulaciones (un aviso puede anular varias cosas de golpe).
ns.handlers.VOID = function(sender, list)
	local g = LG:GuildData()
	if not g or type(list) ~= "table" then return end
	local changed = false
	for _, rec in ipairs(list) do
		if type(rec) == "table" then changed = ns.MergeVoid(g, rec, sender) or changed end
	end
	if changed then LG:DataChanged() end
end

-- items = { { id, kind, member, label }, ... }
function ns.SetVoided(items, active)
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	if not g or not ns.Can("adjust", me) then
		LG:Print(L["Solo los oficiales pueden anular registros."])
		return
	end
	local now = ns.Now()
	local batch = {}
	for _, it in ipairs(items) do
		-- Siempre posterior a la decisión anterior, aunque se deshaga en el mismo segundo.
		local old = g.voids[it.id]
		local t = math.max(now, old and (old.t or 0) + 1 or now)
		local rec = { id = it.id, kind = it.kind, member = it.member, label = it.label, active = active, by = me, t = t }
		if ns.MergeVoid(g, rec) then batch[#batch + 1] = rec end
	end
	if #batch == 0 then return end
	LG:Send("VOID", batch)
	LG:DataChanged()
	LG:Print((active and L["%d registros anulados: ya no dan puntos."] or L["%d registros restaurados."]):format(#batch))
end

function ns.RecentVoids(max)
	local g = LG:GuildData()
	local list = {}
	if not g then return list end
	for id, v in pairs(g.voids) do
		if v.active then list[#list + 1] = { id = id, kind = v.kind, member = v.member, label = v.label, by = v.by, t = v.t } end
	end
	table.sort(list, function(a, b) return a.t > b.t end)
	for i = #list, (max or 10) + 1, -1 do list[i] = nil end
	return list
end

---------------------------------------------------------------------------
-- Avisos
---------------------------------------------------------------------------

local function killItem(k)
	return { id = k.id, kind = "kill", member = k.killerName,
		label = (L["Kill de %s a %s (%s)"]):format(ns.ShortName(k.killerName) or "?", ns.ShortName(k.victimName) or "?", date("%d/%m %H:%M", k.t)) }
end

-- Lista de avisos, los más graves y recientes primero:
-- { key, severity = "high" | "medium" | "info", member, text, detail = { líneas }, items = { anulables }, t }
function ns.Anomalies()
	local g = LG:GuildData()
	local list = {}
	if not g then return list end
	local now = ns.Now()
	local function add(a)
		if not g.dismissed[a.key] then list[#list + 1] = a end
	end

	-- Kills honorables vigentes de cada miembro.
	local byKiller = {}
	for _, k in pairs(g.kills) do
		if k.kind == "kill" and k.honorable and k.killerName and not ns.IsVoided(g, k.id) then
			local l = byKiller[k.killerName] or {}
			l[#l + 1] = k
			byKiller[k.killerName] = l
		end
	end

	for name, kills in pairs(byKiller) do
		table.sort(kills, function(a, b) return a.t < b.t end)
		local m = g.members[name]
		local pvp = m and m.pvp
		local base = pvp and pvp.base
		local short = ns.ShortName(name)

		-- Contador de honor del juego frente a lo registrado.
		if pvp and pvp.hk and base and base.hk and base.t then
			if pvp.hk < base.hk then
				add({
					key = ("hkdown|%s|%d"):format(name, pvp.hk), severity = "high", member = name, t = m.t or now,
					text = (L["%s: su contador de muertes honorables ha bajado."]):format(short),
					detail = { (L["Empezó en %d y ahora dice %d. El juego nunca lo baja: puede tener el addon modificado."]):format(base.hk, pvp.hk) },
				})
			else
				local claimed = {}
				for _, k in ipairs(kills) do
					if k.t > base.t and k.t <= (m.t or now) then claimed[#claimed + 1] = k end
				end
				local real = pvp.hk - base.hk
				local excess = #claimed - real
				if excess > HK_TOLERANCE then
					local items = {}
					for i = #claimed - excess + 1, #claimed do items[#items + 1] = killItem(claimed[i]) end
					add({
						key = ("hk|%s|%d|%d"):format(name, base.t, excess), severity = "high", member = name, t = claimed[#claimed].t,
						text = (L["%s: %d kills registradas, pero su contador de honor solo ha subido %d."]):format(short, #claimed, real),
						detail = {
							(L["Desde el %s el juego le cuenta %d muertes honorables y el addon tiene %d."]):format(date("%d/%m", base.t), real, #claimed),
							L["Anular quita las más recientes que sobran."],
						},
						items = items,
					})
				end
			end
		end

		-- (la comparación con la inspección va aparte, para todos los miembros)

		-- Misma víctima muchas veces el mismo día.
		local perDay = {}
		for _, k in ipairs(kills) do
			if now - k.t <= WINDOW then
				local key = ("%s|%d"):format(k.victim or k.victimName or "?", math.floor(k.t / DAY))
				perDay[key] = perDay[key] or {}
				table.insert(perDay[key], k)
			end
		end
		for key, ks in pairs(perDay) do
			if #ks >= SAME_VICTIM_ALERT then
				local items = {}
				for _, k in ipairs(ks) do items[#items + 1] = killItem(k) end
				add({
					key = ("victim|%s|%s|%d"):format(name, key, #ks), severity = "medium", member = name, t = ks[#ks].t,
					text = (L["%s ha matado %d veces a %s el mismo día."]):format(short, #ks, ns.ShortName(ks[1].victimName) or "?"),
					detail = {
						L["Puede ser un intercambio de kills con un amigo de la otra facción."],
						L["A partir de la cuarta ya no daban insignias. Anular quita también las primeras."],
					},
					items = items,
				})
			end
		end
	end

	-- Contador que manda cada uno frente al que ha visto otro al inspeccionarle.
	-- El contador solo sube: un informe anterior a la inspección no puede tener
	-- más y uno posterior no puede tener menos.
	for name, seen in pairs(g.honorSeen) do
		local m = g.members[name]
		local pvp = m and m.pvp
		if pvp and pvp.hk and m.t then
			local before = m.t <= seen.t and pvp.hk > seen.hk + HK_TOLERANCE
			local after = m.t > seen.t and pvp.hk < seen.hk
			if before or after then
				add({
					key = ("hkseen|%s|%d|%d"):format(name, seen.hk, pvp.hk), severity = "high", member = name, t = math.max(seen.t, m.t),
					text = (L["%s: su addon dice %d muertes honorables, pero al inspeccionarle el juego decía %d."]):format(ns.ShortName(name), pvp.hk, seen.hk),
					detail = {
						(L["Inspección de %s el %s."]):format(ns.ShortName(seen.by) or "?", date("%d/%m %H:%M", seen.t)),
						L["El juego no se equivoca: puede tener el addon modificado."],
					},
				})
			end
		end
	end

	-- Asistencias fuera del horario del evento.
	for eventID, attendees in pairs(g.attendance) do
		local e = g.events[eventID]
		if e and e.start then
			for member, t in pairs(attendees) do
				local vid = ns.AttendanceVoidID(eventID, member)
				local early = t < e.start + ns.ATTEND_FROM - ATTEND_SLACK
				local late = t > e.start + ns.ATTEND_UNTIL + ATTEND_SLACK
				if (early or late) and not ns.IsVoided(g, vid) then
					add({
						key = "attend|" .. vid, severity = "medium", member = member, t = t,
						text = (L["%s: asistencia a %s confirmada fuera de hora."]):format(ns.ShortName(member), e.title or "?"),
						detail = { (L["El evento empezaba el %s y la asistencia llegó el %s."]):format(date("%d/%m %H:%M", e.start), date("%d/%m %H:%M", t)) },
						items = { { id = vid, kind = "attend", member = member, label = (L["Asistencia de %s a %s"]):format(ns.ShortName(member), e.title or "?") } },
					})
				end
			end
		end
	end

	-- Encargos dados por entregados por el propio artesano, sin pasar por el intercambio.
	local selfMarked = {}
	for _, o in pairs(g.orders) do
		if o.status == "done" and not o.auto and o.by == o.crafter and now - (o.updated or o.t or 0) <= WINDOW
			and not ns.IsVoided(g, o.id) then
			selfMarked[o.crafter] = selfMarked[o.crafter] or {}
			table.insert(selfMarked[o.crafter], o)
		end
	end
	for crafter, orders in pairs(selfMarked) do
		if #orders >= SELF_MARKED_ALERT then
			local items = {}
			for _, o in ipairs(orders) do
				items[#items + 1] = { id = o.id, kind = "order", member = crafter,
					label = (L["Encargo de %s para %s"]):format(ns.RecipeName(o.recipe) or "?", ns.ShortName(o.requester) or "?") }
			end
			add({
				key = ("orders|%s|%d"):format(crafter, #orders), severity = "medium", member = crafter, t = orders[1].updated or orders[1].t,
				text = (L["%s ha dado por entregados %d encargos sin intercambio."]):format(ns.ShortName(crafter), #orders),
				detail = { L["Ni se vio el objeto en la ventana de intercambio ni lo confirmó quien lo pidió."] },
				items = items,
			})
		end
	end

	-- Ajustes grandes de otros oficiales.
	local me = ns.PlayerFullName()
	for id, a in pairs(g.adjustments) do
		if a.by ~= me and now - a.t <= WINDOW and not ns.IsVoided(g, id)
			and (math.abs(a.merits or 0) >= BIG_ADJUST or math.abs(a.rep or 0) >= BIG_ADJUST) then
			add({
				key = "adjust|" .. id, severity = "info", member = a.member, t = a.t,
				text = (L["%s ha ajustado a %s: %+d insignias, %+d reputación."]):format(ns.ShortName(a.by), ns.ShortName(a.member), a.merits or 0, a.rep or 0),
				detail = { (L["Motivo: %s"]):format(a.reason or "-") },
				items = { { id = id, kind = "adjust", member = a.member, label = (L["Ajuste de %s a %s"]):format(ns.ShortName(a.by), ns.ShortName(a.member)) } },
			})
		end
	end

	local order = { high = 1, medium = 2, info = 3 }
	table.sort(list, function(a, b)
		if order[a.severity] ~= order[b.severity] then return order[a.severity] < order[b.severity] end
		return (a.t or 0) > (b.t or 0)
	end)
	return list
end

-- "Visto": el aviso no vuelve a salir en este addon (si empeora, sale uno nuevo).
function ns.DismissAnomaly(key)
	local g = LG:GuildData()
	if not g then return end
	g.dismissed[key] = true
	LG:DataChanged()
end

---------------------------------------------------------------------------
-- Aviso al entrar e inspección de honor
---------------------------------------------------------------------------

function Integrity:OnEnable()
	self:ScheduleTimer("AnnounceAnomalies", 30)
	-- En Forever no existe RequestInspectHonorData (comprobado): el honor llega
	-- con la inspección normal, así que se lee también al terminar (INSPECT_READY).
	if NotifyInspect and GetInspectHonorData then
		ns.RegisterEvent(self, "INSPECT_HONOR_UPDATE", function() self:ReadInspectHonor() end)
		ns.RegisterEvent(self, "INSPECT_READY", function() self:ReadInspectHonor() end)
		self:ScheduleRepeatingTimer("InspectSomeone", INSPECT_EVERY)
	end
end

function Integrity:AnnounceAnomalies()
	if not LG:GuildData() or not ns.CanManageEvents(ns.PlayerFullName()) then return end
	local n = 0
	for _, a in ipairs(ns.Anomalies()) do
		if a.severity ~= "info" then n = n + 1 end
	end
	if n > 0 then LG:Print((L["Hay %d avisos de datos sospechosos en /gmk > Oficial."]):format(n)) end
end

local lastInspect = {}

function Integrity:InspectSomeone()
	local g = LG:GuildData()
	if not g or not IsInGroup() or InCombatLockdown() then return end
	-- Dentro de instancias los datos pueden ser secretos: solo en el mundo.
	if IsInInstance and select(1, IsInInstance()) then return end
	if InspectFrame and InspectFrame:IsShown() then return end
	local prefix = IsInRaid() and "raid" or "party"
	local count = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
	local now = GetTime()
	for i = 1, count do
		local unit = prefix .. i
		local name = ns.UnitFullName(unit)
		if name and g.members[name] and not UnitIsUnit(unit, "player") and now - (lastInspect[name] or -INSPECT_AGAIN) >= INSPECT_AGAIN
			and CanInspect(unit) and CheckInteractDistance(unit, 1) then
			lastInspect[name] = now
			self.inspecting = { name = name, at = now }
			pcall(NotifyInspect, unit)
			if RequestInspectHonorData then pcall(RequestInspectHonorData) end
			-- Se deja de escuchar a los 10 s (llegan INSPECT_READY y, si hay, INSPECT_HONOR_UPDATE).
			self:ScheduleTimer(function()
				-- Al final, con los datos ya llegados, se guarda el contador visto.
				if self.inspecting and self.inspecting.name == name then self:ReadInspectHonor(true) end
				self.inspecting = nil
				if not (InspectFrame and InspectFrame:IsShown()) and ClearInspectPlayer then pcall(ClearInspectPlayer) end
			end, 10)
			return
		end
	end
end

-- Se guarda lo último que llegue: el primer aviso puede venir antes que los datos de honor.
-- save: guardar y compartir el contador (solo al final de la inspección, nunca con el primer aviso).
function Integrity:ReadInspectHonor(save)
	local target = self.inspecting
	if not target or GetTime() - target.at > 15 then return end
	local values = { pcall(GetInspectHonorData) }
	local ok = table.remove(values, 1)
	local g = LG:GuildData()
	local m = g and g.members[target.name]
	LG.db.global.diag.inspectHonor = {
		t = date("%Y-%m-%d %H:%M:%S"),
		name = target.name,
		ok = ok,
		values = values,
		selfReported = m and m.pvp and { hk = m.pvp.hk, today = m.pvp.today } or nil,
	}
	-- Guardar y compartir el contador visto (si vienen los datos: hoy en [1], totales en [5]).
	if issecretvalue and (issecretvalue(values[1]) or issecretvalue(values[5])) then return end
	local hk = ok and tonumber(values[5])
	if save and g and hk and hk >= 0 then
		local rec = { member = target.name, hk = hk, today = tonumber(values[1]), t = ns.Now(), by = ns.PlayerFullName() }
		local old = g.honorSeen[target.name]
		if (not old or old.hk ~= hk or ns.Now() - (old.t or 0) > 3600) and ns.MergeHonorSeen(g, rec) then
			LG:Send("HONOR", rec)
			LG:DataChanged()
		end
	end
end
