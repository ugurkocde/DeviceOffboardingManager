function Show-BulkImportDialog {
    try {
        $reader = (New-Object System.Xml.XmlNodeReader $bulkImportModalXaml)
        $bulkImportWindow = [Windows.Markup.XamlReader]::Load($reader)

        if ($null -eq $bulkImportWindow) {
            throw "Failed to create bulk import window. XamlReader returned null."
        }
    }
    catch {
        Write-Log "Error creating bulk import window: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to create the bulk import dialog. Error: $_",
            "Dialog Creation Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return $null
    }

    # Get controls
    $downloadTemplateButton = $bulkImportWindow.FindName('DownloadTemplateButton')
    $browseFileButton = $bulkImportWindow.FindName('BrowseFileButton')
    $filePathTextBox = $bulkImportWindow.FindName('FilePathTextBox')
    $previewSection = $bulkImportWindow.FindName('PreviewSection')
    $previewDataGrid = $bulkImportWindow.FindName('PreviewDataGrid')
    $deviceCountText = $bulkImportWindow.FindName('DeviceCountText')
    $errorSection = $bulkImportWindow.FindName('ErrorSection')
    $errorText = $bulkImportWindow.FindName('ErrorText')
    $cancelButton = $bulkImportWindow.FindName('CancelButton')
    $importButton = $bulkImportWindow.FindName('ImportButton')

    # Variable to store parsed devices
    $script:parsedDevices = @()

    # Download template button handler
    $downloadTemplateButton.Add_Click({
            $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
            $saveDialog.Filter = "CSV files (*.csv)|*.csv"
            $saveDialog.FileName = "device_import_template.csv"

            if ($saveDialog.ShowDialog() -eq 'OK') {
                $template = @"
DESKTOP-ABC123
LAPTOP-XYZ789
1234567890
0987654321
"@
                try {
                    [System.IO.File]::WriteAllText($saveDialog.FileName, $template)
                    [System.Windows.MessageBox]::Show(
                        "Template saved successfully!",
                        "Success",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Information
                    )
                }
                catch {
                    [System.Windows.MessageBox]::Show(
                        "Error saving template: $_",
                        "Error",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Error
                    )
                }
            }
        })

    # Browse file button handler
    $browseFileButton.Add_Click({
            $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $openFileDialog.Filter = "CSV files (*.csv)|*.csv|TXT files (*.txt)|*.txt"
            $openFileDialog.Title = "Select Device List File"

            if ($openFileDialog.ShowDialog() -eq 'OK') {
                $filePath = $openFileDialog.FileName
                $filePathTextBox.Text = [System.IO.Path]::GetFileName($filePath)
                $filePathTextBox.ToolTip = $filePath

                # Reset UI
                $errorSection.Visibility = 'Collapsed'
                $previewSection.Visibility = 'Collapsed'
                $importButton.IsEnabled = $false

                try {
                    # Read and parse the file
                    $content = Get-Content -Path $filePath | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

                    if ($content.Count -eq 0) {
                        $errorText.Text = "The selected file is empty or contains only whitespace."
                        $errorSection.Visibility = 'Visible'
                        return
                    }

                    # Create preview data
                    $previewData = New-Object System.Collections.ObjectModel.ObservableCollection[Object]
                    $lineNumber = 1
                    $maxPreviewItems = 10

                    foreach ($device in $content) {
                        if ($lineNumber -le $maxPreviewItems) {
                            $previewData.Add([PSCustomObject]@{
                                    LineNumber       = $lineNumber
                                    DeviceIdentifier = $device
                                })
                        }
                        $lineNumber++
                    }

                    # Update preview
                    $previewDataGrid.ItemsSource = $previewData
                    $previewSection.Visibility = 'Visible'

                    # Update device count
                    if ($content.Count -gt $maxPreviewItems) {
                        $deviceCountText.Text = "Showing first $maxPreviewItems of $($content.Count) devices"
                    }
                    else {
                        $deviceCountText.Text = "Total devices: $($content.Count)"
                    }

                    # Store devices for import
                    $script:parsedDevices = $content
                    $importButton.IsEnabled = $true

                    Write-Log "Preview loaded for $($content.Count) devices from file: $filePath"
                }
                catch {
                    $errorText.Text = "Error reading file: $_"
                    $errorSection.Visibility = 'Visible'
                    Write-Log "Error reading bulk import file: $_"
                }
            }
        })

    # Cancel button handler
    $cancelButton.Add_Click({
            $script:parsedDevices = @()
            $bulkImportWindow.DialogResult = $false
            $bulkImportWindow.Close()
        })

    # Import button handler
    $importButton.Add_Click({
            if ($script:parsedDevices.Count -gt 0) {
                $bulkImportWindow.DialogResult = $true
                $bulkImportWindow.Close()
            }
        })

    # Show dialog and return result
    try {
        if ($null -eq $bulkImportWindow) {
            throw "Bulk import window is null. Cannot show dialog."
        }
        $result = $bulkImportWindow.ShowDialog()
    }
    catch {
        Write-Log "Error showing bulk import dialog: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to show the bulk import dialog. Error: $_",
            "Dialog Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return $null
    }

    if ($result -eq $true -and $script:parsedDevices.Count -gt 0) {
        return $script:parsedDevices
    }

    return $null
}
