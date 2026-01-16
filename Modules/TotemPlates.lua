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

-- Duration Bar Update (for totems like Capacitor Totem)
local function OnUpdateDurationBar(self)
    local elapsed = GetTime() - self.durationStart
    local remaining = self.durationTotal - elapsed
    
    if remaining <= 0 then
        if self.durationBar then
            self.durationBarBg:Hide()
            self.durationBar:Hide()
            self.durationText:Hide()
        end
        self:SetScript("OnUpdate", nil)
        return
    end
    
    local progress = remaining / self.durationTotal
    if self.durationBar then
        self.durationBar:SetWidth(Gladdy.db.npTotemPlatesSize * Gladdy.db.npTotemPlatesWidthFactor * progress)
        self.durationText:SetText(string.format("%.1f", remaining))
    end
end

local function HideDurationBar(totem)
    if totem and totem.durationBar then
        totem.durationBarBg:Hide()
        totem.durationBar:Hide()
        totem.durationText:Hide()
        totem:SetScript("OnUpdate", nil)
        totem.durationStart = nil
        totem.durationTotal = nil
    end
end

local function ShowDurationBar(totem, duration)
    if not totem then return end
    
    -- Create duration bar elements if they don't exist
    if not totem.durationBarBg then
        local size = Gladdy.db.npTotemPlatesSize
        local width = size * Gladdy.db.npTotemPlatesWidthFactor
        local barHeight = 4
        
        -- Background
        local bg = totem:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOP", totem, "BOTTOM", 0, -2)
        bg:SetSize(width, barHeight)
        bg:SetColorTexture(0, 0, 0, 0.7)
        totem.durationBarBg = bg
        
        -- Progress bar
        local bar = totem:CreateTexture(nil, "ARTWORK")
        bar:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
        bar:SetHeight(barHeight)
        bar:SetColorTexture(0.9, 0.1, 0.9, 1)
        totem.durationBar = bar
        
        -- Timer text
        local text = totem:CreateFontString(nil, "OVERLAY")
        text:SetFont("Fonts\\ARIALN.TTF", 8, "OUTLINE")
        text:SetPoint("CENTER", bg, "CENTER", 0, 0)
        text:SetTextColor(1, 1, 1)
        totem.durationText = text
    end
    
    local width = Gladdy.db.npTotemPlatesSize * Gladdy.db.npTotemPlatesWidthFactor
    totem.durationBarBg:SetWidth(width)
    totem.durationBar:SetWidth(width)
    
    totem.durationStart = GetTime()
    totem.durationTotal = duration
    totem.durationText:SetText(string.format("%.1f", duration))
    totem.durationBarBg:Show()
    totem.durationBar:Show()
    totem.durationText:Show()
    totem:SetScript("OnUpdate", OnUpdateDurationBar)
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
        totem.pulseText:SetTextColor(1, 1, 0)
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
                HideDurationBar(nameplate.gladdyTotemFrame)
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
        HideDurationBar(nameplate.gladdyTotemFrame)
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
	if ( IsAddOnLoaded("Kui_Nameplates") ) then
		self.addon = "Kui_Nameplates"
	elseif ( IsAddOnLoaded("TidyPlates") ) then
		self.addon = "TidyPlates"
	elseif ( IsAddOnLoaded("TurboPlates") ) then
		self.addon = "TurboPlates"
	elseif ( IsAddOnLoaded("ElvUI") ) then
		local E = unpack(ElvUI)
		if ( E.private.nameplates.enable ) then
			return
		end
	end

	TotemPlates.void = function()end
	self:SetScript("OnEvent", TotemPlates.OnEvent)
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

local function NameplateScanValid(self)
	if ( self ) then
		if ( TotemPlates.addon ) then
			return TotemPlates:GetAddonFrame(self)
		elseif ( not self:GetName() ) then
			local _, obj = self:GetRegions()
			if ( obj and obj:GetObjectType() == "Texture" ) then
				return obj:GetTexture() == "Interface\\Tooltips\\Nameplate-Border"
			end
		end
	end
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

		if ( totem and totem.active ) then
			local totemName = totem.activeName or (totem.nametext and totem.nametext:GetText())
			if totemName then
				TotemPlates:SetTotemAlpha(totem, totemName)
			end
		end

		return PLAYER_TARGET_CHANGED_UPDATE(...)
	end
end

function TotemPlates:PLAYER_TARGET_CHANGED()
	NAMEPLATE_TARGET = UnitName("target")

	-- Always update alphas (both when targeting and untargeting)
	PLAYER_TARGET_CHANGED_UPDATE(WorldFrame:GetChildren())
