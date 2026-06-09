function Get-MdeAccessToken {
    try {
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

        if ($script:CurrentAuthDetails -and $script:CurrentAuthDetails.Method -eq 'Secret') {
            foreach ($scopes in $resourceScopes) {
                try {
                    $mdeToken = (Get-MsalToken `
                            -ClientId $script:CurrentAuthDetails.AppId `
                            -TenantId $script:CurrentAuthDetails.TenantId `
                            -ClientSecret $script:CurrentAuthDetails.SecretSecureString `
                            -Scopes @($scopes) `
                            -ErrorAction Stop).AccessToken

                    Write-Log "Acquired app-only Defender for Endpoint token with client secret for resource $scopes"
                    return $mdeToken
                } catch {
                    Write-Log "Client secret Defender token acquisition failed for $scopes`: $_" -Severity "WARN"
                }
            }
        }

        if ($script:CurrentAuthDetails -and $script:CurrentAuthDetails.Method -eq 'Certificate') {
            $thumbprint = ($script:CurrentAuthDetails.Thumbprint -replace '\s', '')
            $certificate = $null
            foreach ($certPath in @("Cert:\CurrentUser\My\$thumbprint", "Cert:\LocalMachine\My\$thumbprint")) {
                $certificate = Get-Item -Path $certPath -ErrorAction SilentlyContinue
                if ($certificate) {
                    break
                }
            }

            if (-not $certificate) {
                Write-Log "Could not find certificate with thumbprint $thumbprint for Defender token acquisition." -Severity "WARN"
            }
            else {
                foreach ($scopes in $resourceScopes) {
                    try {
                        $mdeToken = (Get-MsalToken `
                                -ClientId $script:CurrentAuthDetails.AppId `
                                -TenantId $script:CurrentAuthDetails.TenantId `
                                -ClientCertificate $certificate `
                                -Scopes @($scopes) `
                                -ErrorAction Stop).AccessToken

                        Write-Log "Acquired app-only Defender for Endpoint token with certificate for resource $scopes"
                        return $mdeToken
                    } catch {
                        Write-Log "Certificate Defender token acquisition failed for $scopes`: $_" -Severity "WARN"
                    }
                }
            }
        }

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

        Write-Log "Could not acquire Defender for Endpoint token. Ensure WindowsDefenderATP Machine.ReadWrite.All and Machine.Offboard permissions are consented for app-only auth, or Machine.ReadWrite and Machine.Offboard are consented for delegated auth." -Severity "ERROR"
        return $null
    } catch {
        Write-Log "Error acquiring MDE access token: $_" -Severity "ERROR"
        return $null
    }
}
