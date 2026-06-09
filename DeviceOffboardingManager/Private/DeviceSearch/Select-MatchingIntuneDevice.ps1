function Select-MatchingIntuneDevice {
    param(
        [Parameter(Mandatory = $false)]
        $AADDevice,
        [Parameter(Mandatory = $false)]
        $IntuneDevices,
        [Parameter(Mandatory = $false)]
        [string]$SerialNumber,
        [Parameter(Mandatory = $false)]
        [string]$DeviceName
    )

    if (-not $IntuneDevices) {
        return $null
    }

    if ($AADDevice -and $AADDevice.deviceId) {
        $byAzureAdDeviceId = Select-UniqueDeviceByProperty -Devices $IntuneDevices -PropertyName "azureADDeviceId" -ExpectedValue $AADDevice.deviceId -MatchDescription "Intune azureADDeviceId"
        if ($byAzureAdDeviceId) {
            return $byAzureAdDeviceId
        }
    }

    if ($SerialNumber) {
        $bySerial = Select-UniqueDeviceByProperty -Devices $IntuneDevices -PropertyName "serialNumber" -ExpectedValue $SerialNumber -MatchDescription "Intune serial number"
        if ($bySerial) {
            return $bySerial
        }
    }

    if ($DeviceName) {
        $byName = @($IntuneDevices | Where-Object { Test-SameIdentifier -Left $_.deviceName -Right $DeviceName })
        if ($byName.Count -eq 1) {
            return $byName[0]
        }
        elseif ($byName.Count -gt 1) {
            Write-Log "Multiple Intune devices matched name '$DeviceName'. Skipping name-only correlation to prevent wrong-device operations." -Severity "WARN"
        }
    }

    return $null
}
