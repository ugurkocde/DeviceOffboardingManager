# Playbook: List all corporate devices in Intune
# This script identifies all company-owned devices managed in Intune

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

function Get-CorporateDevices {
    try {
        # Get all corporate devices from Intune
        Write-Host "Fetching corporate devices from Intune..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=managedDeviceOwnerType eq 'company'"
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
                IntuneLastContact = if ($_.lastSyncDateTime) {
                    [DateTime]::Parse($_.lastSyncDateTime)
                }
                else { $null }
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