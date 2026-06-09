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
        $resourceScopes = @(
            "https://api.securitycenter.microsoft.com/.default",
            "https://api.security.microsoft.com/.default"
        )

        foreach ($scopes in $resourceScopes) {
            try {
                $mdeToken = (Get-MsalToken -ClientId $context.ClientId -TenantId $context.TenantId -Scopes @($scopes) -Silent -ErrorAction Stop).AccessToken
                Write-Log "Acquired Defender for Endpoint token silently for resource $scopes"
                return $mdeToken
            } catch {
                Write-Log "Silent Defender token acquisition failed for $scopes`: $_" -Severity "WARN"
            }

            try {
                $mdeToken = (Get-MsalToken -ClientId $context.ClientId -TenantId $context.TenantId -Scopes @($scopes) -Interactive -ErrorAction Stop).AccessToken
                Write-Log "Acquired Defender for Endpoint token interactively for resource $scopes"
                return $mdeToken
            } catch {
                Write-Log "Interactive Defender token acquisition failed for $scopes`: $_" -Severity "WARN"
            }
        }

        Write-Log "Could not acquire Defender for Endpoint token. Ensure WindowsDefenderATP Machine.ReadWrite.All and Machine.Offboard permissions are consented." -Severity "ERROR"
        return $null
    } catch {
        Write-Log "Error acquiring MDE access token: $_" -Severity "ERROR"
        return $null
    }
}
