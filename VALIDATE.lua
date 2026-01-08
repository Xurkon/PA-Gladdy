--[[
	VALIDATE.lua
	Quick validation script to check Gladdy Ascension port integrity

	Copy-paste this into WoW chat to run diagnostics:
	/run local f=io.open("Interface\\AddOns\\Gladdy\\VALIDATE.lua");local s=f:read("*a");f:close();loadstring(s)()

	OR simply type this in-game after login:
	/script GladdyValidate()
]]

function GladdyValidate()
	local results = {}
	local errors = 0
	local warnings = 0

	local function Pass(msg)
		table.insert(results, "|cff00ff00[PASS]|r " .. msg)
	end

	local function Fail(msg)
		table.insert(results, "|cffff0000[FAIL]|r " .. msg)
		errors = errors + 1
	end

	local function Warn(msg)
		table.insert(results, "|cffffff00[WARN]|r " .. msg)
		warnings = warnings + 1
	end

	DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff=== Gladdy Ascension Validation ===|r")

	-- Check 1: GladdyCompat loaded
	if _G.C_CreatureInfo and _G.C_CreatureInfo.GetClassInfo then
		Pass("C_CreatureInfo exists and has GetClassInfo")
	else
		Fail("C_CreatureInfo missing or incomplete - GladdyCompat.lua not loaded?")
	end

	-- Check 2: AuraUtil
	if _G.AuraUtil and _G.AuraUtil.FindAuraByName then
		Pass("AuraUtil.FindAuraByName exists")
	else
		Fail("AuraUtil.FindAuraByName missing - GladdyCompat.lua not loaded?")
	end

	-- Check 3: WOW_PROJECT constants
	if _G.WOW_PROJECT_ID_RCE and _G.WOW_PROJECT_WRATH_CLASSIC then
		Pass("WOW_PROJECT constants set (value: " .. tostring(_G.WOW_PROJECT_ID_RCE) .. ")")
	else
		Warn("WOW_PROJECT constants not set - may cause issues")
	end

	-- Check 4: Gladdy library loaded
	local Gladdy = LibStub and LibStub("Gladdy", true)
	if Gladdy then
		Pass("Gladdy library loaded (version: " .. tostring(Gladdy.version_num) .. ")")
	else
		Fail("Gladdy library not loaded - addon failed to initialize")
		for _, msg in ipairs(results) do
			DEFAULT_CHAT_FRAME:AddMessage(msg)
		end
		DEFAULT_CHAT_FRAME:AddMessage("|cffff0000=== Validation FAILED (" .. errors .. " errors, " .. warnings .. " warnings) ===|r")
		return
	end

	-- Check 5: GetSpecBuffs
	if Gladdy.GetSpecBuffs then
		local specBuffs = Gladdy:GetSpecBuffs()
		if specBuffs and next(specBuffs) then
			Pass("GetSpecBuffs() returns data (" .. tostring(select("#", pairs(specBuffs))) .. "+ entries)")
		else
			Fail("GetSpecBuffs() returns empty table - Constants_Wrath.lua issue?")
		end
	else
		Fail("GetSpecBuffs is nil - Constants_Wrath.lua not loaded!")
	end

	-- Check 6: GetSpecSpells
	if Gladdy.GetSpecSpells then
		Pass("GetSpecSpells exists")
	else
		Fail("GetSpecSpells is nil - Constants_Wrath.lua not loaded!")
	end

	-- Check 7: GetCooldownList
	if Gladdy.GetCooldownList then
		local cdList = Gladdy:GetCooldownList()
		if cdList and cdList.MAGE then
			Pass("GetCooldownList() returns data with class entries")
		else
			Fail("GetCooldownList() returns invalid data")
		end
	else
		Fail("GetCooldownList is nil - Constants_Wrath.lua not loaded!")
	end

	-- Check 8: Localization
	if Gladdy.L then
		if Gladdy.L["Druid"] and Gladdy.L["Mage"] then
			Pass("Localization loaded (Druid=" .. tostring(Gladdy.L["Druid"]) .. ")")
		else
			Fail("Localization incomplete - Lang.lua issue?")
		end
	else
		Fail("Gladdy.L is nil - Lang.lua not loaded!")
	end

	-- Check 9: Vanilla APIs
	if UnitAura and UnitClass and UnitRace and GetSpellInfo then
		Pass("Vanilla 3.3.5 APIs available")
	else
		Fail("Core WoW APIs missing - wrong client version?")
	end

	-- Check 10: ClassicAPI NOT loaded
	local hasClassicAPI = IsAddOnLoaded("!!!ClassicAPI")
	if hasClassicAPI then
		Warn("!!!ClassicAPI is still loaded - should be removed!")
	else
		Pass("ClassicAPI correctly removed")
	end

	-- Check 11: Modules
	if Gladdy.modules then
		local moduleCount = 0
		for _ in pairs(Gladdy.modules) do moduleCount = moduleCount + 1 end
		if moduleCount >= 20 then
			Pass("Modules loaded (" .. moduleCount .. " modules)")
		else
			Warn("Only " .. moduleCount .. " modules loaded - expected ~22")
		end
	else
		Fail("No modules loaded - addon initialization incomplete")
	end

	-- Check 12: Test C_CreatureInfo functionality
	local testClass = _G.C_CreatureInfo.GetClassInfo(8)
	if testClass and testClass.className then
		Pass("C_CreatureInfo.GetClassInfo works (Mage=" .. testClass.className .. ")")
	else
		Fail("C_CreatureInfo.GetClassInfo returns invalid data")
	end

	-- Check 13: Test AuraUtil functionality
	local testAura = _G.AuraUtil.FindAuraByName
	if type(testAura) == "function" then
		Pass("AuraUtil.FindAuraByName is callable")
	else
		Fail("AuraUtil.FindAuraByName is not a function")
	end

	-- Print results
	for _, msg in ipairs(results) do
		DEFAULT_CHAT_FRAME:AddMessage(msg)
	end

	-- Summary
	if errors == 0 and warnings == 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00=== Validation PASSED - Gladdy ready for arena! ===|r")
	elseif errors == 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00=== Validation PASSED with " .. warnings .. " warning(s) ===|r")
	else
		DEFAULT_CHAT_FRAME:AddMessage("|cffff0000=== Validation FAILED (" .. errors .. " errors, " .. warnings .. " warnings) ===|r")
		DEFAULT_CHAT_FRAME:AddMessage("|cffff0000See ASCENSION_MIGRATION.md for troubleshooting|r")
	end
end

-- Auto-run if loaded directly (not via TOC)
if DEFAULT_CHAT_FRAME then
	DEFAULT_CHAT_FRAME:AddMessage("|cff00ffffGladdy validation script loaded. Type: /script GladdyValidate()|r")
end
