-- Tienda de la hermandad: lo que cada uno compra con sus insignias.
--
-- Cosméticos del perfil (marco y terciopelo del estuche de medallas), que los
-- demás ven en tu perfil, y tasas: crear una tribu y cambiar su icono.
--
-- Una compra (BUY) solo vale si en ese momento tenías las insignias: se
-- resuelve al recorrer el libro de puntos (Merits.lua), igual en todos los
-- addons. La tasa de una tribu que un oficial rechaza no se cobra.
local _, ns = ...
local L = ns.L
local LG = ns.LG

-- kind: "frame" y "velvet" se compran una vez y se eligen en el perfil; "fee" se paga cada vez.
ns.SHOP_ITEMS = {
	{ key = "frame_bronze", short = L["Bronce"], kind = "frame", price = 100, label = L["Marco de bronce"], color = { 0.8, 0.5, 0.25 },
		icon = "Interface\\Icons\\INV_Jewelry_Ring_01", desc = L["Aro de bronce en tu retrato y borde del estuche a juego."] },
	{ key = "frame_silver", short = L["Plata"], kind = "frame", price = 250, label = L["Marco de plata"], color = { 0.78, 0.8, 0.85 },
		icon = "Interface\\Icons\\INV_Jewelry_Ring_02", desc = L["Aro de plata en tu retrato y borde del estuche a juego."] },
	{ key = "frame_gold", short = L["Oro"], kind = "frame", price = 500, label = L["Marco de oro"], color = { 1, 0.82, 0.2 },
		icon = "Interface\\Icons\\INV_Jewelry_Ring_03", desc = L["Aro de oro en tu retrato y borde del estuche a juego."] },
	{ key = "velvet_blue", short = L["Azul"], kind = "velvet", price = 75, label = L["Terciopelo azul"], color = { 0.05, 0.09, 0.22 },
		icon = "Interface\\Icons\\INV_Fabric_Mageweave_02", desc = L["Fondo azul para tu estuche de medallas."] },
	{ key = "velvet_green", short = L["Verde"], kind = "velvet", price = 75, label = L["Terciopelo verde"], color = { 0.04, 0.16, 0.07 },
		icon = "Interface\\Icons\\INV_Fabric_Wool_02", desc = L["Fondo verde para tu estuche de medallas."] },
	{ key = "velvet_black", short = L["Negro"], kind = "velvet", price = 75, label = L["Terciopelo negro"], color = { 0.04, 0.04, 0.05 },
		icon = "Interface\\Icons\\INV_Fabric_Felcloth_01", desc = L["Fondo negro para tu estuche de medallas."] },
	{ key = "velvet_purple", short = L["Púrpura"], kind = "velvet", price = 150, label = L["Terciopelo púrpura"], color = { 0.15, 0.04, 0.2 },
		icon = "Interface\\Icons\\INV_Fabric_Silk_02", desc = L["Fondo púrpura real para tu estuche de medallas."] },
	{ key = "tribeCreate", kind = "fee", price = 100, label = L["Fundar una tribu"],
		icon = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude", desc = L["Se paga al proponerla; si un oficial la rechaza, no se cobra."] },
	{ key = "tribeIcon", kind = "fee", price = 50, label = L["Icono de tribu"],
		icon = "Interface\\Icons\\INV_Misc_Note_02", desc = L["Cambiar el icono de tu tribu por uno elegido."] },
}
local ITEMS = {}
for _, item in ipairs(ns.SHOP_ITEMS) do ITEMS[item.key] = item end
function ns.ShopItem(key) return ITEMS[key] end

-- El terciopelo rojo del estuche es el de siempre: no se compra.
ns.DEFAULT_VELVET = { 0.2, 0.05, 0.07 }

---------------------------------------------------------------------------
-- Datos
---------------------------------------------------------------------------

function ns.MergePurchase(g, rec, sender)
	if type(rec.id) ~= "string" or type(rec.member) ~= "string" or type(rec.t) ~= "number" then return false end
	if not ITEMS[rec.item] then return false end
	if rec.ref ~= nil and type(rec.ref) ~= "string" then return false end
	if g.purchases[rec.id] then return false end
	if sender and rec.member ~= sender then return false end
	g.purchases[rec.id] = { id = rec.id, member = rec.member, t = rec.t, item = rec.item, ref = rec.ref }
	return true
end

ns.handlers.BUY = function(sender, rec)
	local g = LG:GuildData()
	if g and type(rec) == "table" and ns.MergePurchase(g, rec, sender) then LG:DataChanged() end
end

-- ¿La compra cuenta? (la tasa de una tribu rechazada no se cobra)
function ns.PurchaseCharged(g, p)
	if p.item == "tribeCreate" and p.ref then
		local tribe = g.tribes and g.tribes[p.ref]
		if tribe and tribe.status == "rejected" then return false end
	end
	return true
end

-- ¿Tiene el miembro ese cosmético? (lo resuelve Merits.lua)
function ns.Owns(name, key)
	return ns.ShopOwned()[name .. "|" .. key] ~= nil
end

-- Paga algo de la tienda (ref: la tribu, para las tasas). Devuelve ok, error.
function ns.Buy(key, ref)
	local g = LG:GuildData()
	local item = ITEMS[key]
	local me = ns.PlayerFullName()
	if not g or not item then return false, L["No estás en una hermandad."] end
	if item.kind ~= "fee" and ns.Owns(me, key) then return false, L["Ya lo tienes."] end
	local free = ns.AvailableInsignias(nil)
	if free < item.price then return false, (L["Cuesta %d insignias y tienes %d libres."]):format(item.price, free) end
	local now = ns.Now()
	local rec = { id = ("%s:buy:%d:%d"):format(me, now, math.random(1000, 9999)), member = me, t = now, item = key, ref = ref }
	ns.MergePurchase(g, rec)
	LG:Send("BUY", rec)
	LG:DataChanged()
	if item.kind ~= "fee" then LG:Print((L["Has comprado: %s."]):format(item.label)) end
	return true
end

-- Elegir el marco o el terciopelo del perfil (nil = el de siempre).
function ns.UseCosmetic(kind, key)
	if key and not ns.Owns(ns.PlayerFullName(), key) then return false end
	ns.SaveProfile({ [kind] = key or "" })
	return true
end
