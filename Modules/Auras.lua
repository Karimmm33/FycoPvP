--[[ FycoPvP - Modules/Auras.lua
     Step 4. Target and focus auras, split into two rows that answer two
     different questions at a glance:
       top row    - what THEY have up that changes what you should cast
                    (defensives and immunities, plus any CC they are sitting in)
       bottom row - what YOU have on them, so you know when to refresh
     Reads UnitBuff/UnitDebuff directly rather than the Core cache: we hold a
     real token for target and focus, so durations and textures are exact.
     The Core cache exists for units with no token, which is step 7's problem.

     Deliberate choice: "my DoTs" is decided by unitCaster == "player", not by
     a spell ID table. A missing rank in a table fails silently, which is the
     exact failure that broke the old PlateBuffs setup. The API already knows
     who cast it, so we ask it instead of guessing.
     Loaded by Core.lua at PLAYER_LOGIN.                                      ]]

local ADDON, ns = ...
local M = ns:Module("auras")

local UnitBuff   = UnitBuff
local UnitDebuff = UnitDebuff
local UnitExists = UnitExists

local THEIR_SIZE, GAP = 34, 4
-- The bottom row holds up to MAX_MINE icons. With "show every debuff" off that
-- is more than your own dots will ever fill; with it on the row is shared with
-- everybody else's, so it needs the headroom.
local MAX_THEIRS, MAX_MINE = 8, 16

local COLOR = {
	defensive = { 0.95, 0.20, 0.20 },   -- they are immune or mitigating
	cc        = { 0.95, 0.80, 0.20 },   -- they are controlled, do not break it
	mine      = { 0.25, 0.85, 0.35 },   -- your own dot
}

-- How strongly the coloured border is drawn. Yours at full strength, everyone
-- else's dimmed: the same language Dispel.lua uses to separate the buffs you
-- can actually strip from the ones that are only context.
local BORDER_MINE, BORDER_OTHER = 1, 0.45

local auraDefaults = {
	-- Off by default. The bottom row answering "what have I got on them, and
	-- when does it fall off" is the point of it; turning this on trades that
	-- focus for a fuller picture.
	showAll   = false,
	mineSize  = 26,
	otherSize = 20,
}

--- Named opts(), not cfg(): `cfg` is already this file's name for a UNITS
--- entry, and shadowing it inside MakeGroup would be a quiet disaster.
local function opts()
	FycoPvPDB.auras = FycoPvPDB.auras or {}
	return FycoPvPDB.auras
end

-- Debuffs you cast that are noise rather than information. Add spell IDs here
-- with a value of false to hide them from the bottom row.
local MINE_IGNORE = {}

local UNITS = {
	{ unit = "target", label = "Target", def = { "CENTER", 0, 160 } },
	{ unit = "focus",  label = "Focus",  def = { "CENTER", 0, 290 } },
}

local groups = {}

-- Reused between refreshes: UnitDebuff slot -> already drawn in the top row.
-- A fresh table per refresh would be garbage on every UNIT_AURA event, and
-- Refresh runs one group at a time, so sharing it is safe.
local promoted = {}

----------------------------------------------------------------------
-- icon pool
----------------------------------------------------------------------

--- Icons are pooled, and the bottom row now mixes two sizes in one pass, so
--- size is a per-draw property rather than something fixed at creation. The
--- timer font has to follow it or a shrunk icon keeps oversized text.
--- Guarded on the cached size: this runs for every icon on every refresh.
local function Resize(f, size)
	if f.size == size then return end
	f.size = size
	f:SetWidth(size)
	f:SetHeight(size)
	f.time:SetFont("Fonts\\FRIZQT__.TTF", size > 30 and 13 or (size > 22 and 11 or 10), "OUTLINE")
end

local function MakeIcon(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(size)
	f:SetHeight(size)

	f.border = f:CreateTexture(nil, "BACKGROUND")
	f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
	f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)

	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints(f)
	f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints(f)
	f.cd:SetReverse(true)
	-- we draw our own countdown under the icon; stop OmniCC drawing a second
	-- one over it (its opt-out flag, config.lua:265)
	f.cd.noCooldownCount = true

	f.time = f:CreateFontString(nil, "OVERLAY")
	f.time:SetPoint("BOTTOM", f, "BOTTOM", 0, -11)

	f.count = f:CreateFontString(nil, "OVERLAY")
	f.count:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)

	Resize(f, size)   -- sets the timer font as well, so it is not set twice

	-- Blizzard's own aura tooltip on hover. Apply() keeps tipUnit/tipIndex
	-- pointing at the right aura; a hidden icon has neither, so it says
	-- nothing rather than describing whatever it showed last.
	ns:AuraTooltip(f)
	f:HookScript("OnHide", function(self)
		self.tipUnit, self.tipIndex = nil, nil
	end)

	f:Hide()
	return f
