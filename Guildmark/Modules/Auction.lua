-- Subasta de hermandad con insignias (nunca con oro ni con tickets del canal).
--
-- Cualquier miembro subasta un objeto suyo durante 1 día, con precio mínimo, y
-- cualquiera puja cuando quiera, sin estar en grupo. El ganador paga en
-- insignias: el 90 % para el vendedor y el 10 % para el cofre de hermandad.
-- Los oficiales también subastan objetos del banco de la hermandad ("bank", con
-- la duración que quieran): entonces todo va al cofre. No es el reparto del
-- botín de raid.
--
-- Datos sincronizados por el canal de la hermandad:
--   AUCTION  la subasta (la crea su vendedor; la cierran él o un oficial; sube "rev")
--   BID      la puja más alta de un miembro en una subasta (solo suya, solo sube)
--   SPEND    el pago del ganador (id = id de la subasta); lo descuenta el cálculo de
--            insignias y abona al vendedor. Si no lo publica un oficial, tiene que
--            coincidir con la puja del ganador.
--
-- El ganador sale de las mismas reglas en todos los addons; quien lo publica
-- (SPEND + subasta cerrada) es el vendedor, o cualquier oficial conectado si el
-- vendedor no está cuando termina.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Auction = LG:NewModule("Auction", "AceEvent-3.0", "AceTimer-3.0")

local MIN_INCREMENT = 5
local EXTEND = 120          -- una puja en los últimos 2 min alarga la subasta hasta 2 min
local CREATOR_GRACE = 300   -- otros oficiales cierran si el creador no lo ha hecho en 5 min
local AUCTION_TTL = 30 * 86400
local PERSONAL_HOURS = 24   -- las de los miembros duran 1 día
local MAX_OPEN = 3          -- subastas abiertas a la vez por vendedor
ns.SELLER_SHARE = 0.9       -- parte del pago para el vendedor (el resto, al cofre)

ns.AUCTION_DEFAULTS = { minBid = 10, hours = 24 }

-- Filtro de la lista: por la clase del objeto (Enum.ItemClass: 0 consumible, 2 arma, 4 armadura, 9 receta).
ns.AUCTION_TYPES = {
	{ key = "all", label = L["Todo"] },
	{ key = "weapon", label = L["Armas"] },
	{ key = "armor", label = L["Armaduras"] },
	{ key = "consumable", label = L["Consumibles"] },
	{ key = "recipe", label = L["Recetas"] },
	{ key = "other", label = L["Otros"] },
}
local CLASS_TYPE = { [0] = "consumable", [2] = "weapon", [4] = "armor", [9] = "recipe" }

function ns.AuctionType(itemID)
	local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if not getInfo or not itemID then return "other" end
	local ok, _, _, _, _, _, classID = pcall(getInfo, itemID)
	return ok and CLASS_TYPE[tonumber(classID) or -1] or "other"
end

---------------------------------------------------------------------------
-- Reglas comunes (todos los addons llegan al mismo resultado)
---------------------------------------------------------------------------

