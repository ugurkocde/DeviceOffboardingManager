# Playbook: List all corporate devices in Intune
# This script identifies all company-owned devices managed in Intune

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