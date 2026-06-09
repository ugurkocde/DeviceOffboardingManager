function Show-GroupTagDialog {
    [xml]$groupTagDialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Set Autopilot Group Tag" Height="260" Width="480"
        WindowStartupLocation="CenterScreen" Background="#F8F9FA">
    <Border Background="White" CornerRadius="8" Margin="16" Padding="20">
        <DockPanel>
            <StackPanel DockPanel.Dock="Top" Margin="0,0,0,16">
                <TextBlock Text="Set Autopilot Group Tag" FontSize="20" FontWeight="SemiBold" Foreground="#1A202C"/>
                <TextBlock Text="Apply a group tag to all selected devices that have an Autopilot identity."
                           TextWrapping="Wrap" Foreground="#4A5568" Margin="0,8,0,0"/>
            </StackPanel>
            <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,20,0,0">
                <Button x:Name="CancelButton" Content="Cancel" Width="100" Height="36" Margin="0,0,8,0" IsCancel="True"/>
                <Button x:Name="ApplyButton" Content="Apply" Width="100" Height="36" IsDefault="True" Background="#7C3AED" Foreground="White" BorderThickness="0"/>
            </StackPanel>
            <StackPanel>
                <TextBlock Text="Group Tag" FontWeight="SemiBold" Foreground="#2D3748" Margin="0,0,0,6"/>
                <TextBox x:Name="GroupTagTextBox" Height="34" Padding="10,6" BorderBrush="#CBD5E0" BorderThickness="1"/>
                <CheckBox x:Name="ClearGroupTagCheckBox" Content="Clear existing group tag" Margin="0,12,0,0"/>
            </StackPanel>
        </DockPanel>
    </Border>
</Window>
'@

    try {
        $reader = (New-Object System.Xml.XmlNodeReader $groupTagDialogXaml)
        $dialog = [Windows.Markup.XamlReader]::Load($reader)
    }
    catch {
        Write-Log "Error creating group tag dialog: $_" -Severity "ERROR"
        Show-Toast -Message "Failed to create group tag dialog." -Type "error"
        return $null
    }

    $tagTextBox = $dialog.FindName('GroupTagTextBox')
    $clearCheckBox = $dialog.FindName('ClearGroupTagCheckBox')
    $applyButton = $dialog.FindName('ApplyButton')
    $cancelButton = $dialog.FindName('CancelButton')

    $clearCheckBox.Add_Checked({
            $tagTextBox.IsEnabled = $false
            $tagTextBox.Text = ""
        })
    $clearCheckBox.Add_Unchecked({
            $tagTextBox.IsEnabled = $true
            $tagTextBox.Focus()
        })
    $cancelButton.Add_Click({
            $dialog.DialogResult = $false
            $dialog.Close()
        })
    $applyButton.Add_Click({
            if (-not $clearCheckBox.IsChecked -and [string]::IsNullOrWhiteSpace($tagTextBox.Text)) {
                [System.Windows.MessageBox]::Show(
                    "Enter a group tag or select 'Clear existing group tag'.",
                    "Group Tag Required",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                )
                return
            }
            $dialog.DialogResult = $true
            $dialog.Close()
        })

    if ($dialog.ShowDialog() -eq $true) {
        return @{
            GroupTag = if ($clearCheckBox.IsChecked) { "" } else { $tagTextBox.Text.Trim() }
            Clear    = [bool]$clearCheckBox.IsChecked
        }
    }

    return $null
}
