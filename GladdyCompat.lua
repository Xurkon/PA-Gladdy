--[[
	GladdyCompat.lua
	Minimal compatibility shim for Ascension WoW

	Provides only the APIs that Gladdy uses from ClassicAPI but are missing on Ascension.
	Does NOT override native Ascension APIs - only polyfills what's missing.
]]

local _G = _G

-- ========================================
-- ENVIRONMENT DETECTION
-- ========================================

-- Check if we're on Ascension (no WOW_PROJECT_* constants or different values)
local isAscension = (not WOW_PROJECT_WRATH_CLASSIC) or (WOW_PROJECT_ID and WOW_PROJECT_ID ~= 3)

-- Make Ascension appear as Wrath Classic to addon code
if isAscension then
	-- Set the constants that Constants_Wrath.lua expects
	_G.WOW_PROJECT_ID_RCE = 3
	_G.WOW_PROJECT_WRATH_CLASSIC = 3
	_G.WOW_PROJECT_ID = _G.WOW_PROJECT_ID or 3

	-- Define all WOW_PROJECT constants for libs (LibClassAuras, DRList, etc.)
	_G.WOW_PROJECT_MAINLINE = 1
	_G.WOW_PROJECT_CLASSIC = 2
	_G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
	_G.WOW_PROJECT_CATACLYSM_CLASSIC = 6
end

-- Debug helper (disabled for release)
local function GladdyCompat_Debug(msg)
	-- Debug messages disabled
	-- Uncomment below to enable debug output:
	-- if DEFAULT_CHAT_FRAME then
	-- 	DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[GladdyCompat]|r " .. tostring(msg))
	-- end
end

-- GladdyCompat_Debug("Initializing compatibility layer for Ascension...")

-- ========================================
-- C_CreatureInfo POLYFILL
-- ========================================

-- Only create if it doesn't exist natively
if not _G.C_CreatureInfo then
	_G.C_CreatureInfo = {}

	-- Hardcoded class data for WotLK (classID -> localized names)
	-- These will be overridden by actual localized values from GetClassInfo() if available
	local classData = {
		[1] = { classID = 1, className = "Warrior", classFile = "WARRIOR" },
		[2] = { classID = 2, className = "Paladin", classFile = "PALADIN" },
		[3] = { classID = 3, className = "Hunter", classFile = "HUNTER" },
		[4] = { classID = 4, className = "Rogue", classFile = "ROGUE" },
		[5] = { classID = 5, className = "Priest", classFile = "PRIEST" },
		[6] = { classID = 6, className = "Death Knight", classFile = "DEATHKNIGHT" },
		[7] = { classID = 7, className = "Shaman", classFile = "SHAMAN" },
		[8] = { classID = 8, className = "Mage", classFile = "MAGE" },
		[9] = { classID = 9, className = "Warlock", classFile = "WARLOCK" },
		[11] = { classID = 11, className = "Druid", classFile = "DRUID" },
	}

	-- Hardcoded race data for WotLK
	local raceData = {
		[1] = { raceID = 1, raceName = "Human", clientFileString = "Human" },
		[2] = { raceID = 2, raceName = "Orc", clientFileString = "Orc" },
		[3] = { raceID = 3, raceName = "Dwarf", clientFileString = "Dwarf" },
		[4] = { raceID = 4, raceName = "Night Elf", clientFileString = "NightElf" },
		[5] = { raceID = 5, raceName = "Undead", clientFileString = "Scourge" },
		[6] = { raceID = 6, raceName = "Tauren", clientFileString = "Tauren" },
		[7] = { raceID = 7, raceName = "Gnome", clientFileString = "Gnome" },
		[8] = { raceID = 8, raceName = "Troll", clientFileString = "Troll" },
		[10] = { raceID = 10, raceName = "Blood Elf", clientFileString = "BloodElf" },
		[11] = { raceID = 11, raceName = "Draenei", clientFileString = "Draenei" },
	}

	-- Try to get localized names from GetClassInfo if it exists
	if GetClassInfo then
		for classID = 1, 11 do
			local localizedName, classFile = GetClassInfo(classID)
			if localizedName and classData[classID] then
				classData[classID].className = localizedName
				classData[classID].classFile = classFile or classData[classID].classFile
			end
		end
	end

	-- Try to get localized race names from UnitRace if possible
	-- We'll use the hardcoded English names as fallback

	function _G.C_CreatureInfo.GetClassInfo(classID)
		if not classID then return nil end
		local data = classData[classID]
		if not data then
			GladdyCompat_Debug("WARNING: Unknown classID " .. tostring(classID))
			return { classID = classID, className = "Unknown", classFile = "UNKNOWN" }
		end
		return data
	end

	function _G.C_CreatureInfo.GetRaceInfo(raceID)
		if not raceID then return nil end
		local data = raceData[raceID]
		if not data then
			GladdyCompat_Debug("WARNING: Unknown raceID " .. tostring(raceID))
			return { raceID = raceID, raceName = "Unknown", clientFileString = "Unknown" }
		end
		return data
	end

	GladdyCompat_Debug("Created C_CreatureInfo polyfill")
