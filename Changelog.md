## Version 0.4 - Planned

### WinUI App Track
- Added the initial WinUI 3 / Windows App SDK solution scaffold for a native Windows app.
- Ported the core app surface to native C# services for MSAL.NET authentication, Graph device search, dashboard counts, Autopilot group tags, offboarding, optional Defender offboarding, recovery-key lookup, playbook reports, settings import, audit logging, CSV export, and HTML reports.
- Reworked the WinUI prototype into a page-based shell with Home, Dashboard, Devices, Offboarding, Playbooks, Settings, and About views, including dashboard drilldowns and device filtering.
- Added native file picker flows for bulk CSV/TXT import and app registration JSON import, plus About page changelog and repository actions.
- Replaced placeholder package images with branded app logo assets and an executable icon.
- Added the Visual Studio `MsixPackage` launch profile required to debug the packaged WinUI app.
- Added the v0.4 migration plan for signed releases, Intune packaging, WinGet, and Microsoft Store readiness.
- Added static validation for the WinUI project structure, package manifest, package assets, and migration plan.

---

## Version 0.3 - 3/14/2026

### Bug Fixes
- **Fixed 8 Critical Bugs** across device offboarding and playbook execution
  - Fixed Autopilot property typo (`lastContactDateTime` -> `lastContactedDateTime`)
  - Fixed BitLocker key retrieval array bug: access first element explicitly
  - Fixed stale `parsedDevices` not clearing on bulk import cancel
  - Fixed status string corruption from counter increment inside PSCustomObject
  - Fixed permission scopes: `Device.ReadWrite.All`, added `BitlockerKey.Read.All`
  - Fixed export functions to use actual DeviceObject class properties
  - Fixed playbook result columns to generate dynamically from actual output schema
- **Full PowerShell Module Migration**: The project now ships as a module with a manifest, exported `Start-DeviceOffboardingManager` command, split private/public source files, XAML resources, bundled playbooks, and a compatibility `DeviceOffboardingManager.ps1` launcher.
- **Module Verification Tests**: Added repository checks for parser health, manifest/import behavior, packaged module import, compatibility launcher validation, XAML control bindings, bundled playbooks, and a Windows-only WPF smoke test.
- **Local Playbook Execution**: Playbooks now load from the module's bundled `Playbooks/` directory instead of downloading from GitHub URLs at runtime
- **Hardened Device Identity Correlation**: Search and offboarding now prefer Graph object IDs, Entra `deviceId`, Intune `azureADDeviceId`, and exact serial matches before any name-only fallback. Ambiguous duplicate matches are skipped with warnings to reduce wrong-device deletion risk.
- **Improved Empty Autopilot DisplayName Handling**: Autopilot device-name matching now avoids server-side displayName filters and supports client-side serial matching for devices with blank Autopilot display names.
- **Safer Audit Trail**: Confirmation preview now shows full Entra, Intune, and Autopilot IDs; CSV exports include Graph IDs; recovery keys and LAPS values are written to the timestamped audit log with a `SENSITIVE` prefix.
- **Authentication Fallback**: Added Device Code login to avoid browser localhost redirect / WAM issues with interactive Microsoft Graph authentication.

### Graph API Performance and Reliability
- **Retry Logic with Backoff**: New `Invoke-GraphRequestWithRetry` wrapper handles 429 throttling (reads Retry-After header), 5xx transient errors (exponential backoff), and network failures
- **Batch Requests**: New `Invoke-GraphBatchRequest` helper auto-chunks up to 20 sub-requests per `$batch` call with sub-request retry logic
  - Search queries batch Entra+Intune (device name) and Intune+Autopilot (serial number) lookups
  - Per-device offboarding batches Entra+Intune+Autopilot operations into a single `$batch` call
- **Dashboard Statistics via `$count`**: Single `$batch` call with `$count` sub-requests replaces 3 full-collection fetches and client-side counting, with automatic fallback for tenants without `$count` support
- **Bulk Autopilot Deletion**: Uses `deleteDevices` bulk endpoint when 2+ devices are selected, with individual deletion fallback
- **Migrated All Endpoints to Beta**: All v1.0 Graph API references replaced with beta across the main script and all playbooks
- **Added `$select` to All GET Calls**: Every GET endpoint now specifies only the properties used downstream, reducing API payload size

