-- Ventana de formulario genérica (la usan las herramientas de oficial).
--
-- ns.ShowInputDialog({
--   title = "Ajustar puntos",
--   fields = { { key = "name", label = "Nombre", width = 200, numeric = false, default = "" }, ... },
--   submit = "Aplicar",
--   onSubmit = function(values) return nil end, -- devuelve un texto de error para no cerrar
-- })
local _, ns = ...
local L = ns.L

local dialog
local MAX_FIELDS = 5
local ROW = 30
local PICK_ROW = 18
local PICK_VISIBLE = 10

---------------------------------------------------------------------------
-- Lista de opciones de un campo: desplegable (botón ▼) y autocompletado.
--   field.options = function() return { { label = "Grupo", items = { "A", "B" } }, ... } end
--   field.onPick = function(value, setField) end  -- p. ej. ajustar otro campo
--   field.multi = true  -- varios valores separados por comas (se completa el último)
--   field.choices = { { value = "tank", label = "Tanque" }, ... }  -- botones en vez de caja
--   field.multiline = true, field.height = 110  -- recuadro de varias líneas (uno por formulario)
---------------------------------------------------------------------------

local function plain(s)
	s = (s or ""):lower()
	for from, to in pairs({ ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ü"] = "u", ["ñ"] = "n" }) do s = s:gsub(from, to) end
	return s
end

local function setField(key, value)
	for i, field in ipairs(dialog.spec.fields) do
		if field.key == key then dialog.boxes[i]:SetText(tostring(value)) end
	end
end

local function hidePick()
	if dialog and dialog.pick then dialog.pick:Hide() end
end

-- Muestra la lista bajo la caja i: todas las opciones (filter nil) o las que coinciden.
local function showPick(i, filter)
	local field = dialog.spec and dialog.spec.fields[i]
	if not field or not field.options then return hidePick() end
	local ok, groups = pcall(field.options)
	if not ok or type(groups) ~= "table" then return hidePick() end
	local entries = {}
	local wanted = filter and plain(filter) or nil
	for _, grp in ipairs(groups) do
		local matched = {}
		for _, item in ipairs(grp.items or {}) do
			if not wanted or wanted == "" or plain(item):find(wanted, 1, true) then matched[#matched + 1] = item end
		end
		if #matched > 0 then
			if grp.label and not wanted then entries[#entries + 1] = { header = grp.label } end
			for _, item in ipairs(matched) do entries[#entries + 1] = { value = item } end
		end
	end
	-- Escribiendo: sin coincidencias, o si ya coincide exactamente, no estorba.
	if #entries == 0 or (wanted and #entries == 1 and plain(entries[1].value) == wanted) then return hidePick() end

	local pick = dialog.pick
	pick.box = i
	pick:ClearAllPoints()
	pick:SetPoint("TOPLEFT", dialog.boxes[i], "BOTTOMLEFT", -4, -2)
	pick:SetWidth(math.max(220, dialog.boxes[i]:GetWidth() + 8))
	pick:SetHeight(math.min(#entries, PICK_VISIBLE) * PICK_ROW + 10)
	pick.child:SetSize(pick:GetWidth() - 28, #entries * PICK_ROW)
	for n, e in ipairs(entries) do
		local b = pick.rows[n]
		if not b then
			b = CreateFrame("Button", nil, pick.child)
			b:SetHeight(PICK_ROW)
			b:SetPoint("TOPLEFT", 0, -(n - 1) * PICK_ROW)
			b:SetPoint("RIGHT", pick.child, "RIGHT")
			b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.text:SetPoint("LEFT", 6, 0)
			b.text:SetJustifyH("LEFT")
			pick.rows[n] = b
		end
		b.text:SetText(e.header and ("|cffffd100" .. e.header .. "|r") or e.value)
		b:EnableMouse(not e.header)
		b:SetScript("OnClick", not e.header and function()
			if field.multi then
				local before = dialog.boxes[i]:GetText():match("^(.*,)") or ""
				dialog.boxes[i]:SetText(before .. (before ~= "" and " " or "") .. e.value .. ", ")
			else
				dialog.boxes[i]:SetText(e.value)
			end
			hidePick()
			if field.onPick then pcall(field.onPick, e.value, setField) end
		end or nil)
		b:Show()
	end
	for n = #entries + 1, #pick.rows do pick.rows[n]:Hide() end
	pick.scroll:SetVerticalScroll(0)
	pick:Show()
end

local function createPick()
	local pick = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
	pick:SetFrameStrata("FULLSCREEN_DIALOG")
	if pick.SetBackdrop then
		pick:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		pick:SetBackdropColor(0.05, 0.04, 0.03, 0.97)
	end
	pick.scroll = CreateFrame("ScrollFrame", nil, pick, "UIPanelScrollFrameTemplate")
	ns.StyleScrollBar(pick.scroll)
	pick.scroll:SetPoint("TOPLEFT", 5, -5)
	pick.scroll:SetPoint("BOTTOMRIGHT", -26, 5)
	pick.child = CreateFrame("Frame", nil, pick.scroll)
	pick.scroll:SetScrollChild(pick.child)
	pick.rows = {}
	pick:Hide()
	dialog.pick = pick
end

-- Botones de elección de un campo (field.choices): el valor va en su caja, oculta.
local CHOICE_W = 80

local function paintChoices(i)
	local field = dialog.spec and dialog.spec.fields[i]
	local value = dialog.boxes[i]:GetText()
	for j, b in ipairs(dialog.choices[i] or {}) do
		local choice = field and field.choices and field.choices[j]
		b:SetShown(choice ~= nil)
		if choice then
			b:SetText(choice.label)
			local fs = b:GetFontString()
			b:SetWidth(math.max(CHOICE_W, (fs and fs:GetStringWidth() or 0) + 24))
			if choice.value == value then b:LockHighlight() else b:UnlockHighlight() end
			local fs = b:GetFontString()
			if fs then fs:SetTextColor(choice.value == value and 1 or 0.6, choice.value == value and 0.82 or 0.6, choice.value == value and 0 or 0.6) end
		end
	end
end

local function choiceButtons(i)
	dialog.choices[i] = dialog.choices[i] or {}
	local list = dialog.choices[i]
	for j = #list + 1, 6 do
		local b = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
		b:SetSize(CHOICE_W, 22)
		b:SetPoint("LEFT", j == 1 and dialog.labels[i] or list[j - 1], "RIGHT", j == 1 and 10 or 4, 0)
		b:SetScript("OnClick", function()
			local field = dialog.spec.fields[i]
			local choice = field.choices and field.choices[j]
			if choice then
				dialog.boxes[i]:SetText(choice.value)
				paintChoices(i)
			end
		end)
		list[j] = b
	end
	return list
end

local function create()
	dialog = CreateFrame("Frame", "LantuxGuildInputDialog", UIParent, "BasicFrameTemplateWithInset")
	dialog:SetFrameStrata("DIALOG")
	dialog:SetPoint("CENTER", 0, 100)
	dialog:EnableMouse(true)
	dialog:SetMovable(true)
	dialog:SetClampedToScreen(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

	dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	dialog.title:SetPoint("TOP", 0, -5)

	dialog.labels, dialog.boxes, dialog.choices = {}, {}, {}
	for i = 1, MAX_FIELDS do
		local label = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", 16, -10 - i * ROW)
		label:SetWidth(100)
		label:SetJustifyH("LEFT")
		local box = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
		box:SetHeight(20)
		box:SetPoint("LEFT", label, "RIGHT", 10, 0)
		box:SetAutoFocus(false)
		box:SetScript("OnEscapePressed", function()
			if dialog.pick and dialog.pick:IsShown() then hidePick() else dialog:Hide() end
		end)
		box:SetScript("OnEnterPressed", function() hidePick(); dialog.submit:Click() end)
		box:SetScript("OnTabPressed", function()
			hidePick()
			local nextBox = dialog.boxes[i + 1]
			if nextBox and nextBox:IsShown() then nextBox:SetFocus() else dialog.boxes[1]:SetFocus() end
		end)
		-- Autocompletado: al escribir en un campo con opciones, las que coinciden.
		box:SetScript("OnTextChanged", function(self, userInput)
			local field = dialog.spec and dialog.spec.fields[i]
			if userInput and field and field.options then
				-- Lista de nombres separados por comas (field.multi): se completa el último.
				local text = self:GetText()
				if field.multi then text = text:match("([^,]*)$") or "" end
				showPick(i, strtrim(text))
			end
		end)
		-- Botón ▼ para ver todas las opciones.
		local drop = CreateFrame("Button", nil, dialog)
		drop:SetSize(22, 22)
		drop:SetPoint("LEFT", box, "RIGHT", 2, 0)
		drop:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
		drop:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
		drop:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		drop:SetScript("OnClick", function()
			if dialog.pick:IsShown() and dialog.pick.box == i then hidePick() else showPick(i, nil) end
		end)
		box.drop = drop
		dialog.labels[i], dialog.boxes[i] = label, box
	end
	createPick()
	-- Mayúsculas + clic en un objeto (bolsas, banco, chat) con un campo del formulario activo: pone su enlace.
	if HandleModifiedItemClick and hooksecurefunc then
		hooksecurefunc("HandleModifiedItemClick", function(link)
			if not dialog:IsShown() or not link or not (IsModifiedClick and IsModifiedClick("CHATLINK")) then return end
			for i, box in ipairs(dialog.boxes) do
				if box:IsShown() and box.HasFocus and box:HasFocus() then box:SetText(link) end
			end
		end)
	end

	-- Recuadro de varias líneas (field.multiline): fondo oscuro con borde, como una caja grande.
	local area = CreateFrame("Frame", nil, dialog)
	local areaBg = area:CreateTexture(nil, "BACKGROUND")
	areaBg:SetAllPoints()
	areaBg:SetColorTexture(0, 0, 0, 0.55)
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
		local t = area:CreateTexture(nil, "BORDER")
		t:SetColorTexture(0.45, 0.42, 0.38, 0.9)
		t:SetPoint(side[1])
		t:SetPoint(side[2])
		if side[3] then t:SetHeight(1) else t:SetWidth(1) end
	end
	area.box = CreateFrame("EditBox", nil, area)
	area.box:SetMultiLine(true)
	area.box:SetAutoFocus(false)
	area.box:SetFontObject(ChatFontNormal)
	area.box:SetPoint("TOPLEFT", 6, -5)
	area.box:SetPoint("BOTTOMRIGHT", -6, 5)
	area.box:SetScript("OnEscapePressed", function() dialog:Hide() end)
	area:EnableMouse(true)
	area:SetScript("OnMouseDown", function() area.box:SetFocus() end)
	area:Hide()
	dialog.area = area

	-- Texto explicativo opcional (p. ej. una confirmación sin campos).
	dialog.text = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	dialog.text:SetPoint("TOPLEFT", 16, -34)
	dialog.text:SetJustifyH("LEFT")

	dialog.error = dialog:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
	dialog.error:SetJustifyH("LEFT")

	dialog.submit = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	dialog.submit:SetSize(120, 24)
	dialog.submit:SetPoint("BOTTOMRIGHT", -16, 12)
	dialog.submit:SetScript("OnClick", function()
		hidePick()
		local values = {}
		for i, field in ipairs(dialog.spec.fields) do
			local box = field.multiline and dialog.area.box or dialog.boxes[i]
			local text = strtrim(box:GetText() or "")
			values[field.key] = field.numeric and tonumber(text) or text
		end
		local err = dialog.spec.onSubmit(values)
		if err then dialog.error:SetText(err) else dialog:Hide() end
	end)

	local cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	cancel:SetSize(100, 24)
	cancel:SetPoint("RIGHT", dialog.submit, "LEFT", -6, 0)
	cancel:SetText(CANCEL)
	cancel:SetScript("OnClick", function() dialog:Hide() end)
end

function ns.ShowInputDialog(spec)
	if not dialog then create() end
	hidePick()
	dialog.spec = spec
	dialog.title:SetText(spec.title or "")
	dialog.submit:SetText(spec.submit or OKAY)
	local n = #spec.fields
	for i = 1, MAX_FIELDS do
		local field = spec.fields[i]
		dialog.labels[i]:SetShown(field ~= nil)
		dialog.boxes[i]:SetShown(field ~= nil and not field.choices and not field.multiline)
		dialog.boxes[i].drop:SetShown(field ~= nil and field.options ~= nil)
		if field and field.choices then choiceButtons(i) end
		if field then
			dialog.labels[i]:SetText(field.label)
			dialog.boxes[i]:SetWidth(field.width or 200)
			dialog.boxes[i]:SetNumeric(field.numeric and not field.signed or false)
			dialog.boxes[i]:SetMaxLetters(field.maxLetters or 0) -- 0 = sin límite (los códigos de guerra son largos)
			dialog.boxes[i]:SetText(field.default and tostring(field.default) or "")
		end
		paintChoices(i)
	end
	-- Ancho: el normal o lo que ocupen sus campos (etiqueta + caja + ▼, o etiqueta + botones).
	local width = 380
	dialog.area:Hide()
	for i, field in ipairs(spec.fields) do
		width = math.max(width, 16 + 100 + 10 + (field.width or 200) + (field.options and 26 or 0) + 16)
		if field.multiline then
			dialog.area:SetSize(field.width or 300, field.height or 110)
			dialog.area.box:SetWidth((field.width or 300) - 12)
			dialog.area.box:SetMaxLetters(field.maxLetters or 0)
			dialog.area.box:SetText(field.default and tostring(field.default) or "")
			dialog.area:Show()
		end
		if field.choices then
			-- Se mide cada botón con su texto para saber cuánto ocupan.
			local list = choiceButtons(i)
			local total = 0
			for j, choice in ipairs(field.choices) do
				list[j]:SetText(choice.label)
				local fs = list[j]:GetFontString()
				total = total + math.max(CHOICE_W, (fs and fs:GetStringWidth() or 0) + 24) + 4
			end
			width = math.max(width, 16 + 100 + 10 + total + 16)
		end
	end
	-- El texto con un ancho fijo antes de medirlo, para que pase a la línea siguiente.
	dialog.text:SetWidth(width - 32)
	dialog.text:SetWordWrap(true)
	dialog.text:SetText(spec.text or "")
	local textHeight = spec.text and (dialog.text:GetStringHeight() + 12) or 0
	-- Si hay texto, los campos van debajo; cada fila mide ROW salvo el recuadro grande.
	local acc = ROW
	for i = 1, MAX_FIELDS do
		local field = spec.fields[i]
		dialog.labels[i]:ClearAllPoints()
		dialog.labels[i]:SetPoint("TOPLEFT", 16, -10 - acc - textHeight)
		if field and field.multiline then
			dialog.area:ClearAllPoints()
			dialog.area:SetPoint("TOPLEFT", dialog.labels[i], "TOPRIGHT", 10, 6)
			acc = acc + (field.height or 110) + 10
		elseif field then
			acc = acc + ROW
		end
	end
	dialog.error:ClearAllPoints()
	dialog.error:SetPoint("TOPLEFT", 16, -16 - acc - textHeight)
	dialog.error:SetPoint("RIGHT", -16, 0)
	dialog.error:SetText("")
	dialog:SetSize(width, 90 + acc + textHeight - (n == 0 and ROW or 0))
	dialog:Show()
	if n > 0 then dialog.boxes[1]:SetFocus() end
	-- highlight = true: texto seleccionado, listo para Ctrl+C.
	if n > 0 and spec.highlight then dialog.boxes[1]:HighlightText() end
end
