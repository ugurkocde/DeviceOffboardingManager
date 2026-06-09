function Get-DefenderIntegrationEnabled {
    if (-not $script:DeviceOffboardingSettings) {
        $script:DeviceOffboardingSettings = Get-DeviceOffboardingSettings
    }

    return [bool]$script:DeviceOffboardingSettings.DefenderIntegrationEnabled
}
