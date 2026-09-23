--[[ FycoPvP - Modules/Stats.lua
     Counts the things that decide games, so "I think my kicks are fine" can be
     checked against what actually happened.

     THREE SCOPES, and the difference matters:
       match   - in memory. Zeroed every time you enter an arena or a
                 battleground, so it always describes the game you are in.
       session - saved per character. Survives a /reload, because reloading is
                 something you do mid-evening and it should not cost you your
                 numbers. Rolls over on its own once FycoPvPDB.sessionGap
                 seconds (default two hours) pass with nothing recorded, which
                 is what makes "tonight" and "last Tuesday" separate sessions
                 without anyone having to press a button.
       life    - saved per character, never resets by itself.

     Nothing here is inferred loosely. A kick counts as wasted only after we
     have watched for the interrupt that never came, and CC counts as ending
     early only when it really did -- the report says plainly that it cannot
     tell a damage break from a dispel from a trinket.
     Loaded by Core.lua at PLAYER_LOGIN.                                      ]]

local ADDON, ns = ...
local M = ns:Module("stats")

local GetTime      = GetTime
local GetSpellInfo = GetSpellInfo
local time         = time
local date         = date

-- how long we wait for the SPELL_INTERRUPT that proves a kick connected
local KICK_GRACE = 0.8
-- CC gone sooner than this counts as having ended early
local CC_SHORT   = 3.0

local COUNTERS = {
	"kicksLanded", "kicksWasted", "lockedOut", "lockedSeconds",
	"ccLanded", "ccShort", "drWasted", "trinketsSeen",
	"dispelsDone", "dispelsTaken", "deaths", "killingBlows",
}

local LABEL = {
	kicksLanded   = "interrupts landed",
	kicksWasted   = "interrupts wasted",
	lockedOut     = "times you were kicked",
	lockedSeconds = "seconds locked out",
	ccLanded      = "CC landed on players",
	ccShort       = "CC that ended early",
	drWasted      = "CC into 25% or immune",
	trinketsSeen  = "enemy trinkets seen",
	dispelsDone   = "dispels you did",
	dispelsTaken  = "dispels taken from you",
	deaths        = "deaths",
	killingBlows  = "killing blows",
}

local match                     -- in memory only
local pendingKick               -- an interrupt we cast, waiting to be judged
local ccOut = {}                -- ["guid:spellID"] = time you applied it

local TRINKET = { [42292] = true, [59752] = true, [7744] = true }

----------------------------------------------------------------------
-- storage
----------------------------------------------------------------------

local function blank()
	local t = {}
	for i = 1, #COUNTERS do t[COUNTERS[i]] = 0 end
	return t
end

local function Store()
	FycoPvPLog = FycoPvPLog or {}
	FycoPvPLog.stats = FycoPvPLog.stats or {}
	return FycoPvPLog.stats
end

--- Start a new session, leaving lifetime intact.
local function NewSession(s)
	s.session = blank()
	s.session.started      = time()
	s.session.lastActivity = time()
end

local function bump(key, by)
	local s = Store()
	by = by or 1
	if match then match[key] = (match[key] or 0) + by end
	if s.session then
		s.session[key] = (s.session[key] or 0) + by
		s.session.lastActivity = time()
	end
	if s.life then s.life[key] = (s.life[key] or 0) + by end
end

----------------------------------------------------------------------
-- counting
----------------------------------------------------------------------

local function IsMyInterrupt(spellID)
	local n = spellID and GetSpellInfo(spellID)
	if not n then return false end
	for _, info in pairs(ns.Interrupts) do
		if info.name == n then return true end
	end
	return false
end

local function Judge(now)
	-- An interrupt that connects produces SPELL_INTERRUPT almost immediately.
	-- One that does not connect produces nothing at all, so the only honest
	-- way to count a waste is to wait and see.
	if pendingKick and now - pendingKick > KICK_GRACE then
		pendingKick = nil
		bump("kicksWasted")
	end
end

----------------------------------------------------------------------
-- reporting
----------------------------------------------------------------------

local function pct(a, b)
	if not b or b == 0 then return "-" end
	return string.format("%.0f%%", a / b * 100)
end

-- What each counter is actually telling you. Printed by /fyco stats help so
-- the table itself stays a table instead of turning into an essay.
local TIP = {
	kicksLanded   = "an interrupt that connected with a cast",
	kicksWasted   = "you pressed an interrupt and nothing was being cast",
	lockedOut     = "how often somebody shut your school down",
	lockedSeconds = "total time you could not cast. Deaths hide in here",
	ccLanded      = "CC that landed on a real player, pets and mobs excluded",
	ccShort       = "CC gone in under 3s. Broken, dispelled or trinketed",
	drWasted      = "CC thrown into a category already at 25% or immune",
	trinketsSeen  = "enemy trinkets you watched being used",
	dispelsDone   = "auras you removed from somebody",
	dispelsTaken  = "your auras somebody removed",
	deaths        = "yours. /fyco recap says what did it",
	killingBlows  = "kills the server credited to you",
}