end

local function MakeGroup(cfg)
	local g = { cfg = cfg, theirs = {}, mine = {} }

	g.frame = CreateFrame("Frame", ADDON .. "Auras" .. cfg.unit, UIParent)
	g.frame:SetWidth(MAX_THEIRS * (THEIR_SIZE + GAP))
	g.frame:SetHeight(THEIR_SIZE + opts().mineSize + 24)
	g.frame:SetMovable(true)
	g.frame:EnableMouse(false)
	g.frame:RegisterForDrag("LeftButton")
	g.frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	g.frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, _, x, y = self:GetPoint(1)
		FycoPvPDB.auraPos = FycoPvPDB.auraPos or {}
		FycoPvPDB.auraPos[cfg.unit] = { p, x, y }
	end)

	local saved = FycoPvPDB.auraPos and FycoPvPDB.auraPos[cfg.unit]
	local p = saved or cfg.def
	g.frame:SetPoint(p[1], UIParent, p[1], p[2], p[3])

	g.theirRow = CreateFrame("Frame", nil, g.frame)
	g.theirRow:SetPoint("TOP", g.frame, "TOP", 0, 0)
	g.theirRow:SetWidth(1)
	g.theirRow:SetHeight(THEIR_SIZE)

	g.mineRow = CreateFrame("Frame", nil, g.frame)
	g.mineRow:SetPoint("TOP", g.theirRow, "BOTTOM", 0, -14)
	g.mineRow:SetWidth(1)
	g.mineRow:SetHeight(opts().mineSize)

	for i = 1, MAX_THEIRS do g.theirs[i] = MakeIcon(g.theirRow, THEIR_SIZE) end
	for i = 1, MAX_MINE  do g.mine[i]   = MakeIcon(g.mineRow,  opts().mineSize) end

	return g
end

--- Lay out n icons, wrapping after ns:PerRow() of them. The row frame is
--- resized to what was actually used, which is what lets the row below it
--- move down when this one wraps onto a second line.
local function LayoutRow(row, icons, n, size)
	local w, h = ns:LayoutIcons(row, icons, n, GAP)
	row:SetWidth(math.max(1, w))
	row:SetHeight(math.max(size, h))
	return h
end

----------------------------------------------------------------------
-- scanning
----------------------------------------------------------------------

--- `unit`, `index` and `harmful` are optional and used only for the hover
--- tooltip: index is the real UnitBuff/UnitDebuff slot, so the game can be
--- asked about this exact aura rather than about whatever sits in this icon.
--- The preview in ToggleLock omits them, which correctly leaves it silent.
---
--- `size` and `strength` are how one pooled row draws two classes of aura:
--- yours large with a solid border, everybody else's small and dimmed.
local function Apply(icon, tex, count, duration, expires, color, unit, index, harmful,
                     size, strength)
	Resize(icon, size or icon.size or THEIR_SIZE)
	icon.tex:SetTexture(tex)
	icon.border:SetTexture(color[1], color[2], color[3], strength or BORDER_MINE)
	icon.count:SetText((count and count > 1) and count or "")
	if duration and duration > 0 and expires then
		icon.cd:SetCooldown(expires - duration, duration)
		icon.expires = expires
	else
		icon.cd:SetCooldown(0, 0)
		icon.expires = nil
		icon.time:SetText("")
	end

	icon.tipUnit, icon.tipIndex, icon.tipHarmful = unit, index, harmful
	if unit then ns:AuraTooltipRefresh(icon) end

	icon:Show()
end

