# Playbook: BitLocker Key Report
# This script retrieves BitLocker recovery key metadata for all Windows devices

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-BitLockerKeyReport {
    try {
        # Get all BitLocker recovery keys (metadata only, not actual key values)
        Write-Host "Fetching BitLocker recovery key metadata..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys?`$select=id,createdDateTime,deviceId,volumeType"
        $recoveryKeys = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($recoveryKeys.Count) BitLocker recovery keys" -ForegroundColor Green

        if ($recoveryKeys.Count -eq 0) {
            Write-Host "No BitLocker recovery keys found" -ForegroundColor Yellow
            return @([PSCustomObject]@{
                DeviceName      = "No keys found"
                SerialNumber    = "N/A"
                KeyId           = "N/A"
                VolumeType      = "N/A"
                CreatedDateTime = $null
            })
        }

        # Get unique device IDs and resolve device names
        $deviceIds = $recoveryKeys | Select-Object -ExpandProperty deviceId -Unique | Where-Object { $_ }
        Write-Host "Resolving device names for $($deviceIds.Count) devices..." -ForegroundColor Cyan

        $deviceInfoMap = @{}
        foreach ($deviceId in $deviceIds) {
            try {
                # Get device name from Entra
                $uri = "https://graph.microsoft.com/beta/devices?`$filter=deviceId eq '$deviceId'&`$select=displayName"
                $device = (Get-GraphPagedResults -Uri $uri) | Select-Object -First 1
                $devName = if ($device) { $device.displayName } else { "Unknown Device" }

                # Get serial number from Intune via azureADDeviceId
                $serialNumber = "N/A"
                try {
                    $intuneUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=azureADDeviceId eq '$deviceId'&`$select=serialNumber"
                    $intuneDevice = (Get-GraphPagedResults -Uri $intuneUri) | Select-Object -First 1
                    if ($intuneDevice -and $intuneDevice.serialNumber) {
                        $serialNumber = $intuneDevice.serialNumber
                    }
                } catch {}

                $deviceInfoMap[$deviceId] = @{ Name = $devName; Serial = $serialNumber }
            }
            catch {
                continue
            }
        }

        $formattedKeys = $recoveryKeys | ForEach-Object {
            $info = if ($_.deviceId -and $deviceInfoMap.ContainsKey($_.deviceId)) {
                $deviceInfoMap[$_.deviceId]
            } else { @{ Name = "Unknown Device"; Serial = "N/A" } }

            [PSCustomObject]@{
                DeviceName      = $info.Name
                SerialNumber    = $info.Serial
                KeyId           = $_.id
                VolumeType      = $_.volumeType
                CreatedDateTime = ConvertTo-SafeDateTime -dateString $_.createdDateTime
            }
        }

        Write-Host "Successfully processed $($formattedKeys.Count) BitLocker keys" -ForegroundColor Yellow
        return $formattedKeys
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

$results = Get-BitLockerKeyReport
if ($results) {
    $results | Format-Table -AutoSize
}

return $results
