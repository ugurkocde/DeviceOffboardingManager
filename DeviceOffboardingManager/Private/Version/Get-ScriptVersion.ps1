function Get-ScriptVersion {
    try {
        if ($script:DeviceOffboardingManagerVersion) {
            return $script:DeviceOffboardingManagerVersion
        }

        $manifestPath = Join-Path $script:DeviceOffboardingManagerModuleRoot 'DeviceOffboardingManager.psd1'
        if (Test-Path $manifestPath) {
            return (Test-ModuleManifest -Path $manifestPath).Version.ToString()
        }

        return "Unknown"
    }
    catch {
        return "Unknown"
    }
}
