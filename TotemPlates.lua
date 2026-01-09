local select, pairs, tremove, tinsert, format, strsplit, tonumber, ipairs = select, pairs, tremove, tinsert, format, strsplit, tonumber, ipairs
local Gladdy = LibStub("Gladdy")
local L = Gladdy.L
local UnitName, GetSpellInfo, CreateFrame, WorldFrame, C_Timer_Tick = UnitName, GetSpellInfo, CreateFrame, WorldFrame, C_Timer.NewTicker
local totemData, totemNameTotemData = Gladdy:GetTotemData()

local NAMEPLATE_TIMER
local NAMEPLATE_THROTTLE = .5
local NAMEPLATE_NUM = 0
local NAMEPLATE_NUM_PREVIOUS = 1
local NAMEPLATE_TARGET

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
})

function TotemPlates.OnEvent(self, event, ...)
	local Func = TotemPlates[event]
	if ( Func ) then
		Func(self, ...)
	end
end

function TotemPlates:Initialize()
	-- Detect nameplate addons and set appropriate mode
	-- Mode determines how we interact with nameplates

	-- NotPlater: Works differently - has its own frame structure
	-- We need to hook into NotPlater's frames instead
	if IsAddOnLoaded("NotPlater") or IsAddOnLoaded("NotPlater-3.3.5") or IsAddOnLoaded("NotPlater-2.4.3") then
		self.addon = "NotPlater"
		-- NotPlater stores frames in NotPlater.frames table
		-- We'll hook into those instead of raw nameplates
	end

	-- Plater (retail-style nameplate addon)
	if IsAddOnLoaded("Plater") then
		self.addon = "Plater"
	end

	-- NeatPlates / ThreatPlates
	if IsAddOnLoaded("NeatPlates") then
		self.addon = "NeatPlates"
	end
	if IsAddOnLoaded("ThreatPlates") then
		self.addon = "ThreatPlates"
	end

	-- Kui_Nameplates: Can coexist if we disable Kui's TotemPlates module
	if IsAddOnLoaded("Kui_Nameplates") then
		self.addon = "Kui_Nameplates"
		local kuiAddon = LibStub("AceAddon-3.0"):GetAddon("KuiNameplates", true)
		if kuiAddon then
			-- Disable Kui's TotemPlates if it exists
			if kuiAddon.modules and kuiAddon.modules.TotemPlates then
				local kuiTotemPlates = kuiAddon.modules.TotemPlates
				if kuiTotemPlates and kuiTotemPlates:IsEnabled() then
					kuiTotemPlates:Disable()
					Gladdy:Print("Kui_Nameplates TotemPlates disabled: Gladdy TotemPlates active")
				end
			end
		end
	end

	-- TidyPlates: We have special handling for this
	if IsAddOnLoaded("TidyPlates") then
		self.addon = "TidyPlates"
	end

	-- ElvUI: Only conflict if ElvUI nameplates are enabled
	if IsAddOnLoaded("ElvUI") then
		local E = ElvUI and unpack(ElvUI)
		if E and E.private and E.private.nameplates and E.private.nameplates.enable then
			self.addon = "ElvUI"
		end
	end

	TotemPlates.void = function()end
	self:SetScript("OnEvent", TotemPlates.OnEvent)
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

local function NameplateScanValid(self)
	if ( not self ) then
		return false
	end

	-- For addon-managed nameplates, check for their specific frame markers
	if ( TotemPlates.addon ) then
		if ( TotemPlates.addon == "NotPlater" ) then
			-- NotPlater marks its frames with npFrame
			return self.npFrame or self.npHealthBar
		elseif ( TotemPlates.addon == "Kui_Nameplates" ) then
			return self.kui
		elseif ( TotemPlates.addon == "TidyPlates" ) then
			return self.extended
		elseif ( TotemPlates.addon == "NeatPlates" or TotemPlates.addon == "ThreatPlates" ) then
			return self.extended or self.carrier
		elseif ( TotemPlates.addon == "Plater" ) then
			return self.PlaterOnScreen or self.unitFrame
		elseif ( TotemPlates.addon == "ElvUI" ) then
			return self.UnitFrame
		end
	end

	-- Default: Check for vanilla nameplate texture
	if ( not self:GetName() ) then
		local _, obj = self:GetRegions()
		if ( obj and obj:GetObjectType() == "Texture" ) then
			local tex = obj:GetTexture()
			return tex == "Interface\\Tooltips\\Nameplate-Border" or
			       tex == "Interface\\TargetingFrame\\UI-TargetingFrame-Flash"
		end
	end

	return false
