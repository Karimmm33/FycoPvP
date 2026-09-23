--[[ FycoPvP - Modules/CDText.lua
     Countdown numbers on every cooldown in the game: action bars, items, bags,
     the pet bar. What OmniCC does, without needing OmniCC.

     ------------------------------------------------------------------------
     Derived from OmniCC 3.0.4 by Tuller, used under the MIT licence.

       Copyright (c) 2010 Jason Greer

       Permission is hereby granted, free of charge, to any person obtaining a
       copy of this software and associated documentation files (the
       "Software"), to deal in the Software without restriction, including
       without limitation the rights to use, copy, modify, merge, publish,
       distribute, sublicense, and/or sell copies of the Software, and to
       permit persons to whom the Software is furnished to do so, subject to
       the following conditions:

       The above copyright notice and this permission notice shall be included
       in all copies or substantial portions of the Software.

       THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
       OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
       MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
       IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
       CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
       TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
       SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
     ------------------------------------------------------------------------

     This is a port, not a copy. OmniCC's cc.lua needs Classy-1.0 through
     LibStub and reads every setting from its own 514-line config module, so
     lifting the file wholesale would have dragged three more files in and
     broken this addon's zero-dependency rule. What IS carried across is the
     part worth keeping -- the timing logic, which is subtler than it looks:

       * ADAPTIVE UPDATES. FormatTime returns the text *and* how long until
         that text would next change. A timer showing "4" needs no attention
         for another second. Redrawing every cooldown every frame is the
         obvious implementation, and it is what makes naive versions of this
         cost real framerate.
       * TRANSITION CONSTANTS at 59.5 and 5.5 seconds rather than 60 and 5, so
         the display does not flicker between units as it rounds.
       * FONT SCALED against a 36px reference icon and hidden below a minimum
         size -- without that, bag-slot cooldowns render as unreadable smears.
       * The text frame is CENTRED on the cooldown with an explicit size,
         never SetAllPoints. Tuller's comment notes the text drifts when the
         frame is scaled otherwise.

     Loaded by Core.lua at PLAYER_LOGIN. Stands down if OmniCC is running.  ]]

local ADDON, ns = ...
local M = ns:Module("cdtext")

local GetTime = GetTime
local floor   = math.floor
local format  = string.format

local function round(x) return floor(x + 0.5) end

-- the size an icon is assumed to be when the font size is chosen
local ICON_SIZE = 36
local DAY, HOUR, MINUTE = 86400, 3600, 60
-- transition points, deliberately half a second early (see the header)
local DAYISH, HOURISH, MINUTEISH, SOONISH = HOUR * 23.5, MINUTE * 59.5, 59.5, 5.5
local HALFDAYISH, HALFHOURISH, HALFMINUTEISH =
	DAY / 2 + 0.5, HOUR / 2 + 0.5, MINUTE / 2 + 0.5

local DEFAULTS = {
	minDuration = 3,      -- ignore anything shorter: the GCD, mostly
	tenths      = 3,      -- show tenths below this many seconds (0 = never)
	mmss        = 0,      -- show M:SS below this many seconds (0 = never)
	fontSize    = 18,
	minFontSize = 8,      -- below this the text hides rather than be squinted at
	scaleText   = true,
	hideModel   = false,  -- true removes Blizzard's sweep, leaving only numbers
}

local COLORS = {
	soon    = { 1.00, 0.20, 0.20 },
	seconds = { 1.00, 0.90, 0.30 },
	minutes = { 1.00, 1.00, 1.00 },
	hours   = { 0.70, 0.70, 0.70 },
}

local timers = setmetatable({}, { __mode = "k" })  -- weak: frames get recycled
local hooked = false

----------------------------------------------------------------------

local function cfg()
	FycoPvPDB.cdtext = FycoPvPDB.cdtext or {}
	local c = FycoPvPDB.cdtext
	for k, v in pairs(DEFAULTS) do
		if c[k] == nil then c[k] = v end
	end
	return c
end

