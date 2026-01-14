local select, pairs, tremove, tinsert, format, strsplit, tonumber, ipairs = select, pairs, tremove, tinsert, format, strsplit, tonumber, ipairs
local Gladdy = LibStub("Gladdy")
local L = Gladdy.L
local UnitName, GetSpellInfo, CreateFrame, WorldFrame = UnitName, GetSpellInfo, CreateFrame, WorldFrame
local totemData, totemNameTotemData = Gladdy:GetTotemData()

local NAMEPLATE_LOGIN = -.4 -- Delay processing all nameplates on initial load.
local NAMEPLATE_THROTTLE = .5 -- .04 = instant
local NAMEPLATE_THROTTLE_CURRENT = NAMEPLATE_LOGIN
local NAMEPLATE_NUM = 0
local NAMEPLATE_NUM_PREVIOUS = 0
local NAMEPLATE_TARGET

-- Pulse Timer Variables
local activeNameplates = {}
local timestamp = {}

-- Helper function to find unit for a nameplate
local function GetNameplateUnit(nameplate)
	-- Try C_NamePlate API first
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, np in pairs(C_NamePlate.GetNamePlates()) do
			if np == nameplate then
				-- Found match, now find the unit
				for i = 1, 40 do
					local unit = "nameplate" .. i
					local unitPlate = C_NamePlate.GetNamePlateForUnit(unit)
					if unitPlate == nameplate then
						return unit
					end
				end
			end
		end
	end
	return nil
end

---------------------------------------------------

-- Pulse Timer Functions (from core.lua)

---------------------------------------------------

local function OnUpdateTimer(self)
    local remainingTime = self.timestamp - GetTime()
    local cycleTime = remainingTime % 3
    if self.pulseText then
        self.pulseText:SetText(string.format("%.1f", cycleTime))
    end
end

local function HidePulse(totem)
    if totem and totem.pulseText then
        totem.pulseText:Hide()
        totem:SetScript("OnUpdate", nil)
        totem.timestamp = nil
    end
end

local function ShowPulse(totem, timestampData)
    if not totem then return end

    -- Create pulse text if it doesn't exist
    if not totem.pulseText then
        totem.pulseText = totem:CreateFontString(nil, "OVERLAY")
        totem.pulseText:SetFont("Fonts\\ARIALN.TTF", 7, "OUTLINE")
        totem.pulseText:SetPoint("CENTER", totem, "CENTER", 0, -10)
        totem.pulseText:SetTextColor(1, 1, 0) -- Yellow color for visibility
    end

    totem.timestamp = timestampData.timeStamp
    local cycleTime = (timestampData.timeStamp - GetTime()) % 3
    totem.pulseText:SetText(string.format("%.1f", cycleTime))
    totem.pulseText:Show()
    totem:SetScript("OnUpdate", OnUpdateTimer)
end

local function CLEU(_, eventType, sourceGUID, _, _, destGUID)
    local guid = destGUID and tonumber((destGUID):sub(-10, -7), 16)

    -- Check for tremor totem (5913) or cleansing totem (5924)
    if guid and guid ~= 5913 and guid ~= 5924 then return end

    if (eventType == "UNIT_DESTROYED" or eventType == "SWING_DAMAGE" or eventType == "SPELL_DAMAGE") and timestamp[destGUID] then
        timestamp[destGUID] = nil
        -- Remove from active nameplates if destroyed
        if activeNameplates[destGUID] then
            local nameplate = activeNameplates[destGUID]
            if nameplate.gladdyTotemFrame then
                HidePulse(nameplate.gladdyTotemFrame)
            end
            activeNameplates[destGUID] = nil
        end
    elseif eventType == "SPELL_CAST_SUCCESS" then
        timestamp[sourceGUID] = { timeStamp = GetTime() }
    elseif eventType == "SPELL_SUMMON" then
        if timestamp[sourceGUID] then
            timestamp[destGUID] = timestamp[sourceGUID]
            timestamp[sourceGUID] = nil
        else
            timestamp[destGUID] = { timeStamp = GetTime() }
        end
        
        -- Check if we already have a nameplate for this GUID
        if activeNameplates[destGUID] and timestamp[destGUID] then
            local nameplate = activeNameplates[destGUID]
            if nameplate.gladdyTotemFrame then
                ShowPulse(nameplate.gladdyTotemFrame, timestamp[destGUID])
            end
        end
    end
end

