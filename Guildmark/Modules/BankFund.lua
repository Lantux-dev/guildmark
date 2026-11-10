-- Colecta de oro para abrir el banco de la hermandad.
--
-- El maestro de hermandad la crea (ajuste de hermandad "bankFund" = { goal, treasurer }):
-- cuánto oro hace falta y quién lo guarda. Los miembros le dan el oro al tesorero por
-- intercambio o por correo, y es el addon del tesorero el que lo apunta (FUNDGIFT):
-- nadie se apunta su propia donación, así que la barra es la misma para todos.
--   - Intercambio: cuenta si el otro pone oro y el tesorero no da nada (un pago o una
--     propina de un encargo llevan objetos del tesorero: esos no cuentan).
--   - Correo: cuenta al recoger el oro de una carta de un miembro (no las devueltas).
-- Cada aportación da reputación e insignias (Merits.lua), y quien aporta queda como
-- fundador del banco. El logro de hermandad «Las arcas» se cumple al llegar a la meta.
-- Lo que sobre de la meta se mete en el banco cuando exista. Un oficial puede anular
-- una aportación (por ejemplo, un pago que no era para la colecta).
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Fund = LG:NewModule("BankFund", "AceEvent-3.0")
ns.BankFundModule = Fund -- para las pruebas

ns.FUND_DEFAULT_GOAL = 100 * 10000      -- 100 de oro: la primera pestaña del banco
ns.FUND_REWARD = { rep = 2, merits = 2 } -- por cada moneda de oro aportada
local MAX_GIFT = 100000 * 10000          -- tope de cordura por aportación

---------------------------------------------------------------------------
-- Configuración y registros
---------------------------------------------------------------------------

-- La colecta configurada: { goal = cobre, treasurer = nombre } o nil.
function ns.BankFund()
	local f = ns.GuildSetting and ns.GuildSetting("bankFund")
	if type(f) ~= "table" or type(f.treasurer) ~= "string" or type(f.goal) ~= "number" or f.goal <= 0 then return nil end
	return f
end

function ns.ValidFundSetting(value)
	if value == nil then return true end
	return type(value) == "table" and type(value.treasurer) == "string" and type(value.goal) == "number"
		and value.goal > 0 and value.goal <= MAX_GIFT and value.goal == math.floor(value.goal)
end

-- Una aportación: la apunta el tesorero (by), por quién (member), cuánto (cobre) y cómo (via).
function ns.MergeFundGift(g, rec, sender)
	if type(rec) ~= "table" or type(rec.id) ~= "string" or type(rec.t) ~= "number" then return false end
	if type(rec.member) ~= "string" or type(rec.by) ~= "string" or rec.member == rec.by then return false end
	if type(rec.amount) ~= "number" or rec.amount < 1 or rec.amount > MAX_GIFT or rec.amount ~= math.floor(rec.amount) then return false end
	if rec.via ~= "trade" and rec.via ~= "mail" then return false end
	if sender and rec.by ~= sender then return false end
	g.fundGifts = g.fundGifts or {}
	if g.fundGifts[rec.id] then return false end
	g.fundGifts[rec.id] = { id = rec.id, t = rec.t, member = rec.member, amount = rec.amount, via = rec.via, by = rec.by }
	return true
end

ns.handlers.FUNDGIFT = function(sender, rec)
	local g = LG:GuildData()
	if g and ns.MergeFundGift(g, rec, sender) then LG:DataChanged() end
end

function ns.CountFundGifts(g)
	local n = 0
	for _ in pairs(g and g.fundGifts or {}) do n = n + 1 end
	return n
end