--- The text to show, and how many seconds until it would change.
--- Returning both is the whole performance story; see the header.
local function FormatTime(s, c)
	if c.tenths > 0 and s < c.tenths then
		return format("%.1f", s), (s * 10 - floor(s * 10)) / 10
	end

	if s < MINUTEISH then
		local seconds = round(s)
		if seconds == 0 then return "", s end
		-- tighten the update rate as we approach the tenths threshold
		if c.tenths > 0 and s < (c.tenths + 0.5) then
			return seconds, (s * 10 - floor(s * 10)) / 10
		end
		return seconds, s - (seconds - 0.51)
	end

	if c.mmss > 0 and s < c.mmss then
		local seconds = round(s)
		return format("%d:%02d", seconds / MINUTE, seconds % MINUTE),
		       s - (seconds - 0.51)
	end

	if s < HOURISH then
		local minutes = round(s / MINUTE)
		return minutes .. "m",
		       minutes > 1 and (s - (minutes * MINUTE - HALFMINUTEISH))
		                   or (s - MINUTEISH)
	end

	if s < DAYISH then
		local hours = round(s / HOUR)
		return hours .. "h",
		       hours > 1 and (s - (hours * HOUR - HALFHOURISH)) or (s - HOURISH)
	end

	local days = round(s / DAY)
	return days .. "d",
	       days > 1 and (s - (days * DAY - HALFDAYISH)) or (s - DAYISH)
end

local function PeriodColor(s)
	if s < SOONISH   then return COLORS.soon end
	if s < MINUTEISH then return COLORS.seconds end
	if s < HOURISH   then return COLORS.minutes end
	return COLORS.hours
end

----------------------------------------------------------------------

local Stop, UpdateFont

local function UpdateText(t)
	if not (t.start and t.duration) then return Stop(t) end

	local remain = t.duration - (GetTime() - t.start)
	if remain <= 0 then return Stop(t) end

	local text, nextUpdate = FormatTime(remain, cfg())
	t.text:SetText(text)
	local col = PeriodColor(remain)
	t.text:SetTextColor(col[1], col[2], col[3])
	t.nextUpdate = nextUpdate or 0.1
end

local function OnUpdate(self, elapsed)
	if self.nextUpdate > 0 then
		self.nextUpdate = self.nextUpdate - elapsed
	else
		UpdateText(self)
	end
end

function UpdateFont(t)
	local c = cfg()
	local size = c.fontSize
	if c.scaleText then
		local w = t:GetWidth()
		if w and w > 0 then size = size * (w / ICON_SIZE) end
	end
	t.fontSize = size
	if size >= c.minFontSize then
		t.text:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
		t.text:Show()
	else
		-- too small to read; drawing it would only be noise
		t.text:Hide()
	end
end

function Stop(t)
	t.start, t.duration, t.nextUpdate = nil, nil, nil
	t:Hide()
end

