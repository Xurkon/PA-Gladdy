local select, string_gsub, tostring, pairs, ipairs = select, string.gsub, tostring, pairs, ipairs
local wipe = wipe
local unpack = unpack

local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local AURA_TYPE_DEBUFF = AURA_TYPE_DEBUFF
local AURA_TYPE_BUFF = AURA_TYPE_BUFF

local UnitName, UnitAura, UnitRace, UnitClass, UnitGUID, UnitIsUnit, UnitExists = UnitName, (C_UnitAura or UnitAura), UnitRace, UnitClass, UnitGUID, UnitIsUnit, UnitExists
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local GetSpellInfo = GetSpellInfo
local FindAuraByName = AuraUtil.FindAuraByName
local GetTime = GetTime

local Gladdy = LibStub("Gladdy")
local L = Gladdy.L
local Cooldowns = Gladdy.modules["Cooldowns"]
local Diminishings = Gladdy.modules["Diminishings"]

local PVP_TRINKET, NS, EM, POM, FD

-- Stealth spells for detection (populated in Initialize)
local STEALTH_SPELLS = {}
-- Spells that MAINTAIN stealth (clearing these = no longer stealthed)
-- Vanish is NOT included because it's a temporary buff that fades into Stealth
local STEALTH_AURAS = {}

local EventListener = Gladdy:NewModule("EventListener", 101, {
    test = true,
})

