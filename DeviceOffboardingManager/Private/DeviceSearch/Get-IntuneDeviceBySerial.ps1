function Get-IntuneDeviceBySerial {
    param(
        [Parameter(Mandatory = $false)]
        [string]$SerialNumber
    )

    if ([string]::IsNullOrWhiteSpace($SerialNumber)) {
        return $null
    }

    $escapedSerial = ConvertTo-ODataStringValue -Value $SerialNumber.Trim()
    $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=serialNumber eq '$escapedSerial'&`$select=id,deviceName,serialNumber,operatingSystem,userDisplayName,lastSyncDateTime,azureADDeviceId,complianceState,managementAgent"
    $candidateDevices = @(Get-GraphPagedResults -Uri $uri)
    return Select-UniqueDeviceByProperty -Devices $candidateDevices -PropertyName "serialNumber" -ExpectedValue $SerialNumber -MatchDescription "Intune serial number"
}
