# PA-Gladdy Changelog

**Current Version:** v2.9.3-Ascension
**Ascension Port Credits:** Hutsh (Initial Backport), Xurkon (Optimizations & Critical Fixes)

This changelog documents the complete history of changes, hotfixes, and optimizations applied to make Gladdy fully compatible with Project Ascension.

---

## v2.9.3-Ascension (2026-01-14)

### Preference Persistence Fix
- **Fixed**: Totem plates choice now properly saved and remembered across reloads
- Saves directly to `GladdyXZ` SavedVariables instead of AceDB proxy

---

## v2.9.2-Ascension (2026-01-14)

### Turboplates Seamless Integration
- **User Choice Dialog**: When both Gladdy and Turboplates are installed, a popup asks which addon should handle totem icons
- **Smart Disable**: Automatically disables the other addon's totem feature based on user choice
- **Preference Saved**: Choice is remembered to prevent repeat prompts
- **Gladdy Advantage**: Dialog highlights Gladdy's exclusive features (click-to-target, pulse timers)

---

## v2.9.1-Ascension (2026-01-14)

### Turboplates Conflict Fix (superseded by v2.9.2)
- Auto-disable logic replaced with user choice dialog in v2.9.2

---

## v2.9-Ascension (2026-01-14)

### Merged Hutsh's Upstream Changes
Integrated new features from Hutsh's upstream development branch:

#### Cooldowns Module Enhancements
- **Spec Filtering**: Custom cooldowns can now be filtered by class spec (e.g., Restoration Druid only)
- **Duration Overrides**: Users can customize individual spell cooldown durations via `cooldownDurationOverrides`
- **CLASS_SPECS Table**: Added support for all 9 classes with their 3 specializations each
- **Improved Custom Cooldown Format**: Enhanced string serialization with spec field support

#### Healthbar Module Enhancements
- **Stealth Border**: New configurable border color for stealthed targets
  - `healthBarStealthBorderEnabled`: Toggle purple border when target is stealthed
  - `healthBarStealthBorderColor`: Customizable border color (default: purple `{0.5, 0.0, 0.8}`)
- **Improved Stealth Color**: Better default stealth color (dark blue-purple `{0.4, 0.4, 0.6}`)
- **Enhanced Color Logic**: Background color resets properly when leaving stealth
- **Stealth State Reset**: `ResetUnit` now properly clears stealth state and restores border color

#### Core Improvements
- **DYNAMIC_DATA_TABLES**: Added `cooldownDurationOverrides` to prevent SavedVariable cleanup from deleting user customizations

---

## v2.8.1-Ascension (2026-01-13)

### TotemPlates Stability Fix
- Fixed Lua error `attempt to index field 'nametext' (a nil value)` that could occur with certain nameplate addons
- Added nil checks in `NAME_PLATE_UNIT_ADDED`, `PLAYER_TARGET_CHANGED_UPDATE`, and `OnUpdate` functions
- Prevents crashes when nameplate text elements aren't fully initialized (common when switching addon versions)

---

## v2.8-Ascension (2026-01-12)

### TotemPlates Click-to-Target
- Added **click-to-target** functionality for totem icons
- Uses hybrid approach: SecureActionButton outside combat, pass-through clicks during combat
- Totems are now clickable to target in ALL situations (pre-combat and mid-combat spawns)
- No taint issues - proper InCombatLockdown() checks on all attribute changes

### TotemPlates Universal Compatibility
- Rewrote TotemPlates module to work with **any nameplate addon**
- Removed hardcoded addon-specific checks (Kui_Nameplates, TidyPlates, ElvUI)
- Uses overlay approach - totem icons display on top of any nameplate system
- Generic nameplate detection via health bar and border texture scanning

### Diminishing Returns Expansion
- Added **47 new Ascension-specific CC spells** to DRList for proper DR tracking
  - 17 stun spells, 13 root spells, 4 fear spells, 4 silence spells, 9 incapacitate spells

### Notes
- **Spec Icons**: Enable "Show Spec Icon" in Class Icon settings
- **DR Debug**: Use `/run Gladdy.DR_DEBUG = true` to see DR detection

---

## v2.6-Ascension (Release)
- Consolidated all previous hotfixes into a stable release.
- Updated TOC version to 2.6-Ascension.
- Added comprehensive documentation and GitHub Pages site.

---

## detailed Development History (Hotfix Rounds 1 - 11.6)

### Round 11.6: Final Polish
- **Debug Messages**: Disabled all `GladdyCompat` debug spam (11+ lines removed) for a clean chat window on login.
- **Loading Message**: Updated initialization message to be professional and credit Hutsh properly.

