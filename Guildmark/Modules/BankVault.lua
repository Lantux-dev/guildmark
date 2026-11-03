-- Banco de la hermandad del juego: lo que hay dentro y las peticiones para sacar algo.
--
-- Contenido: el juego solo deja leer el banco a quien lo tiene abierto. Al abrirlo, el
-- addon pide al juego cada pestaña que ese jugador puede ver (una detrás de otra), las
-- copia (objeto y cantidad por hueco) y comparte la foto con la hermandad (BANKSNAP),
-- con la hora y quién la hizo. Cada pestaña se queda con la foto más reciente.
-- Qué pestañas ve cada rango en el addon lo decide el maestro (ajustes "bankTab:<n>"):
-- así un oficial que abre el banco no destapa una pestaña oculta a los reclutas.
--
-- Peticiones (BANKASK): un miembro pide un objeto del banco y le llega a quien tenga
-- el permiso «Entregar objetos del banco». Estados: open -> accepted (un oficial la coge)
-- -> done (entregada); open -> declined | open/accepted -> cancelled. La retirada se
-- comprueba con el registro del banco (la saca ese oficial) y la entrega con el
-- intercambio; si no se detecta (correo...), se marca a mano.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Vault = LG:NewModule("BankVault", "AceEvent-3.0", "AceTimer-3.0")
ns.BankVaultModule = Vault -- para las pruebas

local SLOTS = 98            -- huecos por pestaña (14 x 7)
local MAX_TABS = 8
local TAB_TIMEOUT = 3       -- segundos de espera a que llegue una pestaña pedida
local ASK_KEEP = 30 * 86400 -- las peticiones cerradas se guardan 30 días
local ASK_MAX_OPEN = 5      -- peticiones abiertas por miembro
ns.BANK_SLOTS = SLOTS
local pendingItems = {}   -- objetos cuyo nombre se ha pedido al servidor (para repintar al llegar)

---------------------------------------------------------------------------
-- Pestañas visibles por rango
---------------------------------------------------------------------------

-- Rango más bajo (índice más alto) que ve una pestaña; por defecto, todos.
function ns.BankTabMaxRank(tab)
	local v = ns.GuildSetting and ns.GuildSetting("bankTab:" .. tab)
	return type(v) == "number" and v or (ns.GuildRankCount() - 1)
end

function ns.BankTabVisible(tab, name)
	local idx = ns.RankIndexOf(name or ns.PlayerFullName())
	if idx == nil then return false end
	return idx == 0 or idx <= ns.BankTabMaxRank(tab)
end

---------------------------------------------------------------------------
-- Foto del contenido
---------------------------------------------------------------------------

local function cleanText(s, max)
	if type(s) ~= "string" then return nil end
	s = s:gsub("|", ""):sub(1, max)
	return s ~= "" and s or nil
end

-- Una pestaña recibida: válida y limpia, o nil.
local function cleanTab(tab)
	if type(tab) ~= "table" or type(tab.t) ~= "number" or type(tab.slots) ~= "table" then return nil end
	if tab.t > ns.Now() + 300 then return nil end
	local out = { t = tab.t, by = cleanText(tab.by, 60), name = cleanText(tab.name, 32),
		icon = (type(tab.icon) == "number" or type(tab.icon) == "string") and tab.icon or nil, slots = {} }
	if type(out.icon) == "string" then out.icon = out.icon:sub(1, 120) end
	for slot, s in pairs(tab.slots) do
		slot = tonumber(slot)
		if slot and slot >= 1 and slot <= SLOTS and type(s) == "table" and type(s.id) == "number" and s.id > 0
			and type(s.n) == "number" and s.n >= 1 and s.n <= 1000 then
			out.slots[slot] = { id = math.floor(s.id), n = math.floor(s.n),
				l = type(s.l) == "string" and s.l:find("|Hitem:", 1, true) and s.l:sub(1, 160) or nil }
		end
	end
	return out
end

