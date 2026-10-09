-- Cofre de hermandad y proyectos.
--
-- El cofre es de toda la hermandad: se llena con donaciones de los miembros y
-- con una parte de cada subasta, y los oficiales lo invierten en proyectos.
-- Los miembros también pueden aportar directamente a un proyecto.
--
-- Los proyectos son de un catálogo fijo (PROJECT_KINDS): cada uno con su coste,
-- su duración y su efecto, que el addon aplica solo. Un proyecto se completa al
-- reunir su coste y empieza cuando un oficial lo activa (así se puede guardar
-- para el fin de semana). Solo uno de cada tipo a la vez.
--
-- Como el resto de puntos, el saldo no se envía: cada addon lo calcula a partir
-- de los registros sincronizados.
--   PROJECT    proyecto (lo crean, activan y cancelan oficiales; sube "rev")
--   DONATE     donación de un miembro al cofre o a un proyecto (solo la suya)
--   CHESTMOVE  un oficial pasa insignias del cofre a un proyecto
-- Una donación nunca descuenta más de lo que el miembro tenía en ese momento, y
-- un movimiento nunca saca más de lo que había en el cofre: lo que no llega no cuenta.
--
-- Los efectos sobre las insignias (Merits.lua) dependen solo de cuándo se activó
-- cada proyecto, que es un dato del registro: así el cálculo de insignias no
-- depende del cofre, que a su vez depende de las insignias.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local AUCTION_SHARE = 0.10   -- parte de cada subasta que va al cofre (no se le cobra al ganador)
local MAX_GOAL = 100000
local LOG_SIZE = 15
local CHEST = "chest"
local DAY = 86400

-- factor: multiplica las insignias y la reputación de lo que afecta (y su tope).
ns.PROJECT_KINDS = {
	{ key = "standard", label = L["Estandarte de hermandad"], icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01", goal = 300, days = 30,
		desc = L["El emblema de la hermandad aparece junto al retrato de todos los miembros."] },
	{ key = "dungeons", label = L["Mazmorras por doquier"], icon = "Interface\\Icons\\INV_Misc_Key_03", goal = 400, days = 3, factor = 1.5,
		desc = L["Mazmorras con la hermandad: x1,5 insignias y reputación, y su tope semanal también."] },
	{ key = "levels", label = L["Sube como la espuma"], icon = "Interface\\Icons\\Spell_Holy_InnerFire", goal = 300, days = 7,
		desc = L["Cada nivel 10, 20, 30... que alcance un miembro: +15 insignias y +15 de reputación."] },
	{ key = "bg", label = L["Llamamiento a las armas: Campos de batalla"], icon = "Interface\\Icons\\INV_BannerPVP_01", goal = 400, days = 3, factor = 2,
		desc = L["Victorias y derrotas en campos de batalla: x2 insignias y reputación, y su tope también."] },
	{ key = "hunt", label = L["Temporada de caza"], icon = "Interface\\Icons\\Ability_Hunter_SniperShot", goal = 400, days = 3, factor = 2,
		desc = L["Bajas a hermandades objetivo y venganzas: x2 insignias y reputación, y su tope también."] },
	{ key = "crafts", label = L["Feria de artesanos"], icon = "Interface\\Icons\\Trade_BlackSmithing", goal = 300, days = 7, factor = 2,
		desc = L["Encargos entregados: x2 insignias y reputación, y su tope semanal también."] },
	{ key = "gathering", label = L["Gran reunión"], icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02", goal = 400, days = 7, factor = 1.5,
		desc = L["Asistencia a eventos de la hermandad: x1,5 insignias y reputación."] },
	{ key = "aid", label = L["Toque de corneta"], icon = "Interface\\Icons\\Ability_Warrior_BattleShout", goal = 300, days = 3, factor = 2,
		desc = L["Ayudar en auxilios y asaltos de otras hermandades: x2 insignias y reputación, y el tope por llamada también."] },
}

local KINDS = {}
for _, k in ipairs(ns.PROJECT_KINDS) do KINDS[k.key] = k end

function ns.ProjectKind(key)
	return KINDS[key]
end

-- Fin de un proyecto activado.
local function endsAt(p)
	local kind = KINDS[p.kind]
	return p.activatedAt and kind and (p.activatedAt + kind.days * DAY) or nil
end
ns.ProjectEnds = endsAt

