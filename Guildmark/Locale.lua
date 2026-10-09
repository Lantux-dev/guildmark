-- Textos de la interfaz.
--
-- Los textos se escriben en español en el propio código, como L["..."]: la
-- clave es el texto en español. Con el cliente del juego en español (esES,
-- esMX) se muestran tal cual; en cualquier otro idioma, Locales/enUS.lua
-- rellena esta tabla con la traducción al inglés. Si falta alguna, se ve en
-- español (tools/locale.js avisa de las que faltan).
local _, ns = ...

ns.LOCALE = GetLocale and GetLocale() or "esES"
ns.IS_SPANISH = ns.LOCALE == "esES" or ns.LOCALE == "esMX"

ns.L = setmetatable({}, { __index = function(_, key) return key end })
-- Nombre del addon tal como se muestra (la carpeta y los datos guardados también
-- se llaman Guildmark desde la 1.0.0).
ns.ADDON_TITLE = "Guildmark"
