--[[ FycoPvP - Modules/Range.lua
     Am I in range of the thing I am about to cast?

     There is no GetDistance in 3.3.5a and no way to read yards. What there is
     is IsSpellInRange(spellName, unit), which returns 1, 0 or nil for a spell
     YOU know -- so the check has to be anchored to a real spell rather than to
     a number. Each class gets a sensible default from ns.RangeSpell, and any
     spell can be substituted with /fyco range <spell name>.

     nil means the question could not be answered: the spell is not in your
     book, or the unit is not a valid target for it. That is shown as unknown
     rather than quietly rendered as out of range, because a grey readout you
     can see beats a red one that lies.
     Loaded by Core.lua at PLAYER_LOGIN.                                      ]]

local ADDON, ns = ...
local M = ns:Module("range")

local IsSpellInRange = IsSpellInRange
local UnitExists     = UnitExists
local UnitCanAttack  = UnitCanAttack
local GetSpellInfo   = GetSpellInfo

local W, H = 150, 20

local frame
local spellName        -- what we are actually testing with

-- Published for Plates, which greys the target's name when this is true.
-- nil = unknown, so a consumer can tell "out of range" from "no idea".
ns.RangeOut = nil

----------------------------------------------------------------------

local function Resolve()
	local want = FycoPvPDB.rangeSpell
	if not want or want == "" then
		local _, class = UnitClass("player")
		want = ns.RangeSpell[class]
	end
	-- GetSpellInfo returns nil for a spell this character has not learned,
	-- which is the cheapest way to find out before trying to use it
	spellName = (want and GetSpellInfo(want)) and want or nil
	return spellName
end

local function Build()
	local f = CreateFrame("Frame", ADDON .. "Range", UIParent)
	f:SetWidth(W)
	f:SetHeight(H)
	f:SetMovable(true)
	f:EnableMouse(false)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, _, x, y = self:GetPoint(1)
		FycoPvPDB.rangePos = { p, x, y }
	end)

	local p = FycoPvPDB.rangePos or { "CENTER", 0, -200 }
	f:SetPoint(p[1], UIParent, p[1], p[2], p[3])

	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints(f)
	f.bg:SetTexture(0, 0, 0, 0.55)

	f.text = f:CreateFontString(nil, "OVERLAY")
	f.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	f.text:SetPoint("CENTER", f, "CENTER", 0, 0)

	f:Hide()
	return f
end

local function Update()
	if not frame or frame.preview then return end

	if not ns:Enabled("range") then
		ns.RangeOut = nil
		if frame:IsShown() then frame:Hide() end
		return
	end

	if not UnitExists("target") or not UnitCanAttack("player", "target") then
		ns.RangeOut = nil
		if frame:IsShown() then frame:Hide() end
		return
	end

	if not spellName and not Resolve() then
		ns.RangeOut = nil
		frame.text:SetText("|cff808080no range spell|r")
		frame.bg:SetTexture(0, 0, 0, 0.55)
		if not frame:IsShown() then frame:Show() end
		return
	end

	local r = IsSpellInRange(spellName, "target")
	if r == 1 then
		ns.RangeOut = false
		frame.text:SetText("|cff40ff40IN RANGE|r |cff808080" .. spellName .. "|r")
		frame.bg:SetTexture(0.05, 0.25, 0.05, 0.55)
	elseif r == 0 then
		ns.RangeOut = true
		frame.text:SetText("|cffff4040OUT OF RANGE|r")
		frame.bg:SetTexture(0.30, 0.05, 0.05, 0.65)
	else
		ns.RangeOut = nil
		frame.text:SetText("|cff808080range unknown|r")
		frame.bg:SetTexture(0, 0, 0, 0.55)
	end
	if not frame:IsShown() then frame:Show() end
end

----------------------------------------------------------------------

--- /fyco range [spell name | default]
function ns:RangeConfig(rest)
	if rest == "" then
		local _, class = UnitClass("player")
		ns:Print("range check uses: |cffffff00" .. tostring(spellName or "nothing") .. "|r")
		ns:Print("  class default: " .. tostring(ns.RangeSpell[class] or "none"))
		ns:Print("  change with |cffffff00/fyco range <spell name>|r, spelled exactly")
		ns:Print("  as it appears in your spellbook, or |cffffff00/fyco range default|r")
		return
	end
	if rest:lower() == "default" then
		FycoPvPDB.rangeSpell = nil
		Resolve()
		ns:Print("range spell reset to the class default: "
		      .. tostring(spellName or "none known"))
		return
	end
	if not GetSpellInfo(rest) then
		ns:Print("|cffff4040" .. rest .. "|r is not a spell you know - not changed")
		return
	end
	FycoPvPDB.rangeSpell = rest
	Resolve()
	ns:Print("range check now uses |cffffff00" .. rest .. "|r")
end

function M:OnLoad()
	frame = Build()
	Resolve()

	-- 10Hz is plenty here: this only has to beat your reaction time
	ns:OnTick(Update)

	-- a respec or a new rank can change what is castable
	ns:On("LEARNED_SPELL_IN_TAB", Resolve)
	ns:On("SPELLS_CHANGED", Resolve)

	ns:Subscribe("ToggleLock", function()
		if frame:IsMouseEnabled() then
			frame:EnableMouse(false)
			frame.preview = nil
			frame:Hide()
		else
			frame:EnableMouse(true)
			frame.preview = true
			frame.text:SetText("|cff40ff40IN RANGE|r |cff808080drag me|r")
			frame.bg:SetTexture(0.05, 0.25, 0.05, 0.55)
			frame:Show()
		end
	end)
end
