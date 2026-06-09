[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$moduleManifest = Join-Path $repoRoot 'DeviceOffboardingManager/DeviceOffboardingManager.psd1'
$launcher = Join-Path $repoRoot 'DeviceOffboardingManager.ps1'

$parseErrors = New-Object System.Collections.Generic.List[string]
foreach ($path in Get-ChildItem -Path $repoRoot -Recurse -Filter '*.ps1') {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($errorRecord in $errors) {
        $parseErrors.Add("$($path.FullName):$($errorRecord.Extent.StartLineNumber): $($errorRecord.Message)")
    }
}

$moduleSourceFiles = Get-ChildItem -Path (Join-Path $repoRoot 'DeviceOffboardingManager') -Recurse -Include *.ps1,*.xaml
$moduleSourceText = ($moduleSourceFiles | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
$findNameTargets = @(
    [regex]::Matches($moduleSourceText, '\.FindName\(([''"])(?<name>[^''"]+)\1\)') |
        ForEach-Object { $_.Groups['name'].Value } |
        Sort-Object -Unique
)
$definedXamlNames = @(
    [regex]::Matches($moduleSourceText, 'x:Name\s*=\s*([''"])(?<name>[^''"]+)\1') |
        ForEach-Object { $_.Groups['name'].Value } |
        Sort-Object -Unique
)
$missingXamlNames = @($findNameTargets | Where-Object { $definedXamlNames -notcontains $_ })
if ($missingXamlNames.Count -gt 0) {
    throw "FindName targets missing from XAML resources: $($missingXamlNames -join ', ')"
}

if ($parseErrors.Count -gt 0) {
    throw "Parser errors found:`n$($parseErrors -join [Environment]::NewLine)"
}

$runtimeText = Get-Content -Path (Join-Path $repoRoot 'DeviceOffboardingManager/Private/Runtime/Start-DeviceOffboardingManager.Runtime.ps1') -Raw
$summaryText = Get-Content -Path (Join-Path $repoRoot 'DeviceOffboardingManager/Private/UI/Show-OffboardingSummary.ps1') -Raw
$connectText = Get-Content -Path (Join-Path $repoRoot 'DeviceOffboardingManager/Private/Auth/Connect-ToGraph.ps1') -Raw
$mdeAuthText = Get-Content -Path (Join-Path $repoRoot 'DeviceOffboardingManager/Private/Auth/Get-MdeAccessToken.ps1') -Raw

if ($runtimeText -notmatch '\$offboardMde\s*=\s*\(Get-DefenderIntegrationEnabled\)') {
    throw 'Defender offboarding is not gated by the Defender integration setting in the runtime.'
}
if ($summaryText -notmatch '\$mdeSelected\s*=\s*\(Get-DefenderIntegrationEnabled\)') {
    throw 'Defender summary display is not gated by the Defender integration setting.'
}
if ($connectText -notmatch 'SecretSecureString' -or $connectText -notmatch '\$script:CurrentAuthDetails') {
    throw 'Graph authentication no longer preserves session-only auth metadata for Defender token acquisition.'
}
if ($mdeAuthText -notmatch '-ClientSecret\s+\$script:CurrentAuthDetails\.SecretSecureString' -or
    $mdeAuthText -notmatch '-ClientCertificate\s+\$certificate') {
    throw 'Defender token acquisition no longer supports app-only client secret and certificate flows.'
}

$manifest = Test-ModuleManifest -Path $moduleManifest
if ($manifest.Name -ne 'DeviceOffboardingManager') {
    throw "Unexpected module name: $($manifest.Name)"
}
if (-not $manifest.ExportedFunctions.ContainsKey('Start-DeviceOffboardingManager')) {
    throw 'Start-DeviceOffboardingManager is not exported by the module manifest.'
}

Import-Module $moduleManifest -Force
$commands = @(Get-Command -Module DeviceOffboardingManager)
if ($commands.Count -ne 1 -or $commands[0].Name -ne 'Start-DeviceOffboardingManager') {
    throw "Unexpected exported commands: $($commands.Name -join ', ')"
}

$moduleValidation = Start-DeviceOffboardingManager -ValidateOnly
if (-not $moduleValidation.IsValid) {
    throw "Module validation failed: $($moduleValidation | ConvertTo-Json -Depth 5)"
}

$launcherValidation = & $launcher -ValidateOnly
if (-not $launcherValidation.IsValid) {
    throw "Compatibility launcher validation failed: $($launcherValidation | ConvertTo-Json -Depth 5)"
}

$smokeTestResult = $null
if ($IsWindows) {
    $smokeTestResult = Start-DeviceOffboardingManager -SmokeTest
    if (-not $smokeTestResult.IsValid) {
        throw "Windows UI smoke test failed: $($smokeTestResult | ConvertTo-Json -Depth 5)"
    }
}
else {
    try {
        Start-DeviceOffboardingManager -SmokeTest | Out-Null
        throw 'Unexpected Windows UI smoke test success on a non-Windows host.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'requires Windows') {
            throw
        }
    }
}

$temporaryModuleRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DOM_ModuleVerify_$([System.Guid]::NewGuid().ToString('N'))"
try {
    New-Item -Path $temporaryModuleRoot -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $repoRoot 'DeviceOffboardingManager') -Destination $temporaryModuleRoot -Recurse -Force

    Remove-Module DeviceOffboardingManager -Force -ErrorAction SilentlyContinue
    $previousModulePath = $env:PSModulePath
    $env:PSModulePath = "$temporaryModuleRoot$([System.IO.Path]::PathSeparator)$previousModulePath"

    Import-Module DeviceOffboardingManager -Force
    $packagedCommand = Get-Command -Module DeviceOffboardingManager -Name Start-DeviceOffboardingManager -ErrorAction Stop
    $packagedValidation = Start-DeviceOffboardingManager -ValidateOnly
    if (-not $packagedValidation.IsValid) {
        throw "Packaged module validation failed: $($packagedValidation | ConvertTo-Json -Depth 5)"
    }
}
finally {
    $env:PSModulePath = $previousModulePath
    Remove-Module DeviceOffboardingManager -Force -ErrorAction SilentlyContinue
    if (Test-Path $temporaryModuleRoot) {
        Remove-Item -Path $temporaryModuleRoot -Recurse -Force
    }
}

[pscustomobject]@{
    ParserFilesChecked = @(Get-ChildItem -Path $repoRoot -Recurse -Filter '*.ps1').Count
    ModuleName         = $manifest.Name
    ModuleVersion      = $manifest.Version.ToString()
    ExportedCommand    = $commands[0].Name
    PackagedCommand    = $packagedCommand.Name
    FindNameTargets    = $findNameTargets.Count
    PlaybookCount      = $moduleValidation.PlaybookCount
    WindowsUiSmokeTest = if ($IsWindows) { $smokeTestResult.IsValid } else { 'SkippedOnNonWindowsWithExpectedGuard' }
    IsValid            = $true
}
