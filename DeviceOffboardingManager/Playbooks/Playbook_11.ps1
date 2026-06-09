# Playbook: Corporate Identifier Stale Report
# This script lists imported corporate device identifiers and their last contact state.

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-CorporateIdentifierStaleReport {
    try {
        Write-Host "Fetching imported corporate device identifiers..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/importedDeviceIdentities?`$select=id,importedDeviceIdentifier,importedDeviceIdentityType,lastModifiedDateTime,createdDateTime,lastContactedDateTime,description,enrollmentState,platform"
        $identifiers = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($identifiers.Count) imported device identifiers" -ForegroundColor Green

        if ($identifiers.Count -eq 0) {
            Write-Host "No imported device identifiers found" -ForegroundColor Yellow
            return @([PSCustomObject]@{
                Identifier            = "No imported identifiers found"
                Type                  = "N/A"
                Platform              = "N/A"
                EnrollmentState       = "N/A"
                Description           = "N/A"
                CreatedDateTime       = $null
                LastModifiedDateTime  = $null
                LastContactedDateTime = $null
                DaysSinceLastContact  = $null
                ContactState          = "N/A"
            })
        }

        $now = Get-Date
        $formattedIdentifiers = $identifiers | ForEach-Object {
            $lastContact = ConvertTo-SafeDateTime -dateString $_.lastContactedDateTime
            $daysSinceLastContact = if ($lastContact) { [Math]::Round(($now - $lastContact).TotalDays, 1) } else { $null }
            $contactState = if (-not $lastContact) {
                "Never Contacted"
            }
            elseif ($daysSinceLastContact -ge 180) {
                "Stale 180+ Days"
            }
            elseif ($daysSinceLastContact -ge 90) {
                "Stale 90+ Days"
            }
            elseif ($daysSinceLastContact -ge 30) {
                "Stale 30+ Days"
            }
            else {
                "Recent"
            }

            [PSCustomObject]@{
                Identifier            = $_.importedDeviceIdentifier
                Type                  = $_.importedDeviceIdentityType
                Platform              = $_.platform
                EnrollmentState       = $_.enrollmentState
                Description           = $_.description
                CreatedDateTime       = ConvertTo-SafeDateTime -dateString $_.createdDateTime
                LastModifiedDateTime  = ConvertTo-SafeDateTime -dateString $_.lastModifiedDateTime
                LastContactedDateTime = $lastContact
                DaysSinceLastContact  = $daysSinceLastContact
                ContactState          = $contactState
            }
        }

        $formattedIdentifiers = $formattedIdentifiers | Sort-Object @{ Expression = { if ($null -eq $_.DaysSinceLastContact) { [double]::PositiveInfinity } else { $_.DaysSinceLastContact } }; Descending = $true }, Identifier
        Write-Host "Successfully processed $($formattedIdentifiers.Count) corporate identifiers" -ForegroundColor Yellow
        return $formattedIdentifiers
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

$results = Get-CorporateIdentifierStaleReport
if ($results) {
    $results | Format-Table -AutoSize
}

return $results
