-- Profesiones: nivel de cada profesión y recetas conocidas de cada miembro,
-- para el buscador "¿quién puede fabricarlo?".
--
-- Comprobado en la beta de Forever (1.60.1): usa la API moderna (GetProfessions,
-- GetProfessionInfo, C_TradeSkillUI). La de Classic (GetSkillLineInfo,
-- GetTradeSkillInfo) no existe.
--
-- Las recetas se guardan por ID (es el ID del hechizo), no por nombre, para que
-- cada jugador las vea en el idioma de su cliente con C_Spell.GetSpellName.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Professions = LG:NewModule("Professions", "AceEvent-3.0", "AceTimer-3.0")

local SCAN_DELAY = 1

function Professions:OnEnable()
	ns.RegisterEvent(self, "SKILL_LINES_CHANGED", "UpdateProfessions")
	ns.RegisterEvent(self, "TRADE_SKILL_LIST_UPDATE", "QueueScan")
	ns.RegisterEvent(self, "TRADE_SKILL_SHOW", "QueueScan")
	ns.RegisterEvent(self, "NEW_RECIPE_LEARNED", "QueueScan")
	self:UpdateProfessions()
end

-- Profesiones aprendidas y su nivel, sin abrir ninguna ventana.
function Professions:UpdateProfessions()
	if not GetProfessions then return end
	local list = {}
	for _, index in pairs({ GetProfessions() }) do
		local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
		if skillLine then
			list[skillLine] = { name = name, rank = rank, max = maxRank, icon = icon }
		end
	end
	local old = LG.db.char.professions
	local changed = false
	for id, p in pairs(list) do
		local o = old[id]
		if not o or o.rank ~= p.rank or o.max ~= p.max or o.icon ~= p.icon then changed = true end
	end
	for id in pairs(old) do
		if not list[id] then changed = true end
	end
	if changed then
		LG.db.char.professions = list
		LG:MarkDirty()
	end
end

function Professions:QueueScan()
	if self.scanTimer then self:CancelTimer(self.scanTimer) end
	self.scanTimer = self:ScheduleTimer("ScanRecipes", SCAN_DELAY)
end

-- Solo cuenta la ventana de una profesión propia: no la de otro jugador
-- enlazada en el chat, ni la de la hermandad, ni la de un PNJ.
local function isOwnTradeSkill(api)
	if not api.IsTradeSkillReady or not api.IsTradeSkillReady() then return false end
	if api.IsTradeSkillLinked and api.IsTradeSkillLinked() then return false end
	if api.IsTradeSkillGuild and api.IsTradeSkillGuild() then return false end
	if api.IsNPCCrafting and api.IsNPCCrafting() then return false end
	return true
end

