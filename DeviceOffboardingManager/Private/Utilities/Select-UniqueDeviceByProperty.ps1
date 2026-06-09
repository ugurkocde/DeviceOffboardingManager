function Select-UniqueDeviceByProperty {
    param(
        [Parameter(Mandatory = $false)]
        $Devices,
        [Parameter(Mandatory = $true)]
        [string]$PropertyName,
        [Parameter(Mandatory = $false)]
        [string]$ExpectedValue,
        [Parameter(Mandatory = $false)]
        [string]$MatchDescription = $PropertyName
    )

    if (-not $Devices -or [string]::IsNullOrWhiteSpace($ExpectedValue)) {
        return $null
    }

    $matches = @($Devices | Where-Object { Test-SameIdentifier -Left $_.$PropertyName -Right $ExpectedValue })
    if ($matches.Count -eq 1) {
        return $matches[0]
    }

    if ($matches.Count -gt 1) {
        Write-Log "Multiple devices matched $MatchDescription '$ExpectedValue'. Skipping automatic correlation to prevent wrong-device operations." -Severity "WARN"
    }

    return $null
}
