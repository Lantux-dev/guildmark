-- Desafíos de hermandad: logros de toda la guild, al estilo de los desafíos de
-- legado de Forever (que son logros personales; de hermandad no hay ninguno).
--
-- El progreso se calcula con los datos ya sincronizados, igual que las insignias.
-- Cuando un desafío se completa por primera vez se guarda la fecha y se comparte
-- (ACH); si llega de varios addons, vale la más antigua.
--
-- Cada desafío da 1 punto de hermandad; con los puntos se desbloquean recompensas
-- del addon (títulos de hermandad y la marca de agua dorada).
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Achievements = LG:NewModule("Achievements", "AceEvent-3.0", "AceTimer-3.0")

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
-- Profesiones principales (líneas de habilidad).
local PRIMARY_PROFESSIONS = { 164, 165, 171, 182, 186, 197, 202, 333, 393 }
local TOAST_WINDOW = 600 -- solo se anuncian los completados en los últimos 10 minutos

ns.ACH_CATEGORIES = {
	{ key = "general", label = L["General"], icon = "Interface\\Icons\\Spell_Holy_PrayerofFortitude" },
	-- JcE: los genéricos ("X mazmorras con la hermandad") en la propia categoría
	-- (own) y los de cada mazmorra y banda en sus subcategorías.
	{ key = "pve", label = L["JcE"], icon = "Interface\\Icons\\INV_Misc_Key_03", own = true, sub = {
		{ key = "dungeons", label = L["Mazmorras"], empty = L["Próximamente: un logro por cada mazmorra de Forever."] },
		{ key = "raids", label = L["Bandas"], empty = L["Próximamente: los jefes de cada banda de Forever."] },
	} },
	-- Categoría con subcategorías: los desafíos usan la clave de la subcategoría.
	{ key = "jcj", label = L["JcJ"], icon = "Interface\\Icons\\Ability_DualWield", sub = {
		{ key = "pvp", label = L["Caza"] },
		{ key = "aid", label = L["Auxilio"] },
		{ key = "assault", label = L["Asaltos"] },
		{ key = "bg", label = L["Campos de batalla"] },
		{ key = "wars", label = L["Guerras"] },
	} },
	{ key = "professions", label = L["Profesiones"], icon = "Interface\\Icons\\Trade_BlackSmithing" },
	{ key = "community", label = L["Comunidad"], icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02" },
	-- Proezas de fuerza: lo logrado en temporadas pasadas; permanentes y sin puntos.
	{ key = "feats", label = L["Proezas de fuerza"], icon = "Interface\\Icons\\INV_Misc_Trophy_03", feats = true },
}

-- Nivel de hermandad: uno cada 10 puntos (del 1 al 10). Cada nivel desbloquea una
-- recompensa; todas son de prestigio (el addon no puede dar objetos ni oro) y las
-- que tocan algo de la hermandad son pequeñas. perk = clave que se consulta con ns.GuildPerks().
ns.ACH_REWARDS = {
	{ points = 10, title = L["Hermandad prometedora"], label = L["Título: Hermandad prometedora"], icon = "Interface\\Icons\\INV_Misc_Note_01" },
	{ points = 20, perk = "goldToast", label = L["Aviso de logro dorado"], icon = "Interface\\Icons\\INV_Misc_Bell_01" },
	{ points = 30, perk = "goldRing", label = L["Borde dorado en las insignias del marco"], icon = "Interface\\Icons\\INV_Jewelry_Ring_03" },
	{ points = 40, title = L["Hermandad curtida"], perk = "watermark", label = L["Título: Hermandad curtida y emblema dorado"], icon = "Interface\\Icons\\INV_BannerPVP_02" },
	{ points = 50, perk = "elite", label = L["Insignia: Hermandad de élite"], icon = "Interface\\Icons\\Ability_Warrior_RallyingCry" },
	{ points = 60, title = L["Hermandad veterana"], perk = "tribe12", label = L["Título: Hermandad veterana y tribus de 12"], icon = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude" },
	{ points = 70, perk = "star", label = L["Estrella en el directorio y la clasificación"], icon = "Interface\\Icons\\Spell_Holy_ChampionsBond" },
	{ points = 80, perk = "tribeIcons", label = L["Iconos de tribu exclusivos (próximamente)"], icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_04" },
	{ points = 90, title = L["Hermandad legendaria"], perk = "goldFrame", label = L["Título: Hermandad legendaria y marco dorado"], icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
}

function ns.GuildLevel(points)
	return math.max(1, math.min(#ns.ACH_REWARDS + 1, math.floor((points or 0) / 10) + 1))
end

-- Recompensas desbloqueadas: { level, title, [perk] = true }.
function ns.GuildPerks()
	local points = ns.AchievementState().points
	local perks = { level = ns.GuildLevel(points) }
	for _, r in ipairs(ns.ACH_REWARDS) do
		if points >= r.points then
			if r.title then perks.title = r.title end
			if r.perk then perks[r.perk] = true end
		end
	end
	return perks
end

---------------------------------------------------------------------------
-- Hechos de la hermandad (lo que miden los desafíos)
---------------------------------------------------------------------------

local function sortedTimes(list)
	table.sort(list)
	return list
end

-- Momento en que un contador llegó a "target": la marca de tiempo del hecho n.º target.
local function reachedAt(times, target)
	return times[target]
end

local function gatherFacts(g)
	local f = {
		kills = {}, revenges = {}, nemesis = {}, dungeonDays = {}, dungeonsSeen = {},
		raidBosses = {}, orders = {}, events = {}, auctions = {},
	}
	-- PvP
	for _, k in pairs(g.kills) do
		if k.kind == "kill" and k.honorable and not ns.IsVoided(g, k.id) then
			f.kills[#f.kills + 1] = k.t
			if k.revenge then f.revenges[#f.revenges + 1] = k.t end
			if k.guild and not k.bg then
				f.nemesis[k.guild] = f.nemesis[k.guild] or {}
				table.insert(f.nemesis[k.guild], k.t)
			end
		end
	end
	-- Mazmorras (como en los puntos: 5 jugadores, 4+ de la hermandad, 2+ testigos) y bandas.
	local seenDay, firstBoss = {}, {}
	for _, r in pairs(g.runs) do
		local witnesses = 0
		for _ in pairs(r.witnesses or {}) do witnesses = witnesses + 1 end
		if witnesses >= 2 then
			if r.raid then
				-- Banda de hermandad: al menos el 80 % del grupo es de la guild.
				if r.size >= 10 and r.guildCount >= r.size * 0.8 then
					local key = tostring(r.encounterID or r.boss)
					if not firstBoss[key] or r.t < firstBoss[key].t then firstBoss[key] = { t = r.t, name = r.boss } end
				end
			elseif r.size == 5 and r.guildCount >= 4 then
				local dayKey = ("%s|%d"):format(tostring(r.instanceID or r.instance), math.floor(r.t / 86400))
				if not seenDay[dayKey] or r.t < seenDay[dayKey] then seenDay[dayKey] = r.t end
				local name = r.instance or "?"
				if not f.dungeonsSeen[name] or r.t < f.dungeonsSeen[name] then f.dungeonsSeen[name] = r.t end
			end
		end
	end
	for _, t in pairs(seenDay) do f.dungeonDays[#f.dungeonDays + 1] = t end
	for _, b in pairs(firstBoss) do f.raidBosses[#f.raidBosses + 1] = b.t end
	-- Artesanía, eventos y mercado
	for _, o in pairs(g.orders) do
		if o.status == "done" and not ns.IsVoided(g, o.id) then f.orders[#f.orders + 1] = o.updated or o.t end
	end
	for id, list in pairs(g.attendance) do
		local e = g.events[id]
		local n = 0
		for member in pairs(list) do
			if not ns.IsVoided(g, ns.AttendanceVoidID(id, member)) then n = n + 1 end
		end
		if e and e.status ~= "cancelled" and n >= 5 then f.events[#f.events + 1] = e.start end
	end
	for _, s in pairs(g.spends) do f.auctions[#f.auctions + 1] = s.t end

	for _, key in ipairs({ "kills", "revenges", "dungeonDays", "raidBosses", "orders", "events", "auctions" }) do
		sortedTimes(f[key])
	end
	for guild, list in pairs(f.nemesis) do sortedTimes(list) end

	-- Instantáneas: miembros con el addon, honor sumado, profesiones, clases por nivel.
	f.addonMembers, f.hkSum, f.skillSum = 0, 0, 0
	f.mining, f.herb, f.skinning, f.crafted, f.bestDay, f.bestWeekCrafted = 0, 0, 0, 0, 0, 0
	f.professions = {}
	for _, m in pairs(g.members) do
		f.addonMembers = f.addonMembers + 1
		f.hkSum = f.hkSum + (m.pvp and m.pvp.hk or 0)
		local s = m.stats
		if s then
			f.mining = f.mining + (s.gathered and s.gathered.mining or 0)
			f.herb = f.herb + (s.gathered and s.gathered.herb or 0)
			f.skinning = f.skinning + (s.gathered and s.gathered.skinning or 0)
			f.crafted = f.crafted + (s.crafted or 0)
			f.bestDay = math.max(f.bestDay, s.bestDay or 0)
			local _, weekCrafted = ns.MemberWeekStats(m)
			f.bestWeekCrafted = math.max(f.bestWeekCrafted, weekCrafted)
		end
		for skillLine, p in pairs(m.prof or {}) do
			f.skillSum = f.skillSum + (p.rank or 0)
			f.professions[skillLine] = true
		end
	end
	-- Profesiones que el directorio de Blizzard sabe que hay en la hermandad (aunque no tengan el addon).
	if not LG:InTestMode() and GetNumGuildTradeSkill and GetGuildTradeSkillInfo then
		for i = 1, GetNumGuildTradeSkill() or 0 do
			local ok, skillID, _, _, _, _, _, numPlayers = pcall(GetGuildTradeSkillInfo, i)
			if ok and skillID and (numPlayers or 0) > 0 then f.professions[skillID] = true end
		end
	end
	-- Mejor nivel por clase: roster del juego (toda la hermandad) y fichas del addon.
	f.classLevel = {}
	local function seeClass(class, level)
		if class and level and level > (f.classLevel[class] or 0) then f.classLevel[class] = level end
	end
	for _, r in pairs(ns.roster) do seeClass(r.class, r.level) end
	for _, m in pairs(g.members) do seeClass(m.class, m.level) end

	-- Auxilio y asaltos (Aid.lua).
	f.helps, f.defended, f.assaults, f.regicides, f.soloRegicides = {}, {}, {}, {}, {}
	local myGuild = LG:GuildName()
	local helped = {}
	for _, h in pairs(g.aidHelps or {}) do
		local kills = h.guild ~= myGuild and ns.AidHelpKills and ns.AidHelpKills(g, h) or {}
		if kills[1] and (not helped[h.id] or kills[1].t < helped[h.id]) then helped[h.id] = kills[1].t end
	end
	for _, t in pairs(helped) do f.helps[#f.helps + 1] = t end
	for _, c in pairs(g.calls or {}) do
		if c.kind == "assault" then
			if ns.AssaultCompleted and ns.AssaultCompleted(g, c) then f.assaults[#f.assaults + 1] = c.t end
		elseif (c.external or 0) >= 1 then f.defended[#f.defended + 1] = c.ends or c.t end
	end
	local cities = {}
	for _, r in pairs(g.regicides or {}) do
		f.regicides[#f.regicides + 1] = r.t
		if r.solo then f.soloRegicides[#f.soloRegicides + 1] = r.t end
		cities[r.city] = true
	end
	f.regicideCities = 0
	for _ in pairs(cities) do f.regicideCities = f.regicideCities + 1 end
	-- Asaltos relámpago: el líder cae menos de 30 minutos después de declarar el asalto.
	f.fastAssaults = {}
	for _, r in pairs(g.regicides or {}) do
		local c = r.call and g.calls and g.calls[r.call]
		if c and c.kind == "assault" and r.t - c.t <= 1800 then f.fastAssaults[#f.fastAssaults + 1] = r.t end
	end
	for _, key in ipairs({ "helps", "defended", "assaults", "regicides", "soloRegicides", "fastAssaults" }) do sortedTimes(f[key]) end

	-- Niveles: personajes de la hermandad (roster del juego y fichas del addon) por encima de un nivel.
	local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
	local levels = {}
	for name, r in pairs(ns.roster) do levels[name] = r.level or 0 end
	for name, m in pairs(g.members) do levels[name] = math.max(levels[name] or 0, tonumber(m.level) or 0) end
	f.level30, f.levelMax = 0, 0
	for _, level in pairs(levels) do
		if level >= 30 then f.level30 = f.level30 + 1 end
		if level >= maxLevel then f.levelMax = f.levelMax + 1 end
	end

	-- Campos de batalla (PvP.lua): victorias, golpes de gracia y victorias de escuadrón
	-- (5 miembros registran la misma victoria: mismo mapa y a menos de 3 minutos).
	f.bgWins, f.bgSquads, f.bgKB = {}, {}, 0
	local wins = {}
	for id, m in pairs(g.bgMatches or {}) do
		if not ns.IsVoided(g, id) then
			f.bgKB = f.bgKB + (m.kb or 0)
			if m.result == "win" then
				f.bgWins[#f.bgWins + 1] = m.t
				wins[#wins + 1] = m
			end
		end
	end
	table.sort(wins, function(a, b) return a.t < b.t end)
	local used = {}
	for i, w in ipairs(wins) do
		if not used[i] then
			local members, group = { [w.member] = true }, { i }
			for j = i + 1, #wins do
				local o = wins[j]
				if o.t - w.t > 180 then break end
				if not used[j] and o.map == w.map and not members[o.member] then
					members[o.member] = true
					group[#group + 1] = j
				end
			end
			if #group >= 5 then
				for _, j in ipairs(group) do used[j] = true end
				f.bgSquads[#f.bgSquads + 1] = wins[group[5]].t
			end
		end
	end

	-- Cofre (Chest.lua): proyectos activados, tipos distintos y lo donado entre todos.
	f.projects, f.projectKinds = {}, {}
	for _, p in pairs(g.projects or {}) do
		if p.activatedAt and ns.ProjectKind and ns.ProjectKind(p.kind) then
			f.projects[#f.projects + 1] = p.activatedAt
			if not f.projectKinds[p.kind] or p.activatedAt < f.projectKinds[p.kind] then f.projectKinds[p.kind] = p.activatedAt end
		end
	end
	f.chestDonated = ns.ChestState and ns.ChestState().donated or 0

	-- Cabezas con precio (Bounty.lua): cobradas y miembros con botín de guerra ahora.
	f.bountyClaims, f.wagerMembers = {}, 0
	for _, pot in ipairs(ns.BountyPots and ns.BountyPots() or {}) do
		if pot.claimedAt then f.bountyClaims[#f.bountyClaims + 1] = pot.claimedAt end
	end
	sortedTimes(f.bountyClaims)
	if ns.InWager then
		for name in pairs(g.members) do
			if ns.InWager(name, ns.Now()) then f.wagerMembers = f.wagerMembers + 1 end
		end
	end

	-- Banco de la hermandad del juego (GuildBank.lua): oro y objetos depositados entre todos.
	f.bankGold, f.bankItems = 0, 0
	for _, d in ipairs(ns.BankDonors and ns.BankDonors() or {}) do
		f.bankGold = f.bankGold + math.floor(d.gold / 10000)
	end
	f.bankRequests = {}
	for _, st in pairs(ns.BankRequestAllocations and ns.BankRequestAllocations(g).byReq or {}) do
		if st.doneAt then f.bankRequests[#f.bankRequests + 1] = st.doneAt end
	end
	sortedTimes(f.bankRequests)
	f.bankItems = 0 -- depósitos de objetos (no unidades)
	for _, d in pairs(g.bankLog or {}) do
		if d.kind == "item" then f.bankItems = f.bankItems + 1 end
	end

	-- Tienda (Shop.lua): cosméticos comprados y el coleccionista que lo tiene todo.
	f.purchases, f.bestCollection, f.cosmetics = {}, 0, 0
	for _, item in ipairs(ns.SHOP_ITEMS or {}) do
		if item.kind ~= "fee" then f.cosmetics = f.cosmetics + 1 end
	end
	local collections = {}
	for key, t in pairs(ns.ShopOwned and ns.ShopOwned() or {}) do
		f.purchases[#f.purchases + 1] = t
		local name = key:match("^(.*)|")
		collections[name] = (collections[name] or 0) + 1
	end
	for _, n in pairs(collections) do f.bestCollection = math.max(f.bestCollection, n) end
	sortedTimes(f.purchases)

	-- Medallas del perfil (Profile.lua): oros entre todos y el estuche más lleno.
	f.goldMedals, f.bestCase = 0, 0
	if ns.MemberMedals then
		for name in pairs(g.members) do
			local n = 0
			for _, md in ipairs(ns.MemberMedals(name)) do
				if md.tier > 0 then n = n + 1 end
				if md.tier == 3 then f.goldMedals = f.goldMedals + 1 end
			end
			f.bestCase = math.max(f.bestCase, n)
		end
	end
	for _, key in ipairs({ "bgWins", "bgSquads", "projects" }) do sortedTimes(f[key]) end
	return f
end

---------------------------------------------------------------------------
-- Catálogo
--
-- Cada desafío tiene una función que devuelve:
--   progress, target, doneAt (si se sabe cuándo se completó) y criteria opcional
--   (lista de { label, done } para los que son una lista de requisitos).
---------------------------------------------------------------------------

local function counter(key, target)
	return function(f)
		local list = f[key]
		return math.min(#list, target), target, reachedAt(list, target)
	end
end

local function classes(minLevel)
	return function(f)
		local level = minLevel == "max" and (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) or minLevel
		local criteria, done = {}, 0
		for _, class in ipairs(CLASSES) do
			local ok = (f.classLevel[class] or 0) >= level
			if ok then done = done + 1 end
			local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
			criteria[#criteria + 1] = { label = name, done = ok }
		end
		return done, #CLASSES, nil, criteria
	end
end

local function snapshot(key, target)
	return function(f)
		return math.min(f[key], target), target, nil
	end
end

local ACH = {
	-- General
	{ id = "classes1", cat = "general", name = L["Variedad de clases"], icon = "Interface\\Icons\\Spell_Holy_PrayerofFortitude",
		desc = L["Ten en la hermandad un personaje de cada clase."], eval = classes(1) },
	{ id = "classes2", cat = "general", name = L["Clase a clase"], icon = "Interface\\Icons\\Spell_Holy_PrayerofFortitude",
		desc = L["Ten un personaje de cada clase a nivel 30 o más."], eval = classes(30) },
	{ id = "classes3", cat = "general", name = L["Una hermandad completa"], icon = "Interface\\Icons\\Spell_Holy_PrayerofFortitude",
		desc = L["Ten un personaje de cada clase al nivel máximo."], eval = classes("max") },
	{ id = "addon1", cat = "general", name = L["Conectados"], icon = "Interface\\Icons\\INV_Letter_15",
		desc = L["5 miembros usan el addon de la hermandad."], eval = snapshot("addonMembers", 5) },
	{ id = "addon2", cat = "general", name = L["Bien conectados"], icon = "Interface\\Icons\\INV_Letter_15",
		desc = L["15 miembros usan el addon de la hermandad."], eval = snapshot("addonMembers", 15) },
	{ id = "addon3", cat = "general", name = L["Todos a una"], icon = "Interface\\Icons\\INV_Letter_15",
		desc = L["30 miembros usan el addon de la hermandad."], eval = snapshot("addonMembers", 30) },
	{ id = "level30", cat = "general", name = L["Creciendo juntos"], icon = "Interface\\Icons\\Spell_Holy_InnerFire",
		desc = L["10 personajes de la hermandad llegan a nivel 30."], eval = snapshot("level30", 10) },
	{ id = "levelMax1", cat = "general", name = L["Veteranos de Azeroth"], icon = "Interface\\Icons\\Spell_Holy_InnerFire",
		desc = L["5 personajes de la hermandad llegan al nivel máximo."], eval = snapshot("levelMax", 5) },
	{ id = "levelMax2", cat = "general", name = L["Ejército curtido"], icon = "Interface\\Icons\\Spell_Holy_InnerFire",
		desc = L["15 personajes de la hermandad llegan al nivel máximo."], eval = snapshot("levelMax", 15) },
	{ id = "levelMax3", cat = "general", name = L["Leyendas vivas"], icon = "Interface\\Icons\\Spell_Holy_InnerFire",
		desc = L["40 personajes de la hermandad llegan al nivel máximo."], eval = snapshot("levelMax", 40) },

	-- Mazmorras
	{ id = "dungeons1", cat = "pve", name = L["Espeleólogos de hermandad novicios"], icon = "Interface\\Icons\\INV_Misc_Key_03",
		desc = L["Completa 10 mazmorras con un grupo de hermandad (4 o 5 de la guild)."], eval = counter("dungeonDays", 10) },
	{ id = "dungeons2", cat = "pve", name = L["Espeleólogos de hermandad veteranos"], icon = "Interface\\Icons\\INV_Misc_Key_03",
		desc = L["Completa 50 mazmorras con un grupo de hermandad."], eval = counter("dungeonDays", 50) },
	{ id = "dungeons3", cat = "pve", name = L["Maestros espeleólogos de hermandad"], icon = "Interface\\Icons\\INV_Misc_Key_03",
		desc = L["Completa 150 mazmorras con un grupo de hermandad."], eval = counter("dungeonDays", 150) },
	{ id = "variety1", cat = "pve", name = L["Exploradores de mazmorras"], icon = "Interface\\Icons\\INV_Misc_Map_01",
		desc = L["Completa 5 mazmorras distintas con un grupo de hermandad."], eval = function(f)
			local criteria = {}
			for name in pairs(f.dungeonsSeen) do criteria[#criteria + 1] = { label = name, done = true } end
			table.sort(criteria, function(a, b) return a.label < b.label end)
			return math.min(#criteria, 5), 5, nil, criteria
		end },
	{ id = "variety2", cat = "pve", name = L["Cartógrafos de mazmorras"], icon = "Interface\\Icons\\INV_Misc_Map_01",
		desc = L["Completa 10 mazmorras distintas con un grupo de hermandad."], eval = function(f)
			local n = 0
			for _ in pairs(f.dungeonsSeen) do n = n + 1 end
			return math.min(n, 10), 10, nil
		end },

	-- Bandas
	{ id = "raid1", cat = "pve", name = L["Primera sangre en banda"], icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
		desc = L["Derrota a un jefe de banda con un grupo de hermandad (80 % de la guild)."], eval = counter("raidBosses", 1) },
	{ id = "raid2", cat = "pve", name = L["Asaltantes de hermandad"], icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
		desc = L["Derrota a 5 jefes de banda distintos con un grupo de hermandad."], eval = counter("raidBosses", 5) },
	{ id = "raid3", cat = "pve", name = L["Azote de jefes"], icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
		desc = L["Derrota a 15 jefes de banda distintos con un grupo de hermandad."], eval = counter("raidBosses", 15) },

	-- JcJ y caza
	{ id = "kills1", cat = "pvp", name = L["Cazadores novatos"], icon = "Interface\\Icons\\Ability_DualWield",
		desc = L["Consigue 25 muertes honorables entre toda la hermandad (registradas por el addon)."], eval = counter("kills", 25) },
	{ id = "kills2", cat = "pvp", name = L["Cazadores curtidos"], icon = "Interface\\Icons\\Ability_DualWield",
		desc = L["Consigue 100 muertes honorables entre toda la hermandad."], eval = counter("kills", 100) },
	{ id = "kills3", cat = "pvp", name = L["Maestros de la caza"], icon = "Interface\\Icons\\Ability_DualWield",
		desc = L["Consigue 500 muertes honorables entre toda la hermandad."], eval = counter("kills", 500) },
	-- Auxilio y asaltos
	{ id = "aid1", cat = "aid", name = L["Acudimos a la llamada"], icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
		desc = L["Llegad a ayudar a otra hermandad que pide auxilio."], eval = counter("helps", 1) },
	{ id = "aid2", cat = "aid", name = L["Hermanos de armas"], icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
		desc = L["Ayudad en 10 llamadas de auxilio o asaltos de otras hermandades."], eval = counter("helps", 10) },
	{ id = "aid3", cat = "aid", name = L["Escudo de la facción"], icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
		desc = L["Ayudad en 50 llamadas de auxilio o asaltos de otras hermandades."], eval = counter("helps", 50) },
	{ id = "defend1", cat = "aid", name = L["No estamos solos"], icon = "Interface\\Icons\\Ability_Defend",
		desc = L["Otra hermandad acude a vuestra llamada de auxilio."], eval = counter("defended", 1) },
	{ id = "assault1", cat = "assault", name = L["A las puertas"], icon = "Interface\\Icons\\INV_BannerPVP_01",
		desc = L["Completad un asalto a una capital enemiga: derribad a su líder o haced 10 kills en la ciudad."], eval = counter("assaults", 1) },
	{ id = "assault2", cat = "assault", name = L["Asaltantes"], icon = "Interface\\Icons\\INV_BannerPVP_01",
		desc = L["Completad 10 asaltos a capitales enemigas."], eval = counter("assaults", 10) },
	{ id = "regicide1", cat = "assault", name = L["Regicidas"], icon = "Interface\\Icons\\INV_Crown_01",
		desc = L["Derribad al líder de una capital enemiga."], eval = counter("regicides", 1) },
	{ id = "regicide3", cat = "assault", name = L["Azote de reyes"], icon = "Interface\\Icons\\INV_Crown_02",
		desc = L["Derribad a los líderes de las tres capitales enemigas."], eval = snapshot("regicideCities", 3) },
	-- Oculto: un líder derribado en un asalto solo de la hermandad, sin pedir ayuda a la facción.
	{ id = "assaultFast", cat = "assault", name = L["Asalto relámpago"], icon = "Interface\\Icons\\Spell_Nature_Lightning",
		desc = L["Derribad a un líder enemigo menos de 30 minutos después de declarar el asalto."], eval = counter("fastAssaults", 1) },
	{ id = "regicideSolo", cat = "assault", hidden = true, name = L["Por nuestra cuenta"], icon = "Interface\\Icons\\INV_Crown_01",
		desc = L["Derribad a un líder enemigo en un asalto solo de la hermandad, sin pedir ayuda a la facción."], eval = counter("soloRegicides", 1) },

	-- Campos de batalla
	{ id = "bg1", cat = "bg", name = L["Primera victoria"], icon = "Interface\\Icons\\INV_BannerPVP_01",
		desc = L["Gana un campo de batalla (registrado por el addon)."], eval = counter("bgWins", 1) },
	{ id = "bg2", cat = "bg", name = L["Veteranos del campo"], icon = "Interface\\Icons\\INV_BannerPVP_01",
		desc = L["Ganad 25 campos de batalla entre toda la hermandad."], eval = counter("bgWins", 25) },
	{ id = "bg3", cat = "bg", name = L["Señores de la guerra"], icon = "Interface\\Icons\\INV_BannerPVP_02",
		desc = L["Ganad 100 campos de batalla entre toda la hermandad."], eval = counter("bgWins", 100) },
	{ id = "bgSquad", cat = "bg", name = L["Escuadrón"], icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
		desc = L["Ganad un campo de batalla con 5 miembros de la hermandad en el mismo bando."], eval = counter("bgSquads", 1) },
	{ id = "bgKB", cat = "bg", name = L["Golpe de gracia"], icon = "Interface\\Icons\\Ability_Rogue_Eviscerate",
		desc = L["Sumad 250 golpes de gracia en campos de batalla."], eval = snapshot("bgKB", 250) },

	{ id = "bounty1", cat = "pvp", name = L["Cazarrecompensas"], icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
		desc = L["Cobrad el precio por la cabeza de un enemigo."], eval = counter("bountyClaims", 1) },
	{ id = "bounty2", cat = "pvp", name = L["Se hace justicia"], icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
		desc = L["Cobrad 10 precios por cabezas enemigas."], eval = counter("bountyClaims", 10) },
	{ id = "wager1", cat = "pvp", name = L["Sangre fría"], icon = "Interface\\Icons\\INV_Misc_Bag_11",
		desc = L["5 miembros llevan el botín de guerra activado a la vez."], eval = snapshot("wagerMembers", 5) },
	{ id = "revenge1", cat = "pvp", name = L["Ajuste de cuentas"], icon = "Interface\\Icons\\Ability_Warrior_Revenge",
		desc = L["Venga a un compañero 5 veces."], eval = counter("revenges", 5) },
	{ id = "revenge2", cat = "pvp", name = L["Nadie se queda atrás"], icon = "Interface\\Icons\\Ability_Warrior_Revenge",
		desc = L["Venga a un compañero 25 veces."], eval = counter("revenges", 25) },
	{ id = "nemesis", cat = "pvp", name = L["Némesis"], icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
		desc = L["Mata 50 veces a miembros de una misma hermandad."], eval = function(f)
			local best, bestAt = 0, nil
			for _, list in pairs(f.nemesis) do
				if #list > best then best = #list end
				if #list >= 50 and (not bestAt or list[50] < bestAt) then bestAt = list[50] end
			end
			return math.min(best, 50), 50, bestAt
		end },
	{ id = "hk1", cat = "pvp", name = L["Honor de hermandad"], icon = "Interface\\Icons\\INV_BannerPVP_02",
		desc = L["Suma 1.000 muertes por honor entre los miembros con el addon."], eval = snapshot("hkSum", 1000) },
	{ id = "hk2", cat = "pvp", name = L["Gloria de hermandad"], icon = "Interface\\Icons\\INV_BannerPVP_02",
		desc = L["Suma 5.000 muertes por honor entre los miembros con el addon."], eval = snapshot("hkSum", 5000) },
	{ id = "hk3", cat = "pvp", name = L["Leyenda de la guerra"], icon = "Interface\\Icons\\INV_BannerPVP_02",
		desc = L["Suma 20.000 muertes por honor entre los miembros con el addon."], eval = snapshot("hkSum", 20000) },

	-- Profesiones
	{ id = "orders1", cat = "professions", name = L["Manos a la obra"], icon = "Interface\\Icons\\Trade_BlackSmithing",
		desc = L["Entrega 10 encargos entre miembros de la hermandad."], eval = counter("orders", 10) },
	{ id = "orders2", cat = "professions", name = L["Taller de hermandad"], icon = "Interface\\Icons\\Trade_BlackSmithing",
		desc = L["Entrega 50 encargos entre miembros de la hermandad."], eval = counter("orders", 50) },
	{ id = "orders3", cat = "professions", name = L["Gremio de artesanos"], icon = "Interface\\Icons\\Trade_BlackSmithing",
		desc = L["Entrega 200 encargos entre miembros de la hermandad."], eval = counter("orders", 200) },
	{ id = "skill1", cat = "professions", name = L["Trabajo en equipo"], icon = "Interface\\Icons\\Trade_Engineering",
		desc = L["Suma 1.000 niveles de profesión entre los miembros con el addon."], eval = snapshot("skillSum", 1000) },
	{ id = "skill2", cat = "professions", name = L["Maestría compartida"], icon = "Interface\\Icons\\Trade_Engineering",
		desc = L["Suma 3.000 niveles de profesión entre los miembros con el addon."], eval = snapshot("skillSum", 3000) },
	{ id = "allprofs", cat = "professions", name = L["Todos los oficios"], icon = "Interface\\Icons\\INV_Misc_Note_01",
		desc = L["Que alguien de la hermandad tenga cada profesión principal."], eval = function(f)
			local criteria, done = {}, 0
			for _, id in ipairs(PRIMARY_PROFESSIONS) do
				local ok = f.professions[id] == true
				if ok then done = done + 1 end
				criteria[#criteria + 1] = { label = ns.ProfessionName(id), done = ok }
			end
			return done, #PRIMARY_PROFESSIONS, nil, criteria
		end },

	-- Recolección y fabricación (cantidades que cuenta el addon de cada miembro)
	{ id = "mining1", cat = "professions", name = L["Mineros de hermandad"], icon = "Interface\\Icons\\Trade_Mining",
		desc = L["Recoged 1.000 menas y piedras entre toda la hermandad."], eval = snapshot("mining", 1000) },
	{ id = "mining2", cat = "professions", name = L["Vetas sin fin"], icon = "Interface\\Icons\\Trade_Mining",
		desc = L["Recoged 10.000 menas y piedras entre toda la hermandad."], eval = snapshot("mining", 10000) },
	{ id = "mining3", cat = "professions", name = L["Las entrañas de Azeroth"], icon = "Interface\\Icons\\Trade_Mining",
		desc = L["Recoged 50.000 menas y piedras entre toda la hermandad."], eval = snapshot("mining", 50000) },
	{ id = "herb1", cat = "professions", name = L["Jardineros de hermandad"], icon = "Interface\\Icons\\Spell_Nature_NatureTouchGrow",
		desc = L["Recoged 1.000 hierbas entre toda la hermandad."], eval = snapshot("herb", 1000) },
	{ id = "herb2", cat = "professions", name = L["Cosecha abundante"], icon = "Interface\\Icons\\Spell_Nature_NatureTouchGrow",
		desc = L["Recoged 10.000 hierbas entre toda la hermandad."], eval = snapshot("herb", 10000) },
	{ id = "herb3", cat = "professions", name = L["Los jardines de Azeroth"], icon = "Interface\\Icons\\Spell_Nature_NatureTouchGrow",
		desc = L["Recoged 50.000 hierbas entre toda la hermandad."], eval = snapshot("herb", 50000) },
	{ id = "skin1", cat = "professions", name = L["Curtidores de hermandad"], icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
		desc = L["Recoged 1.000 pieles entre toda la hermandad."], eval = snapshot("skinning", 1000) },
	{ id = "skin2", cat = "professions", name = L["Ni una piel desperdiciada"], icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
		desc = L["Recoged 10.000 pieles entre toda la hermandad."], eval = snapshot("skinning", 10000) },
	{ id = "craft1", cat = "professions", name = L["Forja incansable"], icon = "Interface\\Icons\\Trade_BlackSmithing",
		desc = L["Fabricad 500 objetos entre toda la hermandad."], eval = snapshot("crafted", 500) },
	{ id = "craft2", cat = "professions", name = L["La gran fábrica"], icon = "Interface\\Icons\\Trade_BlackSmithing",
		desc = L["Fabricad 5.000 objetos entre toda la hermandad."], eval = snapshot("crafted", 5000) },
	-- Ocultos: no se ven hasta que alguien los consigue.
	{ id = "motherlode", cat = "professions", hidden = true, name = L["La veta madre"], icon = "Interface\\Icons\\INV_Ore_Mithril_02",
		desc = L["Un miembro recoge 100 unidades de un mismo material en un solo día."], eval = snapshot("bestDay", 100) },
	{ id = "factory", cat = "professions", hidden = true, name = L["Fábrica humana"], icon = "Interface\\Icons\\INV_Gizmo_02",
		desc = L["Un miembro fabrica 500 objetos en una semana."], eval = snapshot("bestWeekCrafted", 500) },

	-- Comunidad
	{ id = "events1", cat = "community", name = L["Unidos"], icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02",
		desc = L["Celebra un evento con al menos 5 asistentes."], eval = counter("events", 1) },
	{ id = "events2", cat = "community", name = L["Siempre juntos"], icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02",
		desc = L["Celebra 10 eventos con al menos 5 asistentes."], eval = counter("events", 10) },
	{ id = "events3", cat = "community", name = L["Una gran familia"], icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02",
		desc = L["Celebra 25 eventos con al menos 5 asistentes."], eval = counter("events", 25) },
	{ id = "auctions1", cat = "community", name = L["Mercaderes"], icon = "Interface\\Icons\\INV_Misc_Bag_10",
		desc = L["Cierra 5 subastas de hermandad con ganador."], eval = counter("auctions", 5) },
	{ id = "auctions2", cat = "community", name = L["Casa de subastas propia"], icon = "Interface\\Icons\\INV_Misc_Bag_10",
		desc = L["Cierra 25 subastas de hermandad con ganador."], eval = counter("auctions", 25) },
	-- Banco de la hermandad
	{ id = "bank1", cat = "community", name = L["Despensa llena"], icon = "Interface\\Icons\\INV_Box_04",
		desc = L["Haced 100 depósitos de objetos en el banco de la hermandad."], eval = snapshot("bankItems", 100) },
	{ id = "bankReq", cat = "community", name = L["Proveedores"], icon = "Interface\\Icons\\INV_Crate_01",
		desc = L["Completad 5 pedidos del banco de la hermandad."], eval = counter("bankRequests", 5) },
	{ id = "bank2", cat = "community", name = L["Arcas de oro"], icon = "Interface\\Icons\\INV_Misc_Coin_01",
		desc = L["Depositad 1.000 de oro entre todos en el banco de la hermandad."], eval = snapshot("bankGold", 1000) },
	-- Tienda
	{ id = "shop1", cat = "community", name = L["Buen gusto"], icon = "Interface\\Icons\\INV_Fabric_Silk_02",
		desc = L["Comprad 10 cosméticos en la tienda entre toda la hermandad."], eval = counter("purchases", 10) },
	{ id = "shopAll", cat = "community", name = L["Coleccionista"], icon = "Interface\\Icons\\INV_Jewelry_Ring_03",
		desc = L["Un miembro tiene todos los marcos y terciopelos de la tienda."], eval = function(f)
			return math.min(f.bestCollection, f.cosmetics), f.cosmetics, nil
		end },
	-- Medallas del perfil
	{ id = "medal1", cat = "community", name = L["Condecorados"], icon = "Interface\\Icons\\INV_Misc_Trophy_03",
		desc = L["Un miembro consigue una medalla de oro."], eval = snapshot("goldMedals", 1) },
	{ id = "medal2", cat = "community", name = L["Galería de héroes"], icon = "Interface\\Icons\\INV_Misc_Trophy_03",
		desc = L["Sumad 10 medallas de oro entre toda la hermandad."], eval = snapshot("goldMedals", 10) },
	{ id = "medalFull", cat = "community", name = L["Pecho de medallas"], icon = "Interface\\Icons\\INV_Misc_Trophy_02",
		desc = L["Un miembro tiene las 8 medallas del estuche (de cualquier grado)."], eval = snapshot("bestCase", 8) },
	-- Cofre de hermandad
	{ id = "chest1", cat = "community", name = L["Primer proyecto"], icon = "Interface\\Icons\\INV_Box_02",
		desc = L["Activad un proyecto del cofre de hermandad."], eval = counter("projects", 1) },
	{ id = "chest2", cat = "community", name = L["Hermandad emprendedora"], icon = "Interface\\Icons\\INV_Box_02",
		desc = L["Activad 10 proyectos del cofre de hermandad."], eval = counter("projects", 10) },
	{ id = "chest3", cat = "community", name = L["Catálogo completo"], icon = "Interface\\Icons\\INV_Box_03",
		desc = L["Activad al menos una vez cada proyecto del catálogo."], eval = function(f)
			local criteria, done, last = {}, 0, nil
			for _, kind in ipairs(ns.PROJECT_KINDS or {}) do
				local t = f.projectKinds[kind.key]
				if t then
					done = done + 1
					last = math.max(last or 0, t)
				end
				criteria[#criteria + 1] = { label = kind.label, done = t ~= nil }
			end
			return done, #criteria, done == #criteria and last or nil, criteria
		end },
	{ id = "chestDonate", cat = "community", name = L["Arcas llenas"], icon = "Interface\\Icons\\INV_Misc_Coin_02",
		desc = L["Donad 2.000 insignias entre todos al cofre y a sus proyectos."], eval = snapshot("chestDonated", 2000) },
}
ns.ACHIEVEMENTS = ACH

---------------------------------------------------------------------------
-- Estado: progreso de cada desafío, fechas y puntos
---------------------------------------------------------------------------

local cache

-- Devuelve { list = { { def, progress, target, done, doneAt, criteria } }, points, total }.
function ns.AchievementState()
	if cache then return cache end
	local g = LG:GuildData()
	-- Catálogo fijo más los de mazmorras y bandas de legado (Legacy.lua, si están encendidos).
	local defs = {}
	for _, def in ipairs(ACH) do defs[#defs + 1] = def end
	for _, def in ipairs(ns.LegacyChallengeDefs and ns.LegacyChallengeDefs() or {}) do defs[#defs + 1] = def end
	for _, def in ipairs(ns.WarChallengeDefs and ns.WarChallengeDefs() or {}) do defs[#defs + 1] = def end
	-- Las proezas de fuerza no cuentan para los puntos ni para el total.
	local total = 0
	for _, def in ipairs(defs) do
		if not def.feat then total = total + 1 end
	end
	local state = { list = {}, byId = {}, points = 0, total = total }
	if not g then return state end
	local f = gatherFacts(g)
	for _, def in ipairs(defs) do
		local ok, progress, target, doneAt, criteria = pcall(def.eval, f)
		if not ok then progress, target, doneAt, criteria = 0, 1, nil, nil end
		local done = progress >= target
		local entry = { def = def, progress = progress, target = target, done = done, criteria = criteria }
		if done then
			-- Fecha: la registrada (la más antigua que ha visto la hermandad) o la calculada.
			local rec = g.achievements[def.id]
			entry.doneAt = (rec and rec.t) or doneAt
			if not def.feat then state.points = state.points + 1 end
		end
		state.list[#state.list + 1] = entry
		state.byId[def.id] = entry
	end
	cache = state
	return state
end

function ns.InvalidateAchievements()
	cache = nil
end

function ns.MergeAchievement(g, rec)
	if type(rec.id) ~= "string" or type(rec.t) ~= "number" then return false end
	local old = g.achievements[rec.id]
	if old and old.t <= rec.t then return false end
	g.achievements[rec.id] = { t = rec.t }
	return true
end

ns.handlers.ACH = function(sender, rec)
	local g = LG:GuildData()
	if g and ns.MergeAchievement(g, rec) then
		ns.InvalidateAchievements()
		LG:DataChanged()
	end
end

-- Título y emblema dorado (lo que pinta la cabecera de la ventana).
function ns.AchievementRewards()
	local perks = ns.GuildPerks()
	return perks.title, perks.watermark or false, perks
end

-- Revisa si hay desafíos recién completados: guarda su fecha, la comparte y los anuncia.
function Achievements:Check()
	local g = LG:GuildData()
	if not g or not LG:HasConsent() then return end
	ns.InvalidateAchievements()
	local state = ns.AchievementState()
	local now = ns.Now()
	local newOnes = {}
	for _, entry in ipairs(state.list) do
		if entry.done and not g.achievements[entry.def.id] then
			local t = entry.doneAt or now
			g.achievements[entry.def.id] = { t = t }
			LG:Send("ACH", { id = entry.def.id, t = t })
			if now - t <= TOAST_WINDOW then newOnes[#newOnes + 1] = entry end
		end
	end
	if #newOnes > 0 then
		ns.InvalidateAchievements()
		for i = 1, math.min(3, #newOnes) do
			if ns.ShowAchievementToast then ns.ShowAchievementToast(newOnes[i]) end
		end
		LG:DataChanged()
	end
end

function Achievements:OnEnable()
	self:RegisterMessage("LANTUX_DATA_CHANGED", function()
		-- Se agrupan los cambios: la revisión se hace un instante después.
		if self.pending then return end
		self.pending = self:ScheduleTimer(function()
			self.pending = nil
			self:Check()
		end, 2)
	end)
	self:ScheduleTimer("Check", 15)
end