function Professions:ScanRecipes()
	self.scanTimer = nil
	local api = C_TradeSkillUI
	if not api or not isOwnTradeSkill(api) then return end
	local base = api.GetBaseProfessionInfo and api.GetBaseProfessionInfo()
	if not base or not base.professionID then return end

	-- Categorías de la ventana de la profesión (Armas, Fundición...) en su orden.
	local catNames, catOrder = {}, {}
	if api.GetCategories and api.GetCategoryInfo then
		local okList, list = pcall(function() return { api.GetCategories() } end)
		for i, catID in ipairs(okList and list or {}) do
			local okInfo, info = pcall(api.GetCategoryInfo, catID)
			if okInfo and type(info) == "table" and info.name then catNames[catID], catOrder[catID] = info.name, i end
		end
	end

	local ids, out, cat = {}, {}, {}
	for _, recipeID in ipairs(api.GetAllRecipeIDs() or {}) do
		local info = api.GetRecipeInfo(recipeID)
		if info and info.learned then
			ids[#ids + 1] = recipeID
			if info.categoryID then
				cat[recipeID] = info.categoryID
				-- Una subcategoría que no salió en la lista: su nombre igualmente.
				if not catNames[info.categoryID] and api.GetCategoryInfo then
					local okInfo, ci = pcall(api.GetCategoryInfo, info.categoryID)
					if okInfo and type(ci) == "table" and ci.name then catNames[info.categoryID] = ci.name end
				end
			end
			-- Objeto que produce la receta: sirve para reconocer la entrega de un encargo.
			local ok, output = pcall(api.GetRecipeOutputItemData, recipeID)
			if ok and type(output) == "table" and output.itemID then out[recipeID] = output.itemID end
		end
	end
	table.sort(ids)

	local recipes = LG.db.char.recipes
	local old = recipes[base.professionID]
	local same = old and old.out and old.cat and #old.ids == #ids
	if same then
		for i = 1, #ids do
			if old.ids[i] ~= ids[i] then same = false break end
		end
	end
	if same then return end

	recipes[base.professionID] = { name = base.professionName, ids = ids, out = out, cat = cat, catNames = catNames, catOrder = catOrder, t = ns.Now() }
	LG:Debug("recetas de", base.professionName, #ids)
	self:UpdateProfessions()
	LG:MarkDirty()
end

table.insert(ns.recordProviders, function(rec)
	rec.prof = LG.db.char.professions
	local recipes = {}
	for id, r in pairs(LG.db.char.recipes) do
		recipes[id] = { name = r.name, ids = r.ids, out = r.out, cat = r.cat, catNames = r.catNames, catOrder = r.catOrder }
	end
	rec.recipes = recipes
end)

-- Icono de una profesión: el que mandó el miembro o, en registros antiguos,
-- el habitual de esa línea de habilidad.
local PROFESSION_ICONS = {
	[164] = "Interface\\Icons\\Trade_BlackSmithing",      -- Herrería
	[165] = "Interface\\Icons\\INV_Misc_ArmorKit_17",     -- Peletería
	[171] = "Interface\\Icons\\Trade_Alchemy",            -- Alquimia
	[182] = "Interface\\Icons\\Spell_Nature_NatureTouchGrow", -- Herboristería
	[185] = "Interface\\Icons\\INV_Misc_Food_15",         -- Cocina
	[186] = "Interface\\Icons\\Trade_Mining",             -- Minería
	[197] = "Interface\\Icons\\Trade_Tailoring",          -- Sastrería
	[202] = "Interface\\Icons\\Trade_Engineering",        -- Ingeniería
	[333] = "Interface\\Icons\\Trade_Engraving",          -- Encantamiento
	[356] = "Interface\\Icons\\Trade_Fishing",            -- Pesca
	[393] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",    -- Desuello
	[129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", -- Primeros auxilios
}

-- Nombre de una profesión por su línea de habilidad (el del juego si lo da).
local PROFESSION_NAMES = {
	[164] = L["Herrería"], [165] = L["Peletería"], [171] = L["Alquimia"], [182] = L["Herboristería"],
	[185] = L["Cocina"], [186] = L["Minería"], [197] = L["Sastrería"], [202] = L["Ingeniería"],
	[333] = L["Encantamiento"], [356] = L["Pesca"], [393] = L["Desuello"], [129] = L["Primeros auxilios"],
}
function ns.ProfessionName(skillLine)
	local api = C_TradeSkillUI
	local ok, name = pcall(function() return api and api.GetTradeSkillDisplayName and api.GetTradeSkillDisplayName(skillLine) end)
	return (ok and name) or PROFESSION_NAMES[skillLine] or tostring(skillLine)
end

function ns.ProfessionIcon(skillLine, p)
	return (p and p.icon) or PROFESSION_ICONS[skillLine] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- { { skillLine, name, icon, players (directorio del juego), addon, best, bestName }, ... }
function ns.GuildProfessions()
	local g = LG:GuildData()
	local byLine = {}
	local function entry(skillLine)
		byLine[skillLine] = byLine[skillLine] or { skillLine = skillLine, addon = 0, best = 0 }
		return byLine[skillLine]
	end
	-- Fichas del addon: quién la tiene y el nivel más alto.
	for name, m in pairs(g and g.members or {}) do
		for skillLine, p in pairs(m.prof or {}) do
			local e = entry(tonumber(skillLine) or skillLine)
			e.addon = e.addon + 1
			e.name, e.icon = e.name or p.name, e.icon or p.icon
			if (p.rank or 0) > e.best then e.best, e.bestName = p.rank or 0, name end
		end
	end
	-- Directorio de profesiones del juego (solo en la hermandad real).
	if not LG:InTestMode() and GetNumGuildTradeSkill and GetGuildTradeSkillInfo then
		local ok, n = pcall(GetNumGuildTradeSkill)
		for i = 1, (ok and n or 0) do
			local okInfo, skillID, _, icon, headerName, _, _, numPlayers = pcall(GetGuildTradeSkillInfo, i)
			if okInfo and type(skillID) == "number" and PROFESSION_ICONS[skillID] and (numPlayers or 0) > 0 then
				local e = entry(skillID)
				e.players, e.name, e.icon = numPlayers, headerName or e.name, icon or e.icon
			end
		end
	end
	local list = {}
	for skillLine, e in pairs(byLine) do
		if type(skillLine) == "number" then
			e.name = e.name or ns.ProfessionName(skillLine)
			e.icon = e.icon or ns.ProfessionIcon(skillLine)
			list[#list + 1] = e
		end
	end
	table.sort(list, function(a, b) return (a.players or a.addon) > (b.players or b.addon) end)
	return list
end

---------------------------------------------------------------------------
-- Buscador
---------------------------------------------------------------------------

local spellNames = {}
function ns.RecipeName(id)
	local name = spellNames[id]
	if name == nil then
		name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
			or (GetSpellInfo and GetSpellInfo(id)) or false
		spellNames[id] = name
	end
	return name or nil
end

-- Recetas cuyo nombre contiene el texto buscado, con quién puede fabricarlas.
-- Devuelve una lista { name = receta, profession = profesión, crafters = { nombres } }.
function ns.FindCrafters(query, max)
	local g = LG:GuildData()
	if not g or not query or query == "" then return {} end
	query = query:lower()
	local byRecipe = {}
	for memberName, m in pairs(g.members) do
		for _, r in pairs(m.recipes or {}) do
			for _, id in ipairs(r.ids or {}) do
				local name = ns.RecipeName(id)
				if name and name:lower():find(query, 1, true) then
					local entry = byRecipe[id]
					if not entry then
						entry = { name = name, profession = r.name, crafters = {} }
						byRecipe[id] = entry
					end
					entry.crafters[#entry.crafters + 1] = memberName
				end
			end
		end
	end
	local list = {}
	for _, entry in pairs(byRecipe) do
		table.sort(entry.crafters)
		list[#list + 1] = entry
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	for i = #list, (max or 40) + 1, -1 do list[i] = nil end
	return list
end