-- Efecto de un tipo de proyecto en el momento t: factor (o true) y el proyecto, o nil.
-- Solo mira los registros, nunca el cofre (ver arriba).
function ns.BoostAt(g, kindKey, t)
	local kind = KINDS[kindKey]
	if not g or not kind then return nil end
	for _, p in pairs(g.projects or {}) do
		if p.kind == kindKey and p.activatedAt and p.status ~= "cancelled" and t >= p.activatedAt and t < endsAt(p) then
			return kind.factor or true, kind
		end
	end
	return nil
end

-- Tipos activos ahora: { [clave] = hasta cuándo }.
function ns.ActiveProjects()
	local active = {}
	local g = LG:GuildData()
	local now = ns.Now()
	for _, p in pairs(g and g.projects or {}) do
		local ends = endsAt(p)
		if ends and p.status ~= "cancelled" and now >= p.activatedAt and now < ends and ends > (active[p.kind] or 0) then
			active[p.kind] = ends
		end
	end
	return active
end

---------------------------------------------------------------------------
-- Fusión de datos recibidos
---------------------------------------------------------------------------

local function validAmount(n)
	return type(n) == "number" and n >= 1 and n <= MAX_GOAL and n == math.floor(n)
end

function ns.MergeProject(g, rec, sender)
	if type(rec.id) ~= "string" or type(rec.rev) ~= "number" or not KINDS[rec.kind] then return false end
	if not validAmount(rec.goal) then return false end
	if rec.activatedAt ~= nil and type(rec.activatedAt) ~= "number" then return false end
	if sender and rec.by ~= sender then return false end
	if not ns.Can("projects", rec.by) then return false end
	local old = g.projects[rec.id]
	if old then
		if old.rev >= rec.rev then return false end
		-- El tipo, el coste, el creador y la activación no cambian una vez puestos.
		if old.goal ~= rec.goal or old.kind ~= rec.kind or old.creator ~= rec.creator then return false end
		if old.activatedAt and old.activatedAt ~= rec.activatedAt then return false end
	end
	g.projects[rec.id] = rec
	return true, old
end

function ns.MergeDonation(g, rec, sender)
	if type(rec.id) ~= "string" or type(rec.member) ~= "string" or type(rec.t) ~= "number" then return false end
	if not validAmount(rec.merits) or type(rec.project) ~= "string" then return false end
	if g.donations[rec.id] then return false end
	if sender and rec.member ~= sender then return false end
	g.donations[rec.id] = rec
	return true
end

function ns.MergeChestMove(g, rec, sender)
	if type(rec.id) ~= "string" or type(rec.project) ~= "string" or type(rec.t) ~= "number" then return false end
	if not validAmount(rec.merits) then return false end
	if g.chestMoves[rec.id] then return false end
	if sender and rec.by ~= sender then return false end
	if not ns.Can("projects", rec.by) then return false end
	g.chestMoves[rec.id] = rec
	return true
end

---------------------------------------------------------------------------
-- Cálculo del cofre
---------------------------------------------------------------------------

local cache, cacheScores

