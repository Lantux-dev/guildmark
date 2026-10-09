-- Encargos de artesanía: un miembro pide una receta a un artesano de la guild
-- o a todo su gremio (los que tienen esa receta): el primero que acepta se la queda.
--
-- Estados: open (pedido) -> accepted (aceptado) -> done (entregado)
--          open -> declined (rechazado) | open/accepted -> cancelled (cancelado)
--
-- Cada cambio sube "rev" y lo firma "by". Solo puede hacer cada cambio quien
-- toca: el que pide crea y cancela, el artesano acepta y rechaza, y la entrega
-- la puede marcar cualquiera de los dos. La entrega se detecta sola al ver el
-- objeto pasar de uno a otro en la ventana de intercambio.
--
-- Encargo al gremio (guild = true, sin artesano): lo puede aceptar cualquiera que
-- no sea quien lo pide, y al aceptarlo pasa a ser su artesano. Si dos aceptan a la
-- vez (misma "rev"), todos los addons se quedan con el mismo: el que lo hizo antes
-- (hora del servidor) y, si empatan, el primero por orden alfabético. Lo mismo vale
-- si quien lo pidió lo cancela mientras alguien lo acepta. Caduca a los 7 días sin
-- que nadie lo acepte.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Orders = LG:NewModule("Orders", "AceEvent-3.0")

local ORDER_TTL = 30 * 86400
local GUILD_ORDER_TTL = 7 * 86400 -- encargo al gremio sin aceptar: caduca

-- ¿Encargo al gremio que nadie aceptó a tiempo?
function ns.OrderExpired(o)
	return o.guild and o.status == "open" and ns.Now() - (o.t or 0) > GUILD_ORDER_TTL or false
end
local TRADE_SLOTS = 6 -- el séptimo hueco es "no se intercambiará"

-- Quién puede dejar el encargo en cada estado.
local function authorized(order, status, who)
	if status == "open" or status == "cancelled" then return who == order.requester end
	-- Al gremio: lo acepta cualquiera menos quien lo pide (y pasa a ser su artesano); no se rechaza.
	if order.guild and status == "accepted" then return who ~= order.requester and (order.crafter == nil or order.crafter == who) end
	if order.guild and status == "declined" then return false end
	if status == "accepted" or status == "declined" then return who == order.crafter end
	if status == "done" then return who == order.requester or who == order.crafter end
	return false
end

-- Con la misma "rev" (dos cambios a la vez): gana el anterior y, si empatan, el primero por nombre.
local function wins(rec, old)
	if (rec.updated or 0) ~= (old.updated or 0) then return (rec.updated or 0) < (old.updated or 0) end
	return tostring(rec.by) < tostring(old.by)
end

function ns.MergeOrder(g, rec, sender)
	if type(rec.id) ~= "string" or type(rec.rev) ~= "number" then return false end
	if not authorized(rec, rec.status, rec.by) then return false end
	if sender and rec.by ~= sender then return false end
	if rec.guild and rec.status == "accepted" and rec.crafter ~= rec.by then return false end
	local old = g.orders[rec.id]
	if old then
		-- Lo que no cambia nunca: quién lo pide, qué y cuánto, y si es al gremio.
		if old.requester ~= rec.requester or old.recipe ~= rec.recipe or old.qty ~= rec.qty or (old.guild or false) ~= (rec.guild or false) then return false end
		-- Un encargo directo no cambia de artesano.
		if not old.guild and old.crafter ~= rec.crafter then return false end
		if old.rev > rec.rev then return false end
		if old.rev == rec.rev and (old.by == rec.by or not wins(rec, old)) then return false end
	end
	g.orders[rec.id] = rec
	return true, old
end

-- Avisos en el chat cuando un encargo te afecta.
local function notify(rec, old)
	local me = ns.PlayerFullName()
	if rec.by == me then return end
	local what = ("%dx %s"):format(rec.qty or 1, ns.RecipeName(rec.recipe) or "?")
	if rec.guild and rec.status == "open" and not old and rec.requester ~= me and ns.KnowsRecipe(me, rec.recipe) then
		LG:Print((L["Encargo para tu gremio: %s (lo pide %s). El primero que lo acepte se lo queda: /gmk > Encargos."]):format(what, ns.ShortName(rec.requester)))
	elseif rec.guild and rec.status == "accepted" and old and old.status == "accepted" and old.crafter == me and rec.crafter ~= me then
		LG:Print((L["%s ha aceptado antes que tú el encargo de %s."]):format(ns.ShortName(rec.crafter), what))
	elseif rec.guild and rec.status == "accepted" and rec.requester ~= me and rec.crafter ~= me and ns.KnowsRecipe(me, rec.recipe) then
		LG:Print((L["El encargo de %s ya lo ha cogido %s."]):format(what, ns.ShortName(rec.crafter)))
	elseif rec.status == "open" and not old and rec.crafter == me then
		LG:Print((L["%s te pide %s. Míralo en /gmk > Encargos."]):format(rec.requester, what))
	elseif rec.requester == me and rec.status == "accepted" then
		LG:Print((L["%s ha aceptado tu encargo de %s."]):format(rec.crafter, what))
	elseif rec.requester == me and rec.status == "declined" then
		LG:Print((L["%s no puede hacer tu encargo de %s."]):format(rec.crafter, what))
	elseif rec.crafter == me and rec.status == "cancelled" then
		LG:Print((L["%s ha cancelado el encargo de %s."]):format(rec.requester, what))
	elseif rec.status == "done" and (rec.requester == me or rec.crafter == me) then
		LG:Print((L["Encargo entregado: %s."]):format(what))
	end
