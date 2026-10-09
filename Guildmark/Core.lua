local ADDON_NAME, ns = ...
local L = ns.L

local LG = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceComm-3.0")
ns.LG = LG

-- Imágenes propias del addon (TGA de 32 bits con transparencia, medidas en potencia de 2).
ns.MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"

local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
LG.VERSION = GetAddOnMetadata(ADDON_NAME, "Version") or "0.0.0"

-- Tiempo mínimo entre dos envíos de nuestro propio registro a la guild.
local RECORD_THROTTLE = 120
-- Sube cuando cambia lo que se comparte: quien ya aceptó vuelve a ver el aviso.
-- 2: guerras entre hermandades y directorio público.
-- 3: actividad (Ahora), tribus e insignias visibles para otros usuarios del addon.
local CONSENT_VERSION = 5

local defaults = {
	profile = {
		minimap = { angle = 215, hide = false },
		debug = false,
		testMode = false,
		callToArms = "zone", -- "always" | "zone" | "off"
		banner = { player = true, target = true, share = true }, -- insignias sobre los marcos (UI/Banner.lua)
	},
	char = {
		consent = "pending", -- "pending" | "yes" | "no"
		optional = { alts = false, played = false },
		levelHistory = {},
		played = nil,
		joined = {},      -- [hermandad] = primera vez que el addon te vio en ella
		professions = {}, -- [skillLine] = { name, rank, max }
		recipes = {},     -- [professionID] = { name, ids = { recetas aprendidas } }
		wager = {},       -- botín de guerra: { periods = { { desde, hasta } } } (Bounty.lua)
		profile = {},     -- ficha de rol: título, papel, lema, historia e insignias del retrato (Profile.lua)
		hkBase = {},      -- [hermandad] = { t, hk }: contador de honor cuando el addon empezó a contar
		stats = {         -- recolección y fabricación (Modules/Gathering.lua)
			gathered = { mining = 0, herb = 0, skinning = 0 },
			crafted = 0, crafts = 0, bestDay = 0,
		},
	},
	factionrealm = {
		guilds = {
			["*"] = {
				members = {},    -- [nombreCompleto] = registro del miembro
				kills = {},      -- [id] = kill o muerte en PvP
				runs = {},       -- [clave] = jefe derrotado en mazmorra
				guildCache = {}, -- [GUID] = hermandad y datos vistos de otros jugadores
				orders = {},     -- [id] = encargo de artesanía
				events = {},     -- [id] = evento de hermandad
				signups = {},    -- [idEvento][miembro] = { status, role, t }
				attendance = {}, -- [idEvento][miembro] = momento en que se confirmó
				adjustments = {}, -- [id] = ajuste de puntos de un oficial
				targets = {},    -- [hermandad] = { active, by, t }: objetivos manuales
				spends = {},     -- [idSubasta] = insignias pagadas por el ganador
				auctions = {},   -- [id] = subasta de hermandad
				bids = {},       -- [idSubasta][miembro] = { amount, t }: su puja más alta
				achievements = {}, -- [idDesafío] = { t }: cuándo lo completó la hermandad
				voids = {},      -- [id de kill, encargo, asistencia o ajuste] = anulación de un oficial
				dismissed = {},  -- [clave de aviso] = true: avisos marcados como vistos (solo en este PC)
				settings = {},   -- [clave] = { value, by, t }: ajustes de la hermandad (p. ej. salir en el directorio)
				wars = {},       -- [id] = guerra con otra hermandad (Modules/Wars.lua)
				warSeen = {},    -- [idGuerra][miembro] = true: vistos en la zona de la guerra (solo en este PC)
				lfg = {},       -- [id] = grupo publicado en el buscador de grupo (Modules/LFG.lua)
				tribes = {},     -- [id] = tribu (Modules/Tribes.lua)
				tribeAccepts = {}, -- [idTribu][miembro] = cuándo aceptó
				tribeLeft = {},  -- [idTribu][miembro] = cuándo se salió
				tribeInvites = {}, -- [idTribu][miembro] = { t, by }: invitaciones del líder
				tribeIcons = {},  -- [idTribu] = { icon, by, t }: icono elegido por el líder (Tribes.lua)
				calls = {},       -- [id] = llamadas de auxilio y asaltos de la hermandad, con su resultado (Aid.lua)
				aidHelps = {},    -- [id|miembro] = miembros que llegaron a ayudar a otra hermandad
				regicides = {},   -- [id] = líderes enemigos derribados
				honorSeen = {},   -- [miembro] = { hk, today, t, by }: su contador visto al inspeccionarle (Integrity.lua)
				projects = {},    -- [id] = proyecto de hermandad (Chest.lua)
				donations = {},   -- [id] = donación de un miembro al cofre o a un proyecto
				chestMoves = {},  -- [id] = insignias que un oficial pasa del cofre a un proyecto
				bgMatches = {},   -- [id] = resultado de un campo de batalla de un miembro (PvP.lua)
				bounties = {},    -- [id] = insignias puestas por la cabeza de un enemigo (Bounty.lua)
				purchases = {},   -- [id] = compra en la tienda (Shop.lua)
				bankLog = {},     -- [clave] = depósito o retirada en el banco de la hermandad del juego (GuildBank.lua)
				bankRequests = {}, -- [id] = pedido del banco: objeto, cantidad y recompensa del cofre (GuildBank.lua)
			},
		},
	},
	global = {
		chars = {}, -- personajes de esta cuenta, para la lista de alts
		blocked = {}, -- diagnóstico de acciones bloqueadas por Blizzard
		forbiddenEvents = {}, -- [evento] = fecha en que Blizzard prohibió registrarlo
		diag = {}, -- resultados de /gmk diag y /gmk dump
		recapDebug = {}, -- volcado del informe de muerte de las últimas muertes
		castDebug = {},  -- últimos hechizos lanzados (solo con /gmk debug), para los ID de Forever
		directory = {},  -- [hermandad] = lo que anuncia en la red de hermandades (Modules/Network.lua)
		net = {},        -- estado del canal de la red: número, errores, si llega a la otra facción
		seasonStarts = {}, -- [temporada] = cuándo la vio empezar este addon (clasificación de la facción)
		layerKnown = {},   -- [continente][id de capa] = cuándo se vio (para numerar las capas, Layer.lua)
		legacyLearned = {}, -- [criterio de legado] = jefe final aprendido (Modules/Legacy.lua)
	},
}

---------------------------------------------------------------------------
-- Utilidades compartidas
---------------------------------------------------------------------------

