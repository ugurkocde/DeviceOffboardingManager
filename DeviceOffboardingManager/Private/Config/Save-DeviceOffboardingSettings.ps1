function Save-DeviceOffboardingSettings {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Settings
    )

    if (-not $script:ConfigDirectory) {
        throw "Config directory is not initialized."
    }

    if (-not (Test-Path $script:ConfigDirectory)) {
        New-Item -Path $script:ConfigDirectory -ItemType Directory -Force | Out-Null
    }

    $settingsPath = [System.IO.Path]::Combine($script:ConfigDirectory, "settings.json")
    $Settings | ConvertTo-Json | Set-Content -Path $settingsPath -Force
    $script:DeviceOffboardingSettings = $Settings
}
