# Runtime UI setup and event wiring generated from the original script top-level statements.
$script:LogDirectory = [System.IO.Path]::Combine([Environment]::GetFolderPath("Desktop"), "DOM_Logs")

if (-not (Test-Path $script:LogDirectory)) { New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null }

$script:LogFilePath = [System.IO.Path]::Combine($script:LogDirectory, "DOM_$(Get-Date -Format 'yyyyMMdd_HHmmss').log")

$script:AdminUPN = $null
$script:CurrentAuthDetails = $null

$script:ConfigDirectory = [System.IO.Path]::Combine(
    [Environment]::GetFolderPath("LocalApplicationData"),
    "DeviceOffboardingManager")

if (-not (Test-Path $script:ConfigDirectory)) {
    New-Item -Path $script:ConfigDirectory -ItemType Directory -Force | Out-Null
}

$script:DeviceOffboardingSettings = Get-DeviceOffboardingSettings

try {
    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    $Window = [Windows.Markup.XamlReader]::Load($reader)

    if ($null -eq $Window) {
        throw "Failed to create main window. XamlReader returned null."
    }
}
catch {
    Write-Log "Error creating main window: $_"
    [System.Windows.MessageBox]::Show(
        "Failed to create the main application window. Error: $_",
        "Application Startup Error",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    )
    throw
}

$scriptVersion = Get-ScriptVersion

$Window.Title = "Device Offboarding Manager (Preview) - $scriptVersion"

$SearchButton = $Window.FindName("SearchButton")

$OffboardButton = $Window.FindName("OffboardButton")

$ExportSelectedButton = $Window.FindName("ExportSelectedButton")

$SetGroupTagButton = $Window.FindName("SetGroupTagButton")

$AuthenticateButton = $Window.FindName("AuthenticateButton")

$SearchInputText = $Window.FindName("SearchInputText")

$bulk_import_button = $Window.FindName('bulk_import_button')

$Dropdown = $Window.FindName("dropdown")

$Disconnect = $Window.FindName('disconnect_button')

$ToastNotification = $Window.FindName('ToastNotification')

$ToastMessage = $Window.FindName('ToastMessage')

$ToastDismissButton = $Window.FindName('ToastDismissButton')

$SidebarToggleButton = $Window.FindName('SidebarToggleButton')

$SidebarTopContent = $Window.FindName('SidebarTopContent')

$SidebarBottomContent = $Window.FindName('SidebarBottomContent')

$SidebarCenterContent = $Window.FindName('SidebarCenterContent')

$SidebarColumn = $Window.Content.ColumnDefinitions[0]

$CollapsedStatusDot = $Window.FindName('CollapsedStatusDot')

$script:SidebarCollapsed = $false

$script:ToastGeneration = 0

$ToastDismissButton.Add_Click({ Hide-Toast })

$SidebarToggleButton.Add_Click({
    Set-SidebarState -Collapsed (-not $script:SidebarCollapsed)
})

$logs_button = $Window.FindName('logs_button')

$PrerequisitesButton = $Window.FindName('PrerequisitesButton')

$FeedbackLink = $Window.FindName('FeedbackLink')

$FilterRow = $Window.FindName('FilterRow')

$FilterDeviceName = $Window.FindName('FilterDeviceName')

$FilterSerialNumber = $Window.FindName('FilterSerialNumber')

$FilterOS = $Window.FindName('FilterOS')

$FilterPrimaryUser = $Window.FindName('FilterPrimaryUser')

$FilterCompliance = $Window.FindName('FilterCompliance')

$SearchResultsDataGrid = $Window.FindName('SearchResultsDataGrid')

$ConnectionStatusDot = $Window.FindName('ConnectionStatusDot')

$SearchPlaceholder = $Window.FindName('SearchPlaceholder')

$ResultCountText = $Window.FindName('ResultCountText')

$FilterToggleButton = $Window.FindName('FilterToggleButton')

$ClearSearchButton = $Window.FindName('ClearSearchButton')

$SearchEmptyState = $Window.FindName('SearchEmptyState')

$OffboardPanel = $Window.FindName('OffboardPanel')

$SelectedDeviceCount = $Window.FindName('SelectedDeviceCount')

$FilterDeviceName.Add_TextChanged({ Update-DeviceFilter })

$FilterSerialNumber.Add_TextChanged({ Update-DeviceFilter })

$FilterOS.Add_TextChanged({ Update-DeviceFilter })

$FilterPrimaryUser.Add_TextChanged({ Update-DeviceFilter })

$FilterCompliance.Add_TextChanged({ Update-DeviceFilter })

$SearchInputText.Add_GotFocus({ $SearchPlaceholder.Visibility = 'Collapsed' })

$SearchInputText.Add_LostFocus({
        if ([string]::IsNullOrEmpty($SearchInputText.Text)) {
            $SearchPlaceholder.Visibility = 'Visible'
        }
    })

$SearchInputText.Add_TextChanged({
        if ([string]::IsNullOrEmpty($SearchInputText.Text)) {
            $SearchPlaceholder.Visibility = 'Visible'
        } else {
            $SearchPlaceholder.Visibility = 'Collapsed'
        }
    })

$FilterToggleButton.Add_Click({
        if ($FilterRow.Visibility -eq 'Visible') {
            $FilterRow.Visibility = 'Collapsed'
            $FilterToggleButton.Content = 'Filter'
        } else {
            $FilterRow.Visibility = 'Visible'
            $FilterToggleButton.Content = 'Hide Filter'
        }
    })

$ClearSearchButton.Add_Click({
        $SearchInputText.Text = ''
        $SearchResultsDataGrid.ItemsSource = $null
        $script:AllSearchResults = $null
        $FilterRow.Visibility = 'Collapsed'
        $FilterToggleButton.Content = 'Filter'
        $FilterDeviceName.Text = ''
        $FilterSerialNumber.Text = ''
        $FilterOS.Text = ''
        $FilterPrimaryUser.Text = ''
        $FilterCompliance.Text = ''
        $ResultCountText.Text = ''
        $SearchEmptyState.Visibility = 'Visible'
        $SearchResultsDataGrid.Visibility = 'Collapsed'
        $OffboardPanel.Visibility = 'Collapsed'
        $OffboardButton.IsEnabled = $false
        $ExportSelectedButton.IsEnabled = $false
        $SetGroupTagButton.IsEnabled = $false
        $Window.FindName('intune_status').Text = 'Intune'
        $Window.FindName('autopilot_status').Text = 'Autopilot'
        $Window.FindName('aad_status').Text = 'Entra ID'
        $SearchInputText.Focus()
    })

$script:LastCheckedIndex = -1

$SearchResultsDataGrid.Add_PreviewMouseLeftButtonDown({
        param($sender, $e)
        $source = $e.OriginalSource
        # Walk up to find CheckBox
        $element = $source
        $isCheckBox = $false
        while ($element -ne $null) {
            if ($element -is [System.Windows.Controls.CheckBox]) {
                $isCheckBox = $true
                break
            }
            if ($element -is [System.Windows.Controls.DataGridRow]) { break }
            $element = [System.Windows.Media.VisualTreeHelper]::GetParent($element)
        }
        if (-not $isCheckBox) { return }

        # Find the DataGridRow
        $row = $source
        while ($row -ne $null -and $row -isnot [System.Windows.Controls.DataGridRow]) {
            $row = [System.Windows.Media.VisualTreeHelper]::GetParent($row)
        }
        if (-not $row) { return }
        $currentIndex = $SearchResultsDataGrid.ItemContainerGenerator.IndexFromContainer($row)
        if ($currentIndex -lt 0) { return }

        if ([System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::LeftShift) -or
            [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::RightShift)) {
            if ($script:LastCheckedIndex -ge 0) {
                $start = [Math]::Min($script:LastCheckedIndex, $currentIndex)
                $end = [Math]::Max($script:LastCheckedIndex, $currentIndex)
                $items = $SearchResultsDataGrid.ItemsSource
                $targetState = -not $items[$currentIndex].IsSelected
                for ($i = $start; $i -le $end; $i++) {
                    $items[$i].IsSelected = $targetState
                }
                $e.Handled = $true
            }
        }
        $script:LastCheckedIndex = $currentIndex
    })

$FeedbackLink.Add_Click({
        Start-Process "https://github.com/ugurkocde/DeviceOffboardingManager/issues"
    })