end

local function NameplateScan(...)
	for i=NAMEPLATE_NUM_PREVIOUS,NAMEPLATE_NUM do
		local nameplate = select(i, ...)
		if ( not nameplate.gladdyTotemFrame and NameplateScanValid(nameplate) ) then
			TotemPlates:CreateTotemFrame(nameplate)
		end
	end
end

local function NameplateHandler()
	NAMEPLATE_NUM = WorldFrame:GetNumChildren()

	if ( NAMEPLATE_NUM ~= NAMEPLATE_NUM_PREVIOUS ) then
		NameplateScan(WorldFrame:GetChildren())
		NAMEPLATE_NUM_PREVIOUS = NAMEPLATE_NUM
	end
end

---------------------------------------------------

-- Events

---------------------------------------------------

local function PLAYER_TARGET_CHANGED_UPDATE(nameplate, ...)
	if ( nameplate ) then
		local totem = nameplate.gladdyTotemFrame

		if ( totem and totem.active ) then
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
		if ( totem ) then
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

						TotemPlates:SetTotemAlpha(totem, nameplateText)
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
		end

		TotemPlates:ToggleAddon(nameplate, true)
	end
end

function TotemPlates:PLAYER_ENTERING_WORLD()
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self:SetFrameStrata("BACKGROUND") -- Prevent icons from overlapping other frames.
	self:UpdateFrameOnce()
end

---------------------------------------------------

-- Gladdy Call

---------------------------------------------------

local function SettingRefresh(enabled, nameplate, ...)
	if ( nameplate ) then
		local totem = nameplate.gladdyTotemFrame

		if ( totem ) then
			if ( enabled and TotemPlates:NameplateTypeValid(totem) ) then
				if ( nameplate:IsShown() ) then
					TotemPlates:NAME_PLATE_UNIT_ADDED(nameplate)
				end

				totem:SetSize(Gladdy.db.npTotemPlatesSize * Gladdy.db.npTotemPlatesWidthFactor, Gladdy.db.npTotemPlatesSize)
				totem.totemName:SetFont(Gladdy:SMFetch("font", "npTremorFont"), Gladdy.db.npTremorFontSize, "OUTLINE")
				totem.totemName:SetPoint("TOP", totem, "BOTTOM", Gladdy.db.npTremorFontXOffset, Gladdy.db.npTremorFontYOffset)
				totem.totemBorder:SetTexture(Gladdy.db.npTotemPlatesBorderStyle)
			else
				TotemPlates:NAME_PLATE_UNIT_REMOVED(nameplate)
			end
		end

		return SettingRefresh(enabled, ...)
	end
end

