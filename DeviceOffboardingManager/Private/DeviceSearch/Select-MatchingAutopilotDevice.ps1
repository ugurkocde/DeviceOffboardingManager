function Select-MatchingAutopilotDevice {
    param(
        [Parameter(Mandatory = $false)]
        $AutopilotDevices,
        [Parameter(Mandatory = $false)]
        [string]$SerialNumber,
        [Parameter(Mandatory = $false)]
        [string]$DeviceName
    )

    if (-not $AutopilotDevices) {
        return $null
    }

    if ($SerialNumber) {
        $bySerial = Select-UniqueDeviceByProperty -Devices $AutopilotDevices -PropertyName "serialNumber" -ExpectedValue $SerialNumber -MatchDescription "Autopilot serial number"
        if ($bySerial) {
            return $bySerial
        }
    }

    if ($DeviceName) {
        $byName = @($AutopilotDevices | Where-Object { Test-SameIdentifier -Left $_.displayName -Right $DeviceName })
        if ($byName.Count -eq 1) {
            return $byName[0]
        }
        elseif ($byName.Count -gt 1) {
            Write-Log "Multiple Autopilot devices matched display name '$DeviceName'. Skipping name-only correlation to prevent wrong-device operations." -Severity "WARN"
        }
    }

    return $null
}
