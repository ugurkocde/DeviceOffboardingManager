function Show-DeviceGroupMembership {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EntraDeviceId,
        [string]$DeviceName = "Device"
    )

    try {
        $uri = "https://graph.microsoft.com/beta/devices/$EntraDeviceId/memberOf?`$select=displayName,groupTypes,mailEnabled,securityEnabled"
        $groups = Get-GraphPagedResults -Uri $uri

        [xml]$groupModalXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Group Memberships - $([System.Security.SecurityElement]::Escape($DeviceName) -replace '&quot;', '')" Height="400" Width="500" WindowStartupLocation="CenterScreen" Background="#F8F9FA">
    <Border Background="White" CornerRadius="8" Margin="16">
        <DockPanel Margin="24">
            <TextBlock DockPanel.Dock="Top" Text="Group Memberships" FontSize="18" FontWeight="SemiBold" Foreground="#1A202C" Margin="0,0,0,16"/>
            <Button x:Name="GroupCloseButton" DockPanel.Dock="Bottom" Content="Close" Width="100" Height="36"
                    Background="#0078D4" Foreground="White" BorderThickness="0" HorizontalAlignment="Right" Margin="0,16,0,0"
                    IsCancel="True" Cursor="Hand"/>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <ItemsControl x:Name="GroupList">
                    <ItemsControl.ItemTemplate>
                        <DataTemplate>
                            <Border Background="#F7FAFC" BorderBrush="#E2E8F0" BorderThickness="1" CornerRadius="6" Padding="12" Margin="0,0,0,8">
                                <StackPanel>
                                    <TextBlock Text="{Binding Name}" FontWeight="Medium" FontSize="13"/>
                                    <TextBlock Text="{Binding Type}" FontSize="11" Foreground="#718096"/>
                                </StackPanel>
                            </Border>
                        </DataTemplate>
                    </ItemsControl.ItemTemplate>
                </ItemsControl>
            </ScrollViewer>
        </DockPanel>
    </Border>
</Window>
"@

        $reader = (New-Object System.Xml.XmlNodeReader $groupModalXaml)
        $groupWindow = [Windows.Markup.XamlReader]::Load($reader)
        $groupList = $groupWindow.FindName('GroupList')
        $groupCloseBtn = $groupWindow.FindName('GroupCloseButton')

        $groupItems = @()
        if ($groups -and $groups.Count -gt 0) {
            foreach ($group in $groups) {
                $groupType = if ($group.groupTypes -contains "Unified") { "Microsoft 365 Group" }
                             elseif ($group.groupTypes -contains "DynamicMembership") { "Dynamic Security Group" }
                             elseif ($group.securityEnabled) { "Security Group" }
                             else { "Distribution Group" }
                $groupItems += [PSCustomObject]@{
                    Name = $group.displayName
                    Type = $groupType
                }
            }
        } else {
            $groupItems += [PSCustomObject]@{
                Name = "No group memberships found"
                Type = ""
            }
        }

        $groupList.ItemsSource = $groupItems
        $groupCloseBtn.Add_Click({ $groupWindow.Close() })
        $groupWindow.ShowDialog() | Out-Null
    } catch {
        Write-Log "Error retrieving group memberships: $_" -Severity "ERROR"
        [System.Windows.MessageBox]::Show("Error retrieving group memberships: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
}
