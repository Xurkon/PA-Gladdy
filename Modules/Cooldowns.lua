local type, pairs, ipairs, ceil, tonumber, mod, tostring, upper, select, tinsert, tremove = type, pairs, ipairs, ceil, tonumber, mod, tostring, string.upper, select, tinsert, tremove
local tbl_sort = table.sort
local C_Timer = C_Timer
local GetTime = GetTime
local CreateFrame = CreateFrame
local GetSpellInfo = C_GetSpellInfo or GetSpellInfo
local AURA_TYPE_BUFF = AURA_TYPE_BUFF

local Gladdy = LibStub("Gladdy")
local LCG = LibStub("LibCustomGlow-1.0")
local L = Gladdy.L

local function tableLength(tbl)
	local getN = 0
	for n in pairs(tbl) do
		getN = getN + 1
	end
	return getN
end

-- Specializations per class
local CLASS_SPECS = {
	["WARRIOR"] = { "Arms", "Fury", "Protection" },
	["PALADIN"] = { "Holy", "Protection", "Retribution" },
	["HUNTER"] = { "Beast Mastery", "Marksmanship", "Survival" },
	["ROGUE"] = { "Assassination", "Combat", "Subtlety" },
	["PRIEST"] = { "Discipline", "Holy", "Shadow" },
	["DEATHKNIGHT"] = { "Blood", "Frost", "Unholy" },
	["SHAMAN"] = { "Elemental", "Enhancement", "Restoration" },
	["MAGE"] = { "Arcane", "Fire", "Frost" },
	["WARLOCK"] = { "Affliction", "Demonology", "Destruction" },
	["DRUID"] = { "Balance", "Feral", "Restoration" },
}

-- Get specs for a class (returns table with localized spec names)
local function getSpecsForClass(class)
	if class == "ALL" or class == "NONE" or not class then
		return nil
	end
	local specs = CLASS_SPECS[class]
	if not specs then
		return nil
	end
	-- Return localized names
	local localizedSpecs = {}
	for _, spec in ipairs(specs) do
		local localizedName = L[spec] or spec
		tinsert(localizedSpecs, localizedName)
	end
	return localizedSpecs
end

local function getDefaultCooldown()
	local cooldowns = {}
	local cooldownsOrder = {}
	for class,spellTable in pairs(Gladdy:GetCooldownList()) do
		if not spellTable.class and not cooldownsOrder[class] then
			cooldownsOrder[class] = {}
		end
		for spellId,val in pairs(spellTable) do
			local spellName = GetSpellInfo(spellId)
			if spellName then
				cooldowns[tostring(spellId)] = true
				if type(val) == "table" and val.class then
					if val.class and not cooldownsOrder[val.class] then
						cooldownsOrder[val.class] = {}
					end
					if not cooldownsOrder[val.class][tostring(spellId)] then
						cooldownsOrder[val.class][tostring(spellId)] = tableLength(cooldownsOrder[val.class]) + 1
					end
				else
					if not cooldownsOrder[class][tostring(spellId)] then
						cooldownsOrder[class][tostring(spellId)] = tableLength(cooldownsOrder[class]) + 1
					end
				end
			else
				Gladdy:Debug("ERROR", "spellid does not exist  " .. spellId)
			end
		end
	end
	return cooldowns, cooldownsOrder
end

local Cooldowns = Gladdy:NewModule("Cooldowns", nil, {
	cooldownFont = "DorisPP",
	cooldownFontScale = 1,
	cooldownFontColor = { r = 1, g = 1, b = 0, a = 1 },
	cooldown = true,
	cooldownYGrowDirection = "UP",
	cooldownXGrowDirection = "RIGHT",
	cooldownYOffset = 0,
	cooldownXOffset = 0,
	cooldownSize = 30,
	cooldownIconGlow = true,
	cooldownIconGlowColor = {r = 0.95, g = 0.95, b = 0.32, a = 1},
	cooldownIconZoomed = false,
	cooldownIconDesaturateOnCooldown = false,
	cooldownIconAlphaOnCooldown = 1,
	cooldownWidthFactor = 1,
	cooldownIconPadding = 1,
	cooldownMaxIconsPerLine = 10,
	cooldownBorderStyle = "Interface\\AddOns\\Gladdy\\Images\\Border_Gloss",
	cooldownBorderColor = { r = 1, g = 1, b = 1, a = 1 },
	cooldownDisableCircle = false,
	cooldownCooldownAlpha = 1,
	cooldownCooldowns = getDefaultCooldown(),
	cooldownCooldownsOrder = select(2, getDefaultCooldown()),
	cooldownFrameStrata = "MEDIUM",
	cooldownFrameLevel = 3,
	cooldownGroup = false,
	cooldownGroupDirection = "DOWN",
	-- Custom cooldowns - stored as simple string to avoid cleanup issues
	-- Format: "spellId1,cd1,class1,name1,texture1;spellId2,cd2,class2,name2,texture2;..."
	customCooldownsString = "",
	customCooldownInput = "",
	customCooldownDuration = "60",
	customCooldownClass = "ALL",
	customCooldownSpec = "NONE",
	-- Cooldown duration overrides - allows users to customize individual spell cooldowns
	-- Format: cooldownDurationOverrides[spellId] = customDuration (in seconds)
	cooldownDurationOverrides = {},
})

function Cooldowns:Initialize()
	self.frames = {}
	self.cooldownSpellIds = {}
	self.spellTextures = {}
	self.iconCache = {}
	-- Ensure cooldownDurationOverrides table exists
	if not Gladdy.db.cooldownDurationOverrides then
		Gladdy.db.cooldownDurationOverrides = {}
	end
	-- Load built-in cooldowns
	for _,spellTable in pairs(Gladdy:GetCooldownList()) do
		for spellId,val in pairs(spellTable) do
			local spellName, _, texture = GetSpellInfo(spellId)
			if type(val) == "table" then
				if val.icon then
					texture = val.icon
				end
				if val.altName then
					spellName = val.altName
				end
			end
			if spellName then
				self.cooldownSpellIds[spellName] = spellId
				self.spellTextures[spellId] = texture
			else
				Gladdy:Debug("ERROR", "spellid does not exist  " .. spellId)
			end
		end
	end
	-- Load custom cooldowns from user config
	self:LoadCustomCooldowns()
	self:RegisterMessage("ENEMY_SPOTTED")
	self:RegisterMessage("UNIT_SPEC")
	self:RegisterMessage("UNIT_DEATH")
	self:RegisterMessage("UNIT_DESTROYED")
	self:RegisterMessage("AURA_GAIN")
end

-- Custom cooldowns management
-- Runtime cache of parsed custom cooldowns
Cooldowns.customCooldownsCache = {}

-- Parse the stored string into a table
function Cooldowns:GetCustomCooldownsTable()
	local result = {}
	local str = Gladdy.db.customCooldownsString or ""
	if str == "" then return result end

	-- Format: "spellId,cd,class,spec,name,texture;spellId2,cd2,class2,spec2,name2,texture2;..."
	-- For backwards compatibility, also support old format without spec
	for entry in str:gmatch("([^;]+)") do
		-- Try new format with spec first (6 fields)
		local spellId, cd, class, spec, name, texture = entry:match("^(%d+),(%d+),([^,]+),([^,]+),([^,]+),(.+)$")
		if spellId and name then
			result[spellId] = {
				spellId = tonumber(spellId),
				cd = tonumber(cd),
				class = class,
				spec = spec ~= "NONE" and spec or nil,
				spellName = name,
				texture = texture,
			}
		else
			-- Fallback to old format without spec (5 fields)
			spellId, cd, class, name, texture = entry:match("^(%d+),(%d+),([^,]+),([^,]+),(.+)$")
			if spellId then
				result[spellId] = {
					spellId = tonumber(spellId),
					cd = tonumber(cd),
					class = class,
					spec = nil,
					spellName = name,
					texture = texture,
				}
			end
		end
	end
	return result
end

-- Save the table back to string format
function Cooldowns:SaveCustomCooldownsTable(tbl)
	local parts = {}
	for spellId, data in pairs(tbl) do
		-- Escape commas in name and texture by replacing with placeholder
		local safeName = (data.spellName or "Unknown"):gsub(",", "%%COMMA%%")
		local safeTexture = (data.texture or "Interface\\Icons\\INV_Misc_QuestionMark"):gsub(",", "%%COMMA%%")
		local safeSpec = data.spec or "NONE"
		local entry = string.format("%d,%d,%s,%s,%s,%s",
			data.spellId,
			data.cd,
			data.class or "ALL",
			safeSpec,
			safeName,
			safeTexture
		)
		tinsert(parts, entry)
	end
	Gladdy.db.customCooldownsString = table.concat(parts, ";")
end

function Cooldowns:LoadCustomCooldowns()
	-- Initialize custom cooldown list if not exists
	if not Gladdy:GetCooldownList()["CUSTOM"] then
		Gladdy:GetCooldownList()["CUSTOM"] = {}
	end
	-- Initialize order table for custom cooldowns
	if not Gladdy.db.cooldownCooldownsOrder["CUSTOM"] then
		Gladdy.db.cooldownCooldownsOrder["CUSTOM"] = {}
	end

	-- Parse stored string
	local customCooldowns = self:GetCustomCooldownsTable()
	self.customCooldownsCache = customCooldowns

	-- Load each custom cooldown
	local count = 0
	for key, data in pairs(customCooldowns) do
		-- Restore commas in name and texture
		local spellName = (data.spellName or "Unknown"):gsub("%%COMMA%%", ",")
		local texture = (data.texture or ""):gsub("%%COMMA%%", ",")
		local classFilter = data.class or "ALL"
		local specFilter = data.spec  -- Can be nil for "all specs"

		self:RegisterCustomCooldown(spellName, data.cd, data.spellId, texture, classFilter, specFilter, true)
		-- Make sure it's enabled
		Gladdy.db.cooldownCooldowns[tostring(data.spellId)] = true
		count = count + 1
	end
	if count > 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Gladdy]|r Loaded " .. count .. " custom cooldown(s)")
	end
end

