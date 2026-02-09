# PA-Gladdy Changelog

**Current Version:** v2.15-Ascension
**Ascension Port Credits:** Hutsh (Initial Backport), Xurkon (Optimizations & Critical Fixes), Surm (TotemPlates & TurboPlates Integration)

This changelog documents the complete history of changes, hotfixes, and optimizations applied to make Gladdy fully compatible with Project Ascension.

---

## v2.15-Ascension (Release)
- **Critical Bug Fix**: Fixed a crash that occurred when entering arena, caused by a GetStatusBarColor nil value error in the TotemPlates module.

### Technical Details
- **Error**: Attempt to call method 'GetStatusBarColor' (a nil value) at TotemPlates.lua:1026
- **Cause**: The code was attempting to call GetStatusBarColor() on healthbar frames that didn't have this method.
- **Solution**: Added method existence validation before calling GetStatusBarColor() in the NameplateTypeValid function.
- **Context**: Different nameplate addons (Blizzard UI, ElvUI, TurboPlates, etc.) provide healthbar frames with different APIs. Not all of them implement the StatusBar interface. This fix adds a check to ensure the method exists before attempting to call it.

## v2.13-Ascension (Release)
- **TotemPlates Enhancements**: Improved totem detection and display logic.
- **Fixes**: General enhancements and bug fixes for TotemPlates module.

## v2.12-Ascension (Release)
- **Settings Persistence Fix**: Resolved "First Run" reuse issue. Gladdy now uses an internal `firstRun` flag instead of checking frame position, ensuring the welcome frame only appears once per install, even if the game crashes later.
- **Migration**: Existing users are automatically migrated to the new system.

---

## v2.11-Ascension (Release)
- **TotemPlates Rewrite**: Complete rewrite of TotemPlates module by Surm.
- **TurboPlates Integration**: Native integration with TurboPlates nameplate addon for seamless totem tracking.
- **Gladdy Delegation**: When TurboPlates has a totem plate active, Gladdy defers to avoid conflicts.
- **Click-to-Target**: Improved totem targeting with hybrid click-through system.

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
