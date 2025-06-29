# Playbook: List all devices that are in Intune but not in Autopilot
# This script identifies devices that are managed in Intune but not registered in Windows Autopilot

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

function Get-IntuneNotAutopilotDevices {
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