end

ns.handlers.ORDER = function(sender, rec)
	local g = LG:GuildData()
	if not g then return end
	local changed, old = ns.MergeOrder(g, rec, sender)
	if changed then
		notify(rec, old)
		LG:DataChanged()
	end
end

local function publish(g, rec)
	g.orders[rec.id] = rec
	LG:Send("ORDER", rec)
	LG:DataChanged()
end

-- Objeto que produce una receta, según los datos del artesano.
local function outputItem(crafter, recipeID)
	local g = LG:GuildData()
	local m = g and g.members[crafter]
	for _, r in pairs(m and m.recipes or {}) do
		if r.out and r.out[recipeID] then return r.out[recipeID] end
	end
	return nil
end

-- crafter = nil: al gremio de esa receta (skillLine, para mostrar de qué gremio es).
function ns.CreateOrder(crafter, recipeID, qty, note, skillLine)
	local g = LG:GuildData()
	if not g or not LG:HasConsent() then return end
	local me = ns.PlayerFullName()
	local now = ns.Now()
	local item = crafter and outputItem(crafter, recipeID)
	if not crafter then
		for _, name in ipairs(ns.MembersWithRecipe(recipeID)) do item = item or outputItem(name, recipeID) end
	end
	local rec = {
		id = ("%s:%d:%d"):format(me, now, math.random(1000, 9999)),
		t = now,
		requester = me,
		crafter = crafter,
		guild = not crafter or nil,
		skillLine = not crafter and tonumber(skillLine) or nil,
		recipe = recipeID,
		item = item,
		qty = math.max(1, math.floor(tonumber(qty) or 1)),
		note = note and note ~= "" and note:sub(1, 80) or nil,
		status = "open",
		rev = 1,
		by = me,
		updated = now,
	}
	publish(g, rec)
	if crafter then
		LG:Print((L["Encargo enviado a %s: %dx %s."]):format(crafter, rec.qty, ns.RecipeName(recipeID) or "?"))
	else
		LG:Print((L["Encargo enviado al gremio: %dx %s. El primero que lo acepte se lo queda."]):format(rec.qty, ns.RecipeName(recipeID) or "?"))
	end
end

-- Aceptar un encargo al gremio: pasas a ser su artesano.
function ns.AcceptGuildOrder(id)
	return ns.SetOrderStatus(id, "accepted", { crafter = ns.PlayerFullName() })
end

