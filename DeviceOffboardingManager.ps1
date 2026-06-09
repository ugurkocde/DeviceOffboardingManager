<#PSScriptInfo

.VERSION 0.3.0

.GUID a686724d-588d-472e-b927-c4840c32eed1

.AUTHOR ugurk

.COMPANYNAME

.COPYRIGHT

.TAGS Intune, PowerShell, Automation

.LICENSEURI https://github.com/ugurkocde/DeviceOffboardingManager/blob/main/LICENSE

.PROJECTURI https://github.com/ugurkocde/DeviceOffboardingManager

.ICONURI

.EXTERNALMODULEDEPENDENCIES Microsoft.Graph.Authentication

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES Changelog: https://github.com/ugurkocde/DeviceOffboardingManager/blob/main/Changelog.md

.PRIVATEDATA

#>

<#

.DESCRIPTION
Compatibility launcher for the DeviceOffboardingManager PowerShell module.

#>

[CmdletBinding()]
param(
    [switch]$ValidateOnly
)

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication

$moduleManifest = Join-Path $PSScriptRoot 'DeviceOffboardingManager/DeviceOffboardingManager.psd1'
if (-not (Test-Path $moduleManifest)) {
    throw "DeviceOffboardingManager module manifest was not found at: $moduleManifest"
}

Import-Module $moduleManifest -Force -ErrorAction Stop

$startParameters = @{}
if ($ValidateOnly) {
    $startParameters.ValidateOnly = $true
}
if ($PSBoundParameters.ContainsKey('Verbose')) {
    $startParameters.Verbose = $PSBoundParameters['Verbose']
}

Start-DeviceOffboardingManager @startParameters
