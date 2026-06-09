function Show-DashboardCardResults {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $false)]
        [array]$DeviceList = @()
    )

    [xml]$dashboardResultsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Dashboard Results" Height="600" Width="900" WindowStartupLocation="CenterScreen" Background="#F8F9FA">
    <Border Background="White" CornerRadius="8" Margin="16">
        <DockPanel Margin="24">
            <!-- Header -->
            <Grid DockPanel.Dock="Top" Margin="0,0,0,24">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock x:Name="TitleText" Text="Dashboard Results" FontSize="24" FontWeight="SemiBold" Foreground="#1A202C"/>
                    <TextBlock x:Name="CountText" Text="" Foreground="#4A5568" FontSize="14" Margin="0,8,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button x:Name="ExportHTMLButton"
                            Content="Export HTML"
                            Height="36"
                            Padding="16,0"
                            Background="#1B2A47"
                            Foreground="White"
                            BorderThickness="0"
                            Margin="0,0,8,0"
                            Cursor="Hand"
                            ToolTip="Export results as a formatted HTML report">
                        <Button.Resources><Style TargetType="Border"><Setter Property="CornerRadius" Value="4"/></Style></Button.Resources>
                    </Button>
                    <Button x:Name="ExportButton"
                            Content="Export to CSV"
                            Height="36"
                            Padding="16,0"
                            Background="#0078D4"
                            Foreground="White"
                            BorderThickness="0"
                            Cursor="Hand"
                            ToolTip="Export results as a CSV file">
                        <Button.Resources><Style TargetType="Border"><Setter Property="CornerRadius" Value="4"/></Style></Button.Resources>
                    </Button>
                </StackPanel>
            </Grid>

            <!-- Close Button -->
            <Button x:Name="CloseButton" DockPanel.Dock="Bottom" Content="Close" Width="120" Height="40"
                    Background="#F0F0F0" Foreground="#2D3748" BorderThickness="0" HorizontalAlignment="Right" Margin="0,24,0,0"
                    IsCancel="True" Cursor="Hand"/>

            <!-- Main Content DataGrid -->
            <DataGrid x:Name="ResultsDataGrid"
                      AutoGenerateColumns="False"
                      IsReadOnly="True"
                      HeadersVisibility="Column"
                      GridLinesVisibility="All"
                      AlternatingRowBackground="#F8F8F8"
                      CanUserResizeRows="False"
                      CanUserReorderColumns="False"
                      SelectionMode="Extended"
                      SelectionUnit="FullRow">
                <DataGrid.Columns>
                    <DataGridTextColumn Header="Device Name" Binding="{Binding DeviceName}" Width="*" MinWidth="150"/>
                    <DataGridTextColumn Header="Serial Number" Binding="{Binding SerialNumber}" Width="150"/>
                    <DataGridTextColumn Header="Last Contact" Binding="{Binding LastContact}" Width="150"/>
                    <DataGridTextColumn Header="Operating System" Binding="{Binding OperatingSystem}" Width="120"/>
                    <DataGridTextColumn Header="OS Version" Binding="{Binding OSVersion}" Width="100"/>
                    <DataGridTextColumn Header="Primary User" Binding="{Binding PrimaryUser}" Width="150"/>
                    <DataGridTextColumn Header="Ownership" Binding="{Binding Ownership}" Width="100"/>
                </DataGrid.Columns>
            </DataGrid>
        </DockPanel>
    </Border>