-- Quién tiene una receta (según las fichas del addon) y si la tiene alguien en concreto.
function ns.MembersWithRecipe(recipeID)
	local g = LG:GuildData()
	local list = {}
	for name, m in pairs(g and g.members or {}) do
		for _, r in pairs(m.recipes or {}) do
			for _, id in ipairs(r.ids or {}) do
				if id == recipeID then list[#list + 1] = name break end
			end
			if list[#list] == name then break end
		end
	end
	table.sort(list)
	return list
end

function ns.KnowsRecipe(name, recipeID)
	for _, n in ipairs(ns.MembersWithRecipe(recipeID)) do
		if n == name then return true end
	end
	return false
end

-- Cambia el estado de un encargo si el jugador puede hacerlo.
function ns.SetOrderStatus(id, status, extra)
	local g = LG:GuildData()
	local old = g and g.orders[id]
	if not old then return false end
	local me = ns.PlayerFullName()
	if not authorized(old, status, me) then return false end
	local rec = {}
	for k, v in pairs(old) do rec[k] = v end
	for k, v in pairs(extra or {}) do rec[k] = v end
	rec.status = status
	rec.rev = old.rev + 1
	rec.by = me
	rec.updated = ns.Now()
	publish(g, rec)
	return true
end

function ns.OrdersByRole()
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	local roles = { forMe = {}, mine = {}, others = {} }
	if not g then return roles end
	for _, o in pairs(g.orders) do
		if ns.OrderExpired(o) and o.requester ~= me then
			-- Al gremio y sin aceptar a tiempo: solo lo ve quien lo pidió.
		elseif o.guild and o.status == "open" and o.requester ~= me and ns.KnowsRecipe(me, o.recipe) then
			roles.forMe[#roles.forMe + 1] = o
		elseif o.crafter == me then
			roles.forMe[#roles.forMe + 1] = o
		elseif o.requester == me then
			roles.mine[#roles.mine + 1] = o
		else
			roles.others[#roles.others + 1] = o
		end
	end
	-- Primero los pendientes, luego por fecha.
	local rank = { open = 1, accepted = 2, done = 3, declined = 4, cancelled = 5 }
	for _, list in pairs(roles) do
		table.sort(list, function(a, b)
			if rank[a.status] ~= rank[b.status] then return (rank[a.status] or 9) < (rank[b.status] or 9) end
			return a.updated > b.updated
		end)
	end
	return roles
end

function ns.PruneOrders(g)
	local now = ns.Now()
	for id, o in pairs(g.orders) do
		if now - (o.updated or o.t or 0) > ORDER_TTL then g.orders[id] = nil end
	end
end

---------------------------------------------------------------------------
-- Detección de entregas en la ventana de intercambio
---------------------------------------------------------------------------

local trade -- { partner, give = { [itemID] = { count, createdBy } }, get = {...} }

local createdByPattern
local function buildCreatedByPattern()
	local fmt = ITEM_CREATED_BY
	if not fmt then return nil end
	-- "|cff00ff00<Hecho por %s>|r" -> "^<Hecho por (.+)>$"
	fmt = fmt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	fmt = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1"):gsub("%%s", "(.+)")
	return "^" .. fmt .. "$"
end

-- "Hecho por X" del objeto en un hueco del intercambio, si lo tiene.
local function createdBy(getter, slot)
	if not createdByPattern or not getter then return nil end
	local ok, data = pcall(getter, slot)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
	for _, line in ipairs(data.lines) do
		local text = line.leftText
		if type(text) == "string" then
			local name = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match(createdByPattern)
			if name then return ns.FullName(name) end
		end
	end
	return nil
end

local function snapshotSide(linkFn, infoFn, tooltipFn)
	local items = {}
	for slot = 1, TRADE_SLOTS do
		local link = linkFn(slot)
		local itemID = link and tonumber(link:match("item:(%d+)"))
		if itemID then
			local count = infoFn and select(3, infoFn(slot)) or 1
			local entry = items[itemID] or { count = 0 }
			entry.count = entry.count + (count or 1)
			entry.createdBy = entry.createdBy or createdBy(tooltipFn, slot)
			items[itemID] = entry
		end
	end
	return items
end

function Orders:OnEnable()
	createdByPattern = buildCreatedByPattern()
	ns.RegisterEvent(self, "TRADE_SHOW")
	ns.RegisterEvent(self, "TRADE_ACCEPT_UPDATE")
	ns.RegisterEvent(self, "UI_INFO_MESSAGE")
end

function Orders:TRADE_SHOW()
	trade = { partner = ns.UnitFullName("NPC") }
end

-- Se guarda lo que hay en la mesa cada vez que alguien acepta; el intercambio
-- se cierra justo después y entonces ya no se puede leer.
function Orders:TRADE_ACCEPT_UPDATE()
	if not trade then return end
	local tip = C_TooltipInfo or {}
	trade.give = snapshotSide(GetTradePlayerItemLink, GetTradePlayerItemInfo, tip.GetTradePlayerItem)
	trade.get = snapshotSide(GetTradeTargetItemLink, GetTradeTargetItemInfo, tip.GetTradeTargetItem)
end

function Orders:UI_INFO_MESSAGE(_, _, message)
	if message ~= ERR_TRADE_COMPLETE or not trade or not trade.partner then return end
	local done = trade
	trade = nil
	self:CheckDeliveries(done)
end

function Orders:CheckDeliveries(t)
	local g = LG:GuildData()
	if not g then return end
	if ns.CheckAuctionDeliveries then ns.CheckAuctionDeliveries(t.partner, t.give) end
	local me = ns.PlayerFullName()
	for id, o in pairs(g.orders) do
		if o.status == "accepted" or o.status == "open" then
			local item, side
			if o.crafter == me and ns.SameName(o.requester, t.partner) then
				item = o.item and t.give and t.give[o.item]
				side = "crafter"
			elseif o.requester == me and ns.SameName(o.crafter, t.partner) then
				item = o.item and t.get and t.get[o.item]
				side = "requester"
			end
			if item then
				local verified = item.createdBy and ns.SameName(item.createdBy, o.crafter) or nil
				ns.SetOrderStatus(id, "done", { delivered = item.count, verified = verified, auto = side })
			end
		end
	end
end
