## Version 0.2 - TBD

- **Improved Bulk Offboarding**: Removed individual device confirmation dialogs when offboarding multiple devices (Issue #28)
- **Offboarding Summary**: Added a comprehensive summary dialog that shows results for all devices after bulk offboarding
- **Enhanced Logging**: Added detailed logging for all offboarding operations to help troubleshoot issues
- **Better Error Handling**: Errors are now collected and displayed in the summary instead of interrupting the process
- **Fixed Playbook Downloads**: All 5 playbooks now download and execute correctly (Issue #26)
- **Enabled Additional Playbooks**: Enabled Intune Not in Autopilot, Corporate Devices, Personal Devices, and Stale Device Report playbooks
- **Selective Service Offboarding**: Added checkboxes to select/deselect specific services (Entra ID, Intune, Autopilot) during offboarding (Issue #25)
- **Service Selection Validation**: Added validation to ensure at least one service is selected before offboarding

## Version 0.1.1 - 1/18/2025

- **Improved Performance**: Intune data is being retrieved concurrently through threaded API calls for enhanced performance.
- **Check for available Update**: Implemented a Version Checker to notify you of available updates.
- **Select “All” Devices**: Added a new checkbox to select all devices from the search results.

## Version 0.1 - 1/11/2025

- Initial Release "Hello World!"
