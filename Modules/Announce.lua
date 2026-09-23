--[[ FycoPvP - Modules/Announce.lua
     Tells your team what you just did, in party chat.

     OFF BY DEFAULT, on purpose. This is the one module that puts text in front
     of other people, and an addon that floods a battleground gets its owner
     muted or reported rather than thanked. Turn it on with /fyco announce on.

     Two safeguards are not optional and cannot be configured away:
       - a minimum gap between any two messages
       - a ceiling on messages per window, after which it goes quiet until the
         window rolls over
     Between them the module cannot spam even if every event fires at once.

     Default channel is PARTY rather than BATTLEGROUND: your own group wants to
     know the healer is feared, thirty-nine strangers do not.
     Loaded by Core.lua at PLAYER_LOGIN.                                      ]]

local ADDON, ns = ...
local M = ns:Module("announce")

local GetTime         = GetTime
local GetSpellInfo    = GetSpellInfo
local SendChatMessage = SendChatMessage

local MIN_GAP   = 1.5   -- seconds between any two messages
local MAX_BURST = 5     -- messages allowed per WINDOW
local WINDOW    = 15

local lastSent, burst, burstStart = 0, 0, 0

local DEFAULTS = {
	enabled   = false,
	channel   = "PARTY",
	cc        = true,
	kick      = true,
	trinket   = true,
	drink     = true,
	defensive = false,
}

local CHANNELS = { PARTY = true, BATTLEGROUND = true, RAID = true, SAY = true }

----------------------------------------------------------------------

local function cfg()
	FycoPvPDB.announce = FycoPvPDB.announce or {}
	return FycoPvPDB.announce
end

local function Name(guid)
	local u = guid and ns.units[guid]
	local n = u and u.name
	return n and (n:match("^([^-]+)") or n) or "someone"
end

--- Is there anywhere to send this, and are we allowed to right now?
local function Send(msg)
	local c = cfg()
	if not c.enabled or not ns:Enabled("announce") then return end

	local now = GetTime()
	if now - lastSent < MIN_GAP then return end
	if now - burstStart > WINDOW then
		burstStart, burst = now, 0
	end
	if burst >= MAX_BURST then return end

	local channel = c.channel
	if channel == "PARTY" and GetNumPartyMembers() == 0
	   and GetNumRaidMembers() == 0 then
		return                       -- solo: nobody to tell
	end
	if channel == "RAID" and GetNumRaidMembers() == 0 then return end
	if channel == "BATTLEGROUND" and not ns:InPvP() then return end

	lastSent = now
	burst = burst + 1
	SendChatMessage(msg, channel)
end

----------------------------------------------------------------------

--- /fyco announce [on|off|<channel>|<what>]
function ns:AnnounceConfig(rest)
	local c = cfg()
	rest = (rest or ""):lower()

	if rest == "" then
		ns:Print("party announce: " ..
			(c.enabled and "|cff00ff00on|r" or "|cffff0000off|r") ..
			"  channel |cffffff00" .. tostring(c.channel) .. "|r")
		ns:Print("  cc " .. (c.cc and "on" or "off")
			.. " | kick " .. (c.kick and "on" or "off")
			.. " | trinket " .. (c.trinket and "on" or "off")
			.. " | drink " .. (c.drink and "on" or "off")
			.. " | defensive " .. (c.defensive and "on" or "off"))
		ns:Print("  |cffffff00/fyco announce on|off|r, |cffffff00/fyco announce "
		      .. "party|bg|raid|say|r, or toggle one with |cffffff00/fyco announce cc|r")
		ns:Print("  |cff808080capped at " .. MAX_BURST .. " messages per "
		      .. WINDOW .. "s no matter what is enabled|r")
		return
	end

	if rest == "on" or rest == "off" then
		c.enabled = (rest == "on")
		ns:Print("party announce " .. (c.enabled and "|cff00ff00on|r" or "|cffff0000off|r"))
		return
	end

	local chan = rest:upper()
	if chan == "BG" then chan = "BATTLEGROUND" end
	if CHANNELS[chan] then
		c.channel = chan
		ns:Print("announcing to |cffffff00" .. chan .. "|r")
		return
	end

	if rest ~= "enabled" and type(c[rest]) == "boolean" then
		c[rest] = not c[rest]
		ns:Print(rest .. " announce " .. (c[rest] and "on" or "off"))
		return
	end

	ns:Print("not a setting: " .. rest .. " - try |cffffff00/fyco announce|r")
end

----------------------------------------------------------------------

function M:OnLoad()
	local c = cfg()
	for k, v in pairs(DEFAULTS) do
		if c[k] == nil then c[k] = v end
	end

	-- CC you landed. DRApplied carries the level, which is the part your team
	-- actually needs: a fear at 25% is not worth peeling for.
	ns:Subscribe("DRApplied", function(guid, cat, level, srcGUID, spellID)
		if srcGUID ~= ns.player or not cfg().cc then return end
		local label = ns.DRLabel[level] or "100%"
		Send(string.format("%s -> %s [%s]",
			GetSpellInfo(spellID) or cat, Name(guid), label))
	end)

	ns:Subscribe("Interrupt", function(srcGUID, dstGUID, kickID, extraID)
		if srcGUID ~= ns.player or not cfg().kick then return end
		Send(string.format("Interrupted %s: %s",
			Name(dstGUID), GetSpellInfo(extraID) or "cast"))
	end)

	ns:Subscribe("AuraApplied", function(dstGUID, spellID)
		if dstGUID == ns.player then return end
		local c2 = cfg()
		if spellID == 42292 or spellID == 59752 or spellID == 7744 then
			if c2.trinket then Send(Name(dstGUID) .. " TRINKETED") end
			return
		end
		local def = ns.Defensives[spellID]
		if def and c2.defensive then
			Send(string.format("%s used %s", Name(dstGUID), def.name))
		end
	end)

	ns:Subscribe("Drinking", function(guid, name)
		if cfg().drink then Send((name or Name(guid)) .. " is drinking") end
	end)

	ns:Subscribe("MatchStart", function()
		lastSent, burst, burstStart = 0, 0, 0
	end)
end
