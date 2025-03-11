# Playbook: List all stale devices in Intune
# This script identifies devices that haven't checked in for a specified number of days

param(
    [int]$StaleDays = 30 # Default to 30 days if not specified
)

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

function Get-StaleDevices {
    param(
        [int]$StaleDays = 30
    )
    
    try {
        # Calculate the stale date threshold
        $staleDate = (Get-Date).AddDays(-$StaleDays)
        $staleDateString = $staleDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
        
        # Get all stale devices from Intune
        Write-Host "Fetching devices not synced since $staleDateString..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=lastSyncDateTime lt $staleDateString"
        $staleDevices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($staleDevices.Count) stale devices" -ForegroundColor Green

        # Format the devices for display and calculate days since last sync
        $formattedDevices = $staleDevices | ForEach-Object {
            $lastSyncDate = if ($_.lastSyncDateTime) { [DateTime]::Parse($_.lastSyncDateTime) } else { $null }
            $diffDays = if ($lastSyncDate) { 
                [Math]::Ceiling(([DateTime]::Now - $lastSyncDate).TotalDays)
            }
            else { 
                "Unknown" 
            }
            
            [PSCustomObject]@{
                DeviceName        = $_.deviceName
                SerialNumber      = $_.serialNumber
                OperatingSystem   = $_.operatingSystem
                Model             = $_.model
                OwnershipType     = $_.managedDeviceOwnerType
                IntuneLastContact = $lastSyncDate
                DaysSinceLastSync = $diffDays
            }
        }

        # Sort by days since last sync (descending)
        $formattedDevices = $formattedDevices | Sort-Object -Property DaysSinceLastSync -Descending

        Write-Host "Successfully processed $($formattedDevices.Count) stale devices" -ForegroundColor Yellow
        return $formattedDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

# Execute the playbook and return results
$results = Get-StaleDevices -StaleDays $StaleDays
if ($results) {
    # Display results in console for debugging
    $results | Format-Table -AutoSize
}

# Return results to be displayed in UI
return $results