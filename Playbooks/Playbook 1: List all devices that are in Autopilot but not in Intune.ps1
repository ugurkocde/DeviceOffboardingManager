# Playbook: List all devices that are in Autopilot but not in Intune
# This script identifies devices that are registered in Windows Autopilot but not present in Intune management

function Get-GraphPagedResults {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )
    
    $results = @()
    $nextLink = $Uri
    
    do {
        try {
            $response = Invoke-MgGraphRequest -Uri $nextLink -Method GET
            if ($response.value) {
                $results += $response.value
            }
            $nextLink = $response.'@odata.nextLink'
        }
        catch {
            Write-Error "Error in pagination: $_"
            break
        }
    } while ($nextLink)
    
    return $results
}

function Get-AutopilotNotIntuneDevices {
    try {
        # Get all Autopilot devices
        Write-Host "Fetching Autopilot devices..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities"
        $autopilotDevices = Get-GraphPagedResults -Uri $uri

        if (-not $autopilotDevices) {
            Write-Host "No Autopilot devices found." -ForegroundColor Yellow
            return $null
        }

        Write-Host "Found $($autopilotDevices.Count) Autopilot devices" -ForegroundColor Green

        # Get all Intune devices
        Write-Host "Fetching Intune devices..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
        $intuneDevices = Get-GraphPagedResults -Uri $uri

        if (-not $intuneDevices) {
            Write-Host "No Intune devices found." -ForegroundColor Yellow
            return $autopilotDevices # All Autopilot devices are missing from Intune
        }

        Write-Host "Found $($intuneDevices.Count) Intune devices" -ForegroundColor Green

        # Find devices in Autopilot but not in Intune
        $missingDevices = @()
        foreach ($autopilotDevice in $autopilotDevices) {
            $foundInIntune = $false
            foreach ($intuneDevice in $intuneDevices) {
                if ($intuneDevice.serialNumber -eq $autopilotDevice.serialNumber) {
                    $foundInIntune = $true
                    break
                }
            }
            
            if (-not $foundInIntune) {
                $deviceInfo = [PSCustomObject]@{
                    DeviceName = $autopilotDevice.displayName
                    SerialNumber = $autopilotDevice.serialNumber
                    OperatingSystem = "$($autopilotDevice.model) ($($autopilotDevice.manufacturer))"
                    PrimaryUser = "Not enrolled"
                    AutopilotLastContact = if ($autopilotDevice.lastContactDateTime) {
                        [DateTime]::Parse($autopilotDevice.lastContactDateTime)
                    } else { $null }
                }
                $missingDevices += $deviceInfo
            }
        }

        # Return results
        if ($missingDevices.Count -eq 0) {
            Write-Host "All Autopilot devices are properly enrolled in Intune." -ForegroundColor Green
            return $null
        } else {
            Write-Host "Found $($missingDevices.Count) devices in Autopilot that are not enrolled in Intune:" -ForegroundColor Yellow
            return $missingDevices
        }
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

# Execute the playbook and return results
$results = Get-AutopilotNotIntuneDevices
if ($results) {
    # Display results in console for debugging
    $results | Format-Table -AutoSize
}

# Return results to be displayed in UI
return $results
