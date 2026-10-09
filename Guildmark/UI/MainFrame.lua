-- Ventana principal.
--
-- Secciones (navegación a la izquierda, al estilo de los desafíos de legado):
--   Inicio     tu progreso, próximos eventos, encargos pendientes, grupo y movimientos
--   Eventos    calendario de la hermandad
--   Mercado    subasta de hermandad, recetas, encargos y tienda
--   JcE        buscador de grupo de la hermandad y tiempos de mazmorra
--   JcJ        objetivos y kills, guerras con otras hermandades y directorio de la red
--   Hermandad  ahora, miembros (con ficha), tribus, clasificación, crónica y cofre
--   Oficial    solo la ven los oficiales: avisos de datos sospechosos y herramientas
--
-- Cada vista devuelve una lista de filas:
--   { kind = "header", text, buttons }          título de sección con línea dorada
--   { text | cols, indent, onClick, buttons }   fila normal (cols = { { texto, ancho }, ... })
--   { kind = "bar", label, value, max, text, color }  barra de progreso
--   { kind = "space" }
-- y opcionalmente search = true para mostrar el buscador.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local frame, scroll, scrollChild, searchBox, searchHint, summary, subtitle, achButton, watermark
local segmentButtons = {}
local current = "home"
local subview = { market = "auction", guild = "members", hunt = "targets", pve = "lfg", faction = "ranking" }
local expanded = {}
local tabButtons = {}

local CONTENT_WIDTH = 690
local WATERMARK_ALPHA = 0.08 -- opacidad de la marca de agua del canal (0 = invisible, 1 = opaca)
local MAX_BUTTONS = 6
local MAX_COLS = 6

local GOLD = "|cffffd100"
local GREY = "|cff9d9d9d"
local GREEN = "|cff1eff00"
local RED = "|cffff6b5a"
local BLUE = "|cff69ccf0"
local R = "|r"

-- Las fuentes del juego no tienen símbolos como ● o ✔: se usan iconos del propio cliente.
local ICON_ONLINE = "|TInterface\\COMMON\\Indicator-Green:12:12|t"
local ICON_OFFLINE = "|TInterface\\COMMON\\Indicator-Gray:12:12|t"
local ICON_YES = "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:12:12|t"
local ICON_NO = "|TInterface\\RAIDFRAME\\ReadyCheck-NotReady:12:12|t"
local ICON_SKULL = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"

local ANOMALY_KINDS -- tipo de aviso según el principio de su clave (se rellena al pintar)

local function refresh() if ns.RefreshMainFrame then ns.RefreshMainFrame() end end

local function toggle(key, default)
	return function()
		local open = expanded[key]
		if open == nil then open = default or false end
		expanded[key] = not open
		refresh()
	end
end

local function isOpen(key, default)
	local open = expanded[key]
	if open == nil then return default or false end
	return open
end