function EventListener:Initialize()
    PVP_TRINKET = GetSpellInfo(42292)
    NS = GetSpellInfo(16188)
    EM = GetSpellInfo(16166)
    POM = GetSpellInfo(12043)
    FD = GetSpellInfo(5384)

    -- Build stealth spells table for stealth detection
    -- STEALTH_SPELLS = all spells that indicate going INTO stealth (used to prevent clearing stealth on cast)
    STEALTH_SPELLS["Stealth"] = true
    STEALTH_SPELLS["Vanish"] = true
    STEALTH_SPELLS["Shadowmeld"] = true
    STEALTH_SPELLS["Prowl"] = true
    -- STEALTH_AURAS = buffs that MAINTAIN stealth (removing these = no longer stealthed)
    -- Vanish is NOT here because it's a temporary buff that fades into regular Stealth
    STEALTH_AURAS["Stealth"] = true
    STEALTH_AURAS["Shadowmeld"] = true
    STEALTH_AURAS["Prowl"] = true
    -- Overkill = rogue talent that procs when entering stealth (reliable stealth indicator on Ascension)
    STEALTH_SPELLS["Overkill"] = true
    -- Master of Subtlety procs when LEAVING stealth, so we track it to know they WERE stealthed
    -- (not added to STEALTH_SPELLS since it means they're OUT of stealth)
    -- Add localized spell names
    local stealthName = GetSpellInfo(1784)   -- Stealth
    local vanishName = GetSpellInfo(1856)    -- Vanish
    local shadowmeldName = GetSpellInfo(58984) -- Shadowmeld
    local prowlName = GetSpellInfo(5215)     -- Prowl
    if stealthName then
        STEALTH_SPELLS[stealthName] = true
        STEALTH_AURAS[stealthName] = true
    end
    if vanishName then STEALTH_SPELLS[vanishName] = true end  -- Vanish only in STEALTH_SPELLS, NOT STEALTH_AURAS
    if shadowmeldName then
        STEALTH_SPELLS[shadowmeldName] = true
        STEALTH_AURAS[shadowmeldName] = true
    end
    if prowlName then
        STEALTH_SPELLS[prowlName] = true
        STEALTH_AURAS[prowlName] = true
    end

    -- Store for debug access
    Gladdy.STEALTH_SPELL_NAMES = {
        stealth = stealthName,
        vanish = vanishName,
        shadowmeld = shadowmeldName,
        prowl = prowlName
    }

    self:RegisterMessage("JOINED_ARENA")
end

function EventListener.OnEvent(self, event, ...)
    EventListener[event](self, ...)
end

function EventListener:JOINED_ARENA()
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterEvent("ARENA_OPPONENT_UPDATE")
    self:RegisterEvent("UNIT_AURA")
    self:RegisterEvent("UNIT_SPELLCAST_START")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    -- in case arena has started already we check for units
    for i=1,Gladdy.curBracket do
        if Gladdy.buttons["arena"..i].lastAuras then
            wipe(Gladdy.buttons["arena"..i].lastAuras)
        end
        if UnitExists("arena" .. i) then
            Gladdy:SpotEnemy("arena" .. i, true)
        end
        if UnitExists("arenapet" .. i) then
            Gladdy:SendMessage("PET_SPOTTED", "arenapet" .. i)
        end
    end
    self:SetScript("OnEvent", EventListener.OnEvent)
end

function EventListener:Reset()
    self:UnregisterAllEvents()
    self:SetScript("OnEvent", nil)
end

function Gladdy:SpotEnemy(unit, auraScan)
    local button = self.buttons[unit]
    if not unit or not button then
        return
    end
    if UnitExists(unit) then
        local classLoc, class = UnitClass(unit)
        local raceLoc, race = UnitRace(unit)
        local name = UnitName(unit)
        local guid = UnitGUID(unit)

        -- Ascension compatibility: UnitClass/UnitRace may return nil initially
        -- Store values only if valid, keep previous values otherwise
        if raceLoc and raceLoc ~= "" then
            button.raceLoc = raceLoc
        end
        if race and race ~= "" then
            button.race = race
        end
        if classLoc and classLoc ~= "" then
            button.classLoc = classLoc
        end
        if class and class ~= "" then
            button.class = class
        end
        if name and name ~= "" then
            button.name = name
        end
        if guid then
            Gladdy.guids[guid] = unit
        end

        -- If data incomplete, retry after short delay (Ascension server delay)
        -- Only retry once per unit to avoid multiple retries conflicts
        if (not button.class or button.class == "" or not button.race or button.race == "") then
            if not button.retryScheduled then
                button.retryScheduled = true
                C_Timer.After(0.5, function()
                    if UnitExists(unit) then
                        button.retryScheduled = nil
                        Gladdy:SpotEnemy(unit, true)
                    end
                end)
            end
        else
            -- Data is complete, clear retry flag
            button.retryScheduled = nil
        end
    end
    if button.class and button.class ~= "" and button.race and button.race ~= "" then
        Gladdy:SendMessage("ENEMY_SPOTTED", unit)
    end
    if auraScan and not button.spec then
        Gladdy:SendMessage("AURA_FADE", unit, "HELPFUL")
        for n = 1, 30 do
            -- WotLK 3.3.5 / Ascension signature includes 'rank' as 2nd return value
            local spellName, rank, texture, count, dispelType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellID = UnitAura(unit, n, "HELPFUL")
            if ( not spellName ) then
                Gladdy:SendMessage("AURA_GAIN_LIMIT", unit, AURA_TYPE_BUFF, n - 1)
                break
            end

            if spellID and Gladdy.exceptionNames[spellID] then
                spellName = Gladdy.exceptionNames[spellID]
            end

            if Gladdy.specBuffs[spellName] and unitCaster then -- Check for auras that detect a spec
                -- Detect spec on the CASTER of the buff, not just self-buffs
                -- This allows detecting Disc priest when Grace/Divine Aegis appears on allies
                for arenaUnit, arenaButton in pairs(Gladdy.buttons) do
                    if not arenaButton.spec and UnitIsUnit(arenaUnit, unitCaster) then
                        EventListener:DetectSpec(arenaUnit, Gladdy.specBuffs[spellName])
                        break
                    end
                end
            end
            if Gladdy.cooldownBuffs[spellName] and unitCaster then -- Check for auras that detect used CDs (like Fear Ward)
                for arenaUnit,v in pairs(self.buttons) do
                    if (UnitIsUnit(arenaUnit, unitCaster)) then
                        Cooldowns:CooldownUsed(arenaUnit, v.class, Gladdy.cooldownBuffs[spellName].spellId, Gladdy.cooldownBuffs[spellName].cd(expirationTime - GetTime()))
                        -- /run LibStub("Gladdy").modules["Cooldowns"]:CooldownUsed("arena5", "PRIEST", 6346, 10)
                    end
                end
            end
            if Gladdy.cooldownBuffs.racials[spellName] and Gladdy.cooldownBuffs.racials[spellName] then
                Gladdy:SendMessage("RACIAL_USED", unit, spellName, Gladdy.cooldownBuffs.racials[spellName].cd(expirationTime - GetTime()), spellName)
            end
            Gladdy:SendMessage("AURA_GAIN", unit, AURA_TYPE_BUFF, spellID, spellName, texture, duration, expirationTime, count, dispelType, n, unitCaster)
        end
    end
end

-- Helper function to find arena unit by GUID (fallback for Ascension GUID format issues)
local function FindArenaUnitByGUID(guid)
    if not guid then return nil end
    -- First try direct lookup
    local unit = Gladdy.guids[guid]
    if unit then return unit end
    -- Fallback: compare with UnitGUID for each arena unit
    for i = 1, Gladdy.curBracket or 5 do
        local arenaUnit = "arena" .. i
        if UnitExists(arenaUnit) and UnitGUID(arenaUnit) == guid then
            -- Cache it for future lookups
            Gladdy.guids[guid] = arenaUnit
            return arenaUnit
        end
        local petUnit = "arenapet" .. i
        if UnitExists(petUnit) and UnitGUID(petUnit) == guid then
            Gladdy.guids[guid] = petUnit
            return petUnit
        end
    end
    return nil
end

function EventListener:COMBAT_LOG_EVENT_UNFILTERED(...)
    -- WotLK 3.3.5 / Ascension format (same as DiminishingReturns addon):
    -- timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellId, spellName, ...
    local timestamp, eventType, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellID, spellName, spellSchool, extraArg1, extraArg2, extraArg3 = ...

    local srcUnit = FindArenaUnitByGUID(sourceGUID) -- can be a PET
    local destUnit = FindArenaUnitByGUID(destGUID) -- can be a PET

    -- DEBUG: Print DR-related events (now checks by name too)
    if Gladdy.DR_DEBUG and eventType == "SPELL_AURA_APPLIED" then
        local drCat = LibStub("DRList-1.0"):GetCategoryBySpellID(spellID, spellName)
        if drCat then
            print("|cff00ff00[DR DEBUG]|r", destName, spellID, spellName, "cat:", drCat, "unit:", destUnit or "NIL")
        end
    end

    if (Gladdy.db.shadowsightTimerEnabled and eventType == "SPELL_AURA_APPLIED" and spellID == 34709) then
        Gladdy.modules["Shadowsight Timer"]:AURA_GAIN(nil, nil, 34709)
    end
    if Gladdy.exceptionNames[spellID] then
        spellName = Gladdy.exceptionNames[spellID]
    end

    if destUnit then
        -- diminish tracker
        -- Pass both spellID and spellName for Ascension compatibility (custom spell IDs)
        if Gladdy.buttons[destUnit] and Gladdy.db.drEnabled then
            if (eventType == "SPELL_AURA_REMOVED") then
                Diminishings:AuraFade(destUnit, spellID, spellName)
            end
            if (eventType == "SPELL_AURA_REFRESH") then
                Diminishings:AuraGain(destUnit, spellID, spellName)
            end
            if (eventType == "SPELL_AURA_APPLIED") then
                Diminishings:AuraGain(destUnit, spellID, spellName)
            end
        end
        -- death detection
        if (eventType == "UNIT_DIED" or eventType == "PARTY_KILL" or eventType == "SPELL_INSTAKILL") then
            if not Gladdy:isFeignDeath(destUnit) then
                Gladdy:SendMessage("UNIT_DEATH", destUnit)
            end
        end
        -- spec detection
        if Gladdy.buttons[destUnit] and (not Gladdy.buttons[destUnit].class or not Gladdy.buttons[destUnit].race) then
            Gladdy:SpotEnemy(destUnit, true)
        end
        --interrupt detection
        if Gladdy.buttons[destUnit] and eventType == "SPELL_INTERRUPT" then
            -- For SPELL_INTERRUPT: extraArg1=extraSpellId, extraArg2=extraSpellName, extraArg3=extraSpellSchool
            Gladdy:SendMessage("SPELL_INTERRUPT", destUnit,spellID,spellName,spellSchool,extraArg1,extraArg2,extraArg3)
        end
        -- Stealth buff removal detection (Ascension fix)
        -- Use STEALTH_AURAS (not STEALTH_SPELLS) - Vanish buff fading should NOT clear stealth
        -- because the unit still has the regular Stealth buff after Vanish fades
        if Gladdy.buttons[destUnit] and eventType == "SPELL_AURA_REMOVED" then
            if STEALTH_AURAS[spellName] and Gladdy.buttons[destUnit].stealthed then
                Gladdy.buttons[destUnit].stealthed = false
                Gladdy:SendMessage("ENEMY_STEALTH", destUnit, false)
            end
        end
        -- Stealth buff applied detection (Ascension fix - ARENA_OPPONENT_UPDATE may not fire)
        if Gladdy.buttons[destUnit] and eventType == "SPELL_AURA_APPLIED" then
            -- Debug: show all aura applied events to find stealth spell names on Ascension
            if Gladdy.STEALTH_DEBUG then
                print("|cffaaaaaa[AURA]|r", destUnit, spellID, spellName)
            end
            if STEALTH_SPELLS[spellName] and not Gladdy.buttons[destUnit].stealthed then
                Gladdy.buttons[destUnit].stealthed = true
                if Gladdy.STEALTH_DEBUG then
                    print("|cff00ff00[STEALTH]|r", destUnit, "APPLIED:", spellName, "-> stealthed = true")
                end
                Gladdy:SendMessage("ENEMY_STEALTH", destUnit, true)
            end
        end
    end
    if srcUnit then
        srcUnit = string_gsub(srcUnit, "pet", "")
        if (not UnitExists(srcUnit)) then
            return
        end
        -- Clear stealth when unit performs any action EXCEPT stealth spells (Ascension fix)
        -- Don't clear stealth if they're casting Vanish/Shadowmeld (they're going INTO stealth)
        if Gladdy.buttons[srcUnit].stealthed and not STEALTH_SPELLS[spellName] then
            Gladdy.buttons[srcUnit].stealthed = false
            if Gladdy.STEALTH_DEBUG then
                print("|cffff0000[ACTION]|r", srcUnit, spellName, "-> stealth = false")
            end
            Gladdy:SendMessage("ENEMY_STEALTH", srcUnit, false)
        end
        if not Gladdy.buttons[srcUnit].class or not Gladdy.buttons[srcUnit].race then
            Gladdy:SpotEnemy(srcUnit, true)
        end
        if not Gladdy.buttons[srcUnit].spec then
            self:DetectSpec(srcUnit, Gladdy.specSpells[spellName])
            -- Also detect via specBuffs when buffs like Grace/Divine Aegis are applied
            if eventType == "SPELL_AURA_APPLIED" and Gladdy.specBuffs[spellName] then
                self:DetectSpec(srcUnit, Gladdy.specBuffs[spellName])
            end
        end
        if (eventType == "SPELL_CAST_SUCCESS" or eventType == "SPELL_AURA_APPLIED" or eventType == "SPELL_MISSED") then
            -- cooldown tracker
            if Gladdy.db.cooldown and Cooldowns.cooldownSpellIds[spellName] then
                local unitClass
                local spellId = Cooldowns.cooldownSpellIds[spellName] -- don't use spellId from combatlog, in case of different spellrank
                if spellID == 16188 or spellID == 17116 then -- Nature's Swiftness (same name for druid and shaman)
                    spellId = spellID
                elseif ( eventType == "SPELL_AURA_APPLIED" and spellID ~= 51514 ) then
                    return -- Warmane: Workaround missing hex event.
                end
                if Gladdy.db.cooldownCooldowns[tostring(spellId)] and (eventType == "SPELL_CAST_SUCCESS" or eventType == "SPELL_AURA_APPLIED" or eventType == "SPELL_MISSED" or eventType == "SPELL_DODGED") then
                    if (Gladdy:GetCooldownList()[Gladdy.buttons[srcUnit].class][spellId]) then
                        unitClass = Gladdy.buttons[srcUnit].class
                    else
                        unitClass = Gladdy.buttons[srcUnit].race
                    end
                    if spellID ~= 16188 and spellID ~= 17116 and spellID ~= 16166 and spellID ~= 12043 and spellID ~= 5384 then -- Nature's Swiftness CD starts when buff fades
                        Gladdy:Debug("INFO", eventType, "- CooldownUsed", srcUnit, "spellID:", spellID)
                        Cooldowns:CooldownUsed(srcUnit, unitClass, spellId)
                    end
                end
            end
        end
        if (eventType == "SPELL_AURA_REMOVED" and (spellID == 16188 or spellID == 17116 or spellID == 16166 or spellID == 12043) and Gladdy.buttons[srcUnit].class) then
            Gladdy:Debug("INFO", "SPELL_AURA_REMOVED - CooldownUsed", srcUnit, "spellID:", spellID)
            Cooldowns:CooldownUsed(srcUnit, Gladdy.buttons[srcUnit].class, spellID)
        end
        if (eventType == "SPELL_AURA_REMOVED" and Gladdy.db.cooldown and Cooldowns.cooldownSpellIds[spellName]) then
            local unit = Gladdy:GetArenaUnit(srcUnit, true)
            local spellId = Cooldowns.cooldownSpellIds[spellName] -- don't use spellId from combatlog, in case of different spellrank
            if spellID == 16188 or spellID == 17116 then -- Nature's Swiftness (same name for druid and shaman)
                spellId = spellID
            end
            if unit then
                --Gladdy:Debug("INFO", "EL:CL:SPELL_AURA_REMOVED (srcUnit)", "Cooldowns:AURA_FADE", unit, spellId)
                Cooldowns:AURA_FADE(unit, spellId)
            end
        end
    end
end

function EventListener:ARENA_OPPONENT_UPDATE(unit, updateReason)
    --[[ updateReason: seen, unseen, destroyed, cleared ]]

    unit = Gladdy:GetArenaUnit(unit)
    local button = Gladdy.buttons[unit]
    local pet = Gladdy.modules["Pets"].frames[unit]
    Gladdy:Debug("INFO", "ARENA_OPPONENT_UPDATE", unit, updateReason)
    if Gladdy.STEALTH_DEBUG then
        print("|cffff9900[ARENA_UPDATE]|r", unit, updateReason)
    end
    if button or pet then
        if updateReason == "seen" then
            -- ENEMY_SPOTTED
            if button then
                -- Ascension fix: Check if unit is actually visible before clearing stealth
                -- Sometimes "seen" fires incorrectly when rogue Vanishes
                local isVisible = UnitIsVisible(unit)
                if Gladdy.STEALTH_DEBUG then
                    print("|cffff9900[SEEN]|r", unit, "UnitIsVisible:", isVisible)
                end
                if isVisible then
                    button.stealthed = false
                    button.destroyed = nil
                    if Gladdy.STEALTH_DEBUG then
                        print("|cffff0000[SEEN]|r", unit, "-> stealth = false")
                    end
                    Gladdy:SendMessage("ENEMY_STEALTH", unit, false)
                else
                    -- Unit not visible, they're probably stealthed - don't clear stealth
                    if Gladdy.STEALTH_DEBUG then
                        print("|cff00ff00[SEEN IGNORED]|r", unit, "not visible, keeping stealth")
                    end
                    if not button.stealthed then
                        button.stealthed = true
                        Gladdy:SendMessage("ENEMY_STEALTH", unit, true)
                    end
                end
                if not button.class or not button.race then
                    Gladdy:SpotEnemy(unit, true)
                end
            end
            if pet then
                Gladdy:SendMessage("PET_SPOTTED", unit)
            end
        elseif updateReason == "unseen" then
            -- STEALTH
            if button then
                button.stealthed = true
                if Gladdy.STEALTH_DEBUG then
                    print("|cff00ff00[UNSEEN]|r", unit, "-> stealth = true")
                end
                Gladdy:SendMessage("ENEMY_STEALTH", unit, true)
            end
            if pet then
                Gladdy:SendMessage("PET_STEALTH", unit)
            end
        elseif updateReason == "destroyed" then
            -- Ascension fix: "destroyed" fires for stealth instead of "unseen"
            -- Check if unit still exists - if yes, they're stealthed, not actually gone
            local unitExists = UnitExists(unit)
            if Gladdy.STEALTH_DEBUG then
                print("|cffff00ff[DESTROYED]|r", unit, "UnitExists:", unitExists)
            end
            if button then
                if unitExists then
                    -- Unit exists but "destroyed" fired = they're stealthed
                    button.stealthed = true
                    if Gladdy.STEALTH_DEBUG then
                        print("|cff00ff00[DESTROYED->STEALTH]|r", unit, "-> stealth = true")
                    end
                    Gladdy:SendMessage("ENEMY_STEALTH", unit, true)
                else
                    -- Unit really gone
                    button.destroyed = true
                    Gladdy:SendMessage("UNIT_DESTROYED", unit)
                end
            end
            if pet then
                if not unitExists then
                    Gladdy:SendMessage("PET_DESTROYED", unit)
                end
            end
        elseif updateReason == "cleared" then
            --Gladdy:Print("ARENA_OPPONENT_UPDATE", updateReason, unit)
        end
    end
end

Gladdy.cooldownBuffs = {
    [GetSpellInfo(6346)] = { cd = function(expTime) -- 180s uptime == cd
        return expTime
    end, spellId = 6346 }, -- Fear Ward
    [GetSpellInfo(11305)] = { cd = function(expTime) -- 15s uptime
        return 300 - (15 - expTime)
    end, spellId = 11305 }, -- Sprint
    [36554] = { cd = function(expTime) -- 3s uptime
        return 30 - (3 - expTime)
    end, spellId = 36554 }, -- Shadowstep speed buff
    [36563] = { cd = function(expTime) -- 10s uptime
        return 30 - (10 - expTime)
    end, spellId = 36554 }, -- Shadowstep dmg buff
    [GetSpellInfo(26889)] = { cd = function(expTime) -- 3s uptime
        return 180 - (10 - expTime)
    end, spellId = 26889 }, -- Vanish
    racials = {
        [GetSpellInfo(20600)] = { cd = function(expTime) -- 20s uptime
            return GetTime() - (20 - expTime)
        end, spellId = 20600 }, -- Perception
    }
}
--[[
/run local f,sn,dt for i=1,2 do f=(i==1 and "HELPFUL"or"HARMFUL")for n=1,30 do sn,_,_,dt=UnitAura("player",n,f) if(not sn)then break end print(sn,dt,dt and dt:len())end end
--]]
function EventListener:UNIT_AURA(unit, isFullUpdate, updatedAuras)
    local button = Gladdy.buttons[unit]
    if not button then
        return
    end
    if not button.auras then
        button.auras = {}
    end
    wipe(button.auras)
    if not button.lastAuras then
        button.lastAuras = {}
    end
    Gladdy:Debug("INFO", "AURA_FADE", unit, AURA_TYPE_BUFF, AURA_TYPE_DEBUFF)
    Gladdy:SendMessage("AURA_FADE", unit, AURA_TYPE_BUFF)
    Gladdy:SendMessage("AURA_FADE", unit, AURA_TYPE_DEBUFF)
    for i = 1, 2 do
        if not Gladdy.buttons[unit].class or not Gladdy.buttons[unit].race then
            Gladdy:SpotEnemy(unit, false)
        end
        local filter = (i == 1 and "HELPFUL" or "HARMFUL")
        local auraType = i == 1 and AURA_TYPE_BUFF or AURA_TYPE_DEBUFF
        for n = 1, 30 do
            -- WotLK 3.3.5 / Ascension signature includes 'rank' as 2nd return value
            local spellName, rank, texture, count, dispelType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellID = UnitAura(unit, n, filter)
            -- Use spellName for loop termination (more reliable on Ascension)
            if ( not spellName ) then
                Gladdy:SendMessage("AURA_GAIN_LIMIT", unit, auraType, n - 1)
                break
            end
            if spellID and Gladdy.exceptionNames[spellID] then
                spellName = Gladdy.exceptionNames[spellID]
            end
            -- Use spellID as key if available, otherwise use spellName (Ascension compatibility)
            local auraKey = spellID or spellName
            button.auras[auraKey] = { auraType, spellID, spellName, texture, duration, expirationTime, count, dispelType }
            if Gladdy.specBuffs[spellName] and unitCaster then
                -- Detect spec on the CASTER of the buff, not just self-buffs
                -- This allows detecting Disc priest when Grace/Divine Aegis appears on allies
                for arenaUnit, arenaButton in pairs(Gladdy.buttons) do
                    if not arenaButton.spec and UnitIsUnit(arenaUnit, unitCaster) then
                        self:DetectSpec(arenaUnit, Gladdy.specBuffs[spellName])
                        break
                    end
                end
            end
            if (Gladdy.cooldownBuffs[spellName] or Gladdy.cooldownBuffs[spellID]) and unitCaster then -- Check for auras that hint used CDs (like Fear Ward)
                local cooldownBuff = Gladdy.cooldownBuffs[spellID] or Gladdy.cooldownBuffs[spellName]
                for arenaUnit,v in pairs(Gladdy.buttons) do
                    if (UnitIsUnit(arenaUnit, unitCaster)) then
                        Cooldowns:CooldownUsed(arenaUnit, v.class, cooldownBuff.spellId, cooldownBuff.cd(expirationTime - GetTime()))
                    end
                end
            end
            if Gladdy.cooldownBuffs.racials[spellName] then
                Gladdy:SendMessage("RACIAL_USED", unit, spellName, Gladdy.cooldownBuffs.racials[spellName].cd(expirationTime - GetTime()), spellName)
            end
            Gladdy:Debug("INFO", "AURA_GAIN", unit, auraType, spellName)
            Gladdy:SendMessage("AURA_GAIN", unit, auraType, spellID, spellName, texture, duration, expirationTime, count, dispelType, i, unitCaster)
        end
    end
    -- check auras
    for spellID,v in pairs(button.lastAuras) do
        if not button.auras[spellID] then
            if Gladdy.db.cooldown and Cooldowns.cooldownSpellIds[v[3]] then
                local spellId = Cooldowns.cooldownSpellIds[v[3]] -- don't use spellId from combatlog, in case of different spellrank
                if spellID == 16188 or spellID == 17116 then -- Nature's Swiftness (same name for druid and shaman)
                    spellId = spellID
                end
                --Gladdy:Debug("INFO", "EL:UNIT_AURA Cooldowns:AURA_FADE", unit, spellId)
                Cooldowns:AURA_FADE(unit, spellId)
                if spellID == 5384 then -- Feign Death CD Detection needs this
                    Cooldowns:CooldownUsed(unit, Gladdy.buttons[unit].class, 5384)
                end
            end
        end
    end
    wipe(button.lastAuras)
    button.lastAuras = Gladdy:DeepCopy(button.auras)
end

function EventListener:UpdateAuras(unit)
    local button = Gladdy.buttons[unit]
    if not button or button.lastAuras then
        return
    end
    for i=1, #button.lastAuras do
        Gladdy.modules["Auras"]:AURA_GAIN(unit, unpack(button.lastAuras[i]))
    end
end

function EventListener:UNIT_SPELLCAST_START(unit)
    if Gladdy.buttons[unit] then
        local spellName = UnitCastingInfo(unit)
        if Gladdy.specSpells[spellName] and not Gladdy.buttons[unit].spec then
            self:DetectSpec(unit, Gladdy.specSpells[spellName])
        end
    end
end

function EventListener:UNIT_SPELLCAST_CHANNEL_START(unit)
    if Gladdy.buttons[unit] then
        local spellName = UnitChannelInfo(unit)
        if Gladdy.specSpells[spellName] and not Gladdy.buttons[unit].spec then
            self:DetectSpec(unit, Gladdy.specSpells[spellName])
        end
    end
end

function EventListener:UNIT_SPELLCAST_SUCCEEDED(...)
    --local unit, castGUID, spellID = ...
    local unit, spellID = ...
    unit = Gladdy:GetArenaUnit(unit, true) or unit
    local Button = Gladdy.buttons[unit]
    if Button then
        local unitRace = Button.race
        --local spellName = GetSpellInfo(spellID)
        local spellName = spellID

        if Gladdy.exceptionNames[spellID] then
            spellName = Gladdy.exceptionNames[spellID]
        end

        -- spec detection
        if spellName and  Gladdy.specSpells[spellName] and not Button.spec then
            self:DetectSpec(unit, Gladdy.specSpells[spellName])
        end

        -- trinket
        --if spellID == 42292 or spellID == 59752 then
        if spellID == PVP_TRINKET then
            Gladdy:Debug("INFO", "UNIT_SPELLCAST_SUCCEEDED - TRINKET_USED", unit, spellID)
            Gladdy:SendMessage("TRINKET_USED", unit)
        end

        -- racial
        --if unitRace and  Gladdy:Racials()[unitRace].spellName == spellName and Gladdy:Racials()[unitRace][spellID] then
        if unitRace and Gladdy:Racials()[unitRace].spellName == spellName then
            Gladdy:Debug("INFO", "UNIT_SPELLCAST_SUCCEEDED - RACIAL_USED", unit, spellID)
            Gladdy:SendMessage("RACIAL_USED", unit)
        end

        --cooldown
        local unitClass
        if (Gladdy:GetCooldownList()[Button.class][unit]) then
            unitClass = Button.class
        else
            unitClass = Button.race
        end
        --if spellID ~= 16188 and spellID ~= 17116 and spellID ~= 16166 and spellID ~= 12043 and spellID ~= 5384 then -- Nature's Swiftness CD starts when buff fades
        if spellID ~= NS and spellID ~= EM and spellID ~= POM and spellID ~= FD then -- Nature's Swiftness CD starts when buff fades
            Gladdy:Debug("INFO", "UNIT_SPELLCAST_SUCCEEDED", "- CooldownUsed", unit, "spellID:", spellID)
            Cooldowns:CooldownUsed(unit, unitClass, spellID)
        end
    end
end

function EventListener:DetectSpec(unit, spec)
    local button = Gladdy.buttons[unit]
    if (not button or not spec or button.spec) then
        return
    end
    if button.class == "PALADIN" and not Gladdy:contains(spec, {L["Holy"], L["Retribution"], L["Protection"]})
            or button.class == "SHAMAN" and not Gladdy:contains(spec, {L["Restoration"], L["Enhancement"], L["Elemental"]})
            or button.class == "ROGUE" and not Gladdy:contains(spec, {L["Subtlety"], L["Assassination"], L["Combat"]})
            or button.class == "WARLOCK" and not Gladdy:contains(spec, {L["Demonology"], L["Destruction"], L["Affliction"]})
            or button.class == "PRIEST" and not Gladdy:contains(spec, {L["Shadow"], L["Discipline"], L["Holy"]})
            or button.class == "MAGE" and not Gladdy:contains(spec, {L["Frost"], L["Fire"], L["Arcane"]})
            or button.class == "DRUID" and not Gladdy:contains(spec, {L["Restoration"], L["Feral"], L["Balance"]})
            or button.class == "HUNTER" and not Gladdy:contains(spec, {L["Beast Mastery"], L["Marksmanship"], L["Survival"]})
            or button.class == "WARRIOR" and not Gladdy:contains(spec, {L["Arms"], L["Protection"], L["Fury"]})
            or button.class == "DEATHKNIGHT" and not Gladdy:contains(spec, {L["Unholy"], L["Blood"], L["Frost"]}) then
        return
    end
    if not button.spec then
        button.spec = spec
        Gladdy:SendMessage("UNIT_SPEC", unit, spec)
    end
end

function EventListener:Test(unit)
    local button = Gladdy.buttons[unit]
    if (button and Gladdy.testData[unit].testSpec) then
        button.spec = nil
        Gladdy:SpotEnemy(unit, false)
        self:DetectSpec(unit, button.testSpec)
    end
end
