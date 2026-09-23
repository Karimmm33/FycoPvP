--[[ FycoPvP - Modules/Procs.lua
     Step 2. Your own procs: Nightfall (Shadow Trance), Backdraft, Molten Core,
     Decimation, Eradication, Backlash. Each gets an icon in a row, plus an
     optional screen-edge flash in the style of Blizzard's spell activation
     overlay (what the Cheese addon backports).
     Reads UnitBuff("player") only, so durations and stacks are real API values.
     Loaded by Core.lua at PLAYER_LOGIN. Consumes ns.Procs from Data.lua.     ]]

local ADDON, ns = ...
local M = ns:Module("procs")

local UnitBuff = UnitBuff
local SIZE, GAP = 48, 6

local anchor, flash
local icons = {}      -- [spellID] = frame
local shown = {}      -- [spellID] = true while visible
local order = {}      -- stable left-to-right order

----------------------------------------------------------------------
-- frames
----------------------------------------------------------------------

local function MakeIcon(spellID)
	local f = CreateFrame("Frame", ADDON .. "Proc" .. spellID, anchor)
	f:SetWidth(SIZE)
	f:SetHeight(SIZE)

	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints(f)
	f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.tex:SetTexture(select(3, GetSpellInfo(spellID)))

	f.glow = f:CreateTexture(nil, "BACKGROUND")
	f.glow:SetPoint("TOPLEFT", f, "TOPLEFT", -4, 4)
	f.glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -4)
	f.glow:SetTexture(1, 0.85, 0.2, 1)

	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints(f)
	f.cd:SetReverse(true)

	f.count = f:CreateFontString(nil, "OVERLAY")
	f.count:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
	f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)

	f:Hide()
	return f
end

-- reused each pass: the icons are keyed by spell ID, and the layout helper
-- wants them contiguous
local laid = {}

local function Layout()
	local n = 0
	for i = 1, #order do
		local id = order[i]
		if shown[id] then
			n = n + 1
			laid[n] = icons[id]
		end
	end
	local w, h = ns:LayoutIcons(anchor, laid, n, GAP)
	anchor:SetWidth(math.max(SIZE, w))
	anchor:SetHeight(math.max(SIZE, h))
end

local function Build()
	anchor = CreateFrame("Frame", ADDON .. "Procs", UIParent)
	anchor:SetWidth(SIZE)
	anchor:SetHeight(SIZE)
	anchor:SetMovable(true)
	anchor:EnableMouse(false)
	anchor:RegisterForDrag("LeftButton")
	anchor:SetScript("OnDragStart", function(self) self:StartMoving() end)
	anchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, _, x, y = self:GetPoint(1)
		FycoPvPDB.procsPos = { p, x, y }
	end)

	local pos = FycoPvPDB.procsPos
	if pos then
		anchor:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
	else
		anchor:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
	end

	-- Screen-edge overlay, Blizzard's spell-activation style: a mirrored pair
	-- hugging the left and right edges. The earlier full-screen LowHealth
	-- texture does not exist on this client, which is why nothing showed.
	flash = CreateFrame("Frame", ADDON .. "ProcFlash", UIParent)
	flash:SetAllPoints(UIParent)
	flash:SetFrameStrata("BACKGROUND")

	local w = UIParent:GetWidth() * 0.32
	flash.left = flash:CreateTexture(nil, "BACKGROUND")
	flash.left:SetPoint("TOPLEFT", flash, "TOPLEFT", 0, 0)
	flash.left:SetPoint("BOTTOMLEFT", flash, "BOTTOMLEFT", 0, 0)
	flash.left:SetWidth(w)
	flash.left:SetBlendMode("ADD")

	flash.right = flash:CreateTexture(nil, "BACKGROUND")
	flash.right:SetPoint("TOPRIGHT", flash, "TOPRIGHT", 0, 0)
	flash.right:SetPoint("BOTTOMRIGHT", flash, "BOTTOMRIGHT", 0, 0)
	flash.right:SetWidth(w)
	flash.right:SetBlendMode("ADD")
	flash.right:SetTexCoord(1, 0, 0, 1)   -- mirrored

	flash.top = flash:CreateTexture(nil, "BACKGROUND")
	flash.top:SetPoint("TOPLEFT", flash, "TOPLEFT", 0, 0)
	flash.top:SetPoint("TOPRIGHT", flash, "TOPRIGHT", 0, 0)
	flash.top:SetHeight(UIParent:GetHeight() * 0.26)
	flash.top:SetBlendMode("ADD")

	flash:SetAlpha(0)
	flash:Hide()

	for spellID in pairs(ns.Procs) do
		table.insert(order, spellID)
	end
	table.sort(order)
	for i = 1, #order do
		icons[order[i]] = MakeIcon(order[i])
	end