-- Function to handle NAME_PLATE_UNIT_ADDED event
local function HandleNameplateAdded(unit)
    if not Gladdy.db.npTotemPulseTimer then return end
    
    local guid = UnitGUID(unit)
    if not guid then return end
    
    local creatureID = tonumber((guid):sub(-10, -7), 16)
    if creatureID ~= 5913 and creatureID ~= 5924 then return end -- Not tremor or cleansing totem
    
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then return end
    
    activeNameplates[guid] = nameplate
    
    -- If we have timestamp data for this GUID, show the pulse timer
    if timestamp[guid] then
        -- Wait a bit for the gladdy totem frame to be created
        C_Timer.After(0.1, function()
            if nameplate.gladdyTotemFrame then
                ShowPulse(nameplate.gladdyTotemFrame, timestamp[guid])
            end
        end)
    else
        -- Create timestamp for existing totem
        timestamp[guid] = { timeStamp = GetTime() }
        C_Timer.After(0.1, function()
            if nameplate.gladdyTotemFrame then
                ShowPulse(nameplate.gladdyTotemFrame, timestamp[guid])
            end
        end)
    end
end

-- Function to handle NAME_PLATE_UNIT_REMOVED event
local function HandleNameplateRemoved(unit)
    local guid = UnitGUID(unit)
    if not guid then return end
    
    local nameplate = activeNameplates[guid]
    if nameplate and nameplate.gladdyTotemFrame then
        HidePulse(nameplate.gladdyTotemFrame)
        activeNameplates[guid] = nil
    end
end

---------------------------------------------------

-- Option Helpers

---------------------------------------------------

local function GetTotemColorDefaultOptions()
	local defaultDB = {}
	local options = {}
	local indexedList = {}
	for k,v in pairs(totemData) do
		tinsert(indexedList, {name = k, id = v.id, color = v.color, texture = v.texture})
	end
	table.sort(indexedList, function (a, b)
		return a.name < b.name
	end)
	for i=1,#indexedList do
		defaultDB["totem" .. indexedList[i].id] = {color = indexedList[i].color, enabled = true, alpha = 0.6, customText = ""}
		options["npTotemsHideDisabledTotems"] = {
			order = 1,
			name = L["Hide Disabled Totem Plates"],
			desc = L["Hide Disabled Totem Plates"],
			type = "toggle",
			width = "full",
			get = function() return Gladdy.dbi.profile.npTotemsHideDisabledTotems end,
			set = function(_, value)
				Gladdy.dbi.profile.npTotemsHideDisabledTotems = value
				Gladdy:UpdateFrame()
			end
		}
		options["totem" .. indexedList[i].id] = {
			order = i+1,
			name = select(1, GetSpellInfo(indexedList[i].id)),
			--inline = true,
			width  = "3.0",
			type = "group",
			icon = indexedList[i].texture,
			args = {
				headerTotemConfig = {
					type = "header",
					name = format("|T%s:20|t %s", indexedList[i].texture, select(1, GetSpellInfo(indexedList[i].id))),
					order = 1,
				},
				enabled = {
					order = 2,
					name = L["Enabled"],
					desc = "Enable " .. format("|T%s:20|t %s", indexedList[i].texture, select(1, GetSpellInfo(indexedList[i].id))),
					type = "toggle",
					width = "full",
					get = function() return Gladdy.dbi.profile.npTotemColors["totem" .. indexedList[i].id].enabled end,
					set = function(_, value)
						Gladdy.dbi.profile.npTotemColors["totem" .. indexedList[i].id].enabled = value
						Gladdy:UpdateFrame()
					end
				},
				color = {
					type = "color",
					name = L["Border color"],
					desc = L["Color of the border"],
					order = 3,
					hasAlpha = true,
					width = "full",
					get = function()
						return Gladdy.dbi.profile.npTotemColors["totem" .. indexedList[i].id].color.r,
						Gladdy.dbi.profile.npTotemColors["totem" .. indexedList[i].id].color.g,
						Gladdy.dbi.profile.npTotemColors["totem" .. indexedList[i].id].color.b,
						Gladdy.dbi.profile.npTotemColors["totem" .. indexedList[i].id].color.a
					end,
					set = function(_, r, g, b, a)
						Gladdy.dbi.profile.npTotemColors["totem" .. indexedList[i].id].color.r,
						Gladdy.dbi.profile.npTotemColors["totem" .. indexedList[i].id].color.g,
						Gladdy.dbi.profile.npTotemColors["totem" .. indexedList[i].id].color.b,
						Gladdy.dbi.profile.npTotemColors["totem" .. indexedList[i].id].color.a = r, g, b, a
						Gladdy:UpdateFrame()
					end,
				},
				alpha = {
					type = "range",
					name = L["Alpha"],
					order = 4,
					min = 0,
					max = 1,
					step = 0.1,
					width = "full",
					get = function()
						return Gladdy.dbi.profile.npTotemColors["totem" .. indexedList[i].id].alpha
					end,
					set = function(_, value)
						Gladdy.dbi.profile.npTotemColors["totem" .. indexedList[i].id].alpha = value
						Gladdy:UpdateFrame()
					end
				},
				customText = {
					type = "input",
					name = L["Custom totem name"],
					order = 5,
					width = "full",
					get = function() return Gladdy.db.npTotemColors["totem" .. indexedList[i].id].customText end,
					set = function(_, value) Gladdy.db.npTotemColors["totem" .. indexedList[i].id].customText = value Gladdy:UpdateFrame() end
				},
			}
		}
	end
	return defaultDB, options, indexedList
