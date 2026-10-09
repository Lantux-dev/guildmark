-- Reputación y insignias.
--
-- Los puntos no se envían: cada addon los calcula con las mismas reglas a partir
-- de los datos ya sincronizados (asistencias, mazmorras, kills, encargos), así
-- que todos llegan al mismo resultado y nadie puede inventarse un saldo.
-- Lo único que viaja son los ajustes de oficiales (ADJUST) y la lista manual
-- de hermandades objetivo (TARGET).
--
--   Reputación: acumulativa, nunca se gasta. Da el rango.
--   Insignias:    se gastan (subasta, cofre de hermandad, tienda...) y bajan un 5 % cada semana; lo que baja va al cofre.
local _, ns = ...
local L = ns.L
local LG = ns.LG

---------------------------------------------------------------------------
-- Reglas (valores iniciales del documento de diseño, ajustables)
---------------------------------------------------------------------------

-- Iconos de las insignias propias (bolsa) y del cofre de la hermandad. Cuando haya arte propio
-- (Media/insignia.tga), se cambia aquí.
ns.INSIGNIA_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
ns.CHEST_ICON = "Interface\\Icons\\INV_Box_02"

local POINTS = {
	event = {
		raid = { rep = 25, merits = 25 },
		dungeon = { rep = 10, merits = 10 },
		pvp = { rep = 10, merits = 10 },
		social = { rep = 5, merits = 5 },
	},
	dungeonFull = { rep = 10, merits = 10 },    -- grupo 5/5 de hermandad
	dungeonPartial = { rep = 5, merits = 5 },   -- grupo 4/5
	huntKill = { rep = 5, merits = 10 },        -- kill de una hermandad objetivo
	revengeBonus = { rep = 0, merits = 5 },
	order = { rep = 5, merits = 5 },            -- encargo entregado (para el artesano)
	aidHelp = { rep = 5, merits = 10 },         -- cada kill en la llamada de auxilio o el asalto de otra hermandad (tope por llamada)
	bgWin = { rep = 10, merits = 15 },          -- campo de batalla ganado (cuenta en el tope diario de JcJ)
	bgLoss = { rep = 5, merits = 5 },           -- perdido o empatado
	levelUp = { rep = 15, merits = 15 },        -- nivel 10, 20... durante «Sube como la espuma» (Chest.lua)
}

-- Topes de insignias por categoría. "week" se reinicia cada semana y "day" cada día.
local CAPS = {
	dungeons = { week = 100 },
	professions = { week = 100 },
	pvp = { day = 100 },
}

-- Misma víctima en el mismo día: 1.ª y 2.ª al 100 %, 3.ª al 50 %, a partir de la 4.ª nada.
local SAME_VICTIM_FACTOR = { 1, 1, 0.5 }

local MIN_RUN_WITNESSES = 2
local MERIT_DECAY = 0.95
local TARGET_AUTO_COUNT = 5
local TARGET_WINDOW = 7 * 86400

-- Las semanas empiezan el miércoles a las 04:00 UTC (reinicio semanal europeo).
local WEEK_ANCHOR = 1767758400 -- miércoles 7 de enero de 2026, 04:00 UTC
local WEEK = 7 * 86400
local DAY = 86400

-- Antigüedad: una semana más por rango, para subir como mucho un rango por semana.
ns.MERIT_RANKS = {
	{ key = "recruit", label = L["Recluta"], rep = 0, weeks = 0 },
	{ key = "member", label = L["Miembro"], rep = 100, weeks = 1 },
	{ key = "veteran", label = L["Veterano"], rep = 500, weeks = 2 },
	{ key = "elite", label = L["Élite"], rep = 1500, weeks = 3 },
}

local function weekIndex(t) return math.floor((t - WEEK_ANCHOR) / WEEK) end
local function dayIndex(t) return math.floor(t / DAY) end

function ns.WeekStart(t)
	return WEEK_ANCHOR + weekIndex(t or ns.Now()) * WEEK
end

---------------------------------------------------------------------------
-- Hermandades objetivo
---------------------------------------------------------------------------

