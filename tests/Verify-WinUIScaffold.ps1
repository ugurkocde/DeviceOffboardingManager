[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$solutionFile = Join-Path $repoRoot 'DeviceOffboardingManager.WinUI.sln'
$projectRoot = Join-Path $repoRoot 'src/DeviceOffboardingManager.WinUI'
$projectFile = Join-Path $projectRoot 'DeviceOffboardingManager.WinUI.csproj'
$packageManifest = Join-Path $projectRoot 'Package.appxmanifest'
$mainWindowXaml = Join-Path $projectRoot 'MainWindow.xaml'
$appXaml = Join-Path $projectRoot 'App.xaml'
$migrationPlan = Join-Path $repoRoot 'docs/v0.4-winui-migration-plan.md'

$requiredFiles = @(
    $solutionFile,
    $projectFile,
    $packageManifest,
    $mainWindowXaml,
    $appXaml,
    (Join-Path $projectRoot 'App.xaml.cs'),
    (Join-Path $projectRoot 'MainWindow.xaml.cs'),
    (Join-Path $projectRoot 'app.manifest'),
    (Join-Path $projectRoot 'Models/DeviceOffboardingSettings.cs'),
    (Join-Path $projectRoot 'Services/Contracts/IAuthenticationService.cs'),
    (Join-Path $projectRoot 'Services/Contracts/IDeviceInventoryService.cs'),
    (Join-Path $projectRoot 'Services/Contracts/IOffboardingService.cs'),
    (Join-Path $projectRoot 'Services/Contracts/ISettingsService.cs'),
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
if ($properties['EnableMsixTooling'] -ne 'true') {
    throw 'The WinUI project must enable MSIX tooling.'
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
    Assets            = 4
    IsValid           = $true
}