-- Junta una foto (propia o de otro): cada pestaña se queda con la más reciente.
function ns.MergeBankSnapshot(g, data, sender)
	if type(data) ~= "table" then return false end
	if sender and not g.members[sender] then return false end
	g.bankSnap = g.bankSnap or { tabs = {} }
	g.bankSnap.tabs = g.bankSnap.tabs or {}
	local changed = false
	for n, tab in pairs(type(data.tabs) == "table" and data.tabs or {}) do
		n = tonumber(n)
		local clean = n and n >= 1 and n <= MAX_TABS and n == math.floor(n) and cleanTab(tab)
		if clean and (not sender or clean.by == sender) then
			local old = g.bankSnap.tabs[n]
			if not old or clean.t > old.t then
				g.bankSnap.tabs[n] = clean
				changed = true
			end
		end
	end
	local m = data.money
	if type(m) == "table" and type(m.t) == "number" and type(m.amount) == "number" and m.amount >= 0 and m.amount <= 1e11
		and m.t <= ns.Now() + 300 and (not sender or m.by == sender) then
		local old = g.bankSnap.money
		if not old or m.t > old.t then
			g.bankSnap.money = { t = m.t, by = cleanText(m.by, 60), amount = math.floor(m.amount) }
			changed = true
		end
	end
	return changed
end

ns.handlers.BANKSNAP = function(sender, data)
	local g = LG:GuildData()
	if g and ns.MergeBankSnapshot(g, data, sender) then LG:DataChanged() end
end