$SearchInputText.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Return) {
            $e.Handled = $true
            $SearchButton.RaiseEvent(
                (New-Object System.Windows.RoutedEventArgs(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        }
    })

$Window.Add_Loaded({
        $Dropdown.Items.Add("Device Name")
        $Dropdown.Items.Add("Serial Number")
        $Dropdown.Items.Add("Device ID")
        $Dropdown.Items.Add("Contains (partial match)")
        $Dropdown.SelectedIndex = 0
    })

$Dropdown.Add_SelectionChanged({
        $placeholderText = switch ($Dropdown.SelectedItem) {
            "Device Name"              { "Enter device name (e.g., DESKTOP-ABC123)..." }
            "Serial Number"            { "Enter serial number (e.g., 1234567890)..." }
            "Device ID"                { "Enter Intune device ID (GUID)..." }
            "Contains (partial match)" { "Enter partial name or serial (comma-separated)..." }
            default                    { "Enter device name, serial number, or ID..." }
        }
        $SearchPlaceholder.Text = $placeholderText
    })

$Window.Add_Loaded({
        try {
            Write-Log "Window is loading..."

            $context = Get-MgContext

            if ($null -eq $context) {
                Write-Log "Not connected to MS Graph"
                $AuthenticateButton.Content = "Connect to Microsoft Graph"
                $AuthenticateButton.IsEnabled = $true
                $Disconnect.IsEnabled = $false
                $PrerequisitesButton.IsEnabled = $true

                # Disable navigation menus
                $MenuDashboard.IsEnabled = $false
                $MenuDeviceManagement.IsEnabled = $false
                $MenuPlaybooks.IsEnabled = $false
                $HomeNavDashboard.IsEnabled = $false
                $HomeNavDeviceMgmt.IsEnabled = $false
                $HomeNavPlaybooks.IsEnabled = $false
                Update-HomePageState -Connected $false

                # Force Home menu selection
                $MenuHome.IsChecked = $true
            }
            else {
                Write-Log "Successfully connected to MS Graph"
                # Capture admin identity for audit logging on existing connection
                if ($context.Account) {
                    $script:AdminUPN = $context.Account
                } else {
                    $script:AdminUPN = "AppId:$($context.ClientId)"
                }
                $AuthenticateButton.Content = "Successfully connected"
                $AuthenticateButton.IsEnabled = $false
                $Disconnect.IsEnabled = $true
                $PrerequisitesButton.IsEnabled = $true
                $ConnectionStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#48BB78')
                $ConnectionStatusDot.ToolTip = "Connected"
                $CollapsedStatusDot.Fill = $ConnectionStatusDot.Fill
                $CollapsedStatusDot.ToolTip = "Connected"

                # Enable navigation menus
                $MenuDashboard.IsEnabled = $true
                $MenuDeviceManagement.IsEnabled = $true
                $MenuPlaybooks.IsEnabled = $true
                $HomeNavDashboard.IsEnabled = $true
                $HomeNavDeviceMgmt.IsEnabled = $true
                $HomeNavPlaybooks.IsEnabled = $true
                Update-HomePageState -Connected $true

                # Get tenant details for existing connection
                try {
                    Write-Log "Retrieving tenant information for existing connection..."
                    $tenantInfo = Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/organization?`$select=displayName,id,verifiedDomains" -Method GET
                    if ($tenantInfo.value) {
                        $org = $tenantInfo.value[0]
                        Write-Log "Found tenant: $($org.displayName)"

                        # Update UI elements
                        $Window.FindName('TenantDisplayName').Text = $org.displayName
                        $Window.FindName('TenantId').Text = $org.id
                        $Window.FindName('TenantDomain').Text = $org.verifiedDomains[0].name
                        $Window.FindName('TenantInfoSection').Visibility = 'Visible'
                    }
                }
                catch {
                    Write-Log "Warning: Could not retrieve tenant details for existing connection: $_"
                }

                # Verify permissions for existing connection
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
                    Write-Log "Warning: Missing permissions for existing connection: $missingList"
                    Show-Toast -Message "Missing permissions: $missingList" -Type "info" -DurationSeconds 6
                }
            }

            # Update version displays
            Update-VersionDisplays -window $Window
            Write-Log "Version displays updated"

            # If already connected on launch, navigate to Dashboard
            if ($null -ne (Get-MgContext)) {
                $MenuDashboard.IsChecked = $true
            }
        }
        catch {
            Write-Log "Error occurred during window load: $_"
            $AuthenticateButton.Content = "Not Connected to MS Graph"
            $AuthenticateButton.IsEnabled = $true
            $Disconnect.IsEnabled = $false
            $PrerequisitesButton.IsEnabled = $true

            # Disable navigation menus
            $MenuDashboard.IsEnabled = $false
            $MenuDeviceManagement.IsEnabled = $false
            $MenuPlaybooks.IsEnabled = $false
            $HomeNavDashboard.IsEnabled = $false
            $HomeNavDeviceMgmt.IsEnabled = $false
            $HomeNavPlaybooks.IsEnabled = $false
            Update-HomePageState -Connected $false
        }
    })

$Disconnect.Add_Click({
        try {
            Write-Log "Attempting to disconnect from MS Graph..."

            # Disconnect from Graph
            Disconnect-MgGraph -ErrorAction Stop
            if ($script:CurrentAuthDetails -and $script:CurrentAuthDetails.SecretSecureString) {
                $script:CurrentAuthDetails.SecretSecureString.Dispose()
            }
            $script:CurrentAuthDetails = $null

            # Reset UI state
            $Disconnect.Content = "Disconnected"
            $Disconnect.IsEnabled = $false
            $AuthenticateButton.Content = "Connect to MS Graph"
            $AuthenticateButton.IsEnabled = $true
            $PrerequisitesButton.IsEnabled = $true
            $ConnectionStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FC8181')
            $ConnectionStatusDot.ToolTip = "Disconnected"
            $CollapsedStatusDot.Fill = $ConnectionStatusDot.Fill
            $CollapsedStatusDot.ToolTip = "Disconnected"

            # Hide tenant info
            $Window.FindName('TenantInfoSection').Visibility = 'Collapsed'
            $Window.FindName('TenantDisplayName').Text = ""
            $Window.FindName('TenantId').Text = ""
            $Window.FindName('TenantDomain').Text = ""

            # Disable navigation menus and force Home selection
            $MenuDashboard.IsEnabled = $false
            $MenuDeviceManagement.IsEnabled = $false
            $MenuPlaybooks.IsEnabled = $false
            $HomeNavDashboard.IsEnabled = $false
            $HomeNavDeviceMgmt.IsEnabled = $false
            $HomeNavPlaybooks.IsEnabled = $false
            Update-HomePageState -Connected $false
            $MenuHome.IsChecked = $true

            # Clear any sensitive data from the dashboard
            $Window.FindName('IntuneDevicesCount').Text = "--"
            $Window.FindName('AutopilotDevicesCount').Text = "--"
            $Window.FindName('EntraIDDevicesCount').Text = "--"
            $Window.FindName('StaleDevices30Count').Text = "--"
            $Window.FindName('StaleDevices90Count').Text = "--"
            $Window.FindName('StaleDevices180Count').Text = "--"
            $Window.FindName('PersonalDevicesCount').Text = "--"
            $Window.FindName('CorporateDevicesCount').Text = "--"
            $Window.FindName('DashboardLastRefreshed').Text = ""

            Write-Log "Successfully disconnected from MS Graph"
        }
        catch {
            if ($script:CurrentAuthDetails -and $script:CurrentAuthDetails.SecretSecureString) {
                $script:CurrentAuthDetails.SecretSecureString.Dispose()
            }
            $script:CurrentAuthDetails = $null
            Write-Log "Error occurred while attempting to disconnect from MS Graph: $_"
            Show-Toast -Message "Error disconnecting from Microsoft Graph: $_" -Type "error" -DurationSeconds 6
        }
    })

$AuthenticateButton.Add_Click({
        try {
            # Check if already connected
            $context = Get-MgContext
            if ($context) {
                Write-Log "Already connected to MS Graph, skipping authentication dialog"
                return
            }

            Write-Log "Authentication button clicked, showing authentication dialog..."

            # Reset the connection failed flag
            $script:connectionFailed = $false

            # Show authentication dialog
            $authDetails = Show-AuthenticationDialog
            if (-not $authDetails) {
                Write-Log "Authentication cancelled by user"
                # Reset button state if cancelled
                $AuthenticateButton.Content = "Connect to MS Graph"
                $AuthenticateButton.IsEnabled = $true
                return
            }

            # Set button to "Connecting..." state
            $AuthenticateButton.Content = "Connecting..."
            $AuthenticateButton.IsEnabled = $false

            # Attempt to connect
            $connected = Connect-ToGraph -AuthDetails $authDetails

            # Check connection status and update UI accordingly
            if ($connected -and -not $script:connectionFailed) {
                Write-Log "Authentication Successful"
                $AuthenticateButton.Content = "Connected to MS Graph"
                $AuthenticateButton.IsEnabled = $false
                $Disconnect.Content = "Disconnect"
                $Disconnect.IsEnabled = $true
                $ConnectionStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#48BB78')
                $ConnectionStatusDot.ToolTip = "Connected"
                $CollapsedStatusDot.Fill = $ConnectionStatusDot.Fill
                $CollapsedStatusDot.ToolTip = "Connected"

                # Enable navigation menus
                $MenuDashboard.IsEnabled = $true
                $MenuDeviceManagement.IsEnabled = $true
                $MenuPlaybooks.IsEnabled = $true
                $HomeNavDashboard.IsEnabled = $true
                $HomeNavDeviceMgmt.IsEnabled = $true
                $HomeNavPlaybooks.IsEnabled = $true
                Update-HomePageState -Connected $true
            }
            else {
                # Reset button state on failed connection
                Write-Log "Authentication Failed"
                if ($script:CurrentAuthDetails -and $script:CurrentAuthDetails.SecretSecureString) {
                    $script:CurrentAuthDetails.SecretSecureString.Dispose()
                }
                $script:CurrentAuthDetails = $null
                $AuthenticateButton.Content = "Connect to MS Graph"
                $AuthenticateButton.IsEnabled = $true
                $Disconnect.Content = "Disconnected"
                $Disconnect.IsEnabled = $false
                $ConnectionStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FC8181')
                $ConnectionStatusDot.ToolTip = "Disconnected"
                $CollapsedStatusDot.Fill = $ConnectionStatusDot.Fill
                $CollapsedStatusDot.ToolTip = "Disconnected"

                # Disable navigation menus
                $MenuDashboard.IsEnabled = $false
                $MenuDeviceManagement.IsEnabled = $false
                $MenuPlaybooks.IsEnabled = $false
                $HomeNavDashboard.IsEnabled = $false
                $HomeNavDeviceMgmt.IsEnabled = $false
                $HomeNavPlaybooks.IsEnabled = $false
                Update-HomePageState -Connected $false

                # Hide tenant info
                $Window.FindName('TenantInfoSection').Visibility = 'Collapsed'
                $Window.FindName('TenantDisplayName').Text = ""
                $Window.FindName('TenantId').Text = ""
                $Window.FindName('TenantDomain').Text = ""
            }
        }
        catch {
            Write-Log "Error occurred during authentication. Exception: $_"
            if ($script:CurrentAuthDetails -and $script:CurrentAuthDetails.SecretSecureString) {
                $script:CurrentAuthDetails.SecretSecureString.Dispose()
            }
            $script:CurrentAuthDetails = $null
            # Reset button state on error
            $AuthenticateButton.Content = "Connect to MS Graph"
            $AuthenticateButton.IsEnabled = $true
            $Disconnect.Content = "Disconnected"
            $Disconnect.IsEnabled = $false

            # Disable navigation menus
            $MenuDashboard.IsEnabled = $false
            $MenuDeviceManagement.IsEnabled = $false
            $MenuPlaybooks.IsEnabled = $false
            Update-HomePageState -Connected $false

            # Hide tenant info
            $Window.FindName('TenantInfoSection').Visibility = 'Collapsed'
            $Window.FindName('TenantDisplayName').Text = ""
            $Window.FindName('TenantId').Text = ""
            $Window.FindName('TenantDomain').Text = ""

            Show-Toast -Message "Authentication failed: $_" -Type "error" -DurationSeconds 6
        }
    })

$SearchButton.Add_Click({
        if ($AuthenticateButton.IsEnabled) {
            Write-Log "User is not connected to MS Graph. Attempted search operation."
            Show-Toast -Message "You are not connected to MS Graph. Please connect first." -Type "info"
            return
        }

        try {
            # Trim the input and split by comma
            $searchInput = $SearchInputText.Text.Trim()
            $SearchTexts = $searchInput -split ', ' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

            if ($SearchTexts.Count -eq 0) {
                Show-Toast -Message "Please enter at least one device name or serial number." -Type "info"
                return
            }

            # Show searching state
            $SearchButton.Content = "Searching..."
            $SearchButton.IsEnabled = $false
            $Window.Cursor = [System.Windows.Input.Cursors]::Wait
            $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action]{})

            Write-Log "Searching for devices: $SearchTexts"
            $searchOption = $Dropdown.SelectedItem

            # Call the centralized search function
            Invoke-DeviceSearch -SearchTexts $SearchTexts -SearchOption $searchOption
        }
        catch {
            Write-Log "Error occurred during search operation. Exception: $_"
            Show-Toast -Message "Error in search operation. Please ensure the Serial Number or Device Name is valid." -Type "error" -DurationSeconds 6
        }
        finally {
            $SearchButton.Content = "Search"
            $SearchButton.IsEnabled = $true
            $Window.Cursor = $null
        }
    })

$bulk_import_button.Add_Click({
        if ($AuthenticateButton.IsEnabled) {
            Write-Log "User is not connected to MS Graph. Attempted bulk import operation."
            Show-Toast -Message "You are not connected to MS Graph. Please connect first." -Type "info"
            return
        }

        try {
            Write-Log "Opening bulk import dialog..."

            # Show the bulk import modal
            $devices = Show-BulkImportDialog

            if ($devices -and $devices.Count -gt 0) {
                Write-Log "User imported $($devices.Count) devices from bulk import dialog"

                # Join device names for display
                $deviceNamesString = $devices -join ", "
                $SearchInputText.Text = $deviceNamesString

                # Get the selected search option
                $searchOption = $Dropdown.SelectedItem

                # Automatically trigger the search
                Write-Log "Automatically triggering search for imported devices"
                Invoke-DeviceSearch -SearchTexts $devices -SearchOption $searchOption
            }
            else {
                Write-Log "Bulk import cancelled or no devices imported"
            }
        }
        catch {
            Write-Log "Exception in bulk import: $_"
            Show-Toast -Message "Error in bulk import operation: $_" -Type "error" -DurationSeconds 6
        }
    })

$OffboardButton.Add_Click({
        if ($AuthenticateButton.IsEnabled) {
            Write-Log "User is not connected to MS Graph. Attempted offboarding operation."
            Show-Toast -Message "You are not connected to MS Graph. Please connect first." -Type "info"
            return
        }

        $selectedDevices = $SearchResultsDataGrid.ItemsSource | Where-Object { $_.IsSelected }

        if (-not $selectedDevices) {
            Show-Toast -Message "Please select at least one device to offboard." -Type "info"
            return
        }

        # Resolve missing IDs for selected devices before showing confirmation
        foreach ($device in $selectedDevices) {
            try {
                $resolvedIntuneDevice = $null

                # Prefer serial-number correlation for Intune. Do not fall back to name when a serial was provided but no exact serial match exists.
                if (-not $device.IntuneDeviceId) {
                    if ($device.SerialNumber) {
                        $resolvedIntuneDevice = Get-IntuneDeviceBySerial -SerialNumber $device.SerialNumber
                        if ($resolvedIntuneDevice) {
                            $device.IntuneDeviceId = $resolvedIntuneDevice.id
                            if (-not $device.DeviceName) { $device.DeviceName = $resolvedIntuneDevice.deviceName }
                            if (-not $device.SerialNumber) { $device.SerialNumber = $resolvedIntuneDevice.serialNumber }
                            if (-not $device.OperatingSystem) { $device.OperatingSystem = $resolvedIntuneDevice.operatingSystem }
                            if (-not $device.PrimaryUser) { $device.PrimaryUser = $resolvedIntuneDevice.userDisplayName }
                            if (-not $device.ComplianceState) { $device.ComplianceState = $resolvedIntuneDevice.complianceState }
                            if (-not $device.ManagementAgent) { $device.ManagementAgent = $resolvedIntuneDevice.managementAgent }
                        }
                        else {
                            Write-Log "No unique Intune serial match found for '$($device.SerialNumber)'. Skipping Intune ID auto-resolution by name." -Severity "WARN"
                        }
                    }
                    elseif ($device.DeviceName) {
                        $escapedName = ConvertTo-ODataStringValue -Value $device.DeviceName
                        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=deviceName eq '$escapedName'&`$select=id,deviceName,serialNumber,operatingSystem,userDisplayName,lastSyncDateTime,azureADDeviceId,complianceState,managementAgent"
                        $intuneDevices = @(Get-GraphPagedResults -Uri $uri)
                        if ($intuneDevices.Count -eq 1) {
                            $resolvedIntuneDevice = $intuneDevices[0]
                            $device.IntuneDeviceId = $resolvedIntuneDevice.id
                            if (-not $device.SerialNumber) { $device.SerialNumber = $resolvedIntuneDevice.serialNumber }
                        }
                        elseif ($intuneDevices.Count -gt 1) {
                            Write-Log "Multiple Intune devices found for name '$($device.DeviceName)' - skipping auto-resolution to prevent wrong-device match" -Severity "WARN"
                        }
                    }
                }

                if (-not $resolvedIntuneDevice -and $device.IntuneDeviceId) {
                    try {
                        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($device.IntuneDeviceId)?`$select=id,deviceName,serialNumber,operatingSystem,userDisplayName,lastSyncDateTime,azureADDeviceId,complianceState,managementAgent"
                        $resolvedIntuneDevice = Invoke-GraphRequestWithRetry -Uri $uri -Method GET
                    }
                    catch {
                        Write-Log "Could not refresh Intune device '$($device.IntuneDeviceId)' before confirmation: $_" -Severity "WARN"
                    }
                }

                # Resolve Entra by Intune azureADDeviceId or serial-bearing physicalIds before considering a unique name fallback.
                if (-not $device.EntraDeviceId) {
                    $entraDevice = $null
                    if ($resolvedIntuneDevice) {
                        $entraDevice = Get-EntraDeviceForIntuneDevice -IntuneDevice $resolvedIntuneDevice
                    }

                    if (-not $entraDevice -and $device.SerialNumber -and $device.DeviceName) {
                        $escapedName = ConvertTo-ODataStringValue -Value $device.DeviceName
                        $uri = "https://graph.microsoft.com/beta/devices?`$filter=displayName eq '$escapedName'&`$select=id,deviceId,displayName,operatingSystem,approximateLastSignInDateTime,accountEnabled,physicalIds"
                        $entraMatches = @(Get-GraphPagedResults -Uri $uri | Where-Object {
                                Test-SameIdentifier -Left (Get-SerialNumberFromPhysicalIds -PhysicalIds $_.physicalIds) -Right $device.SerialNumber
                            })
                        if ($entraMatches.Count -eq 1) {
                            $entraDevice = $entraMatches[0]
                        }
                        elseif ($entraMatches.Count -gt 1) {
                            Write-Log "Multiple Entra ID devices matched name '$($device.DeviceName)' and serial '$($device.SerialNumber)'. Skipping automatic correlation." -Severity "WARN"
                        }
                    }

                    if (-not $entraDevice -and -not $device.SerialNumber -and $device.DeviceName) {
                        $escapedName = ConvertTo-ODataStringValue -Value $device.DeviceName
                        $uri = "https://graph.microsoft.com/beta/devices?`$filter=displayName eq '$escapedName'&`$select=id,deviceId,displayName,operatingSystem,approximateLastSignInDateTime,accountEnabled,physicalIds"
                        $entraDevices = @(Get-GraphPagedResults -Uri $uri)
                        if ($entraDevices.Count -eq 1) {
                            $entraDevice = $entraDevices[0]
                        }
                        elseif ($entraDevices.Count -gt 1) {
                            Write-Log "Multiple Entra ID devices found for name '$($device.DeviceName)' - skipping auto-resolution to prevent wrong-device match" -Severity "WARN"
                        }
                    }

                    if ($entraDevice) {
                        $device.EntraDeviceId = $entraDevice.id
                        $device.EntraDeviceObjectId = $entraDevice.deviceId
                        $device.EntraAccountEnabled = if ($null -ne $entraDevice.accountEnabled) { $entraDevice.accountEnabled.ToString() } else { $null }
                    }
                }

                # If we have a serial number but no Autopilot ID, try to resolve it by exact serial.
                if ($device.SerialNumber -and -not $device.AutopilotIdentityId) {
                    $autopilotDevice = Get-AutopilotDeviceBySerial -SerialNumber $device.SerialNumber
                    if ($autopilotDevice) {
                        $device.AutopilotIdentityId = $autopilotDevice.id
                    }
                }
                Write-Log "Resolved IDs for $($device.DeviceName): Entra=$($device.EntraDeviceId), Intune=$($device.IntuneDeviceId), Autopilot=$($device.AutopilotIdentityId)"
            }
            catch {
                Write-Log "Error resolving IDs for device $($device.DeviceName): $_" -Severity "WARN"
            }
        }

        # Show confirmation modal
        [xml]$confirmationModalXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Confirm Device Offboarding" Height="800" Width="700" WindowStartupLocation="CenterScreen" Background="#F8F9FA">
    <Border Background="White" CornerRadius="8" Margin="16">
        <DockPanel Margin="24">
            <!-- Header -->
            <StackPanel DockPanel.Dock="Top" Margin="0,0,0,16">
                <TextBlock Text="Confirm Device Offboarding" FontSize="24" FontWeight="SemiBold" Foreground="#1A202C"/>
                <TextBlock x:Name="ConfirmSubtitle" Text="Select which services to offboard from" Foreground="#4A5568" FontSize="14" Margin="0,8,0,0"/>
            </StackPanel>

            <!-- Warning Message (Top, always visible) -->
            <Border DockPanel.Dock="Top" Background="#FEF2F2" BorderBrush="#FEE2E2" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,16">
                <StackPanel Orientation="Horizontal">
                    <Path Data="M12,2L1,21H23M12,6L19.53,19H4.47M11,10V13H13V10M11,15V17H13V15" Fill="#DC2626" Width="24" Height="24" Stretch="Uniform" Margin="0,0,12,0"/>
                    <TextBlock Text="This action cannot be undone. Devices will be removed or disabled from the selected services." Foreground="#DC2626" TextWrapping="Wrap" VerticalAlignment="Center" MaxWidth="400"/>
                </StackPanel>
            </Border>

            <!-- Action Buttons with Type-to-Confirm -->
            <StackPanel DockPanel.Dock="Bottom" Margin="0,16,0,0">
                <StackPanel Margin="0,0,0,12">
                    <TextBlock Text="Type OFFBOARD to confirm:" FontWeight="SemiBold" FontSize="13" Foreground="#DC2626" Margin="0,0,0,6"/>
                    <TextBox x:Name="ConfirmationTextBox" Height="36" Padding="12,8" FontSize="14" BorderBrush="#FEE2E2" BorderThickness="1" MaxWidth="300" HorizontalAlignment="Left"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button x:Name="CancelButton" Content="Cancel" Width="120" Height="40" Background="#F0F0F0" Foreground="#2D3748" BorderThickness="0" Margin="0,0,12,0" IsCancel="True" Cursor="Hand"/>
                    <Button x:Name="ConfirmButton" Content="Confirm Offboarding" Width="160" Height="40" Background="#DC2626" Foreground="White" BorderThickness="0" IsEnabled="False" Cursor="Hand"/>
                </StackPanel>
            </StackPanel>

            <!-- Main Content -->
            <StackPanel>
                <!-- Co-Management Warning Banner -->
                <Border x:Name="CoMgmtBanner" Background="#FFFBEB" BorderBrush="#FDE68A" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,16" Visibility="Collapsed">
                    <TextBlock Text="One or more devices are co-managed with Configuration Manager. Removing from Intune may disrupt SCCM management." Foreground="#92400E" TextWrapping="Wrap" FontSize="13"/>
                </Border>

                <!-- Pre-Offboarding Action -->
                <StackPanel Margin="0,0,0,16">
                    <TextBlock Text="Pre-Offboarding Action" FontWeight="SemiBold" FontSize="14" Margin="0,0,0,8"/>
                    <TextBlock Text="Optionally retire or wipe devices before deletion." Foreground="#718096" FontSize="12" Margin="0,0,0,8"/>
                    <ComboBox x:Name="PreActionComboBox" Width="250" HorizontalAlignment="Left" SelectedIndex="0">
                        <ComboBoxItem Content="Delete only (no pre-action)"/>
                        <ComboBoxItem Content="Retire then Delete"/>
                        <ComboBoxItem Content="Wipe then Delete"/>
                    </ComboBox>
                </StackPanel>

                <!-- Services List -->
                <WrapPanel x:Name="ServicesList" Margin="0,0,0,24" Orientation="Horizontal"/>

                <!-- Device Identity Preview -->
                <Border Background="#F0FFF4" BorderBrush="#C6F6D5" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,16" MaxHeight="200">
                    <Grid VerticalAlignment="Stretch">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <TextBlock Grid.Row="0" Text="Device Identity Preview" FontWeight="SemiBold" FontSize="14" Margin="0,0,0,8"/>
                        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" VerticalAlignment="Stretch">
                            <ItemsControl x:Name="DevicePreviewList">
                                <ItemsControl.ItemTemplate>
                                    <DataTemplate>
                                        <Border Background="White" BorderBrush="#E2E8F0" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                                            <StackPanel>
                                                <TextBlock FontWeight="SemiBold" Margin="0,0,0,4">
                                                    <Run Text="{Binding DeviceName, Mode=OneWay}"/>
                                                    <Run Text=" | " Foreground="#A0AEC0"/>
                                                    <Run Text="{Binding SerialText, Mode=OneWay}" Foreground="#718096"/>
                                                </TextBlock>
                                                <WrapPanel>
                                                    <TextBlock Margin="0,0,16,0" FontSize="11" TextWrapping="Wrap" MaxWidth="620">
                                                        <Run Text="Entra: " FontWeight="Medium"/>
                                                        <Run Text="{Binding EntraIdText, Mode=OneWay}" Foreground="{Binding EntraIdColor, Mode=OneWay}"/>
                                                    </TextBlock>
                                                    <TextBlock Margin="0,0,16,0" FontSize="11" TextWrapping="Wrap" MaxWidth="620">
                                                        <Run Text="Intune: " FontWeight="Medium"/>
                                                        <Run Text="{Binding IntuneIdText, Mode=OneWay}" Foreground="{Binding IntuneIdColor, Mode=OneWay}"/>
                                                    </TextBlock>
                                                    <TextBlock FontSize="11" TextWrapping="Wrap" MaxWidth="620">
                                                        <Run Text="Autopilot: " FontWeight="Medium"/>
                                                        <Run Text="{Binding AutopilotIdText, Mode=OneWay}" Foreground="{Binding AutopilotIdColor, Mode=OneWay}"/>
                                                    </TextBlock>
                                                </WrapPanel>
                                            </StackPanel>
                                        </Border>
                                    </DataTemplate>
                                </ItemsControl.ItemTemplate>
                            </ItemsControl>
                        </ScrollViewer>
                    </Grid>
                </Border>

                <!-- Encryption Key Section -->
                <Border Background="#EDF2F7" BorderBrush="#E2E8F0" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,16" Height="300">
                    <Grid VerticalAlignment="Stretch">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <TextBlock Grid.Row="0" Text="Device Credentials &amp; Keys" FontWeight="SemiBold" FontSize="14" Margin="0,0,0,8"/>
                        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" VerticalAlignment="Stretch">
                            <ItemsControl x:Name="EncryptionKeysList">
                                <ItemsControl.ItemTemplate>
                                    <DataTemplate>
                                        <StackPanel Margin="0,0,0,24">
                                            <TextBlock Text="{Binding DeviceName}" FontWeight="SemiBold" Margin="0,0,0,4"/>
                                            <TextBlock Text="{Binding KeyText}" TextWrapping="Wrap" Margin="0,0,0,12"/>
                                            <Button x:Name="CopyKeyButton" Content="Copy Key" Width="100" HorizontalAlignment="Left"
                                                    Height="32" Background="#0078D4" Foreground="White" BorderThickness="0"
                                                    Tag="{Binding Key}" Margin="0,0,0,4" Cursor="Hand"
                                                    ToolTip="Copy recovery key to clipboard">
                                                <Button.Resources>
                                                    <Style TargetType="Border">
                                                        <Setter Property="CornerRadius" Value="4"/>
                                                    </Style>
                                                </Button.Resources>
                                            </Button>
                                        </StackPanel>
                                    </DataTemplate>
                                </ItemsControl.ItemTemplate>
                            </ItemsControl>
                        </ScrollViewer>
                    </Grid>
                </Border>
            </StackPanel>
        </DockPanel>
    </Border>
</Window>
'@

        try {
            $reader = (New-Object System.Xml.XmlNodeReader $confirmationModalXaml)
            $confirmationWindow = [Windows.Markup.XamlReader]::Load($reader)

            if ($null -eq $confirmationWindow) {
                throw "Failed to create confirmation window. XamlReader returned null."
            }
        }
        catch {
            Write-Log "Error creating confirmation window: $_"
            Show-Toast -Message "Failed to create the confirmation dialog: $_" -Type "error" -DurationSeconds 6
            return
        }

        # Get controls
        $servicesList = $confirmationWindow.FindName('ServicesList')
        $cancelButton = $confirmationWindow.FindName('CancelButton')
        $confirmButton = $confirmationWindow.FindName('ConfirmButton')
        $encryptionKeysList = $confirmationWindow.FindName('EncryptionKeysList')
        $devicePreviewList = $confirmationWindow.FindName('DevicePreviewList')
        $preActionCombo = $confirmationWindow.FindName('PreActionComboBox')
        $coMgmtBanner = $confirmationWindow.FindName('CoMgmtBanner')
        $confirmationTextBox = $confirmationWindow.FindName('ConfirmationTextBox')
        $confirmSubtitle = $confirmationWindow.FindName('ConfirmSubtitle')

        # Set device count in subtitle
        $deviceCount = @($selectedDevices).Count
        $confirmSubtitle.Text = "Offboarding $deviceCount device$(if ($deviceCount -ne 1) { 's' }) -- select which services to remove from"

        # Wire type-to-confirm: enable ConfirmButton only when user types "OFFBOARD"
        $confirmationTextBox.Add_TextChanged({
                if ($confirmationTextBox.Text -eq 'OFFBOARD') {
                    $confirmButton.IsEnabled = $true
                    $confirmationTextBox.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#48BB78')
                } else {
                    $confirmButton.IsEnabled = $false
                    $confirmationTextBox.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FEE2E2')
                }
            })

        # Check for co-managed devices and show warning banner
        $hasCoManaged = $selectedDevices | Where-Object { $_.ManagementAgent -and $_.ManagementAgent -like '*configurationManager*' }
        if ($hasCoManaged) {
            $coMgmtBanner.Visibility = 'Visible'
        }

        # Populate Device Identity Preview
        $previewItems = New-Object System.Collections.ObjectModel.ObservableCollection[Object]
        foreach ($device in $selectedDevices) {
            $resolvedColor = "#48BB78"
            $notFoundColor = "#F56565"
            $previewItems.Add([PSCustomObject]@{
                DeviceName     = if ($device.DeviceName) { $device.DeviceName } else { "Unknown" }
                SerialText     = if ($device.SerialNumber) { "S/N: $($device.SerialNumber)" } else { "S/N: N/A" }
                EntraIdText    = if ($device.EntraDeviceId) { $device.EntraDeviceId } else { "Not found" }
                EntraIdColor   = if ($device.EntraDeviceId) { $resolvedColor } else { $notFoundColor }
                IntuneIdText   = if ($device.IntuneDeviceId) { $device.IntuneDeviceId } else { "Not found" }
                IntuneIdColor  = if ($device.IntuneDeviceId) { $resolvedColor } else { $notFoundColor }
                AutopilotIdText  = if ($device.AutopilotIdentityId) { $device.AutopilotIdentityId } else { "Not found" }
                AutopilotIdColor = if ($device.AutopilotIdentityId) { $resolvedColor } else { $notFoundColor }
            })
        }
        $devicePreviewList.ItemsSource = $previewItems

        # Create a list to store encryption key information
        $encryptionKeys = New-Object System.Collections.ObjectModel.ObservableCollection[Object]

        # Get encryption keys for all selected devices using cached IDs
        foreach ($selectedDevice in $selectedDevices) {
            try {
                $keyInfo = @{
                    DeviceName = $selectedDevice.DeviceName
                    KeyText    = "Loading encryption key..."
                    Key        = $null
                }

                # Use cached Intune ID to get device details if needed
                $intuneDevice = $null
                if ($selectedDevice.IntuneDeviceId) {
                    $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($selectedDevice.IntuneDeviceId)?`$select=operatingSystem,azureADDeviceId,serialNumber"
                    try { $intuneDevice = Invoke-GraphRequestWithRetry -Uri $uri -Method GET } catch { $intuneDevice = $null }
                }

                if ($intuneDevice) {
                    # Check OS type and get appropriate encryption key
                    if ($intuneDevice.operatingSystem -eq "Windows") {
                        try {
                            # Use cached EntraDeviceObjectId for BitLocker lookup
                            $bitlockerDeviceId = $selectedDevice.EntraDeviceObjectId ?? $intuneDevice.azureADDeviceId
                            $uri = "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$bitlockerDeviceId'"
                            $keyIdResponse = Get-GraphPagedResults -Uri $uri

                            if ($keyIdResponse.Count -gt 0) {
                                $recoveryKeyId = $keyIdResponse[0].id
                                $uri = "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys/$($recoveryKeyId)?`$select=key"
                                $recoveryKeyData = Invoke-MgGraphRequest -Uri $uri -Method GET

                                if ($recoveryKeyData.key) {
                                    $keyInfo.KeyText = "BitLocker Recovery Key: $($recoveryKeyData.key)"
                                    $keyInfo.Key = $recoveryKeyData.key
                                    Write-Log "SENSITIVE: BitLocker recovery key for device $($selectedDevice.DeviceName): $($recoveryKeyData.key)" -Severity "AUDIT"
                                }
                                else {
                                    $keyInfo.KeyText = "Error retrieving BitLocker key details."
                                }
                            }
                            else {
                                $keyInfo.KeyText = "No BitLocker recovery key found for this device."
                            }
                        }
                        catch {
                            Write-Log "Error retrieving BitLocker key: $_" -Severity "ERROR"
                            if ($_.Exception.Response.StatusCode -eq 'Forbidden') {
                                $keyInfo.KeyText = "BitLocker key access denied. Ensure BitlockerKey.Read.All permission is granted."
                            }
                            else {
                                $keyInfo.KeyText = "Error retrieving BitLocker key. Check logs for details."
                            }
                        }
                    }
                    elseif ($intuneDevice.operatingSystem -eq "macOS") {
                        # Get FileVault key using cached Intune ID
                        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$($selectedDevice.IntuneDeviceId)')/getFileVaultKey"
                        try {
                            $fileVaultKey = Invoke-MgGraphRequest -Uri $uri -Method GET
                            if ($fileVaultKey.value) {
                                $keyInfo.KeyText = "FileVault Recovery Key: $($fileVaultKey.value)"
                                $keyInfo.Key = $fileVaultKey.value
                                Write-Log "SENSITIVE: FileVault recovery key for device $($selectedDevice.DeviceName): $($fileVaultKey.value)" -Severity "AUDIT"
                            }
                            else {
                                $keyInfo.KeyText = "No FileVault recovery key found for this device."
                            }
                        }
                        catch {
                            Write-Log "Error retrieving FileVault key: $_" -Severity "ERROR"
                            $keyInfo.KeyText = "Error retrieving FileVault key details."
                        }
                    }
                    else {
                        $keyInfo.KeyText = "Encryption key not applicable for this device type."
                    }
                }
                else {
                    $keyInfo.KeyText = "Device not found in Intune."
                }

                # LAPS password retrieval (works for any OS, uses Entra device ID)
                $lapsKeyInfo = @{
                    DeviceName = "$($selectedDevice.DeviceName) - LAPS"
                    KeyText    = "Loading LAPS password..."
                    Key        = $null
                }
                $lapsDeviceId = $selectedDevice.EntraDeviceObjectId
                if (-not $lapsDeviceId) { $lapsDeviceId = $intuneDevice.azureADDeviceId }
                Write-Log "LAPS lookup - EntraDeviceObjectId: '$($selectedDevice.EntraDeviceObjectId)', intuneDevice.azureADDeviceId: '$($intuneDevice.azureADDeviceId)', resolved lapsDeviceId: '$lapsDeviceId'" -Severity "INFO"
                if ($lapsDeviceId) {
                    try {
                        $uri = "https://graph.microsoft.com/beta/directory/deviceLocalCredentials/$($lapsDeviceId)?`$select=credentials"
                        $lapsResponse = Invoke-MgGraphRequest -Uri $uri -Method GET
                        if ($lapsResponse.credentials -and $lapsResponse.credentials.Count -gt 0) {
                            $latestCred = $lapsResponse.credentials | Sort-Object -Property backupDateTime -Descending | Select-Object -First 1
                            $lapsPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($latestCred.passwordBase64))
                            $lapsAccount = $latestCred.accountName
                            $lapsKeyInfo.KeyText = "LAPS Password: $lapsPassword (Account: $lapsAccount)"
                            $lapsKeyInfo.Key = $lapsPassword
                            Write-Log "SENSITIVE: LAPS password for device $($selectedDevice.DeviceName) account '$lapsAccount': $lapsPassword" -Severity "AUDIT"
                        } else {
                            $lapsKeyInfo.KeyText = "No LAPS password found for this device."
                        }
                    }
                    catch {
                        if ($_.Exception.Response.StatusCode -eq 'NotFound' -or $_ -match '404') {
                            $lapsKeyInfo.KeyText = "No LAPS password found for this device."
                        } else {
                            Write-Log "Error retrieving LAPS password: $_" -Severity "ERROR"
                            $lapsKeyInfo.KeyText = "Error retrieving LAPS password. Check logs for details."
                        }
                    }
                } else {
                    $lapsKeyInfo.KeyText = "No Entra device ID available for LAPS lookup."
                }
                $encryptionKeys.Add([PSCustomObject]$lapsKeyInfo)
            }
            catch {
                Write-Log "Error retrieving encryption key for $($selectedDevice.DeviceName): $_" -Severity "ERROR"
                $keyInfo.KeyText = "Error retrieving encryption key. Please check logs for details."
            }

            $encryptionKeys.Add([PSCustomObject]$keyInfo)
        }

        # Set the ItemsSource of the EncryptionKeysList
        $encryptionKeysList.ItemsSource = $encryptionKeys

        # Add copy button handler
        $confirmationWindow.Add_SourceInitialized({
                $copyKeyButton_Click = {
                    param($sender, $e)
                    $button = $e.OriginalSource -as [System.Windows.Controls.Button]
                    if ($button -and $button.Tag) {
                        Set-Clipboard -Value $button.Tag
                        $button.Content = "Copied!"
                        $script:copyButtonTimer = New-Object System.Windows.Threading.DispatcherTimer
                        $script:copyButtonTimer.Interval = [TimeSpan]::FromSeconds(2)
                        $script:copyButtonTimer.Add_Tick({
                                $button.Content = "Copy Key"
                                $script:copyButtonTimer.Stop()
                            }.GetNewClosure())
                        $script:copyButtonTimer.Start()
                    }
                }.GetNewClosure()

                $encryptionKeysList = $confirmationWindow.FindName('EncryptionKeysList')
                $encryptionKeysList.AddHandler(
                    [System.Windows.Controls.Button]::ClickEvent,
                    [System.Windows.RoutedEventHandler]$copyKeyButton_Click
                )
            })

        # Add services to the list with checkboxes
        $services = @(
            @{ Name = "Entra ID"; Icon = "M12,5.5A3.5,3.5 0 0,1 15.5,9A3.5,3.5 0 0,1 12,12.5A3.5,3.5 0 0,1 8.5,9A3.5,3.5 0 0,1 12,5.5M5,8C5.56,8 6.08,8.15 6.53,8.42C6.38,9.85 6.8,11.27 7.66,12.38C7.16,13.34 6.16,14 5,14A3,3 0 0,1 2,11A3,3 0 0,1 5,8M19,8A3,3 0 0,1 22,11A3,3 0 0,1 19,14C17.84,14 16.84,13.34 16.34,12.38C17.2,11.27 17.62,9.85 17.47,8.42C17.92,8.15 18.44,8 19,8M5.5,18.25C5.5,16.18 8.41,14.5 12,14.5C15.59,14.5 18.5,16.18 18.5,18.25V20H5.5V18.25M0,20V18.5C0,17.11 1.89,15.94 4.45,15.6C3.86,16.28 3.5,17.22 3.5,18.25V20H0M24,20H20.5V18.25C20.5,17.22 20.14,16.28 19.55,15.6C22.11,15.94 24,17.11 24,18.5V20Z"; DefaultChecked = $true },
            @{ Name = "Disable in Entra ID"; Icon = "M12,5.5A3.5,3.5 0 0,1 15.5,9A3.5,3.5 0 0,1 12,12.5A3.5,3.5 0 0,1 8.5,9A3.5,3.5 0 0,1 12,5.5M5,8C5.56,8 6.08,8.15 6.53,8.42C6.38,9.85 6.8,11.27 7.66,12.38C7.16,13.34 6.16,14 5,14A3,3 0 0,1 2,11A3,3 0 0,1 5,8M19,8A3,3 0 0,1 22,11A3,3 0 0,1 19,14C17.84,14 16.84,13.34 16.34,12.38C17.2,11.27 17.62,9.85 17.47,8.42C17.92,8.15 18.44,8 19,8M5.5,18.25C5.5,16.18 8.41,14.5 12,14.5C15.59,14.5 18.5,16.18 18.5,18.25V20H5.5V18.25M0,20V18.5C0,17.11 1.89,15.94 4.45,15.6C3.86,16.28 3.5,17.22 3.5,18.25V20H0M24,20H20.5V18.25C20.5,17.22 20.14,16.28 19.55,15.6C22.11,15.94 24,17.11 24,18.5V20Z"; DefaultChecked = $false },
            @{ Name = "Intune"; Icon = "M21,14V4H3V14H21M21,2A2,2 0 0,1 23,4V16A2,2 0 0,1 21,18H14L16,21V22H8V21L10,18H3C1.89,18 1,17.1 1,16V4C1,2.89 1.89,2 3,2H21M4,5H20V13H4V5Z"; DefaultChecked = $true },
            @{ Name = "Autopilot"; Icon = "M12,3L1,9L12,15L21,10.09V17H23V9M5,13.18V17.18L12,21L19,17.18V13.18L12,17L5,13.18Z"; DefaultChecked = $true }
        )

        if (Get-DefenderIntegrationEnabled) {
            $services += @{ Name = "Defender for Endpoint"; Icon = "M12,1L3,5V11C3,16.55 6.84,21.74 12,23C17.16,21.74 21,16.55 21,11V5L12,1M12,3.18L19,6.3V11.22C19,15.54 16.18,19.5 12,20.93C7.82,19.5 5,15.54 5,11.22V6.3L12,3.18Z"; DefaultChecked = $false }
        }

        # Create hashtable to store checkbox references
        $script:serviceCheckboxes = @{}

        foreach ($service in $services) {
            $serviceItem = New-Object System.Windows.Controls.Border
            $serviceItem.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#F7FAFC"))
            $serviceItem.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#E2E8F0"))
            $serviceItem.BorderThickness = New-Object System.Windows.Thickness(1)
            $serviceItem.CornerRadius = New-Object System.Windows.CornerRadius(6)
            $serviceItem.Padding = New-Object System.Windows.Thickness(16, 12, 16, 12)
            $serviceItem.Margin = New-Object System.Windows.Thickness(0, 0, 12, 12)
            $serviceItem.MinWidth = 200

            $stackPanel = New-Object System.Windows.Controls.StackPanel
            $stackPanel.Orientation = "Horizontal"

            # Checkbox
            $checkbox = New-Object System.Windows.Controls.CheckBox
            $checkbox.IsChecked = $service.DefaultChecked
            $checkbox.VerticalAlignment = "Center"
            $checkbox.Margin = New-Object System.Windows.Thickness(0, 0, 12, 0)
            $script:serviceCheckboxes[$service.Name] = $checkbox

            # Icon
            $path = New-Object System.Windows.Shapes.Path
            $path.Data = [System.Windows.Media.Geometry]::Parse($service.Icon)
            $path.Fill = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#4A5568"))
            $path.Width = 24
            $path.Height = 24
            $path.Stretch = "Uniform"
            $path.Margin = New-Object System.Windows.Thickness(0, 0, 12, 0)
            $path.VerticalAlignment = "Center"

            # Service name
            $text = New-Object System.Windows.Controls.TextBlock
            $text.Text = $service.Name
            $text.FontSize = 14
            $text.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#2D3748"))
            $text.VerticalAlignment = "Center"

            $stackPanel.Children.Add($checkbox)
            $stackPanel.Children.Add($path)
            $stackPanel.Children.Add($text)
            $serviceItem.Child = $stackPanel
            $servicesList.Children.Add($serviceItem)
        }

        # Mutual exclusivity: "Entra ID" (delete) vs "Disable in Entra ID"
        $script:serviceCheckboxes["Entra ID"].Add_Checked({
            $script:serviceCheckboxes["Disable in Entra ID"].IsChecked = $false
        }.GetNewClosure())
        $script:serviceCheckboxes["Disable in Entra ID"].Add_Checked({
            $script:serviceCheckboxes["Entra ID"].IsChecked = $false
        }.GetNewClosure())

        # Add button handlers
        $cancelButton.Add_Click({
                $confirmationWindow.DialogResult = $false
                $confirmationWindow.Close()
            })

        $confirmButton.Add_Click({
                # Check if at least one service is selected
                $anyServiceSelected = $false
                foreach ($checkbox in $script:serviceCheckboxes.Values) {
                    if ($checkbox.IsChecked) {
                        $anyServiceSelected = $true
                        break
                    }
                }

                if (-not $anyServiceSelected) {
                    [System.Windows.MessageBox]::Show(
                        "Please select at least one service to remove the device(s) from.",
                        "No Service Selected",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    )
                    return
                }

                $confirmationWindow.DialogResult = $true
                $confirmationWindow.Close()
            })

        # Show dialog
        try {
            if ($null -eq $confirmationWindow) {
                throw "Confirmation window is null. Cannot show dialog."
            }
            $confirmationResult = $confirmationWindow.ShowDialog()
        }
        catch {
            Write-Log "Error showing confirmation dialog: $_"
            Show-Toast -Message "Failed to show the confirmation dialog: $_" -Type "error" -DurationSeconds 6
            return
        }
        if (-not $confirmationResult) {
            Write-Log "User canceled offboarding operation."
            return
        }

        # Capture pre-action selection (0=none, 1=retire, 2=wipe)
        $script:preAction = $preActionCombo.SelectedIndex
        if ($script:preAction -gt 0) {
            $preActionName = if ($script:preAction -eq 1) { "Retire" } else { "Wipe" }
            Write-Log "Pre-offboarding action selected: $preActionName" -Severity "AUDIT"
        }

        # Create results collection to track all operations
        $offboardingResults = @()
        $bulkAutopilotIds = @()

        try {
            # Determine which services are selected
            $disableEntra = $script:serviceCheckboxes.ContainsKey("Disable in Entra ID") -and $script:serviceCheckboxes["Disable in Entra ID"].IsChecked
            $deleteEntra = (-not $disableEntra) -and $script:serviceCheckboxes["Entra ID"].IsChecked
            $deleteIntune = $script:serviceCheckboxes["Intune"].IsChecked
            $deleteAutopilot = $script:serviceCheckboxes["Autopilot"].IsChecked
            $offboardMde = (Get-DefenderIntegrationEnabled) -and $script:serviceCheckboxes.ContainsKey("Defender for Endpoint") -and $script:serviceCheckboxes["Defender for Endpoint"].IsChecked

            # Resolve MDE device IDs if MDE offboarding is selected
            if ($offboardMde) {
                try {
                    $mdeToken = Get-MdeAccessToken
                    if ($mdeToken) {
                        foreach ($device in $selectedDevices) {
                            if ($device.EntraDeviceObjectId -and -not $device.MdeDeviceId) {
                                try {
                                    $mdeHeaders = @{ Authorization = "Bearer $mdeToken" }
                                    $mdeResponse = Invoke-RestMethod -Uri "https://api.security.microsoft.com/api/machines?`$filter=aadDeviceId eq '$($device.EntraDeviceObjectId)'" -Headers $mdeHeaders -Method GET
                                    if ($mdeResponse.value -and $mdeResponse.value.Count -gt 0) {
                                        $device.MdeDeviceId = $mdeResponse.value[0].id
                                        Write-Log "Resolved MDE device ID for $($device.DeviceName): $($device.MdeDeviceId)"
                                    }
                                } catch {
                                    Write-Log "Could not resolve MDE device ID for $($device.DeviceName): $_" -Severity "WARN"
                                }
                            }
                        }
                    } else {
                        Write-Log "Could not acquire MDE access token. MDE offboarding will be skipped." -Severity "WARN"
                        $offboardMde = $false
                    }
                } catch {
                    Write-Log "Error during MDE token acquisition: $_" -Severity "ERROR"
                    $offboardMde = $false
                }
            }

            # Collect serial numbers and Autopilot IDs for potential bulk deletion (2+ devices)
            $bulkAutopilotSerials = @()
            if ($deleteAutopilot) {
                $bulkAutopilotIds = @($selectedDevices | Where-Object { $_.AutopilotIdentityId } | ForEach-Object { $_.AutopilotIdentityId })
                $bulkAutopilotSerials = @($selectedDevices | Where-Object { $_.AutopilotIdentityId -and $_.SerialNumber } | ForEach-Object { $_.SerialNumber })
            }
            $useBulkAutopilot = $bulkAutopilotSerials.Count -ge 2

            foreach ($device in $selectedDevices) {
                $deviceName = $device.DeviceName
                $serialNumber = $device.SerialNumber
                $deviceResult = @{
                    DeviceName   = $deviceName
                    SerialNumber = $serialNumber
                    EntraID      = @{ Found = $false; Success = $false; Error = $null; Action = $null }
                    Intune       = @{ Found = $false; Success = $false; Error = $null }
                    Autopilot    = @{ Found = $false; Success = $false; Error = $null }
                    MDE          = @{ Found = $false; Success = $false; Error = $null }
                    PreAction    = @{ Action = $null; Success = $false; Error = $null }
                }

                Write-Log "Starting offboarding for device: $deviceName (Serial: $serialNumber, EntraId: $($device.EntraDeviceId), IntuneId: $($device.IntuneDeviceId), AutopilotId: $($device.AutopilotIdentityId))" -Severity "AUDIT"

                # Execute pre-offboarding action (retire/wipe) if selected
                if ($script:preAction -gt 0 -and $device.IntuneDeviceId) {
                    $preActionName = if ($script:preAction -eq 1) { "retire" } else { "wipe" }
                    $deviceResult.PreAction.Action = $preActionName
                    try {
                        $preActionUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($device.IntuneDeviceId)/$preActionName"
                        $preActionBody = if ($script:preAction -eq 2) { '{}' } else { $null }
                        if ($preActionBody) {
                            Invoke-MgGraphRequest -Uri $preActionUri -Method POST -Body $preActionBody -ContentType "application/json"
                        } else {
                            Invoke-MgGraphRequest -Uri $preActionUri -Method POST
                        }
                        $deviceResult.PreAction.Success = $true
                        Write-Log "Successfully executed $preActionName on device $deviceName (IntuneId: $($device.IntuneDeviceId))" -Severity "AUDIT"
                        Start-Sleep -Seconds 2
                    } catch {
                        $deviceResult.PreAction.Error = $_.Exception.Message
                        Write-Log "Error executing $preActionName on device $deviceName`: $_" -Severity "ERROR"
                        $continueChoice = [System.Windows.MessageBox]::Show(
                            "Failed to $preActionName device '$deviceName'. Continue with deletion?`n`nError: $($_.Exception.Message)",
                            "Pre-Action Failed",
                            [System.Windows.MessageBoxButton]::YesNo,
                            [System.Windows.MessageBoxImage]::Warning
                        )
                        if ($continueChoice -eq [System.Windows.MessageBoxResult]::No) {
                            $offboardingResults += $deviceResult
                            continue
                        }
                    }
                }

                # Execute MDE offboarding if selected
                if ($offboardMde -and $device.MdeDeviceId) {
                    $deviceResult.MDE.Found = $true
                    try {
                        $mdeHeaders = @{ Authorization = "Bearer $mdeToken"; "Content-Type" = "application/json" }
                        $mdeBody = @{ Comment = "Offboarded via DeviceOffboardingManager" } | ConvertTo-Json
                        Invoke-RestMethod -Uri "https://api.security.microsoft.com/api/machines/$($device.MdeDeviceId)/offboard" -Headers $mdeHeaders -Method POST -Body $mdeBody -ContentType "application/json"
                        $deviceResult.MDE.Success = $true
                        Write-Log "Successfully offboarded device $deviceName from MDE (MdeId: $($device.MdeDeviceId))" -Severity "AUDIT"
                    } catch {
                        $deviceResult.MDE.Error = $_.Exception.Message
                        Write-Log "Error offboarding device $deviceName from MDE: $_" -Severity "ERROR"
                    }
                } elseif ($offboardMde -and -not $device.MdeDeviceId) {
                    Write-Log "Skipping MDE offboarding for $deviceName - no MDE device ID resolved" -Severity "WARN"
                }

                # Build batch requests for this device
                $batchRequests = @()

                if ($disableEntra) {
                    if ($device.EntraDeviceId) {
                        $deviceResult.EntraID.Found = $true
                        $deviceResult.EntraID.Action = "Disabled"
                        $batchRequests += @{ id = "entra"; method = "PATCH"; url = "/devices/$($device.EntraDeviceId)"; body = @{ accountEnabled = $false }; headers = @{ "Content-Type" = "application/json" } }
                    } else {
                        Write-Log "Skipping Entra ID disable for $deviceName - no Entra Device ID resolved" -Severity "WARN"
                    }
                } elseif ($deleteEntra) {
                    if ($device.EntraDeviceId) {
                        $deviceResult.EntraID.Found = $true
                        $deviceResult.EntraID.Action = "Removed"
                        $batchRequests += @{ id = "entra"; method = "DELETE"; url = "/devices/$($device.EntraDeviceId)" }
                    } else {
                        Write-Log "Skipping Entra ID deletion for $deviceName - no Entra Device ID resolved" -Severity "WARN"
                    }
                } else {
                    Write-Log "Skipping Entra ID operation for device $deviceName (not selected)"
                }

                if ($deleteIntune) {
                    if ($device.IntuneDeviceId) {
                        $deviceResult.Intune.Found = $true
                        $batchRequests += @{ id = "intune"; method = "DELETE"; url = "/deviceManagement/managedDevices/$($device.IntuneDeviceId)" }
                    } else {
                        Write-Log "Skipping Intune deletion for $deviceName - no Intune Device ID resolved" -Severity "WARN"
                    }
                } else {
                    Write-Log "Skipping Intune removal for device $deviceName (not selected)"
                }

                # Include Autopilot in per-device batch only if not using bulk deletion
                if ($deleteAutopilot -and -not $useBulkAutopilot) {
                    if ($device.AutopilotIdentityId) {
                        $deviceResult.Autopilot.Found = $true
                        $batchRequests += @{ id = "autopilot"; method = "DELETE"; url = "/deviceManagement/windowsAutopilotDeviceIdentities/$($device.AutopilotIdentityId)" }
                    } else {
                        Write-Log "Skipping Autopilot deletion for $deviceName - no Autopilot Identity ID resolved" -Severity "WARN"
                    }
                } elseif ($deleteAutopilot -and $useBulkAutopilot) {
                    if ($device.AutopilotIdentityId) {
                        $deviceResult.Autopilot.Found = $true
                        # Will be handled by bulk deletion after the loop
                    } else {
                        Write-Log "Skipping Autopilot deletion for $deviceName - no Autopilot Identity ID resolved" -Severity "WARN"
                    }
                } else {
                    Write-Log "Skipping Autopilot removal for device $deviceName (not selected)"
                }

                # Execute batch if there are requests
                if ($batchRequests.Count -gt 0) {
                    try {
                        $batchResponses = Invoke-GraphBatchRequest -Requests $batchRequests

                        # Parse Entra response
                        $entraResp = $batchResponses | Where-Object { $_.id -eq "entra" }
                        if ($entraResp) {
                            if ($entraResp.status -in @(200, 204)) {
                                $deviceResult.EntraID.Success = $true
                                Write-Log "Successfully $($deviceResult.EntraID.Action.ToLower()) device $deviceName in Entra ID (ID: $($device.EntraDeviceId))" -Severity "AUDIT"
                            } elseif ($entraResp.status -eq 403 -and $entraResp.body.error.code -match 'multipleAdminApproval|protectedOperation') {
                                $deviceResult.EntraID.Error = "Requires Multi-Admin Approval"
                                Write-Log "Entra ID operation for $deviceName requires Multi-Admin Approval" -Severity "WARN"
                            } else {
                                $deviceResult.EntraID.Error = "HTTP $($entraResp.status)"
                                Write-Log "Error with Entra ID operation for $deviceName`: HTTP $($entraResp.status)" -Severity "ERROR"
                            }
                        }

                        # Parse Intune response
                        $intuneResp = $batchResponses | Where-Object { $_.id -eq "intune" }
                        if ($intuneResp) {
                            if ($intuneResp.status -in @(200, 204)) {
                                $deviceResult.Intune.Success = $true
                                Write-Log "Successfully removed device $deviceName from Intune (ID: $($device.IntuneDeviceId))" -Severity "AUDIT"
                            } elseif ($intuneResp.status -eq 403 -and $intuneResp.body.error.code -match 'multipleAdminApproval|protectedOperation') {
                                $deviceResult.Intune.Error = "Requires Multi-Admin Approval"
                                Write-Log "Intune operation for $deviceName requires Multi-Admin Approval" -Severity "WARN"
                            } else {
                                $deviceResult.Intune.Error = "HTTP $($intuneResp.status)"
                                Write-Log "Error removing device $deviceName from Intune: HTTP $($intuneResp.status)" -Severity "ERROR"
                            }
                        }

                        # Parse Autopilot response (only if not using bulk)
                        $autopilotResp = $batchResponses | Where-Object { $_.id -eq "autopilot" }
                        if ($autopilotResp) {
                            if ($autopilotResp.status -in @(200, 204)) {
                                $deviceResult.Autopilot.Success = $true
                                Write-Log "Successfully removed device $deviceName from Autopilot (ID: $($device.AutopilotIdentityId))" -Severity "AUDIT"
                            } elseif ($autopilotResp.status -eq 403 -and $autopilotResp.body.error.code -match 'multipleAdminApproval|protectedOperation') {
                                $deviceResult.Autopilot.Error = "Requires Multi-Admin Approval"
                                Write-Log "Autopilot operation for $deviceName requires Multi-Admin Approval" -Severity "WARN"
                            } else {
                                $deviceResult.Autopilot.Error = "HTTP $($autopilotResp.status)"
                                Write-Log "Error removing device $deviceName from Autopilot: HTTP $($autopilotResp.status)" -Severity "ERROR"
                            }
                        }
                    }
                    catch {
                        Write-Log "Batch request failed for device $deviceName`: $_" -Severity "ERROR"
                        if ($deviceResult.EntraID.Found -and -not $deviceResult.EntraID.Success) { $deviceResult.EntraID.Error = $_.Exception.Message }
                        if ($deviceResult.Intune.Found -and -not $deviceResult.Intune.Success) { $deviceResult.Intune.Error = $_.Exception.Message }
                        if ($deviceResult.Autopilot.Found -and -not $deviceResult.Autopilot.Success) { $deviceResult.Autopilot.Error = $_.Exception.Message }
                    }
                }

                $offboardingResults += $deviceResult
                Write-Log "Completed offboarding attempt for device: $deviceName" -Severity "AUDIT"
            }

            # Bulk Autopilot deletion when 2+ devices have serial numbers
            if ($useBulkAutopilot -and $bulkAutopilotSerials.Count -ge 2) {
                Write-Log "Executing bulk Autopilot deletion for $($bulkAutopilotSerials.Count) devices by serial number" -Severity "AUDIT"
                try {
                    $bulkBody = @{
                        serialNumbers = $bulkAutopilotSerials
                    } | ConvertTo-Json -Depth 5
                    $bulkResponse = Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/deleteDevices" -Method POST -Body $bulkBody -ContentType "application/json"

                    # Parse per-device deletion status from response
                    if ($bulkResponse.value) {
                        foreach ($deleteState in $bulkResponse.value) {
                            $matchingResult = $offboardingResults | Where-Object { $_.SerialNumber -eq $deleteState.serialNumber }
                            if ($matchingResult) {
                                if ($deleteState.deletionState -eq "failed") {
                                    $matchingResult.Autopilot.Error = $deleteState.errorMessage
                                    Write-Log "Bulk Autopilot deletion failed for serial $($deleteState.serialNumber): $($deleteState.errorMessage)" -Severity "ERROR"
                                } else {
                                    $matchingResult.Autopilot.Success = $true
                                }
                            }
                        }
                    } else {
                        # No detailed response -- set optimistic success
                        foreach ($result in $offboardingResults) {
                            if ($result.Autopilot.Found) {
                                $result.Autopilot.Success = $true
                            }
                        }
                    }
                    Write-Log "Bulk Autopilot deletion completed for $($bulkAutopilotSerials.Count) devices" -Severity "AUDIT"
                }
                catch {
                    Write-Log "Bulk Autopilot deletion failed: $_ -- falling back to individual deletion" -Severity "ERROR"
                    foreach ($result in $offboardingResults) {
                        if ($result.Autopilot.Found -and -not $result.Autopilot.Success) {
                            $matchingDevice = $selectedDevices | Where-Object { $_.DeviceName -eq $result.DeviceName -and $_.AutopilotIdentityId }
                            if ($matchingDevice) {
                                try {
                                    Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$($matchingDevice.AutopilotIdentityId)" -Method DELETE
                                    $result.Autopilot.Success = $true
                                    Write-Log "Successfully removed device $($result.DeviceName) from Autopilot (fallback)" -Severity "AUDIT"
                                }
                                catch {
                                    $result.Autopilot.Error = $_.Exception.Message
                                    Write-Log "Error removing device $($result.DeviceName) from Autopilot (fallback): $_" -Severity "ERROR"
                                }
                            }
                        }
                    }
                }
            }

            # Show summary of all operations
            Show-OffboardingSummary -Results $offboardingResults

            # Update UI status indicators if all operations were successful
            $allEntraSuccess = $offboardingResults | Where-Object { $_.EntraID.Found -and $_.EntraID.Success } | Measure-Object | Select-Object -ExpandProperty Count
            $allIntuneSuccess = $offboardingResults | Where-Object { $_.Intune.Found -and $_.Intune.Success } | Measure-Object | Select-Object -ExpandProperty Count
            $allAutopilotSuccess = $offboardingResults | Where-Object { $_.Autopilot.Found -and $_.Autopilot.Success } | Measure-Object | Select-Object -ExpandProperty Count

            $allEntraDisabled = $offboardingResults | Where-Object { $_.EntraID.Found -and $_.EntraID.Success -and $_.EntraID.Action -eq "Disabled" } | Measure-Object | Select-Object -ExpandProperty Count
            if ($allEntraDisabled -gt 0) {
                $Window.FindName('aad_status').Text = "Entra ID: Devices Disabled"
                $Window.FindName('aad_status').Foreground = "#ECC94B"
            }
            elseif ($allEntraSuccess -gt 0) {
                $Window.FindName('aad_status').Text = "Entra ID: Devices Removed"
                $Window.FindName('aad_status').Foreground = "#FC8181"
            }
            if ($allIntuneSuccess -gt 0) {
                $Window.FindName('intune_status').Text = "Intune: Devices Removed"
                $Window.FindName('intune_status').Foreground = "#FC8181"
            }
            if ($allAutopilotSuccess -gt 0) {
                $Window.FindName('autopilot_status').Text = "Autopilot: Devices Removed"
                $Window.FindName('autopilot_status').Foreground = "#FC8181"
            }
        }
        catch {
            Write-Log "Critical error in offboarding operation. Exception: $_"
            Show-Toast -Message "Critical error in offboarding operation. Please check the logs for details." -Type "error" -DurationSeconds 8
        }
    })