--- Every printed line goes through this, so the columns cannot drift apart.
--- Colour codes are passed as separate arguments rather than baked into the
--- format string: |cffffffff is invisible but still eight characters, so a
--- width specifier wrapped around one pads to the wrong place.
local function Line(label, m, s, l, labelColor)
	ns:Print(string.format("  %s%-22s|r %s%6s|r  %s%8s|r  %s%9s|r",
		labelColor or "|cffcccccc", label,
		"|cffffffff", tostring(m),
		"|cffaaaaaa", tostring(s),
		"|cff808080", tostring(l)))
end

--- Turn the session numbers into a few things worth doing differently.
--- Every threshold here is a rule of thumb I picked, not a measured truth,
--- and each one needs a minimum sample before it will say anything at all --
--- two wasted kicks out of three is noise, not a habit.
local function Assess(t)
	local out = {}

	local kicks = (t.kicksLanded or 0) + (t.kicksWasted or 0)
	if kicks >= 8 then
		local acc = (t.kicksLanded or 0) / kicks
		if acc < 0.70 then
			out[#out + 1] = { 3, string.format(
				"interrupt accuracy %s: roughly one kick in %d is hitting nothing. "
				.. "Kick the cast you can see, not the cooldown.",
				pct(t.kicksLanded, kicks), math.max(2, math.floor(1 / (1 - acc)))) }
		elseif acc >= 0.90 then
			out[#out + 1] = { 1, "interrupt accuracy " .. pct(t.kicksLanded, kicks)
				.. ": your kicks are going where they should. Nothing to change." }
		end
	end

	local cc = t.ccLanded or 0
	if cc >= 15 then
		if (t.ccShort or 0) / cc > 0.35 then
			out[#out + 1] = { 3, string.format(
				"%s of your CC ends inside 3 seconds. If it is your own damage "
				.. "breaking it, stop the DoT before the fear rather than after.",
				pct(t.ccShort, cc)) }
		end
		if (t.drWasted or 0) / cc > 0.15 then
			out[#out + 1] = { 2, string.format(
				"%s of your CC went into a category already at 25%% or immune. "
				.. "The DR row shows this before you press it.",
				pct(t.drWasted, cc)) }
		end
	end

	if (t.lockedOut or 0) >= 8 then
		local avg = (t.lockedSeconds or 0) / t.lockedOut
		out[#out + 1] = { 2, string.format(
			"kicked %d times for %.0f seconds total, about %.1fs each. That is "
			.. "the window they kill you in - fake-cast before the real one.",
			t.lockedOut, t.lockedSeconds or 0, avg) }
	end

	if cc >= 15 and (t.dispelsTaken or 0) > cc * 0.4 then
		out[#out + 1] = { 2, string.format(
			"%d of your auras were dispelled. Bait the dispel with something "
			.. "cheap before committing the one that matters.", t.dispelsTaken) }
	end

	if (t.deaths or 0) >= 5 then
		out[#out + 1] = { 1, string.format(
			"%d deaths this session. |cffffff00/fyco recap|r replays the last one.",
			t.deaths) }
	end

	table.sort(out, function(a, b) return a[1] > b[1] end)
	return out
end

--- /fyco stats help
function ns:StatsHelp()
	ns:Print("what each row means:")
	for i = 1, #COUNTERS do
		local k = COUNTERS[i]
		ns:Print(string.format("  |cffffff00%-24s|r %s", LABEL[k], TIP[k] or ""))
	end
	ns:Print("|cff808080columns are match / session / lifetime. |cffffff00/fyco stats|r"
	      .. " shows them, |cffffff00/fyco stats reset|r ends the session.|r")
end

