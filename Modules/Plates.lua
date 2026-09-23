--[[ FycoPvP - Modules/Plates.lua
     Step 7, and the risky one. 3.3.5a has no nameplate unit tokens and no
     NAME_PLATE_UNIT_ADDED: plates are anonymous WorldFrame children that must
     be found by polling, identified by their structure, and matched to units
     by name. Everything here follows from that.

     Region order is fixed and verified twice over -- LibNameplates-1.0.lua:47
     and TidyPlatesCore.lua:818 agree:
       1 threatglow  2 healthborder  3 castborder  4 castnostop  5 spellicon
       6 highlight   7 name          8 level       9 dangerskull 10 raidicon
       11 eliteicon
     and plate:GetChildren() yields health, cast.

     This AUGMENTS the Blizzard plate rather than rebuilding it: the border art
     is blanked, the bar restyled, and scale/alpha set per unit type. Rebuilding
     plates wholesale is what TidyPlates does, and it is a lot of code with
     nothing PvP-specific to show for it.

     Pet vs player is the requirement that shaped this. Healthbar colour alone
     cannot separate an enemy player from a hunter pet unless class colours are
     on, so type is resolved three ways, strongest first:
       1. GUID from target/mouseover -> ns.units[guid].utype (combat log flags)
       2. name seen in the combat log -> that type, cached by name
       3. healthbar colour            -> the classic heuristic
     Loaded by Core.lua at PLAYER_LOGIN.                                      ]]

local ADDON, ns = ...
local M = ns:Module("plates")

local WorldFrame = WorldFrame
local UnitGUID   = UnitGUID
local UnitName   = UnitName
local UnitExists = UnitExists
local GetTime    = GetTime

-- AURA_SMALL is for debuffs somebody else applied, which appear only when
-- showAllDebuffs is on. Yours and their defensives stay at AURA_SIZE, so the
-- icons you are actually tracking still read first at a glance.
local AURA_SIZE, AURA_SMALL, AURA_GAP, MAX_AURAS = 22, 16, 2, 8

local plates    = {}   -- [frame] = our per-plate data
local byName    = {}   -- [name]  = utype, learned from the combat log
local ambiguous = {}   -- [name]  = true once two GUIDs have shared that name
local strong    = {}   -- [name]  = guid learned from a real unit token
local known     = 0    -- last WorldFrame child count

local defaults = {
	petScale     = 0.65,
	petAlpha     = 0.55,
	npcScale     = 0.80,
	npcAlpha     = 0.70,
	playerScale  = 1.00,
	showPetAuras = false,
	-- Off by default. On, the aura row stops being "your dots and their
	-- defensives" and becomes every debuff on the unit -- see UpdateAuras for
	-- what that costs in timer accuracy away from your own target.
	showAllDebuffs = false,
	-- visibility. These are real CVars on this client, confirmed against
	-- TidyPlatesPanel.lua:216-217, so hiding allies is engine-level rather
	-- than us fighting the plate every frame.
	hideFriendly  = true,
	showEnemies   = true,
	-- appearance
	classColor    = true,
	showClassIcon = true,
	showLevel     = false,
	showHealthPct = true,
	showHealthValue = true,
	nameColor     = "white",   -- "white" or "match" (follows the bar colour)
	nameSize      = 10,
	colorEnemy    = { 0.85, 0.20, 0.20 },  -- enemy player of unknown class
	colorFriendly = { 0.20, 0.65, 0.90 },  -- allies, when you choose to show them
	colorNpc      = { 0.75, 0.55, 0.20 },
	colorPet      = { 0.55, 0.35, 0.70 },
}

----------------------------------------------------------------------
-- identification
----------------------------------------------------------------------

--- A nameplate is an unnamed Frame whose 7th region is the name FontString.
local function IsPlate(frame)
	if frame:GetName() then return false end
	if frame:GetObjectType() ~= "Frame" then return false end
	if frame:GetNumRegions() < 11 then return false end
	if frame:GetNumChildren() < 2 then return false end
	local name = select(7, frame:GetRegions())
	return name and name.GetObjectType and name:GetObjectType() == "FontString"
end