end

---------------------------------------------------

-- Core

---------------------------------------------------

local TotemPlates = Gladdy:NewModule("Totem Plates", 2, {
	npTotems = true,
	npTotemsShowFriendly = true,
	npTotemsShowEnemy = true,
	npTotemPlatesBorderStyle = "Interface\\AddOns\\Gladdy\\Images\\Border_rounded_blp",
	npTotemPlatesSize = 40,
	npTotemPlatesWidthFactor = 1,
	npTremorFont = "DorisPP",
	npTremorFontSize = 10,
	npTremorFontXOffset = 0,
	npTremorFontYOffset = 0,
	npTotemPlatesAlpha = 0.6,
	npTotemPlatesAlphaAlways = false,
	npTotemPlatesAlphaAlwaysTargeted = false,
	npTotemColors = select(1, GetTotemColorDefaultOptions()),
	npTotemsHideDisabledTotems = false,
	npTotemPulseTimer = true, -- New option for pulse timer
})

function TotemPlates.OnEvent(self, event, ...)
	local Func = TotemPlates[event]
	if ( Func ) then
		Func(self, ...)
	else
		-- Handle events for pulse timer
		if event == "COMBAT_LOG_EVENT_UNFILTERED" then
			CLEU(...)
		elseif event == "NAME_PLATE_UNIT_ADDED" then
			HandleNameplateAdded(...)
		elseif event == "NAME_PLATE_UNIT_REMOVED" then
			HandleNameplateRemoved(...)
		end
	end
end

function TotemPlates:Initialize()
	local hasTurboplates = IsAddOnLoaded("Turboplates") or IsAddOnLoaded("TurboPlates")
	
	if hasTurboplates then
		local saved = Gladdy.dbi and Gladdy.dbi.global and Gladdy.dbi.global.totemPlatesChoice
		
		if saved == "gladdy" then
			if TurboPlatesDB then
				TurboPlatesDB.totemDisplay = "disabled"
			end
		elseif saved == "turboplates" then
			Gladdy.db.npTotems = false
			return
		elseif saved == nil then
			StaticPopupDialogs["GLADDY_TOTEMPLATES_CHOICE"] = {
				text = "Both Gladdy and Turboplates can display totem icons.\n\nWhich addon should handle totem nameplates?\n\n(Gladdy has click-to-target and pulse timers)",
				button1 = "Gladdy",
				button2 = "Turboplates",
				OnAccept = function()
					Gladdy.dbi.global.totemPlatesChoice = "gladdy"
					if TurboPlatesDB then
						TurboPlatesDB.totemDisplay = "disabled"
					end
					Gladdy:Print("TotemPlates: Using Gladdy (Turboplates totem icons disabled)")
					ReloadUI()
				end,
				OnCancel = function()
					Gladdy.dbi.global.totemPlatesChoice = "turboplates"
					Gladdy.db.npTotems = false
					Gladdy:Print("TotemPlates: Using Turboplates (Gladdy totem icons disabled)")
					ReloadUI()
				end,
				timeout = 0,
				whileDead = true,
				hideOnEscape = false,
				preferredIndex = 3,
			}
			C_Timer.After(2, function()
				StaticPopup_Show("GLADDY_TOTEMPLATES_CHOICE")
			end)
			return
		end
	end

	TotemPlates.void = function()end
	self:SetScript("OnEvent", TotemPlates.OnEvent)
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

local function NameplateScanValid(self)
	if not self then return false end
	
	-- Skip named frames (usually UI elements, not nameplates)
	if self:GetName() then return false end
	
	-- Method 1: Check for Blizzard nameplate border texture
	local numRegions = self:GetNumRegions()
	for i = 1, numRegions do
		local region = select(i, self:GetRegions())
		if region and region:GetObjectType() == "Texture" then
			local texture = region:GetTexture()
			if texture == "Interface\\Tooltips\\Nameplate-Border" then
				return true
			end
		end
	end
	
	-- Method 2: Check for health bar child (common nameplate element)
	local numChildren = self:GetNumChildren()
	for i = 1, numChildren do
		local child = select(i, self:GetChildren())
		if child and child:GetObjectType() == "StatusBar" then
			-- Found a status bar, likely a health bar - this is probably a nameplate
			return true
		end
	end
	
	return false
end

local function NameplateScan(nameplate, ...)
	if ( nameplate ) then
		if ( (not nameplate.gladdyTotemFrame) and NameplateScanValid(nameplate) ) then
			TotemPlates:CreateTotemFrame(nameplate)
		end

		return NameplateScan(...)
	end
end

