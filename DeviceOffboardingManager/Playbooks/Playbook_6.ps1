# Playbook: List devices by operating system
# This script filters managed devices by a specified operating system

param(
    [string]$OSFilter = "Windows"
)

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-OSSpecificDevices {
    param(
        [string]$OSFilter = "Windows"
    )

    try {
        Write-Host "Fetching $OSFilter devices from Intune..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=operatingSystem eq '$OSFilter'&`$select=deviceName,serialNumber,operatingSystem,model,osVersion,lastSyncDateTime,userDisplayName"
        $devices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($devices.Count) $OSFilter devices" -ForegroundColor Green

        $formattedDevices = $devices | ForEach-Object {
            [PSCustomObject]@{
                DeviceName        = $_.deviceName
                SerialNumber      = $_.serialNumber
                OperatingSystem   = $_.operatingSystem
                Model             = $_.model
                OSVersion         = $_.osVersion
                IntuneLastContact = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime
                PrimaryUser       = $_.userDisplayName
            }
        }

        Write-Host "Successfully processed $($formattedDevices.Count) devices" -ForegroundColor Yellow
        return $formattedDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

$results = Get-OSSpecificDevices -OSFilter $OSFilter
if ($results) {
    $results | Format-Table -AutoSize
}

return $results