$ExportSearchResultsButton = $Window.FindName('ExportSearchResultsButton')

$ExportSearchResultsButton.Add_Click({
        $results = $SearchResultsDataGrid.ItemsSource
        if ($results -and $results.Count -gt 0) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $fileName = "Device_Search_Results_${timestamp}.csv"

            # Create a clean export list without UI-specific properties
            $exportData = @()
            foreach ($device in $results) {
                $exportData += [PSCustomObject]@{
                    DeviceName           = $device.DeviceName
                    SerialNumber         = $device.SerialNumber
                    OperatingSystem      = $device.OperatingSystem
                    PrimaryUser          = $device.PrimaryUser
                    ComplianceState      = $device.ComplianceState
                    EntraObjectId        = $device.EntraDeviceId
                    EntraDeviceId        = $device.EntraDeviceObjectId
                    IntuneDeviceId       = $device.IntuneDeviceId
                    AutopilotIdentityId  = $device.AutopilotIdentityId
                    AzureADLastContact   = $device.AzureADLastContact
                    IntuneLastContact    = $device.IntuneLastContact
                    AutopilotLastContact = $device.AutopilotLastContact
                }
            }

            Export-DeviceListToCSV -DeviceList $exportData -DefaultFileName $fileName
        }
        else {
            Show-Toast -Message "No search results to export." -Type "info"
        }
    })

