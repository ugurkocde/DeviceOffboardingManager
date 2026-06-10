[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$solutionFile = Join-Path $repoRoot 'DeviceOffboardingManager.WinUI.sln'
$projectRoot = Join-Path $repoRoot 'src/DeviceOffboardingManager.WinUI'
$projectFile = Join-Path $projectRoot 'DeviceOffboardingManager.WinUI.csproj'
$packageManifest = Join-Path $projectRoot 'Package.appxmanifest'
$launchSettings = Join-Path $projectRoot 'Properties/launchSettings.json'
$mainWindowXaml = Join-Path $projectRoot 'MainWindow.xaml'
$appXaml = Join-Path $projectRoot 'App.xaml'
$migrationPlan = Join-Path $repoRoot 'docs/v0.4-winui-migration-plan.md'

$requiredFiles = @(
    $solutionFile,
    $projectFile,
    $packageManifest,
    $launchSettings,
    $mainWindowXaml,
    $appXaml,
    (Join-Path $projectRoot 'App.xaml.cs'),
    (Join-Path $projectRoot 'MainWindow.xaml.cs'),
    (Join-Path $projectRoot 'app.manifest'),
    (Join-Path $projectRoot 'Models/DashboardDeviceCategory.cs'),
    (Join-Path $projectRoot 'Models/DeviceOffboardingSettings.cs'),
    (Join-Path $projectRoot 'Models/DeviceRecord.cs'),
    (Join-Path $projectRoot 'Models/OffboardingOptions.cs'),
    (Join-Path $projectRoot 'Services/Contracts/IAuthenticationService.cs'),
    (Join-Path $projectRoot 'Services/Contracts/IDeviceInventoryService.cs'),
    (Join-Path $projectRoot 'Services/Contracts/IOffboardingService.cs'),
    (Join-Path $projectRoot 'Services/Contracts/ISettingsService.cs'),
    (Join-Path $projectRoot 'Services/AuthenticationService.cs'),
    (Join-Path $projectRoot 'Services/DeviceInventoryService.cs'),
    (Join-Path $projectRoot 'Services/OffboardingService.cs'),
    (Join-Path $projectRoot 'Services/RecoveryKeyService.cs'),
    (Join-Path $projectRoot 'Services/PlaybookService.cs'),
    (Join-Path $projectRoot 'Services/SettingsService.cs'),
    (Join-Path $projectRoot 'Services/Graph/GraphApiClient.cs'),
    (Join-Path $projectRoot 'Services/Defender/DefenderApiClient.cs'),
    (Join-Path $projectRoot 'Services/ReportExportService.cs'),
    (Join-Path $projectRoot 'Services/AuditLogService.cs'),
    (Join-Path $projectRoot 'Assets/AppIcon.ico'),
    (Join-Path $projectRoot 'Assets/StoreLogo.png'),
    (Join-Path $projectRoot 'Assets/Square44x44Logo.png'),
    (Join-Path $projectRoot 'Assets/Square150x150Logo.png'),
    (Join-Path $projectRoot 'Assets/Wide310x150Logo.png'),
    $migrationPlan
)

foreach ($requiredFile in $requiredFiles) {
    if (-not (Test-Path $requiredFile)) {
        throw "Missing WinUI scaffold file: $requiredFile"
    }
}

$solutionText = Get-Content -Path $solutionFile -Raw
if ($solutionText -notmatch [regex]::Escape('src\DeviceOffboardingManager.WinUI\DeviceOffboardingManager.WinUI.csproj')) {
    throw 'The WinUI solution does not reference the WinUI project.'
}
foreach ($solutionPlatform in @('Debug|x64', 'Debug|x86', 'Debug|ARM64', 'Release|x64', 'Release|x86', 'Release|ARM64')) {
    if ($solutionText -notmatch [regex]::Escape("$solutionPlatform.Deploy.0 = $solutionPlatform")) {
        throw "The WinUI solution must enable deployment for $solutionPlatform."
    }
}

[xml]$projectXml = Get-Content -Path $projectFile -Raw
$properties = @{}
foreach ($propertyGroup in @($projectXml.Project.PropertyGroup)) {
    foreach ($child in @($propertyGroup.ChildNodes)) {
        if ($child.NodeType -eq 'Element') {
            $properties[$child.Name] = $child.InnerText
        }
    }
}

if ($properties['UseWinUI'] -ne 'true') {
    throw 'The WinUI project must set UseWinUI=true.'
}
if ($properties['WindowsPackageType'] -ne 'MSIX') {
    throw 'The WinUI project must be configured as an MSIX packaged app.'
}
if ($properties['EnableMsixTooling'] -ne 'true') {
    throw 'The WinUI project must enable MSIX tooling.'
}
if ($properties['ApplicationIcon'] -ne 'Assets\AppIcon.ico') {
    throw 'The WinUI project must reference the branded application icon.'
}
if ($properties['WindowsAppSdkDeploymentManagerInitialize'] -eq 'false') {
    throw 'The WinUI project must not disable the Windows App SDK Deployment Manager auto-initializer.'
}
if ($properties['TargetFramework'] -notmatch '^net[0-9]+\.0-windows10\.0\.19041\.0$') {
    throw "Unexpected WinUI target framework: $($properties['TargetFramework'])"
}

$packageReferences = @(
    Select-Xml -Path $projectFile -XPath '//PackageReference' |
        ForEach-Object { $_.Node.Include }
)
foreach ($packageName in @('Microsoft.WindowsAppSDK', 'Microsoft.Identity.Client', 'Microsoft.Graph', 'CommunityToolkit.Mvvm')) {
    if ($packageReferences -notcontains $packageName) {
        throw "Missing required WinUI package reference: $packageName"
    }
}
if (-not (Select-Xml -Path $projectFile -XPath '//Content[@Link="Changelog.md"]')) {
    throw 'The WinUI project must include Changelog.md as linked content for the About page.'
}

$launchSettingsJson = Get-Content -Path $launchSettings -Raw | ConvertFrom-Json
$launchProfiles = @($launchSettingsJson.profiles.PSObject.Properties.Value)
if (-not @($launchProfiles | Where-Object { $_.commandName -eq 'MsixPackage' })) {
    throw 'The WinUI project must include a launchSettings.json profile with commandName=MsixPackage for Visual Studio debugging.'
}

$sourceText = (Get-ChildItem -Path $projectRoot -Recurse -Filter '*.cs' | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
foreach ($requiredPattern in @(
        'AcquireTokenInteractive',
        'AcquireTokenWithDeviceCode',
        'AcquireTokenForClient',
        'DeviceManagementManagedDevices.ReadWrite.All',
        'DeviceManagementServiceConfig.ReadWrite.All',
        'Machine.Offboard',
        'deviceManagement/windowsAutopilotDeviceIdentities',
        'api.security.microsoft.com/api/machines',
        'informationProtection/bitlocker/recoveryKeys',
        'directory/deviceLocalCredentials',
        'getFileVaultKey',
        'importedDeviceIdentities',
        'Autopilot not in Intune',
        'GetDashboardDevicesAsync',
        'ExportOffboardingHtmlAsync')) {
    if ($sourceText -notmatch [regex]::Escape($requiredPattern)) {
        throw "The WinUI source is missing expected ported behavior: $requiredPattern"
    }
}
if ($sourceText -match 'Services\.Placeholders|not implemented yet') {
    throw 'The WinUI source still references placeholder services.'
}

foreach ($xamlFile in @($appXaml, $mainWindowXaml)) {
    [xml](Get-Content -Path $xamlFile -Raw) | Out-Null
}

$mainWindowText = Get-Content -Path $mainWindowXaml -Raw
if ($mainWindowText -match '<Grid\s+[^>]*Padding=') {
    throw 'WinUI Grid does not support Padding; use Margin or a padded Border instead.'
}
if ($mainWindowText -notmatch 'NavigationView') {
    throw 'The WinUI shell should include a NavigationView.'
}
foreach ($requiredControl in @(
        'HomePage',
        'DashboardPage',
        'DevicesPage',
        'OffboardingPage',
        'PlaybooksPage',
        'SettingsPage',
        'AboutPage',
        'DashboardPlatformFilter',
        'SelectAllDevicesBox',
        'ImportBulkFile_Click',
        'BrowseConfig_Click',
        'OpenChangelog_Click',
        'OpenRepository_Click',
        'ReviewSelectedIds_Click',
        'RunOffboarding_Click',
        'SetGroupTag_Click',
        'ExportLastPlaybook_Click',
        'ExportReport_Click')) {
    if ($mainWindowText -notmatch $requiredControl) {
        throw "The WinUI shell is missing required control or handler: $requiredControl"
    }
}
if ($mainWindowText -match '<muxc:Expander') {
    throw 'The WinUI app should use first-class pages instead of the old expander prototype shell.'
}

$manifestNamespace = @{
    appx = 'http://schemas.microsoft.com/appx/manifest/foundation/windows10'
}
$identity = Select-Xml -Path $packageManifest -Namespace $manifestNamespace -XPath '/appx:Package/appx:Identity'
if (-not $identity -or $identity.Node.Name -ne 'UgurKoc.DeviceOffboardingManager') {
    throw 'The package manifest identity is missing or unexpected.'
}

$planText = Get-Content -Path $migrationPlan -Raw
foreach ($requiredPlanTerm in @('Issue #60', 'MSIX', 'WinGet', 'Microsoft Store', 'AllSigned')) {
    if ($planText -notmatch [regex]::Escape($requiredPlanTerm)) {
        throw "The WinUI migration plan is missing required term: $requiredPlanTerm"
    }
}

[pscustomobject]@{
    Solution          = Split-Path -Path $solutionFile -Leaf
    Project           = Split-Path -Path $projectFile -Leaf
    TargetFramework   = $properties['TargetFramework']
    PackageReferences = $packageReferences.Count
    LaunchProfiles    = $launchProfiles.Count
    DeployProfiles    = ([regex]::Matches($solutionText, '\.Deploy\.0\s*=')).Count
    SourceFiles       = @(Get-ChildItem -Path $projectRoot -Recurse -Filter '*.cs').Count
    Assets            = 5
    IsValid           = $true
}
