-- Aportaciones al banco de la hermandad del juego (objetos y oro).
--
-- Cuando alguien con el addon abre el banco, se leen sus registros (los últimos
-- movimientos de cada pestaña y los del dinero) y se comparten los depósitos y
-- las retiradas (BANK). El oro da reputación de hermandad (lo neto: lo que
-- metes menos lo que sacas, con tope semanal), nunca insignias. Los objetos
-- sueltos solo salen en el ranking; los que pide un pedido del banco (BANKREQ)
-- cobran la recompensa del pedido, que sale del cofre de hermandad.
--
-- El juego da la antigüedad de cada movimiento en años, meses, días y horas, así
-- que el momento es aproximado (a la hora); el mismo depósito leído por dos
-- personas en horas distintas se reconoce por quién, qué y cuánto, con una hora
-- de margen.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Bank = LG:NewModule("GuildBank", "AceEvent-3.0", "AceTimer-3.0")

local HOUR = 3600
local KEEP = 90 * 86400        -- se guardan 90 días
ns.BANK_REP = {
	item = 2,                  -- por cada depósito de objetos
	perGold = 1,               -- por cada moneda de oro depositada...
	maxGold = 10,              -- ...hasta 10 por depósito
	weekCap = 50,              -- y como mucho 50 a la semana
}

-- Hora aproximada de un movimiento a partir de su antigüedad.
local function hourOf(now, years, months, days, hours)
	local ago = (((tonumber(years) or 0) * 365 + (tonumber(months) or 0) * 30 + (tonumber(days) or 0)) * 24 + (tonumber(hours) or 0))
	return math.floor(now / HOUR) - ago
end

-- Firma de un depósito: quién, qué y cuánto (sin la hora, que varía según cuándo se lea).
local function sigOf(rec)
	return ("%s|%s|%s|%d"):format(rec.member, rec.kind, tostring(rec.item or 0), rec.amount)
end

local function valid(rec)
	if type(rec) ~= "table" or type(rec.member) ~= "string" or type(rec.hour) ~= "number" then return false end
	-- item / money: depósitos; itemOut / moneyOut: retiradas (para contar lo neto).
	if rec.kind ~= "item" and rec.kind ~= "money" and rec.kind ~= "itemOut" and rec.kind ~= "moneyOut" then return false end
	if type(rec.amount) ~= "number" or rec.amount < 1 or rec.amount ~= math.floor(rec.amount) then return false end
	if (rec.kind == "money" or rec.kind == "moneyOut") and rec.amount > 1e9 then return false end
	if (rec.kind == "item" or rec.kind == "itemOut") and (type(rec.item) ~= "number" or rec.amount > 1000) then return false end
	return true
end

---------------------------------------------------------------------------
-- Datos
---------------------------------------------------------------------------

