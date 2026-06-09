# Playbook: Identify devices running end-of-life OS versions
# This script checks devices against known OS end-of-life dates

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-EOLDevices {
    # End-of-life dates for OS versions (OS name pattern -> EOL date)
    $eolTable = @(
        @{ Pattern = "^10\.0\.(1904[0-3]|1836[0-7]|1776[0-5]|1713[0-4]|1658[0-9]|1600[0-9]|1439[0-3]|1058[0-6]|1024[0-0])"; OS = "Windows 10"; EOLDate = "2025-10-14" }
        @{ Pattern = "^12\."; OS = "macOS 12 Monterey"; EOLDate = "2024-09-16" }
        @{ Pattern = "^13\."; OS = "macOS 13 Ventura"; EOLDate = "2025-10-01" }
        @{ Pattern = "^16\."; OS = "iOS 16"; EOLDate = "2024-09-16" }
        @{ Pattern = "^17\."; OS = "iOS 17"; EOLDate = "2025-09-15" }
        @{ Pattern = "^13$|^13\."; OS = "Android 13"; EOLDate = "2025-03-01" }
    )

    try {
        Write-Host "Fetching all managed devices..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=deviceName,serialNumber,operatingSystem,osVersion,lastSyncDateTime"
        $devices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($devices.Count) total devices" -ForegroundColor Green

        $eolDevices = @()
        $today = Get-Date

        foreach ($device in $devices) {
            $osVersion = $device.osVersion
            $osName = $device.operatingSystem
            if (-not $osVersion) { continue }

            foreach ($eolEntry in $eolTable) {
                $matchVersion = $osVersion
                # For Windows, use the full build number; for others use osVersion directly
                if ($osName -eq "Windows" -and $osVersion -match "^10\.0\.(\d+)") {
                    $matchVersion = $osVersion
                } elseif ($osName -ne "Windows") {
                    $matchVersion = $osVersion
                }

                if ($matchVersion -match $eolEntry.Pattern) {
                    $eolDate = [DateTime]::Parse($eolEntry.EOLDate)
                    $daysPast = [Math]::Ceiling(($today - $eolDate).TotalDays)

                    $eolDevices += [PSCustomObject]@{
                        DeviceName        = $device.deviceName
                        SerialNumber      = $device.serialNumber
                        OperatingSystem   = "$osName ($($eolEntry.OS))"
                        OSVersion         = $osVersion
                        EndOfSupportDate  = $eolEntry.EOLDate
                        DaysPastEOL       = $daysPast
                    }
                    break
                }
            }
        }

        $eolDevices = $eolDevices | Sort-Object -Property DaysPastEOL -Descending
        Write-Host "Found $($eolDevices.Count) devices running EOL operating systems" -ForegroundColor Yellow
        return $eolDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

$results = Get-EOLDevices
if ($results) {
    $results | Format-Table -AutoSize
}

return $results