local function Refresh(g)
	local unit = g.cfg.unit
	if not ns:Enabled("auras") or not UnitExists(unit) then
		for i = 1, MAX_THEIRS do g.theirs[i]:Hide() end
		for i = 1, MAX_MINE  do g.mine[i]:Hide() end
		return
	end

	local o = opts()

	-- top row: their defensives
	local t = 0
	for i = 1, 40 do
		local name, _, tex, count, _, duration, expires, _, _, _, spellID = UnitBuff(unit, i)
		if not name then break end
		if spellID and ns.Defensives[spellID] and t < MAX_THEIRS then
			t = t + 1
			Apply(g.theirs[t], tex, count, duration, expires, COLOR.defensive,
			      unit, i, false, THEIR_SIZE, BORDER_MINE)
		end
	end

	-- CC on them is promoted to the TOP row, so you do not break it by
	-- accident. Which UnitDebuff slots went up there is remembered, because
	-- with "show every debuff" on the bottom row must not list them twice.
	for i = 1, 40 do promoted[i] = nil end
	for i = 1, 40 do
		local name, _, tex, count, dtype, duration, expires, _, _, _, spellID = UnitDebuff(unit, i)
		if not name then break end
		if spellID and ns.CC[spellID] and t < MAX_THEIRS then
			t = t + 1
			promoted[i] = true
			local dc = ns.DebuffColor[dtype or "none"] or ns.DebuffColor.none
			Apply(g.theirs[t], tex, count, duration, expires, dc, unit, i, true,
			      THEIR_SIZE, BORDER_MINE)
		end
	end

	-- Bottom row: what YOU have on them, decided by caster and not by an ID
	-- table -- a missing rank in a table fails silently, and the API already
	-- knows who cast it.
	--
	-- With showAll on the row becomes every debuff instead: yours first, at
	-- full size with a solid border, then everyone else's, smaller and dimmed.
	-- Two passes over UnitDebuff rather than a sort. The API's own order is
	-- stable, so walking it twice puts yours in front while leaving the order
	-- inside each group alone -- an icon does not hop about as dots are recast.
	local m = 0
	local passes = o.showAll and 2 or 1
	for pass = 1, passes do
		for i = 1, 40 do
			local name, _, tex, count, dtype, duration, expires, caster, _, _, spellID = UnitDebuff(unit, i)
			if not name then break end

			local isMine = (caster == "player")
			local want
			if pass == 1 then want = isMine else want = not isMine end

			if want and not promoted[i] and not MINE_IGNORE[spellID] and m < MAX_MINE then
				m = m + 1
				local dc = ns.DebuffColor[dtype or "none"] or ns.DebuffColor.none
				Apply(g.mine[m], tex, count, duration, expires, dc, unit, i, true,
				      isMine and o.mineSize or o.otherSize,
				      isMine and BORDER_MINE or BORDER_OTHER)
			end
		end
	end

	for i = t + 1, MAX_THEIRS do g.theirs[i]:Hide() end
	for i = m + 1, MAX_MINE  do g.mine[i]:Hide() end
	LayoutRow(g.theirRow, g.theirs, t, THEIR_SIZE)
	LayoutRow(g.mineRow,  g.mine,   m, o.mineSize)
end

----------------------------------------------------------------------
-- load
----------------------------------------------------------------------