else
	GladdyCompat_Debug("C_CreatureInfo already exists natively - using native version")
end

-- ========================================
-- AuraUtil POLYFILL
-- ========================================

if not _G.AuraUtil then
	_G.AuraUtil = {}

	-- FindAuraByName wrapper around vanilla UnitAura
	function _G.AuraUtil.FindAuraByName(auraName, unit, filter)
		if not auraName or not unit then return nil end

		-- Iterate through auras manually using UnitAura
		local i = 1
		while true do
			local name, icon, count, dispelType, duration, expirationTime, unitCaster, isStealable,
				  nameplateShowPersonal, spellID = UnitAura(unit, i, filter)

			if not name then
				break -- No more auras
			end

			if name == auraName then
				-- Return in the format expected by AuraUtil.FindAuraByName
				return name, icon, count, dispelType, duration, expirationTime, unitCaster,
					   isStealable, nameplateShowPersonal, spellID
			end

			i = i + 1
		end

		return nil -- Aura not found
	end

	GladdyCompat_Debug("Created AuraUtil.FindAuraByName polyfill")
else
	-- AuraUtil exists but might be missing FindAuraByName
	if not _G.AuraUtil.FindAuraByName then
		function _G.AuraUtil.FindAuraByName(auraName, unit, filter)
			if not auraName or not unit then return nil end

			local i = 1
			while true do
				local name, icon, count, dispelType, duration, expirationTime, unitCaster, isStealable,
					  nameplateShowPersonal, spellID = UnitAura(unit, i, filter)

				if not name then break end
				if name == auraName then
					return name, icon, count, dispelType, duration, expirationTime, unitCaster,
						   isStealable, nameplateShowPersonal, spellID
				end

				i = i + 1
			end

			return nil
		end

		GladdyCompat_Debug("Added FindAuraByName to existing AuraUtil")
	else
		GladdyCompat_Debug("AuraUtil.FindAuraByName already exists - using native version")
	end
end

-- ========================================
-- C_UnitAura HANDLING
-- ========================================

-- EventListener.lua already has fallback: (C_UnitAura or UnitAura)
-- So if C_UnitAura doesn't exist, it will use vanilla UnitAura
-- No additional polyfill needed here

if not _G.C_UnitAura then
	GladdyCompat_Debug("C_UnitAura not present - EventListener will use vanilla UnitAura fallback")
else
	GladdyCompat_Debug("C_UnitAura exists natively - using native version")
end

-- ========================================
-- GetSpellInfo / GetItemInfo - NO GLOBAL WRAPPING
-- ========================================

-- IMPORTANT: We CANNOT wrap GetSpellInfo or GetItemInfo globally!
-- These functions are used by Blizzard's secure UI code (spellbook, macros, action bars)
-- Wrapping them causes TAINT which breaks macros and spellbook icons
--
-- Instead, individual Gladdy modules handle nil returns locally where needed
-- Example: Cooldowns.lua lines 1051, 1054, 1135, 1138 have nil fallbacks
--
-- On Ascension, some Wrath spell/item IDs don't exist - those will return nil
-- This is expected and handled per-module

GladdyCompat_Debug("GetSpellInfo/GetItemInfo: Using native functions (no wrapping to avoid taint)")

-- ========================================
-- C_Timer POLYFILL
-- ========================================