function Cooldowns:AddCustomCooldown(spellName, cooldownDuration, classFilter, specFilter)
	if not spellName or spellName == "" then
		return false, "Spell name is empty"
	end

	local name, texture, spellId
	local inputSpellId = nil

	-- Method 1: Try to extract spell ID from a chat link (e.g., |cff71d5ff|Hspell:12345|h[Spell Name]|h|r)
	local linkSpellId = spellName:match("spell:(%d+)")
	local linkSpellName = spellName:match("%[(.-)%]")
	if linkSpellId then
		inputSpellId = tonumber(linkSpellId)
		spellId = inputSpellId
		name, _, texture = GetSpellInfo(spellId)
		-- If GetSpellInfo fails, use the name from the link
		if not name and linkSpellName then
			name = linkSpellName
		end
	end

	-- Method 2: Try as a direct spell ID number
	if not name then
		local numAsId = tonumber(spellName)
		if numAsId then
			inputSpellId = numAsId
			name, _, texture = GetSpellInfo(numAsId)
			spellId = numAsId
		end
	end

	-- Method 3: Try to get spell info by name (only works for spells in player's spellbook)
	if not name then
		name, _, texture, _, _, _, spellId = GetSpellInfo(spellName)
	end

	-- Method 4: For Ascension custom spells - allow manual entry with spell ID
	-- If we have a spell ID but GetSpellInfo failed, use manual entry mode
	if not name and inputSpellId then
		-- Use the name from the link if available
		if linkSpellName then
			name = linkSpellName
		else
			-- Ask user to provide name via link
			return false, "Spell ID " .. inputSpellId .. " not found. Please paste the spell LINK from chat (Shift+Click) instead of just the ID"
		end
		spellId = inputSpellId
		texture = "Interface\\Icons\\INV_Misc_QuestionMark"
		DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[Gladdy]|r Added Ascension custom spell: " .. name .. " (ID: " .. spellId .. ")")
	end

	if not name then
		return false, "Spell not found: " .. spellName .. " - For Ascension custom spells, paste the spell link from chat (Shift+Click)"
	end

	-- Default cooldown to 60 seconds if not specified
	local cd = cooldownDuration or 60

	-- Default class to ALL if not specified
	local selectedClass = classFilter or "ALL"

	-- Spec filter (nil means all specs)
	local selectedSpec = (specFilter and specFilter ~= "NONE" and specFilter ~= "") and specFilter or nil

	-- Get current custom cooldowns table
	local customCooldowns = self:GetCustomCooldownsTable()

	-- Add new entry
	local key = tostring(spellId)
	customCooldowns[key] = {
		spellId = spellId,
		cd = cd,
		texture = texture or "Interface\\Icons\\INV_Misc_QuestionMark",
		spellName = name,
		class = selectedClass,
		spec = selectedSpec,
	}

	-- Save back to string format (this persists!)
	self:SaveCustomCooldownsTable(customCooldowns)
	self.customCooldownsCache = customCooldowns

	-- Register the cooldown in runtime lists
	self:RegisterCustomCooldown(name, cd, spellId, texture, selectedClass, selectedSpec, false)

	-- Enable it by default
	Gladdy.db.cooldownCooldowns[tostring(spellId)] = true

	-- Rebuild the cooldowns options to show in class tab
	if Gladdy.options and Gladdy.options.args["Cooldowns"] then
		Gladdy.options.args["Cooldowns"].args.cooldowns.args = Cooldowns:GetCooldownOptions()
	end

	local classText = selectedClass == "ALL" and "All Classes" or selectedClass
	local specText = selectedSpec and (" - " .. selectedSpec) or ""
	return true, "Added: " .. name .. " (CD: " .. cd .. "s, Class: " .. classText .. specText .. ")"
end

function Cooldowns:RegisterCustomCooldown(spellName, cd, spellId, texture, classFilter, specFilter, skipRefresh)
	local targetClass = classFilter or "ALL"
	local targetSpec = specFilter  -- Can be nil for "all specs"

	-- Add to spell tracking tables
	self.cooldownSpellIds[spellName] = spellId
	self.spellTextures[spellId] = texture or "Interface\\Icons\\INV_Misc_QuestionMark"

	-- Build cooldown value - simple number if no spec, table with spec if spec is specified
	local cooldownValue
	if targetSpec then
		cooldownValue = { cd = cd, spec = targetSpec }
	else
		cooldownValue = cd
	end

	if targetClass == "ALL" then
		-- Add to CUSTOM list (applies to all classes)
		if not Gladdy:GetCooldownList()["CUSTOM"] then
			Gladdy:GetCooldownList()["CUSTOM"] = {}
		end
		Gladdy:GetCooldownList()["CUSTOM"][spellId] = cooldownValue

		-- Add to CUSTOM order table
		if not Gladdy.db.cooldownCooldownsOrder["CUSTOM"] then
			Gladdy.db.cooldownCooldownsOrder["CUSTOM"] = {}
		end
		if not Gladdy.db.cooldownCooldownsOrder["CUSTOM"][tostring(spellId)] then
			Gladdy.db.cooldownCooldownsOrder["CUSTOM"][tostring(spellId)] = tableLength(Gladdy.db.cooldownCooldownsOrder["CUSTOM"]) + 1
		end
	else
		-- Add to specific class list
		if not Gladdy:GetCooldownList()[targetClass] then
			Gladdy:GetCooldownList()[targetClass] = {}
		end
		Gladdy:GetCooldownList()[targetClass][spellId] = cooldownValue

		-- Add to class order table
		if not Gladdy.db.cooldownCooldownsOrder[targetClass] then
			Gladdy.db.cooldownCooldownsOrder[targetClass] = {}
		end
		if not Gladdy.db.cooldownCooldownsOrder[targetClass][tostring(spellId)] then
			Gladdy.db.cooldownCooldownsOrder[targetClass][tostring(spellId)] = tableLength(Gladdy.db.cooldownCooldownsOrder[targetClass]) + 1
		end
	end

	-- Refresh UI if needed
	if not skipRefresh then
		Gladdy:UpdateFrame()
	end
end

function Cooldowns:RemoveCustomCooldown(key)
	-- Key is spellId as string
	local customCooldowns = self:GetCustomCooldownsTable()
	local data = customCooldowns[key]
	if not data then
		return false, "Custom cooldown not found: " .. key
	end

	local spellId = data.spellId
	local spellName = (data.spellName or key):gsub("%%COMMA%%", ",")
	local classFilter = data.class or "ALL"

	-- Remove from table and save
	customCooldowns[key] = nil
	self:SaveCustomCooldownsTable(customCooldowns)
	self.customCooldownsCache = customCooldowns

	-- Remove from cooldown list based on class
	if classFilter == "ALL" then
		if Gladdy:GetCooldownList()["CUSTOM"] then
			Gladdy:GetCooldownList()["CUSTOM"][spellId] = nil
		end
		-- Remove from CUSTOM order
		if Gladdy.db.cooldownCooldownsOrder["CUSTOM"] then
			Gladdy.db.cooldownCooldownsOrder["CUSTOM"][tostring(spellId)] = nil
		end
	else
		-- Remove from class-specific list
		if Gladdy:GetCooldownList()[classFilter] then
			Gladdy:GetCooldownList()[classFilter][spellId] = nil
		end
		-- Remove from class-specific order
		if Gladdy.db.cooldownCooldownsOrder[classFilter] then
			Gladdy.db.cooldownCooldownsOrder[classFilter][tostring(spellId)] = nil
		end
	end

	-- Remove from tracking tables
	self.cooldownSpellIds[spellName] = nil
	self.spellTextures[spellId] = nil

	-- Remove from enabled cooldowns
	Gladdy.db.cooldownCooldowns[tostring(spellId)] = nil

	-- Rebuild the cooldowns options
	if Gladdy.options and Gladdy.options.args["Cooldowns"] then
		Gladdy.options.args["Cooldowns"].args.cooldowns.args = Cooldowns:GetCooldownOptions()
	end

	Gladdy:UpdateFrame()
	return true, "Removed: " .. spellName
end

---------------------
-- Cooldown Duration Helpers
---------------------

-- Get the effective cooldown duration for a spell, considering user overrides
function Cooldowns:GetEffectiveCooldown(spellId, unitClass, spec)
	-- Check for user override first
	local override = Gladdy.db.cooldownDurationOverrides[tostring(spellId)]
	if override and override > 0 then
		return override
	end

	-- Get default cooldown from cooldownList
	local cooldown = Gladdy:GetCooldownList()[unitClass] and Gladdy:GetCooldownList()[unitClass][spellId]
	if not cooldown and Gladdy:GetCooldownList()["CUSTOM"] then
		cooldown = Gladdy:GetCooldownList()["CUSTOM"][spellId]
	end

	if not cooldown then
		return nil
	end

	-- Handle simple number cooldowns
	if type(cooldown) == "number" then
		return cooldown
	end

	-- Handle table cooldowns with spec-specific durations
	if type(cooldown) == "table" then
		if spec and cooldown[spec] then
			return cooldown[spec]
		end
		return cooldown.cd
	end

	return nil
end

-- Get the default (unmodified) cooldown duration for display in options
function Cooldowns:GetDefaultCooldown(spellId, unitClass)
	local cooldown = Gladdy:GetCooldownList()[unitClass] and Gladdy:GetCooldownList()[unitClass][spellId]
	if not cooldown and Gladdy:GetCooldownList()["CUSTOM"] then
		cooldown = Gladdy:GetCooldownList()["CUSTOM"][spellId]
	end

	if not cooldown then
		return 60 -- Default fallback
	end

	if type(cooldown) == "number" then
		return cooldown
	end

	if type(cooldown) == "table" then
		return cooldown.cd or 60
	end

	return 60
end

-- Reset a cooldown override to its default value
function Cooldowns:ResetCooldownOverride(spellId)
	Gladdy.db.cooldownDurationOverrides[tostring(spellId)] = nil
end

---------------------
-- Frame
---------------------

function Cooldowns:CreateFrame(unit)
	local button = Gladdy.buttons[unit]
	local spellCooldownFrame = CreateFrame("Frame", nil, button)
	spellCooldownFrame:EnableMouse(false)
	spellCooldownFrame:SetMovable(true)
	spellCooldownFrame:SetFrameStrata(Gladdy.db.cooldownFrameStrata)
	spellCooldownFrame:SetFrameLevel(Gladdy.db.cooldownFrameLevel)
	spellCooldownFrame.icons = {}
	button.spellCooldownFrame = spellCooldownFrame
	self.frames[unit] = spellCooldownFrame
end

function Cooldowns:CreateIcon()
	local icon
	if (#self.iconCache > 0) then
		icon = tremove(self.iconCache, #self.iconCache)
	else
		icon = CreateFrame("Frame")
		icon:EnableMouse(false)

		icon.texture = icon:CreateTexture(nil, "BACKGROUND")
		-- SetMask is BFA 8.0+ API, not available in 3.3.5 - check existence
		if icon.texture.SetMask then
			icon.texture:SetMask("Interface\\AddOns\\Gladdy\\Images\\mask")
			icon.texture.masked = true
		end
		icon.texture:SetAllPoints(icon)

		icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
		icon.cooldown.noCooldownCount = true
		icon.cooldown:SetReverse(false)
		-- SetHideCountdownNumbers and SetDrawEdge are Cataclysm 4.0+ APIs
		if icon.cooldown.SetHideCountdownNumbers then
			icon.cooldown:SetHideCountdownNumbers(true)
		end
		if icon.cooldown.SetDrawEdge then
			icon.cooldown:SetDrawEdge(true)
		end

		icon.cooldownFrame = CreateFrame("Frame", nil, icon)
		icon.cooldownFrame:ClearAllPoints()
		icon.cooldownFrame:SetAllPoints(icon)

		icon.border = icon.cooldownFrame:CreateTexture(nil, "OVERLAY")
		icon.border:SetAllPoints(icon)

		icon.cooldownFont = icon.cooldownFrame:CreateFontString(nil, "OVERLAY")
		icon.cooldownFont:SetAllPoints(icon)

		icon.glow = CreateFrame("Frame", nil, icon)
		icon.glow:SetAllPoints(icon)

		self:UpdateIcon(icon)
	end
	return icon
end

function Cooldowns:UpdateIcon(icon)
	icon:SetFrameStrata(Gladdy.db.cooldownFrameStrata)
	icon:SetFrameLevel(Gladdy.db.cooldownFrameLevel)
	icon.cooldown:SetFrameStrata(Gladdy.db.cooldownFrameStrata)
	icon.cooldown:SetFrameLevel(Gladdy.db.cooldownFrameLevel + 1)
	icon.cooldownFrame:SetFrameStrata(Gladdy.db.cooldownFrameStrata)
	icon.cooldownFrame:SetFrameLevel(Gladdy.db.cooldownFrameLevel + 2)
	icon.glow:SetFrameStrata(Gladdy.db.cooldownFrameStrata)
	icon.glow:SetFrameLevel(Gladdy.db.cooldownFrameLevel + 3)

	icon:SetHeight(Gladdy.db.cooldownSize)
	icon:SetWidth(Gladdy.db.cooldownSize * Gladdy.db.cooldownWidthFactor)
	icon.cooldownFont:SetFont(Gladdy:SMFetch("font", "cooldownFont"), Gladdy.db.cooldownSize / 2 * Gladdy.db.cooldownFontScale, "OUTLINE")
	icon.cooldownFont:SetTextColor(Gladdy:SetColor(Gladdy.db.cooldownFontColor))

	if Gladdy.db.cooldownIconZoomed then
		icon.cooldown:SetWidth(icon:GetWidth())
		icon.cooldown:SetHeight(icon:GetHeight())
	else
		icon.cooldown:SetWidth(icon:GetWidth() - icon:GetWidth()/16)
		icon.cooldown:SetHeight(icon:GetHeight() - icon:GetHeight()/16)
	end
	icon.cooldown:ClearAllPoints()
	icon.cooldown:SetPoint("CENTER", icon, "CENTER")
	icon.cooldown:SetAlpha(Gladdy.db.cooldownCooldownAlpha)

	icon.cooldownFont:SetFont(Gladdy:SMFetch("font", "cooldownFont"), (icon:GetWidth()/2 - 1) * Gladdy.db.cooldownFontScale, "OUTLINE")
	icon.cooldownFont:SetTextColor(Gladdy:SetColor(Gladdy.db.cooldownFontColor))

	icon.border:SetTexture(Gladdy.db.cooldownBorderStyle)
	icon.border:SetVertexColor(Gladdy:SetColor(Gladdy.db.cooldownBorderColor))

	if Gladdy.db.cooldownIconZoomed then
		if icon.texture.masked then
			-- SetMask is BFA 8.0+ API, check existence
			if icon.texture.SetMask then
				icon.texture:SetMask("")
			end
			icon.texture:SetTexCoord(0.1,0.9,0.1,0.9)
			icon.texture.masked = nil
		end
	else
		if not icon.texture.masked then
			-- SetMask is BFA 8.0+ API, check existence
			if icon.texture.SetMask then
				icon.texture:SetMask("")
				icon.texture:SetTexCoord(0,1,0,1)
				icon.texture:SetMask("Interface\\AddOns\\Gladdy\\Images\\mask")
				icon.texture.masked = true
			else
				icon.texture:SetTexCoord(0,1,0,1)
			end
		end
	end
	if Gladdy.db.cooldownIconDesaturateOnCooldown and icon.active then
		icon.texture:SetDesaturated(true)
	else
		icon.texture:SetDesaturated(false)
	end
	if Gladdy.db.cooldownIconAlphaOnCooldown < 1 and icon.active then
		icon.texture:SetAlpha(Gladdy.db.cooldownIconAlphaOnCooldown)
	else
		icon.texture:SetAlpha(1)
	end
	if icon.timer and not icon.timer:IsCancelled() then
		LCG.PixelGlow_Start(icon.glow, Gladdy:ColorAsArray(Gladdy.db.cooldownIconGlowColor), 12, 0.15, nil, 2)
	end
end

function Cooldowns:IconsSetPoint(button)
	local orderedIcons = {}
	for _,icon in pairs(button.spellCooldownFrame.icons) do
		tinsert(orderedIcons, icon)
	end
	-- Helper to get order for a spellId (check class first, then CUSTOM)
	local function getOrder(spellId)
		local strId = tostring(spellId)
		if Gladdy.db.cooldownCooldownsOrder[button.class] and Gladdy.db.cooldownCooldownsOrder[button.class][strId] then
			return Gladdy.db.cooldownCooldownsOrder[button.class][strId]
		elseif Gladdy.db.cooldownCooldownsOrder["CUSTOM"] and Gladdy.db.cooldownCooldownsOrder["CUSTOM"][strId] then
			return 1000 + Gladdy.db.cooldownCooldownsOrder["CUSTOM"][strId] -- Custom cooldowns appear after class cooldowns
		end
		return 9999 -- Unknown spells at the end
	end
	tbl_sort(orderedIcons, function(a, b)
		return getOrder(a.spellId) < getOrder(b.spellId)
	end)

	for i,icon in ipairs(orderedIcons) do
		icon:SetParent(button.spellCooldownFrame)
		icon:ClearAllPoints()
		if (Gladdy.db.cooldownXGrowDirection == "LEFT") then
			if (i == 1) then
				icon:SetPoint("LEFT", button.spellCooldownFrame, "LEFT", 0, 0)
			elseif (mod(i-1,Gladdy.db.cooldownMaxIconsPerLine) == 0) then
				if (Gladdy.db.cooldownYGrowDirection == "DOWN") then
					icon:SetPoint("TOP", orderedIcons[i-Gladdy.db.cooldownMaxIconsPerLine], "BOTTOM", 0, -Gladdy.db.cooldownIconPadding)
				else
					icon:SetPoint("BOTTOM", orderedIcons[i-Gladdy.db.cooldownMaxIconsPerLine], "TOP", 0, Gladdy.db.cooldownIconPadding)
				end
			else
				icon:SetPoint("RIGHT", orderedIcons[i-1], "LEFT", -Gladdy.db.cooldownIconPadding, 0)
			end
		end
		if (Gladdy.db.cooldownXGrowDirection == "RIGHT") then
			if (i == 1) then
				icon:SetPoint("LEFT", button.spellCooldownFrame, "LEFT", 0, 0)
			elseif (mod(i-1,Gladdy.db.cooldownMaxIconsPerLine) == 0) then
				if (Gladdy.db.cooldownYGrowDirection == "DOWN") then
					icon:SetPoint("TOP", orderedIcons[i-Gladdy.db.cooldownMaxIconsPerLine], "BOTTOM", 0, -Gladdy.db.cooldownIconPadding)
				else
					icon:SetPoint("BOTTOM", orderedIcons[i-Gladdy.db.cooldownMaxIconsPerLine], "TOP", 0, Gladdy.db.cooldownIconPadding)
				end
			else
				icon:SetPoint("LEFT", orderedIcons[i-1], "RIGHT", Gladdy.db.cooldownIconPadding, 0)
			end
		end
	end
end

function Cooldowns:UpdateFrameOnce()
	for _,icon in ipairs(self.iconCache) do
		Cooldowns:UpdateIcon(icon)
	end
end

function Cooldowns:UpdateFrame(unit)
	local button = Gladdy.buttons[unit]
	local testAgain = false
	if (Gladdy.db.cooldown) then
		button.spellCooldownFrame:SetHeight(Gladdy.db.cooldownSize)
		button.spellCooldownFrame:SetWidth(1)
		button.spellCooldownFrame:SetFrameStrata(Gladdy.db.cooldownFrameStrata)
		button.spellCooldownFrame:SetFrameLevel(Gladdy.db.cooldownFrameLevel)

		Gladdy:SetPosition(button.spellCooldownFrame, unit, "cooldownXOffset", "cooldownYOffset", Cooldowns:LegacySetPosition(button, unit), Cooldowns)

		if (unit == "arena1") then
			Gladdy:CreateMover(button.spellCooldownFrame,"cooldownXOffset", "cooldownYOffset", L["Cooldown"],
					{"TOPLEFT", "TOPLEFT"},
					Gladdy.db.cooldownSize * Gladdy.db.cooldownWidthFactor, Gladdy.db.cooldownSize, 0, 0, "cooldown")
		end

		if (Gladdy.db.cooldownGroup) then
			--TODO fix overlapping
			if (unit ~= "arena1") then
				local previousUnit = "arena" .. string.gsub(unit, "arena", "") - 1
				self.frames[unit]:ClearAllPoints()
				self.frames[unit]:SetPoint("TOP", self.frames[previousUnit], "BOTTOM", 0, -Gladdy.db.cooldownIconPadding)
			end
		end

		-- Update each cooldown icon
		for _,icon in pairs(button.spellCooldownFrame.icons) do
			testAgain = icon.texture.masked
			self:UpdateIcon(icon)
			if icon.texture.masked ~= testAgain then
				testAgain = true
			else
				testAgain = false
			end
		end
		self:IconsSetPoint(button)
		button.spellCooldownFrame:Show()
	else
		button.spellCooldownFrame:Hide()
	end
	if testAgain and Gladdy.frame.testing then
		Cooldowns:ResetUnit(unit)
		Cooldowns:ENEMY_SPOTTED(unit)
		Cooldowns:UNIT_SPEC(unit)
		Cooldowns:Test(unit)
	end
end

function Cooldowns:ResetUnit(unit)
	local button = Gladdy.buttons[unit]
	if not button then
		return
	end
	for i=#button.spellCooldownFrame.icons,1,-1 do
		self:ClearIcon(button, i)
	end
end

function Cooldowns:ClearIcon(button, index, spellId, icon)
	if index then
		icon = tremove(button.spellCooldownFrame.icons, index)
	else
		for i=#button.spellCooldownFrame.icons,1,-1 do
			if icon then
				if button.spellCooldownFrame.icons[i] == icon then
					icon = tremove(button.spellCooldownFrame.icons, index)
				end
			end
			if not icon and spellId then
				if button.spellCooldownFrame.icons[i].spellId == spellId then
					icon = tremove(button.spellCooldownFrame.icons, index)
				end
			end
		end
	end
	icon:Show()
	LCG.PixelGlow_Stop(icon.glow)
	if icon.timer then
		icon.timer:Cancel()
	end
	icon:ClearAllPoints()
	icon:SetParent(nil)
	icon:Hide()
	icon.spellId = nil
	icon.active = false
	icon.cooldown:Hide()
	icon.cooldownFont:SetText("")
	icon:SetScript("OnUpdate", nil)
	tinsert(self.iconCache, icon)
end

---------------------
-- Test
---------------------

-- /run LibStub("Gladdy").modules["Cooldowns"]:AURA_GAIN(_, AURA_TYPE_BUFF, 22812, "Barkskin", _, 20, _, _, _, _, "arena1", true)
-- /run LibStub("Gladdy").modules["Cooldowns"]:AURA_FADE("arena1", 22812)
function Cooldowns:Test(unit)
	if Gladdy.frame.testing then
		self:UpdateTestCooldowns(unit)
	end
	Cooldowns:AURA_GAIN(_, AURA_TYPE_BUFF, 22812, "Barkskin", _, 20, _, _, _, _, unit, true)
end

function Cooldowns:UpdateTestCooldowns(unit)
	local button = Gladdy.buttons[unit]
	local orderedIcons = {}

	for _,icon in pairs(button.spellCooldownFrame.icons) do
		tinsert(orderedIcons, icon)
	end
	-- Helper to get order for a spellId (check class first, then CUSTOM)
	local function getOrder(spellId)
		local strId = tostring(spellId)
		if Gladdy.db.cooldownCooldownsOrder[button.class] and Gladdy.db.cooldownCooldownsOrder[button.class][strId] then
			return Gladdy.db.cooldownCooldownsOrder[button.class][strId]
		elseif Gladdy.db.cooldownCooldownsOrder["CUSTOM"] and Gladdy.db.cooldownCooldownsOrder["CUSTOM"][strId] then
			return 1000 + Gladdy.db.cooldownCooldownsOrder["CUSTOM"][strId]
		end
		return 9999
	end
	tbl_sort(orderedIcons, function(a, b)
		return getOrder(a.spellId) < getOrder(b.spellId)
	end)

	for _,icon in ipairs(orderedIcons) do
		if icon.timer then
			icon.timer:Cancel()
		end
		self:CooldownUsed(unit, button.class, icon.spellId)
	end
end

---------------------
-- Events
---------------------

function Cooldowns:ENEMY_SPOTTED(unit)
	if (not Gladdy.buttons[unit]) then
		return
	end
	self:UpdateCooldowns(Gladdy.buttons[unit])
end

function Cooldowns:UNIT_SPEC(unit)
	if (not Gladdy.buttons[unit]) then
		return
	end
	self:UpdateCooldowns(Gladdy.buttons[unit])
end

function Cooldowns:UNIT_DESTROYED(unit)
	-- Don't reset cooldowns if unit still exists (just stealthed, not actually gone)
	-- Ascension fix: UNIT_DESTROYED may fire for stealth instead of unseen
	if UnitExists(unit) then
		return
	end
	self:ResetUnit(unit)
end

function Cooldowns:AURA_GAIN(_, auraType, spellID, spellName, _, duration, _, _, _, _, unitCaster, test)
	local arenaUnit = test and unitCaster or Gladdy:GetArenaUnit(unitCaster, true)
	if not Gladdy.db.cooldownIconGlow or not arenaUnit or not Gladdy.buttons[arenaUnit] or auraType ~= AURA_TYPE_BUFF or spellID == 26889 then
		return
	end
	local cooldownFrame = Gladdy.buttons[arenaUnit].spellCooldownFrame

	local spellId = Cooldowns.cooldownSpellIds[spellName] -- don't use spellId from combatlog, in case of different spellrank
	if spellID == 16188 or spellID == 17116 then -- Nature's Swiftness (same name for druid and shaman)
		spellId = spellID
	end

	for _,icon in pairs(cooldownFrame.icons) do
		if (icon.spellId == spellId) then
			Gladdy:Debug("INFO", "Cooldowns:AURA_GAIN", "PixelGlow_Start", spellID)
			LCG.PixelGlow_Start(icon.glow, Gladdy:ColorAsArray(Gladdy.db.cooldownIconGlowColor), 12, 0.15, nil, 2)
			if icon.timer then
				icon.timer:Cancel()
			end
			icon.timer = C_Timer.NewTimer(duration, function()
				LCG.PixelGlow_Stop(icon.glow)
				icon.timer:Cancel()
			end)
		end
	end
end

function Cooldowns:AURA_FADE(unit, spellID)
	if not Gladdy.buttons[unit] or Gladdy.buttons[unit].stealthed then
		return
	end
	local cooldownFrame = Gladdy.buttons[unit].spellCooldownFrame
	for _,icon in pairs(cooldownFrame.icons) do
		if (icon.spellId == spellID) then
			Gladdy:Debug("INFO", "Cooldowns:AURA_FADE", "LCG.ButtonGlow_Stop")
			if icon.timer then
				icon.timer:Cancel()
			end
			LCG.PixelGlow_Stop(icon.glow)
		end
	end
end

---------------------
-- Cooldown Start/Ready
---------------------

function Cooldowns:CooldownStart(button, spellId, duration, start)
	if not duration or duration == nil or type(duration) ~= "number" then
		return
	end
	-- Check class cooldowns first, then custom cooldowns
	local cooldown = Gladdy:GetCooldownList()[button.class] and Gladdy:GetCooldownList()[button.class][spellId]
	if not cooldown and Gladdy:GetCooldownList()["CUSTOM"] then
		cooldown = Gladdy:GetCooldownList()["CUSTOM"][spellId]
	end
	if type(cooldown) == "table" then
		if (button.spec ~= nil and cooldown[button.spec] ~= nil) then
			cooldown = cooldown[button.spec]
		else
			cooldown = cooldown.cd
		end
	end
	for _,icon in pairs(button.spellCooldownFrame.icons) do
		if (icon.spellId == spellId) then
			if not start and icon.active and icon.timeLeft > cooldown/2 then
				return -- do not trigger cooldown again
			end
			icon.active = true
			icon.timeLeft = start and start - GetTime() + duration or duration
			if (not Gladdy.db.cooldownDisableCircle) then icon.cooldown:SetCooldown(start or GetTime(), duration) end
			if Gladdy.db.cooldownIconDesaturateOnCooldown then
				icon.texture:SetDesaturated(true)
			end
			if Gladdy.db.cooldownIconAlphaOnCooldown < 1 then
				icon.texture:SetAlpha(Gladdy.db.cooldownIconAlphaOnCooldown)
			end
			icon:SetScript("OnUpdate", function(self, elapsed)
				self.timeLeft = self.timeLeft - elapsed
				local timeLeft = ceil(self.timeLeft)
				if timeLeft >= 540 then
					self.cooldownFont:SetFont(Gladdy:SMFetch("font", "cooldownFont"), Gladdy.db.cooldownSize / 3.1 * Gladdy.db.cooldownFontScale, "OUTLINE")
				elseif timeLeft < 540 and timeLeft >= 60 then
					self.cooldownFont:SetFont(Gladdy:SMFetch("font", "cooldownFont"), Gladdy.db.cooldownSize / 2.15 * Gladdy.db.cooldownFontScale, "OUTLINE")
				elseif timeLeft < 60 and timeLeft > 0 then
					self.cooldownFont:SetFont(Gladdy:SMFetch("font", "cooldownFont"), Gladdy.db.cooldownSize / 2.15 * Gladdy.db.cooldownFontScale, "OUTLINE")
				end
				Gladdy:FormatTimer(self.cooldownFont, self.timeLeft, self.timeLeft < 0)
				if (self.timeLeft <= 0) then
					Cooldowns:CooldownReady(button, spellId, icon)
				end
				if (self.timeLeft <= 0) then
					Cooldowns:CooldownReady(button, spellId, icon)
				end
			end)
			break
			--C_VoiceChat.SpeakText(2, GetSpellInfo(spellId), 3, 4, 100)
		end
	end
end

local function resetIcon(icon)
	if Gladdy.db.cooldownIconDesaturateOnCooldown then
		icon.texture:SetDesaturated(false)
	end
	if Gladdy.db.cooldownIconAlphaOnCooldown < 1 then
		icon.texture:SetAlpha(1)
	end
	icon.active = false
	icon.cooldown:Hide()
	icon.cooldownFont:SetText("")
	icon:SetScript("OnUpdate", nil)
	if icon.timer then
		icon.timer:Cancel()
	end
	LCG.PixelGlow_Stop(icon.glow)
end

function Cooldowns:CooldownReady(button, spellId, frame)
	if (frame == false) then
		for _,icon in pairs(button.spellCooldownFrame.icons) do
			if (icon.spellId == spellId) then
				resetIcon(icon)
			end
		end
	else
		resetIcon(frame)
	end
end

function Cooldowns:CooldownUsed(unit, unitClass, spellId, expirationTimeInSeconds)
	local button = Gladdy.buttons[unit]
	if not button then
		return
	end

	-- Check class cooldowns first, then custom cooldowns
	local cooldown = Gladdy:GetCooldownList()[unitClass] and Gladdy:GetCooldownList()[unitClass][spellId]
	if not cooldown and Gladdy:GetCooldownList()["CUSTOM"] then
		cooldown = Gladdy:GetCooldownList()["CUSTOM"][spellId]
	end
	if (cooldown) then
		local cd = cooldown
		if (type(cooldown) == "table") then
			-- return if the spec doesn't have a cooldown for this spell
			if (button.spec ~= nil and cooldown.notSpec ~= nil and button.spec == cooldown.notSpec) then
				return
			end

			-- check if we need to reset other cooldowns because of this spell
			if (cooldown.resetCD ~= nil) then
				for spellID,_ in pairs(cooldown.resetCD) do
					self:CooldownReady(button, spellID, false)
				end
			end

			-- check if there is a special cooldown for the units spec
			if (button.spec ~= nil and cooldown[button.spec] ~= nil) then
				cd = cooldown[button.spec]
			else
				cd = cooldown.cd
			end

			-- check if there is a shared cooldown with an other spell
			if (cooldown.sharedCD ~= nil) then
				local sharedCD = cooldown.sharedCD.cd and cooldown.sharedCD.cd or cd

				for spellID,_ in pairs(cooldown.sharedCD) do
					if (spellID ~= "cd") then
						local skip = false
						for _,icon in pairs(button.spellCooldownFrame.icons) do
							if (icon.spellId == spellID and icon.active and icon.timeLeft > sharedCD) then
								skip = true
								break
							end
						end
						if not skip then
							-- Check for user override on shared cooldowns
							local sharedOverride = Gladdy.db.cooldownDurationOverrides[tostring(spellID)]
							self:CooldownStart(button, spellID, sharedOverride or sharedCD)
						end
					end
				end
			end
		end

		-- Check for user override on main cooldown duration
		local cdOverride = Gladdy.db.cooldownDurationOverrides[tostring(spellId)]
		local effectiveCD = cdOverride or cd

		if (Gladdy.db.cooldown) then
			-- start cooldown with effective duration (user override or default)
			self:CooldownStart(button, spellId, effectiveCD, expirationTimeInSeconds and (GetTime() + expirationTimeInSeconds - effectiveCD) or nil)
		end

		--[[ announcement
		if (self.db.cooldownAnnounce or self.db.cooldownAnnounceList[spellId] or self.db.cooldownAnnounceList[unitClass]) then
		   self:SendAnnouncement(string.format(L["COOLDOWN USED: %s (%s) used %s - %s sec. cooldown"], UnitName(unit), UnitClass(unit), spellName, cd), RAID_CLASS_COLORS[UnitClass(unit)], self.db.cooldownAnnounceList[spellId] and self.db.cooldownAnnounceList[spellId] or self.db.announceType)
		end]]

		--[[ sound file
		if (db.cooldownSoundList[spellId] ~= nil and db.cooldownSoundList[spellId] ~= "disabled") then
		   PlaySoundFile(LSM:Fetch(LSM.MediaType.SOUND, db.cooldownSoundList[spellId]))
		end  ]]
	end
end

---------------------
-- Update Cooldowns
---------------------

function Cooldowns:AddCooldown(spellID, value, button)
	-- see if we have shared cooldowns without a cooldown defined
	-- e.g. hunter traps have shared cooldowns, so only display one trap instead all of them
	local sharedCD = false
	if (type(value) == "table" and value.sharedCD ~= nil and value.sharedCD.cd == nil) then
		for spellId, _ in pairs(value.sharedCD) do
			for _,icon in pairs(button.spellCooldownFrame.icons) do
				if (icon.spellId == spellId) then
					sharedCD = true
					break
				end
			end
		end
	end
	for _,icon in pairs(button.spellCooldownFrame.icons) do
		if (icon and icon.spellId == spellID) then
			sharedCD = true
			break
		end
	end
	if (not sharedCD) then
		local icon = self:CreateIcon()
		icon:Show()
		icon.spellId = spellID
		icon.texture:SetTexture(self.spellTextures[spellID])
		tinsert(button.spellCooldownFrame.icons, icon)
		self:IconsSetPoint(button)
	end
end

function Cooldowns:UpdateCooldowns(button)
	local class = button.class
	local race = button.race
	local spec = button.spec
	if not class or not race then
		return
	end

	for k, v in pairs(Gladdy:GetCooldownList()[class]) do
		if Gladdy.db.cooldownCooldowns[tostring(k)] then
			if (type(v) ~= "table" or (type(v) == "table" and v.spec == nil)) then
				Cooldowns:AddCooldown(k, v, button)
			end
			if (type(v) == "table" and v.spec ~= nil and v.spec == spec) then
				Cooldowns:AddCooldown(k, v, button)
			end
		end
	end
	for k, v in pairs(Gladdy:GetCooldownList()[race]) do
		if Gladdy.db.cooldownCooldowns[tostring(k)] then
			if (type(v) ~= "table" or (type(v) == "table" and v.spec == nil)) then
				Cooldowns:AddCooldown(k, v, button)
			end
			if (type(v) == "table" and v.spec ~= nil and v.spec == spec) then
				Cooldowns:AddCooldown(k, v, button)
			end
		end
	end
	-- Add custom cooldowns (apply to all units)
	if Gladdy:GetCooldownList()["CUSTOM"] then
		for k, v in pairs(Gladdy:GetCooldownList()["CUSTOM"]) do
			if Gladdy.db.cooldownCooldowns[tostring(k)] then
				Cooldowns:AddCooldown(k, v, button)
			end
		end
	end
end

---------------------
-- Options
---------------------

function Cooldowns:GetOptions()
	return {
		headerCooldown = {
			type = "header",
			name = L["Cooldown"],
			order = 2,
		},
		cooldown = Gladdy:option({
			type = "toggle",
			name = L["Enabled"],
			desc = L["Enabled cooldown module"],
			order = 2,
		}),
		cooldownGroup = Gladdy:option({
			type = "toggle",
			name = L["Group"] .. " " .. L["Cooldown"],
			order = 3,
			disabled = function() return not Gladdy.db.cooldown end,
		}),
		group = {
			type = "group",
			childGroups = "tree",
			name = L["Frame"],
			order = 3,
			disabled = function() return not Gladdy.db.cooldown end,
			args = {
				icon = {
					type = "group",
					name = L["Icon"],
					order = 1,
					args = {
						headerIcon = {
							type = "header",
							name = L["Icon"],
							order = 2,
						},
						cooldownIconZoomed = Gladdy:option({
							type = "toggle",
							name = L["Zoomed Icon"],
							desc = L["Zoomes the icon to remove borders"],
							order = 4,
							width = "full",
						}),
						cooldownSize = Gladdy:option({
							type = "range",
							name = L["Cooldown size"],
							desc = L["Size of each cd icon"],
							order = 5,
							min = 5,
							max = 50,
							width = "full",
						}),
						cooldownWidthFactor = Gladdy:option({
							type = "range",
							name = L["Icon Width Factor"],
							desc = L["Stretches the icon"],
							order = 6,
							min = 0.5,
							max = 2,
							step = 0.05,
							width = "full",
						}),
						cooldownIconPadding = Gladdy:option({
							type = "range",
							name = L["Icon Padding"],
							desc = L["Space between Icons"],
							order = 7,
							min = 0,
							max = 10,
							step = 0.1,
							width = "full",
						}),
					},
				},
				cooldown = {
					type = "group",
					name = L["Cooldown"],
					order = 2,
					args = {
						header = {
							type = "header",
							name = L["Cooldown"],
							order = 2,
						},
						cooldownIconDesaturateOnCooldown = Gladdy:option({
							type = "toggle",
							name = L["Desaturate Icon"],
							order = 5,
							width = "full",
						}),
						cooldownIconAlphaOnCooldown = Gladdy:option({
							type = "range",
							name = L["Cooldown alpha on CD"],
							desc = L["Alpha of the icon when cooldown active"],
							desc = L["changes "],
							order = 6,
							min = 0,
							max = 1,
							step = 0.1,
							width = "full",
						}),
						headerCircle = {
							type = "header",
							name = L["Cooldowncircle"],
							order = 10,
						},
						cooldownDisableCircle = Gladdy:option({
							type = "toggle",
							name = L["No Cooldown Circle"],
							order = 11,
							width = "full",
						}),
						cooldownCooldownAlpha = Gladdy:option({
							type = "range",
							name = L["Cooldown circle alpha"],
							min = 0,
							max = 1,
							step = 0.1,
							order = 12,
							width = "full",
						}),
						cooldownCooldownNumberAlpha = {
							type = "range",
							name = L["Cooldown number alpha"],
							min = 0,
							max = 1,
							step = 0.1,
							order = 13,
							width = "full",
							set = function(info, value)
								Gladdy.db.cooldownFontColor.a = value
								Gladdy:UpdateFrame()
							end,
							get = function(info)
								return Gladdy.db.cooldownFontColor.a
							end,
						},
					},
				},
				glow = {
					type = "group",
					name = L["Glow"],
					order = 3,
					args = {
						header = {
							type = "header",
							name = L["Glow"],
							order = 1,
						},
						cooldownIconGlow = Gladdy:option({
							type = "toggle",
							name = L["Glow Icon"],
							desc = L["Glow the icon when cooldown active"],
							order = 2,
							width = "full",
						}),
						cooldownIconGlowColor = Gladdy:colorOption({
							disabled = function() return not Gladdy.db.cooldownIconGlow end,
							type = "color",
							hasAlpha = true,
							name = L["Glow color"],
							desc = L["Color of the glow"],
							order = 3,
							width = "full",
						}),
						resetGlow = {
							type = "execute",
							name = L["Reset Glow"],
							desc = L["Reset Glow Color"],
							func = function()
								Gladdy.db.cooldownIconGlowColor = {r = 0.95, g = 0.95, b = 0.32, a = 1}
								Gladdy:UpdateFrame()
							end,
							order = 3,
						}
					},
				},
				font = {
					type = "group",
					name = L["Font"],
					order = 4,
					args = {
						header = {
							type = "header",
							name = L["Font"],
							order = 2,
						},
						cooldownFont = Gladdy:option({
							type = "select",
							name = L["Font"],
							desc = L["Font of the cooldown"],
							order = 11,
							dialogControl = "LSM30_Font",
							values = AceGUIWidgetLSMlists.font,
						}),
						cooldownFontScale = Gladdy:option({
							type = "range",
							name = L["Font scale"],
							desc = L["Scale of the font"],
							order = 12,
							min = 0.1,
							max = 2,
							step = 0.1,
							width = "full",
						}),
						cooldownFontColor = Gladdy:colorOption({
							type = "color",
							name = L["Font color"],
							desc = L["Color of the text"],
							order = 13,
							hasAlpha = true,
						}),
					},
				},
				position = {
					type = "group",
					name = L["Position"],
					order = 6,
					args = {
						header = {
							type = "header",
							name = L["Position"],
							order = 2,
						},
						cooldownYGrowDirection = Gladdy:option({
							type = "select",
							name = L["Vertical Grow Direction"],
							desc = L["Vertical Grow Direction of the cooldown icons"],
							order = 3,
							values = {
								["UP"] = L["Up"],
								["DOWN"] = L["Down"],
							},
						}),
						cooldownXGrowDirection = Gladdy:option({
							type = "select",
							name = L["Horizontal Grow Direction"],
							desc = L["Horizontal Grow Direction of the cooldown icons"],
							order = 4,
							values = {
								["LEFT"] = L["Left"],
								["RIGHT"] = L["Right"],
							},
						}),
						cooldownMaxIconsPerLine = Gladdy:option({
							type = "range",
							name = L["Max Icons per row"],
							order = 5,
							min = 3,
							max = 14,
							step = 1,
							width = "full",
						}),
						headerOffset = {
							type = "header",
							name = L["Offset"],
							order = 10,
						},
						cooldownXOffset = Gladdy:option({
							type = "range",
							name = L["Horizontal offset"],
							order = 11,
							min = -400,
							max = 400,
							step = 0.1,
							width = "full",
						}),
						cooldownYOffset = Gladdy:option({
							type = "range",
							name = L["Vertical offset"],
							order = 12,
							min = -400,
							max = 400,
							step = 0.1,
							width = "full",
						}),
					},
				},
				border = {
					type = "group",
					name = L["Border"],
					order = 5,
					args = {
						header = {
							type = "header",
							name = L["Border"],
							order = 2,
						},
						cooldownBorderStyle = Gladdy:option({
							type = "select",
							name = L["Border style"],
							order = 31,
							values = Gladdy:GetIconStyles()
						}),
						cooldownBorderColor = Gladdy:colorOption({
							type = "color",
							name = L["Border color"],
							desc = L["Color of the border"],
							order = 32,
							hasAlpha = true,
						}),
					},
				},
				frameStrata = {
					type = "group",
					name = L["Frame Strata and Level"],
					order = 7,
					args = {
						headerAuraLevel = {
							type = "header",
							name = L["Frame Strata and Level"],
							order = 1,
						},
						cooldownFrameStrata = Gladdy:option({
							type = "select",
							name = L["Frame Strata"],
							order = 2,
							values = Gladdy.frameStrata,
							sorting = Gladdy.frameStrataSorting,
							width = "full",
						}),
						cooldownFrameLevel = Gladdy:option({
							type = "range",
							name = L["Frame Level"],
							min = 0,
							max = 500,
							step = 1,
							order = 3,
							width = "full",
						}),
					},
				},
			},
		},
		cooldowns = {
			type = "group",
			childGroups = "tree",
			name = L["Cooldowns"],
			order = 4,
			disabled = function() return not Gladdy.db.cooldown end,
			args = Cooldowns:GetCooldownOptions(),
		},
		customCooldowns = {
			type = "group",
			name = L["Custom Cooldowns"] or "Custom Cooldowns",
			order = 5,
			disabled = function() return not Gladdy.db.cooldown end,
			args = {
				header = {
					type = "header",
					name = L["Add Custom Cooldown"] or "Add Custom Cooldown",
					order = 1,
				},
				description = {
					type = "description",
					name = L["Enter a spell name to track its cooldown. The spell must exist in the game."] or "Enter a spell name to track its cooldown. The spell must exist in the game.",
					order = 2,
				},
				spellNameInput = {
					type = "input",
					name = L["Spell Name"] or "Spell Name",
					desc = L["Enter the exact spell name (e.g., 'Bladestorm')"] or "Enter the exact spell name (e.g., 'Bladestorm')",
					order = 3,
					width = "full",
					get = function() return Gladdy.db.customCooldownInput or "" end,
					set = function(_, value) Gladdy.db.customCooldownInput = value end,
				},
				cooldownInput = {
					type = "input",
					name = L["Cooldown (seconds)"] or "Cooldown (seconds)",
					desc = L["Enter the cooldown duration in seconds (default: 60)"] or "Enter the cooldown duration in seconds (default: 60)",
					order = 4,
					width = "normal",
					get = function() return Gladdy.db.customCooldownDuration or "60" end,
					set = function(_, value) Gladdy.db.customCooldownDuration = value end,
				},
				classSelect = {
					type = "select",
					name = L["Class Filter"] or "Class Filter",
					desc = L["Select which class this cooldown applies to"] or "Select which class this cooldown applies to",
					order = 4.5,
					width = "normal",
					values = {
						["ALL"] = "All Classes",
						["WARRIOR"] = LOCALIZED_CLASS_NAMES_MALE["WARRIOR"] or "Warrior",
						["PALADIN"] = LOCALIZED_CLASS_NAMES_MALE["PALADIN"] or "Paladin",
						["HUNTER"] = LOCALIZED_CLASS_NAMES_MALE["HUNTER"] or "Hunter",
						["ROGUE"] = LOCALIZED_CLASS_NAMES_MALE["ROGUE"] or "Rogue",
						["PRIEST"] = LOCALIZED_CLASS_NAMES_MALE["PRIEST"] or "Priest",
						["DEATHKNIGHT"] = LOCALIZED_CLASS_NAMES_MALE["DEATHKNIGHT"] or "Death Knight",
						["SHAMAN"] = LOCALIZED_CLASS_NAMES_MALE["SHAMAN"] or "Shaman",
						["MAGE"] = LOCALIZED_CLASS_NAMES_MALE["MAGE"] or "Mage",
						["WARLOCK"] = LOCALIZED_CLASS_NAMES_MALE["WARLOCK"] or "Warlock",
						["DRUID"] = LOCALIZED_CLASS_NAMES_MALE["DRUID"] or "Druid",
					},
					sorting = {"ALL", "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID"},
					get = function() return Gladdy.db.customCooldownClass or "ALL" end,
					set = function(_, value)
						Gladdy.db.customCooldownClass = value
						-- Reset spec when class changes
						Gladdy.db.customCooldownSpec = "NONE"
						LibStub("AceConfigRegistry-3.0"):NotifyChange("Gladdy")
					end,
				},
				specSelect = {
					type = "select",
					name = L["Specialization"] or "Specialization",
					desc = L["Select which specialization this cooldown applies to (optional)"] or "Select which specialization this cooldown applies to (optional). Leave as 'All Specs' if the cooldown should show for all specs of the selected class.",
					order = 4.6,
					width = "normal",
					values = function()
						local selectedClass = Gladdy.db.customCooldownClass or "ALL"
						local specs = getSpecsForClass(selectedClass)
						local values = { ["NONE"] = L["All Specs"] or "All Specs" }
						if specs then
							for _, specName in ipairs(specs) do
								values[specName] = specName
							end
						end
						return values
					end,
					sorting = function()
						local selectedClass = Gladdy.db.customCooldownClass or "ALL"
						local specs = getSpecsForClass(selectedClass)
						local sorting = { "NONE" }
						if specs then
							for _, specName in ipairs(specs) do
								tinsert(sorting, specName)
							end
						end
						return sorting
					end,
					disabled = function()
						local selectedClass = Gladdy.db.customCooldownClass or "ALL"
						return selectedClass == "ALL"
					end,
					get = function() return Gladdy.db.customCooldownSpec or "NONE" end,
					set = function(_, value) Gladdy.db.customCooldownSpec = value end,
				},
				addButton = {
					type = "execute",
					name = L["Add Cooldown"] or "Add Cooldown",
					order = 5,
					func = function()
						local spellName = Gladdy.db.customCooldownInput
						local cd = tonumber(Gladdy.db.customCooldownDuration) or 60
						local classFilter = Gladdy.db.customCooldownClass or "ALL"
						local specFilter = Gladdy.db.customCooldownSpec
						-- Don't pass spec if class is ALL or spec is NONE
						if classFilter == "ALL" or specFilter == "NONE" or specFilter == "" then
							specFilter = nil
						end
						local success, msg = Cooldowns:AddCustomCooldown(spellName, cd, classFilter, specFilter)
						if success then
							Gladdy.db.customCooldownInput = ""
							Gladdy.db.customCooldownSpec = "NONE"
							DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Gladdy]|r " .. msg)
							-- Refresh the custom list display
							if Gladdy.options and Gladdy.options.args["Cooldowns"] then
								Gladdy.options.args["Cooldowns"].args.customCooldowns.args.customList.args = Cooldowns:GetCustomCooldownListOptions()
							end
							LibStub("AceConfigRegistry-3.0"):NotifyChange("Gladdy")
						else
							DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[Gladdy]|r " .. msg)
						end
					end,
				},
				headerList = {
					type = "header",
					name = L["Custom Cooldowns List"] or "Custom Cooldowns List",
					order = 10,
				},
				customList = {
					type = "group",
					name = "",
					order = 11,
					inline = true,
					args = {},
					-- Dynamic args using a plugin callback
				},
				refreshList = {
					type = "execute",
					name = L["Refresh List"] or "Refresh List",
					order = 12,
					func = function()
						-- Force rebuild both custom list and cooldowns tabs
						Gladdy.options.args["Cooldowns"].args.customCooldowns.args.customList.args = Cooldowns:GetCustomCooldownListOptions()
						Gladdy.options.args["Cooldowns"].args.cooldowns.args = Cooldowns:GetCooldownOptions()
						LibStub("AceConfigRegistry-3.0"):NotifyChange("Gladdy")
					end,
				},
				debugCustom = {
					type = "execute",
					name = "Debug: Show Stored",
					order = 13,
					func = function()
						DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Gladdy Custom Cooldowns]|r")
						DEFAULT_CHAT_FRAME:AddMessage("Stored string: " .. (Gladdy.db.customCooldownsString or "empty"))
						local customCooldowns = Cooldowns:GetCustomCooldownsTable()
						local count = 0
						for key, data in pairs(customCooldowns) do
							count = count + 1
							local name = (data.spellName or "Unknown"):gsub("%%COMMA%%", ",")
							local specInfo = data.spec and (", Spec: " .. data.spec) or ""
							DEFAULT_CHAT_FRAME:AddMessage("  " .. count .. ". " .. name .. " (ID: " .. tostring(data.spellId) .. ", CD: " .. tostring(data.cd) .. "s, Class: " .. (data.class or "ALL") .. specInfo .. ")")
						end
						if count == 0 then
							DEFAULT_CHAT_FRAME:AddMessage("  No custom cooldowns stored.")
						end
						-- Also check CUSTOM list
						if Gladdy:GetCooldownList()["CUSTOM"] then
							DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[CUSTOM Cooldown List (Runtime)]|r")
							for spellId, cdData in pairs(Gladdy:GetCooldownList()["CUSTOM"]) do
								if type(cdData) == "table" then
									local specInfo = cdData.spec and (", Spec: " .. cdData.spec) or ""
									DEFAULT_CHAT_FRAME:AddMessage("  SpellID: " .. tostring(spellId) .. " -> CD: " .. tostring(cdData.cd) .. specInfo)
								else
									DEFAULT_CHAT_FRAME:AddMessage("  SpellID: " .. tostring(spellId) .. " -> CD: " .. tostring(cdData))
								end
							end
						end
					end,
				},
			},
		},
	}
end

function Cooldowns:GetCustomCooldownListOptions()
	local options = {}
	local order = 1

	-- Class colors for display
	local CLASS_COLORS = {
		["WARRIOR"] = "|cffc79c6e",
		["PALADIN"] = "|cfff58cba",
		["HUNTER"] = "|cffabd473",
		["ROGUE"] = "|cfffff569",
		["PRIEST"] = "|cffffffff",
		["DEATHKNIGHT"] = "|cffc41f3b",
		["SHAMAN"] = "|cff0070de",
		["MAGE"] = "|cff69ccf0",
		["WARLOCK"] = "|cff9482c9",
		["DRUID"] = "|cffff7d0a",
		["ALL"] = "|cff00ff00",
	}

	-- Use the new string-based storage
	local customCooldowns = self:GetCustomCooldownsTable()

	for key, data in pairs(customCooldowns) do
		local texture = (data.texture or "Interface\\Icons\\INV_Misc_QuestionMark"):gsub("%%COMMA%%", ",")
		local spellId = data.spellId or key
		local spellName = (data.spellName or ("Spell " .. key)):gsub("%%COMMA%%", ",")
		local cd = data.cd or 60
		local classFilter = data.class or "ALL"
		local specFilter = data.spec
		local classColor = CLASS_COLORS[classFilter] or "|cff00ff00"
		local classDisplay = classFilter == "ALL" and "All Classes" or classFilter
		local specDisplay = specFilter and ("|cffaaaaaa - " .. specFilter .. "|r") or ""

		options["spell_" .. key] = {
			type = "group",
			name = "",
			inline = true,
			order = order,
			args = {
				icon = {
					type = "description",
					name = "|T" .. texture .. ":24|t",
					order = 1,
					width = 0.15,
				},
				info = {
					type = "description",
					name = "|cffffd100" .. spellName .. "|r\n" ..
						   "|cff888888Spell ID:|r " .. tostring(spellId) .. "\n" ..
						   "|cff888888Cooldown:|r " .. cd .. "s\n" ..
						   "|cff888888Applies to:|r " .. classColor .. classDisplay .. "|r" .. specDisplay,
					order = 2,
					width = 1.3,
					fontSize = "medium",
				},
				remove = {
					type = "execute",
					name = L["Remove"] or "Remove",
					order = 3,
					width = 0.5,
					func = function()
						local success, msg = Cooldowns:RemoveCustomCooldown(key)
						if success then
							DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Gladdy]|r " .. msg)
							-- Rebuild options list
							if Gladdy.options and Gladdy.options.args["Cooldowns"] then
								Gladdy.options.args["Cooldowns"].args.customCooldowns.args.customList.args = Cooldowns:GetCustomCooldownListOptions()
							end
							LibStub("AceConfigRegistry-3.0"):NotifyChange("Gladdy")
						else
							DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[Gladdy]|r " .. msg)
						end
					end,
				},
			},
		}
		order = order + 1
	end

	if order == 1 then
		options["empty"] = {
			type = "description",
			name = "|cff888888" .. (L["No custom cooldowns added yet."] or "No custom cooldowns added yet.") .. "|r\n\n" ..
				   "To add a custom cooldown:\n" ..
				   "1. Shift+Click a spell in chat to get its link\n" ..
				   "2. Paste the link in the 'Spell Name' field above\n" ..
				   "3. Set the cooldown duration\n" ..
				   "4. Select the class (or All Classes)\n" ..
				   "5. |cff00ff00(Optional)|r Select a specialization to only show this cooldown for that spec\n" ..
				   "6. Click 'Add Cooldown'\n\n" ..
				   "|cff00ff00Custom cooldowns appear in the Cooldowns tab under their class!|r\n" ..
				   "|cffaaaaaa(Spec-filtered cooldowns only show when the enemy's spec is detected)|r",
			order = 1,
			fontSize = "medium",
		}
	end

	return options
