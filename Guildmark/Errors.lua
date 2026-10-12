-- Registro de los errores de Lua del propio addon.
--
-- Un addon no puede enviar nada fuera del juego, así que los fallos solo llegan si el
-- jugador los cuenta, y casi todo el mundo juega con los errores de Lua ocultos. Aquí se
-- guardan los errores que salen de los archivos de Guildmark (los 20 últimos, sin repetir)
-- y /gmk errores abre una ventana con el texto listo para copiar (UI/ErrorsFrame.lua).
--
-- No se sustituye el gestor de errores del juego: se escucha, con hooksecurefunc, la
-- ventana de errores de Blizzard, que recibe todos los errores aunque esté oculta. Si hay
-- BugGrabber (que sí sustituye el gestor), se le pide que avise.
local ADDON_NAME, ns = ...
local L = ns.L

local MAX_ERRORS = 20
local MAX_STACK = 1500
local ISSUES_URL = "https://github.com/Lantux-dev/guildmark/issues"
ns.ERRORS_URL = ISSUES_URL

local early = {}  -- errores anteriores a que existan los datos guardados
local notified    -- ya se avisó en el chat en esta sesión
local busy        -- un error dentro del registro no se vuelve a registrar

-- Texto legible (ni secreto ni inaccesible) o nil.
local function plain(v)
	if type(v) ~= "string" then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	if canaccessvalue and not canaccessvalue(v) then return nil end
	return v
end

-- ¿El error sale de un archivo de este addon? (no de Guildmark_Discord ni de otro addon)
local function isOurs(text)
	return text:find("AddOns[/\\]" .. ADDON_NAME .. "[/\\]") ~= nil
end

local function list()
	local LG = ns.LG
	local global = LG and LG.db and LG.db.global
	if not global then return early end
	global.errors = global.errors or {}
	return global.errors
end

local function version()
	return ns.LG and ns.LG.VERSION or "?"
end

local function notify()
	if notified then return end
	notified = true
	local function say()
		if ns.LG and ns.LG.Print then
			ns.LG:Print("|cffff6b5a" .. L["Guildmark ha tenido un error."] .. "|r " .. L["Escribe /gmk errores para verlo y copiarlo."])
		end
	end
	if C_Timer and C_Timer.After then C_Timer.After(1, say) else say() end
end

local function record(message, stack)
	message, stack = plain(message), plain(stack) or ""
	if not message then return false end
	if not isOurs(message) and not isOurs(stack) then return false end
	local errors = list()
	local found
	for _, e in ipairs(errors) do
		if e.msg == message then found = e break end
	end
	if found then
		found.n = (found.n or 1) + 1
		found.t = date("%Y-%m-%d %H:%M:%S")
		found.v = version()
	else
		table.insert(errors, 1, { msg = message, stack = stack:sub(1, MAX_STACK), t = date("%Y-%m-%d %H:%M:%S"), n = 1, v = version() })
		for i = #errors, MAX_ERRORS + 1, -1 do errors[i] = nil end
	end
	notify()
	return true
end

-- Apunta un error del addon. Devuelve true si se guardó (o se sumó a uno repetido).
function ns.RecordError(message, stack)
	if busy then return false end
	busy = true
	local ok, saved = pcall(record, message, stack)
	busy = nil
	return ok and saved or false
end

-- Al crearse los datos guardados, los errores de la carga pasan a ellos.
function ns.ErrorsReady()
	local pending = early
	early = {}
	for i = #pending, 1, -1 do
		local e = pending[i]
		local errors = list()
		local found
		for _, old in ipairs(errors) do
			if old.msg == e.msg then found = old break end
		end
		if found then
			found.n, found.t, found.v = (found.n or 1) + (e.n or 1), e.t, e.v
		else
			table.insert(errors, 1, e)
		end
	end
	local errors = list()
	for i = #errors, MAX_ERRORS + 1, -1 do errors[i] = nil end
end

-- Un error a propósito (/gmk errores prueba), para comprobar que el registro funciona.
function ns.TestError()
	local function fail() error("error de prueba (/gmk errores prueba)") end
	if C_Timer and C_Timer.After then C_Timer.After(0, fail) else fail() end
end

function ns.ErrorCount()
	return #list()
end

function ns.ClearErrors()
	local errors = list()
	for i = #errors, 1, -1 do errors[i] = nil end
end

-- El informe para pegar en un comentario o en una incidencia: sin colores del juego.
local function clean(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return (text:gsub("|", "||"))
end

function ns.ErrorReport()
	local errors = list()
	local build, buildNumber = "?", "?"
	if GetBuildInfo then build, buildNumber = GetBuildInfo() end
	local lines = {
		("Guildmark %s  ·  WoW %s (%s)  ·  %s  ·  %s"):format(version(), tostring(build), tostring(buildNumber), ns.LOCALE or "?", date("%Y-%m-%d %H:%M")),
	}
	if #errors == 0 then
		lines[#lines + 1] = L["Sin errores registrados."]
		return table.concat(lines, "\n")
	end
	for i, e in ipairs(errors) do
		lines[#lines + 1] = ""
		lines[#lines + 1] = ("[%d] x%d  ·  %s  ·  v%s"):format(i, e.n or 1, e.t or "?", e.v or "?")
		lines[#lines + 1] = clean(e.msg or "?")
		if e.stack and e.stack ~= "" then lines[#lines + 1] = clean(e.stack) end
	end
	return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- De dónde llegan los errores
---------------------------------------------------------------------------

local hooked

local function hookBlizzard()
	if hooked or not hooksecurefunc then return end
	local errorsFrame = ScriptErrorsFrame
	if type(errorsFrame) ~= "table" or type(errorsFrame.DisplayMessageInternal) ~= "function" then return end
	hooked = true
	-- messageType 0 = error (1 = aviso).
	hooksecurefunc(errorsFrame, "DisplayMessageInternal", function(_, message, messageType, stack)
		if messageType ~= 0 then return end
		ns.RecordError(message, stack)
	end)
end

local function hookBugGrabber()
	local grabber = BugGrabber
	if type(grabber) ~= "table" or type(grabber.RegisterCallback) ~= "function" or grabber.guildmarkHooked then return end
	grabber.guildmarkHooked = true
	pcall(grabber.RegisterCallback, ns, "BugGrabber_BugGrabbed", function(_, bug)
		if type(bug) == "table" then ns.RecordError(bug.message, bug.stack) end
	end)
end

hookBlizzard()
hookBugGrabber()

-- La ventana de errores de Blizzard o BugGrabber pueden cargarse después que este addon.
if CreateFrame then
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:RegisterEvent("PLAYER_LOGIN")
	watcher:SetScript("OnEvent", function()
		hookBlizzard()
		hookBugGrabber()
	end)
end