$ExportSelectedButton = $Window.FindName('ExportSelectedButton')

$ExportSelectedButton.Add_Click({
        $selectedDevices = $SearchResultsDataGrid.ItemsSource | Where-Object { $_.IsSelected }
        if ($selectedDevices -and $selectedDevices.Count -gt 0) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $fileName = "Selected_Devices_${timestamp}.csv"

            # Create a clean export list with device names and relevant metadata
            $exportData = @()
            foreach ($device in $selectedDevices) {
                $exportData += [PSCustomObject]@{
                    DeviceName           = $device.DeviceName
                    SerialNumber         = $device.SerialNumber
                    OperatingSystem      = $device.OperatingSystem
                    PrimaryUser          = $device.PrimaryUser
                    ComplianceState      = $device.ComplianceState
                    EntraObjectId        = $device.EntraDeviceId
                    EntraDeviceId        = $device.EntraDeviceObjectId
                    IntuneDeviceId       = $device.IntuneDeviceId
                    AutopilotIdentityId  = $device.AutopilotIdentityId
                    AzureADLastContact   = $device.AzureADLastContact
                    IntuneLastContact    = $device.IntuneLastContact
                    AutopilotLastContact = $device.AutopilotLastContact
                }
            }

            Export-DeviceListToCSV -DeviceList $exportData -DefaultFileName $fileName
        }
        else {
            Show-Toast -Message "No devices selected to export." -Type "info"
        }
    })