end



function Cooldowns:GetCooldownOptions()
	local group = {}

	-- Get custom cooldowns for display
	local customCooldowns = self:GetCustomCooldownsTable()

	local p = 1
	for i,class in ipairs(Gladdy.CLASSES) do
		group[class] = {
			type = "group",
			name = LOCALIZED_CLASS_NAMES_MALE[class],
			order = i,
			icon = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes",
			iconCoords = CLASS_ICON_TCOORDS[class],
			args = {}
		}
		local tblLength = tableLength(Gladdy.db.cooldownCooldownsOrder[class] or {})
		for spellId,cooldown in pairs(Gladdy:GetCooldownList()[class]) do
			-- Calculate default cooldown for display
			local defaultCD = type(cooldown) == "number" and cooldown or (type(cooldown) == "table" and cooldown.cd or 60)
			local specInfo = type(cooldown) == "table" and cooldown.spec and (" - " .. cooldown.spec) or ""

			group[class].args[tostring(spellId)] = {
				name = "",
				type = "group",
				inline = true,
				order = Gladdy.db.cooldownCooldownsOrder[class] and Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)] or 999,
				args = {
					toggle = {
						type = "toggle",
						name = (select(1, GetSpellInfo(spellId)) or ("SpellID:" .. spellId)) .. specInfo,
						order = 1,
						width = 0.9,
						image = select(3, GetSpellInfo(spellId)) or "Interface\\Icons\\INV_Misc_QuestionMark",
						get = function()
							return Gladdy.db.cooldownCooldowns[tostring(spellId)]
						end,
						set = function(_, value)
							Gladdy.db.cooldownCooldowns[tostring(spellId)] = value
							for unit in pairs(Gladdy.buttons) do
								Cooldowns:ResetUnit(unit)
								Cooldowns:UpdateCooldowns(Gladdy.buttons[unit])
								Cooldowns:Test(unit)
							end
							Gladdy:UpdateFrame()
						end
					},
					cdInput = {
						type = "input",
						name = "",
						desc = L["Cooldown duration in seconds"] or "Cooldown duration in seconds (default: " .. defaultCD .. "s)",
						order = 1.5,
						width = 0.4,
						get = function()
							local override = Gladdy.db.cooldownDurationOverrides[tostring(spellId)]
							if override then
								return tostring(override)
							end
							return tostring(defaultCD)
						end,
						set = function(_, value)
							local numVal = tonumber(value)
							if numVal and numVal > 0 then
								if numVal == defaultCD then
									-- If setting back to default, remove the override
									Gladdy.db.cooldownDurationOverrides[tostring(spellId)] = nil
								else
									Gladdy.db.cooldownDurationOverrides[tostring(spellId)] = numVal
								end
							end
						end,
					},
					resetCD = {
						type = "execute",
						name = "R",
						desc = L["Reset to default"] or "Reset to default (" .. defaultCD .. "s)",
						order = 1.6,
						width = 0.15,
						func = function()
							Gladdy.db.cooldownDurationOverrides[tostring(spellId)] = nil
							LibStub("AceConfigRegistry-3.0"):NotifyChange("Gladdy")
						end,
					},
					uparrow = {
						type = "execute",
						name = "",
						order = 2,
						width = 0.1,
						image = "Interface\\Addons\\Gladdy\\Images\\uparrow",
						imageWidth = 15,
						imageHeight = 15,
						func = function()
							if Gladdy.db.cooldownCooldownsOrder[class] and (Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)] or 0) > 1 then
								local current = Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)]
								local next
								for k,v in pairs(Gladdy.db.cooldownCooldownsOrder[class]) do
									if v == current - 1 then
										next = k
									end
								end
								if next then
									Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)] = Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)] - 1
									Gladdy.db.cooldownCooldownsOrder[class][next] = Gladdy.db.cooldownCooldownsOrder[class][next] + 1
									Gladdy.options.args["Cooldowns"].args.cooldowns.args[class].args[tostring(spellId)].order = Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)]
									Gladdy.options.args["Cooldowns"].args.cooldowns.args[class].args[next].order = Gladdy.db.cooldownCooldownsOrder[class][next]
									Gladdy:UpdateFrame()
								end
							end
						end,
					},
					downarrow = {
						type = "execute",
						name = "",
						order = 3,
						width = 0.1,
						image = "Interface\\Addons\\Gladdy\\Images\\downarrow",
						imageWidth = 15,
						imageHeight = 15,
						func = function()
							if Gladdy.db.cooldownCooldownsOrder[class] and (Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)] or 0) < tblLength then
								local current = Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)]
								local next
								for k,v in pairs(Gladdy.db.cooldownCooldownsOrder[class]) do
									if v == current + 1 then
										next = k
									end
								end
								if next then
									Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)] = Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)] + 1
									Gladdy.db.cooldownCooldownsOrder[class][next] = Gladdy.db.cooldownCooldownsOrder[class][next] - 1
									Gladdy.options.args["Cooldowns"].args.cooldowns.args[class].args[tostring(spellId)].order = Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)]
									Gladdy.options.args["Cooldowns"].args.cooldowns.args[class].args[next].order = Gladdy.db.cooldownCooldownsOrder[class][next]
									Gladdy:UpdateFrame()
								end
							end
						end,
					}
				}
			}
		end

		-- Add custom cooldowns for this class
		for key, data in pairs(customCooldowns) do
			if data.class == class then
				local spellId = data.spellId
				local spellName = (data.spellName or "Unknown"):gsub("%%COMMA%%", ",")
				local texture = (data.texture or "Interface\\Icons\\INV_Misc_QuestionMark"):gsub("%%COMMA%%", ",")
				local customDefaultCD = data.cd or 60
				local customSpec = data.spec
				local specDisplay = customSpec and (" - " .. customSpec) or ""

				group[class].args["custom_" .. tostring(spellId)] = {
					name = "",
					type = "group",
					inline = true,
					order = 1000 + (Gladdy.db.cooldownCooldownsOrder[class] and Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)] or 1),
					args = {
						toggle = {
							type = "toggle",
							name = "|cff00ff00[Custom]|r " .. spellName .. specDisplay,
							order = 1,
							width = 0.9,
							image = texture,
							get = function()
								return Gladdy.db.cooldownCooldowns[tostring(spellId)]
							end,
							set = function(_, value)
								Gladdy.db.cooldownCooldowns[tostring(spellId)] = value
								for unit in pairs(Gladdy.buttons) do
									Cooldowns:ResetUnit(unit)
									Cooldowns:UpdateCooldowns(Gladdy.buttons[unit])
									Cooldowns:Test(unit)
								end
								Gladdy:UpdateFrame()
							end
						},
						cdInput = {
							type = "input",
							name = "",
							desc = L["Cooldown duration in seconds"] or "Cooldown duration in seconds",
							order = 1.5,
							width = 0.4,
							get = function()
								local override = Gladdy.db.cooldownDurationOverrides[tostring(spellId)]
								if override then
									return tostring(override)
								end
								return tostring(customDefaultCD)
							end,
							set = function(_, value)
								local numVal = tonumber(value)
								if numVal and numVal > 0 then
									Gladdy.db.cooldownDurationOverrides[tostring(spellId)] = numVal
								end
							end,
						},
						remove = {
							type = "execute",
							name = "X",
							order = 2,
							width = 0.15,
							func = function()
								Cooldowns:RemoveCustomCooldown(tostring(spellId))
								LibStub("AceConfigRegistry-3.0"):NotifyChange("Gladdy")
							end,
						},
					}
				}
			end
		end
		p = p + i
	end

	-- Add "All Classes" group for custom cooldowns with class="ALL"
	local hasAllClassCustom = false
	for key, data in pairs(customCooldowns) do
		if data.class == "ALL" then
			hasAllClassCustom = true
			break
		end
	end

	if hasAllClassCustom then
		group["CUSTOM"] = {
			type = "group",
			name = "|cff00ff00Custom (All Classes)|r",
			order = 100,
			args = {}
		}
		for key, data in pairs(customCooldowns) do
			if data.class == "ALL" then
				local spellId = data.spellId
				local spellName = (data.spellName or "Unknown"):gsub("%%COMMA%%", ",")
				local texture = (data.texture or "Interface\\Icons\\INV_Misc_QuestionMark"):gsub("%%COMMA%%", ",")
				local customDefaultCD = data.cd or 60

				group["CUSTOM"].args["custom_" .. tostring(spellId)] = {
					name = "",
					type = "group",
					inline = true,
					order = Gladdy.db.cooldownCooldownsOrder["CUSTOM"] and Gladdy.db.cooldownCooldownsOrder["CUSTOM"][tostring(spellId)] or 1,
					args = {
						toggle = {
							type = "toggle",
							name = spellName,
							order = 1,
							width = 0.9,
							image = texture,
							get = function()
								return Gladdy.db.cooldownCooldowns[tostring(spellId)]
							end,
							set = function(_, value)
								Gladdy.db.cooldownCooldowns[tostring(spellId)] = value
								for unit in pairs(Gladdy.buttons) do
									Cooldowns:ResetUnit(unit)
									Cooldowns:UpdateCooldowns(Gladdy.buttons[unit])
									Cooldowns:Test(unit)
								end
								Gladdy:UpdateFrame()
							end
						},
						cdInput = {
							type = "input",
							name = "",
							desc = L["Cooldown duration in seconds"] or "Cooldown duration in seconds",
							order = 1.5,
							width = 0.4,
							get = function()
								local override = Gladdy.db.cooldownDurationOverrides[tostring(spellId)]
								if override then
									return tostring(override)
								end
								return tostring(customDefaultCD)
							end,
							set = function(_, value)
								local numVal = tonumber(value)
								if numVal and numVal > 0 then
									Gladdy.db.cooldownDurationOverrides[tostring(spellId)] = numVal
								end
							end,
						},
						remove = {
							type = "execute",
							name = "X",
							order = 2,
							width = 0.15,
							func = function()
								Cooldowns:RemoveCustomCooldown(tostring(spellId))
								LibStub("AceConfigRegistry-3.0"):NotifyChange("Gladdy")
							end,
						},
					}
				}
			end
		end
	end
	for i,race in ipairs(Gladdy.RACES) do
		for spellId,cooldown in pairs(Gladdy:GetCooldownList()[race]) do
			local tblLength = tableLength(Gladdy.db.cooldownCooldownsOrder[cooldown.class])
			local class = cooldown.class
			-- Calculate default cooldown for racials
			local racialDefaultCD = type(cooldown) == "number" and cooldown or (type(cooldown) == "table" and cooldown.cd or 120)
			local specInfo = type(cooldown) == "table" and cooldown.spec and (" - " .. cooldown.spec) or ""

			group[class].args[tostring(spellId)] = {
				name = "",
				type = "group",
				inline = true,
				order = Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)],
				args = {
					toggle = {
						type = "toggle",
						name = (select(1, GetSpellInfo(spellId)) or ("SpellID:" .. spellId)) .. specInfo,
						order = 1,
						width = 0.9,
						image = select(3, GetSpellInfo(spellId)) or "Interface\\Icons\\INV_Misc_QuestionMark",
						get = function()
							return Gladdy.db.cooldownCooldowns[tostring(spellId)]
						end,
						set = function(_, value)
							Gladdy.db.cooldownCooldowns[tostring(spellId)] = value
							Gladdy:UpdateFrame()
						end
					},
					cdInput = {
						type = "input",
						name = "",
						desc = L["Cooldown duration in seconds"] or "Cooldown duration in seconds (default: " .. racialDefaultCD .. "s)",
						order = 1.5,
						width = 0.4,
						get = function()
							local override = Gladdy.db.cooldownDurationOverrides[tostring(spellId)]
							if override then
								return tostring(override)
							end
							return tostring(racialDefaultCD)
						end,
						set = function(_, value)
							local numVal = tonumber(value)
							if numVal and numVal > 0 then
								if numVal == racialDefaultCD then
									Gladdy.db.cooldownDurationOverrides[tostring(spellId)] = nil
								else
									Gladdy.db.cooldownDurationOverrides[tostring(spellId)] = numVal
								end
							end
						end,
					},
					resetCD = {
						type = "execute",
						name = "R",
						desc = L["Reset to default"] or "Reset to default (" .. racialDefaultCD .. "s)",
						order = 1.6,
						width = 0.15,
						func = function()
							Gladdy.db.cooldownDurationOverrides[tostring(spellId)] = nil
							LibStub("AceConfigRegistry-3.0"):NotifyChange("Gladdy")
						end,
					},
					uparrow = {
						type = "execute",
						name = "",
						order = 2,
						width = 0.1,
						image = "Interface\\Addons\\Gladdy\\Images\\uparrow",
						imageWidth = 20,
						imageHeight = 20,
						func = function()
							if (Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)] > 1) then
								local current = Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)]
								local next
								for k,v in pairs(Gladdy.db.cooldownCooldownsOrder[class]) do
									if v == current - 1 then
										next = k
									end
								end
								Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)] = Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)] - 1
								Gladdy.db.cooldownCooldownsOrder[class][next] = Gladdy.db.cooldownCooldownsOrder[class][next] + 1
								Gladdy.options.args["Cooldowns"].args.cooldowns.args[class].args[tostring(spellId)].order = Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)]
								Gladdy.options.args["Cooldowns"].args.cooldowns.args[class].args[next].order = Gladdy.db.cooldownCooldownsOrder[class][next]
								Gladdy:UpdateFrame()
							end
						end,
					},
					downarrow = {
						type = "execute",
						name = "",
						order = 3,
						width = 0.1,
						image = "Interface\\Addons\\Gladdy\\Images\\downarrow",
						imageWidth = 20,
						imageHeight = 20,
						func = function()
							if (Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)] < tblLength) then
								local current = Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)]
								local next
								for k,v in pairs(Gladdy.db.cooldownCooldownsOrder[class]) do
									if v == current + 1 then
										next = k
									end
								end
								Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)] = Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)] + 1
								Gladdy.db.cooldownCooldownsOrder[class][next] = Gladdy.db.cooldownCooldownsOrder[class][next] - 1
								Gladdy.options.args["Cooldowns"].args.cooldowns.args[class].args[tostring(spellId)].order = Gladdy.db.cooldownCooldownsOrder[class][tostring(spellId)]
								Gladdy.options.args["Cooldowns"].args.cooldowns.args[class].args[next].order = Gladdy.db.cooldownCooldownsOrder[class][next]
								Gladdy:UpdateFrame()
							end
						end,
					}
				}
			}
		end
	end
	return group