local function NewTimer(cooldown)
	local t = CreateFrame("Frame", nil, cooldown:GetParent())
	t:Hide()
	t.cooldown = cooldown
	t:SetFrameLevel(cooldown:GetFrameLevel() + 5)

	t.text = t:CreateFontString(nil, "OVERLAY")
	t.text:SetPoint("CENTER", 0, 0)
	t.text:SetJustifyH("CENTER")

	-- Centred with an explicit size rather than SetAllPoints: the text drifts
	-- when the frame is scaled otherwise (Tuller's note, kept).
	t:SetPoint("CENTER", cooldown)
	t:SetWidth(cooldown:GetWidth() or ICON_SIZE)
	t:SetHeight(cooldown:GetHeight() or ICON_SIZE)

	t:SetScript("OnUpdate", OnUpdate)
	t:SetScript("OnSizeChanged", function(self, w, h)
		if w and w > 0 then
			self:SetWidth(w)
			self:SetHeight(h)
		end
		UpdateFont(self)
	end)

	UpdateFont(t)
	timers[cooldown] = t
	return t
end

local function Start(cooldown, start, duration)
	local t = timers[cooldown] or NewTimer(cooldown)
	t.start, t.duration, t.nextUpdate = start, duration, 0

	-- the cooldown may have been resized since we last saw it
	local w = cooldown:GetWidth()
	if w and w > 0 and math.abs(w - (t:GetWidth() or 0)) > 0.5 then
		t:SetWidth(w)
		t:SetHeight(cooldown:GetHeight())
		UpdateFont(t)
	end

	if t.fontSize >= cfg().minFontSize then
		t:Show()
		UpdateText(t)
	else
		t:Hide()
	end
end

--- Runs for every cooldown the game starts, anywhere in the interface.
local function OnSetCooldown(self, start, duration)
	-- Any frame may opt out by setting this, which is the same flag OmniCC
	-- reads. FycoPvP's own icons set it, because they draw their own text.
	if self.noCooldownCount then return end

	if not ns:Enabled("cdtext") then
		local t = timers[self]
		if t and t:IsShown() then Stop(t) end
		return
	end

	local c = cfg()
	if c.hideModel then self:SetAlpha(0) end

	if start and start > 0 and duration and duration >= c.minDuration then
		Start(self, start, duration)
	else
		local t = timers[self]
		if t then Stop(t) end
	end
end

----------------------------------------------------------------------

--- /fyco cdtext [setting] [value]
function ns:CDTextConfig(rest)
	local c = cfg()
	local key, val = (rest or ""):match("^(%a+)%s*([%d%.]*)$")

	if not key or key == "" then
		if ns.cdtextIdle then
			ns:Print("|cff808080" .. ns.cdtextIdle .. ".|r Disable OmniCC and "
			      .. "|cffffff00/reload|r to use this instead.")
		end
		ns:Print("cooldown numbers on your action bars:")
		ns:Print(string.format("  minDuration %s   tenths %s   mmss %s",
			c.minDuration, c.tenths, c.mmss))
		ns:Print(string.format("  fontSize %s   minFontSize %s   scaleText %s   hideModel %s",
			c.fontSize, c.minFontSize, tostring(c.scaleText), tostring(c.hideModel)))
		ns:Print("  |cffffff00/fyco cdtext <setting> <number>|r, or")
		ns:Print("  |cffffff00/fyco cdtext scaletext|r / |cffffff00hidemodel|r to toggle")
		return
	end

	local lower = key:lower()
	if lower == "scaletext" then
		c.scaleText = not c.scaleText
		ns:Print("scaleText " .. tostring(c.scaleText)
		      .. " - |cffffff00/reload|r to apply")
		return
	end
	if lower == "hidemodel" then
		c.hideModel = not c.hideModel
		ns:Print("hideModel " .. tostring(c.hideModel)
		      .. " - |cffffff00/reload|r to apply")
		return
	end

	for k in pairs(DEFAULTS) do
		if k:lower() == lower then
			local n = tonumber(val)
			if not n then
				ns:Print(k .. " is " .. tostring(c[k])
				      .. " - give it a number to change it")
			else
				c[k] = n
				ns:Print(string.format("%s = %s - |cffffff00/reload|r to apply everywhere",
					k, n))
			end
			return
		end
	end

	ns:Print("not a setting: " .. key .. " - try |cffffff00/fyco cdtext|r")
end

----------------------------------------------------------------------

function M:OnLoad()
	cfg()

	-- Two addons drawing numbers on one icon gives you two numbers. If OmniCC
	-- is running it owns this job, and we stay out of its way.
	if IsAddOnLoaded("OmniCC") then
		ns.cdtextIdle = "OmniCC is handling cooldown numbers"
		ns:Debug("cdtext: OmniCC is loaded, standing down")
		return
	end

	-- One hook on the shared Cooldown metatable covers every cooldown in the
	-- game: action bars, items, bags, the pet bar. ActionButton1Cooldown is
	-- simply a convenient instance to reach that metatable through.
	if not hooked and ActionButton1Cooldown then
		hooksecurefunc(getmetatable(ActionButton1Cooldown).__index,
			"SetCooldown", OnSetCooldown)
		hooked = true
	end

	-- entering an arena can leave timers stale; nudge them
	ns:On("PLAYER_ENTERING_WORLD", function()
		for _, t in pairs(timers) do
			if t:IsShown() then UpdateText(t) end
		end
	end)
end
