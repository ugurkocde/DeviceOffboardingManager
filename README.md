# ⚙️ Device Offboarding Manager

<div align="center">
  <p>
    <a href="https://twitter.com/UgurKocDe">
      <img src="https://img.shields.io/badge/Follow-@UgurKocDe-1DA1F2?style=flat&logo=x&logoColor=white" alt="Twitter Follow"/>
    </a>
    <a href="https://www.linkedin.com/in/ugurkocde/">
      <img src="https://img.shields.io/badge/LinkedIn-Connect-0A66C2?style=flat&logo=linkedin" alt="LinkedIn"/>
    </a>
    <img src="https://img.shields.io/github/license/ugurkocde/IntuneAssignmentChecker?style=flat" alt="License"/>
  </p>
  <a href="https://www.powershellgallery.com/packages/DeviceOffboardingManager">
      <img src="https://img.shields.io/powershellgallery/v/DeviceOffboardingManager?style=flat&label=PSGallery%20Version" alt="PowerShell Gallery Version"/>
    </a>
    <a href="https://www.powershellgallery.com/packages/DeviceOffboardingManager">
      <img src="https://img.shields.io/powershellgallery/dt/DeviceOffboardingManager?style=flat&label=PSGallery%20Downloads&color=brightgreen" alt="PowerShell Gallery Downloads"/>
    </a>
</div>

A modern PowerShell-based GUI tool for managing and offboarding devices from Microsoft Intune, Autopilot, and Entra ID (formerly Azure AD). This tool provides a streamlined interface for device lifecycle management across Microsoft services.

## Watch the full walkthrough of the tool:

<div align="center">
      <a href="https://www.youtube.com/watch?v=CbximIIAEgc">
     <img
      src="https://img.youtube.com/vi/CbximIIAEgc/maxresdefault.jpg"
      alt="IntuneAssignmentChecker"
      style="width:100%;">
      </a>
</div>

## Table of Contents

