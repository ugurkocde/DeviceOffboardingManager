function Get-EntraDeviceForIntuneDevice {
    param(
        [Parameter(Mandatory = $false)]
        $IntuneDevice
    )

    if (-not $IntuneDevice) {
        return $null
    }

    if ($IntuneDevice.azureADDeviceId) {
        $escapedDeviceId = ConvertTo-ODataStringValue -Value $IntuneDevice.azureADDeviceId
        $uri = "https://graph.microsoft.com/beta/devices?`$filter=deviceId eq '$escapedDeviceId'&`$select=id,deviceId,displayName,operatingSystem,approximateLastSignInDateTime,accountEnabled,physicalIds"
        $entraDevices = @(Get-GraphPagedResults -Uri $uri)
        if ($entraDevices.Count -eq 1) {
            return $entraDevices[0]
        }
        elseif ($entraDevices.Count -gt 1) {
            Write-Log "Multiple Entra ID devices matched deviceId '$($IntuneDevice.azureADDeviceId)'. Skipping automatic correlation." -Severity "WARN"
            return $null
        }
    }

    if ($IntuneDevice.deviceName) {
        $escapedName = ConvertTo-ODataStringValue -Value $IntuneDevice.deviceName
        $uri = "https://graph.microsoft.com/beta/devices?`$filter=displayName eq '$escapedName'&`$select=id,deviceId,displayName,operatingSystem,approximateLastSignInDateTime,accountEnabled,physicalIds"
        $entraDevices = @(Get-GraphPagedResults -Uri $uri)
        if ($entraDevices.Count -eq 1) {
            return $entraDevices[0]
        }
        elseif ($entraDevices.Count -gt 1) {
            Write-Log "Multiple Entra ID devices matched name '$($IntuneDevice.deviceName)'. Skipping name-only correlation to prevent wrong-device operations." -Severity "WARN"
        }
    }

    return $null
}