local function sortedBids(g, a)
	local list = {}
	for member, b in pairs(g.bids[a.id] or {}) do
		list[#list + 1] = { member = member, amount = b.amount, t = b.t }
	end
	return list
end

-- Fin real de la subasta: las pujas cerca del final la alargan.
function ns.AuctionEnds(g, a)
	local ends = a.ends
	local bids = sortedBids(g, a)
	table.sort(bids, function(x, y) return x.t < y.t end)
	for _, b in ipairs(bids) do
		if b.t <= ends and ends - b.t < EXTEND then ends = b.t + EXTEND end
	end
	return ends
end

-- Insignias que el miembro tiene comprometidas por ir ganando en otras subastas abiertas.
function ns.CommittedInsignias(member, exceptID)
	local g = LG:GuildData()
	if not g then return 0 end
	local total = 0
	for id, a in pairs(g.auctions) do
		if id ~= exceptID and a.status == "open" then
			local top = ns.AuctionTop(g, a)
			if top and top.member == member then total = total + top.amount end
		end
	end
	return total
end

-- Puja ganadora: la más alta (y la más antigua si empatan) cuyo autor tiene las
-- insignias para pagarla y que llegó antes del final.
function ns.AuctionTop(g, a)
	local ends = ns.AuctionEnds(g, a)
	local bids = sortedBids(g, a)
	table.sort(bids, function(x, y)
		if x.amount ~= y.amount then return x.amount > y.amount end
		return x.t < y.t
	end)
	local scores = ns.Scores()
	for _, b in ipairs(bids) do
		local s = scores[b.member]
		if b.t <= ends and b.amount >= a.min and s and b.amount <= s.merits then return b end
	end
	return nil
end

function ns.MinNextBid(g, a)
	local top = ns.AuctionTop(g, a)
	return top and (top.amount + MIN_INCREMENT) or a.min
end

-- Insignias que puede usar el jugador para pujar en esta subasta.
function ns.AvailableInsignias(auctionID)
	local me = ns.PlayerFullName()
	local s = ns.Scores()[me]
	return math.max(0, (s and s.merits or 0) - ns.CommittedInsignias(me, auctionID))
end

---------------------------------------------------------------------------
-- Fusión de datos recibidos
---------------------------------------------------------------------------

function ns.MergeAuction(g, rec, sender)
	if type(rec.id) ~= "string" or type(rec.rev) ~= "number" or type(rec.link) ~= "string" or type(rec.creator) ~= "string" then return false end
	if sender and rec.by ~= sender then return false end
	-- La abre su vendedor; la cierran él o un oficial. Las del banco, solo oficiales.
	if rec.by ~= rec.creator and not ns.CanManageEvents(rec.by) then return false end
	if rec.bank and not ns.Can("bankAuction", rec.creator) then return false end
	local old = g.auctions[rec.id]
	if old then
		if old.rev >= rec.rev then return false end
		if old.creator ~= rec.creator or old.link ~= rec.link or old.min ~= rec.min or (old.bank and true) ~= (rec.bank and true) then return false end
	end
	g.auctions[rec.id] = rec
	return true, old
end

function ns.MergeBid(g, rec, sender)
	if type(rec.auction) ~= "string" or type(rec.member) ~= "string" or type(rec.amount) ~= "number" then return false end
	if sender and rec.member ~= sender then return false end
	local a = g.auctions[rec.auction]
	if a and a.creator == rec.member and not a.bank then return false end -- nadie puja en lo suyo (las del banco no son de nadie)
	local list = g.bids[rec.auction]
	if not list then
		list = {}
		g.bids[rec.auction] = list
	end
	local old = list[rec.member]
	if old and old.amount >= rec.amount then return false end
	list[rec.member] = { amount = rec.amount, t = rec.t }
	return true, old
end

function ns.MergeSpend(g, rec, sender)
	if type(rec.id) ~= "string" or type(rec.member) ~= "string" or type(rec.merits) ~= "number" then return false end
	if g.spends[rec.id] then return false end
	if sender and rec.by ~= sender then return false end
	if not ns.CanManageEvents(rec.by) then
		-- El vendedor cierra su propia subasta: el pago tiene que ser la puja del ganador.
		local bid = g.bids[rec.id] and g.bids[rec.id][rec.member]
		if rec.by ~= rec.seller or rec.bank or not bid or bid.amount ~= rec.merits then return false end
	end
	g.spends[rec.id] = rec
	return true
end

ns.handlers.AUCTION = function(sender, rec)
	local g = LG:GuildData()
	if not g then return end
	local changed, old = ns.MergeAuction(g, rec, sender)
	if not changed then return end
	local me = ns.PlayerFullName()
	if not old and rec.status == "open" then
		LG:Print((L["Nueva subasta de hermandad: %s, desde %d insignias. Puja en /gmk > Mercado."]):format(rec.link, rec.min))
	elseif rec.status == "closed" and old and old.status == "open" and rec.winner == me then
		LG:Print((L["¡Has ganado %s por %d insignias! %s te lo entregará."]):format(rec.link, rec.amount or 0, ns.ShortName(rec.by)))
	end
	LG:DataChanged()
end

ns.handlers.BID = function(sender, rec)
	local g = LG:GuildData()
	if not g then return end
	local a = g.auctions[rec.auction]
	local me = ns.PlayerFullName()
	local wasTop = a and ns.AuctionTop(g, a)
	if not ns.MergeBid(g, rec, sender) then return end
	if a and wasTop and wasTop.member == me and rec.member ~= me then
		local nowTop = ns.AuctionTop(g, a)
		if nowTop and nowTop.member ~= me then
			LG:Print((L["Te han superado en %s: ahora va %d insignias."]):format(a.link, nowTop.amount))
		end
	end
	LG:DataChanged()
end

ns.handlers.SPEND = function(sender, rec)
	local g = LG:GuildData()
	if g and ns.MergeSpend(g, rec, sender) then
		LG:DataChanged()
		if rec.seller == ns.PlayerFullName() and not rec.bank then
			LG:Print((L["Has vendido %s por %d insignias: cobras %d. Pásaselo a %s por intercambio."]):format(
				rec.link or "?", rec.merits, math.floor(rec.merits * ns.SELLER_SHARE), ns.ShortName(rec.member)))
		end
	end
end

---------------------------------------------------------------------------
-- Acciones
---------------------------------------------------------------------------

local function publishAuction(g, rec)
	g.auctions[rec.id] = rec
	LG:Send("AUCTION", rec)
	LG:DataChanged()
end

local function copy(t)
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return c
end

-- bank = true: objeto del banco de la hermandad (solo oficiales; todo el pago al cofre).
function ns.StartAuction(link, minBid, hours, bank)
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	if not g then return false, L["No estás en una hermandad."] end
	if bank and not ns.Can("bankAuction", me) then return false, L["Tu rango no puede subastar objetos del banco."] end
	local itemID = link and tonumber(link:match("item:(%d+)"))
	if not itemID then return false, L["Arrastra primero un objeto."] end
	if bank then
		hours = tonumber(hours) or ns.AUCTION_DEFAULTS.hours
		if hours < 0.1 or hours > 24 * 7 then return false, L["La duración tiene que estar entre 0,1 y 168 horas."] end
	else
		hours = PERSONAL_HOURS
		local mine = 0
		for _, a in pairs(g.auctions) do
			if a.status == "open" and a.creator == me then mine = mine + 1 end
		end
		if mine >= MAX_OPEN then return false, (L["Puedes tener %d subastas abiertas a la vez."]):format(MAX_OPEN) end
	end
	local now = ns.Now()
	local rec = {
		id = ("%s:%d:%d"):format(me, now, math.random(1000, 9999)),
		link = link,
		itemID = itemID,
		min = math.max(1, math.floor(tonumber(minBid) or ns.AUCTION_DEFAULTS.minBid)),
		created = now,
		ends = now + math.floor(hours * 3600),
		status = "open",
		rev = 1,
		by = me,
		creator = me,
		bank = bank and true or nil,
	}
	publishAuction(g, rec)
	LG:Print((L["Subasta abierta: %s, desde %d insignias, %s."]):format(link, rec.min, ns.FormatDuration(rec.ends - now)))
	ns.GuildAnnounce((bank and L["Subasta del banco: %s desde %d insignias, %s. Puja en /gmk > Mercado."]
		or L["Nueva subasta: %s desde %d insignias, %s. Puja en /gmk > Mercado."]):format(link, rec.min, ns.FormatDuration(rec.ends - now)))
	return true
end

function ns.PlaceBid(auctionID, amount)
	local g = LG:GuildData()
	local a = g and g.auctions[auctionID]
	local me = ns.PlayerFullName()
	amount = math.floor(tonumber(amount) or 0)
	if not a or a.status ~= "open" then return false, L["Esa subasta ya no está abierta."] end
	if a.creator == me and not a.bank then return false, L["No puedes pujar en tu propia subasta."] end
	local now = ns.Now()
	if now > ns.AuctionEnds(g, a) then return false, L["La subasta ya ha terminado."] end
	local minimum = ns.MinNextBid(g, a)
	local mine = g.bids[auctionID] and g.bids[auctionID][me]
	if mine and amount <= mine.amount then return false, (L["Ya pujaste %d; tiene que ser más."]):format(mine.amount) end
	if amount < minimum then return false, (L["La puja mínima es %d."]):format(minimum) end
	local available = ns.AvailableInsignias(auctionID)
	if amount > available then return false, (L["Solo tienes %d insignias libres."]):format(available) end
	local rec = { auction = auctionID, member = me, amount = amount, t = now }
	ns.MergeBid(g, rec)
	LG:Send("BID", rec)
	LG:DataChanged()
	return true
end

-- Cierra una subasta: con ganador (paga sus insignias) o sin él.
function ns.FinishAuction(auctionID, cancelled)
	local g = LG:GuildData()
	local a = g and g.auctions[auctionID]
	local me = ns.PlayerFullName()
	if not a or a.status ~= "open" or (a.creator ~= me and not ns.CanManageEvents(me)) then return end
	local rec = copy(a)
	rec.rev = a.rev + 1
	rec.by = me
	if cancelled then
		rec.status = "cancelled"
	else
		local top = ns.AuctionTop(g, a)
		rec.status = "closed"
		if top then
			rec.winner, rec.amount = top.member, top.amount
			local spend = { id = a.id, member = top.member, merits = top.amount, link = a.link, itemID = a.itemID, t = ns.Now(), by = me,
				seller = a.creator, bank = a.bank, v = 2 }
			ns.MergeSpend(g, spend)
			LG:Send("SPEND", spend)
		end
	end
	publishAuction(g, rec)
	if rec.winner then
		ns.GuildAnnounce((L["%s gana %s por %d insignias."]):format(ns.ShortName(rec.winner), rec.link, rec.amount))
		LG:Print((L["%s gana %s por %d insignias. Pásaselo por intercambio y se marcará como entregado."]):format(
			ns.ShortName(rec.winner), rec.link, rec.amount))
	end
end

function ns.MarkAuctionDelivered(auctionID, auto)
	local g = LG:GuildData()
	local a = g and g.auctions[auctionID]
	local me = ns.PlayerFullName()
	if not a or a.status ~= "closed" or a.delivered or (a.creator ~= me and not ns.CanManageEvents(me)) then return end
	local rec = copy(a)
	rec.rev = a.rev + 1
	rec.by = ns.PlayerFullName()
	rec.delivered = ns.Now()
	rec.auto = auto or nil
	publishAuction(g, rec)
end

-- Listas para la interfaz: abiertas (las que acaban antes primero) y terminadas.
function ns.AuctionLists()
	local g = LG:GuildData()
	local open, finished = {}, {}
	if not g then return open, finished end
	for _, a in pairs(g.auctions) do
		if a.status == "open" then open[#open + 1] = a else finished[#finished + 1] = a end
	end
	table.sort(open, function(x, y) return ns.AuctionEnds(g, x) < ns.AuctionEnds(g, y) end)
	table.sort(finished, function(x, y) return (x.created or 0) > (y.created or 0) end)
	return open, finished
end

function ns.PruneAuctions(g)
	local now = ns.Now()
	for id, a in pairs(g.auctions) do
		if a.status ~= "open" and now - (a.ends or 0) > AUCTION_TTL then
			g.auctions[id] = nil
			g.bids[id] = nil
		end
	end
end

function ns.FormatDuration(seconds)
	seconds = math.max(0, seconds)
	if seconds < 3600 then return (L["%d min"]):format(math.ceil(seconds / 60)) end
	if seconds < 86400 then return (L["%d h"]):format(math.floor(seconds / 3600)) end
	return (L["%d d %d h"]):format(math.floor(seconds / 86400), math.floor((seconds % 86400) / 3600))
end

---------------------------------------------------------------------------
-- Cierre automático y entregas
---------------------------------------------------------------------------

function Auction:OnEnable()
	self:ScheduleRepeatingTimer("CheckEnds", 30)
end

function Auction:CheckEnds()
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	if not g then return end
	local officer = ns.CanManageEvents(me)
	local now = ns.Now()
	for id, a in pairs(g.auctions) do
		if a.status == "open" then
			local ends = ns.AuctionEnds(g, a)
			-- La cierra su vendedor; si no está, cualquier oficial pasados 5 minutos.
			if now >= ends and (a.creator == me or (officer and now >= ends + CREATOR_GRACE)) then
				ns.FinishAuction(id)
			end
		end
	end
end

-- La llama Orders al completarse un intercambio: si un oficial le pasa a alguien
-- un objeto que ganó en subasta, queda como entregado.
function ns.CheckAuctionDeliveries(partner, given)
	local g = LG:GuildData()
	if not g or not given then return end
	local me = ns.PlayerFullName()
	for id, a in pairs(g.auctions) do
		if a.status == "closed" and not a.delivered and a.winner and ns.SameName(a.winner, partner) and given[a.itemID]
			and (a.creator == me or ns.CanManageEvents(me)) then
			ns.MarkAuctionDelivered(id, true)
			LG:Print((L["Subasta entregada: %s a %s."]):format(a.link, ns.ShortName(a.winner)))
		end
	end
end
