[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [int]$AppPid,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'ui-test-results')
)

$ErrorActionPreference = 'Continue'
$pass = 0
$fail = 0
$results = @()

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$screenshotDirectory = Join-Path $OutputDirectory 'screenshots'
New-Item -ItemType Directory -Path $screenshotDirectory -Force | Out-Null

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class UiTestWindow
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool MoveWindow(IntPtr hWnd, int x, int y, int width, int height, bool repaint);
}
'@

$windows = winapp ui list-windows -a $AppPid --json 2>$null | ConvertFrom-Json
$mainWindow = $windows | Where-Object { $_.title -ne 'PopupHost' } | Select-Object -First 1
$handleText = "$($mainWindow.hwnd)"
$handleValue = if ($handleText.StartsWith('0x', [StringComparison]::OrdinalIgnoreCase)) {
    [Convert]::ToInt64($handleText.Substring(2), 16)
}
else {
    [Convert]::ToInt64($handleText)
}
$appWindowHandle = [IntPtr]::new($handleValue)

function Resize-AppWindow {
    param(
        [int]$Width,
        [int]$Height
    )

    if (-not [UiTestWindow]::MoveWindow($appWindowHandle, 40, 40, $Width, $Height, $true)) {
        throw "Could not resize the app window to ${Width}x${Height}."
    }
    Start-Sleep -Milliseconds 500
}

function Test-UI {
    param(
        [string]$Name,
        [scriptblock]$Script
    )

    try {
        $global:LASTEXITCODE = 0
        $output = & $Script 2>&1
        if ($LASTEXITCODE -eq 0) {
            $script:pass++
            $script:results += @{ name = $Name; status = 'PASS' }
        }
        else {
            throw ($output -join [Environment]::NewLine)
        }
    }
    catch {
        $script:fail++
        $script:results += @{ name = $Name; status = 'FAIL'; detail = "$_" }
    }
}

function Save-StateScreenshot {
    param(
        [string]$Name,
        [int]$Index
    )

    $path = Join-Path $screenshotDirectory ("{0:D2}-{1}.png" -f $Index, $Name)
    winapp ui screenshot -a $AppPid -o $path 2>$null | Out-Null
}

function Test-VisibleAutomationIds {
    param([string]$PageName)

    try {
        $global:LASTEXITCODE = 0
        $inspection = winapp ui inspect -a $AppPid --interactive --json 2>$null | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            throw "UI inspection failed with exit code $LASTEXITCODE."
        }

        $interactiveElements = @($inspection.elements | Where-Object {
            $_.type -match 'Button|TextBox|ComboBox|CheckBox|ToggleSwitch|ListView|Edit' -and
            $_.name -notmatch 'Minimize|Maximize|Close|System' -and
            $_.className -notmatch 'PickerHost|#32770|CabinetWClass'
        })
        $missingIds = @($interactiveElements | Where-Object { -not $_.automationId })
        if ($missingIds.Count -gt 0) {
            $detail = ($missingIds | ForEach-Object { "$($_.type) '$($_.name)'" }) -join ', '
            throw "Missing AutomationId: $detail"
        }

        $script:pass++
        $script:results += @{ name = "$PageName AutomationId coverage"; status = 'PASS' }
    }
    catch {
        $script:fail++
        $script:results += @{ name = "$PageName AutomationId coverage"; status = 'FAIL'; detail = "$_" }
    }
}

Test-UI 'Home page loads' { winapp ui wait-for 'BtnHomeConnect' -a $AppPid -t 5000 }
Test-UI 'Shared status bar exists' { winapp ui wait-for 'StatusInfoBar' -a $AppPid -t 3000 }
Save-StateScreenshot -Name 'home' -Index 1
Test-VisibleAutomationIds -PageName 'Home'

Test-UI 'Navigate to Dashboard' { winapp ui invoke 'NavDashboard' -a $AppPid }
Test-UI 'Dashboard page loads' { winapp ui wait-for 'DashboardRefreshButton' -a $AppPid -t 3000 }
Save-StateScreenshot -Name 'dashboard' -Index 2
Test-VisibleAutomationIds -PageName 'Dashboard'