### New Features
- **Saved Authentication Config** (Issue #48): Save and auto-load certificate and client secret configurations to `%LocalAppData%/DeviceOffboardingManager`. Client secret is never persisted for security.
- **Co-Management Awareness**: Displays `ManagementAgent` property on devices and shows an amber warning banner in the confirmation dialog for co-managed devices
- **Platform Filtering on Dashboard** (Issue #40): ComboBox to filter all dashboard statistics by OS platform
- **Grid Filtering and Shift-Click Range Selection** (Issue #33): Filter TextBoxes above the DataGrid for live column filtering, shift-click on checkboxes to toggle device ranges
- **HTML Offboarding Report Generation**: Professional styled HTML reports with per-device service status and summary statistics, accessible via export buttons in summary and dashboard dialogs
- **Defender for Endpoint**: Now shown as a supported service on the homepage (no longer marked as "Soon"). Defender offboarding is optional and disabled by default; admins can enable it from Prerequisites to show the Defender target and request Defender API tokens only when used.
- **Autopilot Group Tag Management** (Issue #21): Set or clear the Autopilot group tag for selected devices from the device management results grid.

### New Playbooks
- **Playbook 6: OS-Specific Devices** -- Filter and list managed devices by operating system
- **Playbook 7: Outdated OS Devices** -- Identify devices running outdated OS versions
- **Playbook 8: End-of-Life OS Devices** -- Detect devices running end-of-life OS versions
- **Playbook 9: BitLocker Key Report** -- Retrieve BitLocker recovery key metadata for Windows devices
- **Playbook 10: FileVault Key Report** -- Check FileVault key availability for macOS devices
- **Playbook 11: Corporate Identifier Stale Report** -- List imported corporate device identifiers with enrollment state and last contact status
- **Shared Playbook Helpers**: Extracted common utility functions (`Get-GraphPagedResults`, `ConvertTo-SafeDateTime`, etc.) into `PlaybookHelpers.ps1` to reduce duplication across playbooks

---

## Version 0.2.2 - 7/26/2025

- **Fixed Autopilot Device Removal by Serial Number**: Enhanced offboarding process to properly retrieve and use serial numbers for Autopilot device removal (Issue #45)
  - Captures serial number from Intune device data during offboarding
  - Extracts serial number from Entra ID device physicalIds when available
  - Ensures devices searched by name can be properly removed from Autopilot
  - Fixes "BadRequest" API error when searching Autopilot devices by displayName
- **Fixed Critical Error with Duplicate Entra ID Devices**: Enhanced offboarding to handle duplicate device records in Entra ID (Issue #44)
  - Processes all duplicate devices instead of just the first one
  - Validates serial numbers to avoid deleting wrong duplicates
  - Provides detailed logging for each duplicate device processed
  - Reports partial success when some duplicates fail to delete
  - Prevents critical errors when multiple devices share the same name
- **Export Selected Devices to CSV**: Added new feature to export only selected device names to CSV (Issue #43)
  - Added "Export Selected" button next to existing "Export Results" button
  - Exports device names along with all metadata (serial number, OS, user, service status)
  - Button is enabled/disabled based on device selection
  - Allows easy transfer of device information to other systems for cleanup
  - Maintains consistent export format with existing export functionality
- **Enhanced Dialog Error Handling**: Added comprehensive error handling for all dialog windows (Issue #42)
  - Added null checks before calling ShowDialog() on all windows
  - Wrapped all ShowDialog() calls in try-catch blocks
  - Added error handling for window creation with XamlReader.Load()
  - Provides user-friendly error messages when dialogs fail to load
  - Prevents "null-valued expression" errors during offboarding

## Version 0.2.1 - 6/29/2025

- **Fixed Autopilot Device Removal**: Enhanced Autopilot device removal to use displayName as fallback when serial number is unavailable (Issue #34)
  - Added search by displayName for Autopilot devices
  - Improved handling of pre-provisioned Autopilot devices that may not be in Intune
  - Better error messages indicating why removal might fail
- **Fixed CSV Bulk Import**: CSV bulk import now automatically triggers device search after import (Issue #32)
  - Created centralized `Invoke-DeviceSearch` function for consistent search behavior
  - Added automatic search execution after CSV file selection
  - Improved validation for empty files and whitespace
- **Enhanced Device Search**: Improved device search to handle Autopilot-only devices (Related to Issue #34)
  - Devices existing only in Autopilot service are now properly displayed
  - Serial numbers are populated from any available source (Intune or Autopilot)
  - Fixed handling of devices that exist in Autopilot but not in Intune
- **Input Validation**: Added trimming of newlines and whitespace from search input to prevent accidental multi-line entries (Related to Issue #34)
- **Enhanced Bulk Import UI**: Replaced file dialog with professional modal interface for bulk device import
  - Added visual CSV template with example device identifiers
  - Implemented downloadable template CSV functionality
  - Added file preview showing first 10 devices before import
  - Improved error handling with clear visual feedback
  - Enhanced user experience with modern, consistent styling
- **Dynamic Version Display**: Added automatic version number display in window title
- **Improved Changelog Display**: Enhanced markdown rendering in changelog modal
  - Added support for **bold text** formatting
  - Added support for `inline code` formatting
  - Properly handles nested list indentation
  - Mixed formatting (bold, italic, code) now renders correctly
  - Improved visual styling with appropriate fonts and colors
- **Fixed Date Parsing Issues**: Implemented culture-invariant date parsing across the entire application
  - Fixed Autopilot last contact date showing 1/1/0001 12:00AM (Issue #31)
  - Fixed Playbook_1.ps1 date parsing error with culture-specific formats (Issue #30)
  - Fixed Dashboard date parsing errors causing multiple log entries (Issue #16)
  - Added `ConvertTo-SafeDateTime` helper function for consistent date handling
  - Updated all playbooks to use culture-invariant date parsing
  - Replaced all DateTime::Parse calls with safe parsing that handles multiple formats

## Version 0.2 - 6/20/2025

- **Improved Bulk Offboarding**: Removed individual device confirmation dialogs when offboarding multiple devices (Issue #28)
- **Offboarding Summary**: Added a comprehensive summary dialog that shows results for all devices after bulk offboarding
- **Enhanced Logging**: Added detailed logging for all offboarding operations to help troubleshoot issues
- **Better Error Handling**: Errors are now collected and displayed in the summary instead of interrupting the process
- **Fixed Playbook Downloads**: All 5 playbooks now download and execute correctly (Issue #26)
- **Enabled Additional Playbooks**: Enabled Intune Not in Autopilot, Corporate Devices, Personal Devices, and Stale Device Report playbooks
- **Selective Service Offboarding**: Added checkboxes to select/deselect specific services (Entra ID, Intune, Autopilot) during offboarding (Issue #25)
- **Service Selection Validation**: Added validation to ensure at least one service is selected before offboarding
- **Fixed BitLocker Permission Documentation**: Added missing BitlockerKey.Read.All permission to prerequisites (Issue #24)
- **Improved BitLocker Error Handling**: Added specific error messages when BitLocker permissions are missing
- **Fixed Entra ID Permission**: Updated Device.Read.All to Device.ReadWrite.All to enable device deletion from Entra ID (Issue #23)
- **Export to CSV Feature**: Added export functionality for device lists (Issue #20)
  - Export search results to CSV
  - Export playbook results to CSV
  - Includes all device details in a clean format
- **Clickable Dashboard Cards**: Made all dashboard cards interactive with export functionality
  - Click on any stale device card (30/90/180 days) to view and export the device list
  - Click on personal or corporate device cards to view and export those lists
  - Click on Intune, Autopilot, or Entra ID total device cards to view all devices from that service
  - Each card shows a modal with the device details and export button

## Version 0.1.1 - 1/18/2025

- **Improved Performance**: Intune data is being retrieved concurrently through threaded API calls for enhanced performance.
- **Check for available Update**: Implemented a Version Checker to notify you of available updates.
- **Select “All” Devices**: Added a new checkbox to select all devices from the search results.

## Version 0.1 - 1/11/2025

- Initial Release "Hello World!"
