-- Marcador de guerra en pantalla: aparece 15 minutos antes de una guerra y
-- mientras dura, con el marcador, el tiempo que queda, quién está en la zona y
-- si los dos bandos están en la misma capa. Se arrastra a donde quieras (la
-- posición se guarda) y con clic abre JcJ › Guerras.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local WarHud = LG:NewModule("WarHud", "AceEvent-3.0", "AceTimer-3.0")

local BEFORE = 15 * 60
local GOLD, GREEN, RED, GREY, R = "|cffffd100", "|cff5ad55a", "|cffff6b5a", "|cff9d9d9d", "|r"

local hud
local hiddenFor -- id de la guerra que has cerrado (vuelve con la siguiente)

local function edge(f, point, w, h)
	local t = f:CreateTexture(nil, "BORDER")
	t:SetColorTexture(0.78, 0.62, 0.25, 0.9)
	t:SetPoint(point)
	if w then t:SetWidth(w) end
	if h then t:SetHeight(h) end
	return t
end

local function create()
	local f = CreateFrame("Button", "LantuxGuildWarHud", UIParent)
	f:SetSize(250, 74)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:RegisterForClicks("LeftButtonUp")
	local pos = LG.db.profile.warHud
	if pos and pos.point then
		f:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
	else
		f:SetPoint("TOP", UIParent, "TOP", 0, -190)
	end
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		LG.db.profile.warHud = { point = point, x = x, y = y }
	end)
	f:SetScript("OnClick", function() if ns.ShowWars then ns.ShowWars() end end)

	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetColorTexture(0.05, 0.04, 0.03, 0.88)
	local top = edge(f, "TOPLEFT", nil, 1); top:SetPoint("TOPRIGHT")
	local bottom = edge(f, "BOTTOMLEFT", nil, 1); bottom:SetPoint("BOTTOMRIGHT")
	local left = edge(f, "TOPLEFT", 1, nil); left:SetPoint("BOTTOMLEFT")
	local right = edge(f, "TOPRIGHT", 1, nil); right:SetPoint("BOTTOMRIGHT")

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(16, 16)
	f.icon:SetPoint("TOPLEFT", 8, -7)
	f.icon:SetTexture("Interface\\Icons\\Ability_DualWield")
	f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
	f.title:SetPoint("RIGHT", -24, 0)
	f.title:SetJustifyH("LEFT")
	f.title:SetWordWrap(false)

	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetSize(20, 20)
	f.close:SetPoint("TOPRIGHT", 0, 0)
	f.close:SetScript("OnClick", function()
		hiddenFor = f.warID
		f:Hide()
	end)

	f.score = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	f.score:SetPoint("TOPLEFT", 10, -28)
	f.state = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.state:SetPoint("LEFT", f.score, "RIGHT", 10, 0)
	f.state:SetPoint("RIGHT", -8, 0)
	f.state:SetJustifyH("RIGHT")
	f.layer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.layer:SetPoint("BOTTOMLEFT", 10, 7)
	f.layer:SetPoint("BOTTOMRIGHT", -8, 7)
	f.layer:SetJustifyH("LEFT")
	f.layer:SetWordWrap(false)

	f:SetScript("OnEnter", function(self)
		if not self.tip then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		for i, line in ipairs(self.tip) do
			if i == 1 then GameTooltip:SetText(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
		end
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f:Hide()
	return f
end

-- La guerra que toca enseñar: la que está en curso o la próxima que empieza en 15 minutos.
local function currentWar()
	local g = LG:GuildData()
	if not g then return nil end
	local now = ns.Now()
	local best, bestPhase
	for _, w in pairs(g.wars) do
		local phase = ns.WarPhase(w, now)
		if phase == "active" and (bestPhase ~= "active" or w.start < best.start) then
			best, bestPhase = w, phase
		elseif phase == "upcoming" and w.start - now <= BEFORE and bestPhase ~= "active" and (not best or w.start < best.start) then
			best, bestPhase = w, phase
		end
	end
	return best, bestPhase
end

local function minutes(seconds)
	return math.max(0, math.ceil(seconds / 60))
end

function ns.RefreshWarHud()
	if not LG.db or not LG:HasConsent() or ns.WARS_PAUSED then
		if hud then hud:Hide() end
		return
	end
	local w, phase = currentWar()
	if not w or w.id == hiddenFor then
		if hud then hud:Hide() end
		return
	end
	hud = hud or create()
	hud.warID = w.id
	local enemy = ns.WarEnemy(w)
	local zone = ns.MapName(w.map, w.zone)
	hud.title:SetText((L["Guerra contra <%s>"]):format(enemy))
	if phase == "active" then
		local s = ns.WarScore(w)
		local color = s.ours > s.theirs and GREEN or (s.ours < s.theirs and RED or GOLD)
		hud.score:SetText(color .. ("%d – %d"):format(s.ours, s.theirs) .. R)
		local ourCount = ns.WarPresence(w)
		hud.state:SetText((L["quedan %d min"]):format(minutes(w.start + w.duration - ns.Now())) .. "\n"
			.. GREY .. (L["En la zona: %d · %s"]):format(ourCount, w.report and tostring(w.report.present) or "?") .. R)
		hud.tip = { (L["Guerra contra <%s>"]):format(enemy), zone,
			s.confirmed and (GREEN .. L["Marcador confirmado por el rival."] .. R) or (GREY .. L["Marcador según nuestro registro."] .. R),
			GREY .. L["Clic para ver la guerra · arrastra para moverlo."] .. R }
	else
		hud.score:SetText(GOLD .. (L["En %d min"]):format(minutes(w.start - ns.Now())) .. R)
		hud.state:SetText(zone)
		hud.tip = { (L["Guerra contra <%s>"]):format(enemy), zone, GREY .. L["Clic para ver la guerra · arrastra para moverlo."] .. R }
	end
	hud.layer:SetText(ns.WarLayerText and ns.WarLayerText(w, true) or "")
	hud:Show()
end

function WarHud:OnEnable()
	ns.OnDataChanged(ns.RefreshWarHud)
	self:ScheduleRepeatingTimer(ns.RefreshWarHud, 5)
	self:ScheduleTimer(ns.RefreshWarHud, 3)
end
