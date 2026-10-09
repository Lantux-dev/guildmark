-- Ventana para pedir un encargo: cantidad y nota.
-- Es un marco propio y no un StaticPopup para no tocar la interfaz de Blizzard.
local _, ns = ...
local L = ns.L

local dialog

local function create()
	dialog = CreateFrame("Frame", "LantuxGuildOrderDialog", UIParent, "BasicFrameTemplateWithInset")
	dialog:SetSize(360, 190)
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

	local send = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	send:SetSize(110, 24)
	send:SetPoint("BOTTOMRIGHT", -16, 14)
	send:SetText(L["Pedir"])
	send:SetScript("OnClick", function()
		ns.CreateOrder(dialog.crafter, dialog.recipe, dialog.qty:GetText(), dialog.note:GetText(), dialog.skillLine)
		dialog:Hide()
	end)

	local cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	cancel:SetSize(110, 24)
	cancel:SetPoint("RIGHT", send, "LEFT", -8, 0)
	cancel:SetText(CANCEL)
	cancel:SetScript("OnClick", function() dialog:Hide() end)

	for _, box in ipairs({ dialog.qty, dialog.note }) do
		box:SetScript("OnEscapePressed", function() dialog:Hide() end)
		box:SetScript("OnEnterPressed", function() send:Click() end)
	end
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
	dialog:Show()
	dialog.qty:SetFocus()
	dialog.qty:HighlightText()
end
