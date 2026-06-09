function Set-AutopilotGroupTagForDevices {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Devices,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$GroupTag
    )

    $updated = 0
    $failed = 0
    foreach ($device in $Devices) {
        try {
            if (-not $device.AutopilotIdentityId -and $device.SerialNumber) {
                $autopilotDevice = Get-AutopilotDeviceBySerial -SerialNumber $device.SerialNumber
                if ($autopilotDevice) {
                    $device.AutopilotIdentityId = $autopilotDevice.id
                }
            }

            if (-not $device.AutopilotIdentityId) {
                $failed++
                Write-Log "Cannot set Autopilot group tag for $($device.DeviceName): no Autopilot identity resolved" -Severity "WARN"
                continue
            }

            $body = @{ groupTag = $GroupTag } | ConvertTo-Json -Depth 3
            $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$($device.AutopilotIdentityId)/updateDeviceProperties"
            Invoke-GraphRequestWithRetry -Uri $uri -Method POST -Body $body -ContentType "application/json"
            $updated++
            Write-Log "Set Autopilot group tag for $($device.DeviceName) (AutopilotId: $($device.AutopilotIdentityId)) to '$GroupTag'" -Severity "AUDIT"
        }
        catch {
            $failed++
            Write-Log "Failed to set Autopilot group tag for $($device.DeviceName): $_" -Severity "ERROR"
        }
    }

    return @{
        Updated = $updated
        Failed  = $failed
    }
}