local function NameplateHandler(self, elapsed)
	if ( NAMEPLATE_THROTTLE_CURRENT > NAMEPLATE_THROTTLE ) then
		NAMEPLATE_NUM = WorldFrame:GetNumChildren()

		if ( NAMEPLATE_NUM ~= NAMEPLATE_NUM_PREVIOUS ) then
			NameplateScan(WorldFrame:GetChildren())
			NAMEPLATE_NUM_PREVIOUS = NAMEPLATE_NUM
		end

		NAMEPLATE_THROTTLE_CURRENT = 0
	end

	NAMEPLATE_THROTTLE_CURRENT = NAMEPLATE_THROTTLE_CURRENT + elapsed
end

---------------------------------------------------

-- Events

---------------------------------------------------

local function PLAYER_TARGET_CHANGED_UPDATE(nameplate, ...)
	if ( nameplate ) then
		local totem = nameplate.gladdyTotemFrame

		if ( totem and totem.active and totem.nametext ) then
			TotemPlates:SetTotemAlpha(totem, totem.nametext:GetText())
		end

		return PLAYER_TARGET_CHANGED_UPDATE(...)
	end
end

function TotemPlates:PLAYER_TARGET_CHANGED()
	NAMEPLATE_TARGET = UnitName("target")

	if ( NAMEPLATE_TARGET ) then
		PLAYER_TARGET_CHANGED_UPDATE(WorldFrame:GetChildren())
	end
end

function TotemPlates:NAME_PLATE_UNIT_ADDED(nameplate)
	if ( Gladdy.db.npTotems ) then
		if ( not nameplate ) then
			nameplate = self -- OnShow
		end

		local totem = nameplate.gladdyTotemFrame
		if ( totem and totem.nametext ) then
			local nameplateText = totem.nametext:GetText()
			local totemData = totemNameTotemData[nameplateText]

			if ( totemData ) then
				if ( TotemPlates:NameplateTypeValid(totem) ) then
					local totemInfo = Gladdy.db.npTotemColors["totem" .. totemData.id]

					if ( totemInfo.enabled ) then
						totem.totemIcon:SetTexture(totemData.texture)
						totem.totemBorder:SetVertexColor(totemInfo.color.r, totemInfo.color.g, totemInfo.color.b, totemInfo.color.a)
						totem.totemName:SetText(totemInfo.customText or "")

						TotemPlates:ToggleTotem(totem, true)
						TotemPlates:ToggleAddon(nameplate)
						totem.active = totemData

						-- Hybrid click-to-target: secure button if possible, pass-through otherwise
						if not InCombatLockdown() then
							-- Outside combat: enable secure targeting on our button
							local unit = GetNameplateUnit(nameplate)
							if unit then
								totem:SetAttribute("unit", unit)
								totem:EnableMouse(true) -- Our button handles clicks
							end
						else
							-- In combat: can't set attributes, so pass clicks to underlying nameplate
							totem:EnableMouse(false) -- Let clicks pass through to nameplate
						end

						TotemPlates:SetTotemAlpha(totem, nameplateText)

						-- Check if this is a tremor or cleansing totem and add pulse timer
						if Gladdy.db.npTotemPulseTimer and (nameplateText == "Tremor Totem" or nameplateText == "Cleansing Totem") then
							-- Create a timestamp for the totem if it doesn't exist
							local fakeGUID = "totem_" .. GetTime()
							timestamp[fakeGUID] = { timeStamp = GetTime() }
							ShowPulse(totem, timestamp[fakeGUID])
						end
					else
						-- If certain totem is disabled, then hide it and the plate depending on setting.
						if ( totem.active ) then
							TotemPlates:ToggleTotem(totem)
						end

						TotemPlates:ToggleAddon(nameplate, not Gladdy.db.npTotemsHideDisabledTotems)
					end
				end
			end
		end
	end
end

function TotemPlates:NAME_PLATE_UNIT_REMOVED(nameplate)
	if ( not nameplate ) then
		nameplate = self -- OnHide
	end

	local totem = nameplate.gladdyTotemFrame

	if ( totem ) then
		if ( totem.active ) then
			TotemPlates:ToggleTotem(totem)
			totem.active = nil
			
			-- Clear click-to-target unit (only outside combat to prevent taint)
			if not InCombatLockdown() then
				totem:SetAttribute("unit", nil)
			end
		end

		-- Hide pulse timer if it exists
		HidePulse(totem)

		TotemPlates:ToggleAddon(nameplate, true)
	end
end

function TotemPlates:PLAYER_ENTERING_WORLD()
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self:SetFrameStrata("BACKGROUND") -- Prevent icons from overlapping other frames.
	
	-- Clear pulse timer data
	timestamp = {}
	activeNameplates = {}
	
	self:UpdateFrameOnce()
end

---------------------------------------------------

-- Gladdy Call

---------------------------------------------------

