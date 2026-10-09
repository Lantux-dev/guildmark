-- Botón del minimapa: clic para abrir la ventana, arrastrar para moverlo alrededor del minimapa.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local button

local function position()
	local angle = math.rad(LG.db.profile.minimap.angle)
	local radius = (Minimap:GetWidth() / 2) + 10
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	LG.db.profile.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
	position()
end

local function create()
	button = CreateFrame("Button", "LantuxGuildMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture(ns.MEDIA .. "emblem_small")
	icon:SetSize(21, 21)
	icon:SetPoint("TOPLEFT", 6, -5)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then ns.ShowConsent() else ns.ToggleMainFrame() end
	end)
	button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(ns.ADDON_TITLE)
		GameTooltip:AddLine(L["Clic: abrir"], 1, 1, 1)
		GameTooltip:AddLine(L["Clic derecho: privacidad"], 1, 1, 1)
		GameTooltip:AddLine(L["Arrastrar: mover"], 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function ns.UpdateMinimapButton()
	if not button then create() end
	position()
	button:SetShown(not LG.db.profile.minimap.hide)
end
