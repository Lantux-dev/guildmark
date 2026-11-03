-- Sección Banco: el contenido del banco de la hermandad como se ve en el juego (cuadrícula
-- de 14 x 7 huecos con las pestañas a la derecha), las peticiones para sacar algo, los
-- pedidos de depósito y el registro de aportaciones.
--
-- Las filas genéricas las pinta MainFrame; aquí van las vistas y la cuadrícula (fila
-- kind = "bankgrid"). Las piezas de MainFrame llegan por ns.RowKit.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local SLOT, GAP, PAIR_GAP = 36, 4, 6   -- hueco, separación y aire entre parejas de columnas (como en el juego)
local COLS, ROWS = 14, 7
local TAB_SIZE, TAB_GAP = 34, 4
local GRID_TOP = 30                    -- debajo del título de la pestaña
local GRID_W = COLS * (SLOT + GAP) + 6 * PAIR_GAP
local GRID_H = ROWS * (SLOT + GAP)
ns.BANKGRID_HEIGHT = GRID_TOP + GRID_H + 34

local selectedTab -- pestaña elegida en la vista (número del banco)

local function K() return ns.RowKit end

local function ago(t)
	if not t then return "?" end
	return (L["hace %s"]):format(ns.FormatDuration(math.max(60, ns.Now() - t)))
end

---------------------------------------------------------------------------
-- Cuadrícula (fila "bankgrid")
---------------------------------------------------------------------------

local function slotPosition(i)
	-- El juego numera por columnas: hueco 1-7 en la primera columna, 8-14 en la segunda...
	local col, row = math.floor((i - 1) / ROWS), (i - 1) % ROWS
	return col * (SLOT + GAP) + math.floor(col / 2) * PAIR_GAP, -GRID_TOP - row * (SLOT + GAP)
end