</Window>
'@

    try {
        $reader = (New-Object System.Xml.XmlNodeReader $dashboardResultsXaml)
        $dashboardWindow = [Windows.Markup.XamlReader]::Load($reader)

        if ($null -eq $dashboardWindow) {
            throw "Failed to create dashboard window. XamlReader returned null."
        }
    }
    catch {
        Write-Log "Error creating dashboard window: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to create the dashboard dialog. Error: $_",
            "Dialog Creation Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return
    }

    # Get controls
    $titleText = $dashboardWindow.FindName('TitleText')
    $countText = $dashboardWindow.FindName('CountText')
    $resultsDataGrid = $dashboardWindow.FindName('ResultsDataGrid')
    $exportButton = $dashboardWindow.FindName('ExportButton')
    $exportHTMLButton = $dashboardWindow.FindName('ExportHTMLButton')
    $closeButton = $dashboardWindow.FindName('CloseButton')

    # Ensure DeviceList is an array
    if ($null -eq $DeviceList) {
        $DeviceList = @()
    }
    elseif ($DeviceList -isnot [array]) {
        $DeviceList = @($DeviceList)
    }

    # Set title and count
    $dashboardWindow.Title = $Title
    $titleText.Text = $Title
    $countText.Text = "$($DeviceList.Count) devices found"

    # Set data
    $resultsDataGrid.ItemsSource = $DeviceList

    # Export button handler
    $exportButton.Add_Click({
            if ($DeviceList.Count -gt 0) {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $fileName = "Dashboard_${Title.Replace(' ', '_')}_${timestamp}.csv"
                Export-DeviceListToCSV -DeviceList $DeviceList -DefaultFileName $fileName
            }
        })

    # Export HTML button handler
    $exportHTMLButton.Add_Click({
            if ($DeviceList.Count -gt 0) {
                try {
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
                    $saveFileDialog.Filter = "HTML Files (*.html)|*.html"
                    $saveFileDialog.DefaultExt = "html"
                    $saveFileDialog.FileName = "Dashboard_$($Title.Replace(' ', '_'))_${timestamp}.html"
                    $saveFileDialog.Title = "Export Dashboard Results"

                    if ($saveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        $reportTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                        $version = Get-ScriptVersion
                        $rows = ""
                        foreach ($d in $DeviceList) {
                            $dn = [System.Web.HttpUtility]::HtmlEncode($d.DeviceName)
                            $sn = [System.Web.HttpUtility]::HtmlEncode($d.SerialNumber)
                            $os = [System.Web.HttpUtility]::HtmlEncode($d.OperatingSystem)
                            $lc = [System.Web.HttpUtility]::HtmlEncode($d.LastContact)
                            $pu = [System.Web.HttpUtility]::HtmlEncode($d.PrimaryUser)
                            $ow = [System.Web.HttpUtility]::HtmlEncode($d.Ownership)
                            $rows += "<tr><td>$dn</td><td>$sn</td><td>$os</td><td>$lc</td><td>$pu</td><td>$ow</td></tr>`n"
                        }
                        $html = @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><title>$([System.Web.HttpUtility]::HtmlEncode($Title))</title>
<style>
body{font-family:'Segoe UI',sans-serif;margin:0;padding:20px;background:#f8f9fa;color:#1a202c}
.container{max-width:1100px;margin:0 auto}
.header{background:#1B2A47;color:white;padding:24px 32px;border-radius:8px 8px 0 0}
.header h1{margin:0 0 8px 0;font-size:22px}.header .meta{font-size:12px;color:#a0aec0}
table{width:100%;border-collapse:collapse;background:white}
th{background:#edf2f7;padding:10px 12px;text-align:left;font-size:12px;font-weight:600;color:#4a5568;border-bottom:2px solid #e2e8f0}
td{padding:10px 12px;font-size:13px;border-bottom:1px solid #e2e8f0}
tr:nth-child(even){background:#f8f8f8}
.footer{padding:16px 32px;background:white;border-radius:0 0 8px 8px;border-top:1px solid #e2e8f0;font-size:11px;color:#a0aec0;text-align:center}
@media print{body{background:white;padding:0}.container{max-width:100%}}
</style></head><body><div class="container">
<div class="header"><h1>$([System.Web.HttpUtility]::HtmlEncode($Title))</h1>
<div class="meta">Generated: $reportTimestamp | $($DeviceList.Count) devices | Device Offboarding Manager $version</div></div>
<table><thead><tr><th>Device Name</th><th>Serial Number</th><th>OS</th><th>Last Contact</th><th>Primary User</th><th>Ownership</th></tr></thead>
<tbody>$rows</tbody></table>
<div class="footer">Device Offboarding Manager - Dashboard Report</div></div></body></html>
"@
                        [System.IO.File]::WriteAllText($saveFileDialog.FileName, $html)
                        Write-Log "Exported dashboard HTML report to: $($saveFileDialog.FileName)"
                        [System.Windows.MessageBox]::Show("Report exported successfully.", "Export Successful", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                    }
                }
                catch {
                    Write-Log "Error exporting dashboard HTML: $_" -Severity "ERROR"
                    [System.Windows.MessageBox]::Show("Error exporting report: $_", "Export Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                }
            }
        })

    # Close button handler
    $closeButton.Add_Click({
            $dashboardWindow.Close()
        })

    # Show dialog
    try {
        if ($null -eq $dashboardWindow) {
            throw "Dashboard window is null. Cannot show dialog."
        }
        $dashboardWindow.ShowDialog() | Out-Null
    }
    catch {
        Write-Log "Error showing dashboard dialog: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to show the dashboard dialog. Error: $_",
            "Dialog Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}
