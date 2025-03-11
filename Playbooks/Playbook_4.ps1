# Playbook: List all personal devices in Intune
# This script identifies all personally-owned devices managed in Intune

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

function Get-PersonalDevices {
    try {
        # Get all personal devices from Intune
        Write-Host "Fetching personal devices from Intune..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=managedDeviceOwnerType eq 'personal'"
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
                IntuneLastContact = if ($_.lastSyncDateTime) {
                    [DateTime]::Parse($_.lastSyncDateTime)
                }
                else { $null }
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