local function SettingRefresh(nameplate, ...)
	if ( nameplate ) then
		local totem = nameplate.gladdyTotemFrame

		if ( totem ) then
			if ( Gladdy.db.npTotems and TotemPlates:NameplateTypeValid(totem) ) then
				if ( nameplate:IsShown() ) then
					TotemPlates:NAME_PLATE_UNIT_ADDED(nameplate)
				end

				if ( totem ) then
					totem:SetSize(Gladdy.db.npTotemPlatesSize * Gladdy.db.npTotemPlatesWidthFactor, Gladdy.db.npTotemPlatesSize)
					totem.totemName:SetFont(Gladdy:SMFetch("font", "npTremorFont"), Gladdy.db.npTremorFontSize, "OUTLINE")
					totem.totemName:SetPoint("TOP", totem, "BOTTOM", Gladdy.db.npTremorFontXOffset, Gladdy.db.npTremorFontYOffset)
					totem.totemBorder:SetTexture(Gladdy.db.npTotemPlatesBorderStyle)
				end
			else
				TotemPlates:NAME_PLATE_UNIT_REMOVED(nameplate)
			end
		end

		return SettingRefresh(...)
	end
end

function TotemPlates:UpdateFrameOnce()
	if ( Gladdy.db.npTotems and Gladdy.db.npTotemsShowEnemy ) then
		SetCVar("nameplateShowEnemyTotems", 1)
	end

	if ( Gladdy.db.npTotems and Gladdy.db.npTotemsShowFriendly ) then
		SetCVar("nameplateShowFriendlyTotems", 1)
	end

	if ( Gladdy.db.npTotems ) then
		self:RegisterEvent("PLAYER_TARGET_CHANGED")
		self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") -- Always register for pulse timer
		self:RegisterEvent("NAME_PLATE_UNIT_ADDED") -- Always register for nameplate events
		self:RegisterEvent("NAME_PLATE_UNIT_REMOVED") -- Always register for nameplate events
		self:SetScript("OnUpdate", NameplateHandler)
		self:SetScript("OnEvent", TotemPlates.OnEvent)
	else
		self:UnregisterEvent("PLAYER_TARGET_CHANGED")
		self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED") -- Unregister pulse timer
		self:UnregisterEvent("NAME_PLATE_UNIT_ADDED") -- Unregister nameplate events
		self:UnregisterEvent("NAME_PLATE_UNIT_REMOVED") -- Unregister nameplate events
		self:SetScript("OnUpdate", nil)
		self:SetScript("OnEvent", nil)
	end

	if ( NAMEPLATE_THROTTLE_CURRENT ~= NAMEPLATE_LOGIN ) then
		SettingRefresh(WorldFrame:GetChildren())

		if ( self.testFrame and self.testFrame:IsShown() ) then
			TotemPlates:TestOnce()
		end
	end
end

---------------------------------------------------

-- TotemPlates Frame

---------------------------------------------------

