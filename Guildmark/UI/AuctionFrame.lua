-- Ventana para abrir una subasta de hermandad: cualquier miembro con un objeto suyo
-- (1 día), o un oficial con uno del banco (bank, con la duración que quiera).
-- Las pujas se hacen desde la pestaña Mercado de la ventana principal.
local _, ns = ...
local L = ns.L

local GREY = "|cff9d9d9d"

local function itemIcon(itemID)
	if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
	return GetItemIcon and GetItemIcon(itemID) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local startFrame

local function setStartItem(link)
	local itemID = link and tonumber(link:match("item:(%d+)"))
	startFrame.link = itemID and link or nil
	startFrame.slot.link = startFrame.link
	startFrame.slot.icon:SetTexture(itemID and itemIcon(itemID) or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
	startFrame.name:SetText(startFrame.link or (GREY .. L["Arrastra aquí un objeto o haz mayúsculas + clic en él."] .. "|r"))
	startFrame.start:SetEnabled(startFrame.link ~= nil)
end

local function numberBox(parent, anchor, width, label)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("LEFT", anchor, "RIGHT", anchor == parent and 16 or 20, 0)
	fs:SetText(label)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 20)
	box:SetPoint("LEFT", fs, "RIGHT", 12, 0)
	box:SetAutoFocus(false)
	return box, fs
end

local function create()
	local f = CreateFrame("Frame", "LantuxGuildAuctionStart", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(380, 200)
	f:SetPoint("CENTER", 0, 80)
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.title:SetPoint("TOP", 0, -5)
	f.title:SetText(L["Nueva subasta de hermandad"])

	f.slot = CreateFrame("Button", nil, f)
	f.slot:SetSize(40, 40)
	f.slot:SetPoint("TOPLEFT", 16, -34)
	f.slot.icon = f.slot:CreateTexture(nil, "ARTWORK")
	f.slot.icon:SetAllPoints()
	f.slot:SetScript("OnEnter", function(self)
		if self.link then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self.link)
			GameTooltip:Show()
		end
	end)
	f.slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local function takeCursorItem()
		local kind, _, link = GetCursorInfo()
		if kind == "item" and link then
			setStartItem(link)
			ClearCursor()
		end
	end
	f.slot:SetScript("OnReceiveDrag", takeCursorItem)
	f.slot:SetScript("OnClick", takeCursorItem)

	f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.name:SetPoint("LEFT", f.slot, "RIGHT", 10, 0)
	f.name:SetPoint("RIGHT", -12, 0)
	f.name:SetJustifyH("LEFT")

	local minLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	minLabel:SetPoint("TOPLEFT", 16, -92)
	minLabel:SetText(L["Puja mínima"])
	f.min = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	f.min:SetSize(50, 20)
	f.min:SetPoint("LEFT", minLabel, "RIGHT", 12, 0)
	f.min:SetAutoFocus(false)
	f.min:SetNumeric(true)
	f.hours, f.hoursLabel = numberBox(f, f.min, 40, L["Duración (horas)"])

	f.help = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.help:SetPoint("TOPLEFT", 16, -118)
	f.help:SetPoint("RIGHT", -16, 0)
	f.help:SetJustifyH("LEFT")

	f.error = f:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
	f.error:SetPoint("TOPLEFT", 16, -146)
	f.error:SetPoint("RIGHT", -16, 0)
	f.error:SetJustifyH("LEFT")

	f.start = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.start:SetSize(130, 24)
	f.start:SetPoint("BOTTOMRIGHT", -16, 12)
	f.start:SetText(L["Abrir subasta"])
	f.start:SetScript("OnClick", function()
		local hours = tonumber(((f.hours:GetText() or ""):gsub(",", ".")))
		local ok, err = ns.StartAuction(f.link, tonumber(f.min:GetText()), hours, f.bank)
		if ok then f:Hide() else f.error:SetText(err or "") end
	end)
	local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	cancel:SetSize(100, 24)
	cancel:SetPoint("RIGHT", f.start, "LEFT", -6, 0)
	cancel:SetText(CANCEL)
	cancel:SetScript("OnClick", function() f:Hide() end)
	startFrame = f

	-- Mayúsculas + clic en un objeto (bolsas, banco, chat) con la ventana abierta lo pone aquí.
	-- hooksecurefunc solo escucha después de Blizzard, sin alterar su código.
	if HandleModifiedItemClick then
		hooksecurefunc("HandleModifiedItemClick", function(link)
			if startFrame:IsShown() and IsModifiedClick("CHATLINK") and link then setStartItem(link) end
		end)
	end
end

-- bank = true: objeto del banco de la hermandad (oficiales; el pago va entero al cofre).
function ns.ShowAuctionStart(link, bank)
	if bank and not ns.Can("bankAuction", ns.PlayerFullName()) then
		print("|cffff6b5aGuildmark:|r " .. L["Tu rango no puede subastar objetos del banco."])
		return
	end
	if not startFrame then create() end
	startFrame.bank = bank and true or nil
	startFrame.title:SetText(bank and L["Subasta del banco de la hermandad"] or L["Nueva subasta de hermandad"])
	startFrame.hours:SetShown(bank and true or false)
	startFrame.hoursLabel:SetShown(bank and true or false)
	startFrame.help:SetText(bank and L["Todo lo que se pague va al cofre de hermandad. Para subastar en directo en una banda, pon 0,1 h (6 min)."]
		or L["Dura 1 día. Cobras el 90 % de la puja ganadora (el 10 % va al cofre) y le pasas el objeto al ganador por intercambio."])
	startFrame.min:SetText(tostring(ns.AUCTION_DEFAULTS.minBid))
	startFrame.hours:SetText(tostring(ns.AUCTION_DEFAULTS.hours))
	startFrame.error:SetText("")
	setStartItem(link)
	startFrame:Show()
end
