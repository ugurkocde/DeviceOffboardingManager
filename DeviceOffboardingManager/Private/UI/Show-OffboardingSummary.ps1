function Show-OffboardingSummary {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Results
    )

    [xml]$summaryModalXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Offboarding Summary" Height="650" Width="900" WindowStartupLocation="CenterScreen" Background="#F8F9FA">
    <Border Background="White" CornerRadius="8" Margin="16">
        <DockPanel Margin="24">
            <!-- Header -->
            <StackPanel DockPanel.Dock="Top" Margin="0,0,0,24">
                <TextBlock Text="Offboarding Summary" FontSize="24" FontWeight="SemiBold" Foreground="#1A202C"/>
                <TextBlock x:Name="SummarySubtitle" Text="Results of the offboarding operation" Foreground="#4A5568" FontSize="14" Margin="0,8,0,0"/>
            </StackPanel>

            <!-- Close and Export Buttons -->
            <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,24,0,0">
                <Button x:Name="ExportReportButton" Content="Export Report" Width="130" Height="40"
                        Background="#1B2A47" Foreground="White" BorderThickness="0" Margin="0,0,12,0"
                        Cursor="Hand" ToolTip="Export a detailed HTML report of offboarding results">
                    <Button.Resources><Style TargetType="Border"><Setter Property="CornerRadius" Value="4"/></Style></Button.Resources>
                </Button>
                <Button x:Name="CloseButton" Content="Close" Width="120" Height="40"
                        Background="#0078D4" Foreground="White" BorderThickness="0"
                        IsCancel="True" Cursor="Hand"/>
            </StackPanel>

            <!-- Main Content ScrollViewer -->
            <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,0,0,16">
                <StackPanel>
                    <!-- MAA Info Banner -->
                    <Border x:Name="MAABanner" Background="#FFFBEB" BorderBrush="#FDE68A" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,16" Visibility="Collapsed">
                        <TextBlock Text="One or more actions require Multi-Admin Approval. A second administrator must approve in the Entra admin center." Foreground="#92400E" TextWrapping="Wrap" FontSize="13"/>
                    </Border>

                    <!-- Summary Statistics -->
                    <Border Background="#EDF2F7" BorderBrush="#E2E8F0" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,16">
                        <StackPanel>
                            <TextBlock Text="Summary Statistics" FontWeight="SemiBold" FontSize="16" Margin="0,0,0,12"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>

                                <StackPanel Grid.Column="0" Margin="0,0,16,0">
                                    <TextBlock x:Name="TotalDevicesText" FontSize="24" FontWeight="Bold" Foreground="#2D3748"/>
                                    <TextBlock Text="Total Devices" FontSize="12" Foreground="#718096"/>
                                </StackPanel>

                                <StackPanel Grid.Column="1" Margin="0,0,16,0">
                                    <TextBlock x:Name="SuccessfulText" FontSize="24" FontWeight="Bold" Foreground="#48BB78"/>
                                    <TextBlock Text="Successful" FontSize="12" Foreground="#718096"/>
                                </StackPanel>

                                <StackPanel Grid.Column="2" Margin="0,0,16,0">
                                    <TextBlock x:Name="PartialText" FontSize="24" FontWeight="Bold" Foreground="#ECC94B"/>
                                    <TextBlock Text="Partial Success" FontSize="12" Foreground="#718096"/>
                                </StackPanel>

                                <StackPanel Grid.Column="3">
                                    <TextBlock x:Name="FailedText" FontSize="24" FontWeight="Bold" Foreground="#F56565"/>
                                    <TextBlock Text="Failed" FontSize="12" Foreground="#718096"/>
                                </StackPanel>
                            </Grid>
                        </StackPanel>
                    </Border>

                    <!-- Detailed Results -->
                    <TextBlock Text="Detailed Results" FontWeight="SemiBold" FontSize="16" Margin="0,0,0,12"/>
                    <ItemsControl x:Name="ResultsList">
                        <ItemsControl.ItemTemplate>
                            <DataTemplate>
                                <Border Background="#F7FAFC" BorderBrush="#E2E8F0" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,12">
                                    <Grid>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <!-- Device Header -->
                                        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
                                            <TextBlock Text="{Binding DeviceName}" FontWeight="SemiBold" FontSize="14" Margin="0,0,12,0"/>
                                            <TextBlock Text="{Binding SerialNumber, StringFormat='Serial: {0}'}" FontSize="12" Foreground="#718096" VerticalAlignment="Center"/>
                                        </StackPanel>

                                        <!-- Pre-Action Result -->
                                        <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,8" Visibility="{Binding PreActionVisibility}">
                                            <TextBlock Text="Pre-Action: " FontWeight="Medium" FontSize="11"/>
                                            <TextBlock Text="{Binding PreActionStatus}" FontSize="11" Foreground="{Binding PreActionColor}"/>
                                        </StackPanel>

                                        <!-- Service Results -->
                                        <Grid Grid.Row="2">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="*"/>
                                            </Grid.ColumnDefinitions>

                                            <!-- Entra ID Result -->
                                            <StackPanel Grid.Column="0" Margin="0,0,16,0">
                                                <TextBlock Text="Entra ID" FontWeight="Medium" FontSize="12" Margin="0,0,0,4"/>
                                                <TextBlock x:Name="EntraStatus" Text="{Binding EntraIDStatus}" FontSize="11" Foreground="{Binding EntraIDColor}"/>
                                                <TextBlock Text="{Binding EntraIDError}" FontSize="10" Foreground="#F56565" TextWrapping="Wrap" Visibility="{Binding EntraIDErrorVisibility}"/>
                                            </StackPanel>

                                            <!-- Intune Result -->
                                            <StackPanel Grid.Column="1" Margin="0,0,16,0">
                                                <TextBlock Text="Intune" FontWeight="Medium" FontSize="12" Margin="0,0,0,4"/>
                                                <TextBlock x:Name="IntuneStatus" Text="{Binding IntuneStatus}" FontSize="11" Foreground="{Binding IntuneColor}"/>
                                                <TextBlock Text="{Binding IntuneError}" FontSize="10" Foreground="#F56565" TextWrapping="Wrap" Visibility="{Binding IntuneErrorVisibility}"/>
                                            </StackPanel>

                                            <!-- Autopilot Result -->
                                            <StackPanel Grid.Column="2" Margin="0,0,16,0">
                                                <TextBlock Text="Autopilot" FontWeight="Medium" FontSize="12" Margin="0,0,0,4"/>
                                                <TextBlock x:Name="AutopilotStatus" Text="{Binding AutopilotStatus}" FontSize="11" Foreground="{Binding AutopilotColor}"/>
                                                <TextBlock Text="{Binding AutopilotError}" FontSize="10" Foreground="#F56565" TextWrapping="Wrap" Visibility="{Binding AutopilotErrorVisibility}"/>
                                            </StackPanel>

                                            <!-- MDE Result -->
                                            <StackPanel Grid.Column="3" Visibility="{Binding MDEVisibility}">
                                                <TextBlock Text="Defender" FontWeight="Medium" FontSize="12" Margin="0,0,0,4"/>
                                                <TextBlock Text="{Binding MDEStatus}" FontSize="11" Foreground="{Binding MDEColor}"/>
                                                <TextBlock Text="{Binding MDEError}" FontSize="10" Foreground="#F56565" TextWrapping="Wrap" Visibility="{Binding MDEErrorVisibility}"/>
                                            </StackPanel>
                                        </Grid>
                                    </Grid>
                                </Border>
                            </DataTemplate>
                        </ItemsControl.ItemTemplate>
                    </ItemsControl>
                </StackPanel>
            </ScrollViewer>
        </DockPanel>
    </Border>
