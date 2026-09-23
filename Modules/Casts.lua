--[[ FycoPvP - Modules/Casts.lua
     Step 3. Cast bars for player, target and focus, with a spell icon, name,
     remaining time and an interrupt-state colour.
     3.3.5a return signatures, confirmed against TidyPlatesCore.lua:679-683:
       UnitCastingInfo -> name, rank, displayName, icon, startTime, endTime,
                          isTradeSkill, castID, notInterruptible   (9)
       UnitChannelInfo -> name, rank, displayName, icon, startTime, endTime,
                          isTradeSkill, notInterruptible           (8)
     startTime/endTime are milliseconds, so both are divided by 1000.
     Runs its own OnUpdate rather than the shared 10 Hz tick: a cast bar
     stepping ten times a second reads as stuttering.
     Loaded by Core.lua at PLAYER_LOGIN.                                      ]]

local ADDON, ns = ...
local M = ns:Module("casts")

local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local UnitExists      = UnitExists
local GetTime         = GetTime

local BARS = {
	{ unit = "player", label = "You",    w = 260, h = 22, def = { "CENTER", 0, -240 } },
	{ unit = "target", label = "Target", w = 240, h = 20, def = { "CENTER", 0,  200 } },
	{ unit = "focus",  label = "Focus",  w = 240, h = 20, def = { "CENTER", 0,  250 } },
}

local COLOR = {
	player      = { 0.20, 0.45, 0.90 },
	channel     = { 0.25, 0.70, 0.90 },
	stoppable   = { 0.95, 0.80, 0.20 },  -- you can interrupt this
	unstoppable = { 0.45, 0.45, 0.45 },  -- do not waste Spell Lock
}

local bars = {}

----------------------------------------------------------------------
-- construction
----------------------------------------------------------------------

local function MakeBar(cfg)
	local f = CreateFrame("Frame", ADDON .. "Cast" .. cfg.unit, UIParent)
	f:SetWidth(cfg.w)
	f:SetHeight(cfg.h)
	f:SetMovable(true)
	f:EnableMouse(false)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, _, x, y = self:GetPoint(1)
		FycoPvPDB.castPos = FycoPvPDB.castPos or {}
		FycoPvPDB.castPos[cfg.unit] = { p, x, y }
	end)

	local saved = FycoPvPDB.castPos and FycoPvPDB.castPos[cfg.unit]
	local p = saved or cfg.def
	f:SetPoint(p[1], UIParent, p[1], p[2], p[3])

	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints(f)
	f.bg:SetTexture(0, 0, 0, 0.65)

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetWidth(cfg.h)
	f.icon:SetHeight(cfg.h)
	f.icon:SetPoint("RIGHT", f, "LEFT", -3, 0)
	f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	f.bar = CreateFrame("StatusBar", nil, f)
	f.bar:SetAllPoints(f)
	f.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	f.bar:SetMinMaxValues(0, 1)
	f.bar:SetValue(0)

	f.name = f.bar:CreateFontString(nil, "OVERLAY")
	f.name:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	f.name:SetPoint("LEFT", f, "LEFT", 5, 0)
	f.name:SetJustifyH("LEFT")
	f.name:SetWidth(cfg.w - 60)

	f.time = f.bar:CreateFontString(nil, "OVERLAY")
	f.time:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	f.time:SetPoint("RIGHT", f, "RIGHT", -5, 0)

	f.cfg = cfg
	f:Hide()
	return f
end

----------------------------------------------------------------------
-- polling
----------------------------------------------------------------------

--- Returns icon, name, start, finish, notInterruptible, isChannel -- or nil.
local function CastInfo(unit)
	local name, _, _, icon, startTime, endTime, _, _, notInterruptible = UnitCastingInfo(unit)
	if name then
		return icon, name, startTime / 1000, endTime / 1000, notInterruptible, false
	end
	local cname, _, _, cicon, cstart, cend, _, cnotInt = UnitChannelInfo(unit)
	if cname then
		return cicon, cname, cstart / 1000, cend / 1000, cnotInt, true
	end
	return nil
end

