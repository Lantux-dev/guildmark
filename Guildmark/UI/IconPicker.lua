-- Selector de icono, como el de /macro: primero los de Guildmark (los de tu
-- facción delante) y después todos los del juego (GetMacroIcons), por páginas.
-- ns.ShowIconPicker(actual, alElegir)
local _, ns = ...
local L = ns.L

local COLS, ROWS, SIZE, GAP = 8, 6, 38, 6
local PER_PAGE = COLS * ROWS

local frame, page, icons, onPick, selected

-- Lista completa: los nuestros y, si el juego los da, los suyos (números de archivo).
local function allIcons()
	local list = {}
	local mine = (UnitFactionGroup and UnitFactionGroup("player") == "Alliance") and "Alliance" or "Horde"
	local other = mine == "Alliance" and "Horde" or "Alliance"
	for _, key in ipairs(ns.TRIBE_ICONS[mine]) do list[#list + 1] = key end
	for _, key in ipairs(ns.TRIBE_ICONS[other]) do list[#list + 1] = key end
	ns.iconPickerCustom = #list
	local game = {}
	if GetMacroIcons then pcall(GetMacroIcons, game) end
	if GetMacroItemIcons then pcall(GetMacroItemIcons, game) end
	local seen = {}
	for _, id in ipairs(game) do
		if type(id) == "number" and not seen[id] then
			seen[id] = true
			list[#list + 1] = id
		end
	end
	return list
end

local function refresh()
	local pages = math.max(1, math.ceil(#icons / PER_PAGE))
	page = math.max(1, math.min(page, pages))
	for i, b in ipairs(frame.buttons) do
		local icon = icons[(page - 1) * PER_PAGE + i]
		b.value = icon
		b:SetShown(icon ~= nil)
		if icon then
			local tex, custom = ns.TribeIconTexture(icon)
			b.icon:SetTexture(tex)
			b.icon:SetTexCoord(custom and 0 or 0.07, custom and 1 or 0.93, custom and 0 or 0.07, custom and 1 or 0.93)
			b.border:SetShown(not custom)
			b.selected:SetShown(icon == selected)
		end
	end
	frame.pageText:SetText((L["Página %d de %d"]):format(page, pages))
	frame.prev:SetEnabled(page > 1)
	frame.next:SetEnabled(page < pages)
	local custom = ns.iconPickerCustom or 0
	frame.section:SetText((page - 1) * PER_PAGE < custom and L["Iconos de Guildmark"] or L["Iconos del juego"])
end

local function create()
	local f = CreateFrame("Frame", "GuildmarkIconPicker", UIParent, "BackdropTemplate")
	f:SetSize(COLS * (SIZE + GAP) + 34, ROWS * (SIZE + GAP) + 110)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
			tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
	end
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOP", 0, -16)
	f.title:SetText(L["Elige un icono"])
	f.section = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.section:SetPoint("TOPLEFT", 18, -42)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", -4, -4)

	f.buttons = {}
	for i = 1, PER_PAGE do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(SIZE, SIZE)
		local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
		b:SetPoint("TOPLEFT", 18 + col * (SIZE + GAP), -60 - row * (SIZE + GAP))
		b.border = b:CreateTexture(nil, "BACKGROUND")
		b.border:SetPoint("TOPLEFT", -1, 1)
		b.border:SetPoint("BOTTOMRIGHT", 1, -1)
		b.border:SetColorTexture(0.3, 0.3, 0.3, 1)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b.selected = b:CreateTexture(nil, "OVERLAY")
		b.selected:SetPoint("TOPLEFT", -3, 3)
		b.selected:SetPoint("BOTTOMRIGHT", 3, -3)
		b.selected:SetColorTexture(1, 0.82, 0, 0.35)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b:SetScript("OnClick", function(self)
			if self.value ~= nil and onPick then onPick(self.value) end
			f:Hide()
		end)
		f.buttons[i] = b
	end

	f.prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.prev:SetSize(90, 22)
	f.prev:SetPoint("BOTTOMLEFT", 18, 16)
	f.prev:SetText(L["Anterior"])
	f.prev:SetScript("OnClick", function() page = page - 1; refresh() end)
	f.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.next:SetSize(90, 22)
	f.next:SetPoint("BOTTOMRIGHT", -18, 16)
	f.next:SetText(L["Siguiente"])
	f.next:SetScript("OnClick", function() page = page + 1; refresh() end)
	f.pageText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.pageText:SetPoint("BOTTOM", 0, 22)
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta) page = page - delta; refresh() end)
	if UISpecialFrames then tinsert(UISpecialFrames, "GuildmarkIconPicker") end -- se cierra con Escape
	f:Hide()
	return f
end

function ns.ShowIconPicker(current, callback)
	frame = frame or create()
	icons = allIcons()
	onPick, selected = callback, current
	page = 1
	-- Abre en la página del icono actual.
	for i, icon in ipairs(icons) do
		if icon == current then page = math.floor((i - 1) / PER_PAGE) + 1 end
	end
	refresh()
	frame:Show()
end
