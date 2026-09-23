--[[ FycoPvP - Modules/Recap.lua
     Death recap. Keeps a rolling window of everything that happened TO you and
     prints it when you die, so "what even killed me" stops being a guess.

     Runs its own COMBAT_LOG_EVENT_UNFILTERED handler rather than going through
     the message bus: damage is the highest-frequency event in the game and the
     bus would mean allocating and dispatching for every tick of every DoT on
     every unit in a 40-man battleground. The handler's first act is to compare
     dstGUID against the player and return, which is one comparison.

     Storage is a fixed ring buffer. A growing table pruned on insert is O(n)
     per event; a ring is O(1) and never allocates after load.
     Loaded by Core.lua at PLAYER_LOGIN.                                      ]]

local ADDON, ns = ...
local M = ns:Module("recap")

local GetTime     = GetTime
local UnitHealth  = UnitHealth
local UnitHealthMax = UnitHealthMax

local SIZE   = 160     -- ring slots; ~15s of a heavy battleground
local LINES  = 16      -- most lines we will print

local ring, pos, filled = {}, 0, false
local last                    -- the most recent recap, for /fyco recap

for i = 1, SIZE do ring[i] = {} end

----------------------------------------------------------------------
-- capture
----------------------------------------------------------------------

local function push(kind, src, spell, amount, crit, school)
	pos = pos + 1
	if pos > SIZE then pos = 1 filled = true end
	local e = ring[pos]
	e.t      = GetTime()
	e.kind   = kind
	e.src    = src
	e.spell  = spell
	e.amount = amount
	e.crit   = crit
	e.school = school
	local max = UnitHealthMax("player")
	e.hp = (max and max > 0) and (UnitHealth("player") / max) or nil
end

-- Damage events differ only in how many arguments sit before the amount.
-- offset = how many event-specific args precede it.
local DAMAGE = {
	SWING_DAMAGE           = 0,
	SPELL_DAMAGE           = 3,
	SPELL_PERIODIC_DAMAGE  = 3,
	RANGE_DAMAGE           = 3,
	DAMAGE_SHIELD          = 3,
	SPELL_BUILDING_DAMAGE  = 3,
}

local HEAL = {
	SPELL_HEAL          = 3,
	SPELL_PERIODIC_HEAL = 3,
}

local function OnCombatLog(_, _, ev, srcGUID, srcName, srcFlags,
                           dstGUID, dstName, dstFlags, ...)
	if dstGUID ~= ns.player then return end
	if not ns:Enabled("recap") then return end

	local off = DAMAGE[ev]
	if off then
		local spell, amount, crit
		if off == 0 then
			spell  = "Melee"
			amount = ...
			crit   = select(7, ...)
		else
			spell  = select(2, ...)
			amount = select(4, ...)
			crit   = select(10, ...)
		end
		if amount and amount > 0 then
			push("dmg", srcName, spell, amount, crit)
		end
		return
	end

	if ev == "ENVIRONMENTAL_DAMAGE" then
		local etype, amount = ...
		if amount and amount > 0 then push("dmg", "Environment", etype, amount) end
		return
	end

	off = HEAL[ev]
	if off then
		local spell  = select(2, ...)
		local amount = select(4, ...)
		local over   = select(5, ...)
		if amount and amount > 0 then
			push("heal", srcName, spell, amount - (over or 0))
		end
		return
	end

	if ev == "SPELL_AURA_APPLIED" then
		local spellID = ...
		local cc = spellID and ns.CC[spellID]
		if cc then
			push("cc", srcName, GetSpellInfo(spellID) or "?", nil, nil, cc.cat)
		end
		return
	end

	if ev == "SPELL_INTERRUPT" then
		local _, _, _, extraID = ...
		push("kick", srcName, GetSpellInfo(extraID) or "a cast")
	end
end

----------------------------------------------------------------------
-- reporting
----------------------------------------------------------------------

local function comma(n)
	n = tostring(math.floor(n + 0.5))
	local out = n
	while true do
		local swapped
		out, swapped = out:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if swapped == 0 then break end
	end
	return out
end

--- Walk the ring newest-first, stopping at the window edge.
local function Collect(window)
	local cut, out = GetTime() - window, {}
	local n = filled and SIZE or pos
	for i = 1, n do
		local idx = pos - i + 1
		if idx < 1 then idx = idx + SIZE end
		local e = ring[idx]
		if not e.t or e.t < cut then break end
		table.insert(out, 1, e)   -- oldest first for printing
	end
	return out