local function header(rows, text, buttons)
	rows[#rows + 1] = { kind = "header", text = text, buttons = buttons }
end
local function line(rows, text, indent, extra)
	local row = extra or {}
	row.text, row.indent = text, indent
	rows[#rows + 1] = row
end
local function space(rows) rows[#rows + 1] = { kind = "space" } end
local function grey(text) return GREY .. text .. R end

local function notInGuild()
	return { { text = grey(L["No estás en una hermandad. Con /gmk prueba tu grupo cuenta como hermandad para probar el addon."]) } }
end

-- Selector de subvista (Recetas / Encargos, Miembros / Clasificación / Crónica).
-- Se dibuja fijo arriba a la izquierda, con el buscador en la misma línea.
local function segments(rows, tab, options)
	local list = {}
	for _, o in ipairs(options) do
		list[#list + 1] = { key = o.key, label = o.label, selected = subview[tab] == o.key, onClick = function()
			if subview[tab] ~= o.key then searchBox:SetText("") end
			subview[tab] = o.key
			refresh()
		end }
	end
	rows.segments = list
end

function ns.FindMember(text)
	local g = LG:GuildData()
	if not g or not text or text == "" then return nil end
	local wanted = ns.FullName(text)
	for name in pairs(g.members) do if name == wanted then return name end end
	for name in pairs(ns.roster) do if name == wanted then return name end end
	for name in pairs(g.members) do if ns.SameName(name, wanted) then return name end end
	for name in pairs(ns.roster) do if ns.SameName(name, wanted) then return name end end
	return nil
end

---------------------------------------------------------------------------
-- Piezas compartidas
---------------------------------------------------------------------------

local auctionRow -- fila de subasta; se define en la sección Mercado y la usa también Inicio

-- Iconos de objetos, recetas y eventos.
local function itemIcon(itemID)
	if not itemID then return nil end
	if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
	return GetItemIcon and GetItemIcon(itemID) or nil
end

-- Color de la calidad del objeto (gris, blanco, verde, azul, morado...) para el marco del icono.
local function qualityColor(itemID)
	local quality = itemID and C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
	local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if c then return { c.r, c.g, c.b } end
	return nil
end

-- Icono de una receta: el del objeto que fabrica si se conoce, si no el del hechizo.
local function recipeIcon(recipeID, outputItemID)
	if outputItemID then return itemIcon(outputItemID), qualityColor(outputItemID) end
	local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(recipeID)
	return texture or "Interface\\Icons\\INV_Misc_QuestionMark", nil
end

-- Unidad cargada en el cliente para ese nombre (tú, tu grupo o tu objetivo), si la hay.
local function unitForName(name)
	if name == ns.PlayerFullName() then return "player" end
	local prefix = IsInRaid() and "raid" or "party"
	local count = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
	for i = 1, count do
		local unit = prefix .. i
		if ns.UnitFullName(unit) == name then return unit end
	end
	if ns.UnitFullName("target") == name then return "target" end
	return nil
end

-- Retrato del personaje si el juego lo tiene cargado; si no, el emblema
-- redondo de su clase (el de los marcos de grupo). Devuelve campos de fila.
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local PORTRAIT_SIZE, PORTRAIT_ROW_H = 34, 46 -- retratos de las listas de miembros (con aire entre filas)
local function portraitFields(name, classFile, fields)
	fields = fields or {}
	local unit = unitForName(name)
	if unit then
		fields.portraitUnit = unit
		fields.icon = CLASS_CIRCLES -- se sustituye por el retrato al pintar la fila
	elseif classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile] then
		fields.icon = CLASS_CIRCLES
		fields.iconCoords = CLASS_ICON_TCOORDS[classFile]
	else
		fields.icon = "Interface\\Icons\\INV_Misc_QuestionMark"
	end
	local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	fields.iconColor = color and { color.r, color.g, color.b } or nil
	-- Retrato redondo con un aro fino del color de la clase, algo más grande.
	fields.portrait = true
	fields.height = math.max(fields.height or 0, PORTRAIT_ROW_H)
	return fields
end

local EVENT_ICONS = {
	raid = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
	dungeon = "Interface\\Icons\\INV_Misc_Key_03",
	pvp = "Interface\\Icons\\Ability_DualWield",
	social = "Interface\\Icons\\INV_Drink_04",
}

local ROLE_LABEL = {}
for _, r in ipairs(ns.ROLES) do ROLE_LABEL[r.key] = r.label end

local STATUS = {
	open = { GOLD, L["pendiente"] },
	accepted = { BLUE, L["aceptado"] },
	done = { GREEN, L["entregado"] },
	declined = { RED, L["rechazado"] },
	cancelled = { GREY, L["cancelado"] },
}

local function setOrder(id, status) return function() ns.SetOrderStatus(id, status) end end

-- Encargo en tarjeta: el objeto, quién lo pide y quién lo hace, y su estado.
local function orderRow(o, who, buttons)
	local s = STATUS[o.status] or { GREY, o.status }
	if ns.OrderExpired(o) then s = { GREY, L["caducado"] } end
	local icon, color = recipeIcon(o.recipe, o.item)
	local foot = { date("%d/%m %H:%M", o.t) }
	if o.guild then foot[#foot + 1] = (L["al gremio de %s"]):format(o.skillLine and ns.ProfessionName(o.skillLine) or "?") end
	if o.status == "done" and o.verified then foot[#foot + 1] = GREEN .. L["verificado por intercambio"] .. R end
	if o.note then foot[#foot + 1] = "\"" .. o.note .. "\"" end
	return {
		kind = "card",
		state = (o.status == "declined" or o.status == "cancelled") and "off" or "normal",
		accent = (o.status == "open" and buttons) and ns.ACCENT.action or (o.status == "done" and ns.ACCENT.good or nil),
		link = o.item and ("item:" .. o.item) or nil,
		icon = icon, iconColor = color,
		title = ("%dx %s"):format(o.qty or 1, ns.RecipeName(o.recipe) or "?"),
		desc = who,
		status = s[1] .. s[2] .. R,
		foot = grey(table.concat(foot, "  ·  ")),
		buttons = buttons,
	}
end

-- Encargo terminado de otros: una línea compacta.
local function orderLine(rows, o)
	local s = STATUS[o.status] or { GREY, o.status }
	local icon, color = recipeIcon(o.recipe, o.item)
	line(rows, ("%s  %dx %s  %s  %s%s|r"):format(grey(date("%d/%m", o.t)), o.qty or 1, ns.RecipeName(o.recipe) or "?",
		grey(("%s > %s"):format(ns.ShortName(o.requester) or "?", o.crafter and ns.ShortName(o.crafter) or L["gremio"])), s[1], s[2]), 1, { icon = icon, iconColor = color })
end

local function orderButtons(o, me)
	if o.guild and o.status == "open" and o.requester ~= me then
		return { { label = L["Aceptar"], onClick = function() ns.AcceptGuildOrder(o.id) end,
			tooltip = { L["Aceptar"], L["El primero que lo acepta se lo queda."] } } }
	end
	if o.crafter == me then
		if o.status == "open" then
			return { { label = L["Aceptar"], onClick = setOrder(o.id, "accepted") }, { label = L["Rechazar"], onClick = setOrder(o.id, "declined") } }
		elseif o.status == "accepted" then
			return { { label = L["Entregado"], onClick = setOrder(o.id, "done") } }
		end
	elseif o.requester == me then
		if o.status == "open" then
			return { { label = L["Cancelar"], onClick = setOrder(o.id, "cancelled") } }
		elseif o.status == "accepted" then
			return { { label = L["Recibido"], onClick = setOrder(o.id, "done") }, { label = L["Cancelar"], onClick = setOrder(o.id, "cancelled") } }
		end
	end
	return nil
end

local function roleCount(g, e, role)
	local n = 0
	for _, s in pairs(g.signups[e.id] or {}) do
		if s.status == "yes" and s.role == role then n = n + 1 end
	end
	return n
end

local function signupButtons(e, mine)
	local buttons = {}
	for _, r in ipairs(ns.ROLES) do
		buttons[#buttons + 1] = { label = r.label, disabled = mine and mine.status == "yes" and mine.role == r.key,
			onClick = function() ns.SignUp(e.id, "yes", r.key) end }
	end
	buttons[#buttons + 1] = { label = L["No voy"], disabled = mine and mine.status == "no", onClick = function() ns.SignUp(e.id, "no") end }
	return buttons
end

-- Iconos de rol (escudo, cruz, espadas) para plazas y botones.
local ROLE_ATLAS = { tank = "roleicon-tiny-tank", healer = "roleicon-tiny-healer", dps = "roleicon-tiny-dps" }
local function roleIcon(role, size)
	return ("|A:%s:%d:%d|a"):format(ROLE_ATLAS[role] or ROLE_ATLAS.dps, size or 14, size or 14)
end
ns.RoleIcon = roleIcon

-- Plazas por rol con su icono: "[escudo] 0/1  [cruz] 1/1  [espadas] 2/3".
-- colored: en verde lo completo y en rojo lo que falta; si no, todo en gris.
local function roleSlots(have, need, colored)
	local parts = {}
	for _, role in ipairs({ "tank", "healer", "dps" }) do
		local h, n = have[role] or 0, need[role] or 0
		if n > 0 or h > 0 then
			local text = ("%d/%d"):format(h, n)
			if colored then text = (h >= n and GREEN or RED) .. text .. R else text = grey(text) end
			parts[#parts + 1] = roleIcon(role, 13) .. " " .. text
		end
	end
	return table.concat(parts, "   ")
end

local function eventSlots(g, e)
	return roleSlots({ tank = roleCount(g, e, "tank"), healer = roleCount(g, e, "healer"), dps = roleCount(g, e, "dps") }, e.comp, false)
end

local function eventTitle(g, e, me)
	local comp = ""
	if e.comp and (e.comp.tank + e.comp.healer + e.comp.dps) > 0 then
		comp = "   " .. eventSlots(g, e)
	end
	local mine = g.signups[e.id] and g.signups[e.id][me]
	local tag = ""
	if mine and mine.status == "yes" then
		tag = GREEN .. "  [" .. (ROLE_LABEL[mine.role] or "?") .. "]" .. R
	elseif mine and mine.status == "no" then
		tag = grey("  [" .. L["no voy"] .. "]")
	end
	return ("%s%s|r  %s  %s%s%s"):format(GOLD, date("%d/%m %H:%M", e.start), ns.EVENT_KIND_LABEL[e.kind] or "", e.title, comp, tag), mine
end

-- Apuntados por rol, con los que asistieron marcados con * en verde.
local function signupRows(g, e, rows)
	local signups = g.signups[e.id] or {}
	local attendance = g.attendance[e.id] or {}
	local byRole = { tank = {}, healer = {}, dps = {} }
	local declined = {}
	for member, s in pairs(signups) do
		local m = g.members[member]
		local name = ns.ClassColorName(member, m and m.class)
		if attendance[member] then name = name .. GREEN .. "*" .. R end
		if s.status == "yes" and byRole[s.role] then
			table.insert(byRole[s.role], name)
		elseif s.status == "no" then
			declined[#declined + 1] = ns.ShortName(member)
		end
	end
	local anyone = false
	for _, r in ipairs(ns.ROLES) do
		local list = byRole[r.key]
		table.sort(list)
		local want = e.comp and e.comp[r.key] or 0
		if #list > 0 then anyone = true end
		if want > 0 or #list > 0 then
			local color = (#list >= want) and GREEN or GOLD
			line(rows, ("|A:%s:14:14|a %s%s %d/%d|r   %s"):format(ROLE_ATLAS[r.key], color, r.label, #list, want,
				#list > 0 and table.concat(list, ", ") or grey(L["nadie todavía"])), 2)
		end
	end
	if not anyone and not (e.comp and (e.comp.tank + e.comp.healer + e.comp.dps) > 0) then
		line(rows, grey(L["Nadie apuntado todavía."]), 2)
	end
	if #declined > 0 then
		table.sort(declined)
		line(rows, grey(L["No van"] .. ": " .. table.concat(declined, ", ")), 2)
	end
	local extra = {}
	for member in pairs(attendance) do
		if not signups[member] or signups[member].status ~= "yes" then extra[#extra + 1] = ns.ShortName(member) end
	end
	if #extra > 0 then
		table.sort(extra)
		line(rows, GREEN .. L["Vinieron sin apuntarse"] .. ": " .. table.concat(extra, ", ") .. R, 2)
	end
end

-- "Hoy", "Ayer" o "Lunes 28/09" (date() del juego no traduce los días).
local WEEKDAYS = { L["Domingo"], L["Lunes"], L["Martes"], L["Miércoles"], L["Jueves"], L["Viernes"], L["Sábado"] }
local function dayLabel(t)
	local today = date("%Y-%m-%d")
	local day = date("%Y-%m-%d", t)
	if day == today then return L["Hoy"] end
	if day == date("%Y-%m-%d", time() - 86400) then return L["Ayer"] end
	return WEEKDAYS[tonumber(date("%w", t)) + 1] .. " " .. date("%d/%m", t)
end

-- "hace un momento", "hace 5 min", "hace 3 h", "hace 2 días".
local function ago(t)
	local s = math.max(0, ns.Now() - t)
	if s < 60 then return L["hace un momento"] end
	if s < 3600 then return (L["hace %d min"]):format(math.floor(s / 60)) end
	if s < 86400 then return (L["hace %d h"]):format(math.floor(s / 3600)) end
	return (L["hace %d días"]):format(math.floor(s / 86400))
end

local function sortedCounts(counts, max)
	local list = {}
	for key, n in pairs(counts) do list[#list + 1] = { key = key, n = n } end
	table.sort(list, function(a, b) return a.n > b.n end)
	for i = #list, max + 1, -1 do list[i] = nil end
	return list
end

---------------------------------------------------------------------------
-- Inicio
---------------------------------------------------------------------------

local views = {}

views.home = function()
	local g = LG:GuildData()
	if not g then return notInGuild() end
	local rows = {}
	local me = ns.PlayerFullName()
	local s = ns.Scores()[me] or { merits = 0, recent = {}, capsUsed = {} }
	local current, nextRank, rep, weeks = ns.MeritRank(me)

	header(rows, L["Tu progreso"])
	if nextRank then
		line(rows, (L["Rango actual: %s%s|r"]):format(GOLD, current.label), 1)
		rows[#rows + 1] = { kind = "bar", label = (L["Reputación hacia %s"]):format(nextRank.label), value = rep, max = nextRank.rep,
			text = ("%d / %d"):format(rep, nextRank.rep), color = { 0.25, 0.8, 0.25 } }
		if LG:InTestMode() then
			line(rows, grey(L["Modo prueba: no se exige antigüedad para subir de rango."]), 1)
		else
			rows[#rows + 1] = { kind = "bar", label = L["Semanas en la hermandad"], value = weeks, max = nextRank.weeks,
				text = ("%d / %d"):format(weeks, nextRank.weeks), color = { 0.35, 0.6, 1 } }
			if rep >= nextRank.rep and weeks < nextRank.weeks then
				local left = nextRank.weeks - weeks
				line(rows, GOLD .. (left == 1 and L["Ya tienes la reputación para %s: te falta 1 semana en la hermandad."]
					or L["Ya tienes la reputación para %s: te faltan %d semanas en la hermandad."]):format(nextRank.label, left) .. R, 1)
			end
		end
		line(rows, grey(L["El rango del addon no cambia el rango del juego: eso lo hacen los oficiales."]), 1)
	else
		line(rows, (L["Rango máximo alcanzado: %s%s|r · %d de reputación"]):format(GOLD, current.label, rep), 1)
	end
	local caps = s.capsUsed or {}
	for _, c in ipairs({ { "dungeons", L["Insignias de mazmorras (semana)"] }, { "professions", L["Insignias de artesanía (semana)"] }, { "pvp", L["Insignias de caza (hoy)"] } }) do
		local cap = caps[c[1]] or { used = 0, limit = 100 }
		rows[#rows + 1] = { kind = "bar", label = c[2], value = cap.used, max = cap.limit,
			text = ("%d / %d"):format(cap.used, cap.limit), color = { 0.85, 0.65, 0.1 } }
	end
	line(rows, grey(L["Las insignias se gastan en la subasta, la tienda y el cofre, y bajan un 5 % cada miércoles (eso va al cofre). La reputación no se pierde."]), 1)

	-- Proyectos del cofre activos: que nadie se los pierda.
	local activeProjects = ns.ProjectLists().active
	if #activeProjects > 0 then
		space(rows)
		header(rows, L["Proyectos activos"], { { label = L["Ver el cofre"], onClick = function()
			ns.SelectSubview("guild", "chest")
		end } })
		for _, item in ipairs(activeProjects) do
			local kind = ns.ProjectKind(item.p.kind)
			rows[#rows + 1] = { kind = "card", state = "normal", accent = ns.ACCENT.good, icon = kind.icon, title = kind.label,
				desc = grey(kind.desc), status = GREEN .. (L["activo: %s"]):format(ns.FormatDuration(ns.ProjectEnds(item.p) - ns.Now())) .. R }
		end
	end

	-- Próximos eventos (los tres primeros), con apuntarse en un clic.
	local upcoming = ns.EventLists()
	space(rows)
	header(rows, L["Próximos eventos"], { { label = L["Ver todos"], onClick = function() ns.SelectTab("events") end } })
	local shown = 0
	for _, e in ipairs(upcoming) do
		if e.status ~= "cancelled" and shown < 3 then
			shown = shown + 1
			local title, mine = eventTitle(g, e, me)
			line(rows, title, 1, { icon = EVENT_ICONS[e.kind], buttons = signupButtons(e, mine) })
		end
	end
	if shown == 0 then line(rows, grey(L["No hay eventos programados."]), 1) end

	-- Subastas en las que has pujado y siguen abiertas.
	local myAuctions = {}
	for _, a in ipairs((ns.AuctionLists())) do
		if g.bids[a.id] and g.bids[a.id][me] then myAuctions[#myAuctions + 1] = a end
	end
	if #myAuctions > 0 then
		space(rows)
		header(rows, L["Tus pujas"], { { label = L["Ver subastas"], onClick = function()
			subview.market = "auction"
			ns.SelectTab("market")
		end } })
		local canManage = ns.CanManageEvents(me)
		for _, a in ipairs(myAuctions) do rows[#rows + 1] = auctionRow(g, a, me, canManage) end
	end

	-- Encargos que necesitan algo de ti.
	local roles = ns.OrdersByRole()
	local pending = {}
	for _, o in ipairs(roles.forMe) do
		if o.status == "open" or o.status == "accepted" then pending[#pending + 1] = { o = o, who = L["de"] .. " " .. ns.ShortName(o.requester) } end
	end
	for _, o in ipairs(roles.mine) do
		if o.status == "open" or o.status == "accepted" then pending[#pending + 1] = { o = o, who = o.crafter and (L["a"] .. " " .. ns.ShortName(o.crafter))
			or grey(L["esperando a que alguien del gremio lo acepte"]) } end
	end
	if #pending > 0 then
		space(rows)
		header(rows, L["Encargos pendientes"])
		for _, p in ipairs(pending) do rows[#rows + 1] = orderRow(p.o, p.who, orderButtons(p.o, me)) end
	end

	-- Grupo de mazmorra actual.
	if IsInGroup() and not IsInRaid() then
		local all, guild = ns.GroupComposition()
		space(rows)
		header(rows, L["Grupo actual"])
		local state
		if #all == 5 and #guild == 5 then
			state = GREEN .. L["5/5 de hermandad: bonus completo en mazmorras."] .. R
		elseif #all == 5 and #guild == 4 then
			state = GOLD .. L["4/5 de hermandad: bonus parcial."] .. R
		else
			state = grey((L["%d de %d son de la hermandad. Con 4 o 5 de la hermandad hay bonus."]):format(#guild, #all))
		end
		line(rows, state, 1)
	end

	space(rows)
	header(rows, L["Últimos movimientos"])
	if #s.recent == 0 then line(rows, grey(L["Todavía nada. Se ganan con eventos, mazmorras de hermandad, caza y encargos."]), 1) end
	for i = 1, math.min(6, #s.recent) do
		local e = s.recent[i]
		line(rows, ("%s  %s%+d|r rep  %s%+d|r %s  %s%s"):format(grey(date("%d/%m", e.t)), GOLD, e.rep, GREEN, e.merits,
			L["insignias"], e.reason or "", e.capped and grey(" (" .. L["tope"] .. ")") or ""), 1)
	end

	space(rows)
	-- Estado de la sincronización: con quién y hace cuánto.
	local sync = LG.lastSync or LG.lastHeard
	if LG.lastSync and LG.lastHeard and LG.lastHeard.t > LG.lastSync.t then sync = LG.lastHeard end
	if sync then
		line(rows, grey((L["Sincronizado %s con %s."]):format(ago(sync.t), ns.ShortName(sync.from) or "?")), 0,
			{ icon = "Interface\\COMMON\\Indicator-Green", tooltip = { L["Sincronización"],
				L["Cada addon comparte sus datos con los demás miembros conectados. Cuantos más lo tengan, más completo está todo."] } })
	else
		line(rows, grey(LG:InTestMode() and L["Modo prueba: los datos se comparten con tu grupo."]
			or L["Todavía no has recibido datos de nadie: llegan cuando otro miembro con el addon está conectado."]), 0,
			{ icon = "Interface\\COMMON\\Indicator-Gray" })
	end
	local consent = LG.db.char.consent == "yes"
	line(rows, consent and grey(L["Compartes tus datos con la hermandad."]) or (RED .. L["No compartes datos: no sumas puntos ni ves los de la hermandad."] .. R), 0,
		{ buttons = { { label = L["Privacidad"], onClick = ns.ShowConsent } } })
	return rows
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------

-- Calendario: mes que se ve y día elegido ("AAAA-MM-DD"; nil = próximos eventos).
local calMonth, calSelected

ns.MONTH_NAMES = { L["Enero"], L["Febrero"], L["Marzo"], L["Abril"], L["Mayo"], L["Junio"], L["Julio"],
	L["Agosto"], L["Septiembre"], L["Octubre"], L["Noviembre"], L["Diciembre"] }
ns.WEEKDAYS_SHORT = { L["Lun"], L["Mar"], L["Mié"], L["Jue"], L["Vie"], L["Sáb"], L["Dom"] } -- la semana empieza el lunes

local function dayKey(t) return date("%Y-%m-%d", t) end

-- Eventos y guerras de cada día del mes: [día] = { events = {...}, wars = {...} }.
local function monthData(g, year, month)
	local days = {}
	local function slot(t)
		local d = date("*t", t)
		if d.year ~= year or d.month ~= month then return nil end
		days[d.day] = days[d.day] or { events = {}, wars = {} }
		return days[d.day]
	end
	for _, e in pairs(g.events) do
		local d = e.status ~= "cancelled" and slot(e.start)
		if d then table.insert(d.events, e) end
	end
	for _, w in pairs(ns.WARS_PAUSED and {} or g.wars) do
		local phase = ns.WarPhase(w)
		local d = (phase == "pending" or phase == "upcoming" or phase == "active" or phase == "finished") and slot(w.start)
		if d then table.insert(d.wars, w) end
	end
	for _, d in pairs(days) do
		table.sort(d.events, function(a, b) return a.start < b.start end)
		table.sort(d.wars, function(a, b) return a.start < b.start end)
	end
	return days
end

local function eventRow(rows, g, e, me, canManage)
	local cancelled = e.status == "cancelled"
	local key = "event|" .. e.id
	local open = not cancelled and isOpen(key, false)
	local mine = g.signups[e.id] and g.signups[e.id][me]
	local going = mine and mine.status == "yes"

	-- Tarjeta: título, tipo y hora, plazas por rol y tu inscripción.
	local desc = ("%s%s|r  ·  %s"):format(GOLD, dayLabel(e.start) .. " " .. date("%H:%M", e.start), ns.EVENT_KIND_LABEL[e.kind] or "")
	if e.comp and (e.comp.tank + e.comp.healer + e.comp.dps) > 0 then
		desc = desc .. "   " .. eventSlots(g, e)
	end
	local status
	if cancelled then
		status = RED .. L["cancelado"] .. R
	elseif going then
		status = GREEN .. (ROLE_LABEL[mine.role] or "?") .. R
	elseif mine and mine.status == "no" then
		status = grey(L["no voy"])
	end
	local foot = {}
	if e.minLevel then foot[#foot + 1] = (L["nivel %d+"]):format(e.minLevel) end
	foot[#foot + 1] = (L["organiza %s"]):format(ns.ShortName(e.creator))
	rows[#rows + 1] = {
		kind = "card",
		icon = EVENT_ICONS[e.kind],
		title = e.title,
		desc = desc,
		status = status,
		foot = grey(table.concat(foot, "  ·  ")),
		state = cancelled and "off" or "normal", accent = (not cancelled and going) and ns.ACCENT.good or nil,
		onClick = not cancelled and toggle(key, false) or nil,
		tooltip = not cancelled and { e.title, grey(L["Clic para ver quién va."]) } or nil,
		buttons = not cancelled and signupButtons(e, mine) or nil,
	}
	if open then
		if e.note then line(rows, grey("\"" .. e.note .. "\""), 1) end
		signupRows(g, e, rows)
		if canManage then
			line(rows, grey(L["Herramientas de oficial"]), 2, { buttons = { { label = L["Cancelar evento"], onClick = function() ns.CancelEvent(e.id) end } } })
		end
		space(rows)
	end
end

local function warDayRow(rows, w)
	local enemy = ns.WarEnemy(w)
	local phase = ns.WarPhase(w)
	local status = phase == "active" and (RED .. L["EN CURSO"] .. R) or (phase == "pending" and grey(L["pendiente"]) or (phase == "finished" and grey(L["terminada"]) or ""))
	rows[#rows + 1] = {
		kind = "card",
		icon = "Interface\\Icons\\Ability_DualWield",
		iconColor = { 0.75, 0.18, 0.12 },
		title = (L["Guerra contra <%s>"]):format(enemy),
		desc = ("%s%s|r  ·  %s"):format(GOLD, date("%H:%M", w.start), ns.MapName(w.map, w.zone)),
		status = status,
		state = phase == "finished" and "off" or "normal", accent = phase == "active" and ns.ACCENT.active or nil,
		onClick = function() ns.ShowWars() end,
		tooltip = { (L["Guerra contra <%s>"]):format(enemy), grey(L["Clic: ver la guerra"]) },
	}
end

views.events = function()
	local g = LG:GuildData()
	if not g then return notInGuild() end
	local rows = {}
	local me = ns.PlayerFullName()
	local canManage = ns.Can("events", me)
	local upcoming, past = ns.EventLists()

	local eventButtons = {}
	-- Un día elegido en el calendario: el evento nuevo sale con esa fecha.
	local function selectedTime()
		local y, m, d = (calSelected or ""):match("^(%d+)-(%d+)-(%d+)$")
		return y and time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }) or nil
	end
	if canManage then eventButtons[#eventButtons + 1] = { label = L["Nuevo evento"], onClick = function() ns.ShowEventDialog(selectedTime()) end } end
	eventButtons[#eventButtons + 1] = ns.PublishButton("events")

	-- Calendario del mes.
	if not calMonth then
		local now = date("*t", ns.Now())
		calMonth = { year = now.year, month = now.month }
	end
	header(rows, L["Calendario"], eventButtons)
	rows[#rows + 1] = {
		kind = "calendar",
		year = calMonth.year, month = calMonth.month,
		days = monthData(g, calMonth.year, calMonth.month),
		selected = calSelected,
		signups = g.signups, me = me,
		onDay = function(day)
			local key = ("%04d-%02d-%02d"):format(calMonth.year, calMonth.month, day)
			calSelected = calSelected ~= key and key or nil
			refresh()
		end,
		-- Doble clic en un día: crear un evento ese día (oficiales).
		onDayDouble = canManage and function(day)
			calSelected = ("%04d-%02d-%02d"):format(calMonth.year, calMonth.month, day)
			refresh()
			ns.ShowEventDialog(time({ year = calMonth.year, month = calMonth.month, day = day, hour = 12 }))
		end or nil,
		onMonth = function(delta)
			local m = calMonth.month + delta
			calMonth = { year = calMonth.year + (m > 12 and 1 or (m < 1 and -1 or 0)), month = (m - 1) % 12 + 1 }
			refresh()
		end,
		onToday = function()
			local now = date("*t", ns.Now())
			calMonth = { year = now.year, month = now.month }
			calSelected = dayKey(ns.Now())
			refresh()
		end,
	}
	space(rows)

	-- Día elegido: sus eventos y guerras.
	if calSelected then
		local y, m, d = calSelected:match("^(%d+)-(%d+)-(%d+)$")
		local t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
		header(rows, dayLabel(t), { { label = L["Ver próximos"], onClick = function() calSelected = nil; refresh() end } })
		local any = false
		for _, w in pairs(ns.WARS_PAUSED and {} or g.wars) do
			local phase = ns.WarPhase(w)
			if dayKey(w.start) == calSelected and phase ~= "declined" and phase ~= "cancelled" and phase ~= "expired" then
				warDayRow(rows, w)
				any = true
			end
		end
		local dayEvents = {}
		for _, e in pairs(g.events) do
			if dayKey(e.start) == calSelected then dayEvents[#dayEvents + 1] = e end
		end
		table.sort(dayEvents, function(a, b) return a.start < b.start end)
		for _, e in ipairs(dayEvents) do
			eventRow(rows, g, e, me, canManage)
			any = true
		end
		if not any then line(rows, grey(L["Nada este día."]), 1) end
		return rows
	end

	header(rows, L["Próximos eventos"])
	if #upcoming == 0 then line(rows, grey(L["No hay eventos programados."]), 1) end
	for _, e in ipairs(upcoming) do eventRow(rows, g, e, me, canManage) end

	space(rows)
	header(rows, L["Eventos pasados"])
	if #past == 0 then line(rows, grey(L["Todavía no hay."]), 1) end
	for i = 1, math.min(10, #past) do
		local e = past[i]
		local attended = 0
		for _ in pairs(g.attendance[e.id] or {}) do attended = attended + 1 end
		local key = "past|" .. e.id
		local open = isOpen(key)
		line(rows, ("%s %s  %s  %s%d %s|r"):format(open and "[-]" or "[+]", grey(date("%d/%m", e.start)), e.title, GREEN, attended, L["asistentes"]), 1,
			{ onClick = toggle(key) })
		if open then signupRows(g, e, rows) end
	end
	space(rows)
	line(rows, grey(L["La asistencia se confirma sola si estás en grupo con la hermandad durante el evento (*)."]))
	return rows
end

---------------------------------------------------------------------------
-- Artesanía
---------------------------------------------------------------------------

-- Gremio elegido (línea de profesión) o nil = índice de gremios.
local guildFilter

-- Recetario por profesión: [skillLine][receta] = { name, out, crafters = { nombres } }
-- y artesanos: [skillLine] = { { name, m, rank, max, recipes } }.
local function guildCatalog(g)
	local catalog, crafters = {}, {}
	for name, m in pairs(g.members) do
		for skillLine, p in pairs(m.prof or {}) do
			local skill = tonumber(skillLine) or skillLine
			catalog[skill] = catalog[skill] or {}
			crafters[skill] = crafters[skill] or {}
			local count = 0
			for _, r in pairs(m.recipes or {}) do
				if r.name == p.name then
					for _, id in ipairs(r.ids or {}) do
						count = count + 1
						local c = catalog[skill][id]
						if not c then
							c = { id = id, name = ns.RecipeName(id), out = r.out and r.out[id], crafters = {} }
							catalog[skill][id] = c
						end
						c.out = c.out or (r.out and r.out[id])
						local catID = r.cat and r.cat[id]
						if catID and not c.category then
							c.category = r.catNames and r.catNames[catID]
							c.catOrder = r.catOrder and r.catOrder[catID] or 999
						end
						c.crafters[#c.crafters + 1] = name
					end
				end
			end
			table.insert(crafters[skill], { name = name, m = m, rank = p.rank or 0, max = p.max or 0, recipes = count })
		end
	end
	return catalog, crafters
end

-- Una receta del recetario: quién puede hacerla y los botones para pedirla.
local function recipeRow(rows, me, skill, c, indent)
	local icon, color = recipeIcon(c.id, c.out)
	local others = {}
	for _, n in ipairs(c.crafters) do
		if n ~= me then others[#others + 1] = n end
	end
	table.sort(others)
	local buttons = {}
	if #others > 0 then
		buttons[#buttons + 1] = { label = L["Pedir al gremio"], onClick = function() ns.ShowOrderDialog(nil, c.id, skill) end,
			tooltip = { L["Pedir al gremio"], L["Les llega a todos los que tienen esta receta; el primero que lo acepta se lo queda."] } }
		buttons[#buttons + 1] = { label = L["A un artesano"], onClick = function()
			ns.ShowInputDialog({
				title = c.name or "?",
				fields = { { key = "who", label = L["Artesano"], width = 200, default = ns.ShortName(others[1]),
					options = function()
						local items = {}
						for _, n in ipairs(others) do items[#items + 1] = ns.ShortName(n) end
						return { { items = items } }
					end } },
				submit = L["Siguiente"],
				onSubmit = function(v)
					for _, n in ipairs(others) do
						if ns.ShortName(n) == v.who or n == v.who then
							ns.ShowOrderDialog(n, c.id)
							return nil
						end
					end
					return L["Elige a uno de la lista."]
				end,
			})
		end }
	end
	local who = #c.crafters == 1 and ns.ShortName(c.crafters[1]) or (L["%d artesanos"]):format(#c.crafters)
	line(rows, (c.name or "?") .. "  " .. grey(who), indent or 1, {
		icon = icon, iconColor = color, link = c.out and ("item:" .. c.out) or nil,
		buttons = #buttons > 0 and buttons or nil,
	})
end

-- Mercado › Gremios: índice de profesiones; al pulsar una, su gremio (artesanos y recetario).
local function guildsView(g, rows)
	local me = ns.PlayerFullName()
	local query = (searchBox:GetText() or ""):lower()
	local searching = query ~= ""
	local catalog, crafters = guildCatalog(g)

	-- Búsqueda: recetas que coinciden (en el gremio elegido o en todos).
	if searching then
		header(rows, guildFilter and (L["Gremio de %s"]):format(ns.ProfessionName(guildFilter)) or L["Recetas"])
		local found = 0
		for skill, recipes in pairs(catalog) do
			if not guildFilter or skill == guildFilter then
				local list = {}
				for _, c in pairs(recipes) do
					if c.name and c.name:lower():find(query, 1, true) then list[#list + 1] = c end
				end
				table.sort(list, function(a, b) return a.name < b.name end)
				for _, c in ipairs(list) do
					recipeRow(rows, me, skill, c)
					found = found + 1
				end
			end
		end
		if found == 0 then line(rows, grey(L["Nadie en la hermandad tiene esa receta (o aún no ha abierto su profesión con el addon)."]), 1) end
		return
	end

	-- Índice: los gremios de la hermandad (pulsa uno para entrar).
	if not guildFilter then
		header(rows, L["Gremios de la hermandad"])
		local profs = ns.GuildProfessions()
		if #profs == 0 then line(rows, grey(L["Todavía no hay datos de profesiones."]), 1) end
		for _, p in ipairs(profs) do
			local nRecipes = 0
			for _ in pairs(catalog[p.skillLine] or {}) do nRecipes = nRecipes + 1 end
			rows[#rows + 1] = {
				kind = "card", state = (p.addon > 0) and "normal" or "off",
				icon = p.icon,
				title = p.name or "?",
				desc = (p.players and ((L["%d en la hermandad"]):format(p.players) .. "  ·  ") or "") .. (L["%d con el addon"]):format(p.addon),
				status = nRecipes > 0 and (GOLD .. (L["%d recetas"]):format(nRecipes) .. R) or nil,
				foot = p.best > 0 and grey((L["mejor: %d (%s)"]):format(p.best, ns.ShortName(p.bestName) or "?")) or nil,
				onClick = p.addon > 0 and function() guildFilter = p.skillLine; refresh() end or nil,
				tooltip = p.addon > 0 and { p.name, grey(L["Clic para ver sus artesanos y su recetario."]) } or nil,
			}
		end
		space(rows)
		line(rows, grey(L["Las recetas se registran al abrir la ventana de cada profesión."]))
		return
	end

	-- Un gremio: artesanos (por nivel) y recetario.
	local list = crafters[guildFilter] or {}
	table.sort(list, function(a, b) return a.rank > b.rank end)
	header(rows, (L["Gremio de %s"]):format(ns.ProfessionName(guildFilter)), { { label = L["Volver"], onClick = function() guildFilter = nil; refresh() end } })
	for _, c in ipairs(list) do
		rows[#rows + 1] = portraitFields(c.name, c.m.class, { indent = 1, tall = true,
			cols = { { ns.ClassColorName(c.name, c.m.class), 200 }, { GOLD .. ("%d/%d"):format(c.rank, c.max) .. R, 90 },
				{ grey(c.recipes == 1 and L["1 receta"] or (L["%d recetas"]):format(c.recipes)), 120 } } })
	end
	space(rows)
	header(rows, L["Recetario del gremio"])
	local groups, order = {}, {}
	for _, c in pairs(catalog[guildFilter] or {}) do
		local name = c.category or L["Otras recetas"]
		if not groups[name] then
			groups[name] = { name = name, order = c.category and (c.catOrder or 999) or 10000, list = {} }
			order[#order + 1] = groups[name]
		end
		if c.category and (c.catOrder or 999) < groups[name].order then groups[name].order = c.catOrder end
		table.insert(groups[name].list, c)
	end
	table.sort(order, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.name < b.name
	end)
	if #order == 0 then line(rows, grey(L["Sin recetas registradas: tiene que abrir esta profesión con el addon."]), 1) end
	for _, grp in ipairs(order) do
		table.sort(grp.list, function(a, b) return (a.name or "") < (b.name or "") end)
		-- Cada categoría con su desplegable (abiertas al principio).
		local key = "cat|" .. tostring(guildFilter) .. "|" .. grp.name
		local open = isOpen(key, true)
		line(rows, ("%s %s%s|r  %s"):format(open and "[-]" or "[+]", GOLD, grp.name, grey(("(%d)"):format(#grp.list))), 1, { onClick = toggle(key, true) })
		if open then
			for _, c in ipairs(grp.list) do recipeRow(rows, me, guildFilter, c, 2) end
		end
	end
end

local function ordersView(g, rows)
	local me = ns.PlayerFullName()
	local roles = ns.OrdersByRole()
	header(rows, L["Me piden a mí"])
	if #roles.forMe == 0 then line(rows, grey(L["Nada por ahora."]), 1) end
	for _, o in ipairs(roles.forMe) do
		local who = (L["lo pide %s"]):format(ns.ShortName(o.requester))
		if o.guild and o.status == "open" then who = who .. "  ·  " .. GOLD .. L["para tu gremio"] .. R end
		rows[#rows + 1] = orderRow(o, who, orderButtons(o, me))
	end
	space(rows)
	header(rows, L["Mis pedidos"])
	if #roles.mine == 0 then line(rows, grey(L["Pide desde Recetas: busca lo que necesitas y pulsa Pedir."]), 1) end
	for _, o in ipairs(roles.mine) do
		local who = o.crafter and (L["lo hace %s"]):format(ns.ShortName(o.crafter)) or grey(L["esperando a que alguien del gremio lo acepte"])
		rows[#rows + 1] = orderRow(o, who, orderButtons(o, me))
	end
	space(rows)
	header(rows, L["Resto de la hermandad"])
	if #roles.others == 0 then line(rows, grey(L["Nada por ahora."]), 1) end
	-- En curso de otros, en tarjeta; los terminados, en una lista compacta.
	local shown = 0
	for _, o in ipairs(roles.others) do
		if o.status == "open" or o.status == "accepted" then
			rows[#rows + 1] = orderRow(o, o.crafter and (L["%s se lo pide a %s"]):format(ns.ShortName(o.requester), ns.ShortName(o.crafter))
				or (L["%s lo pide al gremio"]):format(ns.ShortName(o.requester)))
		elseif shown < 10 then
			shown = shown + 1
			orderLine(rows, o)
		end
	end
	space(rows)
	line(rows, grey(L["La entrega se marca sola al pasar el objeto por la ventana de intercambio."]))
end

local function showBidDialog(g, a)
	local minimum = ns.MinNextBid(g, a)
	ns.ShowInputDialog({
		title = (L["Pujar por %s"]):format(a.link),
		submit = L["Pujar"],
		fields = { { key = "amount", label = (L["Insignias (libres: %d)"]):format(ns.AvailableInsignias(a.id)), width = 70, numeric = true, default = minimum } },
		onSubmit = function(v)
			local ok, err = ns.PlaceBid(a.id, v.amount)
			if not ok then return err end
		end,
	})
end

-- Situación de tu puja en una subasta abierta, para Mercado e Inicio.
local function myBidState(g, a, me)
	local top = ns.AuctionTop(g, a)
	local mine = g.bids[a.id] and g.bids[a.id][me]
	if top and top.member == me then return GREEN .. L["vas ganando"] .. R, top end
	if mine then return RED .. L["te han superado"] .. R, top end
	return nil, top
end

function auctionRow(g, a, me, canManage)
	local now = ns.Now()
	local state, top = myBidState(g, a, me)
	local bidText = top and ("%s%d|r %s"):format(GOLD, top.amount, grey(L["de"] .. " " .. ns.ShortName(top.member)))
		or grey((L["sin pujas · mín. %d"]):format(a.min))
	-- El vendedor no puja en lo suyo; la cierra él o un oficial, y solo un oficial la cancela con pujas.
	local seller = a.creator == me and not a.bank
	local buttons = {}
	if not seller then buttons[#buttons + 1] = { label = L["Pujar"], onClick = function() showBidDialog(g, a) end } end
	if seller or canManage then
		buttons[#buttons + 1] = { label = L["Cerrar"], onClick = function() ns.FinishAuction(a.id) end }
		if canManage or not top then
			buttons[#buttons + 1] = { label = L["Cancelar"], onClick = function() ns.FinishAuction(a.id, true) end }
		end
	end
	-- Tarjeta: el objeto (con su descripción al pasar el ratón), la puja que va
	-- ganando, el tiempo que queda y tu situación.
	local winning = top and top.member == me
	return {
		kind = "card",
		state = "normal", accent = winning and ns.ACCENT.good or nil,
		link = a.link,
		icon = itemIcon(a.itemID) or "Interface\\Icons\\INV_Misc_QuestionMark",
		iconColor = qualityColor(a.itemID),
		title = a.link or "?",
		desc = bidText,
		status = state or (seller and (GOLD .. L["la tuya"] .. R) or nil),
		foot = grey((a.bank and L["Banco de la hermandad"] or (L["vende %s"]):format(ns.ShortName(a.creator) or "?"))
			.. "  ·  " .. (L["termina en %s"]):format(ns.FormatDuration(ns.AuctionEnds(g, a) - now))),
		buttons = #buttons > 0 and buttons or nil,
	}
end

local function auctionView(g, rows)
	local me = ns.PlayerFullName()
	local canManage = ns.CanManageEvents(me)
	local open, finished = ns.AuctionLists()
	local s = ns.Scores()[me]

	header(rows, L["Subastas abiertas"], { { label = L["Subastar algo"], onClick = function() ns.ShowAuctionStart() end } })
	-- Filtro por tipo de objeto (se guarda con las subvistas para no gastar otra variable local).
	local filter = subview.auctionType or "all"
	local buttons = {}
	for _, f in ipairs(ns.AUCTION_TYPES) do
		buttons[#buttons + 1] = { label = (f.key == filter and "|cffffffff" or "") .. f.label .. (f.key == filter and R or ""),
			onClick = function() subview.auctionType = f.key; refresh() end }
	end
	line(rows, grey(L["Ver:"]), 1, { buttons = buttons })
	local shownOpen = {}
	for _, a in ipairs(open) do
		if filter == "all" or ns.AuctionType(a.itemID) == filter then shownOpen[#shownOpen + 1] = a end
	end
	open = shownOpen
	line(rows, grey((L["Tienes %d insignias; %d libres para pujar (las que vas ganando quedan reservadas)."]):format(
		s and s.merits or 0, ns.AvailableInsignias(nil))), 1)
	if #open == 0 then
		line(rows, grey(canManage and L["No hay subastas abiertas. Pon un objeto con \"Nueva subasta\"."] or L["No hay subastas abiertas."]), 1)
	end
	for _, a in ipairs(open) do rows[#rows + 1] = auctionRow(g, a, me, canManage) end

	space(rows)
	header(rows, L["Terminadas"])
	if #finished == 0 then line(rows, grey(L["Todavía no hay."]), 1) end
	for i = 1, math.min(10, #finished) do
		local a = finished[i]
		local desc, status
		if a.status == "cancelled" then
			desc, status = grey(L["cancelada"]), nil
		elseif a.winner then
			local m = g.members[a.winner]
			desc = ("%s %s %s%d|r %s"):format(ns.ClassColorName(a.winner, m and m.class), L["por"], GOLD, a.amount or 0, L["insignias"])
			status = a.delivered and (GREEN .. L["entregado"] .. R) or (GOLD .. L["pendiente de entregar"] .. R)
		else
			desc = grey(L["sin pujas"])
		end
		rows[#rows + 1] = {
			kind = "card",
			state = (a.winner and a.status ~= "cancelled") and "normal" or "off",
			link = a.link,
			icon = itemIcon(a.itemID) or "Interface\\Icons\\INV_Misc_QuestionMark",
			iconColor = qualityColor(a.itemID),
			title = a.link or "?",
			desc = desc,
			status = status,
			foot = grey(date("%d/%m", a.ends or a.created or 0)),
			buttons = (canManage and a.status == "closed" and a.winner and not a.delivered)
				and { { label = L["Entregado"], onClick = function() ns.MarkAuctionDelivered(a.id) end } } or nil,
		}
	end
	space(rows)
	line(rows, grey(L["Solo insignias, nunca oro. Quien vende entrega el objeto por intercambio y se marca solo. Una puja en los últimos 2 minutos alarga la subasta."]))
end

-- Hermandad › Cofre: saldo, proyectos (activos, listos, reuniendo), catálogo y movimientos.
local chestUI = {} -- funciones del cofre en una tabla (MainFrame va justo de variables locales)
function chestUI.donate(projectID, title)
	local remaining = projectID and ns.ProjectRemaining(projectID)
	ns.ShowInputDialog({
		title = projectID and (L["Aportar a %s"]):format(title) or L["Donar al cofre"],
		text = (L["Tienes %d insignias libres."]):format(ns.DonatableInsignias())
			.. (remaining and ("  " .. (L["Le faltan %d."]):format(remaining)) or ""),
		submit = L["Donar"],
		fields = { { key = "amount", label = L["Insignias"], width = 80, numeric = true,
			default = remaining and math.min(remaining, ns.DonatableInsignias()) or 10 } },
		onSubmit = function(v)
			local ok, err = ns.Donate(v.amount, projectID)
			if not ok then return err end
		end,
	})
end

function chestUI.fund(projectID, title)
	local remaining = ns.ProjectRemaining(projectID) or 0
	local balance = ns.ChestState().balance
	ns.ShowInputDialog({
		title = (L["Del cofre a %s"]):format(title),
		text = (L["En el cofre hay %d insignias. Al proyecto le faltan %d."]):format(balance, remaining),
		submit = L["Pasar"],
		fields = { { key = "amount", label = L["Insignias"], width = 80, numeric = true, default = math.min(balance, remaining) } },
		onSubmit = function(v)
			local ok, err = ns.FundProject(projectID, v.amount)
			if not ok then return err end
		end,
	})
end

function chestUI.duration(days)
	return days == 1 and L["1 día"] or (L["%d días"]):format(days)
end

-- Tarjeta de un proyecto según su fase.
function chestUI.card(rows, item, canManage)
	local p, kind = item.p, ns.ProjectKind(item.p.kind)
	local title = kind.label
	local row = { kind = "card", state = "normal", icon = kind.icon, title = title, desc = grey(kind.desc),
		tooltip = { title, kind.desc, grey((L["Dura %s desde que se activa."]):format(chestUI.duration(kind.days))) } }
	if item.phase == "active" then
		row.accent = ns.ACCENT.good
		row.status = GREEN .. (L["activo: %s"]):format(ns.FormatDuration(ns.ProjectEnds(p) - ns.Now())) .. R
		row.foot = grey((L["Activado por %s el %s"]):format(ns.ShortName(p.by), date("%d/%m %H:%M", p.activatedAt)))
	elseif item.phase == "ready" then
		row.accent = ns.ACCENT.action
		row.status = GOLD .. L["listo para activar"] .. R
		row.foot = grey((L["Completado el %s  ·  dura %s"]):format(date("%d/%m", item.doneAt), chestUI.duration(kind.days)))
		row.buttons = canManage and { { label = L["Activar"], onClick = function() ns.ActivateProject(p.id) end } } or nil
	else
		row.accent = ns.ACCENT.active
		row.status = GOLD .. ("%d / %d"):format(item.funded, p.goal) .. R
		row.foot = grey((L["Abierto por %s  ·  dura %s"]):format(ns.ShortName(p.creator), chestUI.duration(kind.days)))
		row.buttons = { { label = L["Aportar"], onClick = function() chestUI.donate(p.id, title) end } }
		if canManage then
			row.buttons[#row.buttons + 1] = { label = L["Del cofre"], onClick = function() chestUI.fund(p.id, title) end }
			row.buttons[#row.buttons + 1] = { label = L["Cancelar"], onClick = function() ns.CancelProject(p.id) end }
		end
	end
	rows[#rows + 1] = row
	if item.phase == "open" then
		rows[#rows + 1] = { kind = "bar", indent = 1, label = L["Reunido"], value = item.funded, max = p.goal,
			text = ("%d%%"):format(math.floor(item.funded * 100 / p.goal)) }
	end
end

function chestUI.view(g, rows)
	local me = ns.PlayerFullName()
	local canManage = ns.Can("projects", me)
	local state = ns.ChestState()
	local lists = ns.ProjectLists()

	header(rows, L["Cofre de la hermandad"], { { label = L["Donar"], onClick = function() chestUI.donate() end } })
	rows[#rows + 1] = {
		kind = "card", state = "normal", accent = state.balance > 0 and ns.ACCENT.action or nil,
		icon = "Interface\\Icons\\INV_Box_02",
		title = (L["%s%d|r insignias en el cofre"]):format(GOLD, state.balance),
		desc = grey((L["Donaciones: %d  ·  De las subastas: %d  ·  Invertido en proyectos: %d"]):format(state.donated, state.auctions, state.spent)),
		foot = grey((L["Tienes %d insignias libres."]):format(ns.DonatableInsignias())),
	}
	line(rows, grey(L["Se llena con donaciones, el 10 % de cada subasta, la bajada semanal de las insignias y los precios por cabezas que nadie cobra. Los oficiales lo invierten en proyectos."]), 1)

	local current = #lists.active + #lists.ready + #lists.open
	if current > 0 then
		space(rows)
		header(rows, L["Proyectos"])
		for _, phase in ipairs({ "active", "ready", "open" }) do
			for _, item in ipairs(lists[phase]) do chestUI.card(rows, item, canManage) end
		end
	end

	-- Mayores donantes: lo que cada uno ha aportado al cofre y a sus proyectos.
	local donors = ns.ChestDonors()
	if #donors > 0 then
		space(rows)
		header(rows, L["Mayores donantes"])
		for i = 1, math.min(5, #donors) do
			local d = donors[i]
			local m = g.members[d.name] or ns.roster[d.name]
			line(rows, ("%s  %s  %s%d|r %s  %s"):format(GOLD .. i .. "." .. R, ns.ClassColorName(d.name, m and m.class), GOLD, d.total, L["insignias"],
				grey((L["%d en los últimos 30 días"]):format(d.month))), 1)
		end
	end

	-- Banco de la hermandad del juego: quién aporta (lo leen los registros al abrir el banco).
	local bankDonors = ns.BankDonors()
	space(rows)
	header(rows, L["Banco de la hermandad"])
	if #bankDonors == 0 then
		line(rows, grey(L["Todavía no hay aportaciones registradas. Se apuntan cuando alguien con el addon abre el banco (solo de quien comparte sus datos)."]), 1)
	end
	for i = 1, math.min(5, #bankDonors) do
		local d = bankDonors[i]
		local m = g.members[d.name] or ns.roster[d.name]
		line(rows, ("%s  %s  %s  %s"):format(GOLD .. i .. "." .. R, ns.ClassColorName(d.name, m and m.class),
			d.gold > 0 and ns.MoneyText(d.gold) or "", d.items > 0 and grey((L["%d objetos"]):format(d.items)) or ""), 1)
	end
	if #bankDonors > 0 then
		for _, d in ipairs(ns.BankRecent(5)) do
			line(rows, grey(date("%d/%m %H:00", d.t)) .. "  " .. ns.ShortName(d.member) .. "  "
				.. (d.kind == "money" and ns.MoneyText(d.amount) or ((d.link or "?") .. (d.amount > 1 and (" x" .. d.amount) or ""))), 2)
		end
	end
	line(rows, grey((L["El oro da reputación (lo neto de la semana, hasta %d), nunca insignias. Los objetos solo cuentan si los pide un pedido."]):format(ns.BANK_REP.weekCap)), 1)

	-- Pedidos del banco: lo que la hermandad necesita, con su recompensa del cofre.
	space(rows)
	local canRequest = ns.CanRequestBank(me)
	header(rows, L["Pedidos del banco"], canRequest and { { label = L["Nuevo pedido"], onClick = function()
		ns.ShowInputDialog({
			title = L["Nuevo pedido del banco"],
			text = (L["Quien deposite ese objeto en los próximos %d días cobra su parte de la recompensa, que sale del cofre (%d insignias libres). Mayúsculas + clic en un objeto lo pone en el campo."]):format(
				ns.BANK_REQUEST.days, math.max(0, ns.ChestState().balance - ns.BankRequestsReserved())),
			submit = L["Pedir"],
			fields = {
				{ key = "item", label = L["Objeto"], width = 260 },
				{ key = "qty", label = L["Cantidad"], width = 70, numeric = true, default = 20 },
				{ key = "reward", label = L["Recompensa (insignias)"], width = 70, numeric = true, default = 20 },
			},
			onSubmit = function(v)
				local ok, err = ns.CreateBankRequest(v.item, v.qty, v.reward)
				if not ok then return err end
			end,
		})
	end } } or nil)
	local openReqs, closedReqs = ns.BankRequestLists()
	if #openReqs == 0 then line(rows, grey(L["Ningún pedido abierto."]), 1) end
	for _, item in ipairs(openReqs) do
		local r = item.r
		local canCancel = r.creator == me or ns.Can("bankRequests", me)
		rows[#rows + 1] = {
			kind = "card", state = "normal", accent = ns.ACCENT.action, link = r.link,
			icon = itemIcon(r.item) or "Interface\\Icons\\INV_Misc_QuestionMark", iconColor = qualityColor(r.item),
			title = r.link or "?",
			desc = (L["%d de %d entregados"]):format(item.delivered, r.qty),
			status = GOLD .. (L["%d insignias"]):format(r.reward) .. R,
			foot = grey((L["pedido por %s  ·  caduca en %s"]):format(ns.ShortName(r.creator), ns.FormatDuration(r.ends - ns.Now()))),
			buttons = canCancel and { { label = L["Cancelar"], onClick = function() ns.CancelBankRequest(r.id) end } } or nil,
		}
		rows[#rows + 1] = { kind = "bar", indent = 1, label = L["Entregado"], value = item.delivered, max = r.qty,
			text = ("%d / %d"):format(item.delivered, r.qty) }
	end
	for i = 1, math.min(3, #closedReqs) do
		local item = closedReqs[i]
		local label = item.phase == "done" and (GREEN .. L["completado"] .. R) or grey(item.phase == "cancelled" and L["cancelado"] or L["caducado"])
		line(rows, ("%s  %s  %d/%d  %s"):format(item.r.link or "?", label, item.delivered, item.r.qty, grey(ns.ShortName(item.r.creator))), 1)
	end

	-- Catálogo: los tipos que se pueden abrir (uno de cada a la vez).
	space(rows)
	header(rows, L["Catálogo de proyectos"])
	for _, kind in ipairs(ns.PROJECT_KINDS) do
		local busy = ns.ProjectOfKind(kind.key)
		local last
		for _, item in ipairs(lists.ended) do
			if item.p.kind == kind.key then last = item break end
		end
		rows[#rows + 1] = {
			kind = "card", state = busy and "off" or "normal",
			icon = kind.icon, title = kind.label, desc = grey(kind.desc),
			status = GOLD .. (L["%d insignias"]):format(kind.goal) .. R,
			foot = grey(chestUI.duration(kind.days) .. (busy and ("  ·  " .. L["en curso"]) or "")
				.. (last and ("  ·  " .. (L["último: %s"]):format(date("%d/%m", last.p.activatedAt))) or "")),
			buttons = (canManage and not busy) and { { label = L["Abrir proyecto"], onClick = function() ns.CreateProject(kind.key) end } } or nil,
		}
	end
	if not canManage then line(rows, grey(L["Los proyectos los abren y activan los oficiales; todos pueden aportar."]), 1) end

	space(rows)
	header(rows, L["Movimientos"])
	if #state.log == 0 then line(rows, grey(L["Todavía no hay."]), 1) end
	for _, e in ipairs(state.log) do
		local p = e.project and g.projects[e.project]
		local pTitle = p and ns.ProjectTitle(p) or "?"
		local m = e.member and (g.members[e.member] or ns.roster[e.member])
		local who = e.member and ns.ClassColorName(e.member, m and m.class) or "?"
		local what
		if e.kind == "auction" then
			what = (L["10 %% de la subasta que ganó %s"]):format(who)
		elseif e.kind == "bounty" then
			what = L["Precio por una cabeza que nadie cobró"]
		elseif e.kind == "decay" then
			what = L["Bajada semanal de las insignias (5 %)"]
		elseif e.kind == "request" then
			what = (L["Recompensa de un pedido del banco para %s"]):format(who)
		elseif e.kind == "move" then
			what = (L["%s lo pasa del cofre a %s"]):format(who, pTitle)
		elseif p then
			what = (L["%s aporta a %s"]):format(who, pTitle)
		else
			what = (L["%s dona al cofre"]):format(who)
		end
		local sign = (e.kind == "move" or e.kind == "request") and "|cffff6b5a-" or (GREEN .. "+")
		if e.kind == "donate" and p and not e.overflow then sign = "|cff9d9d9d" end
		line(rows, ("%s  %s%d|r  %s"):format(grey(date("%d/%m %H:%M", e.t)), sign, e.merits, what), 1)
	end
	if #lists.cancelled > 0 then
		space(rows)
		line(rows, grey((L["Proyectos cancelados: %d (lo reunido volvió al cofre)."]):format(#lists.cancelled)), 1)
	end
end

-- Mercado › Tienda: cosméticos del perfil (comprar y usar) y las tasas de las tribus.
local shopUI = {} -- en una tabla: MainFrame va justo de variables locales
function shopUI.view(g, rows)
	local me = ns.PlayerFullName()
	local profile = ns.MemberProfile(me)
	header(rows, L["Tienda"], { { label = L["Ver mi perfil"], onClick = function() ns.ToggleProfile() end } })
	line(rows, grey((L["Tienes %d insignias libres. Lo que compras aquí se queda para siempre (las insignias, no: se gastan)."]):format(ns.AvailableInsignias(nil))), 1)
	local sections = {
		{ kind = "frame", title = L["Marcos del perfil"], current = profile.frame and profile.frame.key },
		{ kind = "velvet", title = L["Terciopelo del estuche"], current = profile.velvet and profile.velvet.key },
	}
	for _, sec in ipairs(sections) do
		space(rows)
		header(rows, sec.title, sec.current and { { label = L["Quitar"], onClick = function() ns.UseCosmetic(sec.kind, nil) end } } or nil)
		for _, item in ipairs(ns.SHOP_ITEMS) do
			if item.kind == sec.kind then
				local owns = ns.Owns(me, item.key)
				local inUse = sec.current == item.key
				local button
				if not owns then
					button = { label = L["Comprar"], onClick = function()
						local ok, err = ns.Buy(item.key)
						if not ok then LG:Print(err) end
					end }
				elseif not inUse then
					button = { label = L["Usar"], onClick = function() ns.UseCosmetic(sec.kind, item.key) end }
				end
				rows[#rows + 1] = {
					kind = "card", state = (owns or ns.AvailableInsignias(nil) >= item.price) and "normal" or "off",
					accent = inUse and ns.ACCENT.good or (owns and ns.ACCENT.mine or nil),
					icon = item.icon,
					title = item.label, desc = grey(item.desc),
					status = inUse and (GREEN .. L["en uso"] .. R) or (owns and grey(L["comprado"]) or (GOLD .. (L["%d insignias"]):format(item.price) .. R)),
					buttons = button and { button } or nil,
				}
			end
		end
	end
	space(rows)
	header(rows, L["Tasas"])
	for _, item in ipairs(ns.SHOP_ITEMS) do
		if item.kind == "fee" then
			line(rows, ("|T%s:16|t  %s  %s%d|r  %s"):format(item.icon, item.label, GOLD, item.price, grey(item.desc)), 1)
		end
	end
end

views.market = function()
	local g = LG:GuildData()
	if not g then return notInGuild() end
	local rows = {}
	local pending = 0
	for _, o in ipairs(ns.OrdersByRole().forMe) do
		if o.status == "open" then pending = pending + 1 end
	end
	local openAuctions = ns.AuctionLists()
	segments(rows, "market", {
		{ key = "auction", label = #openAuctions > 0 and (L["Subasta"] .. " (" .. #openAuctions .. ")") or L["Subasta"] },
		{ key = "recipes", label = L["Gremios"] },
		{ key = "orders", label = pending > 0 and (L["Encargos"] .. " (" .. pending .. ")") or L["Encargos"] },
		{ key = "shop", label = L["Tienda"] },
	})
	if subview.market == "orders" then
		ordersView(g, rows)
	elseif subview.market == "shop" then
		shopUI.view(g, rows)
	elseif subview.market == "recipes" then
		guildsView(g, rows)
	else
		auctionView(g, rows)
	end
	rows.search = subview.market == "recipes" and L["Buscar receta..."] or nil
	if subview.market ~= "recipes" then guildFilter = nil end -- al volver a Gremios, el índice
	return rows
end

---------------------------------------------------------------------------
-- Caza
---------------------------------------------------------------------------

local function targetsView(g, rows)
	local canManage = ns.CanManageEvents(ns.PlayerFullName())
	local s = ns.HuntStats(7)

	-- Hermandades objetivo: cartel con calavera, cuántas veces nos han matado y la recompensa.
	header(rows, L["Objetivos de caza"], { ns.PublishButton("hunt") })
	local targets = {}
	for guild, how in pairs(ns.TargetGuilds()) do targets[#targets + 1] = { guild = guild, how = how } end
	table.sort(targets, function(a, b) return (s.killedBy[a.guild] or 0) > (s.killedBy[b.guild] or 0) end)
	if #targets == 0 then line(rows, grey(L["Ninguno. Salen solos cuando una hermandad nos mata, o los añade un oficial."]), 1) end
	local enemyFaction = (UnitFactionGroup("player") == "Alliance") and "Horde" or "Alliance"
	for _, t in ipairs(targets) do
		local deaths = s.killedBy[t.guild] or 0
		local entry = ns.DirectoryEntry(t.guild)
		local danger = s.dangerous[t.guild]
		local foot = {}
		if danger and danger.name then
			foot[#foot + 1] = (L["Más peligroso: %s (%d)"]):format(ns.ShortName(danger.name), danger.n)
		end
		foot[#foot + 1] = t.how == "manual" and L["puesta por un oficial"] or L["objetivo automático (nos mata a menudo)"]
		rows[#rows + 1] = {
			kind = "card", state = "normal", accent = { 0.85, 0.2, 0.12 },
			icon = ns.FactionBanner(entry and entry.faction or enemyFaction),
			title = RED .. "<" .. t.guild .. ">" .. R,
			desc = (deaths == 1 and L["nos ha matado 1 vez"] or (L["nos ha matado %d veces"]):format(deaths))
				.. "  ·  " .. GREEN .. (L["%d cazados"]):format(s.hunted[t.guild] or 0) .. R,
			status = GOLD .. L["10 insignias"] .. R,
			foot = grey(table.concat(foot, "  ·  ")),
			buttons = (canManage and t.how == "manual") and { { label = L["Quitar"], onClick = function() ns.ToggleTarget(t.guild) end } } or nil,
		}
	end
	line(rows, grey(L["Kills honorables · misma víctima: 2 al día (la 3.ª a la mitad) · +5 por venganza · tope 100 al día"]), 1)

	-- Nos cazan: hermandades que nos matan y no son objetivo, con el mismo cartel
	-- que los objetivos pero más discreto y el botón para hacerlas objetivo.
	local hunters7 = {}
	for _, e in ipairs(sortedCounts(s.killedBy, 20)) do
		if not ns.TargetGuilds()[e.key] and #hunters7 < 6 then hunters7[#hunters7 + 1] = e end
	end
	if #hunters7 > 0 then
		space(rows)
		header(rows, L["Nos cazan (7 días)"])
	end
	for _, e in ipairs(hunters7) do
		local loose = e.key == ns.NO_GUILD -- jugadores sueltos: ni estandarte ni objetivo
		local entry = not loose and ns.DirectoryEntry(e.key)
		local danger = s.dangerous[e.key]
		rows[#rows + 1] = {
			kind = "card", state = "normal", accent = { 0.55, 0.3, 0.2 },
			icon = loose and ICON_SKULL or ns.FactionBanner(entry and entry.faction or enemyFaction),
			title = loose and grey(ns.NO_GUILD) or (RED .. "<" .. e.key .. ">" .. R),
			desc = (e.n == 1 and L["nos ha matado 1 vez"] or (L["nos ha matado %d veces"]):format(e.n))
				.. "  ·  " .. GREEN .. (L["%d cazados"]):format(s.hunted[e.key] or 0) .. R,
			foot = danger and danger.name and grey((L["Más peligroso: %s (%d)"]):format(ns.ShortName(danger.name), danger.n)) or nil,
			buttons = (canManage and not loose) and { { label = L["Objetivo"], onClick = function() ns.ToggleTarget(e.key) end } } or nil,
		}
	end

	-- Cazadores de la semana: puesto, retrato, kills y venganzas.
	local since = ns.Now() - 7 * 86400
	local revenges = {}
	for _, k in ipairs(s.recent) do
		if k.kind == "kill" and k.revenge and k.t >= since then revenges[k.killerName] = (revenges[k.killerName] or 0) + 1 end
	end
	space(rows)
	header(rows, L["Cazadores de la semana"])
	local hunters = sortedCounts(s.hunters, 5)
	if #hunters == 0 then line(rows, grey(L["Nadie todavía."]), 1) end
	for i, e in ipairs(hunters) do
		local m = g.members[e.key]
		local medal = i == 1 and GOLD or (i <= 3 and "|cffc0c0c0" or GREY)
		rows[#rows + 1] = portraitFields(e.key, m and m.class, {
			indent = 1,
			tall = true,
			iconOffset = 30,
			cols = { { medal .. ("%d."):format(i) .. R, 30 }, { ns.ClassColorName(e.key, m and m.class), 200 },
				{ GREEN .. (e.n == 1 and L["1 kill"] or (L["%d kills"]):format(e.n)) .. R, 90 },
				{ revenges[e.key] and (GOLD .. (revenges[e.key] == 1 and L["1 venganza"] or (L["%d venganzas"]):format(revenges[e.key])) .. R) or "", 110 } },
		})
	end

	-- Últimas kills y muertes: verde cuando cazamos, rojo cuando nos matan, agrupadas por día.
	-- El rival va en grande (con el emblema de su clase); zona y honor, al pasar el ratón.
	space(rows)
	header(rows, L["Últimas kills y muertes"])
	if #s.recent == 0 then line(rows, grey(L["Todavía no hay registros."]), 1) end
	local lastDay
	for i = 1, math.min(25, #s.recent) do
		local k = s.recent[i]
		local day = dayLabel(k.t)
		if day ~= lastDay then
			lastDay = day
			line(rows, GOLD .. day .. R, 1)
		end
		local isKill = k.kind == "kill"
		local opponent = isKill and k.victimName or k.killerName
		local ours = isKill and k.killerName or k.victimName
		local guild = k.guild and (RED .. "  <" .. k.guild .. ">" .. R) or grey("  " .. ns.NO_GUILD)

		local tooltip = { (isKill and (GREEN .. L["Caza"] .. R) or (RED .. L["Caído"] .. R)) .. "  " .. (k.zone or "?") }
		if isKill and k.honorable then tooltip[#tooltip + 1] = (L["Honor: +%d"]):format(k.honor or 0) end
		if k.revenge then tooltip[#tooltip + 1] = GOLD .. (L["Venganza por %s"]):format(ns.ShortName(k.avenged) or "?") .. R end
		for _, a in ipairs(k.assists or {}) do
			tooltip[#tooltip + 1] = (L["También pegó: %s %s"]):format(ns.ShortName(a.name) or "?", a.guild and ("<" .. a.guild .. ">") or "")
		end

		local fields = portraitFields(opponent, k.class, {
			indent = 1,
			tall = true,
			tint = (isKill and k.revenge) and { 1, 0.75, 0.1 } or (isKill and { 0.2, 0.85, 0.25 } or { 0.9, 0.2, 0.15 }),
			tintAlpha = 0.05, -- franja de color a la izquierda y un fondo apenas teñido
			tooltip = tooltip,
			-- Las venganzas llevan su propia etiqueta dorada en lugar de CAZA.
			cols = {
				{ grey(date("%H:%M", k.t)), 40 },
				{ (isKill and k.revenge) and (GOLD .. L["VENGANZA"] .. R) or (isKill and (GREEN .. L["CAZA"] .. R) or (RED .. L["CAÍDO"] .. R)), 92 },
				{ ns.ClassColorName(opponent, k.class) .. guild, 280 },
				{ grey((isKill and L["por %s"] or L["a %s"]):format(ns.ShortName(ours) or "?")), 190 },
			},
		})
		-- Sin clase conocida: espadas si cazamos, calavera si nos mataron (no el interrogante).
		if fields.icon == "Interface\\Icons\\INV_Misc_QuestionMark" then
			fields.icon = isKill and "Interface\\Icons\\Ability_DualWield" or "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
		end
		rows[#rows + 1] = fields
	end
end

---------------------------------------------------------------------------
-- JcJ > Guerras: vitrina, guerras en curso, pendientes e historial
---------------------------------------------------------------------------

local ICON_WAR = "Interface\\Icons\\Ability_DualWield"

local function minutesLeft(t)
	local m = math.max(0, math.ceil((t - ns.Now()) / 60))
	return m >= 60 and (L["%d h %d min"]):format(math.floor(m / 60), m % 60) or (L["%d min"]):format(m)
end

local function showCode(id)
	local code = ns.WarCode(id)
	if not code then return end
	ns.ShowInputDialog({
		title = L["Código de la guerra"],
		text = L["Cópialo (Ctrl+C) y pásaselo al maestro de la otra hermandad, por ejemplo por Discord. Solo hace falta si no os llegan los mensajes del addon."],
		fields = { { key = "code", label = L["Código"], width = 230, default = code } },
		submit = CLOSE or L["Cerrar"],
		highlight = true,
		onSubmit = function() return nil end,
	})
end

function ns.ShowPasteWarCode(text)
	if text and text ~= "" then
		local err = ns.ApplyWarCode(text)
		if err then LG:Print(err) end
		return
	end
	ns.ShowInputDialog({
		title = L["Pegar código de guerra"],
		text = L["Pega (Ctrl+V) el código que te ha pasado la otra hermandad."],
		fields = { { key = "code", label = L["Código"], width = 230 } },
		submit = L["Aplicar"],
		onSubmit = function(v) return ns.ApplyWarCode(v.code) end,
	})
end

function ns.ShowDeclareWarDialog(enemy)
	local zone = GetZoneText and GetZoneText() or ""
	local nextHour = time() + 3600
	ns.ShowInputDialog({
		title = L["Declarar la guerra"],
		text = L["Cuentan todas las kills y muertes de la zona. Escribe su nombre (vale un trozo, sin tildes). La otra hermandad tiene que aceptarla."],
		fields = {
			{ key = "guild", label = L["Hermandad"], width = 200, default = enemy or "" },
			{ key = "zone", label = L["Zona"], width = 200, default = zone, options = function() return ns.ZoneOptions() end },
			{ key = "date", label = L["Fecha (DD/MM)"], width = 60, default = date("%d/%m", nextHour) },
			{ key = "time", label = L["Hora (HH:MM)"], width = 60, default = date("%H:00", nextHour) },
			{ key = "minutes", label = L["Duración (min)"], width = 60, numeric = true, default = 60 },
		},
		submit = L["Declarar"],
		onSubmit = function(v)
			local start = ns.ParseStart(v.date or "", v.time or "")
			if not start then return L["Fecha u hora no válidas. Usa DD/MM y HH:MM, por ejemplo 12/11 y 21:00."] end
			return ns.DeclareWar(v.guild, start, v.minutes, v.zone)
		end,
	})
end

-- Una línea de estadística de la guerra (dentro del desplegable).
local function statLine(rows, label, value)
	line(rows, grey(label .. ": ") .. value, 2)
end

local function warStatsRows(rows, w)
	local st = ns.WarStats(w)
	if st.topKiller then statLine(rows, L["Máximo asesino"], ("%s (%d)"):format(ns.ShortName(st.topKiller.name), st.topKiller.kills)) end
	if st.unbeaten then statLine(rows, L["Invicto"], ("%s%s"):format(ns.ShortName(st.unbeaten.name),
		st.unbeaten.kills > 0 and (" (" .. (L["%d kills"]):format(st.unbeaten.kills) .. ")") or "")) end
	if st.firstBlood then
		statLine(rows, L["Primera sangre"], st.firstBlood.ours
			and (GREEN .. (L["%s mató a %s"]):format(ns.ShortName(st.firstBlood.name) or "?", ns.ShortName(st.firstBlood.victim) or "?") .. R)
			or (RED .. (L["%s mató a %s"]):format(ns.ShortName(st.firstBlood.name) or "?", ns.ShortName(st.firstBlood.victim) or "?") .. R))
	end
	if st.streak then statLine(rows, L["Mejor racha"], (L["%s, %d seguidas"]):format(ns.ShortName(st.streak.name), st.streak.best)) end
	if st.theirTop then statLine(rows, L["Su mayor asesino"], RED .. ("%s (%d)"):format(ns.ShortName(st.theirTop.name), st.theirTop.kills) .. R) end
	-- La tribu cuyos miembros más bajas hicieron en esta guerra.
	local byTribe = {}
	for _, p in ipairs(st.players or {}) do
		local tribe = p.kills > 0 and ns.TribeOf and ns.TribeOf(p.name)
		if tribe then byTribe[tribe.name] = (byTribe[tribe.name] or 0) + p.kills end
	end
	local bestTribe, bestKills
	for name, n in pairs(byTribe) do
		if not bestKills or n > bestKills then bestTribe, bestKills = name, n end
	end
	if bestTribe then statLine(rows, (L["%s con más bajas"]):format(ns.TribeWords().One), ("%s«%s»|r (%d)"):format(GOLD, bestTribe, bestKills)) end
	if not st.topKiller and not st.firstBlood then line(rows, grey(L["Sin bajas registradas."]), 2) end
end

local RESULT_STYLE = {
	[1] = { label = L["VICTORIA"], color = GREEN, tint = { 0.2, 0.85, 0.25 } },
	[0] = { label = L["DERROTA"], color = RED, tint = { 0.9, 0.2, 0.15 } },
	[0.5] = { label = L["EMPATE"], color = GOLD, tint = { 0.9, 0.75, 0.2 } },
}

local function warsView(g, rows)
	local guild = LG:GuildName()
	local me = ns.PlayerFullName()
	local isGM = ns.IsGuildMaster(me)
	local isOfficer = ns.CanManageEvents(me)
	local record = ns.WarRecord()
	local league = ns.WarLeague(record.rating)

	-- Temporada: puntos de guerra y liga. Los trofeos están en Desafíos › Guerras.
	local specialsDone = 0
	for _ in pairs(record.specials) do specialsDone = specialsDone + 1 end
	-- Barra hacia la siguiente liga.
	local nextLeague
	for _, l in ipairs(ns.WAR_LEAGUES) do
		if l.min > record.rating and not nextLeague then nextLeague = l end
	end
	rows[#rows + 1] = {
		kind = "crest",
		league = league,
		title = (L["Temporada %d · Liga de %s"]):format(record.season, league.label),
		desc = ("%s%d|r %s  ·  %s"):format(GOLD, record.rating, L["puntos de guerra"],
			(L["%d victorias, %d derrotas, %d empates"]):format(record.wins, record.losses, record.draws)),
		bar = nextLeague and { min = league.min, max = nextLeague.min, value = record.rating,
			text = ("%d / %d  >  %s"):format(record.rating, nextLeague.min, nextLeague.label) }
			or { min = 0, max = 1, value = 1, text = L["Liga máxima"] },
		foot = grey((L["Trofeos de guerra: %d/%d · Proezas: %d"]):format(specialsDone, #ns.WAR_SPECIALS, #record.feats)),
		tooltip = { L["Clasificación de guerras"], L["Ganar a una hermandad mejor clasificada da más puntos; perder contra una peor, quita más."],
			(L["Bronce desde 0, plata desde %d, oro desde %d."]):format(ns.WAR_LEAGUES[2].min, ns.WAR_LEAGUES[3].min),
			L["Se reinicia con cada temporada JcJ; lo logrado queda en Logros › Proezas de fuerza."] },
		buttons = { { label = L["Trofeos"], onClick = function() ns.ShowAchievementsCategory("wars") end } },
	}

	-- Guerras.
	space(rows)
	local buttons = {}
	if isGM then buttons[#buttons + 1] = { label = L["Declarar guerra"], onClick = function() ns.ShowDeclareWarDialog() end } end
	if isOfficer then buttons[#buttons + 1] = { label = L["Pegar código"], onClick = function() ns.ShowPasteWarCode() end } end
	header(rows, L["Guerras"], buttons)

	local groups = { active = {}, pending = {}, upcoming = {}, finished = {}, closed = {} }
	for _, w in pairs(g.wars) do
		local phase = ns.WarPhase(w)
		local list = groups[phase] or groups.closed
		list[#list + 1] = w
	end
	for _, list in pairs(groups) do table.sort(list, function(a, b) return a.start > b.start end) end
	local any = false

	for _, w in ipairs(groups.active) do
		any = true
		local enemy = ns.WarEnemy(w, guild)
		local s = ns.WarScore(w)
		local ourCount = ns.WarPresence(w)
		local winning = s.ours > s.theirs and GREEN or (s.ours < s.theirs and RED or GOLD)
		local key = "war" .. w.id
		rows[#rows + 1] = {
			kind = "card", state = "normal", accent = ns.ACCENT.active,
			icon = ICON_WAR, iconColor = { 0.85, 0.2, 0.12 },
			title = (L["Guerra contra <%s>"]):format(enemy),
			desc = ("%s  ·  %s"):format(ns.MapName(w.map, w.zone), grey((L["quedan %s"]):format(minutesLeft(w.start + w.duration)))),
			status = RED .. L["EN CURSO"] .. R .. "   " .. winning .. ("%d – %d"):format(s.ours, s.theirs) .. R,
			foot = ns.WarLayerStatus(w).mismatch and ns.WarLayerText(w)
				or s.confirmed and (GREEN .. L["Marcador confirmado por el rival."] .. R)
				or grey((L["En la zona: %d de los nuestros · %s de los suyos"]):format(ourCount, w.report and tostring(w.report.present) or "?")),
			tooltip = { (L["Guerra contra <%s>"]):format(enemy), ns.WarLayerText(w), grey(L["Clic para ver las estadísticas."]) },
			onClick = toggle(key, true),
			buttons = { { label = L["Código"], onClick = function() showCode(w.id) end } },
		}
		if isOpen(key, true) then warStatsRows(rows, w); space(rows) end
	end

	for _, w in ipairs(groups.pending) do
		any = true
		local enemy = ns.WarEnemy(w, guild)
		local incoming = w.to == guild
		local info = ("%s  ·  %s%s|r  ·  %d min"):format(ns.MapName(w.map, w.zone), GOLD, date("%d/%m %H:%M", w.start), math.floor(w.duration / 60))
		local btns
		if isGM and incoming then
			btns = { { label = L["Aceptar"], onClick = function() ns.AnswerWar(w.id, "accepted") end },
				{ label = L["Rechazar"], onClick = function() ns.AnswerWar(w.id, "declined") end } }
		elseif isGM then
			btns = { { label = L["Código"], onClick = function() showCode(w.id) end },
				{ label = L["Cancelar"], onClick = function() ns.AnswerWar(w.id, "cancelled") end } }
		end
		rows[#rows + 1] = {
			kind = "card", state = "normal", accent = incoming and ns.ACCENT.action or nil,
			icon = ns.FactionBanner(ns.WarEnemyFaction(w, guild)),
			title = incoming and (L["<%s> os declara la guerra"]):format(enemy) or (L["Esperando respuesta de <%s>"]):format(enemy),
			desc = info,
			status = incoming and (GOLD .. L["pendiente"] .. R) or grey(L["pendiente"]),
			foot = (incoming and not isGM) and grey(L["(decide el maestro de hermandad)"]) or nil,
			buttons = btns,
		}
	end

	for _, w in ipairs(groups.upcoming) do
		any = true
		local enemy = ns.WarEnemy(w, guild)
		rows[#rows + 1] = {
			kind = "card", state = "normal",
			icon = ns.FactionBanner(ns.WarEnemyFaction(w, guild)),
			title = (L["Guerra contra <%s>"]):format(enemy),
			desc = ("%s  ·  %s%s|r  ·  %d min"):format(ns.MapName(w.map, w.zone), GOLD, dayLabel(w.start) .. " " .. date("%H:%M", w.start), math.floor(w.duration / 60)),
			status = GOLD .. L["Próxima"] .. R,
			foot = (w.start - ns.Now() <= 15 * 60) and ns.WarLayerText(w) or nil,
			buttons = isGM and { { label = L["Código"], onClick = function() showCode(w.id) end },
				{ label = L["Cancelar"], onClick = function() ns.AnswerWar(w.id, "cancelled") end } } or nil,
		}
	end

	local byWar = {}
	for _, h in ipairs(record.history) do byWar[h.war.id] = h end
	for i, w in ipairs(groups.finished) do
		if i > 10 then break end
		any = true
		local enemy = ns.WarEnemy(w, guild)
		local h = byWar[w.id]
		local s = h or ns.WarScore(w)
		local style = h and RESULT_STYLE[h.result] or { label = L["SIN BAJAS"], color = GREY, tint = { 0.5, 0.5, 0.5 } }
		local key = "war" .. w.id
		rows[#rows + 1] = {
			kind = "card", state = (h and h.result == 1) and "normal" or "off",
			icon = ns.FactionBanner(ns.WarEnemyFaction(w, guild)),
			iconColor = { style.tint[1], style.tint[2], style.tint[3] },
			desaturate = false,
			title = (L["Guerra contra <%s>"]):format(enemy),
			desc = ("%s  ·  %s"):format(date("%d/%m", w.start), ns.MapName(w.map, w.zone)),
			status = style.color .. style.label .. R .. "   " .. ("%d – %d"):format(s.ours, s.theirs),
			foot = h and (((h.delta >= 0 and GREEN or RED) .. ("%+d"):format(h.delta) .. R) .. grey(" " .. L["puntos de guerra"])) or nil,
			tooltip = { (L["Guerra contra <%s>"]):format(enemy),
				(h and h.confirmed) and (GREEN .. L["Marcador confirmado por el rival."] .. R) or grey(L["Marcador según nuestro registro."]),
				grey(L["Clic para ver las estadísticas."]) },
			onClick = toggle(key, false),
			buttons = { { label = L["Código"], onClick = function() showCode(w.id) end } },
		}
		if isOpen(key, false) then warStatsRows(rows, w); space(rows) end
	end

	for i, w in ipairs(groups.closed) do
		if i > 5 then break end
		any = true
		local phase = ns.WarPhase(w)
		local label = phase == "declined" and L["rechazada"] or (phase == "cancelled" and L["cancelada"] or L["sin respuesta"])
		line(rows, grey(("%s  <%s>  %s"):format(date("%d/%m", w.start), ns.WarEnemy(w, guild), label)), 1)
	end

	if not any then
		line(rows, grey(L["Ninguna todavía. El maestro de hermandad puede declarar la guerra desde Hermandades."]), 1)
	end
	space(rows)
	line(rows, grey(L["Cada bando cuenta sus propias muertes y se las pasa al otro: nadie puede inventarse las bajas del rival. Las kills sobre rivales sin el addon cuentan tal cual."]))
end

---------------------------------------------------------------------------
-- JcJ > Hermandades: directorio de la red
---------------------------------------------------------------------------

local function directoryRow(rows, e, own, canDeclare)
	local league = ns.WarLeague(e.rating)
	local key = "dir" .. e.guild
	local buttons = {}
	if e.trophies and #e.trophies > 0 then
		buttons[#buttons + 1] = { label = L["Vitrina"], onClick = toggle(key, false) }
	end
	if canDeclare and not own then
		buttons[#buttons + 1] = { label = L["Guerra"], onClick = function() ns.ShowDeclareWarDialog(e.guild) end }
	end
	if ns.WARS_PAUSED then
		-- Sin guerras: el directorio es el registro de las hermandades con el addon.
		local stats = own and ns.GuildSeasonStats and ns.GuildSeasonStats() or e.stats
		rows[#rows + 1] = {
			indent = 1, tall = true,
			icon = ns.FactionBanner(e.faction),
			cols = {
				{ ((stats and (stats.points or 0) >= 70) and "|TInterface\\COMMON\\FavoritesIcon:14:14|t " or "") .. (own and GOLD or "") .. e.guild .. (own and R or ""), 200 },
				{ grey(((e.members or 0) == 1 and L["1 miembro"] or L["%d miembros"]):format(e.members or 0)), 105 },
				{ grey((L["%d con el addon"]):format(e.addon or 0)), 110 },
				{ GOLD .. (L["%d logros"]):format(stats and stats.points or 0) .. R, 90 },
				{ grey(own and L["tú"] or (e.t and ago(e.t) or "")), 90 },
			},
			tooltip = { e.guild, ns.FactionName(e.faction),
				e.t and grey((L["Visto: %s"]):format(dayLabel(e.t) .. " " .. date("%H:%M", e.t))) or nil },
		}
		return
	end
	rows[#rows + 1] = {
		indent = 1, tall = true,
		icon = ns.FactionBanner(e.faction), iconColor = league.color,
		cols = {
			{ (own and GOLD or "") .. e.guild .. (own and R or ""), 185 },
			{ grey(((e.members or 0) == 1 and L["1 miembro"] or L["%d miembros"]):format(e.members or 0)), 105 },
			{ grey((L["%d con el addon"]):format(e.addon or 0)), 100 },
			{ ("%d %s"):format(e.rating or 1000, league.label), 90 },
			{ grey(("%d-%d-%d"):format(e.wins or 0, e.losses or 0, e.draws or 0)), 60 },
		},
		tooltip = { e.guild, ns.FactionName(e.faction),
			(L["%d victorias, %d derrotas, %d empates"]):format(e.wins or 0, e.losses or 0, e.draws or 0),
			e.t and grey((L["Visto: %s"]):format(dayLabel(e.t) .. " " .. date("%H:%M", e.t))) or nil },
		buttons = #buttons > 0 and buttons or nil,
	}
	if isOpen(key, false) then
		for _, tr in ipairs(e.trophies or {}) do
			line(rows, GOLD .. tr.title .. R .. (tr.sub and ("  " .. grey(tr.sub)) or ""), 2)
		end
	end
end

local function directoryView(g, rows)
	local status = ns.NetStatus()
	local me = ns.PlayerFullName()
	local myFactionGroup = UnitFactionGroup and UnitFactionGroup("player")

	-- Estado de la red.
	if status.testMode then
		line(rows, GOLD .. L["Modo prueba: red de pruebas aparte; solo te ven los que también tienen el modo prueba. Las hermandades de ejemplo aceptan solas."] .. R, 0,
			{ icon = "Interface\\FriendsFrame\\InformationIcon", tall = true })
	elseif status.connected then
		line(rows, GREEN .. L["Conectado a la red de hermandades."] .. R, 0, { icon = "Interface\\RAIDFRAME\\ReadyCheck-Ready", tall = true })
	else
		line(rows, RED .. L["Sin conexión con la red de hermandades."] .. R .. (status.error and grey("  (" .. status.error .. ")") or ""), 0,
			{ icon = "Interface\\RAIDFRAME\\ReadyCheck-NotReady", tall = true })
	end
	line(rows, status.crossFaction and (GREEN .. (L["La red llega a la otra facción (comprobado el %s)."]):format(date("%d/%m", status.crossFaction)) .. R)
		or grey(L["Aún no se ha visto a la otra facción en la red."]), 0)
	-- Puente por Battle.net: amigos de la otra facción con el addon.
	local bridge = status.bridge
	if bridge and bridge.available then
		local peers = ns.BridgePeers()
		local names = {}
		for _, p in ipairs(peers) do names[#names + 1] = p.name or "?" end
		line(rows, #peers > 0 and (GREEN .. (#peers == 1 and L["Puente con la otra facción: 1 amigo de Battle.net con el addon."] or (L["Puente con la otra facción: %d amigos de Battle.net con el addon."]):format(#peers)) .. R)
			or grey(L["Sin puente con la otra facción: hace falta un amigo de Battle.net de la otra facción con el addon."]), 0, {
			icon = "Interface\\FriendsFrame\\Battlenet-Battleneticon",
			tooltip = { L["Puente por Battle.net"],
				L["Los canales del juego no cruzan entre Horda y Alianza. Lo que interesa a la otra facción (directorio y clasificación) se pasa por amigos de Battle.net que tengan el addon, y ellos lo reparten en su facción."],
				#names > 0 and table.concat(names, ", ") or nil },
		})
	end
	if ns.CanManageEvents(me) then
		local listed = ns.GuildSetting("listed", true)
		line(rows, listed and L["Tu hermandad aparece en el directorio."] or GOLD .. L["Tu hermandad está oculta en el directorio."] .. R, 0, {
			buttons = { { label = listed and L["Ocultar"] or L["Mostrar"], onClick = function() ns.SetGuildSetting("listed", not listed) end } },
		})
	end

	local query = searchBox and searchBox:GetText():lower() or ""
	local list = ns.Directory()
	local own = ns.GuildAnnouncement()
	if own and not own.hidden then own.faction = own.faction or myFactionGroup end
	local canDeclare = ns.IsGuildMaster(me) and not ns.WARS_PAUSED
	for _, faction in ipairs({ myFactionGroup == "Alliance" and "Horde" or "Alliance", myFactionGroup or "Horde" }) do
		local entries = {}
		for _, e in ipairs(list) do
			if e.faction == faction and (query == "" or e.guild:lower():find(query, 1, true)) then entries[#entries + 1] = e end
		end
		local showOwn = own and not own.hidden and own.faction == faction and (query == "" or own.guild:lower():find(query, 1, true))
		if #entries > 0 or showOwn then
			space(rows)
			header(rows, ns.FactionName(faction))
			if showOwn then directoryRow(rows, own, true, false) end
			for _, e in ipairs(entries) do directoryRow(rows, e, false, canDeclare) end
		end
	end
	if #list == 0 then
		space(rows)
		line(rows, grey(L["Todavía no hay otras hermandades en el directorio. Aparecen solas cuando alguno de sus miembros tiene el addon."]), 1)
	end
end

-- JcJ › Auxilio: llamadas de auxilio en curso (Modules/Aid.lua).
local ICON_AID = "Interface\\Icons\\Ability_Warrior_BattleShout"
local ICON_ASSAULT = "Interface\\Icons\\Ability_Warrior_Charge"



-- Hace cuánto empezó (para los asaltos, que no tienen hora de fin).
local function sinceText(t)
	local m = math.max(0, math.floor((ns.Now() - t) / 60))
	return m >= 60 and (L["%d h %d min"]):format(math.floor(m / 60), m % 60) or (L["%d min"]):format(m)
end

-- Tarjetas de las llamadas o asaltos en curso (kind = "help" | "assault").
local function callCards(g, rows, kind)
	local guild = LG:GuildName()
	local me = ns.PlayerFullName()
	local any = false
	for _, c in ipairs(ns.ActiveAidCalls()) do
		if (c.kind or "help") == kind then
			any = true
			local mine = c.guild == guild
			local goers = ns.aidGoers[c.id] or {}
			local nGoers = 0
			for _ in pairs(goers) do nGoers = nGoers + 1 end
			local here = ns.AidOnLayer(c)
			local btns
			if not here and not goers[me] then
				btns = { { label = mine and L["Ir a su capa"] or L["Acudir"], onClick = function() ns.GoToAid(c.id) end } }
			end
			if mine and (ns.CanManageEvents(me) or c.by == me) then
				btns = btns or {}
				btns[#btns + 1] = { label = L["Terminar"], onClick = function() ns.EndCall(c.id) end }
			end
			local layer = ns.CallLayerText(c)
			local assault = kind == "assault"
			rows[#rows + 1] = {
				kind = "card", state = "normal", accent = mine and ns.ACCENT.action or ns.ACCENT.active,
				icon = assault and ICON_ASSAULT or ICON_AID, iconColor = { 0.85, 0.2, 0.12 },
				title = assault and (mine and (L["Tu hermandad asalta %s"]):format(c.zone) or (L["<%s> asalta %s"]):format(c.guild, c.zone))
					or (mine and (L["Tu hermandad pide ayuda en %s"]):format(c.subzone or c.zone) or (L["<%s> pide ayuda en %s"]):format(c.guild, c.subzone or c.zone)),
				desc = assault and ((c.open and L["abierto a la facción"] or L["solo la hermandad"]) .. "  ·  " .. layer)
					or (L["contra <%s>  ·  %s  ·  %d muertes"]):format(ns.AidEnemyName(c.enemy), layer, c.deaths or 0),
				status = assault and (RED .. (L["en curso · %s"]):format(sinceText(c.t)) .. R) or (RED .. (L["quedan %s"]):format(minutesLeft(c.ends)) .. R),
				foot = (here and (GREEN .. L["Estás en su capa."] .. R .. "  ·  ") or (goers[me] and grey(L["Has respondido: espera la invitación.  ·  "]) or ""))
					.. grey(assault and (L["Acuden: %d  ·  bajas en la ciudad: %d"]):format(nGoers, ns.AidKills(c))
						or (L["Acuden: %d  ·  bajas de <%s>: %d"]):format(nGoers, ns.AidEnemyName(c.enemy), ns.AidKills(c))),
				buttons = btns,
			}
			if mine then
				for name, info in pairs(goers) do
					if name ~= me then
						local canInvite = here and (not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
						line(rows, ns.ShortName(name) .. (info.guild and info.guild ~= guild and grey((" <%s>"):format(info.guild)) or "")
							.. (info.invited and grey("  · " .. L["invitado"]) or ""), 2,
							{ buttons = canInvite and { { label = L["Invitar"], onClick = function() ns.InviteAidGoer(c.id, name) end } } or nil })
					end
				end
			end
		end
	end
	return any
end

-- Historial de la hermandad de un tipo (las terminadas).
local function callHistory(g, kind)
	local list = {}
	for _, c in pairs(g.calls or {}) do
		if (c.kind or "help") == kind and (c.ends or 0) < ns.Now() then list[#list + 1] = c end
	end
	table.sort(list, function(a, b) return a.t > b.t end)
	return list
end

-- JcJ › Auxilio: llamadas de auxilio (Modules/Aid.lua).
local function aidView(g, rows)
	local buttons = LG:InTestMode() and { { label = L["Simular llamada"], onClick = function() ns.SimulateAidCall() end } } or nil
	header(rows, L["Llamadas de auxilio"], buttons)
	if not callCards(g, rows, "help") then line(rows, grey(L["No hay llamadas de auxilio en curso."]), 1) end
	local history = callHistory(g, "help")
	if #history > 0 then
		space(rows)
		header(rows, L["Historial"])
		for i = 1, math.min(10, #history) do
			local c = history[i]
			line(rows, ("%s  %s  %s"):format(grey(date("%d/%m %H:%M", c.t)), (L["Auxilio en %s contra <%s>"]):format(c.zone, ns.AidEnemyName(c.enemy)),
				grey((L["%d bajas · acudieron %d de %d hermandades"]):format(c.kills or 0, c.goers or 0, c.guilds or 0))), 1, { icon = ICON_AID })
		end
	end
	space(rows)
	line(rows, grey(L["Si una hermandad enemiga os mata 3 veces en 10 minutos en la misma zona, la víctima puede pedir ayuda (la aprueba un oficial si hay alguno conectado). La llamada llega a toda tu facción con el addon y dura 30 minutos."]))
	line(rows, grey(L["Quien acude entra en la banda de alguien que está en la capa buena y se queda en ella: al salir del grupo el juego puede devolverle a su capa."]))
end

-- Icono de cada capital: el del portal de mago a esa ciudad.
local CITY_ICONS = {
	stormwind = "Interface\\Icons\\Spell_Arcane_TeleportStormWind",
	ironforge = "Interface\\Icons\\Spell_Arcane_TeleportIronForge",
	darnassus = "Interface\\Icons\\Spell_Arcane_TeleportDarnassus",
	orgrimmar = "Interface\\Icons\\Spell_Arcane_TeleportOrgrimmar",
	undercity = "Interface\\Icons\\Spell_Arcane_TeleportUnderCity",
	thunderbluff = "Interface\\Icons\\Spell_Arcane_TeleportThunderBluff",
}

-- Declarar un asalto: a quién se anuncia, con dos botones.
local function showDeclareAssault(city)
	ns.ShowInputDialog({
		title = (L["Asalto a %s"]):format(ns.CityName(city.key)),
		text = (L["Objetivo: %s. El asalto acaba al caer el líder, cuando lo terminas o tras 2 horas sin bajas en la ciudad."]):format(city.leader),
		fields = { { key = "who", label = L["Anunciarlo a"], default = "faction", choices = {
			{ value = "faction", label = L["Toda la facción"] },
			{ value = "guild", label = L["Solo la hermandad"] } } } },
		submit = L["Declarar"],
		onSubmit = function(v)
			ns.DeclareAssault(city.key, v.who ~= "guild")
			return nil
		end,
	})
end

-- JcJ › Asaltos: en curso, una tarjeta por capital enemiga (con récord y botón) e historial.
local function assaultView(g, rows)
	local me = ns.PlayerFullName()
	local canDeclare = ns.CanManageEvents(me)

	-- En curso (solo si hay alguno: los míos y los de otras hermandades de la facción).
	local active = false
	for _, c in ipairs(ns.ActiveAidCalls()) do
		if c.kind == "assault" then active = true end
	end
	if active then
		header(rows, L["Asaltos en curso"])
		callCards(g, rows, "assault")
		space(rows)
	end

	-- Capitales enemigas: récord de la hermandad, asaltos hechos y caídas del líder.
	header(rows, L["Capitales enemigas"])
	local best = ns.AssaultTimes(g)
	local mine = {}
	for _, c in ipairs(ns.ActiveAidCalls()) do
		if c.kind == "assault" and c.guild == LG:GuildName() then mine[c.city] = c end
	end
	for _, city in ipairs(ns.EnemyCities()) do
		local assaults, falls, last = 0, 0, nil
		for _, c in pairs(g.calls or {}) do
			if c.kind == "assault" and c.city == city.key then
				assaults = assaults + 1
				if not last or c.t > last then last = c.t end
			end
		end
		for _, r in pairs(g.regicides or {}) do
			if r.city == city.key then falls = falls + 1 end
		end
		local foot = { (assaults == 1 and L["1 asalto"] or (L["%d asaltos"]):format(assaults)),
			(falls == 1 and L["el líder ha caído 1 vez"] or (L["el líder ha caído %d veces"]):format(falls)) }
		if last then foot[#foot + 1] = (L["último: %s"]):format(dayLabel(last)) end
		local running = mine[city.key]
		rows[#rows + 1] = {
			kind = "card", state = "normal",
			accent = running and ns.ACCENT.active or (best[city.key] and ns.ACCENT.good or nil),
			icon = CITY_ICONS[city.key],
			title = ns.CityName(city.key),
			desc = (L["Líder: %s"]):format(city.leader),
			status = running and (RED .. L["EN CURSO"] .. R)
				or (best[city.key] and (GOLD .. (L["Récord %s"]):format(ns.FormatDuration(best[city.key])) .. R) or grey(L["sin derribar"])),
			foot = grey(table.concat(foot, "  ·  ")),
			buttons = (canDeclare and not running) and { { label = L["Declarar asalto"], onClick = function() showDeclareAssault(city) end } } or nil,
		}
	end

	-- Historial: líderes derribados (con su tiempo) y asaltos terminados.
	local fallen = {}
	for _, r in pairs(g.regicides or {}) do fallen[#fallen + 1] = r end
	table.sort(fallen, function(a, b) return a.t > b.t end)
	local history = callHistory(g, "assault")
	if #history > 0 or #fallen > 0 then
		space(rows)
		header(rows, L["Historial"])
		for _, r in ipairs(fallen) do
			local c = r.call and g.calls[r.call]
			line(rows, ("%s  |cffffd100%s|r  %s"):format(grey(date("%d/%m %H:%M", r.t)), (L["¡%s ha caído!"]):format(ns.CITY[r.city].leader),
				grey((c and (L["en %s"]):format(ns.FormatDuration(r.t - c.t)) or "") .. (r.solo and ("  " .. L["(asalto solo de la hermandad)"]) or ""))),
				1, { icon = "Interface\\Icons\\INV_Crown_01" })
		end
		for i = 1, math.min(10, #history) do
			local c = history[i]
			line(rows, ("%s  %s  %s"):format(grey(date("%d/%m %H:%M", c.t)), (L["Asalto a %s"]):format(c.zone),
				grey((L["%d bajas · acudieron %d de %d hermandades"]):format(c.kills or 0, c.goers or 0, c.guilds or 0))), 1,
				{ icon = CITY_ICONS[c.city] or ICON_ASSAULT })
		end
	end
	space(rows)
	line(rows, grey(L["Un asalto no tiene hora de fin: acaba al caer el líder (su tiempo cuenta para los récords de la facción), cuando un oficial lo termina o tras 2 horas sin bajas en la ciudad. El líder se detecta si alguien lo tiene seleccionado cuando cae."]))
end

-- JcJ › Cabezas con precio: el botín de guerra propio, los precios abiertos y los cobrados.
local bountyUI = {} -- en una tabla: MainFrame va justo de variables locales
function bountyUI.place(name)
	-- Nombres para elegir: quienes nos han matado en la última semana.
	local names, seen = {}, {}
	local g = LG:GuildData()
	for _, k in pairs(g and g.kills or {}) do
		if k.kind == "death" and not k.bg and k.killerName and k.t >= ns.Now() - 7 * 86400 and not seen[k.killerName] then
			seen[k.killerName] = true
			names[#names + 1] = k.killerName
		end
	end
	table.sort(names)
	ns.ShowInputDialog({
		title = name and (L["Precio por %s"]):format(ns.ShortName(name)) or L["Poner precio a una cabeza"],
		text = (L["Tienes %d insignias libres. Las cobra entero quien lo mate en 7 días; si nadie lo caza, van al cofre."]):format(ns.AvailableInsignias(nil)),
		submit = L["Poner precio"],
		fields = {
			{ key = "name", label = L["Enemigo"], width = 220, default = name or "",
				options = function() return { { label = L["Os han matado esta semana"], items = names } } end },
			{ key = "amount", label = L["Insignias"], width = 80, numeric = true, default = 20 },
		},
		onSubmit = function(v)
			local ok, err = ns.PlaceBounty(v.name, v.amount)
			if not ok then return err end
		end,
	})
end

function bountyUI.view(g, rows)
	local me = ns.PlayerFullName()
	local w = ns.WagerState()
	local W = ns.WAGER

	-- Botín de guerra: activarlo o quitarlo.
	header(rows, L["Botín de guerra"])
	local button
	if w.on then
		button = w.canOff and { label = L["Desactivar"], onClick = function() ns.SetWager(false) end } or nil
	else
		button = { label = L["Activar"], onClick = function() ns.SetWager(true) end }
	end
	rows[#rows + 1] = {
		kind = "card", state = w.on and "normal" or "off", accent = w.on and { 0.85, 0.2, 0.12 } or nil,
		icon = "Interface\\Icons\\INV_Misc_Bag_11",
		title = w.on and (RED .. L["Activado"] .. R) or L["Desactivado"],
		desc = (L["Cazando ganas x%s insignias. Si un enemigo te mata, pierdes el %d %% de lo que pase de %d (una vez al día) y queda como precio por su cabeza."]):format(
			(tostring(W.bonus):gsub("%.", ",")), math.floor(W.pct * 100), W.floor),
		status = w.on and not w.canOff and grey((L["mínimo 24 h: %s"]):format(ns.FormatDuration(w.offAt - ns.Now()))) or nil,
		foot = grey(L["Fuera de campos de batalla y solo muertes que le den honor al asesino."]),
		buttons = button and { button } or nil,
	}

	-- Precios abiertos, por enemigo.
	space(rows)
	header(rows, L["Cabezas con precio"], { { label = L["Poner precio"], onClick = function() bountyUI.place() end } })
	local targets = ns.BountyTargets()
	if #targets == 0 then line(rows, grey(L["Ninguna. Salen cuando alguien con botín de guerra muere o cuando alguien pone precio a un enemigo."]), 1) end
	for _, t in ipairs(targets) do
		local victims, manual = {}, 0
		for _, pot in ipairs(t.pots) do
			if pot.manual then manual = manual + pot.amount
			elseif pot.victim then victims[#victims + 1] = ns.ShortName(pot.victim) end
		end
		local desc = {}
		if t.guild then desc[#desc + 1] = "<" .. t.guild .. ">" end
		if #victims > 0 then desc[#desc + 1] = (L["mató a %s"]):format(table.concat(victims, ", ")) end
		if manual > 0 then desc[#desc + 1] = (L["%d puestas a mano"]):format(manual) end
		rows[#rows + 1] = {
			kind = "card", state = "normal", accent = { 0.85, 0.2, 0.12 },
			icon = ICON_SKULL,
			title = RED .. (ns.ShortName(t.name) or "?") .. R,
			desc = table.concat(desc, "  ·  "),
			status = GOLD .. (L["%d insignias"]):format(t.total) .. R,
			foot = grey((L["caduca en %s"]):format(ns.FormatDuration(t.expires - ns.Now()))),
			tooltip = { ns.ShortName(t.name) or "?", L["Quien lo mate cobra el precio. Lo de las víctimas con botín de guerra se reparte: la mitad para el cazador y la mitad vuelve a la víctima."] },
			buttons = { { label = L["Añadir"], onClick = function() bountyUI.place(t.name) end } },
		}
	end

	-- Cobradas.
	local claims = ns.BountyClaims(8)
	if #claims > 0 then
		space(rows)
		header(rows, L["Cobradas"])
		for _, pot in ipairs(claims) do
			local m = g.members[pot.hunter] or ns.roster[pot.hunter]
			line(rows, ("%s  %s  %s%d|r  %s"):format(grey(date("%d/%m %H:%M", pot.claimedAt)),
				ns.ClassColorName(pot.hunter, m and m.class), GOLD, pot.hunterGets or 0,
				(L["por la cabeza de %s"]):format(ns.ShortName(pot.name) or "?")), 1)
		end
	end
end

views.hunt = function()
	local g = LG:GuildData()
	if not g then return notInGuild() end
	local rows = {}
	local guild = LG:GuildName()
	local pending = 0
	for _, w in pairs(g.wars) do
		local phase = ns.WarPhase(w)
		if phase == "active" or (phase == "pending" and w.to == guild) then pending = pending + 1 end
	end
	local calls, assaults = 0, 0
	for _, c in ipairs(ns.ActiveAidCalls()) do
		if c.kind == "assault" then assaults = assaults + 1 else calls = calls + 1 end
	end
	local function label(text, n) return n > 0 and (text .. " (" .. n .. ")") or text end
	local list = { { key = "targets", label = L["Objetivos"] }, { key = "bounty", label = label(L["Cabezas con precio"], #ns.BountyTargets()) } }
	if ns.WARS_PAUSED then
		list[#list + 1] = { key = "aid", label = label(L["Auxilio"], calls) }
		list[#list + 1] = { key = "assault", label = label(L["Asaltos"], assaults) }
	else
		list[#list + 1] = { key = "wars", label = label(L["Guerras"], pending) }
	end
	if not ns.WARS_PAUSED then list[#list + 1] = { key = "directory", label = L["Hermandades"] } end
	segments(rows, "hunt", list)
	if subview.hunt == "aid" or (subview.hunt == "wars" and ns.WARS_PAUSED) then
		aidView(g, rows)
	elseif subview.hunt == "assault" then
		assaultView(g, rows)
	elseif subview.hunt == "bounty" then
		bountyUI.view(g, rows)
	elseif subview.hunt == "wars" then
		warsView(g, rows)
	elseif subview.hunt == "directory" and not ns.WARS_PAUSED then
		directoryView(g, rows)
		rows.search = L["Buscar hermandad..."]
	else
		targetsView(g, rows)
	end
	return rows
end

---------------------------------------------------------------------------
-- JcE: buscador de grupo y tiempos de mazmorra
---------------------------------------------------------------------------

local ROLE_ICONS = {
	tank = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
	healer = "Interface\\Icons\\Spell_Holy_Renew",
	dps = "Interface\\Icons\\Ability_DualWield",
}

local function parseRole(text)
	local c = (strtrim(text or "")):sub(1, 1):lower()
	if c == "t" then return "tank" end
	if c == "s" or c == "h" then return "healer" end
	if c == "d" then return "dps" end
	return nil
end

-- Mazmorras de Forever para el desplegable, por nivel (los tres desafíos de
-- legado de mazmorras van de las de nivel bajo a las de nivel máximo).
local DUNGEON_TIERS = { L["Mazmorras de nivel bajo"], L["Mazmorras de nivel medio"], L["Mazmorras de nivel alto"] }
function ns.DungeonOptions()
	local groups, tier = {}, 0
	for _, entry in ipairs(ns.LegacyList and ns.LegacyList() or {}) do
		if entry.kind == "dungeon" then
			tier = tier + 1
			local items = {}
			for _, c in ipairs(entry.criteria) do
				-- "Sima Ígnea o Salón de los Feudales": dos mazmorras en un criterio.
				local a, b = c.name:match("^(.-) o (.+)$")
				if a and b then items[#items + 1] = a; items[#items + 1] = b else items[#items + 1] = c.name end
			end
			groups[#groups + 1] = { label = DUNGEON_TIERS[tier] or entry.name, items = items }
		end
	end
	return groups
end

-- Zonas del juego para la declaración de guerra.
local function zoneOptions()
	local items = {}
	for _, z in ipairs(ns.WarZones and ns.WarZones() or {}) do items[#items + 1] = z.name end
	return { { items = items } }
end
ns.ZoneOptions = zoneOptions

function ns.ShowCreateLFG()
	ns.ShowInputDialog({
		title = L["Crear grupo"],
		text = L["Plazas por rol según el tamaño: 5 = 1 tanque, 1 sanador y 3 DPS. Los demás piden invitación y tú decides."],
		fields = {
			{ key = "dest", label = L["Mazmorra o banda"], width = 200, options = ns.DungeonOptions,
				onPick = function(_, setField) setField("size", 5) end },
			{ key = "size", label = L["Tamaño"], width = 50, numeric = true, default = 5 },
			{ key = "role", label = L["Tu rol"], default = "dps", choices = {
				{ value = "tank", label = ns.RoleIcon("tank", 13) .. " " .. L["Tanque"] },
				{ value = "healer", label = ns.RoleIcon("healer", 13) .. " " .. L["Sanador"] },
				{ value = "dps", label = ns.RoleIcon("dps", 13) .. " " .. L["DPS"] } } },
			{ key = "note", label = L["Nota"], width = 200 },
		},
		submit = L["Publicar"],
		onSubmit = function(v)
			local role = (v.role == "tank" or v.role == "healer" or v.role == "dps") and v.role or parseRole(v.role)
			if not role then return L["Elige tu rol."] end
			return ns.CreateLFG(v.dest, v.size, role, v.note)
		end,
	})
end

-- Plazas con el icono de cada rol, en rojo lo que falta.
local function slotsText(grp)
	return roleSlots(grp.have, grp.need, true)
end

local function lfgView(g, rows)
	local me = ns.PlayerFullName()
	local mine = ns.MyLFGGroup()
	header(rows, L["Grupos de la hermandad"], {
		mine and { label = L["Cerrar mi grupo"], onClick = function() ns.CloseLFG(mine.id) end }
			or { label = L["Crear grupo"], onClick = ns.ShowCreateLFG },
	})
	local groups = ns.LFGGroups()
	if #groups == 0 then
		line(rows, grey(L["Nadie busca gente ahora mismo. Crea un grupo y la hermandad podrá pedirte invitación."]), 1,
			{ icon = "Interface\\Icons\\INV_Misc_Key_03", desaturate = true, tall = true })
	end
	for _, grp in ipairs(groups) do
		local own = grp.leader == me
		local missing = ns.LFGMissing(grp)
		local mineReq = ns.lfgMine[grp.id]
		local buttons
		if own then
			buttons = { { label = L["Cerrar"], onClick = function() ns.CloseLFG(grp.id) end } }
		elseif grp.members and grp.members[me] then
			buttons = nil
		elseif mineReq == "pending" then
			buttons = { { label = L["Solicitado"], disabled = true } }
		elseif #missing > 0 then
			buttons = {}
			for _, role in ipairs(missing) do
				buttons[#buttons + 1] = { label = roleIcon(role, 13) .. " " .. ns.RoleLabel(role), onClick = function() ns.RequestLFG(grp.id, role) end,
					tooltip = { L["Pedir invitación"], (L["Pedir unirte como %s."]):format(ns.RoleLabel(role)) } }
			end
		end
		local leaderInfo = g.members[grp.leader] or ns.roster[grp.leader]
		local status
		if #missing == 0 then
			status = GREEN .. L["completo"] .. R
		elseif mineReq == "accepted" then
			status = GREEN .. L["te ha invitado"] .. R
		elseif mineReq == "declined" then
			status = grey(L["sin sitio"])
		else
			local names = {}
			for _, r in ipairs(missing) do names[#names + 1] = roleIcon(r, 13) end
			status = GOLD .. (L["faltan: %s"]):format(table.concat(names, ", ")) .. R
		end
		rows[#rows + 1] = {
			kind = "card",
			state = (not own and #missing == 0) and "off" or "normal",
			accent = own and (next(ns.lfgRequests[grp.id] or {}) and ns.ACCENT.action or ns.ACCENT.mine) or nil,
			icon = grp.kind == "raid" and "Interface\\Icons\\INV_Misc_Head_Dragon_01" or "Interface\\Icons\\INV_Misc_Key_03",
			title = grp.dest,
			desc = slotsText(grp),
			status = status,
			foot = grey((L["líder %s · %s"]):format(ns.ClassColorName(grp.leader, leaderInfo and leaderInfo.class), ago(grp.t))
				.. (grp.note and ("  ·  \"" .. grp.note .. "\"") or "")),
			buttons = buttons,
		}
		-- Peticiones a mi grupo.
		if own then
			local reqs = {}
			for name, req in pairs(ns.lfgRequests[grp.id] or {}) do reqs[#reqs + 1] = { name = name, req = req } end
			table.sort(reqs, function(a, b) return a.req.t < b.req.t end)
			for _, e in ipairs(reqs) do
				local m = g.members[e.name] or ns.roster[e.name]
				rows[#rows + 1] = portraitFields(e.name, m and m.class, {
					indent = 2, tall = true,
					cols = { { ns.ClassColorName(e.name, m and m.class), 200 }, { roleIcon(e.req.role) .. " " .. GOLD .. ns.RoleLabel(e.req.role) .. R, 120 },
						{ grey(m and m.level and (L["nivel %d"]):format(m.level) or ""), 80 } },
					buttons = {
						{ label = L["Invitar"], onClick = function() ns.AnswerLFG(grp.id, e.name, true) end },
						{ label = L["Rechazar"], onClick = function() ns.AnswerLFG(grp.id, e.name, false) end },
					},
				})
			end
		end
	end
	space(rows)
	line(rows, grey(L["Los grupos desaparecen solos a las 2 horas. Al invitar a alguien su plaza queda ocupada."]))
end

local function timesView(g, rows)
	local times = ns.DungeonTimes()
	header(rows, L["Tiempos de mazmorra"])
	if #times == 0 then
		line(rows, grey(L["Todavía no hay tiempos. Se miden desde que el grupo entra en la mazmorra hasta que cae su jefe final."]), 1,
			{ icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", desaturate = true, tall = true })
	end
	for _, d in ipairs(times) do
		local best = d.runs[1]
		local names = {}
		for _, name in ipairs(best.members) do
			local m = g.members[name]
			names[#names + 1] = ns.ClassColorName(name, m and m.class)
		end
		local key = "times|" .. d.dungeon
		-- Si el mejor tiempo lo hizo una tribu (3 o más de sus miembros): su icono y su nombre delante.
		local tribe = ns.TribeTogether and ns.TribeTogether(best.members)
		local tex, custom = "Interface\\Icons\\INV_Misc_PocketWatch_01", false
		if tribe then tex, custom = ns.TribeIconTexture(ns.TribeIcon(tribe)) end
		rows[#rows + 1] = {
			kind = "card", state = "normal",
			icon = tex, iconBare = custom, iconCoords = custom and { 0, 1, 0, 1 } or nil,
			title = d.dungeon,
			desc = (tribe and (GOLD .. "«" .. tribe.name .. "»" .. R .. "  ") or "") .. table.concat(names, ", "),
			status = GOLD .. ns.FormatRunTime(best.duration) .. R,
			foot = grey((L["%s · %d/5 de la hermandad · %d partidas"]):format(date("%d/%m", best.t), best.guildCount, #d.runs)),
			onClick = #d.runs > 1 and toggle(key, false) or nil,
			tooltip = #d.runs > 1 and { d.dungeon, grey(L["Clic para ver los demás tiempos."]) } or nil,
		}
		if isOpen(key, false) then
			for i = 2, math.min(5, #d.runs) do
				local r = d.runs[i]
				local others = {}
				for _, name in ipairs(r.members) do others[#others + 1] = ns.ShortName(name) end
				line(rows, ("%s%d.|r  %s%s|r  %s  %s"):format(GREY, i, GOLD, ns.FormatRunTime(r.duration), table.concat(others, ", "),
					grey(date("%d/%m", r.t))), 2)
			end
		end
	end
end

views.pve = function()
	local g = LG:GuildData()
	if not g then return notInGuild() end
	local rows = {}
	local mine, pending = ns.MyLFGGroup(), 0
	for _ in pairs(mine and ns.lfgRequests[mine.id] or {}) do pending = pending + 1 end
	segments(rows, "pve", {
		{ key = "lfg", label = pending > 0 and (L["Buscar grupo"] .. " (" .. pending .. ")") or L["Buscar grupo"] },
		{ key = "times", label = L["Tiempos"] },
	})
	if subview.pve == "times" then timesView(g, rows) else lfgView(g, rows) end
	return rows
end

---------------------------------------------------------------------------
-- Ajustes del addon
---------------------------------------------------------------------------

-- Fila de ajuste: nombre, estado (sí / no) y botón para cambiarlo.
local function toggleRow(rows, label, on, onToggle, tip)
	rows[#rows + 1] = {
		indent = 1, tall = true,
		cols = { { label, 380 }, { on and (GREEN .. L["Sí"] .. R) or grey(L["No"]), 60 } },
		buttons = { { label = on and L["Desactivar"] or L["Activar"], onClick = onToggle } },
		tooltip = tip,
	}
end

-- Ajustes › Rangos y permisos: los rangos del juego, quién es oficial, qué puede hacer
-- cada rango y los nombres de los rangos del addon. Lo cambia el maestro de hermandad.
local ranksUI = {}
function ranksUI.view(rows)
	if not LG:GuildData() then return end
	local me = ns.PlayerFullName()
	local isGM = ns.IsGuildMaster(me)
	local count = ns.GuildRankCount()
	local function upTo(max)
		local names = {}
		for i = 0, math.min(max, count - 1) do names[#names + 1] = ns.GuildRankName(i) end
		return table.concat(names, ", ")
	end
	local function stepper(get, set, min)
		if not isGM then return nil end
		local v = get()
		return {
			{ label = "-", disabled = v <= (min or 0), onClick = function() set(v - 1) end },
			{ label = "+", disabled = v >= count - 1, onClick = function() set(v + 1) end },
		}
	end
	space(rows)
	header(rows, L["Rangos y permisos"])
	local names = {}
	for i = 0, count - 1 do names[#names + 1] = ns.GuildRankName(i) end
	line(rows, (L["Rangos de la hermandad: %s"]):format(table.concat(names, ", ")), 1)
	if LG:InTestMode() then
		local mine = ns.RankIndexOf(me)
		line(rows, GOLD .. (L["Modo prueba: tu rango simulado es %s."]):format(ns.GuildRankName(mine)) .. R, 1, {
			buttons = {
				{ label = "-", disabled = mine <= 0, onClick = function() LG.db.profile.testRank = mine - 1; LG:DataChanged() end },
				{ label = "+", disabled = mine >= count - 1, onClick = function() LG.db.profile.testRank = mine + 1; LG:DataChanged() end },
			},
			tooltip = { L["Rango simulado"], L["Para ver el addon como lo vería alguien de otro rango. El maestro (el primero) lo puede todo."] },
		})
	end
	line(rows, (L["Oficiales: %s"]):format(GOLD .. upTo(ns.OfficerMaxRank()) .. R), 1, {
		buttons = stepper(ns.OfficerMaxRank, function(v) ns.SetGuildSetting("officerMaxRank", v) end),
		tooltip = { L["Oficiales"], L["Ven la pestaña Oficial y cierran las subastas que su vendedor no cierre. Lo demás va por permisos."] },
	})
	for _, perm in ipairs(ns.PERMISSIONS) do
		local note = perm.key == "bankRequests" and ("  " .. grey(L["(y quien tenga la medalla de Artesano de oro)"])) or ""
		line(rows, ("%s: %s%s"):format(perm.label, GOLD .. upTo(ns.PermissionRank(perm.key)) .. R, note), 1, {
			buttons = stepper(function() return ns.PermissionRank(perm.key) end, function(v) ns.SetGuildSetting("perm:" .. perm.key, v) end),
		})
	end
	-- Rangos del addon (se ganan con reputación): nombres a gusto de la hermandad.
	ns.ApplyRankNames()
	for _, r in ipairs(ns.MERIT_RANKS) do
		local custom = r.label ~= r.defaultLabel
		local buttons
		if isGM then
			buttons = { { label = L["Renombrar"], onClick = function()
				ns.ShowInputDialog({
					title = (L["Renombrar «%s»"]):format(r.label),
					submit = L["Guardar"],
					fields = { { key = "name", label = L["Nombre"], width = 200, maxLetters = 24, default = r.label } },
					onSubmit = function(v)
						local name = (v.name or ""):gsub("|", "")
						if name == "" then return L["Escribe un nombre."] end
						ns.SetGuildSetting("rankName:" .. r.key, name ~= r.defaultLabel and name or nil)
					end,
				})
			end } }
			if custom then buttons[2] = { label = L["Restablecer"], onClick = function() ns.SetGuildSetting("rankName:" .. r.key, nil) end } end
		end
		line(rows, ("%s%s|r  %s"):format(GOLD, r.label, grey((L["rango del addon · %d de reputación"]):format(r.rep)
			.. (custom and ("  (" .. r.defaultLabel .. ")") or ""))), 1, { buttons = buttons })
	end
	if not isGM then line(rows, grey(L["Solo el maestro de hermandad puede cambiarlos."]), 1) end
end

views.settings = function()
	local rows = {}
	local p = LG.db.profile

	header(rows, L["Insignias sobre los marcos"])
	toggleRow(rows, L["Mostrar las insignias encima de mi marco"], ns.BannerSetting("player"),
		function() ns.SetBannerSetting("player", not ns.BannerSetting("player")); refresh() end)
	toggleRow(rows, L["Mostrar las insignias del objetivo"], ns.BannerSetting("target"),
		function() ns.SetBannerSetting("target", not ns.BannerSetting("target")); refresh() end)
	toggleRow(rows, L["Enseñar mis insignias a otros jugadores con el addon"], ns.BannerSetting("share"),
		function() ns.SetBannerSetting("share", not ns.BannerSetting("share")); refresh() end,
		{ L["Compartir insignias"], L["Si lo quitas, quien te seleccione fuera de tu hermandad no verá tus insignias."] })

	space(rows)
	header(rows, L["Avisos"])
	local modeLabel = ""
	for _, m in ipairs(ns.CALL_MODES) do
		if m.key == ns.CallToArmsMode() then modeLabel = m.label end
	end
	line(rows, L["Llamada a las armas: aviso cuando matan a un compañero"], 1, {
		tall = true, cols = { { L["Llamada a las armas: aviso cuando matan a un compañero"], 380 }, { GOLD .. modeLabel .. R, 120 } },
		buttons = { { label = L["Cambiar"], onClick = function() ns.CycleCallToArmsMode(); refresh() end } },
	})
	toggleRow(rows, L["Avisos de auxilio y asaltos de otras hermandades"], ns.AidSetting(), function() ns.ToggleAidSetting(); refresh() end)
	if LG:GuildData() then
		local on = ns.GuildSetting("guildChat", true)
		if ns.CanManageEvents(ns.PlayerFullName()) then
			toggleRow(rows, L["Anunciar en el chat de hermandad (subastas, pedidos, proyectos, eventos...)"], on,
				function() ns.SetGuildSetting("guildChat", not on); refresh() end,
				{ L["Chat de hermandad"], L["Lo escribe quien hace la acción, y lo ven también los que no tienen el addon. Es un ajuste de la hermandad: lo cambian los oficiales."] })
		else
			line(rows, grey((L["Anuncios en el chat de hermandad: %s (lo deciden los oficiales)."]):format(on and L["sí"] or L["no"])), 1)
		end
	end

	space(rows)
	header(rows, L["Interfaz"])
	toggleRow(rows, L["Botón del minimapa"], not p.minimap.hide, function() LG:SlashCommand("minimapa"); refresh() end)

	space(rows)
	header(rows, L["Privacidad"])
	local consent = LG.db.char.consent == "yes"
	line(rows, consent and L["Compartes tus datos con la hermandad."] or (RED .. L["No compartes datos: no sumas puntos ni ves los de la hermandad."] .. R), 1, {
		tall = true, buttons = { { label = L["Privacidad"], onClick = ns.ShowConsent } },
	})
	toggleRow(rows, L["Compartir la lista de mis personajes (alts)"], LG.db.char.optional.alts,
		function() LG:SlashCommand("opcional alts"); refresh() end)
	toggleRow(rows, L["Compartir mi tiempo jugado"], LG.db.char.optional.played,
		function() LG:SlashCommand("opcional jugado"); refresh() end)
	line(rows, L["Borrar mis datos aquí y en los addons de la hermandad"], 1, {
		tall = true, buttons = { { label = L["Borrar"], onClick = function() LG:SlashCommand("borrar") end } },
	})

	space(rows)
	ranksUI.view(rows)
	space(rows)
	header(rows, L["Pruebas"])
	toggleRow(rows, L["Modo prueba (tu grupo hace de hermandad)"], p.testMode, function() LG:SlashCommand("prueba") end)
	toggleRow(rows, L["Mensajes de depuración en el chat"], p.debug, function() LG:SlashCommand("debug"); refresh() end)
	space(rows)
	line(rows, grey((L["%s %s · /gmk para abrir la ventana"]):format(ns.ADDON_TITLE, LG.VERSION)))
	return rows
end

-- Abre JcJ en una sección: "targets", "wars" o "directory".
function ns.ShowHuntSection(key)
	subview.hunt = key
	if not frame or not frame:IsShown() then ns.ToggleMainFrame() end
	ns.SelectTab("hunt")
end

function ns.ShowWars() ns.ShowHuntSection("wars") end

---------------------------------------------------------------------------
-- Hermandad
---------------------------------------------------------------------------

local function memberCard(g, name, rows)
	local m = g.members[name]
	if not m then
		line(rows, grey(L["No tiene el addon: solo hay datos del roster."]), 2)
		return
	end
	local rank, _, rep = ns.MeritRank(name)
	local s = ns.Scores()[name] or { merits = 0 }
	local medals = 0
	for _, md in ipairs(ns.MemberMedals(name)) do
		if md.tier > 0 then medals = medals + 1 end
	end
	line(rows, (L["Medallas: %d de %d"]):format(medals, #ns.MEDALS), 2,
		{ buttons = { { label = L["Ver perfil"], onClick = function() ns.ToggleProfile(name) end } } })
	line(rows, ("%s %s%s|r  ·  %d rep  ·  %s%d|r %s  ·  %s"):format(L["Rango"], GOLD, rank.label, rep, GREEN, s.merits, L["insignias"],
		grey((L["idioma %s"]):format(m.locale or "?"))), 2)
	local profs = {}
	for _, p in pairs(m.prof or {}) do profs[#profs + 1] = ("%s %d/%d"):format(p.name or "?", p.rank or 0, p.max or 0) end
	table.sort(profs)
	if #profs > 0 then line(rows, L["Profesiones"] .. ": " .. table.concat(profs, "  ·  "), 2) end
	if m.pvp and m.pvp.hk then
		line(rows, ("%s: %d  ·  %s %s"):format(L["Muertes por honor"], m.pvp.hk, L["hoy"], tostring(m.pvp.today or 0)), 2)
	end
	local bg = ns.BGRecord(name)
	if bg.wins + bg.losses > 0 then
		line(rows, (L["Campos de batalla: %s%d|r victorias, %d derrotas  ·  %d golpes de gracia"]):format(GREEN, bg.wins, bg.losses, bg.kb), 2)
	end
	-- Mazmorras completadas: sus estadísticas de jefe final (Legacy.lua).
	local stats = name == ns.PlayerFullName() and ns.MyBossStats() or (type(m.bossStats) == "table" and m.bossStats or {})
	local done, seen = {}, {}
	for id, v in pairs(stats) do
		local info = ns.FINAL_BOSS_STATS[tonumber(id)]
		if info and not info.raid and (tonumber(v) or 0) > 0 and not seen[info.dungeon] then
			seen[info.dungeon] = true
			done[#done + 1] = info.dungeon
		end
	end
	if #done > 0 then
		table.sort(done)
		line(rows, (L["Mazmorras completadas (%d): %s"]):format(#done, table.concat(done, ", ")), 2)
	end
	local pr = ns.MemberPvPRank(name)
	if pr then
		local icon = ns.PvPRankIcon(pr.level)
		line(rows, (icon and ("|T%s:14|t "):format(icon) or "") .. (L["Rango JcJ: %d de %d"]):format(pr.level, pr.max)
			.. (pr.need > 0 and grey(("  ·  %d/%d"):format(pr.earned, pr.need)) or ""), 2)
	end
end

-- Icono pequeño del rango JcJ detrás del nombre, si tiene.
local function rankTag(name)
	local pr = ns.MemberPvPRank(name)
	local icon = pr and ns.PvPRankIcon(pr.level)
	return icon and (" |T%s:14|t"):format(icon) or ""
end

local function membersView(g, rows)
	local query = (searchBox:GetText() or ""):lower()
	local list, online, withAddon = {}, 0, 0
	for name, r in pairs(ns.roster) do
		if query == "" or name:lower():find(query, 1, true) then list[#list + 1] = { name = name, r = r, m = g.members[name] } end
		if r.online then online = online + 1 end
		if g.members[name] then withAddon = withAddon + 1 end
	end
	if LG:InTestMode() then
		for name, m in pairs(g.members) do
			if not ns.roster[name] and (query == "" or name:lower():find(query, 1, true)) then
				list[#list + 1] = { name = name, m = m, r = { class = m.class, level = m.level, rank = L["Ejemplo"], online = false } }
				withAddon = withAddon + 1
			end
		end
	end
	table.sort(list, function(a, b)
		if a.r.online ~= b.r.online then return a.r.online end
		return a.name < b.name
	end)
	header(rows, (#list == 1 and L["%d miembro · %d conectados · %d con el addon"] or L["%d miembros · %d conectados · %d con el addon"]):format(#list, online, withAddon))
	rows[#rows + 1] = { indent = 0, iconSpacer = 26, cols = { { grey(L["Nombre"]), 200 }, { grey(L["Nv"]), 34 }, { grey(L["Rango"]), 120 },
		{ grey(L["Insignias"]), 70 }, { grey(L["Zona"]), 120 }, { grey(L["Capa"]), 50 } } }
	for _, e in ipairs(list) do
		local open = isOpen("member|" .. e.name)
		local s = ns.Scores()[e.name]
		local rankLabel = e.m and ns.MeritRank(e.name).label or grey("-")
		rows[#rows + 1] = portraitFields(e.name, e.r.class, {
			indent = 0,
			tall = true,
			desaturate = not e.r.online,
			onClick = toggle("member|" .. e.name),
			cols = {
				{ (open and "[-] " or "[+] ") .. (e.r.online and ICON_ONLINE or ICON_OFFLINE) .. " " .. ns.ClassColorName(e.name, e.r.class) .. rankTag(e.name), 200 },
				{ tostring(e.r.level or "?"), 34 },
				{ (e.r.rank or "?") .. (e.m and grey(" · " .. rankLabel) or ""), 120 },
				{ s and (GREEN .. s.merits .. R) or grey("-"), 70 },
				{ e.r.online and (e.r.zone or "") or grey(L["desconectado"]), 120 },
				{ e.r.online and ns.MemberLayerText(e.name) or grey("-"), 50 },
			},
			tooltip = e.r.online and ns.MemberLayer(e.name) and { ns.ShortName(e.name),
				(L["Capa %s en %s (id del servidor: %d)."]):format(tostring(ns.LayerNumber(ns.MemberLayer(e.name), select(3, ns.MemberLayer(e.name))) or "?"),
					select(2, ns.MemberLayer(e.name)) or "?", ns.MemberLayer(e.name)),
				grey(L["Verde: misma capa que tú en tu zona; rojo: otra capa (no os veis). Las capas se numeran con las que ha visto la hermandad: al principio el número puede recolocarse."]) } or nil,
		})
		if open then memberCard(g, e.name, rows) end
	end
	if #list == 0 then line(rows, grey(L["Nadie coincide con la búsqueda."]), 1) end
end

-- Clasificación: reputación, recolectores o artesanos (de la semana).
local rankingMode = "rep"

local function medalText(i)
	local medal = i == 1 and GOLD or (i <= 3 and "|cffc0c0c0" or GREY)
	return medal .. ("%d."):format(i) .. R
end

local function weeklyRanking(g, rows, mode)
	local list = {}
	for name, m in pairs(g.members) do
		local gathered, crafted = ns.MemberWeekStats(m)
		local value = mode == "gather" and ((gathered.mining or 0) + (gathered.herb or 0) + (gathered.skinning or 0)) or crafted
		if value > 0 then list[#list + 1] = { name = name, m = m, value = value, gathered = gathered, crafted = crafted } end
	end
	table.sort(list, function(a, b) return a.value > b.value end)
	if mode == "gather" then
		rows[#rows + 1] = { indent = 0, cols = { { "", 30 }, { "", 22 }, { grey(L["Nombre"]), 200 }, { grey(L["Menas"]), 80 },
			{ grey(L["Hierbas"]), 80 }, { grey(L["Pieles"]), 80 }, { grey(L["Total"]), 70 } } }
	else
		rows[#rows + 1] = { indent = 0, cols = { { "", 30 }, { "", 22 }, { grey(L["Nombre"]), 200 }, { grey(L["Objetos fabricados"]), 160 } } }
	end
	if #list == 0 then
		line(rows, grey(mode == "gather" and L["Nadie ha recolectado esta semana. Cuenta lo que recoges con Minería, Herboristería y Desuello."]
			or L["Nadie ha fabricado esta semana."]), 1)
	end
	for i = 1, math.min(25, #list) do
		local e = list[i]
		local cols
		if mode == "gather" then
			cols = { { medalText(i), 30 }, { ns.ClassColorName(e.name, e.m.class), 200 }, { tostring(e.gathered.mining or 0), 80 },
				{ tostring(e.gathered.herb or 0), 80 }, { tostring(e.gathered.skinning or 0), 80 }, { GREEN .. e.value .. R, 70 } }
		else
			cols = { { medalText(i), 30 }, { ns.ClassColorName(e.name, e.m.class), 200 }, { GREEN .. e.value .. R, 160 } }
		end
		rows[#rows + 1] = portraitFields(e.name, e.m.class, { indent = 0, tall = true, iconOffset = 30, cols = cols })
	end
	line(rows, grey(L["Cuenta desde el miércoles. Lo cuenta el addon de cada uno y se comparte en su ficha."]), 1)
end

-- Clasificación por rango JcJ (lo que manda cada uno en su ficha).
local function pvpRanking(g, rows)
	local list = {}
	for name, m in pairs(g.members) do
		local pr = ns.MemberPvPRank(name) or { level = 0, earned = 0, need = 0 }
		local bg = ns.BGRecord(name)
		if pr.level > 0 or pr.earned > 0 or bg.wins + bg.losses > 0 then
			list[#list + 1] = { name = name, m = m, pr = pr, bg = bg, hk = m.pvp and tonumber(m.pvp.hk) or 0 }
		end
	end
	table.sort(list, function(a, b)
		if a.pr.level ~= b.pr.level then return a.pr.level > b.pr.level end
		if a.pr.earned ~= b.pr.earned then return a.pr.earned > b.pr.earned end
		if a.bg.wins ~= b.bg.wins then return a.bg.wins > b.bg.wins end
		return a.hk > b.hk
	end)
	rows[#rows + 1] = { indent = 0, cols = { { "", 30 }, { "", 22 }, { grey(L["Nombre"]), 180 }, { grey(L["Rango"]), 90 },
		{ grey(L["Progreso"]), 80 }, { grey(L["Campos de batalla"]), 120 }, { grey(L["Muertes por honor"]), 110 } } }
	if #list == 0 then
		line(rows, grey(L["Nadie tiene rango JcJ ni campos de batalla todavía. El rango se sube durante la temporada JcJ."]), 1)
	end
	for i = 1, math.min(25, #list) do
		local e = list[i]
		local icon = ns.PvPRankIcon(e.pr.level)
		rows[#rows + 1] = portraitFields(e.name, e.m.class, { indent = 0, tall = true, iconOffset = 30,
			cols = { { medalText(i), 30 }, { ns.ClassColorName(e.name, e.m.class), 180 },
				{ e.pr.level > 0 and ((icon and ("|T%s:16|t "):format(icon) or "") .. GOLD .. (L["Rango %d"]):format(e.pr.level) .. R) or grey("-"), 90 },
				{ e.pr.need > 0 and grey(("%d/%d"):format(e.pr.earned, e.pr.need)) or "", 80 },
				{ (e.bg.wins + e.bg.losses > 0) and ((L["%s%d|r V  ·  %d D"]):format(GREEN, e.bg.wins, e.bg.losses)) or grey("-"), 120 },
				{ tostring(e.hk), 110 } } })
	end
	line(rows, grey(L["Lo manda el addon de cada uno: el juego solo deja leer el rango propio."]), 1)
end

-- Personas: cazadores de la semana (kills y venganzas).
local function huntersRanking(g, rows)
	local s = ns.HuntStats(7)
	local revenges = {}
	for _, k in ipairs(s.recent) do
		if k.kind == "kill" and k.revenge and k.t >= ns.Now() - 7 * 86400 then revenges[k.killerName] = (revenges[k.killerName] or 0) + 1 end
	end
	rows[#rows + 1] = { indent = 0, cols = { { "", 30 }, { "", 22 }, { grey(L["Nombre"]), 200 }, { grey(L["Kills"]), 100 }, { grey(L["Venganzas"]), 100 } } }
	local list = sortedCounts(s.hunters, 25)
	if #list == 0 then line(rows, grey(L["Nadie todavía."]), 1) end
	for i, e in ipairs(list) do
		local m = g.members[e.key]
		rows[#rows + 1] = portraitFields(e.key, m and m.class, { indent = 0, tall = true, iconOffset = 30,
			cols = { { medalText(i), 30 }, { ns.ClassColorName(e.key, m and m.class), 200 }, { GREEN .. e.n .. R, 100 },
				{ revenges[e.key] and (GOLD .. revenges[e.key] .. R) or grey("-"), 100 } } })
	end
end

-- Personas: mazmorras distintas completadas (sus estadísticas de jefe final).
local function dungeonsRanking(g, rows)
	local list = {}
	for name, m in pairs(g.members) do
		local stats = name == ns.PlayerFullName() and ns.MyBossStats() or (type(m.bossStats) == "table" and m.bossStats or {})
		local seen, n, total = {}, 0, 0
		for id, v in pairs(stats) do
			local info = ns.FINAL_BOSS_STATS[tonumber(id)]
			if info and not info.raid and (tonumber(v) or 0) > 0 then
				total = total + (tonumber(v) or 0)
				if not seen[info.dungeon] then seen[info.dungeon] = true; n = n + 1 end
			end
		end
		if n > 0 then list[#list + 1] = { name = name, m = m, n = n, total = total } end
	end
	table.sort(list, function(a, b)
		if a.n ~= b.n then return a.n > b.n end
		return a.total > b.total
	end)
	rows[#rows + 1] = { indent = 0, cols = { { "", 30 }, { "", 22 }, { grey(L["Nombre"]), 200 }, { grey(L["Distintas"]), 100 }, { grey(L["Veces"]), 100 } } }
	if #list == 0 then line(rows, grey(L["Nadie todavía. Cuenta al completar una mazmorra (su jefe final)."]), 1) end
	for i = 1, math.min(25, #list) do
		local e = list[i]
		rows[#rows + 1] = portraitFields(e.name, e.m.class, { indent = 0, tall = true, iconOffset = 30,
			cols = { { medalText(i), 30 }, { ns.ClassColorName(e.name, e.m.class), 200 }, { GREEN .. e.n .. R, 100 }, { grey(tostring(e.total)), 100 } } })
	end
end

-- Personas: encargos entregados como artesano (los de los últimos 30 días).
local function ordersRanking(g, rows)
	local byCrafter = {}
	for _, o in pairs(g.orders) do
		if o.status == "done" and o.crafter and not ns.IsVoided(g, o.id) then
			local e = byCrafter[o.crafter] or { n = 0, verified = 0 }
			e.n = e.n + 1
			if o.verified then e.verified = e.verified + 1 end
			byCrafter[o.crafter] = e
		end
	end
	local list = {}
	for name, e in pairs(byCrafter) do list[#list + 1] = { name = name, n = e.n, verified = e.verified } end
	table.sort(list, function(x, y) return x.n > y.n end)
	rows[#rows + 1] = { indent = 0, cols = { { "", 30 }, { "", 22 }, { grey(L["Nombre"]), 200 }, { grey(L["Entregados"]), 100 }, { grey(L["Verificados"]), 100 } } }
	if #list == 0 then line(rows, grey(L["Nadie todavía."]), 1) end
	for i = 1, math.min(25, #list) do
		local e = list[i]
		local m = g.members[e.name] or ns.roster[e.name]
		rows[#rows + 1] = portraitFields(e.name, m and m.class, { indent = 0, tall = true, iconOffset = 30,
			cols = { { medalText(i), 30 }, { ns.ClassColorName(e.name, m and m.class), 200 }, { GREEN .. e.n .. R, 100 }, { grey(tostring(e.verified)), 100 } } })
	end
end

-- Clasificación de personas: reputación, cazadores, recolectores, encargos, mazmorras y JcJ.
local PEOPLE_MODES = {
	{ key = "rep", label = L["Reputación"], title = L["Clasificación por reputación"] },
	{ key = "hunt", label = L["Cazadores"], title = L["Cazadores de la semana"] },
	{ key = "gather", label = L["Recolectores"], title = L["Recolectores de la semana"] },
	{ key = "orders", label = L["Encargos"], title = L["Encargos entregados (30 días)"] },
	{ key = "dungeons", label = L["Mazmorras"], title = L["Mazmorras completadas"] },
	{ key = "pvp", label = L["JcJ"], title = L["Rango JcJ de la temporada"] },
}

local function rankingView(g, rows)
	local buttons, title = {}, nil
	for _, m in ipairs(PEOPLE_MODES) do
		if m.key == rankingMode then title = m.title end
		buttons[#buttons + 1] = { label = m.label, disabled = m.key == rankingMode, onClick = function() rankingMode = m.key; refresh() end }
	end
	local first, second = {}, {}
	for i, b in ipairs(buttons) do table.insert(i <= 3 and first or second, b) end
	header(rows, title or L["Clasificación"], { ns.PublishButton("ranking") })
	line(rows, "", 0, { buttons = first })
	line(rows, "", 0, { buttons = second })
	if rankingMode == "pvp" then pvpRanking(g, rows) return end
	if rankingMode == "orders" then ordersRanking(g, rows) return end
	if rankingMode == "hunt" then huntersRanking(g, rows) return end
	if rankingMode == "dungeons" then dungeonsRanking(g, rows) return end
	if rankingMode ~= "rep" then
		weeklyRanking(g, rows, rankingMode)
		return
	end

	local ranking = {}
	for name, s in pairs(ns.Scores()) do
		if g.members[name] or ns.roster[name] then ranking[#ranking + 1] = { name = name, s = s } end
	end
	table.sort(ranking, function(a, b) return a.s.rep > b.s.rep end)
	rows[#rows + 1] = { indent = 0, cols = { { "", 30 }, { "", 22 }, { grey(L["Nombre"]), 200 }, { grey(L["Rango"]), 110 }, { grey(L["Reputación"]), 100 }, { grey(L["Insignias"]), 90 } } }
	if #ranking == 0 then line(rows, grey(L["Todavía no hay puntos."]), 1) end
	for i = 1, math.min(25, #ranking) do
		local e = ranking[i]
		local m = g.members[e.name]
		-- El puesto va delante del retrato: se reserva su hueco con una columna vacía.
		local medal = i == 1 and GOLD or (i <= 3 and "|cffc0c0c0" or GREY)
		rows[#rows + 1] = portraitFields(e.name, m and m.class, {
			indent = 0,
			tall = true,
			iconOffset = 30,
			cols = { { medal .. ("%d."):format(i) .. R, 30 }, { ns.ClassColorName(e.name, m and m.class), 200 },
				{ GOLD .. ns.MeritRank(e.name).label .. R, 110 }, { tostring(e.s.rep), 100 }, { GREEN .. e.s.merits .. R, 90 } },
		})
	end
end

local function chronicleView(g, rows)
	header(rows, L["Mazmorras con la hermandad"])
	local runs = {}
	for _, r in pairs(g.runs) do runs[#runs + 1] = r end
	table.sort(runs, function(a, b) return a.t > b.t end)
	if #runs == 0 then line(rows, grey(L["Todavía no hay registros."]), 1) end
	-- En columnas: fecha, mazmorra (el nombre del juego), jefe, grupo de hermandad y testigos.
	for i = 1, math.min(20, #runs) do
		local r = runs[i]
		local witnesses = 0
		for _ in pairs(r.witnesses) do witnesses = witnesses + 1 end
		local full = r.raid and (r.guildCount >= r.size * 0.8) or r.guildCount >= 5
		local boss = (r.finalStat or r.criterion) and L["jefe final"] or (r.boss or "?")
		rows[#rows + 1] = { indent = 1, tall = true,
			icon = r.raid and "Interface\\Icons\\INV_Misc_Head_Dragon_01" or "Interface\\Icons\\INV_Misc_Key_03",
			cols = { { grey(date("%d/%m %H:%M", r.t)), 90 }, { r.instance or "?", 210 }, { grey(boss), 150 },
				{ (full and GREEN or GOLD) .. ("%d/%d"):format(r.guildCount or 0, r.size or 0) .. R, 60 },
				{ grey((L["%d testigos"]):format(witnesses)), 90 } } }
	end

	space(rows)
	header(rows, L["Eventos pasados"])
	local _, past = ns.EventLists()
	if #past == 0 then line(rows, grey(L["Todavía no hay."]), 1) end
	for i = 1, math.min(15, #past) do
		local e = past[i]
		local attended = 0
		for _ in pairs(g.attendance[e.id] or {}) do attended = attended + 1 end
		rows[#rows + 1] = { indent = 1, tall = true, icon = EVENT_ICONS[e.kind] or EVENT_ICONS.social,
			cols = { { grey(date("%d/%m %H:%M", e.start)), 90 }, { e.title or "?", 210 }, { grey(ns.EVENT_KIND_LABEL[e.kind] or ""), 150 },
				{ GREEN .. (L["%d asistentes"]):format(attended) .. R, 150 } } }
	end
end

---------------------------------------------------------------------------
-- Hermandad › Ahora: grupos y gente conectada
---------------------------------------------------------------------------

local ACTIVITY_KINDS = {
	dungeon = { label = L["Mazmorra"], icon = "Interface\\Icons\\INV_Misc_Key_03" },
	raid = { label = L["Banda"], icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
	bg = { label = L["Campo de batalla"], icon = "Interface\\Icons\\INV_BannerPVP_01" },
	war = { label = L["Guerra"], icon = "Interface\\Icons\\Ability_DualWield" },
	world = { label = L["Mundo"], icon = "Interface\\Icons\\INV_Misc_Map_01" },
}

local function nowView(g, rows)
	local me = ns.PlayerFullName()
	local groups, loose = ns.GuildActivity()

	-- Resumen: conectados y lo que ha pasado hoy.
	local s = ns.ActivitySummary()
	rows[#rows + 1] = {
		kind = "card", state = "normal",
		icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
		title = (L["%s%d|r conectados de %d"]):format(GREEN, s.online, s.members),
		desc = (L["%d con el addon  ·  %d en grupo  ·  %d en mazmorra, banda o JcJ"]):format(s.addon, s.grouped, s.instance),
		status = GOLD .. L["Hoy"] .. R,
		foot = (L["%d mazmorras (%d jefes)  ·  %d kills, %d muertes  ·  %d eventos  ·  %d logros"]):format(
			s.runs, s.bosses, s.kills, s.deaths, s.events, s.achievements),
	}
	space(rows)

	header(rows, L["Grupos ahora"])
	if #groups == 0 then line(rows, grey(L["Nadie de la hermandad está en grupo ahora mismo."]), 1) end
	for _, grp in ipairs(groups) do
		local kind = ACTIVITY_KINDS[grp.kind] or ACTIVITY_KINDS.world
		local names, mine = {}, false
		for _, m in ipairs(grp.members) do
			local info = g.members[m] or ns.roster[m]
			names[#names + 1] = ns.ClassColorName(m, info and info.class)
			if m == me then mine = true end
		end
		local leader = ns.ShortName(grp.members[1]) or "?"
		rows[#rows + 1] = {
			kind = "card", state = "normal",
			accent = grp.tribe and ns.ACCENT.action or (mine and ns.ACCENT.mine or nil),
			icon = grp.tribe and ns.TribeIconTexture(ns.TribeIcon(grp.tribe)) or kind.icon,
			iconBare = grp.tribe and select(2, ns.TribeIconTexture(ns.TribeIcon(grp.tribe))) or nil,
			iconCoords = grp.tribe and select(2, ns.TribeIconTexture(ns.TribeIcon(grp.tribe))) and { 0, 1, 0, 1 } or nil,
			title = grp.tribe and ("%s«%s»|r"):format(GOLD, grp.tribe.name) or (L["Grupo de %s"]):format(leader),
			desc = ("%s  ·  %s"):format(kind.label, grp.instance or grp.zone or "?"),
			status = (L["%d/%d de la hermandad"]):format(grp.guildCount, #grp.members),
			foot = table.concat(names, ", ") .. grey("  ·  " .. ago(grp.since or ns.Now())),
		}
	end

	-- Cerca de ti: miembros conectados en tu misma zona (la lista completa ya está en Miembros).
	space(rows)
	local myZone = GetZoneText and GetZoneText() or ""
	header(rows, (L["Cerca de ti · %s"]):format(myZone))
	local near = 0
	for _, p in ipairs(loose) do
		if p.name ~= me and (p.instance or p.zone) == myZone then
			near = near + 1
			local info = g.members[p.name] or ns.roster[p.name]
			local kind = ACTIVITY_KINDS[p.kind] or ACTIVITY_KINDS.world
			rows[#rows + 1] = portraitFields(p.name, info and info.class, {
				indent = 1, tall = true,
				cols = {
					{ ns.ClassColorName(p.name, info and info.class), 200 },
					{ grey(info and info.level and (L["nivel %d"]):format(info.level) or ""), 80 },
					{ p.noAddon and grey(L["sin el addon"]) or kind.label, 160 },
					{ p.since and grey(ago(p.since)) or "", 110 },
				},
			})
		end
	end
	if near == 0 then line(rows, grey(L["Nadie más de la hermandad en tu zona."]), 1) end
	space(rows)
	line(rows, grey(L["Con el addon se ve qué hace cada uno y con quién; sin él, solo su zona (en gris)."]))
end

---------------------------------------------------------------------------
-- Hermandad › Tribus
---------------------------------------------------------------------------

local function memberOptions()
	local names, seen = {}, {}
	local me = ns.PlayerFullName()
	local g = LG:GuildData()
	for name in pairs(ns.roster) do if name ~= me then seen[name] = true end end
	for name in pairs(g and g.members or {}) do if name ~= me then seen[name] = true end end
	for name in pairs(seen) do names[#names + 1] = name end
	table.sort(names)
	return { { items = names } }
end

function ns.ShowProposeTribe()
	ns.ShowInputDialog({
		title = (L["Crear: %s"]):format(ns.TribeWords().one),
		text = (L["De %d a %d jugadores de la hermandad que jugáis juntos, contándote a ti. Cada uno tiene que aceptar y un oficial dar el visto bueno."]):format(ns.TRIBE_MIN, ns.TribeMax()),
		fields = {
			{ key = "name", label = L["Nombre"], width = 200, maxLetters = 24 },
			{ key = "members", label = L["Miembros"], width = 230, options = memberOptions, multi = true },
		},
		submit = L["Proponer"],
		onSubmit = function(v)
			local list = {}
			for part in (v.members or ""):gmatch("[^,]+") do
				part = strtrim(part)
				if part ~= "" then list[#list + 1] = part end
			end
			return ns.ProposeTribe(v.name, list)
		end,
	})
end

-- Tribus: por qué se ordenan en su pestaña.
local TRIBE_MODES = {
	{ key = "dungeons", label = L["Mazmorras juntos"], value = function(s) return s.dungeons end,
		status = function(s) return (L["%d mazmorras juntos"]):format(s.dungeons) end },
	{ key = "best", label = L["Mejor tiempo"], value = function(s) return s.best and -s.best or -1e9 end,
		status = function(s) return (L["mejor tiempo %s"]):format(s.best and ns.FormatRunTime(s.best) or "-") end },
	{ key = "events", label = L["Eventos juntos"], value = function(s) return s.events end,
		status = function(s) return (L["%d eventos juntos"]):format(s.events) end },
	{ key = "kills", label = L["Kills"], value = function(s) return s.kills end,
		status = function(s) return (L["%d kills"]):format(s.kills) end },
}
local tribeMode = "dungeons"

local function tribesView(g, rows)
	local me = ns.PlayerFullName()
	local canManage = ns.CanManageEvents(me)
	local myTribe = ns.TribeOf(me)
	local W = ns.TribeWords()
	header(rows, (L["%s de la hermandad"]):format(W.Many), not myTribe and { { label = (L["Crear: %s"]):format(W.one), onClick = ns.ShowProposeTribe } } or nil)

	-- Invitaciones del líder de una tribu ya aprobada.
	for _, inv in ipairs(ns.MyTribeInvites()) do
		local tex, custom = ns.TribeIconTexture(ns.TribeIcon(inv.tribe))
		rows[#rows + 1] = {
			kind = "card", state = "normal", accent = ns.ACCENT.action,
			icon = tex, iconBare = custom, iconCoords = custom and { 0, 1, 0, 1 } or nil,
			title = ("«%s»"):format(inv.tribe.name),
			desc = (L["%s te invita a unirte."]):format(ns.ShortName(inv.by) or "?"),
			status = GOLD .. L["invitación"] .. R,
			foot = grey(ago(inv.t)),
			buttons = {
				{ label = L["Aceptar"], disabled = myTribe ~= nil, onClick = function() ns.AcceptTribe(inv.tribe.id) end,
					tooltip = myTribe and { L["Aceptar"], (L["Antes tienes que salir de «%s»."]):format(myTribe.name) } or nil },
				{ label = L["Rechazar"], onClick = function() ns.LeaveTribe(inv.tribe.id) end },
			},
		}
	end

	-- Propuestas pendientes: para aceptar (si estoy) o aprobar (oficiales).
	local pending = {}
	for _, tribe in pairs(g.tribes) do
		if tribe.status == "pending" and (tribe.members[me] or canManage) then pending[#pending + 1] = tribe end
	end
	table.sort(pending, function(a, b) return (a.t or 0) > (b.t or 0) end)
	for _, tribe in ipairs(pending) do
		local accepted = g.tribeAccepts[tribe.id] or {}
		local left = g.tribeLeft[tribe.id] or {}
		local names, total, ok = {}, 0, 0
		for name in pairs(tribe.members) do
			total = total + 1
			local yes = (accepted[name] or name == tribe.creator) and not left[name]
			if yes then ok = ok + 1 end
			names[#names + 1] = (yes and GREEN or GREY) .. ns.ShortName(name) .. R
		end
		table.sort(names)
		local buttons = {}
		local iAccepted = accepted[me] or tribe.creator == me
		if tribe.members[me] and not iAccepted and not left[me] then
			buttons[#buttons + 1] = { label = L["Aceptar"], onClick = function() ns.AcceptTribe(tribe.id) end }
			buttons[#buttons + 1] = { label = L["Rechazar"], onClick = function() ns.LeaveTribe(tribe.id) end }
		end
		if canManage then
			buttons[#buttons + 1] = { label = L["Aprobar"], disabled = ok < ns.TRIBE_MIN, onClick = function() ns.DecideTribe(tribe.id, "approved") end,
				tooltip = { L["Aprobar"], (L["Hace falta que acepten al menos %d."]):format(ns.TRIBE_MIN) } }
			buttons[#buttons + 1] = { label = L["Rechazar"], onClick = function() ns.DecideTribe(tribe.id, "rejected") end }
		end
		local tex, custom = ns.TribeIconTexture(ns.TribeIcon(tribe))
		rows[#rows + 1] = {
			kind = "card", state = "normal", accent = ns.ACCENT.action,
			icon = tex, iconBare = custom, iconCoords = custom and { 0, 1, 0, 1 } or nil,
			title = ("«%s»"):format(tribe.name),
			desc = table.concat(names, ", "),
			status = GOLD .. L["pendiente"] .. R,
			foot = grey((L["han aceptado %d de %d · propone %s"]):format(ok, total, ns.ShortName(tribe.creator))),
			buttons = #buttons > 0 and buttons or nil,
		}
	end

	-- Tribus activas, como clasificación (se ordenan por la categoría elegida).
	local stats = ns.TribeStats()
	local sortMode = TRIBE_MODES[1]
	for _, m in ipairs(TRIBE_MODES) do
		if m.key == tribeMode then sortMode = m end
	end
	table.sort(stats, function(x, y) return sortMode.value(x) > sortMode.value(y) end)
	if #stats > 1 then
		local sortButtons = {}
		for _, m in ipairs(TRIBE_MODES) do
			sortButtons[#sortButtons + 1] = { label = m.label, disabled = m.key == tribeMode, onClick = function() tribeMode = m.key; refresh() end }
		end
		line(rows, grey(L["Ordenar por:"]), 1, { buttons = sortButtons })
	end
	if #stats == 0 and #pending == 0 then
		line(rows, grey((L["Todavía no hay %s. Juntad a los jugadores con los que soléis ir."]):format(W.many)), 1,
			{ icon = ns.TribeIconTexture(ns.TRIBE_ICONS[(UnitFactionGroup("player") == "Alliance") and "Alliance" or "Horde"][1]),
				iconBare = true, iconCoords = { 0, 1, 0, 1 }, desaturate = true, tall = true })
	end
	for i, s in ipairs(stats) do
		local names, mine = {}, false
		for _, m in ipairs(s.members) do
			local info = g.members[m] or ns.roster[m]
			names[#names + 1] = ns.ClassColorName(m, info and info.class)
			if m == me then mine = true end
		end
		local buttons = {}
		local leader = ns.TribeLeader(g, s.tribe)
		if leader == me and #s.members < ns.TribeMax() then
			local id = s.tribe.id
			buttons[#buttons + 1] = { label = L["Invitar"], onClick = function()
				ns.ShowInputDialog({
					title = L["Invitar"],
					text = (L["¿A quién invitas a «%s»? Tiene que aceptar. Sin oficial: lo decides tú como líder."]):format(s.tribe.name),
					fields = { { key = "name", label = L["Miembro"], width = 220, options = memberOptions } },
					submit = L["Invitar"],
					onSubmit = function(v) return ns.InviteTribe(id, v.name) end,
				})
			end }
		end
		local current = ns.TribeIcon(s.tribe)
		if leader == me or canManage then
			local id = s.tribe.id
			local price = ns.ShopItem("tribeIcon").price
			buttons[#buttons + 1] = { label = ("%s · %d"):format(L["Icono"], price),
				tooltip = { L["Cambiar el icono"], (L["Cuesta %d insignias (tienes %d libres)."]):format(price, ns.AvailableInsignias(nil)) },
				onClick = function()
					ns.ShowIconPicker(current, function(icon)
						-- Cambiar el icono cuesta insignias (Shop.lua): se confirma antes de cobrar.
						ns.ShowInputDialog({
							title = L["Cambiar el icono"],
							text = (L["Cambiar el icono de la tribu cuesta %d insignias (tienes %d libres)."]):format(price, ns.AvailableInsignias(nil)),
							fields = {},
							submit = (L["Pagar %d"]):format(price),
							onSubmit = function()
								local ok, err = ns.Buy("tribeIcon", id)
								if not ok then return err end
								ns.SetTribeIcon(id, icon)
							end,
						})
					end)
				end }
		end
		if mine then buttons[#buttons + 1] = { label = L["Salir"], onClick = function() ns.LeaveTribe(s.tribe.id) end } end
		if canManage then buttons[#buttons + 1] = { label = L["Disolver"], onClick = function() ns.DecideTribe(s.tribe.id, "dissolved") end } end
		local medal = i == 1 and GOLD or (i <= 3 and "|cffc0c0c0" or GREY)
		local tex, custom = ns.TribeIconTexture(current)
		rows[#rows + 1] = {
			kind = "card", state = "normal", accent = mine and ns.ACCENT.mine or nil,
			icon = tex, iconBare = custom, iconCoords = custom and { 0, 1, 0, 1 } or nil,
			title = ("%s%d.|r  «%s»"):format(medal, i, s.tribe.name),
			desc = table.concat(names, ", "),
			-- A la derecha, el dato por el que se ordena; abajo, todos.
			status = GOLD .. sortMode.status(s) .. R,
			foot = grey((L["%d mazmorras juntos"]):format(s.dungeons) .. "  ·  " .. (L["mejor tiempo %s · %d eventos juntos · %d kills"]):format(s.best and ns.FormatRunTime(s.best) or "-", s.events, s.kills)),
			buttons = #buttons > 0 and buttons or nil,
		}
	end
	space(rows)
	line(rows, grey((L["Cuenta como jugar en grupo cuando hay %d o más de sus miembros en el mismo grupo: así sale en Ahora, en los tiempos y en las guerras. Es solo prestigio: no da insignias."]):format(ns.TRIBE_TOGETHER)))
end

views.guild = function()
	local g = LG:GuildData()
	if not g then return notInGuild() end
	local rows = {}
	local pendingTribes = 0
	local me = ns.PlayerFullName()
	for _, tribe in pairs(g.tribes) do
		if tribe.status == "pending" and tribe.members[me] and not (g.tribeAccepts[tribe.id] or {})[me] and tribe.creator ~= me then
			pendingTribes = pendingTribes + 1
		end
	end
	pendingTribes = pendingTribes + #ns.MyTribeInvites()
	segments(rows, "guild", {
		{ key = "now", label = L["Ahora"] },
		{ key = "members", label = L["Miembros"] },
		{ key = "tribes", label = pendingTribes > 0 and (ns.TribeWords().Many .. " (" .. pendingTribes .. ")") or ns.TribeWords().Many },
		{ key = "ranking", label = L["Clasificación"] },
		{ key = "chronicle", label = L["Crónica"] },
		{ key = "chest", label = L["Cofre"] },
	})
	if subview.guild == "ranking" then
		rankingView(g, rows)
	elseif subview.guild == "chronicle" then
		chronicleView(g, rows)
	elseif subview.guild == "chest" then
		chestUI.view(g, rows)
	elseif subview.guild == "now" then
		nowView(g, rows)
	elseif subview.guild == "tribes" then
		tribesView(g, rows)
	else
		membersView(g, rows)
	end
	rows.search = subview.guild == "members" and L["Buscar miembro..."] or nil
	return rows
end

---------------------------------------------------------------------------
-- Panel de oficial
---------------------------------------------------------------------------

local function showAdjustDialog()
	ns.ShowInputDialog({
		title = L["Ajustar puntos"],
		submit = L["Aplicar"],
		fields = {
			{ key = "name", label = L["Miembro"], width = 200 },
			{ key = "merits", label = L["Insignias (+/-)"], width = 60, numeric = true, signed = true, default = 0 },
			{ key = "rep", label = L["Reputación (+/-)"], width = 60, numeric = true, signed = true, default = 0 },
			{ key = "reason", label = L["Motivo"], width = 220 },
		},
		onSubmit = function(v)
			local member = ns.FindMember(v.name)
			if not member then return L["No encuentro a ese miembro."] end
			if (v.merits or 0) == 0 and (v.rep or 0) == 0 then return L["Pon insignias o reputación."] end
			if v.reason == "" then return L["Escribe el motivo: queda en el historial."] end
			ns.AdjustPoints(member, v.merits or 0, v.rep or 0, v.reason)
		end,
	})
end

local function showTargetDialog()
	ns.ShowInputDialog({
		title = L["Añadir hermandad objetivo"],
		submit = L["Añadir"],
		fields = { { key = "guild", label = L["Hermandad"], width = 220 } },
		onSubmit = function(v)
			if v.guild == "" then return L["Escribe el nombre de la hermandad."] end
			local g = LG:GuildData()
			if g and g.targets[v.guild] and g.targets[v.guild].active then return L["Ya es objetivo."] end
			ns.ToggleTarget(v.guild)
		end,
	})
end

-- Inactivos: plazos que se pueden elegir (días sin conectarse).
local INACTIVE_STEPS = { 14, 30, 60, 90 }
local inactiveDays = 30
local function indexOf(list, value)
	for i, v in ipairs(list) do if v == value then return i end end
	return 1
end

-- Nombre de un rango de la hermandad (0 = maestro de hermandad).
local function rankName(index)
	if GuildControlGetRankName then
		local ok, name = pcall(GuildControlGetRankName, index + 1)
		if ok and name and name ~= "" then return name end
	end
	for _, r in pairs(ns.roster) do
		if r.rankIndex == index and r.rank then return r.rank end
	end
	return (L["rango %d"]):format(index)
end

local function rankCount()
	if GuildControlGetNumRanks then
		local ok, n = pcall(GuildControlGetNumRanks)
		if ok and type(n) == "number" and n > 0 then return n end
	end
	local max = 0
	for _, r in pairs(ns.roster) do max = math.max(max, (r.rankIndex or 0) + 1) end
	return math.max(max, 2)
end

local ANOMALY_STYLE = {
	high = { icon = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew", tint = { 0.9, 0.2, 0.15 } },
	medium = { icon = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertOther", tint = { 0.95, 0.6, 0.1 } },
	info = { icon = "Interface\\FriendsFrame\\InformationIcon", tint = { 0.3, 0.6, 0.95 } },
}

views.officer = function()
	local g = LG:GuildData()
	if not g then return notInGuild() end
	local rows = {}

	-- Avisos de datos sospechosos: el addon señala, el oficial decide.
	local anomalies = ns.Anomalies()
	ANOMALY_KINDS = ANOMALY_KINDS or {
		hk = L["contador de honor"], hkdown = L["contador de honor"], hkseen = L["inspección de honor"],
		victim = L["misma víctima"], attend = L["asistencia"], orders = L["encargos"], adjust = L["ajuste grande"],
	}
	header(rows, L["Avisos"])
	if #anomalies == 0 then
		line(rows, GREEN .. L["Todo en orden: no hay nada sospechoso en los últimos 7 días."] .. R, 1,
			{ icon = "Interface\\RAIDFRAME\\ReadyCheck-Ready", tall = true })
	end
	for _, a in ipairs(anomalies) do
		local style = ANOMALY_STYLE[a.severity] or ANOMALY_STYLE.info
		local tooltip = { a.text }
		for _, d in ipairs(a.detail or {}) do tooltip[#tooltip + 1] = d end
		for i, it in ipairs(a.items or {}) do
			if i > 8 then
				tooltip[#tooltip + 1] = grey((L["... y %d más"]):format(#a.items - 8))
				break
			end
			tooltip[#tooltip + 1] = grey("- " .. it.label)
		end
		local buttons = {}
		if a.items and #a.items > 0 then
			local items = a.items
			buttons[#buttons + 1] = { label = (L["Anular (%d)"]):format(#items), onClick = function() ns.SetVoided(items, true) end,
				tooltip = { L["Anular"], L["Deja de dar puntos y de contar para los logros, en el addon de toda la hermandad. Se puede deshacer."] } }
		end
		local key = a.key
		buttons[#buttons + 1] = { label = L["Visto"], onClick = function() ns.DismissAnomaly(key) end,
			tooltip = { L["Visto"], L["Oculta el aviso solo para ti. Si la situación empeora, saldrá otro."] } }
		-- Tarjeta: quién y qué arriba, el texto entero debajo y el detalle abajo.
		local kind = ANOMALY_KINDS[(a.key or ""):match("^(%a+)")]
		local who = a.member and ns.ShortName(a.member) or nil
		local text = who and a.text:gsub("^" .. who:gsub("(%W)", "%%%1") .. ":%s*", "") or a.text
		rows[#rows + 1] = {
			kind = "card", state = "normal", accent = style.tint,
			icon = style.icon,
			title = (who or "") .. (kind and ((who and "  ·  " or "") .. kind) or ""),
			desc = text,
			foot = grey(date("%d/%m %H:%M", a.t or ns.Now()) .. (a.detail and a.detail[1] and ("  ·  " .. a.detail[1]) or "")),
			tooltip = tooltip, buttons = buttons,
		}
	end

	local voids = ns.RecentVoids(8)
	if #voids > 0 then
		space(rows)
		header(rows, L["Anulado"])
		for _, v in ipairs(voids) do
			local item = { id = v.id, kind = v.kind, member = v.member, label = v.label }
			line(rows, ("%s  %s  %s"):format(grey(date("%d/%m", v.t)), v.label or v.id, grey("(" .. (ns.ShortName(v.by) or "?") .. ")")), 1,
				{ buttons = { { label = L["Restaurar"], onClick = function() ns.SetVoided({ item }, false) end } } })
		end
	end

	space(rows)
	header(rows, L["Herramientas de oficial"])
	-- Cada herramienta en su fila, más alta y con su icono.
	line(rows, L["Eventos de la hermandad"], 1, { tall = true, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
		buttons = { { label = L["Nuevo evento"], onClick = ns.ShowEventDialog } } })
	line(rows, L["Subastar objetos del banco de la hermandad (lo que se pague va al cofre)"], 1, { tall = true, icon = "Interface\\Icons\\INV_Misc_Coin_02",
		buttons = { { label = L["Abrir subasta"], onClick = function() ns.ShowAuctionStart(nil, true) end } } })
	line(rows, L["Dar o quitar insignias y reputación"], 1, { tall = true, icon = "Interface\\Icons\\INV_Misc_Note_02",
		buttons = { { label = L["Ajustar"], onClick = showAdjustDialog } } })
	if LG:InTestMode() then
		line(rows, GOLD .. L["Modo prueba: datos de ejemplo para ver cómo queda la interfaz"] .. R, 1, { tall = true, icon = "Interface\\Icons\\INV_Misc_Book_09",
			buttons = { { label = L["Cargar"], onClick = ns.FillTestData }, { label = L["Borrar"], onClick = ns.RemoveTestData } } })
		line(rows, GOLD .. L["Modo prueba: ver el aviso de llamada a las armas"] .. R, 1, { tall = true, icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
			buttons = { { label = L["Probar aviso"], onClick = ns.TestCallToArms } } })
	end

	space(rows)
	header(rows, L["Hermandades objetivo puestas a mano"], { { label = L["Añadir"], onClick = showTargetDialog } })
	local manual = {}
	for guild, t in pairs(g.targets) do
		if t.active then manual[#manual + 1] = guild end
	end
	table.sort(manual)
	if #manual == 0 then line(rows, grey(L["Ninguna. Las que más nos matan entran solas."]), 1) end
	for _, guild in ipairs(manual) do
		local entry = ns.DirectoryEntry(guild)
		line(rows, RED .. "<" .. guild .. ">" .. R, 1, { tall = true,
			icon = ns.FactionBanner(entry and entry.faction or ((UnitFactionGroup("player") == "Alliance") and "Horde" or "Alliance")),
			buttons = { { label = L["Quitar"], onClick = function() ns.ToggleTarget(guild) end } } })
	end

	space(rows)
	header(rows, L["Últimos ajustes"])
	local adjustments = {}
	for _, a in pairs(g.adjustments) do adjustments[#adjustments + 1] = a end
	table.sort(adjustments, function(a, b) return a.t > b.t end)
	if #adjustments == 0 then line(rows, grey(L["Todavía no hay."]), 1) end
	for i = 1, math.min(10, #adjustments) do
		local a = adjustments[i]
		local m = g.members[a.member] or ns.roster[a.member]
		rows[#rows + 1] = portraitFields(a.member, m and m.class, { indent = 1, tall = true,
			cols = { { grey(date("%d/%m", a.t)), 50 }, { ns.ClassColorName(a.member, m and m.class), 150 },
				{ ("%s%+d|r %s  %s%+d|r rep"):format(GREEN, a.merits or 0, L["insignias"], GOLD, a.rep or 0), 170 },
				{ (a.reason or "") .. "  " .. grey("(" .. ns.ShortName(a.by) .. ")"), 220 } } })
	end
	-- Miembros que llevan tiempo sin conectarse (del roster del juego: tengan o no el addon).
	space(rows)
	local days = inactiveDays
	local inactive = {}
	for name, r in pairs(ns.roster) do
		if not r.online and (r.offlineHours or 0) >= days * 24 then inactive[#inactive + 1] = { name = name, r = r } end
	end
	table.sort(inactive, function(a, b) return (a.r.offlineHours or 0) > (b.r.offlineHours or 0) end)
	header(rows, (L["Inactivos (más de %d días)"]):format(days), { { label = (L["%d días"]):format(INACTIVE_STEPS[(indexOf(INACTIVE_STEPS, days) % #INACTIVE_STEPS) + 1]),
		onClick = function()
			inactiveDays = INACTIVE_STEPS[(indexOf(INACTIVE_STEPS, inactiveDays) % #INACTIVE_STEPS) + 1]
			refresh()
		end, tooltip = { L["Cambiar el plazo"] } } })
	if #inactive == 0 then line(rows, grey(L["Nadie."]), 1) end
	for i, e in ipairs(inactive) do
		if i > 25 then
			line(rows, grey((L["... y %d más"]):format(#inactive - 25)), 1)
			break
		end
		local m = g.members[e.name]
		rows[#rows + 1] = portraitFields(e.name, e.r.class, {
			indent = 1,
			cols = {
				{ ns.ClassColorName(e.name, e.r.class), 200 },
				{ grey(e.r.rank or "?"), 120 },
				{ grey((L["nivel %d"]):format(e.r.level or 0)), 70 },
				{ (L["%d días"]):format(math.floor((e.r.offlineHours or 0) / 24)), 80 },
				{ m and grey(L["con el addon"]) or "", 110 },
			},
		})
	end

	space(rows)
	line(rows, grey(L["Quién es oficial y qué puede hacer cada rango: Ajustes › Rangos y permisos."]), 0)
	return rows
end

---------------------------------------------------------------------------
-- Filas
---------------------------------------------------------------------------

local CAL_W, CAL_H, CAL_GAP = 94, 50, 3 -- celdas del calendario (7 × 94 + huecos caben en 690)
local CAL_TOP = 58                       -- barra del mes + nombres de los días
local HEIGHTS = { header = 26, row = 20, bar = 20, space = 8, tall = 32, calendar = CAL_TOP + 6 * (CAL_H + CAL_GAP) + 4 }
local rowPool = {}

---------------------------------------------------------------------------
-- Calendario (fila kind = "calendar")
---------------------------------------------------------------------------

local function createCalendar(row)
	local cal = CreateFrame("Frame", nil, row)
	cal:SetPoint("TOPLEFT", row, "TOPLEFT", 6, 0)
	cal:SetSize(7 * (CAL_W + CAL_GAP), HEIGHTS.calendar)

	cal.prev = CreateFrame("Button", nil, cal, "UIPanelButtonTemplate")
	cal.prev:SetSize(30, 22)
	cal.prev:SetPoint("TOPLEFT", 0, -4)
	cal.prev:SetText("<")
	cal.next = CreateFrame("Button", nil, cal, "UIPanelButtonTemplate")
	cal.next:SetSize(30, 22)
	cal.next:SetPoint("LEFT", cal.prev, "RIGHT", 4, 0)
	cal.title = cal:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	cal.title:SetPoint("LEFT", cal.next, "RIGHT", 12, 0)
	cal.next:SetText(">")
	cal.today = CreateFrame("Button", nil, cal, "UIPanelButtonTemplate")
	cal.today:SetSize(70, 22)
	cal.today:SetPoint("TOPRIGHT", 0, -4)
	cal.today:SetText(L["Hoy"])

	cal.weekdays = {}
	for i = 1, 7 do
		local fs = cal:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("TOPLEFT", (i - 1) * (CAL_W + CAL_GAP), -36)
		fs:SetWidth(CAL_W)
		fs:SetJustifyH("CENTER")
		fs:SetText(ns.WEEKDAYS_SHORT[i])
		cal.weekdays[i] = fs
	end

	cal.cells = {}
	for i = 1, 42 do
		local col, rowIndex = (i - 1) % 7, math.floor((i - 1) / 7)
		local cell = CreateFrame("Button", nil, cal)
		cell:SetSize(CAL_W, CAL_H)
		cell:SetPoint("TOPLEFT", col * (CAL_W + CAL_GAP), -CAL_TOP - rowIndex * (CAL_H + CAL_GAP))
		-- Borde (color según hoy / elegido) y fondo dentro.
		cell.edge = cell:CreateTexture(nil, "BACKGROUND")
		cell.edge:SetAllPoints()
		cell.bg = cell:CreateTexture(nil, "BORDER")
		cell.bg:SetPoint("TOPLEFT", 1, -1)
		cell.bg:SetPoint("BOTTOMRIGHT", -1, 1)
		cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		cell.day = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cell.day:SetPoint("TOPLEFT", 5, -4)
		cell.mine = cell:CreateTexture(nil, "OVERLAY")
		cell.mine:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
		cell.mine:SetSize(12, 12)
		cell.mine:SetPoint("TOPRIGHT", -4, -4)
		cell.icons = {}
		for k = 1, 4 do
			local icon = cell:CreateTexture(nil, "ARTWORK")
			icon:SetSize(18, 18)
			icon:SetPoint("BOTTOMLEFT", 4 + (k - 1) * 21, 4)
			icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			cell.icons[k] = icon
		end
		cal.cells[i] = cell
	end
	row.cal = cal
	return cal
end

local function layoutCalendar(row, spec)
	local cal = row.cal or createCalendar(row)
	cal:Show()
	cal.title:SetText(("%s %d"):format(ns.MONTH_NAMES[spec.month], spec.year))
	cal.prev:SetScript("OnClick", function() spec.onMonth(-1) end)
	cal.next:SetScript("OnClick", function() spec.onMonth(1) end)
	cal.today:SetScript("OnClick", spec.onToday)

	local first = time({ year = spec.year, month = spec.month, day = 1, hour = 12 })
	local offset = (tonumber(date("%w", first)) + 6) % 7 -- lunes = 0
	local daysInMonth = tonumber(date("%d", time({ year = spec.year, month = spec.month + 1, day = 0, hour = 12 })))
	local today = date("*t", ns.Now())
	local isThisMonth = today.year == spec.year and today.month == spec.month

	for i, cell in ipairs(cal.cells) do
		local day = i - offset
		local inMonth = day >= 1 and day <= daysInMonth
		cell:SetShown(inMonth or i <= 35) -- la sexta fila solo si hace falta
		cell:EnableMouse(inMonth)
		for _, icon in ipairs(cell.icons) do icon:Hide() end
		cell.mine:Hide()
		cell:SetScript("OnEnter", nil)
		cell:SetScript("OnLeave", nil)
		if not inMonth then
			cell.day:SetText("")
			cell.edge:SetColorTexture(0.12, 0.1, 0.07, 0.6)
			cell.bg:SetColorTexture(0.07, 0.06, 0.04, 0.6)
			cell:SetScript("OnClick", nil)
		else
			local key = ("%04d-%02d-%02d"):format(spec.year, spec.month, day)
			local data = spec.days[day]
			local isToday = isThisMonth and today.day == day
			local isPast = not isToday and time({ year = spec.year, month = spec.month, day = day, hour = 23, min = 59 }) < ns.Now()
			cell.day:SetText((isToday and GOLD or (isPast and GREY or "|cffffffff")) .. day .. R)
			if spec.selected == key then
				cell.edge:SetColorTexture(1, 0.82, 0, 1)
				cell.bg:SetColorTexture(0.28, 0.22, 0.08, 0.95)
			elseif isToday then
				cell.edge:SetColorTexture(0.75, 0.58, 0.2, 1)
				cell.bg:SetColorTexture(0.16, 0.12, 0.07, 0.95)
			else
				cell.edge:SetColorTexture(0.23, 0.18, 0.12, 1)
				cell.bg:SetColorTexture(data and 0.16 or 0.1, data and 0.12 or 0.08, data and 0.08 or 0.06, 0.92)
			end
			if data then
				-- Iconos: guerras primero (espadas), luego los tipos de evento.
				local k = 0
				for _, w in ipairs(data.wars) do
					k = k + 1
					if k <= 4 then
						cell.icons[k]:SetTexture("Interface\\Icons\\Ability_DualWield")
						cell.icons[k]:SetDesaturated(isPast)
						cell.icons[k]:Show()
					end
				end
				for _, e in ipairs(data.events) do
					k = k + 1
					if k <= 4 then
						cell.icons[k]:SetTexture(EVENT_ICONS[e.kind] or "Interface\\Icons\\INV_Misc_QuestionMark")
						cell.icons[k]:SetDesaturated(isPast)
						cell.icons[k]:Show()
					end
					local s = spec.signups[e.id] and spec.signups[e.id][spec.me]
					if s and s.status == "yes" then cell.mine:Show() end
				end
				cell:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(dayLabel(time({ year = spec.year, month = spec.month, day = day, hour = 12 })))
					for _, w in ipairs(data.wars) do
						GameTooltip:AddLine(("%s  %s"):format(date("%H:%M", w.start), (L["Guerra contra <%s>"]):format(ns.WarEnemy(w))), 1, 0.42, 0.35)
					end
					for _, e in ipairs(data.events) do
						GameTooltip:AddLine(("%s  %s (%s)"):format(date("%H:%M", e.start), e.title, ns.EVENT_KIND_LABEL[e.kind] or ""), 1, 1, 1)
					end
					GameTooltip:Show()
				end)
				cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
			end
			cell:SetScript("OnClick", function() spec.onDay(day) end)
			cell:SetScript("OnDoubleClick", spec.onDayDouble and function() spec.onDayDouble(day) end or nil)
		end
	end
end

local function getRow(i)
	local row = rowPool[i]
	if row then return row end
	row = CreateFrame("Button", nil, scrollChild)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)

	row.cells = {}
	for c = 1, MAX_COLS do
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		row.cells[c] = fs
	end

	-- Fondo tintado y franja de color a la izquierda (p. ej. verde = caza, rojo = muerte).
	row.tint = row:CreateTexture(nil, "BACKGROUND")
	row.tint:SetPoint("TOPLEFT", 0, -1)
	row.tint:SetPoint("BOTTOMRIGHT", 0, 1) -- 2 px de aire entre filas tintadas
	row.stripe = row:CreateTexture(nil, "BORDER")
	row.stripe:SetWidth(3)
	row.stripe:SetPoint("TOPLEFT", 0, -1)
	row.stripe:SetPoint("BOTTOMLEFT", 0, 1)

	-- Icono opcional a la izquierda, con un marco del color de la calidad del objeto.
	row.iconBorder = row:CreateTexture(nil, "BORDER")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	-- Máscaras redondas para los retratos (si el cliente las tiene).
	row.iconMask = row.CreateMaskTexture and row:CreateMaskTexture() or nil
	row.borderMask = row.iconMask and row:CreateMaskTexture() or nil
	if row.iconMask and row.borderMask and row.icon.AddMaskTexture then
		row.iconMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		row.iconMask:SetAllPoints(row.icon)
		row.borderMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		row.borderMask:SetAllPoints(row.iconBorder)
	else
		row.iconMask, row.borderMask = nil, nil
	end
	row.iconMasked = false

	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetHeight(1)
	row.line:SetColorTexture(1, 0.82, 0, 0.35)
	row.line:SetPoint("BOTTOMLEFT", 4, 2)
	row.line:SetPoint("BOTTOMRIGHT", -4, 2)

	row.bar = CreateFrame("StatusBar", nil, row)
	row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	row.bar:SetHeight(14)
	row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND")
	row.bar.bg:SetAllPoints()
	row.bar.bg:SetColorTexture(0.25, 0.22, 0.15, 0.9)
	row.bar.value = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.bar.value:SetPoint("CENTER")

	row.buttons = {}
	for b = 1, MAX_BUTTONS do
		local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		btn:SetSize(84, 19)
		if b == 1 then btn:SetPoint("RIGHT", row, "RIGHT", -4, 0) else btn:SetPoint("RIGHT", row.buttons[b - 1], "LEFT", -3, 0) end
		row.buttons[b] = btn
	end
	rowPool[i] = row
	return row
end

---------------------------------------------------------------------------
-- Tarjetas (fila kind = "card"), como las de los desafíos de legado:
--   { kind = "card", icon, iconColor (solo objetos: color de calidad), title, desc,
--     status, foot, state = "normal" | "off", accent = { r, g, b } (franja a la
--     izquierda para lo que pide atención), desaturate, onClick, tooltip, buttons }
-- Los botones van abajo a la derecha, el estado arriba a la derecha y el pie es
-- la tercera línea, a la izquierda.
---------------------------------------------------------------------------

local CARD_H = 82
local CARD_ART = {
	normal = { "Legacy-Challenge-Cards", 0.15, 0.12, 0.07 },
	off = { "Legacy-Challenge-Cards-Disable", 0.09, 0.08, 0.06 },
}
-- Colores de la franja.
ns.ACCENT = {
	active = { 0.85, 0.22, 0.15 },  -- en curso
	action = { 1, 0.78, 0.2 },      -- te toca decidir
	good = { 0.3, 0.85, 0.3 },      -- va bien (vas ganando, estás apuntado)
	mine = { 0.4, 0.65, 1 },        -- tuyo
}

local function cardArt(texture, state)
	local art = CARD_ART[state] or CARD_ART.normal
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(art[1]) then
		texture:SetAtlas(art[1])
		texture:SetVertexColor(1, 1, 1, 1)
	else
		texture:SetColorTexture(art[2], art[3], art[4], 0.95)
	end
end

local function getCardParts(row)
	if row.card then return row.card end
	local c = {}
	c.bg = row:CreateTexture(nil, "BACKGROUND")
	c.bg:SetPoint("BOTTOMRIGHT", 0, 2)
	c.accent = row:CreateTexture(nil, "BORDER")
	c.accent:SetWidth(4)
	c.glow = row:CreateTexture(nil, "BORDER")
	c.glow:SetWidth(90)
	c.glow:SetTexture("Interface\\Buttons\\WHITE8x8")
	c.iconBorder = row:CreateTexture(nil, "BORDER")
	c.iconBorder:SetSize(48, 48)
	c.icon = row:CreateTexture(nil, "ARTWORK")
	c.icon:SetSize(44, 44)
	c.icon:SetPoint("CENTER", c.iconBorder, "CENTER")
	c.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	c.title:SetJustifyH("LEFT")
	c.title:SetWordWrap(false)
	c.desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	c.desc:SetJustifyH("LEFT")
	c.desc:SetWordWrap(false)
	c.foot = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.foot:SetJustifyH("LEFT")
	c.foot:SetWordWrap(false)
	c.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	c.status:SetPoint("TOPRIGHT", row, "TOPRIGHT", -14, -14)
	c.status:SetJustifyH("RIGHT")
	row.card = c
	return c
end

local function showCardParts(row, shown)
	if not row.card then return end
	for _, part in pairs(row.card) do part:SetShown(shown) end
end

local function layoutCard(row, spec, indentX)
	local c = getCardParts(row)
	showCardParts(row, true)
	row:SetHeight(CARD_H)
	cardArt(c.bg, spec.state)
	c.bg:SetPoint("TOPLEFT", indentX - 6, -2)

	-- Franja de color a la izquierda (y un brillo muy suave) para lo que pide atención.
	local accent = spec.accent
	c.accent:SetShown(accent ~= nil)
	c.glow:SetShown(accent ~= nil)
	if accent then
		c.accent:ClearAllPoints()
		c.accent:SetPoint("TOPLEFT", row, "TOPLEFT", indentX - 3, -8)
		c.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", indentX - 3, 8)
		c.accent:SetColorTexture(accent[1], accent[2], accent[3], 0.95)
		c.glow:ClearAllPoints()
		c.glow:SetPoint("TOPLEFT", c.accent, "TOPRIGHT")
		c.glow:SetPoint("BOTTOMLEFT", c.accent, "BOTTOMRIGHT")
		c.glow:SetGradient("HORIZONTAL", CreateColor and CreateColor(accent[1], accent[2], accent[3], 0.18) or { r = accent[1], g = accent[2], b = accent[3], a = 0.18 },
			CreateColor and CreateColor(accent[1], accent[2], accent[3], 0) or { r = accent[1], g = accent[2], b = accent[3], a = 0 })
	end

	-- Icono con marco dorado, como en Desafíos; los objetos, con el color de su calidad.
	c.iconBorder:ClearAllPoints()
	c.iconBorder:SetPoint("LEFT", row, "LEFT", indentX + 10, 0)
	local col = (spec.link and spec.iconColor) or (spec.state == "off" and { 0.35, 0.32, 0.28 } or { 0.78, 0.62, 0.25 })
	c.iconBorder:SetColorTexture(col[1], col[2], col[3], spec.iconBare and 0 or 1) -- los iconos propios traen su marco
	c.icon:SetTexture(spec.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	if spec.iconCoords then c.icon:SetTexCoord(unpack(spec.iconCoords)) else c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
	c.icon:SetDesaturated(spec.desaturate or spec.state == "off")

	-- Botones abajo a la derecha (los demás se encadenan a la izquierda del primero).
	local first = row.buttons[1]
	first:ClearAllPoints()
	first:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -12, 10)
	local buttonsWidth = 0
	for _, btn in ipairs(row.buttons) do
		if btn:IsShown() then buttonsWidth = buttonsWidth + btn:GetWidth() + 3 end
	end

	local left = indentX + 72
	local full = CONTENT_WIDTH - left - 14
	c.title:ClearAllPoints()
	c.title:SetPoint("TOPLEFT", row, "TOPLEFT", left, -14)
	c.title:SetWidth(math.max(60, full - 150)) -- deja sitio al estado de arriba a la derecha
	c.title:SetText((spec.state == "off" and GREY or "|cffffffff") .. (spec.title or "") .. R)
	c.desc:ClearAllPoints()
	c.desc:SetPoint("TOPLEFT", row, "TOPLEFT", left, -38)
	c.desc:SetWidth(math.max(60, full - 150))
	c.desc:SetText(spec.desc or "")
	c.foot:ClearAllPoints()
	c.foot:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left, 13)
	c.foot:SetWidth(math.max(60, full - (buttonsWidth > 0 and buttonsWidth + 12 or 0)))
	c.foot:SetText(spec.foot or "")
	c.status:SetText(spec.status or "")
end

---------------------------------------------------------------------------
-- Tarjeta de la hermandad en la temporada (fila kind = "crest"): el tabardo de
-- la hermandad, el escudo de su liga, la barra hacia la siguiente liga y los
-- botones abajo a la derecha.
--   { kind = "crest", title, desc, league = { label, color, art }, bar = { min, max, value, text },
--     status, foot, buttons, tooltip }
---------------------------------------------------------------------------

local CREST_H = 104

local function getCrestParts(row)
	if row.crest then return row.crest end
	local c = {}
	c.bg = row:CreateTexture(nil, "BACKGROUND")
	c.bg:SetPoint("BOTTOMRIGHT", 0, 2)
	-- Tabardo: fondo, borde y emblema, con las mismas piezas que la invitación a
	-- hermandad de Blizzard (GuildInviteFrame): el color lo pone el juego.
	c.tabardBg = row:CreateTexture(nil, "BORDER")
	c.tabardBg:SetSize(62, 62)
	c.tabardBg:SetTexture("Interface\\GuildFrame\\GuildFrame")
	c.tabardBg:SetTexCoord(0.63183594, 0.69238281, 0.61914063, 0.74023438)
	c.tabardBorder = row:CreateTexture(nil, "OVERLAY")
	c.tabardBorder:SetSize(61, 60)
	c.tabardBorder:SetPoint("TOPLEFT", c.tabardBg, "TOPLEFT", 1, -1)
	c.tabardBorder:SetTexture("Interface\\GuildFrame\\GuildFrame")
	c.tabardBorder:SetTexCoord(0.63183594, 0.69238281, 0.74414063, 0.86523438)
	c.tabardEmblem = row:CreateTexture(nil, "ARTWORK")
	c.tabardEmblem:SetSize(56, 64)
	c.tabardEmblem:SetPoint("CENTER", c.tabardBg, "CENTER")
	-- Escudo de la liga.
	c.league = row:CreateTexture(nil, "ARTWORK")
	c.league:SetSize(62, 62)
	c.leagueText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	c.leagueText:SetPoint("TOP", c.league, "BOTTOM", 0, 2)
	c.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	c.title:SetJustifyH("LEFT")
	c.desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	c.desc:SetJustifyH("LEFT")
	c.bar = CreateFrame("StatusBar", nil, row)
	c.bar:SetSize(260, 12)
	local fill = c.bar:CreateTexture(nil, "ARTWORK")
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Legacy-Progressbar-Fill") then fill:SetAtlas("Legacy-Progressbar-Fill")
	else fill:SetColorTexture(0.85, 0.65, 0.1, 1) end
	c.bar:SetStatusBarTexture(fill)
	c.bar.bg = c.bar:CreateTexture(nil, "BACKGROUND")
	c.bar.bg:SetAllPoints()
	c.bar.bg:SetColorTexture(0, 0, 0, 0.55)
	c.bar.text = c.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.bar.text:SetPoint("CENTER")
	c.foot = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.foot:SetJustifyH("LEFT")
	c.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	c.status:SetPoint("TOPRIGHT", row, "TOPRIGHT", -14, -14)
	c.status:SetJustifyH("RIGHT")
	row.crest = c
	return c
end

local function showCrestParts(row, shown)
	if not row.crest then return end
	for _, part in pairs(row.crest) do part:SetShown(shown) end
end

-- Pinta el tabardo de tu hermandad; si no hay (sin hermandad, sin tabardo), el emblema del addon.
local function paintTabard(c)
	-- En Forever (cliente de retail) el tabardo se pide con C_GuildInfo.GetGuildTabardInfo.
	-- Sin tabardo diseñado, la misma función de Blizzard pinta el estandarte gris
	-- que se ve en la ventana de hermandad del juego.
	if IsInGuild and IsInGuild() and SetLargeGuildTabardTextures then
		local info
		if C_GuildInfo and C_GuildInfo.GetGuildTabardInfo then
			local ok, data = pcall(C_GuildInfo.GetGuildTabardInfo, "player")
			info = ok and data or nil
		end
		c.tabardEmblem:SetSize(56, 64)
		local ok = pcall(SetLargeGuildTabardTextures, "player", c.tabardEmblem, c.tabardBg, c.tabardBorder, info)
		if ok then
			c.tabardBg:Show(); c.tabardBorder:Show()
			return
		end
	end
	-- Sin hermandad: el emblema del addon.
	c.tabardBg:Hide(); c.tabardBorder:Hide()
	c.tabardEmblem:SetTexture(ns.MEDIA .. "emblem_small")
	c.tabardEmblem:SetTexCoord(0, 1, 0, 1)
	c.tabardEmblem:SetSize(60, 60)
	c.tabardEmblem:SetVertexColor(1, 1, 1, 1)
end

local function layoutCrest(row, spec, indentX)
	local c = getCrestParts(row)
	showCrestParts(row, true)
	row:SetHeight(CREST_H)
	cardArt(c.bg, "normal")
	c.bg:SetPoint("TOPLEFT", indentX - 6, -2)

	c.tabardBg:ClearAllPoints()
	c.tabardBg:SetPoint("LEFT", row, "LEFT", indentX + 12, 0)
	paintTabard(c)

	-- Escudo de la liga: diseño propio si existe (league.art) o el escudo de legado teñido.
	local league = spec.league or {}
	c.league:ClearAllPoints()
	c.league:SetPoint("LEFT", c.tabardBg, "RIGHT", 14, 6)
	if league.art then
		c.league:SetTexture(league.art)
		c.league:SetVertexColor(1, 1, 1, 1)
		c.league:SetDesaturated(false)
	else
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-Legacy-Points-icon-c60") then
			c.league:SetAtlas("UI-Legacy-Points-icon-c60")
		else
			c.league:SetTexture("Interface\\Icons\\INV_Shield_05")
		end
		c.league:SetDesaturated(true)
		local col = league.color or { 1, 1, 1 }
		c.league:SetVertexColor(col[1] * 1.15, col[2] * 1.15, col[3] * 1.15, 1)
	end
	local col = league.color or { 1, 1, 1 }
	c.leagueText:SetText(league.label or "")
	c.leagueText:SetTextColor(col[1], col[2], col[3])

	local left = indentX + 168
	c.title:ClearAllPoints()
	c.title:SetPoint("TOPLEFT", row, "TOPLEFT", left, -16)
	c.title:SetText("|cffffffff" .. (spec.title or "") .. R)
	c.desc:ClearAllPoints()
	c.desc:SetPoint("TOPLEFT", row, "TOPLEFT", left, -40)
	c.desc:SetText(spec.desc or "")
	local bar = spec.bar
	c.bar:SetShown(bar ~= nil)
	if bar then
		c.bar:ClearAllPoints()
		c.bar:SetPoint("TOPLEFT", row, "TOPLEFT", left, -60)
		c.bar:SetMinMaxValues(bar.min or 0, math.max((bar.min or 0) + 1, bar.max or 1))
		c.bar:SetValue(bar.value or 0)
		c.bar:SetStatusBarColor(col[1], col[2], col[3])
		c.bar.text:SetText(bar.text or "")
	end
	c.foot:ClearAllPoints()
	c.foot:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left, 12)
	c.foot:SetText(spec.foot or "")
	c.status:SetText(spec.status or "")

	local first = row.buttons[1]
	first:ClearAllPoints()
	first:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -12, 10)
end

local function layoutRow(row, spec)
	local kind = spec.kind or "row"
	local indentX = 6 + (spec.indent or 0) * 18
	local height = spec.height or (spec.tall and HEIGHTS.tall) or HEIGHTS[kind] or 20
	row:SetHeight(height)
	if kind ~= "crest" then showCrestParts(row, false) end
	if kind ~= "card" and kind ~= "crest" then
		showCardParts(row, false)
		-- Las tarjetas mueven los botones abajo; en las filas van centrados a la derecha.
		row.buttons[1]:ClearAllPoints()
		row.buttons[1]:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	end

	-- El calendario ocupa la fila entera con sus propias celdas.
	if row.cal then row.cal:SetShown(kind == "calendar") end
	if kind == "calendar" then
		row.text:Hide()
		for _, fs in ipairs(row.cells) do fs:Hide() end
		for _, btn in ipairs(row.buttons) do btn:Hide() end
		row.bar:Hide(); row.icon:Hide(); row.iconBorder:Hide(); row.tint:Hide(); row.stripe:Hide(); row.line:Hide()
		row:SetScript("OnClick", nil)
		row:SetScript("OnEnter", nil)
		row:SetScript("OnLeave", nil)
		row:EnableMouse(false)
		layoutCalendar(row, spec)
		return
	end

	-- Icono: el contenido empieza a su derecha.
	local contentX = indentX
	row.icon:SetShown(spec.icon ~= nil)
	row.iconBorder:SetShown(spec.icon ~= nil)
	if spec.iconSpacer then
		-- Cabecera de columnas: deja el mismo hueco que el icono de las filas de debajo.
		contentX = indentX + spec.iconSpacer + 8
	end
	-- Retratos: recorte redondo (el icono y, algo mayor detrás, el aro de color).
	local round = spec.portrait and row.iconMask ~= nil
	if row.iconMasked ~= round then
		if round then
			row.icon:AddMaskTexture(row.iconMask)
			row.iconBorder:AddMaskTexture(row.borderMask)
		elseif row.iconMask then
			row.icon:RemoveMaskTexture(row.iconMask)
			row.iconBorder:RemoveMaskTexture(row.borderMask)
		end
		row.iconMasked = round
	end
	if spec.icon then
		local size = spec.portrait and PORTRAIT_SIZE or (height - 6)
		local ring = spec.portrait and 4 or 2
		row.iconBorder:ClearAllPoints()
		row.iconBorder:SetPoint("LEFT", row, "LEFT", indentX + (spec.iconOffset or 0), 0)
		row.iconBorder:SetSize(size + ring, size + ring)
		local c = spec.iconColor or (spec.portrait and { 0.78, 0.62, 0.25 }) or { 0.3, 0.3, 0.3 }
		row.iconBorder:SetColorTexture(c[1], c[2], c[3], spec.iconBare and 0 or 1)
		row.icon:ClearAllPoints()
		row.icon:SetPoint("CENTER", row.iconBorder, "CENTER")
		row.icon:SetSize(size, size)
		row.icon:SetTexture(spec.icon)
		if spec.iconCoords then
			row.icon:SetTexCoord(unpack(spec.iconCoords))
		elseif spec.portraitUnit and SetPortraitTexture then
			row.icon:SetTexCoord(0, 1, 0, 1)
			SetPortraitTexture(row.icon, spec.portraitUnit)
		else
			row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- recorta el borde de los iconos del juego
		end
		row.icon:SetDesaturated(spec.desaturate or false)
		contentX = indentX + (spec.iconOffset or 0) + size + 8
	end
	row:SetScript("OnClick", spec.onClick)
	-- Filas con objeto: al pasar el ratón se ve su descripción, como en el juego.
	local link = spec.link
	-- O un tooltip de texto: spec.tooltip = { "Título", "línea", ... }.
	local tooltip = spec.tooltip
	row:SetScript("OnEnter", (link or tooltip) and function(self)
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		if link then
			GameTooltip:SetHyperlink(link)
		else
			for i, text in ipairs(tooltip) do
				if i == 1 then GameTooltip:SetText(text) else GameTooltip:AddLine(text, 1, 1, 1, true) end
			end
		end
		GameTooltip:Show()
	end or nil)
	row:SetScript("OnLeave", (link or tooltip) and function() GameTooltip:Hide() end or nil)
	row:EnableMouse(spec.onClick ~= nil or link ~= nil or tooltip ~= nil)

	local tint = spec.tint
	row.tint:SetShown(tint ~= nil)
	row.stripe:SetShown(tint ~= nil)
	if tint then
		row.tint:SetColorTexture(tint[1], tint[2], tint[3], spec.tintAlpha or 0.13)
		row.stripe:SetColorTexture(tint[1], tint[2], tint[3], 0.9)
	end
	row.line:SetShown(kind == "header" and not spec.segments)
	row.bar:SetShown(kind == "bar")

	-- Botones de derecha a izquierda: el primero de la lista queda más a la izquierda.
	local buttons = spec.buttons or {}
	local buttonsWidth = 0 -- espacio que ocupan los botones a la derecha
	for b, btn in ipairs(row.buttons) do
		local def = buttons[#buttons - b + 1]
		btn:SetShown(def ~= nil)
		if def then
			btn:SetText(def.label)
			local width = math.max(70, btn:GetFontString():GetStringWidth() + 20)
			btn:SetWidth(width)
			btn:SetScript("OnClick", def.onClick)
			-- Tooltip opcional del botón: def.tooltip = { "Título", "línea", ... }
			local tip = def.tooltip
			btn:SetScript("OnEnter", tip and function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				for i, text in ipairs(tip) do
					if i == 1 then GameTooltip:SetText(text) else GameTooltip:AddLine(text, 1, 1, 1, true) end
				end
				GameTooltip:Show()
			end or nil)
			btn:SetScript("OnLeave", tip and function() GameTooltip:Hide() end or nil)
			btn:SetEnabled(not def.disabled)
			buttonsWidth = buttonsWidth + width + 3
		end
	end
	-- Límite derecho para el contenido (columnas, barras): nunca por debajo de los botones.
	local contentRight = CONTENT_WIDTH - 4 - (buttonsWidth > 0 and (buttonsWidth + 8) or 0)
	local rightAnchor = #buttons > 0 and row.buttons[math.min(#buttons, MAX_BUTTONS)] or nil

	-- Tarjeta: su propio dibujo; los botones, el clic y el tooltip son los de la fila.
	if kind == "card" or kind == "crest" then
		row.text:Hide()
		for _, fs in ipairs(row.cells) do fs:Hide() end
		row.bar:Hide(); row.icon:Hide(); row.iconBorder:Hide(); row.tint:Hide(); row.stripe:Hide(); row.line:Hide()
		if kind == "crest" then
			showCardParts(row, false)
			layoutCrest(row, spec, indentX)
		else
			layoutCard(row, spec, indentX)
		end
		return
	end

	for _, fs in ipairs(row.cells) do fs:Hide() end
	row.text:Show()
	row.text:ClearAllPoints()
	row.text:SetFontObject(kind == "header" and "GameFontNormalLarge" or "GameFontHighlight")

	if kind == "bar" then
		row.text:SetPoint("LEFT", row, "LEFT", indentX + 18, 0)
		row.text:SetWidth(240)
		row.text:SetText(spec.label or "")
		row.bar:ClearAllPoints()
		row.bar:SetPoint("LEFT", row, "LEFT", indentX + 270, 0)
		row.bar:SetWidth(math.min(300, contentRight - (indentX + 270)))
		row.bar:SetMinMaxValues(0, math.max(1, spec.max or 1))
		row.bar:SetValue(math.min(spec.value or 0, spec.max or 0))
		local c = spec.color or { 0.25, 0.8, 0.25 }
		row.bar:SetStatusBarColor(c[1], c[2], c[3])
		local bg = spec.bgColor or { 0.25, 0.22, 0.15 }
		row.bar.bg:SetColorTexture(bg[1], bg[2], bg[3], 0.9)
		row.bar.value:SetText(spec.text or "")
		-- Números en los extremos (Horda a la izquierda, Alianza a la derecha).
		if not row.bar.left then
			row.bar.left = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.bar.left:SetPoint("LEFT", 6, 0)
			row.bar.right = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.bar.right:SetPoint("RIGHT", -6, 0)
		end
		row.bar.left:SetText(spec.leftText or "")
		row.bar.right:SetText(spec.rightText or "")
	elseif spec.cols then
		row.text:Hide()
		-- Con iconOffset, la primera columna va delante del icono (p. ej. el puesto
		-- en la clasificación) y el resto detrás.
		local x = spec.iconOffset and indentX or contentX
		for c, col in ipairs(spec.cols) do
			local fs = row.cells[c]
			if fs then
				fs:ClearAllPoints()
				fs:SetPoint("LEFT", row, "LEFT", x, 0)
				-- Si no cabe antes de los botones, se recorta (con "...") en vez de quedar debajo.
				local width = math.min(col[2], contentRight - x)
				fs:SetWidth(math.max(1, width))
				fs:SetText(col[1] or "")
				fs:SetShown(width > 10)
				x = (spec.iconOffset and c == 1) and contentX or (x + col[2] + 6)
			end
		end
	elseif kind == "row" and not rightAnchor then
		-- Sin botones, el texto puede ocupar varias líneas y la fila crece con él.
		row.text:SetPoint("TOPLEFT", row, "TOPLEFT", contentX, -3)
		row.text:SetWidth(CONTENT_WIDTH - contentX - 12)
		row.text:SetWordWrap(true)
		row.text:SetText(spec.text or "")
		row:SetHeight(math.max(height, math.ceil(row.text:GetStringHeight()) + 6))
		return
	else
		row.text:SetPoint("LEFT", row, "LEFT", contentX, kind == "header" and 2 or 0)
		if rightAnchor then
			row.text:SetPoint("RIGHT", rightAnchor, "LEFT", -6, 0)
		else
			row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
		end
		row.text:SetText(spec.text or "")
	end
	row.text:SetWordWrap(false)
end

local function layoutRows(rows)
	local y = 0
	for i, spec in ipairs(rows) do
		local row = getRow(i)
		layoutRow(row, spec)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
		row:Show()
		y = y + row:GetHeight()
	end
	for i = #rows + 1, #rowPool do rowPool[i]:Hide() end
	scrollChild:SetHeight(y + 10)
end

---------------------------------------------------------------------------
-- Ventana, con el aspecto de los desafíos de legado de Forever:
-- navegación a la izquierda (secciones y sus apartados), contenido a la
-- derecha sobre el fondo de legado y, arriba, el escudo de puntos de hermandad
-- con la barra de tu rango.
---------------------------------------------------------------------------

local FRAME_W, FRAME_H = 960, 640 -- alto: el menú con Oficial y 5 subapartados desplegados, más Logros y Ajustes abajo
local PAGE_HEADER_H, PAGE_GAP = 58, 8 -- barra de título (encaja con la franja de Legacy-Challenge-BG) y margen hasta el contenido
local NAV_W = 200
local NAV_BUTTON_H, SUB_BUTTON_H = 34, 24

---------------------------------------------------------------------------
-- Facción: clasificación de las hermandades de tu facción, récords y Horda
-- contra Alianza (Modules/Faction.lua). Solo temporada JcJ.
---------------------------------------------------------------------------

local factionMode = "kills"
-- Categorías: valor para ordenar, columna principal y detalle.
local FACTION_MODES = {
	{ key = "kills", label = L["Muertes con honor"], short = L["Muertes"], value = function(s) return s.kills end },
	{ key = "gmKills", label = L["Cabecillas"], short = L["Cabecillas abatidos"], value = function(s) return s.gmKills end,
		tip = L["Kills a líderes de hermandades enemigas."] },
	{ key = "assaults", label = L["Asaltos"], short = L["Asaltos"], value = function(s) return s.assaults end,
		tip = L["Asaltos completados: cae el líder de la ciudad o 10 kills de la hermandad en ella."] },
	{ key = "regicides", label = L["Capitales"], short = L["Líderes"], value = function(s) return s.regicides end,
		tip = L["Líderes de capitales enemigas derribados."] },
	{ key = "helps", label = L["Auxilio"], short = L["Llamadas"], value = function(s) return s.helps end,
		tip = L["Llamadas de auxilio de otras hermandades atendidas con al menos una kill."] },
	{ key = "dungeons", label = L["Mazmorras"], short = L["Completadas"], value = function(s) return s.dungeonClears end,
		tip = L["Mazmorras completadas con un grupo de hermandad (4 o 5 de la guild)."] },
	{ key = "raids", label = L["Bandas"], short = L["Jefes"], value = function(s) return ns.RaidBosses(s.raids) end,
		detail = function(s) return ns.RaidProgressText(s.raids) end },
	{ key = "points", label = L["Logros"], short = L["Puntos"], value = function(s) return s.points end },
	{ key = "members", label = L["Miembros"], short = L["Miembros"], value = function(_, e) return e.members end,
		detail = function(_, e) return (L["%d con el addon"]):format(e.addon or 0) end },
}

local function myFactionToken() return UnitFactionGroup and UnitFactionGroup("player") or "Horde" end

-- Nivel 8 de hermandad (70 puntos): estrella junto al nombre.
local STAR = "|TInterface\\COMMON\\FavoritesIcon:14:14|t "
local function guildStar(stats) return (stats and (stats.points or 0) >= 70) and STAR or "" end

local function factionRanking(rows)
	local guilds, season = ns.FactionGuilds()
	local faction = myFactionToken()
	local mode = FACTION_MODES[1]
	for _, m in ipairs(FACTION_MODES) do
		if m.key == factionMode then mode = m end
	end
	header(rows, (L["Clasificación de la %s · temporada %d"]):format(ns.FactionName(faction), season))
	-- Categorías en dos filas de botones (la elegida, desactivada).
	local function modeButton(m)
		return { label = m.label, disabled = m.key == factionMode, tooltip = m.tip and { m.label, m.tip } or nil, onClick = function()
			factionMode = m.key
			refresh()
		end }
	end
	local first, second = {}, {}
	for i, m in ipairs(FACTION_MODES) do
		table.insert(i <= 5 and first or second, modeButton(m))
	end
	line(rows, "", 0, { buttons = first })
	line(rows, "", 0, { buttons = second })
	local list = {}
	for _, e in ipairs(guilds) do
		if e.faction == faction then list[#list + 1] = { e = e, v = mode.value(e.stats or {}, e) or 0 } end
	end
	table.sort(list, function(a, b)
		if a.v ~= b.v then return a.v > b.v end
		return a.e.guild < b.e.guild
	end)
	rows[#rows + 1] = { indent = 0, cols = { { "", 30 }, { "", 22 }, { grey(L["Hermandad"]), 220 }, { grey(mode.short), 140 },
		{ grey(mode.detail and "" or L["Miembros"]), 240 } } }
	if #list == 0 then line(rows, grey(L["Todavía no hay hermandades de tu facción en la red."]), 1) end
	for i = 1, math.min(30, #list) do
		local x = list[i]
		local e = x.e
		rows[#rows + 1] = { indent = 0, tall = true, icon = ns.FactionBanner(e.faction), iconOffset = 30,
			cols = { { medalText(i), 30 }, { guildStar(e.stats) .. (e.own and GOLD or "") .. e.guild .. (e.own and R or ""), 220 }, { GREEN .. x.v .. R, 140 },
				{ grey(mode.detail and mode.detail(e.stats or {}, e) or tostring(e.members or 0)), 240 } } }
	end
	space(rows)
	line(rows, grey(L["Cada hermandad manda sus propios datos al anunciarse en la red (cada 10 minutos). Cuentan desde que su addon vio empezar la temporada."]), 1)
end

local function factionRecords(rows)
	local guilds = ns.FactionGuilds()
	local faction = myFactionToken()
	local function guildName(e) return (e.own and GOLD or "") .. "<" .. e.guild .. ">" .. (e.own and R or "") end

	-- Asaltos: una tarjeta por capital con el récord, su podio y vuestro mejor tiempo.
	header(rows, (L["Asaltos más rápidos de la %s"]):format(ns.FactionName(faction)))
	for _, c in ipairs(ns.EnemyCities()) do
		local list, ownTime = {}, nil
		for _, e in ipairs(guilds) do
			local secs = e.faction == faction and e.stats and e.stats.assaultTimes and e.stats.assaultTimes[c.key]
			if secs and secs > 0 then
				list[#list + 1] = { e = e, secs = secs }
				if e.own then ownTime = secs end
			end
		end
		table.sort(list, function(x, y) return x.secs < y.secs end)
		local top = list[1]
		local foot = {}
		for i = 2, math.min(3, #list) do
			foot[#foot + 1] = ("%d.º %s %s"):format(i, guildName(list[i].e), ns.FormatDuration(list[i].secs))
		end
		if ownTime and not (top and top.e.own) then foot[#foot + 1] = GOLD .. (L["vuestro mejor: %s"]):format(ns.FormatDuration(ownTime)) .. R end
		rows[#rows + 1] = {
			kind = "card", state = top and "normal" or "off", accent = top and top.e.own and ns.ACCENT.good or nil,
			icon = CITY_ICONS[c.key],
			title = ns.CityName(c.key),
			desc = top and guildName(top.e) or grey(L["nadie ha derribado a su líder"]),
			status = top and (GOLD .. ns.FormatDuration(top.secs) .. R) or nil,
			foot = #foot > 0 and grey(table.concat(foot, "  ·  ")) or nil,
		}
	end

	-- Mazmorras: el mejor tiempo de cada una entre todas las hermandades de la facción.
	space(rows)
	header(rows, L["Mazmorras más rápidas"])
	local dungeons, names = {}, {}
	for _, e in ipairs(guilds) do
		if e.faction == faction and e.stats then
			for name, secs in pairs(e.stats.dungeons or {}) do
				if secs > 0 and (not dungeons[name] or secs < dungeons[name].secs) then
					if not dungeons[name] then names[#names + 1] = name end
					dungeons[name] = { secs = secs, e = e }
				end
			end
		end
	end
	table.sort(names)
	if #names == 0 then line(rows, grey(L["Todavía no hay tiempos de mazmorra esta temporada."]), 1) end
	for _, name in ipairs(names) do
		local d = dungeons[name]
		rows[#rows + 1] = { indent = 1, tall = true, icon = "Interface\\Icons\\INV_Misc_Key_03",
			cols = { { name, 260 }, { GOLD .. ns.FormatRunTime(d.secs) .. R, 90 }, { guildName(d.e), 240 } } }
	end
end

-- Horda contra Alianza: una barra por dato (rojo la Horda, azul la Alianza, en
-- proporción) y arriba las categorías que gana cada facción.
local VERSUS = {
	{ "guilds", L["Hermandades con el addon"], "Interface\\Icons\\INV_BannerPVP_02" },
	{ "members", L["Miembros"], "Interface\\Icons\\Spell_Holy_PrayerofFortitude" },
	{ "kills", L["Muertes con honor"], "Interface\\Icons\\Ability_DualWield" },
	{ "gmKills", L["Cabecillas abatidos"], "Interface\\Icons\\INV_Crown_02" },
	{ "assaults", L["Asaltos completados"], ICON_ASSAULT },
	{ "regicides", L["Líderes de capital derribados"], "Interface\\Icons\\INV_Crown_01" },
	{ "helps", L["Llamadas de auxilio atendidas"], ICON_AID },
	{ "dungeonClears", L["Mazmorras completadas"], "Interface\\Icons\\INV_Misc_Key_03" },
	{ "raidBosses", L["Jefes de banda"], "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
}
local HORDE_RED, ALLIANCE_BLUE = { 0.75, 0.13, 0.1 }, { 0.16, 0.36, 0.85 }

local function factionVersus(rows)
	local guilds, season = ns.FactionGuilds()
	local totals = { Horde = {}, Alliance = {} }
	for _, t in pairs(totals) do
		for _, v in ipairs(VERSUS) do t[v[1]] = 0 end
	end
	for _, e in ipairs(guilds) do
		local t = totals[e.faction]
		if t then
			local s = e.stats or {}
			t.guilds = t.guilds + 1
			t.members = t.members + (e.members or 0)
			for _, key in ipairs({ "kills", "gmKills", "assaults", "regicides", "helps", "dungeonClears" }) do t[key] = t[key] + (s[key] or 0) end
			t.raidBosses = t.raidBosses + ns.RaidBosses(s.raids)
		end
	end
	-- Marcador: categorías que gana cada una.
	local hWins, aWins = 0, 0
	for _, v in ipairs(VERSUS) do
		local h, a = totals.Horde[v[1]], totals.Alliance[v[1]]
		if h > a then hWins = hWins + 1 elseif a > h then aWins = aWins + 1 end
	end
	header(rows, (L["Horda contra Alianza · temporada %d"]):format(season))
	rows[#rows + 1] = {
		kind = "card", state = "normal",
		accent = hWins > aWins and HORDE_RED or (aWins > hWins and ALLIANCE_BLUE or nil),
		icon = ns.FactionBanner(hWins >= aWins and "Horde" or "Alliance"),
		title = ("|cffff5040%s %d|r   –   |cff4a9eff%d %s|r"):format(ns.FactionName("Horde"), hWins, aWins, ns.FactionName("Alliance")),
		desc = grey(L["Categorías ganadas esta temporada"]),
		status = hWins == aWins and GOLD .. L["Empate"] .. R
			or ((hWins > aWins and "|cffff5040" or "|cff4a9eff") .. (L["Va ganando la %s"]):format(ns.FactionName(hWins > aWins and "Horde" or "Alliance")) .. R),
	}
	space(rows)
	for _, v in ipairs(VERSUS) do
		local h, a = totals.Horde[v[1]], totals.Alliance[v[1]]
		rows[#rows + 1] = {
			kind = "bar", indent = 1,
			label = ("|T%s:16|t  %s"):format(v[3], v[2]),
			value = (h + a) > 0 and h or 1, max = (h + a) > 0 and (h + a) or 2,
			color = HORDE_RED, bgColor = ALLIANCE_BLUE,
			leftText = (h > a and "|cffffffff" or "|cffd0d0d0") .. h .. "|r",
			rightText = (a > h and "|cffffffff" or "|cffd0d0d0") .. a .. "|r",
		}
	end
	space(rows)
	line(rows, grey(L["Lo de la otra facción llega por el puente de Battle.net: si nadie tiene un amigo de la otra facción con el addon, su columna se queda corta."]), 1)
end

views.faction = function()
	local g = LG:GuildData()
	if not g then return notInGuild() end
	local rows = {}
	segments(rows, "faction", {
		{ key = "ranking", label = L["Clasificación"] },
		{ key = "directory", label = L["Hermandades"] },
		{ key = "records", label = L["Récords"] },
		{ key = "versus", label = L["Horda contra Alianza"] },
	})
	if subview.faction == "directory" then
		directoryView(g, rows)
		rows.search = L["Buscar hermandad..."]
	elseif subview.faction == "records" then
		factionRecords(rows)
	elseif subview.faction == "versus" then
		factionVersus(rows)
	else
		factionRanking(rows)
	end
	return rows
end

local SECTIONS = {
	{ key = "home", label = L["Inicio"], icon = ns.MEDIA .. "emblem_small", noCrop = true },
	{ key = "events", label = L["Eventos"], icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
	{ key = "pve", label = L["JcE"], icon = "Interface\\Icons\\INV_Misc_Key_03" },
	{ key = "hunt", label = L["JcJ"], icon = "Interface\\Icons\\Ability_DualWield" },
	{ key = "faction", label = L["Facción"], icon = "Interface\\Icons\\INV_BannerPVP_01" },
	{ key = "market", label = L["Mercado"], icon = "Interface\\Icons\\INV_Misc_Coin_02" },
	{ key = "guild", label = L["Hermandad"], icon = "Interface\\Icons\\INV_BannerPVP_02" },
	{ key = "officer", label = L["Oficial"], icon = "Interface\\Icons\\INV_Crown_01", officer = true },
}

local navButtons, subButtons = {}, {}
local rankBar, insignias, challengesButton, settingsButton

local function hasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- La textura de legado si existe; si no, un color.
local function setArt(texture, atlas, r, g, b, a)
	if hasAtlas(atlas) then
		texture:SetAtlas(atlas)
		texture:SetVertexColor(1, 1, 1, 1)
		return true
	end
	texture:SetColorTexture(r or 0.1, g or 0.09, b or 0.07, a or 0.9)
	return false
end

local function progressBar(parent, width, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(width, height)
	local fill = bar:CreateTexture(nil, "ARTWORK")
	setArt(fill, "Legacy-Progressbar-Fill", 0.85, 0.65, 0.1, 1)
	bar:SetStatusBarTexture(fill)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	setArt(bar.bg, "Legacy-Progressbar-BG", 0, 0, 0, 0.6)
	bar.border = bar:CreateTexture(nil, "OVERLAY")
	bar.border:SetPoint("TOPLEFT", -4, 4)
	bar.border:SetPoint("BOTTOMRIGHT", 4, -4)
	if not setArt(bar.border, "Legacy-Progressbar-Frame") then bar.border:Hide() end
	bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.text:SetPoint("CENTER")
	bar.text:SetDrawLayer("OVERLAY", 7)
	return bar
end

-- Botón de la navegación: icono, nombre y un contador a la derecha.
local function navButton(parent, height, small)
	local b = CreateFrame("Button", nil, parent)
	b.isNav = true -- navegación (las pruebas la saltan al pulsar los botones de una vista)
	b:SetSize(small and NAV_W - 30 or NAV_W - 10, height)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	if not small then
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(24, 24)
		b.icon:SetPoint("LEFT", 8, 0)
	end
	b.label = b:CreateFontString(nil, "OVERLAY", small and "GameFontHighlightSmall" or "GameFontNormal")
	b.label:SetPoint("LEFT", small and 14 or 40, 0)
	b.label:SetJustifyH("LEFT")
	b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.count:SetPoint("RIGHT", -10, 0)
	b.count:SetJustifyH("RIGHT")
	return b
end

-- Avisos por sección: lo que reclama tu atención.
local function sectionBadge(key)
	local g = LG:GuildData()
	if not g then return nil end
	local me = ns.PlayerFullName()
	if key == "officer" then
		local n = 0
		for _, a in ipairs(ns.Anomalies()) do
			if a.severity ~= "info" then n = n + 1 end
		end
		return n > 0 and (RED .. n .. R) or nil
	elseif key == "hunt" then
		local guild, n = LG:GuildName(), 0
		if ns.WARS_PAUSED then
			n = #ns.ActiveAidCalls()
			return n > 0 and (RED .. n .. R) or nil
		end
		for _, w in pairs(g.wars) do
			local phase = ns.WarPhase(w)
			if phase == "active" or (phase == "pending" and w.to == guild) then n = n + 1 end
		end
		return n > 0 and (RED .. n .. R) or nil
	elseif key == "pve" then
		local mine, n = ns.MyLFGGroup(), 0
		for _ in pairs(mine and ns.lfgRequests[mine.id] or {}) do n = n + 1 end
		return n > 0 and (GOLD .. n .. R) or nil
	elseif key == "market" then
		local n = 0
		for _, o in ipairs(ns.OrdersByRole().forMe) do
			if o.status == "open" then n = n + 1 end
		end
		return n > 0 and (GOLD .. n .. R) or nil
	end
	return nil
end

local function updateHeader()
	local guildName = LG:GuildName()
	local me = ns.PlayerFullName()
	-- Título de hermandad desbloqueado con los desafíos, y la marca de agua dorada.
	local title, goldWatermark = nil, false
	local perks
	if guildName and ns.AchievementRewards then title, goldWatermark, perks = ns.AchievementRewards() end
	-- Nivel 10: marco dorado alrededor de la ventana.
	if frame.goldFrame then
		for _, edge in ipairs(frame.goldFrame) do edge:SetShown(perks and perks.goldFrame or false) end
	end
	subtitle:SetText((guildName and ("<" .. guildName .. ">") or L["Sin hermandad"]) ..
		(LG:InTestMode() and ("\n" .. GOLD .. L["modo prueba"] .. R) or (title and ("\n" .. GREY .. title .. R) or "")))
	if goldWatermark then
		watermark:SetVertexColor(1, 0.82, 0.35)
		watermark:SetAlpha(WATERMARK_ALPHA * 1.8)
	else
		watermark:SetVertexColor(1, 1, 1)
		watermark:SetAlpha(WATERMARK_ALPHA)
	end

	-- Escudo: puntos de los desafíos de hermandad.
	achButton:SetShown(guildName ~= nil)
	if frame.profButton then frame.profButton:SetShown(guildName ~= nil) end
	if guildName and ns.AchievementState then achButton.text:SetText(tostring(ns.AchievementState().points)) end

	-- Barra: tu rango y la reputación hacia el siguiente; a la derecha, tus insignias.
	rankBar:SetShown(guildName ~= nil and me ~= nil)
	insignias:SetShown(guildName ~= nil and me ~= nil)
	frame.chestText:SetShown(guildName ~= nil and me ~= nil)
	frame.chestButton:SetShown(guildName ~= nil and me ~= nil)
	if guildName and me then
		local rank, nextRank, rep = ns.MeritRank(me)
		if nextRank then
			rankBar:SetMinMaxValues(rank.rep, nextRank.rep)
			rankBar:SetValue(math.min(rep, nextRank.rep))
			rankBar.text:SetText(("%s  ·  %d / %d rep  >  %s"):format(rank.label, rep, nextRank.rep, nextRank.label))
		else
			rankBar:SetMinMaxValues(0, 1)
			rankBar:SetValue(1)
			rankBar.text:SetText(("%s  ·  %d rep"):format(rank.label, rep))
		end
		local s = ns.Scores()[me]
		insignias:SetText(("|T%s:18:18:0:0:64:64:5:59:5:59|t %s%d|r %s"):format(ns.INSIGNIA_ICON, GREEN, s and s.merits or 0, L["insignias"]))
		frame.chestText:SetText(("|T%s:14:14:0:0:64:64:5:59:5:59|t %s%d|r %s"):format(ns.CHEST_ICON, GOLD, ns.ChestState().balance, L["en el cofre"]))
	end

	-- Sin ser oficial no hay sección de oficial.
	if current == "officer" and not (guildName and ns.CanManageEvents(me)) then current = "home" end
end

-- Navegación: secciones y, bajo la elegida, sus apartados (si los tiene).
local function layoutNav(segments)
	local me = ns.PlayerFullName()
	local isOfficer = LG:GuildName() ~= nil and ns.CanManageEvents(me)
	local y = -4
	local sub = 0
	for _, s in ipairs(SECTIONS) do
		local b = navButtons[s.key]
		local visible = not s.officer or isOfficer
		b:SetShown(visible)
		if visible then
			local selected = s.key == current
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", 4, y)
			setArt(b.bg, selected and "Legacy-Challenge-Left-Sub-Tab-selected" or "Legacy-Challenge-Left-Sub-Tab",
				selected and 0.3 or 0.12, selected and 0.24 or 0.1, selected and 0.1 or 0.08, 0.95)
			b.label:SetText((selected and "|cffffffff" or GOLD) .. s.label .. R)
			b.count:SetText(sectionBadge(s.key) or "")
			y = y - NAV_BUTTON_H - 4
			if selected then
				for _, seg in ipairs(segments or {}) do
					sub = sub + 1
					local sb = subButtons[sub]
					if not sb then
						sb = navButton(frame.nav, SUB_BUTTON_H, true)
						subButtons[sub] = sb
					end
					sb:ClearAllPoints()
					sb:SetPoint("TOPLEFT", 24, y + 2)
					setArt(sb.bg, seg.selected and "Legacy-Challenge-Left-Sub-Tab-selected" or "Legacy-Challenge-Left-Sub-Tab",
						0.1, 0.08, 0.06, seg.selected and 0.95 or 0.6)
					sb.bg:SetAlpha(seg.selected and 1 or 0.55)
					sb.label:SetText((seg.selected and "|cffffffff" or "|cffd8c8a0") .. seg.label .. R)
					sb.count:SetText("")
					sb:SetScript("OnClick", seg.onClick)
					sb:Show()
					y = y - SUB_BUTTON_H - 2
				end
				y = y - 4
			end
		end
	end
	for i = sub + 1, #subButtons do subButtons[i]:Hide() end
	-- Ajustes: abajo, marcado cuando está abierto.
	local inSettings = current == "settings"
	setArt(settingsButton.bg, inSettings and "Legacy-Challenge-Left-Sub-Tab-selected" or "Legacy-Challenge-Left-Sub-Tab",
		inSettings and 0.3 or 0.12, inSettings and 0.24 or 0.1, inSettings and 0.1 or 0.08, 0.95)
	settingsButton.label:SetText((inSettings and "|cffffffff" or GOLD) .. L["Ajustes"] .. R)
end

local function render()
	if not frame or not frame:IsShown() then return end
	-- Al repintar (p. ej. tras pulsar una tarjeta), fuera el tooltip que se quedaría colgado.
	local owner = GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()
	local guard = 0
	while owner and guard < 12 do
		if owner == frame then GameTooltip:Hide() break end
		owner = owner.GetParent and owner:GetParent()
		guard = guard + 1
	end
	updateHeader()
	local rows = views[current]()
	layoutNav(rows.segments)

	-- Título de la página: sección y, si tiene, el apartado elegido.
	local title, icon, noCrop = L["Ajustes"], "Interface\\Icons\\Trade_Engineering", false
	for _, s in ipairs(SECTIONS) do
		if s.key == current then title, icon, noCrop = s.label, s.icon, s.noCrop end
	end
	local sub
	for _, seg in ipairs(rows.segments or {}) do
		if seg.selected then sub = seg.label end
	end
	frame.page.icon:SetTexture(icon)
	if noCrop then frame.page.icon:SetTexCoord(0, 1, 0, 1) else frame.page.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
	frame.page.title:SetText(title)
	frame.page.sub:SetText(sub and ("·  " .. sub) or "")

	-- Buscador en la barra de título, si la vista lo usa.
	searchBox:SetShown(rows.search ~= nil)
	searchHint:SetText(rows.search or "")
	searchHint:SetShown(rows.search ~= nil and searchBox:GetText() == "")
	layoutRows(rows)
end
ns.RefreshMainFrame = render

-- Abrir una sección en un apartado concreto (p. ej. Hermandad › Cofre).
function ns.SelectSubview(tab, key)
	subview[tab] = key
	ns.SelectTab(tab)
end

-- Apartados de una sección (para las pruebas) y la vista actual.
function ns.SubviewKeys(tab)
	local keys = {}
	for _, seg in ipairs(views[tab] and views[tab]().segments or {}) do keys[#keys + 1] = seg.key end
	return keys
end
function ns.CurrentView() return current, subview[current] end

function ns.SelectTab(key)
	if current ~= key then searchBox:SetText("") end
	current = key
	scroll:SetVerticalScroll(0)
	render()
end

local function create()
	local ok, f = pcall(CreateFrame, "Frame", "LantuxGuildFrame", UIParent, "PortraitFrameTemplate")
	if not ok or not f then f = CreateFrame("Frame", "LantuxGuildFrame", UIParent, "BasicFrameTemplateWithInset") end
	frame = f
	frame:SetSize(FRAME_W, FRAME_H)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetScript("OnShow", render)
	-- No se añade a UISpecialFrames (cerrar con Escape): en la beta contamina el menú
	-- del juego y Blizzard bloquea la acción con el aviso de "solo para la interfaz de Blizzard".

	-- Título y retrato con el emblema (como la ventana de Desafíos).
	if frame.SetTitle then
		frame:SetTitle(ns.ADDON_TITLE)
	else
		local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		title:SetPoint("TOP", 0, -5)
		title:SetText(ns.ADDON_TITLE)
	end
	if frame.SetPortraitToAsset then pcall(frame.SetPortraitToAsset, frame, ns.MEDIA .. "emblem_small") end

	-- Cabecera: hermandad, escudo de puntos de hermandad, barra de rango e insignias.
	subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	subtitle:SetPoint("TOPLEFT", 70, -32)
	subtitle:SetWidth(NAV_W - 10)
	subtitle:SetJustifyH("LEFT")

	achButton = CreateFrame("Button", nil, frame)
	achButton:SetSize(46, 46)
	achButton:SetPoint("TOPLEFT", NAV_W + 64, -26)
	achButton.tex = achButton:CreateTexture(nil, "ARTWORK")
	achButton.tex:SetAllPoints()
	if not setArt(achButton.tex, "UI-Legacy-Points-icon-c60") then achButton.tex:SetTexture("Interface\\Icons\\INV_Shield_06") end
	achButton.text = achButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	achButton.text:SetPoint("CENTER", 0, -4)
	achButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	achButton:SetScript("OnClick", function() ns.ToggleAchievements() end)
	achButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText(L["Logros de hermandad"])
		GameTooltip:AddLine(L["Logros de toda la hermandad. Clic para verlos."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	achButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Perfil: tu retrato, junto al escudo de logros.
	local profButton = CreateFrame("Button", nil, frame)
	profButton:SetSize(42, 42)
	profButton:SetPoint("LEFT", achButton, "RIGHT", 6, 0)
	profButton.tex = profButton:CreateTexture(nil, "ARTWORK")
	profButton.tex:SetSize(36, 36)
	profButton.tex:SetPoint("CENTER")
	if SetPortraitTexture then SetPortraitTexture(profButton.tex, "player") end
	profButton.ring = profButton:CreateTexture(nil, "OVERLAY")
	profButton.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	profButton.ring:SetSize(42 * 1.7, 42 * 1.7)
	profButton.ring:SetPoint("TOPLEFT", -1, 1)
	profButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	profButton:SetScript("OnClick", function() ns.ToggleProfile() end)
	profButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText(L["Tu perfil"])
		GameTooltip:AddLine(L["Tus medallas, tu ficha y las insignias del retrato."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	profButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.profButton = profButton

	rankBar = progressBar(frame, 390, 18)
	rankBar:SetPoint("LEFT", profButton, "RIGHT", 12, 0)
	-- A la derecha: tus insignias (bolsa) y, debajo, las del cofre de la hermandad (clic: Hermandad › Cofre).
	insignias = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	insignias:SetPoint("BOTTOMLEFT", rankBar, "RIGHT", 18, -2)
	frame.chestText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.chestText:SetPoint("TOPLEFT", rankBar, "RIGHT", 20, -10)
	frame.chestButton = CreateFrame("Button", nil, frame)
	frame.chestButton:SetPoint("TOPLEFT", frame.chestText, "TOPLEFT", -2, 2)
	frame.chestButton:SetPoint("BOTTOMRIGHT", frame.chestText, "BOTTOMRIGHT", 2, -2)
	frame.chestButton:SetScript("OnClick", function() ns.SelectSubview("guild", "chest") end)
	frame.chestButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText(L["Cofre de la hermandad"])
		GameTooltip:AddLine(L["Las insignias de toda la hermandad. Clic para ver el cofre y sus proyectos."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame.chestButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	summary = insignias -- compatibilidad con el código que actualiza el resumen

	-- Navegación a la izquierda.
	frame.nav = CreateFrame("Frame", nil, frame)
	frame.nav:SetPoint("TOPLEFT", 8, -82)
	frame.nav:SetPoint("BOTTOMLEFT", 8, 8)
	frame.nav:SetWidth(NAV_W)
	for _, s in ipairs(SECTIONS) do
		local b = navButton(frame.nav, NAV_BUTTON_H)
		b.icon:SetTexture(s.icon)
		if not s.noCrop then b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
		b:SetScript("OnClick", function() ns.SelectTab(s.key) end)
		navButtons[s.key] = b
		tabButtons[s.key] = b
	end
	-- Abajo del todo, los ajustes del addon; encima, separado, los Logros de hermandad.
	settingsButton = navButton(frame.nav, NAV_BUTTON_H)
	settingsButton:SetPoint("BOTTOMLEFT", 4, 4)
	challengesButton = navButton(frame.nav, NAV_BUTTON_H)
	challengesButton:SetPoint("BOTTOMLEFT", settingsButton, "TOPLEFT", 0, 14)
	-- Línea dorada fina entre los dos.
	local separator = frame.nav:CreateTexture(nil, "ARTWORK")
	separator:SetHeight(1)
	separator:SetColorTexture(1, 0.82, 0, 0.35)
	separator:SetPoint("BOTTOMLEFT", settingsButton, "TOPLEFT", 8, 7)
	separator:SetPoint("BOTTOMRIGHT", settingsButton, "TOPRIGHT", -8, 7)
	settingsButton.icon:SetTexture("Interface\\Icons\\Trade_Engineering")
	settingsButton.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	settingsButton:SetScript("OnClick", function() ns.SelectTab("settings") end)
	if not setArt(challengesButton.icon, "UI-Legacy-Points-icon-c60") then challengesButton.icon:SetTexture("Interface\\Icons\\INV_Shield_06") end
	setArt(challengesButton.bg, "Legacy-Challenge-Left-Sub-Tab", 0.12, 0.1, 0.08, 0.95)
	challengesButton.label:SetText(GOLD .. L["Logros de hermandad"] .. R)
	challengesButton:SetScript("OnClick", function() ns.ToggleAchievements() end)

	-- Contenido a la derecha, sobre el fondo de legado.
	frame.content = CreateFrame("Frame", nil, frame)
	frame.content:SetPoint("TOPLEFT", frame.nav, "TOPRIGHT", 6, 0)
	frame.content:SetPoint("BOTTOMRIGHT", -8, 8)
	frame.content.bg = frame.content:CreateTexture(nil, "BACKGROUND")
	frame.content.bg:SetAllPoints()
	setArt(frame.content.bg, "Legacy-Challenge-BG", 0.06, 0.05, 0.04, 0.9)

	-- Barra de título de la página: icono y sección · apartado sobre la franja del fondo.
	-- El contenido empieza debajo, así no queda tapado por el remate del fondo.
	local page = CreateFrame("Frame", nil, frame.content)
	page:SetPoint("TOPLEFT", 0, 0)
	page:SetPoint("TOPRIGHT", 0, 0)
	page:SetHeight(PAGE_HEADER_H)
	page:SetFrameLevel(frame.content:GetFrameLevel() + 3)
	page.icon = page:CreateTexture(nil, "ARTWORK")
	page.icon:SetSize(26, 26)
	page.icon:SetPoint("LEFT", 16, -1)
	page.title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	page.title:SetPoint("LEFT", page.icon, "RIGHT", 10, 0)
	page.sub = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	page.sub:SetPoint("LEFT", page.title, "RIGHT", 8, 0)
	page.sub:SetTextColor(0.75, 0.7, 0.6)
	frame.page = page

	searchBox = CreateFrame("EditBox", "LantuxGuildSearch", page, "InputBoxTemplate")
	searchBox:SetSize(220, 20)
	searchBox:SetPoint("RIGHT", page, "RIGHT", -16, -1)
	searchBox:SetAutoFocus(false)
	searchBox:SetScript("OnTextChanged", function(self, userInput)
		searchHint:SetShown(self:GetText() == "")
		if userInput then render() end
	end)
	searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	-- Texto de ayuda dentro de la caja mientras está vacía.
	searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	searchHint:SetPoint("LEFT", searchBox, "LEFT", 2, 0)

	-- Marca de agua del canal, por encima del fondo y por debajo del contenido.
	-- Marco dorado (recompensa del nivel 10 de hermandad): cuatro bordes finos.
	frame.goldFrame = {}
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 }, { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
		local t = frame:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(1, 0.78, 0.2, 0.85)
		t:SetPoint(side[1], frame, side[1], 0, 0)
		t:SetPoint(side[2], frame, side[2], 0, 0)
		if side[3] then t:SetWidth(side[3]) end
		if side[4] then t:SetHeight(side[4]) end
		t:Hide()
		frame.goldFrame[#frame.goldFrame + 1] = t
	end

	local watermarkLayer = CreateFrame("Frame", nil, frame.content)
	watermarkLayer:SetAllPoints()
	watermarkLayer:SetFrameLevel(frame.content:GetFrameLevel() + 1)
	watermark = watermarkLayer:CreateTexture(nil, "BACKGROUND")
	watermark:SetTexture(ns.MEDIA .. "emblem")
	watermark:SetSize(380, 380)
	watermark:SetPoint("CENTER")
	watermark:SetAlpha(WATERMARK_ALPHA)

	scroll = CreateFrame("ScrollFrame", "LantuxGuildScroll", frame.content, "UIPanelScrollFrameTemplate")
	ns.StyleScrollBar(scroll)
	scroll:SetPoint("TOPLEFT", 8, -(PAGE_HEADER_H + PAGE_GAP))
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	scroll:SetFrameLevel(watermarkLayer:GetFrameLevel() + 1)
	scrollChild = CreateFrame("Frame", nil, scroll)
	scrollChild:SetSize(CONTENT_WIDTH, 400)
	scroll:SetScrollChild(scrollChild)

	ns.OnDataChanged(function() ns.RefreshMainFrame() end)
end

function ns.ToggleMainFrame()
	if not frame then
		create() -- el marco nace visible, así que OnShow no salta: se pinta a mano
		render()
		return
	end
	frame:SetShown(not frame:IsShown())
end