local function edgeBorder(parent, size, layer)
	local edges = {}
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
		local t = parent:CreateTexture(nil, layer or "OVERLAY")
		t:SetPoint(side[1])
		t:SetPoint(side[2])
		if side[3] then t:SetHeight(size) else t:SetWidth(size) end
		edges[#edges + 1] = t
	end
	return edges
end

local function setEdges(edges, r, g, b, a)
	for _, e in ipairs(edges) do e:SetColorTexture(r, g, b, a or 1) end
end

function ns.CreateBankGrid(row)
	local grid = CreateFrame("Frame", nil, row)
	grid:SetPoint("TOPLEFT", row, "TOPLEFT", 6, 0)
	grid:SetSize(GRID_W + 16 + TAB_SIZE + 8, ns.BANKGRID_HEIGHT)

	-- Fondo de piedra oscura con borde, como el marco del banco.
	grid.bg = grid:CreateTexture(nil, "BACKGROUND")
	grid.bg:SetPoint("TOPLEFT", -6, 4)
	grid.bg:SetSize(GRID_W + 12, ns.BANKGRID_HEIGHT - 2)
	grid.bg:SetColorTexture(0.07, 0.06, 0.05, 0.92)
	local frameEdge = CreateFrame("Frame", nil, grid)
	frameEdge:SetAllPoints(grid.bg)
	setEdges(edgeBorder(frameEdge, 2, "BORDER"), 0.45, 0.36, 0.2, 1)

	grid.title = grid:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	grid.title:SetPoint("TOPLEFT", 2, -4)
	grid.stamp = grid:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	grid.stamp:SetPoint("TOPRIGHT", grid, "TOPLEFT", GRID_W, -9)
	grid.money = grid:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	grid.money:SetPoint("TOPRIGHT", grid, "TOPLEFT", GRID_W, -GRID_TOP - GRID_H - 8)
	grid.moneyLabel = grid:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	grid.moneyLabel:SetPoint("RIGHT", grid.money, "LEFT", -8, 0)
	grid.moneyLabel:SetText(L["Oro del banco:"])
	grid.hint = grid:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	grid.hint:SetPoint("TOPLEFT", 2, -GRID_TOP - GRID_H - 10)
	grid.hint:SetText(L["Clic en un objeto para pedirlo a los oficiales."])

	-- Separadores verticales entre parejas de columnas (como las rejillas del juego).
	for p = 1, 6 do
		local x = p * 2 * (SLOT + GAP) + (p - 1) * PAIR_GAP + PAIR_GAP / 2 - GAP / 2
		local sep = grid:CreateTexture(nil, "BORDER")
		sep:SetColorTexture(0.3, 0.24, 0.14, 0.6)
		sep:SetSize(1, GRID_H - GAP)
		sep:SetPoint("TOPLEFT", x, -GRID_TOP)
	end

	grid.slots = {}
	for i = 1, COLS * ROWS do
		local b = CreateFrame("Button", nil, grid)
		b:SetSize(SLOT, SLOT)
		b:SetPoint("TOPLEFT", slotPosition(i))
		b.empty = b:CreateTexture(nil, "BACKGROUND")
		b.empty:SetAllPoints()
		b.empty:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
		b.empty:SetTexCoord(0.14, 0.86, 0.14, 0.86)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetPoint("TOPLEFT", 1, -1)
		b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		b.edges = edgeBorder(b, 1)
		b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		b.count:SetPoint("BOTTOMRIGHT", -2, 2)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b:SetScript("OnEnter", function(self)
			if not self.data then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, self.data.l or ("item:" .. self.data.id))
			if not ok then GameTooltip:SetText(("item:%d"):format(self.data.id)) end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(L["Clic: pedirlo a los oficiales"], 0.2, 1, 0.2)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:SetScript("OnClick", function(self)
			if self.data and grid.onItem then grid.onItem(self.data) end
		end)
		grid.slots[i] = b
	end

	-- Pestañas a la derecha, de arriba abajo.
	grid.tabs = {}
	for n = 1, 8 do
		local t = CreateFrame("Button", nil, grid)
		t:SetSize(TAB_SIZE, TAB_SIZE)
		t:SetPoint("TOPLEFT", grid, "TOPLEFT", GRID_W + 18, -GRID_TOP - (n - 1) * (TAB_SIZE + TAB_GAP))
		t.bg = t:CreateTexture(nil, "BACKGROUND")
		t.bg:SetPoint("TOPLEFT", -3, 3)
		t.bg:SetPoint("BOTTOMRIGHT", 3, -3)
		t.icon = t:CreateTexture(nil, "ARTWORK")
		t.icon:SetAllPoints()
		t.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		t:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		t:SetScript("OnEnter", function(self)
			if not self.tab then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tab.name)
			GameTooltip:AddLine((L["Actualizada %s por %s"]):format(ago(self.tab.t), ns.ShortName(self.tab.by) or "?"), 1, 1, 1)
			GameTooltip:Show()
		end)
		t:SetScript("OnLeave", function() GameTooltip:Hide() end)
		t:SetScript("OnClick", function(self)
			if self.tab and grid.onSelect then grid.onSelect(self.tab.n) end
		end)
		grid.tabs[n] = t
	end
	row.bankGrid = grid
	return grid
end

