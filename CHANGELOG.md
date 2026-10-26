# Changelog

All notable changes to the MCP Profiling & COREnergy App project are documented in this file.

## [0.2.5] - 2026-10-26

### Fixed & Improved
- **iOS Deployment Readiness & Minimum Target Platform**: Configured minimum deployment target platform to `13.0` in `ios/Podfile`, ensuring modern Flutter and CocoaPods plugin compatibility with Xcode 15/16.
- **iOS Permission Descriptions & Photo Library Access**: Added `NSPhotoLibraryUsageDescription` for visit photo uploads and updated `NSLocationWhenInUseUsageDescription` and `NSCameraUsageDescription` strings in `ios/Runner/Info.plist` to explicitly identify PIMS MCP-COREnergy.

## [0.2.4] - 2026-10-01

### Added & Improved
- **Mandatory Location Capture & Tab Access Guard**: Enforced strict on-site physical location verification in `COREnergyEngageDetailScreen`. MedReps MUST capture their high-accuracy GPS coordinates before being permitted access to the other 3 tabs (`Contacts`, `Engagements / Visits`, `Action Items / Next Steps`). Tabs remain locked with visual lock icons and animated intercepts with direct-action dialogs.
- **Zero-Mockup High-Precision Geolocation**: Removed all artificial Laguna coordinate seeding across `COREnergyEngageDetailScreen` and `DetailScreen`. Upgraded GPS acquisition to `LocationAccuracy.best` with automatic service enablement checks, runtime permission negotiation, and exact satellite accuracy logging (`±X.X m`).
- **Interactive Coverage Map MedRep Filter**: Embedded an interactive MedRep selector directly on the Coverage Map. Managers and reps can instantly toggle between "All Sales Reps (Nationwide)" and specific MedReps, with the map automatically recalculating pins, adjusting camera centroid, and reflecting real-time stats (`Succ`, `Unsucc`, `Accts`, `Total Geotagged`).
- **Deep Work Activity Inspection on Map Pins**: Upgraded map pin modal sheets to display complete field activity. Engagement pins present call outcome (Successful vs Unsuccessful), mandatory reason for failure, contact person met, role, contact phone/email, decision maker presence, date/time, and exact GPS coordinates with accuracy. Account pins detail historical call counts, past visit logs, registered contacts, and action items.

## [0.2.3] - 2026-10-01

### Fixed
- **Bidirectional Cross-DocType Synchronization**: Unified `COREnergy Engage Copy` and `Successful COREnergy Engagement`/`Unsuccessful COREnergy Engagement`. Visits logged on accounts auto-sync to engagement call logs, and call engagements logged in the field auto-append into the corresponding account's visit history child table.
- **Institution ID Sanitization (HTTP 417 Fix)**: Integrated `_resolveInstitutionId()` to automatically resolve hospital/clinic names and institution codes against the `Institution` masterlist, permanently preventing Frappe `417 LinkValidationError: Could not find Company`.
- **Interactive Coverage Map & UI Unblocking**: Removed full-screen blocking black modal overlay on sync, replaced with non-blocking top status pill. Upgraded map renderer to plot both successful engagements (blue), unsuccessful engagements (red), and geotagged COREnergy accounts (green), complete with live pin details bottom sheet and persistent quick-action FAB.
- **Batch SQLite Performance Engine**: Replaced sequential awaiting of 3,956+ records with transactional `db.batch()`, eliminating 60+ second UI thread locks during initial data caching.
- **Defensive Geolocation & CSRF Re-auth**: Injected latitude/longitude/accuracy tracking into `COREnergyEngage` model with automatic CSRF token verification and silent session renewal across all create/update endpoints.

## [0.2.2] - 2026-10-01

### Fixed
- **Sync Non-Blocking Architecture**: Moved SQLite background synchronization out of the critical rendering path in `_loadData()`. Data from local cache and network displays instantly without waiting for queued submissions to sync.
- **Auto-Sync Throttling**: Increased background auto-sync check interval from 5s to 30s to prevent network saturation, tablet slowdown, and battery drain.
- **Offline Queue Resilient Self-Healing**: Enhanced `syncOfflineData()` to skip individual failing SQLite rows via `continue` instead of breaking the entire queue, allowing valid offline visits to upload even if one item is invalid.
- **Detail Screen Graceful Fallback**: Upgraded `fetchCOREnergyEngageByName()` with automatic silent re-authentication on 401/403, cached detail lookup, main list fallback search, and safe default instantiation so navigating to engagement details never throws an unhandled exception.
- **Coverage Map Vector Tile Resilience**: Configured OpenStreetMap tile server with Google Maps satellite fallback, completely eliminating CartoCDN watermark and API key requirements.

## [0.2.1] - 2026-10-01

### Fixed
- **417 LinkValidationError on Company Field**: Sanitized `company` field submission across `createEngagement()` and `updateEngagement()`. Removed invalid `"COREnergy"` string value that previously caused ERPNext Frappe to reject calls with HTTP 417 Expectation Failed.
- **Offline Sync CSRF Token & Re-auth Engine**: Upgraded `syncOfflineData()` to systematically invoke `ensureCsrfToken()`, perform autonomous background session re-authentication upon 401/403 status codes, and handle both institution logs (`COREnergyEngage`) and raw field visit logs (`Engagement`).
- **Offline Zero-Data-Loss Queueing**: Replaced unhandled exceptions in `createEngagement()` and `updateEngagement()` with automatic SQLite fallbacks (`_saveEngagementOffline`), ensuring field visits save locally and display in UI immediately regardless of network state.
- **Robust Session Cookie Parsing**: Replaced fragile semicolon-splitting logic with regex `RegExp(r'sid=([^;,\s]+)')` to reliably extract session IDs from concatenated reverse proxy `Set-Cookie` headers.
- **Coverage Map Tile Provider**: Eliminated third-party CartoCDN API key dependency, ensuring reliable vector map rendering via OpenStreetMap and Google Maps tile fallback.

## [0.2.0] - 2026-09-30

### Fixed
- **DocType 403 Forbidden Error on COREnergy Engage Copy**: Configured Custom DocPerms on ERPNext v15 server (`https://dev.pmii-marketing.com`) granting Read, Write, and Create permissions for `Employee - COREnergy`, `Next Level Manager - COREnergy`, `Field Force Manager`, and `System Manager`.
- **Query 417 Expectation Failed Error**: Added Custom Field `ownership_nationality` to `COREnergy Engage` and Custom Fields `decision_maker_or_responsible_person_not_available` and `unsuccessful_call` to `Unsuccessful COREnergy Engagement`.
- **Zero-Byte Bundled Asset Fallback Crashes**: Populated `assets/institutions.json` with 4,006 live institution records and `assets/engagements.json` with 237 live engagement records, removing `FormatException` crashes during offline load.
- **Engagement Multi-DocType Alignment**: Re-engineered `fetchEngagements()` to simultaneously query and merge both `Successful COREnergy Engagement` and `Unsuccessful COREnergy Engagement` records.
- **Field Reason Validation**: Aligned all unsuccessful call reasons in mobile and web forms with Frappe's exact valid Select options.

### Added
- **24/7 Production Resilience Engine**: Implemented autonomous session renewal, 15-second timeouts, automatic transient error retries, and defensive schema deserialization.
- **Repository Organization Standard**: Relocated web simulator files to `web_simulator/`, release binaries to `releases/`, and maintenance scripts to `scripts/`.
- **Production Architecture Specification**: Documented high-availability runbook in `docs/24_7_PRODUCTION_RESILIENCE_AND_FAILOVER_SPECIFICATION.md`.