$SetGroupTagButton = $Window.FindName('SetGroupTagButton')

$SetGroupTagButton.Add_Click({
            if ($AuthenticateButton.IsEnabled) {
                Show-Toast -Message "Please connect to Microsoft Graph first." -Type "info"
                return
            }

            $selectedDevices = @($SearchResultsDataGrid.ItemsSource | Where-Object { $_.IsSelected })
            if (-not $selectedDevices -or $selectedDevices.Count -eq 0) {
                Show-Toast -Message "Select at least one device first." -Type "info"
                return
            }

            $groupTagResult = Show-GroupTagDialog
            if (-not $groupTagResult) {
                return
            }

            $tagText = if ($groupTagResult.Clear) { "(cleared)" } else { $groupTagResult.GroupTag }
            Write-Log "Starting Autopilot group tag update for $($selectedDevices.Count) selected device(s): $tagText" -Severity "AUDIT"
            $SetGroupTagButton.IsEnabled = $false
            try {
                $result = Set-AutopilotGroupTagForDevices -Devices $selectedDevices -GroupTag $groupTagResult.GroupTag
                if ($result.Failed -gt 0) {
                    Show-Toast -Message "Group tag updated for $($result.Updated) device(s), failed for $($result.Failed). Check logs." -Type "warning" -DurationSeconds 7
                }
                else {
                    Show-Toast -Message "Group tag updated for $($result.Updated) device(s)." -Type "success"
                }
            }
            catch {
                Write-Log "Group tag update failed: $_" -Severity "ERROR"
                Show-Toast -Message "Group tag update failed. Check logs." -Type "error" -DurationSeconds 6
            }
            finally {
                $selectedDevices = @($SearchResultsDataGrid.ItemsSource | Where-Object { $_.IsSelected })
                $SetGroupTagButton.IsEnabled = ($selectedDevices.Count -gt 0)
            }
        })