-- Pinta la pestaña elegida y las pestañas visibles. spec: { tabs, selected, query, money, onSelect, onItem }
function ns.LayoutBankGrid(row, spec)
	local grid = row.bankGrid or ns.CreateBankGrid(row)
	grid:Show()
	grid.onSelect, grid.onItem = spec.onSelect, spec.onItem
	local current
	for _, tab in ipairs(spec.tabs) do
		if tab.n == spec.selected then current = tab end
	end
	current = current or spec.tabs[1]
	for i, t in ipairs(grid.tabs) do
		local tab = spec.tabs[i]
		t.tab = tab
		t:SetShown(tab ~= nil)
		if tab then
			t.icon:SetTexture(tab.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			local on = current and tab.n == current.n
			t.bg:SetColorTexture(on and 1 or 0.3, on and 0.82 or 0.24, on and 0.2 or 0.14, 1)
			t.icon:SetDesaturated(not on)
			t.icon:SetAlpha(on and 1 or 0.75)
		end
	end
	grid.title:SetText(current and current.name or "")
	grid.stamp:SetText(current and (L["Actualizada %s por %s"]):format(ago(current.t), ns.ShortName(current.by) or "?") or "")
	grid.money:SetText(spec.money and ns.MoneyText(spec.money) or "?")
	local query = (spec.query or ""):lower()
	for i, b in ipairs(grid.slots) do
		local data = current and current.slots[i]
		b.data = data
		b.icon:SetShown(data ~= nil)
		b.count:SetShown(data ~= nil and data.n > 1)
		if data then
			local icon = ns.RowKit.itemIcon(data.id)
			b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			b.count:SetText(data.n)
			local c = ns.RowKit.qualityColor(data.id)
			if c then setEdges(b.edges, c[1], c[2], c[3], 0.9) else setEdges(b.edges, 0, 0, 0, 0) end
			-- Búsqueda: lo que no coincide se apaga.
			local match = true
			if query ~= "" then
				local name = ns.GetItemInfo and ns.GetItemInfo(data.l or data.id)
				match = type(name) == "string" and name:lower():find(query, 1, true) ~= nil
			end
			b:SetAlpha(match and 1 or 0.2)
		else
			setEdges(b.edges, 0, 0, 0, 0)
			b:SetAlpha(1)
		end
	end
end

---------------------------------------------------------------------------
-- Vistas
---------------------------------------------------------------------------

function ns.BankSegments()
	local lists = ns.BankAskLists()
	local n = #lists.pending
	return {
		{ key = "contents", label = L["Contenido"] },
		{ key = "asks", label = n > 0 and (L["Peticiones"] .. " (" .. n .. ")") or L["Peticiones"] },
		{ key = "requests", label = L["Pedidos de depósito"] },
		{ key = "log", label = L["Registro"] },
	}
end

local function askItem(data)
	local link = data.l
	if not link and ns.GetItemInfo then
		local ok, _, l = pcall(ns.GetItemInfo, data.id)
		if ok and type(l) == "string" then link = l end
	end
	local have = ns.BankItemCount(data.id)
	ns.ShowInputDialog({
		title = L["Pedir del banco"],
		text = (L["%s (hay %d en el banco). La petición llega a quien pueda entregar objetos del banco."]):format(ns.BankItemLink(data.id, link), have),
		submit = L["Pedir"],
		fields = {
			{ key = "qty", label = L["Cantidad"], width = 60, numeric = true, default = math.min(have > 0 and have or 1, data.n or 1) },
			{ key = "note", label = L["Nota"], width = 240, maxLetters = 80 },
		},
		onSubmit = function(v)
			local ok, err = ns.CreateBankAsk(data.id, link, v.qty, v.note or "")
			if not ok then return err end
		end,
	})
end

local function contentsView(g, rows)
	local k = K()
	local tabs = ns.BankTabs()
	rows.search = L["Buscar objeto..."]
	k.header(rows, L["Banco de la hermandad"])
	if #tabs == 0 then
		k.line(rows, k.grey(L["Todavía no hay foto del banco. Se hace sola cuando alguien con el addon abre el banco de la hermandad en el juego."]), 1, { tall = true })
		return
	end
	local found = false
	for _, t in ipairs(tabs) do if t.n == selectedTab then found = true end end
	if not found then selectedTab = tabs[1].n end
	rows[#rows + 1] = {
		kind = "bankgrid", tabs = tabs, selected = selectedTab, query = k.search(),
		money = g.bankSnap and g.bankSnap.money and g.bankSnap.money.amount,
		onSelect = function(n) selectedTab = n; k.refresh() end,
		onItem = askItem,
	}
	k.line(rows, k.grey(L["Es una foto: se actualiza cada vez que alguien con el addon abre el banco. Cada pestaña dice cuándo y quién."]), 1)
end

local STATUS = {
	open = { "|cffffd100", L["esperando oficial"] },
	accepted = { "|cff69ccf0", L["en manos de %s"] },
	done = { "|cff1eff00", L["entregado"] },
	declined = { "|cffff6b5a", L["rechazado"] },
	cancelled = { "|cff9d9d9d", L["cancelado"] },
}

local function askCard(g, a, buttons)
	local k = K()
	local s = STATUS[a.status] or { "|cff9d9d9d", a.status }
	local label = a.status == "accepted" and s[2]:format(ns.ShortName(a.officer) or "?") or s[2]
	local foot = { date("%d/%m %H:%M", a.t), (L["la pide %s"]):format(ns.ShortName(a.requester) or "?") }
	if a.status == "accepted" then
		local withdrawn = ns.BankAskWithdrawn(g, a)
		foot[#foot + 1] = withdrawn and ("|cff1eff00" .. L["retirado del banco (registro)"] .. "|r") or L["aún sin retirar del banco"]
	end
	if a.status == "done" and a.auto == "trade" then foot[#foot + 1] = "|cff1eff00" .. L["verificado por intercambio"] .. "|r" end
	if a.note then foot[#foot + 1] = "\"" .. a.note .. "\"" end
	return {
		kind = "card", state = (a.status == "declined" or a.status == "cancelled") and "off" or "normal",
		accent = buttons and ns.ACCENT.action or (a.status == "done" and ns.ACCENT.good or nil),
		link = a.link or ("item:" .. a.item),
		icon = k.itemIcon(a.item) or "Interface\\Icons\\INV_Misc_QuestionMark", iconColor = k.qualityColor(a.item),
		title = ("%dx %s"):format(a.qty, ns.BankItemLink(a.item, a.link)),
		desc = (L["Banco › %s"]):format(ns.ShortName(a.requester) or "?"),
		status = s[1] .. label .. "|r",
		foot = k.grey(table.concat(foot, "  ·  ")),
		buttons = buttons,
	}
end

local function asksView(g, rows)
	local k = K()
	local me = ns.PlayerFullName()
	local lists = ns.BankAskLists()
	local deliver = ns.Can("bankDeliver", me)
	if deliver then
		k.header(rows, L["Esperando oficial"])
		if #lists.pending == 0 then k.line(rows, k.grey(L["Nadie ha pedido nada del banco."]), 1) end
		for _, a in ipairs(lists.pending) do
			rows[#rows + 1] = askCard(g, a, {
				{ label = L["Me encargo"], onClick = function() ns.SetBankAskStatus(a.id, "accepted") end },
				{ label = L["Rechazar"], onClick = function() ns.SetBankAskStatus(a.id, "declined") end },
			})
		end
		if #lists.handling > 0 then
			k.space(rows)
			k.header(rows, L["Me encargo yo"])
			k.line(rows, k.grey(L["Sácalo del banco y dáselo por intercambio (se marca solo) o por correo (márcalo tú)."]), 1)
			for _, a in ipairs(lists.handling) do
				rows[#rows + 1] = askCard(g, a, { { label = L["Entregado"], onClick = function() ns.SetBankAskStatus(a.id, "done") end } })
			end
		end
		k.space(rows)
	end
	k.header(rows, L["Mis peticiones"], { { label = L["Ver el banco"], onClick = function() ns.SelectSubview("bank", "contents") end } })
	if #lists.mine == 0 then k.line(rows, k.grey(L["No has pedido nada. En Contenido, clic en un objeto para pedirlo."]), 1) end
	for _, a in ipairs(lists.mine) do
		local buttons = { { label = L["Cancelar"], onClick = function() ns.SetBankAskStatus(a.id, "cancelled") end } }
		if a.status == "accepted" then table.insert(buttons, 1, { label = L["Recibido"], onClick = function() ns.SetBankAskStatus(a.id, "done") end }) end
		rows[#rows + 1] = askCard(g, a, buttons)
	end
	if #lists.closed > 0 then
		k.space(rows)
		k.header(rows, L["Cerradas"])
		for i = 1, math.min(8, #lists.closed) do rows[#rows + 1] = askCard(g, lists.closed[i], nil) end
	end
	if not deliver then
		k.space(rows)
		k.line(rows, k.grey(L["Las peticiones las atiende quien tenga el permiso «Entregar objetos del banco» (Ajustes › Rangos y permisos)."]), 1)
	end
end

function ns.BankView(g, rows, sub)
	if sub == "asks" then
		asksView(g, rows)
	elseif sub == "requests" then
		ns.BankRequestsView(g, rows)
	elseif sub == "log" then
		ns.BankLogView(g, rows)
	else
		contentsView(g, rows)
	end
end