-- C_Timer is a retail API (added in Legion 7.0+), not available in 3.3.5
-- Modules use C_Timer.NewTicker and C_Timer.NewTimer extensively
if not _G.C_Timer then
	_G.C_Timer = {}

	-- NewTicker: Runs callback every duration seconds until cancelled
	function _G.C_Timer.NewTicker(duration, callback, iterations)
		local ticker = {
			_cancelled = false,
			_iterations = iterations or nil,
			_count = 0,
			_callback = callback,
			_duration = duration,
		}

		-- Create a frame to handle OnUpdate
		local frame = CreateFrame("Frame")
		ticker._frame = frame
		frame._elapsed = 0

		frame:SetScript("OnUpdate", function(self, elapsed)
			if ticker._cancelled then
				self:SetScript("OnUpdate", nil)
				return
			end

			self._elapsed = self._elapsed + elapsed
			if self._elapsed >= ticker._duration then
				self._elapsed = 0
				ticker._count = ticker._count + 1

				-- Call the callback
				ticker._callback()

				-- Check if we've reached iteration limit
				if ticker._iterations and ticker._count >= ticker._iterations then
					ticker:Cancel()
				end
			end
		end)

		function ticker:Cancel()
			self._cancelled = true
			if self._frame then
				self._frame:SetScript("OnUpdate", nil)
			end
		end

		function ticker:IsCancelled()
			return self._cancelled
		end

		return ticker
	end

	-- NewTimer: Runs callback once after duration seconds
	function _G.C_Timer.NewTimer(duration, callback)
		local timer = {
			_cancelled = false,
			_callback = callback,
			_duration = duration,
		}

		local frame = CreateFrame("Frame")
		timer._frame = frame
		frame._elapsed = 0

		frame:SetScript("OnUpdate", function(self, elapsed)
			if timer._cancelled then
				self:SetScript("OnUpdate", nil)
				return
			end

			self._elapsed = self._elapsed + elapsed
			if self._elapsed >= timer._duration then
				timer._callback()
				timer:Cancel()
			end
		end)

		function timer:Cancel()
			self._cancelled = true
			if self._frame then
				self._frame:SetScript("OnUpdate", nil)
			end
		end

		function timer:IsCancelled()
			return self._cancelled
		end

		return timer
	end

	-- After creates a one-shot timer (alias for NewTimer for compatibility)
	_G.C_Timer.After = _G.C_Timer.NewTimer

	GladdyCompat_Debug("Created C_Timer polyfill (NewTicker, NewTimer, After)")
else
	GladdyCompat_Debug("C_Timer already exists natively - using native version")
end

-- ========================================
-- GetPhysicalScreenSize POLYFILL
-- ========================================

-- GetPhysicalScreenSize is a retail API (added in BFA 8.0+), not available in 3.3.5
-- Used for pixel-perfect UI scaling calculations
if not _G.GetPhysicalScreenSize then
	function _G.GetPhysicalScreenSize()
		-- In 3.3.5, use GetScreenWidth() and GetScreenHeight()
		-- These return the actual screen dimensions
		local width = GetScreenWidth()
		local height = GetScreenHeight()
		return width, height
	end
	GladdyCompat_Debug("Created GetPhysicalScreenSize polyfill")
else
	GladdyCompat_Debug("GetPhysicalScreenSize already exists natively")
end

-- ========================================
-- RegisterUnitEvent Polyfill (Legion 7.0+)
-- ========================================
-- RegisterUnitEvent(event, unit) doesn't exist in 3.3.5
-- It was added in Legion to filter UNIT_* events by specific unit
-- We polyfill it to just call RegisterEvent() without filtering
-- The actual filtering is done manually in each module's OnEvent()

local frame_mt = getmetatable(CreateFrame("Frame")).__index
if not frame_mt.RegisterUnitEvent then
	frame_mt.RegisterUnitEvent = function(self, event, unit)
		-- In 3.3.5, just register the event normally (receives ALL units)
		-- Modules must filter manually in OnEvent by checking unit parameter
		self:RegisterEvent(event)
	end
	GladdyCompat_Debug("Created RegisterUnitEvent polyfill (filters manually in OnEvent)")
else
	GladdyCompat_Debug("RegisterUnitEvent already exists natively")
end

-- ========================================
-- INITIALIZATION COMPLETE
-- ========================================

GladdyCompat_Debug("Compatibility layer initialized successfully")
GladdyCompat_Debug("Environment: " .. (isAscension and "Ascension (patched as Wrath)" or "Native Wrath"))
