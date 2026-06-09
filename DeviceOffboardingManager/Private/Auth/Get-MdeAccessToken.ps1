function Get-MdeAccessToken {
    try {
        # Use the existing Graph connection context to get a token for the MDE resource
        $context = Get-MgContext
        if (-not $context) {
            Write-Log "No Graph context available for MDE token acquisition" -Severity "WARN"
            return $null
        }

        # Check if MSAL.PS module is available
        if (-not (Get-Module -ListAvailable -Name "MSAL.PS")) {
            Write-Log "MSAL.PS module not installed. MDE offboarding requires the MSAL.PS module. Install with: Install-Module MSAL.PS" -Severity "WARN"
            return $null
        }

        Import-Module MSAL.PS -ErrorAction Stop
        $scopes = @("https://api.security.microsoft.com/.default")

        # Try silent token acquisition first
        try {
            $mdeToken = (Get-MsalToken -ClientId $context.ClientId -TenantId $context.TenantId -Scopes $scopes -Silent -ErrorAction Stop).AccessToken
            return $mdeToken
        } catch {
            Write-Log "Silent MDE token acquisition failed, trying interactive: $_" -Severity "WARN"
        }
        # Fallback: try interactive token acquisition
        try {
            $mdeToken = (Get-MsalToken -ClientId $context.ClientId -TenantId $context.TenantId -Scopes $scopes -Interactive -ErrorAction Stop).AccessToken
            return $mdeToken
        } catch {
            Write-Log "Interactive MDE token acquisition failed: $_" -Severity "ERROR"
            return $null
        }
    } catch {
        Write-Log "Error acquiring MDE access token: $_" -Severity "ERROR"
        return $null
    }
}
