-- Ventana de /gmk errores: los errores del addon (Errors.lua) en un cuadro de texto para
-- copiarlos (Ctrl+C) y pegarlos en un comentario de CurseForge o en una incidencia de GitHub.
local _, ns = ...
local L = ns.L

local WIDTH, HEIGHT = 560, 420
local window

local function fill()
	window.box:SetText(ns.ErrorReport())
	window.box:SetCursorPosition(0)
	local n = ns.ErrorCount()
	window.count:SetText(n == 0 and L["Sin errores registrados."] or (n == 1 and L["1 error registrado"] or (L["%d errores registrados"]):format(n)))
	window.clear:SetEnabled(n > 0)
end

local function selectAll()
	window.box:SetFocus()
	window.box:HighlightText()
end

local function create()
	window = CreateFrame("Frame", "GuildmarkErrorsFrame", UIParent, "BasicFrameTemplateWithInset")
	window:SetSize(WIDTH, HEIGHT)
	window:SetFrameStrata("DIALOG")
	window:SetPoint("CENTER", 0, 40)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:SetClampedToScreen(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	if window.SetToplevel then window:SetToplevel(true) end

	window.title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	window.title:SetPoint("TOP", 0, -5)
	window.title:SetText((L["Errores de %s"]):format(ns.ADDON_TITLE))

	local icon = window:CreateTexture(nil, "ARTWORK")
	icon:SetSize(32, 32)
	icon:SetPoint("TOPLEFT", 16, -34)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	local help = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
	help:SetPoint("RIGHT", window, "RIGHT", -18, 0)
	help:SetJustifyH("LEFT")
	help:SetWordWrap(true)
	help:SetText(L["Si algo ha fallado, pulsa «Seleccionar todo», copia con Ctrl+C y pégalo en un comentario de CurseForge o en una incidencia de GitHub. Cuenta también qué estabas haciendo."])

	-- El enlace de las incidencias, en una caja para poder copiarlo.
	local urlLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	urlLabel:SetPoint("TOPLEFT", 16, -78)
	urlLabel:SetText(L["Incidencias:"])
	window.url = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
	window.url:SetSize(330, 20)
	window.url:SetPoint("LEFT", urlLabel, "RIGHT", 10, 0)
	window.url:SetAutoFocus(false)
	window.url:SetText(ns.ERRORS_URL)
	window.url:SetCursorPosition(0)
	-- Es de solo lectura: lo que se escriba se deshace.
	window.url:SetScript("OnTextChanged", function(self, user)
		if user then self:SetText(ns.ERRORS_URL); self:HighlightText() end
	end)
	window.url:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	window.url:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	-- El informe: fondo oscuro con borde y desplazamiento.
	local area = CreateFrame("Frame", nil, window)
	area:SetPoint("TOPLEFT", 14, -104)
	area:SetPoint("BOTTOMRIGHT", -14, 44)
	local bg = area:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.55)
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
		local t = area:CreateTexture(nil, "BORDER")
		t:SetColorTexture(0.45, 0.42, 0.38, 0.9)
		t:SetPoint(side[1])
		t:SetPoint(side[2])
		if side[3] then t:SetHeight(1) else t:SetWidth(1) end
	end
	local scroll = CreateFrame("ScrollFrame", "GuildmarkErrorsScroll", area, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	window.box = CreateFrame("EditBox", nil, scroll)
	window.box:SetMultiLine(true)
	window.box:SetAutoFocus(false)
	window.box:SetFontObject(ChatFontNormal)
	window.box:SetWidth(WIDTH - 28 - 40)
	window.box:SetScript("OnEscapePressed", function() window:Hide() end)
	-- De solo lectura: si se escribe encima, vuelve el informe.
	window.box:SetScript("OnTextChanged", function(self, user)
		if user then self:SetText(ns.ErrorReport()); self:HighlightText() end
	end)
	scroll:SetScrollChild(window.box)
	area:EnableMouse(true)
	area:SetScript("OnMouseDown", selectAll)

	window.count = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	window.count:SetPoint("BOTTOMLEFT", 16, 18)

	local close = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	close:SetSize(90, 24)
	close:SetPoint("BOTTOMRIGHT", -14, 12)
	close:SetText(CLOSE or L["Cerrar"])
	close:SetScript("OnClick", function() window:Hide() end)

	window.clear = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	window.clear:SetSize(90, 24)
	window.clear:SetPoint("RIGHT", close, "LEFT", -6, 0)
	window.clear:SetText(L["Borrar"])
	window.clear:SetScript("OnClick", function()
		ns.ClearErrors()
		fill()
	end)

	local all = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	all:SetSize(130, 24)
	all:SetPoint("RIGHT", window.clear, "LEFT", -6, 0)
	all:SetText(L["Seleccionar todo"])
	all:SetScript("OnClick", selectAll)
end

function ns.ShowErrors()
	if not window then create() end
	fill()
	window:Show()
	if window.Raise then window:Raise() end
end