--- 23,400 -> "23.4k". Plates are narrow, so remaining health is abbreviated
--- rather than printed in full.
local function Short(v)
	if v >= 1000000 then return string.format("%.1fm", v / 1000000) end
	if v >= 1000    then return string.format("%.1fk", v / 1000) end
	return string.format("%d", v)
end

local function ReactionByColor(r, g, b)
	if r < 0.01 and b < 0.01 and g > 0.99 then return "FRIENDLY", "npc"    end
	if r < 0.01 and b > 0.99 and g < 0.01 then return "FRIENDLY", "player" end
	if r > 0.99 and b < 0.01 and g > 0.99 then return "NEUTRAL",  "npc"    end
	if r > 0.99 and b < 0.01 and g < 0.01 then return "HOSTILE",  "npc"    end
	return "HOSTILE", "player"
end

----------------------------------------------------------------------
-- per-plate setup
----------------------------------------------------------------------

local function Hook(frame)
	local d = {}
	plates[frame] = d

	d.health, d.cast = frame:GetChildren()
	d.threat, d.healthBorder, d.castBorder, d.castShield, d.spellIcon,
		d.highlight, d.name, d.level, d.skull, d.raid, d.elite = frame:GetRegions()

	-- blank the Blizzard chrome, the same way TidyPlatesCore.lua:822 does
	if d.threat then d.threat:SetTexCoord(0, 0, 0, 0) end
	if d.healthBorder then d.healthBorder:SetTexCoord(0, 0, 0, 0) end
	if d.level then d.level:Hide() end
	if d.skull then d.skull:SetAlpha(0) end
	if d.health then
		d.health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

		d.origR, d.origG, d.origB = d.health:GetStatusBarColor()
	end
	-- class icon, left of the bar. Uses the stock class-circles atlas, so no
	-- extra art ships with the addon.
	d.classIcon = frame:CreateTexture(nil, "OVERLAY")
	d.classIcon:SetWidth(16)
	d.classIcon:SetHeight(16)
	d.classIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
	if d.health then
		d.classIcon:SetPoint("RIGHT", d.health, "LEFT", -3, 0)
	end
	d.classIcon:Hide()

	-- remaining health, centred INSIDE the bar
	d.hp = frame:CreateFontString(nil, "OVERLAY")
	d.hp:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
	if d.health then
		d.hp:SetPoint("CENTER", d.health, "CENTER", 0, 0)
	end
	d.hp:Hide()

	-- Inferred spec, under the bar. Its own line rather than squeezed beside
	-- the name: the space right of the bar already holds level and health,
	-- and the space left of it holds the class icon.
	d.spec = frame:CreateFontString(nil, "OVERLAY")
	d.spec:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
	if d.health then
		d.spec:SetPoint("TOP", d.health, "BOTTOM", 0, -1)
	end
	d.spec:Hide()

	-- health percentage, right of the bar
	d.pct = frame:CreateFontString(nil, "OVERLAY")
	d.pct:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
	if d.health then
		d.pct:SetPoint("LEFT", d.health, "RIGHT", 3, 0)
	end
	d.pct:Hide()

	-- Remember the bar's real size: pets are shrunk by resizing this, never by
	-- scaling the plate frame (see UpdatePlate for why).
	if d.health then
		d.baseW = d.health:GetWidth()
		d.baseH = d.health:GetHeight()
	end

	-- Anchor the overlay to the HEALTH BAR, not to the plate frame. The plate
	-- frame is far taller than the visible bar -- it reserves room for the name,
	-- level and cast bar -- so anchoring to its TOP puts icons way above the
	-- unit, at a distance that changes with camera angle.
	d.overlay = CreateFrame("Frame", nil, frame)
	d.overlay:SetWidth(1)
	d.overlay:SetHeight(AURA_SIZE)
	d.overlay:SetPoint("BOTTOM", d.health or frame, "TOP", 0, 8)

	-- Plates are recycled between units, so cached styling must be dropped
	-- whenever one is handed to somebody new.
	frame:HookScript("OnShow", function()
		d.scale, d.alpha = nil, nil
		-- a recycled plate belongs to somebody new, so forget the cached
		-- colours: the next tick must read the engine's fresh one as truth
		d.lastR, d.lastG, d.lastB = nil, nil, nil
		d.origR, d.origG, d.origB = nil, nil, nil
	end)

	-- No position here: the row can mix two icon sizes, so each pass places
	-- them itself. They are anchored BOTTOMLEFT rather than LEFT so a small
	-- icon shares a baseline with a large one instead of floating in the
	-- middle of it.
	d.auras = {}
	for i = 1, MAX_AURAS do
		local a = CreateFrame("Frame", nil, d.overlay)
		a:SetWidth(AURA_SIZE)
		a:SetHeight(AURA_SIZE)
		a.border = a:CreateTexture(nil, "BACKGROUND")
		a.border:SetPoint("TOPLEFT", a, "TOPLEFT", -2, 2)
		a.border:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 2, -2)
		a.tex = a:CreateTexture(nil, "ARTWORK")
		a.tex:SetAllPoints(a)
		a.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		a.time = a:CreateFontString(nil, "OVERLAY")
		a.time:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
		a.time:SetPoint("BOTTOM", a, "BOTTOM", 0, -9)
		a:Hide()
		d.auras[i] = a
	end

	return d