function TotemPlates:UpdateFrameOnce()
	-- If disabled due to incompatible addon, do nothing
	if self.disabled then
		return
	end

	-- Ascension compatibility: These CVars might not exist or have side effects
	-- Protect with pcall to prevent errors
	if ( Gladdy.db.npTotems and Gladdy.db.npTotemsShowEnemy ) then
		pcall(SetCVar, "nameplateShowEnemyTotems", 1)
	end

	if ( Gladdy.db.npTotems and Gladdy.db.npTotemsShowFriendly ) then
		pcall(SetCVar, "nameplateShowFriendlyTotems", 1)
	end

	if ( Gladdy.db.npTotems ) then
		self:RegisterEvent("PLAYER_TARGET_CHANGED")
		self:SetScript("OnEvent", TotemPlates.OnEvent)

		if ( not NAMEPLATE_TIMER ) then
			NAMEPLATE_TIMER = C_Timer_Tick(NAMEPLATE_THROTTLE, NameplateHandler)
		end
	else
		self:UnregisterEvent("PLAYER_TARGET_CHANGED")
		self:SetScript("OnEvent", nil)

		if ( NAMEPLATE_TIMER ) then
			NAMEPLATE_TIMER:Cancel()
			NAMEPLATE_TIMER = nil
		end
	end

	if ( NAMEPLATE_NUM ~= 0 ) then
		SettingRefresh(Gladdy.db.npTotems, WorldFrame:GetChildren())

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
	Frame:SetPoint("BOTTOM", nameplate, "TOP", 0, -35)
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
	if ( self.addon == "Kui_Nameplates" ) then
		return nameplate.kui
	elseif ( self.addon == "TidyPlates" or self.addon == "NeatPlates" or self.addon == "ThreatPlates" ) then
		return nameplate.extended or nameplate.carrier
	elseif ( self.addon == "NotPlater" ) then
		return nameplate.npFrame or nameplate
	elseif ( self.addon == "Plater" ) then
		return nameplate.unitFrame or nameplate
	elseif ( self.addon == "ElvUI" ) then
		return nameplate.UnitFrame or nameplate
	else
		return nameplate.gladdyTotemFrame
	end
end

function TotemPlates:ToggleAddon(nameplate, show)
	local totemFrame = nameplate.gladdyTotemFrame
	if ( not totemFrame ) then
		return
	end

	-- For third-party nameplate addons, we only hide/show their main frame
	-- We don't try to manipulate individual elements as structures vary
	if ( self.addon ) then
		local addonFrame = self:GetAddonFrame(nameplate)
		if ( addonFrame and addonFrame ~= totemFrame ) then
			if ( self.addon == "Kui_Nameplates" ) then
				if ( show ) then
					addonFrame.Show = nil
					addonFrame.currentAlpha = 1
					addonFrame.lastAlpha = 0
					addonFrame.DoShow = 1
				else
					addonFrame.currentAlpha = 1
					addonFrame.lastAlpha = 1
					addonFrame.DoShow = nil
					addonFrame:Hide()
					addonFrame.Show = TotemPlates.void
				end
			elseif ( self.addon == "NotPlater" ) then
				-- NotPlater: Hide/show the main visual elements
				-- NotPlater uses npHealthBar, npCastBar, etc.
				if ( show ) then
					if ( addonFrame.Show ) then
						addonFrame.Show = nil
					end
					if ( addonFrame.SetAlpha ) then
						addonFrame:SetAlpha(1)
					end
				else
					if ( addonFrame.SetAlpha ) then
						addonFrame:SetAlpha(0)
					end
				end
			elseif ( self.addon == "TidyPlates" or self.addon == "NeatPlates" or self.addon == "ThreatPlates" ) then
				if ( show ) then
					addonFrame.Show = nil
					if ( addonFrame.SetAlpha ) then
						addonFrame:SetAlpha(1)
					end
					addonFrame:Show()
				else
					addonFrame:Hide()
					addonFrame.Show = TotemPlates.void
				end
			elseif ( self.addon == "Plater" or self.addon == "ElvUI" ) then
				if ( show ) then
					addonFrame.Show = nil
					addonFrame:Show()
				else
					addonFrame:Hide()
					addonFrame.Show = TotemPlates.void
				end
			else
				-- Generic handling for unknown addons
				if ( show ) then
					addonFrame.Show = nil
					pcall(addonFrame.Show, addonFrame)
				else
					pcall(addonFrame.Hide, addonFrame)
					addonFrame.Show = TotemPlates.void
				end
			end
		end
		return
	end

	-- Default nameplate handling (no addon)
	if ( show ) then
		if ( totemFrame.healthbar ) then totemFrame.healthbar:Show() end
		if ( totemFrame.healthborder ) then totemFrame.healthborder:Show() end
		if ( totemFrame.highlighttexture ) then totemFrame.highlighttexture:SetAlpha(1) end
		if ( totemFrame.raidicon ) then totemFrame.raidicon:SetAlpha(1) end
		if ( totemFrame.nametext ) then totemFrame.nametext:Show() end
		if ( totemFrame.leveltext ) then totemFrame.leveltext:Show() end
	else
		if ( totemFrame.healthbar ) then totemFrame.healthbar:Hide() end
		if ( totemFrame.healthborder ) then totemFrame.healthborder:Hide() end
		if ( totemFrame.highlighttexture ) then totemFrame.highlighttexture:SetAlpha(0) end
		if ( totemFrame.mobicon ) then totemFrame.mobicon:Hide() end
		if ( totemFrame.bossicon ) then totemFrame.bossicon:Hide() end
		if ( totemFrame.raidicon ) then totemFrame.raidicon:SetAlpha(0) end
		if ( totemFrame.nametext ) then totemFrame.nametext:Hide() end
		if ( totemFrame.leveltext ) then totemFrame.leveltext:Hide() end
	end
