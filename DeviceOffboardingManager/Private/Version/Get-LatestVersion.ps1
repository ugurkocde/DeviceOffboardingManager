function Get-LatestVersion {
    try {
        if (Get-Command -Name Find-PSResource -ErrorAction SilentlyContinue) {
            $resource = Find-PSResource -Name DeviceOffboardingManager -Type Module -ErrorAction Stop
            return $resource.Version.ToString()
        }

        if (Get-Command -Name Find-Module -ErrorAction SilentlyContinue) {
            $module = Find-Module -Name DeviceOffboardingManager -ErrorAction Stop
            return $module.Version.ToString()
        }

        return "Unknown"
    }
    catch {
        Write-Log "Error getting latest version: $_"
        return "Unknown"
    }
}
