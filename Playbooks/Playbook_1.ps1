# Playbook: List all devices that are in Autopilot but not in Intune
# This script identifies devices that are registered in Windows Autopilot but not present in Intune management

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
                AutopilotLastContact = ConvertTo-SafeDateTime -dateString $_.lastContactDateTime
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
