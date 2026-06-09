function Start-DeviceOffboardingManager {
    [CmdletBinding()]
    param(
        [switch]$ValidateOnly,
        [switch]$SmokeTest
    )

    $script:VerboseMode = $VerbosePreference -eq 'Continue'

    if (-not $script:DeviceOffboardingManagerModuleRoot) {
        $script:DeviceOffboardingManagerModuleRoot = Split-Path -Path $PSScriptRoot -Parent
    }
    $script:DeviceOffboardingManagerPlaybookRoot = Join-Path $script:DeviceOffboardingManagerModuleRoot 'Playbooks'

    $privateRoot = Join-Path $script:DeviceOffboardingManagerModuleRoot 'Private'
    $runtimeScript = Join-Path $privateRoot 'Runtime/Start-DeviceOffboardingManager.Runtime.ps1'
    $privateScripts = Get-ChildItem -Path $privateRoot -Recurse -Filter '*.ps1' |
        Where-Object { $_.FullName -ne $runtimeScript } |
        Sort-Object FullName

    foreach ($scriptFile in $privateScripts) {
        . $scriptFile.FullName
    }

    if ($ValidateOnly) {
        return Test-DeviceOffboardingModuleLayout
    }

    if ($SmokeTest) {
        return Test-DeviceOffboardingWindowsUi
    }

    Initialize-DeviceOffboardingAssemblies
    Initialize-DeviceObjectType

    $xaml = Get-DeviceOffboardingXaml -Name MainWindow
    $changelogModalXaml = Get-DeviceOffboardingXaml -Name ChangelogDialog
    $prerequisitesModalXaml = Get-DeviceOffboardingXaml -Name PrerequisitesDialog
    $authModalXaml = Get-DeviceOffboardingXaml -Name AuthenticationDialog
    $bulkImportModalXaml = Get-DeviceOffboardingXaml -Name BulkImportDialog
    $script:requiredPermissions = Get-DeviceOffboardingRequiredPermissions

    . $runtimeScript
}
