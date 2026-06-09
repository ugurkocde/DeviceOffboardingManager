[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
    throw 'Verify-WindowsUi.ps1 must be run on Windows because Device Offboarding Manager uses WPF.'
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$moduleManifest = Join-Path $repoRoot 'DeviceOffboardingManager/DeviceOffboardingManager.psd1'

Import-Module $moduleManifest -Force
Start-DeviceOffboardingManager -SmokeTest