function M:OnLoad()
	local o = opts()
	for k, v in pairs(auraDefaults) do
		if o[k] == nil then o[k] = v end
	end

	for i = 1, #UNITS do
		groups[i] = MakeGroup(UNITS[i])
	end

	local function RefreshAll()
		for i = 1, #groups do Refresh(groups[i]) end
	end

	ns:Subscribe("UnitAura", function(unit)
		for i = 1, #groups do
			if groups[i].cfg.unit == unit then Refresh(groups[i]) end
		end
	end)
	ns:On("PLAYER_TARGET_CHANGED", RefreshAll)
	ns:On("PLAYER_FOCUS_CHANGED",  RefreshAll)

	-- countdown text, red as a dot runs out
	ns:OnTick(function(now)
		for gi = 1, #groups do
			local g = groups[gi]
			for r = 1, 2 do
				local row = (r == 1) and g.theirs or g.mine
				for i = 1, #row do
					local icon = row[i]
					if icon:IsShown() and icon.expires then
						local left = icon.expires - now
						if left <= 0 then
							icon.time:SetText("")
						else
							icon.time:SetText(left < 10 and string.format("%.1f", left)
							                             or string.format("%d", left))
							if left < 3 then
								icon.time:SetTextColor(1, 0.2, 0.2)
							else
								icon.time:SetTextColor(1, 1, 1)
							end
						end
					end
				end
			end
		end
	end)

	ns:Subscribe("ToggleLock", function()
		for gi = 1, #groups do
			local g = groups[gi]
			-- An icon that accepts the mouse swallows the drag, so the icons
			-- give it up while unlocked and take it back afterwards.
			local function iconMouse(on)
				for i = 1, MAX_THEIRS do g.theirs[i]:EnableMouse(on) end
				for i = 1, MAX_MINE  do g.mine[i]:EnableMouse(on) end
			end

			if g.frame:IsMouseEnabled() then
				g.frame:EnableMouse(false)
				iconMouse(true)
				Refresh(g)
			else
				g.frame:EnableMouse(true)
				iconMouse(false)
				-- Preview: three of theirs, then yours and -- when the option
				-- is on -- a couple of somebody else's, so the size and border
				-- difference can be judged while the frame is being placed.
				local o = opts()
				for i = 1, 3 do
					Apply(g.theirs[i], "Interface\\Icons\\Spell_Holy_DivineIntervention",
					      0, 0, nil, (i == 3) and COLOR.cc or COLOR.defensive,
					      nil, nil, nil, THEIR_SIZE, BORDER_MINE)
				end
				for i = 4, MAX_THEIRS do g.theirs[i]:Hide() end

				local shown = o.showAll and 6 or 4
				for i = 1, shown do
					local isMine = (i <= 4)
					Apply(g.mine[i], isMine
						and "Interface\\Icons\\Spell_Shadow_UnstableAffliction_3"
						 or "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
					      0, 0, nil, isMine and COLOR.mine or ns.DebuffColor.none,
					      nil, nil, nil,
					      isMine and o.mineSize or o.otherSize,
					      isMine and BORDER_MINE or BORDER_OTHER)
				end
				for i = shown + 1, MAX_MINE do g.mine[i]:Hide() end
				LayoutRow(g.theirRow, g.theirs, 3, THEIR_SIZE)
				LayoutRow(g.mineRow,  g.mine,   shown, o.mineSize)
			end
		end
	end)

	RefreshAll()

	-- the options panel writes the same keys; refresh so a tick takes effect
	-- without waiting for the target's auras to change
	ns:Subscribe("DebuffOptions", RefreshAll)
end

----------------------------------------------------------------------
-- config
----------------------------------------------------------------------

--- /fyco debuffs [all | plates | mine <n> | other <n>]
--- Every one of these matches a tick box or slider on the Debuffs panel.
function ns:DebuffConfig(rest)
	local o = opts()
	rest = (rest or ""):lower()

	local word = rest:match("^(%a+)$")
	if word == "all" then
		o.showAll = not o.showAll
		ns:Print("target and focus bar: " .. (o.showAll
			and "|cff00ff00every debuff|r - yours first, larger and solid"
			 or "|cffffff00only your own debuffs|r"))
		ns:Fire("DebuffOptions")
		return
	elseif word == "plates" then
		local p = FycoPvPDB.plates
		if not p then ns:Print("plates module is off") return end
		p.showAllDebuffs = not p.showAllDebuffs
		ns:Print("nameplates: " .. (p.showAllDebuffs
			and "|cff00ff00every debuff|r - yours first and full size"
			 or "|cffffff00only your own debuffs and their defensives|r"))
		return
	end

	local key, val = rest:match("^(%a+)%s+(%d+)$")
	if key == "mine" or key == "other" then
		local n = tonumber(val)
		if n and n >= 10 and n <= 48 then
			o[key == "mine" and "mineSize" or "otherSize"] = n
			ns:Print(string.format("%s debuff icons: |cffffff00%d|r px", key, n))
			ns:Fire("DebuffOptions")
			return
		end
		ns:Print("size must be between 10 and 48")
		return
	end

	local p = FycoPvPDB.plates
	ns:Print("debuff tracker:")
	ns:Print(string.format("  bar shows every debuff : %s", tostring(o.showAll)))
	ns:Print(string.format("  plates show every debuff: %s",
		p and tostring(p.showAllDebuffs) or "plates module is off"))
	ns:Print(string.format("  your icons %d px, everyone else's %d px",
		o.mineSize, o.otherSize))
	ns:Print("usage: |cffffff00/fyco debuffs all|r, |cffffff00plates|r, "
	      .. "|cffffff00mine <10-48>|r, |cffffff00other <10-48>|r")
end