$PrerequisitesButton.Add_Click({
        Show-PrerequisitesDialog
    })

$logs_button.Add_Click({
        if (Test-Path $script:LogDirectory) {
            Invoke-Item $script:LogDirectory
        }
        else {
            Show-Toast -Message "Log directory not found." -Type "info"
        }
    })

$MenuHome = $Window.FindName('MenuHome')

$MenuDashboard = $Window.FindName('MenuDashboard')

$MenuDeviceManagement = $Window.FindName('MenuDeviceManagement')

$MenuPlaybooks = $Window.FindName('MenuPlaybooks')

$HomePage = $Window.FindName('HomePage')

$DashboardPage = $Window.FindName('DashboardPage')

$DeviceManagementPage = $Window.FindName('DeviceManagementPage')

$PlaybooksPage = $Window.FindName('PlaybooksPage')

$PlaybookResultsGrid = $Window.FindName('PlaybookResultsGrid')

$PlaybookResultsDataGrid = $Window.FindName('PlaybookResultsDataGrid')

$HomeConnectButton = $Window.FindName('HomeConnectButton')

$HomeGetStartedTitle = $Window.FindName('HomeGetStartedTitle')

$HomeGetStartedDesc = $Window.FindName('HomeGetStartedDesc')

$HomeNavDashboard = $Window.FindName('HomeNavDashboard')

