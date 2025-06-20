# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

DeviceOffboardingManager is a PowerShell-based GUI application for managing and offboarding devices from Microsoft Intune, Autopilot, and Entra ID. It uses Windows Presentation Framework (WPF) for the UI and integrates with Microsoft Graph API.

## Development Commands

### Running the Application

```powershell
# Ensure PowerShell 7+ is being used
$PSVersionTable.PSVersion

# Install required dependencies
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser

# Run the application
.\DeviceOffboardingManager.ps1
```

### Testing Changes

Since this is a GUI application without automated tests, testing is done manually:
1. Launch the application in PowerShell 7+
2. Test authentication methods (interactive, certificate, client secret)
3. Verify device search functionality
4. Test bulk import features
5. Validate dashboard analytics
6. Test playbook execution

### Publishing to PowerShell Gallery

```powershell
# Update version in the PSScriptInfo header
# Publish to PowerShell Gallery (requires API key)
Publish-PSResource -Path .\DeviceOffboardingManager.ps1 -Repository PSGallery
```

## Code Architecture

### Main Components

1. **DeviceOffboardingManager.ps1** (4,394 lines)
   - Entry point and main application logic
   - WPF GUI definition and event handlers
   - Microsoft Graph API integration
   - Version checking and update notifications

2. **Playbooks Directory**
   - Standalone PowerShell scripts for automated tasks
   - Each playbook is self-contained and can be run independently
   - Integration with main application through standardized output

### Key Design Patterns

1. **Authentication Management**
   - Supports multiple authentication methods
   - Stores connection state globally
   - Token management handled by Microsoft.Graph.Authentication module

2. **Concurrent API Calls**
   - Uses PowerShell runspaces for parallel data retrieval
   - Improves performance when fetching device data from multiple services

3. **Error Handling**
   - Comprehensive try-catch blocks throughout
   - User-friendly error messages in dialog boxes
   - Logging function for debugging (Write-Log)

4. **UI Threading**
   - WPF dispatcher for UI updates from background threads
   - Progress indicators during long-running operations

### Data Flow

1. User authenticates → Graph API connection established
2. Device search → Concurrent API calls to Intune/Autopilot/Entra ID
3. Results displayed in DataGrid → User selects devices
4. Offboarding action → Confirmation dialog → API calls to remove devices
5. Dashboard updates → Real-time statistics refresh

## Important Considerations

1. **PowerShell Version**: The application requires PowerShell 7.0 or higher and will not work with Windows PowerShell 5.1

2. **Permissions**: The application requires extensive Microsoft Graph permissions for device management

3. **No Automated Testing**: All changes must be manually tested in a development environment

4. **GUI Application**: Most functionality is tied to WPF UI events, making isolated testing challenging

5. **Version Management**: Version is tracked in the PSScriptInfo header and must be updated before publishing

6. **Dependencies**: Only external dependency is Microsoft.Graph.Authentication module

7. **Cross-Platform**: While PowerShell 7 is cross-platform, this application uses WPF which is Windows-only