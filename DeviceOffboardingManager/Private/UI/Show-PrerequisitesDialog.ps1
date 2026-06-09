function Show-PrerequisitesDialog {
    try {
        $reader = (New-Object System.Xml.XmlNodeReader $prerequisitesModalXaml)
        $prereqWindow = [Windows.Markup.XamlReader]::Load($reader)

        if ($null -eq $prereqWindow) {
            throw "Failed to create prerequisites window. XamlReader returned null."
        }
    }
    catch {
        Write-Log "Error creating prerequisites window: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to create the prerequisites dialog. Error: $_",
            "Dialog Creation Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return
    }

    # Get controls
    $permissionsPanel = $prereqWindow.FindName('PermissionsPanel')
    $modulePanel = $prereqWindow.FindName('ModulePanel')
    $closeButton = $prereqWindow.FindName('ClosePrereqButton')

    # Add required permissions with checkboxes
    $requiredPermissions = @(
        @{
            Name        = "Device.ReadWrite.All"
            Description = "Read and delete device objects from Entra ID"
        },
        @{
            Name        = "DeviceManagementApps.Read.All"
            Description = "Read mobile app management policies and configurations"
        },
        @{
            Name        = "DeviceManagementConfiguration.Read.All"
            Description = "Read device configuration policies and assignments"
        },
        @{
            Name        = "DeviceManagementManagedDevices.ReadWrite.All"
            Description = "Read and modify managed device information and compliance policies"
        },
        @{
            Name        = "DeviceManagementServiceConfig.ReadWrite.All"
            Description = "Read and modify Autopilot deployment profiles"
        },
        @{
            Name        = "Group.Read.All"
            Description = "Read group information and memberships"
        },
        @{
            Name        = "User.Read.All"
            Description = "Read user profile information and check group memberships"
        },
        @{
            Name        = "BitlockerKey.Read.All"
            Description = "Read BitLocker recovery keys for Windows devices"
        }
    )

    $context = Get-MgContext
    $currentPermissions = if ($context) { $context.Scopes } else { @() }

    foreach ($permission in $requiredPermissions) {
        $permItem = New-Object System.Windows.Controls.StackPanel
        $permItem.Style = $prereqWindow.FindResource("CheckItemStyle")
        $permItem.Orientation = "Horizontal"

        $checkbox = New-Object System.Windows.Controls.CheckBox
        $checkbox.IsEnabled = $false
        $checkbox.VerticalAlignment = "Center"
        $checkbox.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)

        if ($currentPermissions -contains $permission.Name -or
            $currentPermissions -contains $permission.Name.Replace(".Read", ".ReadWrite")) {
            $checkbox.IsChecked = $true
            $checkbox.Foreground = "#28A745"
        }
        else {
            $checkbox.IsChecked = $false
            $checkbox.Foreground = "#DC3545"
        }

        # Create a StackPanel for permission text and description
        $textPanel = New-Object System.Windows.Controls.StackPanel
        $textPanel.Orientation = "Vertical"
        $textPanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)

        # Permission name
        $permText = New-Object System.Windows.Controls.TextBlock
        $permText.Text = $permission.Name
        $permText.Style = $prereqWindow.FindResource("CheckTextStyle")
        $permText.FontWeight = "SemiBold"

        # Permission description
        $descText = New-Object System.Windows.Controls.TextBlock
        $descText.Text = $permission.Description
        $descText.Style = $prereqWindow.FindResource("CheckTextStyle")
        $descText.Foreground = "#666666"
        $descText.FontSize = 12
        $descText.TextWrapping = "Wrap"
        $descText.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)

        $textPanel.Children.Add($permText)
        $textPanel.Children.Add($descText)

        $permItem.Children.Add($checkbox)
        $permItem.Children.Add($textPanel)
        $permissionsPanel.Children.Add($permItem)
    }

    # Add module check
    $moduleItem = New-Object System.Windows.Controls.StackPanel
    $moduleItem.Style = $prereqWindow.FindResource("CheckItemStyle")
    $moduleItem.Orientation = "Horizontal"

    $moduleCheckbox = New-Object System.Windows.Controls.CheckBox
    $moduleCheckbox.IsEnabled = $false
    $moduleCheckbox.VerticalAlignment = "Center"
    $moduleCheckbox.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)

    # Create a StackPanel for module text and description
    $textPanel = New-Object System.Windows.Controls.StackPanel
    $textPanel.Orientation = "Vertical"
    $textPanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)

    # Module name
    $moduleText = New-Object System.Windows.Controls.TextBlock
    $moduleText.Text = "Microsoft.Graph.Authentication"
    $moduleText.Style = $prereqWindow.FindResource("CheckTextStyle")
    $moduleText.FontWeight = "SemiBold"

    # Module description
    $descText = New-Object System.Windows.Controls.TextBlock
    $descText.Text = "Required for Microsoft Graph API authentication and operations"
    $descText.Style = $prereqWindow.FindResource("CheckTextStyle")
    $descText.Foreground = "#666666"
    $descText.FontSize = 12
    $descText.TextWrapping = "Wrap"
    $descText.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)

    $textPanel.Children.Add($moduleText)
    $textPanel.Children.Add($descText)

    $installButton = New-Object System.Windows.Controls.Button
    $installButton.Content = "Install"
    $installButton.Style = $prereqWindow.FindResource("InstallButtonStyle")
    $installButton.Visibility = "Collapsed"
    $installButton.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)

    if (Get-Module -ListAvailable -Name "Microsoft.Graph.Authentication") {
        $moduleCheckbox.IsChecked = $true
        $moduleCheckbox.Foreground = "#28A745"
    }
    else {
        $moduleCheckbox.IsChecked = $false
        $moduleCheckbox.Foreground = "#DC3545"
        $installButton.Visibility = "Visible"
    }

    $moduleItem.Children.Add($moduleCheckbox)
    $moduleItem.Children.Add($textPanel)
    $moduleItem.Children.Add($installButton)
    $modulePanel.Children.Add($moduleItem)

    # Add install button click handler
    $installButton.Add_Click({
            try {
                $installButton.IsEnabled = $false
                $installButton.Content = "Installing..."

                Install-Module "Microsoft.Graph.Authentication" -Scope CurrentUser -Force

                $moduleCheckbox.IsChecked = $true
                $moduleCheckbox.Foreground = "#28A745"
                $installButton.Visibility = "Collapsed"

                # Restart required message
                [System.Windows.MessageBox]::Show(
                    "Module installed successfully. Please restart the application for changes to take effect.",
                    "Installation Complete",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )
            }
            catch {
                Write-Log "Error installing module: $_"
                [System.Windows.MessageBox]::Show(
                    "Failed to install module. Please ensure you have internet connection and necessary permissions.",
                    "Installation Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
                $installButton.IsEnabled = $true
                $installButton.Content = "Install"
            }
        })

    # Optional Defender for Endpoint integration toggle
    $defenderSettingsItem = New-Object System.Windows.Controls.StackPanel
    $defenderSettingsItem.Style = $prereqWindow.FindResource("CheckItemStyle")
    $defenderSettingsItem.Orientation = "Horizontal"

    $defenderToggle = New-Object System.Windows.Controls.CheckBox
    $defenderToggle.VerticalAlignment = "Center"
    $defenderToggle.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $defenderToggle.IsChecked = Get-DefenderIntegrationEnabled

    $defenderTextPanel = New-Object System.Windows.Controls.StackPanel
    $defenderTextPanel.Orientation = "Vertical"
    $defenderTextPanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)

    $defenderTitle = New-Object System.Windows.Controls.TextBlock
    $defenderTitle.Text = "Enable Defender for Endpoint integration"
    $defenderTitle.Style = $prereqWindow.FindResource("CheckTextStyle")
    $defenderTitle.FontWeight = "SemiBold"

    $defenderDescription = New-Object System.Windows.Controls.TextBlock
    $defenderDescription.Text = "Optional. When enabled, Defender appears as an offboarding target and requests a separate Defender API token only when selected. Requires WindowsDefenderATP permissions: Machine.ReadWrite.All and Machine.Offboard."
    $defenderDescription.Style = $prereqWindow.FindResource("CheckTextStyle")
    $defenderDescription.Foreground = "#666666"
    $defenderDescription.FontSize = 12
    $defenderDescription.TextWrapping = "Wrap"
    $defenderDescription.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)

    $defenderTextPanel.Children.Add($defenderTitle)
    $defenderTextPanel.Children.Add($defenderDescription)
    $defenderSettingsItem.Children.Add($defenderToggle)
    $defenderSettingsItem.Children.Add($defenderTextPanel)
    $modulePanel.Children.Add($defenderSettingsItem)

    # Optional MSAL.PS module check for Defender token acquisition
    $msalItem = New-Object System.Windows.Controls.StackPanel
    $msalItem.Style = $prereqWindow.FindResource("CheckItemStyle")
    $msalItem.Orientation = "Horizontal"

    $msalCheckbox = New-Object System.Windows.Controls.CheckBox
    $msalCheckbox.IsEnabled = $false
    $msalCheckbox.VerticalAlignment = "Center"
    $msalCheckbox.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)

    $msalTextPanel = New-Object System.Windows.Controls.StackPanel
    $msalTextPanel.Orientation = "Vertical"
    $msalTextPanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)

    $msalText = New-Object System.Windows.Controls.TextBlock
    $msalText.Text = "MSAL.PS"
    $msalText.Style = $prereqWindow.FindResource("CheckTextStyle")
    $msalText.FontWeight = "SemiBold"

    $msalDesc = New-Object System.Windows.Controls.TextBlock
    $msalDesc.Text = "Optional module used only for Defender for Endpoint token acquisition."
    $msalDesc.Style = $prereqWindow.FindResource("CheckTextStyle")
    $msalDesc.Foreground = "#666666"
    $msalDesc.FontSize = 12
    $msalDesc.TextWrapping = "Wrap"
    $msalDesc.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)

    $msalTextPanel.Children.Add($msalText)
    $msalTextPanel.Children.Add($msalDesc)

    $installMsalButton = New-Object System.Windows.Controls.Button
    $installMsalButton.Content = "Install"
    $installMsalButton.Style = $prereqWindow.FindResource("InstallButtonStyle")
    $installMsalButton.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)

    if (Get-Module -ListAvailable -Name "MSAL.PS") {
        $msalCheckbox.IsChecked = $true
        $msalCheckbox.Foreground = "#28A745"
        $installMsalButton.Visibility = "Collapsed"
    }
    else {
        $msalCheckbox.IsChecked = $false
        $msalCheckbox.Foreground = "#DC3545"
        $installMsalButton.Visibility = if (Get-DefenderIntegrationEnabled) { "Visible" } else { "Collapsed" }
    }

    $msalItem.Children.Add($msalCheckbox)
    $msalItem.Children.Add($msalTextPanel)
    $msalItem.Children.Add($installMsalButton)
    $modulePanel.Children.Add($msalItem)

    $defenderToggle.Add_Checked({
            Set-DefenderIntegrationEnabled -Enabled $true
            if (-not (Get-Module -ListAvailable -Name "MSAL.PS")) {
                $installMsalButton.Visibility = "Visible"
            }
        })

    $defenderToggle.Add_Unchecked({
            Set-DefenderIntegrationEnabled -Enabled $false
            if (-not (Get-Module -ListAvailable -Name "MSAL.PS")) {
                $installMsalButton.Visibility = "Collapsed"
            }
        })

    $installMsalButton.Add_Click({
            try {
                $installMsalButton.IsEnabled = $false
                $installMsalButton.Content = "Installing..."

                Install-Module "MSAL.PS" -Scope CurrentUser -Force

                $msalCheckbox.IsChecked = $true
                $msalCheckbox.Foreground = "#28A745"
                $installMsalButton.Visibility = "Collapsed"

                [System.Windows.MessageBox]::Show(
                    "MSAL.PS installed successfully. Please restart the application for changes to take effect.",
                    "Installation Complete",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )
            }
            catch {
                Write-Log "Error installing MSAL.PS module: $_"
                [System.Windows.MessageBox]::Show(
                    "Failed to install MSAL.PS. Please ensure you have internet connection and necessary permissions.",
                    "Installation Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
                $installMsalButton.IsEnabled = $true
                $installMsalButton.Content = "Install"
            }
        })

    # Add close button handler
    $closeButton.Add_Click({
            $prereqWindow.Close()
        })

    # Show dialog
    try {
        if ($null -eq $prereqWindow) {
            throw "Prerequisites window is null. Cannot show dialog."
        }
        $prereqWindow.ShowDialog()
    }
    catch {
        Write-Log "Error showing prerequisites dialog: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to show the prerequisites dialog. Error: $_",
            "Dialog Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}
