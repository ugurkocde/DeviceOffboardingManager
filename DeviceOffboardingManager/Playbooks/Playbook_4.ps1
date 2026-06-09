# Playbook: List all personal devices in Intune
# This script identifies all personally-owned devices managed in Intune

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-PersonalDevices {
    try {
        # Get all personal devices from Intune
        Write-Host "Fetching personal devices from Intune..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=managedDeviceOwnerType eq 'personal'&`$select=deviceName,serialNumber,operatingSystem,model,managedDeviceOwnerType,lastSyncDateTime"
        $personalDevices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($personalDevices.Count) personal devices" -ForegroundColor Green

        # Format the devices for display
        $formattedDevices = $personalDevices | ForEach-Object {
            [PSCustomObject]@{
                DeviceName        = $_.deviceName
                SerialNumber      = $_.serialNumber
                OperatingSystem   = $_.operatingSystem
                Model             = $_.model
                OwnershipType     = $_.managedDeviceOwnerType
                IntuneLastContact = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime
            }
        }

        Write-Host "Successfully processed $($formattedDevices.Count) personal devices" -ForegroundColor Yellow
        return $formattedDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

# Execute the playbook and return results
$results = Get-PersonalDevices
if ($results) {
    # Display results in console for debugging
    $results | Format-Table -AutoSize
}

# Return results to be displayed in UI
return $results