end

local function Scan()
	local n = WorldFrame:GetNumChildren()
	if n == known then return end
	known = n
	local kids = { WorldFrame:GetChildren() }
	for i = 1, #kids do
		local f = kids[i]
		if not plates[f] and IsPlate(f) then Hook(f) end
	end
end

----------------------------------------------------------------------
-- styling and auras
----------------------------------------------------------------------

-- ns.auras is keyed by spell ID, which lands in Lua's hash part, so pairs()
-- order is unspecified AND changes whenever the table is rehashed -- that is,
-- every time an aura is added or removed. Truncating that order at MAX_AURAS
-- meant an arbitrary subset of your dots drew, and which ones changed as you
-- recast. Collect, order deliberately, then draw.
local buf, bufN = {}, 0

local function bufPush(id, a, prio, left)
	bufN = bufN + 1
	local e = buf[bufN]
	if not e then e = {} ; buf[bufN] = e end
	e.id, e.a, e.prio, e.left = id, a, prio, left
end

--- Insertion sort: bufN is tiny (<= ~15), and this avoids table.sort needing a
--- clean array, so the pooled entries can be reused every frame.
local function bufSort()
	for i = 2, bufN do
		local e, j = buf[i], i - 1
		while j >= 1 do
			local o = buf[j]
			local after = (o.prio > e.prio)
				or (o.prio == e.prio and o.left > e.left)
				or (o.prio == e.prio and o.left == e.left and o.id > e.id)
			if not after then break end
			buf[j + 1] = o
			j = j - 1
		end
		buf[j + 1] = e
	end
end

