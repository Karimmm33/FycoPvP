--[[ FycoPvP - Modules/Archive.lua
     Records each arena and battleground as its own row, so a game can be read
     back on its own rather than only as part of a running total.

     COST. This module is built to be nearly free, because it runs during the
     only moments that matter:
       - it registers NO ticker. Not one. Everything is event driven.
       - it does nothing at all outside an arena or battleground: the first
         line of every handler tests `rec`, which is nil in the world.
       - it adds no combat log handler. Every fact it stores already passes
         through the message bus for some other module, so the parsing cost is
         already paid and this module only keeps a copy.
       - the record is assembled in one table in memory and written to
         SavedVariables once, when the match ends.
     What it costs is a few hundred small fields per game and one table insert
     per interesting event, capped.

     SEPARATE SAVEDVARIABLE, on purpose. FycoPvPArchive is not FycoPvPDB. The
     archive is the only part of this addon that grows without bound, so it
     lives in its own file: if it ever bloats or corrupts, delete that one file
     and every setting survives.
     Loaded by Core.lua at PLAYER_LOGIN.                                      ]]

local ADDON, ns = ...
local M = ns:Module("archive")

local GetTime      = GetTime
local GetSpellInfo = GetSpellInfo
local UnitExists   = UnitExists
local UnitName     = UnitName
local UnitClass    = UnitClass
local time         = time
local date         = date

local SCHEMA     = 1
local MAX_EVENTS = 250   -- per match
local MAX_DEATHS = 15
local MAX_TOPDMG = 6     -- damage lines kept per death
local MAX_ROSTER = 40

local TRINKET = { [42292] = true, [59752] = true, [7744] = true }

local rec        -- the match being recorded, or nil when not in one
local started    -- GetTime() at match start, for relative timestamps

----------------------------------------------------------------------
-- storage
----------------------------------------------------------------------

local function Store()
	FycoPvPArchive = FycoPvPArchive or {}
	FycoPvPArchive.v = SCHEMA
	FycoPvPArchive.matches = FycoPvPArchive.matches or {}
	return FycoPvPArchive
end

local function Keep()
	return FycoPvPDB.archiveKeep or 60
end

local function Short(name)
	if not name then return nil end
	return name:match("^([^-]+)") or name
end

----------------------------------------------------------------------
-- roster
----------------------------------------------------------------------

--- Your own spec, which 3.3.5a will tell us properly: whichever talent tree
--- has the most points in it. No inference needed for the player.
local function MySpec()
	local best, bestPts = nil, -1
	for i = 1, GetNumTalentTabs() do
		local name, _, pts = GetTalentTabInfo(i)
		if pts and pts > bestPts then best, bestPts = name, pts end
	end
	return best
end

local function Roster(name)
	if not rec or not name then return nil end
	local r = rec.roster[name]
	if not r then
		if rec.rosterN >= MAX_ROSTER then return nil end
		rec.rosterN = rec.rosterN + 1
		r = { name = name }
		rec.roster[name] = r
	end
	return r
end

--- Fold whatever Core and Spec have learned into the match roster. Called at
--- match end and when arena opponents appear, never on a timer.
local function HarvestRoster()
	if not rec then return end
	for guid, u in pairs(ns.units) do
		if u.utype == "player" and guid ~= ns.player and u.name then
			local r = Roster(Short(u.name))
			if r then
				r.class = r.class or u.class
				if not r.side then
					if u.reaction == "hostile" then r.side = "enemy"
					elseif u.reaction == "friendly" then r.side = "ally" end
				end
				local sp = ns.GetSpec and ns:GetSpec(guid)
				if sp and sp.spec then
					r.spec  = sp.spec
					r.role  = sp.role
					r.class = r.class or sp.class
				end
			end
		end
	end
end

--- Arena hands us real unit tokens, which beats every inference we have.
local function ScanArena()
	if not rec then return end
	for i = 1, 5 do
		local unit = "arena" .. i
		if UnitExists(unit) then
			local r = Roster(UnitName(unit))
			if r then
				r.side = "enemy"
				local _, c = UnitClass(unit)
				r.class = c or r.class
			end
		end
	end
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitExists(unit) then
			local r = Roster(UnitName(unit))
			if r then
				r.side = "ally"
				local _, c = UnitClass(unit)
				r.class = c or r.class
			end
		end
	end
end

----------------------------------------------------------------------
-- events
----------------------------------------------------------------------

local function Event(kind, fields)
	if not rec or rec.eventN >= MAX_EVENTS then return end
	rec.eventN = rec.eventN + 1
	fields.t = math.floor((GetTime() - started) * 10 + 0.5) / 10
	fields.e = kind
	rec.events[rec.eventN] = fields
end

local function ClassOf(name)
	local r = rec and rec.roster[Short(name)]
	return r and r.class or nil
end

local function WhoIs(guid)
	if guid == ns.player then return "me" end
	local u = ns.units[guid]
	return u and Short(u.name) or nil
end

----------------------------------------------------------------------
-- result
----------------------------------------------------------------------

