-- Cabezas con precio y botín de guerra.
--
-- Botín de guerra (opcional, cada jugador decide): mientras lo tienes activado
-- ganas x1,5 insignias cazando, pero si un enemigo te mata (fuera de campos de
-- batalla, con una muerte que le dé honor) pierdes un 10 % de tus insignias por
-- encima de 50, como mucho una vez al día. Lo que pierdes no desaparece: es el
-- precio por la cabeza de tu asesino durante 7 días. Si tú o cualquiera de la
-- hermandad lo matáis, la mitad vuelve a ti y la otra mitad es para quien lo
-- mató. Si nadie lo caza, va al cofre de hermandad.
--
-- Además cualquiera puede poner insignias suyas por la cabeza de un enemigo
-- (BOUNTY): las cobra entero quien lo mate; si caduca, van al cofre.
--
-- Como el resto de puntos, todo se calcula (Merits.lua) con los datos ya
-- sincronizados: las muertes, las kills, los periodos de botín de guerra de cada
-- miembro (en su registro) y las recompensas puestas.
local _, ns = ...
local L = ns.L
local LG = ns.LG

ns.WAGER = {
	pct = 0.10,          -- parte de las insignias que se pierde
	floor = 50,          -- las primeras 50 no se pierden nunca
	bonus = 1.5,         -- caza con botín de guerra activado
	days = 7,            -- lo que dura un precio
	levelGap = 7,        -- el asesino no puede sacarte más niveles (si no, la muerte no le da honor)
	minOn = 86400,       -- una vez activado, al menos 24 h
	maxPeriods = 10,
}
local MAX_BOUNTY = 1000

---------------------------------------------------------------------------
-- Periodos de botín de guerra
---------------------------------------------------------------------------

local function periodsOf(name)
	local g = LG:GuildData()
	local raw
	if name == ns.PlayerFullName() then raw = LG.db.char.wager and LG.db.char.wager.periods
	else raw = g and g.members[name] and g.members[name].wager end
	return type(raw) == "table" and raw or {}
end

-- ¿Tenía el botín de guerra activado en el momento t?
function ns.InWager(name, t)
	for _, p in ipairs(periodsOf(name)) do
		if type(p) == "table" and type(p[1]) == "number" and t >= p[1] and (type(p[2]) ~= "number" or t < p[2]) then return true end
	end
	return false
end