--- HONESTY, and it matters here. The cache behind this row is fed by the
--- combat log, which gives spell IDs but never durations. For YOUR OWN target
--- and focus, Core rescans with a real unit token and the timers are exact;
--- for every other plate a foreign debuff arrives with no duration at all, so
--- it draws an icon with no countdown under it. That is the truth -- a made-up
--- number would be worse -- but it is why showAllDebuffs is off by default.
local function UpdateAuras(d, guid, utype)
	local cfg = FycoPvPDB.plates
	local show = guid and (utype ~= "pet" or cfg.showPetAuras)
	local n, x, tallest = 0, 0, 0

	if show and ns.auras[guid] then
		local now = GetTime()
		bufN = 0
		for spellID, a in pairs(ns.auras[guid]) do
			local def  = ns.Defensives[spellID]
			-- `harmful` is set by Core when the aura landed as a DEBUFF, so a
			-- buff never leaks into the row through this branch
			local keep = def or a.mine or (cfg.showAllDebuffs and a.harmful)
			if keep and (not a.expires or a.expires == 0 or a.expires > now) then
				-- Their defensives first, then YOUR dots, then everyone
				-- else's, and inside each group whatever expires soonest --
				-- so the dot you most need to refresh is never the one that
				-- gets cut by the MAX_AURAS limit.
				bufPush(spellID, a,
					def and 0 or (a.mine and 1 or 2),
					(a.expires and a.expires > 0) and (a.expires - now) or 1e9)
			end
		end
		bufSort()

		for b = 1, bufN do
			if n >= MAX_AURAS then break end
			local spellID, a = buf[b].id, buf[b].a
			n = n + 1
			local icon = d.auras[n]

			-- Somebody else's debuff is context, not something you are
			-- tracking: drawn small, dimmed, and after yours.
			local foreign = not a.mine and not ns.Defensives[spellID]
			local size = foreign and AURA_SMALL or AURA_SIZE
			icon:SetWidth(size)
			icon:SetHeight(size)
			icon:ClearAllPoints()
			icon:SetPoint("BOTTOMLEFT", d.overlay, "BOTTOMLEFT", x, 0)
			x = x + size + AURA_GAP
			if size > tallest then tallest = size end

			icon.tex:SetTexture(select(3, GetSpellInfo(spellID)))
			icon.tex:SetAlpha(foreign and 0.75 or 1)
			if ns.Defensives[spellID] then
				icon.border:SetTexture(0.95, 0.20, 0.20, 1)
			else
				-- debuffs take their dispel-type colour
				local dc = ns.DebuffColor[a.dtype or "none"] or ns.DebuffColor.none
				icon.border:SetTexture(dc[1], dc[2], dc[3], foreign and 0.45 or 1)
			end
			icon.expires = a.expires
			icon:Show()
		end
	end
	for i = n + 1, MAX_AURAS do d.auras[i]:Hide() end
	-- Sized from what was actually placed, not from n * AURA_SIZE: the row can
	-- hold both sizes at once, and the overlay is centred on the health bar, so
	-- a width that lies moves every icon off centre.
	d.overlay:SetWidth(math.max(1, x - AURA_GAP))
	d.overlay:SetHeight(math.max(AURA_SIZE, tallest))
	d.shownAuras = n
end

--- Is this the plate of the unit we currently have targeted? When a target
--- exists the default UI fades every other plate, so the unfaded one is it.
local function IsTargetPlate(frame)
	return UnitExists("target") and frame:GetAlpha() > 0.9
end