--- Who won. The API is tried first and the answer is labelled with where it
--- came from, because GetBattlefieldWinner is not verified on this core, and
--- a guess presented as a fact is worse than a guess labelled as one.
local function Decide()
	if GetBattlefieldWinner then
		local ok, winner = pcall(GetBattlefieldWinner)
		if ok and winner ~= nil then
			-- 0 = Horde, 1 = Alliance in 3.3.5a battlegrounds
			local mine = (UnitFactionGroup("player") == "Alliance") and 1 or 0
			return (winner == mine) and "win" or "loss", "api"
		end
	end

	-- Fall back to who is still standing. Decisive in arena, weak in a
	-- battleground, so the caller is told which of the two this was.
	local enemies, enemyDead = 0, 0
	for _, r in pairs(rec.roster) do
		if r.side == "enemy" then
			enemies = enemies + 1
			if r.died then enemyDead = enemyDead + 1 end
		end
	end
	if rec.kind == "arena" and enemies > 0 then
		if enemyDead >= enemies then return "win", "inferred" end
		if rec.iDied then return "loss", "inferred" end
	end
	return "unknown", "unknown"
end

----------------------------------------------------------------------
-- lifecycle
----------------------------------------------------------------------

local function Begin(kind)
	local _, class = UnitClass("player")
	started = GetTime()
	rec = {
		id     = date("%Y%m%d-%H%M%S"),
		t      = time(),
		kind   = kind,
		zone   = GetRealZoneText() or "?",
		me     = { class = class, spec = MySpec(), level = UnitLevel("player") },
		roster = {}, rosterN = 0,
		events = {}, eventN  = 0,
		deaths = {}, deathN  = 0,
		kills  = 0,
	}
	ScanArena()
end

local function Commit()
	if not rec then return end

	HarvestRoster()
	rec.ended = time()
	rec.dur   = math.floor(GetTime() - started + 0.5)
	rec.stats = ns.MatchStats and ns:MatchStats() or nil
	rec.result, rec.resultSrc = Decide()

	-- drop bookkeeping counters; they only matter while recording
	rec.rosterN, rec.eventN, rec.deathN = nil, nil, nil

	-- the roster is keyed by name for fast lookup while recording, but an
	-- array survives the trip through a serializer far better
	local list, n = {}, 0
	for _, r in pairs(rec.roster) do n = n + 1 ; list[n] = r end
	rec.roster = list

	local db = Store()
	table.insert(db.matches, rec)
	while #db.matches > Keep() do table.remove(db.matches, 1) end

	ns:Print(string.format("|cff00ff00game recorded|r %s %s - %s, %ds. "
		.. "|cffffff00/fyco games|r", rec.kind, rec.zone, rec.result, rec.dur))
	rec = nil
end

----------------------------------------------------------------------
-- reporting
----------------------------------------------------------------------

local function CompLabel(m)
	local parts, n = {}, 0
	for i = 1, #m.roster do
		local r = m.roster[i]
		if r.side == "enemy" then
			n = n + 1
			parts[n] = (r.spec and (r.spec .. " ") or "")
			        .. (r.class and (r.class:sub(1, 1) .. r.class:sub(2):lower()) or "?")
		end
	end
	return n > 0 and table.concat(parts, " + ") or "unknown"
end