-- Estado propio: activo, desde cuándo y si ya se puede desactivar.
function ns.WagerState()
	local periods = LG.db.char.wager and LG.db.char.wager.periods or {}
	local last = periods[#periods]
	local on = last ~= nil and last[2] == nil
	local canOff = on and ns.Now() - last[1] >= ns.WAGER.minOn
	return { on = on, since = on and last[1] or nil, canOff = canOff, offAt = on and (last[1] + ns.WAGER.minOn) or nil }
end

function ns.SetWager(on)
	LG.db.char.wager = LG.db.char.wager or {}
	local w = LG.db.char.wager
	w.periods = w.periods or {}
	local state = ns.WagerState()
	if on and not state.on then
		w.periods[#w.periods + 1] = { ns.Now() }
		while #w.periods > ns.WAGER.maxPeriods do table.remove(w.periods, 1) end
		LG:Print(L["Botín de guerra activado: x1,5 insignias cazando, pero si te matan pierdes un 10 % (una vez al día) y ponen precio a tu asesino."])
	elseif not on and state.on then
		if not state.canOff then
			LG:Print((L["El botín de guerra se queda activado al menos 24 h: podrás quitarlo en %s."]):format(ns.FormatDuration(state.offAt - ns.Now())))
			return false
		end
		w.periods[#w.periods][2] = ns.Now()
		LG:Print(L["Botín de guerra desactivado."])
	end
	LG:MarkDirty()
	return true
end

-- Los periodos viajan en el registro propio.
table.insert(ns.recordProviders, function(rec)
	local periods = LG.db.char.wager and LG.db.char.wager.periods
	if type(periods) == "table" and #periods > 0 then
		local list = {}
		for _, p in ipairs(periods) do list[#list + 1] = { p[1], p[2] } end
		rec.wager = list
	end
end)

---------------------------------------------------------------------------
-- Recompensas puestas a mano
---------------------------------------------------------------------------

-- Clave de un jugador para casar muertes y kills: su GUID o, si no, su nombre.
function ns.BountyMatches(pot, guid, name)
	if pot.guid and guid then return pot.guid == guid end
	return pot.name ~= nil and name ~= nil and ns.SameName(pot.name, name)
end

function ns.MergeBounty(g, rec, sender)
	if type(rec.id) ~= "string" or type(rec.member) ~= "string" or type(rec.t) ~= "number" then return false end
	if type(rec.merits) ~= "number" or rec.merits < 1 or rec.merits > MAX_BOUNTY or rec.merits ~= math.floor(rec.merits) then return false end
	if type(rec.name) ~= "string" and type(rec.guid) ~= "string" then return false end
	if g.bounties[rec.id] then return false end
	if sender and rec.member ~= sender then return false end
	g.bounties[rec.id] = { id = rec.id, member = rec.member, t = rec.t, merits = rec.merits,
		name = type(rec.name) == "string" and rec.name:sub(1, 48) or nil, guid = type(rec.guid) == "string" and rec.guid or nil,
		guild = type(rec.guild) == "string" and rec.guild:sub(1, 48) or nil }
	return true
end

ns.handlers.BOUNTY = function(sender, rec)
	local g = LG:GuildData()
	if g and type(rec) == "table" and ns.MergeBounty(g, rec, sender) then LG:DataChanged() end
end

-- Pone insignias propias por la cabeza de un enemigo (por nombre; el GUID si lo conocemos).
function ns.PlaceBounty(name, amount)
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	if not g then return false, L["No estás en una hermandad."] end
	name = name and strtrim(name) or ""
	if name == "" then return false, L["Escribe el nombre del enemigo."] end
	amount = math.floor(tonumber(amount) or 0)
	if amount < 1 then return false, L["Pon cuántas insignias."] end
	if amount > MAX_BOUNTY then return false, (L["Como mucho %d insignias por recompensa."]):format(MAX_BOUNTY) end
	local free = ns.AvailableInsignias(nil)
	if amount > free then return false, (L["Solo tienes %d insignias libres."]):format(free) end
	if g.members[name] or ns.roster[name] then return false, L["No se puede poner precio a alguien de tu hermandad."] end
	local guid, guild
	for gid, c in pairs(g.guildCache) do
		if ns.SameName(c.n, name) then guid, guild, name = gid, c.g, c.n or name end
	end
	local now = ns.Now()
	local rec = { id = ("%s:b:%d:%d"):format(me, now, math.random(1000, 9999)), member = me, t = now, merits = amount,
		name = name, guid = guid, guild = guild }
	ns.MergeBounty(g, rec)
	LG:Send("BOUNTY", rec)
	LG:DataChanged()
	LG:Print((L["Has puesto %d insignias por la cabeza de %s."]):format(amount, ns.ShortName(name)))
	ns.GuildAnnounce((L["Se pone precio a la cabeza de %s: %d insignias para quien lo mate."]):format(ns.ShortName(name), amount))
	return true
end

---------------------------------------------------------------------------
-- Precios (los calcula Merits.lua) y avisos
---------------------------------------------------------------------------

-- Precios abiertos agrupados por enemigo: { { name, guid, guild, total, pots, expires }, ... }, el más alto primero.
function ns.BountyTargets()
	local now = ns.Now()
	local byKey, list = {}, {}
	for _, pot in ipairs(ns.BountyPots()) do
		if not pot.claimedAt and pot.t + ns.WAGER.days * 86400 > now and pot.amount > 0 then
			local key = pot.guid or ("n:" .. (pot.name or "?"):lower())
			local tgt = byKey[key]
			if not tgt then
				tgt = { name = pot.name, guid = pot.guid, guild = pot.guild, total = 0, pots = {}, expires = 0 }
				byKey[key] = tgt
				list[#list + 1] = tgt
			end
			tgt.total = tgt.total + pot.amount
			tgt.pots[#tgt.pots + 1] = pot
			tgt.expires = math.max(tgt.expires, pot.t + ns.WAGER.days * 86400)
			tgt.name, tgt.guild = tgt.name or pot.name, tgt.guild or pot.guild
		end
	end
	table.sort(list, function(a, b) return a.total > b.total end)
	return list
end

-- Precios cobrados recientemente (para el historial).
function ns.BountyClaims(max)
	local list = {}
	for _, pot in ipairs(ns.BountyPots()) do
		if pot.claimedAt then list[#list + 1] = pot end
	end
	table.sort(list, function(a, b) return a.claimedAt > b.claimedAt end)
	for i = #list, (max or 10) + 1, -1 do list[i] = nil end
	return list
end

-- Tras una muerte o una kill propia: lo que se ha perdido o cobrado, en el chat.
function ns.BountyNotify(rec)
	local me = ns.PlayerFullName()
	for _, pot in ipairs(ns.BountyPots()) do
		if rec.kind == "death" and pot.death == rec.id and pot.victim == me and pot.amount > 0 then
			LG:Print((L["|cffff6b5aBotín de guerra:|r pierdes %d insignias. Ahora hay precio por la cabeza de %s: si la hermandad lo caza, recuperas la mitad."]):format(
				pot.amount, ns.ShortName(pot.name) or "?"))
		elseif rec.kind == "kill" and pot.claimKill == rec.id and pot.hunter == me then
			LG:Print((L["|cffffd100¡Recompensa!|r Cobras %d insignias por la cabeza de %s."]):format(pot.hunterGets, ns.ShortName(pot.name) or "?"))
			ns.GuildAnnounce((L["%s ha cobrado la cabeza de %s: %d insignias."]):format(ns.ShortName(me), ns.ShortName(pot.name) or "?", pot.hunterGets))
		end
	end
end
