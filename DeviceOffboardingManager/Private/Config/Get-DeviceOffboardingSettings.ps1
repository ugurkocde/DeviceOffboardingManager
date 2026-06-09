function Get-DeviceOffboardingSettings {
    $defaults = [ordered]@{
        DefenderIntegrationEnabled = $false
    }

    if (-not $script:ConfigDirectory) {
        return [pscustomobject]$defaults
    }

    $settingsPath = [System.IO.Path]::Combine($script:ConfigDirectory, "settings.json")
    if (-not (Test-Path $settingsPath)) {
        return [pscustomobject]$defaults
    }

    try {
        $savedSettings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
        foreach ($key in @($defaults.Keys)) {
            if ($savedSettings.PSObject.Properties.Name -contains $key) {
                $defaults[$key] = $savedSettings.$key
            }
        }
    }
    catch {
        Write-Log "Error reading settings file: $_" -Severity "WARN"
    }

    return [pscustomobject]$defaults
}
