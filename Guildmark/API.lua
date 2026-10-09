-- API pública para complementos (otros addons que se apoyan en este).
--
-- El addon no sabe nada de servicios externos. Un complemento puede añadir un
-- botón "Publicar" en los apartados (registrando un publicador) y leer un
-- resumen de la hermandad ya calculado. Nada de lo que se expone permite
-- cambiar los datos de la hermandad ni enviar mensajes en su nombre.
--
--   GuildmarkAPI.RegisterPublisher({ button = function(section) ... end, publish = function(section) ... end })
--   GuildmarkAPI.BuildSummary()   -> resumen de la hermandad (clasificación, caza, eventos, desafíos)
--   GuildmarkAPI.IsGuildMaster()  -> true si eres maestro de hermandad (o en modo prueba)
--   GuildmarkAPI.GuildName()      -> hermandad actual (o "~Pruebas" en modo prueba)
--   GuildmarkAPI.ShowDialog(spec) -> ventana de formulario del addon
--   GuildmarkAPI.Refresh()        -> repinta la ventana
local _, ns = ...
local LG = ns.LG

-- Publicador registrado por un complemento (nil sin complementos).
ns.publisher = nil

-- Botón de publicar para la cabecera de un apartado, si hay complemento.
function ns.PublishButton(section)
	local p = ns.publisher
	if not p or not p.button then return nil end
	local ok, def = pcall(p.button, section)
	return ok and def or nil
end

function ns.Publish(section)
	local p = ns.publisher
	if p and p.publish then pcall(p.publish, section) end
end

GuildmarkAPI = {
	version = 1,
	RegisterPublisher = function(p)
		if type(p) == "table" then
			ns.publisher = p
			if ns.RefreshMainFrame then ns.RefreshMainFrame() end
			if ns.RefreshAchievements then ns.RefreshAchievements() end
		end
	end,
	BuildSummary = function() return ns.BuildExport and ns.BuildExport() or nil end,
	IsGuildMaster = function() return ns.IsGuildMaster and ns.IsGuildMaster() or false end,
	GuildName = function() return LG:GuildName() end,
	ShowDialog = function(spec) return ns.ShowInputDialog(spec) end,
	Refresh = function() if ns.RefreshMainFrame then ns.RefreshMainFrame() end end,
}