local function UpdatePlate(frame, d)
	if not frame:IsShown() or not d.health then return end

	local plateName = d.name and d.name:GetText()
	local cfg = FycoPvPDB.plates

	-- Recovering the engine's own bar colour, which is what reaction is read
	-- from. We also WRITE that colour, so a naive read gets our own output back.
	-- A hook on SetStatusBarColor does not help: nameplate colours are set by
	-- the C engine, which never goes through the Lua method, so the hook never
	-- fires. What does work is comparing against the last colour WE wrote --
	-- anything else came from the engine and is the truth.
	local curR, curG, curB = d.health:GetStatusBarColor()
	local mine = d.lastR
		and math.abs(curR - d.lastR) < 0.02
		and math.abs(curG - d.lastG) < 0.02
		and math.abs(curB - d.lastB) < 0.02
	if not mine then
		d.origR, d.origG, d.origB = curR, curG, curB
	end

	local reaction, byColor = ReactionByColor(d.origR or 1, d.origG or 0, d.origB or 0)
	local utype = (plateName and byName[plateName]) or byColor

	local function Blank()
		if d.alpha ~= 0 then
			d.alpha = 0
			d.health:SetAlpha(0)
			if d.name then d.name:SetAlpha(0) end
		end
		d.classIcon:Hide()
		d.spec:Hide()
		d.pct:Hide()
		d.hp:Hide()
		if d.level then d.level:Hide() end
		UpdateAuras(d, nil, utype)
	end

	-- Friendly plates: the CVar normally stops them existing at all, but a
	-- plate already on screen when the setting changes still needs dealing
	-- with, and friendly pets can slip through.
	if cfg.hideFriendly and reaction == "FRIENDLY" then
		Blank()
		return
	end

	local scale, alpha
	if utype == "pet" then
		scale, alpha = cfg.petScale, cfg.petAlpha
	elseif utype == "npc" then
		scale, alpha = cfg.npcScale, cfg.npcAlpha
	else
		scale, alpha = cfg.playerScale, 1
	end

	-- NEVER frame:SetScale() a nameplate on 3.3.5a. The engine writes the
	-- plate's screen position every frame in unscaled coordinates, so a scaled
	-- frame lands at position/scale instead -- the plate drifts off to the side
	-- or top and moves as the camera turns. Resize the bar instead.
	if d.scale ~= scale and d.baseW then
		d.scale = scale
		d.health:SetWidth(d.baseW * scale)
		d.health:SetHeight(d.baseH * scale)
	end
	if d.alpha ~= alpha then
		d.alpha = alpha
		d.health:SetAlpha(alpha)
		if d.name then d.name:SetAlpha(alpha) end
	end

	-- Name collisions are real and common: every training dummy here is called
	-- "Expert's Training Dummy", and one name cannot map to one GUID. When a
	-- name is ambiguous, only the plate we can positively identify -- the
	-- current target -- gets an aura row. Everything else shows nothing rather
	-- than somebody else's dots.
	local guid
	if plateName then
		if IsTargetPlate(frame) and plateName == UnitName("target") then
			guid = UnitGUID("target")
		elseif not ambiguous[plateName] then
			guid = ns.nameGUID[plateName]
		end
	end
	local unit = guid and ns.units[guid]

	-- Bar colour. Class colour needs the class, and the combat log never
	-- reports it -- it only arrives from a real unit token, so it is known for
	-- anyone you have targeted or moused over and nobody else. Until then an
	-- enemy player falls back to colorEnemy.
	-- Colour by REACTION first, which is the one thing the bar colour tells us
	-- reliably. Hostile is an enemy whether it is a player or a mob; friendly is
	-- an ally either way. Class colour and the pet tint are refinements applied
	-- only when we actually know who this is.
	-- Decide in order of confidence. A green or yellow bar cannot belong to a
	-- player at all, so those are certainly NPCs. A RED bar is ambiguous -- a
	-- mob, or an enemy player whose class colours the client never applied --
	-- so it only counts as an NPC once the combat log has flagged that name,
	-- and otherwise falls through and is treated as an enemy player.
	local isPet = (plateName and byName[plateName] == "pet") or utype == "pet"
	local isNpc = (plateName and byName[plateName] == "npc")
	              or (byColor == "npc" and reaction ~= "HOSTILE")

	local col
	if isPet then
		col = cfg.colorPet
	elseif isNpc then
		col = cfg.colorNpc
	elseif cfg.classColor and reaction == "HOSTILE" and unit and unit.class
	       and RAID_CLASS_COLORS and RAID_CLASS_COLORS[unit.class] then
		local c = RAID_CLASS_COLORS[unit.class]
		col = { c.r, c.g, c.b }
	elseif reaction == "FRIENDLY" then
		col = cfg.colorFriendly
	else
		col = cfg.colorEnemy
	end

	d.health:SetStatusBarColor(col[1], col[2], col[3])
	-- remember it so the next tick can tell our colour from the engine's
	d.lastR, d.lastG, d.lastB = col[1], col[2], col[3]

	-- Blizzard tints the name red for hostile/attacking units, which is why an
	-- ally's name sometimes turned red. Set it ourselves every pass instead of
	-- inheriting whatever the engine left there.
	if d.name then
		if cfg.nameColor == "match" then
			d.name:SetTextColor(col[1], col[2], col[3])
		else
			d.name:SetTextColor(1, 1, 1)
		end
	end

	-- Players only. UnitClass() returns a real class for mobs and pets as well
	-- -- most creatures carry one in the game's database -- so without this
	-- gate every wolf and quest giver got a class icon.
	if cfg.showClassIcon and not isPet and not isNpc and reaction ~= "NEUTRAL"
	   and unit and unit.class
	   and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[unit.class] then
		d.classIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[unit.class]))
		d.classIcon:SetAlpha(alpha)
		d.classIcon:Show()
	else
		d.classIcon:Hide()
	end

	-- Inferred spec, healers called out in green. Players only, and only once
	-- a signature spell has actually been seen -- an empty line is the honest
	-- answer for someone who has not cast anything yet.
	local rec = (not isPet and not isNpc)
		and ((guid and ns.GetSpec and ns:GetSpec(guid))
		     or (plateName and ns.GetSpecByName and ns:GetSpecByName(plateName)))
	if cfg.showSpec ~= false and rec and rec.spec then
		local rc = ns.RoleColor[rec.role] or { 1, 1, 1 }
		d.spec:SetText(rec.role == "healer" and ("+ " .. rec.spec) or rec.spec)
		d.spec:SetTextColor(rc[1], rc[2], rc[3])
		d.spec:SetAlpha(alpha)
		d.spec:Show()
	else
		d.spec:Hide()
	end

	-- Out of range, on your target only. ns.RangeOut is nil when the question
	-- could not be answered, and nil must not read as "out".
	if d.name and cfg.rangeFade ~= false and ns.RangeOut == true
	   and IsTargetPlate(frame) and plateName == UnitName("target") then
		d.name:SetTextColor(0.55, 0.40, 0.40)
	end

	-- Level and health percentage both want the space to the right of the bar
	-- -- Blizzard's level fontstring is anchored there by default, which is
	-- what made them sit on top of each other. Stack them instead: level above
	-- the bar's centre line, percentage below. When only one is on, it takes
	-- the middle so nothing looks off-centre.
	local wantLevel = (cfg.showLevel and d.level) and true or false
	local wantPct   = cfg.showHealthPct and true or false
	local stack     = tostring(wantLevel) .. tostring(wantPct)

	if d.stack ~= stack then
		d.stack = stack
		if d.level then d.level:ClearAllPoints() end
		d.pct:ClearAllPoints()
		if wantLevel and wantPct then
			d.level:SetPoint("BOTTOMLEFT", d.health, "RIGHT", 4, 0)
			d.pct:SetPoint("TOPLEFT", d.health, "RIGHT", 4, 0)
		elseif wantLevel then
			d.level:SetPoint("LEFT", d.health, "RIGHT", 4, 0)
		else
			d.pct:SetPoint("LEFT", d.health, "RIGHT", 4, 0)
		end
	end

	if d.level then
		if wantLevel then
			d.level:SetAlpha(alpha)
			d.level:Show()
		else
			d.level:Hide()
		end
	end

	-- percentage is computed from the bar itself, since there is no unit token
	if wantPct then
		local _, maxv = d.health:GetMinMaxValues()
		local v = d.health:GetValue()
		if maxv and maxv > 0 and v then
			d.pct:SetText(string.format("%d%%", math.floor(v / maxv * 100 + 0.5)))
			d.pct:SetAlpha(alpha)
			d.pct:Show()
		else
			d.pct:Hide()
		end
	else
		d.pct:Hide()
	end

	-- remaining health inside the bar. Nameplate bars carry real values on this
	-- client; if a bar ever reports a 0-100 range it is normalised and the
	-- number would be meaningless, so it is skipped.
	if cfg.showHealthValue then
		local _, maxv = d.health:GetMinMaxValues()
		local v = d.health:GetValue()
		if maxv and maxv > 100 and v then
			d.hp:SetText(Short(v))
			d.hp:SetAlpha(alpha)
			d.hp:Show()
		else
			d.hp:Hide()
		end
	else
		d.hp:Hide()
	end

	if d.name and d.nameSize ~= cfg.nameSize then
		d.nameSize = cfg.nameSize
		d.name:SetFont("Fonts\\FRIZQT__.TTF", cfg.nameSize, "OUTLINE")
	end

	UpdateAuras(d, guid, utype)
