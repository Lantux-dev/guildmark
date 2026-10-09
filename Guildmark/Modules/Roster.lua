-- Roster de la guild: lo que da el juego de todos los miembros, tengan o no el addon.
local _, ns = ...
local L = ns.L
local LG = ns.LG

local Roster = LG:NewModule("Roster", "AceEvent-3.0", "AceTimer-3.0")

-- [nombreCompleto] = { rank, rankIndex, level, class, zone, online, lastOnline }
ns.roster = {}

local requestRoster = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster

function ns.IsGuildMember(name)
	return ns.roster[name] ~= nil
end

function Roster:OnEnable()
	ns.RegisterEvent(self, "GUILD_ROSTER_UPDATE", "Update")
	ns.RegisterEvent(self, "PLAYER_GUILD_UPDATE", "Request")
	ns.RegisterEvent(self, "GROUP_ROSTER_UPDATE", "Request")
	self:RegisterMessage("LANTUX_GUILD_CHANGED", "Request")
	self:Request()
	self:ScheduleRepeatingTimer("Request", 60)
end

function Roster:Request()
	if IsInGuild() and not LG:InTestMode() then
		if requestRoster then requestRoster() end
	else
		self:Update()
	end
end

-- Modo prueba: el "roster" es uno mismo más el grupo.
function Roster:UpdateFromGroup()
	local fresh = {}
	local units = { "player" }
	local prefix = IsInRaid() and "raid" or "party"
	local count = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
	for i = 1, count do units[#units + 1] = prefix .. i end
	for _, unit in ipairs(units) do
		local name = ns.UnitFullName(unit)
		if name and not fresh[name] then
			local _, classFile = UnitClass(unit)
			fresh[name] = {
				rank = L["Grupo"],
				rankIndex = 0,
				level = UnitLevel(unit),
				class = classFile,
				zone = UnitIsUnit(unit, "player") and GetZoneText() or "",
				online = UnitIsConnected(unit) and true or false,
				offlineHours = 0,
			}
		end
	end
	-- Alguien nuevo en el grupo (o acabo de entrar en uno): sincronización
	-- completa, como al conectarse en una hermandad de verdad. Si no, el que
	-- llega solo recibiría lo nuevo y no lo que ya había.
	local me = ns.PlayerFullName()
	local newcomer = false
	for name in pairs(fresh) do
		if name ~= me and not ns.roster[name] then newcomer = true end
	end
	ns.roster = fresh
	if newcomer and IsInGroup() and LG:HasConsent() and GetTime() - (self.lastGroupSync or -60) > 20 then
		self.lastGroupSync = GetTime()
		self:ScheduleTimer(function() LG:StartSync() end, 3)
	end
	LG:DataChanged()
end

function Roster:Update()
	if LG:InTestMode() then return self:UpdateFromGroup() end
	if not IsInGuild() then
		wipe(ns.roster)
		LG:DataChanged()
		return
	end
	local fresh = {}
	for i = 1, GetNumGuildMembers() do
		local name, rankName, rankIndex, level, _, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
		if name then
			local y, m, d, h = GetGuildRosterLastOnline(i)
			fresh[ns.FullName(name)] = {
				rank = rankName,
				rankIndex = rankIndex,
				level = level,
				class = classFile,
				zone = zone,
				online = online and true or false,
				-- Años, meses, días y horas desde la última conexión, en horas aproximadas.
				offlineHours = (not online and y) and ((y * 365 + m * 30 + d) * 24 + h) or 0,
			}
		end
	end
	ns.roster = fresh
	LG:DataChanged()
end
