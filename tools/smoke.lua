-- Prueba de humo: carga el addon con una imitación mínima de la API de WoW y
-- pinta todas las vistas con datos de ejemplo. No comprueba el aspecto, solo
-- que no haya errores de Lua (llamadas a nil, formatos mal, etc.).
local ROOT = ADDON_ROOT
unpack = table.unpack
loadstring = load
NOW = 1790000000

-- string.format estricto como el Lua 5.1 del juego: %s y %d con nil dan error
-- (el Lua de las pruebas los acepta y escondía fallos).
do
	local format = string.format
	string.format = function(fmt, ...)
		local args, i = { ... }, 0
		for conv in tostring(fmt):gsub("%%%%", ""):gmatch("%%[%-%+ #0]*%d*%.?%d*(%a)") do
			i = i + 1
			if args[i] == nil then error(("bad argument #%d to 'format' (got nil for %%%s)"):format(i + 1, conv), 2) end
		end
		return format(fmt, ...)
	end
end

-- Objeto comodín: cualquier método existe y devuelve valores razonables.
local function mock(name)
	local o = { __name = name }
	return setmetatable(o, { __index = function(t, k)
		if type(k) ~= "string" or not k:match("^%u") then return nil end -- solo métodos (CamelCase)
		if k == "GetFrameLevel" then return function() return 1 end end
		if k == "GetStringWidth" or k == "GetStringHeight" or k == "GetHeight" or k == "GetWidth" then return function() return 20 end end
		if k == "GetText" then return function(self) return rawget(self, "_text") or "" end end
		if k == "SetText" then return function(self, v) rawset(self, "_text", v) end end
		if k == "IsShown" then return function(self) return rawget(self, "_shown") ~= false end end
		if k == "SetShown" then return function(self, v) rawset(self, "_shown", v and true or false) end end
		if k == "Show" then return function(self) rawset(self, "_shown", true) end end
		if k == "Hide" then return function(self) rawset(self, "_shown", false) end end
		if k == "SetScript" then return function(self, event, fn) local s = rawget(self, "_scripts") or {}; s[event] = fn; rawset(self, "_scripts", s) end end
		if k == "GetFontString" then return function() return mock("fs") end end
		if k == "CreateFontString" or k == "CreateTexture" or k == "CreateAnimationGroup" or k == "CreateAnimation" then return function() return mock(k) end end
		return function() return nil end
	end })
end
ALL_FRAMES = {}
CreateFrame = function(_, name) local f = mock(name or "frame"); if name then _G[name] = f end; ALL_FRAMES[#ALL_FRAMES + 1] = f; return f end
UIParent, Minimap, RaidWarningFrame, GameTooltip = mock("UIParent"), mock("Minimap"), mock("RWF"), mock("GT")
ChatTypeInfo = { RAID_WARNING = {} }
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { colorStr = "ffffffff" } end })
COMBATLOG_HONORGAIN = "%s muere (muerte con honor: %s). Obtienes %d p. de honor."
COMBATLOG_HONORGAIN_NO_RANK = "%s muere (muerte con honor). Obtienes %d p. de honor."
COMBATLOG_HONORAWARD = "Has recibido %d p. de honor."
GetPlayerInfoByGUID = GetPlayerInfoByGUID or function() return nil end
COMBATLOG_HONORGAIN_NO_RANK_EXHAUSTION1 = "%s muere (muerte con honor). Obtienes %d p. de honor (%s %s de bonificación)."
ITEM_CREATED_BY = "|cff00ff00<Hecho por %s>|r"
UNKNOWNOBJECT, CANCEL, OKAY, ERR_TRADE_COMPLETE = "Entidad desconocida", "Cancelar", "Aceptar", "Intercambio completado"
StaticPopupDialogs = {}
RELOADS = 0
ReloadUI = function() RELOADS = RELOADS + 1 end
SetPortraitTexture = function() end
CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 0.25, 0, 0.25 } end })
ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 } }
StaticPopup_Show = function() end
RaidNotice_AddMessage = function() end
hooksecurefunc = function() end
PanelTemplates_TabResize = function() end
PanelTemplates_SelectTab, PanelTemplates_DeselectTab = function() end, function() end
C_Timer = { After = function() end }
C_GuildInfo = { GuildRoster = function() end }
C_Spell = { GetSpellName = function(id) return "Receta " .. id end }
C_Item = { GetItemIconByID = function() return "icon" end }
C_TradeSkillUI = {}
date, time = os.date, os.time
GetServerTime = function() return NOW end
GetTime = function() return 1000 + (GET_TIME_OFFSET or 0) end
GetLocale = function() return SMOKE_LOCALE or "esES" end
GetRealmName, GetNormalizedRealmName = function() return "Classic Beta PvP 2" end, function() return "ClassicBetaPvP2" end
UnitName = function(u) if u == "player" then return "Lantux", "Dev" end return nil end
UnitGUID = function(u) return u == "player" and "Player-1-1" or nil end
UnitClass = function() return "Guerrero", "WARRIOR" end
UnitRace = function() return "Orco", "Orc" end
UnitLevel = function() return 30 end
UnitExists, UnitIsPlayer, UnitIsUnit, UnitIsInMyGuild = function() return false end, function() return false end, function() return false end, function() return false end
UnitInParty, UnitInRaid, UnitIsConnected = function() return false end, function() return false end, function() return true end
IsInGuild, IsInGroup, IsInRaid = function() return false end, function() return true end, function() return false end
GetNumSubgroupMembers, GetNumGroupMembers = function() return 0 end, function() return 1 end
GetGuildInfo = function() return nil end
GetInstanceInfo = function() return "Orgrimmar", "none" end
GetZoneText, GetSubZoneText = function() return "Orgrimmar" end, function() return "" end
-- Mapas: 1434 Vega de Tuercespina y 1413 Los Baldíos; 1415 Reinos del Este y 1414 Kalimdor; 947 Azeroth.
local MAPS = {
	[1434] = { name = "Vega de Tuercespina", parentMapID = 1415 }, [1413] = { name = "Los Baldíos", parentMapID = 1414 },
	[1415] = { name = "Reinos del Este", parentMapID = 947 }, [1414] = { name = "Kalimdor", parentMapID = 947 },
	[947] = { name = "Azeroth" },
}
C_Map = {
	GetBestMapForUnit = function() return 1434 end,
	GetMapInfo = function(id) return MAPS[id] or { name = "Mapa " .. id } end,
	GetMapChildrenInfo = function() return { { mapID = 1434, name = "Vega de Tuercespina" }, { mapID = 1413, name = "Los Baldíos" } } end,
	GetMapRectOnMap = function(zone, parent) return 0.4, 0.5, 0.6, 0.7 end,
}
UnitFactionGroup = function() return "Horde" end
GetProfessions = function() return nil end
GetPVPLifetimeStats = function() return 12, 0 end
GetPVPSessionStats, GetPVPYesterdayStats = function() return 2, 0 end, function() return 1, 0 end
GetAddOnMetadata = function() return "0.1.0" end
InCombatLockdown = function() return false end
IsModifiedClick = function() return false end
GetCursorInfo, ClearCursor = function() return nil end, function() end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tContains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
bit = { band = function(a, b) return a & b end }
print_ = print