end

----------------------------------------------------------------------
-- flash, hand-rolled: 3.3.5a has no C_Timer and no animation API
----------------------------------------------------------------------

local flashAlpha = 0     -- current opacity
local holdID             -- the proc driving the overlay; nil when nothing is
local fadeLeft   = 0     -- seconds of fade-out left once nothing holds it
local phase      = 0     -- pulse phase while held

--- Show this proc's overlay: its own shape, tint and screen position.
--- `transient` gives the old one-shot pulse, used by the preview and the demo;
--- otherwise the overlay is held until the proc actually falls off.
local function Flash(spellID, transient)
	if not FycoPvPDB.procFlash then return end
	local o = (spellID and ns.ProcOverlay[spellID]) or ns.ProcOverlayDefault
	local path = ns.TextureDir .. o.art .. ".blp"
	local c = o.color

	if o.pos == "TOP" then
		flash.top:SetTexture(path)
		flash.top:SetVertexColor(c[1], c[2], c[3])
		flash.top:Show()
		flash.left:Hide()
		flash.right:Hide()
	else
		flash.left:SetTexture(path)
		flash.right:SetTexture(path)
		flash.left:SetVertexColor(c[1], c[2], c[3])
		flash.right:SetVertexColor(c[1], c[2], c[3])
		flash.left:Show()
		flash.right:Show()
		flash.top:Hide()
	end

	if transient then
		holdID   = nil
		fadeLeft = ns.FlashHold + ns.FlashOut
	else
		holdID   = spellID
		fadeLeft = 0
	end
	phase = 0
	flash:Show()
end

--- Switch the overlay to a different proc without restarting the ramp-in,
--- for when the one that was driving it drops while another is still up.
local function FlashSwitch(spellID)
	if holdID == spellID then return end
	local a = flashAlpha
	Flash(spellID)
	flashAlpha = a
	flash:SetAlpha(a)
end

----------------------------------------------------------------------
-- detection
----------------------------------------------------------------------

local function Refresh()
	if not ns:Enabled("procs") then
		for id in pairs(shown) do
			shown[id] = nil
			if icons[id] then icons[id]:Hide() end
		end
		holdID = nil
		if flash then flash:Hide() end
		return
	end
	local live = {}

	for i = 1, 40 do
		local name, _, _, count, _, duration, expires, _, _, _, spellID = UnitBuff("player", i)
		if not name then break end
		if spellID and ns.Procs[spellID] then
			live[spellID] = true
			local f = icons[spellID]
			if f then
				if not shown[spellID] then
					shown[spellID] = true
					f:Show()
					Flash(spellID)
					ns:Sound("proc", 0.4)
				end
				if duration and duration > 0 and expires then
					f.cd:SetCooldown(expires - duration, duration)
				end
				f.count:SetText((count and count > 1) and count or "")
			end
		end
	end

	local changed = false
	for spellID in pairs(shown) do
		if not live[spellID] then
			shown[spellID] = nil
			if icons[spellID] then icons[spellID]:Hide() end
			changed = true
		end
	end
	for spellID in pairs(live) do
		if not shown[spellID] then changed = true end
	end
	if changed then Layout() end

	-- The overlay follows whichever proc is still up. If the one driving it
	-- fell off but another is active, hand it over rather than fading out and
	-- straight back in; if nothing is left, release it and let the tick fade.
	if holdID and not live[holdID] then
		local nextID
		for i = 1, #order do
			if live[order[i]] then nextID = order[i]; break end
		end
		if nextID then
			FlashSwitch(nextID)
		else
			holdID = nil
		end
	end
