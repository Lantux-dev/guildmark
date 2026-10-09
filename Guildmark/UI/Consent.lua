-- Ventanas de consentimiento y de borrado de datos.
local _, ns = ...
local L = ns.L
local LG = ns.LG

StaticPopupDialogs["LANTUX_CONSENT"] = {
	-- Un único texto (una sola clave de traducción).
	text = "|cffffd100" .. ns.ADDON_TITLE .. "|r\n\n" .. L["Si aceptas, se comparte con tu hermandad:\nnombre, clase, raza, nivel, idioma del cliente, estadísticas de honor y rango JcJ, profesiones y recetas, lo que recolectas y fabricas (cantidades), las mazmorras que completas, jefes derrotados en grupo y tus kills y muertes contra otros jugadores (con la hermandad del rival).\n\nLo que estás haciendo (mazmorra, banda, zona y capa) y con quién vas en grupo se comparte con tu hermandad.\n\nTu hermandad sale en un directorio público del addon y en la clasificación de la facción con sus totales de la temporada (miembros, kills, asaltos, logros, mejores tiempos); lo ven las demás hermandades con el addon, también de la otra facción. Un oficial puede ocultarla. Las llamadas de auxilio y los asaltos avisan a tu facción de tu hermandad, la zona y la capa; si acudes a una, la hermandad que la hizo ve tu nombre para invitarte.\n\nOtros jugadores con el addon pueden ver tu rango del addon, tu rango JcJ, tu tribu y los honores de tu hermandad (se puede quitar en Ajustes).\n\nTambién se comparte con tu hermandad tu actividad con las insignias (subastas, pujas, donaciones al cofre, compras de la tienda, botín de guerra y recompensas), tus resultados en campos de batalla, tu ficha de rol (título, papel y el lema y la historia que escribas) y tus aportaciones al banco de la hermandad (oro y objetos que metes y sacas, leídos de su registro).\n\nTu hermandad puede mostrar estos datos fuera del juego (por ejemplo, en su Discord o su web).\n\nOpcional y desactivado: lista de alts y tiempo jugado (/gmk opcional).\nNunca se recoge el contenido del chat.\n\nPuedes borrar tus datos cuando quieras con /gmk borrar."],
	button1 = L["Acepto"],
	button2 = L["Ahora no"],
	OnAccept = function() LG:SetConsent(true) end,
	OnCancel = function(_, _, reason)
		if reason == "clicked" then LG:SetConsent(false) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["LANTUX_WIPE"] = {
	text = L["¿Borrar todos tus datos del addon?\n\nSe borran en este PC y se pide a los addons de la hermandad que los borren también. Dejarás de compartir datos."],
	button1 = L["Borrar"],
	button2 = CANCEL,
	OnAccept = function() LG:WipeMyData() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function ns.ShowConsent()
	StaticPopup_Show("LANTUX_CONSENT")
end