-- Junta una lectura del registro (la propia o la de otro) con lo guardado. Cada
-- depósito leído se empareja con uno guardado de la misma firma a una hora o
-- menos; los que sobran son nuevos. Así dos depósitos iguales seguidos cuentan
-- dos veces, y el mismo leído por otro una hora más tarde, una sola.
function ns.AbsorbBankDeposits(g, list, sender)
	local stored = {}
	for key, d in pairs(g.bankLog) do
		local sig = sigOf(d)
		stored[sig] = stored[sig] or {}
		table.insert(stored[sig], { hour = d.hour })
	end
	local incoming = {}
	for _, rec in ipairs(type(list) == "table" and list or {}) do
		-- Solo de quien tiene el addon y ha aceptado compartir (tiene ficha en la hermandad):
		-- los movimientos de los demás no se copian ni se reparten.
		if valid(rec) and (not sender or rec.by == sender) and g.members[rec.member] then incoming[#incoming + 1] = rec end
	end
	table.sort(incoming, function(x, y) return x.hour < y.hour end)
	local added = 0
	for _, rec in ipairs(incoming) do
		local sig = sigOf(rec)
		local best
		for _, st in ipairs(stored[sig] or {}) do
			local diff = math.abs(st.hour - rec.hour)
			if not st.used and diff <= 1 and (not best or diff < math.abs(best.hour - rec.hour)) then best = st end
		end
		if best then
			best.used = true
		else
			local n = 1
			while g.bankLog[("%s|%d|%d"):format(sig, rec.hour, n)] do n = n + 1 end
			g.bankLog[("%s|%d|%d"):format(sig, rec.hour, n)] = { member = rec.member, kind = rec.kind, item = rec.item, amount = rec.amount,
				hour = rec.hour, t = rec.hour * HOUR, by = rec.by,
				link = rec.kind == "item" and type(rec.link) == "string" and rec.link:sub(1, 200) or nil }
			stored[sig] = stored[sig] or {}
			table.insert(stored[sig], { hour = rec.hour, used = true })
			added = added + 1
		end
	end
	return added
end

-- Un depósito suelto (pruebas).
function ns.MergeBankDeposit(g, rec, sender)
	return ns.AbsorbBankDeposits(g, { rec }, sender) > 0
end

-- Llega la lectura entera de otro miembro.
ns.handlers.BANK = function(sender, list)
	local g = LG:GuildData()
	if g and ns.AbsorbBankDeposits(g, list, sender) > 0 then LG:DataChanged() end
end

function ns.PruneBankLog(g)
	local now = ns.Now()
	for key, d in pairs(g.bankLog or {}) do
		if now - (d.t or 0) > KEEP or not g.members[d.member] then g.bankLog[key] = nil end
	end
end

-- Aportaciones por miembro: { { name, gold (en cobre), items, deposits } }, de más a menos oro.
function ns.BankDonors()
	local g = LG:GuildData()
	local by, list = {}, {}
	for _, d in pairs(g and g.bankLog or {}) do
		if (d.kind == "item" or d.kind == "money") and g.members[d.member] then -- solo depósitos, de quien comparte
			local e = by[d.member]
			if not e then
				e = { name = d.member, gold = 0, items = 0, deposits = 0 }
				by[d.member] = e
				list[#list + 1] = e
			end
			e.deposits = e.deposits + 1
			if d.kind == "money" then e.gold = e.gold + d.amount else e.items = e.items + d.amount end
		end
	end
	table.sort(list, function(a, b)
		if a.gold ~= b.gold then return a.gold > b.gold end
		return a.items > b.items
	end)
	return list
end

-- Últimos depósitos, para el historial.
function ns.BankRecent(max)
	local g = LG:GuildData()
	local list = {}
	for _, d in pairs(g and g.bankLog or {}) do
		if d.kind == "item" or d.kind == "money" then list[#list + 1] = d end
	end
	table.sort(list, function(a, b) return a.t > b.t end)
	for i = #list, (max or 10) + 1, -1 do list[i] = nil end
	return list
end

-- Cobre a texto con los iconos de las monedas, sin las partes a cero: "12[o] 30[p]".
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
function ns.MoneyText(copper)
	copper = math.max(0, math.floor(tonumber(copper) or 0))
	local gold, silver, cop = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
	local parts = {}
	if gold > 0 then parts[#parts + 1] = gold .. COIN:format("Gold") end
	if silver > 0 then parts[#parts + 1] = silver .. COIN:format("Silver") end
	if cop > 0 or #parts == 0 then parts[#parts + 1] = cop .. COIN:format("Copper") end
	return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Pedidos del banco: un oficial (o un maestro artesano) pide un objeto y una
-- cantidad, con una recompensa en insignias que sale del cofre. Quien deposita
-- ese objeto mientras está abierto cobra su parte (lo neto: depósitos menos
-- retiradas), hasta completar la cantidad.
---------------------------------------------------------------------------

local REQUEST_DAYS = 14
local ARTISAN_MAX_OPEN, ARTISAN_MAX_REWARD = 2, 30
ns.BANK_REQUEST = { days = REQUEST_DAYS, artisanOpen = ARTISAN_MAX_OPEN, artisanReward = ARTISAN_MAX_REWARD }

-- ¿Puede pedir? Por rango (permiso «Pedidos del banco») o por la medalla de Artesano de oro.
function ns.CanRequestBank(name, reward)
	if ns.Can("bankRequests", name) then return true end
	return ns.MedalTier and ns.MedalTier(name, "artisan") == 3 and (reward == nil or reward <= ARTISAN_MAX_REWARD) or false
end

function ns.MergeBankRequest(g, rec, sender)
	if type(rec) ~= "table" or type(rec.id) ~= "string" or type(rec.rev) ~= "number" or type(rec.creator) ~= "string" then return false end
	if type(rec.item) ~= "number" or type(rec.t) ~= "number" or type(rec.ends) ~= "number" or rec.ends <= rec.t or rec.ends > rec.t + 31 * 86400 then return false end
	if type(rec.qty) ~= "number" or rec.qty < 1 or rec.qty > 10000 or rec.qty ~= math.floor(rec.qty) then return false end
	if type(rec.reward) ~= "number" or rec.reward < 0 or rec.reward > 10000 or rec.reward ~= math.floor(rec.reward) then return false end
	if rec.status ~= "open" and rec.status ~= "cancelled" then return false end
	if sender and rec.by ~= sender then return false end
	local old = g.bankRequests[rec.id]
	if old then
		if old.rev >= rec.rev then return false end
		if old.item ~= rec.item or old.qty ~= rec.qty or old.reward ~= rec.reward or old.creator ~= rec.creator or old.t ~= rec.t then return false end
		if rec.by ~= rec.creator and not ns.Can("bankRequests", rec.by) then return false end
	elseif rec.by ~= rec.creator or not ns.CanRequestBank(rec.creator, rec.reward) then
		return false
	end
	g.bankRequests[rec.id] = { id = rec.id, rev = rec.rev, item = rec.item, qty = rec.qty, reward = rec.reward, creator = rec.creator,
		by = rec.by, t = rec.t, ends = rec.ends, status = rec.status, cancelledAt = tonumber(rec.cancelledAt),
		link = type(rec.link) == "string" and rec.link:sub(1, 200) or nil }
	return true, old
end

ns.handlers.BANKREQ = function(sender, rec)
	local g = LG:GuildData()
	if not g then return end
	local changed, old = ns.MergeBankRequest(g, rec, sender)
	if not changed then return end
	if not old and rec.status == "open" then
		LG:Print((L["Pedido del banco: %s x%d (%d insignias del cofre). Deposítalo en el banco de la hermandad."]):format(rec.link or "?", rec.qty, rec.reward))
	end
	LG:DataChanged()
end

-- Reparto de los pedidos, solo con datos (no depende de las insignias, así que Merits y el cofre
-- lo pueden usar sin dar vueltas): { allocs = { { t, member, units, insignias, req } }, byReq = { [id] = { delivered, doneAt } } }.
function ns.BankRequestAllocations(g)
	local out = { allocs = {}, byReq = {} }
	if not g then return out end
	for id, r in pairs(g.bankRequests or {}) do
		local from = math.floor(r.t / HOUR) * HOUR
		local to = math.min(r.ends, r.status == "cancelled" and (r.cancelledAt or r.t) or r.ends)
		local per = {}
		for _, d in pairs(g.bankLog) do
			if d.item == r.item and d.t >= from and d.t <= to and (d.kind == "item" or d.kind == "itemOut") then
				local e = per[d.member]
				if not e then
					e = { member = d.member, net = 0 }
					per[d.member] = e
				end
				if d.kind == "item" then
					e.net = e.net + d.amount
					e.first = math.min(e.first or d.t, d.t)
					e.last = math.max(e.last or d.t, d.t)
				else
					e.net = e.net - d.amount
				end
			end
		end
		local order = {}
		for _, e in pairs(per) do
			if e.first and e.net > 0 then order[#order + 1] = e end
		end
		table.sort(order, function(a, b)
			if a.first ~= b.first then return a.first < b.first end
			return a.member < b.member
		end)
		local remaining, st = r.qty, { delivered = 0 }
		for _, e in ipairs(order) do
			local units = math.min(e.net, remaining)
			if units > 0 then
				remaining = remaining - units
				st.delivered = st.delivered + units
				out.allocs[#out.allocs + 1] = { t = e.last, member = e.member, units = units,
					insignias = math.floor(r.reward * units / r.qty), req = r }
				if remaining == 0 then st.doneAt = e.last end
			end
		end
		out.byReq[id] = st
	end
	table.sort(out.allocs, function(a, b) return a.t < b.t end)
	return out
end

-- Fase de un pedido: "open", "done", "expired" o "cancelled".
function ns.BankRequestPhase(r, st)
	if st and st.doneAt then return "done" end
	if r.status == "cancelled" then return "cancelled" end
	if ns.Now() > r.ends then return "expired" end
	return "open"
end

-- Pedidos para la interfaz: abiertos (los que caducan antes primero) y terminados recientes.
function ns.BankRequestLists()
	local g = LG:GuildData()
	local open, closed = {}, {}
	if not g then return open, closed end
	local alloc = ns.BankRequestAllocations(g)
	for id, r in pairs(g.bankRequests) do
		local st = alloc.byReq[id] or { delivered = 0 }
		local item = { r = r, delivered = st.delivered, phase = ns.BankRequestPhase(r, st), doneAt = st.doneAt }
		if item.phase == "open" then open[#open + 1] = item else closed[#closed + 1] = item end
	end
	table.sort(open, function(a, b) return a.r.ends < b.r.ends end)
	table.sort(closed, function(a, b) return (a.doneAt or a.r.ends) > (b.doneAt or b.r.ends) end)
	return open, closed
end

-- Insignias del cofre apartadas para los pedidos abiertos (lo que aún no se ha pagado).
function ns.BankRequestsReserved()
	local reserved = 0
	local g = LG:GuildData()
	if not g then return 0 end
	local alloc = ns.BankRequestAllocations(g)
	local paid = {}
	for _, a in ipairs(alloc.allocs) do paid[a.req.id] = (paid[a.req.id] or 0) + a.insignias end
	for id, r in pairs(g.bankRequests) do
		if ns.BankRequestPhase(r, alloc.byReq[id]) == "open" then reserved = reserved + math.max(0, r.reward - (paid[id] or 0)) end
	end
	return reserved
end

-- Un objeto escrito (enlace, nombre o número) a id y enlace.
local function resolveItem(text)
	text = text and strtrim(text) or ""
	local id = tonumber(text:match("item:(%d+)")) or tonumber(text)
	local link = text:match("(|c%x+|Hitem:.-|h.-|h|r)") or text:match("(|Hitem:.-|h.-|h)")
	if not id and text ~= "" and GetItemInfo then
		local ok, _, l = pcall(GetItemInfo, text)
		if ok and type(l) == "string" then id, link = tonumber(l:match("item:(%d+)")), l end
	end
	if id and not link and GetItemInfo then
		local ok, _, l = pcall(GetItemInfo, id)
		if ok and type(l) == "string" then link = l end
	end
	return id, link
end

function ns.CreateBankRequest(itemText, qty, reward)
	local g = LG:GuildData()
	local me = ns.PlayerFullName()
	if not g then return false, L["No estás en una hermandad."] end
	qty, reward = math.floor(tonumber(qty) or 0), math.floor(tonumber(reward) or 0)
	if not ns.CanRequestBank(me) then return false, L["Tu rango no puede hacer pedidos del banco."] end
	if not ns.Can("bankRequests", me) then
		if reward > ARTISAN_MAX_REWARD then return false, (L["Como maestro artesano, la recompensa es de %d insignias como mucho."]):format(ARTISAN_MAX_REWARD) end
		local mine = 0
		for _, item in ipairs((ns.BankRequestLists())) do
			if item.r.creator == me then mine = mine + 1 end
		end
		if mine >= ARTISAN_MAX_OPEN then return false, (L["Como maestro artesano, %d pedidos abiertos como mucho."]):format(ARTISAN_MAX_OPEN) end
	end
	local id, link = resolveItem(itemText)
	if not id then return false, L["No encuentro ese objeto: haz mayúsculas + clic en él para ponerlo."] end
	if qty < 1 or qty > 10000 then return false, L["Pon una cantidad."] end
	local free = ns.ChestState().balance - ns.BankRequestsReserved()
	if reward > free then return false, (L["En el cofre hay %d insignias libres para recompensas."]):format(math.max(0, free)) end
	local now = ns.Now()
	local rec = { id = ("%s:req:%d:%d"):format(me, now, math.random(1000, 9999)), rev = 1, item = id, link = link, qty = qty, reward = reward,
		creator = me, by = me, t = now, ends = now + REQUEST_DAYS * 86400, status = "open" }
	ns.MergeBankRequest(g, rec)
	LG:Send("BANKREQ", rec)
	LG:DataChanged()
	LG:Print((L["Pedido publicado: %s x%d, %d insignias del cofre. La hermandad ha recibido el aviso."]):format(link or "?", qty, reward))
	ns.GuildAnnounce((L["Pedido del banco: %s x%d. Recompensa: %d insignias. Deposítalo en el banco de la hermandad."]):format(link or "?", qty, reward))
	return true
end

function ns.CancelBankRequest(id)
	local g = LG:GuildData()
	local r = g and g.bankRequests[id]
	local me = ns.PlayerFullName()
	if not r or r.status ~= "open" or (r.creator ~= me and not ns.Can("bankRequests", me)) then return false end
	local rec = {}
	for k, v in pairs(r) do rec[k] = v end
	rec.rev, rec.by, rec.status, rec.cancelledAt = r.rev + 1, me, "cancelled", ns.Now()
	ns.MergeBankRequest(g, rec)
	LG:Send("BANKREQ", rec)
	LG:DataChanged()
	return true
end

---------------------------------------------------------------------------
-- Lectura de los registros del banco
---------------------------------------------------------------------------

-- Nombre del registro (puede venir sin reino) al nombre completo del miembro.
local function fullName(name)
	if type(name) ~= "string" or name == "" then return nil end
	return ns.FindMember(name) or ns.FullName(name)
end

function Bank:Read()
	local g = LG:GuildData()
	if not g or not LG:HasConsent() then return end
	local now, me = ns.Now(), ns.PlayerFullName()
	local found = {} -- todo lo leído: se comparte entero para que los demás emparejen igual
	local function add(rec)
		if rec.member and valid(rec) then found[#found + 1] = rec end
	end
	local tabs = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
	for tab = 1, tabs do
		local n = GetNumGuildBankTransactions and GetNumGuildBankTransactions(tab) or 0
		for i = 1, n do
			local ok, kind, name, link, count, _, _, y, mo, d, h = pcall(GetGuildBankTransaction, tab, i)
			local itemID = ok and type(link) == "string" and tonumber(link:match("item:(%d+)"))
			if ok and (kind == "deposit" or kind == "withdraw") and itemID then
				add({ member = fullName(name), kind = kind == "deposit" and "item" or "itemOut", item = itemID, link = link,
					amount = tonumber(count) or 1, hour = hourOf(now, y, mo, d, h), by = me })
			end
		end
	end
	local n = GetNumGuildBankMoneyTransactions and GetNumGuildBankMoneyTransactions() or 0
	for i = 1, n do
		local ok, kind, name, amount, y, mo, d, h = pcall(GetGuildBankMoneyTransaction, i)
		if ok and (kind == "deposit" or kind == "withdraw") and tonumber(amount) and amount > 0 then
			add({ member = fullName(name), kind = kind == "deposit" and "money" or "moneyOut", amount = math.floor(amount),
				hour = hourOf(now, y, mo, d, h), by = me })
		end
	end
	if ns.AbsorbBankDeposits(g, found) > 0 then
		LG:Send("BANK", found)
		LG:DataChanged()
	end
end

-- Pide al juego los registros (cada pestaña y el del dinero); llegan con GUILDBANKLOG_UPDATE.
local function queryLogs()
	if not QueryGuildBankLog then return end
	local tabs = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
	for tab = 1, tabs do pcall(QueryGuildBankLog, tab) end
	pcall(QueryGuildBankLog, (MAX_GUILDBANK_TABS or 8) + 1) -- el registro del dinero
end

function Bank:Opened()
	queryLogs()
	-- Los registros tardan en llegar: se leen ahora y otra vez un poco después.
	self:ScheduleTimer("Read", 3)
	self:ScheduleTimer("Read", 10)
end

function Bank:OnEnable()
	if not GetNumGuildBankTabs then return end -- sin banco de hermandad en este cliente
	-- Clientes modernos: abrir el banco es una «interacción» (PLAYER_INTERACTION_MANAGER_FRAME_SHOW,
	-- tipo GuildBanker = 10); los antiguos tenían GUILDBANKFRAME_OPENED. pcall: si un evento no
	-- existe en este cliente, el resto del addon sigue.
	local guildBanker = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker or 10
	pcall(ns.RegisterEvent, self, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
		if kind == guildBanker then self:Opened() end
	end)
	pcall(ns.RegisterEvent, self, "GUILDBANKFRAME_OPENED", function() self:Opened() end)
	-- Un depósito con el banco abierto: se vuelve a pedir el registro.
	pcall(ns.RegisterEvent, self, "GUILDBANK_UPDATE_MONEY", function() self:Opened() end)
	pcall(ns.RegisterEvent, self, "GUILDBANKBAGSLOTS_CHANGED", function()
		if self.slotsTimer then return end
		self.slotsTimer = self:ScheduleTimer(function() self.slotsTimer = nil; self:Opened() end, 2)
	end)
	pcall(ns.RegisterEvent, self, "GUILDBANKLOG_UPDATE", function()
		if self.readTimer then return end
		self.readTimer = self:ScheduleTimer(function() self.readTimer = nil; self:Read() end, 1)
	end)
end

-- Diagnóstico con el banco abierto: /gmk dump LantuxGuild_Bank() (la primera vez pide
-- los registros; repetirlo a los pocos segundos para ver lo que ha llegado).
function LantuxGuild_Bank()
	queryLogs()
	local parts = {}
	local tabs = GetNumGuildBankTabs and GetNumGuildBankTabs() or "sin API"
	parts[#parts + 1] = ("tabs=%s maxTabs=%s"):format(tostring(tabs), tostring(MAX_GUILDBANK_TABS))
	for tab = 1, tonumber(tabs) or 0 do
		local ok, n = pcall(GetNumGuildBankTransactions, tab)
		parts[#parts + 1] = ("tab%d=%s"):format(tab, tostring(ok and n or "error"))
	end
	local ok, n = pcall(GetNumGuildBankMoneyTransactions)
	parts[#parts + 1] = "money=" .. tostring(ok and n or "error")
	if ok and (n or 0) > 0 then
		parts[#parts + 1] = "last=" .. ns.DeepDescribe({ GetGuildBankMoneyTransaction(n) }, 2)
	end
	local g = LG:GuildData()
	local saved = 0
	for _ in pairs(g and g.bankLog or {}) do saved = saved + 1 end
	parts[#parts + 1] = "guardados=" .. saved
	return table.concat(parts, " || ")
end

function ns.ReadGuildBank() Bank:Read() end -- para las pruebas
