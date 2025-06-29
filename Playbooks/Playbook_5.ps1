# Playbook: List all stale devices in Intune
# This script identifies devices that haven't checked in for a specified number of days

param(
    [int]$StaleDays = 30 # Default to 30 days if not specified
)

# Helper function to safely convert date strings to DateTime objects
function ConvertTo-SafeDateTime {
    param(
        [Parameter(Mandatory = $false)]
        [string]$dateString
    )
    
    if ([string]::IsNullOrWhiteSpace($dateString)) {
        return $null
    }
    
    # Define supported date formats
    $formats = @(
        "yyyy-MM-ddTHH:mm:ssZ",
        "yyyy-MM-ddTHH:mm:ss.fffffffZ",
        "yyyy-MM-ddTHH:mm:ss",
        "MM/dd/yyyy HH:mm:ss",
        "dd/MM/yyyy HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "M/d/yyyy h:mm:ss tt",
        "M/d/yyyy H:mm:ss"
    )
    
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    
    # Try each format
    foreach ($format in $formats) {
        try {
            $parsedDate = [DateTime]::ParseExact($dateString, $format, $culture, [System.Globalization.DateTimeStyles]::None)
            # Check for DateTime.MinValue (1/1/0001)
            if ($parsedDate -eq [DateTime]::MinValue) {
                return $null
            }
            return $parsedDate
        }
        catch {
            # Continue to next format
            continue
        }
    }
    
    # Try default parse as last resort with InvariantCulture
    try {
        $parsedDate = [DateTime]::Parse($dateString, $culture)
        if ($parsedDate -eq [DateTime]::MinValue) {
            return $null
        }
        return $parsedDate
    }
    catch {
        Write-Warning "Failed to parse date: $dateString"
        return $null
    }
}

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
            $lastSyncDate = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime
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