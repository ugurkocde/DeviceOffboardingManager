function Invoke-Playbook {
    param(
        [string]$PlaybookName,
        [string]$PlaybookPath,
        [string]$Description,
        [hashtable]$Parameters = @{}
    )

    try {
        Write-Log "Starting execution of playbook: $PlaybookName"

        # Show progress modal
        $progressWindow = Show-PlaybookProgressModal -PlaybookName $PlaybookName -Description $Description
        $status = $progressWindow.FindName('StatusMessage')
        $errorSection = $progressWindow.FindName('ErrorSection')
        $errorMessage = $progressWindow.FindName('ErrorMessage')
        $closeButton = $progressWindow.FindName('CloseButton')

        # Show the progress window and bring it to front
        $progressWindow.Show()
        $progressWindow.Activate()

        # Verify playbook exists locally
        $status.Text = "Loading playbook script..."
        Write-Log "Loading playbook from: $PlaybookPath"

        try {
            if (-not (Test-Path $PlaybookPath)) {
                throw "Playbook file not found: $PlaybookPath"
            }

            # Execute playbook
            $status.Text = "Executing playbook..."
            Write-Log "Executing playbook: $PlaybookPath"

            $rawResults = & $PlaybookPath @Parameters

            # Filter out only the actual device objects
            $results = $rawResults | Where-Object {
                $_ -and
                $_.PSObject.Properties['SerialNumber'] -and
                $_.SerialNumber -and
                -not $_.PSObject.Properties['ClassId2e4f51ef21dd47e99d3c952918aff9cd']
            }

            $status.Text = "Processing results..."

            if ($results) {
                # Update the DataGrid with results -- pass playbook output directly
                $PlaybookResultsDataGrid.Dispatcher.Invoke([Action] {

                        # Clear existing results
                        $PlaybookResultsDataGrid.ItemsSource = $null

                        # Add each result to the collection
                        $collection = New-Object System.Collections.ObjectModel.ObservableCollection[object]
                        foreach ($device in $results) {
                            $collection.Add($device)
                        }

                        # Build columns dynamically from the first result's properties
                        $PlaybookResultsDataGrid.Columns.Clear()
                        $columnHeaders = @{
                            DeviceName           = "Device Name"
                            SerialNumber         = "Serial Number"
                            OperatingSystem      = "Operating System"
                            PrimaryUser          = "Primary User"
                            AzureADLastContact   = "Entra ID Last Contact"
                            IntuneLastContact    = "Intune Last Contact"
                            AutopilotLastContact = "Autopilot Last Contact"
                            ComplianceState      = "Compliance State"
                            EnrollmentDate       = "Enrollment Date"
                            LastSyncDateTime     = "Last Sync"
                            Ownership            = "Ownership"
                            Model                = "Model"
                            OSVersion            = "OS Version"
                            OwnershipType        = "Ownership Type"
                            CurrentVersion       = "Current Version"
                            LatestVersion        = "Latest Version"
                            EndOfSupportDate     = "End of Support Date"
                            DaysPastEOL          = "Days Past EOL"
                            DaysSinceLastSync    = "Days Since Last Sync"
                            KeyId                = "Key ID"
                            VolumeType           = "Volume Type"
                            CreatedDateTime      = "Created Date"
                            HasFileVaultKey      = "Has FileVault Key"
                        }
                        $firstResult = $results | Select-Object -First 1
                        foreach ($prop in $firstResult.PSObject.Properties) {
                            $header = if ($columnHeaders.ContainsKey($prop.Name)) { $columnHeaders[$prop.Name] } else { $prop.Name }
                            $PlaybookResultsDataGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
                                        Header  = $header
                                        Binding = New-Object System.Windows.Data.Binding($prop.Name)
                                        Width   = "Auto"
                                    }))
                        }

                        # Set the ItemsSource
                        $PlaybookResultsDataGrid.ItemsSource = $collection
                        # Update visibility and header text
                        $Window.FindName('PlaybooksScrollViewer').Visibility = 'Collapsed'
                        $PlaybookResultsGrid.Visibility = 'Visible'
                        $Window.FindName('PlaybookResultsHeader').Text = "$PlaybookName ($($collection.Count) devices)"

                        # Force layout update
                        $PlaybookResultsDataGrid.UpdateLayout()
                    })

                $status.Text = "Playbook completed successfully!"
                Write-Log "Playbook completed successfully!"
                Start-Sleep -Seconds 2
                $progressWindow.Close()
            }
            else {
                throw "Playbook returned no results"
            }
        }
        catch {
            throw $_
        }
    }
    catch {
        Write-Log "Error executing playbook: $_"
        if ($null -ne $progressWindow) {
            $errorMessage.Text = $_.Exception.Message
            $errorSection.Visibility = 'Visible'
            $closeButton.Visibility = 'Visible'
            $status.Text = "Error occurred during execution"
        }
        else {
            Show-Toast -Message "Error executing playbook: $_" -Type "error" -DurationSeconds 6
        }
    }
}