end

---------------------------

-- LAGACY HANDLER

---------------------------

function Cooldowns:LegacySetPosition(button, unit)
	if Gladdy.db.newLayout then
		return Gladdy.db.newLayout
	end
	button.spellCooldownFrame:ClearAllPoints()
	local powerBarHeight = Gladdy.db.powerBarEnabled and (Gladdy.db.powerBarHeight + 1) or 0
	local horizontalMargin = (Gladdy.db.highlightInset and 0 or Gladdy.db.highlightBorderSize)

	local offset = 0
	if (Gladdy.db.cooldownXPos == "RIGHT") then
		offset = -(Gladdy.db.cooldownSize * Gladdy.db.cooldownWidthFactor)
	end

	if Gladdy.db.cooldownYPos == "TOP" then
		Gladdy.db.cooldownYGrowDirection = "UP"
		if Gladdy.db.cooldownXPos == "RIGHT" then
			Gladdy.db.cooldownXGrowDirection = "LEFT"
			button.spellCooldownFrame:SetPoint("BOTTOMRIGHT", button.healthBar, "TOPRIGHT", Gladdy.db.cooldownXOffset + offset, horizontalMargin + Gladdy.db.cooldownYOffset)
		else
			Gladdy.db.cooldownXGrowDirection = "RIGHT"
			button.spellCooldownFrame:SetPoint("BOTTOMLEFT", button.healthBar, "TOPLEFT", Gladdy.db.cooldownXOffset + offset, horizontalMargin + Gladdy.db.cooldownYOffset)
		end
	elseif Gladdy.db.cooldownYPos == "BOTTOM" then
		Gladdy.db.cooldownYGrowDirection = "DOWN"
		if Gladdy.db.cooldownXPos == "RIGHT" then
			Gladdy.db.cooldownXGrowDirection = "LEFT"
			button.spellCooldownFrame:SetPoint("TOPRIGHT", button.healthBar, "BOTTOMRIGHT", Gladdy.db.cooldownXOffset + offset, -horizontalMargin + Gladdy.db.cooldownYOffset - powerBarHeight)
		else
			Gladdy.db.cooldownXGrowDirection = "RIGHT"
			button.spellCooldownFrame:SetPoint("TOPLEFT", button.healthBar, "BOTTOMLEFT", Gladdy.db.cooldownXOffset + offset, -horizontalMargin + Gladdy.db.cooldownYOffset - powerBarHeight)
		end
	elseif Gladdy.db.cooldownYPos == "LEFT" then
		Gladdy.db.cooldownYGrowDirection = "DOWN"
		local anchor = Gladdy:GetAnchor(unit, "LEFT")
		if anchor == Gladdy.buttons[unit].healthBar then
			Gladdy.db.cooldownXGrowDirection = "LEFT"
			button.spellCooldownFrame:SetPoint("RIGHT", anchor, "LEFT", -(horizontalMargin + Gladdy.db.padding) + Gladdy.db.cooldownXOffset + offset, Gladdy.db.cooldownYOffset)
		else
			Gladdy.db.cooldownXGrowDirection = "LEFT"
			button.spellCooldownFrame:SetPoint("RIGHT", anchor, "LEFT", -Gladdy.db.padding + Gladdy.db.cooldownXOffset + offset, Gladdy.db.cooldownYOffset)
		end
	elseif Gladdy.db.cooldownYPos == "RIGHT" then
		Gladdy.db.cooldownYGrowDirection = "DOWN"
		local anchor = Gladdy:GetAnchor(unit, "RIGHT")
		if anchor == Gladdy.buttons[unit].healthBar then
			Gladdy.db.cooldownXGrowDirection = "RIGHT"
			button.spellCooldownFrame:SetPoint("LEFT", anchor, "RIGHT", horizontalMargin + Gladdy.db.padding + Gladdy.db.cooldownXOffset + offset, Gladdy.db.cooldownYOffset)
		else
			Gladdy.db.cooldownXGrowDirection = "RIGHT"
			button.spellCooldownFrame:SetPoint("LEFT", anchor, "RIGHT", Gladdy.db.padding + Gladdy.db.cooldownXOffset + offset, Gladdy.db.cooldownYOffset)
		end
	end
	LibStub("AceConfigRegistry-3.0"):NotifyChange("Gladdy")

	return Gladdy.db.newLayout
end