--- /fyco stats
function ns:StatsReport()
	local s = Store()
	local sess, life = s.session or blank(), s.life or blank()
	local m = match or blank()

	Line("statistics", "match", "session", "lifetime", "|cffffff00")
	if sess.started then
		ns:Print(string.format("  |cff808080session opened %s|r",
			date("%Y-%m-%d %H:%M", sess.started)))
	end

	for i = 1, #COUNTERS do
		local k = COUNTERS[i]
		if k == "lockedSeconds" then
			Line(LABEL[k], string.format("%.0f", m[k] or 0),
				string.format("%.0f", sess[k] or 0),
				string.format("%.0f", life[k] or 0))
		else
			Line(LABEL[k], m[k] or 0, sess[k] or 0, life[k] or 0)
		end
	end

	-- the two ratios actually worth looking at
	local mk = (m.kicksLanded or 0) + (m.kicksWasted or 0)
	local sk = (sess.kicksLanded or 0) + (sess.kicksWasted or 0)
	local lk = (life.kicksLanded or 0) + (life.kicksWasted or 0)
	Line("interrupt accuracy",
		pct(m.kicksLanded or 0, mk),
		pct(sess.kicksLanded or 0, sk),
		pct(life.kicksLanded or 0, lk), "|cffffff00")
	Line("CC that stuck",
		pct((m.ccLanded or 0) - (m.ccShort or 0), m.ccLanded or 0),
		pct((sess.ccLanded or 0) - (sess.ccShort or 0), sess.ccLanded or 0),
		pct((life.ccLanded or 0) - (life.ccShort or 0), life.ccLanded or 0),
		"|cffffff00")

	local notes = Assess(sess)
	if #notes == 0 then
		ns:Print("|cff808080reading it: not enough recorded this session for any of "
		      .. "it to mean much yet.|r")
	else
		ns:Print("|cffffff00reading it|r |cff808080(this session)|r")
		for i = 1, math.min(3, #notes) do
			ns:Print("  |cff808080-|r " .. notes[i][2])
		end
	end

	ns:Print("|cff808080CC that ended early cannot tell a damage break from a "
	      .. "dispel or a trinket, and the advice above is rules of thumb, not "
	      .. "verdicts. |cffffff00/fyco stats help|r explains every row.|r")
	ns:Print("|cff808080the session rolls over by itself after "
	      .. math.floor((FycoPvPDB.sessionGap or 7200) / 60)
	      .. " idle minutes. |cffffff00/fyco stats reset|r ends it now.|r")
end

--- A copy of the current match's counters, for Archive to store with the game.
--- A copy rather than the table itself: the next MatchStart replaces `match`,
--- and a record that quietly re-pointed at the following game would be worse
--- than no record at all.
function ns:MatchStats()
	local out = {}
	for i = 1, #COUNTERS do
		out[COUNTERS[i]] = (match and match[COUNTERS[i]]) or 0
	end
	return out
end

--- /fyco stats reset [all]
function ns:StatsReset(all)
	local s = Store()
	NewSession(s)
	match = blank()
	if all then
		s.life = blank()
		s.life.started = time()
		ns:Print("session |cff00ff00and lifetime|r statistics cleared")
	else
		ns:Print("session statistics cleared (lifetime kept - "
		      .. "|cffffff00/fyco stats reset all|r clears that too)")
	end
end

----------------------------------------------------------------------

function M:OnLoad()
	if FycoPvPDB.sessionGap == nil then FycoPvPDB.sessionGap = 7200 end

	local s = Store()
	s.life = s.life or blank()
	s.life.started = s.life.started or time()

	-- Decide whether the saved session is still the one we are in. A /reload
	-- lands here seconds after the last event and continues it; coming back
	-- tomorrow lands here hours later and starts a new one.
	if not s.session or not s.session.lastActivity
	   or (time() - s.session.lastActivity) > FycoPvPDB.sessionGap then
		NewSession(s)
	end

	match = blank()

	-- your interrupts, and whether they hit anything
	ns:Subscribe("CastSuccess", function(srcGUID, spellID)
		if not ns:Enabled("stats") then return end
		if srcGUID == ns.player and IsMyInterrupt(spellID) then
			pendingKick = GetTime()
		end
	end)

	ns:Subscribe("Interrupt", function(srcGUID, dstGUID)
		if not ns:Enabled("stats") then return end
		if srcGUID == ns.player then
			pendingKick = nil
			bump("kicksLanded")
		end
		if dstGUID == ns.player then bump("lockedOut") end
	end)

	ns:Subscribe("Lockout", function(_, dstGUID, dur)
		if ns:Enabled("stats") and dstGUID == ns.player then
			bump("lockedSeconds", dur or 0)
		end
	end)

	-- CC you land, and whether it lasted
	ns:Subscribe("AuraApplied", function(dstGUID, spellID, srcGUID, _, dstFlags)
		if not ns:Enabled("stats") then return end

		if TRINKET[spellID] and dstGUID ~= ns.player then
			bump("trinketsSeen")
		end

		if srcGUID == ns.player and ns.CC[spellID]
		   and ns.TypeFromFlags(dstFlags) == "player" then
			bump("ccLanded")
			ccOut[tostring(dstGUID) .. ":" .. spellID] = GetTime()
		end
	end)

	ns:Subscribe("AuraRemoved", function(dstGUID, spellID)
		if not ns:Enabled("stats") then return end
		local key = tostring(dstGUID) .. ":" .. tostring(spellID)
		local at  = ccOut[key]
		if at then
			ccOut[key] = nil
			if GetTime() - at < CC_SHORT then bump("ccShort") end
		end
	end)

	-- CC thrown into a category that was already half used up
	ns:Subscribe("DRApplied", function(guid, cat, level)
		if ns:Enabled("stats") and level and level >= 3 then bump("drWasted") end
	end)

	ns:Subscribe("Dispel", function(srcGUID, dstGUID)
		if not ns:Enabled("stats") then return end
		if srcGUID == ns.player then bump("dispelsDone") end
		if dstGUID == ns.player then bump("dispelsTaken") end
	end)

	ns:Subscribe("Death", function(dstGUID, srcGUID, isKill)
		if not ns:Enabled("stats") then return end
		if dstGUID == ns.player then bump("deaths") end
		if isKill and srcGUID == ns.player then bump("killingBlows") end
	end)

	ns:OnTick(Judge)

	ns:Subscribe("MatchStart", function()
		match = blank()
		ccOut, pendingKick = {}, nil
	end)
end