end

function TotemPlates.OnUpdate(self, elapsed)
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
		local totem

		if ( not test ) then
			test = CreateFrame("Frame")
			test:SetSize(1, 32)
			test:SetPoint("CENTER", UIParent, "CENTER", 0, -175)
			self.testFrame = test

			self:CreateTotemFrame(test, true)

			totem = test.gladdyTotemFrame
			totem:SetParent(test)
			totem.totemIcon:SetTexture(totemData["tremor totem"].texture)
			totem.totemName:SetText("Gladdy: Totem Plates")
			totem:Show()
		end

		totem = test.gladdyTotemFrame
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

	-- Cleanup totem frames and restore nameplate visibility
	if ( NAMEPLATE_NUM and NAMEPLATE_NUM > 0 ) then
		for i = 1, NAMEPLATE_NUM do
			local nameplate = select(i, WorldFrame:GetChildren())
			if ( nameplate and nameplate.gladdyTotemFrame ) then
				-- Hide and cleanup our totem frame
				local totem = nameplate.gladdyTotemFrame
				if ( totem and totem.active ) then
					TotemPlates:ToggleTotem(totem)
					totem.active = nil
				end

				-- Restore nameplate visibility
				TotemPlates:ToggleAddon(nameplate, true)
			end
		end
	end
end


---------------------------------------------------

-- Interface options

---------------------------------------------------

function TotemPlates:GetOptions()
	local options = {
		headerTotems = {
			type = "header",
			name = L["Totem Plates"],
			order = 2,
		},
	}

	-- Show warning if disabled due to incompatible addon
	if self.disabled and self.addon then
		options.disabledWarning = {
			type = "description",
			name = "|cffff5555WARNING: Gladdy Totem Plates is disabled because " .. self.addon .. " is loaded.|r\n\nTo use Gladdy Totem Plates, disable " .. self.addon .. " or use its built-in totem features instead.\n\n",
			order = 2.5,
			fontSize = "medium",
		}
	end

	options.npTotems = Gladdy:option({
		type = "toggle",
		name = L["Enabled"],
		desc = L["Turns totem icons instead of nameplates on or off."],
		order = 3,
		width = 0.9,
		disabled = function() return self.disabled end,
	})

	options.npTotemsShowFriendly = Gladdy:option({
		type = "toggle",
		name = L["Show friendly"],
		desc = L["Turns totem icons instead of nameplates on or off."],
		disabled = function() return not Gladdy.db.npTotems end,
		order = 4,
		width = 0.65,
	})

	options.npTotemsShowEnemy = Gladdy:option({
		type = "toggle",
		name = L["Show enemy"],
		desc = L["Turns totem icons instead of nameplates on or off."],
		disabled = function() return not Gladdy.db.npTotems end,
		order = 5,
		width = 0.6,
	})

	options.group = {
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
							min = 20,
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
	}

	options.npTotemColors = {
		order = 50,
		name = L["Customize Totems"],
		type = "group",
		childGroups = "tree",
		disabled = function() return not Gladdy.db.npTotems end,
		args = select(2, GetTotemColorDefaultOptions())
	}

	return options
end