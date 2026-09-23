--[[ FycoPvP - Modules/Options.lua
     Panels under Interface -> AddOns, alongside every other addon.
     Everything writes the same FycoPvPDB keys the slash commands do, so the
     two stay in step whichever you use.

     LAYOUT. Read HARD RULE 1 in CLAUDE.md before touching this file. Twice now
     widgets have escaped the panel and rendered over the game world, both times
     because Y offsets were worked out by hand and a column quietly grew past
     the bottom of a container that does not clip its children.

     Two things prevent that happening again, and neither is optional:

       1. A LAYOUT CURSOR. Nothing in this file writes a literal Y offset.
          Column:Check, :Slider, :Title, :Note, :Button and :Swatch each place
          their widget at the cursor and then advance it by that widget's real
          height -- a Note measures its own wrapped text rather than guessing.
          Reordering or inserting a setting cannot break the ones below it.

       2. A SCROLL FRAME per panel. The content area is about 500x500; a panel
          longer than that now scrolls instead of overflowing. Finish() sizes
          the scroll child to the deepest column, so a panel that outgrows the
          view keeps working with no further thought.

     Two columns, 230 wide each. A third ran off the right edge once already.
     Built with stock 3.3.5a widget templates, so the addon keeps zero
     dependencies. Loaded by Core.lua at PLAYER_LOGIN.                       ]]

local ADDON, ns = ...
local M = ns:Module("options")

-- column origins and width. Two columns is the maximum that fits.
local COL1, COL2, COL_W = 8, 250, 230
local SLIDER_W = 180

-- how far the cursor advances per widget. A Note measures itself instead.
local H_CHECK, H_TITLE, H_BTN, H_SWATCH = 24, 34, 28, 28
local H_SLIDER_TOP, H_SLIDER_BODY = 16, 36   -- the caption sits above the bar

local panels = {}

----------------------------------------------------------------------
-- panel scaffolding
----------------------------------------------------------------------