end

----------------------------------------------------------------------
-- load
----------------------------------------------------------------------

function M:OnLoad()
	FycoPvPDB.plates = FycoPvPDB.plates or {}
	for k, v in pairs(defaults) do
		if FycoPvPDB.plates[k] == nil then FycoPvPDB.plates[k] = v end
	end

	-- class colours separate enemy players from red NPCs, which is the whole
	-- pet-vs-player problem. Harmless if this client ignores the CVar.
	pcall(SetCVar, "ShowClassColorInNameplate", 1)
	ns:ApplyPlateCVars()

	-- Blizzard's Interface -> Game -> Names panel owns these same two CVars, and
	-- commits its own checkbox states when the window closes -- which silently
	-- undid ours. Re-assert once the frame is gone.
	if InterfaceOptionsFrame then
		InterfaceOptionsFrame:HookScript("OnHide", function()
			if ns.ApplyPlateCVars then ns:ApplyPlateCVars() end
		end)
	end

	ns.nameGUID = ns.nameGUID or {}

	-- Core drops every cached unit when a match starts, so the name maps here
	-- have to go with it. A name left pointing at last game's GUID resolves to
	-- a unit that no longer exists, which is how a plate ends up showing no
	-- auras at all -- the exact failure the strong/ambiguous split was added
	-- to cure. Clearing them together keeps the two sides consistent.
	ns:Subscribe("MatchStart", function()
		for k in pairs(byName)      do byName[k] = nil end
		for k in pairs(ambiguous)   do ambiguous[k] = nil end
		for k in pairs(strong)      do strong[k] = nil end
		for k in pairs(ns.nameGUID) do ns.nameGUID[k] = nil end
	end)

	local function Bind(unit)
		if not UnitExists(unit) then return end
		local n, g = UnitName(unit), UnitGUID(unit)
		if n and g then
			-- a real token: trust this over anything the combat log said, and
			-- clear any ambiguity flag the log may have raised by mistake
			strong[n]       = g
			ns.nameGUID[n]  = g
			ambiguous[n]    = nil
			local u = ns.units[g]
			if u and u.utype then byName[n] = u.utype end
		end
	end

	ns:On("PLAYER_TARGET_CHANGED", function() Bind("target") end)
	ns:On("UPDATE_MOUSEOVER_UNIT", function() Bind("mouseover") end)
	ns:On("PLAYER_FOCUS_CHANGED",  function() Bind("focus") end)

	ns:OnTick(function(now)
		Scan()

		-- Everything the combat log has taught Core, indexed by name.
		--
		-- Two things matter here. First, the combat log reports cross-realm
		-- players as "Name-Realm" while the NAMEPLATE only ever shows "Name",
		-- so the suffix has to come off or the lookup can never match. Second,
		-- a mapping learned from a real unit token is authoritative: combat-log
		-- entries must not overwrite it, and must not flag it ambiguous. That
		-- mismatch is how an enemy's whole aura row could blank at once -- the
		-- plate resolved no GUID, so every icon hid together.
		for guid, u in pairs(ns.units) do
			if u.name then
				local short = u.name:match("^([^-]+)") or u.name
				if u.utype then byName[short] = u.utype end
				if not strong[short] then
					local prev = ns.nameGUID[short]
					if prev and prev ~= guid and prev ~= strong[short] then
						ambiguous[short] = true
					end
					ns.nameGUID[short] = guid
				end
			end
		end

		for frame, d in pairs(plates) do
			UpdatePlate(frame, d)
			if d.shownAuras and d.shownAuras > 0 then
				for i = 1, d.shownAuras do
					local icon = d.auras[i]
					if icon.expires and icon.expires > 0 then
						local left = icon.expires - now
						icon.time:SetText(left > 0 and string.format("%d", left) or "")
					else
						icon.time:SetText("")
					end
				end
			end
		end
	end)

	ns:Print("plates active - |cffffff00/fyco plates|r for pet scaling")
