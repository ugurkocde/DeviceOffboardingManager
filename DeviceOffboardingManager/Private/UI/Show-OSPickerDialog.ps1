function Show-OSPickerDialog {
    [xml]$osPickerXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Select Operating System" Height="250" Width="350" WindowStartupLocation="CenterScreen" Background="#F8F9FA" ResizeMode="NoResize">
    <Border Background="White" CornerRadius="8" Margin="16">
        <StackPanel Margin="24">
            <TextBlock Text="Select Operating System" FontSize="18" FontWeight="SemiBold" Foreground="#1A202C" Margin="0,0,0,16"/>
            <TextBlock Text="Choose the OS to filter devices by:" Foreground="#718096" FontSize="12" Margin="0,0,0,12"/>
            <ComboBox x:Name="OSComboBox" Width="250" HorizontalAlignment="Left" SelectedIndex="0">
                <ComboBoxItem Content="Windows"/>
                <ComboBoxItem Content="macOS"/>
                <ComboBoxItem Content="iOS"/>
                <ComboBoxItem Content="iPadOS"/>
                <ComboBoxItem Content="Android"/>
                <ComboBoxItem Content="Linux"/>
            </ComboBox>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,24,0,0">
                <Button x:Name="OSCancelButton" Content="Cancel" Width="80" Height="32" Background="#F0F0F0" Foreground="#2D3748" BorderThickness="0" Margin="0,0,8,0" IsCancel="True" Cursor="Hand"/>
                <Button x:Name="OSOkButton" Content="OK" Width="80" Height="32" Background="#0078D4" Foreground="White" BorderThickness="0" IsDefault="True" Cursor="Hand"/>
            </StackPanel>
        </StackPanel>
    </Border>
</Window>
'@

    $reader = (New-Object System.Xml.XmlNodeReader $osPickerXaml)
    $osWindow = [Windows.Markup.XamlReader]::Load($reader)
    $osCombo = $osWindow.FindName('OSComboBox')
    $osCancelBtn = $osWindow.FindName('OSCancelButton')
    $osOkBtn = $osWindow.FindName('OSOkButton')

    $script:selectedOS = $null
    $osCancelBtn.Add_Click({ $osWindow.DialogResult = $false; $osWindow.Close() })
    $osOkBtn.Add_Click({
        $script:selectedOS = ($osCombo.SelectedItem).Content.ToString()
        $osWindow.DialogResult = $true
        $osWindow.Close()
    })

    $dialogResult = $osWindow.ShowDialog()
    if ($dialogResult) {
        return $script:selectedOS
    }
    return $null
}
