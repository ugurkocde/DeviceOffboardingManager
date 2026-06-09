# Playbook: FileVault Key Report
# This script checks FileVault key availability for all macOS devices

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-FileVaultKeyReport {
    try {
        Write-Host "Fetching macOS devices from Intune..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=operatingSystem eq 'macOS'&`$select=id,deviceName,serialNumber,lastSyncDateTime"
        $macDevices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($macDevices.Count) macOS devices" -ForegroundColor Green

        if ($macDevices.Count -eq 0) {
            Write-Host "No macOS devices found" -ForegroundColor Yellow
            return @([PSCustomObject]@{
                DeviceName        = "No macOS devices found"
                SerialNumber      = "N/A"
                HasFileVaultKey   = "N/A"
                IntuneLastContact = $null
            })
        }

        Write-Host "Checking FileVault key availability for each device..." -ForegroundColor Cyan
        $formattedDevices = @()
        $counter = 0

        foreach ($device in $macDevices) {
            $counter++
            if ($counter % 10 -eq 0) {
                Write-Host "  Checked $counter of $($macDevices.Count) devices..." -ForegroundColor Gray
            }

            $hasKey = $false
            try {
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$($device.id)')/getFileVaultKey"
                $keyResponse = Invoke-MgGraphRequest -Uri $uri -Method GET
                if ($keyResponse.value) {
                    $hasKey = $true
                }
            }
            catch {
                # 404 or other error means no key available
                $hasKey = $false
            }

            $formattedDevices += [PSCustomObject]@{
                DeviceName        = $device.deviceName
                SerialNumber      = $device.serialNumber
                HasFileVaultKey   = if ($hasKey) { "Yes" } else { "No" }
                IntuneLastContact = ConvertTo-SafeDateTime -dateString $device.lastSyncDateTime
            }
        }

        Write-Host "Successfully processed $($formattedDevices.Count) macOS devices" -ForegroundColor Yellow
        return $formattedDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

$results = Get-FileVaultKeyReport
if ($results) {
    $results | Format-Table -AutoSize
}

return $results