end

----------------------------------------------------------------------
-- diagnostics
----------------------------------------------------------------------

--- Dump what the plate layer believes about the current target, next to what
--- the API actually reports. If those two agree, the plate is telling the
--- truth and the debuff really is gone; if they disagree, the cache or the
--- name->GUID resolution is at fault.
function ns:AuraDebug()
	if not UnitExists("target") then ns:Print("no target") return end
	local name, guid = UnitName("target"), UnitGUID("target")
	ns:Print("target: " .. tostring(name) .. "  guid " .. tostring(guid))
	ns:Print("  ambiguous name: " .. tostring(ambiguous[name] and "YES - plate will hide auras unless targeted" or "no"))
	ns:Print("  nameGUID maps to: " .. tostring(ns.nameGUID and ns.nameGUID[name]))
	ns:Print("  strong (token) map: " .. tostring(strong[name]))
	ns:Print("  type: " .. tostring(byName[name]))

	local all = FycoPvPDB.plates and FycoPvPDB.plates.showAllDebuffs
	ns:Print("  show every debuff: " .. tostring(all and "yes" or "no"))

	-- With showAllDebuffs on, everyone's debuffs are ground truth, not only
	-- yours -- so print the lot and mark which ones are yours.
	local truth = 0
	ns:Print("|cffffff00what UnitDebuff reports (ground truth):|r")
	for i = 1, 40 do
		local n, _, _, _, dt, _, _, caster, _, _, sid = UnitDebuff("target", i)
		if not n then break end
		if caster == "player" or all then
			truth = truth + 1
			ns:Print(string.format("  %s%s (%s) type=%s",
				caster == "player" and "|cff00ff00*|r " or "  ",
				n, tostring(sid), tostring(dt)))
		end
	end
	if truth == 0 then ns:Print(all and "  none at all" or "  none cast by you") end

	local cached, mine, foreign = 0, 0, 0
	local a = ns.auras[guid]
	if a then
		for sid, e in pairs(a) do
			cached = cached + 1
			if e.mine then
				mine = mine + 1
			elseif e.harmful then
				foreign = foreign + 1
			end
		end
	end
	ns:Print(string.format("|cffffff00plate cache:|r %d entries, %d yours, "
		.. "%d other debuffs%s", cached, mine, foreign,
		all and "" or " (hidden - show every debuff is off)"))

	local plate
	for f, d in pairs(plates) do
		if d.name and d.name:GetText() == name and f:IsShown() then plate = d break end
	end
	ns:Print("  plate found: " .. tostring(plate ~= nil)
		.. (plate and ("  icons shown: " .. tostring(plate.shownAuras)) or ""))
