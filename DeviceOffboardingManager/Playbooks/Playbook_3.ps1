# Playbook: List all corporate devices in Intune
# This script identifies all company-owned devices managed in Intune

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-CorporateDevices {
    try {
        # Get all corporate devices from Intune
        Write-Host "Fetching corporate devices from Intune..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=managedDeviceOwnerType eq 'company'&`$select=deviceName,serialNumber,operatingSystem,model,managedDeviceOwnerType,lastSyncDateTime"
        $corporateDevices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($corporateDevices.Count) corporate devices" -ForegroundColor Green

        # Format the devices for display
        $formattedDevices = $corporateDevices | ForEach-Object {
            [PSCustomObject]@{
                DeviceName        = $_.deviceName
                SerialNumber      = $_.serialNumber
                OperatingSystem   = $_.operatingSystem
                Model             = $_.model
                OwnershipType     = $_.managedDeviceOwnerType
                IntuneLastContact = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime
            }
        }

        Write-Host "Successfully processed $($formattedDevices.Count) corporate devices" -ForegroundColor Yellow
        return $formattedDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

# Execute the playbook and return results
$results = Get-CorporateDevices
if ($results) {
    # Display results in console for debugging
    $results | Format-Table -AutoSize
}

# Return results to be displayed in UI
return $results