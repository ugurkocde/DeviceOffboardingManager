function Export-DeviceListToCSV {
    param(
        [Parameter(Mandatory = $true)]
        [array]$DeviceList,
        [Parameter(Mandatory = $true)]
        [string]$DefaultFileName
    )

    try {
        # Create SaveFileDialog
        $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveFileDialog.Filter = "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*"
        $saveFileDialog.DefaultExt = "csv"
        $saveFileDialog.FileName = $DefaultFileName
        $saveFileDialog.Title = "Export Device List"

        if ($saveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $exportPath = $saveFileDialog.FileName

            # Export to CSV
            $DeviceList | Export-Csv -Path $exportPath -NoTypeInformation -Force

            Write-Log "Exported $($DeviceList.Count) devices to: $exportPath"

            Show-Toast -Message "Successfully exported $($DeviceList.Count) devices to: $exportPath" -Type "success"

            return $true
        }
        return $false
    }
    catch {
        Write-Log "Error exporting device list: $_"
        Show-Toast -Message "Error exporting device list: $_" -Type "error" -DurationSeconds 6
        return $false
    }
}
