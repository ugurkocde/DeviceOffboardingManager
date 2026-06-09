# Playbook: List all devices that are in Intune but not in Autopilot
# This script identifies devices that are managed in Intune but not registered in Windows Autopilot

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-IntuneNotAutopilotDevices {
    try {
        # Get all Autopilot devices
        Write-Host "Fetching Autopilot devices..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$select=serialNumber"
        $autopilotDevices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($autopilotDevices.Count) Autopilot devices" -ForegroundColor Green

        # Get all Intune devices
        Write-Host "Fetching Intune devices..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=id,deviceName,serialNumber,operatingSystem,model,userDisplayName,lastSyncDateTime"
        $intuneDevices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($intuneDevices.Count) Intune devices" -ForegroundColor Green

        # Create a HashSet of Autopilot serial numbers for efficient lookup
        $autopilotSerialNumbers = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($device in $autopilotDevices) {
            if ($device.serialNumber) {
                $autopilotSerialNumbers.Add($device.serialNumber) | Out-Null
            }
        }

        # Find devices in Intune but not in Autopilot using efficient HashSet lookup
        $notInAutopilotDevices = $intuneDevices | Where-Object {
            $_.serialNumber -and -not $autopilotSerialNumbers.Contains($_.serialNumber)
        } | ForEach-Object {
            [PSCustomObject]@{
                DeviceName        = $_.deviceName
                SerialNumber      = $_.serialNumber
                OperatingSystem   = $_.operatingSystem
                Model             = $_.model
                PrimaryUser       = $_.userDisplayName
                IntuneLastContact = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime
            }
        }

        Write-Host "Found $($notInAutopilotDevices.Count) devices in Intune that are not registered in Autopilot" -ForegroundColor Yellow
        return $notInAutopilotDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

# Execute the playbook and return results
$results = Get-IntuneNotAutopilotDevices
if ($results) {
    # Display results in console for debugging
    $results | Format-Table -AutoSize
}

# Return results to be displayed in UI
return $results