-- Ace3 imitado: lo justo para que el addon arranque.
local function deepcopy(t) if type(t) ~= "table" then return t end local c = {} for k, v in pairs(t) do c[k] = deepcopy(v) end return c end
local messages = {}
local mixin = {
	RegisterEvent = function() end, UnregisterEvent = function() end,
	-- Como CallbackHandler: un solo manejador por objeto y mensaje (el segundo sustituye al primero).
	RegisterMessage = function(self, msg, fn) messages[tostring(self) .. "|" .. msg] = type(fn) == "string" and function() self[fn](self, msg) end or fn end,
	SendMessage = function(_, msg) for key, fn in pairs(messages) do if key:sub(-#msg - 1) == "|" .. msg then fn() end end end,
	ScheduleTimer = function() return 1 end, ScheduleRepeatingTimer = function() return 1 end, CancelTimer = function() end,
	Print = function(_, ...) print_("  [chat]", ...) end,
	RegisterChatCommand = function() end,
	SendCommMessage = function() end,
	RegisterComm = function(_, prefix, method) COMM_REGISTERED = COMM_REGISTERED or {}; COMM_REGISTERED[prefix] = method or "OnCommReceived" end,
	GetArgs = function(_, input) return input:match("^(%S+)%s*(%S*)") end,
}
local function newObject() local o = {} for k, v in pairs(mixin) do o[k] = v end return o end
local addon = newObject()
function addon:NewModule() return newObject() end
local libs = {
	["AceAddon-3.0"] = { NewAddon = function() return addon end },
	["AceDB-3.0"] = { New = function(_, _, defaults)
		local guildDefaults = defaults.factionrealm.guilds["*"]
		return { profile = deepcopy(defaults.profile), char = deepcopy(defaults.char), global = deepcopy(defaults.global),
			factionrealm = { guilds = setmetatable({}, { __index = function(t, k) local v = deepcopy(guildDefaults); rawset(t, k, v); return v end }) } }
	end },
	-- Ida y vuelta sin comprimir de verdad: el "texto" serializado es una clave a la tabla.
	LibSerialize = {
		Serialize = function(_, t) SERIALIZED = SERIALIZED or {}; SERIALIZED[#SERIALIZED + 1] = t; return "msg" .. #SERIALIZED end,
		Deserialize = function(_, s) local t = SERIALIZED and SERIALIZED[tonumber(s:match("^msg(%d+)$") or 0)]; return t ~= nil, t end,
	},
	LibDeflate = { CompressDeflate = function(_, s) return s end, DecompressDeflate = function(_, s) return s end,
		EncodeForWoWAddonChannel = function(_, s) return s end, DecodeForWoWAddonChannel = function(_, s) return s end,
		EncodeForPrint = function(_, s) return s end, DecodeForPrint = function(_, s) return s end },
}
LibStub = function(name) return libs[name] end

-- Carga en el orden del .toc.
local ns = {}
-- SOURCES lo rellena smoke.js con el código de cada archivo del .toc
for _, entry in ipairs(SOURCES) do
	local chunk = assert(load(entry.src, "@" .. entry.name))
	chunk("LantuxGuild", ns)
end

local LG = ns.LG
LG:OnInitialize()
LG:OnEnable()
for _, k in ipairs({ "Roster", "PvP", "Dungeon", "Hunt", "Professions", "Orders", "Events" }) do end
LG.db.profile.testMode = true
LG.db.char.consent = "yes"
-- Los bucles que pulsan todos los botones pasan por Ajustes: que no apaguen el modo
-- prueba ni la depuración a mitad de las pruebas (la pestaña se prueba aparte).
local realSlash = LG.SlashCommand
LG.SlashCommand = function(self, input)
	if input == "prueba" or input == "debug" then return end
	return realSlash(self, input)
end

-- Datos de ejemplo.
local g = LG:GuildData()
local me = ns.PlayerFullName()
ns.roster = { [me] = { rank = "Grupo", rankIndex = 0, level = 30, class = "WARRIOR", zone = "Orgrimmar", online = true },
	["Ana Sol"] = { rank = "Grupo", rankIndex = 0, level = 28, class = "MAGE", zone = "", online = false } }
g.members[me] = LG:BuildMyRecord()
g.members[me].prof = { [186] = { name = "Minería", rank = 14, max = 75 } }
g.members[me].recipes = { [186] = { name = "Minería", ids = { 2657 } } }
g.members["Ana Sol"] = { name = "Ana Sol", class = "MAGE", locale = "enUS", joined = NOW - 30 * 86400,
	prof = { [171] = { name = "Alquimia", rank = 40, max = 75 } }, recipes = { [171] = { name = "Alquimia", ids = { 2330, 2331 } } }, pvp = { hk = 5, today = 1 } }
ns.CreateEvent({ title = "Núcleo de Magma", kind = "raid", start = NOW + 3600, comp = { tank = 2, healer = 5, dps = 13 }, note = "traed fuego" })
local eventID = next(g.events)
ns.SignUp(eventID, "yes", "tank")
g.events.past1 = { id = "past1", title = "Mazmorra", kind = "dungeon", start = NOW - 10 * 86400, status = "active", creator = me, rev = 1 }
g.attendance.past1 = { [me] = NOW - 10 * 86400 }
ns.CreateOrder("Ana Sol", 2330, 3, "para la raid")
-- Encargo al gremio: lo acepta el primero; si dos aceptan a la vez, gana el anterior (y si empatan, por nombre).
do
	ns.CreateOrder(nil, 2331, 2, nil, 171)
	local gid
	for id, o in pairs(g.orders) do if o.guild then gid = id end end
	local base = g.orders[gid]
	assert(base and base.guild and not base.crafter and base.skillLine == 171, "encargo al gremio creado")
	assert(ns.MembersWithRecipe(2331)[1] == "Ana Sol" and ns.KnowsRecipe("Ana Sol", 2331), "quién tiene la receta")
	local function accept(who, t)
		local rec = {}
		for k, v in pairs(base) do rec[k] = v end
		rec.status, rec.rev, rec.by, rec.crafter, rec.updated = "accepted", 2, who, who, t
		ns.handlers.ORDER(who, rec)
	end
	assert(not ns.SetOrderStatus(gid, "accepted", { crafter = me }), "quien lo pide no lo acepta")
	accept("Vexa Sombrafría", NOW + 10)
	assert(g.orders[gid].crafter == "Vexa Sombrafría", "el primero que acepta se lo queda")
	accept("Ana Sol", NOW + 5)
	assert(g.orders[gid].crafter == "Ana Sol", "si otro aceptó antes (hora del servidor), gana ese")
	accept("Oskell Filonegro", NOW + 5)
	assert(g.orders[gid].crafter == "Ana Sol", "mismo momento: el primero por nombre")
	local fake = {}
	for k, v in pairs(g.orders[gid]) do fake[k] = v end
	fake.qty, fake.rev, fake.status, fake.by = 99, 3, "done", "Ana Sol"
	ns.handlers.ORDER("Ana Sol", fake)
	assert(g.orders[gid].qty == 2, "la cantidad no se puede cambiar")
	assert(ns.OrderExpired({ guild = true, status = "open", t = NOW - 8 * 86400 }) and not ns.OrderExpired(base), "caduca a los 7 días")
	g.orders[gid] = nil
end
g.orders.o2 = { id = "o2", t = NOW - 100, requester = "Ana Sol", crafter = me, recipe = 2657, qty = 20, status = "open", rev = 1, by = "Ana Sol", updated = NOW - 100 }
g.kills.d1 = { id = "d1", kind = "death", t = NOW - 500, guild = "Horda Mala", killerName = "Malo Uno", victimName = me, zone = "Baldíos" }
g.kills.k1 = { id = "k1", kind = "kill", t = NOW - 400, guild = "Horda Mala", killerName = me, victimName = "Malo Uno", victim = "Player-9", honorable = true, honor = 62, revenge = true, zone = "Baldíos" }
g.runs.r1 = { key = "r1", t = NOW - 300, instance = "Monasterio", instanceID = 1, boss = "Herod", members = { me, "Ana Sol" }, guildMembers = { me, "Ana Sol" }, guildCount = 5, size = 5, witnesses = { [me] = true, ["Ana Sol"] = true } }
g.spends.s1 = { id = "s1", member = "Ana Sol", merits = 5, link = "[Guanteletes]", t = NOW - 50, by = me }
ns.AdjustPoints(me, 50, 10, "prueba")
ns.ToggleTarget("Los Manual")
LG:DataChanged()

-- Pinta todas las vistas.
ns.ToggleMainFrame()
for _, tab in ipairs({ "home", "events", "market", "hunt", "guild", "officer" }) do
	ns.SelectTab(tab)
	print_("OK vista", tab)
end
-- Subvistas y desplegables.
ns.SelectTab("market")
LantuxGuildSearch:SetText("receta 23")
ns.RefreshMainFrame()
print_("OK artesanía con búsqueda")
local function clickAll() end
for _, sub in ipairs({ "orders" }) do end
-- Cambiar subvista mediante la función de los segmentos no es accesible; se fuerza por estado:
ns.SelectTab("guild")
print_("OK hermandad")
local s = ns.Scores()[me]
print_(("Puntos de %s: rep %d, méritos %d"):format(me, s.rep, s.merits))
-- Subasta de hermandad: abrir, pujas, insignias reservadas y cierre con cobro.
local link = "|cffa335ee|Hitem:16863::::|h[Guanteletes]|h|r"
assert(ns.StartAuction(link, 10, 24, true)) -- del banco: el oficial que la abre también puja
local auctionID
for id, a in pairs(g.auctions) do if a.link == link then auctionID = id end end
local before = ns.Scores()[me].merits
assert(ns.PlaceBid(auctionID, 20), "mi puja de 20")
ns.handlers.BID("Ana Sol", { auction = auctionID, member = "Ana Sol", amount = 30, t = NOW })
assert(ns.AuctionTop(g, g.auctions[auctionID]).member == me, "Ana no tiene insignias: su puja no vale")
ns.AdjustPoints("Ana Sol", 100, 0, "prueba")
assert(ns.AuctionTop(g, g.auctions[auctionID]).member == "Ana Sol", "con saldo, Ana va ganando")
local ok, err = ns.PlaceBid(auctionID, 32)
assert(not ok, "32 no supera en 5 a 30")
assert(ns.PlaceBid(auctionID, 35), "35 sí")
assert(ns.AvailableInsignias(nil) == before - 35, "35 quedan reservadas")
NOW = NOW + 25 * 3600
ns.FinishAuction(auctionID)
assert(g.auctions[auctionID].winner == me and g.auctions[auctionID].amount == 35, "gano yo por 35")
assert(ns.Scores()[me].merits == before - 35, "se cobran 35 insignias")
print_(("OK subasta: gano por 35, insignias %d -> %d"):format(before, ns.Scores()[me].merits))

-- Cofre de hermandad: el 10 % de la subasta, donaciones, catálogo de proyectos, activación y efectos.
do
	local chest0 = ns.ChestState().balance
	local decay = 0
	for _, d in ipairs(ns.DecayedToChest()) do decay = decay + d.amount end
	assert(chest0 == 35 + decay, "la subasta del banco de 35 entera, nada de la de 5 (antigua) y la bajada semanal: " .. chest0)
	ns.AdjustPoints(me, 2000, 0, "prueba del cofre")
	local function projectOf(kind)
		local item = ns.ProjectOfKind(kind)
		return item and item.p.id
	end
	assert(ns.CreateProject("dungeons"))
	assert(not ns.CreateProject("dungeons"), "solo uno de cada tipo a la vez")
	local pid = projectOf("dungeons")
	local mine = ns.Scores()[me].merits
	assert(not ns.Donate(mine + 1, pid), "no puedo donar más de lo que tengo")
	assert(ns.Donate(20, pid))
	assert(ns.Scores()[me].merits == mine - 20, "la donación descuenta")
	assert(ns.ChestState().projects[pid].funded == 20, "el proyecto suma 20")
	-- Una donación de otro que no es suya no vale; la suya sin saldo suficiente solo descuenta lo que tiene.
	ns.handlers.DONATE("Malo Uno", { id = "x1", member = "Ana Sol", merits = 10, project = pid, t = NOW })
	assert(not g.donations.x1, "nadie dona en nombre de otro")
	local ana = ns.Scores()["Ana Sol"].merits
	ns.handlers.DONATE("Ana Sol", { id = "x2", member = "Ana Sol", merits = ana + 500, project = "chest", t = NOW + 1 })
	assert(ns.Scores()["Ana Sol"].merits == 0, "Ana se queda a 0")
	assert(ns.ChestState().balance == chest0 + ana, "al cofre solo llega lo que tenía Ana")
	NOW = NOW + 10
	local bal = ns.ChestState().balance
	assert(not ns.FundProject(pid, bal + 1), "no se saca más de lo que hay")
	assert(ns.FundProject(pid, math.min(bal, 30)))
	assert(ns.ChestState().balance == bal - math.min(bal, 30), "sale del cofre")
	assert(ns.Donate(ns.ProjectRemaining(pid), pid))
	assert(ns.ProjectPhase(g.projects[pid]) == "ready", "completado, falta activarlo")
	assert(not ns.Donate(1, pid), "completado: no admite más")
	assert(not ns.BoostAt(g, "dungeons", NOW), "sin activar no hace nada")
	NOW = NOW + 10
	assert(ns.ActivateProject(pid))
	assert(ns.ProjectPhase(g.projects[pid]) == "active" and ns.BoostAt(g, "dungeons", NOW) == 1.5, "activo: x1,5")
	-- Efecto: una mazmorra 5/5 durante el proyecto da 15 en vez de 10.
	local beforeRun = ns.Scores()[me].merits
	NOW = NOW + 10
	g.runs.boosted = { key = "boosted", t = NOW, instance = "Cavernas", instanceID = 77, boss = "Jefe", members = { me, "Ana Sol" },
		guildMembers = { me, "Ana Sol" }, guildCount = 5, size = 5, witnesses = { [me] = true, ["Ana Sol"] = true } }
	ns.InvalidateScores()
	assert(ns.Scores()[me].merits - beforeRun == 15, "mazmorra x1,5: " .. (ns.Scores()[me].merits - beforeRun))
	assert(ns.Scores()[me].recent[1].reason:find("x1,5", 1, true), "el motivo dice el extra")
	g.runs.boosted = nil
	-- Sube como la espuma: un nivel 20 alcanzado durante el proyecto.
	assert(ns.CreateProject("levels"))
	local lid = projectOf("levels")
	assert(ns.Donate(ns.ProjectRemaining(lid), lid) and ns.ActivateProject(lid))
	NOW = NOW + 10
	g.members[me].levels = { { level = 19, t = NOW - 5 }, { level = 20, t = NOW } }
	ns.InvalidateScores()
	assert(ns.Scores()[me].recent[1].reason:find("20", 1, true), "nivel 20: +15")
	g.members[me].levels = nil
	-- Estandarte: el emblema de la hermandad sale junto al retrato.
	assert(not ns.BadgeData(me).standard or ns.ActiveProjects().standard, "sin estandarte, sin emblema")
	assert(ns.CreateProject("standard"))
	local sid = projectOf("standard")
	assert(ns.Donate(ns.ProjectRemaining(sid), sid) and ns.ActivateProject(sid))
	assert(ns.BadgeData(me).standard, "con estandarte, emblema")
	-- Cancelar devuelve lo reunido al cofre.
	NOW = NOW + 10
	assert(ns.CreateProject("hunt"))
	local cid = projectOf("hunt")
	assert(ns.Donate(5, cid))
	local before = ns.ChestState().balance
	NOW = NOW + 10
	assert(ns.CancelProject(cid))
	assert(ns.ChestState().balance == before + 5, "lo reunido vuelve al cofre")
	assert(not ns.Donate(1, cid), "cancelado: no admite más")
	assert(ns.CreateProject("hunt"), "cancelado: se puede abrir otro")
	-- Un proyecto de alguien que no es oficial no vale.
	LG.db.profile.testMode = false
	ns.handlers.PROJECT("Pepe Raso", { id = "p:pepe", rev = 1, kind = "bg", goal = 400, status = "open", creator = "Pepe Raso", by = "Pepe Raso" })
	LG.db.profile.testMode = true
	assert(not g.projects["p:pepe"], "solo oficiales crean proyectos")
	ns.handlers.PROJECT(me, { id = "p:raro", rev = 1, kind = "inventado", goal = 400, status = "open", creator = me, by = me })
	assert(not g.projects["p:raro"], "solo tipos del catálogo")
	-- Un proyecto guardado con el formato antiguo (sin tipo del catálogo) se ignora y no rompe nada.
	g.projects.legacy = { id = "legacy", rev = 1, title = "Viejo", goal = 100, reward = "standard", status = "open", creator = me, by = me }
	g.donations.legacyd = { id = "legacyd", member = me, merits = 5, project = "legacy", t = NOW }
	ns.InvalidateScores()
	local lists = ns.ProjectLists()
	for _, phase in pairs(lists) do for _, item in ipairs(phase) do assert(item.p.id ~= "legacy", "el antiguo no sale") end end
	print_(("OK cofre: %d insignias, %d activos, %d abiertos"):format(ns.ChestState().balance, #lists.active, #lists.open))
end
ns.ShowOrderDialog("Ana Sol", 2330)
ns.ShowEventDialog()
ns.ShowAuctionStart()
print_("OK diálogos")

-- Pulsa todos los botones visibles de cada pestaña, varias rondas.
local clicks = 0
for round = 1, 3 do
	for _, tab in ipairs({ "home", "events", "market", "hunt", "guild", "officer" }) do
		ns.SelectTab(tab)
		for _, f in ipairs(ALL_FRAMES) do
			local onClick = rawget(f, "_scripts") and f._scripts.OnClick
			if onClick and rawget(f, "_shown") ~= false then
				local ok, err = pcall(onClick, f, "LeftButton")
				if not ok then error(("clic en la pestaña %s: %s"):format(tab, tostring(err))) end
				clicks = clicks + 1
			end
		end
	end
end
-- Los clics pasan también por Ajustes (modo prueba, depuración...): se deja como estaba.
LG.db.profile.testMode, LG.db.profile.debug, LG.db.char.consent = true, false, "yes"; LG.db.profile.testRank = nil
print_("OK clics sin errores:", clicks)

-- Cada apartado de cada sección (los clics de arriba casi nunca llegan: los botones de
-- navegación cambian de sección antes), pintado y con sus botones pulsados.
do
	local subClicks, seen = 0, 0
	for _, tab in ipairs({ "market", "hunt", "guild", "pve", "faction" }) do
		for _, key in ipairs(ns.SubviewKeys(tab)) do
			ns.SelectSubview(tab, key)
			seen = seen + 1
			for _, f in ipairs(ALL_FRAMES) do
				local onClick = rawget(f, "_scripts") and f._scripts.OnClick
				if onClick and not rawget(f, "isNav") and rawget(f, "_shown") ~= false then
					local ok, err = pcall(onClick, f, "LeftButton")
					if not ok then error(("clic en %s › %s: %s"):format(tab, key, tostring(err))) end
					subClicks = subClicks + 1
					local cur, sub = ns.CurrentView()
					if cur ~= tab or sub ~= key then ns.SelectSubview(tab, key) end
				end
			end
		end
	end
	LG.db.profile.testMode, LG.db.profile.debug, LG.db.char.consent = true, false, "yes"; LG.db.profile.testRank = nil
	g.settings.listed = nil -- y por «salir en el directorio» de Facción
	print_(("OK apartados: %d pintados, %d clics"):format(seen, subClicks))
end

-- Recepción: el prefijo tiene que estar registrado o AceComm no entrega nada.
assert(COMM_REGISTERED and COMM_REGISTERED[ns.COMM_PREFIX], "prefijo de la hermandad registrado")
do
	-- Un mensaje de hermandad que llega por un canal público se descarta; el mismo
	-- por el grupo (modo prueba) sí entra.
	local LibSerialize, LibDeflate = LibStub("LibSerialize"), LibStub("LibDeflate")
	local function packed(id)
		return LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(LibSerialize:Serialize({ p = 1, k = "KILL", v = "0.0.1",
			d = { id = id, kind = "death", t = 1, reporter = "Intruso Malo", victimName = "Intruso Malo" } })))
	end
	LG:OnCommReceived(ns.COMM_PREFIX, packed("por-canal"), "CHANNEL", "Intruso Malo")
	assert(not g.kills["por-canal"], "mensaje de hermandad por canal descartado")
	LG:OnCommReceived(ns.COMM_PREFIX, packed("por-grupo"), "PARTY", "Intruso Malo")
	assert(g.kills["por-grupo"], "el mismo mensaje por el grupo sí entra (control)")
	g.kills["por-grupo"] = nil
end
print_("OK recepción: prefijo registrado, nada de la hermandad por canales")

-- Datos de ejemplo de Caza en modo prueba.
ns.FillTestData()
local s2 = ns.HuntStats(7)
local nKills = 0
for _, k in pairs(g.kills) do if k.test and not k.war then nKills = nKills + 1 end end
assert(nKills == 58, "22 muertes + 30 kills + 6 sospechosas de ejemplo")
ns.SelectTab("hunt")
ns.SelectTab("guild")
print_(("OK datos de ejemplo: %d registros, %d hermandades nos matan"):format(nKills, (function() local c = 0 for _ in pairs(s2.killedBy) do c = c + 1 end return c end)()))

-- Integridad: los datos sospechosos de ejemplo generan avisos, y anular quita los puntos.
do
	local kinds = {}
	for _, a in ipairs(ns.Anomalies()) do kinds[a.key:match("^(%a+)")] = a end
	assert(kinds.hk and kinds.hk.severity == "high", "aviso de contador de honor")
	assert(kinds.victim, "aviso de misma víctima")
	assert(kinds.adjust and kinds.adjust.severity == "info", "aviso de ajuste grande")
	local function cheaterHunts()
		local n = 0
		for _, k in ipairs(ns.HuntStats(7).recent) do
			if k.kind == "kill" and k.killerName == "Oskell Filonegro" then n = n + 1 end
		end
		return n
	end
	local before = cheaterHunts()
	ns.SetVoided(kinds.victim.items, true)
	assert(cheaterHunts() == before - #kinds.victim.items, "las kills anuladas desaparecen")
	for _, a in ipairs(ns.Anomalies()) do assert(not a.key:find("^victim"), "el aviso se va al anular") end
	assert(#ns.RecentVoids(10) == #kinds.victim.items, "lista de anuladas")
	ns.SelectTab("officer")
	ns.SetVoided(kinds.victim.items, false)
	assert(cheaterHunts() == before, "restaurar devuelve las kills")
	ns.DismissAnomaly(kinds.adjust.key)
	for _, a in ipairs(ns.Anomalies()) do assert(a.key ~= kinds.adjust.key, "visto oculta el aviso") end
	-- Quien firma la anulación tiene que ser quien la envía.
	local fake = { id = "x", t = ns.Now() + 10, active = true, by = "Lantux Dev" }
	assert(not ns.MergeVoid(g, fake, "Otro Nombre"), "anulación con firma falsa")
	-- Inspección: el contador visto por otro frente al que manda su addon.
	local vexa = g.members["Vexa Sombrafría"]
	local function seenAlert()
		for _, a in ipairs(ns.Anomalies()) do if a.key:find("^hkseen|Vexa") then return a end end
	end
	assert(not ns.MergeHonorSeen(g, { member = "Vexa Sombrafría", hk = 5, t = NOW, by = "Vexa Sombrafría" }), "nadie se inspecciona a sí mismo")
	assert(not ns.MergeHonorSeen(g, { member = "Vexa Sombrafría", hk = 5, t = NOW, by = "Ana Sol" }, "Otro"), "la inspección la firma quien la envía")
	ns.handlers.HONOR("Ana Sol", { member = "Vexa Sombrafría", hk = vexa.pvp.hk, t = vexa.t + 60, by = "Ana Sol" })
	assert(g.honorSeen["Vexa Sombrafría"] and not seenAlert(), "contador que cuadra: sin aviso")
	ns.handlers.HONOR("Ana Sol", { member = "Vexa Sombrafría", hk = vexa.pvp.hk - 10, t = vexa.t + 120, by = "Ana Sol" })
	assert(seenAlert() and seenAlert().severity == "high", "su addon dice más de lo que ve el juego: aviso")
	g.honorSeen["Vexa Sombrafría"] = nil
	print_("OK integridad: avisos de honor, víctima, ajuste e inspección; anular, restaurar y visto")
end

-- Guerras y red de hermandades con los datos de ejemplo (las guerras, en pausa: se encienden solo aquí).
do
	ns.WARS_PAUSED = false
	ns.InvalidateAchievements()
	local guild = LG:GuildName()
	assert(#ns.Directory() == 6, "6 hermandades de ejemplo en el directorio")
	local byEnemy, phases = {}, {}
	for _, w in pairs(g.wars) do
		byEnemy[ns.WarEnemy(w, guild)] = w
		local p = ns.WarPhase(w)
		phases[p] = (phases[p] or 0) + 1
	end
	assert(phases.finished == 2 and phases.active == 1 and phases.pending == 1, "fases de las guerras de ejemplo")
	-- Ganada: 10 muertes que confirma el rival + 3 kills sobre un rival sin addon = 13; 6 bajas nuestras.
	local s = ns.WarScore(byEnemy["Guardia de Ventormenta"])
	assert(s.confirmed and s.ours == 13 and s.theirs == 6, ("marcador ganado: %d-%d"):format(s.ours, s.theirs))
	s = ns.WarScore(byEnemy["Escudo de Plata"])
	assert(s.ours == 5 and s.theirs == 8, ("marcador perdido: %d-%d"):format(s.ours, s.theirs))
	local record = ns.WarRecord()
	assert(record.wins == 1 and record.losses == 1, "una victoria y una derrota")
	assert(record.specials.first and record.specials.crush and not record.specials.streak3, "trofeos: primera victoria y aplastante (13-6)")
	-- En Desafíos: categoría Guerras con los 6 trofeos especiales, 2 conseguidos.
	ns.InvalidateAchievements()
	local ach = ns.AchievementState()
	assert(ach.byId["war:first"].done and ach.byId["war:crush"].done and not ach.byId["war:wall"].done, "trofeos de guerra en Desafíos")
	-- Temporadas: una guerra ganada de la temporada pasada (temporada 0 = antes de la 1) da una proeza y no cuenta en la actual.
	local old = byEnemy["Guardia de Ventormenta"]
	local savedSeason = old.season
	old.season = ns.PvPSeason() - 1
	local rec2 = ns.WarRecord()
	assert(rec2.wins == 0 and rec2.losses == 1, "la temporada actual solo tiene la derrota")
	assert(ns.WarRecord(old.season).wins == 1, "la victoria queda en su temporada")
	old.season = savedSeason
	local pointsBefore = ach.points
	ns.InvalidateAchievements()
	assert(ns.AchievementState().points == pointsBefore, "las proezas no dan puntos")
	local st = ns.WarStats(byEnemy["Guardia de Ventormenta"])
	assert(st.topKiller and st.firstBlood and st.theirTop, "estadísticas de la guerra")

	-- Aceptar la declaración pendiente.
	local incoming = byEnemy["Hijos de Forjaz"]
	ns.AnswerWar(incoming.id, "accepted")
	assert(incoming.status == "accepted" and incoming.ratingTo == record.rating, "declaración aceptada con nuestra puntuación")
	-- Una vez aceptada no se puede rechazar.
	ns.AnswerWar(incoming.id, "declined")
	assert(incoming.status == "accepted", "aceptar es definitivo")

	-- Declarar una guerra: la hermandad de ejemplo acepta (aquí se simula al momento).
	assert(ns.DeclareWar("Colmillo Sangriento", ns.Now() + 7200, 5) ~= nil, "duración demasiado corta rechazada")
	local declareErr = ns.DeclareWar("Colmillo Sangriento", ns.Now() + 7200, 60)
	assert(declareErr == nil, "guerra declarada: " .. tostring(declareErr))
	local declared
	for _, w in pairs(g.wars) do if w.to == "Colmillo Sangriento" then declared = w end end
	assert(declared and declared.status == "pending" and declared.map == 1434, "pendiente, en la zona actual")
	assert(ns.DeclareWar("Colmillo Sangriento", ns.Now() + 9000, 60) ~= nil, "no dos guerras a la vez con la misma hermandad")
	ns.SimulateWarAnswer(declared.id, "accepted")
	assert(declared.status == "accepted" and ns.WarPhase(declared) == "upcoming", "aceptada por la otra hermandad")

	-- Seguridad: lo de mi bando no puede venir por la red ni en un código.
	local fake = {}
	for k, v in pairs(declared) do fake[k] = v end
	fake.status, fake.rev, fake.side, fake.by = "cancelled", declared.rev + 1, guild, "Impostor Malo"
	assert(not ns.MergeWar(g, guild, fake, "Impostor Malo", "code"), "un código no habla por mi hermandad")
	-- Y lo del rival, por la red, solo lo firma quien lo envía.
	fake.side, fake.by = "Colmillo Sangriento", "GM Colmillo"
	assert(not ns.MergeWar(g, guild, fake, "Otro Distinto", "net"), "firma falsa por la red")
	-- Un marcador de mi propia hermandad no se toma como el del rival.
	assert(not ns.MergeWarReport(g, guild, { id = declared.id, guild = guild, t = ns.Now() + 5, deaths = 99 }, "X", "net"), "marcador propio")

	-- Códigos: ida y vuelta.
	local code = ns.WarCode(byEnemy["Guardia de Ventormenta"].id)
	assert(code and code:find("^LG1:"), "código generado")
	local kind, data = ns.DecodeCode(code)
	assert(kind == "TICK" and data.guild == guild and data.final, "el código de una guerra terminada lleva nuestro marcador final")

	-- Marcador en pantalla: con la guerra de ejemplo en curso, se ve.
	ns.WARS_PAUSED = true
	ns.RefreshWarHud()
	assert(not (_G.LantuxGuildWarHud and _G.LantuxGuildWarHud:IsShown()), "guerras en pausa: sin marcador en pantalla")
	ns.WARS_PAUSED = false
	ns.RefreshWarHud()
	assert(_G.LantuxGuildWarHud and _G.LantuxGuildWarHud:IsShown(), "marcador de guerra en pantalla")

	-- Directorio por la red: un anuncio de la otra facción marca la red como común.
	ns.netHandlers.HI("Alguien Lejano", { guild = "Nueva Alianza", faction = "Alliance", members = 10, addon = 3, rating = 1000 })
	assert(ns.DirectoryEntry("Nueva Alianza"), "anuncio guardado")
	ns.netHandlers.HI("Alguien Lejano", { guild = "Nueva Alianza", hidden = true })
	assert(not ns.DirectoryEntry("Nueva Alianza"), "una hermandad oculta desaparece")
	assert(ns.netHandlers.KILL == nil and ns.netHandlers.ME == nil, "la red no tiene manejadores de datos de hermandad")
	-- Red de pruebas: en modo prueba solo se oye el prefijo de pruebas, y lo que
	-- llega se marca como de prueba (fuera del modo prueba no se ve).
	do
		local LS, LD = LibStub("LibSerialize"), LibStub("LibDeflate")
		local function netText(kind, d) return LD:EncodeForWoWAddonChannel(LD:CompressDeflate(LS:Serialize({ p = 1, k = kind, v = LG.VERSION, d = d }))) end
		local hiTest = { guild = "~Pruebas Alianza", faction = "Alliance", members = 3, addon = 1 }
		ns.OnNetMessage("LantuxNet", netText("HI", hiTest), "CHANNEL", "Probador Real")
		assert(not ns.DirectoryEntry("~Pruebas Alianza"), "modo prueba: la red real no se oye")
		ns.OnNetMessage("LantuxNetT", netText("HI", hiTest), "CHANNEL", "Probador Real")
		local e = ns.DirectoryEntry("~Pruebas Alianza")
		assert(e and e.test and e.live, "modo prueba: la red de pruebas sí, marcada como de prueba")
		LG.db.profile.testMode = false
		assert(not ns.DirectoryEntry("~Pruebas Alianza"), "lo de la red de pruebas no se ve fuera del modo prueba")
		ns.OnNetMessage("LantuxNetT", netText("HI", { guild = "Otra Prueba", faction = "Alliance" }), "CHANNEL", "Probador Real")
		assert(not LG.db.global.directory["Otra Prueba"], "fuera del modo prueba la red de pruebas no se oye")
		LG.db.profile.testMode = true
		LG.db.global.directory["~Pruebas Alianza"] = nil
		assert(ns.IsTestGuild(LG:GuildName()) and LG:GuildName() ~= "~Pruebas", "la hermandad de prueba lleva la facción")
	end

	-- Las tres secciones de Caza, con clics en todo.
	local warClicks = 0
	for _, section in ipairs({ "targets", "wars", "directory" }) do
		for round = 1, 2 do
			ns.ShowHuntSection(section)
			for _, f in ipairs(ALL_FRAMES) do
				local onClick = rawget(f, "_scripts") and f._scripts.OnClick
				if onClick and rawget(f, "_shown") ~= false then
					local ok, err = pcall(onClick, f, "LeftButton")
					if not ok then error(("clic en Caza > %s: %s"):format(section, tostring(err))) end
					warClicks = warClicks + 1
				end
			end
		end
	end
	ns.ShowPasteWarCode()
	ns.ShowDeclareWarDialog("Escudo de Plata")

	-- Calendario: días con eventos/guerras marcados, elegir un día y cambiar de mes.
	if not LantuxGuildFrame:IsShown() then ns.ToggleMainFrame() end
	ns.SelectTab("events")
	local cal
	for _, f in ipairs(ALL_FRAMES) do if rawget(f, "cal") then cal = f.cal end end
	assert(cal, "calendario pintado en Eventos")
	local marked = 0
	for _, cell in ipairs(cal.cells) do
		if rawget(cell.icons[1], "_shown") then marked = marked + 1 end
	end
	assert(marked >= 3, ("días marcados en el calendario: %d"):format(marked))
	local function shownTexts()
		local all = {}
		for _, f in ipairs(ALL_FRAMES) do
			local t = rawget(f, "text")
			if type(t) == "table" and rawget(f, "_shown") ~= false then all[#all + 1] = tostring(rawget(t, "_text") or "") end
			local card = rawget(f, "card")
			if card and rawget(f, "_shown") ~= false and rawget(card.title, "_shown") ~= false then all[#all + 1] = tostring(rawget(card.title, "_text") or "") end
		end
		return table.concat(all, "\n")
	end
	cal.today._scripts.OnClick() -- hoy: la guerra en curso contra Los Errantes
	assert(shownTexts():find("Los Errantes", 1, true), "el día de hoy muestra la guerra en curso")
	for _ = 1, 13 do cal.next._scripts.OnClick() end
	local wrapped = rawget(cal.title, "_text") or ""
	for _ = 1, 13 do cal.prev._scripts.OnClick() end
	assert(wrapped ~= (rawget(cal.title, "_text") or ""), "13 meses adelante es otro año")
	print_(("OK calendario: %d días marcados, día elegido con su guerra, %s"):format(marked, wrapped))

	-- Zona por nombre, sin estar allí.
	assert(ns.FindZone("vega") == 1434, "zona por un trozo del nombre")
	assert(ns.FindZone("BALDIOS") == 1413, "zona sin tildes ni mayúsculas")
	assert(ns.FindZone("Atlántida") == nil, "zona desconocida")
	assert(ns.DeclareWar("Escudo de Plata", ns.Now() + 7200, 60, "baldios") == nil, "guerra en otra zona")
	for _, w in pairs(g.wars) do
		if w.to == "Escudo de Plata" and w.status == "pending" then assert(w.map == 1413 and w.zone == "Los Baldíos", "zona elegida") end
	end

	-- Mapa del mundo: espadas en la zona y en su continente, no en el otro.
	local shownMap = 1434
	WorldMapFrame = CreateFrame("Frame")
	WorldMapFrame.GetMapID = function() return shownMap end
	WorldMapFrame.GetCanvas = function() return CreateFrame("Frame") end
	local expected = 0
	for _, w in pairs(g.wars) do
		local p = ns.WarPhase(w)
		if (p == "active" or p == "upcoming") and w.map == 1434 then expected = expected + 1 end
	end
	local inZone = ns.RefreshWarMap()
	shownMap = 1415
	local inContinent = ns.RefreshWarMap()
	shownMap = 1414
	local elsewhere = ns.RefreshWarMap()
	assert(expected > 0 and inZone == expected and inContinent == expected and elsewhere == 0,
		("espadas en el mapa (%d guerras): zona %d, continente %d, otro continente %d"):format(expected, inZone, inContinent, elsewhere))
	WorldMapFrame = nil
	ns.WARS_PAUSED = true
	ns.InvalidateAchievements()
	print_(("OK guerras: marcadores 13-6 y 5-8, clasificación %d, %d trofeos, aceptar/declarar, seguridad, códigos, directorio, %d clics"):format(
		record.rating, (function() local n = 0 for _ in pairs(record.specials) do n = n + 1 end return n end)(), warClicks))
end
-- Desafíos de hermandad con los datos de ejemplo.
local st = ns.AchievementState()
assert(ns.GuildLevel(0) == 1 and ns.GuildLevel(13) == 2 and ns.GuildLevel(95) == 10 and ns.GuildLevel(500) == 10, "nivel de hermandad: uno cada 10 puntos, del 1 al 10")
assert(#ns.ACH_REWARDS == 9 and ns.GuildPerks().level == ns.GuildLevel(st.points), "recompensas por nivel")
assert(st.total == #ns.ACHIEVEMENTS + #ns.WarChallengeDefs() + #ns.LegacyChallengeDefs(), "estado de todos los desafíos (con los de legado; los de guerra, en pausa)")
local lines = {}
for _, e in ipairs(st.list) do
	if e.progress > 0 then lines[#lines + 1] = ("%s %d/%d%s"):format(e.def.id, e.progress, e.target, e.done and " ✓" or "") end
end
print_(("OK desafíos: %d/%d puntos · %s"):format(st.points, st.total, table.concat(lines, ", ")))
ns.ToggleAchievements()
local before = #ALL_FRAMES
for round = 1, 3 do
	for _, f in ipairs(ALL_FRAMES) do
		local onClick = rawget(f, "_scripts") and f._scripts.OnClick
		if onClick then
			local ok, err = pcall(onClick, f, "LeftButton")
			if not ok then error("clic en desafíos: " .. tostring(err)) end
		end
	end
end
print_(("OK ventana de desafíos: %d marcos, clics sin errores"):format(#ALL_FRAMES - before))

-- Con la ventana de Desafíos ya creada, la principal tiene que seguir
-- repintándose al cambiar los datos (antes la de Desafíos le "robaba" el aviso).
do
	local repaints = 0
	local original = ns.RefreshMainFrame
	ns.RefreshMainFrame = function(...) repaints = repaints + 1; return original(...) end
	LG:DataChanged()
	ns.RefreshMainFrame = original
	assert(repaints == 1, ("la ventana principal se repinta tras abrir Desafíos (%d)"):format(repaints))
	print_("OK refresco: la ventana principal sigue repintándose con Desafíos abierto")
end

-- Copia de seguridad de los datos guardados (fallo de la beta: a veces no cargan).
do
	-- 1. Restaurar desde la copia si GuildmarkDB no cargó.
	GuildmarkDB = { global = { schema = 2, diag = { grande = true }, chars = { ["Lantux Dev"] = {} } }, char = { x = { consent = "yes" } } }
	ns.WriteBackup()
	assert(GuildmarkBackup and GuildmarkBackup.db.global.schema == 2, "copia escrita")
	assert(GuildmarkBackup.db.global.diag == nil, "sin el diagnóstico en la copia")
	GuildmarkDB = nil
	assert(ns.RestoreSavedVariables() and GuildmarkDB.global.schema == 2 and GuildmarkDB.char.x.consent == "yes", "restaurado desde la copia")
	assert(not ns.RestoreSavedVariables(), "con datos cargados no se toca nada")
	GuildmarkDB, GuildmarkBackup = nil, nil
	assert(not ns.RestoreSavedVariables(), "sin datos ni copia: instalación nueva")

	-- 2. Recuperar lo personal desde la ficha que tiene la hermandad.
	local s = LG.db.char.stats
	local mining, crafted = s.gathered.mining or 0, s.crafted or 0
	local guild = LG:GuildName()
	LG.db.char.hkBase[guild] = { t = NOW, hk = 50 }
	LG.db.char.joined[guild] = NOW
	local adopted = ns.AdoptOwnRecord({ name = ns.PlayerFullName(), joined = NOW - 20 * 86400,
		stats = { gathered = { mining = mining + 300 }, crafted = 0, week = s.week },
		pvp = { base = { t = NOW - 30 * 86400, hk = 12 } }, legacy = { [3263] = { [777] = { instanceID = 33 } } } })
	assert(adopted, "se adopta lo que falta")
	assert(s.gathered.mining == mining + 300 and s.crafted == crafted, "cuentas: el mayor (sin bajar las que ya eran mayores)")
	assert(LG.db.char.joined[guild] == NOW - 20 * 86400, "antigüedad: la más antigua")
	assert(LG.db.char.hkBase[guild].hk == 12, "contador de honor de partida: el más antiguo")
	assert(LG.db.global.legacyLearned[3263][777], "jefes aprendidos: se juntan")
	assert(not ns.AdoptOwnRecord({ name = ns.PlayerFullName(), stats = { gathered = { mining = 1 } } }), "nada que recuperar: no cambia")
	LG.db.global.legacyLearned[3263] = nil
	print_("OK copia de seguridad: restaurar, sin diagnóstico, recuperar de la ficha de la hermandad")
end

-- Puente por Battle.net con la otra facción.
do
	local sent = {}
	BNET_CLIENT_WOW = "WoW"
	BNGetNumFriends = function() return 2 end
	C_BattleNet = {
		GetFriendNumGameAccounts = function() return 1 end,
		GetFriendGameAccountInfo = function(i)
			if i == 1 then return { isOnline = true, gameAccountID = 101, clientProgram = "WoW", characterName = "Aldric Escudoalto", factionName = "Alliance" } end
			return { isOnline = true, gameAccountID = 102, clientProgram = "WoW", characterName = "Grom Amigo", factionName = "Horde" }
		end,
	}
	BNSendGameData = function(id, prefix, text) sent[#sent + 1] = { id = id, prefix = prefix, text = text } end
	local LS, LD = LibStub("LibSerialize"), LibStub("LibDeflate")
	local function text(tbl) return LD:EncodeForWoWAddonChannel(LD:CompressDeflate(LS:Serialize(tbl))) end

	assert(#ns.BridgeFriends() == 2, "amigos de Battle.net en el juego")
	-- Solo cuentan como puente los de la otra facción que han respondido (tienen el addon).
	assert(#ns.BridgePeers() == 0, "sin respuesta no hay puente")
	-- Modo prueba: el puente usa su propio prefijo y no oye el real.
	ns.OnBridgeMessage("LantuxBr", text({ k = "BA", f = "Alliance" }), "WHISPER", 101)
	assert(#ns.BridgePeers() == 0, "modo prueba: el puente real no se oye")
	ns.OnBridgeMessage("LantuxBrT", text({ k = "BA", f = "Alliance" }), "WHISPER", 101)
	assert(#ns.BridgePeers() == 1, "modo prueba: puente de pruebas")
	assert(ns.BridgeForward({ o = "Yo", of = "Horde", id = "a1", k = "HI", d = { guild = "X" } }) == 1 and sent[#sent].prefix == "LantuxBrT", "modo prueba: se envía con el prefijo de pruebas")
	ns.BridgeReset()
	local testGuild = LG:GuildName()
	LG.db.profile.testMode = false

	ns.OnBridgeMessage("LantuxBr", text({ k = "BA", f = "Alliance" }), "WHISPER", 101)
	ns.OnBridgeMessage("LantuxBr", text({ k = "BA", f = "Horde" }), "WHISPER", 102)
	local peers = ns.BridgePeers()
	assert(#peers == 1 and peers[1].id == 101 and peers[1].name == "Aldric Escudoalto", "puente: solo el amigo de la Alianza")

	-- Enviar: al amigo de la otra facción, con el prefijo real.
	local n = ns.BridgeForward({ o = "Yo", of = "Horde", id = "a2", k = "HI", d = { guild = "X" } })
	assert(n == 1 and sent[#sent].id == 101 and sent[#sent].prefix == "LantuxBr", "enviado al amigo de la otra facción")

	-- Recibir de la otra facción: se usa (directorio) y no se repite dos veces.
	local hi = { o = "Brenna Vientoclaro", of = "Alliance", id = "b1", k = "HI", d = { guild = "Puente Alianza", faction = "Alliance", members = 12, addon = 3 } }
	ns.OnBridgeMessage("LantuxBr", text({ k = "ENV", e = hi }), "WHISPER", 101)
	assert(ns.DirectoryEntry("Puente Alianza"), "hermandad de la otra facción por el puente")
	LG.db.global.directory["Puente Alianza"] = nil
	ns.OnBridgeMessage("LantuxBr", text({ k = "ENV", e = hi }), "WHISPER", 101)
	assert(not ns.DirectoryEntry("Puente Alianza"), "el mismo mensaje dos veces se ignora")
	-- Lo que dice ser de mi propia facción por el puente se descarta.
	ns.OnBridgeMessage("LantuxBr", text({ k = "ENV", e = { o = "Z", of = "Horde", id = "b2", k = "HI", d = { guild = "Falsa Horda", faction = "Horde" } } }), "WHISPER", 101)
	assert(not ns.DirectoryEntry("Falsa Horda"), "de mi facción por el puente, no")
	-- Repetido en el canal por otro puente (RLY): se usa una sola vez.
	local rly = { o = "Dalia Rayoluna", of = "Alliance", id = "b3", k = "HI", d = { guild = "Escudo Lejano", faction = "Alliance" } }
	ns.netHandlers.RLY("Otro Horda", rly)
	assert(ns.DirectoryEntry("Escudo Lejano"), "RLY del canal entregado")
	LG.db.global.directory["Escudo Lejano"] = nil
	ns.netHandlers.RLY("Otro Horda", rly)
	assert(not ns.DirectoryEntry("Escudo Lejano"), "RLY repetido ignorado")
	LG.db.profile.testMode = true
	-- Reenviado nunca habla por mi hermandad.
	local guild = testGuild
	local fakeWar = { id = "w-relay", rev = 1, from = guild, to = "Puente Alianza", start = ns.Now() + 3600, duration = 3600,
		status = "pending", side = guild, by = ns.PlayerFullName() }
	assert(not ns.MergeWar(g, guild, fakeWar, ns.PlayerFullName(), "relay"), "un reenvío no declara guerras por mi hermandad")
	-- Capas: se leen del GUID de los PNJ y cada bando anuncia la suya en la guerra.
	ns.NoteLayer(17292, 1413); ns.NoteLayer(206, 1413); ns.NoteLayer(9999, 1413)
	assert(ns.LayerNumber(206, 1413) == 1 and ns.LayerNumber(9999, 1413) == 2 and ns.LayerNumber(17292, 1413) == 3, "capas numeradas de menor a mayor")
	assert(ns.LayerLabel(1, 1413) == ns.L["capa ?"], "capa sin numerar")
	assert(ns.ParseLayer("Creature-0-4621-2991-206-257521-0000451660") == 206, "capa del GUID de un PNJ")
	assert(ns.ParseLayer("Player-4621-0ABCDEF1") == nil and ns.ParseLayer("Pet-0-4621-2991-206-1234-0000451660") == nil, "solo PNJ")
	local layerWar = { id = "w-layer", rev = 1, from = guild, to = "~Pruebas Alianza", zone = "Los Baldíos",
		start = ns.Now() - 60, duration = 3600, status = "accepted", side = "~Pruebas Alianza", by = "Rival", t = ns.Now() }
	g.wars[layerWar.id] = layerWar
	ns.activity["Compi Capa"] = { kind = "war", zone = "Los Baldíos", layer = 206, t = ns.Now() }
	ns.netHandlers.LAYER("Rival Alianza", { id = layerWar.id, guild = "Otra Cualquiera", layers = { [307] = 2 } })
	assert(not layerWar.enemyLayers, "solo cuenta la capa del rival de esa guerra")
	ns.netHandlers.LAYER("Rival Alianza", { id = layerWar.id, guild = "~Pruebas Alianza", layers = { [307] = 2, [206] = 1 } })
	local ls = ns.WarLayerStatus(layerWar)
	assert(ls.ours == 206 and ls.theirs == 307 and ls.mismatch, "capas distintas detectadas")
	assert(ns.WarLayerText(layerWar):find("307"), "aviso de capas distintas en la tarjeta")
	layerWar.enemyLayers.layers = { [206] = 4 }
	assert(not ns.WarLayerStatus(layerWar).mismatch, "misma capa")
	g.wars[layerWar.id], ns.activity["Compi Capa"] = nil, nil

	BNSendGameData, C_BattleNet, BNGetNumFriends = nil, nil, nil
	print_("OK puente Battle.net: amigos, solo la otra facción, envío, recepción sin repetidos, RLY, seguridad")
end

-- JcE: buscador de grupo y tiempos de mazmorra (con los datos de ejemplo).
do
	ns.FillTestData()
	local me = ns.PlayerFullName()
	local groups = ns.LFGGroups()
	assert(#groups == 3 and groups[1].leader == me, "3 grupos de ejemplo, el mío delante")
	local mine = ns.MyLFGGroup()
	assert(ns.CreateLFG("Uldaman", 5, "dps") ~= nil, "no dos grupos a la vez")
	-- Aceptar la petición de ejemplo (Mirelle como tanque): ocupa la plaza.
	ns.AnswerLFG(mine.id, "Mirelle Hojaverde", true)
	mine = ns.MyLFGGroup()
	assert(mine.have.tank == 1 and mine.members["Mirelle Hojaverde"] == "tank", "invitar ocupa la plaza")
	assert(not ns.lfgRequests[mine.id]["Mirelle Hojaverde"], "la petición se va")
	-- Pedir invitación a otro grupo: solo a los roles que faltan.
	local vexa
	for _, grp in ipairs(groups) do if grp.leader == "Vexa Sombrafría" then vexa = grp end end
	assert(#ns.LFGMissing(vexa) == 2, "a Vexa le faltan sanador y un DPS")
	ns.lfgMine[vexa.id] = nil -- los clics de antes pueden haber pedido ya plaza
	ns.RequestLFG(vexa.id, "tank")
	assert(not ns.lfgMine[vexa.id], "no se pide un rol que no falta")
	ns.RequestLFG(vexa.id, "healer")
	assert(ns.lfgMine[vexa.id] == "pending", "petición enviada")
	-- Una petición que llega a mi grupo de alguien de la hermandad.
	ns.handlers.LFGREQ("Thorvi Martillo", { group = mine.id, to = me, role = "dps", t = ns.Now() })
	assert(ns.lfgRequests[mine.id]["Thorvi Martillo"], "petición recibida")
	-- Solo el líder cambia su grupo.
	local fake = {}
	for k, v in pairs(vexa) do fake[k] = v end
	fake.rev, fake.status = vexa.rev + 1, "closed"
	assert(not ns.MergeLFG(g, fake, "Otro Cualquiera"), "solo el líder cierra su grupo")
	ns.CloseLFG(mine.id)
	assert(not ns.MyLFGGroup(), "cerrado")
	assert(ns.CreateLFG("minas", 5, "healer") == nil and ns.MyLFGGroup().dest == "Las Minas de la Muerte", "destino por un trozo del nombre")
	assert(ns.CreateLFG("x", 7, "dps") ~= nil, "tamaño no válido")
	-- Tiempos: mejor marca por mazmorra.
	local times = ns.DungeonTimes()
	assert(#times == 2 and times[1].dungeon == "Las Minas de la Muerte" and math.floor(times[1].runs[1].duration / 60) == 41, "tiempos de ejemplo")
	assert(ns.FormatRunTime(41.5 * 60) == "41:30", "formato del tiempo")
	-- Entrada en la instancia: morir y volver no reinicia el reloj.
	local instType, instID = "party", 36
	local savedGII = GetInstanceInfo
	GetInstanceInfo = function() return "Minas", instType, 1, "", 5, 0, false, instID end
	NOW = NOW + 1
	ns.TrackInstanceEntry()
	local entered = ns.InstanceEnteredAt()
	instType = "none"; NOW = NOW + 120; ns.TrackInstanceEntry()
	instType = "party"; NOW = NOW + 120; ns.TrackInstanceEntry()
	assert(ns.InstanceEnteredAt() == entered, "volver tras morir no reinicia")
	GetInstanceInfo = savedGII
	-- Las vistas, con clics.
	for _, section in ipairs({ "lfg", "times" }) do
		ns.SelectTab("pve")
		for _, f in ipairs(ALL_FRAMES) do
			local onClick = rawget(f, "_scripts") and f._scripts.OnClick
			if onClick and rawget(f, "_shown") ~= false then pcall(onClick, f, "LeftButton") end
		end
	end
	ns.ShowCreateLFG()
	-- Desplegable y autocompletado del destino.
	local opts = ns.DungeonOptions()
	local total = 0
	for _, grp in ipairs(opts) do total = total + #grp.items end
	assert(#opts == 3 and total == 34, ("mazmorras por nivel: %d grupos, %d mazmorras"):format(#opts, total))
	local dlg = LantuxGuildInputDialog
	local destBox = dlg.boxes[1]
	destBox.drop._scripts.OnClick()
	assert(rawget(dlg.pick, "_shown") ~= false, "el botón despliega la lista")
	destBox:SetText("cuev")
	destBox._scripts.OnTextChanged(destBox, true)
	local firstValue
	for _, b in ipairs(dlg.pick.rows) do
		if rawget(b, "_shown") ~= false and b._scripts.OnClick then firstValue = b; break end
	end
	assert(firstValue, "al escribir aparecen coincidencias")
	firstValue._scripts.OnClick()
	assert(destBox:GetText() == "Cuevas de los Lamentos" and dlg.boxes[2]:GetText() == "5", "elegir rellena el destino y el tamaño")
	assert(ns.FindDestination("salon de los feudales") == "Salón de los Feudales", "las dos mazmorras de un mismo criterio")
	print_("OK JcE: grupos, peticiones, invitar, solo el líder, destino, tiempos, entrada en la instancia")
end

-- Tribus y actividad (Ahora).
do
	LG.db.profile.testMode = true
	ns.FillTestData()
	local me = ns.PlayerFullName()
	assert(#ns.ActiveTribes() == 1 and ns.TribeOf(me) and ns.TribeOf(me).name == "Colmillos de Hierro", "tribu aprobada de ejemplo")
	-- Ahora: el grupo de ejemplo es la tribu jugando junta.
	local groups, loose = ns.GuildActivity()
	assert(#groups == 1 and groups[1].tribe and groups[1].tribe.name == "Colmillos de Hierro", "grupo de la tribu en Ahora")
	assert(#loose >= 2, "gente suelta por zona")
	-- Mi actividad y su aviso.
	local sum = ns.ActivitySummary()
	assert(sum.grouped == 5 and sum.instance == 5, ("resumen de Ahora: %d en grupo"):format(sum.grouped))
	ns.handlers.ACT("Ana Sol", { kind = "dungeon", zone = "Desolace", instance = "Maraudon", since = NOW })
	assert(ns.activity["Ana Sol"].instance == "Maraudon", "actividad recibida")
	ns.handlers.ACT("Ana Sol", { kind = "hackeo" })
	assert(ns.activity["Ana Sol"].kind == "dungeon", "tipo de actividad desconocido ignorado")
	-- Proponer: no se puede estar en dos tribus.
	assert(ns.ProposeTribe("Otra Más", { "Draknar Puñohierro", "Ana Sol" }) ~= nil, "una sola tribu por jugador")
	-- Propuesta de otro miembro, aceptación y aprobación.
	local id = "Ana Sol:1"
	ns.handlers.TRIBE("Ana Sol", { id = id, name = "Los Rezagados", members = { ["Ana Sol"] = true, ["Thorvi Martillo"] = true, ["Mirelle Hojaverde"] = true },
		creator = "Ana Sol", status = "pending", rev = 1, by = "Ana Sol", t = NOW })
	assert(g.tribes[id] and g.tribes[id].status == "pending", "propuesta recibida")
	ns.handlers.TRIBEACC("Impostor", { tribe = id, member = "Thorvi Martillo", t = NOW })
	assert(not (g.tribeAccepts[id] or {})["Thorvi Martillo"], "solo el propio miembro acepta")
	-- Modo prueba: un miembro de ejemplo acepta por boca de otro (sim), pero fuera del modo prueba no.
	LG.db.profile.testMode = false
	assert(not ns.MergeTribeAccept(g, { tribe = id, member = "Thorvi Martillo", t = NOW, sim = true }, "Impostor"), "sin modo prueba no hay aceptaciones simuladas")
	LG.db.profile.testMode = true
	assert(ns.MergeTribeAccept(g, { tribe = id, member = "Thorvi Martillo", t = NOW, sim = true }, "Impostor"), "modo prueba: el de ejemplo acepta solo")
	g.tribeAccepts[id]["Thorvi Martillo"] = nil
	ns.handlers.TRIBEACC("Thorvi Martillo", { tribe = id, member = "Thorvi Martillo", t = NOW })
	ns.handlers.TRIBEACC("Mirelle Hojaverde", { tribe = id, member = "Mirelle Hojaverde", t = NOW })
	ns.DecideTribe(id, "approved")
	assert(g.tribes[id].status == "approved" and #ns.TribeMembers(g, g.tribes[id]) == 3, "aprobada con 3")
	-- Una propuesta con 2 miembros no vale.
	ns.handlers.TRIBE("Ana Sol", { id = "Ana Sol:2", name = "Dúo", members = { ["Ana Sol"] = true, ["Lantux Dev"] = true },
		creator = "Ana Sol", status = "pending", rev = 1, by = "Ana Sol", t = NOW })
	assert(not g.tribes["Ana Sol:2"], "mínimo 3 miembros")
	-- Invitar a una tribu existente: lo hace el líder, sin oficial; el invitado acepta.
	local mine = ns.TribeOf(me)
	assert(ns.TribeLeader(g, mine) == "Draknar Puñohierro", "líder: quien la propuso")
	assert(ns.InviteTribe(mine.id, "Ana Sol") ~= nil, "solo el líder invita")
	ns.handlers.TRIBEINV("Draknar Puñohierro", { tribe = mine.id, member = "Kaelthorn Ojoagudo", by = "Draknar Puñohierro", t = NOW + 1 })
	assert(#ns.TribeMembers(g, mine) == 4, "invitado, aún no es miembro")
	ns.handlers.TRIBEACC("Kaelthorn Ojoagudo", { tribe = mine.id, member = "Kaelthorn Ojoagudo", t = NOW + 2 })
	assert(#ns.TribeMembers(g, mine) == 5, "al aceptar, entra")
	-- Icono: uno de Guildmark por defecto; lo cambia el líder (no cualquiera) con el selector.
	local icon = ns.TribeIcon(mine)
	assert(ns.ValidTribeIcon(icon) and select(2, ns.TribeIconTexture(icon)), "icono propio por defecto")
	local savedCan = ns.CanManageEvents
	ns.CanManageEvents = function() return false end -- en modo prueba todos son oficiales
	assert(not ns.MergeTribeIcon(g, { tribe = mine.id, icon = "alliance_03", by = "Ana Sol", t = NOW + 5 }, "Ana Sol"), "solo el líder cambia el icono")
	ns.CanManageEvents = savedCan
	ns.handlers.TRIBEICON("Draknar Puñohierro", { tribe = mine.id, icon = 136243, by = "Draknar Puñohierro", t = NOW + 6 })
	assert(ns.TribeIcon(mine) == 136243 and not select(2, ns.TribeIconTexture(136243)), "el líder elige un icono del juego")
	assert(not ns.ValidTribeIcon("../../malo") and not ns.ValidTribeIcon(-1), "iconos inválidos")
	GetMacroIcons = function(t) t[#t + 1] = 136243; t[#t + 1] = 134400 end
	local picked
	ns.ShowIconPicker(ns.TribeIcon(mine), function(v) picked = v end)
	assert(GuildmarkIconPicker:IsShown() and GuildmarkIconPicker.buttons[1].value == ns.TRIBE_ICONS[UnitFactionGroup("player") == "Alliance" and "Alliance" or "Horde"][1], "selector: primero los de Guildmark de tu facción")
	GuildmarkIconPicker.buttons[2]._scripts.OnClick(GuildmarkIconPicker.buttons[2])
	assert(picked and ns.ValidTribeIcon(picked), "elegir un icono")
	GetMacroIcons = nil
	g.tribeIcons[mine.id] = nil
	-- Alguien de otra tribu no puede ser invitado.
	ns.handlers.TRIBEINV("Draknar Puñohierro", { tribe = mine.id, member = "Thorvi Martillo", by = "Draknar Puñohierro", t = NOW + 3 })
	assert(not (g.tribeInvites[mine.id] or {})["Thorvi Martillo"], "una tribu por jugador")
	-- Salir y volver con una invitación nueva.
	ns.handlers.TRIBELEFT("Kaelthorn Ojoagudo", { tribe = mine.id, member = "Kaelthorn Ojoagudo", t = NOW + 4 })
	assert(#ns.TribeMembers(g, mine) == 4, "salió")
	ns.handlers.TRIBEINV("Draknar Puñohierro", { tribe = mine.id, member = "Kaelthorn Ojoagudo", by = "Draknar Puñohierro", t = NOW + 5 })
	ns.handlers.TRIBEACC("Kaelthorn Ojoagudo", { tribe = mine.id, member = "Kaelthorn Ojoagudo", t = NOW + 6 })
	assert(#ns.TribeMembers(g, mine) == 5, "vuelve con otra invitación")
	-- Nombre según la facción.
	assert(ns.TribeWords().One == ns.L["Tribu"], "Horda: tribu")
	local savedFaction = UnitFactionGroup
	UnitFactionGroup = function() return "Alliance" end
	assert(ns.TribeWords().One == ns.L["Clan"] and ns.TribeWords().the == ns.L["el clan"], "Alianza: clan")
	UnitFactionGroup = savedFaction
	-- Clasificación y salir.
	assert(#ns.TribeStats() == 2, "clasificación de tribus")
	ns.LeaveTribe(ns.TribeOf(me).id)
	assert(not ns.TribeOf(me), "salir de la tribu")
	-- Vistas y formulario.
	ns.SelectTab("guild")
	for round = 1, 3 do
		for _, f in ipairs(ALL_FRAMES) do
			local onClick = rawget(f, "_scripts") and f._scripts.OnClick
			if onClick and rawget(f, "_shown") ~= false and f ~= LantuxGuildFrame then pcall(onClick, f, "LeftButton") end
		end
	end
	LG.db.profile.testMode, LG.db.profile.debug, LG.db.char.consent = true, false, "yes"; LG.db.profile.testRank = nil
	ns.ShowProposeTribe()
	print_("OK tribus y Ahora: tribu junta, actividad, una tribu por jugador, aceptar, aprobar, mínimo 3, salir")
end

-- Insignias sobre los marcos de jugador y de objetivo.
do
	LG.db.profile.testMode = true
	LG.db.profile.banner = { player = true, target = true, share = true } -- los bucles de clics pasan por Ajustes
	LG.db.char.profile = {} -- y por el selector de insignias del perfil
	ns.FillTestData()
	ns.InvalidateAchievements()
	PlayerFrame, TargetFrame = CreateFrame("Frame"), CreateFrame("Frame")
	local Banner = ns.BannerModule
	Banner:OnEnable()
	Banner:UpdatePlayer()
	local strip = LantuxGuildPlayerBanner
	assert(rawget(strip, "_shown") ~= false and strip.tabard.tip[1]:find(LG:GuildName(), 1, true), "insignias propias con la hermandad")
	local honors = ns.BadgeData(ns.PlayerFullName()).honors
	assert(#honors > 0 and #honors <= 5, ("honores propios: %d"):format(#honors))
	for _, key in ipairs(honors) do assert(ns.ResolveHonor(key), "honor sin traducir: " .. key) end
	-- Rango JcJ (renombre 2800): el propio en directo, va primero en las insignias y sale en la clasificación.
	C_MajorFactions = { GetMajorFactionProgressionInfo = function(id)
		if id == 2800 then return { renownLevel = 3, maxLevel = 14, renownReputationEarned = 200, renownLevelThreshold = 750 } end
	end }
	local pr = ns.MemberPvPRank(ns.PlayerFullName())
	assert(pr and pr.level == 3 and pr.max == 14 and pr.need == 750, "rango JcJ propio")
	assert(ns.BadgeData(ns.PlayerFullName()).honors[1]:find("^pvp:%u:3$") and ns.ResolveHonor(ns.BadgeData(ns.PlayerFullName()).honors[1]), "el rango JcJ va primero en las insignias")
	assert(not ns.ResolveHonor("pvp:H:99"), "rango JcJ fuera de rango, ignorado")
	g.members["Ana Sol"].pvp.rank = { level = "7", max = 14, earned = 10, need = 750 }
	assert(ns.MemberPvPRank("Ana Sol").level == 7, "rango JcJ de otro miembro, saneado")
	C_MajorFactions = nil
	-- Objetivo de otra hermandad: se pide por la red y llega su respuesta.
	local savedExists, savedPlayer, savedFriend = UnitExists, UnitIsPlayer, UnitIsFriend
	UnitExists, UnitIsPlayer, UnitIsFriend = function() return true end, function() return true end, function() return true end
	local savedUFN = ns.UnitFullName
	ns.UnitFullName = function(unit) return unit == "target" and "Ajeno Lejano" or savedUFN(unit) end
	Banner:UpdateTarget()
	assert(rawget(LantuxGuildTargetBanner, "_shown") == false, "sin respuesta aún, no se ve")
	ns.netHandlers.BDA("Ajeno Lejano", { name = "Ajeno Lejano", guild = "Otra Hermandad", faction = "Horde",
		honors = { "feat:league:1:3", "title:4", "war:giant", "Interface/Icons/Inventado" }, rank = "veteran", rankLabel = "Veterano", standard = true })
	Banner:UpdateTarget()
	assert(rawget(LantuxGuildTargetBanner, "_shown") ~= false and LantuxGuildTargetBanner.tabard.tip[1] == "<Otra Hermandad>", "insignias del objetivo por la red")
	assert(rawget(LantuxGuildTargetBanner.badges[3], "_shown") ~= false and rawget(LantuxGuildTargetBanner.badges[4], "_shown") == false, "3 honores válidos; la clave inventada no se pinta")
	assert(rawget(LantuxGuildTargetBanner.crownFrame, "_shown") == false, "sin corona si no es el líder")
	ns.netHandlers.BDA("Sin Estandarte", { name = "Sin Estandarte", guild = "Pobres", faction = "Horde", honors = {} })
	local savedName = ns.UnitFullName
	ns.UnitFullName = function(unit) return unit == "target" and "Sin Estandarte" or savedUFN(unit) end
	Banner:UpdateTarget()
	assert(rawget(LantuxGuildTargetBanner.tabard, "_shown") == false, "sin estandarte no sale el emblema")
	ns.UnitFullName = savedName
	Banner:UpdateTarget()
	-- Una respuesta firmada por otro no vale.
	ns.netHandlers.BDA("Impostor", { name = "Ajeno Lejano", guild = "Falsa" })
	Banner:UpdateTarget()
	assert(LantuxGuildTargetBanner.tabard.tip[1] == "<Otra Hermandad>", "respuesta con firma falsa ignorada")
	UnitExists, UnitIsPlayer, UnitIsFriend, ns.UnitFullName = savedExists, savedPlayer, savedFriend, savedUFN
	ns.ToggleBanner()
	assert(rawget(strip, "_shown") == false, "/gmk insignias las oculta")
	ns.ToggleBanner()
	print_("OK insignias: propias, del objetivo por la red, firma, ocultar")
	-- Ajustes: la pestaña y sus botones.
	ns.SelectTab("settings")
	for _, f in ipairs(ALL_FRAMES) do
		local onClick = rawget(f, "_scripts") and f._scripts.OnClick
		if onClick and rawget(f, "_shown") ~= false and f ~= LantuxGuildFrame then pcall(onClick, f, "LeftButton") end
	end
	ns.SetBannerSetting("share", false)
	assert(not ns.BannerSetting("share"), "ajuste de compartir insignias")
	LG.db.profile.testMode, LG.db.profile.debug, LG.db.char.consent = true, false, "yes"; LG.db.profile.testRank = nil
	ns.SetBannerSetting("share", true)
	print_("OK ajustes: pestaña y opciones")
end

-- Desafíos de legado (encendidos desde que las estadísticas de jefe final dan la mazmorra).
do
	ns.LEGACY_CHALLENGES = false
	ns.InvalidateAchievements()
	local base = ns.AchievementState().total
	assert(base == #ns.ACHIEVEMENTS + #ns.WarChallengeDefs(), "apagados no cambian el catálogo")
	local savedRuns = g.runs
	g.runs = {} -- sin las partidas de los datos de ejemplo
	ns.LEGACY_CHALLENGES = true
	local function run(key, fields)
		local r = { key = key, t = NOW - 3600, size = 5, guildCount = 5, witnesses = { ["Lantux Dev"] = true, ["Ana Sol"] = true } }
		for k, v in pairs(fields) do r[k] = v end
		g.runs[key] = r
	end
	local learned = LG.db.global.legacyLearned
	-- Minas de la Muerte: un jefe que no es el final (criatura distinta) no cuenta.
	run("lg:deadmines", { instance = "Las Minas de la Muerte", encounterID = 1, boss = "Rhahk'Zor", creatures = { 644 } })
	-- Colmillo Oscuro: jefe final aprendido (777); otro jefe no cuenta, el final sí.
	learned[3263] = { [777] = { instanceID = 33 } }
	run("lg:sfk-wrong", { instance = "Castillo de Colmillo Oscuro", instanceID = 33, encounterID = 5, boss = "Rethilgore" })
	-- "Sima Ígnea o Salón de los Feudales": dos jefes finales posibles; vale cualquiera.
	learned[19213] = { [100] = { instanceID = 389 }, [200] = { instanceID = 9001 } }
	run("lg:thanes", { instance = "Salón de los Feudales", instanceID = 9001, encounterID = 200, boss = "Rey de los Feudales" })
	-- Banda de hermandad (18 de 20) contra un jefe de Conqueror of the Wilds.
	run("lg:raid", { raid = true, size = 20, guildCount = 18, boss = "Bandalar", instance = "Barrow Deeps" })
	ns.InvalidateAchievements()
	local st = ns.AchievementState()
	local dungeonCount = 0
	for _, id in ipairs({ 62031, 62032, 62033 }) do dungeonCount = dungeonCount + #ns.LEGACY_FALLBACK[id].criteria end
	assert(st.total == base + 5 + dungeonCount, ("5 agrupados + %d por mazmorra (%d)"):format(dungeonCount, st.total - base))
	assert(st.byId["dg:19213"].done, "Sima Ígnea o Salón de los Feudales: vale el Salón")
	assert(not st.byId["dg:3263"].done, "Colmillo Oscuro: otro jefe no cuenta")
	assert(not st.byId["dg:3262"].done, "Minas: otro jefe no cuenta")
	-- Sin criatura en el criterio y sin aprender: ya no queda "por identificar" (lo da la estadística).
	learned[19213] = nil
	ns.InvalidateAchievements()
	local thanes = ns.AchievementState().byId["dg:19213"]
	assert(not thanes.done and not thanes.criteria, "Sima Ígnea o Salón: pendiente, pero se sabe por la estadística")
	-- Partida registrada por la estadística de jefe final: cuenta por su criterio.
	run("lg:ragefire-stat", { instance = "Sima Ígnea", boss = "Sima Ígnea", finalStat = 15027, criterion = 19213 })
	ns.InvalidateAchievements()
	assert(ns.AchievementState().byId["dg:19213"].done, "Sima Ígnea completada por su estadística")
	g.runs["lg:ragefire-stat"] = nil
	learned[19213] = { [100] = { instanceID = 389 }, [200] = { instanceID = 9001 } }
	ns.InvalidateAchievements()
	st = ns.AchievementState()
	assert(st.byId.legacy_dg1.progress == 1, ("Espeleólogo novicio 1/6 (%d)"):format(st.byId.legacy_dg1.progress))
	run("lg:sfk-final", { instance = "Castillo de Colmillo Oscuro", instanceID = 33, encounterID = 777, boss = "Arugal" })
	ns.InvalidateAchievements()
	st = ns.AchievementState()
	assert(st.byId["dg:3263"].done and st.byId.legacy_dg1.progress == 2, "con el jefe final, Colmillo Oscuro cuenta")
	-- VanCleef (639) entre los jefes muertos que trae ENCOUNTER_END: Minas completada sin aprender nada.
	run("lg:deadmines-final", { instance = "Las Minas de la Muerte", encounterID = 2, boss = "VanCleef", creatures = { 639 } })
	ns.InvalidateAchievements()
	assert(ns.AchievementState().byId["dg:3262"].done, "jefe final por ID de criatura")
	st = ns.AchievementState()
	assert(st.byId.legacy_raid1.target == 13 and st.byId.legacy_raid1.progress == 1, "banda: 1 de 13 jefes")
	-- Lo aprendido por otro miembro (en su ficha) también vale.
	learned[3263] = nil
	g.members["Ana Sol"] = g.members["Ana Sol"] or { name = "Ana Sol", t = NOW }
	g.members["Ana Sol"].legacy = { [3263] = { [777] = { instanceID = 33 } } }
	ns.InvalidateAchievements()
	assert(ns.AchievementState().byId["dg:3263"].done, "jefe final aprendido por otro miembro")
	-- Diagnóstico del aviso de jefe derrotado.
	ns.OnEncounterEnd(1144, "VanCleef", 1, 5, 1)
	local log = LG.db.global.diag.encounters
	assert(log and log[#log].id == 1144 and log[#log].name == "VanCleef", "aviso de jefe guardado en diag")
	-- La estadística de un jefe final sube: se apunta en el diagnóstico (y, en grupo de hermandad, partida).
	local values = { [15028] = 2 }
	local savedStat = GetStatistic
	GetStatistic = function(id) return values[id] and tostring(values[id]) or "--" end
	ns.CheckBossStats()
	values[15028] = 3
	local risen = ns.CheckBossStats()
	GetStatistic = savedStat
	local blog = LG.db.global.diag.bossStats
	assert(#risen == 1 and risen[1] == 15028 and blog[#blog].dungeon == "Cuevas de los Lamentos", "sube la estadística de Mutanus: Cuevas de los Lamentos")
	-- Deja todo como estaba.
	g.runs = savedRuns
	learned[19213] = nil
	g.members["Ana Sol"].legacy = nil
	ns.LEGACY_CHALLENGES = true
	ns.InvalidateAchievements()
	print_(("OK desafíos de legado: 5 agrupados + %d por mazmorra, jefe final por criatura o aprendido, varios finales, aprendido por otro, banda 1/13"):format(dungeonCount))
end
ns.ShowAchievementToast(st.list[1])
print_("OK aviso de desafío completado")

-- Recolección y fabricación: mensajes de botín con el formato del juego.
LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE = "Recibes botín: %s.", "Recibes botín: %sx%d."
LOOT_ITEM_CREATED_SELF, LOOT_ITEM_CREATED_SELF_MULTIPLE = "Creas: %s.", "Creas: %sx%d."
local ore = "|cffffffff|Hitem:2770::::::::|h[Mena de cobre]|h|r"
local kind, itemID, qty = ns.ParseLootMessage("Recibes botín: " .. ore .. "x3.")
assert(kind == "looted" and itemID == 2770 and qty == 3, "botín múltiple")
kind, itemID, qty = ns.ParseLootMessage("Recibes botín: " .. ore .. ".")
assert(kind == "looted" and qty == 1, "botín simple")
kind, itemID, qty = ns.ParseLootMessage("Creas: |cffffffff|Hitem:2840::::|h[Lingote de cobre]|h|rx5.")
assert(kind == "created" and itemID == 2840 and qty == 5, "objetos creados")
local st0 = LG.db.char.stats
local mining0 = st0.gathered.mining
ns.HandleLootMessage("Recibes botín: " .. ore .. "x2.")
assert(st0.gathered.mining == mining0, "botín sin recolectar no cuenta")
ns.HandleSpellcast(2575) -- Minería
ns.HandleLootMessage("Recibes botín: " .. ore .. "x2.")
assert(LG.db.char.stats.gathered.mining == mining0 + 2, "botín tras Minería cuenta")
GET_TIME_OFFSET = 30
ns.HandleLootMessage("Recibes botín: " .. ore .. "x2.")
assert(LG.db.char.stats.gathered.mining == mining0 + 2, "fuera de la ventana no cuenta")
GET_TIME_OFFSET = 0
local crafted0 = LG.db.char.stats.crafted
ns.HandleLootMessage("Creas: |cffffffff|Hitem:2840::::|h[Lingote de cobre]|h|rx5.")
assert(LG.db.char.stats.crafted == crafted0 + 5, "objetos fabricados")
print_("OK recolección y fabricación: botín tras Minería, fuera de ventana, objetos creados")

-- Llamada a las armas: muerte de otro miembro recibida por el canal.
-- (Los bucles de clics anteriores pueden haber cambiado el modo con el botón "Cambiar".)
LG.db.profile.callToArms = "zone"
GetZoneText = function() return "Baldíos" end
ns.TestCallToArms()
assert(LantuxGuildCallToArms and LantuxGuildCallToArms:IsShown(), "aviso de prueba visible")
LantuxGuildCallToArms:Hide()
ns.OnKillReceived({ kind = "death", t = NOW, reporter = "Ana Sol", victimName = "Ana Sol", killerName = "Malo Uno",
	class = "ROGUE", guild = "Horda Mala", zone = "Baldíos" })
assert(LantuxGuildCallToArms:IsShown(), "aviso al caer un compañero en tu zona")
LantuxGuildCallToArms:Hide()
ns.OnKillReceived({ kind = "death", t = NOW, reporter = "Ana Sol", victimName = "Ana Sol", killerName = "Malo Dos",
	class = "MAGE", guild = "Horda Mala", zone = "Desolace" })
assert(not LantuxGuildCallToArms:IsShown(), "en otra zona solo una línea en el chat")
ns.OnKillReceived({ kind = "death", t = NOW - 3600, reporter = "Ana Sol", victimName = "Ana Sol", killerName = "Viejo",
	zone = "Baldíos" })
assert(not LantuxGuildCallToArms:IsShown(), "no se avisa de muertes antiguas")
print_("OK llamada a las armas: zona, otra zona y muertes antiguas")

-- Perfil: medallas, ficha limpia, títulos comprobados, insignias elegidas y texto oculto por un oficial.
do
	local me = ns.PlayerFullName()
	local medals = ns.MemberMedals(me)
	assert(#medals == 8 and type(medals[1].value) == "number", "8 medallas con su valor")
	for _, md in ipairs(medals) do
		if md.def.key == "regicide" then assert(md.tier == 0 or md.tier == 3, "el regicidio solo tiene oro") end
	end
	ns.SaveProfile({ motto = "Hola |TInterface\\Icons\\Inventado:64|t mundo", story = string.rep("a", 500), title = "medal:hunter", role = "tank" })
	local p = ns.MemberProfile(me)
	assert(p.motto and not p.motto:find("|", 1, true), "el lema sale sin códigos de escape")
	assert(#p.story == 300, "la historia se corta a 300")
	assert(p.role == ns.L["Tanque"], "papel")
	local hunter = ns.MedalTier(me, "hunter")
	assert((p.title ~= nil) == (hunter == 3), "el título de una medalla solo con su oro")
	-- Insignias elegidas: una medalla que tengo sale con su grado; una que no tengo, no.
	local earned
	for _, md in ipairs(ns.MemberMedals(me)) do if md.tier > 0 and not earned then earned = md end end
	if earned then
		ns.SaveProfile({ badges = { "medal:" .. earned.def.key, "medal:inventada", "elite" } })
		local honors = ns.BadgeData(me).honors
		assert(honors[1] == ("medal:%s:%d"):format(earned.def.key, earned.tier), "la medalla elegida, con su grado")
		assert(ns.ResolveHonor(honors[1]), "la medalla se pinta")
		for _, k in ipairs(honors) do assert(k ~= "medal:inventada", "no se cuela una que no existe") end
	end
	assert(not ns.ResolveHonor("medal:inventada:1"), "medalla inventada, ignorada")
	local rec = LG:BuildMyRecord()
	assert(rec.profile and rec.profile.role == "tank" and #rec.profile.story == 300, "la ficha viaja en el registro")
	-- La ficha de otro, oculta por un oficial.
	g.members["Ana Sol"].profile = { motto = "Soy Ana", story = "Historia de Ana" }
	assert(ns.MemberProfile("Ana Sol").motto == "Soy Ana", "lema de Ana")
	ns.SetProfileHidden("Ana Sol", true)
	assert(ns.MemberProfile("Ana Sol").hidden and not ns.MemberProfile("Ana Sol").motto, "texto oculto")
	ns.SetProfileHidden("Ana Sol", false)
	if ns.ProfileShown() then ns.ToggleProfile(ns.ProfileShown()) end -- los clics de antes pueden haberlo dejado abierto
	ns.ToggleProfile()
	assert(ns.ProfileShown() == me, "perfil propio abierto")
	ns.ToggleProfile("Ana Sol")
	assert(ns.ProfileShown() == "Ana Sol", "perfil de Ana")
	ns.ToggleProfile("Ana Sol")
	assert(not ns.ProfileShown(), "cerrado")
	LG.db.char.profile = {}
	print_("OK perfil: medallas, ficha limpia, títulos, insignias elegidas y texto oculto")
end

-- Botín de guerra y cabezas con precio: pérdida al morir (una al día), reparto al cazar al asesino,
-- recompensas puestas a mano que caducan al cofre y el mínimo de 24 h activado.
do
	local me = ns.PlayerFullName()
	ns.AdjustPoints(me, 500, 0, "prueba del botín")
	LG.db.char.wager = {}
	NOW = NOW + 86400
	assert(ns.SetWager(true) and ns.WagerState().on, "botín de guerra activado")
	assert(not ns.SetWager(false), "no se quita antes de 24 h")
	LG:MarkDirty()
	local myLevel = tonumber(g.members[me].level) or 30
	local before = ns.Scores()[me].merits
	NOW = NOW + 60
	local death = { id = "w:d1", kind = "death", t = NOW, reporter = me, victimName = me, victim = "Player-ME",
		killer = "Player-K1", killerName = "Asesino Uno", level = myLevel, guild = "Los Malos", zone = "Baldíos" }
	ns.MergeKill(g, death)
	ns.OnKillReceived(death)
	LG:DataChanged()
	local lost = math.floor((before - 50) * 0.10)
	assert(ns.Scores()[me].merits == before - lost, ("pierdo el 10 %% de lo que pasa de 50: %d -> %d"):format(before, ns.Scores()[me].merits))
	local targets = ns.BountyTargets()
	assert(#targets >= 1 and targets[1].total >= lost and ns.SameName(targets[1].name, "Asesino Uno"), "precio por su cabeza")
	-- Otra muerte el mismo día: no se pierde más.
	local death2 = { id = "w:d2", kind = "death", t = NOW + 30, reporter = me, victimName = me, killer = "Player-K2",
		killerName = "Asesino Dos", level = myLevel, zone = "Baldíos" }
	ns.MergeKill(g, death2)
	LG:DataChanged()
	assert(ns.Scores()[me].merits == before - lost, "una pérdida al día")
	-- Un asesino de mucho más nivel o en un campo de batalla tampoco cuenta.
	NOW = NOW + 86400
	ns.MergeKill(g, { id = "w:d3", kind = "death", t = NOW, reporter = me, victimName = me, killer = "Player-K3", killerName = "Gigante", level = myLevel + 20 })
	ns.MergeKill(g, { id = "w:d4", kind = "death", t = NOW + 1, reporter = me, victimName = me, killer = "Player-K4", killerName = "Del CdB", level = myLevel, bg = true })
	LG:DataChanged()
	assert(ns.Scores()[me].merits == before - lost, "sin honor para el asesino o en un CdB, no se pierde")
	-- Ana caza al asesino: la mitad para ella y la mitad vuelve a mí.
	local ana = ns.Scores()["Ana Sol"].merits
	NOW = NOW + 60
	ns.MergeKill(g, { id = "w:k1", kind = "kill", t = NOW, reporter = "Ana Sol", killerName = "Ana Sol", victim = "Player-K1", victimName = "Asesino Uno", guild = "Los Malos" })
	LG:DataChanged()
	local half = math.floor(lost / 2)
	assert(ns.Scores()[me].merits == before - lost + half, "recupero la mitad")
	assert(ns.Scores()["Ana Sol"].merits >= ana + (lost - half), "Ana cobra la otra mitad")
	assert(#ns.BountyClaims() >= 1, "cobrada")
	-- Recompensa a mano: si nadie la cobra en 7 días, va al cofre.
	local mine = ns.Scores()[me].merits
	assert(not ns.PlaceBounty("Ana Sol", 10), "no a alguien de la hermandad")
	assert(ns.PlaceBounty("Malo Dos", 30))
	assert(ns.Scores()[me].merits == mine - 30, "pongo 30")
	local chest = ns.ChestState().balance
	NOW = NOW + 8 * 86400
	LG:DataChanged()
	assert(ns.ChestState().balance >= chest + 30, "caducada: al cofre")
	ns.handlers.BOUNTY("Malo Uno", { id = "bx", member = "Ana Sol", t = NOW, merits = 10, name = "Alguien" })
	assert(not g.bounties.bx, "nadie pone precio en nombre de otro")
	assert(ns.SetWager(false), "a los 10 días ya se puede quitar")
	for _, id in ipairs({ "w:d1", "w:d2", "w:d3", "w:d4", "w:k1" }) do g.kills[id] = nil end
	LG.db.char.wager = {}
	LG:DataChanged()
	print_(("OK botín de guerra: pierdo %d, recupero %d, precio a mano al cofre"):format(lost, half))
end

-- Tienda: comprar, no comprar dos veces, usar en el perfil, compras sin saldo y tasas de tribus rechazadas.
do
	local me = ns.PlayerFullName()
	wipe(g.purchases) -- los clics de los apartados pueden haber comprado algo
	ns.AdjustPoints(me, 300, 0, "prueba de la tienda")
	NOW = NOW + 10
	local before = ns.Scores()[me].merits
	assert(ns.Buy("frame_bronze"), "compro el marco de bronce")
	assert(ns.Owns(me, "frame_bronze") and ns.Scores()[me].merits == before - 100, "lo tengo y cuesta 100")
	assert(not ns.Buy("frame_bronze"), "no se compra dos veces")
	assert(ns.UseCosmetic("frame", "frame_bronze") and ns.MemberProfile(me).frame.key == "frame_bronze", "lo llevo en el perfil")
	assert(not ns.UseCosmetic("velvet", "velvet_purple"), "no puedo usar lo que no tengo")
	-- Ana dice llevar el marco de oro sin haberlo comprado: no sale.
	g.members["Ana Sol"].profile = { frame = "frame_gold" }
	assert(not ns.MemberProfile("Ana Sol").frame, "sin comprar no hay marco")
	-- Una compra sin saldo no vale ni descuenta.
	local ana = ns.Scores()["Ana Sol"].merits
	ns.handlers.BUY("Ana Sol", { id = "buy:x", member = "Ana Sol", t = NOW, item = "frame_gold" })
	LG:DataChanged()
	assert((ana >= 500) == ns.Owns("Ana Sol", "frame_gold"), "solo con saldo")
	ns.handlers.BUY("Malo Uno", { id = "buy:y", member = "Ana Sol", t = NOW, item = "frame_silver" })
	assert(not g.purchases["buy:y"], "nadie compra en nombre de otro")
	-- La tasa de una tribu rechazada no se cobra.
	g.tribes["t:rej"] = { id = "t:rej", name = "Rechazada", status = "rejected", members = {}, creator = me, rev = 2, by = me, t = NOW }
	assert(not ns.PurchaseCharged(g, { item = "tribeCreate", ref = "t:rej" }), "tribu rechazada, tasa devuelta")
	g.tribes["t:rej"] = nil
	g.members["Ana Sol"].profile = nil
	LG.db.char.profile = {}
	print_("OK tienda: compra, perfil, sin saldo, en nombre de otro y tasas")
end

-- Subastas de los miembros: 1 día, el 90 % para el vendedor y el 10 % al cofre; las del banco, al cofre;
-- un vendedor no puede inventarse el pago; como mucho 3 abiertas.
do
	local me = ns.PlayerFullName()
	for id, a in pairs(g.auctions) do if a.status == "open" then g.auctions[id] = nil end end
	ns.AdjustPoints("Ana Sol", 200, 0, "prueba de subastas")
	NOW = NOW + 10
	local link = "|cff0070dd|Hitem:2000::::|h[Espada de prueba]|h|r"
	assert(ns.StartAuction(link, 10, 99))
	local id
	for aid, a in pairs(g.auctions) do if a.link == link and a.status == "open" then id = aid end end
	local a = g.auctions[id]
	assert(a.ends - a.created == 86400 and not a.bank, "personal: 1 día")
	assert(not ns.PlaceBid(id, 20), "el vendedor no puja en lo suyo")
	ns.handlers.BID("Ana Sol", { auction = id, member = "Ana Sol", amount = 40, t = NOW + 5 })
	local mine, ana, chest = ns.Scores()[me].merits, ns.Scores()["Ana Sol"].merits, ns.ChestState().balance
	NOW = NOW + 86400 + 60
	ns.FinishAuction(id)
	local spend = g.spends[id]
	assert(spend and spend.seller == me and spend.v == 2, "pago con vendedor")
	assert(ns.Scores()["Ana Sol"].merits == ana - 40, "Ana paga 40")
	assert(ns.Scores()[me].merits == mine + 36, "el vendedor cobra 36")
	assert(ns.ChestState().balance >= chest + 4, "el cofre, 4")
	-- Un vendedor que no es oficial no puede inventarse el pago.
	LG.db.profile.testMode = false
	ns.handlers.SPEND("Pepe Raso", { id = "fake:1", member = "Ana Sol", merits = 99, seller = "Pepe Raso", by = "Pepe Raso", v = 2 })
	LG.db.profile.testMode = true
	assert(not g.spends["fake:1"], "pago sin puja, rechazado")
	-- Como mucho 3 abiertas.
	for i = 1, 3 do assert(ns.StartAuction(("|Hitem:%d::::|h[Cosa %d]|h"):format(3000 + i, i), 10)) end
	assert(not ns.StartAuction("|Hitem:3999::::|h[Una más]|h", 10), "la cuarta no")
	-- Del banco: con su duración y todo al cofre.
	assert(ns.StartAuction("|Hitem:4000::::|h[Del banco]|h", 10, 2, true))
	local bankID
	for aid, x in pairs(g.auctions) do if x.bank and x.status == "open" then bankID = aid end end
	assert(bankID and g.auctions[bankID].ends - g.auctions[bankID].created == 7200, "del banco: 2 horas")
	ns.handlers.BID("Ana Sol", { auction = bankID, member = "Ana Sol", amount = 30, t = NOW + 5 })
	chest = ns.ChestState().balance
	NOW = NOW + 3 * 3600
	ns.FinishAuction(bankID)
	assert(ns.ChestState().balance == chest + 30, "del banco: todo al cofre")
	assert(ns.AuctionType(2000) and ns.AUCTION_TYPES[1].key == "all", "tipos de objeto")
	for aid, x in pairs(g.auctions) do if x.status == "open" then ns.FinishAuction(aid, true) end end
	print_("OK subastas de miembros: 1 día, 90/10, pago falso, máximo 3 y banco")
end

-- Banco de la hermandad del juego: depósitos leídos de los registros, sin duplicados, reputación sin insignias y tope semanal.
do
	local me = ns.PlayerFullName()
	wipe(g.bankLog)
	local saved = { GetNumGuildBankTabs, GetNumGuildBankTransactions, GetGuildBankTransaction, GetNumGuildBankMoneyTransactions, GetGuildBankMoneyTransaction }
	GetNumGuildBankTabs = function() return 1 end
	GetNumGuildBankTransactions = function() return 3 end
	GetGuildBankTransaction = function(_, i)
		if i == 1 then return "deposit", "Ana Sol", "|cffffffff|Hitem:2589::::|h[Lino]|h|r", 20, 1, nil, 0, 0, 0, 2 end
		if i == 2 then return "withdraw", "Ana Sol", "|cffffffff|Hitem:2589::::|h[Lino]|h|r", 5, 1, nil, 0, 0, 0, 1 end
		return "deposit", "Nadie Raro", nil, 1, 1, nil, 0, 0, 0, 1
	end
	GetNumGuildBankMoneyTransactions = function() return 1 end
	GetGuildBankMoneyTransaction = function() return "deposit", "Ana Sol", 50 * 10000, 0, 0, 1, 0 end
	local rep, merits = ns.Scores()["Ana Sol"].rep, ns.Scores()["Ana Sol"].merits
	ns.ReadGuildBank()
	local n = 0
	for _ in pairs(g.bankLog) do n = n + 1 end
	assert(n == 3, "depósito de objetos, su retirada y el oro (el objeto sin enlace no): " .. n)
	assert(ns.Scores()["Ana Sol"].rep == rep + 50, "reputación: los objetos sueltos nada, 50 de oro = 50 (el tope)")
	assert(ns.Scores()["Ana Sol"].merits == merits, "nunca insignias")
	local repNow = ns.Scores()["Ana Sol"].rep
	ns.MergeBankDeposit(g, { member = "Ana Sol", kind = "money", amount = 1, hour = math.floor(NOW / 3600) - 30, by = me })
	LG:DataChanged()
	assert(ns.Scores()["Ana Sol"].rep == repNow, "un cobre no da reputación")
	assert(not ns.MoneyText(2):find("Gold", 1, true) and ns.MoneyText(123456):find("Gold", 1, true), "sin partes a cero")
	-- Otro lo lee una hora después: el mismo depósito no se repite.
	NOW = NOW + 3600
	GetGuildBankMoneyTransaction = function() return "deposit", "Ana Sol", 50 * 10000, 0, 0, 1, 1 end
	ns.ReadGuildBank()
	n = 0
	for _ in pairs(g.bankLog) do n = n + 1 end
	assert(n == 4, "sin duplicados (3 + el cobre)")
	-- Tope semanal de reputación.
	for i = 1, 10 do
		ns.MergeBankDeposit(g, { member = "Ana Sol", kind = "money", amount = 100 * 10000, hour = math.floor(NOW / 3600) - 100 - i * 2, by = me })
	end
	LG:DataChanged()
	assert(ns.Scores()["Ana Sol"].rep - rep <= 50 * 3, "tope de 50 a la semana")
	assert(ns.BankDonors()[1].name == "Ana Sol" and ns.MoneyText(123456), "donantes y dinero en texto")
	assert(not ns.MergeBankDeposit(g, { member = "Sin Addon", kind = "money", amount = 50000, hour = math.floor(NOW / 3600), by = me }), "de quien no comparte, nada")
	-- Dos depósitos iguales seguidos (1 cobre y 1 cobre): cuentan los dos, y releídos más tarde no se duplican.
	wipe(g.bankLog)
	GetNumGuildBankTransactions = function() return 0 end
	GetNumGuildBankMoneyTransactions = function() return 2 end
	GetGuildBankMoneyTransaction = function() return "deposit", "Ana Sol", 1, 0, 0, 0, 0 end
	ns.ReadGuildBank()
	local count = 0
	for _ in pairs(g.bankLog) do count = count + 1 end
	assert(count == 2, "dos depósitos iguales seguidos: " .. count)
	NOW = NOW + 3600
	GetGuildBankMoneyTransaction = function() return "deposit", "Ana Sol", 1, 0, 0, 0, 1 end
	ns.ReadGuildBank()
	ns.handlers.BANK("Ana Sol", { { member = "Ana Sol", kind = "money", amount = 1, hour = math.floor(NOW / 3600) - 1, by = "Ana Sol" } })
	count = 0
	for _ in pairs(g.bankLog) do count = count + 1 end
	assert(count == 2, "releídos una hora después, siguen siendo dos: " .. count)
	GetNumGuildBankTabs, GetNumGuildBankTransactions, GetGuildBankTransaction, GetNumGuildBankMoneyTransactions, GetGuildBankMoneyTransaction = unpack(saved)
	-- Pedidos del banco: recompensa del cofre repartida por lo neto (depósitos menos retiradas), hasta la cantidad.
	wipe(g.bankLog)
	ns.AdjustPoints(me, 200, 0, "prueba de pedidos")
	assert(ns.Donate(100))
	NOW = NOW + 10
	local chestBefore = ns.ChestState().balance
	assert(ns.CreateBankRequest("|cffffffff|Hitem:2589::::|h[Lino]|h|r", 30, 30))
	local req
	for _, r in pairs(g.bankRequests) do if r.item == 2589 and r.status == "open" then req = r end end
	assert(req and ns.BankRequestsReserved() >= 30, "pedido abierto y su recompensa apartada")
	local hour = math.floor(NOW / 3600) + 1
	local anaBefore, meBefore = ns.Scores()["Ana Sol"].merits, ns.Scores()[me].merits
	ns.MergeBankDeposit(g, { member = "Ana Sol", kind = "item", item = 2589, amount = 20, hour = hour, by = me })
	ns.MergeBankDeposit(g, { member = "Ana Sol", kind = "itemOut", item = 2589, amount = 5, hour = hour, by = me })
	ns.MergeBankDeposit(g, { member = me, kind = "item", item = 2589, amount = 20, hour = hour + 1, by = me })
	NOW = NOW + 3 * 3600
	LG:DataChanged()
	assert(ns.Scores()["Ana Sol"].merits == anaBefore + 15, "Ana: 20 menos 5 sacadas = 15 de 30 -> 15 insignias")
	assert(ns.Scores()[me].merits == meBefore + 15, "yo: los 15 que faltaban -> 15")
	local open, closed = ns.BankRequestLists()
	assert(#open == 0 and closed[1].phase == "done", "pedido completado")
	assert(ns.ChestState().balance == chestBefore - 30, "del cofre salen 30")
	-- Con un rango sin permiso (y sin la medalla de Artesano de oro), no se pide.
	LG.db.profile.testRank = 4
	assert(not ns.CanRequestBank(me) or ns.MedalTier(me, "artisan") == 3, "sin permiso no se pide")
	assert(not ns.Can("projects", me) and ns.Can("projects", "Ana Sol"), "permisos por rango")
	LG.db.profile.testRank = nil
	ns.SetGuildSetting("rankName:recruit", "Grumete")
	ns.ApplyRankNames()
	assert(ns.MERIT_RANKS[1].label == "Grumete", "rango del addon renombrado")
	ns.SetGuildSetting("rankName:recruit", nil)
	ns.ApplyRankNames()
	assert(ns.MERIT_RANKS[1].label == ns.MERIT_RANKS[1].defaultLabel, "y restablecido")
	print_("OK pedidos del banco y permisos por rango")
	print_("OK banco de la hermandad: depósitos, sin duplicados, reputación con tope y sin insignias")
end

-- Anuncios en el chat de hermandad (en modo prueba, al grupo): sin texturas y apagables.
do
	local sent = {}
	local savedSend, savedCI, savedGroup = SendChatMessage, C_ChatInfo, IsInGroup
	C_ChatInfo = nil
	SendChatMessage = function(msg, channel) sent[#sent + 1] = { msg = msg, channel = channel } end
	g.settings.guildChat = nil -- los clics de Ajustes pueden haberlo apagado
	IsInGroup = function() return true end
	ns.GuildAnnounce("Hola |TInterface/Icons/X:0|t mundo")
	assert(#sent == 1 and sent[1].msg == "[Guildmark] Hola  mundo" and (sent[1].channel == "PARTY" or sent[1].channel == "RAID"), "anuncio sin texturas, al grupo en modo prueba")
	ns.SetGuildSetting("guildChat", false)
	ns.GuildAnnounce("No debería salir")
	assert(#sent == 1, "apagado, no sale")
	ns.SetGuildSetting("guildChat", nil)
	SendChatMessage, C_ChatInfo, IsInGroup = savedSend, savedCI, savedGroup
	print_("OK anuncios en el chat de hermandad")
end

-- Mensaje de muerte con honor: todas las variantes del juego (con rango y sin él); uno desconocido se guarda.
do
	local Hunt = ns.HuntModule
	Hunt:OnEnable()
	Hunt.hasCombatLog = nil -- en Forever el registro de combate está prohibido: las bajas salen del mensaje de honor
	local before = 0
	for _ in pairs(g.kills) do before = before + 1 end
	Hunt:CHAT_MSG_COMBAT_HONOR_GAIN(nil, "Pepe Lejano muere (muerte con honor). Obtienes 31 p. de honor.")
	local found
	for _, k in pairs(g.kills) do
		if k.kind == "kill" and k.victimName and k.victimName:find("Pepe", 1, true) and k.honor == 31 then found = k end
	end
	assert(found and found.honorable, "baja con el mensaje sin rango")
	-- Con rango numérico: el honor es el número del hueco del honor, no el rango.
	Hunt:CHAT_MSG_COMBAT_HONOR_GAIN(nil, "Rangoso Tres muere (muerte con honor: 3). Obtienes 45 p. de honor.")
	-- Con bonificación (variante de Forever).
	Hunt:CHAT_MSG_COMBAT_HONOR_GAIN(nil, "Bonus Uno muere (muerte con honor). Obtienes 20 p. de honor (+10 descanso de bonificación).")
	local rangoso, bonus
	for id, k in pairs(g.kills) do
		if k.victimName == "Rangoso Tres" then rangoso = k; g.kills[id] = nil end
		if k.victimName == "Bonus Uno" then bonus = k; g.kills[id] = nil end
	end
	assert(rangoso and rangoso.honor == 45, "con rango: honor 45, no el rango")
	assert(bonus and bonus.honor == 20, "con bonificación: honor 20")
	-- Forever: «Has recibido N p. de honor.» sin víctima. Sin nadie muerto a la vista, no es una baja;
	-- con el objetivo enemigo muerto, la baja es suya.
	local savedU = { UnitExists, UnitIsPlayer, UnitIsFriend, UnitIsDeadOrGhost, UnitGUID, ns.UnitFullName }
	local count = function() local n = 0 for _ in pairs(g.kills) do n = n + 1 end return n end
	local n0 = count()
	Hunt:CHAT_MSG_COMBAT_HONOR_GAIN(nil, "Has recibido 6 p. de honor.")
	assert(count() == n0, "honor sin nadie muerto a la vista: no es una baja")
	UnitExists = function(u) return u == "target" end
	UnitIsPlayer = function() return true end
	UnitIsFriend = function() return false end
	UnitIsDeadOrGhost = function(u) return u == "target" end
	UnitGUID = function(u) return u == "target" and "Player-4613-0000AAAA" or savedU[5](u) end
	ns.UnitFullName = function(u) return u == "target" and "Gnomo Valiente" or savedU[6](u) end
	Hunt:CHAT_MSG_COMBAT_HONOR_GAIN(nil, "Has recibido 6 p. de honor.")
	UnitExists, UnitIsPlayer, UnitIsFriend, UnitIsDeadOrGhost, UnitGUID, ns.UnitFullName = savedU[1], savedU[2], savedU[3], savedU[4], savedU[5], savedU[6]
	local gnomo
	for id, k in pairs(g.kills) do if k.victimName == "Gnomo Valiente" then gnomo = k; g.kills[id] = nil end end
	assert(gnomo and gnomo.honorable and gnomo.honor == 6, "baja atribuida al objetivo enemigo muerto")
	Hunt:CHAT_MSG_COMBAT_HONOR_GAIN(nil, "Un formato que nadie conoce")
	assert(LG.db.global.diag.honorMsgs and LG.db.global.diag.honorMsgs[1].text == "Un formato que nadie conoce", "el desconocido se guarda")
	g.kills[found.id] = nil
	print_("OK mensajes de honor: con y sin rango, y los desconocidos al diagnóstico")
end

-- Tiempos: una partida completada por la estadística de jefe final (sin criatura, como en Forever) cuenta.
do
	g.runs["stat15027:test"] = { key = "stat15027:test", t = NOW, entered = NOW - 2602, instance = "Sima Ígnea", finalStat = 15027,
		criterion = 19213, members = { ns.PlayerFullName() }, guildMembers = { ns.PlayerFullName() }, guildCount = 5, size = 5,
		witnesses = { [ns.PlayerFullName()] = true } }
	local found
	for _, d in ipairs(ns.DungeonTimes()) do
		if d.dungeon == "Sima Ígnea" then
			for _, run in ipairs(d.runs) do if run.duration == 2602 then found = true end end
		end
	end
	assert(found, "tiempo de Sima Ígnea por su estadística (43:22)")
	g.runs["stat15027:test"] = nil
	print_("OK tiempos por estadística de jefe final")
end

-- Auxilio contra jugadores sin hermandad: 3 muertes en 10 minutos en la misma zona, aunque los asesinos sean distintos.
do
	LG.db.profile.aidCalls = true
	if ns.AidResetPopup then ns.AidResetPopup() end
	local shown = {}
	local savedShow = StaticPopup_Show
	StaticPopup_Show = function(which, text, _, data) shown[#shown + 1] = { which = which, text = text, data = data } end
	local me = ns.PlayerFullName()
	for i = 1, 3 do
		local rec = { id = "ng:death:" .. i, kind = "death", t = NOW - 30 + i, reporter = me, victimName = me,
			killer = "Player-9-" .. i, killerName = "Suelto " .. i, zone = "Bosque del Ocaso" }
		ns.MergeKill(g, rec)
		ns.OnKillReceived(rec)
	end
	StaticPopup_Show = savedShow
	local ask
	for _, s in ipairs(shown) do if s.which == "LANTUX_AID_ASK" then ask = s end end
	assert(ask and ask.data.enemy == ns.AID_GUILDLESS and ask.text:find(ns.AidEnemyName(ns.AID_GUILDLESS), 1, true), "auxilio contra jugadores sin hermandad")
	for i = 1, 3 do g.kills["ng:death:" .. i] = nil end
	print_("OK auxilio contra jugadores sin hermandad")
end

-- Campos de batalla: las muertes no piden auxilio ni crean objetivos; el resultado se registra y da insignias.
do
	local shown = {}
	local savedShow, savedInstance = StaticPopup_Show, IsInInstance
	StaticPopup_Show = function(which) shown[#shown + 1] = which end
	IsInInstance = function() return true, "pvp" end
	assert(ns.InBattleground(), "dentro de un campo de batalla")
	local me = ns.PlayerFullName()
	for i = 1, 4 do
		local rec = { id = "bg:death:" .. i, kind = "death", t = NOW - 60 + i, reporter = me, victimName = me, killerName = "Rival " .. i,
			guild = "Hermandad del CdB", zone = "Garganta Grito de Guerra", bg = true }
		ns.MergeKill(g, rec)
		ns.OnKillReceived(rec)
	end
	assert(#shown == 0, "en un campo de batalla no se pide auxilio")
	assert(not ns.TargetGuilds()["Hermandad del CdB"], "ni se convierte en objetivo")
	assert(not ns.HuntStats(7).killedBy["Hermandad del CdB"], "ni sale en «Nos cazan»")
	local before, winsBefore = ns.Scores()[me].merits, ns.BGRecord(me).wins
	ns.RecordBGMatch("Garganta Grito de Guerra", UnitFactionGroup("player") == "Alliance" and 1 or 0, 900, { kb = 3, hk = 12, deaths = 4 })
	assert(ns.BGRecord(me).wins == winsBefore + 1, "victoria registrada")
	assert(ns.Scores()[me].merits >= before, "la victoria suma (si no está en el tope)")
	ns.handlers.BGMATCH("Malo Uno", { id = "bgx", member = "Ana Sol", t = NOW, result = "win" })
	assert(not g.bgMatches.bgx, "nadie registra partidas de otro")
	ns.handlers.BGMATCH("Ana Sol", { id = "bgy", member = "Ana Sol", t = NOW, result = "loss", map = "Valle de Alterac", kb = 99999 })
	assert(g.bgMatches.bgy and g.bgMatches.bgy.kb == nil, "derrota de Ana, sin cifras absurdas")
	for i = 1, 4 do g.kills["bg:death:" .. i] = nil end
	IsInInstance, StaticPopup_Show = savedInstance, savedShow
	ns.InvalidateScores()
	print_("OK campos de batalla: sin auxilio ni objetivos, victorias y derrotas registradas")
end

-- Llamada de auxilio: 3 muertes por la misma hermandad en 10 min → pregunta a la víctima.
do
	LG.db.profile.aidCalls = true -- los clics de Ajustes pueden haberlo apagado
	local shown = {}
	local savedShow = StaticPopup_Show
	StaticPopup_Show = function(which, text, _, data) shown[#shown + 1] = { which = which, text = text, data = data } end
	local me = ns.PlayerFullName()
	for i = 1, 3 do
		local rec = { id = "aid:death:" .. i, kind = "death", t = NOW - 60 + i, reporter = me, victimName = me, killerName = "Cazador " .. i,
			guild = "Olympus Prueba", zone = "Crestagrana" }
		ns.MergeKill(g, rec)
		ns.OnKillReceived(rec)
	end
	assert(ns.AidRecentDeaths(g, "Olympus Prueba", "Crestagrana", NOW) == 3, "3 muertes recientes")
	assert(#shown == 1 and shown[1].which == "LANTUX_AID_ASK" and shown[1].data.enemy == "Olympus Prueba", "a la tercera, ¿pedir ayuda?")
	-- Una llamada de otra hermandad por la red: se guarda, se avisa y se puede acudir.
	ns.AidResetPopup()
	ns.netHandlers.HELP("Alguien", { id = "Otra:1", guild = "Otra Horda", enemy = "Olympus Prueba", zone = "Crestagrana",
		layer = 206, deaths = 4, by = "Alguien", t = NOW, ends = NOW + 1800 })
	assert(ns.aidCalls["Otra:1"] and shown[#shown].which == "LANTUX_AID_HELP", "llamada recibida con Acudir")
	ns.netHandlers.HELP("Alguien", { id = "Otra:2", guild = "Otra Horda", enemy = "X", zone = "Y", t = NOW, ends = NOW + 1800 })
	assert(not ns.aidCalls["Otra:2"], "una llamada por hermandad a la vez")
	ns.netHandlers.HELP("Alguien", { id = "Larga:1", guild = "Larga", enemy = "X", zone = "Y", t = NOW, ends = NOW + 99999 })
	assert(not ns.aidCalls["Larga:1"], "llamada demasiado larga ignorada")
	ns.GoToAid("Otra:1")
	assert(ns.aidGoers["Otra:1"][me], "acudir apunta al jugador")
	ns.SelectTab("hunt")
	assert(ns.ActiveAidCalls()[1].id == "Otra:1", "llamadas en curso")
	ns.aidCalls["Otra:1"], ns.aidGoers["Otra:1"] = nil, nil
	for i = 1, 3 do g.kills["aid:death:" .. i] = nil end

	-- Llegar a ayudar a otra hermandad da insignias y cuenta para los logros.
	local before = (ns.Scores()[me] or { merits = 0 }).merits
	assert(ns.MergeAidHelp(g, { id = "Otra:9", member = me, guild = "Otra Horda", kind = "help", zone = "Crestagrana", t = NOW }), "ayuda registrada")
	assert(not ns.MergeAidHelp(g, { id = "Otra:9", member = "Ana Sol", guild = "Otra Horda", t = NOW }, "Impostor"), "la ayuda la firma quien llega")
	ns.InvalidateScores()
	assert((ns.Scores()[me] or { merits = 0 }).merits == before, "acudir sin kills no da nada")
	-- 7 kills en la zona durante la llamada: cuentan 5 (tope por llamada); una fuera de la zona, no.
	for i = 1, 7 do
		g.kills["aidk" .. i] = { id = "aidk" .. i, kind = "kill", killerName = me, victimName = "Rival " .. i, zone = "Crestagrana", t = NOW + i }
	end
	g.kills.aidkOut = { id = "aidkOut", kind = "kill", killerName = me, victimName = "Lejos", zone = "Desolace", t = NOW + 9 }
	local h = g.aidHelps["Otra:9|" .. me]
	assert(#ns.AidHelpKills(g, h) == ns.AID_KILL_CAP, "tope de kills por llamada")
	ns.InvalidateScores()
	assert(ns.Scores()[me].merits > before, "cada kill en la llamada da insignias")
	for i = 1, 7 do g.kills["aidk" .. i] = nil end
	g.kills.aidkOut = nil
	-- Para los logros de abajo, una kill que cuente.
	g.kills.aidkAch = { id = "aidkAch", kind = "kill", killerName = me, victimName = "Rival", zone = "Crestagrana", t = NOW + 1 }

	-- Asalto solo de la hermandad a una capital enemiga y su líder derribado.
	local city = ns.EnemyCities()[1]
	ns.DeclareAssault(city.key, false)
	local assault
	for _, c in pairs(ns.aidCalls) do if c.kind == "assault" then assault = c end end
	assert(assault and assault.city == city.key and not assault.open and g.calls[assault.id], "asalto declarado y guardado")
	local savedGUID, savedExists, savedDead, savedPlayer = UnitGUID, UnitExists, UnitIsDead, UnitIsPlayer
	UnitGUID = function() return ("Creature-0-4621-2991-206-%d-0000451660"):format(city.npc) end
	UnitExists, UnitIsPlayer = function() return true end, function() return false end
	UnitIsDead = function() return false end
	ns.CheckLeader("target")
	assert(not next(g.regicides), "vivo: nada")
	UnitIsDead = function() return true end
	ns.CheckLeader("target")
	local fallen = select(2, next(g.regicides))
	assert(fallen and fallen.city == city.key and fallen.call == assault.id and fallen.solo, "líder derribado en un asalto solo de la hermandad")
	UnitGUID, UnitExists, UnitIsDead, UnitIsPlayer = savedGUID, savedExists, savedDead, savedPlayer
	ns.InvalidateAchievements()
	local state = ns.AchievementState()
	local function isDone(id) return state.byId[id] and state.byId[id].done end
	assert(isDone("aid1") and isDone("assault1") and isDone("regicide1") and isDone("regicideSolo"), "logros de auxilio, asalto y regicidio")
	ns.EndCall(assault.id)
	local stillActive = false
	for _, c in ipairs(ns.ActiveAidCalls()) do if c.id == assault.id then stillActive = true end end
	assert(assault.closed and not stillActive and g.calls[assault.id].rev == 2, "un oficial termina el asalto: cerrado y con su resultado")
	ns.aidCalls[assault.id], g.calls[assault.id], g.aidHelps["Otra:9|" .. me] = nil, nil, nil
	g.kills.aidkAch = nil
	wipe(g.regicides)
	StaticPopup_Show = savedShow
	print_("OK auxilio: detección, llamada por la red, una por hermandad, acudir, insignias, asalto, regicidio y logros")

	-- Facción: datos de la temporada en el anuncio, limpieza de lo que llega y clasificación.
	local stats = ns.GuildSeasonStats()
	assert(stats and stats.season and stats.kills >= 0 and type(stats.dungeons) == "table", "datos de la temporada propios")
	assert(ns.GuildAnnouncement().stats, "van en el anuncio de la red")
	local clean = ns.SanitizeSeasonStats({ season = 0, kills = "50", assaults = -3, assaultTimes = { stormwind = 900, inventada = 5 },
		dungeons = { ["Mina|cff"] = 1200 } })
	assert(clean.kills == 50 and clean.assaults == 0 and clean.assaultTimes.stormwind == 900 and not clean.assaultTimes.inventada, "datos ajenos saneados")
	ns.netHandlers.HI("Alguien Lejano", { guild = "Horda Rápida", faction = UnitFactionGroup("player"), members = 30, addon = 5,
		stats = { season = ns.PvPSeason(), kills = 999, assaultTimes = { [ns.EnemyCities()[1].key] = 600 } } })
	local guilds = ns.FactionGuilds()
	local own, fast = false, nil
	for _, e in ipairs(guilds) do
		if e.own then own = true end
		if e.guild == "Horda Rápida" then fast = e end
	end
	assert(own and fast and fast.stats.kills == 999, "clasificación con la propia y las de la red")
	ns.SelectTab("faction")
	LG.db.global.directory["Horda Rápida"] = nil
	print_("OK facción: datos de temporada, saneado, clasificación")
end

ns.RemoveTestData()
for _, k in pairs(g.kills) do assert(not k.test, "se borran los datos de ejemplo") end
print_("OK datos de ejemplo borrados")

-- Modo prueba dentro de una hermandad real: nada por el canal GUILD.
IsInGuild = function() return true end
GetGuildInfo = function() return "MURLOCS EXILIADOS", "Initiate", 4 end
local channels = {}
LG.SendCommMessage = function(_, _, _, channel) channels[#channels + 1] = channel end
assert(ns.IsTestGuild(LG:GuildName()), "en modo prueba la hermandad es ~Pruebas (con la facción)")
ns.CreateEvent({ title = "Prueba privada", kind = "social", start = NOW + 7200, comp = { tank = 0, healer = 0, dps = 0 } })
ns.SignUp(next(g.events), "yes", "dps")
for _, ch in ipairs(channels) do assert(ch ~= "GUILD", "en modo prueba no se envía nada a la hermandad") end
print_(("OK modo prueba en hermandad: %d mensajes, todos por %s"):format(#channels, channels[1] or "-"))
IsInGroup = function() return false end
channels = {}
ns.SignUp(next(g.events), "no")
assert(#channels == 0, "solo y en modo prueba no se envía nada")
print_("OK modo prueba en solitario: 0 mensajes")
LG.db.profile.testMode = false
assert(LG:GuildName() == "MURLOCS EXILIADOS", "sin modo prueba vuelve la hermandad real")
print_("OK sin modo prueba: hermandad real")

-- Sin complementos no hay botón de publicar; un complemento lo añade por la API.
assert(ns.PublishButton("hunt") == nil, "sin complemento no hay botón Publicar")
assert(GuildmarkAPI and GuildmarkAPI.BuildSummary() and GuildmarkAPI.BuildSummary().guild, "la API da el resumen de la hermandad")
local published
GuildmarkAPI.RegisterPublisher({
	button = function(section) return { label = "Publicar", onClick = function() published = section end } end,
	publish = function(section) published = section end,
})
local def = ns.PublishButton("hunt")
assert(def, "con complemento sí")
def.onClick()
assert(published == "hunt", "el botón llama al complemento")
ns.publisher = nil
print_("OK complementos: sin Discord en el addon público, publicar por la API")

-- Rangos de oficial: los decide el maestro de hermandad.
do
	local me = ns.PlayerFullName()
	local saved = { testMode = LG.db.profile.testMode, rank = ns.roster[me] }
	LG.db.profile.testMode = false
	IsInGuild = function() return true end
	local gr = LG:GuildData()
	ns.roster["Oficial Dos"] = { rankIndex = 2 }
	ns.roster[me] = { rankIndex = 0 }
	assert(not ns.CanManageEvents("Oficial Dos"), "rango 2: no es oficial por defecto")
	ns.SetGuildSetting("officerMaxRank", 2)
	assert(ns.CanManageEvents("Oficial Dos"), "el GM sube el corte: rango 2 es oficial")
	-- Un oficial que no es GM no puede cambiarlo.
	ns.roster["Oficial Uno"] = { rankIndex = 1 }
	assert(not ns.MergeSetting(gr, { key = "officerMaxRank", value = 9, by = "Oficial Uno", t = ns.Now() + 100 }, "Oficial Uno"), "solo el GM decide quién es oficial")
	ns.SetGuildSetting("officerMaxRank", 1)
	assert(not ns.CanManageEvents("Oficial Dos"), "y lo vuelve a bajar")
	ns.roster["Oficial Dos"], ns.roster["Oficial Uno"] = nil, nil
	ns.roster[me] = saved.rank
	LG.db.profile.testMode = saved.testMode
	print_("OK rangos de oficial: los decide el GM")
end

-- Resumen para publicar (lo que leerá el bot).
LG.db.profile.testMode = true
ns.FillTestData()
local ex = ns.BuildExport()
assert(ex and ns.IsTestGuild(ex.guild) and ex.test, "resumen de ~Pruebas")
assert(ex.ranking and #ex.ranking.reputation > 0, "clasificación")
assert(ex.hunt and #ex.hunt.targets > 0 and ex.hunt.targets[1].mostDangerous, "caza con el más peligroso")
assert(ex.events and ex.achievements and ex.achievements.points > 0, "eventos y desafíos")
print_(("OK resumen: %d en clasificación, %d objetivos (más peligroso de <%s>: %s), %d/%d puntos de desafío"):format(
	#ex.ranking.reputation, #ex.hunt.targets, ex.hunt.targets[1].guild, ex.hunt.targets[1].mostDangerous,
	ex.achievements.points, ex.achievements.total))

-- Resumen en JSON (para probar la publicación en Discord con datos de ejemplo).
local function json(v)
	local t = type(v)
	if t == "nil" then return "null" end
	if t == "boolean" or t == "number" then return tostring(v) end
	if t == "string" then
		local escaped = v:gsub('[%c"\\]', function(c)
			if c == '"' then return '\\"' end
			if c == "\\" then return "\\\\" end
			return ("\\u%04x"):format(c:byte())
		end)
		return '"' .. escaped .. '"'
	end
	local isArray = #v > 0 or next(v) == nil
	local parts = {}
	if isArray then
		for _, x in ipairs(v) do parts[#parts + 1] = json(x) end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	for k, x in pairs(v) do parts[#parts + 1] = json(tostring(k)) .. ":" .. json(x) end
	return "{" .. table.concat(parts, ",") .. "}"
end
print_("EXPORT_JSON:" .. json(ex))
