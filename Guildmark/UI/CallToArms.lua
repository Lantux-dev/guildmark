-- Llamada a las armas: cuando matan a un compañero, aviso al resto de la
-- hermandad con quién ha sido, dónde y el tiempo que queda para vengarlo.
--
-- Por defecto, aviso grande solo si estás en la misma zona; si no, una línea
-- en el chat. Se cambia en Caza (Siempre / Solo mi zona / Nunca).
local _, ns = ...
local L = ns.L
local LG = ns.LG

local REVENGE_WINDOW = 600  -- igual que la venganza del cazarrecompensas
local MAX_AGE = 90          -- no se avisa de muertes de hace más de 90 s (p. ej. al sincronizar)
local THROTTLE = 15         -- como mucho un aviso grande cada 15 s
local SHOW_FOR = 12

ns.CALL_MODES = {
	{ key = "always", label = L["Siempre"] },
	{ key = "zone", label = L["Solo mi zona"] },
	{ key = "off", label = L["Nunca"] },
}

function ns.CallToArmsMode()
	return LG.db and LG.db.profile.callToArms or "zone"
end

function ns.CycleCallToArmsMode()
	local current = ns.CallToArmsMode()
	for i, m in ipairs(ns.CALL_MODES) do
		if m.key == current then
			LG.db.profile.callToArms = ns.CALL_MODES[i % #ns.CALL_MODES + 1].key
			break
		end
	end
	LG:DataChanged()
end

local banner, lastShown = nil, 0

local function create()
	local f = CreateFrame("Button", "LantuxGuildCallToArms", UIParent)
	f:SetSize(460, 70)
	f:SetPoint("TOP", 0, -110)
	f:SetFrameStrata("HIGH")
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetColorTexture(0.12, 0.02, 0.02, 0.88)
	f.glow = f:CreateTexture(nil, "BORDER")
	f.glow:SetPoint("TOPLEFT")
	f.glow:SetPoint("TOPRIGHT")
	f.glow:SetHeight(2)
	f.glow:SetColorTexture(0.95, 0.2, 0.12, 1)
	f.stripe = f:CreateTexture(nil, "BORDER")
	f.stripe:SetPoint("TOPLEFT")
	f.stripe:SetPoint("BOTTOMLEFT")
	f.stripe:SetWidth(4)
	f.stripe:SetColorTexture(0.95, 0.2, 0.12, 1)

	f.iconBorder = f:CreateTexture(nil, "BORDER")
	f.iconBorder:SetSize(50, 50)
	f.iconBorder:SetPoint("LEFT", 14, 0)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(46, 46)
	f.icon:SetPoint("CENTER", f.iconBorder, "CENTER")

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", 76, -12)
	f.title:SetPoint("RIGHT", -70, 0)
	f.title:SetJustifyH("LEFT")
	f.title:SetWordWrap(false)
	f.line = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.line:SetPoint("TOPLEFT", 76, -38)
	f.line:SetPoint("RIGHT", -70, 0)
	f.line:SetJustifyH("LEFT")
	f.line:SetWordWrap(false)

	f.timer = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.timer:SetPoint("RIGHT", -16, 6)
	f.timerLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.timerLabel:SetPoint("TOP", f.timer, "BOTTOM", 0, -2)
	f.timerLabel:SetText(L["venganza"])

	f:SetScript("OnClick", function(self) self:Hide() end)
	f:SetScript("OnUpdate", function(self, elapsed)
		self.age = (self.age or 0) + elapsed
		local left = math.max(0, (self.deadline or 0) - ns.Now())
		self.timer:SetText(("%d:%02d"):format(math.floor(left / 60), left % 60))
		if self.age > SHOW_FOR then
			self:SetAlpha(math.max(0, 1 - (self.age - SHOW_FOR)))
			if self.age > SHOW_FOR + 1 then self:Hide() end
		end
	end)
	banner = f
end

local function classIcon(texture, classFile)
	local coords = CLASS_ICON_TCOORDS and classFile and CLASS_ICON_TCOORDS[classFile]
	if coords then
		texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
		texture:SetTexCoord(unpack(coords))
	else
		texture:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
		texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end
end

-- rec: registro de muerte (kind = "death") de un miembro de la hermandad.
function ns.CallToArms(rec, force)
	if not force then
		if rec.kind ~= "death" or rec.reporter == ns.PlayerFullName() then return end
		if ns.Now() - (rec.t or 0) > MAX_AGE then return end
	end
	local mode = ns.CallToArmsMode()
	if mode == "off" and not force then return end

	local victim = ns.ShortName(rec.victimName) or "?"
	local killer = ns.ShortName(rec.killerName) or "?"
	local guild = rec.guild and (" <" .. rec.guild .. ">") or ""
	local zone = rec.zone or "?"
	local sameZone = zone == GetZoneText()

	if not force and (mode == "zone" and not sameZone) then
		LG:Print((L["|cffff6b5a%s ha caído|r en %s a manos de %s%s."]):format(victim, zone, killer, guild))
		return
	end
	if not force and GetTime() - lastShown < THROTTLE then
		LG:Print((L["|cffff6b5a%s ha caído|r en %s a manos de %s%s."]):format(victim, zone, killer, guild))
		return
	end
	if not force then lastShown = GetTime() end -- el aviso de prueba no cuenta para el límite

	if not banner then create() end
	local classColor = rec.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[rec.class]
	banner.iconBorder:SetColorTexture(classColor and classColor.r or 0.6, classColor and classColor.g or 0.1, classColor and classColor.b or 0.08, 1)
	classIcon(banner.icon, rec.class)
	banner.title:SetText((L["¡%s ha caído en %s!"]):format(victim, zone))
	banner.line:SetText(ns.ClassColorName(rec.killerName, rec.class) .. "|cffff6b5a" .. guild .. "|r  " ..
		(sameZone and ("|cffffd100" .. L["¡está cerca!"] .. "|r") or ""))
	banner.deadline = (rec.t or ns.Now()) + REVENGE_WINDOW
	banner.age = 0
	banner:SetAlpha(1)
	banner:Show()
	pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959)
end

-- Botón de Oficial en modo prueba: un aviso de ejemplo para ver cómo queda.
function ns.TestCallToArms()
	ns.CallToArms({
		kind = "death", t = ns.Now(), victimName = "Vexa Sombrafría", killerName = "Aldric Escudoalto",
		class = "PALADIN", guild = "Guardia de Ventormenta", zone = GetZoneText(),
	}, true)
end