Test-UI 'Navigate to Devices' { winapp ui invoke 'NavDevices' -a $AppPid }
Test-UI 'Devices page loads' { winapp ui wait-for 'SearchTextBox' -a $AppPid -t 3000 }
Test-UI 'Search input commits immediately' {
    winapp ui set-value 'SearchTextBox' 'DOM-UI-TEST' -a $AppPid
    winapp ui wait-for 'SearchTextBox' -a $AppPid --value 'DOM-UI-TEST' -t 2000
}
Test-UI 'Device filter commits immediately' {
    winapp ui set-value 'FilterDeviceNameBox' 'Laptop' -a $AppPid
    winapp ui wait-for 'FilterDeviceNameBox' -a $AppPid --value 'Laptop' -t 2000
}
Save-StateScreenshot -Name 'devices' -Index 3
Test-VisibleAutomationIds -PageName 'Devices'

Test-UI 'Navigate to Offboarding' { winapp ui invoke 'NavOffboarding' -a $AppPid }
Test-UI 'Offboarding page loads' { winapp ui wait-for 'BtnRunOffboarding' -a $AppPid -t 3000 }
Test-UI 'Offboarding actions are keyboard-accessible controls' { winapp ui wait-for 'DeleteEntraBox' -a $AppPid -t 3000 }
Save-StateScreenshot -Name 'offboarding' -Index 4
Test-VisibleAutomationIds -PageName 'Offboarding'

Test-UI 'Navigate to Playbooks' { winapp ui invoke 'NavPlaybooks' -a $AppPid }
Test-UI 'Playbooks page loads' { winapp ui wait-for 'PlaybookBox' -a $AppPid -t 3000 }
Save-StateScreenshot -Name 'playbooks' -Index 5
Test-VisibleAutomationIds -PageName 'Playbooks'

Test-UI 'Navigate to Settings' { winapp ui invoke 'NavSettings' -a $AppPid }
Test-UI 'Settings page loads' { winapp ui wait-for 'ClientIdBox' -a $AppPid -t 3000 }
Test-UI 'Tenant ID commits immediately' {
    winapp ui set-value 'TenantIdBox' '00000000-0000-0000-0000-000000000000' -a $AppPid
    winapp ui wait-for 'TenantIdBox' -a $AppPid --value '00000000-0000-0000-0000-000000000000' -t 2000
}
Test-UI 'Defender toggle is readable' { winapp ui get-value 'DefenderToggle' -a $AppPid --json }
Save-StateScreenshot -Name 'settings' -Index 6
Test-VisibleAutomationIds -PageName 'Settings'

Test-UI 'Navigate to About' { winapp ui invoke 'NavAbout' -a $AppPid }
Test-UI 'About page loads' { winapp ui wait-for 'AboutVersionText' -a $AppPid -t 3000 }
Save-StateScreenshot -Name 'about' -Index 7
Test-VisibleAutomationIds -PageName 'About'

Test-UI 'Dashboard remains usable at compact width' {
    winapp ui invoke 'NavDashboard' -a $AppPid
    Resize-AppWindow -Width 640 -Height 800
    winapp ui wait-for 'DashboardRefreshButton' -a $AppPid -t 3000
    winapp ui wait-for 'BtnViewIntune' -a $AppPid -t 3000
}
Save-StateScreenshot -Name 'dashboard-compact' -Index 8
Test-UI 'Dashboard remains usable at wide width' {
    Resize-AppWindow -Width 1280 -Height 800
    winapp ui wait-for 'BtnDashboardDevices' -a $AppPid -t 3000
}
Save-StateScreenshot -Name 'dashboard-wide' -Index 9

$resultPath = Join-Path $OutputDirectory 'test-results.json'
$results | ConvertTo-Json -Depth 5 | Set-Content -Path $resultPath -Encoding utf8
Write-Host "Passed: $pass | Failed: $fail"
$results | Where-Object { $_.status -eq 'FAIL' } | ForEach-Object {
    Write-Host "FAIL: $($_.name) - $($_.detail)" -ForegroundColor Red
}

if ($fail -gt 0) {
    exit 1
}
