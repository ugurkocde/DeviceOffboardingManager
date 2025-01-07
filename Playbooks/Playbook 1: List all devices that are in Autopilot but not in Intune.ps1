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
        Write-Host "Found $($autopilotDevices.Count) Autopilot devices" -ForegroundColor Green

        # Get all Intune devices
        Write-Host "Fetching Intune devices..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
        $intuneDevices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($intuneDevices.Count) Intune devices" -ForegroundColor Green

        # Create a HashSet of Intune serial numbers for efficient lookup
        $intuneSerialNumbers = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($device in $intuneDevices) {
            if ($device.serialNumber) {
                $intuneSerialNumbers.Add($device.serialNumber) | Out-Null
            }
        }

        # Find devices in Autopilot but not in Intune using efficient HashSet lookup
        $notEnrolledDevices = $autopilotDevices | Where-Object {
            -not $intuneSerialNumbers.Contains($_.serialNumber)
        } | ForEach-Object {
            [PSCustomObject]@{
                DeviceName = $_.displayName
                SerialNumber = $_.serialNumber
                OperatingSystem = "$($_.model) ($($_.manufacturer))"
                PrimaryUser = "Not enrolled"
                AutopilotLastContact = if ($_.lastContactDateTime) {
                    [DateTime]::Parse($_.lastContactDateTime)
                } else { $null }
            }
        }

        Write-Host "Found $($notEnrolledDevices.Count) devices in Autopilot that are not enrolled in Intune" -ForegroundColor Yellow
        return $notEnrolledDevices
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
