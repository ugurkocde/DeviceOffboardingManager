function Connect-ToGraph {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthDetails
    )

    try {
        Write-Log "Attempting to connect to Microsoft Graph using $($AuthDetails.Method) authentication..."
        $script:CurrentAuthDetails = $null

        # Get required permissions
        $permissionsList = ($script:requiredPermissions | ForEach-Object { $_.Permission })

        # Connect based on authentication method
        switch ($AuthDetails.Method) {
            'Interactive' {
                $connectionResult = Connect-MgGraph -Scopes $permissionsList -NoWelcome -ErrorAction Stop
                $script:CurrentAuthDetails = @{
                    Method = 'Interactive'
                }
            }
            'DeviceCode' {
                $connectionResult = Connect-MgGraph -Scopes $permissionsList -UseDeviceCode -NoWelcome -ErrorAction Stop
                $script:CurrentAuthDetails = @{
                    Method = 'DeviceCode'
                }
            }
            'Certificate' {
                # Validate certificate credentials before attempting connection
                if ([string]::IsNullOrWhiteSpace($AuthDetails.AppId)) {
                    throw "App ID is required for certificate authentication"
                }
                if ([string]::IsNullOrWhiteSpace($AuthDetails.TenantId)) {
                    throw "Tenant ID is required for certificate authentication"
                }
                if ([string]::IsNullOrWhiteSpace($AuthDetails.Thumbprint)) {
                    throw "Certificate Thumbprint is required for certificate authentication"
                }

                # Disconnect any existing connections first
                Disconnect-MgGraph -ErrorAction SilentlyContinue

                $connectionResult = Connect-MgGraph -ClientId $AuthDetails.AppId -TenantId $AuthDetails.TenantId -CertificateThumbprint $AuthDetails.Thumbprint -NoWelcome -ErrorAction Stop
                $script:CurrentAuthDetails = @{
                    Method     = 'Certificate'
                    AppId      = $AuthDetails.AppId
                    TenantId   = $AuthDetails.TenantId
                    Thumbprint = $AuthDetails.Thumbprint
                }
            }
            'Secret' {
                # Validate client secret credentials before attempting connection
                if ([string]::IsNullOrWhiteSpace($AuthDetails.AppId)) {
                    throw "App ID is required for client secret authentication"
                }
                if ([string]::IsNullOrWhiteSpace($AuthDetails.TenantId)) {
                    throw "Tenant ID is required for client secret authentication"
                }
                if ([string]::IsNullOrWhiteSpace($AuthDetails.Secret)) {
                    throw "Client Secret is required for client secret authentication"
                }

                $SecuredPasswordPassword = ConvertTo-SecureString -String $AuthDetails.Secret -AsPlainText -Force
                $ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AuthDetails.AppId, $SecuredPasswordPassword

                $connectionResult = Connect-MgGraph -TenantId $AuthDetails.TenantId -ClientSecretCredential $ClientSecretCredential -NoWelcome -ErrorAction Stop
                $script:CurrentAuthDetails = @{
                    Method             = 'Secret'
                    AppId              = $AuthDetails.AppId
                    TenantId           = $AuthDetails.TenantId
                    SecretSecureString = $SecuredPasswordPassword
                }

                # Clear sensitive credentials from memory
                $SecuredPasswordPassword = $null
                $ClientSecretCredential = $null
                $AuthDetails.Secret = $null
                $AuthDetails.Remove('Secret')
            }
            default {
                throw "Invalid authentication method specified"
            }
        }

        # Check permissions
        $context = Get-MgContext
        if (-not $context) {
            throw "Failed to get Microsoft Graph context after connection"
        }

        # Capture admin identity for audit logging
        if ($context.Account) {
            $script:AdminUPN = $context.Account
        } else {
            $script:AdminUPN = "AppId:$($context.ClientId)"
        }
        Write-Log "Authenticated as $($script:AdminUPN)" -Severity "AUDIT"

        # Get tenant details and update UI
        try {
            Write-Log "Retrieving tenant information..."
            $tenantInfo = Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/organization?`$select=displayName,id,verifiedDomains" -Method GET
            if ($tenantInfo.value) {
                $org = $tenantInfo.value[0]
                Write-Log "Found tenant: $($org.displayName)"

                # Update UI elements
                $Window.FindName('TenantDisplayName').Text = $org.displayName
                $Window.FindName('TenantId').Text = $org.id
                $Window.FindName('TenantDomain').Text = ($org.verifieddomains | Where-Object { $_.isDefault -eq $true }).name
                $Window.FindName('TenantInfoSection').Visibility = 'Visible'
            }
            else {
                Write-Log "Warning: No tenant information found in response"
            }
        }
        catch {
            Write-Log "Warning: Could not retrieve tenant details: $_"
            # Don't throw here, as the connection is still valid
        }

        $currentPermissions = $context.Scopes
        $missingPermissions = @()

        foreach ($permissionInfo in $script:requiredPermissions) {
            $permission = $permissionInfo.Permission
            if (-not ($currentPermissions -contains $permission -or
                    $currentPermissions -contains $permission.Replace(".Read", ".ReadWrite"))) {
                $missingPermissions += $permission
            }
        }

        if ($missingPermissions.Count -gt 0) {
            $missingList = $missingPermissions -join ", "
            Write-Log "Warning: Missing permissions: $missingList"
            Show-Toast -Message "Missing permissions: $missingList" -Type "info" -DurationSeconds 6
        }

        Write-Log "Successfully connected to Microsoft Graph"
        return $true
    }
    catch {
        Write-Log "Failed to connect to Microsoft Graph: $_"
        Show-Toast -Message "Failed to connect to Microsoft Graph: $_" -Type "error" -DurationSeconds 8

        # Reset UI state on connection failure
        $script:connectionFailed = $true  # Add this flag to track connection failure
        return $false
    }
}