end

----------------------------------------------------------------------
-- config
----------------------------------------------------------------------

--- Push the visibility settings to the engine. These are the only two things
--- here the addon cannot do itself: whether plates exist at all.
function ns:ApplyPlateCVars()
	local cfg = FycoPvPDB.plates
	if not cfg then return end
	pcall(SetCVar, "nameplateShowFriends", cfg.hideFriendly and "0" or "1")
	pcall(SetCVar, "nameplateShowEnemies", cfg.showEnemies and "1" or "0")
end

--- Read the live CVars back into our settings. Blizzard's own Names panel and
--- the V / shift-V keybinds change these behind our back, so the checkbox must
--- reflect reality rather than a stale saved value.
function ns:SyncPlateCVars()
	local cfg = FycoPvPDB.plates
	if not cfg then return end
	local f = GetCVar("nameplateShowFriends")
	local e = GetCVar("nameplateShowEnemies")
	if f then cfg.hideFriendly = (f == "0") end
	if e then cfg.showEnemies  = (e == "1") end
end

local toggles = {
	hideFriendly = true, showEnemies = true, classColor = true,
	showHealthValue = true,
	showClassIcon = true, showLevel = true, showHealthPct = true,
	showPetAuras = true, showAllDebuffs = true,
}

function ns:PlatesConfig(rest)
	local cfg = FycoPvPDB.plates
	rest = rest or ""

	-- bare word toggles a boolean; "petauras" kept as an alias
	local word = rest:match("^(%a+)$")
	if word == "petauras" then word = "showPetAuras" end
	if word and toggles[word] then
		cfg[word] = not cfg[word]
		ns:Print(string.format("plates.%s = %s", word, tostring(cfg[word])))
		if word == "hideFriendly" or word == "showEnemies" then
			ns:ApplyPlateCVars()
		end
		return
	end
	local key, val = rest:match("^(%a+)%s+([%d%.]+)$")
	if key and cfg[key] ~= nil and tonumber(val) then
		cfg[key] = tonumber(val)
		ns:Print(string.format("plates.%s = %s", key, val))
		return
	end
	ns:Print("usage: |cffffff00/fyco plates <setting> <number>|r, or |cffffff00petauras|r")
	for k, v in pairs(cfg) do
		ns:Print(string.format("  %-13s %s", k, tostring(v)))
	end
end
