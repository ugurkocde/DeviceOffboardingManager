function Show-AuthenticationDialog {
    try {
        $reader = (New-Object System.Xml.XmlNodeReader $authModalXaml)
        $authWindow = [Windows.Markup.XamlReader]::Load($reader)

        if ($null -eq $authWindow) {
            throw "Failed to create authentication window. XamlReader returned null."
        }
    }
    catch {
        Write-Log "Error creating authentication window: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to create the authentication dialog. Error: $_",
            "Dialog Creation Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return $null
    }

    # Get controls
    $interactiveAuth = $authWindow.FindName('InteractiveAuth')
    $deviceCodeAuth = $authWindow.FindName('DeviceCodeAuth')
    $certificateAuth = $authWindow.FindName('CertificateAuth')
    $secretAuth = $authWindow.FindName('SecretAuth')
    $certificateInputs = $authWindow.FindName('CertificateInputs')
    $secretInputs = $authWindow.FindName('SecretInputs')
    $connectButton = $authWindow.FindName('ConnectButton')
    $cancelAuthButton = $authWindow.FindName('CancelAuthButton')
    $importCertButton = $authWindow.FindName('ImportCertButton')
    $importSecretButton = $authWindow.FindName('ImportSecretButton')
    $saveCertButton = $authWindow.FindName('SaveCertButton')
    $saveSecretButton = $authWindow.FindName('SaveSecretButton')

    # Auto-load saved config if available
    $certConfigPath = [System.IO.Path]::Combine($script:ConfigDirectory, "cert_config.json")
    $secretConfigPath = [System.IO.Path]::Combine($script:ConfigDirectory, "secret_config.json")
    if (Test-Path $certConfigPath) {
        try {
            $savedCert = Get-Content $certConfigPath -Raw | ConvertFrom-Json
            if ($savedCert.AppId) { $authWindow.FindName('CertAppId').Text = $savedCert.AppId }
            if ($savedCert.TenantId) { $authWindow.FindName('CertTenantId').Text = $savedCert.TenantId }
            if ($savedCert.Thumbprint) { $authWindow.FindName('CertThumbprint').Text = $savedCert.Thumbprint }
        }
        catch { }
    }
    if (Test-Path $secretConfigPath) {
        try {
            $savedSecret = Get-Content $secretConfigPath -Raw | ConvertFrom-Json
            if ($savedSecret.AppId) { $authWindow.FindName('SecretAppId').Text = $savedSecret.AppId }
            if ($savedSecret.TenantId) { $authWindow.FindName('SecretTenantId').Text = $savedSecret.TenantId }
        }
        catch { }
    }

    # Add event handlers for radio buttons
    $certificateAuth.Add_Checked({
            $certificateInputs.Visibility = 'Visible'
            $secretInputs.Visibility = 'Collapsed'
        })

    $secretAuth.Add_Checked({
            $secretInputs.Visibility = 'Visible'
            $certificateInputs.Visibility = 'Collapsed'
        })

    $interactiveAuth.Add_Checked({
            $certificateInputs.Visibility = 'Collapsed'
            $secretInputs.Visibility = 'Collapsed'
        })

    $deviceCodeAuth.Add_Checked({
            $certificateInputs.Visibility = 'Collapsed'
            $secretInputs.Visibility = 'Collapsed'
        })

    # Auto-select auth method if saved config exists
    if (Test-Path $certConfigPath) {
        $certificateAuth.IsChecked = $true
    } elseif (Test-Path $secretConfigPath) {
        $secretAuth.IsChecked = $true
    }

    # Add import button handlers
    $importCertButton.Add_Click({
            $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $OpenFileDialog.Filter = "JSON files (*.json)|*.json"
            $OpenFileDialog.Title = "Import Certificate Configuration"

            if ($OpenFileDialog.ShowDialog() -eq 'OK') {
                try {
                    $config = Get-Content $OpenFileDialog.FileName | ConvertFrom-Json

                    if ($config.AppId -and $config.TenantId -and $config.Thumbprint) {
                        $authWindow.FindName('CertAppId').Text = $config.AppId
                        $authWindow.FindName('CertTenantId').Text = $config.TenantId
                        $authWindow.FindName('CertThumbprint').Text = $config.Thumbprint
                    }
                    else {
                        [System.Windows.MessageBox]::Show(
                            "Invalid configuration file. Please ensure it contains AppId, TenantId, and Thumbprint.",
                            "Invalid Configuration",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Warning
                        )
                    }
                }
                catch {
                    [System.Windows.MessageBox]::Show(
                        "Error reading configuration file: $_",
                        "Error",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Error
                    )
                }
            }
        })

    $importSecretButton.Add_Click({
            $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $OpenFileDialog.Filter = "JSON files (*.json)|*.json"
            $OpenFileDialog.Title = "Import Secret Configuration"

            if ($OpenFileDialog.ShowDialog() -eq 'OK') {
                try {
                    $config = Get-Content $OpenFileDialog.FileName | ConvertFrom-Json

                    if ($config.AppId -and $config.TenantId -and $config.ClientSecret) {
                        $authWindow.FindName('SecretAppId').Text = $config.AppId
                        $authWindow.FindName('SecretTenantId').Text = $config.TenantId
                        $authWindow.FindName('ClientSecret').Password = $config.ClientSecret
                    }
                    else {
                        [System.Windows.MessageBox]::Show(
                            "Invalid configuration file. Please ensure it contains AppId, TenantId, and ClientSecret.",
                            "Invalid Configuration",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Warning
                        )
                    }
                }
                catch {
                    [System.Windows.MessageBox]::Show(
                        "Error reading configuration file: $_",
                        "Error",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Error
                    )
                }
            }
        })

    # Save config button handlers
    $saveCertButton.Add_Click({
            $appId = $authWindow.FindName('CertAppId').Text
            $tenantId = $authWindow.FindName('CertTenantId').Text
            $thumbprint = $authWindow.FindName('CertThumbprint').Text
            if ([string]::IsNullOrWhiteSpace($appId) -or [string]::IsNullOrWhiteSpace($tenantId) -or [string]::IsNullOrWhiteSpace($thumbprint)) {
                [System.Windows.MessageBox]::Show(
                    "Please fill in App ID, Tenant ID, and Thumbprint before saving.",
                    "Validation Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                )
                return
            }
            try {
                $config = @{ AppId = $appId; TenantId = $tenantId; Thumbprint = $thumbprint }
                $configPath = [System.IO.Path]::Combine($script:ConfigDirectory, "cert_config.json")
                $config | ConvertTo-Json | Set-Content -Path $configPath -Force
                [System.Windows.MessageBox]::Show(
                    "Certificate configuration saved. It will be auto-loaded next time you open the authentication dialog.",
                    "Configuration Saved",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )
            }
            catch {
                [System.Windows.MessageBox]::Show(
                    "Error saving configuration: $_",
                    "Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            }
        })

    $saveSecretButton.Add_Click({
            $appId = $authWindow.FindName('SecretAppId').Text
            $tenantId = $authWindow.FindName('SecretTenantId').Text
            if ([string]::IsNullOrWhiteSpace($appId) -or [string]::IsNullOrWhiteSpace($tenantId)) {
                [System.Windows.MessageBox]::Show(
                    "Please fill in App ID and Tenant ID before saving.",
                    "Validation Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                )
                return
            }
            try {
                $config = @{ AppId = $appId; TenantId = $tenantId }
                $configPath = [System.IO.Path]::Combine($script:ConfigDirectory, "secret_config.json")
                $config | ConvertTo-Json | Set-Content -Path $configPath -Force
                [System.Windows.MessageBox]::Show(
                    "Configuration saved (App ID and Tenant ID only). The client secret is not persisted for security reasons and must be entered each session.",
                    "Configuration Saved",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )
            }
            catch {
                [System.Windows.MessageBox]::Show(
                    "Error saving configuration: $_",
                    "Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            }
        })

    # Add event handlers for buttons
    $cancelAuthButton.Add_Click({
            $script:authCancelled = $true
            $authWindow.DialogResult = $false
            $authWindow.Close()
        })

    $connectButton.Add_Click({
            # Validate fields based on selected authentication method
            if ($certificateAuth.IsChecked) {
                if ([string]::IsNullOrWhiteSpace($authWindow.FindName('CertAppId').Text) -or
                    [string]::IsNullOrWhiteSpace($authWindow.FindName('CertTenantId').Text) -or
                    [string]::IsNullOrWhiteSpace($authWindow.FindName('CertThumbprint').Text)) {
                    [System.Windows.MessageBox]::Show(
                        "Please fill in all required fields for certificate authentication.",
                        "Validation Error",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    )
                    return
                }
            }
            elseif ($secretAuth.IsChecked) {
                if ([string]::IsNullOrWhiteSpace($authWindow.FindName('SecretAppId').Text) -or
                    [string]::IsNullOrWhiteSpace($authWindow.FindName('SecretTenantId').Text) -or
                    [string]::IsNullOrWhiteSpace($authWindow.FindName('ClientSecret').Password)) {
                    [System.Windows.MessageBox]::Show(
                        "Please fill in all required fields for client secret authentication.",
                        "Validation Error",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    )
                    return
                }
            }

            $script:authCancelled = $false
            $authWindow.DialogResult = $true
            $authWindow.Close()
        })

    # Show dialog and return result
    try {
        if ($null -eq $authWindow) {
            throw "Authentication window is null. Cannot show dialog."
        }
        $result = $authWindow.ShowDialog()
    }
    catch {
        Write-Log "Error showing authentication dialog: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to show the authentication dialog. Error: $_",
            "Dialog Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return $null
    }

    if ($result) {
        # Return authentication details based on selected method
        if ($interactiveAuth.IsChecked) {
            return @{
                Method = 'Interactive'
            }
        }
        elseif ($deviceCodeAuth.IsChecked) {
            return @{
                Method = 'DeviceCode'
            }
        }
        elseif ($certificateAuth.IsChecked) {
            return @{
                Method     = 'Certificate'
                AppId      = $authWindow.FindName('CertAppId').Text
                TenantId   = $authWindow.FindName('CertTenantId').Text
                Thumbprint = $authWindow.FindName('CertThumbprint').Text
            }
        }
        else {
            return @{
                Method   = 'Secret'
                AppId    = $authWindow.FindName('SecretAppId').Text
                TenantId = $authWindow.FindName('SecretTenantId').Text
                Secret   = $authWindow.FindName('ClientSecret').Password
            }
        }
    }
    return $null
}