-- { balance, auctions, donated, spent, projects = { [id] = { funded, doneAt } }, log = { movimientos recientes } }
function ns.ChestState()
	local scores = ns.Scores()
	if cache and cacheScores == scores then return cache end
	local g = LG:GuildData()
	local state = { balance = 0, auctions = 0, donated = 0, spent = 0, projects = {}, log = {} }
	cache, cacheScores = state, scores
	if not g then return state end

	local applied = ns.DonationsApplied()
	local moves = {}
	for _, s in pairs(g.spends) do
		local share
		if s.v == 2 and s.bank then share = s.merits or 0
		elseif s.v == 2 and s.seller and s.seller ~= s.member then share = (s.merits or 0) - math.floor((s.merits or 0) * (ns.SELLER_SHARE or 0.9))
		else share = math.floor((s.merits or 0) * AUCTION_SHARE) end
		if share > 0 then moves[#moves + 1] = { t = s.t, kind = "auction", merits = share, member = s.member } end
	end
	for id, d in pairs(g.donations) do
		local amount = applied[id] or 0
		if amount > 0 then moves[#moves + 1] = { t = d.t, kind = "donate", merits = amount, member = d.member, project = d.project, id = id } end
	end
	-- Recompensas de los pedidos del banco (GuildBank.lua): salen del cofre.
	for i, al in ipairs(ns.BankRequestAllocations and ns.BankRequestAllocations(g).allocs or {}) do
		if al.insignias > 0 then
			moves[#moves + 1] = { t = al.t, kind = "request", merits = al.insignias, member = al.member, id = "req:" .. al.req.id .. ":" .. al.member }
		end
	end
	-- La bajada semanal de las insignias de todos (Merits.lua).
	for _, d in ipairs(ns.DecayedToChest and ns.DecayedToChest() or {}) do
		moves[#moves + 1] = { t = d.t, kind = "decay", merits = d.amount, id = "decay:" .. d.t }
	end
	-- Precios por cabezas que nadie cobró en 7 días (Bounty.lua).
	local now = ns.Now()
	for _, pot in ipairs(ns.BountyPots and ns.BountyPots() or {}) do
		local expires = pot.t + (ns.WAGER and ns.WAGER.days or 7) * DAY
		if not pot.claimedAt and expires <= now and pot.amount > 0 then
			moves[#moves + 1] = { t = expires, kind = "bounty", merits = pot.amount, member = pot.victim or pot.placer, id = "b:" .. pot.t .. ":" .. (pot.victim or pot.placer or "") }
		end
	end
	for id, m in pairs(g.chestMoves) do
		moves[#moves + 1] = { t = m.t, kind = "move", merits = m.merits, member = m.by, project = m.project, id = id }
	end
	-- Mismo orden en todos los addons: por momento y, si empatan, por id.
	table.sort(moves, function(a, b)
		if a.t ~= b.t then return a.t < b.t end
		return (a.id or a.kind) < (b.id or b.kind)
	end)

	local function project(id)
		local p = g.projects[id]
		if not p or not KINDS[p.kind] then return nil end -- los de un formato antiguo no cuentan
		local st = state.projects[id]
		if not st then
			st = { funded = 0 }
			state.projects[id] = st
		end
		return p, st
	end
	-- ¿Admite aportaciones el proyecto en el momento t? (abierto y sin completar)
	local function accepts(p, st, t)
		if p.status == "cancelled" and (p.cancelledAt or 0) <= t then return false end
		return not st.doneAt
	end

	for _, m in ipairs(moves) do
		local entry = { t = m.t, kind = m.kind, member = m.member, merits = m.merits, project = m.project }
		if m.kind == "auction" or m.kind == "bounty" or m.kind == "decay" then
			state.balance = state.balance + m.merits
			if m.kind == "auction" then state.auctions = state.auctions + m.merits
			elseif m.kind == "decay" then state.decay = (state.decay or 0) + m.merits
			else state.bounties = (state.bounties or 0) + m.merits end
		elseif m.kind == "donate" then
			state.donated = state.donated + m.merits
			local p, st = project(m.project)
			local toProject = 0
			if p and accepts(p, st, m.t) then toProject = math.min(m.merits, p.goal - st.funded) end
			if toProject > 0 then
				st.funded = st.funded + toProject
				if st.funded >= p.goal then st.doneAt = m.t end
			end
			-- Lo que no cabe en el proyecto (o una donación al cofre) se queda en el cofre.
			state.balance = state.balance + (m.merits - toProject)
			if toProject < m.merits and m.project ~= CHEST then entry.overflow = m.merits - toProject end
		elseif m.kind == "request" then
			state.balance = state.balance - m.merits
			state.requests = (state.requests or 0) + m.merits
			entry.merits = m.merits
		else
			local p, st = project(m.project)
			local amount = 0
			if p and accepts(p, st, m.t) then amount = math.min(m.merits, state.balance, p.goal - st.funded) end
			entry.merits = amount
			if amount > 0 then
				state.balance = state.balance - amount
				state.spent = state.spent + amount
				st.funded = st.funded + amount
				if st.funded >= p.goal then st.doneAt = m.t end
			end
		end
		if entry.merits > 0 then table.insert(state.log, 1, entry) end
	end
	-- Un proyecto cancelado devuelve al cofre lo que tenía.
	for id, p in pairs(g.projects) do
		local st = state.projects[id]
		if p.status == "cancelled" and st and not st.doneAt and st.funded > 0 then
			state.balance = state.balance + st.funded
			st.refunded = st.funded
		end
	end
	for i = #state.log, LOG_SIZE + 1, -1 do state.log[i] = nil end
	return state
end

-- Lo que ha donado cada miembro (al cofre y a proyectos): { { name, total, month } }, de más a menos.
function ns.ChestDonors()
	local g = LG:GuildData()
	local applied = ns.DonationsApplied()
	local monthStart = ns.Now() - 30 * DAY
	local by, list = {}, {}
	for id, d in pairs(g and g.donations or {}) do
		local amount = applied[id] or 0
		if amount > 0 then
			local e = by[d.member]
			if not e then
				e = { name = d.member, total = 0, month = 0 }
				by[d.member] = e
				list[#list + 1] = e
			end
			e.total = e.total + amount
			if d.t >= monthStart then e.month = e.month + amount end
		end
	end
	table.sort(list, function(a, b) if a.total ~= b.total then return a.total > b.total end return a.name < b.name end)
	return list
end

-- Fase de un proyecto: "open" (reuniendo), "ready" (completo, sin activar),
-- "active", "ended" o "cancelled".
function ns.ProjectPhase(p, st)
	st = st or ns.ChestState().projects[p.id] or { funded = 0 }
	if p.activatedAt then
		return ns.Now() < endsAt(p) and "active" or "ended"
	end
	if st.doneAt then return "ready" end
	if p.status == "cancelled" then return "cancelled" end
	return "open"
end

-- Proyectos por fase: { open, ready, active, ended, cancelled }, cada uno { p, funded, doneAt }.
function ns.ProjectLists()
	local lists = { open = {}, ready = {}, active = {}, ended = {}, cancelled = {} }
	local g = LG:GuildData()
	if not g then return lists end
	local state = ns.ChestState()
	for id, p in pairs(g.projects) do
		if KINDS[p.kind] then
			local st = state.projects[id] or { funded = 0 }
			local phase = ns.ProjectPhase(p, st)
			table.insert(lists[phase], { p = p, funded = st.funded, doneAt = st.doneAt, phase = phase })
		end
	end
	table.sort(lists.open, function(a, b)
		local ra, rb = a.funded / a.p.goal, b.funded / b.p.goal
		if ra ~= rb then return ra > rb end
		return (a.p.created or 0) < (b.p.created or 0)
	end)
	table.sort(lists.ready, function(a, b) return a.doneAt < b.doneAt end)
	table.sort(lists.active, function(a, b) return endsAt(a.p) < endsAt(b.p) end)
	table.sort(lists.ended, function(a, b) return a.p.activatedAt > b.p.activatedAt end)
	table.sort(lists.cancelled, function(a, b) return (a.p.cancelledAt or 0) > (b.p.cancelledAt or 0) end)
	return lists
end

-- Proyecto de ese tipo en curso (reuniendo, listo o activo), o nil: solo uno a la vez.
function ns.ProjectOfKind(kindKey)
	local lists = ns.ProjectLists()
	for _, phase in ipairs({ "open", "ready", "active" }) do
		for _, item in ipairs(lists[phase]) do
			if item.p.kind == kindKey then return item end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Avisos
---------------------------------------------------------------------------

local function doneSet()
	local set = {}
	for id, st in pairs(ns.ChestState().projects) do
		if st.doneAt then set[id] = true end
	end
	return set
end

local function title(p)
	local kind = KINDS[p.kind]
	return kind and kind.label or "?"
end
ns.ProjectTitle = title

-- Avisa en el chat de los proyectos que se acaban de completar o activar. Si lo ha hecho
-- uno mismo (mine), también en el chat de hermandad.
local function announce(beforeDone, old, rec, mine)
	local g = LG:GuildData()
	for id in pairs(doneSet()) do
		local p = g and g.projects[id]
		if p and not beforeDone[id] and not p.activatedAt then
			LG:Print((L["¡Proyecto completado: %s! Un oficial puede activarlo en Hermandad › Cofre."]):format(title(p)))
			if mine then ns.GuildAnnounce((L["Proyecto completado: %s. ¡Gracias a todos los que habéis aportado!"]):format(title(p))) end
		end
	end
	if rec and rec.activatedAt and not (old and old.activatedAt) then
		LG:Print((L["¡%s activado durante %s!"]):format(title(rec), ns.FormatDuration(endsAt(rec) - ns.Now())))
		if mine then ns.GuildAnnounce((L["%s activado durante %s: %s"]):format(title(rec), ns.FormatDuration(endsAt(rec) - ns.Now()), KINDS[rec.kind].desc)) end
	end
end

local function merged(merge)
	return function(sender, rec)
		local g = LG:GuildData()
		if not g then return end
		local before = doneSet()
		local changed, old = merge(g, rec, sender)
		if changed then
			LG:DataChanged()
			announce(before, old, rec)
		end
	end
end
ns.handlers.PROJECT = merged(ns.MergeProject)
ns.handlers.DONATE = merged(ns.MergeDonation)
ns.handlers.CHESTMOVE = merged(ns.MergeChestMove)

---------------------------------------------------------------------------
-- Acciones
---------------------------------------------------------------------------

local function newID(me)
	return ("%s:%d:%d"):format(me, ns.Now(), math.random(1000, 9999))
end

local function publish(kind, merge, rec)
	local g = LG:GuildData()
	local before = doneSet()
	local _, old = merge(g, rec)
	LG:Send(kind, rec)
	LG:DataChanged()
	announce(before, old, kind == "PROJECT" and rec or nil, true)
end

local function copy(p)
	local rec = {}
	for k, v in pairs(p) do rec[k] = v end
	return rec
end

function ns.CreateProject(kindKey)
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	local kind = KINDS[kindKey]
	if not g then return false, L["No estás en una hermandad."] end
	if not ns.Can("projects", me) then return false, L["Solo los oficiales pueden crear proyectos."] end
	if not kind then return false end
	if ns.ProjectOfKind(kindKey) then return false, L["Ya hay un proyecto de ese tipo en curso."] end
	local now = ns.Now()
	local rec = { id = newID(me), rev = 1, kind = kind.key, goal = kind.goal, status = "open", created = now, creator = me, by = me }
	publish("PROJECT", ns.MergeProject, rec)
	LG:Print((L["Proyecto abierto: %s (%d insignias)."]):format(kind.label, kind.goal))
	ns.GuildAnnounce((L["Nuevo proyecto de la hermandad: %s (%d insignias). Aporta en /gmk > Hermandad > Cofre."]):format(kind.label, kind.goal))
	return true
end

function ns.ActivateProject(id)
	local g = LG:GuildData()
	local p = g and g.projects[id]
	local me = ns.PlayerFullName()
	if not p or not ns.Can("projects", me) or ns.ProjectPhase(p) ~= "ready" then return false end
	local rec = copy(p)
	rec.rev, rec.by, rec.activatedAt = p.rev + 1, me, ns.Now()
	publish("PROJECT", ns.MergeProject, rec)
	return true
end

function ns.CancelProject(id)
	local g = LG:GuildData()
	local p = g and g.projects[id]
	local me = ns.PlayerFullName()
	if not p or not ns.Can("projects", me) or ns.ProjectPhase(p) ~= "open" then return false end
	local rec = copy(p)
	rec.rev, rec.by, rec.status, rec.cancelledAt = p.rev + 1, me, "cancelled", ns.Now()
	publish("PROJECT", ns.MergeProject, rec)
	return true
end

-- Insignias que puedo donar: las mías menos las reservadas en subastas.
function ns.DonatableInsignias()
	return ns.AvailableInsignias(nil)
end

-- Lo que le falta a un proyecto abierto (nil si no admite más).
function ns.ProjectRemaining(id)
	local g = LG:GuildData()
	local p = g and g.projects[id]
	if not p or ns.ProjectPhase(p) ~= "open" then return nil end
	local st = ns.ChestState().projects[id] or { funded = 0 }
	return p.goal - st.funded
end

-- Donar al cofre (projectID nil) o a un proyecto.
function ns.Donate(amount, projectID)
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	if not g then return false, L["No estás en una hermandad."] end
	amount = math.floor(tonumber(amount) or 0)
	if amount < 1 then return false, L["Pon cuántas insignias."] end
	local free = ns.DonatableInsignias()
	if amount > free then return false, (L["Solo tienes %d insignias libres."]):format(free) end
	if projectID then
		local remaining = ns.ProjectRemaining(projectID)
		if not remaining then return false, L["Ese proyecto ya no admite aportaciones."] end
		if amount > remaining then return false, (L["Al proyecto solo le faltan %d insignias."]):format(remaining) end
	end
	local rec = { id = newID(me), member = me, merits = amount, project = projectID or CHEST, t = ns.Now() }
	publish("DONATE", ns.MergeDonation, rec)
	return true
end

-- Un oficial pasa insignias del cofre a un proyecto.
function ns.FundProject(id, amount)
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	if not g or not ns.Can("projects", me) then return false, L["Solo los oficiales pueden usar el cofre."] end
	amount = math.floor(tonumber(amount) or 0)
	if amount < 1 then return false, L["Pon cuántas insignias."] end
	local remaining = ns.ProjectRemaining(id)
	if not remaining then return false, L["Ese proyecto ya no admite aportaciones."] end
	local balance = ns.ChestState().balance - (ns.BankRequestsReserved and ns.BankRequestsReserved() or 0)
	if amount > balance then return false, (L["En el cofre solo hay %d insignias."]):format(math.max(0, balance)) end
	if amount > remaining then return false, (L["Al proyecto solo le faltan %d insignias."]):format(remaining) end
	local rec = { id = newID(me), project = id, merits = amount, by = me, t = ns.Now() }
	publish("CHESTMOVE", ns.MergeChestMove, rec)
	return true
end