-- Quien entra recibe la colecta en el SYNC, pero contesta un solo miembro y puede tener
-- una versión sin colecta o no tenerla al día. El tesorero (y el maestro de hermandad),
-- si ven en el HELLO que a quien entra le faltan aportaciones, se las pasan por susurro.
function ns.OnFundHello(sender, data, rawSender)
	local g = LG:GuildData()
	local fund = ns.BankFund()
	local me = ns.PlayerFullName()
	if not g or not fund or type(data) ~= "table" or type(data.fundCount) ~= "number" then return end -- versiones sin colecta: nada
	if fund.treasurer ~= me and not ns.IsGuildMaster(me) then return end
	local setting = g.settings and g.settings.bankFund
	local lacksSetting = setting and (tonumber(data.fundSet) or 0) < (setting.t or 0)
	if data.fundCount >= ns.CountFundGifts(g) and not lacksSetting then return end
	-- El maestro solo si el tesorero no está conectado (si no, lo mandarían los dos).
	if fund.treasurer ~= me and ns.roster[fund.treasurer] and ns.roster[fund.treasurer].online then return end
	LG:ScheduleTimer(function()
		LG:Send("FUNDS", { setting = setting, gifts = g.fundGifts }, "WHISPER", rawSender or sender, "BULK")
	end, 3 + math.random() * 3)
end

ns.handlers.FUNDS = function(sender, data, distribution)
	local g = LG:GuildData()
	if not g or distribution ~= "WHISPER" or type(data) ~= "table" then return end
	local changed = false
	local s = data.setting
	if type(s) == "table" and type(s.t) == "number" then
		changed = ns.MergeSetting(g, { key = "bankFund", value = s.value, by = s.by, t = s.t }) or changed
	end
	for _, rec in pairs(type(data.gifts) == "table" and data.gifts or {}) do
		changed = ns.MergeFundGift(g, rec) or changed
	end
	if changed then LG:DataChanged() end
end

-- Cuenta si la apuntó el tesorero de la colecta o el maestro de hermandad, y no está anulada.
local function counts(g, gift, fund)
	if ns.IsVoided(g, gift.id) then return false end
	return gift.by == fund.treasurer or (ns.IsGuildMaster and ns.IsGuildMaster(gift.by))
end