-- Barra de scroll fina y dorada para las ventanas del addon: sin los botones de
-- arriba y abajo, con una línea tenue de fondo y el pulgar dorado (la barra
-- estándar sale con cuadros grises en Forever).
function ns.StyleScrollBar(scroll)
	local bar = scroll and (scroll.ScrollBar or (scroll.GetName and scroll:GetName() and _G[scroll:GetName() .. "ScrollBar"]))
	if type(bar) ~= "table" or bar.guildmarkStyled then return end
	bar.guildmarkStyled = true
	local name = bar.GetName and bar:GetName()
	for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
		local b = bar[key] or (name and _G[name .. key])
		if type(b) == "table" and b.SetAlpha then
			b:SetAlpha(0)
			b:EnableMouse(false)
		end
	end
	local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
	if type(thumb) ~= "table" then thumb = nil end
	-- Fuera las texturas propias de la barra (el pulgar se repinta).
	for _, region in ipairs({ bar:GetRegions() }) do
		if region ~= thumb and region.SetAlpha and region.GetObjectType and region:GetObjectType() == "Texture" then region:SetAlpha(0) end
	end
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("TOP", 0, 0)
	track:SetPoint("BOTTOM", 0, 0)
	track:SetWidth(2)
	track:SetColorTexture(1, 0.82, 0, 0.15)
	if thumb then
		thumb:SetColorTexture(0.78, 0.62, 0.25, 0.9)
		thumb:SetSize(6, 40)
	end
end

function ns.Now()
	return GetServerTime and GetServerTime() or time()
end

-- Nombres en WoW Forever: un solo reino por región y personajes con nombre y
-- apellido. UnitName devuelve (nombre, apellido) y la identidad visible es
-- "Nombre Apellido". El GUID sigue siendo la clave única cuando se tiene.

local function isRealm(s)
	return s == GetRealmName() or s == GetNormalizedRealmName()
end

-- "Nombre Apellido" a partir de un nombre y, opcionalmente, su segunda parte.
-- Quita el sufijo "-Reino" si el juego lo añade (p. ej. en el remitente de un mensaje).
function ns.FullName(name, second)
	if not name or name == "" then return nil end
	name = name:gsub("%-.*$", "")
	if second and second ~= "" and not isRealm(second) and not name:find(" ", 1, true) then
		name = name .. " " .. second
	end
	return name
end

function ns.UnitFullName(unit)
	local name, second = UnitName(unit)
	-- Dentro de instancias algunos nombres son secretos: no se pueden usar.
	if issecretvalue and (issecretvalue(name) or issecretvalue(second)) then return nil end
	if not name or name == "" or name == UNKNOWNOBJECT then return nil end
	return ns.FullName(name, second)
end

function ns.PlayerFullName()
	return ns.UnitFullName("player")
end

-- Nombre para mostrar (ya no hay reino que recortar).
function ns.ShortName(full)
	return full and ns.FullName(full) or full
end

-- Solo el nombre de pila, para casar textos del juego que puedan traerlo sin apellido.
function ns.FirstName(full)
	return full and full:match("^%S+") or full
end

-- true si dos nombres son la misma persona aunque uno venga sin apellido.
function ns.SameName(a, b)
	if not a or not b then return false end
	a, b = ns.FullName(a), ns.FullName(b)
	if a == b then return true end
	local aHasSurname, bHasSurname = a:find(" ", 1, true), b:find(" ", 1, true)
	if aHasSurname and bHasSurname then return false end
	return ns.FirstName(a) == ns.FirstName(b)
end

function ns.ClassColorName(name, classFile)
	local short = ns.ShortName(name) or "?"
	local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if color then
		return ("|c%s%s|r"):format(color.colorStr or "ffffffff", short)
	end
	return short
end

function ns.Hash(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + s:byte(i)) % 4294967296
	end
	return ("%08x"):format(h)
end