local function UpdateBar(f, now)
	local unit = f.cfg.unit

	if f.preview then return end

	if not UnitExists(unit) then
		if f:IsShown() then f:Hide() end
		return
	end

	local icon, name, start, finish, notInt, channel = CastInfo(unit)
	if not name then
		if f:IsShown() then f:Hide() end
		return
	end

	local total = finish - start
	if total <= 0 then return end
	local elapsed = now - start
	if elapsed < 0 then elapsed = 0 end
	if elapsed > total then elapsed = total end

	-- a channel drains rather than fills
	f.bar:SetValue(channel and (1 - elapsed / total) or (elapsed / total))
	f.icon:SetTexture(icon)
	f.name:SetText(name)
	f.time:SetText(string.format("%.1f", math.max(0, finish - now)))

	local c
	if unit == "player" then
		c = channel and COLOR.channel or COLOR.player
	else
		c = notInt and COLOR.unstoppable or COLOR.stoppable
	end
	f.bar:SetStatusBarColor(c[1], c[2], c[3])

	if not f:IsShown() then f:Show() end
end

----------------------------------------------------------------------
-- load
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Blizzard's own cast bars
----------------------------------------------------------------------

-- Silence the stock bars we are replacing. UnregisterAllEvents stops them
-- driving themselves; the OnShow hook catches anything that shows them anyway
-- (MoveAnything re-anchors them, which can re-show them). Reversible with
-- /fyco blizz followed by a UI reload.
local function SuppressBlizzard()
	local frames = { CastingBarFrame, TargetFrameSpellBar, FocusFrameSpellBar }
	for i = 1, #frames do
		local f = frames[i]
		if f and not f.fycoSuppressed then
			f.fycoSuppressed = true
			f:UnregisterAllEvents()
			f:Hide()
			f:HookScript("OnShow", function(self)
				if FycoPvPDB and FycoPvPDB.hideBlizzCast then self:Hide() end
			end)
		end
	end
end

----------------------------------------------------------------------
-- positioning, in MoveAnything's coordinate system
----------------------------------------------------------------------

local byUnit = {}

--- Place a bar at x,y measured from the bottom-left of the screen -- the same
--- anchor and numbers MoveAnything shows, so its coordinates can be copied
--- straight across.
function ns:SetCastBarPos(unit, x, y)
	local f = byUnit[unit]
	if not f then return false end
	f:ClearAllPoints()
	f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
	FycoPvPDB.castPos = FycoPvPDB.castPos or {}
	FycoPvPDB.castPos[unit] = { "BOTTOMLEFT", x, y }
	return true
end

function ns:SetCastBarScale(unit, scale)
	local f = byUnit[unit]
	if not f then return false end
	f:SetScale(scale)
	FycoPvPDB.castScale = FycoPvPDB.castScale or {}
	FycoPvPDB.castScale[unit] = scale
	return true
end

function ns:CastBarInfo()
	for i = 1, #bars do
		local f = bars[i]
		local p, _, _, x, y = f:GetPoint(1)
		ns:Print(string.format("  %-6s %s  x=%.1f y=%.1f scale=%.2f",
			f.cfg.unit, p, x, y, f:GetScale()))
	end
end

function M:OnLoad()
	if FycoPvPDB.hideBlizzCast == nil then FycoPvPDB.hideBlizzCast = true end

	for i = 1, #BARS do
		bars[i] = MakeBar(BARS[i])
		byUnit[BARS[i].unit] = bars[i]
		local s = FycoPvPDB.castScale and FycoPvPDB.castScale[BARS[i].unit]
		if s then bars[i]:SetScale(s) end
	end

	if FycoPvPDB.hideBlizzCast then SuppressBlizzard() end

	local driver = CreateFrame("Frame", ADDON .. "CastDriver", UIParent)
	driver:SetScript("OnUpdate", function()
		if not ns:Enabled("casts") then
			for i = 1, #bars do
				if bars[i]:IsShown() and not bars[i].preview then bars[i]:Hide() end
			end
			return
		end
		local now = GetTime()
		for i = 1, #bars do
			UpdateBar(bars[i], now)
		end
	end)

	ns:Subscribe("ToggleLock", function()
		for i = 1, #bars do
			local f = bars[i]
			if f:IsMouseEnabled() then
				f:EnableMouse(false)
				f.preview = nil
				f:Hide()
			else
				f:EnableMouse(true)
				f.preview = true
				f.bar:SetValue(0.65)
				f.bar:SetStatusBarColor(0.6, 0.6, 0.6)
				f.icon:SetTexture("Interface\\Icons\\Spell_Shadow_ShadowBolt")
				f.name:SetText(f.cfg.label .. " cast bar")
				f.time:SetText("2.5")
				f:Show()
			end
		end
	end)
end
