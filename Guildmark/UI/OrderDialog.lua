-- Ventana para pedir un encargo: cantidad, nota, si pones tú los materiales y una propina.
-- Es un marco propio y no un StaticPopup para no tocar la interfaz de Blizzard.
local _, ns = ...
local L = ns.L

local dialog
local BASE_H, LINE_H, MAX_LINES = 262, 24, 8

local function create()
	dialog = CreateFrame("Frame", "LantuxGuildOrderDialog", UIParent, "BasicFrameTemplateWithInset")
	dialog:SetSize(360, BASE_H)
	dialog:SetPoint("CENTER", 0, 120)
	dialog:SetFrameStrata("DIALOG")
	dialog:EnableMouse(true)
	dialog:SetMovable(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

	local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -5)
	title:SetText(L["Pedir encargo"])

	dialog.what = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	dialog.what:SetPoint("TOPLEFT", 16, -34)
	dialog.what:SetPoint("RIGHT", -16, 0)
	dialog.what:SetJustifyH("LEFT")

	local qtyLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	qtyLabel:SetPoint("TOPLEFT", 16, -72)
	qtyLabel:SetText(L["Cantidad"])
	dialog.qty = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	dialog.qty:SetSize(50, 20)
	dialog.qty:SetPoint("LEFT", qtyLabel, "RIGHT", 12, 0)
	dialog.qty:SetAutoFocus(false)
	dialog.qty:SetNumeric(true)
	dialog.qty:SetMaxLetters(3)

	local noteLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	noteLabel:SetPoint("TOPLEFT", 16, -104)
	noteLabel:SetText(L["Nota"])
	dialog.note = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	dialog.note:SetSize(260, 20)
	dialog.note:SetPoint("LEFT", noteLabel, "RIGHT", 12, 0)
	dialog.note:SetAutoFocus(false)
	dialog.note:SetMaxLetters(80)

	-- Materiales: casilla con su texto (clic en el texto también la marca).
	dialog.mats = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
	dialog.mats:SetSize(24, 24)
	dialog.mats:SetPoint("TOPLEFT", 12, -132)
	local matsLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	matsLabel:SetPoint("LEFT", dialog.mats, "RIGHT", 4, 0)
	matsLabel:SetText(L["Pongo yo los materiales"])
	dialog.mats:SetHitRectInsets(0, -matsLabel:GetStringWidth() - 8, 0, 0)
	dialog.mats:SetScript("OnClick", function() ns.UpdateOrderMaterials() end)

	-- Lista de materiales (debajo de la casilla, solo si está marcada).
	dialog.matLines = {}
	for i = 1, MAX_LINES do
		local icon = dialog:CreateTexture(nil, "ARTWORK")
		icon:SetSize(20, 20)
		icon:SetPoint("TOPLEFT", 40, -160 - (i - 1) * LINE_H)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		local text = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
		text:SetPoint("RIGHT", dialog, "RIGHT", -16, 0)
		text:SetJustifyH("LEFT")
		dialog.matLines[i] = { icon = icon, text = text }
	end
	dialog.matsNone = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	dialog.matsNone:SetPoint("TOPLEFT", 40, -160)
	dialog.matsNone:SetPoint("RIGHT", -16, 0)
	dialog.matsNone:SetJustifyH("LEFT")
	dialog.matsNone:SetText(L["No se saben los materiales de esta receta: el artesano te dirá qué traer."])

	-- Propina: oro, plata y cobre, con el icono de cada moneda.
	local tipLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tipLabel:SetPoint("TOPLEFT", 16, -172)
	dialog.tipLabel = tipLabel
	tipLabel:SetText(L["Propina"])
	dialog.coins = {}
	local anchor, offset = tipLabel, 12
	for _, coin in ipairs({ { "Gold", 4 }, { "Silver", 2 }, { "Copper", 2 } }) do
		local box = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
		box:SetSize(coin[1] == "Gold" and 44 or 28, 20)
		box:SetPoint("LEFT", anchor, "RIGHT", offset, 0)
		box:SetAutoFocus(false)
		box:SetNumeric(true)
		box:SetMaxLetters(coin[2])
		local icon = dialog:CreateTexture(nil, "OVERLAY")
		icon:SetSize(13, 13)
		icon:SetTexture("Interface\\MoneyFrame\\UI-" .. coin[1] .. "Icon")
		icon:SetPoint("LEFT", box, "RIGHT", 3, 0)
		dialog.coins[#dialog.coins + 1] = box
		anchor, offset = icon, 10
	end
	local tipHint = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tipHint:SetPoint("TOPLEFT", tipLabel, "TOPLEFT", 0, -26)
	tipHint:SetPoint("RIGHT", -16, 0)
	tipHint:SetJustifyH("LEFT")
	tipHint:SetText(L["Opcional. Se paga en el intercambio; el addon lo comprueba."])

	local send = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	send:SetSize(110, 24)
	send:SetPoint("BOTTOMRIGHT", -16, 14)
	send:SetText(L["Pedir"])
	send:SetScript("OnClick", function()
		local g, s, c = (tonumber(dialog.coins[1]:GetText()) or 0), (tonumber(dialog.coins[2]:GetText()) or 0), (tonumber(dialog.coins[3]:GetText()) or 0)
		local tip = g * 10000 + math.min(s, 99) * 100 + math.min(c, 99)
		ns.CreateOrder(dialog.crafter, dialog.recipe, dialog.qty:GetText(), dialog.note:GetText(), dialog.skillLine,
			dialog.mats:GetChecked(), tip)
		dialog:Hide()
	end)

	local cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	cancel:SetSize(110, 24)
	cancel:SetPoint("RIGHT", send, "LEFT", -8, 0)
	cancel:SetText(CANCEL)
	cancel:SetScript("OnClick", function() dialog:Hide() end)

	dialog.qty:SetScript("OnTextChanged", function() ns.UpdateOrderMaterials() end)
	for _, box in ipairs({ dialog.qty, dialog.note, dialog.coins[1], dialog.coins[2], dialog.coins[3] }) do
		box:SetScript("OnEscapePressed", function() dialog:Hide() end)
		box:SetScript("OnEnterPressed", function() send:Click() end)
	end
end

-- Materiales de la receta por la cantidad pedida, debajo de la casilla (la ventana crece).
function ns.UpdateOrderMaterials()
	if not dialog or not dialog:IsShown() then return end
	local shown = dialog.mats:GetChecked() and true or false
	local list = shown and ns.RecipeReagents and ns.RecipeReagents(dialog.recipe) or nil
	local qty = math.max(1, tonumber(dialog.qty:GetText()) or 1)
	local lines = 0
	for i, line in ipairs(dialog.matLines) do
		local r = list and list[i]
		line.icon:SetShown(r ~= nil)
		line.text:SetShown(r ~= nil)
		if r then
			lines = i
			local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.id) or (GetItemIcon and GetItemIcon(r.id))
			line.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			line.text:SetText(("%dx %s"):format(r.n * qty, ns.BankItemLink and ns.BankItemLink(r.id) or ("item:" .. r.id)))
		end
	end
	dialog.matsNone:SetShown(shown and not list)
	if shown and not list then lines = 2 end
	local extra = lines > 0 and (lines * LINE_H + 6) or 0
	dialog.tipLabel:ClearAllPoints()
	dialog.tipLabel:SetPoint("TOPLEFT", 16, -172 - extra)
	dialog:SetHeight(BASE_H + extra)
end

-- crafter = nil: al gremio (skillLine: la profesión, para decir a qué gremio).
function ns.ShowOrderDialog(crafter, recipeID, skillLine)
	if not dialog then create() end
	dialog.crafter = crafter
	dialog.recipe = recipeID
	dialog.skillLine = skillLine
	dialog.what:SetText(crafter and (L["%s a %s"]):format(ns.RecipeName(recipeID) or "?", ns.ShortName(crafter))
		or (L["%s al gremio de %s"]):format(ns.RecipeName(recipeID) or "?", skillLine and ns.ProfessionName(skillLine) or "?"))
	dialog.qty:SetText("1")
	dialog.note:SetText("")
	dialog.mats:SetChecked(false)
	for _, box in ipairs(dialog.coins) do box:SetText("") end
	dialog:Show()
	ns.UpdateOrderMaterials()
	dialog.qty:SetFocus()
	dialog.qty:HighlightText()
end
