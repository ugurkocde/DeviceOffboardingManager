# Playbook: Find devices running outdated OS versions
# This script compares device OS versions against known latest versions

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-OutdatedOSDevices {
    # Latest known OS versions (update these as new versions release)
    $latestVersions = @{
        "Windows" = "10.0.26100"   # Windows 11 24H2
        "macOS"   = "15.3"
        "iOS"     = "18.3"
        "Android" = "15"
    }

    try {
        Write-Host "Fetching all managed devices..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=deviceName,serialNumber,operatingSystem,osVersion,lastSyncDateTime"
        $devices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($devices.Count) total devices" -ForegroundColor Green

        $outdatedDevices = @()
        foreach ($device in $devices) {
            $os = $device.operatingSystem
            $currentVersion = $device.osVersion

            if (-not $currentVersion -or -not $os) { continue }

            $latestVersion = $null
            foreach ($key in $latestVersions.Keys) {
                if ($os -match $key) {
                    $latestVersion = $latestVersions[$key]
                    break
                }
            }

            if (-not $latestVersion) { continue }

            # Compare versions - device is outdated if its version is less than the latest
            try {
                $currentParts = $currentVersion -split '\.' | ForEach-Object { [int]$_ }
                $latestParts = $latestVersion -split '\.' | ForEach-Object { [int]$_ }

                $isOutdated = $false
                $maxParts = [Math]::Max($currentParts.Count, $latestParts.Count)
                for ($i = 0; $i -lt $maxParts; $i++) {
                    $c = if ($i -lt $currentParts.Count) { $currentParts[$i] } else { 0 }
                    $l = if ($i -lt $latestParts.Count) { $latestParts[$i] } else { 0 }
                    if ($c -lt $l) { $isOutdated = $true; break }
                    if ($c -gt $l) { break }
                }

                if ($isOutdated) {
                    $outdatedDevices += [PSCustomObject]@{
                        DeviceName        = $device.deviceName
                        SerialNumber      = $device.serialNumber
                        OperatingSystem   = $os
                        CurrentVersion    = $currentVersion
                        LatestVersion     = $latestVersion
                        IntuneLastContact = ConvertTo-SafeDateTime -dateString $device.lastSyncDateTime
                    }
                }
            }
            catch {
                # Skip devices with unparseable versions
                continue
            }
        }

        Write-Host "Found $($outdatedDevices.Count) devices with outdated OS" -ForegroundColor Yellow
        return $outdatedDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

$results = Get-OutdatedOSDevices
if ($results) {
    $results | Format-Table -AutoSize
}

return $results