-- Estado: { fund, total, goal, reachedAt, surplus, donors = { { name, amount, t } }, gifts = { ... } }.
function ns.BankFundState(g)
	g = g or LG:GuildData()
	local fund = ns.BankFund()
	local st = { fund = fund, total = 0, goal = fund and fund.goal or ns.FUND_DEFAULT_GOAL, donors = {}, gifts = {} }
	if not g then return st end
	for _, gift in pairs(g.fundGifts or {}) do
		if not fund or counts(g, gift, fund) then st.gifts[#st.gifts + 1] = gift end
	end
	table.sort(st.gifts, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.id < b.id end)
	local byName = {}
	for _, gift in ipairs(st.gifts) do
		st.total = st.total + gift.amount
		if not st.reachedAt and st.total >= st.goal then st.reachedAt = gift.t end
		local d = byName[gift.member]
		if not d then
			d = { name = gift.member, amount = 0, t = gift.t }
			byName[gift.member] = d
			st.donors[#st.donors + 1] = d
		end
		d.amount = d.amount + gift.amount
	end
	table.sort(st.donors, function(a, b) if a.amount ~= b.amount then return a.amount > b.amount end return a.t < b.t end)
	st.surplus = math.max(0, st.total - st.goal)
	return st
end

-- Fundador del banco: aportó algo a la colecta.
function ns.IsBankFounder(name)
	for _, d in ipairs(ns.BankFundState().donors) do
		if d.name == name then return true, d.amount end
	end
	return false
end

-- Entradas del libro de puntos (Merits.lua): reputación e insignias por cada oro aportado.
function ns.BankFundEntries(g)
	local out = {}
	if not ns.BankFund() then return out end
	for _, gift in ipairs(ns.BankFundState(g).gifts) do
		local gold = math.floor(gift.amount / 10000)
		if gold > 0 then
			out[#out + 1] = { t = gift.t, member = gift.member, gold = gold, amount = gift.amount,
				rep = gold * ns.FUND_REWARD.rep, merits = gold * ns.FUND_REWARD.merits }
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Acciones
---------------------------------------------------------------------------

function ns.SetBankFund(goalGold, treasurer)
	local me = ns.PlayerFullName()
	if not ns.IsGuildMaster(me) then
		LG:Print(L["Solo el maestro de hermandad puede crear la colecta."])
		return false
	end
	if goalGold == nil then
		ns.SetGuildSetting("bankFund", nil)
		return true
	end
	local goal = math.floor((tonumber(goalGold) or 0) * 10000)
	if goal <= 0 then return false, L["Pon cuánto oro hace falta."] end
	ns.SetGuildSetting("bankFund", { goal = goal, treasurer = treasurer or me })
	return true
end

local function record(member, amount, via)
	local g = LG:GuildData()
	local fund = ns.BankFund()
	local me = ns.PlayerFullName()
	if not g or not fund or fund.treasurer ~= me or not member or member == me then return end
	if not ns.roster[member] and not g.members[member] then return end -- solo miembros de la hermandad
	local now = ns.Now()
	local rec = { id = ("%s:fund:%s:%d:%s"):format(me, via, now, member), t = now, member = member, amount = amount, via = via, by = me }
	-- Dos aportaciones iguales en el mismo segundo: la segunda lleva otro id.
	local n = 1
	while g.fundGifts and g.fundGifts[rec.id] do
		n = n + 1
		rec.id = ("%s:fund:%s:%d:%s:%d"):format(me, via, now, member, n)
	end
	if not ns.MergeFundGift(g, rec) then return end
	LG:Send("FUNDGIFT", rec)
	LG:DataChanged()
	local st = ns.BankFundState(g)
	LG:Print((L["Colecta del banco: %s de %s (%s / %s)."]):format(ns.MoneyText(amount), ns.ShortName(member), ns.MoneyText(st.total), ns.MoneyText(st.goal)))
	if st.reachedAt == rec.t and ns.GuildAnnounce then
		ns.GuildAnnounce((L["¡Colecta completa! %s reunidos para abrir el banco de la hermandad. Gracias a los %d fundadores."]):format(ns.MoneyText(st.total), #st.donors))
	end
end
ns.RecordFundGift = record -- para las pruebas

-- Intercambio terminado (Orders.lua): oro del otro sin que el tesorero dé nada.
function ns.OnTradeComplete(t)
	if not t or not t.partner or (tonumber(t.getMoney) or 0) <= 0 then return end
	if (tonumber(t.giveMoney) or 0) > 0 or (t.give and next(t.give)) then return end
	record(t.partner, tonumber(t.getMoney), "trade")
end

-- Correo: se guarda quién manda cuánto en cada carta y se apunta al recoger el oro.
local inbox, taken = {}, {}

local function readInbox()
	wipe(inbox)
	local n = GetInboxNumItems and GetInboxNumItems() or 0
	for i = 1, n do
		local _, _, sender, subject, money, cod, daysLeft, _, _, wasReturned = GetInboxHeaderInfo(i)
		if sender and (money or 0) > 0 and (cod or 0) == 0 and not wasReturned then
			inbox[i] = { sender = ns.FullName(sender), money = money, key = ("%s|%d|%s|%s"):format(sender, money, subject or "", tostring(daysLeft)) }
		end
	end
end

local function tookMoney(index)
	local mail = inbox[index]
	if not mail then return end
	inbox[index] = nil
	-- La misma carta por dos caminos (recoger el oro y luego «recoger todo»): una vez.
	if taken[mail.key] and ns.Now() - taken[mail.key] < 120 then return end
	taken[mail.key] = ns.Now()
	record(mail.sender, mail.money, "mail")
end
ns.FundTookMailMoney = tookMoney -- para las pruebas
ns.FundReadInbox = readInbox

function Fund:OnEnable()
	pcall(ns.RegisterEvent, self, "MAIL_INBOX_UPDATE", readInbox)
	pcall(ns.RegisterEvent, self, "MAIL_SHOW", readInbox)
	if not self.hooked then
		self.hooked = true
		if type(TakeInboxMoney) == "function" then hooksecurefunc("TakeInboxMoney", tookMoney) end
		if type(AutoLootMailItem) == "function" then hooksecurefunc("AutoLootMailItem", tookMoney) end
	end
end