--- /fyco games
function ns:GamesList()
	local db = Store()
	if #db.matches == 0 then
		ns:Print("no games recorded yet - a game is written when the match ends")
		return
	end
	ns:Print(string.format("%d games recorded (|cffffff00/fyco game <n>|r for one):",
		#db.matches))
	local first = math.max(1, #db.matches - 14)
	for i = first, #db.matches do
		local m = db.matches[i]
		local col = (m.result == "win" and "|cff40ff40")
		         or (m.result == "loss" and "|cffff4040") or "|cff808080"
		ns:Print(string.format("  |cffffff00%2d|r %s %s%-7s|r %-6s %4ds  vs %s",
			i, date("%m-%d %H:%M", m.t), col, m.result, m.kind, m.dur or 0,
			CompLabel(m)))
	end
end

--- /fyco game <n>
function ns:GameReport(n)
	local db = Store()
	local m = db.matches[n]
	if not m then
		ns:Print("no game " .. tostring(n) .. " - see |cffffff00/fyco games|r")
		return
	end

	ns:Print(string.format("|cffffff00game %d|r  %s  %s  %s  %ds",
		n, date("%Y-%m-%d %H:%M", m.t), m.kind, m.zone, m.dur or 0))
	ns:Print(string.format("  result |cffffffff%s|r |cff808080(%s)|r   you: %s %s",
		m.result, m.resultSrc, (m.me and m.me.spec) or "?",
		(m.me and m.me.class) or "?"))

	local sides = { "enemy", "ally" }
	for s = 1, #sides do
		local line, c = {}, 0
		for i = 1, #m.roster do
			local r = m.roster[i]
			if r.side == sides[s] then
				c = c + 1
				line[c] = string.format("%s (%s%s)", r.name or "?",
					r.spec and (r.spec .. " ") or "", r.class or "?")
			end
		end
		if c > 0 then ns:Print("  " .. sides[s] .. ": " .. table.concat(line, ", ")) end
	end

	if m.stats then
		ns:Print(string.format("  kicks %d/%d   CC %d (%d short)   locked %ds   "
			.. "deaths %d   kbs %d",
			m.stats.kicksLanded or 0,
			(m.stats.kicksLanded or 0) + (m.stats.kicksWasted or 0),
			m.stats.ccLanded or 0, m.stats.ccShort or 0,
			m.stats.lockedSeconds or 0, m.stats.deaths or 0,
			m.stats.killingBlows or 0))
	end

	for i = 1, #(m.deaths or {}) do
		local d = m.deaths[i]
		ns:Print(string.format("  |cffff4040death %d|r at %.0fs to %s (%s), %d taken",
			i, d.at or 0, d.killer or "?", d.killerClass or "?", d.taken or 0))
		for j = 1, #(d.top or {}) do
			local s = d.top[j]
			ns:Print(string.format("      %-18s %-12s %d",
				(s.spell or "damage"):sub(1, 18), s.src or "?", s.amount or 0))
		end
	end
end

function ns:GamesClear()
	FycoPvPArchive = { v = SCHEMA, matches = {} }
	ns:Print("archive cleared")
end

----------------------------------------------------------------------

function M:OnLoad()
	if FycoPvPDB.archiveKeep == nil then FycoPvPDB.archiveKeep = 60 end
	Store()

	ns:Subscribe("MatchStart", function(kind)
		if ns:Enabled("archive") then Begin(kind) end
	end)

	ns:Subscribe("MatchEnd", Commit)

	-- logging out mid-match would otherwise lose the whole game
	ns:On("PLAYER_LOGOUT", Commit)

	-- arena opponents arrive as real unit tokens; take them when they do
	-- rather than polling for them
	ns:On("ARENA_OPPONENT_UPDATE", function()
		if rec then ScanArena() end
	end)

	ns:Subscribe("SpecLearned", function(guid, sp)
		if not rec then return end
		local u = ns.units[guid]
		local r = u and Roster(Short(u.name))
		if r then
			r.spec  = sp.spec
			r.role  = sp.role
			r.class = r.class or sp.class
		end
	end)

	ns:Subscribe("Death", function(dstGUID, srcGUID, isKill)
		if not rec then return end
		if dstGUID == ns.player then
			rec.iDied = true
		else
			local u = ns.units[dstGUID]
			if u and u.name and u.utype == "player" then
				local r = Roster(Short(u.name))
				if r then r.died = (r.died or 0) + 1 end
			end
		end
		if isKill and srcGUID == ns.player then rec.kills = rec.kills + 1 end
	end)

	-- Recap has already assembled the damage window; keep the top of it
	-- rather than doing that work twice.
	ns:Subscribe("PlayerDied", function(r)
		if not rec or rec.deathN >= MAX_DEATHS then return end
		HarvestRoster()

		local names = {}
		for k in pairs(r.bySource or {}) do names[#names + 1] = k end
		table.sort(names, function(a, b)
			return (r.bySource[a] or 0) > (r.bySource[b] or 0)
		end)

		local top, n = {}, 0
		for i = 1, math.min(MAX_TOPDMG, #names) do
			n = n + 1
			top[n] = { src = names[i], class = ClassOf(names[i]),
			           amount = math.floor(r.bySource[names[i]] or 0) }
		end

		-- name the single biggest hit, which is what people actually remember
		local big
		for i = 1, #(r.events or {}) do
			local e = r.events[i]
			if e.kind == "dmg" and (not big or (e.amount or 0) > (big.amount or 0)) then
				big = e
			end
		end
		if big and top[1] then top[1].spell = big.spell end

		rec.deathN = rec.deathN + 1
		rec.deaths[rec.deathN] = {
			at          = math.floor((GetTime() - started) * 10 + 0.5) / 10,
			killer      = names[1],
			killerClass = ClassOf(names[1]),
			taken       = math.floor(r.total or 0),
			top         = top,
		}
	end)

	ns:Subscribe("DRApplied", function(guid, cat, level, srcGUID, spellID)
		if not rec then return end
		Event("cc", {
			by    = WhoIs(srcGUID),
			on    = WhoIs(guid),
			spell = spellID and GetSpellInfo(spellID),
			lvl   = level,
		})
	end)

	ns:Subscribe("Interrupt", function(srcGUID, dstGUID, kickID, extraID)
		if not rec then return end
		Event("kick", {
			by  = WhoIs(srcGUID),
			on  = WhoIs(dstGUID),
			cut = extraID and GetSpellInfo(extraID),
		})
	end)

	ns:Subscribe("AuraApplied", function(dstGUID, spellID)
		if not rec then return end
		if TRINKET[spellID] then
			Event("trinket", { on = WhoIs(dstGUID) })
			return
		end
		local def = ns.Defensives[spellID]
		if def then
			Event("def", { on = WhoIs(dstGUID), spell = def.name })
		end
	end)
end