--- A config panel whose content scrolls. Widgets are added to `.content`,
--- never to the panel itself.
local function MakePanel(key, displayName, parentName)
	local p = CreateFrame("Frame", ADDON .. "Opt" .. key, UIParent)
	p.name = displayName
	if parentName then p.parent = parentName end

	local scroll = CreateFrame("ScrollFrame", ADDON .. "Opt" .. key .. "Scroll",
	                           p, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetWidth(490)
	content:SetHeight(500)
	scroll:SetScrollChild(content)

	p.scroll, p.content, p.widgets = scroll, content, {}

	p.refresh = function()
		for i = 1, #p.widgets do
			if p.widgets[i].Refresh then p.widgets[i].Refresh() end
		end
	end

	p.resize = function()
		-- match the scroll child to the real width we were given; the panel
		-- has no size at all until the first time it is shown
		local w = scroll:GetWidth()
		if w and w > 50 then content:SetWidth(w) end
	end

	p:SetScript("OnShow", function()
		p.resize()
		p.refresh()
	end)

	panels[#panels + 1] = p
	return p
end

----------------------------------------------------------------------
-- the layout cursor
----------------------------------------------------------------------

local Column = {}
Column.__index = Column

local sliderN = 0

--- A cursor running down one column of a panel.
local function NewColumn(panel, x)
	return setmetatable({
		panel = panel, frame = panel.content, x = x, y = -12,
	}, Column)
end

function Column:advance(h)
	self.y = self.y - h
	return self
end

function Column:track(w)
	self.panel.widgets[#self.panel.widgets + 1] = w
	return w
end

function Column:Gap(h)
	return self:advance(h or 10)
end

function Column:Title(text)
	local fs = self.frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	fs:SetPoint("TOPLEFT", self.x, self.y)
	fs:SetText(text)
	self:advance(H_TITLE)
	return fs
end

function Column:Note(text)
	local fs = self.frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	fs:SetPoint("TOPLEFT", self.x, self.y)
	fs:SetWidth(COL_W)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)

	-- Measure the wrapped height rather than guessing. If the client has not
	-- laid the string out yet, fall back to an estimate from how many lines
	-- this much text needs at this width -- erring long, never short.
	local h = fs:GetStringHeight() or 0
	if h < 1 then h = 11 * math.max(1, math.ceil(#text / 42)) end
	self:advance(math.ceil(h) + 8)
	return fs
end

function Column:Check(label, tooltip, get, set)
	local cb = CreateFrame("CheckButton", nil, self.frame, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", self.x + 4, self.y)
	cb:SetWidth(24)
	cb:SetHeight(24)

	local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	fs:SetWidth(COL_W - 34)
	fs:SetJustifyH("LEFT")
	fs:SetText(label)

	cb.tooltipText = tooltip
	cb:SetScript("OnClick", function(self2)
		set(self2:GetChecked() and true or false)
	end)
	cb.Refresh = function() cb:SetChecked(get()) end

	self:track(cb)
	self:advance(H_CHECK)
	return cb
end

function Column:Slider(label, minV, maxV, step, get, set)
	sliderN = sliderN + 1
	self:advance(H_SLIDER_TOP)         -- the caption is drawn above the bar

	local s = CreateFrame("Slider", ADDON .. "OptSlider" .. sliderN,
	                      self.frame, "OptionsSliderTemplate")
	s:SetPoint("TOPLEFT", self.x + 14, self.y)
	s:SetWidth(SLIDER_W)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	_G[s:GetName() .. "Low"]:SetText(tostring(minV))
	_G[s:GetName() .. "High"]:SetText(tostring(maxV))

	local caption = _G[s:GetName() .. "Text"]
	s:SetScript("OnValueChanged", function(self2, v)
		v = math.floor(v * 100 + 0.5) / 100
		caption:SetText(label .. ": " .. v)
		if not self2.loading then set(v) end
	end)
	s.Refresh = function()
		s.loading = true
		local v = get()
		s:SetValue(v)
		caption:SetText(label .. ": " .. v)
		s.loading = false
	end

	self:track(s)
	self:advance(H_SLIDER_BODY)
	return s
end

function Column:Button(label, fn, w)
	local b = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", self.x + 4, self.y)
	b:SetWidth(w or 150)
	b:SetHeight(22)
	b:SetText(label)
	b:SetScript("OnClick", fn)
	self:advance(H_BTN)
	return b
end

--- Two buttons side by side, costing one row.
function Column:Buttons(l1, f1, l2, f2)
	local a = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
	a:SetPoint("TOPLEFT", self.x + 4, self.y)
	a:SetWidth(108)
	a:SetHeight(22)
	a:SetText(l1)
	a:SetScript("OnClick", f1)

	local b = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", self.x + 116, self.y)
	b:SetWidth(108)
	b:SetHeight(22)
	b:SetText(l2)
	b:SetScript("OnClick", f2)

	self:advance(H_BTN)
	return a, b
end

--- A colour swatch that opens Blizzard's picker. `key` names the {r,g,b}
--- table inside FycoPvPDB.plates, so the picker edits it in place.
function Column:Swatch(label, key)
	local b = CreateFrame("Button", nil, self.frame)
	b:SetPoint("TOPLEFT", self.x + 4, self.y)
	b:SetWidth(20)
	b:SetHeight(20)

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", -1, 1)
	bg:SetPoint("BOTTOMRIGHT", 1, -1)
	bg:SetTexture(0, 0, 0, 1)

	local sw = b:CreateTexture(nil, "ARTWORK")
	sw:SetAllPoints(b)

	local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("LEFT", b, "RIGHT", 6, 0)
	fs:SetText(label)

	local function cur()
		local p = FycoPvPDB.plates
		return (p and p[key]) or { 1, 1, 1 }
	end

	b.Refresh = function()
		local c = cur()
		sw:SetTexture(c[1], c[2], c[3], 1)
	end

	b:SetScript("OnClick", function()
		local c = cur()
		local prev = { c[1], c[2], c[3] }

		ColorPickerFrame.hasOpacity  = false
		ColorPickerFrame.opacityFunc = nil
		ColorPickerFrame.func = function()
			local r, g, b2 = ColorPickerFrame:GetColorRGB()
			if FycoPvPDB.plates then FycoPvPDB.plates[key] = { r, g, b2 } end
			sw:SetTexture(r, g, b2, 1)
		end
		ColorPickerFrame.cancelFunc = function()
			if FycoPvPDB.plates then FycoPvPDB.plates[key] = prev end
			sw:SetTexture(prev[1], prev[2], prev[3], 1)
		end
		ColorPickerFrame.previousValues = prev
		ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
		-- hide then show: 3.3.5a will not re-run its OnShow otherwise
		ColorPickerFrame:Hide()
		ColorPickerFrame:Show()
	end)

	self:track(b)
	self:advance(H_SWATCH)
	return b
end

--- Size the scroll child to whichever column ran deepest, then register the
--- panel. Skipping this leaves it unscrollable however long it grows.
local function Finish(panel, ...)
	local deepest = 0
	for i = 1, select("#", ...) do
		local col = select(i, ...)
		if -col.y > deepest then deepest = -col.y end
	end
	panel.content:SetHeight(deepest + 24)
	InterfaceOptions_AddCategory(panel)
end

----------------------------------------------------------------------
-- shared accessors
----------------------------------------------------------------------

local function plates(key, default)
	local p = FycoPvPDB.plates
	if p and p[key] ~= nil then return p[key] end
	return default
end

local function setPlate(key)
	return function(v) if FycoPvPDB.plates then FycoPvPDB.plates[key] = v end end
end

local function db(key, default)
	if FycoPvPDB[key] ~= nil then return FycoPvPDB[key] end
	return default
end

local function setDB(key)
	return function(v) FycoPvPDB[key] = v end
end

----------------------------------------------------------------------
-- main panel
----------------------------------------------------------------------

local main

local function BuildMain()
	main = MakePanel("Main", "FycoPvP")
	local L, R = NewColumn(main, COL1), NewColumn(main, COL2)

	L:Title("FycoPvP")
	L:Note("Unified PvP interface. Every setting here matches a /fyco command. "
	    .. "Nameplates, Debuffs, Combat and Dispel have their own tabs.")
	L:Gap(6)

	L:Title("Modules")
	L:Note("Changes apply at once. Plates alone needs a /reload.")

	local modsLeft = {
		{ "control",   "Control - CC on you" },
		{ "procs",     "Procs - your own windows" },
		{ "casts",     "Cast bars" },
		{ "auras",     "Auras - target and focus" },
		{ "alerts",    "Alerts - defensives, trinket" },
		{ "cooldowns", "Cooldowns - DR and enemy CDs" },
		{ "plates",    "Plates - nameplates" },
		{ "dispel",    "Dispel - enemy buffs" },
		{ "cdtext",    "Cooldown numbers - action bars" },
		{ "bar",       "Cooldown bar - your spells" },
	}
	local modsRight = {
		{ "buffs",    "Buffs - what is missing" },
		{ "spec",     "Spec - infer spec, mark healers" },
		{ "range",    "Range - in range of target" },
		{ "lockout",  "Lockout - interrupt lockouts" },
		{ "recap",    "Recap - what killed you" },
		{ "stats",    "Stats - session counters" },
		{ "archive",  "Archive - record every game" },
		{ "announce", "Announce - party chat" },
		{ "logger",   "Logger - measure durations" },
	}

	local function ModList(col, list)
		for i = 1, #list do
			local key = list[i][1]
			col:Check(list[i][2], (key == "plates") and "Requires /reload" or nil,
				function() return FycoPvPDB.enabled[key] ~= false end,
				function(v) FycoPvPDB.enabled[key] = v end)
		end
	end

	ModList(L, modsLeft)
	L:Gap(8)
	L:Button("Unlock / lock frames", function() ns:Fire("ToggleLock") end, 180)
	L:Note("Unlock shows every frame with placeholder content so it can be "
	    .. "dragged. Positions save automatically.")

	R:Title("Sound")
	R:Check("Voice and sound cues", nil,
		function() return db("sounds", true) end, setDB("sounds"))
	R:Check("Screen flash on procs", nil,
		function() return db("procFlash", true) end, setDB("procFlash"))
	R:Check("Hide Blizzard cast bars", "Requires /reload",
		function() return db("hideBlizzCast", true) end, setDB("hideBlizzCast"))

	R:Gap(8)
	R:Title("Layout")
	R:Slider("Icons per row", 1, 20, 1,
		function() return db("perRow", 7) end, setDB("perRow"))
	R:Note("Applies to every bar in the addon. Rows laid out once need a "
	    .. "/reload; the rest wrap as soon as they next refresh.")
	R:Gap(6)
	R:Buttons("Test voices", function() SlashCmdList.FYCOPVP("voices") end,
	          "Test procs",  function() if ns.ProcDemo then ns:ProcDemo() end end)
	R:Button("Stop tests", function() SlashCmdList.FYCOPVP("stop") end, 150)

	R:Gap(10)
	R:Title("Modules continued")
	ModList(R, modsRight)

	Finish(main, L, R)
end

----------------------------------------------------------------------
-- nameplates
----------------------------------------------------------------------

local function BuildPlates()
	local p = MakePanel("Plates", "Nameplates", "FycoPvP")
	local L, R = NewColumn(p, COL1), NewColumn(p, COL2)

	L:Title("Nameplates")
	L:Note("Hiding allies uses the nameplateShowFriends console setting, so "
	    .. "those plates are never created at all.")
	L:Gap(4)

	L:Title("Visibility")
	L:Check("Hide friendly plates", "Applies immediately",
		function() return plates("hideFriendly", true) end,
		function(v)
			setPlate("hideFriendly")(v)
			if ns.ApplyPlateCVars then ns:ApplyPlateCVars() end
		end)
	L:Check("Show enemy plates", "Applies immediately",
		function() return plates("showEnemies", true) end,
		function(v)
			setPlate("showEnemies")(v)
			if ns.ApplyPlateCVars then ns:ApplyPlateCVars() end
		end)

	L:Gap(8)
	L:Title("Content")
	L:Check("Class colour enemy players", nil,
		function() return plates("classColor", true) end, setPlate("classColor"))
	L:Check("Class icon", nil,
		function() return plates("showClassIcon", true) end, setPlate("showClassIcon"))
	L:Check("Show spec under the bar", nil,
		function() return plates("showSpec", true) end, setPlate("showSpec"))
	L:Check("Level text", nil,
		function() return plates("showLevel", false) end, setPlate("showLevel"))
	L:Check("Health percentage", nil,
		function() return plates("showHealthPct", true) end, setPlate("showHealthPct"))
	L:Check("Health value in bar", nil,
		function() return plates("showHealthValue", true) end, setPlate("showHealthValue"))
	L:Check("Auras on pet plates", nil,
		function() return plates("showPetAuras", false) end, setPlate("showPetAuras"))
	L:Check("Fade target name out of range", nil,
		function() return plates("rangeFade", true) end, setPlate("rangeFade"))
	L:Slider("Name size", 8, 18, 1,
		function() return plates("nameSize", 10) end, setPlate("nameSize"))

	R:Title("Bar colours")
	R:Note("Used when class colouring is off, and for anyone whose class is "
	    .. "not known yet.")
	R:Swatch("Enemy players", "colorEnemy")
	R:Swatch("Allies",        "colorFriendly")
	R:Swatch("NPCs",          "colorNpc")
	R:Swatch("Pets",          "colorPet")

	R:Gap(10)
	R:Title("Sizing")
	R:Note("Pets are shrunk and faded so they cannot crowd out players.")
	R:Slider("Pet scale", 0.4, 1.0, 0.05,
		function() return plates("petScale", 0.65) end, setPlate("petScale"))
	R:Slider("Pet opacity", 0.2, 1.0, 0.05,
		function() return plates("petAlpha", 0.55) end, setPlate("petAlpha"))
	R:Slider("NPC scale", 0.4, 1.0, 0.05,
		function() return plates("npcScale", 0.80) end, setPlate("npcScale"))

	-- the plate CVars can be changed from Blizzard's own Names panel, so
	-- re-read them every time this one is opened
	p:SetScript("OnShow", function()
		if ns.SyncPlateCVars then ns:SyncPlateCVars() end
		p.resize()
		p.refresh()
	end)

	Finish(p, L, R)
end

----------------------------------------------------------------------
-- debuffs
----------------------------------------------------------------------

local function aur(key, default)
	local a = FycoPvPDB.auras
	if a and a[key] ~= nil then return a[key] end
	return default
end

local function setAur(key)
	return function(v)
		FycoPvPDB.auras = FycoPvPDB.auras or {}
		FycoPvPDB.auras[key] = v
		ns:Fire("DebuffOptions")
	end
end

--- Both places debuffs are drawn, on one panel: the request that produced it
--- treated the bar and the nameplates as one feature, and so do the settings.
local function BuildDebuffs()
	local p = MakePanel("Debuffs", "Debuffs", "FycoPvP")
	local L, R = NewColumn(p, COL1), NewColumn(p, COL2)

	L:Title("Debuffs")
	L:Note("Normally only the debuffs YOU applied are tracked. Turn these on "
	    .. "and every debuff on the unit is shown instead - yours still first, "
	    .. "larger and solid, everyone else's after them, smaller and dimmed.")
	L:Gap(4)

	L:Title("Target and focus bar")
	L:Check("Show every debuff", "Off shows only the debuffs you applied",
		function() return aur("showAll", false) end, setAur("showAll"))
	L:Note("Their defensives, and any CC they are sitting in, stay on the top "
	    .. "row - so this never puts CC somewhere you might break it.")
	L:Slider("Your icons", 16, 44, 2,
		function() return aur("mineSize", 26) end, setAur("mineSize"))
	L:Slider("Everyone else's", 12, 36, 2,
		function() return aur("otherSize", 20) end, setAur("otherSize"))
	L:Note("Up to 16 icons on the bottom row, wrapping at the icons-per-row "
	    .. "setting on the main panel.")

	R:Title("Nameplates")
	R:Check("Show every debuff", "Off shows only your debuffs and their "
	     .. "defensives",
		function() return plates("showAllDebuffs", false) end,
		setPlate("showAllDebuffs"))
	R:Note("Order on a plate: their defensives, then your debuffs at full "
	    .. "size, then everyone else's, smaller and dimmed. Eight icons fit.")

	R:Gap(8)
	R:Title("What the timers can and cannot say")
	R:Note("On your own target and focus the game is asked directly, so those "
	    .. "countdowns are exact. On any OTHER plate a debuff you did not cast "
	    .. "is known only from the combat log, which reports no duration at all "
	    .. "in 3.3.5a - so it draws an icon with no number under it rather than "
	    .. "a guess. That is the main reason this is off by default.")

	R:Gap(6)
	R:Button("What does my target have?", function()
		SlashCmdList.FYCOPVP("auras")
	end, 200)
	R:Note("Prints every debuff the game reports on your target next to what "
	    .. "the plate cache believes, and marks the ones you cast.")

	Finish(p, L, R)
end

----------------------------------------------------------------------
-- combat
----------------------------------------------------------------------

local CHANNEL_CYCLE = { "PARTY", "BATTLEGROUND", "RAID", "SAY" }

local function ann(key, default)
	local a = FycoPvPDB.announce
	if a and a[key] ~= nil then return a[key] end
	return default
end

local function setAnn(key)
	return function(v)
		FycoPvPDB.announce = FycoPvPDB.announce or {}
		FycoPvPDB.announce[key] = v
	end
end

local function BuildCombat()
	local p = MakePanel("Combat", "Combat", "FycoPvP")
	local L, R = NewColumn(p, COL1), NewColumn(p, COL2)

	L:Title("Combat")
	L:Note("Spec is deduced from the spells an enemy casts. 3.3.5a exposes no "
	    .. "spec for anyone but you, so an enemy who has cast nothing shows "
	    .. "nothing rather than a guess.")
	L:Gap(4)

	L:Title("Enemy intel")
	L:Check("Announce healers in chat", "Prints to your own chat frame only",
		function() return db("specAnnounceHealer", true) end,
		setDB("specAnnounceHealer"))

	L:Gap(8)
	L:Title("Drinking")
	L:Check("Call out drinking enemies", nil,
		function() return db("drinkAlert", true) end, setDB("drinkAlert"))
	L:Check("Arena only", "Off means it also fires in battlegrounds, where "
	     .. "somebody is always drinking",
		function() return db("drinkArenaOnly", true) end, setDB("drinkArenaOnly"))
	L:Check("Play a sound for it", nil,
		function() return db("drinkSound", false) end, setDB("drinkSound"))

	L:Gap(8)
	L:Title("Interrupts")
	L:Check("Sound when you are locked out", nil,
		function() return db("lockoutSound", true) end, setDB("lockoutSound"))

	R:Title("Death recap")
	R:Check("Print it when you die", nil,
		function() return db("recapAuto", true) end, setDB("recapAuto"))
	R:Slider("Seconds to replay", 5, 20, 1,
		function() return db("recapWindow", 10) end, setDB("recapWindow"))

	R:Gap(8)
	R:Title("Session")
	R:Note("A session ends by itself after this long with nothing recorded. A "
	    .. "/reload keeps it; coming back tomorrow starts a new one.")
	R:Slider("Idle minutes", 15, 360, 15,
		function() return math.floor(db("sessionGap", 7200) / 60) end,
		function(v) FycoPvPDB.sessionGap = v * 60 end)
	R:Buttons("Show stats", function() SlashCmdList.FYCOPVP("stats") end,
	          "End session", function() SlashCmdList.FYCOPVP("stats reset") end)

	R:Gap(10)
	R:Title("Party announce")
	R:Note("Off by default. Capped at 5 messages per 15s however many events "
	    .. "fire, so it cannot flood a battleground.")
	R:Check("Enabled", nil,
		function() return ann("enabled", false) end, setAnn("enabled"))

	local chanBtn
	chanBtn = R:Button("Channel", function()
		local cur = ann("channel", "PARTY")
		local nextI = 1
		for i = 1, #CHANNEL_CYCLE do
			if CHANNEL_CYCLE[i] == cur then nextI = (i % #CHANNEL_CYCLE) + 1 end
		end
		setAnn("channel")(CHANNEL_CYCLE[nextI])
		chanBtn:SetText("Channel: " .. CHANNEL_CYCLE[nextI])
	end, 180)
	chanBtn.Refresh = function()
		chanBtn:SetText("Channel: " .. ann("channel", "PARTY"))
	end
	R:track(chanBtn)

	local what = {
		{ "cc", "CC you land" }, { "kick", "Your interrupts" },
		{ "trinket", "Enemy trinkets" }, { "drink", "Drinking" },
		{ "defensive", "Enemy defensives" },
	}
	for i = 1, #what do
		local key = what[i][1]
		R:Check(what[i][2], nil,
			function() return ann(key, true) end, setAnn(key))
	end

	Finish(p, L, R)
end

----------------------------------------------------------------------
-- dispel
----------------------------------------------------------------------

local function dis(key, default)
	local d = FycoPvPDB.dispel
	if d and d[key] ~= nil then return d[key] end
	return default
end

local function setDis(key)
	return function(v)
		FycoPvPDB.dispel = FycoPvPDB.dispel or {}
		FycoPvPDB.dispel[key] = v
	end
end

local function BuildDispel()
	local p = MakePanel("Dispel", "Dispel", "FycoPvP")
	local L, R = NewColumn(p, COL1), NewColumn(p, COL2)

	L:Title("Enemy buffs")
	L:Note("A row of the enemy's buffs for target and focus, coloured by "
	    .. "dispel type. The ones worth removing are drawn larger and pulse.")
	L:Gap(4)

	L:Title("Highlight these types")
	L:Note("Only Magic can be taken off an enemy in 3.3.5a - Purge, Spellsteal, "
	    .. "Dispel Magic and Devour Magic all take Magic and nothing else. The "
	    .. "other three are here because the module is generic, not because "
	    .. "they will find anything.")

	for i = 1, #ns.DispelTypes do
		local t = ns.DispelTypes[i]
		local col = ns.DebuffColor[t] or { 1, 1, 1 }
		L:Check(string.format("|cff%02x%02x%02x%s|r",
				col[1] * 255, col[2] * 255, col[3] * 255, t), nil,
			function()
				local types = dis("types", nil)
				return (types and types[t]) or false
			end,
			function(v)
				FycoPvPDB.dispel = FycoPvPDB.dispel or {}
				FycoPvPDB.dispel.types = FycoPvPDB.dispel.types or {}
				FycoPvPDB.dispel.types[t] = v
			end)
	end

	L:Gap(8)
	L:Button("What does my target have?", function()
		SlashCmdList.FYCOPVP("dispel debug")
	end, 200)
	L:Note("Prints every buff on your target with what the game says its dispel "
	    .. "type is. Use it if something you expected to highlight did not.")

	R:Title("Where to show it")
	R:Check("On your target", nil,
		function() return dis("target", true) end, setDis("target"))
	R:Check("On your focus", nil,
		function() return dis("focus", true) end, setDis("focus"))

	R:Gap(8)
	R:Title("The buff bar")
	R:Check("Show every buff", "Off shows only buffs you could dispel",
		function() return dis("showAll", true) end, setDis("showAll"))
	R:Check("Hide Blizzard's buff row", "Replaces the stock target and focus "
	     .. "buffs. Debuffs are left alone.",
		function() return dis("hideBlizzard", false) end, setDis("hideBlizzard"))
	R:Note("Buffs show on anyone - friendly, neutral or hostile. Only the "
	    .. "highlight needs a hostile target, since there is nothing to strip "
	    .. "off a friend.")

	R:Gap(8)
	R:Title("Size")
	R:Slider("Normal icon", 16, 40, 2,
		function() return dis("size", 26) end, setDis("size"))
	R:Slider("Highlighted icon", 20, 56, 2,
		function() return dis("bigSize", 34) end, setDis("bigSize"))
	R:Note("A buff is highlighted when it is a type ticked on the left, the "
	    .. "unit is hostile, and either the watch list is empty or the buff is "
	    .. "on it. Use /fyco dispel watch to manage that list.")

	Finish(p, L, R)
end

----------------------------------------------------------------------

function M:OnLoad()
	BuildMain()
	BuildPlates()
	BuildDebuffs()
	BuildCombat()
	BuildDispel()

	ns.OpenOptions = function()
		InterfaceOptionsFrame_OpenToCategory(main)
		InterfaceOptionsFrame_OpenToCategory(main)  -- 3.3.5a needs it twice
	end
end