end

----------------------------------------------------------------------
-- load
----------------------------------------------------------------------

function M:OnLoad()
	if FycoPvPDB.procFlash == nil then FycoPvPDB.procFlash = true end
	Build()

	ns:Subscribe("UnitAura", function(unit)
		if unit == "player" then Refresh() end
	end)

	ns:Subscribe("ToggleLock", function()
		local unlocked = anchor:IsMouseEnabled()
		if unlocked then
			anchor:EnableMouse(false)
			-- unlocking forced every icon visible, so `shown` no longer reflects
			-- reality. Wipe it and let Refresh rebuild from the live auras,
			-- otherwise the preview icons stay up until the next proc.
			for id in pairs(icons) do
				shown[id] = nil
				icons[id]:Hide()
			end
			Refresh()
			Layout()
			ns:Print("proc row locked")
		else
			anchor:EnableMouse(true)
			for i = 1, #order do
				shown[order[i]] = true
				icons[order[i]]:Show()
			end
			Layout()
			Flash(nil, true)   -- one-shot, so unlocking does not pin the overlay on
			ns:Print("proc row unlocked - drag it, then |cffffff00/fyco lock|r again")
		end
	end)

	-- While a proc is held: ramp up, then breathe between FlashPulseMin and
	-- FlashPulseMax so it keeps drawing the eye for as long as the buff lasts.
	-- Once nothing holds it: fade out over FlashOut.
	ns:OnTick(function()
		if holdID then
			phase = phase + 0.1
			local target
			if phase < ns.FlashIn then
				target = ns.FlashPulseMax * (phase / ns.FlashIn)   -- ramp in
			else
				local mid  = (ns.FlashPulseMax + ns.FlashPulseMin) / 2
				local half = (ns.FlashPulseMax - ns.FlashPulseMin) / 2
				target = mid + half * math.sin(phase * (2 * math.pi) / ns.FlashPulsePeriod)
			end
			flashAlpha = target
			flash:SetAlpha(flashAlpha)
			if not flash:IsShown() then flash:Show() end
			return
		end

		if fadeLeft > 0 then
			fadeLeft = fadeLeft - 0.1
			if fadeLeft <= 0 then
				flashAlpha = 0
				flash:SetAlpha(0)
				flash:Hide()
			elseif fadeLeft < ns.FlashOut then
				flash:SetAlpha(ns.FlashPulseMax * (fadeLeft / ns.FlashOut))
			else
				flash:SetAlpha(ns.FlashPulseMax)
			end
		elseif flashAlpha > 0 then
			-- held overlay just ended: start its fade from wherever it was
			fadeLeft   = ns.FlashOut
			flashAlpha = 0
		end
	end)

	-- Walk every proc overlay in turn so the colour, shape and position of each
	-- can be learned without waiting for the proc to actually happen.
	function ns:ProcDemo()
		local i, elapsed = 0, 0
		local f = CreateFrame("Frame")
		ns._procDemoFrame = f
		ns:Print("previewing " .. #order .. " proc overlays, one every 2s")
		f:SetScript("OnUpdate", function(self, e)
			elapsed = elapsed + e
			if elapsed < 2 then return end
			elapsed = 0
			i = i + 1
			if i > #order then
				self:SetScript("OnUpdate", nil)
				ns:Print("proc preview done")
				return
			end
			local id = order[i]
			local o = ns.ProcOverlay[id] or ns.ProcOverlayDefault
			ns:Print(string.format("  %s |cff%02x%02x%02x%s|r  %s",
				ns.Procs[id] or "?", o.color[1] * 255, o.color[2] * 255, o.color[3] * 255,
				o.art, o.pos))
			Flash(id, true)
		end)
	end

	Refresh()
end