- [⚙️ Device Offboarding Manager](#️-device-offboarding-manager)
  - [Watch the full walkthrough of the tool:](#watch-the-full-walkthrough-of-the-tool)
  - [Table of Contents](#table-of-contents)
  - [🚀 Quick Start](#-quick-start)
    - [Option 1: Install from PowerShell Gallery (Recommended)](#option-1-install-from-powershell-gallery-recommended)
    - [Option 2: Manual Installation](#option-2-manual-installation)
  - [🎯 Features](#-features)
    - [🔑 Core Functionality](#-core-functionality)
    - [💻 Device Management](#-device-management)
    - [📊 Dashboard Analytics](#-dashboard-analytics)
    - [📚 Playbooks](#-playbooks)
  - [⚡ Prerequisites](#-prerequisites)
  - [🔧 Usage](#-usage)
    - [🔐 Authentication](#-authentication)
    - [💻 Device Management](#-device-management-1)
    - [📊 Dashboard](#-dashboard)
    - [📚 Playbooks](#-playbooks-1)
  - [👥 Contributing](#-contributing)
  - [📄 License](#-license)

## 🚀 Quick Start

> **Important**: All commands must be run in a PowerShell 7 session on Windows. The WPF desktop UI will not work in PowerShell 5.1 or on non-Windows platforms.

### Option 1: Install from PowerShell Gallery (Recommended)

```powershell
# Install Microsoft Graph Authentication Module
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser

# Install from PowerShell Gallery as a module
Install-Module DeviceOffboardingManager -Scope CurrentUser
```

```powershell
# Open a new PowerShell 7 session to run the tool
Start-DeviceOffboardingManager
```

### Option 2: Manual Installation

```powershell
# Install Microsoft Graph Authentication Module
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser

# Import the local module from the repository
Import-Module .\DeviceOffboardingManager\DeviceOffboardingManager.psd1 -Force
Start-DeviceOffboardingManager

# Existing script usage remains supported through the compatibility launcher
.\DeviceOffboardingManager.ps1
```

### Update to the latest Version

```powershell
# Restart the PowerShell Session after installing the new version
Update-Module DeviceOffboardingManager -Force
```

### Verify a Local Build

```powershell
# Cross-platform module/package checks
.\tests\Verify-Module.ps1

# Windows-only WPF resource smoke test
.\tests\Verify-WindowsUi.ps1
```

## 🎯 Features

### 🔑 Core Functionality

- **Multi-Service Integration**: Manage devices across Intune, Autopilot, Entra ID, and Defender for Endpoint
- **PowerShell Module Packaging**: Install as a module and launch with `Start-DeviceOffboardingManager`; the root script remains as a compatibility launcher
- **Bulk Operations**: Support for bulk device imports and operations
- **Real-time Dashboard**: View device statistics and distribution
- **Secure Authentication**: Multiple authentication methods including interactive, device code, certificate, and client secret

### 💻 Device Management

![Homer](media/device_offboarding.png)

- Search devices by name, serial number, partial match, or Entra device ID
- View device details including:
  - Last contact times
  - Operating system
  - Primary user
  - Compliance state
  - Management status across services
- Bulk device offboarding with exact Graph ID confirmation
- Optional Entra disable, Intune retire/wipe, and settings-gated Defender for Endpoint offboarding actions
- Automatic retrieval of BitLocker/FileVault keys and LAPS passwords
- Autopilot group tag updates for selected devices

### 📊 Dashboard Analytics

![Dashboard Analytics](media/dashboard.png)

- Total device counts per service
- Stale device tracking (30/90/180 days)
- Personal vs Corporate device distribution
- Platform distribution visualization
- Real-time statistics updates

### 📚 Playbooks

![Playbooks](media/playbooks.png)

- Automated device management tasks
- Pre-built reports and analyses
- Custom playbook support for specific scenarios

## ⚡ Prerequisites

1. PowerShell 7.0 or higher
2. Microsoft.Graph.Authentication module
3. Required Microsoft Graph API permissions:
   - Device.ReadWrite.All
   - DeviceManagementApps.Read.All
   - DeviceManagementConfiguration.Read.All
   - DeviceManagementManagedDevices.ReadWrite.All
   - DeviceManagementServiceConfig.ReadWrite.All
   - Group.Read.All
   - User.Read.All
   - BitlockerKey.Read.All
   - DeviceLocalCredential.Read.All
4. Optional Defender for Endpoint offboarding:
   - Disabled by default for tenants without Defender for Endpoint
   - Enable from the Prerequisites dialog before it appears as an offboarding target
   - MSAL.PS module
   - Defender API `Machine.ReadWrite.All` and `Machine.Offboard` permissions on the `WindowsDefenderATP` API

## 🔧 Usage

### 🔐 Authentication

The tool supports four authentication methods:

1. **Interactive Login**: Best for admin users with appropriate permissions
2. **Device Code Login**: Browser-redirect-free fallback for localhost redirect or WAM issues
3. **Certificate-based**: For automated or service principal authentication
4. **Client Secret**: Alternative service principal authentication method

To connect:

1. Click "Connect to MS Graph" in the sidebar
2. Choose your authentication method
3. Provide required credentials
4. Verify connection status in the tenant information section

### 💻 Device Management

1. **Search for Devices**:

   - Select search type (Device name, Serial number, Device ID, or Contains)
   - Enter search terms (supports multiple values with comma separation)
   - Click Search to retrieve device information

2. **Bulk Import**:

   - Click "Bulk Import"
   - Select a CSV/TXT file containing device names or serial numbers
   - Verify imported devices in the search field

3. **Device Offboarding**:
   - Select devices in the results grid
   - Click "Offboard device(s)"
   - Review the confirmation dialog
   - Note any encryption recovery keys
   - Confirm the operation

4. **Defender for Endpoint Offboarding**:
   - Open "Prerequisites"
   - Enable "Defender for Endpoint integration"
   - Consent the required `WindowsDefenderATP` permissions
   - Select "Defender for Endpoint" during offboarding when needed

5. **Autopilot Group Tags**:
   - Select devices in the results grid
   - Click "Set Group Tag"
   - Enter a tag or clear the existing tag

### 📊 Dashboard

The dashboard provides real-time insights into your device management environment:

- Device counts across services
- Stale device tracking
- Ownership distribution
- Platform distribution
- Quick access to common tasks

### 📚 Playbooks

Automated tasks for common scenarios:

- Find Autopilot devices not in Intune
- List Intune devices not in Autopilot
- Generate corporate device inventory
- View personal device inventory
- Analyze stale devices
- OS-specific device reports
- Encryption key reports
- Corporate device identifier stale report

Playbooks are bundled in the module under `DeviceOffboardingManager/Playbooks/`. In environments using an `AllSigned` execution policy, sign the module files, compatibility launcher, and local playbook files with your organization certificate before running the tool.

## 👥 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
