# Changelog

All notable changes to this project will be documented in this file.

## [2.6-Ascension] - 2026-01-08

### Critical Fixes (Round 11.6 - Repeated Casts)
- **Fixed Repeated Cast Detection**: Implemented unique identifiers (CastID + EndTime) to detect repeated casts of the same spell (e.g., Penance, Polymorph) which were previously ignored.
- **Fixed Short Channel Detection**: Penance and other short channels now show reliably every time.
- **Fixed Identifier Cleanup**: Proper reset of cast/channel identifiers on unit reset/arena join.

### Major Fixes (Round 11.5 - Castbar API)
- **Fixed Castbar Lua Errors**: Implemented dynamic API detection for `UnitCastingInfo` and `UnitChannelInfo` to handle Ascension's custom return order (Texture at pos 4 vs 3).
- **Fixed Arena Frames**: Resolved opaque/non-clickable arena frames caused by castbar error cascade.

### Arena System Fixes (Round 9-11)
- **Fixed Frame Duplication**: Each arena frame (arena1-5) now correctly tracks a unique enemy. Fixed race conditions in `SpotEnemy`.
- **Fixed Kui_Nameplates Conflict**: Automatically disables `TotemPlates` module if Kui_Nameplates is loaded to prevent `SetAttribute` taint.
- **Fixed UnitChannelInfo/UnitCastingInfo**: Switched to native global functions instead of Retail `C_*` tables.
- **Fixed UnitAura Errors**: Corrected parameter usage in `AuraUtil` calls.

### Nameplate & Phasing Fixes (Round 8)
- **Fixed Nameplate Disappearance**: Nameplates now automatically restore when leaving the arena.
- **Fixed UnitPhaseReason Spam**: Added existence check for BFA API `UnitPhaseReason` to prevent 100+ errors/sec.
- **Fixed Taint Issues**: Protected `SetCVar` calls and removed global modifications to secure frames.

### API Compatibility (Rounds 1-7)
- **Fixed Data Delays**: Implemented retry mechanism for slow-loading Ascension unit data.
- **Fixed Taint**: Removed global `GetSpellInfo`/`GetItemInfo` wrappers that caused Blizzard UI taint.
- **Fixed Frame Display**: Resolved `SetMask` (BFA) and `SetIgnoreParentScale` (Legion) API calls preventing frame rendering.
- **Fixed Cooldown Icons**: Added compatibility for cooldown icon creation.

## [2.50-Ascension] - 2026-01-04

### Initial Port
- **Removed Dependencies**: Removed requirement for `!!!ClassicAPI`.
- **Native Compatibility**: Added `GladdyCompat.lua` shim to polyfill missing APIs (`C_CreatureInfo`, `AuraUtil`, `C_Timer`) using native 3.3.5 functions where possible.
- **Ascension Support**: 
  - Enabled `Constants_Wrath.lua` for Ascension environment.
  - Added detection for Ascension's modified API landscape.
- **Optimized**: Reduced polyfill bloat from >10k lines (ClassicAPI) to ~370 lines.

## Credits
- **Hutsh**: Original backport work for Ascension compatibility.
- **Xurkon**: Optimization, critical bug fixes, and stability improvements (Rounds 1-11).
- **Gladdy Team**: XiconQoo, DnB_Junkee, Knall, Tsoukie for the original addon.
