function Get-AutopilotDeviceBySerial {
    param(
        [Parameter(Mandatory = $false)]
        [string]$SerialNumber
    )

    if ([string]::IsNullOrWhiteSpace($SerialNumber)) {
        return $null
    }

    $escapedSerial = ConvertTo-ODataStringValue -Value $SerialNumber.Trim()
    $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$escapedSerial')"
    $candidateDevices = @(Get-GraphPagedResults -Uri $uri)
    return Select-MatchingAutopilotDevice -AutopilotDevices $candidateDevices -SerialNumber $SerialNumber
}
