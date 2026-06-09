function Show-PlaybookProgressModal {
    param(
        [string]$PlaybookName,
        [string]$Description
    )

    $progressModalXaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Playbook Execution" Height="300" Width="500"
    WindowStartupLocation="CenterScreen"
    Background="#F8F9FA">

    <Border Background="White" CornerRadius="8" Margin="16">
        <DockPanel Margin="24">
            <!-- Header -->
            <StackPanel DockPanel.Dock="Top" Margin="0,0,0,24">
                <TextBlock x:Name="PlaybookTitle"
                          Text="Executing Playbook"
                          FontSize="24"
                          FontWeight="SemiBold"
                          Foreground="#1A202C"/>
                <TextBlock x:Name="PlaybookDescription"
                          Text="Please wait while the playbook is being executed..."
                          Foreground="#4A5568"
                          FontSize="14"
                          Margin="0,8,0,0"/>
            </StackPanel>
            <!-- Progress Section -->
            <StackPanel DockPanel.Dock="Bottom">
                <ProgressBar x:Name="ExecutionProgress"
                           Height="4"
                           Margin="0,0,0,16"
                           Background="#EDF2F7"
                           Foreground="#0078D4"
                           IsIndeterminate="True"/>

                <!-- Status Messages -->
                <TextBlock x:Name="StatusMessage"
                         Text="Initializing..."
                         Foreground="#4A5568"
                         TextWrapping="Wrap"
                         Margin="0,0,0,16"/>
                <!-- Error Message (Hidden by default) -->
                <Border x:Name="ErrorSection"
                        Background="#FEF2F2"
                        BorderBrush="#FEE2E2"
                        BorderThickness="1"
                        CornerRadius="6"
                        Padding="16"
                        Visibility="Collapsed">
                    <StackPanel Orientation="Horizontal">
                        <Path Data="M12,2L1,21H23M12,6L19.53,19H4.47M11,10V13H13V10M11,15V17H13V15"
                              Fill="#DC2626"
                              Width="24"
                              Height="24"
                              Stretch="Uniform"
                              Margin="0,0,12,0"/>
                        <TextBlock x:Name="ErrorMessage"
                                 Text=""
                                 Foreground="#DC2626"
                                 TextWrapping="Wrap"
                                 VerticalAlignment="Center"/>
                    </StackPanel>
                </Border>
                <!-- Close Button -->
                <Button x:Name="CloseButton"
                        Content="Close"
                        Width="120"
                        Height="40"
                        Background="#F0F0F0"
                        Foreground="#2D3748"
                        BorderThickness="0"
                        HorizontalAlignment="Right"
                        Margin="0,16,0,0"
                        Visibility="Collapsed"
                        IsCancel="True"
                        Cursor="Hand"/>
            </StackPanel>
        </DockPanel>
    </Border>
</Window>
"@
    try {
        $reader = (New-Object System.Xml.XmlNodeReader ([xml]$progressModalXaml))
        $progressWindow = [Windows.Markup.XamlReader]::Load($reader)

        if ($null -eq $progressWindow) {
            throw "Failed to create progress window. XamlReader returned null."
        }
    }
    catch {
        Write-Log "Error creating progress window: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to create the progress dialog. Error: $_",
            "Dialog Creation Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return $null
    }

    # Get controls
    $title = $progressWindow.FindName('PlaybookTitle')
    $desc = $progressWindow.FindName('PlaybookDescription')
    $progress = $progressWindow.FindName('ExecutionProgress')
    $status = $progressWindow.FindName('StatusMessage')
    $errorSection = $progressWindow.FindName('ErrorSection')
    $errorMessage = $progressWindow.FindName('ErrorMessage')
    $closeButton = $progressWindow.FindName('CloseButton')

    # Set initial content
    $title.Text = $PlaybookName
    $desc.Text = $Description

    # Add close button handler
    $closeButton.Add_Click({
            $progressWindow.Close()
        })

    # Add window closing handler
    $progressWindow.Add_Closing({
            Write-Log "Progress window is closing"
            if ($errorSection.Visibility -eq 'Visible') {
                Write-Log "Window closed with error: $($errorMessage.Text)"
            }
        })

    return $progressWindow
}