-- Pestañas que puede ver un miembro: { { n, name, icon, t, by, slots } } en orden.
function ns.BankTabs(name)
	local g = LG:GuildData()
	local list = {}
	for n = 1, MAX_TABS do
		local tab = g and g.bankSnap and g.bankSnap.tabs and g.bankSnap.tabs[n]
		if tab and ns.BankTabVisible(n, name) then
			list[#list + 1] = { n = n, name = tab.name or (L["Pestaña %d"]):format(n), icon = tab.icon, t = tab.t, by = tab.by, slots = tab.slots }
		end
	end
	return list
end

-- Unidades de un objeto en las pestañas visibles (para pedir como mucho lo que hay).
function ns.BankItemCount(itemID, name)
	local total = 0
	for _, tab in ipairs(ns.BankTabs(name)) do
		for _, s in pairs(tab.slots) do
			if s.id == itemID then total = total + s.n end
		end
	end
	return total
end

---------------------------------------------------------------------------
-- Lectura con el banco abierto
---------------------------------------------------------------------------

local function tabInfo(n)
	if not GetGuildBankTabInfo then return nil end
	local ok, name, icon, viewable = pcall(GetGuildBankTabInfo, n)
	if not ok then return nil end
	return name, icon, viewable
end

-- Lee una pestaña ya cargada: { [hueco] = { id, n, l } } y si tenía algo.
local function readSlots(n)
	local slots, any = {}, false
	for slot = 1, SLOTS do
		local ok, link = pcall(GetGuildBankItemLink, n, slot)
		local id = ok and type(link) == "string" and tonumber(link:match("item:(%d+)"))
		if id then
			local okInfo, _, count = pcall(GetGuildBankItemInfo, n, slot)
			-- El enlace solo hace falta si el objeto tiene sufijo ("del oso"...): si no, basta el número.
			local suffix = link:match("item:%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:(%-?%d+)")
			slots[slot] = { id = id, n = math.max(1, tonumber(okInfo and count) or 1), l = suffix and suffix ~= "0" and link or nil }
			any = true
		end
	end
	return slots, any
end

function Vault:StartScan()
	if not LG:GuildData() or not LG:HasConsent() then return end
	self.open = true
	self.queue, self.result = {}, {}
	local count = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
	for n = 1, math.min(count, MAX_TABS) do
		local _, _, viewable = tabInfo(n)
		if viewable then self.queue[#self.queue + 1] = n end
	end
	self:NextTab()
end

function Vault:NextTab()
	local n = table.remove(self.queue or {}, 1)
	if not n then return self:FinishScan() end
	self.waiting = n
	if QueryGuildBankTab then pcall(QueryGuildBankTab, n) end
	self.timeout = self:ScheduleTimer(function() self:ReadTab(n, true) end, TAB_TIMEOUT)
end

-- El juego avisa de que ha llegado el contenido pedido (o de que algo cambió dentro).
function Vault:SlotsChanged()
	if self.waiting then
		local n = self.waiting
		if self.timeout then self:CancelTimer(self.timeout); self.timeout = nil end
		self:ScheduleTimer(function() if self.waiting == n then self:ReadTab(n, false) end end, 0.2)
	elseif self.open then
		-- Un depósito o una retirada con el banco abierto: otra foto, un poco después.
		if self.rescan then return end
		self.rescan = self:ScheduleTimer(function() self.rescan = nil; if self.open then self:StartScan() end end, 3)
	end
end

function Vault:ReadTab(n, timedOut)
	if self.waiting ~= n then return end
	self.waiting, self.timeout = nil, nil
	local slots, any = readSlots(n)
	-- Si no llegó a cargar y está vacía, no se sabe si lo está de verdad: no se guarda.
	if any or not timedOut then
		local name, icon = tabInfo(n)
		self.result[n] = { t = ns.Now(), by = ns.PlayerFullName(), name = name, icon = icon, slots = slots }
	end
	self:NextTab()
end

function Vault:FinishScan()
	local g = LG:GuildData()
	if not g then return end
	local me, now = ns.PlayerFullName(), ns.Now()
	local data = { tabs = self.result or {} }
	local ok, money = pcall(GetGuildBankMoney)
	if ok and tonumber(money) then data.money = { t = now, by = me, amount = math.floor(money) } end
	if ns.MergeBankSnapshot(g, data) then
		LG:Send("BANKSNAP", data)
		LG:DataChanged()
	end
end

function Vault:OnEnable()
	if not GetNumGuildBankTabs then return end
	local guildBanker = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker or 10
	pcall(ns.RegisterEvent, self, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
		if kind == guildBanker then self:ScheduleTimer("StartScan", 1) end
	end)
	pcall(ns.RegisterEvent, self, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
		if kind == guildBanker then self.open, self.waiting = false, nil end
	end)
	pcall(ns.RegisterEvent, self, "GUILDBANKFRAME_OPENED", function() self:ScheduleTimer("StartScan", 1) end)
	pcall(ns.RegisterEvent, self, "GUILDBANKFRAME_CLOSED", function() self.open, self.waiting = false, nil end)
	pcall(ns.RegisterEvent, self, "GUILDBANKBAGSLOTS_CHANGED", function() self:SlotsChanged() end)
	-- Llega del servidor el nombre de un objeto que se pidió: se repinta (una vez por tanda).
	pcall(ns.RegisterEvent, self, "GET_ITEM_INFO_RECEIVED", function(_, itemID)
		if not pendingItems[itemID] then return end
		pendingItems[itemID] = nil
		if self.itemRefresh then return end
		self.itemRefresh = self:ScheduleTimer(function()
			self.itemRefresh = nil
			if ns.RefreshMainFrame then ns.RefreshMainFrame() end
			if ns.UpdateOrderMaterials then ns.UpdateOrderMaterials() end
		end, 0.3)
	end)
end

---------------------------------------------------------------------------
-- Peticiones para sacar algo del banco
---------------------------------------------------------------------------

local function canDeliver(name) return ns.Can("bankDeliver", name) end

local function authorized(ask, status, who)
	if status == "open" or status == "cancelled" then return who == ask.requester end
	if status == "accepted" then return canDeliver(who) and ask.officer == who end
	if status == "declined" then return canDeliver(who) end
	if status == "done" then return who == ask.requester or who == ask.officer end
	return false
end

-- Con la misma "rev": gana el cambio anterior y, si empatan, el primero por nombre.
local function wins(rec, old)
	if (rec.updated or 0) ~= (old.updated or 0) then return (rec.updated or 0) < (old.updated or 0) end
	return tostring(rec.by) < tostring(old.by)
end

function ns.MergeBankAsk(g, rec, sender)
	if type(rec) ~= "table" or type(rec.id) ~= "string" or type(rec.rev) ~= "number" or type(rec.requester) ~= "string" then return false end
	if type(rec.item) ~= "number" or type(rec.qty) ~= "number" or rec.qty < 1 or rec.qty > 1000 or rec.qty ~= math.floor(rec.qty) then return false end
	if type(rec.t) ~= "number" or type(rec.by) ~= "string" then return false end
	if sender and rec.by ~= sender then return false end
	if not authorized(rec, rec.status, rec.by) then return false end
	local old = g.bankAsks[rec.id]
	if old then
		if old.requester ~= rec.requester or old.item ~= rec.item or old.qty ~= rec.qty or old.t ~= rec.t then return false end
		-- Una vez cogida, solo la puede seguir el mismo oficial.
		if old.officer and rec.officer ~= old.officer then return false end
		if old.rev > rec.rev then return false end
		if old.rev == rec.rev and (old.by == rec.by or not wins(rec, old)) then return false end
	elseif rec.status ~= "open" or rec.by ~= rec.requester then
		return false
	end
	g.bankAsks[rec.id] = { id = rec.id, t = rec.t, requester = rec.requester, item = math.floor(rec.item),
		link = type(rec.link) == "string" and rec.link:find("|Hitem:", 1, true) and rec.link:sub(1, 200) or nil,
		qty = rec.qty, note = cleanText(rec.note, 80), status = rec.status, officer = type(rec.officer) == "string" and rec.officer or nil,
		acceptedAt = tonumber(rec.acceptedAt), auto = rec.auto == "trade" and "trade" or nil,
		rev = rec.rev, by = rec.by, updated = tonumber(rec.updated) or rec.t }
	return true, old
end

-- Enlace de un objeto para mostrarlo: el guardado, el del juego o, si aún no lo tiene en
-- caché, se le pide y mientras tanto sale «[objeto N]» (al llegar se repinta la ventana).
function ns.BankItemLink(itemID, link)
	if type(link) == "string" then return link end
	if ns.GetItemInfo then
		local ok, _, l = pcall(ns.GetItemInfo, itemID)
		if ok and type(l) == "string" then return l end
	end
	-- GetItemInfo ya se lo pide al servidor; se apunta para repintar cuando llegue.
	if itemID and not pendingItems[itemID] then
		pendingItems[itemID] = true
		if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
	end
	return "[" .. (L["objeto %d"]):format(itemID or 0) .. "]"
end

-- Solo el nombre (sin enlace ni colores), con el mismo aviso de repintado.
function ns.ItemName(itemID)
	if ns.GetItemInfo then
		local ok, name = pcall(ns.GetItemInfo, itemID)
		if ok and type(name) == "string" then return name end
	end
	return (ns.BankItemLink(itemID):gsub("^%[", ""):gsub("%]$", ""))
end

local function askText(a)
	return ("%s x%d"):format(ns.BankItemLink(a.item, a.link), a.qty)
end

local function notifyAsk(rec, old)
	local me = ns.PlayerFullName()
	if rec.by == me then return end
	if rec.status == "open" and not old and canDeliver(me) then
		LG:Print((L["%s pide del banco: %s. Míralo en /gmk > Banco."]):format(ns.ShortName(rec.requester), askText(rec)))
	elseif rec.requester == me and rec.status == "accepted" then
		LG:Print((L["%s se encarga de tu petición del banco: %s."]):format(ns.ShortName(rec.officer), askText(rec)))
	elseif rec.requester == me and rec.status == "declined" then
		LG:Print((L["Tu petición del banco (%s) ha sido rechazada."]):format(askText(rec)))
	elseif rec.status == "accepted" and old and old.status == "open" and canDeliver(me) and rec.officer ~= me then
		LG:Print((L["%s ya se encarga de la petición de %s."]):format(ns.ShortName(rec.officer), ns.ShortName(rec.requester)))
	elseif rec.status == "done" and (rec.requester == me or rec.officer == me) then
		LG:Print((L["Petición del banco entregada: %s."]):format(askText(rec)))
	end
end

ns.handlers.BANKASK = function(sender, rec)
	local g = LG:GuildData()
	if not g then return end
	local changed, old = ns.MergeBankAsk(g, rec, sender)
	if changed then
		notifyAsk(rec, old)
		LG:DataChanged()
	end
end

local function publishAsk(g, rec)
	ns.MergeBankAsk(g, rec)
	LG:Send("BANKASK", rec)
	LG:DataChanged()
end

function ns.CreateBankAsk(itemID, link, qty, note)
	local g = LG:GuildData()
	if not g or not LG:HasConsent() then return false, L["No estás en una hermandad."] end
	local me, now = ns.PlayerFullName(), ns.Now()
	qty = math.floor(tonumber(qty) or 0)
	if not tonumber(itemID) then return false, L["Elige un objeto del banco."] end
	if qty < 1 then return false, L["Pon una cantidad."] end
	local have = ns.BankItemCount(itemID, me)
	if have > 0 and qty > have then return false, (L["En el banco hay %d."]):format(have) end
	local open = 0
	for _, a in pairs(g.bankAsks) do
		if a.requester == me and (a.status == "open" or a.status == "accepted") then open = open + 1 end
	end
	if open >= ASK_MAX_OPEN then return false, (L["Tienes %d peticiones abiertas: espera a que te entreguen alguna."]):format(open) end
	local rec = { id = ("%s:ask:%d:%d"):format(me, now, math.random(1000, 9999)), t = now, requester = me,
		item = math.floor(itemID), link = link, qty = qty, note = note ~= "" and note or nil,
		status = "open", rev = 1, by = me, updated = now }
	publishAsk(g, rec)
	LG:Print((L["Petición enviada a los oficiales: %s."]):format(askText(rec)))
	return true
end

-- Cambia el estado de una petición si el jugador puede.
function ns.SetBankAskStatus(id, status, extra)
	local g = LG:GuildData()
	local old = g and g.bankAsks[id]
	if not old then return false end
	local me, now = ns.PlayerFullName(), ns.Now()
	local rec = {}
	for k, v in pairs(old) do rec[k] = v end
	for k, v in pairs(extra or {}) do rec[k] = v end
	if status == "accepted" and not old.officer then rec.officer, rec.acceptedAt = me, now end
	rec.status, rec.rev, rec.by, rec.updated = status, old.rev + 1, me, now
	if not authorized(rec, status, me) then return false end
	publishAsk(g, rec)
	return true
end

-- ¿La retiró ya el oficial? Lo dice el registro del banco: sus retiradas de ese objeto
-- desde que la cogió (con una hora de margen, que el registro va por horas).
function ns.BankAskWithdrawn(g, a)
	if not a.officer or not a.acceptedAt then return false end
	local got, last = 0, nil
	for _, d in pairs(g.bankLog or {}) do
		if d.kind == "itemOut" and d.item == a.item and d.member == a.officer and d.t >= a.acceptedAt - 3600 then
			got = got + d.amount
			last = math.max(last or 0, d.t)
		end
	end
	return got >= a.qty, last
end

-- Peticiones para la interfaz: las que esperan oficial, las mías y las cerradas recientes.
function ns.BankAskLists()
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	local out = { pending = {}, mine = {}, handling = {}, closed = {} }
	if not g then return out end
	for _, a in pairs(g.bankAsks) do
		local active = a.status == "open" or a.status == "accepted"
		if active and a.status == "open" and canDeliver(me) and a.requester ~= me then out.pending[#out.pending + 1] = a end
		if active and a.officer == me then out.handling[#out.handling + 1] = a end
		if active and a.requester == me then out.mine[#out.mine + 1] = a end
		if not active then out.closed[#out.closed + 1] = a end
	end
	for _, list in pairs(out) do table.sort(list, function(x, y) return (x.updated or x.t) > (y.updated or y.t) end) end
	return out
end

-- Entregas en el intercambio (lo llama Orders al cerrarse uno).
function ns.CheckBankAskDeliveries(partner, give, get)
	local g = LG:GuildData()
	if not g or not partner then return end
	local me = ns.PlayerFullName()
	for id, a in pairs(g.bankAsks) do
		if a.status == "accepted" then
			local gave = a.officer == me and ns.SameName(a.requester, partner) and give and give[a.item]
			local got = a.requester == me and ns.SameName(a.officer, partner) and get and get[a.item]
			if gave or got then ns.SetBankAskStatus(id, "done", { auto = "trade" }) end
		end
	end
end

function ns.PruneBankAsks(g)
	local now = ns.Now()
	for id, a in pairs(g.bankAsks or {}) do
		if a.status ~= "open" and a.status ~= "accepted" and now - (a.updated or a.t) > ASK_KEEP then g.bankAsks[id] = nil end
	end
end