-- Las que más nos han matado en los 7 días anteriores a "at", más la lista manual.
local function targetGuildsAt(g, at)
	local counts = {}
	for _, k in pairs(g.kills) do
		if k.kind == "death" and k.guild and not k.bg and k.t <= at and at - k.t <= TARGET_WINDOW then
			counts[k.guild] = (counts[k.guild] or 0) + 1
		end
	end
	local list = {}
	for guild, n in pairs(counts) do list[#list + 1] = { guild = guild, n = n } end
	table.sort(list, function(a, b) return a.n > b.n end)
	local targets = {}
	for i = 1, math.min(TARGET_AUTO_COUNT, #list) do targets[list[i].guild] = "auto" end
	for guild, t in pairs(g.targets) do
		if t.active then targets[guild] = "manual" end
	end
	return targets
end

function ns.TargetGuilds()
	local g = LG:GuildData()
	return g and targetGuildsAt(g, ns.Now()) or {}
end

---------------------------------------------------------------------------
-- Cálculo del libro de puntos
---------------------------------------------------------------------------

local function isGuildMember(g, name)
	return g.members[name] ~= nil or ns.roster[name] ~= nil
end

-- Reúne todos los hechos que dan o quitan puntos, sin aplicar topes ni decaimiento.
local function collectEntries(g)
	local entries = {}
	-- boost: clave de un proyecto del cofre (Chest.lua) que, activo en t, multiplica los puntos y el tope.
	local function add(t, member, cat, pts, reason, factor, boost)
		factor = factor or 1
		local capBoost
		local b, kind
		if boost and ns.BoostAt then b, kind = ns.BoostAt(g, boost, t) end
		if type(b) == "number" then
			factor, capBoost = factor * b, b
			reason = ("%s  x%s (%s)"):format(reason, (tostring(b):gsub("%.", ",")), kind.label)
		end
		entries[#entries + 1] = {
			t = t, member = member, cat = cat, reason = reason, capBoost = capBoost,
			rep = math.floor(pts.rep * factor + 0.5), merits = math.floor(pts.merits * factor + 0.5),
		}
	end

	-- Asistencia a eventos.
	for eventID, list in pairs(g.attendance) do
		local e = g.events[eventID]
		local pts = e and e.status ~= "cancelled" and POINTS.event[e.kind]
		if pts then
			for member in pairs(list) do
				if not ns.IsVoided(g, ns.AttendanceVoidID(eventID, member)) then
					add(e.start, member, "events", pts, (L["Evento: %s"]):format(e.title), nil, "gathering")
				end
			end
		end
	end

	-- Mazmorras: la mejor run por miembro, mazmorra y día, con al menos 2 testigos.
	local best = {}
	for _, r in pairs(g.runs) do
		local witnesses = 0
		for _ in pairs(r.witnesses or {}) do witnesses = witnesses + 1 end
		if witnesses >= MIN_RUN_WITNESSES and r.size == 5 and r.guildCount >= 4 then
			for _, member in ipairs(r.guildMembers or r.members or {}) do
				if isGuildMember(g, member) then
					local key = ("%s|%s|%d"):format(member, tostring(r.instanceID or r.instance), dayIndex(r.t))
					local b = best[key]
					if not b or r.guildCount > b.r.guildCount then best[key] = { r = r, member = member } end
				end
			end
		end
	end
	for _, b in pairs(best) do
		local pts = b.r.guildCount == 5 and POINTS.dungeonFull or POINTS.dungeonPartial
		add(b.r.t, b.member, "dungeons", pts, (L["%s (%d/5 de hermandad)"]):format(b.r.instance or "?", b.r.guildCount), nil, "dungeons")
	end

	-- Cazarrecompensas: kills honorables de hermandades objetivo.
	local kills = {}
	for _, k in pairs(g.kills) do
		if k.kind == "kill" and k.honorable and k.guild and k.killerName and not k.bg and not ns.IsVoided(g, k.id) then kills[#kills + 1] = k end
	end
	table.sort(kills, function(a, b) return a.t < b.t end)
	local sameVictim = {}
	for _, k in ipairs(kills) do
		if targetGuildsAt(g, k.t)[k.guild] then
			local key = ("%s|%s|%d"):format(k.killerName, k.victim or k.victimName or "?", dayIndex(k.t))
			sameVictim[key] = (sameVictim[key] or 0) + 1
			local factor = SAME_VICTIM_FACTOR[sameVictim[key]] or 0
			if factor > 0 then
				-- Botín de guerra (Bounty.lua): x1,5 cazando, también en el tope.
				local wager = ns.InWager and ns.InWager(k.killerName, k.t) and ns.WAGER.bonus or nil
				local suffix = wager and ("  " .. L["(botín de guerra)"]) or ""
				add(k.t, k.killerName, "pvp", POINTS.huntKill, (L["Caza: %s <%s>"]):format(ns.ShortName(k.victimName) or "?", k.guild) .. suffix, factor * (wager or 1), "hunt")
				if wager then entries[#entries].capBoost = (entries[#entries].capBoost or 1) * wager end
				if k.revenge then
					add(k.t, k.killerName, "pvp", POINTS.revengeBonus, L["Venganza"] .. suffix, wager, "hunt")
					if wager then entries[#entries].capBoost = (entries[#entries].capBoost or 1) * wager end
				end
			end
		end
	end

	-- Auxilio: cada kill ayudando a otra hermandad (tope por llamada; cuenta en el tope diario de JcJ).
	local myGuild = LG:GuildName()
	for _, h in pairs(g.aidHelps or {}) do
		if h.guild ~= myGuild and ns.AidHelpKills then
			for _, k in ipairs(ns.AidHelpKills(g, h)) do
				add(k.t, h.member, "pvp", POINTS.aidHelp, (L["Auxilio: <%s> en %s"]):format(h.guild or "?", h.zone or "?"), nil, "aid")
			end
		end
	end

	-- Campos de batalla: victoria o derrota (cuenta en el tope diario de JcJ).
	for id, m in pairs(g.bgMatches or {}) do
		if not ns.IsVoided(g, id) then
			local win = m.result == "win"
			add(m.t, m.member, "pvp", win and POINTS.bgWin or POINTS.bgLoss,
				(win and L["Victoria en %s"] or L["Derrota en %s"]):format(m.map or "?"), nil, "bg")
		end
	end

	-- Encargos entregados: puntos para el artesano.
	for _, o in pairs(g.orders) do
		if o.status == "done" and not ns.IsVoided(g, o.id) then
			add(o.updated or o.t, o.crafter, "professions", POINTS.order,
				(L["Encargo: %s para %s"]):format(ns.RecipeName(o.recipe) or "?", ns.ShortName(o.requester)), nil, "crafts")
		end
	end

	-- Niveles 10, 20, 30... alcanzados durante «Sube como la espuma» (los comparte cada miembro en su ficha).
	if ns.BoostAt then
		for name, m in pairs(g.members) do
			local seen = {}
			for _, lv in ipairs(type(m.levels) == "table" and m.levels or {}) do
				local level, t = type(lv) == "table" and tonumber(lv.level), type(lv) == "table" and tonumber(lv.t)
				if level and t and level % 10 == 0 and not seen[level] and ns.BoostAt(g, "levels", t) then
					seen[level] = true
					add(t, name, "levels", POINTS.levelUp, (L["Nivel %d (Sube como la espuma)"]):format(level))
				end
			end
		end
	end

	-- Subasta ganada: resta insignias al ganador y abona el 90 % al vendedor (las del banco, al cofre).
	for _, s in pairs(g.spends) do
		entries[#entries + 1] = {
			t = s.t, member = s.member, cat = "spend", rep = 0, merits = -s.merits,
			reason = (L["Subasta: %s"]):format(s.link or "?"),
		}
		if s.v == 2 and s.seller and not s.bank and s.seller ~= s.member then
			entries[#entries + 1] = {
				t = s.t, member = s.seller, cat = "sale", rep = 0, merits = math.floor(s.merits * (ns.SELLER_SHARE or 0.9)),
				reason = (L["Venta en subasta: %s"]):format(s.link or "?"),
			}
		end
	end

	-- Donaciones al cofre o a un proyecto (Chest.lua): restan lo que se tuviera.
	for id, d in pairs(g.donations or {}) do
		local p = d.project ~= "chest" and g.projects and g.projects[d.project]
		entries[#entries + 1] = {
			t = d.t, member = d.member, cat = "donate", rep = 0, merits = -d.merits, donation = id,
			reason = p and (L["Proyecto: %s"]):format(ns.ProjectTitle and ns.ProjectTitle(p) or "?") or L["Donación al cofre"],
		}
	end

	-- Botín de guerra y cabezas con precio (Bounty.lua): pérdidas al morir, cobros al
	-- matar y recompensas puestas a mano. Las cantidades dependen del saldo de ese
	-- momento, así que se resuelven al recorrer el libro (ns.Scores).
	if ns.InWager then
		local gap = ns.WAGER.levelGap
		for _, k in pairs(g.kills) do
			if not k.bg and not ns.IsVoided(g, k.id) then
				if k.kind == "death" and k.victimName and (k.killer or k.killerName) and ns.InWager(k.victimName, k.t) then
					local killerLevel = tonumber(k.level)
					local mine = g.members[k.victimName] or ns.roster[k.victimName]
					local myLevel = mine and tonumber(mine.level)
					-- Solo si su muerte le dio honor: un asesino de nivel desconocido o muy superior no cuenta.
					if killerLevel and killerLevel > 0 and myLevel and killerLevel - myLevel <= gap then
						entries[#entries + 1] = { t = k.t, member = k.victimName, special = "loss", rep = 0, merits = 0,
							guid = k.killer, name = k.killerName, guild = k.guild, death = k.id }
					end
				elseif k.kind == "kill" and k.killerName and (k.victim or k.victimName) then
					entries[#entries + 1] = { t = k.t, member = k.killerName, special = "claim", rep = 0, merits = 0,
						guid = k.victim, name = k.victimName, kill = k.id }
				end
			end
		end
		for id, b in pairs(g.bounties or {}) do
			if not ns.IsVoided(g, id) then
				entries[#entries + 1] = { t = b.t, member = b.member, special = "place", rep = 0, merits = 0, amount = b.merits,
					guid = b.guid, name = b.name, guild = b.guild, bounty = id }
			end
		end
	end

	-- Banco de la hermandad del juego (GuildBank.lua). El oro da reputación por lo neto de cada
	-- semana (metido menos sacado), 1 por cada oro y con tope; nunca insignias. Los objetos solo
	-- cuentan si los pide un pedido del banco: entonces cobran su parte de la recompensa (del cofre).
	if ns.BankRequestAllocations then
		local weeks = {}
		for _, d in pairs(g.bankLog or {}) do
			if d.kind == "money" or d.kind == "moneyOut" then
				local key = d.member .. "|" .. weekIndex(d.t)
				local w = weeks[key]
				if not w then
					w = { member = d.member, net = 0 }
					weeks[key] = w
				end
				w.net = w.net + (d.kind == "money" and d.amount or -d.amount)
				if d.kind == "money" then w.last = math.max(w.last or d.t, d.t) end
			end
		end
		for _, w in pairs(weeks) do
			local rep = math.min(ns.BANK_REP.weekCap, math.floor(math.max(0, w.net) / 10000) * ns.BANK_REP.perGold)
			if rep > 0 and w.last then
				add(w.last, w.member, "bank", { rep = rep, merits = 0 }, (L["Banco de la hermandad: %s esta semana"]):format(ns.MoneyText(w.net)))
			end
		end
		for _, al in ipairs(ns.BankRequestAllocations(g).allocs) do
			add(al.t, al.member, "bankRequest", { rep = al.insignias, merits = al.insignias },
				(L["Pedido del banco: %s x%d"]):format(al.req.link or "?", al.units))
		end
	end

	-- Tienda (Shop.lua): solo cuenta si en ese momento había insignias para pagarlo.
	for id, p in pairs(g.purchases or {}) do
		local item = ns.ShopItem and ns.ShopItem(p.item)
		if item and not ns.IsVoided(g, id) and ns.PurchaseCharged(g, p) then
			entries[#entries + 1] = { t = p.t, member = p.member, special = "buy", rep = 0, merits = 0, amount = item.price,
				item = p.item, own = item.kind ~= "fee", reason = (L["Tienda: %s"]):format(item.label) }
		end
	end

	-- Ajustes de oficiales (sin topes).
	for id, a in pairs(g.adjustments) do
		if not ns.IsVoided(g, id) then
			entries[#entries + 1] = {
				t = a.t, member = a.member, cat = "adjust", rep = a.rep or 0, merits = a.merits or 0,
				reason = (L["Ajuste de %s: %s"]):format(ns.ShortName(a.by), a.reason or "-"),
			}
		end
	end

	table.sort(entries, function(a, b) return a.t < b.t end)
	return entries
end

local cache
local donated = {} -- [idDonación] = insignias que de verdad se descontaron
local pots = {}    -- precios por cabezas (Bounty.lua), resueltos al recorrer el libro
local owned = {}   -- ["Nombre|clave"] = cuándo lo compró (Shop.lua)
local decayed = {} -- [semana] = insignias que bajaron esa semana (van al cofre, Chest.lua)

-- Aplica topes y decaimiento en orden cronológico y devuelve, por miembro:
-- { rep, merits, recent = { últimos movimientos }, capsUsed = { [cat] = insignias en el periodo actual } }
function ns.Scores()
	if cache then return cache end
	local g = LG:GuildData()
	local scores = {}
	donated, pots, owned, decayed = {}, {}, {}, {}
	if not g then return scores end

	local function score(member)
		local s = scores[member]
		if not s then
			s = { rep = 0, merits = 0, recent = {}, week = nil, periods = {} }
			scores[member] = s
		end
		return s
	end

	-- Bajada semanal: un 5 % por cada semana completa que pasa. Lo que baja va al cofre.
	local function decayTo(s, week)
		if s.week and week > s.week then
			local before = s.merits
			s.merits = math.floor(s.merits * MERIT_DECAY ^ (week - s.week))
			if before > s.merits then decayed[week] = (decayed[week] or 0) + (before - s.merits) end
		end
		s.week = week
	end

	local function note(s, t, merits, reason)
		table.insert(s.recent, 1, { t = t, rep = 0, merits = merits, reason = reason })
		if #s.recent > 15 then s.recent[16] = nil end
	end
	-- Botín de guerra: pérdida al morir (una al día), cobro al matar y recompensa puesta a mano.
	local lostDay = {}
	local BOUNTY_TTL = ns.WAGER and ns.WAGER.days * DAY or 0
	local function special(e, s)
		if e.special == "loss" then
			local day = e.member .. "|" .. dayIndex(e.t)
			if lostDay[day] then return end
			local amount = math.floor(math.max(0, s.merits - ns.WAGER.floor) * ns.WAGER.pct)
			if amount <= 0 then return end
			lostDay[day] = true
			s.merits = s.merits - amount
			note(s, e.t, -amount, (L["Botín de guerra: te mató %s"]):format(ns.ShortName(e.name) or "?"))
			pots[#pots + 1] = { t = e.t, amount = amount, victim = e.member, guid = e.guid, name = e.name, guild = e.guild, death = e.death }
		elseif e.special == "place" then
			local amount = math.min(s.merits, e.amount)
			if amount <= 0 then return end
			s.merits = s.merits - amount
			note(s, e.t, -amount, (L["Recompensa por %s"]):format(ns.ShortName(e.name) or "?"))
			pots[#pots + 1] = { t = e.t, amount = amount, placer = e.member, manual = true, guid = e.guid, name = e.name, guild = e.guild, bounty = e.bounty }
		elseif e.special == "buy" then
			if e.own and owned[e.member .. "|" .. e.item] then return end
			if s.merits < e.amount then return end
			s.merits = s.merits - e.amount
			note(s, e.t, -e.amount, e.reason)
			if e.own then owned[e.member .. "|" .. e.item] = e.t end
		elseif e.special == "claim" then
			for _, pot in ipairs(pots) do
				if not pot.claimedAt and e.t > pot.t and e.t <= pot.t + BOUNTY_TTL and ns.BountyMatches(pot, e.guid, e.name) then
					local back = pot.manual and 0 or math.floor(pot.amount / 2)
					local gets = pot.amount - back
					pot.claimedAt, pot.hunter, pot.hunterGets, pot.claimKill = e.t, e.member, gets, e.kill
					s.merits = s.merits + gets
					note(s, e.t, gets, (L["Cobras la cabeza de %s"]):format(ns.ShortName(pot.name) or "?"))
					if back > 0 then
						local v = score(pot.victim)
						decayTo(v, weekIndex(e.t))
						v.merits = v.merits + back
						note(v, e.t, back, (L["Recuperas la mitad: %s ha caído"]):format(ns.ShortName(pot.name) or "?"))
					end
				end
			end
		end
	end

	for _, e in ipairs(collectEntries(g)) do
		local s = score(e.member)
		decayTo(s, weekIndex(e.t))
		if e.special then
			special(e, s)
		else
		local allowed = 1
		local cap = CAPS[e.cat]
		if cap and e.merits > 0 then
			local limit = math.floor((cap.week or cap.day) * (e.capBoost or 1))
			local period = cap.week and ("w" .. weekIndex(e.t)) or ("d" .. dayIndex(e.t))
			local key = e.cat .. period
			local used = s.periods[key] or 0
			if used >= limit then
				allowed = 0
			elseif used + e.merits > limit then
				allowed = (limit - used) / e.merits
			end
			s.periods[key] = used + math.floor(e.merits * allowed + 0.5)
		end
		if allowed > 0 then
			local rep = math.floor(e.rep * allowed + 0.5)
			local merits = math.floor(e.merits * allowed + 0.5)
			s.rep = s.rep + rep
			local had = s.merits
			s.merits = math.max(0, s.merits + merits)
			if e.donation then
				merits = s.merits - had
				donated[e.donation] = -merits
			end
			table.insert(s.recent, 1, { t = e.t, rep = rep, merits = merits, reason = e.reason, capped = allowed < 1 })
			if #s.recent > 15 then s.recent[16] = nil end
		end
		end
	end

	-- Decaimiento hasta hoy y uso de topes en el periodo actual (con el tope ampliado si hay un proyecto activo).
	local now = ns.Now()
	local capNow = {}
	if ns.BoostAt then
		local function f(kind) local b = ns.BoostAt(g, kind, now) return type(b) == "number" and b or 1 end
		capNow.dungeons, capNow.professions, capNow.pvp = f("dungeons"), f("crafts"), math.max(f("hunt"), f("bg"), f("aid"))
	end
	for _, s in pairs(scores) do
		decayTo(s, weekIndex(now))
		s.capsUsed = {}
		for cat, cap in pairs(CAPS) do
			local period = cap.week and ("w" .. weekIndex(now)) or ("d" .. dayIndex(now))
			s.capsUsed[cat] = { used = s.periods[cat .. period] or 0, limit = math.floor((cap.week or cap.day) * (capNow[cat] or 1)), period = cap.week and "week" or "day" }
		end
		s.periods = nil
	end
	cache = scores
	return scores
end

-- Precios por cabezas, ya resueltos: { t, amount, victim | placer, manual, guid, name, guild,
-- claimedAt, hunter, hunterGets }. Los no cobrados caducan a los 7 días (van al cofre).
-- Lo que bajó cada semana, para el cofre: { { t = inicio de la semana, amount }, ... }.
function ns.DecayedToChest()
	ns.Scores()
	local list = {}
	for week, amount in pairs(decayed) do list[#list + 1] = { t = WEEK_ANCHOR + week * WEEK, amount = amount } end
	return list
end

function ns.ShopOwned()
	ns.Scores()
	return owned
end

function ns.BountyPots()
	ns.Scores()
	return pots
end

-- Insignias que se descontaron de verdad en cada donación (nunca más de lo que había).
function ns.DonationsApplied()
	ns.Scores()
	return donated
end

-- Nombres de los rangos del addon: los de siempre o los que ponga el maestro de hermandad.
for _, r in ipairs(ns.MERIT_RANKS) do r.defaultLabel = r.label end
function ns.ApplyRankNames()
	for _, r in ipairs(ns.MERIT_RANKS) do
		local custom = ns.GuildSetting and ns.GuildSetting("rankName:" .. r.key)
		r.label = type(custom) == "string" and custom ~= "" and custom or r.defaultLabel
	end
end

-- Rango que corresponde por reputación y antigüedad, y el siguiente.
function ns.MeritRank(name)
	ns.ApplyRankNames()
	local g = LG:GuildData()
	local s = ns.Scores()[name] or { rep = 0 }
	local m = g and g.members[name]
	local weeks = m and m.joined and math.floor((ns.Now() - m.joined) / WEEK) or 0
	-- En modo prueba no se exige antigüedad, para poder probar los ascensos.
	local ignoreWeeks = LG:InTestMode()
	local current, nextRank = ns.MERIT_RANKS[1], nil
	for i, r in ipairs(ns.MERIT_RANKS) do
		if s.rep >= r.rep and (ignoreWeeks or weeks >= r.weeks) then
			current = r
			nextRank = ns.MERIT_RANKS[i + 1]
		end
	end
	return current, nextRank, s.rep, weeks
end

---------------------------------------------------------------------------
-- Ajustes y objetivos manuales (solo oficiales)
---------------------------------------------------------------------------

function ns.MergeAdjustment(g, rec, sender)
	if type(rec.id) ~= "string" or type(rec.member) ~= "string" or g.adjustments[rec.id] then return false end
	if sender and rec.by ~= sender then return false end
	if not ns.Can("adjust", rec.by) then return false end
	g.adjustments[rec.id] = rec
	return true
end

function ns.MergeTarget(g, rec, sender)
	if type(rec.guild) ~= "string" then return false end
	if sender and rec.by ~= sender then return false end
	if not ns.Can("adjust", rec.by) then return false end
	local old = g.targets[rec.guild]
	if old and (old.t or 0) >= (rec.t or 0) then return false end
	g.targets[rec.guild] = { active = rec.active, by = rec.by, t = rec.t }
	return true
end

local function handler(merge)
	return function(sender, rec)
		local g = LG:GuildData()
		if g and merge(g, rec, sender) then LG:DataChanged() end
	end
end
ns.handlers.ADJUST = handler(ns.MergeAdjustment)
ns.handlers.TARGET = handler(ns.MergeTarget)

function ns.AdjustPoints(member, merits, rep, reason)
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	if not g or not ns.Can("adjust", me) then
		LG:Print(L["Solo los oficiales pueden ajustar puntos."])
		return
	end
	local now = ns.Now()
	local rec = { id = ("%s:%d:%d"):format(me, now, math.random(1000, 9999)), t = now, member = member,
		merits = merits, rep = rep, reason = reason, by = me }
	ns.MergeAdjustment(g, rec)
	LG:Send("ADJUST", rec)
	LG:DataChanged()
	LG:Print((L["Ajuste aplicado a %s: %+d insignias, %+d reputación (%s)."]):format(member, merits, rep, reason or "-"))
end

function ns.ToggleTarget(guild)
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	if not g or not ns.Can("adjust", me) then
		LG:Print(L["Solo los oficiales pueden cambiar los objetivos."])
		return
	end
	local active = not (g.targets[guild] and g.targets[guild].active)
	-- Se puede quitar, pero no poner: no es una hermandad sino jugadores sueltos.
	if active and guild == ns.NO_GUILD then
		LG:Print(L["Los jugadores sin hermandad no pueden ser objetivo."])
		return
	end
	local rec = { guild = guild, active = active, by = me, t = ns.Now() }
	ns.MergeTarget(g, rec)
	LG:Send("TARGET", rec)
	LG:DataChanged()
	LG:Print((active and L["<%s> añadida a los objetivos."] or L["<%s> quitada de los objetivos."]):format(guild))
end

-- LG:DataChanged la llama antes de avisar a la ventana: el cálculo se rehace al pedirlo.
function ns.InvalidateScores()
	cache = nil
end