function TotemPlates:CreateTotemFrame(nameplate, test)
	-- Use Button with SecureActionButtonTemplate for click-to-target functionality
	local Frame = CreateFrame("Button", nil, WorldFrame, "SecureActionButtonTemplate")
	Frame:SetPoint("BOTTOM", nameplate, "TOP", 0, -25)
	Frame:SetSize(Gladdy.db.npTotemPlatesSize * Gladdy.db.npTotemPlatesWidthFactor, Gladdy.db.npTotemPlatesSize)
	Frame:Hide()
	
	-- Enable mouse interaction for clicking
	Frame:EnableMouse(true)
	Frame:RegisterForClicks("AnyUp")
	
	-- Set up secure targeting action (static, won't cause taint)
	Frame:SetAttribute("type1", "target")
	-- Unit will be set dynamically when totem is detected (outside combat only)
	
	nameplate.gladdyTotemFrame = Frame

	-- Icon
	local Icon = Frame:CreateTexture(nil, "BACKGROUND")
	Icon:SetPoint("TOPLEFT", Frame, "TOPLEFT")
	Icon:SetPoint("BOTTOMRIGHT", Frame, "BOTTOMRIGHT")
	Frame.totemIcon = Icon

	-- Border
	local Border = Frame:CreateTexture(nil, "BORDER")
	Border:SetPoint("TOPLEFT", Frame, "TOPLEFT")
	Border:SetPoint("BOTTOMRIGHT", Frame, "BOTTOMRIGHT")
	Border:SetTexture(Gladdy.db.npTotemPlatesBorderStyle)
	Frame.totemBorder = Border

	-- Name
	local Name = Frame:CreateFontString(nil, "OVERLAY")
	Name:SetFont(Gladdy:SMFetch("font", "npTremorFont"), Gladdy.db.npTremorFontSize, "OUTLINE")
	Name:SetPoint("TOP", Frame, "BOTTOM", Gladdy.db.npTremorFontXOffset, Gladdy.db.npTremorFontYOffset)
	Frame.totemName = Name

	if ( not test ) then
		-- Highlight
		local Highlight = Frame:CreateTexture(nil, "OVERLAY")
		Highlight:SetTexture("Interface/TargetingFrame/UI-TargetingFrame-BarFill")
		Highlight:SetPoint("TOPLEFT", Frame, "TOPLEFT", Gladdy.db.npTotemPlatesSize/16, -Gladdy.db.npTotemPlatesSize/16)
		Highlight:SetPoint("BOTTOMRIGHT", Frame, "BOTTOMRIGHT", -Gladdy.db.npTotemPlatesSize/16, Gladdy.db.npTotemPlatesSize/16)
		Highlight:SetBlendMode("ADD")
		Highlight:SetAlpha(0)
		Frame.selectionHighlight = Highlight

		-- Universal element discovery - find nameplate elements regardless of addon
		-- Try to find healthbar from children
		local numChildren = nameplate:GetNumChildren()
		for i = 1, numChildren do
			local child = select(i, nameplate:GetChildren())
			if child and child:GetObjectType() == "StatusBar" and not Frame.healthbar then
				Frame.healthbar = child
			end
		end
		
		-- Try to find text and icons from regions
		local numRegions = nameplate:GetNumRegions()
		for i = 1, numRegions do
			local region = select(i, nameplate:GetRegions())
			if region then
				local objType = region:GetObjectType()
				if objType == "Texture" then
					local texture = region:GetTexture()
					if texture then
						if texture:find("Nameplate%-Border") then
							Frame.healthborder = region
						elseif texture:find("Highlight") then
							Frame.highlighttexture = region
						elseif texture:find("Skull") or texture:find("Boss") then
							Frame.bossicon = region
						elseif texture:find("Raid") then
							Frame.raidicon = region
						end
					end
				elseif objType == "FontString" then
					local text = region:GetText()
					if text then
						-- First fontstring is usually the name, second might be level
						if not Frame.nametext then
							Frame.nametext = region
						elseif not Frame.leveltext then
							Frame.leveltext = region
						end
					end
				end
			end
		end

		-- Hooks
		nameplate:HookScript("OnHide", TotemPlates.NAME_PLATE_UNIT_REMOVED)
		nameplate:HookScript("OnShow", TotemPlates.NAME_PLATE_UNIT_ADDED)

		self:NAME_PLATE_UNIT_ADDED(nameplate)
	end
end

---------------------------------------------------

-- Nameplate functions

---------------------------------------------------

function TotemPlates:NameplateTypeValid(self)
	if ( self.healthbar ) then
		local r, g = self.healthbar:GetStatusBarColor()
		local friendly = (r == 0 and g > 0.9)

		if ( (Gladdy.db.npTotemsShowFriendly and friendly) or (Gladdy.db.npTotemsShowEnemy and not friendly) ) then
			return true
		end
	end
end

function TotemPlates:ToggleTotem(totem, show)
	if ( show ) then
		totem:Show()
		if ( not totem.active ) then
			totem:SetScript("OnUpdate", TotemPlates.OnUpdate)
		end
	else
		totem:Hide()
		if ( totem.active ) then
			totem:SetScript("OnUpdate", nil)
		end
	end
end

function TotemPlates:GetAddonFrame(nameplate)
	-- Universal approach: always return the gladdy totem frame
	-- We overlay our frame on top of any nameplate addon
	return nameplate.gladdyTotemFrame
end

function TotemPlates:ToggleAddon(nameplate, show)
	-- Universal overlay approach: we don't manipulate other addon's frames
	-- We simply hide default nameplate elements for cleaner display
	local totem = nameplate.gladdyTotemFrame
	if not totem then return end
	
	-- Try to hide/show standard nameplate elements if they exist
	-- These are stored during CreateTotemFrame
	if show then
		-- Show underlying nameplate elements (restore normal view)
		if totem.healthbar then pcall(function() totem.healthbar:Show() end) end
		if totem.healthborder then pcall(function() totem.healthborder:Show() end) end
		if totem.highlighttexture then pcall(function() totem.highlighttexture:SetAlpha(1) end) end
		if totem.raidicon then pcall(function() totem.raidicon:SetAlpha(1) end) end
		if totem.nametext then pcall(function() totem.nametext:Show() end) end
		if totem.leveltext then pcall(function() totem.leveltext:Show() end) end
	else
		-- Hide underlying nameplate elements for clean totem display
		if totem.healthbar then pcall(function() totem.healthbar:Hide() end) end
		if totem.healthborder then pcall(function() totem.healthborder:Hide() end) end
		if totem.highlighttexture then pcall(function() totem.highlighttexture:SetAlpha(0) end) end
		if totem.mobicon then pcall(function() totem.mobicon:Hide() end) end
		if totem.bossicon then pcall(function() totem.bossicon:Hide() end) end
		if totem.raidicon then pcall(function() totem.raidicon:SetAlpha(0) end) end
		if totem.nametext then pcall(function() totem.nametext:Hide() end) end
		if totem.leveltext then pcall(function() totem.leveltext:Hide() end) end
	end
end

function TotemPlates.OnUpdate(self, elapsed)
	if not self.nametext then return end
	local nameplateName = self.nametext:GetText()

	if ( self.active and (nameplateName == NAMEPLATE_TARGET or UnitName("mouseover") == nameplateName or not NAMEPLATE_TARGET) ) then
		self.selectionHighlight:SetAlpha(.25)
	else
		self.selectionHighlight:SetAlpha(0)
	end
end

function TotemPlates:SetTotemAlpha(totem, nameplateText)
	if ( NAMEPLATE_TARGET ) then
		if ( NAMEPLATE_TARGET == nameplateText ) then -- is target
			if ( Gladdy.db.npTotemPlatesAlphaAlwaysTargeted ) then
				totem:SetAlpha(Gladdy.db.npTotemColors["totem" .. totem.active.id].alpha)
			else
				totem:SetAlpha(1)
			end
		else -- is not target
			totem:SetAlpha(Gladdy.db.npTotemColors["totem" .. totem.active.id].alpha)
		end
	else -- no target
		if ( Gladdy.db.npTotemPlatesAlphaAlways ) then
			totem:SetAlpha(Gladdy.db.npTotemColors["totem" .. totem.active.id].alpha)
		else
			totem:SetAlpha(0.95)
		end
	end
end

---------------------------------------------------

-- Test

---------------------------------------------------

function TotemPlates:TestOnce()
	local test = self.testFrame

	if ( Gladdy.db.npTotems ) then
		if ( not test ) then
			test = CreateFrame("Frame")
			test:SetSize(1, 32)
			test:SetPoint("CENTER", UIParent, "CENTER", 0, -175)
			self.testFrame = test

			self:CreateTotemFrame(test, true)

			local totem = test.gladdyTotemFrame
			totem:SetParent(test)
			totem:ClearAllPoints()
			totem:SetPoint("CENTER", test, "CENTER", 0, 0)
			totem.totemIcon:SetTexture(totemData["tremor totem"].texture)
			totem.totemName:SetText("Gladdy: Totem Plates")
		end

		local totem = test.gladdyTotemFrame
		local totemInfo = Gladdy.db.npTotemColors["totem" .. totemData["tremor totem"].id]

		totem:SetSize(Gladdy.db.npTotemPlatesSize * Gladdy.db.npTotemPlatesWidthFactor, Gladdy.db.npTotemPlatesSize)
		totem.totemName:SetFont(Gladdy:SMFetch("font", "npTremorFont"), Gladdy.db.npTremorFontSize, "OUTLINE")
		totem.totemName:SetPoint("TOP", totem, "BOTTOM", Gladdy.db.npTremorFontXOffset, Gladdy.db.npTremorFontYOffset)
		totem.totemBorder:SetTexture(Gladdy.db.npTotemPlatesBorderStyle)
		totem.totemBorder:SetVertexColor(totemInfo.color.r, totemInfo.color.g, totemInfo.color.b, totemInfo.color.a)
		totem:SetAlpha(1) -- Ensure full visibility for test mode
		totem:Show()

		test:Show()
	elseif ( test ) then
		test:Hide()
	end
end

function TotemPlates:Reset()
	local test = self.testFrame
	if ( test ) then
		test:Hide()
	end
	
	-- Clear pulse timer data
	timestamp = {}
	activeNameplates = {}
end


---------------------------------------------------

-- Interface options

---------------------------------------------------

function TotemPlates:GetOptions()
	return {
		headerTotems = {
			type = "header",
			name = L["Totem Plates"],
			order = 2,
		},
		npTotems = Gladdy:option({
			type = "toggle",
			name = L["Enabled"],
			desc = L["Turns totem icons instead of nameplates on or off."],
			order = 3,
			width = 0.9,
		}),
		npTotemPulseTimer = Gladdy:option({
			type = "toggle",
			name = L["Pulse Timer"],
			desc = L["Shows a pulse timer for Tremor and Cleansing totems."],
			disabled = function() return not Gladdy.db.npTotems end,
			order = 3.5,
			width = 0.9,
		}),
		npTotemsShowFriendly = Gladdy:option({
			type = "toggle",
			name = L["Show friendly"],
			desc = L["Turns totem icons instead of nameplates on or off."],
			disabled = function() return not Gladdy.db.npTotems end,
			order = 4,
			width = 0.65,
		}),
		npTotemsShowEnemy = Gladdy:option({
			type = "toggle",
			name = L["Show enemy"],
			desc = L["Turns totem icons instead of nameplates on or off."],
			disabled = function() return not Gladdy.db.npTotems end,
			order = 5,
			width = 0.6,
		}),
		group = {
			type = "group",
			childGroups = "tree",
			name = L["Frame"],
			disabled = function() return not Gladdy.db.npTotems end,
			order = 4,
			args = {
				icon = {
					type = "group",
					name = L["Icon"],
					order = 1,
					args = {
						header = {
							type = "header",
							name = L["Icon"],
							order = 1,
						},
						npTotemPlatesSize = Gladdy:option({
							type = "range",
							name = L["Totem size"],
							desc = L["Size of totem icons"],
							order = 5,
							min = 5,
							max = 100,
							step = 1,
							width = "full",
						}),
						npTotemPlatesWidthFactor = Gladdy:option({
							type = "range",
							name = L["Icon Width Factor"],
							desc = L["Stretches the icon"],
							order = 6,
							min = 0.5,
							max = 2,
							step = 0.05,
							width = "full",
						}),
					},
				},
				font = {
					type = "group",
					name = L["Font"],
					order = 2,
					args = {
						header = {
							type = "header",
							name = L["Font"],
							order = 1,
						},
						npTremorFont = Gladdy:option({
							type = "select",
							name = L["Font"],
							desc = L["Font of the custom totem name"],
							order = 11,
							dialogControl = "LSM30_Font",
							values = AceGUIWidgetLSMlists.font,
						}),
						npTremorFontSize = Gladdy:option({
							type = "range",
							name = L["Size"],
							desc = L["Scale of the font"],
							order = 12,
							min = 1,
							max = 50,
							step = 0.1,
							width = "full",
						}),
						npTremorFontXOffset = Gladdy:option({
							type = "range",
							name = L["Horizontal offset"],
							desc = L["Scale of the font"],
							order = 13,
							min = -300,
							max = 300,
							step = 1,
							width = "full",
						}),
						npTremorFontYOffset = Gladdy:option({
							type = "range",
							name = L["Vertical offset"],
							desc = L["Scale of the font"],
							order = 14,
							min = -300,
							max = 300,
							step = 1,
							width = "full",
						}),
					},
				},
				alpha = {
					type = "group",
					name = L["Alpha"],
					order = 4,
					args = {
						header = {
							type = "header",
							name = L["Alpha"],
							order = 1,
						},
						npTotemPlatesAlphaAlways = Gladdy:option({
							type = "toggle",
							name = L["Apply alpha when no target"],
							desc = L["Always applies alpha, even when you don't have a target. Else it is 1."],
							width = "full",
							order = 21,
						}),
						npTotemPlatesAlphaAlwaysTargeted = Gladdy:option({
							type = "toggle",
							name = L["Apply alpha when targeted"],
							desc = L["Always applies alpha, even when you target the totem. Else it is 1."],
							width = "full",
							order = 22,
						}),
						npAllTotemAlphas = {
							type = "range",
							name = L["All totem border alphas (configurable per totem)"],
							min = 0,
							max = 1,
							step = 0.1,
							width = "full",
							order = 23,
							get = function()
								local alpha, i = nil, 1
								for _,v in pairs(Gladdy.dbi.profile.npTotemColors) do
									if i == 1 then
										alpha = v.alpha
										i = i + 1
									else
										if v.alpha ~= alpha then
											return ""
										end
									end
								end
								return alpha
							end,
							set = function(_, value)
								for _,v in pairs(Gladdy.dbi.profile.npTotemColors) do
									v.alpha = value
								end
								Gladdy:UpdateFrame()
							end,
						},
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
							order = 1,
						},
						npTotemPlatesBorderStyle = Gladdy:option({
							type = "select",
							name = L["Totem icon border style"],
							order = 41,
							values = Gladdy:GetIconStyles()
						}),
						npAllTotemColors = {
							type = "color",
							name = L["All totem border color"],
							order = 42,
							hasAlpha = true,
							get = function()
								local color
								local i = 1
								for _,v in pairs(Gladdy.dbi.profile.npTotemColors) do
									if i == 1 then
										color = v.color
										i = i + 1
									else
										if v.color.r ~= color.r or v.color.g ~= color.g or v.color.b ~= color.b or v.color.a ~= color.a then
											return 0, 0, 0, 0
										end
									end
								end
								return color.r, color.g, color.b, color.a
							end,
							set = function(_, r, g, b, a)
								for _,v in pairs(Gladdy.dbi.profile.npTotemColors) do
									v.color.r = r
									v.color.g = g
									v.color.b = b
									v.color.a = a
								end
								Gladdy:UpdateFrame()
							end,
						},
					},
				},
			},
		},
		npTotemColors = {
			order = 50,
			name = L["Customize Totems"],
			type = "group",
			childGroups = "tree",
			disabled = function() return not Gladdy.db.npTotems end,
			args = select(2, GetTotemColorDefaultOptions())
		},
	}
end