-- Compara "x.y.z"; devuelve 1 si a > b, -1 si a < b y 0 si son iguales.
function ns.CompareVersions(a, b)
	local function parts(v)
		local t = {}
		for n in tostring(v):gmatch("%d+") do t[#t + 1] = tonumber(n) end
		return t
	end
	local pa, pb = parts(a), parts(b)
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then return x > y and 1 or -1 end
	end
	return 0
end

function ns.FormatAgo(t)
	local d = ns.Now() - (t or 0)
	if d < 60 then return L["ahora"] end
	if d < 3600 then return ("%d min"):format(d / 60) end
	if d < 86400 then return ("%d h"):format(d / 3600) end
	return ("%d d"):format(d / 86400)
end

function LG:Debug(...)
	if self.db and self.db.profile.debug then
		self:Print("|cff888888[debug]|r", ...)
	end
end

---------------------------------------------------------------------------
-- Datos de la guild actual
---------------------------------------------------------------------------

-- Modo prueba: el grupo hace de hermandad, aunque estés en una de verdad.
-- Mientras está activo el addon se olvida de tu hermandad real: no envía ni
-- escucha nada por su canal, te trata como oficial y guarda los datos en una
-- hermandad ficticia aparte, para probar sin que nadie de tu guild se entere.
-- La hermandad ficticia lleva la facción en el nombre: en la red de pruebas
-- (Network.lua) dos probadores de facciones distintas tienen que ser dos
-- hermandades distintas para poder declararse la guerra.
local OLD_TEST_GUILD = "~Pruebas"
local testWarsMigrated = {} -- [nombre] = true: guerras ya pasadas al nombre nuevo (una vez por sesión)

local function testGuildName(self)
	local name = (UnitFactionGroup and UnitFactionGroup("player") == "Alliance") and "~Pruebas Alianza" or "~Pruebas Horda"
	-- Los datos de prueba de antes (sin facción) pasan a la nueva.
	local guilds = self.db.factionrealm.guilds
	local old = rawget(guilds, OLD_TEST_GUILD)
	if old and not rawget(guilds, name) then
		guilds[name] = old
		guilds[OLD_TEST_GUILD] = nil
	end
	-- Las guerras guardan el nombre de cada bando: las de antes pasan al nuevo.
	local g = not testWarsMigrated[name] and rawget(guilds, name)
	testWarsMigrated[name] = true
	for id, w in pairs(g and g.wars or {}) do
		if w.from == OLD_TEST_GUILD or w.to == OLD_TEST_GUILD then
			for _, key in ipairs({ "from", "to", "side" }) do
				if w[key] == OLD_TEST_GUILD then w[key] = name end
			end
		end
	end
	return name
end

function ns.IsTestGuild(name)
	return type(name) == "string" and name:sub(1, #OLD_TEST_GUILD) == OLD_TEST_GUILD
end

function LG:InTestMode()
	return self.db and self.db.profile.testMode or false
end

function LG:GuildName()
	if self:InTestMode() then return testGuildName(self) end
	if IsInGuild() then return (GetGuildInfo("player")) end
	return nil
end

-- true si la unidad es de la guild (en modo prueba, si es de tu grupo).
function ns.IsGuildUnit(unit)
	if LG:InTestMode() then return (UnitInParty(unit) or UnitInRaid(unit)) and true or false end
	return UnitIsInMyGuild(unit) and true or false
end

-- Devuelve la tabla de datos de la guild actual, o nil si aún no se conoce.
function LG:GuildData()
	local name = self:GuildName()
	if not name then return nil end
	return self.db.factionrealm.guilds[name]
end

function LG:HasConsent()
	return self.db.char.consent == "yes"
end

-- Ventanas que se repintan cuando cambian los datos. No usan RegisterMessage
-- sobre LG: AceEvent guarda UN solo manejador por objeto y mensaje, así que la
-- segunda ventana que se registraba dejaba a la primera sin refrescar.
local dataListeners = {}
function ns.OnDataChanged(fn)
	dataListeners[#dataListeners + 1] = fn
end

function LG:DataChanged()
	if ns.InvalidateScores then ns.InvalidateScores() end
	if ns.InvalidateAchievements then ns.InvalidateAchievements() end
	for _, fn in ipairs(dataListeners) do
		-- Un error en una ventana no deja sin refrescar a las demás.
		local ok, err = pcall(fn)
		if not ok and geterrorhandler then geterrorhandler()(err) end
	end
	self:SendMessage("LANTUX_DATA_CHANGED")
end

-- Los módulos añaden sus campos al registro propio con esta lista de funciones.
ns.recordProviders = {}

function LG:BuildMyRecord()
	local _, classFile = UnitClass("player")
	local _, raceFile = UnitRace("player")
	local rec = {
		name = ns.PlayerFullName(),
		guid = UnitGUID("player"),
		class = classFile,
		race = raceFile,
		level = UnitLevel("player"),
		locale = GetLocale(),
		ver = self.VERSION,
		t = ns.Now(),
	}
	local history = self.db.char.levelHistory
	rec.levels = { unpack(history, math.max(1, #history - 9), #history) }

	-- Antigüedad en la hermandad (para los rangos): primera vez que el addon te vio en ella.
	local guildName = self:GuildName()
	if guildName then
		self.db.char.joined[guildName] = self.db.char.joined[guildName] or ns.Now()
		rec.joined = self.db.char.joined[guildName]
	end

	if self.db.char.optional.alts then
		local alts = {}
		for name, info in pairs(self.db.global.chars) do
			if name ~= rec.name and info.guild == self:GuildName() then
				alts[#alts + 1] = name
			end
		end
		rec.alts = alts
	end
	if self.db.char.optional.played and self.db.char.played then
		rec.played = self.db.char.played.total
	end
	for _, provider in ipairs(ns.recordProviders) do
		provider(rec)
	end
	return rec
end

-- Actualiza al momento el registro propio en local (para que la ventana lo
-- refleje) y programa su envío, como mucho uno cada RECORD_THROTTLE segundos.
function LG:MarkDirty()
	if not self:HasConsent() then return end
	local g = self:GuildData()
	if g then
		local rec = self:BuildMyRecord()
		g.members[rec.name] = rec
		self:DataChanged()
	end
	if self.recordTimer then return end
	local wait = math.max(5, RECORD_THROTTLE - (ns.Now() - (self.lastRecordSent or 0)))
	self.recordTimer = self:ScheduleTimer(function()
		self.recordTimer = nil
		self:SendMyRecord()
	end, wait)
end

function LG:SendMyRecord()
	local g = self:GuildData()
	if not g then return end
	local rec = self:BuildMyRecord()
	g.members[rec.name] = rec
	self.lastRecordSent = ns.Now()
	self:Send("ME", rec)
	self:DataChanged()
end

---------------------------------------------------------------------------
-- Ciclo de vida
---------------------------------------------------------------------------

-- Diagnóstico: si Blizzard bloquea una acción del addon, se apunta qué función fue,
-- en el chat y en GuildmarkDB.global.blocked (se puede leer en el archivo de SavedVariables).
local registering -- evento que se está registrando ahora mismo, para el diagnóstico

local function watchBlockedActions(db)
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("ADDON_ACTION_BLOCKED")
	watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
	watcher:SetScript("OnEvent", function(_, event, addon, func)
		if addon ~= ADDON_NAME then return end
		local log = db.global.blocked
		table.insert(log, {
			event = event,
			func = tostring(func),
			registering = registering,
			t = date("%Y-%m-%d %H:%M:%S"),
			combat = InCombatLockdown(),
		})
		while #log > 30 do table.remove(log, 1) end
		if registering then
			db.global.forbiddenEvents[registering] = date("%Y-%m-%d")
		end
		print(("|cffff6b5aGuildmark:|r %s %s %s"):format(event, tostring(func), registering or ""))
	end)
end

-- Algunos eventos están prohibidos para addons en la beta de Forever. Si uno lo
-- está, se apunta y no se vuelve a intentar, para que el aviso salga una sola vez.
-- Devuelve false si el evento no está disponible.
function ns.RegisterEvent(obj, event, handler)
	if LG.db.global.forbiddenEvents[event] then
		LG:Debug("evento no disponible:", event)
		return false
	end
	registering = event
	obj:RegisterEvent(event, handler)
	registering = nil
	return not LG.db.global.forbiddenEvents[event]
end

function ns.EventAvailable(event)
	return not LG.db.global.forbiddenEvents[event]
end

-- Antes de este arreglo, la base de datos se creaba antes de que el juego supiera
-- el nombre del personaje y los datos acababan bajo "Entidad desconocida".
local function cleanUnknownCharacter()
	local sv = GuildmarkDB
	local unknown = UNKNOWNOBJECT or "Unknown"
	if type(sv) ~= "table" then return end
	for _, section in ipairs({ "char", "profileKeys" }) do
		for key in pairs(sv[section] or {}) do
			if key:find(unknown, 1, true) then sv[section][key] = nil end
		end
	end
end

function LG:OnInitialize()
	self:RegisterChatCommand("guildmark", "SlashCommand")
	self:RegisterChatCommand("gmk", "SlashCommand")
	-- Alias de la beta (no sale en la ayuda). /gm no: es el de la ayuda de Blizzard.
	self:RegisterChatCommand("lg", "SlashCommand")
end

-- La base de datos se crea aquí (PLAYER_LOGIN) y no en OnInitialize porque en la
-- beta el nombre del personaje aún no se conoce al cargar el addon.
function LG:OnEnable()
	cleanUnknownCharacter()
	-- Si los datos guardados no se cargaron (fallo de la beta), se recuperan de la copia.
	local restored = ns.RestoreSavedVariables()
	self.db = LibStub("AceDB-3.0"):New("GuildmarkDB", defaults, true)
	if restored then
		self:ScheduleTimer(function()
			self:Print(L["Tus datos guardados no se cargaron bien; se han recuperado de la copia de seguridad."])
		end, 8)
	end
	-- Esquema 2: los nombres pasan de "Nombre-Reino" a "Nombre Apellido". Lo anterior
	-- eran datos de pruebas de la beta con nombres mal formados, así que se descartan.
	if (self.db.global.schema or 1) < 2 then
		for _, g in pairs(self.db.factionrealm.guilds) do
			wipe(g.members); wipe(g.kills); wipe(g.runs); wipe(g.guildCache)
		end
		wipe(self.db.global.chars)
		self.db.global.schema = 2
	end
	watchBlockedActions(self.db)
	-- Sin esto AceComm no entrega nada: el addon enviaba pero nunca recibía.
	self:RegisterComm(ns.COMM_PREFIX)
	ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD")
	ns.RegisterEvent(self, "PLAYER_LEVEL_UP")
	ns.RegisterEvent(self, "TIME_PLAYED_MSG")
	ns.RegisterEvent(self, "PLAYER_GUILD_UPDATE", "RememberCharacter")
	ns.RegisterEvent(self, "GROUP_ROSTER_UPDATE")
	ns.UpdateMinimapButton()
end

-- En modo prueba la "hermandad" cambia al entrar alguien en el grupo: se vuelve a sincronizar.
function LG:GROUP_ROSTER_UPDATE()
	if not self:InTestMode() or not self:HasConsent() or not IsInGroup() then return end
	if ns.Now() - (self.lastTestSync or 0) < 30 then return end
	self.lastTestSync = ns.Now()
	self:ScheduleTimer("StartSync", 3)
end

function LG:PLAYER_ENTERING_WORLD(_, isLogin, isReload)
	if self.started then return end
	self.started = true
	-- La información de guild tarda unos segundos en estar disponible tras entrar.
	self:ScheduleTimer("AfterLogin", 8)
end

function LG:AfterLogin()
	self:RememberCharacter()
	self:Prune()
	if self.db.char.consent == "pending" then
		if self:GuildName() then ns.ShowConsent() end
	elseif self:HasConsent() then
		self:StartSync()
		-- El texto ha cambiado (p. ej. guerras y directorio): se vuelve a preguntar una vez.
		if (self.db.char.consentVersion or 1) < CONSENT_VERSION and self:GuildName() then ns.ShowConsent() end
	end
end

function LG:RememberCharacter()
	local _, classFile = UnitClass("player")
	self.db.global.chars[ns.PlayerFullName()] = {
		class = classFile,
		level = UnitLevel("player"),
		guild = self:GuildName(),
		t = ns.Now(),
	}
end

function LG:PLAYER_LEVEL_UP(_, level)
	table.insert(self.db.char.levelHistory, { level = level, t = ns.Now() })
	self:RememberCharacter()
	self:MarkDirty()
end

-- Solo se guarda cuando el jugador escribe /played; no lo pedimos para no llenar el chat.
function LG:TIME_PLAYED_MSG(_, total, thisLevel)
	self.db.char.played = { total = total, level = thisLevel, t = ns.Now() }
	if self.db.char.optional.played then self:MarkDirty() end
end

function LG:SetConsent(accepted)
	self.db.char.consent = accepted and "yes" or "no"
	if accepted then
		self.db.char.consentVersion = CONSENT_VERSION
		self:Print(L["Gracias. Tus datos se comparten con la hermandad. /gmk privacidad para revisarlo."])
		self:StartSync()
	else
		self:Print(L["No se comparte nada. Puedes activarlo cuando quieras con /gmk privacidad."])
	end
	self:DataChanged()
end

-- Borra lo que hay de este personaje y pide a los demás que lo borren también.
function LG:WipeMyData()
	local me = ns.PlayerFullName()
	local myGUID = UnitGUID("player")
	if self:HasConsent() then self:Send("FORGET", { name = me, guid = myGUID }) end
	for _, g in pairs(self.db.factionrealm.guilds) do
		ns.ForgetMember(g, me, myGUID)
	end
	self.db.char.consent = "no"
	self.db.char.levelHistory = {}
	self.db.char.played = nil
	self.db.char.professions = {}
	self.db.char.recipes = {}
	self.db.char.stats = { gathered = { mining = 0, herb = 0, skinning = 0 }, crafted = 0, crafts = 0, bestDay = 0 }
	self.db.char.optional = { alts = false, played = false }
	self.db.global.chars[me] = nil
	self:Print(L["Datos borrados. El addon ya no comparte nada de este personaje."])
	self:DataChanged()
end

-- Limpia datos viejos para que el archivo de guardado no crezca sin límite.
function LG:Prune()
	local now = ns.Now()
	for _, g in pairs(self.db.factionrealm.guilds) do
		for id, k in pairs(g.kills) do
			if now - (k.t or 0) > 60 * 86400 then g.kills[id] = nil end
		end
		for key, r in pairs(g.runs) do
			if now - (r.t or 0) > 90 * 86400 then g.runs[key] = nil end
		end
		for guid, c in pairs(g.guildCache) do
			if now - (c.t or 0) > 30 * 86400 then g.guildCache[guid] = nil end
		end
		ns.PruneOrders(g)
		if ns.PruneLFG then ns.PruneLFG(g) end
		ns.PruneEvents(g)
		ns.PruneAuctions(g)
		if ns.PruneBankLog then ns.PruneBankLog(g) end
	end
end

---------------------------------------------------------------------------
-- Comandos
---------------------------------------------------------------------------

-- Diagnóstico: evalúa expresiones de la API y guarda el resultado en
-- GuildmarkDB.global.diag, para leerlo desde el archivo tras un /reload.
local DIAG_CHECKS = {
	"select(4, GetBuildInfo())",
	"GetRealmName()",
	"GetNormalizedRealmName()",
	"C_DeathRecap",
	"GetDeathRecapLink",
	"DeathRecap_GetEvents",
	"C_DeathInfo",
	"GetPVPLifetimeStats()",
	"GetPVPSessionStats()",
	"GetPVPYesterdayStats()",
	"GetPVPThisWeekStats",
	"GetPVPThisWeekStats()",
	"UnitPVPRank",
	"UnitPVPRank('player')",
	"GetPVPRankInfo",
	"COMBATLOG_HONORGAIN",
	"C_Calendar",
	"C_DamageMeter",
	"C_CombatLog",
	"C_GuildInfo",
	"GetGuildInfo('target')",
	"UnitName('target')",
	"UnitIsEnemy('player', 'target')",
	"UnitName('player')",
	"UnitFullName('player')",
	"GetUnitName('player', true)",
	"LantuxGuild_PlayerFullName()",
	"select(6, GetPlayerInfoByGUID(UnitGUID('player')))",
	"select(6, GetPlayerInfoByGUID(UnitGUID('target') or ''))",
	"UnitName('target')",
	"C_DeathRecap.HasRecapEvents()",
	"C_CombatLog.IsCombatLogRestricted()",
	-- Profesiones: ¿API de Classic (GetSkillLineInfo, GetTradeSkillInfo) o moderna (C_TradeSkillUI)?
	"LantuxGuild_SkillLines()",
	"GetProfessions",
	"GetProfessions and GetProfessions()",
	"GetProfessionInfo",
	"C_TradeSkillUI",
	"C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillReady and C_TradeSkillUI.IsTradeSkillReady()",
	"C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and #C_TradeSkillUI.GetAllRecipeIDs()",
	"C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()",
	"GetNumTradeSkills",
	"GetNumTradeSkills and GetNumTradeSkills()",
	"GetTradeSkillLine and GetTradeSkillLine()",
	"GetTradeSkillInfo",
	"GetTradeSkillRecipeLink",
	"GetTradeSkillItemLink",
	"GetCraftInfo",
	"C_Professions",
	"C_Spell",
	-- Directorio de recetas y banco de la hermandad de Blizzard
	"GetNumGuildTradeSkill",
	"GetGuildTradeSkillInfo",
	"GetGuildRecipeMember",
	"GetNumGuildBankTabs",
	"GetNumGuildBankTabs and GetNumGuildBankTabs()",
	"C_GuildInfo.IsGuildReputationEnabled and C_GuildInfo.IsGuildReputationEnabled()",
	"C_GuildInfo.AreGuildEventsEnabled and C_GuildInfo.AreGuildEventsEnabled()",
	"C_GuildInfo.IsEncounterGuildNewsEnabled and C_GuildInfo.IsEncounterGuildNewsEnabled()",
	-- Comercio y descripciones de objetos (para verificar entregas "Hecho por X")
	"C_TooltipInfo",
	"C_TooltipInfo and C_TooltipInfo.GetBagItem",
	"GetTradePlayerItemLink",
	"GetTradeTargetItemLink",
	"ITEM_CREATED_BY",
	-- Calendario de Blizzard (fase 2 de eventos)
	"C_Calendar.GetNumGuildEvents and C_Calendar.GetNumGuildEvents()",
	"C_Calendar.CanAddEvent and C_Calendar.CanAddEvent()",
	"C_Calendar.GetNumDayEvents and C_Calendar.GetNumDayEvents(0, tonumber(date('%d')))",
	"C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer()",
	"CalendarFrame",
	-- Dentro de una hermandad real
	"IsInGuild()",
	"GetGuildInfo('player')",
	"GetNumGuildMembers()",
	"LantuxGuild_RosterSample()",
	"LantuxGuild_AddonView()",
	"C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer()",
	"CanEditOfficerNote and CanEditOfficerNote()",
	"C_GuildInfo.CanViewOfficerNote and C_GuildInfo.CanViewOfficerNote()",
	"GuildControlGetNumRanks and GuildControlGetNumRanks()",
	"LantuxGuild_RankNames()",
	"GetNumGuildBankTabs and GetNumGuildBankTabs()",
	"GetGuildBankTabInfo and GetGuildBankTabInfo(1)",
	"GetGuildBankMoney and GetGuildBankMoney()",
	"GetNumGuildTradeSkill and GetNumGuildTradeSkill()",
	"LantuxGuild_GuildTradeSkills()",
	"C_Calendar.GetNumGuildEvents and C_Calendar.GetNumGuildEvents()",
	"LantuxGuild_GuildEvents()",
	"C_GuildInfo.GetMOTD and C_GuildInfo.GetMOTD()",
	-- Rango JcJ (renombre 2800), temporada y título del objetivo.
	"LantuxGuild_PvP()",
}

-- Busca en el entorno del juego nombres que contengan alguno de los textos
-- (sin distinguir mayúsculas): funciones globales, tablas C_* y sus funciones,
-- y marcos con nombre. Para descubrir la API de sistemas nuevos de Forever.
-- Uso: /gmk dump LantuxGuild_Find("legacy", "challenge")
function LantuxGuild_Find(...)
	local patterns = {}
	for i = 1, select("#", ...) do patterns[#patterns + 1] = tostring(select(i, ...)):lower() end
	local function matches(name)
		name = name:lower()
		for _, p in ipairs(patterns) do
			if name:find(p, 1, true) then return true end
		end
		return false
	end
	local found = {}
	for name, value in pairs(_G) do
		if type(name) == "string" then
			if matches(name) then
				found[#found + 1] = name .. ":" .. type(value)
			end
			-- Tablas C_* (y similares): también sus funciones.
			if type(value) == "table" and name:match("^C_") then
				for key in pairs(value) do
					if type(key) == "string" and (matches(key) or matches(name)) then
						found[#found + 1] = name .. "." .. key
					end
				end
			end
		end
		if #found > 400 then break end
	end
	table.sort(found)
	return #found .. " resultados: " .. table.concat(found, ", ")
end

-- Texturas y atlas que usa una ventana de Blizzard (recorre sus regiones y
-- marcos hijos). Para imitar su aspecto con las mismas piezas gráficas.
-- Uso: /gmk dump LantuxGuild_FrameArt("LegacySystemFrame")
function LantuxGuild_FrameArt(frameName, maxItems)
	local root = _G[frameName]
	if not root then return "no existe " .. tostring(frameName) end
	maxItems = maxItems or 150
	local seen, out, visited = {}, {}, {}
	local function addTexture(region)
		local ok, atlas = pcall(region.GetAtlas, region)
		local value = ok and atlas and ("atlas:" .. atlas)
		if not value then
			local ok2, tex = pcall(region.GetTexture, region)
			if ok2 and tex then value = "tex:" .. tostring(tex) end
		end
		if value and not seen[value] then
			seen[value] = true
			out[#out + 1] = value
		end
	end
	local function walk(frame, depth)
		if visited[frame] or depth > 8 or #out >= maxItems then return end
		visited[frame] = true
		for _, region in ipairs({ frame:GetRegions() }) do
			if region.GetObjectType and region:GetObjectType() == "Texture" then addTexture(region) end
		end
		for _, child in ipairs({ frame:GetChildren() }) do walk(child, depth + 1) end
	end
	walk(root, 0)
	return #out .. " texturas: " .. table.concat(out, ", ")
end

-- Categorías de logros del juego (para ver si los desafíos de legado son logros por debajo).
function LantuxGuild_Categories()
	if not GetCategoryList then return "sin GetCategoryList" end
	local parts = {}
	for _, id in ipairs(GetCategoryList() or {}) do
		local ok, name, parent = pcall(GetCategoryInfo, id)
		local okN, total, completed = pcall(GetCategoryNumAchievements, id, true)
		parts[#parts + 1] = ("%s=%s(padre %s, %s/%s)"):format(tostring(id), ok and tostring(name) or "?",
			tostring(parent), okN and tostring(completed) or "?", okN and tostring(total) or "?")
	end
	return #parts .. " categorías: " .. table.concat(parts, ", ")
end

-- Desafíos de legado de Mazmorras y Bandas con sus requisitos: tipo y assetID
-- de cada uno (¿mazmorra o encuentro del jefe final?). Para generar los
-- desafíos de hermandad de mazmorras y bandas a partir de la lista oficial.
-- Uso: /gmk dump LantuxGuild_LegacyDungeons()
function LantuxGuild_LegacyDungeons()
	if not GetCategoryNumAchievements or not GetAchievementInfo then return "sin API de logros" end
	local parts = {}
	for _, categoryID in ipairs({ 15593, 15594 }) do
		local total = GetCategoryNumAchievements(categoryID, true) or 0
		for i = 1, total do
			local id, name = GetAchievementInfo(categoryID, i)
			if id then
				local criteria = {}
				for c = 1, (GetAchievementNumCriteria and GetAchievementNumCriteria(id) or 0) do
					local text, ctype, _, _, required, _, _, assetID, _, criteriaID = GetAchievementCriteriaInfo(id, c)
					criteria[#criteria + 1] = ("%s[tipo %s, asset %s, req %s, id %s]"):format(tostring(text), tostring(ctype),
						tostring(assetID), tostring(required), tostring(criteriaID))
				end
				parts[#parts + 1] = ("%d %s: %s"):format(id, tostring(name), table.concat(criteria, "; "))
			end
		end
	end
	return table.concat(parts, " || ")
end

-- ¿Tiene Forever la Guía de mazmorras (Encounter Journal)? Primeras mazmorras y jefes.
function LantuxGuild_Journal()
	if not EJ_GetNumTiers then return "sin EJ_GetNumTiers" end
	local parts = { ("tiers=%s"):format(tostring(EJ_GetNumTiers())) }
	if EJ_SelectTier then pcall(EJ_SelectTier, EJ_GetNumTiers()) end
	for _, isRaid in ipairs({ false, true }) do
		for i = 1, 30 do
			local ok, instanceID, name = pcall(EJ_GetInstanceByIndex, i, isRaid)
			if not ok or not instanceID then break end
			local bosses = {}
			if EJ_SelectInstance then pcall(EJ_SelectInstance, instanceID) end
			for b = 1, 15 do
				local okB, bossName, _, journalEncounterID, _, _, _, dungeonEncounterID = pcall(EJ_GetEncounterInfoByIndex, b, instanceID)
				if not okB or not bossName then break end
				bosses[#bosses + 1] = ("%s(%s/%s)"):format(bossName, tostring(journalEncounterID), tostring(dungeonEncounterID))
			end
			parts[#parts + 1] = ("%s%s %s: %s"):format(isRaid and "BANDA " or "", tostring(instanceID), tostring(name), table.concat(bosses, ", "))
		end
	end
	return table.concat(parts, " || ")
end

-- Claves de una tabla global (funciones y datos de un sistema, p. ej. LegacySystem).
function LantuxGuild_Keys(tableName)
	local t = _G[tableName]
	if type(t) ~= "table" then return tostring(tableName) .. " no es una tabla" end
	local keys = {}
	for k, v in pairs(t) do keys[#keys + 1] = tostring(k) .. ":" .. type(v) end
	table.sort(keys)
	return #keys .. " claves: " .. table.concat(keys, ", ")
end

-- Primeros miembros del roster tal como los da el juego (formato de nombre, rango, clase...).
function LantuxGuild_RosterSample()
	local parts = {}
	for i = 1, math.min(5, GetNumGuildMembers() or 0) do
		local name, rankName, rankIndex, level, _, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
		parts[#parts + 1] = ("%q rango=%s(%s) nv=%s %s %s %s"):format(tostring(name), tostring(rankName), tostring(rankIndex),
			tostring(level), tostring(classFile), online and "conectado" or "desconectado", tostring(zone))
	end
	return table.concat(parts, " || ")
end

-- Cómo ve el addon la hermandad: nombre, yo, mi entrada en el roster y si soy oficial.
function LantuxGuild_AddonView()
	local me = ns.PlayerFullName()
	local r = ns.roster[me]
	local n = 0
	for _ in pairs(ns.roster) do n = n + 1 end
	return ("hermandad=%q yo=%q enRoster=%s rango=%s(%s) oficial=%s miembrosAddon=%d roster=%d"):format(
		tostring(LG:GuildName()), tostring(me), tostring(r ~= nil), tostring(r and r.rank), tostring(r and r.rankIndex),
		tostring(ns.CanManageEvents and ns.CanManageEvents(me)), (function()
			local g = LG:GuildData(); local c = 0
			for _ in pairs(g and g.members or {}) do c = c + 1 end
			return c
		end)(), n)
end

function LantuxGuild_RankNames()
	if not GuildControlGetNumRanks or not GuildControlGetRankName then return "sin API de rangos" end
	local parts = {}
	for i = 1, GuildControlGetNumRanks() do parts[#parts + 1] = ("%d=%s"):format(i - 1, tostring(GuildControlGetRankName(i))) end
	return table.concat(parts, ", ")
end

-- Directorio de profesiones de la hermandad de Blizzard (primeras entradas).
function LantuxGuild_GuildTradeSkills()
	if not GetNumGuildTradeSkill or not GetGuildTradeSkillInfo then return "sin API" end
	local parts = {}
	for i = 1, math.min(12, GetNumGuildTradeSkill() or 0) do
		local values = { pcall(GetGuildTradeSkillInfo, i) }
		local shown = {}
		for j = 2, math.min(#values, 14) do shown[#shown + 1] = tostring(values[j]) end
		parts[#parts + 1] = table.concat(shown, ",")
	end
	return #parts > 0 and table.concat(parts, " || ") or "vacío (puede que haga falta abrir la ventana de hermandad)"
end

-- Rango JcJ de Forever: es un "renombre" de la facción 2800 (como lo lee la
-- pestaña de rangos de Blizzard), por temporadas. Uso: /gmk dump LantuxGuild_PvP()
function LantuxGuild_PvP()
	local parts = {}
	local function add(label, fn)
		local ok, a, b, c = pcall(fn)
		parts[#parts + 1] = ("%s=%s"):format(label, ok and ns.DeepDescribe({ a, b, c }, 2) or ("error " .. tostring(a)))
	end
	add("rank", function() return C_MajorFactions.GetMajorFactionProgressionInfo(2800) end)
	add("season", function() return GetCurrentArenaSeason() end)
	add("seasonEnds", function() return C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd() end)
	add("pvpName", function() return UnitPVPName("player") end)
	add("targetPvpName", function() return UnitPVPName("target") end)
	add("lifetime", function() return GetPVPLifetimeStats() end)
	add("session", function() return GetPVPSessionStats() end)
	add("yesterday", function() return GetPVPYesterdayStats() end)
	add("honor", function() return UnitHonor and UnitHonor("player"), UnitHonorLevel and UnitHonorLevel("player") end)
	add("bgTypes", function() return GetNumBattlegroundTypes and GetNumBattlegroundTypes() end)
	add("lastMatch", function() return LG.db.global.diag.lastMatch end)
	return table.concat(parts, " || ")
end

-- Logros y estadísticas de Blizzard que tenga Forever (su ventana se puede abrir
-- aunque no se use). Lo guarda todo en diag.blizzAch. Uso: /gmk dump LantuxGuild_Achievements()
function LantuxGuild_Achievements()
	if not GetCategoryList or not GetAchievementInfo then return "sin API de logros" end
	local out = { t = date("%Y-%m-%d %H:%M:%S"), categories = {}, stats = {} }
	local nAch, nDone, nStats = 0, 0, 0
	local function readCategory(cat, isStat)
		local okC, name, parent = pcall(GetCategoryInfo, cat)
		local okN, num = pcall(GetCategoryNumAchievements, cat, true)
		local entry = { id = cat, name = okC and name or "?", parent = okC and parent or nil, items = {} }
		for i = 1, (okN and num or 0) do
			local ok, id, aName, points, completed, _, _, _, desc, flags, _, reward, isGuild = pcall(GetAchievementInfo, cat, i)
			if ok and id then
				local item = { id = id, name = aName, points = points, done = completed or nil, desc = desc, guild = isGuild or nil,
					reward = reward ~= "" and reward or nil }
				if isStat and GetStatistic then
					local okS, value = pcall(GetStatistic, id)
					item.value = okS and value or nil
					nStats = nStats + 1
				else
					nAch = nAch + 1
					if completed then nDone = nDone + 1 end
					local okCr, nCrit = pcall(GetAchievementNumCriteria, id)
					item.criteria = okCr and nCrit or nil
				end
				entry.items[#entry.items + 1] = item
			end
		end
		return entry
	end
	local okL, cats = pcall(GetCategoryList)
	for _, cat in ipairs(okL and cats or {}) do out.categories[#out.categories + 1] = readCategory(cat, false) end
	local okS, statCats = pcall(GetStatisticsCategoryList)
	for _, cat in ipairs(okS and statCats or {}) do out.stats[#out.stats + 1] = readCategory(cat, true) end
	local okG, guildCats = pcall(GetGuildCategoryList)
	out.guildCategories = okG and guildCats and #guildCats or nil
	LG.db.global.diag.blizzAch = out
	return ("%d categorías, %d logros (%d hechos), %d categorías de estadísticas, %d estadísticas; guardado en diag.blizzAch"):format(
		#out.categories, nAch, nDone, #out.stats, nStats)
end

-- Eventos de hermandad del calendario de Blizzard.
function LantuxGuild_GuildEvents()
	if not C_Calendar or not C_Calendar.GetNumGuildEvents then return "sin API" end
	if C_Calendar.OpenCalendar then pcall(C_Calendar.OpenCalendar) end
	local parts = {}
	for i = 1, math.min(5, C_Calendar.GetNumGuildEvents() or 0) do
		local ok, info = pcall(C_Calendar.GetGuildEventInfo, i)
		parts[#parts + 1] = ok and ns.DeepDescribe(info, 2) or ("error " .. tostring(info))
	end
	return #parts > 0 and table.concat(parts, " || ") or "ninguno"
end

-- Líneas de habilidad (profesiones incluidas) con su nivel, para /gmk diag.
function LantuxGuild_SkillLines()
	if not GetNumSkillLines then return "GetNumSkillLines no existe" end
	local parts = {}
	for i = 1, GetNumSkillLines() do
		local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
		parts[#parts + 1] = isHeader and ("[" .. tostring(name) .. "]") or ("%s %s/%s"):format(tostring(name), tostring(rank), tostring(maxRank))
	end
	return table.concat(parts, "; ")
end

-- Accesible desde /gmk dump para comprobar cómo construye el addon el nombre propio.
function LantuxGuild_PlayerFullName()
	return ns.PlayerFullName()
end

-- Vuelca una tabla con sus valores hasta cierta profundidad (para el informe de muerte).
function ns.DeepDescribe(v, depth)
	depth = depth or 3
	if type(v) ~= "table" then
		return type(v) == "string" and ("%q"):format(v) or tostring(v)
	end
	if depth <= 0 then return "{...}" end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for i, k in ipairs(keys) do
		if i > 40 then parts[#parts + 1] = "..." break end
		parts[#parts + 1] = tostring(k) .. "=" .. ns.DeepDescribe(v[k], depth - 1)
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function describeValue(v)
	if type(v) == "table" then
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = tostring(k) end
		table.sort(keys)
		if #keys > 80 then keys[81] = ("... (%d en total)"):format(#keys); for i = #keys, 82, -1 do keys[i] = nil end end
		return "table { " .. table.concat(keys, ", ") .. " }"
	end
	if type(v) == "string" then return ("%q"):format(v) end
	return tostring(v)
end

local function evaluate(expr)
	local fn, err = loadstring("return " .. expr)
	if not fn then return "error de sintaxis: " .. tostring(err) end
	local results = { pcall(fn) }
	if not results[1] then return "error: " .. tostring(results[2]) end
	if #results == 1 then return "nil" end
	local parts = {}
	for i = 2, #results do parts[#parts + 1] = describeValue(results[i]) end
	return table.concat(parts, " | ")
end

function LG:RunDiagnostics(extra)
	local checks = extra and { extra } or DIAG_CHECKS
	local diag = self.db.global.diag
	diag.t = date("%Y-%m-%d %H:%M:%S")
	diag.results = diag.results or {}
	if not extra then wipe(diag.results) end
	for _, expr in ipairs(checks) do
		diag.results[#diag.results + 1] = expr .. "  =>  " .. evaluate(expr)
	end
	self:Print(("%d %s"):format(#checks, L["comprobaciones guardadas. Haz /reload para que se escriban en el archivo."]))
end

local HELP = {
	L["/gmk - abrir o cerrar la ventana"],
	L["/gmk ajustes - opciones del addon"],
	L["/gmk logros - abrir los Logros de hermandad"],
	L["/gmk privacidad - ver qué se comparte y cambiar el consentimiento"],
	L["/gmk opcional alts | jugado - activar o desactivar datos opcionales"],
	L["/gmk borrar - borrar tus datos aquí y en los addons de la hermandad"],
	L["/gmk sync - pedir una sincronización a la hermandad"],
	L["/gmk minimapa - mostrar u ocultar el botón del minimapa"],
	L["/gmk prueba - modo prueba: el grupo hace de hermandad, sin tocar tu hermandad real"],
	L["/gmk subasta [objeto] - subastar un objeto tuyo a la hermandad (1 día)"],
	L["/gmk ajustar Nombre Apellido, insignias, reputación, motivo - (oficiales) ajustar puntos"],
	L["/gmk objetivo Hermandad - (oficiales) añadir o quitar una hermandad objetivo"],
	L["/gmk perfil [nombre] - tu perfil (medallas, ficha e insignias del retrato) o el de otro miembro"],
	L["/gmk red - estado de la red de hermandades"],
	L["/gmk insignias - mostrar u ocultar las insignias sobre el marco de jugador"],
	L["/gmk debug - mensajes de depuración"],
}

-- Los comandos se escriben en español; estos equivalentes en inglés llevan al mismo sitio.
local COMMAND_ALIASES = {
	privacy = "privacidad", settings = "ajustes", options = "ajustes", optional = "opcional", delete = "borrar", minimap = "minimapa",
	adjust = "ajustar", challenges = "desafios", ["desafíos"] = "desafios", logros = "desafios", achievements = "desafios", auction = "subasta",
	target = "objetivo", test = "prueba", profile = "perfil", war = "guerra", network = "red", badges = "insignias",
}

function LG:SlashCommand(input)
	local cmd, arg = self:GetArgs(input, 2)
	cmd = cmd and cmd:lower()
	cmd = cmd and (COMMAND_ALIASES[cmd] or cmd)
	if arg == "played" then arg = "jugado" end
	if not cmd then
		ns.ToggleMainFrame()
	elseif cmd == "ajustes" then
		if not LantuxGuildFrame or not LantuxGuildFrame:IsShown() then ns.ToggleMainFrame() end
		ns.SelectTab("settings")
	elseif cmd == "privacidad" then
		ns.ShowConsent()
	elseif cmd == "opcional" then
		local key = arg == "alts" and "alts" or (arg == "jugado" and "played") or nil
		if not key then
			self:Print(L["Uso: /gmk opcional alts | jugado"])
			return
		end
		local opt = self.db.char.optional
		opt[key] = not opt[key]
		self:Print(("%s: %s"):format(arg, opt[key] and L["activado"] or L["desactivado"]))
		self:MarkDirty()
	elseif cmd == "borrar" then
		StaticPopup_Show("LANTUX_WIPE")
	elseif cmd == "sync" then
		if self:HasConsent() then self:StartSync() else self:Print(L["Primero acepta compartir datos con /gmk privacidad."]) end
	elseif cmd == "minimapa" then
		local mm = self.db.profile.minimap
		mm.hide = not mm.hide
		ns.UpdateMinimapButton()
	elseif cmd == "ajustar" then
		-- /gmk ajustar Nombre Apellido, insignias, reputación, motivo
		-- (con comas porque los nombres de Forever llevan espacio)
		local rest = input:match("^%s*%S+%s+(.+)$") or ""
		local name, merits, rep, reason = rest:match("^%s*([^,]+),%s*(%-?%d+)%s*,?%s*(%-?%d*)%s*,?%s*(.*)$")
		if not name then
			self:Print(L["Uso: /gmk ajustar Nombre Apellido, insignias, reputación, motivo"])
			return
		end
		ns.AdjustPoints(ns.FullName(strtrim(name)), tonumber(merits) or 0, tonumber(rep) or 0, reason ~= "" and reason or nil)
	elseif cmd == "desafios" then
		ns.ToggleAchievements()
	elseif cmd == "perfil" then
		local rest = input:match("^%s*%S+%s+(.+)$")
		ns.ToggleProfile(rest and (ns.FindMember(rest) or ns.FullName(strtrim(rest))) or nil)
	elseif cmd == "subasta" then
		-- /gmk subasta [enlace de objeto]: cualquier miembro, con un objeto suyo
		ns.ShowAuctionStart(input:match("(|c%x+|Hitem:.-|h.-|h|r)") or input:match("(|Hitem:.-|h.-|h)"))
	elseif cmd == "objetivo" then
		-- /gmk objetivo Nombre de la hermandad  (añade o quita)
		local guild = input:match("^%s*%S+%s+(.+)$")
		if guild then ns.ToggleTarget(strtrim(guild)) else self:Print(L["Uso: /gmk objetivo Nombre de la hermandad"]) end
	elseif cmd == "guerra" then
		-- /gmk guerra            abre JcJ > Guerras
		-- /gmk guerra LG1:...    aplica un código pegado
		local code = input:match("^%s*%S+%s+(%S+)")
		if code then ns.ShowPasteWarCode(code) else ns.ShowWars() end
	elseif cmd == "insignias" then
		ns.ToggleBanner()
	elseif cmd == "red" then
		local s = ns.NetStatus()
		self:Print((L["Red de hermandades: %s · %d hermandades · otra facción: %s"]):format(
			s.connected and L["conectado"] or (L["sin conexión"] .. (s.error and (" (" .. s.error .. ")") or "")),
			#ns.Directory(), s.crossFaction and date("%d/%m %H:%M", s.crossFaction) or L["sin ver todavía"]))
	elseif cmd == "diag" then
		self:RunDiagnostics()
	elseif cmd == "dump" then
		-- /gmk dump <expresión>: añade una comprobación suelta al diagnóstico
		local expr = input:match("^%s*%S+%s+(.+)$")
		if expr then self:RunDiagnostics(expr) else self:Print("Uso: /gmk dump <expresión>") end
	elseif cmd == "prueba" then
		local p = self.db.profile
		p.testMode = not p.testMode
		if p.testMode then
			self:Print((L["Modo prueba activado: tu grupo cuenta como hermandad, eres oficial y los datos van a \"%s\"."]):format(self:GuildName()))
			if IsInGuild() then
				self:Print(L["Tu hermandad real no recibe nada mientras esté activo. /gmk prueba para volver a ella."])
			end
			if self.db.char.consent == "pending" then ns.ShowConsent() end
			-- Ya en grupo: lo que tenga el resto del grupo llega enseguida.
			if IsInGroup() and self:HasConsent() then self:ScheduleTimer("StartSync", 3) end
		else
			self:Print(L["Modo prueba desactivado."])
			if IsInGuild() then self:StartSync() end
		end
		self:SendMessage("LANTUX_GUILD_CHANGED")
		self:DataChanged()
	elseif cmd == "debug" then
		self.db.profile.debug = not self.db.profile.debug
		self:Print("debug:", self.db.profile.debug and "on" or "off")
	else
		for _, line in ipairs(HELP) do self:Print(line) end
	end
end
