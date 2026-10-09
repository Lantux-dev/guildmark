-- Recolección y fabricación: cuántas menas, hierbas y pieles recoges y cuántas
-- cosas fabricas. Para las clasificaciones de recolectores y artesanos y para
-- los desafíos de hermandad.
--
-- Sin registro de combate (prohibido en Forever):
--   · Recolectar: al lanzar Minería, Herboristería o Desuello se abre una
--     ventana de unos segundos; el botín que entra en ella (mensaje "Recibes
--     botín: ...") cuenta como recolectado. El botín de monstruos no cuenta.
--   · Fabricar: cada hechizo lanzado que sea una de tus recetas cuenta como una
--     fabricación, y el mensaje "Creas: ..." da los objetos creados.
-- Las cuentas son del propio jugador y se comparten en su ficha.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Gathering = LG:NewModule("Gathering", "AceEvent-3.0")

local GATHER_WINDOW = 6 -- segundos tras el hechizo de recolección en los que el botín cuenta

-- Profesiones de recolección: línea de habilidad y hechizos conocidos de Classic.
-- En Forever los ID pueden cambiar, así que también se reconoce el hechizo por
-- su nombre (el de la profesión o el de recolectar).
local GATHER_KINDS = {
	{ key = "mining", skillLine = 186, spells = { 2575, 2576, 3564, 10248 } },
	{ key = "herb", skillLine = 182, spells = { 2366, 2368, 3570, 11993 } },
	{ key = "skinning", skillLine = 393, spells = { 8613, 8617, 8618, 10768 } },
}
local SPELL_KIND = {}
for _, k in ipairs(GATHER_KINDS) do
	for _, id in ipairs(k.spells) do SPELL_KIND[id] = k.key end
end

local gathering -- { kind, untilT } mientras dura la ventana de recolección

---------------------------------------------------------------------------
-- Mensajes de botín: patrones a partir de las cadenas del propio juego
---------------------------------------------------------------------------

local function buildPattern(fmt)
	if not fmt then return nil end
	local p = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
	p = p:gsub("%%%d%%%$s", "\1"):gsub("%%%d%%%$d", "\2"):gsub("%%s", "\1"):gsub("%%d", "\2")
	p = p:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
	return "^" .. p .. "$"
end

-- Las de "varios" van primero: el patrón simple también casaría con "objeto x5".
local patterns
local function lootPatterns()
	if patterns then return patterns end
	patterns = {}
	local function add(globalName, kind, multiple)
		local p = buildPattern(_G[globalName])
		if p then patterns[#patterns + 1] = { pattern = p, kind = kind, multiple = multiple } end
	end
	add("LOOT_ITEM_CREATED_SELF_MULTIPLE", "created", true)
	add("LOOT_ITEM_CREATED_SELF", "created", false)
	add("LOOT_ITEM_SELF_MULTIPLE", "looted", true)
	add("LOOT_ITEM_PUSHED_SELF_MULTIPLE", "looted", true)
	add("LOOT_ITEM_SELF", "looted", false)
	add("LOOT_ITEM_PUSHED_SELF", "looted", false)
	return patterns
end

-- "Recibes botín: [Mena de cobre]x2." -> "looted", itemID, 2
function ns.ParseLootMessage(text)
	for _, p in ipairs(lootPatterns()) do
		local a, b = text:match(p.pattern)
		if a then
			local itemID = tonumber(a:match("item:(%d+)"))
			if itemID then return p.kind, itemID, p.multiple and tonumber(b) or 1 end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Cuentas propias
---------------------------------------------------------------------------

local function stats()
	local s = LG.db.char.stats
	local week = ns.WeekStart and ns.WeekStart() or 0
	if s.week ~= week then
		s.week = week
		s.weekGathered = { mining = 0, herb = 0, skinning = 0 }
		s.weekCrafted = 0
	end
	local day = math.floor(ns.Now() / 86400)
	if s.day ~= day then
		s.day = day
		s.dayItems = {}
	end
	return s
end

local function addGathered(kind, itemID, qty)
	local s = stats()
	s.gathered[kind] = (s.gathered[kind] or 0) + qty
	s.weekGathered[kind] = (s.weekGathered[kind] or 0) + qty
	s.dayItems[itemID] = (s.dayItems[itemID] or 0) + qty
	if s.dayItems[itemID] > (s.bestDay or 0) then s.bestDay = s.dayItems[itemID] end
	LG:MarkDirty()
end

local function addCrafted(qty)
	local s = stats()
	s.crafted = (s.crafted or 0) + qty
	s.weekCrafted = (s.weekCrafted or 0) + qty
	LG:MarkDirty()
end

-- ¿Es este hechizo uno de recolectar? Por ID conocido o por nombre.
local function gatherKind(spellID)
	if SPELL_KIND[spellID] then return SPELL_KIND[spellID] end
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	if not name then return nil end
	for _, k in ipairs(GATHER_KINDS) do
		local profession = ns.ProfessionName and ns.ProfessionName(k.skillLine)
		if profession and name == profession then return k.key end
	end
	return nil
end

local function isMyRecipe(spellID)
	for _, r in pairs(LG.db.char.recipes or {}) do
		for _, id in ipairs(r.ids or {}) do
			if id == spellID then return true end
		end
	end
	return false
end

-- Se exponen para la prueba de humo.
function ns.HandleSpellcast(spellID)
	local kind = gatherKind(spellID)
	-- Diagnóstico: los últimos hechizos lanzados (también los de recolectar), para los ID de Forever.
	if LG.db.profile.debug then
		local log = LG.db.global.castDebug
		table.insert(log, ("%d %s%s"):format(spellID, tostring(C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)),
			kind and (" [" .. kind .. "]") or (isMyRecipe(spellID) and " [receta]" or "")))
		while #log > 20 do table.remove(log, 1) end
	end
	if kind then
		gathering = { kind = kind, untilT = GetTime() + GATHER_WINDOW }
		LG:Debug("recolección:", kind, spellID)
		return
	end
	if isMyRecipe(spellID) then
		local s = stats()
		s.crafts = (s.crafts or 0) + 1
		LG:Debug("fabricación:", spellID)
	end
end

function ns.HandleLootMessage(text)
	if not LG:HasConsent() then return end
	local kind, itemID, qty = ns.ParseLootMessage(text)
	if kind == "created" then
		addCrafted(qty)
	elseif kind == "looted" and gathering and GetTime() <= gathering.untilT then
		addGathered(gathering.kind, itemID, qty)
	end
end

function Gathering:OnEnable()
	ns.RegisterEvent(self, "UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
		if unit == "player" and spellID then ns.HandleSpellcast(spellID) end
	end)
	ns.RegisterEvent(self, "CHAT_MSG_LOOT", function(_, text) ns.HandleLootMessage(text or "") end)
end

-- En la ficha compartida: totales, los de esta semana y el mejor día con un mismo objeto.
table.insert(ns.recordProviders, function(rec)
	local s = stats()
	rec.stats = {
		gathered = s.gathered,
		crafted = s.crafted or 0,
		crafts = s.crafts or 0,
		week = s.week,
		weekGathered = s.weekGathered,
		weekCrafted = s.weekCrafted or 0,
		bestDay = s.bestDay or 0,
	}
end)

-- Cuentas de la semana actual de un miembro (0 si su ficha es de otra semana).
function ns.MemberWeekStats(m)
	local s = m and m.stats
	local week = ns.WeekStart and ns.WeekStart() or 0
	if not s or s.week ~= week then return { mining = 0, herb = 0, skinning = 0 }, 0 end
	return s.weekGathered or {}, s.weekCrafted or 0
end
