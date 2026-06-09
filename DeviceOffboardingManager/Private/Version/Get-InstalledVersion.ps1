function Get-InstalledVersion {
    try {
        $module = $null
        if (Get-Command -Name Get-InstalledPSResource -ErrorAction SilentlyContinue) {
            $module = Get-InstalledPSResource -Name DeviceOffboardingManager -Type Module -ErrorAction SilentlyContinue |
                Sort-Object Version -Descending |
                Select-Object -First 1
        }

        if (-not $module) {
            $module = Get-Module -ListAvailable -Name DeviceOffboardingManager |
                Sort-Object Version -Descending |
                Select-Object -First 1
        }

        if ($module) {
            return $module.Version.ToString()
        }

        return Get-ScriptVersion
    }
    catch {
        Write-Log "Error getting installed version: $_"
        return "Unknown"
    }
}
