-- Ventana para crear un evento de hermandad (solo oficiales).
local _, ns = ...
local L = ns.L

local dialog

local function label(parent, text, x, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

local function box(parent, width, anchor, maxLetters, numeric)
	local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	eb:SetSize(width, 20)
	eb:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
	eb:SetAutoFocus(false)
	eb:SetMaxLetters(maxLetters)
	if numeric then eb:SetNumeric(true) end
	return eb
end

-- "DD/MM" y "HH:MM" -> marca de tiempo. Si la fecha ya pasó este año, es del siguiente.
local function parseStart(dateText, timeText)
	local d, m = dateText:match("^%s*(%d%d?)/(%d%d?)%s*$")
	local h, mi = timeText:match("^%s*(%d%d?):(%d%d)%s*$")
	d, m, h, mi = tonumber(d), tonumber(m), tonumber(h), tonumber(mi)
	if not d or not h or m < 1 or m > 12 or d < 1 or d > 31 or h > 23 or mi > 59 then return nil end
	local now = time()
	local year = tonumber(date("%Y", now))
	local ts = time({ year = year, month = m, day = d, hour = h, min = mi, sec = 0 })
	if ts < now - 3600 then ts = time({ year = year + 1, month = m, day = d, hour = h, min = mi, sec = 0 }) end
	return ts
end

local function setKind(index)
	dialog.kindIndex = index
	local kind = ns.EVENT_KINDS[index]
	dialog.kindButton:SetText(kind.label)
	dialog.tank:SetText(tostring(kind.comp.tank))
	dialog.healer:SetText(tostring(kind.comp.healer))
	dialog.dps:SetText(tostring(kind.comp.dps))
end

local function create()
	dialog = CreateFrame("Frame", "LantuxGuildEventDialog", UIParent, "BasicFrameTemplateWithInset")
	dialog:SetSize(400, 300)
	dialog:SetPoint("CENTER", 0, 100)
	dialog:SetFrameStrata("DIALOG")
	dialog:EnableMouse(true)
	dialog:SetMovable(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

	local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -5)
	title:SetText(L["Nuevo evento"])

	dialog.title = box(dialog, 280, label(dialog, L["Título"], 16, -38), 60)

	local kindLabel = label(dialog, L["Tipo"], 16, -68)
	dialog.kindButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	dialog.kindButton:SetSize(110, 22)
	dialog.kindButton:SetPoint("LEFT", kindLabel, "RIGHT", 12, 0)
	dialog.kindButton:SetScript("OnClick", function()
		setKind(dialog.kindIndex % #ns.EVENT_KINDS + 1)
	end)
	local kindHint = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	kindHint:SetPoint("LEFT", dialog.kindButton, "RIGHT", 8, 0)
	kindHint:SetText(L["clic para cambiar"])

	dialog.date = box(dialog, 60, label(dialog, L["Fecha (DD/MM)"], 16, -98), 5)
	dialog.time = box(dialog, 60, label(dialog, L["Hora (HH:MM)"], 200, -98), 5)
	dialog.minLevel = box(dialog, 40, label(dialog, L["Nivel mínimo"], 16, -128), 2, true)

	dialog.tank = box(dialog, 30, label(dialog, L["Tanques"], 16, -158), 2, true)
	dialog.healer = box(dialog, 30, label(dialog, L["Sanadores"], 140, -158), 2, true)
	dialog.dps = box(dialog, 30, label(dialog, L["DPS"], 280, -158), 2, true)

	dialog.note = box(dialog, 290, label(dialog, L["Nota"], 16, -188), 120)

	dialog.error = dialog:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
	dialog.error:SetPoint("TOPLEFT", 16, -216)
	dialog.error:SetPoint("RIGHT", -16, 0)
	dialog.error:SetJustifyH("LEFT")

	local createButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	createButton:SetSize(120, 24)
	createButton:SetPoint("BOTTOMRIGHT", -16, 14)
	createButton:SetText(L["Crear evento"])
	createButton:SetScript("OnClick", function()
		local titleText = strtrim(dialog.title:GetText() or "")
		if titleText == "" then
			dialog.error:SetText(L["Ponle un título."])
			return
		end
		local start = parseStart(dialog.date:GetText() or "", dialog.time:GetText() or "")
		if not start then
			dialog.error:SetText(L["Fecha u hora no válidas. Usa DD/MM y HH:MM, por ejemplo 12/11 y 21:00."])
			return
		end
		local note = strtrim(dialog.note:GetText() or "")
		local ok = ns.CreateEvent({
			title = titleText,
			kind = ns.EVENT_KINDS[dialog.kindIndex].key,
			start = start,
			minLevel = tonumber(dialog.minLevel:GetText()),
			comp = {
				tank = tonumber(dialog.tank:GetText()) or 0,
				healer = tonumber(dialog.healer:GetText()) or 0,
				dps = tonumber(dialog.dps:GetText()) or 0,
			},
			note = note ~= "" and note or nil,
		})
		if ok then dialog:Hide() end
	end)

	local cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	cancel:SetSize(110, 24)
	cancel:SetPoint("RIGHT", createButton, "LEFT", -8, 0)
	cancel:SetText(CANCEL)
	cancel:SetScript("OnClick", function() dialog:Hide() end)

	for _, eb in ipairs({ dialog.title, dialog.date, dialog.time, dialog.minLevel, dialog.tank, dialog.healer, dialog.dps, dialog.note }) do
		eb:SetScript("OnEscapePressed", function() dialog:Hide() end)
		eb:SetScript("OnTabPressed", function(self) self:ClearFocus() end)
	end
end

ns.ParseStart = parseStart -- también la usa la declaración de guerra

-- day: un momento de ese día (el día elegido en el calendario); si no, mañana.
function ns.ShowEventDialog(day)
	if not dialog then create() end
	dialog.title:SetText("")
	dialog.note:SetText("")
	dialog.minLevel:SetText("")
	dialog.error:SetText("")
	-- Por defecto: ese día (o mañana) a las 21:00.
	local when = type(day) == "number" and day or (time() + 86400)
	dialog.date:SetText(date("%d/%m", when))
	dialog.time:SetText("21:00")
	setKind(1)
	dialog:Show()
	dialog.title:SetFocus()
end