end

local function Build(window)
	local events = Collect(window)
	if #events == 0 then return nil end

	local died, total, bySource = events[#events].t, 0, {}
	for i = 1, #events do
		local e = events[i]
		if e.kind == "dmg" then
			total = total + (e.amount or 0)
			local k = e.src or "Unknown"
			bySource[k] = (bySource[k] or 0) + (e.amount or 0)
		end
	end

	return { events = events, total = total, bySource = bySource,
	         died = died, window = window }
end

local function Report(r)
	if not r then ns:Print("nothing recorded - no recap to show") return end

	ns:Print(string.format("|cffff4444death recap|r - %s damage over the last %.0fs",
		comma(r.total), r.window))

	local first = math.max(1, #r.events - LINES + 1)
	if first > 1 then
		ns:Print(string.format("  |cff808080...%d earlier events omitted|r", first - 1))
	end

	for i = first, #r.events do
		local e = r.events[i]
		local ago = e.t - r.died
		local hp  = e.hp and string.format("%3.0f%%", e.hp * 100) or "  ?"
		local who = e.src or "?"
		if #who > 14 then who = who:sub(1, 13) .. "." end

		if e.kind == "dmg" then
			ns:Print(string.format("  %5.1fs [%s] |cffff8080%-18s|r %-14s %s%s",
				ago, hp, (e.spell or "?"):sub(1, 18), who,
				comma(e.amount or 0), e.crit and " |cffffff00crit|r" or ""))
		elseif e.kind == "heal" then
			ns:Print(string.format("  %5.1fs [%s] |cff80ff80%-18s|r %-14s +%s",
				ago, hp, (e.spell or "?"):sub(1, 18), who, comma(e.amount or 0)))
		elseif e.kind == "cc" then
			ns:Print(string.format("  %5.1fs [%s] |cffc080ff%-18s|r %-14s |cff808080%s|r",
				ago, hp, (e.spell or "?"):sub(1, 18), who, e.school or "cc"))
		else
			ns:Print(string.format("  %5.1fs [%s] |cff80c0ff%-18s|r %-14s |cff808080interrupted|r",
				ago, hp, (e.spell or "?"):sub(1, 18), who))
		end
	end

	-- who actually did it, which the line-by-line view hides when the damage
	-- is spread over many small hits
	local names = {}
	for k in pairs(r.bySource) do table.insert(names, k) end
	table.sort(names, function(a, b) return r.bySource[a] > r.bySource[b] end)
	local parts = {}
	for i = 1, math.min(4, #names) do
		local pct = r.total > 0 and (r.bySource[names[i]] / r.total * 100) or 0
		table.insert(parts, string.format("%s %s (%.0f%%)",
			names[i], comma(r.bySource[names[i]]), pct))
	end
	if #parts > 0 then
		ns:Print("  |cffffff00by source:|r " .. table.concat(parts, "  |  "))
	end
end

--- /fyco recap -- reprint the last death, or show the current window live.
function ns:RecapReport(live)
	if live then
		Report(Build(FycoPvPDB.recapWindow or 10))
	elseif last then
		Report(last)
	else
		ns:Print("no death recorded yet. |cffffff00/fyco recap now|r shows the last "
		      .. (FycoPvPDB.recapWindow or 10) .. "s as it stands.")
	end
end

----------------------------------------------------------------------

function M:OnLoad()
	if FycoPvPDB.recapWindow == nil then FycoPvPDB.recapWindow = 10 end
	if FycoPvPDB.recapAuto   == nil then FycoPvPDB.recapAuto   = true end

	ns:On("COMBAT_LOG_EVENT_UNFILTERED", OnCombatLog)

	ns:On("PLAYER_DEAD", function()
		if not ns:Enabled("recap") then return end
		last = Build(FycoPvPDB.recapWindow or 10)
		if last then
			last.at = GetTime()
			if FycoPvPDB.recapAuto then Report(last) end
			ns:Fire("PlayerDied", last)
		end
	end)

	-- a new match should not inherit the previous one's damage
	ns:Subscribe("MatchStart", function()
		pos, filled = 0, false
		for i = 1, SIZE do ring[i].t = nil end
	end)
end