end

function TotemPlates:NAME_PLATE_UNIT_ADDED(nameplateOrUnit, unit)
	if ( Gladdy.db.npTotems ) then
		local nameplate = nameplateOrUnit
		
		-- Handle different call contexts:
		-- 1. From OnShow hook: nameplateOrUnit is the nameplate frame (self in hook context)
		-- 2. From event via OnEvent: nameplateOrUnit is unit string like "nameplate1"
		-- 3. Direct call: nameplateOrUnit is nameplate frame, unit may be passed
		if ( type(nameplateOrUnit) == "string" ) then
			-- Called from event - first arg is unit token
			unit = nameplateOrUnit
			nameplate = C_NamePlate.GetNamePlateForUnit(unit)
		elseif ( not nameplateOrUnit ) then
			nameplate = self -- OnShow hook context
		end
		
		if ( not nameplate ) then return end

		local totem = nameplate.gladdyTotemFrame
		if ( totem ) then
			-- TurboPlates hides Blizzard elements, so use UnitName instead of nametext:GetText()
			local nameplateText
			if ( self.addon == "TurboPlates" ) then
				-- Try unit token first, then fallback to stored token
				if ( unit ) then
					nameplateText = UnitName(unit)
				elseif ( nameplate.namePlateUnitToken ) then
					nameplateText = UnitName(nameplate.namePlateUnitToken)
				end
			end
			-- Fallback to Blizzard nametext for non-TurboPlates addons
			if ( not nameplateText and totem.nametext ) then
				nameplateText = totem.nametext:GetText()
			end
			local totemData = totemNameTotemData[nameplateText]

			if ( totemData ) then
				if ( TotemPlates:NameplateTypeValid(totem, unit) ) then
					local totemInfo = Gladdy.db.npTotemColors["totem" .. totemData.id]

					if ( totemInfo.enabled ) then
						totem.totemIcon:SetTexture(totemData.texture)
						totem.totemBorder:SetVertexColor(totemInfo.color.r, totemInfo.color.g, totemInfo.color.b, totemInfo.color.a)
						totem.totemName:SetText(totemInfo.customText or "")

						TotemPlates:ToggleTotem(totem, true)
						TotemPlates:ToggleAddon(nameplate)
						totem.active = totemData
						totem.activeName = nameplateText  -- Store name for TurboPlates compat

						TotemPlates:SetTotemAlpha(totem, nameplateText)

						-- Check if this is a tremor or cleansing totem and add pulse timer
						if Gladdy.db.npTotemPulseTimer and (nameplateText == "Tremor Totem" or nameplateText == "Cleansing Totem") then
							local fakeGUID = "totem_" .. GetTime()
							timestamp[fakeGUID] = { timeStamp = GetTime() }
							ShowPulse(totem, timestamp[fakeGUID])
						end
						
						-- Check if this totem has a duration (like Capacitor Totem)
						if Gladdy.db.npTotemPulseTimer and totemData.duration then
							ShowDurationBar(totem, totemData.duration)
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
			totem.activeName = nil
		end

		-- Hide pulse timer and duration bar if they exist
		HidePulse(totem)
		HideDurationBar(totem)

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
			-- For TurboPlates, skip SettingRefresh validation since we don't have unit token here
			-- The actual validation happens in NAME_PLATE_UNIT_ADDED when event fires
			local isValid = TotemPlates.addon == "TurboPlates" or TotemPlates:NameplateTypeValid(totem, nil)
			if ( Gladdy.db.npTotems and isValid ) then
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
	local Frame = CreateFrame("Frame", nil, WorldFrame) -- Parent prevents parental alpha.
	Frame:SetPoint("BOTTOM", nameplate, "TOP", 0, -25)
	Frame:SetSize(Gladdy.db.npTotemPlatesSize * Gladdy.db.npTotemPlatesWidthFactor, Gladdy.db.npTotemPlatesSize)
	Frame:Hide()
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

		-- References
		local threatglow, castbar, castbarborder, castbarinterrupt, castbaricon -- Unused
		Frame.healthbar, castbar = nameplate:GetChildren()
		threatglow, Frame.healthborder, castborder, castinterrupt, casticon, Frame.highlighttexture, Frame.nametext, Frame.leveltext, Frame.bossicon, Frame.raidicon, Frame.mobicon = nameplate:GetRegions()

		-- Hooks
		nameplate:HookScript("OnHide", TotemPlates.NAME_PLATE_UNIT_REMOVED)
		nameplate:HookScript("OnShow", TotemPlates.NAME_PLATE_UNIT_ADDED)

		self:NAME_PLATE_UNIT_ADDED(nameplate)
	end
