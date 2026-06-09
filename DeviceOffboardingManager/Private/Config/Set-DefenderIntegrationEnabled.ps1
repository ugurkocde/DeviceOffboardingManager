function Set-DefenderIntegrationEnabled {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    $settings = Get-DeviceOffboardingSettings
    $settings.DefenderIntegrationEnabled = $Enabled
    Save-DeviceOffboardingSettings -Settings $settings

    Write-Log "Defender for Endpoint integration setting changed to: $Enabled" -Severity "AUDIT"
}