### Round 11.5: Reset Cleanup
- **API Order Fix**: Fixed critical Lua errors where `UnitCastingInfo` and `UnitChannelInfo` returned values in a different order on Ascension compared to standard 3.3.5, causing "attempt to perform arithmetic" errors.
- **Dynamic Detection**: Implemented smart detection to automatically determine the correct return value positions for specific spells (e.g., Penance).

### Round 11: Castbar Polling System
- **Missing Events**: Discovered that `UNIT_SPELLCAST_*` events do not fire reliably on Ascension.
- **Polling Fix**: Implemented a lightweight polling system in `Castbar.lua` (checking every frame) to detect casts and channels immediately without relying on broken events.
- **Outcome**: Enemy cast bars now appear reliably.

### Round 10: Critical Arena Fixes
- **RegisterUnitEvent Polyfill**: Fixed a major issue where both arena frames would track the *same* player's health/mana. Created a polyfill for `RegisterUnitEvent` (Legion API) to correctly filter events per unit (e.g., `arena1` only processing `arena1` events).
- **Feign Death Fix**: Rewrote `isFeignDeath` to use a manual aura scan instead of `AuraUtil.FindAuraByName` (which caused errors due to missing legacy filter support).
- **Kui Nameplates Conflict**: Completely resolved taint issues with `Kui_Nameplates` by adding comprehensive guards to `TotemPlates.lua`.

### Round 9: Frame Duplication & Taint
- **Frame Duplication**: Fixed logic that caused multiple arena frames to sometimes display the same enemy unit.
- **Taint Prevention**: Added initial protections against taint when interacting with nameplates.

### Round 8: Nameplates & UnitPhaseReason
- **UnitPhaseReason**: Added existence checks for `UnitPhaseReason` calls in `RangeCheck.lua` to prevent "attempt to call nil" errors (API missing in 3.3.5).
- **Nameplate Visibility**: Fixed issue where nameplates would disappear or fail to restore after leaving an arena match.

### Round 7: Ascension Data Delays
- **Data Retry Mechanism**: Implemented a retry system in `EventListener.lua`. Ascension sends unit data (Class, Race) with a slight delay. Gladdy now retries for up to 0.5s if initial data is nil, preventing "white bar" glitches.
- **Health Bar Fixes**: Added protections against nil/zero values from `UnitHealth`, preventing health bars from getting stuck at 0 or crashing.

### Round 6: Critical Taint Fix
- **Secure System Taint**: identified and **REMOVED** global wrappers for `GetSpellInfo` and `GetItemInfo` in `GladdyCompat.lua`. These wrappers were tainting the Blizzard Secure Execution Environment, breaking macros and the spellbook.
- **Solution**: Switched to local nil-handling within individual modules (`Cooldowns.lua`, etc.) to maintain stability without breaking game security.

### Round 5B: Complete SetMask Fixes
- **Widespread API Fix**: `SetMask` (BFA API) was causing crashes across 8 different modules.
- **Modules Fixed**: `Cooldowns`, `Trinket`, `Racial`, `Classicon`, `BuffsDebuffs`, `Auras`, `Castbar`, `Diminishings`, `CombatIndicator`.
- **Outcome**: All icons (classes, cooldowns, trinkets) now render correctly without crashing frame updates.

### Round 5: Initial SetMask Fix
- **Cooldowns**: Addressed the first instance of `SetMask` crashing `Cooldowns.lua`.

### Round 4: Frame Display (The Blocker)
- **SetIgnoreParentScale**: Fixed the critical bug preventing frames from appearing at all. `SetIgnoreParentScale` (Legion API) was causing `UpdateFrame` to crash silently. Added existence checks to safe-guard this call.

### Round 3: Healthbar & Screen Size
- **GetPhysicalScreenSize**: Added polyfill for this BFA API to support pixel-perfect scaling on 3.3.5.
- **Healthbar Safety**: Added nil checks for `button` in `Healthbar.lua` to prevent crashes from non-arena events (e.g., player/target updates).

### Round 2: Timer & API Polyfills
- **C_Timer**: Created a full polyfill for `C_Timer.NewTicker`, `NewTimer`, and `After` in `GladdyCompat.lua`, as these Legion APIs are used extensively by Gladdy.
- **SetClipsChildren**: Disabled calls to this retail-only API in `ExportImport.lua`.
- **ArenaCountDown**: Added nil checks to prevent crashes when the countdown frame wasn't fully initialized.

### Round 1: Initial Port & Migration
- **Project Structure**: Removed dependency on `!!!ClassicAPI` and established `GladdyCompat.lua` as a lightweight, tailored compatibility layer.
- **Constants**: Added missing `WOW_PROJECT_*` constants to fix `LibClassAuras` and `DRList` initialization errors.
- **GetSpellInfo**: Added initial wrappers (later refined in Round 6) to handle missing spell IDs.