$HomeNavDeviceMgmt = $Window.FindName('HomeNavDeviceMgmt')

$HomeNavPlaybooks = $Window.FindName('HomeNavPlaybooks')

$HomeConnectButton.Add_Click({
        $AuthenticateButton.RaiseEvent(
            (New-Object System.Windows.RoutedEventArgs(
                [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    })

$HomeNavDashboard.Add_Click({ $MenuDashboard.IsChecked = $true })

$HomeNavDeviceMgmt.Add_Click({ $MenuDeviceManagement.IsChecked = $true })

$HomeNavPlaybooks.Add_Click({ $MenuPlaybooks.IsChecked = $true })

$Window.Add_Loaded({
        # Set initial page visibility
        $HomePage.Visibility = 'Visible'
        $DashboardPage.Visibility = 'Collapsed'
        $DeviceManagementPage.Visibility = 'Collapsed'
        $PlaybooksPage.Visibility = 'Collapsed'
        $PlaybookResultsGrid.Visibility = 'Collapsed'
    })

$MenuHome.Add_Checked({
        $HomePage.Visibility = 'Visible'
        $DashboardPage.Visibility = 'Collapsed'
        $DeviceManagementPage.Visibility = 'Collapsed'
        $PlaybooksPage.Visibility = 'Collapsed'
        $PlaybookResultsGrid.Visibility = 'Collapsed'
    })

$MenuDashboard.Add_Checked({
        $HomePage.Visibility = 'Collapsed'
        $DashboardPage.Visibility = 'Visible'
        $DeviceManagementPage.Visibility = 'Collapsed'
        $PlaybooksPage.Visibility = 'Collapsed'
        $PlaybookResultsGrid.Visibility = 'Collapsed'

        # Update dashboard statistics if connected
        if (-not $AuthenticateButton.IsEnabled) {
            Update-DashboardStatistics
            $DashboardLastRefreshed.Text = "Last refreshed: $(Get-Date -Format 'HH:mm:ss')"
        }
    })

$MenuDeviceManagement.Add_Checked({
        $HomePage.Visibility = 'Collapsed'
        $DashboardPage.Visibility = 'Collapsed'
        $DeviceManagementPage.Visibility = 'Visible'
        $PlaybooksPage.Visibility = 'Collapsed'
        $PlaybookResultsGrid.Visibility = 'Collapsed'
        # Auto-focus search input
        $Window.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [Action]{ if ($SearchInputText.Focus()) { $SearchInputText.SelectAll() } }
        )
    })

$MenuPlaybooks.Add_Checked({
        $HomePage.Visibility = 'Collapsed'
        $DashboardPage.Visibility = 'Collapsed'
        $DeviceManagementPage.Visibility = 'Collapsed'
        $PlaybooksPage.Visibility = 'Visible'
        $PlaybookResultsGrid.Visibility = 'Collapsed'
        $Window.FindName('PlaybooksScrollViewer').Visibility = 'Visible'
    })

$Window.Add_PreviewKeyDown({
    param($sender, $e)
    # Ctrl+K: Navigate to Device Offboarding and focus search
    if ($e.Key -eq [System.Windows.Input.Key]::K -and
        ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        if ($MenuDeviceManagement.IsEnabled) {
            $e.Handled = $true
            if ($MenuDeviceManagement.IsChecked) {
                $SearchInputText.Focus()
                $SearchInputText.SelectAll()
            } else {
                $MenuDeviceManagement.IsChecked = $true
            }
        }
    }
    # Ctrl+B: Toggle sidebar
    if ($e.Key -eq [System.Windows.Input.Key]::B -and
        ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        $e.Handled = $true
        Set-SidebarState -Collapsed (-not $script:SidebarCollapsed)
    }
    # F5: Refresh dashboard when on Dashboard page
    if ($e.Key -eq [System.Windows.Input.Key]::F5) {
        if ($MenuDashboard.IsChecked -and $DashboardRefreshButton.IsEnabled) {
            $e.Handled = $true
            $DashboardRefreshButton.RaiseEvent(
                (New-Object System.Windows.RoutedEventArgs(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        }
    }
    # Escape: dismiss toast, collapse filter, clear search (contextual)
    if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
        # First priority: dismiss visible toast
        if ($ToastNotification.Visibility -eq 'Visible') {
            $e.Handled = $true
            Hide-Toast
        }
        # Second: collapse filter row if open
        elseif ($FilterRow.Visibility -eq 'Visible') {
            $e.Handled = $true
            $FilterRow.Visibility = 'Collapsed'
            $FilterToggleButton.Content = 'Filter'
        }
        # Third: clear search if search input has text and is on device management page
        elseif ($MenuDeviceManagement.IsChecked -and -not [string]::IsNullOrEmpty($SearchInputText.Text)) {
            $e.Handled = $true
            $ClearSearchButton.RaiseEvent(
                (New-Object System.Windows.RoutedEventArgs(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        }
    }
})

$DashboardPlatformFilter = $Window.FindName('DashboardPlatformFilter')

$DashboardPlatformFilter.Add_SelectionChanged({
        if (-not $AuthenticateButton.IsEnabled) {
            $selected = $DashboardPlatformFilter.SelectedItem.Content
            Update-DashboardStatistics -Platform $selected
        }
    })

$DashboardRefreshButton = $Window.FindName('DashboardRefreshButton')

$DashboardLastRefreshed = $Window.FindName('DashboardLastRefreshed')

$DashboardRefreshButton.Add_Click({
        if (-not $AuthenticateButton.IsEnabled) {
            $DashboardRefreshButton.Content = "Refreshing..."
            $DashboardRefreshButton.IsEnabled = $false
            $Window.Cursor = [System.Windows.Input.Cursors]::Wait
            $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action]{})
            try {
                $selected = $DashboardPlatformFilter.SelectedItem.Content
                Update-DashboardStatistics -Platform $selected
                $DashboardLastRefreshed.Text = "Last refreshed: $(Get-Date -Format 'HH:mm:ss')"
            } finally {
                $DashboardRefreshButton.Content = "Refresh"
                $DashboardRefreshButton.IsEnabled = $true
                $Window.Cursor = $null
            }
        }
    })

$PlaybookButtons = @(
    $Window.FindName('PlaybookAutopilotNotIntune'),
    $Window.FindName('PlaybookIntuneNotAutopilot'),
    $Window.FindName('PlaybookCorporateDevices'),
    $Window.FindName('PlaybookPersonalDevices'),
    $Window.FindName('PlaybookStaleDevices'),
    $Window.FindName('PlaybookSpecificOS'),
    $Window.FindName('PlaybookNotLatestOS'),
    $Window.FindName('PlaybookEOLOS'),
    $Window.FindName('PlaybookBitLocker'),
    $Window.FindName('PlaybookFileVault'),
    $Window.FindName('PlaybookCorporateIdentifiers')
)

foreach ($button in $PlaybookButtons) {
    $button.Add_Click({
            if ($AuthenticateButton.IsEnabled) {
                Show-Toast -Message "Please connect to Microsoft Graph first." -Type "info"
                return
            }
            $playbookName = $this.Content.ToString()
            $playbookDescription = $this.Tag.ToString()

            switch ($playbookName) {
                "Autopilot Devices Not in Intune" {
                    $playbookPath = Join-Path $script:DeviceOffboardingManagerPlaybookRoot "Playbook_1.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "Intune Devices Not in Autopilot" {
                    $playbookPath = Join-Path $script:DeviceOffboardingManagerPlaybookRoot "Playbook_2.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "Corporate Device Inventory" {
                    $playbookPath = Join-Path $script:DeviceOffboardingManagerPlaybookRoot "Playbook_3.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "Personal Device Inventory" {
                    $playbookPath = Join-Path $script:DeviceOffboardingManagerPlaybookRoot "Playbook_4.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "Stale Device Report" {
                    $playbookPath = Join-Path $script:DeviceOffboardingManagerPlaybookRoot "Playbook_5.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "OS-Specific Device List" {
                    $selectedOS = Show-OSPickerDialog
                    if ($selectedOS) {
                        $playbookPath = Join-Path $script:DeviceOffboardingManagerPlaybookRoot "Playbook_6.ps1"
                        Invoke-Playbook -PlaybookName "$playbookName ($selectedOS)" -PlaybookPath $playbookPath -Description $playbookDescription -Parameters @{ OSFilter = $selectedOS }
                    }
                }
                "Outdated OS Report" {
                    $playbookPath = Join-Path $script:DeviceOffboardingManagerPlaybookRoot "Playbook_7.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "End-of-Life OS Report" {
                    $playbookPath = Join-Path $script:DeviceOffboardingManagerPlaybookRoot "Playbook_8.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "BitLocker Key Report" {
                    $playbookPath = Join-Path $script:DeviceOffboardingManagerPlaybookRoot "Playbook_9.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "FileVault Key Report" {
                    $playbookPath = Join-Path $script:DeviceOffboardingManagerPlaybookRoot "Playbook_10.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "Corporate Identifier Stale Report" {
                    $playbookPath = Join-Path $script:DeviceOffboardingManagerPlaybookRoot "Playbook_11.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                default {
                    Show-Toast -Message "This playbook is not yet implemented." -Type "info"
                }
            }
        })
}

$SearchResultsDataGrid = $Window.FindName('SearchResultsDataGrid')

$OffboardButton = $Window.FindName('OffboardButton')

$ExportSelectedButton = $Window.FindName('ExportSelectedButton')

$SetGroupTagButton = $Window.FindName('SetGroupTagButton')

$SelectAllCheckBox = New-Object System.Windows.Controls.CheckBox

$SelectAllCheckBox.Content = "Select All"

($SearchResultsDataGrid.Columns[0]).Header = $SelectAllCheckBox

$SelectAllCheckBox.Add_Click({
        $allChecked = $SelectAllCheckBox.IsChecked
        if ($SearchResultsDataGrid.ItemsSource) {
            foreach ($device in $SearchResultsDataGrid.ItemsSource) {
                $device.IsSelected = $allChecked
            }
            # Update button states
            $OffboardButton.IsEnabled = $allChecked
            $ExportSelectedButton.IsEnabled = $allChecked
            $SetGroupTagButton.IsEnabled = $allChecked
            if ($allChecked) {
                $count = @($SearchResultsDataGrid.ItemsSource).Count
                $SelectedDeviceCount.Text = "$count device(s) selected"
                $OffboardPanel.Visibility = 'Visible'
            } else {
                $OffboardPanel.Visibility = 'Collapsed'
            }
        }
    })

$OffboardButton.IsEnabled = $false

$ExportSelectedButton.IsEnabled = $false

$SetGroupTagButton.IsEnabled = $false

$SearchResultsDataGrid.Add_PreviewMouseDown({
        param($sender, $e)
        $element = $e.OriginalSource
        # Walk up the visual tree to find the TextBlock with Tag
        while ($element -and -not ($element -is [System.Windows.Controls.TextBlock] -and $element.Text -eq "View" -and $element.Tag)) {
            $element = [System.Windows.Media.VisualTreeHelper]::GetParent($element)
            if (-not $element -or $element -is [System.Windows.Controls.DataGrid]) { $element = $null; break }
        }
        if ($element -and $element.Tag) {
            $entraId = $element.Tag.ToString()
            if ($entraId) {
                # Find device name for display
                $deviceObj = $SearchResultsDataGrid.ItemsSource | Where-Object { $_.EntraDeviceId -eq $entraId } | Select-Object -First 1
                $devName = if ($deviceObj) { $deviceObj.DeviceName } else { "Device" }
                Show-DeviceGroupMembership -EntraDeviceId $entraId -DeviceName $devName
            } else {
                Show-Toast -Message "No Entra ID available for this device." -Type "info"
            }
        }
    })

$SearchResultsDataGrid.Add_SelectionChanged({
        # Update the Offboard button state based on selected devices
        $selectedDevices = $SearchResultsDataGrid.ItemsSource | Where-Object { $_.IsSelected }
        $hasSelection = ($null -ne $selectedDevices -and $selectedDevices.Count -gt 0)
        $OffboardButton.IsEnabled = $hasSelection
        $ExportSelectedButton.IsEnabled = $hasSelection
        $SetGroupTagButton.IsEnabled = $hasSelection
        if ($hasSelection) {
            $count = @($selectedDevices).Count
            $SelectedDeviceCount.Text = "$count device(s) selected"
            $OffboardPanel.Visibility = 'Visible'
        } else {
            $OffboardPanel.Visibility = 'Collapsed'
        }
    })

$SearchResultsDataGrid.Add_LoadingRow({
        param($sender, $e)
        $row = $e.Row
        $dataContext = $row.DataContext
        if ($dataContext -and $dataContext.GetType().Name -eq 'DeviceObject') {
            $dataContext.add_PropertyChanged({
                    param($sender, $e)
                    if ($e.PropertyName -eq 'IsSelected') {
                        # Update Select All checkbox state
                        if ($SearchResultsDataGrid.ItemsSource) {
                            $allSelected = -not ($SearchResultsDataGrid.ItemsSource | Where-Object { -not $_.IsSelected })
                            $SelectAllCheckBox.IsChecked = $allSelected
                        }

                        # Update Offboard button state and panel visibility
                        $selectedDevices = $SearchResultsDataGrid.ItemsSource | Where-Object { $_.IsSelected }
                        $hasSelection = ($null -ne $selectedDevices -and $selectedDevices.Count -gt 0)
                        $OffboardButton.IsEnabled = $hasSelection
                        $ExportSelectedButton.IsEnabled = $hasSelection
                        $SetGroupTagButton.IsEnabled = $hasSelection
                        if ($hasSelection) {
                            $count = @($selectedDevices).Count
                            $SelectedDeviceCount.Text = "$count device(s) selected"
                            $OffboardPanel.Visibility = 'Visible'
                        } else {
                            $OffboardPanel.Visibility = 'Collapsed'
                        }
                    }
                })
        }
    })

$BackToPlaybooksButton = $Window.FindName('BackToPlaybooksButton')

$BackToPlaybooksButton.Add_Click({
        $Window.FindName('PlaybooksScrollViewer').Visibility = 'Visible'
        $PlaybookResultsGrid.Visibility = 'Collapsed'
        $PlaybookResultsDataGrid.ItemsSource = $null
    })

$ExportPlaybookResultsButton = $Window.FindName('ExportPlaybookResultsButton')

$ExportPlaybookResultsButton.Add_Click({
        $results = $PlaybookResultsDataGrid.ItemsSource
        if ($results -and $results.Count -gt 0) {
            $playbookName = $Window.FindName('PlaybookResultsHeader').Text
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $fileName = "Playbook_Results_${timestamp}.csv"
            Export-DeviceListToCSV -DeviceList $results -DefaultFileName $fileName
        }
        else {
            Show-Toast -Message "No results to export." -Type "info"
        }
    })

$StaleDevices30Card = $Window.FindName('StaleDevices30Card')

$StaleDevices30Card.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Write-Log "Fetching 30-day stale devices..."
                $thirtyDaysAgo = (Get-Date).AddDays(-30)
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=lastSyncDateTime lt $($thirtyDaysAgo.ToString('yyyy-MM-ddTHH:mm:ssZ'))&`$select=deviceName,serialNumber,lastSyncDateTime,operatingSystem,osVersion,userPrincipalName,managedDeviceOwnerType"
                $staleDevices = Get-GraphPagedResults -Uri $uri

                # Ensure we have a valid array
                if ($null -eq $staleDevices) { $staleDevices = @() }


                $deviceList = @()
                foreach ($device in $staleDevices) {
                    $deviceList += [PSCustomObject]@{
                        DeviceName      = $device.deviceName
                        SerialNumber    = $device.serialNumber
                        LastContact     = if ($device.lastSyncDateTime) {
                            $date = ConvertTo-SafeDateTime -dateString $device.lastSyncDateTime
                            if ($date) { $date.ToString('yyyy-MM-dd HH:mm') } else { "Never" }
                        }
                        else { "Never" }
                        OperatingSystem = $device.operatingSystem
                        OSVersion       = $device.osVersion
                        PrimaryUser     = $device.userPrincipalName
                        Ownership       = $device.managedDeviceOwnerType
                    }
                }

                $title = "30 Day Stale Devices"

                Show-DashboardCardResults -Title $title -DeviceList $deviceList
            }
            catch {
                Write-Log "Error fetching stale devices: $_"
                Show-Toast -Message "Error fetching stale devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

$StaleDevices90Card = $Window.FindName('StaleDevices90Card')

$StaleDevices90Card.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Write-Log "Fetching 90-day stale devices..."
                $ninetyDaysAgo = (Get-Date).AddDays(-90)
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=lastSyncDateTime lt $($ninetyDaysAgo.ToString('yyyy-MM-ddTHH:mm:ssZ'))&`$select=deviceName,serialNumber,lastSyncDateTime,operatingSystem,osVersion,userPrincipalName,managedDeviceOwnerType"
                $staleDevices = Get-GraphPagedResults -Uri $uri

                if ($null -eq $staleDevices) { $staleDevices = @() }

                $deviceList = @()
                foreach ($device in $staleDevices) {
                    $deviceList += [PSCustomObject]@{
                        DeviceName      = $device.deviceName
                        SerialNumber    = $device.serialNumber
                        LastContact     = if ($device.lastSyncDateTime) {
                            $date = ConvertTo-SafeDateTime -dateString $device.lastSyncDateTime
                            if ($date) { $date.ToString('yyyy-MM-dd HH:mm') } else { "Never" }
                        }
                        else { "Never" }
                        OperatingSystem = $device.operatingSystem
                        OSVersion       = $device.osVersion
                        PrimaryUser     = $device.userPrincipalName
                        Ownership       = $device.managedDeviceOwnerType
                    }
                }

                $title = "90 Day Stale Devices"

                Show-DashboardCardResults -Title $title -DeviceList $deviceList
            }
            catch {
                Write-Log "Error fetching stale devices: $_"
                Show-Toast -Message "Error fetching stale devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

$StaleDevices180Card = $Window.FindName('StaleDevices180Card')

$StaleDevices180Card.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Write-Log "Fetching 180-day stale devices..."
                $hundredEightyDaysAgo = (Get-Date).AddDays(-180)
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=lastSyncDateTime lt $($hundredEightyDaysAgo.ToString('yyyy-MM-ddTHH:mm:ssZ'))&`$select=deviceName,serialNumber,lastSyncDateTime,operatingSystem,osVersion,userPrincipalName,managedDeviceOwnerType"
                $staleDevices = Get-GraphPagedResults -Uri $uri

                if ($null -eq $staleDevices) { $staleDevices = @() }

                $deviceList = @()
                foreach ($device in $staleDevices) {
                    $deviceList += [PSCustomObject]@{
                        DeviceName      = $device.deviceName
                        SerialNumber    = $device.serialNumber
                        LastContact     = if ($device.lastSyncDateTime) {
                            $date = ConvertTo-SafeDateTime -dateString $device.lastSyncDateTime
                            if ($date) { $date.ToString('yyyy-MM-dd HH:mm') } else { "Never" }
                        }
                        else { "Never" }
                        OperatingSystem = $device.operatingSystem
                        OSVersion       = $device.osVersion
                        PrimaryUser     = $device.userPrincipalName
                        Ownership       = $device.managedDeviceOwnerType
                    }
                }

                $title = "180 Day Stale Devices"

                Show-DashboardCardResults -Title $title -DeviceList $deviceList
            }
            catch {
                Write-Log "Error fetching stale devices: $_"
                Show-Toast -Message "Error fetching stale devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

$PersonalDevicesCard = $Window.FindName('PersonalDevicesCard')

$PersonalDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Write-Log "Fetching personal devices..."
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=managedDeviceOwnerType eq 'personal'&`$select=deviceName,serialNumber,lastSyncDateTime,operatingSystem,osVersion,userPrincipalName,managedDeviceOwnerType"
                $personalDevices = Get-GraphPagedResults -Uri $uri

                $deviceList = @()
                foreach ($device in $personalDevices) {
                    $deviceList += [PSCustomObject]@{
                        DeviceName      = $device.deviceName
                        SerialNumber    = $device.serialNumber
                        LastContact     = if ($device.lastSyncDateTime) {
                            $date = ConvertTo-SafeDateTime -dateString $device.lastSyncDateTime
                            if ($date) { $date.ToString('yyyy-MM-dd HH:mm') } else { "Never" }
                        }
                        else { "Never" }
                        OperatingSystem = $device.operatingSystem
                        OSVersion       = $device.osVersion
                        PrimaryUser     = $device.userPrincipalName
                        Ownership       = "Personal"
                    }
                }

                $title = "Personal Devices"

                Show-DashboardCardResults -Title $title -DeviceList $deviceList
            }
            catch {
                Write-Log "Error fetching personal devices: $_"
                Show-Toast -Message "Error fetching personal devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

$CorporateDevicesCard = $Window.FindName('CorporateDevicesCard')

$CorporateDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Write-Log "Fetching corporate devices..."
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=managedDeviceOwnerType eq 'company'&`$select=deviceName,serialNumber,lastSyncDateTime,operatingSystem,osVersion,userPrincipalName,managedDeviceOwnerType"
                $corporateDevices = Get-GraphPagedResults -Uri $uri

                $deviceList = @()
                foreach ($device in $corporateDevices) {
                    $deviceList += [PSCustomObject]@{
                        DeviceName      = $device.deviceName
                        SerialNumber    = $device.serialNumber
                        LastContact     = if ($device.lastSyncDateTime) {
                            $date = ConvertTo-SafeDateTime -dateString $device.lastSyncDateTime
                            if ($date) { $date.ToString('yyyy-MM-dd HH:mm') } else { "Never" }
                        }
                        else { "Never" }
                        OperatingSystem = $device.operatingSystem
                        OSVersion       = $device.osVersion
                        PrimaryUser     = $device.userPrincipalName
                        Ownership       = "Corporate"
                    }
                }

                $title = "Corporate Devices"

                Show-DashboardCardResults -Title $title -DeviceList $deviceList
            }
            catch {
                Write-Log "Error fetching corporate devices: $_"
                Show-Toast -Message "Error fetching corporate devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

$IntuneDevicesCard = $Window.FindName('IntuneDevicesCard')

$IntuneDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Write-Log "Fetching all Intune devices..."
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=deviceName,serialNumber,lastSyncDateTime,operatingSystem,osVersion,userPrincipalName,managedDeviceOwnerType"
                $intuneDevices = Get-GraphPagedResults -Uri $uri

                $deviceList = @()
                foreach ($device in $intuneDevices) {
                    $deviceList += [PSCustomObject]@{
                        DeviceName      = $device.deviceName
                        SerialNumber    = $device.serialNumber
                        LastContact     = if ($device.lastSyncDateTime) {
                            $date = ConvertTo-SafeDateTime -dateString $device.lastSyncDateTime
                            if ($date) { $date.ToString('yyyy-MM-dd HH:mm') } else { "Never" }
                        }
                        else { "Never" }
                        OperatingSystem = $device.operatingSystem
                        OSVersion       = $device.osVersion
                        PrimaryUser     = $device.userPrincipalName
                        Ownership       = $device.managedDeviceOwnerType
                    }
                }

                $title = "All Intune Devices"

                Show-DashboardCardResults -Title $title -DeviceList $deviceList
            }
            catch {
                Write-Log "Error fetching Intune devices: $_"
                Show-Toast -Message "Error fetching Intune devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

$AutopilotDevicesCard = $Window.FindName('AutopilotDevicesCard')

$AutopilotDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Write-Log "Fetching all Autopilot devices..."
                $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
                $autopilotDevices = Get-GraphPagedResults -Uri $uri

                $deviceList = @()
                foreach ($device in $autopilotDevices) {
                    $deviceList += [PSCustomObject]@{
                        DeviceName      = $device.displayName
                        SerialNumber    = $device.serialNumber
                        LastContact     = if ($device.lastContactedDateTime) {
                            $date = ConvertTo-SafeDateTime -dateString $device.lastContactedDateTime
                            if ($date) { $date.ToString('yyyy-MM-dd HH:mm') } else { "N/A" }
                        }
                        else { "N/A" }
                        OperatingSystem = "Windows"
                        OSVersion       = $device.systemFamily
                        PrimaryUser     = $device.userPrincipalName
                        Ownership       = $device.managedDeviceOwnerType
                    }
                }

                $title = "All Autopilot Devices"

                Show-DashboardCardResults -Title $title -DeviceList $deviceList
            }
            catch {
                Write-Log "Error fetching Autopilot devices: $_"
                Show-Toast -Message "Error fetching Autopilot devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

$EntraIDDevicesCard = $Window.FindName('EntraIDDevicesCard')

$EntraIDDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Write-Log "Fetching all Entra ID devices..."
                $uri = "https://graph.microsoft.com/beta/devices?`$select=displayName,operatingSystem,operatingSystemVersion,approximateLastSignInDateTime,deviceOwnership"
                $entraDevices = Get-GraphPagedResults -Uri $uri

                $deviceList = @()
                foreach ($device in $entraDevices) {
                    $deviceList += [PSCustomObject]@{
                        DeviceName      = $device.displayName
                        SerialNumber    = "N/A"
                        LastContact     = if ($device.approximateLastSignInDateTime) {
                            $date = ConvertTo-SafeDateTime -dateString $device.approximateLastSignInDateTime
                            if ($date) { $date.ToString('yyyy-MM-dd HH:mm') } else { "Never" }
                        }
                        else { "Never" }
                        OperatingSystem = $device.operatingSystem
                        OSVersion       = $device.operatingSystemVersion
                        PrimaryUser     = "N/A"
                        Ownership       = if ($device.deviceOwnership) { $device.deviceOwnership } else { "N/A" }
                    }
                }

                $title = "All Entra ID Devices"

                Show-DashboardCardResults -Title $title -DeviceList $deviceList
            }
            catch {
                Write-Log "Error fetching Entra ID devices: $_"
                Show-Toast -Message "Error fetching Entra ID devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

$changelog_button = $Window.FindName('changelog_button')

$changelog_button.Add_Click({
        Show-ChangelogDialog
    })

try {
    if ($null -eq $Window) {
        throw "Main window is null. Cannot start application."
    }
    $Window.ShowDialog() | Out-Null
}
catch {
    Write-Log "Error showing main window: $_"
    [System.Windows.MessageBox]::Show(
        "Failed to start the application. Error: $_",
        "Application Error",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    )
    throw
}