</Window>
'@

    try {
        $reader = (New-Object System.Xml.XmlNodeReader $summaryModalXaml)
        $summaryWindow = [Windows.Markup.XamlReader]::Load($reader)

        if ($null -eq $summaryWindow) {
            throw "Failed to create summary window. XamlReader returned null."
        }
    }
    catch {
        Write-Log "Error creating summary window: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to create the summary dialog. Error: $_",
            "Dialog Creation Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return
    }

    # Get controls
    $closeButton = $summaryWindow.FindName('CloseButton')
    $exportReportButton = $summaryWindow.FindName('ExportReportButton')
    $totalDevicesText = $summaryWindow.FindName('TotalDevicesText')
    $successfulText = $summaryWindow.FindName('SuccessfulText')
    $partialText = $summaryWindow.FindName('PartialText')
    $failedText = $summaryWindow.FindName('FailedText')
    $resultsList = $summaryWindow.FindName('ResultsList')
    $maaBanner = $summaryWindow.FindName('MAABanner')

    # Calculate statistics
    $totalDevices = $Results.Count
    $successful = 0
    $partial = 0
    $failed = 0
    $hasMAA = $false

    # Check if MDE was selected
    $mdeSelected = $script:serviceCheckboxes -and $script:serviceCheckboxes.ContainsKey("Defender for Endpoint") -and $script:serviceCheckboxes["Defender for Endpoint"].IsChecked

    # Process results and create display objects
    $displayResults = @()

    foreach ($result in $Results) {
        $deviceSuccess = 0
        $deviceTotal = 0

        # Pre-compute skip flags and count successes outside PSCustomObject to avoid $deviceSuccess++ polluting the pipeline
        $entraIDSkipped = $script:serviceCheckboxes -and $script:serviceCheckboxes["Entra ID"] -and -not $script:serviceCheckboxes["Entra ID"].IsChecked -and -not ($script:serviceCheckboxes.ContainsKey("Disable in Entra ID") -and $script:serviceCheckboxes["Disable in Entra ID"].IsChecked)
        $intuneSkipped = $script:serviceCheckboxes -and $script:serviceCheckboxes["Intune"] -and -not $script:serviceCheckboxes["Intune"].IsChecked
        $autopilotSkipped = $script:serviceCheckboxes -and $script:serviceCheckboxes["Autopilot"] -and -not $script:serviceCheckboxes["Autopilot"].IsChecked

        if (-not $entraIDSkipped -and $result.EntraID.Found -and $result.EntraID.Success) { $deviceSuccess++ }
        if (-not $intuneSkipped -and $result.Intune.Found -and $result.Intune.Success) { $deviceSuccess++ }
        if (-not $autopilotSkipped -and $result.Autopilot.Found -and $result.Autopilot.Success) { $deviceSuccess++ }
        if ($mdeSelected -and $result.MDE.Found -and $result.MDE.Success) { $deviceSuccess++ }

        # Check for MAA errors
        if ($result.EntraID.Error -eq "Requires Multi-Admin Approval" -or $result.Intune.Error -eq "Requires Multi-Admin Approval" -or $result.Autopilot.Error -eq "Requires Multi-Admin Approval") {
            $hasMAA = $true
        }

        # Determine Entra ID action label
        $entraActionLabel = if ($result.EntraID.Action -eq "Disabled") { "Disabled" } else { "Removed" }

        # Pre-action display
        $preActionVis = "Collapsed"
        $preActionStatus = ""
        $preActionColor = "#718096"
        if ($result.PreAction -and $result.PreAction.Action) {
            $preActionVis = "Visible"
            $actionName = if ($result.PreAction.Action -eq "retire") { "Retire" } else { "Wipe" }
            if ($result.PreAction.Success) {
                $preActionStatus = "$actionName - Success"
                $preActionColor = "#48BB78"
            } else {
                $preActionStatus = "$actionName - Failed"
                $preActionColor = "#F56565"
            }
        }

        # Create display object for this device
        $displayResult = [PSCustomObject]@{
            DeviceName               = $result.DeviceName
            SerialNumber             = if ($result.SerialNumber) { $result.SerialNumber } else { "N/A" }

            # Pre-Action
            PreActionVisibility      = $preActionVis
            PreActionStatus          = $preActionStatus
            PreActionColor           = $preActionColor

            # Entra ID
            EntraIDStatus            = if ($entraIDSkipped) {
                "Skipped"
            }
            elseif ($result.EntraID.Found) {
                if ($result.EntraID.Success) { $entraActionLabel } else { "Failed" }
            }
            else { "Not Found" }
            EntraIDColor             = if ($entraIDSkipped) {
                "#A0AEC0"
            }
            elseif (!$result.EntraID.Found) { "#718096" } elseif ($result.EntraID.Success -and $result.EntraID.Action -eq "Disabled") { "#ECC94B" } elseif ($result.EntraID.Success) { "#48BB78" } else { "#F56565" }
            EntraIDError             = $result.EntraID.Error
            EntraIDErrorVisibility   = if ($result.EntraID.Error) { "Visible" } else { "Collapsed" }

            # Intune
            IntuneStatus             = if ($intuneSkipped) {
                "Skipped"
            }
            elseif ($result.Intune.Found) {
                if ($result.Intune.Success) { "Removed" } else { "Failed" }
            }
            else { "Not Found" }
            IntuneColor              = if ($intuneSkipped) {
                "#A0AEC0"
            }
            elseif (!$result.Intune.Found) { "#718096" } elseif ($result.Intune.Success) { "#48BB78" } else { "#F56565" }
            IntuneError              = $result.Intune.Error
            IntuneErrorVisibility    = if ($result.Intune.Error) { "Visible" } else { "Collapsed" }

            # Autopilot
            AutopilotStatus          = if ($autopilotSkipped) {
                "Skipped"
            }
            elseif ($result.Autopilot.Found) {
                if ($result.Autopilot.Success) { "Removed" } else { "Failed" }
            }
            else { "Not Found" }
            AutopilotColor           = if ($autopilotSkipped) {
                "#A0AEC0"
            }
            elseif (!$result.Autopilot.Found) { "#718096" } elseif ($result.Autopilot.Success) { "#48BB78" } else { "#F56565" }
            AutopilotError           = $result.Autopilot.Error
            AutopilotErrorVisibility = if ($result.Autopilot.Error) { "Visible" } else { "Collapsed" }

            # MDE
            MDEVisibility            = if ($mdeSelected) { "Visible" } else { "Collapsed" }
            MDEStatus                = if (-not $mdeSelected) { "Skipped" }
                                       elseif ($result.MDE.Found) {
                                           if ($result.MDE.Success) { "Offboarded" } else { "Failed" }
                                       } else { "Not Found" }
            MDEColor                 = if (-not $mdeSelected) { "#A0AEC0" }
                                       elseif (!$result.MDE.Found) { "#718096" }
                                       elseif ($result.MDE.Success) { "#48BB78" } else { "#F56565" }
            MDEError                 = $result.MDE.Error
            MDEErrorVisibility       = if ($result.MDE.Error) { "Visible" } else { "Collapsed" }
        }

        # Count total services device was found in (only for selected services)
        $entraSelected = ($script:serviceCheckboxes -and $script:serviceCheckboxes["Entra ID"] -and $script:serviceCheckboxes["Entra ID"].IsChecked) -or ($script:serviceCheckboxes -and $script:serviceCheckboxes.ContainsKey("Disable in Entra ID") -and $script:serviceCheckboxes["Disable in Entra ID"].IsChecked)
        if ($entraSelected -and $result.EntraID.Found) {
            $deviceTotal++
        }
        if ($script:serviceCheckboxes -and $script:serviceCheckboxes["Intune"] -and $script:serviceCheckboxes["Intune"].IsChecked -and $result.Intune.Found) {
            $deviceTotal++
        }
        if ($script:serviceCheckboxes -and $script:serviceCheckboxes["Autopilot"] -and $script:serviceCheckboxes["Autopilot"].IsChecked -and $result.Autopilot.Found) {
            $deviceTotal++
        }
        if ($mdeSelected -and $result.MDE.Found) {
            $deviceTotal++
        }

        # Categorize device result
        if ($deviceTotal -eq 0) {
            # Device not found in any selected service
            $failed++
        }
        elseif ($deviceSuccess -eq $deviceTotal) {
            # Successfully removed from all selected services where it was found
            $successful++
        }
        elseif ($deviceSuccess -gt 0) {
            # Partially successful
            $partial++
        }
        else {
            # Failed all operations
            $failed++
        }

        $displayResults += $displayResult
    }

    # Update statistics
    $totalDevicesText.Text = $totalDevices.ToString()
    $successfulText.Text = $successful.ToString()
    $partialText.Text = $partial.ToString()
    $failedText.Text = $failed.ToString()
    $summaryWindow.FindName('SummarySubtitle').Text = "Completed at $(Get-Date -Format 'HH:mm:ss on yyyy-MM-dd')"

    # Show MAA banner if needed
    if ($hasMAA) {
        $maaBanner.Visibility = 'Visible'
    }

    # Set results list
    $resultsList.ItemsSource = $displayResults

    # Export report button handler
    $exportReportButton.Add_Click({
            Export-OffboardingReport -Results $Results
        })

    # Close button handler
    $closeButton.Add_Click({
            $summaryWindow.Close()
        })

    # Show dialog
    try {
        if ($null -eq $summaryWindow) {
            throw "Summary window is null. Cannot show dialog."
        }
        $summaryWindow.ShowDialog() | Out-Null
    }
    catch {
        Write-Log "Error showing summary dialog: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to show the summary dialog. Error: $_",
            "Dialog Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}