end

---------------------------------------------------

-- Nameplate functions

---------------------------------------------------

function TotemPlates:NameplateTypeValid(totemFrame, unit)
	local friendly
	
	-- TurboPlates: Blizzard healthbar is reparented, use UnitIsFriend instead
	if ( self.addon == "TurboPlates" and unit ) then
		friendly = UnitIsFriend("player", unit)
	elseif ( totemFrame.healthbar ) then
		local r, g = totemFrame.healthbar:GetStatusBarColor()
		friendly = (r == 0 and g > 0.9)
	else
		return false
	end

	if ( (Gladdy.db.npTotemsShowFriendly and friendly) or (Gladdy.db.npTotemsShowEnemy and not friendly) ) then
		return true
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
	if ( self.addon == "Kui_Nameplates" ) then
		return nameplate.kui
	elseif ( self.addon == "TidyPlates" ) then
		return nameplate.extended
	elseif ( self.addon == "TurboPlates" ) then
		-- Return myPlate if exists, otherwise nil (liteContainer handled separately)
		return nameplate.myPlate
	else
		return nameplate.gladdyTotemFrame
	end
end

function TotemPlates:ToggleAddon(nameplate, show)
	local addon = TotemPlates:GetAddonFrame(nameplate)

	if ( self.addon ) then
		if ( addon ) then
			local isKui = self.addon == "Kui_Nameplates"
			local isTurbo = self.addon == "TurboPlates"

			if ( show ) then
				addon.Show = nil

				if ( isKui ) then
					addon.currentAlpha = 1
					addon.lastAlpha = 0
					addon.DoShow = 1
				elseif ( isTurbo ) then
					-- TurboPlates: Don't show here - plate is being removed.
					-- If plate reappears for non-totem, FullPlateUpdate will show it.
				else
					addon:Show()
				end
			else
				if ( isKui ) then
					addon.currentAlpha = 1
					addon.lastAlpha = 1
					addon.DoShow = nil
				elseif ( isTurbo ) then
					-- TurboPlates: hide myPlate if it exists
					if addon then addon:Hide() end
					-- Also hide liteContainer (name-only mode)
					if nameplate.liteContainer then nameplate.liteContainer:Hide() end
				end

				if ( not isTurbo ) then
					addon:Hide()
					addon.Show = TotemPlates.void
				end
			end
		end
	else
		if ( show ) then
			addon.healthbar:Show()
			addon.healthborder:Show()
			addon.highlighttexture:SetAlpha(1)
			addon.raidicon:SetAlpha(1)
			addon.nametext:Show()
			addon.leveltext:Show()
		else
			addon.healthbar:Hide()
			addon.healthborder:Hide()
			addon.highlighttexture:SetAlpha(0)
			addon.mobicon:Hide()
			addon.bossicon:Hide()
			addon.raidicon:SetAlpha(0)
			addon.nametext:Hide()
			addon.leveltext:Hide()
		end
	end
end

function TotemPlates.OnUpdate(self, elapsed)
	-- TurboPlates hides vanilla nametext, use stored totem name instead
	local nameplateName = self.activeName
	if not nameplateName and self.nametext then
		nameplateName = self.nametext:GetText()
	end

	if ( self.active and nameplateName and (nameplateName == NAMEPLATE_TARGET or UnitName("mouseover") == nameplateName or not NAMEPLATE_TARGET) ) then
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
			totem.totemIcon:SetTexture(totemData["tremor totem"].texture)
			totem.totemName:SetText("Gladdy: Totem Plates")
			totem:Show()
		end

		local totem = test.gladdyTotemFrame
		local totemInfo = Gladdy.db.npTotemColors["totem" .. totemData["tremor totem"].id]

		totem:SetSize(Gladdy.db.npTotemPlatesSize * Gladdy.db.npTotemPlatesWidthFactor, Gladdy.db.npTotemPlatesSize)
		totem.totemName:SetFont(Gladdy:SMFetch("font", "npTremorFont"), Gladdy.db.npTremorFontSize, "OUTLINE")
		totem.totemName:SetPoint("TOP", totem, "BOTTOM", Gladdy.db.npTremorFontXOffset, Gladdy.db.npTremorFontYOffset)
		totem.totemBorder:SetTexture(Gladdy.db.npTotemPlatesBorderStyle)
		totem.totemBorder:SetVertexColor(totemInfo.color.r, totemInfo.color.g, totemInfo.color.b, totemInfo.color.a)

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