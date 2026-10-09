-- Espadas cruzadas en el mapa del mundo sobre la zona de cada guerra aceptada
-- (programada o en curso): en el mapa de la zona y en el de su continente.
--
-- No usa el sistema de "data providers" del mapa (pide plantillas XML y cambia
-- entre versiones del cliente): son marcos propios encima del lienzo del mapa,
-- que se recolocan al cambiar de mapa. Todo va protegido con pcall: si Forever
-- no deja tocar el mapa, el addon sigue funcionando sin iconos.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local WarMap = LG:NewModule("WarMap", "AceEvent-3.0", "AceTimer-3.0")

local PIN_SIZE = 30
local ICON = "Interface\\Icons\\Ability_DualWield"
local pins = {}
local hooked = false

-- ¿Está "ancestor" por encima de "map" (zona > continente > mundo)?
local function isAncestor(map, ancestor)
	local guard = 0
	while map and guard < 10 do
		local info = C_Map.GetMapInfo(map)
		map = info and info.parentMapID
		if map == ancestor then return true end
		guard = guard + 1
	end
	return false
end

-- Centro de la zona de la guerra en el mapa que se está viendo (0-1), o nil.
local function centerOn(zone, shown)
	if zone == shown then return 0.5, 0.5 end
	if not C_Map.GetMapRectOnMap or not isAncestor(zone, shown) then return nil end
	local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(zone, shown)
	if not minX or not maxX or maxX <= minX then return nil end
	return (minX + maxX) / 2, (minY + maxY) / 2
end

local function tooltip(pin)
	local w = pin.war
	if not w then return end
	local phase = ns.WarPhase(w)
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:SetText((L["Guerra contra <%s>"]):format(ns.WarEnemy(w)), 1, 0.42, 0.35)
	GameTooltip:AddLine(ns.MapName(w.map, w.zone), 1, 0.82, 0)
	if phase == "active" then
		local s = ns.WarScore(w)
		GameTooltip:AddLine(("%d – %d"):format(s.ours, s.theirs), 1, 1, 1)
		local left = math.max(0, math.ceil((w.start + w.duration - ns.Now()) / 60))
		GameTooltip:AddLine((L["Quedan %d min"]):format(left), 0.8, 0.8, 0.8)
	else
		GameTooltip:AddLine((L["Empieza el %s"]):format(date("%d/%m %H:%M", w.start)), 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine(L["Clic: ver la guerra"], 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function createPin(canvas)
	local pin = CreateFrame("Button", nil, canvas)
	pin:SetSize(PIN_SIZE, PIN_SIZE)
	pin:SetFrameLevel(canvas:GetFrameLevel() + 2000) -- encima de los iconos del propio mapa
	-- Halo rojo que late durante la guerra.
	pin.glow = pin:CreateTexture(nil, "BACKGROUND")
	pin.glow:SetTexture("Interface\\Cooldown\\star4")
	pin.glow:SetBlendMode("ADD")
	pin.glow:SetVertexColor(1, 0.2, 0.1)
	pin.glow:SetPoint("CENTER")
	pin.glow:SetSize(PIN_SIZE * 2.2, PIN_SIZE * 2.2)
	pin.pulse = pin.glow:CreateAnimationGroup()
	pin.pulse:SetLooping("BOUNCE")
	local fade = pin.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.25)
	fade:SetToAlpha(0.9)
	fade:SetDuration(0.9)
	-- Marco dorado y el icono de las espadas.
	pin.border = pin:CreateTexture(nil, "BORDER")
	pin.border:SetColorTexture(1, 0.82, 0, 1)
	pin.border:SetPoint("CENTER")
	pin.border:SetSize(PIN_SIZE, PIN_SIZE)
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetTexture(ICON)
	pin.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	pin.icon:SetPoint("CENTER")
	pin.icon:SetSize(PIN_SIZE - 4, PIN_SIZE - 4)
	pin:SetScript("OnEnter", tooltip)
	pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
	pin:SetScript("OnClick", function() if ns.ShowWars then ns.ShowWars() end end)
	return pin
end

-- Guerras que se marcan: aceptadas y todavía no terminadas.
local function warsToShow()
	local list = {}
	local g = LG:GuildData()
	if not g or ns.WARS_PAUSED then return list end
	for _, w in pairs(g.wars) do
		local phase = ns.WarPhase(w)
		if (phase == "upcoming" or phase == "active") and w.map then list[#list + 1] = w end
	end
	table.sort(list, function(a, b) return a.start < b.start end)
	return list
end

function ns.RefreshWarMap()
	local map = WorldMapFrame
	if not map or not map.GetCanvas or not map.GetMapID or not C_Map then return 0 end
	local ok, shown = pcall(function()
		local canvas = map:GetCanvas()
		local mapID = map:GetMapID()
		local width, height = canvas:GetWidth(), canvas:GetHeight()
		local scale = map.GetCanvasScale and map:GetCanvasScale() or 1
		local n = 0
		for _, w in ipairs(warsToShow()) do
			local x, y = centerOn(w.map, mapID)
			if x then
				n = n + 1
				local pin = pins[n] or createPin(canvas)
				pins[n] = pin
				pin.war = w
				-- Mismo tamaño en pantalla aunque el mapa esté ampliado. Ojo: los
				-- desplazamientos de SetPoint van en la escala del propio icono, así
				-- que la posición en el lienzo se multiplica por la escala del mapa.
				local pinScale = 1 / math.max(scale, 0.01)
				pin:SetScale(pinScale)
				pin:ClearAllPoints()
				-- Varias guerras en la misma zona: un poco separadas (en píxeles de pantalla).
				pin:SetPoint("CENTER", canvas, "TOPLEFT", x * width / pinScale + (n - 1) * 14, -y * height / pinScale)
				LG.db.global.diag.warMapLast = { map = mapID, zone = w.map, x = x, y = y, width = width, height = height, scale = scale }
				local active = ns.WarPhase(w) == "active"
				pin.glow:SetShown(active)
				if active then pin.pulse:Play() else pin.pulse:Stop() end
				pin.icon:SetDesaturated(not active)
				pin:Show()
			end
		end
		for i = n + 1, #pins do pins[i]:Hide() end
		return n
	end)
	if not ok then
		LG.db.global.diag.warMapError = tostring(shown)
		return 0
	end
	return shown
end

local function hook()
	if hooked or not WorldMapFrame then return end
	hooked = true
	local refresh = function() ns.RefreshWarMap() end
	pcall(function()
		WorldMapFrame:HookScript("OnShow", refresh)
		if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", refresh) end
		if WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", refresh) end
	end)
end

function WarMap:OnEnable()
	hook()
	if not hooked then
		-- El mapa del mundo puede cargarse más tarde.
		ns.RegisterEvent(self, "ADDON_LOADED", function(_, name)
			if name == "Blizzard_WorldMap" then hook() end
		end)
	end
	self:RegisterMessage("LANTUX_DATA_CHANGED", function()
		if WorldMapFrame and WorldMapFrame:IsShown() then ns.RefreshWarMap() end
	end)
	-- El marcador del tooltip y el paso de "programada" a "en curso".
	self:ScheduleRepeatingTimer(function()
		if WorldMapFrame and WorldMapFrame:IsShown() then ns.RefreshWarMap() end
	end, 30)
end
