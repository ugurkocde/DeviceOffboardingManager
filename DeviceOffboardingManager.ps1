<#PSScriptInfo

.VERSION 0.2.2

.GUID a686724d-588d-472e-b927-c4840c32eed1

.AUTHOR ugurk

.COMPANYNAME

.COPYRIGHT

.TAGS Intune, PowerShell, Automation

.LICENSEURI https://github.com/ugurkocde/DeviceOffboardingManager/blob/main/LICENSE

.PROJECTURI https://github.com/ugurkocde/DeviceOffboardingManager

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES Changelog: https://github.com/ugurkocde/DeviceOffboardingManager/blob/main/Changelog.md


.PRIVATEDATA

#>

<# 

.DESCRIPTION 
 A PowerShell GUI tool for efficiently managing and offboarding devices from Microsoft Intune, Autopilot, and Entra ID, featuring bulk operations and real-time analytics for streamlined device lifecycle management. 

#> 
Param()

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication

# Made by Ugur with ❤️
# Guide and documentation available at https://github.com/ugurkocde/DeviceOffboardingManager
# Feedback and contributions are welcome!

# Load required assemblies with error handling
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName PresentationCore -ErrorAction Stop
    Add-Type -AssemblyName WindowsBase -ErrorAction Stop
}
catch {
    Write-Host "Failed to load required .NET assemblies: $_" -ForegroundColor Red
    Write-Host "Please ensure .NET Framework is properly installed." -ForegroundColor Red
    exit 1
}


$script:LogFilePath = [System.IO.Path]::Combine($env:LOCALAPPDATA, "DeviceOffBoardingManager", "IntuneOffboardingTool_Log.txt")

# Ensure DeviceOffBoardingManager folder exists
Write-Host "Ensuring DeviceOffBoardingManager folder exists"
$settingsFolder = [System.IO.Path]::Combine($env:LOCALAPPDATA, "DeviceOffBoardingManager")
if (-not (Test-Path $settingsFolder)) {
    Write-Host "DeviceOffBoardingManager folder does not exist."
    Write-Host "Creating DeviceOffBoardingManager folder at $settingsFolder"
    New-Item -Path $settingsFolder -ItemType Directory | Out-Null
}

# Create default settings.json file
$settingsPath = [System.IO.Path]::Combine($settingsFolder, "settings.json")
if (-not (Test-Path $settingsPath)) {
    Write-Log -Message "Creating default settings.json file at $settingsPath"
    $defaultSettings = @{
        RememberCertAuthentication = $false
        RememberSecretAuthentication = $false
        QuerySCCM = $true
    }
    $defaultSettings | ConvertTo-Json | Set-Content -Path $settingsPath
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"

    Add-Content -Path $script:LogFilePath -Value $logMessage
}

# Function to get installed version
function Get-InstalledVersion {
    try {
        $module = Get-InstalledPSResource DeviceOffboardingManager | Sort-Object Version -Descending | Select-Object -First 1
        if ($module) {
            return $module.Version.ToString()
        }
        return $script:PSScriptRoot.VERSION
    }
    catch {
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error getting installed version: $_"
        return "Unknown"
    }
}

# Function to get latest version from PowerShell Gallery
function Get-LatestVersion {
    try {
        $module = Find-Script -Name DeviceOffboardingManager -ErrorAction Stop
        return $module.Version
    }
    catch {
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error getting latest version: $_"
        return "Unknown"
    }
}

# Function to get script version from PSScriptInfo
function Get-ScriptVersion {
    try {
        $scriptContent = Get-Content -Path $PSCommandPath -TotalCount 10
        $versionLine = $scriptContent | Where-Object { $_ -match '\.VERSION\s+(.+)' }
        if ($versionLine) {
            return $matches[1].Trim()
        }
        return "Unknown"
    }
    catch {
        return "Unknown"
    }
}

# Function to update version displays
function Update-VersionDisplays {
    param($window)
    
    $updateStatus = $window.FindName('UpdateStatus')
    
    if ($updateStatus) {
        $installedVersion = Get-InstalledVersion
        $latestVersion = Get-LatestVersion
        
        # Update display and add click handler based on version comparison
        if ($installedVersion -ne "Unknown" -and $latestVersion -ne "Unknown") {
            if ([version]$installedVersion -lt [version]$latestVersion) {
                $updateStatus.Text = "Update available"
                $updateStatus.Foreground = "#4FD1C5"  # Highlight newer version
                $updateStatus.Cursor = "Hand"
                
                # Remove existing handler if any
                $updateStatus.RemoveHandler(
                    [System.Windows.Controls.TextBlock]::MouseDownEvent,
                    [System.Windows.Input.MouseButtonEventHandler] { param($s, $e) }
                )
                
                # Add click handler
                $updateStatus.AddHandler(
                    [System.Windows.Controls.TextBlock]::MouseDownEvent,
                    [System.Windows.Input.MouseButtonEventHandler] {
                        Start-Process "https://github.com/ugurkocde/DeviceOffboardingManager/blob/main/README.md#update-to-the-latest-version"
                    }
                )
            }
            else {
                $updateStatus.Text = "No Update available"
                $updateStatus.Foreground = "#A0A0A0"  # Default gray color
                $updateStatus.Cursor = "Arrow"
                
                # Remove click handler if exists
                $updateStatus.RemoveHandler(
                    [System.Windows.Controls.TextBlock]::MouseDownEvent,
                    [System.Windows.Input.MouseButtonEventHandler] { param($s, $e) }
                )
            }
        }
        else {
            $updateStatus.Text = "Version check unavailable"
            $updateStatus.Foreground = "#A0A0A0"
            $updateStatus.Cursor = "Arrow"
            
            # Remove click handler if exists
            $updateStatus.RemoveHandler(
                [System.Windows.Controls.TextBlock]::MouseDownEvent,
                [System.Windows.Input.MouseButtonEventHandler] { param($s, $e) }
            )
        }
    }
}

# Add the DeviceObject class definition
if (-not ([System.Management.Automation.PSTypeName]'DeviceObject').Type) {
    Add-Type -TypeDefinition @"
    using System;
    using System.ComponentModel;

    public class DeviceObject : INotifyPropertyChanged
    {
        private bool isSelected;
        public bool IsSelected
        {
            get { return isSelected; }
            set 
            { 
                isSelected = value;
                OnPropertyChanged("IsSelected");
            }
        }
        
        public string DeviceName { get; set; }
        public string SerialNumber { get; set; }
        public string OperatingSystem { get; set; }
        public string PrimaryUser { get; set; }
        public DateTime? AzureADLastContact { get; set; }
        public DateTime? IntuneLastContact { get; set; }
        public DateTime? AutopilotLastContact { get; set; }
        public DateTime? SCCMLastContact { get; set; }

        public event PropertyChangedEventHandler PropertyChanged;

        protected void OnPropertyChanged(string name)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        }
    }
"@
}

# Define a helper function for paginated Graph API calls
function Get-GraphPagedResults {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )
    
    $results = @()
    $nextLink = $Uri
    
    do {
        try {
            $response = Invoke-MgGraphRequest -Uri $nextLink -Method GET
            if ($response.value) {
                $results += $response.value
            }
            $nextLink = $response.'@odata.nextLink'
        }
        catch {
            Write-Log "Error in pagination: $_"
            break
        }
    } while ($nextLink)
    
    return $results
}

# Helper function to safely convert date strings to DateTime objects
function ConvertTo-SafeDateTime {
    param(
        [Parameter(Mandatory = $false)]
        [string]$dateString
    )
    
    if ([string]::IsNullOrWhiteSpace($dateString)) {
        return $null
    }
    
    # Define supported date formats
    $formats = @(
        "yyyy-MM-ddTHH:mm:ssZ",
        "yyyy-MM-ddTHH:mm:ss.fffffffZ",
        "yyyy-MM-ddTHH:mm:ss",
        "MM/dd/yyyy HH:mm:ss",
        "dd/MM/yyyy HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "M/d/yyyy h:mm:ss tt",
        "M/d/yyyy H:mm:ss"
    )
    
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    
    # Try each format
    foreach ($format in $formats) {
        try {
            $parsedDate = [DateTime]::ParseExact($dateString, $format, $culture, [System.Globalization.DateTimeStyles]::None)
            # Check for DateTime.MinValue (1/1/0001)
            if ($parsedDate -eq [DateTime]::MinValue) {
                return $null
            }
            return $parsedDate
        }
        catch {
            # Continue to next format
            continue
        }
    }
    
    # Try default parse as last resort with InvariantCulture
    try {
        $parsedDate = [DateTime]::Parse($dateString, $culture)
        if ($parsedDate -eq [DateTime]::MinValue) {
            return $null
        }
        return $parsedDate
    }
    catch {
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Failed to parse date: $dateString"
        return $null
    }
}

# Define WPF XAML
[xml]$xaml = @"
<Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Device Offboarding Manager (Preview)" Height="750" Width="1400" 
    Background="#F0F0F0"
    WindowStartupLocation="CenterScreen" 
    ResizeMode="CanResize">
    
    <Window.Resources>
        <!-- Drop Shadow Effect -->
        <DropShadowEffect x:Key="CardShadow"
                         ShadowDepth="2"
                         Direction="315"
                         Color="#000000"
                         Opacity="0.25"
                         BlurRadius="4"/>
                         
        <!-- Base Button Style -->
        <Style TargetType="Button">
            <Setter Property="Background" Value="#0078D4"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="12,5"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Height" Value="28"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" 
                                CornerRadius="2" 
                                BorderThickness="{TemplateBinding BorderThickness}"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#106EBE"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#CCCCCC"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Menu Button Style -->
        <Style x:Key="MenuButtonStyle" TargetType="RadioButton">
            <Setter Property="Foreground" Value="#808080"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Height" Value="40"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RadioButton">
                        <Border x:Name="border" 
                                Background="{TemplateBinding Background}"
                                BorderThickness="0">
                            <Grid>
                                <Border x:Name="indicator" 
                                        Width="3" 
                                        Background="Transparent"
                                        HorizontalAlignment="Left"/>
                                <ContentPresenter Margin="20,0,0,0" 
                                                VerticalAlignment="Center"/>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#404040"/>
                                <Setter Property="Foreground" Value="White"/>
                                <Setter TargetName="indicator" Property="Background" Value="#0078D4"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter Property="Background" Value="#404040"/>
                                <Setter Property="Foreground" Value="White"/>
                                <Setter TargetName="indicator" Property="Background" Value="#0078D4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Sidebar Connection Button Style -->
        <Style x:Key="SidebarButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="#404040"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Height" Value="32"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="2"
                                BorderThickness="0">
                            <ContentPresenter HorizontalAlignment="Center" 
                                            VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#505050"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#333333"/>
                                <Setter Property="Foreground" Value="#808080"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Playbook Button Style -->
        <Style x:Key="PlaybookButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="#1B2A47"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Padding" Value="20,15"/>
            <Setter Property="Margin" Value="0,0,0,15"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Grid>
                            <Border Background="{TemplateBinding Background}"
                                    CornerRadius="8"
                                    Padding="{TemplateBinding Padding}"
                                    Effect="{StaticResource CardShadow}">
                                <Grid>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>
                                    <TextBlock Text="{TemplateBinding Content}"
                                             FontWeight="SemiBold"
                                             TextWrapping="Wrap"/>
                                    <TextBlock Grid.Row="1"
                                             Text="{TemplateBinding Tag}"
                                             FontSize="12"
                                             Opacity="0.7"
                                             TextWrapping="Wrap"
                                             Margin="0,8,0,0"/>
                                </Grid>
                            </Border>
                            <!-- Grey overlay for disabled state -->
                            <Border x:Name="DisabledOverlay"
                                    Background="#80808080"
                                    CornerRadius="8"
                                    Visibility="Collapsed"/>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="DisabledOverlay" Property="Visibility" Value="Visible"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- TextBox Style -->
        <Style TargetType="TextBox">
            <Setter Property="Height" Value="28"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#CCCCCC"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>

        <!-- ComboBox Style -->
        <Style TargetType="ComboBox">
            <Setter Property="Height" Value="28"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#CCCCCC"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>

        <!-- DataGrid Style -->
        <Style TargetType="DataGrid">
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="#CCCCCC"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="RowHeight" Value="35"/>
            <Setter Property="RowBackground" Value="White"/>
            <Setter Property="AlternatingRowBackground" Value="#F8F8F8"/>
            <Setter Property="HorizontalGridLinesBrush" Value="#E0E0E0"/>
            <Setter Property="VerticalGridLinesBrush" Value="#E0E0E0"/>
            <Setter Property="ColumnHeaderHeight" Value="32"/>
        </Style>

        <!-- DataGridColumnHeader Style -->
        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="#F5F5F5"/>
            <Setter Property="Foreground" Value="#323130"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="8,0"/>
            <Setter Property="BorderBrush" Value="#E0E0E0"/>
            <Setter Property="BorderThickness" Value="0,0,1,1"/>
        </Style>

        <!-- Authentication Radio Button Style -->
        <Style x:Key="AuthRadioButtonStyle" TargetType="RadioButton">
            <Setter Property="Margin" Value="0,8,8,8"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Foreground" Value="#2D3748"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RadioButton">
                        <Border x:Name="border" 
                                Background="{TemplateBinding Background}"
                                BorderBrush="#E2E8F0"
                                BorderThickness="1"
                                CornerRadius="6"
                                Padding="12">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="24"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Ellipse x:Name="radioOuter"
                                         Width="18" Height="18"
                                         Stroke="#CBD5E0"
                                         StrokeThickness="2"
                                         Fill="Transparent"/>
                                <Ellipse x:Name="radioInner"
                                         Width="10" Height="10"
                                         Fill="#0078D4"
                                         Opacity="0"/>
                                <ContentPresenter Grid.Column="1"
                                                Margin="12,0,0,0"
                                                VerticalAlignment="Center"/>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#F7FAFC"/>
                                <Setter TargetName="radioOuter" Property="Stroke" Value="#0078D4"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="radioInner" Property="Opacity" Value="1"/>
                                <Setter TargetName="radioOuter" Property="Stroke" Value="#0078D4"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="#0078D4"/>
                                <Setter TargetName="border" Property="Background" Value="#F0F9FF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- TextBox Style -->
        <Style x:Key="AuthTextBoxStyle" TargetType="TextBox">
            <Setter Property="Height" Value="36"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="Margin" Value="0,4"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="#E2E8F0"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="BorderBrush" Value="#0078D4"/>
                </Trigger>
                <Trigger Property="IsFocused" Value="True">
                    <Setter Property="BorderBrush" Value="#0078D4"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Password Box Style -->
        <Style x:Key="AuthPasswordBoxStyle" TargetType="PasswordBox">
            <Setter Property="Height" Value="36"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="Margin" Value="0,4"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="#E2E8F0"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>

        <!-- Button Style -->
        <Style x:Key="AuthButtonStyle" TargetType="Button">
            <Setter Property="Height" Value="40"/>
            <Setter Property="Padding" Value="24,0"/>
            <Setter Property="Background" Value="#0078D4"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" 
                                            VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#106EBE"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#005A9E"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Toast Notification Style -->
        <Style x:Key="ToastNotificationStyle" TargetType="Border">
            <Setter Property="Background" Value="#1B2A47"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="16"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
            <Setter Property="Effect">
                <Setter.Value>
                    <DropShadowEffect ShadowDepth="2"
                                    Direction="315"
                                    Color="#000000"
                                    Opacity="0.25"
                                    BlurRadius="4"/>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Secondary Button Style -->
        <Style x:Key="SecondaryButtonStyle" TargetType="Button">
            <Setter Property="Height" Value="40"/>
            <Setter Property="Padding" Value="24,0"/>
            <Setter Property="Background" Value="#F0F0F0"/>
            <Setter Property="Foreground" Value="#2D3748"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" 
                                            VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#E2E2E2"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#D4D4D4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="200"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Sidebar -->
        <Border Grid.Column="0" Background="#2D2D2D">
            <DockPanel>
                <!-- Menu Items -->
                <StackPanel DockPanel.Dock="Bottom" Margin="0,0,0,0">
                    <!-- Prominent Connect Button -->
                    <Border Margin="15,5,15,10" 
                            Background="#0078D4" 
                            CornerRadius="4">
                        <Button x:Name="AuthenticateButton" 
                                Content="Connect to MS Graph" 
                                Style="{StaticResource SidebarButtonStyle}"
                                Background="Transparent"
                                Foreground="White"
                                Height="40"
                                Margin="0"/>
                    </Border>

                    <!-- Tenant Info Section -->
                    <Border x:Name="TenantInfoSection"
                            Margin="15,0,15,10"
                            Background="#404040"
                            CornerRadius="4"
                            Visibility="Collapsed">
                        <StackPanel Margin="12,8">
                            <TextBlock Text="Connected Tenant"
                                     Foreground="#A0A0A0"
                                     FontSize="12"
                                     Margin="0,0,0,4"/>
                            <TextBlock x:Name="TenantDisplayName"
                                     Text=""
                                     Foreground="White"
                                     FontSize="14"
                                     TextWrapping="Wrap"
                                     Margin="0,0,0,4"/>
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                
                                <TextBlock Text="Domain: "
                                         Grid.Row="0"
                                         Foreground="#A0A0A0"
                                         FontSize="11"
                                         VerticalAlignment="Center"/>
                                <TextBox x:Name="TenantDomain"
                                       Grid.Row="0"
                                       Grid.Column="1"
                                       Text=""
                                       Foreground="#A0A0A0"
                                       FontSize="11"
                                       Background="Transparent"
                                       BorderThickness="0"
                                       IsReadOnly="True"
                                       TextWrapping="NoWrap"
                                       VerticalAlignment="Center"
                                       Margin="0,0,0,4"/>

                                <TextBlock Text="Tenant ID: "
                                         Grid.Row="1"
                                         Foreground="#A0A0A0"
                                         FontSize="11"
                                         VerticalAlignment="Center"/>
                                <TextBox x:Name="TenantId"
                                       Grid.Row="1"
                                       Grid.Column="1"
                                       Text=""
                                       Foreground="#A0A0A0"
                                       FontSize="11"
                                       Background="Transparent"
                                       BorderThickness="0"
                                       IsReadOnly="True"
                                       TextWrapping="NoWrap"
                                       VerticalAlignment="Center"/>
                            </Grid>
                        </StackPanel>
                    </Border>

                    <!-- Version Info -->
                    <Border Background="#1B2A47" 
                            Margin="15,5,15,5" 
                            CornerRadius="6" 
                            Padding="10">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <TextBlock x:Name="UpdateStatus"
                                    Grid.Column="0"
                                    Grid.ColumnSpan="5"
                                    Text=""
                                    Foreground="#A0A0A0"
                                    FontSize="11"
                                    TextWrapping="NoWrap"
                                    VerticalAlignment="Center"
                                    HorizontalAlignment="Center"
                                    Cursor="Hand">
                                <TextBlock.Style>
                                    <Style TargetType="TextBlock">
                                        <Style.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter Property="TextDecorations" Value="Underline"/>
                                            </Trigger>
                                        </Style.Triggers>
                                    </Style>
                                </TextBlock.Style>
                            </TextBlock>
                        </Grid>
                    </Border>

                    <Button x:Name="PrerequisitesButton"
                            Content="Prerequisites"
                            Style="{StaticResource SidebarButtonStyle}"
                            Margin="15,5"/>
                    <Button x:Name="logs_button" 
                            Content="Logs"
                            Style="{StaticResource SidebarButtonStyle}"
                            Margin="15,5"/>
                    <Button x:Name="disconnect_button"
                            Content="Disconnect"
                            Style="{StaticResource SidebarButtonStyle}"
                            IsEnabled="False"
                            Margin="15,5"/>

                    <Button x:Name="changelog_button"
                            Content="Changelog"
                            Style="{StaticResource SidebarButtonStyle}"
                            Margin="15,5"/>

                    <Button x:Name="settings_button"
                            Content="Settings"
                            Style="{StaticResource SidebarButtonStyle}"
                            Margin="15,5,15,15"/>
                </StackPanel>
                
                <!-- Navigation Menu -->
                <StackPanel Margin="0,10,0,0">
                    <RadioButton x:Name="MenuHome"
                                Content="Home"
                                Style="{StaticResource MenuButtonStyle}"
                                IsChecked="True"/>
                    <RadioButton x:Name="MenuDashboard"
                                Content="Dashboard"
                                Style="{StaticResource MenuButtonStyle}"
                                IsEnabled="False"/>
                    <RadioButton x:Name="MenuDeviceManagement"
                                Content="Device Offboarding"
                                Style="{StaticResource MenuButtonStyle}"
                                IsEnabled="False"/>
                    <RadioButton x:Name="MenuPlaybooks"
                                Content="Playbooks"
                                Style="{StaticResource MenuButtonStyle}"
                                IsEnabled="False"/>
                                
                    <!-- Feedback Section -->
                    <Border Margin="15,5,15,5" 
                            Background="#1A365D" 
                            CornerRadius="4">
                        <StackPanel Margin="12,8">
                            <TextBlock Text="Have feedback or found a bug?" 
                                     Foreground="#FCD34D"
                                     FontWeight="SemiBold"
                                     FontSize="12"
                                     Margin="0,4,0,4"
                                     TextWrapping="Wrap"/>
                            <TextBlock>
                                <Hyperlink x:Name="FeedbackLink"
                                         Foreground="#60A5FA"
                                         TextDecorations="None">
                                    Submit on GitHub →
                                </Hyperlink>
                            </TextBlock>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- Main Content Area -->
        <Grid x:Name="MainContent" Grid.Column="1" Margin="20">
            <!-- Home Page -->
            <Grid x:Name="HomePage" Visibility="Visible">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <!-- Header -->
                <StackPanel Grid.Row="0" Margin="0,0,0,30">
                    <TextBlock Text="Device Offboarding Manager"
                              FontSize="32"
                              FontWeight="Bold"
                              Margin="0,0,0,10"/>
                    <TextBlock Text="Streamline your device lifecycle management across Microsoft services"
                              FontSize="16"
                              Opacity="0.7"/>
                    
                    <!-- Warning/Disclaimer Section -->
                    <Border Background="#DC2626"
                            CornerRadius="8"
                            Margin="0,20,0,0"
                            Effect="{StaticResource CardShadow}">
                        <StackPanel Margin="20">
                            <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                <Path Data="M13,13H11V7H13M13,17H11V15H13M12,2A10,10 0 0,0 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12A10,10 0 0,0 12,2Z"
                                      Fill="White"
                                      Width="24"
                                      Height="24"
                                      Stretch="Uniform"
                                      Margin="0,0,10,0"/>
                                <TextBlock Text="PREVIEW WARNING"
                                         FontSize="18"
                                         FontWeight="Bold"
                                         Foreground="White"/>
                            </StackPanel>
                            <TextBlock TextWrapping="Wrap"
                                     Foreground="White"
                                     FontSize="14"
                                     LineHeight="20">
                                This tool is currently in PREVIEW. Please exercise extreme caution when using it. Device deletion operations are PERMANENT and CANNOT be undone. Always verify the selected devices before proceeding with any deletion operation. It is recommended to test the tool in a non-production environment first.
                            </TextBlock>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- Main Content in 2x2 Grid -->
                <Grid Grid.Row="1">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <!-- Quick Actions -->
                    <Border Grid.Column="0" Grid.Row="0" 
                            Background="#1B2A47" 
                            CornerRadius="8" 
                            Margin="0,0,10,10">
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="Quick Actions"
                                     FontSize="20"
                                     FontWeight="SemiBold"
                                     Foreground="White"
                                     Margin="0,0,0,15"/>
                            <StackPanel Grid.Row="1">
                                <TextBlock Text="→ Connect to MS Graph in the sidebar"
                                         FontSize="14"
                                         Foreground="#A0AEC0"
                                         Margin="0,0,0,8"/>
                                <TextBlock Text="→ Check permissions after connecting"
                                         FontSize="14"
                                         Foreground="#A0AEC0"
                                         Margin="0,0,0,8"/>
                                <TextBlock Text="→ Access device management tools"
                                         FontSize="14"
                                         Foreground="#A0AEC0"
                                         Margin="0,0,0,8"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Key Features -->
                    <Border Grid.Column="1" Grid.Row="0" 
                            Background="#172A3A" 
                            CornerRadius="8" 
                            Margin="10,0,0,10">
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="Key Features"
                                     FontSize="20"
                                     FontWeight="SemiBold"
                                     Foreground="White"
                                     Margin="0,0,0,15"/>
                            <StackPanel Grid.Row="1">
                                <TextBlock Text="• Real-time device monitoring"
                                         FontSize="14"
                                         Foreground="#A0AEC0"
                                         Margin="0,0,0,8"/>
                                <TextBlock Text="• Bulk device operations"
                                         FontSize="14"
                                         Foreground="#A0AEC0"
                                         Margin="0,0,0,8"/>
                                <TextBlock Text="• Automated management tasks"
                                         FontSize="14"
                                         Foreground="#A0AEC0"
                                         Margin="0,0,0,8"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Services -->
                    <Border Grid.Column="0" Grid.Row="1" 
                            Background="#2D3748" 
                            CornerRadius="8" 
                            Margin="0,10,10,0">
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="Supported Services"
                                     FontSize="20"
                                     FontWeight="SemiBold"
                                     Foreground="White"
                                     Margin="0,0,0,15"/>
                            <Grid Grid.Row="1">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                
                                <!-- Left Column -->
                                <StackPanel Grid.Column="0">
                                    <TextBlock Text="• Intune"
                                             FontSize="14"
                                             Foreground="#A0AEC0"
                                             Margin="0,0,10,8"/>
                                    <TextBlock Text="• Autopilot"
                                             FontSize="14"
                                             Foreground="#A0AEC0"
                                             Margin="0,0,10,8"/>
                                </StackPanel>
                                
                                <!-- Right Column -->
                                <StackPanel Grid.Column="1">
                                    <TextBlock Text="• Entra ID"
                                             FontSize="14"
                                             Foreground="#A0AEC0"
                                             Margin="0,0,0,8"/>
                                    <TextBlock Text="• SCCM"
                                             FontSize="14"
                                             Foreground="#A0AEC0"
                                             Margin="0,0,0,8"/>
                                </StackPanel>
                            </Grid>
                        </Grid>
                    </Border>

                    <!-- Navigation -->
                    <Border Grid.Column="1" Grid.Row="1" 
                            Background="#1A365D" 
                            CornerRadius="8" 
                            Margin="10,10,0,0">
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="Navigation Guide"
                                     FontSize="20"
                                     FontWeight="SemiBold"
                                     Foreground="White"
                                     Margin="0,0,0,15"/>
                            <StackPanel Grid.Row="1">
                                <TextBlock Text="Dashboard → Device statistics"
                                         FontSize="14"
                                         Foreground="#A0AEC0"
                                         Margin="0,0,0,8"/>
                                <TextBlock Text="Device Management → Search &amp; manage"
                                         FontSize="14"
                                         Foreground="#A0AEC0"
                                         Margin="0,0,0,8"/>
                                <TextBlock Text="Playbooks → Automated tasks"
                                         FontSize="14"
                                         Foreground="#A0AEC0"
                                         Margin="0,0,0,8"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                </Grid>
            </Grid>

            <!-- Dashboard Page -->
            <Grid x:Name="DashboardPage">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <!-- Top Row Statistics -->
                <UniformGrid Grid.Row="0" Rows="1" Margin="20,10,20,10">
                    <Border x:Name="IntuneDevicesCard" Background="#1B2A47" Margin="0,0,10,0" CornerRadius="8" Cursor="Hand">
                        <Border.Style>
                            <Style TargetType="Border">
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#243447"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Border.Style>
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
                                <Path Data="M21,14V4H3V14H21M21,2A2,2 0 0,1 23,4V16A2,2 0 0,1 21,18H14L16,21V22H8V21L10,18H3C1.89,18 1,17.1 1,16V4C1,2.89 1.89,2 3,2H21M4,5H20V13H4V5Z"
                                      Fill="#4299E1" Width="24" Height="24" Stretch="Uniform"/>
                                <TextBlock Text="Intune Devices"
                                         Foreground="#A0AEC0"
                                         FontSize="14"
                                         Margin="12,0,0,0"
                                         VerticalAlignment="Center"/>
                            </StackPanel>
                            <TextBlock Grid.Row="1"
                                     x:Name="IntuneDevicesCount"
                                     Text="0"
                                     Foreground="White"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="Total Managed Devices"
                                     Foreground="#718096"
                                     FontSize="12"/>
                        </Grid>
                    </Border>

                    <Border x:Name="AutopilotDevicesCard" Background="#1B2A47" Margin="10,0" CornerRadius="8" Cursor="Hand">
                        <Border.Style>
                            <Style TargetType="Border">
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#243447"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Border.Style>
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
                                <Path Data="M12,3L1,9L12,15L21,10.09V17H23V9M5,13.18V17.18L12,21L19,17.18V13.18L12,17L5,13.18Z"
                                      Fill="#48BB78" Width="24" Height="24" Stretch="Uniform"/>
                                <TextBlock Text="Autopilot Devices"
                                         Foreground="#A0AEC0"
                                         FontSize="14"
                                         Margin="12,0,0,0"
                                         VerticalAlignment="Center"/>
                            </StackPanel>
                            <TextBlock Grid.Row="1"
                                     x:Name="AutopilotDevicesCount"
                                     Text="0"
                                     Foreground="White"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="Total Registered Devices"
                                     Foreground="#718096"
                                     FontSize="12"/>
                        </Grid>
                    </Border>

                    <Border x:Name="EntraIDDevicesCard" Background="#1B2A47" Margin="10,0" CornerRadius="8" Cursor="Hand">
                        <Border.Style>
                            <Style TargetType="Border">
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#243447"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Border.Style>
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
                                <Path Data="M13.05,4.24L6.56,18.05L2,18L7.09,9.24L13.05,4.24M13.75,5.33L22,19.76H6.74L16.04,18.1L11.17,12.31L13.75,5.33Z"
                                      Fill="#ED64A6" Width="24" Height="24" Stretch="Uniform"/>
                                <TextBlock Text="EntraID Devices"
                                         Foreground="#A0AEC0"
                                         FontSize="14"
                                         Margin="12,0,0,0"
                                         VerticalAlignment="Center"/>
                            </StackPanel>
                            <TextBlock Grid.Row="1"
                                     x:Name="EntraIDDevicesCount"
                                     Text="0"
                                     Foreground="White"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="Total Entra ID Devices"
                                     Foreground="#718096"
                                     FontSize="12"/>
                        </Grid>
                    </Border>

                    <Border x:Name="SCCMDevicesCard" Background="#1B2A47" Margin="10,0,0,0" CornerRadius="8" Cursor="Hand">
                        <Border.Style>
                            <Style TargetType="Border">
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#243447"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Border.Style>
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
                                <Path Data="m124.326-8.588 0 9.63c.964 58.745.001 43.336.28 73.96-.01 2.13-1.11 4.33-2.02 6.35-2.46 5.41-5.99 10.5-7.47 16.14-3.37 12.84-.25 24.68 7.68 35.31 3.81 5.11 2.96 7.64-2.7 10.1-3.03 1.32-5.93 3.01-8.69 4.83-23.23 15.29-24.92 60.96 1.44 77.85-33.02 0-66.04 0-89.156.326-.27-59.84.564-155.244-.963-234.014M44.16 85.04c6.86 0 13.72 0 20.65 0 0-6.72 0-13.56 0-20.45-7.07 0-13.8 0-20.9 0 0 6.68 0 13.11.25 20.45m50.94.53c.54-6.9 1.08-13.8 1.64-20.93-7.83 0-14.7 0-21.56 0 0 7.05 0 13.79 0 21 6.47 0 12.72 0 19.92-.07m-51.2 64c0 4.25 0 8.49 0 12.85 7.34 0 14.07 0 21.02 0 0-6.95 0-13.68 0-20.54-7.02 0-13.89 0-21.02 0 0 2.44 0 4.58 0 7.69m40.65-7.99c-3.11 0-6.22 0-9.31 0 0 7.24 0 13.97 0 20.85 7 0 13.73 0 20.72 0 0-6.94 0-13.66 0-20.85-3.53 0-6.99 0-11.41 0m-40.64-22.17c0 1.44 0 2.87 0 4.34 7.34 0 14.19 0 20.98 0 0-7.03 0-13.75 0-20.5-7.09 0-13.95 0-20.98 0 0 5.26 0 10.22 0 16.16m31.07-2.96c0 2.43 0 4.86 0 7.29 7.36 0 14.22 0 20.98 0 0-7.03 0-13.76 0-20.48-7.1 0-13.96 0-20.98 0 0 4.28 0 8.25 0 13.19zM127.47 226c-1.29-.79-1.97-1.88-2.94-2.32-13.82-6.29-21.43-16.87-22.52-32.09-1.27-17.82 3.31-32.84 20.54-41.28 4.35-2.13 9.4-2.83 14.06-4.17 5.25 14.73 10.75 18.98 22.61 18.18 10.2-.69 15.52-5.73 18.09-17.12 14.16-.87 29.37 9.33 33.28 23.68 4.17 15.28 4.37 30.67-7.23 43.24-4.33 4.69-10.61 7.58-15.67 11.58-19.7.29-39.72.29-60.21.29zM165.71 73.03c18.8 5.11 27.42 21.88 27.16 35.06-.31 15.41-11.84 29.97-27.09 33.78-14.91 3.72-31.78-3.51-38.92-16.68-8.28-15.27-5.92-32.22 6.19-43.35 9.2-8.46 19.94-11.61 32.67-8.81z"
                                      Fill="#8C57B9" Width="24" Height="24" Stretch="Uniform"/>
                                <TextBlock Text="SCCM Devices"
                                         Foreground="#A0AEC0"
                                         FontSize="14"
                                         Margin="12,0,0,0"
                                         VerticalAlignment="Center"/>
                            </StackPanel>
                            <TextBlock Grid.Row="1"
                                     x:Name="SCCMDevicesCount"
                                     Text="0"
                                     Foreground="White"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="Total SCCM Devices"
                                     Foreground="#718096"
                                     FontSize="12"/>
                        </Grid>
                    </Border>
                </UniformGrid>

                <!-- Middle Row - Stale Devices -->
                <UniformGrid Grid.Row="1" Rows="1" Margin="20,10,20,10">
                    <Border x:Name="StaleDevices30Card" Background="#1B2A47" Margin="0,0,10,0" CornerRadius="8" Cursor="Hand">
                        <Border.Style>
                            <Style TargetType="Border">
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#243447"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Border.Style>
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
                                <Path Data="M12,20A7,7 0 0,1 5,13A7,7 0 0,1 12,6A7,7 0 0,1 19,13A7,7 0 0,1 12,20M12,4A9,9 0 0,0 3,13A9,9 0 0,0 12,22A9,9 0 0,0 21,13A9,9 0 0,0 12,4M12.5,8H11V14L15.75,16.85L16.5,15.62L12.5,13.25V8M7.88,3.39L6.6,1.86L2,5.71L3.29,7.24L7.88,3.39M22,5.72L17.4,1.86L16.11,3.39L20.71,7.25L22,5.72Z"
                                      Fill="#F6AD55" Width="24" Height="24" Stretch="Uniform"/>
                                <TextBlock Text="30 Day Stale Devices"
                                         Foreground="#A0AEC0"
                                         FontSize="14"
                                         Margin="12,0,0,0"
                                         VerticalAlignment="Center"/>
                            </StackPanel>
                            <TextBlock Grid.Row="1"
                                     x:Name="StaleDevices30Count"
                                     Text="0"
                                     Foreground="#F6AD55"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="Devices Not Synced"
                                     Foreground="#718096"
                                     FontSize="12"/>
                            <ProgressBar Grid.Row="3"
                                       Height="4"
                                       Margin="0,12,0,0"
                                       Background="#2D3748"
                                       Foreground="#F6AD55"
                                       Value="30"/>
                        </Grid>
                    </Border>

                    <Border x:Name="StaleDevices90Card" Background="#1B2A47" Margin="10,0" CornerRadius="8" Cursor="Hand">
                        <Border.Style>
                            <Style TargetType="Border">
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#243447"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Border.Style>
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
                                <Path Data="M12,20A7,7 0 0,1 5,13A7,7 0 0,1 12,6A7,7 0 0,1 19,13A7,7 0 0,1 12,20M12,4A9,9 0 0,0 3,13A9,9 0 0,0 12,22A9,9 0 0,0 21,13A9,9 0 0,0 12,4M12.5,8H11V14L15.75,16.85L16.5,15.62L12.5,13.25V8M7.88,3.39L6.6,1.86L2,5.71L3.29,7.24L7.88,3.39M22,5.72L17.4,1.86L16.11,3.39L20.71,7.25L22,5.72Z"
                                      Fill="#FC8181" Width="24" Height="24" Stretch="Uniform"/>
                                <TextBlock Text="90 Day Stale Devices"
                                         Foreground="#A0AEC0"
                                         FontSize="14"
                                         Margin="12,0,0,0"
                                         VerticalAlignment="Center"/>
                            </StackPanel>
                            <TextBlock Grid.Row="1"
                                     x:Name="StaleDevices90Count"
                                     Text="0"
                                     Foreground="#FC8181"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="Devices Not Synced"
                                     Foreground="#718096"
                                     FontSize="12"/>
                            <ProgressBar Grid.Row="3"
                                       Height="4"
                                       Margin="0,12,0,0"
                                       Background="#2D3748"
                                       Foreground="#FC8181"
                                       Value="60"/>
                        </Grid>
                    </Border>

                    <Border x:Name="StaleDevices180Card" Background="#1B2A47" Margin="10,0,0,0" CornerRadius="8" Cursor="Hand">
                        <Border.Style>
                            <Style TargetType="Border">
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#243447"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Border.Style>
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
                                <Path Data="M12,20A7,7 0 0,1 5,13A7,7 0 0,1 12,6A7,7 0 0,1 19,13A7,7 0 0,1 12,20M12,4A9,9 0 0,0 3,13A9,9 0 0,0 12,22A9,9 0 0,0 21,13A9,9 0 0,0 12,4M12.5,8H11V14L15.75,16.85L16.5,15.62L12.5,13.25V8M7.88,3.39L6.6,1.86L2,5.71L3.29,7.24L7.88,3.39M22,5.72L17.4,1.86L16.11,3.39L20.71,7.25L22,5.72Z"
                                      Fill="#F56565" Width="24" Height="24" Stretch="Uniform"/>
                                <TextBlock Text="180 Day Stale Devices"
                                         Foreground="#A0AEC0"
                                         FontSize="14"
                                         Margin="12,0,0,0"
                                         VerticalAlignment="Center"/>
                            </StackPanel>
                            <TextBlock Grid.Row="1"
                                     x:Name="StaleDevices180Count"
                                     Text="0"
                                     Foreground="#F56565"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="Devices Not Synced"
                                     Foreground="#718096"
                                     FontSize="12"/>
                            <ProgressBar Grid.Row="3"
                                       Height="4"
                                       Margin="0,12,0,0"
                                       Background="#2D3748"
                                       Foreground="#F56565"
                                       Value="90"/>
                        </Grid>
                    </Border>
                </UniformGrid>

                <!-- Bottom Row - Personal/Corporate and Charts -->
                <Grid Grid.Row="2" Margin="20,10,20,20">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="2*"/>
                    </Grid.ColumnDefinitions>

                    <!-- Personal Devices -->
                    <Border x:Name="PersonalDevicesCard" Grid.Column="0" Background="#1B2A47" Margin="0,0,10,0" CornerRadius="8" Height="220" Cursor="Hand">
                        <Border.Style>
                            <Style TargetType="Border">
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#243447"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Border.Style>
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
                                <Path Data="M12,4A4,4 0 0,1 16,8A4,4 0 0,1 12,12A4,4 0 0,1 8,8A4,4 0 0,1 12,4M12,14C16.42,14 20,15.79 20,18V20H4V18C4,15.79 7.58,14 12,14Z"
                                      Fill="#9F7AEA" Width="24" Height="24" Stretch="Uniform"/>
                                <TextBlock Text="Personal Devices"
                                         Foreground="#A0AEC0"
                                         FontSize="14"
                                         Margin="12,0,0,0"
                                         VerticalAlignment="Center"/>
                            </StackPanel>
                            <TextBlock Grid.Row="1"
                                     x:Name="PersonalDevicesCount"
                                     Text="0"
                                     Foreground="#9F7AEA"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="BYOD Devices in Intune"
                                     Foreground="#718096"
                                     FontSize="12"/>
                            <ProgressBar x:Name="PersonalDevicesProgress"
                                       Grid.Row="3"
                                       Height="4"
                                       Margin="0,12,0,0"
                                       Background="#2D3748"
                                       Foreground="#9F7AEA"
                                       Value="0"/>
                        </Grid>
                    </Border>

                    <!-- Corporate Devices -->
                    <Border x:Name="CorporateDevicesCard" Grid.Column="1" Background="#1B2A47" Margin="10,0" CornerRadius="8" Height="220" Cursor="Hand">
                        <Border.Style>
                            <Style TargetType="Border">
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#243447"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Border.Style>
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
                                <Path Data="M18,15H16V17H18M18,11H16V13H18M20,19H12V17H14V15H12V13H14V11H12V9H20M10,7H8V5H10M10,11H8V9H10M10,15H8V13H10M10,19H8V17H10M6,7H4V5H6M6,11H4V9H6M6,15H4V13H6M6,19H4V17H6M12,7V3H2V21H22V7H12Z"
                                      Fill="#4FD1C5" Width="24" Height="24" Stretch="Uniform"/>
                                <TextBlock Text="Corporate Devices"
                                         Foreground="#A0AEC0"
                                         FontSize="14"
                                         Margin="12,0,0,0"
                                         VerticalAlignment="Center"/>
                            </StackPanel>
                            <TextBlock Grid.Row="1"
                                     x:Name="CorporateDevicesCount"
                                     Text="0"
                                     Foreground="#4FD1C5"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="Company Devices in Intune"
                                     Foreground="#718096"
                                     FontSize="12"/>
                            <ProgressBar x:Name="CorporateDevicesProgress"
                                       Grid.Row="3"
                                       Height="4"
                                       Margin="0,12,0,0"
                                       Background="#2D3748"
                                       Foreground="#4FD1C5"
                                       Value="0"/>
                        </Grid>
                    </Border>

                    <!-- Platform Distribution -->
                    <Border Grid.Column="2" Background="#1B2A47" Margin="10,0,0,0" CornerRadius="8" Height="220">
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
                                <Path Data="M4,6H20V16H4M20,18A2,2 0 0,0 22,16V6C22,4.89 21.1,4 20,4H4C2.89,4 2,4.89 2,6V16A2,2 0 0,0 4,18H0V20H24V18H20Z"
                                      Fill="#4299E1" Width="24" Height="24" Stretch="Uniform"/>
                                <TextBlock Text="Platform Distribution"
                                         Foreground="#A0AEC0"
                                         FontSize="14"
                                         Margin="12,0,0,0"
                                         VerticalAlignment="Center"/>
                            </StackPanel>
                            <Grid Grid.Row="1">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                
                                <!-- Pie Chart Canvas -->
                                <Canvas x:Name="PlatformDistributionCanvas" 
                                        Grid.Column="0"
                                        Width="200" 
                                        Height="200" 
                                        HorizontalAlignment="Center"
                                        VerticalAlignment="Center"/>
                                
                                <!-- Legend -->
                                <StackPanel x:Name="PlatformDistributionLegend"
                                            Grid.Column="1"
                                            Margin="20,0,0,0"
                                            VerticalAlignment="Center"/>
                            </Grid>
                        </Grid>
                    </Border>
                </Grid>
            </Grid>

            <!-- Device Management Page -->
            <Grid x:Name="DeviceManagementPage">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Search Controls -->
                <Grid Grid.Row="1" Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="150"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <ComboBox x:Name="dropdown" 
                              Margin="0,0,8,0"/>
                    <TextBox x:Name="SearchInputText" 
                             Grid.Column="1" 
                             Margin="0,0,8,0"
                             TextWrapping="Wrap"
                             AcceptsReturn="True"
                             VerticalScrollBarVisibility="Auto"/>
                    <Button x:Name="bulk_import_button" 
                            Grid.Column="2" 
                            Content="Bulk Import" 
                            Margin="0,0,8,0"/>
                    <Button x:Name="SearchButton" 
                            Grid.Column="3" 
                            Content="Search"/>
                </Grid>

                <!-- Results Grid -->
                <DataGrid x:Name="SearchResultsDataGrid" 
                          Grid.Row="3"
                          Margin="0,0,0,15"
                          AutoGenerateColumns="False"
                          IsReadOnly="False"
                          HeadersVisibility="Column"
                          GridLinesVisibility="All"
                          CanUserResizeRows="False"
                          CanUserReorderColumns="False"
                          SelectionMode="Extended"
                          SelectionUnit="FullRow"
                          CanUserAddRows="False">
                    <DataGrid.Columns>
                        <DataGridCheckBoxColumn Binding="{Binding IsSelected, UpdateSourceTrigger=PropertyChanged, Mode=TwoWay}" 
                                              Header="Select" 
                                              Width="50"
                                              IsReadOnly="False"/>
                        <DataGridTextColumn Binding="{Binding DeviceName}" 
                                                  Header="Device Name" 
                                                  Width="*"
                                                  IsReadOnly="True"/>
                        <DataGridTextColumn Binding="{Binding SerialNumber}" 
                                                  Header="Serial Number" 
                                                  Width="*"
                                                  IsReadOnly="True"/>
                        <DataGridTextColumn Binding="{Binding OperatingSystem}" 
                                                  Header="OS" 
                                                  Width="*"
                                                  IsReadOnly="True"/>
                        <DataGridTextColumn Binding="{Binding PrimaryUser}" 
                                                  Header="Primary User" 
                                                  Width="*"
                                                  IsReadOnly="True"/>
                        <DataGridTextColumn Binding="{Binding AzureADLastContact}" 
                                                  Header="Entra ID Last Contact" 
                                                  Width="*"
                                                  IsReadOnly="True"/>
                        <DataGridTextColumn Binding="{Binding IntuneLastContact}" 
                                                  Header="Intune Last Contact" 
                                                  Width="*"
                                                  IsReadOnly="True"/>
                        <DataGridTextColumn Binding="{Binding AutopilotLastContact}" 
                                                  Header="Autopilot Last Contact" 
                                                  Width="*"
                                                  IsReadOnly="True"/>
                        <DataGridTextColumn Binding="{Binding SCCMLastContact}" 
                                                  Header="SCCM Last Contact" 
                                                  Width="*"
                                                  IsReadOnly="True"/>
                    </DataGrid.Columns>
                </DataGrid>

                <!-- Status Section -->
                <UniformGrid Grid.Row="4"
                           Rows="1"
                           Margin="0,0,0,15">
                    <!-- Intune Status -->
                    <Border Background="#1B2A47"
                            Margin="0,0,8,0"
                            CornerRadius="6"
                            Effect="{StaticResource CardShadow}">
                        <Grid Margin="12,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Path Data="M21,14V4H3V14H21M21,2A2,2 0 0,1 23,4V16A2,2 0 0,1 21,18H14L16,21V22H8V21L10,18H3C1.89,18 1,17.1 1,16V4C1,2.89 1.89,2 3,2H21M4,5H20V13H4V5Z"
                                  Fill="#4299E1"
                                  Width="20"
                                  Height="20"
                                  Stretch="Uniform"
                                  VerticalAlignment="Center"/>
                            <TextBlock x:Name="intune_status"
                                     Grid.Column="1"
                                     Margin="8,0,0,0"
                                     FontSize="13"
                                     Text="Intune"
                                     Foreground="White"
                                     VerticalAlignment="Center"/>
                        </Grid>
                    </Border>

                    <!-- Autopilot Status -->
                    <Border Background="#1B2A47"
                            Margin="8,0"
                            CornerRadius="6"
                            Effect="{StaticResource CardShadow}">
                        <Grid Margin="12,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Path Data="M12,3L1,9L12,15L21,10.09V17H23V9M5,13.18V17.18L12,21L19,17.18V13.18L12,17L5,13.18Z"
                                  Fill="#48BB78"
                                  Width="20"
                                  Height="20"
                                  Stretch="Uniform"
                                  VerticalAlignment="Center"/>
                            <TextBlock x:Name="autopilot_status"
                                     Grid.Column="1"
                                     Margin="8,0,0,0"
                                     FontSize="13"
                                     Text="Autopilot"
                                     Foreground="White"
                                     VerticalAlignment="Center"/>
                        </Grid>
                    </Border>

                    <!-- Entra ID Status -->
                    <Border Background="#1B2A47"
                            Margin="8,0,0,0"
                            CornerRadius="6"
                            Effect="{StaticResource CardShadow}">
                        <Grid Margin="12,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Path Data="M13.05,4.24L6.56,18.05L2,18L7.09,9.24L13.05,4.24M13.75,5.33L22,19.76H6.74L16.04,18.1L11.17,12.31L13.75,5.33Z"
                                  Fill="#ED64A6"
                                  Width="20"
                                  Height="20"
                                  Stretch="Uniform"
                                  VerticalAlignment="Center"/>
                            <TextBlock x:Name="aad_status"
                                     Grid.Column="1"
                                     Margin="8,0,0,0"
                                     FontSize="13"
                                     Text="Entra ID"
                                     Foreground="White"
                                     VerticalAlignment="Center"/>
                        </Grid>
                    </Border>

                    <!-- SCCM Status -->
                    <Border Background="#1B2A47"
                            Margin="17,0,0,0"
                            CornerRadius="6"
                            Effect="{StaticResource CardShadow}">
                        <Grid Margin="12,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Path Data="m124.326-8.588 0 9.63c.964 58.745.001 43.336.28 73.96-.01 2.13-1.11 4.33-2.02 6.35-2.46 5.41-5.99 10.5-7.47 16.14-3.37 12.84-.25 24.68 7.68 35.31 3.81 5.11 2.96 7.64-2.7 10.1-3.03 1.32-5.93 3.01-8.69 4.83-23.23 15.29-24.92 60.96 1.44 77.85-33.02 0-66.04 0-89.156.326-.27-59.84.564-155.244-.963-234.014M44.16 85.04c6.86 0 13.72 0 20.65 0 0-6.72 0-13.56 0-20.45-7.07 0-13.8 0-20.9 0 0 6.68 0 13.11.25 20.45m50.94.53c.54-6.9 1.08-13.8 1.64-20.93-7.83 0-14.7 0-21.56 0 0 7.05 0 13.79 0 21 6.47 0 12.72 0 19.92-.07m-51.2 64c0 4.25 0 8.49 0 12.85 7.34 0 14.07 0 21.02 0 0-6.95 0-13.68 0-20.54-7.02 0-13.89 0-21.02 0 0 2.44 0 4.58 0 7.69m40.65-7.99c-3.11 0-6.22 0-9.31 0 0 7.24 0 13.97 0 20.85 7 0 13.73 0 20.72 0 0-6.94 0-13.66 0-20.85-3.53 0-6.99 0-11.41 0m-40.64-22.17c0 1.44 0 2.87 0 4.34 7.34 0 14.19 0 20.98 0 0-7.03 0-13.75 0-20.5-7.09 0-13.95 0-20.98 0 0 5.26 0 10.22 0 16.16m31.07-2.96c0 2.43 0 4.86 0 7.29 7.36 0 14.22 0 20.98 0 0-7.03 0-13.76 0-20.48-7.1 0-13.96 0-20.98 0 0 4.28 0 8.25 0 13.19zM127.47 226c-1.29-.79-1.97-1.88-2.94-2.32-13.82-6.29-21.43-16.87-22.52-32.09-1.27-17.82 3.31-32.84 20.54-41.28 4.35-2.13 9.4-2.83 14.06-4.17 5.25 14.73 10.75 18.98 22.61 18.18 10.2-.69 15.52-5.73 18.09-17.12 14.16-.87 29.37 9.33 33.28 23.68 4.17 15.28 4.37 30.67-7.23 43.24-4.33 4.69-10.61 7.58-15.67 11.58-19.7.29-39.72.29-60.21.29zM165.71 73.03c18.8 5.11 27.42 21.88 27.16 35.06-.31 15.41-11.84 29.97-27.09 33.78-14.91 3.72-31.78-3.51-38.92-16.68-8.28-15.27-5.92-32.22 6.19-43.35 9.2-8.46 19.94-11.61 32.67-8.81z"
                                  Fill="#8C57B9"
                                  Width="20"
                                  Height="20"
                                  Stretch="Uniform"
                                  VerticalAlignment="Center"/>
                            <TextBlock x:Name="sccm_status"
                                     Grid.Column="1"
                                     Margin="8,0,0,0"
                                     FontSize="13"
                                     Text="SCCM"
                                     Foreground="White"
                                     VerticalAlignment="Center"/>
                        </Grid>
                    </Border>
                </UniformGrid>

                <!-- Bottom Section -->
                <Grid Grid.Row="5">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <!-- Left Side -->
                    <Button x:Name="OffboardButton"
                            Content="Offboard device(s)"
                            Grid.Column="0"
                            Height="40"
                            Padding="20,0"
                            Background="#DC2626"
                            Foreground="White"
                            BorderThickness="0"
                            Margin="0,0,8,0"
                            Cursor="Hand">
                        <Button.Resources>
                            <Style TargetType="Border">
                                <Setter Property="CornerRadius" Value="6"/>
                            </Style>
                        </Button.Resources>
                        <Button.Style>
                            <Style TargetType="Button">
                                <Setter Property="Template">
                                    <Setter.Value>
                                        <ControlTemplate TargetType="Button">
                                            <Border Background="{TemplateBinding Background}"
                                                    BorderBrush="{TemplateBinding BorderBrush}"
                                                    BorderThickness="{TemplateBinding BorderThickness}"
                                                    CornerRadius="6">
                                                <ContentPresenter HorizontalAlignment="Center"
                                                                VerticalAlignment="Center"
                                                                Margin="{TemplateBinding Padding}"/>
                                            </Border>
                                            <ControlTemplate.Triggers>
                                                <Trigger Property="IsMouseOver" Value="True">
                                                    <Setter Property="Background" Value="#B91C1C"/>
                                                </Trigger>
                                                <Trigger Property="IsEnabled" Value="False">
                                                    <Setter Property="Background" Value="#FCA5A5"/>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                            </Style>
                        </Button.Style>
                    </Button>
                    
                    <!-- Export Button -->
                    <Button x:Name="ExportSearchResultsButton"
                            Content="Export Results"
                            Grid.Column="1"
                            Height="40"
                            MinWidth="140"
                            Padding="20,0"
                            Background="#0078D4"
                            Foreground="White"
                            BorderThickness="0"
                            Margin="0,0,8,0"
                            Cursor="Hand">
                        <Button.Resources>
                            <Style TargetType="Border">
                                <Setter Property="CornerRadius" Value="6"/>
                            </Style>
                        </Button.Resources>
                        <Button.Style>
                            <Style TargetType="Button">
                                <Setter Property="Template">
                                    <Setter.Value>
                                        <ControlTemplate TargetType="Button">
                                            <Border Background="{TemplateBinding Background}"
                                                    BorderBrush="{TemplateBinding BorderBrush}"
                                                    BorderThickness="{TemplateBinding BorderThickness}"
                                                    CornerRadius="6">
                                                <ContentPresenter HorizontalAlignment="Center"
                                                                VerticalAlignment="Center"
                                                                Margin="{TemplateBinding Padding}"/>
                                            </Border>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                            </Style>
                        </Button.Style>
                    </Button>
                    
                    <!-- Export Selected Button -->
                    <Button x:Name="ExportSelectedButton"
                            Content="Export Selected"
                            Grid.Column="2"
                            Height="40"
                            MinWidth="140"
                            Padding="20,0"
                            Background="#059669"
                            Foreground="White"
                            BorderThickness="0"
                            Margin="0,0,8,0"
                            Cursor="Hand"
                            IsEnabled="False">
                        <Button.Resources>
                            <Style TargetType="Border">
                                <Setter Property="CornerRadius" Value="6"/>
                            </Style>
                        </Button.Resources>
                        <Button.Style>
                            <Style TargetType="Button">
                                <Setter Property="Template">
                                    <Setter.Value>
                                        <ControlTemplate TargetType="Button">
                                            <Border Background="{TemplateBinding Background}"
                                                    BorderBrush="{TemplateBinding BorderBrush}"
                                                    BorderThickness="{TemplateBinding BorderThickness}"
                                                    CornerRadius="6">
                                                <ContentPresenter HorizontalAlignment="Center"
                                                                VerticalAlignment="Center"
                                                                Margin="{TemplateBinding Padding}"/>
                                            </Border>
                                            <ControlTemplate.Triggers>
                                                <Trigger Property="IsMouseOver" Value="True">
                                                    <Setter Property="Background" Value="#047857"/>
                                                </Trigger>
                                                <Trigger Property="IsEnabled" Value="False">
                                                    <Setter Property="Background" Value="#A7F3D0"/>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                            </Style>
                        </Button.Style>
                    </Button>
                </Grid>
            </Grid>

            <!-- Playbooks Page -->
            <Grid x:Name="PlaybooksPage" Visibility="Collapsed">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <Grid Grid.Row="0" Margin="20">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Text="Playbooks"
                             FontSize="32"
                             FontWeight="Bold"
                             Foreground="#323130"
                             Margin="0,0,0,10"/>
                    <TextBlock Grid.Row="1"
                             Text="Automated device management tasks and reports"
                             FontSize="16"
                             Opacity="0.7"/>
                </Grid>

                <ScrollViewer Grid.Row="1"
                             x:Name="PlaybooksScrollViewer"
                             Margin="20,0,20,20"
                             VerticalScrollBarVisibility="Auto">
                    <WrapPanel>
                        <Button x:Name="PlaybookAutopilotNotIntune"
                                Style="{StaticResource PlaybookButtonStyle}"
                                Width="380"
                                Height="120"
                                Margin="0,0,15,15"
                                Content="Autopilot Devices Not in Intune"
                                Tag="Identify devices registered in Autopilot but missing from Intune management"/>
                        <Button x:Name="PlaybookIntuneNotAutopilot"
                                Style="{StaticResource PlaybookButtonStyle}"
                                Width="380"
                                Height="120"
                                Margin="0,0,15,15"
                                Content="Intune Devices Not in Autopilot"
                                Tag="Find managed devices that aren't registered in Autopilot"/>
                        <Button x:Name="PlaybookCorporateDevices"
                                Style="{StaticResource PlaybookButtonStyle}"
                                Width="380"
                                Height="120"
                                Margin="0,0,15,15"
                                Content="Corporate Device Inventory"
                                Tag="View all company-owned devices managed in Intune"/>
                        <Button x:Name="PlaybookPersonalDevices"
                                Style="{StaticResource PlaybookButtonStyle}"
                                Width="380"
                                Height="120"
                                Margin="0,0,15,15"
                                Content="Personal Device Inventory"
                                Tag="List all BYOD devices enrolled in Intune"/>
                        <Button x:Name="PlaybookStaleDevices"
                                Style="{StaticResource PlaybookButtonStyle}"
                                Width="380"
                                Height="120"
                                Margin="0,0,15,15"
                                Content="Stale Device Report"
                                Tag="Identify devices that haven't checked in recently"/>
                        <Button x:Name="PlaybookSpecificOS"
                                Style="{StaticResource PlaybookButtonStyle}"
                                Width="380"
                                Height="120"
                                Margin="0,0,15,15"
                                Content="OS-Specific Device List"
                                Tag="Filter devices by operating system version"
                                IsEnabled="False"/>
                        <Button x:Name="PlaybookNotLatestOS"
                                Style="{StaticResource PlaybookButtonStyle}"
                                Width="380"
                                Height="120"
                                Margin="0,0,15,15"
                                Content="Outdated OS Report"
                                Tag="Find devices running older operating system versions"
                                IsEnabled="False"/>
                        <Button x:Name="PlaybookEOLOS"
                                Style="{StaticResource PlaybookButtonStyle}"
                                Width="380"
                                Height="120"
                                Margin="0,0,15,15"
                                Content="End-of-Life OS Report"
                                Tag="Identify devices running unsupported OS versions"
                                IsEnabled="False"/>
                        <Button x:Name="PlaybookBitLocker"
                                Style="{StaticResource PlaybookButtonStyle}"
                                Width="380"
                                Height="120"
                                Margin="0,0,15,15"
                                Content="BitLocker Key Report"
                                Tag="View BitLocker recovery keys for Windows devices"
                                IsEnabled="False"/>
                        <Button x:Name="PlaybookFileVault"
                                Style="{StaticResource PlaybookButtonStyle}"
                                Width="380"
                                Height="120"
                                Margin="0,0,15,15"
                                Content="FileVault Key Report"
                                Tag="View FileVault recovery keys for macOS devices"
                                IsEnabled="False"/>
                    </WrapPanel>
                </ScrollViewer>

                <!-- Playbook Results -->
                <Grid x:Name="PlaybookResultsGrid" 
                      Visibility="Collapsed"
                      Grid.Row="1">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>  <!-- Back button -->
                        <RowDefinition Height="Auto"/>  <!-- Results header -->
                        <RowDefinition Height="*"/>     <!-- DataGrid -->
                    </Grid.RowDefinitions>
                    <!-- Header with Back Button -->
                    <Grid Grid.Row="0" Margin="20,0,20,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <Button Grid.Column="0"
                                x:Name="BackToPlaybooksButton"
                                Content="← Back to Playbooks"
                                Height="32"
                                Padding="12,0"
                                Background="#F0F0F0"
                                Foreground="#2D3748"
                                BorderThickness="0">
                            <Button.Resources>
                                <Style TargetType="Border">
                                    <Setter Property="CornerRadius" Value="4"/>
                                </Style>
                            </Button.Resources>
                        </Button>
                        <Button Grid.Column="2"
                                x:Name="ExportPlaybookResultsButton"
                                Content="Export to CSV"
                                Height="32"
                                Padding="12,0"
                                Background="#0078D4"
                                Foreground="White"
                                BorderThickness="0">
                            <Button.Resources>
                                <Style TargetType="Border">
                                    <Setter Property="CornerRadius" Value="4"/>
                                </Style>
                            </Button.Resources>
                        </Button>
                    </Grid>
                    <!-- Results Header -->
                    <TextBlock Grid.Row="1"
                              x:Name="PlaybookResultsHeader"
                              Text="Devices in Autopilot but not in Intune"
                              FontSize="20"
                              FontWeight="SemiBold"
                              Margin="20,0,20,10"/>
                    <!-- Results DataGrid -->
                    <DataGrid x:Name="PlaybookResultsDataGrid"
                              Grid.Row="2"
                             Margin="20"
                              Style="{StaticResource {x:Type DataGrid}}"
                              AutoGenerateColumns="False"
                              IsReadOnly="True"
                              HeadersVisibility="Column"
                              GridLinesVisibility="All"
                              AlternatingRowBackground="#F8F8F8">
                        <DataGrid.Columns>
                            <DataGridTextColumn Header="Device Name"
                                              Binding="{Binding DeviceName}"
                                              Width="*"/>
                            <DataGridTextColumn Header="Serial Number"
                                              Binding="{Binding SerialNumber}"
                                              Width="*"/>
                            <DataGridTextColumn Header="Operating System"
                                              Binding="{Binding OperatingSystem}"
                                              Width="*"/>
                            <DataGridTextColumn Header="Primary User"
                                              Binding="{Binding PrimaryUser}"
                                              Width="*"/>
                            <DataGridTextColumn Header="Last Contact"
                                              Binding="{Binding AutopilotLastContact}"
                                              Width="*"/>
                        </DataGrid.Columns>
                    </DataGrid>
                </Grid>
            </Grid>
        </Grid>
    </Grid>
</Window>
"@

# Define Changelog Modal XAML
[xml]$changelogModalXaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Changelog" Height="600" Width="800"
    WindowStartupLocation="CenterScreen"
    Background="#F8F9FA">
    
    <Border Background="White"
            CornerRadius="8"
            Margin="16">
        <DockPanel Margin="24">
            <!-- Header -->
            <StackPanel DockPanel.Dock="Top"
                       Margin="0,0,0,24">
                <TextBlock Text="Changelog"
                          FontSize="24"
                          FontWeight="SemiBold"
                          Foreground="#1A202C"/>
            </StackPanel>

            <!-- Close Button -->
            <Button x:Name="CloseChangelogButton"
                    DockPanel.Dock="Bottom"
                    Content="Close"
                    Width="120"
                    Height="40"
                    Background="#F0F0F0"
                    Foreground="#2D3748"
                    BorderThickness="0"
                    HorizontalAlignment="Right"
                    Margin="0,24,0,0"/>

            <!-- Changelog Content -->
            <ScrollViewer VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Auto">
                <RichTextBox x:Name="ChangelogContent"
                            Background="Transparent"
                            BorderThickness="0"
                            IsReadOnly="True"
                            Margin="20"
                            Width="Auto">
                    <RichTextBox.Resources>
                        <Style TargetType="{x:Type Paragraph}">
                            <Setter Property="Margin" Value="0,0,0,10"/>
                        </Style>
                    </RichTextBox.Resources>
                    <RichTextBox.Document>
                        <FlowDocument PageWidth="{Binding ActualWidth, RelativeSource={RelativeSource AncestorType=ScrollViewer}}">
                        </FlowDocument>
                    </RichTextBox.Document>
                </RichTextBox>
            </ScrollViewer>
        </DockPanel>
    </Border>
</Window>
"@

# Define Prerequisites Modal XAML
[xml]$prerequisitesModalXaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Prerequisites Check" Height="500" Width="600"
    WindowStartupLocation="CenterScreen"
    Background="#F8F9FA">
    
    <Window.Resources>
        <Style x:Key="CheckItemStyle" TargetType="StackPanel">
            <Setter Property="Margin" Value="0,8,0,8"/>
        </Style>
        
        <Style x:Key="CheckTextStyle" TargetType="TextBlock">
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin" Value="8,0,0,0"/>
            <Setter Property="FontSize" Value="14"/>
        </Style>
        
        <Style x:Key="InstallButtonStyle" TargetType="Button">
            <Setter Property="Margin" Value="8,0,0,0"/>
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="Background" Value="#0078D4"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
        </Style>
    </Window.Resources>

    <Border Background="White"
            CornerRadius="8"
            Margin="16">
        <DockPanel Margin="24">
            <!-- Header -->
            <StackPanel DockPanel.Dock="Top"
                       Margin="0,0,0,24">
                <TextBlock Text="Prerequisites Check"
                          FontSize="24"
                          FontWeight="SemiBold"
                          Foreground="#1A202C"/>
                <TextBlock Text="Checking required permissions and modules"
                          Foreground="#4A5568"
                          FontSize="14"
                          Margin="0,8,0,0"/>
            </StackPanel>

            <!-- Action Buttons -->
            <StackPanel DockPanel.Dock="Bottom"
                       Orientation="Horizontal"
                       HorizontalAlignment="Right"
                       Margin="0,24,0,0">
                <Button x:Name="ClosePrereqButton"
                        Content="Close"
                        Width="120"
                        Height="40"
                        Background="#F0F0F0"
                        Foreground="#2D3748"
                        BorderThickness="0"/>
            </StackPanel>

            <!-- Scrollable Content -->
            <ScrollViewer VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Disabled">
                <StackPanel>
                    <!-- API Permissions Section -->
                    <TextBlock Text="API Permissions"
                             FontSize="18"
                             FontWeight="SemiBold"
                             Margin="0,0,0,16"/>
                             
                    <StackPanel x:Name="PermissionsPanel">
                        <!-- Permissions will be added here dynamically -->
                    </StackPanel>

                    <!-- Module Section -->
                    <TextBlock Text="Required Modules"
                             FontSize="18"
                             FontWeight="SemiBold"
                             Margin="0,24,0,16"/>
                             
                    <StackPanel x:Name="ModulePanel">
                        <!-- Module check will be added here dynamically -->
                    </StackPanel>
                </StackPanel>
            </ScrollViewer>
        </DockPanel>
    </Border>
</Window>
"@

# Define Authentication Modal XAML
[xml]$authModalXaml = @"
<Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Authentication" Height="690" Width="650"
    WindowStartupLocation="CenterScreen"
    Background="#F8F9FA">
    
    <Window.Resources>
        <!-- Radio Button Style -->
        <Style x:Key="AuthRadioButtonStyle" TargetType="RadioButton">
            <Setter Property="Margin" Value="0,8,8,8"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Foreground" Value="#2D3748"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RadioButton">
                        <Border x:Name="border" 
                                Background="{TemplateBinding Background}"
                                BorderBrush="#E2E8F0"
                                BorderThickness="1"
                                CornerRadius="6"
                                Padding="12">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="24"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Ellipse x:Name="radioOuter"
                                         Width="18" Height="18"
                                         Stroke="#CBD5E0"
                                         StrokeThickness="2"
                                         Fill="Transparent"/>
                                <Ellipse x:Name="radioInner"
                                         Width="10" Height="10"
                                         Fill="#0078D4"
                                         Opacity="0"/>
                                <ContentPresenter Grid.Column="1"
                                                Margin="12,0,0,0"
                                                VerticalAlignment="Center"/>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#F7FAFC"/>
                                <Setter TargetName="radioOuter" Property="Stroke" Value="#0078D4"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="radioInner" Property="Opacity" Value="1"/>
                                <Setter TargetName="radioOuter" Property="Stroke" Value="#0078D4"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="#0078D4"/>
                                <Setter TargetName="border" Property="Background" Value="#F0F9FF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- TextBox Style -->
        <Style x:Key="AuthTextBoxStyle" TargetType="TextBox">
            <Setter Property="Height" Value="36"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="Margin" Value="0,4"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="#E2E8F0"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="BorderBrush" Value="#0078D4"/>
                </Trigger>
                <Trigger Property="IsFocused" Value="True">
                    <Setter Property="BorderBrush" Value="#0078D4"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Password Box Style -->
        <Style x:Key="AuthPasswordBoxStyle" TargetType="PasswordBox">
            <Setter Property="Height" Value="36"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="Margin" Value="0,4"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="#E2E8F0"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>

        <!-- Button Style -->
        <Style x:Key="AuthButtonStyle" TargetType="Button">
            <Setter Property="Height" Value="40"/>
            <Setter Property="Padding" Value="24,0"/>
            <Setter Property="Background" Value="#0078D4"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" 
                                            VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#106EBE"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#005A9E"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Secondary Button Style -->
        <Style x:Key="SecondaryButtonStyle" TargetType="Button">
            <Setter Property="Height" Value="40"/>
            <Setter Property="Padding" Value="24,0"/>
            <Setter Property="Background" Value="#F0F0F0"/>
            <Setter Property="Foreground" Value="#2D3748"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" 
                                            VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#E2E2E2"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#D4D4D4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Border Background="White" 
            CornerRadius="8" 
            Margin="16">
        <DockPanel Margin="24">
            <!-- Header -->
            <StackPanel DockPanel.Dock="Top" 
                       Margin="0,0,0,24">
                <TextBlock Text="Connect to Microsoft Graph" 
                          FontSize="24" 
                          FontWeight="SemiBold" 
                          Foreground="#1A202C"/>
                <TextBlock Text="Choose your preferred authentication method to connect to Microsoft Graph API"
                          Foreground="#4A5568"
                          FontSize="14"
                          Margin="0,8,0,0"/>
            </StackPanel>

            <!-- Action Buttons -->
            <StackPanel DockPanel.Dock="Bottom" 
                       Orientation="Horizontal" 
                       HorizontalAlignment="Right"
                       Margin="0,24,0,0">
                <Button x:Name="CancelAuthButton" 
                        Content="Cancel" 
                        Style="{StaticResource SecondaryButtonStyle}"
                        Width="120" 
                        Margin="0,0,12,0"/>
                <Button x:Name="ConnectButton" 
                        Content="Connect" 
                        Style="{StaticResource AuthButtonStyle}"
                        Width="120"/>
            </StackPanel>

            <!-- Scrollable Content -->
            <ScrollViewer VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Disabled"
                         Padding="0,0,16,0">
                <StackPanel Margin="0,0,8,0">
                    <RadioButton x:Name="InteractiveAuth" 
                                Style="{StaticResource AuthRadioButtonStyle}"
                                Content="Interactive Login (Admin User)" 
                                IsChecked="True"/>
                    
                    <RadioButton x:Name="CertificateAuth" 
                                Style="{StaticResource AuthRadioButtonStyle}"
                                Content="App Registration with Certificate"/>
                    
                    <Grid x:Name="CertificateInputs" 
                          Margin="44,8,0,16" 
                          Visibility="Collapsed">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="100"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <TextBlock Text="App ID" 
                                  Grid.Row="0" 
                                  VerticalAlignment="Center"
                                  Foreground="#4A5568"/>
                        <TextBox x:Name="CertAppId" 
                                 Grid.Row="0" 
                                 Grid.Column="1"
                                 Style="{StaticResource AuthTextBoxStyle}"/>

                        <TextBlock Text="Tenant ID" 
                                  Grid.Row="1" 
                                  VerticalAlignment="Center"
                                  Foreground="#4A5568"/>
                        <TextBox x:Name="CertTenantId" 
                                 Grid.Row="1" 
                                 Grid.Column="1"
                                 Style="{StaticResource AuthTextBoxStyle}"/>

                        <TextBlock Text="Thumbprint" 
                                  Grid.Row="2" 
                                  VerticalAlignment="Center"
                                  Foreground="#4A5568"/>
                        <TextBox x:Name="CertThumbprint" 
                                 Grid.Row="2" 
                                 Grid.Column="1"
                                 Style="{StaticResource AuthTextBoxStyle}"/>

                        <!-- Import Button -->
                        <Button x:Name="ImportCertButton"
                                Grid.Row="3"
                                Grid.Column="1"
                                Content="Import"
                                HorizontalAlignment="Right"
                                Style="{StaticResource SecondaryButtonStyle}"
                                Height="32"
                                Width="120"
                                Margin="0,12,0,0"/>

                        <!-- Help Text -->
                        <TextBlock Grid.Row="4" 
                                  Grid.Column="0"
                                  Grid.ColumnSpan="2"
                                  Text="Import format: JSON file (.json) containing AppId, TenantId, and Thumbprint"
                                  Foreground="#718096"
                                  HorizontalAlignment="Right"
                                  FontSize="12"
                                  Margin="0,8,0,0"
                                  TextWrapping="Wrap"/>
                    </Grid>

                    <RadioButton x:Name="SecretAuth" 
                                Style="{StaticResource AuthRadioButtonStyle}"
                                Content="App Registration with Secret"/>
                    
                    <Grid x:Name="SecretInputs" 
                          Margin="44,8,0,16" 
                          Visibility="Collapsed">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="100"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <TextBlock Text="App ID" 
                                  Grid.Row="0" 
                                  VerticalAlignment="Center"
                                  Foreground="#4A5568"/>
                        <TextBox x:Name="SecretAppId" 
                                 Grid.Row="0" 
                                 Grid.Column="1"
                                 Style="{StaticResource AuthTextBoxStyle}"/>

                        <TextBlock Text="Tenant ID" 
                                  Grid.Row="1" 
                                  VerticalAlignment="Center"
                                  Foreground="#4A5568"/>
                        <TextBox x:Name="SecretTenantId" 
                                 Grid.Row="1" 
                                 Grid.Column="1"
                                 Style="{StaticResource AuthTextBoxStyle}"/>

                        <TextBlock Text="Client Secret" 
                                  Grid.Row="2" 
                                  VerticalAlignment="Center"
                                  Foreground="#4A5568"/>
                        <PasswordBox x:Name="ClientSecret" 
                                    Grid.Row="2" 
                                    Grid.Column="1"
                                    Style="{StaticResource AuthPasswordBoxStyle}"/>

                        <!-- Import Button -->
                        <Button x:Name="ImportSecretButton"
                                Grid.Row="3"
                                Grid.Column="1"
                                Content="Import"
                                HorizontalAlignment="Right"
                                Style="{StaticResource SecondaryButtonStyle}"
                                Height="32"
                                Width="120"
                                Margin="0,12,0,0"/>

                        <RadioButton x:Name="UseSecretFromJsonRadio"
                                     Grid.Row="3"
                                     Grid.Column="0"
                                     Grid.ColumnSpan="2"
                                     Content="Remember Secret"
                                     Style="{StaticResource AuthRadioButtonStyle}"
                                     VerticalAlignment="Center"
                                     HorizontalAlignment="Left"
                                     Width="Auto"/>

                        <!-- Help Text -->
                        <TextBlock Grid.Row="4" 
                                  Grid.Column="0"
                                  Grid.ColumnSpan="2"
                                  Text="Import format: JSON file (.json) containing AppId, TenantId, and ClientSecret"
                                  Foreground="#718096"
                                  HorizontalAlignment="Right"
                                  FontSize="12"
                                  Margin="0,8,0,0"
                                  TextWrapping="Wrap"/>
                    </Grid>
                </StackPanel>
            </ScrollViewer>
        </DockPanel>
    </Border>
</Window>
"@

# Bulk Import Modal XAML
[xml]$bulkImportModalXaml = @"
<Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Bulk Import Devices" Height="650" Width="700"
    WindowStartupLocation="CenterScreen"
    Background="#F8F9FA">
    
    <Window.Resources>
        <!-- Button Styles -->
        <Style x:Key="BulkImportButtonStyle" TargetType="Button">
            <Setter Property="Height" Value="40"/>
            <Setter Property="Padding" Value="24,0"/>
            <Setter Property="Background" Value="#0078D4"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" 
                                            VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#106EBE"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#005A9E"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#CCCCCC"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="BulkImportSecondaryButtonStyle" TargetType="Button">
            <Setter Property="Height" Value="40"/>
            <Setter Property="Padding" Value="24,0"/>
            <Setter Property="Background" Value="#F0F0F0"/>
            <Setter Property="Foreground" Value="#2D3748"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" 
                                            VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#E2E2E2"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#D4D4D4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- TextBox Style -->
        <Style x:Key="BulkImportTextBoxStyle" TargetType="TextBox">
            <Setter Property="Height" Value="36"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="Margin" Value="0,4"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="#E2E8F0"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="BorderBrush" Value="#0078D4"/>
                </Trigger>
                <Trigger Property="IsFocused" Value="True">
                    <Setter Property="BorderBrush" Value="#0078D4"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Border Background="White" 
            CornerRadius="8" 
            Margin="16">
        <DockPanel Margin="24">
            <!-- Header -->
            <StackPanel DockPanel.Dock="Top" Margin="0,0,0,24">
                <TextBlock Text="Bulk Import Devices" 
                          FontSize="24" 
                          FontWeight="SemiBold" 
                          Foreground="#1A202C"/>
                <TextBlock Text="Import multiple devices from a CSV or TXT file"
                          Foreground="#4A5568"
                          FontSize="14"
                          Margin="0,8,0,0"/>
            </StackPanel>

            <!-- Action Buttons -->
            <StackPanel DockPanel.Dock="Bottom" 
                       Orientation="Horizontal" 
                       HorizontalAlignment="Right"
                       Margin="0,24,0,0">
                <Button x:Name="CancelButton" 
                        Content="Cancel" 
                        Style="{StaticResource BulkImportSecondaryButtonStyle}"
                        Width="120" 
                        Margin="0,0,12,0"/>
                <Button x:Name="ImportButton" 
                        Content="Import Devices" 
                        Style="{StaticResource BulkImportButtonStyle}"
                        Width="140"
                        IsEnabled="False"/>
            </StackPanel>

            <!-- Scrollable Content -->
            <ScrollViewer VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Disabled"
                         Padding="0,0,16,0">
                <StackPanel>
                    <!-- CSV Template Section -->
                    <Border Background="#EDF2F7" 
                            BorderBrush="#E2E8F0" 
                            BorderThickness="1" 
                            CornerRadius="6" 
                            Padding="16" 
                            Margin="0,0,0,16">
                        <StackPanel>
                            <TextBlock Text="CSV Template" 
                                      FontWeight="SemiBold" 
                                      FontSize="14" 
                                      Margin="0,0,0,8"/>
                            <TextBlock Text="Your file should contain one device per line. You can use:" 
                                      Margin="0,0,0,8"
                                      Foreground="#4A5568"/>
                            <TextBlock Text="• Device names (e.g., DESKTOP-ABC123)" 
                                      Margin="16,0,0,4"
                                      Foreground="#4A5568"/>
                            <TextBlock Text="• Serial numbers (e.g., 1234567890)" 
                                      Margin="16,0,0,8"
                                      Foreground="#4A5568"/>
                            <Border Background="White" 
                                    BorderBrush="#CBD5E0" 
                                    BorderThickness="1" 
                                    CornerRadius="4" 
                                    Padding="12" 
                                    Margin="0,8,0,8">
                                <TextBlock FontFamily="Consolas" 
                                          FontSize="12"
                                          Foreground="#2D3748">
                                    <Run Text="DESKTOP-ABC123"/><LineBreak/>
                                    <Run Text="LAPTOP-XYZ789"/><LineBreak/>
                                    <Run Text="1234567890"/><LineBreak/>
                                    <Run Text="0987654321"/>
                                </TextBlock>
                            </Border>
                            <Button x:Name="DownloadTemplateButton" 
                                    Content="Download Template" 
                                    Style="{StaticResource BulkImportButtonStyle}" 
                                    Width="180" 
                                    HorizontalAlignment="Left"/>
                        </StackPanel>
                    </Border>

                    <!-- File Upload Section -->
                    <Border Background="#F7FAFC" 
                            BorderBrush="#E2E8F0" 
                            BorderThickness="1" 
                            CornerRadius="6" 
                            Padding="16" 
                            Margin="0,0,0,16">
                        <StackPanel>
                            <TextBlock Text="Upload File" 
                                      FontWeight="SemiBold" 
                                      FontSize="14" 
                                      Margin="0,0,0,8"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="FilePathTextBox" 
                                        Grid.Column="0" 
                                        IsReadOnly="True" 
                                        Style="{StaticResource BulkImportTextBoxStyle}" 
                                        Margin="0,0,8,0"
                                        Text="No file selected"/>
                                <Button x:Name="BrowseFileButton" 
                                        Grid.Column="1" 
                                        Content="Browse..." 
                                        Style="{StaticResource BulkImportSecondaryButtonStyle}" 
                                        Width="100"/>
                            </Grid>
                        </StackPanel>
                    </Border>

                    <!-- Preview Section -->
                    <Border x:Name="PreviewSection" 
                            Visibility="Collapsed" 
                            Background="#FFFFFF" 
                            BorderBrush="#E2E8F0" 
                            BorderThickness="1" 
                            CornerRadius="6" 
                            Padding="16">
                        <Grid Height="200">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <TextBlock Grid.Row="0" 
                                      Text="Preview" 
                                      FontWeight="SemiBold" 
                                      FontSize="14" 
                                      Margin="0,0,0,8"/>
                            <DataGrid x:Name="PreviewDataGrid" 
                                     Grid.Row="1" 
                                     AutoGenerateColumns="False" 
                                     HeadersVisibility="Column" 
                                     GridLinesVisibility="Horizontal"
                                     CanUserAddRows="False"
                                     CanUserDeleteRows="False"
                                     IsReadOnly="True">
                                <DataGrid.Columns>
                                    <DataGridTextColumn Header="Line" 
                                                       Binding="{Binding LineNumber}" 
                                                       Width="50"/>
                                    <DataGridTextColumn Header="Device Identifier" 
                                                       Binding="{Binding DeviceIdentifier}" 
                                                       Width="*"/>
                                </DataGrid.Columns>
                            </DataGrid>
                            <TextBlock x:Name="DeviceCountText" 
                                      Grid.Row="2" 
                                      Margin="0,8,0,0" 
                                      Foreground="#4A5568" 
                                      FontSize="12"/>
                        </Grid>
                    </Border>

                    <!-- Error Section -->
                    <Border x:Name="ErrorSection" 
                            Visibility="Collapsed" 
                            Background="#FEF2F2" 
                            BorderBrush="#FEE2E2" 
                            BorderThickness="1" 
                            CornerRadius="6" 
                            Padding="16" 
                            Margin="0,0,0,16">
                        <StackPanel Orientation="Horizontal">
                            <Path Data="M12,2L1,21H23M12,6L19.53,19H4.47M11,10V13H13V10M11,15V17H13V15" 
                                  Fill="#DC2626" 
                                  Width="24" 
                                  Height="24" 
                                  Stretch="Uniform" 
                                  Margin="0,0,12,0"/>
                            <TextBlock x:Name="ErrorText" 
                                      Text="" 
                                      Foreground="#DC2626" 
                                      TextWrapping="Wrap" 
                                      VerticalAlignment="Center" 
                                      MaxWidth="400"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </ScrollViewer>
        </DockPanel>
    </Border>
</Window>
"@

# Define required permissions with reasons
$script:requiredPermissions = @(
    @{
        Permission = "User.Read.All"
        Reason     = "Required to read user profile information and check group memberships"
    },
    @{
        Permission = "Group.Read.All"
        Reason     = "Needed to read group information and memberships"
    },
    @{
        Permission = "DeviceManagementConfiguration.Read.All"
        Reason     = "Allows reading Intune device configuration policies and their assignments"
    },
    @{
        Permission = "DeviceManagementApps.Read.All"
        Reason     = "Necessary to read mobile app management policies and app configurations"
    },
    @{
        Permission = "DeviceManagementManagedDevices.ReadWrite.All"
        Reason     = "Required to read and modify managed device information and compliance policies"
    },
    @{
        Permission = "Device.Read.All"
        Reason     = "Needed to read device information from Entra ID"
    },
    @{
        Permission = "DeviceManagementServiceConfig.ReadWrite.All"
        Reason     = "Required for Autopilot configuration and management"
    }
)

function Show-AuthenticationDialog {
    try {
        $reader = (New-Object System.Xml.XmlNodeReader $authModalXaml)
        $authWindow = [Windows.Markup.XamlReader]::Load($reader)
        
        if ($null -eq $authWindow) {
            throw "Failed to create authentication window. XamlReader returned null."
        }
    }
    catch {
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error creating authentication window: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to create the authentication dialog. Error: $_",
            "Dialog Creation Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return $null
    }

    # Get controls
    $interactiveAuth = $authWindow.FindName('InteractiveAuth')
    $certificateAuth = $authWindow.FindName('CertificateAuth')
    $secretAuth = $authWindow.FindName('SecretAuth')
    $certificateInputs = $authWindow.FindName('CertificateInputs')
    $secretInputs = $authWindow.FindName('SecretInputs')
    $connectButton = $authWindow.FindName('ConnectButton')
    $cancelAuthButton = $authWindow.FindName('CancelAuthButton')
    $importCertButton = $authWindow.FindName('ImportCertButton')
    $importSecretButton = $authWindow.FindName('ImportSecretButton')

    # Add event handlers for radio buttons
    $certificateAuth.Add_Checked({
            $certificateInputs.Visibility = 'Visible'
            $secretInputs.Visibility = 'Collapsed'
        })

    $secretAuth.Add_Checked({
            $secretInputs.Visibility = 'Visible'
            $certificateInputs.Visibility = 'Collapsed'
        })

    $interactiveAuth.Add_Checked({
            $certificateInputs.Visibility = 'Collapsed'
            $secretInputs.Visibility = 'Collapsed'
        })

    # Add import button handlers
    $importCertButton.Add_Click({
            $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $OpenFileDialog.Filter = "JSON files (*.json)|*.json"
            $OpenFileDialog.Title = "Import Certificate Configuration"
        
            if ($OpenFileDialog.ShowDialog() -eq 'OK') {
                try {
                    $config = Get-Content $OpenFileDialog.FileName | ConvertFrom-Json
                
                    if ($config.AppId -and $config.TenantId -and $config.Thumbprint) {
                        $authWindow.FindName('CertAppId').Text = $config.AppId
                        $authWindow.FindName('CertTenantId').Text = $config.TenantId
                        $authWindow.FindName('CertThumbprint').Text = $config.Thumbprint
                    }
                    else {
                        [System.Windows.MessageBox]::Show(
                            "Invalid configuration file. Please ensure it contains AppId, TenantId, and Thumbprint.",
                            "Invalid Configuration",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Warning
                        )
                    }
                }
                catch {
                    [System.Windows.MessageBox]::Show(
                        "Error reading configuration file: $_",
                        "Error",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Error
                    )
                }
            }
        })

    $importSecretButton.Add_Click({
            $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $OpenFileDialog.Filter = "JSON files (*.json)|*.json"
            $OpenFileDialog.Title = "Import Secret Configuration"
        
            if ($OpenFileDialog.ShowDialog() -eq 'OK') {
                try {
                    $config = Get-Content $OpenFileDialog.FileName | ConvertFrom-Json
                
                    if ($config.AppId -and $config.TenantId -and $config.ClientSecret) {
                        $authWindow.FindName('SecretAppId').Text = $config.AppId
                        $authWindow.FindName('SecretTenantId').Text = $config.TenantId
                        $authWindow.FindName('ClientSecret').Password = $config.ClientSecret
                    }
                    else {
                        [System.Windows.MessageBox]::Show(
                            "Invalid configuration file. Please ensure it contains AppId, TenantId, and ClientSecret.",
                            "Invalid Configuration",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Warning
                        )
                    }
                }
                catch {
                    [System.Windows.MessageBox]::Show(
                        "Error reading configuration file: $_",
                        "Error",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Error
                    )
                }
            }
        })

    # Add event handlers for buttons
    $cancelAuthButton.Add_Click({
            $script:authCancelled = $true
            $authWindow.DialogResult = $false
            $authWindow.Close()
        })

    $connectButton.Add_Click({
            # Validate fields based on selected authentication method
            if ($certificateAuth.IsChecked) {
                if ([string]::IsNullOrWhiteSpace($authWindow.FindName('CertAppId').Text) -or
                    [string]::IsNullOrWhiteSpace($authWindow.FindName('CertTenantId').Text) -or
                    [string]::IsNullOrWhiteSpace($authWindow.FindName('CertThumbprint').Text)) {
                    [System.Windows.MessageBox]::Show(
                        "Please fill in all required fields for certificate authentication.",
                        "Validation Error",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    )
                    return
                }
            }
            elseif ($secretAuth.IsChecked) {
                if ([string]::IsNullOrWhiteSpace($authWindow.FindName('SecretAppId').Text) -or
                    [string]::IsNullOrWhiteSpace($authWindow.FindName('SecretTenantId').Text) -or
                    [string]::IsNullOrWhiteSpace($authWindow.FindName('ClientSecret').Password)) {
                    [System.Windows.MessageBox]::Show(
                        "Please fill in all required fields for client secret authentication.",
                        "Validation Error",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    )
                    return
                }

                # Check if "Remember Secret" is checked and encrypt/save the JSON
                $useSecretRadio = $authWindow.FindName('UseSecretFromJsonRadio')
                if ($useSecretRadio -and $useSecretRadio.IsChecked) {
                    try {
                        $appId = $authWindow.FindName('SecretAppId').Text
                        $tenantId = $authWindow.FindName('SecretTenantId').Text
                        $clientSecret = $authWindow.FindName('ClientSecret').Password

                        $jsonObj = @{
                            AppId        = $appId
                            TenantId     = $tenantId
                            ClientSecret = $clientSecret
                        }
                        $json = $jsonObj | ConvertTo-Json

                        # Save encrypted secret to %localappdata%\DeviceOffBoardingManager
                        $folderPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, "DeviceOffBoardingManager")
                        if (-not (Test-Path $folderPath)) {
                            New-Item -Path $folderPath -ItemType Directory | Out-Null
                        }
                        $secure = ConvertTo-SecureString $json -AsPlainText -Force
                        $encrypted = ConvertFrom-SecureString $secure
                        $secretFilePath = [System.IO.Path]::Combine($env:LOCALAPPDATA, "DeviceOffBoardingManager", "IntuneOffboardingTool_Secret.json")
                        Set-Content -Path $secretFilePath -Value $encrypted
                        [System.Windows.MessageBox]::Show(
                            "Encrypted secret saved successfully.`nFile: $secretFilePath",
                            "Saved",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Information
                        )

                        # Update settings.json to enable RememberSecretAuthentication
                        if (Test-Path $settingsPath) {
                            try {
                                $settings = Get-Content $settingsPath | ConvertFrom-Json
                                $settings.RememberSecretAuthentication = $true
                                $settings | ConvertTo-Json | Set-Content -Path $settingsPath
                            } catch { Write-Log "Error updating settings.json: $_" }
                        }
                    }
                    catch {
                        [System.Windows.MessageBox]::Show(
                            "Failed to save encrypted secret: $_",
                            "Encryption Error",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Error
                        )
                    }
                }
            }

            $script:authCancelled = $false
            $authWindow.DialogResult = $true
            $authWindow.Close()
        })

    # Show dialog and return result
    try {
        if ($null -eq $authWindow) {
            throw "Authentication window is null. Cannot show dialog."
        }
        $result = $authWindow.ShowDialog()
    }
    catch {
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error showing authentication dialog: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to show the authentication dialog. Error: $_",
            "Dialog Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return $null
    }
    
    if ($result) {
        # Return authentication details based on selected method
        if ($interactiveAuth.IsChecked) {
            return @{
                Method = 'Interactive'
            }
        }
        elseif ($certificateAuth.IsChecked) {
            return @{
                Method     = 'Certificate'
                AppId      = $authWindow.FindName('CertAppId').Text
                TenantId   = $authWindow.FindName('CertTenantId').Text
                Thumbprint = $authWindow.FindName('CertThumbprint').Text
            }
        }
        else {
            return @{
                Method   = 'Secret'
                AppId    = $authWindow.FindName('SecretAppId').Text
                TenantId = $authWindow.FindName('SecretTenantId').Text
                Secret   = $authWindow.FindName('ClientSecret').Password
            }
        }
    }
    return $null
}

function Show-BulkImportDialog {
    try {
        $reader = (New-Object System.Xml.XmlNodeReader $bulkImportModalXaml)
        $bulkImportWindow = [Windows.Markup.XamlReader]::Load($reader)
        
        if ($null -eq $bulkImportWindow) {
            throw "Failed to create bulk import window. XamlReader returned null."
        }
    }
    catch {
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error creating bulk import window: $_"
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
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error showing bulk import dialog: $_"
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

function Connect-ToGraph {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthDetails
    )

    try {
        Write-Log "Attempting to connect to Microsoft Graph using $($AuthDetails.Method) authentication..."
        
        # Get required permissions
        $permissionsList = ($script:requiredPermissions | ForEach-Object { $_.Permission })    

        # Connect based on authentication method
        switch ($AuthDetails.Method) {
            'Interactive' {
                Write-Log -Message "Connecting interactively..."
                $connectionResult = Connect-MgGraph -Scopes $permissionsList -NoWelcome -ErrorAction Stop
            }
            'Certificate' {
                Write-Log -Message "Connecting with certificate authentication..."
                # Validate certificate credentials before attempting connection
                if ([string]::IsNullOrWhiteSpace($AuthDetails.AppId)) {
                    throw "App ID is required for certificate authentication"
                }
                if ([string]::IsNullOrWhiteSpace($AuthDetails.TenantId)) {
                    throw "Tenant ID is required for certificate authentication"
                }
                if ([string]::IsNullOrWhiteSpace($AuthDetails.Thumbprint)) {
                    throw "Certificate Thumbprint is required for certificate authentication"
                }
                
                # Disconnect any existing connections first
                Write-Log -Message "Disconnecting any existing Microsoft Graph connections..."
                Disconnect-MgGraph -ErrorAction SilentlyContinue
                
                $connectionResult = Connect-MgGraph -ClientId $AuthDetails.AppId -TenantId $AuthDetails.TenantId -CertificateThumbprint $AuthDetails.Thumbprint -NoWelcome -ErrorAction Stop
            }
            'Secret' {
                Write-Log -Message "Connecting with client secret authentication..."

                # Validate client secret credentials before attempting connection
                if ([string]::IsNullOrWhiteSpace($AuthDetails.AppId)) {
                    throw "App ID is required for client secret authentication"
                }
                if ([string]::IsNullOrWhiteSpace($AuthDetails.TenantId)) {
                    throw "Tenant ID is required for client secret authentication"
                }
                if ([string]::IsNullOrWhiteSpace($AuthDetails.Secret)) {
                    throw "Client Secret is required for client secret authentication"
                }
                
                $SecuredPasswordPassword = ConvertTo-SecureString -String $AuthDetails.Secret -AsPlainText -Force
                $ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AuthDetails.AppId, $SecuredPasswordPassword
                
                $connectionResult = Connect-MgGraph -TenantId $AuthDetails.TenantId -ClientSecretCredential $ClientSecretCredential -NoWelcome -ErrorAction Stop
            }
            default {
                Write-Log -Message "Invalid authentication method specified"
                throw "Invalid authentication method specified"
            }
        }

        # Check permissions
        $context = Get-MgContext
        if (-not $context) {
            throw "Failed to get Microsoft Graph context after connection"
        }

        # Get tenant details and update UI
        try {
            Write-Log "Retrieving tenant information..."
            $tenantInfo = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/organization" -Method GET
            if ($tenantInfo.value) {
                $org = $tenantInfo.value[0]
                Write-Log "Found tenant: $($org.displayName)"
                
                # Update UI elements
                $Window.FindName('TenantDisplayName').Text = $org.displayName
                $Window.FindName('TenantId').Text = $org.id
                $Window.FindName('TenantDomain').Text = ($org.verifieddomains | Where-Object { $_.isDefault -eq $true }).name
                $Window.FindName('TenantInfoSection').Visibility = 'Visible'
            }
            else {
                Write-Log "Warning: No tenant information found in response"
            }
        }
        catch {
            Write-Log "Warning: Could not retrieve tenant details: $_"
            # Don't throw here, as the connection is still valid
        }

        $currentPermissions = $context.Scopes
        $missingPermissions = @()

        foreach ($permissionInfo in $script:requiredPermissions) {
            Write-Log -Message "Checking for required permission: $($permissionInfo.Permission)"
            $permission = $permissionInfo.Permission
            if (-not ($currentPermissions -contains $permission -or
                    $currentPermissions -contains $permission.Replace(".Read", ".ReadWrite"))) {
                $missingPermissions += $permission
            }
        }

        if ($missingPermissions.Count -gt 0) {
            $missingList = $missingPermissions -join ", "
            Write-Log "Warning: Missing permissions: $missingList"
            [System.Windows.MessageBox]::Show(
                "The following permissions are missing: `n$missingList`n`nThe application may not function correctly.",
                "Missing Permissions",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
        }

        Write-Log "Successfully connected to Microsoft Graph"
        return $true
    }
    catch {
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Failed to connect to Microsoft Graph: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to connect to Microsoft Graph: $_",
            "Connection Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        
        # Reset UI state on connection failure
        Write-Log -Message "Resetting UI state due to connection failure"
        $script:connectionFailed = $true  # Add this flag to track connection failure
        return $false
    }
}

# Parse XAML
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
    exit 1
}

# Set window title with version
$scriptVersion = Get-ScriptVersion
$Window.Title = "Device Offboarding Manager (Preview) - $scriptVersion"

# Helper to get the current line number for error logging
function Get-CurrentLineNumber {
    $stack = Get-PSCallStack
    if ($stack.Count -gt 1) {
        return $stack[1].ScriptLineNumber
    }
    return $MyInvocation.ScriptLineNumber
}

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
            
            # Show success message
            [System.Windows.MessageBox]::Show(
                "Successfully exported $($DeviceList.Count) devices to:`n$exportPath",
                "Export Successful",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )
            
            return $true
        }
        return $false
    }
    catch {
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error exporting device list: $_"
        [System.Windows.MessageBox]::Show(
            "Error exporting device list: $_",
            "Export Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return $false
    }
}

Function ConnectSCCM {

    ##Load the Configuration Manager Module
    import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1')
    $Drive = Get-PSDrive -PSProvider CMSite
    Set-Location "$($Drive):"

}

function Invoke-DeviceSearch {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SearchTexts,
        [Parameter(Mandatory = $true)]
        [string]$SearchOption
    )
    
    try {
        $searchResults = New-Object 'System.Collections.Generic.List[DeviceObject]'
        $AADCount = 0
        $IntuneCount = 0
        $AutopilotCount = 0
        $SCCMCount = 0

        # Load QuerySCCM setting from settings.json
        if (Test-Path $settingsPath) {
            try {
                $settings = Get-Content $settingsPath | ConvertFrom-Json
                $QuerySCCM = $settings.QuerySCCM
            } catch {
                Write-Log "Error loading QuerySCCM from settings.json: $_"
                $QuerySCCM = $false
            }
        }

        foreach ($SearchText in $SearchTexts) {
            # Trim whitespace and newlines
            $SearchText = $SearchText.Trim()
            
            if ([string]::IsNullOrWhiteSpace($SearchText)) {
                continue
            }
            
            if ($SearchOption -eq "Devicename") {
                # Get devices from all services independently
                $uri = "https://graph.microsoft.com/v1.0/devices?`$filter=displayName eq '$SearchText'"
                $AADDevices = Get-GraphPagedResults -Uri $uri
                
                $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=deviceName eq '$SearchText'"
                $IntuneDevices = Get-GraphPagedResults -Uri $uri
                
                write-host $querysccm

                If ($QuerySCCM -eq $True) {
                    Write-Log -Message "Attempting to search in SCCM."
                    $originaldrive = Get-Location
                    ConnectSCCM
                
                    $SCCMDevices = get-cmdevice -Name $SearchText -fast | Where-Object { $_.IsClient -eq $true -and $_.IsActive -eq $true }
                    set-location $originaldrive
                }
                Else {
                    $SCCMDevices = $Null
                }
                #Write-Host 'SearchText-'$SearchText 
                #Write-Host 'SCCM-'$SCCMDevices
                
                # Search Autopilot devices by displayName (using client-side filtering)
                try {
                    # Get all Autopilot devices and filter client-side since API doesn't support displayName filtering
                    $uri = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities"
                    $allAutopilotDevices = Get-GraphPagedResults -Uri $uri
                    
                    # Filter by display name (case-insensitive partial match)
                    $AutopilotDevices = $allAutopilotDevices | Where-Object { 
                        $_.displayName -and $_.displayName -like "*$SearchText*" 
                    }
                    
                    Write-Log "Found $($AutopilotDevices.Count) Autopilot devices matching display name: $SearchText"
                }
                catch {
                    Write-Log "Error searching Autopilot devices by display name: $_"
                    $AutopilotDevices = @()
                }

                # Process Entra ID devices
                if ($AADDevices) {
                    foreach ($AADDevice in $AADDevices) {
                        $matchingIntuneDevice = $IntuneDevices | Where-Object { $_.deviceName -eq $AADDevice.displayName } | Select-Object -First 1
                        $matchingAutopilotDevice = $AutopilotDevices | Where-Object { $_.displayName -eq $AADDevice.displayName } | Select-Object -First 1
                        $matchingSCCMDevice = $SCCMDevices | Where-Object { $_.Name -eq $AADDevice.displayName } | Select-Object -First 1
                        # write-host "Matchingsccmdevice" $matchingSCCMDevice.name
                        # write-host "AADDeviceName" $AADDevice.displayName
                        
                        # If no Autopilot match by displayName and we have Intune device with serial, try serial number
                        if (-not $matchingAutopilotDevice -and $matchingIntuneDevice -and $matchingIntuneDevice.serialNumber) {
                            $uri = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$($matchingIntuneDevice.serialNumber)')"
                            $matchingAutopilotDevice = (Get-GraphPagedResults -Uri $uri) | Select-Object -First 1
                        }

                        $CombinedDevice = New-Object DeviceObject
                        $CombinedDevice.IsSelected = $false
                        $CombinedDevice.DeviceName = $AADDevice.displayName
                        
                        # Try to get serial number from multiple sources
                        if ($null -ne $matchingIntuneDevice -and $matchingIntuneDevice.serialNumber) {
                            $CombinedDevice.SerialNumber = $matchingIntuneDevice.serialNumber
                        }
                        elseif ($null -ne $matchingAutopilotDevice -and $matchingAutopilotDevice.serialNumber) {
                            $CombinedDevice.SerialNumber = $matchingAutopilotDevice.serialNumber
                        }
                        elseif ($null -ne $matchingSCCMDevice -and $matchingSCCMDevice.serialNumber) {
                            $CombinedDevice.SerialNumber = $matchingSCCMDevice.serialNumber
                        }
                        else {
                            $CombinedDevice.SerialNumber = $null
                        }
                        # write-host "Combined Serial Line3463" $CombinedDevice.serialNumber
                        # write-host "MatchingSCCMSerial Line 3464" $matchingSCCMDevice.serialNumber

                        # If still no serial number, try to extract from Entra ID physicalIds
                        if (-not $CombinedDevice.SerialNumber -and $AADDevice.physicalIds) {
                            foreach ($physicalId in $AADDevice.physicalIds) {
                                if ($physicalId -match '\[SerialNumber\]:(.+)') {
                                    $CombinedDevice.SerialNumber = $matches[1].Trim()
                                    break
                                }
                            }
                        }

                        $CombinedDevice.OperatingSystem = $AADDevice.operatingSystem
                        #$CombinedDevice.PrimaryUser = $matchingIntuneDevice?.userDisplayName
                        $CombinedDevice.AzureADLastContact = ConvertTo-SafeDateTime -dateString $AADDevice.approximateLastSignInDateTime
                        $CombinedDevice.IntuneLastContact = ConvertTo-SafeDateTime -dateString $matchingIntuneDevice.lastSyncDateTime
                        $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $matchingAutopilotDevice.lastContactedDateTime
                        $CombinedDevice.SCCMLastContact = ConvertTo-SafeDateTime -dateString $matchingSCCMDevice.LastActiveTime

                        # Try and get PrimaryUser from multiple locations
                        if ($null -ne $matchingIntuneDevice -and $matchingIntuneDevice.userDisplayName) {
                            $CombinedDevice.PrimaryUser = $matchingIntuneDevice.userDisplayName
                        }
                        elseif ($null -ne $matchingAutopilotDevice -and $matchingAutopilotDevice.userDisplayName) {
                            $CombinedDevice.PrimaryUser = $matchingAutopilotDevice.userDisplayName
                        }
                        elseif ($null -ne $matchingSCCMDevice -and $matchingSCCMDevice.userDisplayName) {
                            $CombinedDevice.PrimaryUser = $matchingSCCMDevice.userDisplayName
                        }
                        else {
                            $CombinedDevice.PrimaryUser = $null
                        }

                        $searchResults.Add($CombinedDevice)
                        $AADCount++
                        if ($matchingIntuneDevice) { $IntuneCount++ }
                        if ($matchingAutopilotDevice) { $AutopilotCount++ }
                        if ($matchingSCCMDevice) { $SCCMCount++ }
                    }
                }
                
                # Process Intune devices not in Entra ID
                if ($IntuneDevices) {
                    foreach ($IntuneDevice in $IntuneDevices) {
                        # Skip if we already added this device through Entra ID
                        if ($searchResults | Where-Object { $_.DeviceName -eq $IntuneDevice.deviceName }) {
                            continue
                        }
                        
                        # Check if device is in Autopilot
                        $matchingAutopilotDevice = $AutopilotDevices | Where-Object { $_.displayName -eq $IntuneDevice.deviceName } | Select-Object -First 1
                        
                        # If no match by displayName and we have serial number, try serial number
                        if (-not $matchingAutopilotDevice -and $IntuneDevice.serialNumber) {
                            $uri = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$($IntuneDevice.serialNumber)')"
                            $matchingAutopilotDevice = (Get-GraphPagedResults -Uri $uri) | Select-Object -First 1
                        }

                        $CombinedDevice = New-Object DeviceObject
                        $CombinedDevice.IsSelected = $false
                        $CombinedDevice.DeviceName = $IntuneDevice.deviceName
                        $CombinedDevice.SerialNumber = $IntuneDevice.serialNumber ?? $matchingAutopilotDevice?.serialNumber
                        $CombinedDevice.OperatingSystem = $IntuneDevice.operatingSystem
                        $CombinedDevice.PrimaryUser = $IntuneDevice.userDisplayName
                        $CombinedDevice.IntuneLastContact = ConvertTo-SafeDateTime -dateString $IntuneDevice.lastSyncDateTime
                        $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $matchingAutopilotDevice.lastContactedDateTime
                        $CombinedDevice.SCCMLastContact = ConvertTo-SafeDateTime -dateString $matchingSCCMDevice.LastActiveTime
                        
                        $searchResults.Add($CombinedDevice)
                        $IntuneCount++
                        if ($matchingAutopilotDevice) { $AutopilotCount++ }
                    }
                }
                
                # Process Autopilot devices not in Entra ID or Intune
                if ($AutopilotDevices) {
                    foreach ($AutopilotDevice in $AutopilotDevices) {
                        # Skip if we already added this device
                        if ($searchResults | Where-Object { 
                                $_.DeviceName -eq $AutopilotDevice.displayName -or 
                                ($_.SerialNumber -and $_.SerialNumber -eq $AutopilotDevice.serialNumber)
                            }) {
                            continue
                        }

                        $CombinedDevice = New-Object DeviceObject
                        $CombinedDevice.IsSelected = $false
                        $CombinedDevice.DeviceName = $AutopilotDevice.displayName
                        $CombinedDevice.SerialNumber = $AutopilotDevice.serialNumber
                        $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $AutopilotDevice.lastContactedDateTime
                        
                        $searchResults.Add($CombinedDevice)
                        $AutopilotCount++
                    }
                }

                # Process SCCM devices
                If ($QuerySCCM -eq $True) {
                    If ($SCCMDevices) {
                    foreach ($SCCMDevice in $SCCMDevices) {
                        # Skip if we already added this device through Entra ID, Intune, or Autopilot
                        # write-host "SCCM Name Line 3550" $SCCMDevice.Name
                        # write-host "SCCM Serial Line 3551" $SCCMDevice.SerialNumber
                        if ($searchResults | Where-Object { 
                                $_.DeviceName -eq $SCCMDevice.Name -or 
                                ($_.SerialNumber -and $_.SerialNumber -eq $SCCMDevice.SerialNumber)
                            }
                        ) {
                            continue
                        }

                        $CombinedDevice = New-Object DeviceObject
                        $CombinedDevice.IsSelected = $false
                        $CombinedDevice.DeviceName = $SCCMDevice.Name
                        $CombinedDevice.SerialNumber = $SCCMDevice.SerialNumber
                        $CombinedDevice.OperatingSystem = ($SCCMDevice.DeviceOS).Replace(" NT Workstation", "")
                        $CombinedDevice.PrimaryUser = $SCCMDevice.PrimaryUser
                        $CombinedDevice.SCCMLastContact = ConvertTo-SafeDateTime -dateString $SCCMDevice.LastActiveTime
                        
                        write-host $CombinedDevice.SCCMLastContact 

                        $searchResults.Add($CombinedDevice)
                        $SCCMCount++
                    }
                }
                }
            }
            elseif ($SearchOption -eq "Serialnumber") {
                # Get devices from all services independently
                $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=serialNumber eq '$SearchText'"
                $IntuneDevices = Get-GraphPagedResults -Uri $uri
                
                $uri = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$SearchText')"
                $AutopilotDevices = Get-GraphPagedResults -Uri $uri
                
                $originaldrive = Get-Location
                ConnectSCCM
                $SCCMDevices = get-cmdevice -fast | Where-Object { $_.serialnumber -eq $SearchText }
                Set-Location $originaldrive

                if ($IntuneDevices -or $AutopilotDevices) {
                    # If device is in Intune
                    if ($IntuneDevices) {
                        foreach ($IntuneDevice in $IntuneDevices) {
                            # Get Entra ID Device
                            $uri = "https://graph.microsoft.com/v1.0/devices?`$filter=displayName eq '$($IntuneDevice.deviceName)'"
                            $AADDevice = (Get-GraphPagedResults -Uri $uri) | Select-Object -First 1
                            
                            # Get Autopilot Device
                            $matchingAutopilotDevice = $AutopilotDevices | Where-Object { $_.serialNumber -eq $IntuneDevice.serialNumber } | Select-Object -First 1
                            $matchingSCCMDevice = $SCCMDevices | Where-Object { $_.serialnumber -eq $IntuneDevice.serialNumber } | Select-Object -First 1

                            $CombinedDevice = New-Object DeviceObject
                            $CombinedDevice.IsSelected = $false
                            $CombinedDevice.DeviceName = $IntuneDevice.deviceName
                            $CombinedDevice.SerialNumber = $IntuneDevice.serialNumber
                            $CombinedDevice.OperatingSystem = $AADDevice?.operatingSystem ?? $IntuneDevice.operatingSystem
                            $CombinedDevice.PrimaryUser = $IntuneDevice.userDisplayName
                            $CombinedDevice.AzureADLastContact = ConvertTo-SafeDateTime -dateString $AADDevice.approximateLastSignInDateTime
                            $CombinedDevice.IntuneLastContact = ConvertTo-SafeDateTime -dateString $IntuneDevice.lastSyncDateTime
                            $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $matchingAutopilotDevice.lastContactedDateTime
                            $CombinedDevice.SCCMLastContact = ConvertTo-SafeDateTime -dateString $matchingSCCMDevice.LastActiveTime
                            
                            $searchResults.Add($CombinedDevice)
                            if ($AADDevice) { $AADCount++ }
                            $IntuneCount++
                            if ($matchingAutopilotDevice) { $AutopilotCount++ }
                            if ($matchingSCCMDevice) { $SCCMCount++ }
                        }
                    }
                    
                    # If device is in Autopilot but not in Intune
                    if ($AutopilotDevices) {
                        foreach ($AutopilotDevice in $AutopilotDevices) {
                            # Skip if we already added this device through Intune
                            if ($searchResults | Where-Object { $_.SerialNumber -eq $AutopilotDevice.serialNumber }) {
                                continue
                            }

                            $CombinedDevice = New-Object DeviceObject
                            $CombinedDevice.IsSelected = $false
                            $CombinedDevice.DeviceName = $AutopilotDevice.displayName
                            $CombinedDevice.SerialNumber = $AutopilotDevice.serialNumber
                            $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $AutopilotDevice.lastContactedDateTime
                            
                            $searchResults.Add($CombinedDevice)
                            $AutopilotCount++
                        }
                    }

                    # If device is in SCCM
                    if ($SCCMDevices) {
                        foreach ($SCCMDevice in $SCCMDevices) {
                            # Skip if we already added this device through Intune or Autopilot
                            write-host "SCCM Serial = "$SCCMDevice.SerialNumber
                            if ($searchResults | Where-Object { $_.SerialNumber -eq $SCCMDevice.SerialNumber }) {
                                continue
                            }
                                                        
                            $CombinedDevice = New-Object DeviceObject
                            $CombinedDevice.IsSelected = $false
                            $CombinedDevice.DeviceName = $SCCMDevice.Name
                            $CombinedDevice.SerialNumber = $SCCMDevice.SerialNumber
                            $CombinedDevice.OperatingSystem = ($SCCMDevice.DeviceOS).Replace(" NT Workstation", "")
                            $CombinedDevice.PrimaryUser = $SCCMDevice.UserName
                            $CombinedDevice.SCCMLastContact = ConvertTo-SafeDateTime -dateString $SCCMDevice.LastActiveTime
                            
                            $searchResults.Add($CombinedDevice)
                            $SCCMCount++
                        }
                    }
                }
            }
        }
        
        # Update UI status
        $Window.FindName('intune_status').Text = "Intune: $IntuneCount device found"
        $Window.FindName('intune_status').Foreground = if ($IntuneCount -gt 0) { '#4299E1' } else { '#FC8181' }
        $Window.FindName('autopilot_status').Text = "Autopilot: $AutopilotCount device found"
        $Window.FindName('autopilot_status').Foreground = if ($AutopilotCount -gt 0) { '#48BB78' } else { '#FC8181' }
        $Window.FindName('aad_status').Text = "Entra ID: $AADCount device found"
        $Window.FindName('aad_status').Foreground = if ($AADCount -gt 0) { '#ED64A6' } else { '#FC8181' }
        $Window.FindName('sccm_status').Text = "SCCM: $SCCMCount device found"
        $Window.FindName('sccm_status').Foreground = if ($SCCMCount -gt 0) { '#ED64A6' } else { '#FC8181' }

        if ($searchResults.Count -gt 0) {
            $SearchResultsDataGrid.ItemsSource = $searchResults
        }
        else {
            $SearchResultsDataGrid.ItemsSource = $null
            [System.Windows.MessageBox]::Show("No devices found matching the search criteria.")
        }
        
        # Ensure Offboard button and Export Selected button are disabled until selection
        $OffboardButton.IsEnabled = $false
        $ExportSelectedButton.IsEnabled = $false
    }
    catch {
        Write-Error $Error[0]
        Write-Log "Error occurred during search operation. Exception: $_"
        [System.Windows.MessageBox]::Show("Error in search operation. Please ensure the Serialnumber or Devicename is valid.")
    }
}

# Connect to Controls
$SearchButton = $Window.FindName("SearchButton")
$OffboardButton = $Window.FindName("OffboardButton")
$ExportSelectedButton = $Window.FindName("ExportSelectedButton")
$AuthenticateButton = $Window.FindName("AuthenticateButton")
$SearchInputText = $Window.FindName("SearchInputText")
$bulk_import_button = $Window.FindName('bulk_import_button')
$Dropdown = $Window.FindName("dropdown")
$Disconnect = $Window.FindName('disconnect_button')
$logs_button = $Window.FindName('logs_button')
$PrerequisitesButton = $Window.FindName('PrerequisitesButton')
$FeedbackLink = $Window.FindName('FeedbackLink')

# Add feedback link handler
$FeedbackLink.Add_Click({
        Start-Process "https://github.com/ugurkocde/DeviceOffboardingManager/issues"
    })

$SearchInputText.Add_GotFocus({
        # Empty - no resizing needed
    })

$SearchInputText.Add_LostFocus({
        # Empty - no resizing needed
    })
    
$Window.Add_Loaded({
        $Dropdown.Items.Add("Devicename")
        $Dropdown.Items.Add("Serialnumber")
        $Dropdown.SelectedIndex = 0
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
                
                # Force Home menu selection
                $MenuHome.IsChecked = $true
            }
            else {
                Write-Log "Successfully connected to MS Graph"
                $AuthenticateButton.Content = "Successfully connected"
                $AuthenticateButton.IsEnabled = $false
                $Disconnect.IsEnabled = $true
                $PrerequisitesButton.IsEnabled = $true
                
                # Enable navigation menus
                $MenuDashboard.IsEnabled = $true
                $MenuDeviceManagement.IsEnabled = $true
                $MenuPlaybooks.IsEnabled = $true
                
                # Get tenant details for existing connection
                try {
                    Write-Log "Retrieving tenant information for existing connection..."
                    $tenantInfo = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/organization" -Method GET
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
                    [System.Windows.MessageBox]::Show(
                        "The following permissions are missing: `n$missingList`n`nThe application may not function correctly.",
                        "Missing Permissions",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    )
                }
            }

            # Update version displays
            Update-VersionDisplays -window $Window
            Write-Log "Version displays updated"
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
        }
    })
    
$Disconnect.Add_Click({
        try {
            Write-Log "Attempting to disconnect from MS Graph..."
            
            # Disconnect from Graph
            Disconnect-MgGraph -ErrorAction Stop
            
            # Reset UI state
            $Disconnect.Content = "Disconnected"
            $Disconnect.IsEnabled = $false
            $AuthenticateButton.Content = "Connect to MS Graph"
            $AuthenticateButton.IsEnabled = $true
            $PrerequisitesButton.IsEnabled = $true
            
            # Hide tenant info
            $Window.FindName('TenantInfoSection').Visibility = 'Collapsed'
            $Window.FindName('TenantDisplayName').Text = ""
            $Window.FindName('TenantId').Text = ""
            $Window.FindName('TenantDomain').Text = ""
            
            # Disable navigation menus and force Home selection
            $MenuDashboard.IsEnabled = $false
            $MenuDeviceManagement.IsEnabled = $false
            $MenuPlaybooks.IsEnabled = $false
            $MenuHome.IsChecked = $true
            
            # Clear any sensitive data from the dashboard
            $Window.FindName('IntuneDevicesCount').Text = "0"
            $Window.FindName('AutopilotDevicesCount').Text = "0"
            $Window.FindName('EntraIDDevicesCount').Text = "0"
            $Window.FindName('StaleDevices30Count').Text = "0"
            $Window.FindName('StaleDevices90Count').Text = "0"
            $Window.FindName('StaleDevices180Count').Text = "0"
            $Window.FindName('PersonalDevicesCount').Text = "0"
            $Window.FindName('CorporateDevicesCount').Text = "0"
            
            Write-Log "Successfully disconnected from MS Graph"
        }
        catch {
            Write-Log "Error occurred while attempting to disconnect from MS Graph: $_"
            [System.Windows.MessageBox]::Show(
                "Error disconnecting from Microsoft Graph: $_",
                "Disconnect Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
        }
    })
    
$AuthenticateButton.Add_Click({
    Write-Log "AuthenticateButton clicked."
    try {
        # Check if already connected
        $context = Get-MgContext
        if ($context) {
            Write-Log "Already connected to MS Graph, skipping authentication dialog"
            return
        }
        
        Write-Log "Authentication button clicked, showing authentication dialog..."
        
        # Load current setting
        Write-Log "Loading authentication settings from settings.json"
        if (Test-Path $settingsPath) {
            try {
                $settings = Get-Content $settingsPath | ConvertFrom-Json
                $rememberCertAuth = $settings.RememberCertAuthentication
                $rememberSecretAuth = $settings.RememberSecretAuthentication

                If ($rememberCertAuth -or $rememberSecretAuth) {
                    Write-Log "Auto authentication is enabled."
                    $autoAuthCheck.IsChecked = $true
                }
                else {
                    Write-Log "Auto authentication is disabled."
                    $autoAuthCheck.IsChecked = $false
                }
            } catch {
                Write-Log "Error loading authentication settings: $_"
            }
        }
        
        # Reset the connection failed flag
        $script:connectionFailed = $false
    
        # Show authentication dialog
        # Check for saved encrypted secret file before showing authentication dialog
        Write-Log "Check for saved encrypted secret file before showing authentication dialog"
        $secretFilePath = [System.IO.Path]::Combine($env:LOCALAPPDATA, "DeviceOffBoardingManager", "IntuneOffboardingTool_Secret.json")
        $certFilePath = [System.IO.Path]::Combine($env:LOCALAPPDATA, "DeviceOffBoardingManager", "IntuneOffboardingTool_Certificate.pfx")

        $authDetails = $null

        if ($rememberCertAuth -eq $true -and (Test-Path $certFilePath)) {
            Write-Log "Found saved certificate authentication file. Attempting to load."
            try {
                $encrypted = Get-Content $certFilePath -Encoding Byte
                $secure = ConvertTo-SecureString -String $encrypted -AsPlainText -Force
                $json = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
                $config = ConvertFrom-Json $json -AsHashtable
                if ($config.AppId -and $config.TenantId -and $config.CertificatePath -and $config.CertificatePassword) {
                    Write-Log "Loaded certificate authentication details from file."
                    $authDetails = @{
                        Method             = 'Certificate'
                        AppId              = $config.AppId
                        TenantId           = $config.TenantId
                        CertificatePath    = $config.CertificatePath
                        CertificatePassword= $config.CertificatePassword
                    }
                }
                else {
                    Write-Log "Certificate file missing required fields, falling back to authentication dialog."
                    $authDetails = Show-AuthenticationDialog
                }
            }
            catch {
                Write-Log "Failed to decode saved certificate: $_"
                $authDetails = Show-AuthenticationDialog
            }
        }
        elseif ($rememberSecretAuth -eq $true -and (Test-Path $secretFilePath)) {
            Write-Log "Found saved secret authentication file. Attempting to load."
            try {
                $encrypted = Get-Content $secretFilePath
                $secure = $encrypted | ConvertTo-SecureString
                Write-Log "Loaded encrypted secret from file."
                $json = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
                $config = ConvertFrom-Json $json -AsHashtable
                if ($config.AppId -and $config.TenantId -and $config.ClientSecret) {
                    Write-Log "Loaded secret authentication details from file."
                    $authDetails = @{
                        Method   = 'Secret'
                        AppId    = $config.AppId
                        TenantId = $config.TenantId
                        Secret   = $config.ClientSecret
                    }
                }
                else {
                    Write-Log "Secret file missing required fields, falling back to authentication dialog."
                    $authDetails = Show-AuthenticationDialog
                }
            }
            catch {
                Write-Log "Failed to decode saved secret: $_"
                $authDetails = Show-AuthenticationDialog
            }
        }
        else {
            Write-Log "No saved authentication found, showing authentication dialog."
            $authDetails = Show-AuthenticationDialog
        }

        if (-not $authDetails) {
            Write-Log "Authentication cancelled by user"
            # Reset button state if cancelled
            $AuthenticateButton.Content = "Connect to MS Graph"
            $AuthenticateButton.IsEnabled = $true
            return
        }

        # Set button to "Connecting..." state
        Write-Log "Attempting to connect to Microsoft Graph..."
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

            # Enable navigation menus
            $MenuDashboard.IsEnabled = $true
            $MenuDeviceManagement.IsEnabled = $true
            $MenuPlaybooks.IsEnabled = $true
        }
        else {
            # Reset button state on failed connection
            Write-Log "Authentication Failed"
            $AuthenticateButton.Content = "Connect to MS Graph"
            $AuthenticateButton.IsEnabled = $true
            $Disconnect.Content = "Disconnected"
            $Disconnect.IsEnabled = $false
            
            # Disable navigation menus
            $MenuDashboard.IsEnabled = $false
            $MenuDeviceManagement.IsEnabled = $false
            $MenuPlaybooks.IsEnabled = $false
            
            # Hide tenant info
            $Window.FindName('TenantInfoSection').Visibility = 'Collapsed'
            $Window.FindName('TenantDisplayName').Text = ""
            $Window.FindName('TenantId').Text = ""
            $Window.FindName('TenantDomain').Text = ""
        }
    }
    catch {
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error occurred during authentication. Exception: $_"
        # Reset button state on error
        $AuthenticateButton.Content = "Connect to MS Graph"
        $AuthenticateButton.IsEnabled = $true
        $Disconnect.Content = "Disconnected"
        $Disconnect.IsEnabled = $false
        
        # Disable navigation menus
        $MenuDashboard.IsEnabled = $false
        $MenuDeviceManagement.IsEnabled = $false
        $MenuPlaybooks.IsEnabled = $false
        
        # Hide tenant info
        $Window.FindName('TenantInfoSection').Visibility = 'Collapsed'
        $Window.FindName('TenantDisplayName').Text = ""
        $Window.FindName('TenantId').Text = ""
        $Window.FindName('TenantDomain').Text = ""
        
        [System.Windows.MessageBox]::Show(
            "Authentication failed: $_",
            "Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
})

    

$SearchButton.Add_Click({
    if ($AuthenticateButton.IsEnabled) {
        Write-Log "User is not connected to MS Graph. Attempted search operation."
        [System.Windows.MessageBox]::Show("You are not connected to MS Graph. Please connect first.")
        return
    }

    try {
        # Trim the input and split by comma
        $searchInput = $SearchInputText.Text.Trim()
        $SearchTexts = $searchInput -split ', ' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        
        if ($SearchTexts.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Please enter at least one device name or serial number.")
        return
        }
        
        Write-Log "Searching for devices: $SearchTexts"
        $searchOption = $Dropdown.SelectedItem

        # Show loading dialog
        $script:currentLoadingWindow = Show-LoadingDialog -Title 'Searching devices' -Message 'Looking up devices across services...'
        if ($script:currentLoadingWindow) { $script:currentLoadingWindow.Show() }
        
        # Call the centralized search function
        Invoke-DeviceSearch -SearchTexts $SearchTexts -SearchOption $searchOption
    }
    catch {
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error occurred during search operation. Exception: $_"
        [System.Windows.MessageBox]::Show("Error in search operation. Please ensure the Serialnumber or Devicename is valid.")
    }
    finally {
        if ($script:currentLoadingWindow) {
        try { $script:currentLoadingWindow.Close() } catch {}
        $script:currentLoadingWindow = $null
        }
    }
    })
    
        
$bulk_import_button.Add_Click({
        if ($AuthenticateButton.IsEnabled) {
            Write-Log "User is not connected to MS Graph. Attempted bulk import operation."
            [System.Windows.MessageBox]::Show("You are not connected to MS Graph. Please connect first.")
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
                # Show loading dialog
                $script:currentLoadingWindow = Show-LoadingDialog -Title 'Bulk Import Search' -Message 'Looking up imported devices across services...'
                if ($script:currentLoadingWindow) { $script:currentLoadingWindow.Show() }
                try {
                    Invoke-DeviceSearch -SearchTexts $devices -SearchOption $searchOption
                }
                finally {
                    if ($script:currentLoadingWindow) {
                        try { $script:currentLoadingWindow.Close() } catch {}
                        $script:currentLoadingWindow = $null
                    }
                }
            }
            else {
                Write-Log "Bulk import cancelled or no devices imported"
            }
        }
        catch {
            Write-Log "Exception in bulk import: $_"
            [System.Windows.MessageBox]::Show("Error in bulk import operation: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    })

$OffboardButton.Add_Click({
        if ($AuthenticateButton.IsEnabled) {
            Write-Log "User is not connected to MS Graph. Attempted offboarding operation."
            [System.Windows.MessageBox]::Show("You are not connected to MS Graph. Please connect first.")
            return
        }

        $selectedDevices = $SearchResultsDataGrid.ItemsSource | Where-Object { $_.IsSelected }
        
        if (-not $selectedDevices) {
            [System.Windows.MessageBox]::Show("Please select at least one device to offboard.")
            return
        }

        # Show confirmation modal
        [xml]$confirmationModalXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Confirm Device Offboarding" Height="600" Width="700" WindowStartupLocation="CenterScreen" Background="#F8F9FA">
    <Border Background="White" CornerRadius="8" Margin="16">
        <DockPanel Margin="24">
            <!-- Header -->
            <StackPanel DockPanel.Dock="Top" Margin="0,0,0,24">
                <TextBlock Text="Confirm Device Offboarding" FontSize="24" FontWeight="SemiBold" Foreground="#1A202C"/>
                <TextBlock Text="Select the services you want to remove the device(s) from:" Foreground="#4A5568" FontSize="14" Margin="0,8,0,0"/>
            </StackPanel>

            <!-- Action Buttons -->
            <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,24,0,0">
                <Button x:Name="CancelButton" Content="Cancel" Width="120" Height="40" Background="#F0F0F0" Foreground="#2D3748" BorderThickness="0" Margin="0,0,12,0"/>
                <Button x:Name="ConfirmButton" Content="Confirm Offboarding" Width="160" Height="40" Background="#DC2626" Foreground="White" BorderThickness="0"/>
            </StackPanel>

            <!-- Warning Message -->
            <Border DockPanel.Dock="Bottom" Background="#FEF2F2" BorderBrush="#FEE2E2" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,16,0,0">
                <StackPanel Orientation="Horizontal">
                    <Path Data="M12,2L1,21H23M12,6L19.53,19H4.47M11,10V13H13V10M11,15V17H13V15" Fill="#DC2626" Width="24" Height="24" Stretch="Uniform" Margin="0,0,12,0"/>
                    <TextBlock Text="This action cannot be undone. The device(s) will be permanently removed from the selected services." Foreground="#DC2626" TextWrapping="Wrap" VerticalAlignment="Center" MaxWidth="400"/>
                </StackPanel>
            </Border>

            <!-- Main Content -->
            <StackPanel>
                <!-- Services List -->
                <WrapPanel x:Name="ServicesList" Margin="0,0,0,24" Orientation="Horizontal"/>

                <!-- Encryption Key Section -->
                <Border Background="#EDF2F7" BorderBrush="#E2E8F0" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,16" Height="300">
                    <Grid VerticalAlignment="Stretch">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        
                        <TextBlock Grid.Row="0" Text="Device Encryption Keys" FontWeight="SemiBold" FontSize="14" Margin="0,0,0,8"/>
                        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" VerticalAlignment="Stretch">
                            <ItemsControl x:Name="EncryptionKeysList">
                                <ItemsControl.ItemTemplate>
                                    <DataTemplate>
                                        <StackPanel Margin="0,0,0,24">
                                            <TextBlock Text="{Binding DeviceName}" FontWeight="SemiBold" Margin="0,0,0,4"/>
                                            <TextBlock Text="{Binding KeyText}" TextWrapping="Wrap" Margin="0,0,0,12"/>
                                            <Button x:Name="CopyKeyButton" Content="Copy Key" Width="100" HorizontalAlignment="Left"
                                                    Height="32" Background="#0078D4" Foreground="White" BorderThickness="0"
                                                    Tag="{Binding Key}" Margin="0,0,0,4">
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
            [System.Windows.MessageBox]::Show(
                "Failed to create the confirmation dialog. Error: $_",
                "Dialog Creation Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
            return
        }
        
        # Get controls
        $servicesList = $confirmationWindow.FindName('ServicesList')
        $cancelButton = $confirmationWindow.FindName('CancelButton')
        $confirmButton = $confirmationWindow.FindName('ConfirmButton')
        $encryptionKeysList = $confirmationWindow.FindName('EncryptionKeysList')

        # Create a list to store encryption key information
        $encryptionKeys = New-Object System.Collections.ObjectModel.ObservableCollection[Object]

        # Get encryption keys for all selected devices
        foreach ($selectedDevice in $selectedDevices) {
            try {
                # Get device details from Intune
                $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=deviceName eq '$($selectedDevice.DeviceName)'"
                $intuneDevice = (Get-GraphPagedResults -Uri $uri) | Select-Object -First 1

                $keyInfo = @{
                    DeviceName = $selectedDevice.DeviceName
                    KeyText    = "Loading encryption key..."
                    Key        = $null
                }

                if ($intuneDevice) {
                    # Check OS type and get appropriate encryption key
                    if ($intuneDevice.operatingSystem -eq "Windows") {
                        try {
                            # First get the key ID using Azure AD device ID
                            $uri = "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$($intuneDevice.azureADDeviceId)'"
                            $keyIdResponse = Get-GraphPagedResults -Uri $uri
                            
                            if ($keyIdResponse.Count -gt 0) {
                                # Get the actual key using the key ID from the first recovery key
                                $recoveryKeyId = $keyIdResponse.id
                                $uri = "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys/$($recoveryKeyId)?`$select=key"
                                $recoveryKeyData = Invoke-MgGraphRequest -Uri $uri -Method GET
                                
                                if ($recoveryKeyData.key) {
                                    $keyInfo.KeyText = "BitLocker Recovery Key: $($recoveryKeyData.key)"
                                    $keyInfo.Key = $recoveryKeyData.key
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
                            Write-Log "Error retrieving BitLocker key: $_"
                            if ($_.Exception.Response.StatusCode -eq 'Forbidden') {
                                $keyInfo.KeyText = "BitLocker key access denied. Ensure BitlockerKey.Read.All permission is granted."
                            }
                            else {
                                $keyInfo.KeyText = "Error retrieving BitLocker key. Check logs for details."
                            }
                        }
                    }
                    elseif ($intuneDevice.operatingSystem -eq "macOS") {
                        # Get FileVault key using the dedicated endpoint for macOS
                        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$($intuneDevice.id)')/getFileVaultKey"
                        try {
                            $fileVaultKey = Invoke-MgGraphRequest -Uri $uri -Method GET
                            if ($fileVaultKey.value) {
                                $keyInfo.KeyText = "FileVault Recovery Key: $($fileVaultKey.value)"
                                $keyInfo.Key = $fileVaultKey.value
                            }
                            else {
                                $keyInfo.KeyText = "No FileVault recovery key found for this device."
                            }
                        }
                        catch {
                            #Write-Log "Error retrieving FileVault key: $_"
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
            }
            catch {
                #Write-Log "Error retrieving encryption key: $_"
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
            @{ Name = "Entra ID"; Icon = "M12,5.5A3.5,3.5 0 0,1 15.5,9A3.5,3.5 0 0,1 12,12.5A3.5,3.5 0 0,1 8.5,9A3.5,3.5 0 0,1 12,5.5M5,8C5.56,8 6.08,8.15 6.53,8.42C6.38,9.85 6.8,11.27 7.66,12.38C7.16,13.34 6.16,14 5,14A3,3 0 0,1 2,11A3,3 0 0,1 5,8M19,8A3,3 0 0,1 22,11A3,3 0 0,1 19,14C17.84,14 16.84,13.34 16.34,12.38C17.2,11.27 17.62,9.85 17.47,8.42C17.92,8.15 18.44,8 19,8M5.5,18.25C5.5,16.18 8.41,14.5 12,14.5C15.59,14.5 18.5,16.18 18.5,18.25V20H5.5V18.25M0,20V18.5C0,17.11 1.89,15.94 4.45,15.6C3.86,16.28 3.5,17.22 3.5,18.25V20H0M24,20H20.5V18.25C20.5,17.22 20.14,16.28 19.55,15.6C22.11,15.94 24,17.11 24,18.5V20Z" },
            @{ Name = "Intune"; Icon = "M21,14V4H3V14H21M21,2A2,2 0 0,1 23,4V16A2,2 0 0,1 21,18H14L16,21V22H8V21L10,18H3C1.89,18 1,17.1 1,16V4C1,2.89 1.89,2 3,2H21M4,5H20V13H4V5Z" },
            @{ Name = "Autopilot"; Icon = "M12,3L1,9L12,15L21,10.09V17H23V9M5,13.18V17.18L12,21L19,17.18V13.18L12,17L5,13.18Z" }
            @{ Name = "SCCM"; Icon = "m124.326-8.588 0 9.63c.964 58.745.001 43.336.28 73.96-.01 2.13-1.11 4.33-2.02 6.35-2.46 5.41-5.99 10.5-7.47 16.14-3.37 12.84-.25 24.68 7.68 35.31 3.81 5.11 2.96 7.64-2.7 10.1-3.03 1.32-5.93 3.01-8.69 4.83-23.23 15.29-24.92 60.96 1.44 77.85-33.02 0-66.04 0-89.156.326-.27-59.84.564-155.244-.963-234.014M44.16 85.04c6.86 0 13.72 0 20.65 0 0-6.72 0-13.56 0-20.45-7.07 0-13.8 0-20.9 0 0 6.68 0 13.11.25 20.45m50.94.53c.54-6.9 1.08-13.8 1.64-20.93-7.83 0-14.7 0-21.56 0 0 7.05 0 13.79 0 21 6.47 0 12.72 0 19.92-.07m-51.2 64c0 4.25 0 8.49 0 12.85 7.34 0 14.07 0 21.02 0 0-6.95 0-13.68 0-20.54-7.02 0-13.89 0-21.02 0 0 2.44 0 4.58 0 7.69m40.65-7.99c-3.11 0-6.22 0-9.31 0 0 7.24 0 13.97 0 20.85 7 0 13.73 0 20.72 0 0-6.94 0-13.66 0-20.85-3.53 0-6.99 0-11.41 0m-40.64-22.17c0 1.44 0 2.87 0 4.34 7.34 0 14.19 0 20.98 0 0-7.03 0-13.75 0-20.5-7.09 0-13.95 0-20.98 0 0 5.26 0 10.22 0 16.16m31.07-2.96c0 2.43 0 4.86 0 7.29 7.36 0 14.22 0 20.98 0 0-7.03 0-13.76 0-20.48-7.1 0-13.96 0-20.98 0 0 4.28 0 8.25 0 13.19zM127.47 226c-1.29-.79-1.97-1.88-2.94-2.32-13.82-6.29-21.43-16.87-22.52-32.09-1.27-17.82 3.31-32.84 20.54-41.28 4.35-2.13 9.4-2.83 14.06-4.17 5.25 14.73 10.75 18.98 22.61 18.18 10.2-.69 15.52-5.73 18.09-17.12 14.16-.87 29.37 9.33 33.28 23.68 4.17 15.28 4.37 30.67-7.23 43.24-4.33 4.69-10.61 7.58-15.67 11.58-19.7.29-39.72.29-60.21.29zM165.71 73.03c18.8 5.11 27.42 21.88 27.16 35.06-.31 15.41-11.84 29.97-27.09 33.78-14.91 3.72-31.78-3.51-38.92-16.68-8.28-15.27-5.92-32.22 6.19-43.35 9.2-8.46 19.94-11.61 32.67-8.81z" }
        )
        
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
            $checkbox.IsChecked = $true
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
            [System.Windows.MessageBox]::Show(
                "Failed to show the confirmation dialog. Error: $_",
                "Dialog Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
            return
        }
        if (-not $confirmationResult) {
            Write-Log "User canceled offboarding operation."
            return
        }

        # Create results collection to track all operations
        $offboardingResults = @()
        
        try {
            foreach ($device in $selectedDevices) {
                $deviceName = $device.DeviceName
                $serialNumber = $device.SerialNumber
                $deviceResult = @{
                    DeviceName   = $deviceName
                    SerialNumber = $serialNumber
                    EntraID      = @{ Found = $false; Success = $false; Error = $null }
                    Intune       = @{ Found = $false; Success = $false; Error = $null }
                    Autopilot    = @{ Found = $false; Success = $false; Error = $null }
                    SCCM         = @{ Found = $false; Success = $false; Error = $null }
                }

                Write-Log "Starting offboarding for device: $deviceName (Serial: $serialNumber)"

                # Get Entra ID Device(s) - Handle potential duplicates
                if ($script:serviceCheckboxes["Entra ID"].IsChecked -and $deviceName) {
                    $uri = "https://graph.microsoft.com/v1.0/devices?`$filter=displayName eq '$deviceName'"
                    $AADDevices = (Invoke-MgGraphRequest -Uri $uri -Method GET).value
                    
                    if ($AADDevices -and $AADDevices.Count -gt 0) {
                        $deviceResult.EntraID.Found = $true
                        
                        # Log if we found duplicates
                        if ($AADDevices.Count -gt 1) {
                            Write-Log "Found $($AADDevices.Count) devices with name '$deviceName' in Entra ID. Will process all duplicates."
                        }
                        
                        $deletedCount = 0
                        $failedCount = 0
                        $allErrors = @()
                        
                        foreach ($AADDevice in $AADDevices) {
                            # Try to extract serial number from physicalIds if we don't have it (only from first device)
                            if (-not $serialNumber -and $AADDevice.physicalIds -and $deletedCount -eq 0) {
                                foreach ($physicalId in $AADDevice.physicalIds) {
                                    if ($physicalId -match '\[SerialNumber\]:(.+)') {
                                        $serialNumber = $matches[1].Trim()
                                        Write-Log "Retrieved serial number from Entra ID device: $serialNumber"
                                        break
                                    }
                                }
                            }
                            
                            # Check if this device matches our serial number (if we have one)
                            $deviceSerial = $null
                            if ($AADDevice.physicalIds) {
                                foreach ($physicalId in $AADDevice.physicalIds) {
                                    if ($physicalId -match '\[SerialNumber\]:(.+)') {
                                        $deviceSerial = $matches[1].Trim()
                                        break
                                    }
                                }
                            }
                            
                            # If we have a serial number to match, skip devices that don't match
                            if ($serialNumber -and $deviceSerial -and $deviceSerial -ne $serialNumber) {
                                Write-Log "Skipping Entra ID device with ID $($AADDevice.id) - serial number mismatch (Device: $deviceSerial, Expected: $serialNumber)"
                                continue
                            }
                            
                            try {
                                $uri = "https://graph.microsoft.com/v1.0/devices/$($AADDevice.id)"
                                Invoke-MgGraphRequest -Uri $uri -Method DELETE
                                $deletedCount++
                                Write-Log "Successfully removed device $deviceName (ID: $($AADDevice.id), Serial: $deviceSerial) from Entra ID."
                            }
                            catch {
                                $failedCount++
                                $allErrors += $_.Exception.Message
                                Write-Log "Error removing device $deviceName (ID: $($AADDevice.id)) from Entra ID: $_"
                            }
                        }
                        
                        # Set overall success/failure status
                        if ($deletedCount -gt 0 -and $failedCount -eq 0) {
                            $deviceResult.EntraID.Success = $true
                            if ($deletedCount -gt 1) {
                                Write-Log "Successfully removed all $deletedCount duplicate devices named '$deviceName' from Entra ID."
                            }
                        }
                        elseif ($deletedCount -gt 0 -and $failedCount -gt 0) {
                            $deviceResult.EntraID.Success = $false
                            $deviceResult.EntraID.Error = "Partial success: Deleted $deletedCount device(s), failed to delete $failedCount device(s). Errors: " + ($allErrors -join "; ")
                        }
                        else {
                            $deviceResult.EntraID.Success = $false
                            $deviceResult.EntraID.Error = "Failed to delete any devices. Errors: " + ($allErrors -join "; ")
                        }
                    }
                    else {
                        Write-Log "Device $deviceName not found in Entra ID."
                    }
                }
                elseif ($deviceName -and -not $script:serviceCheckboxes["Entra ID"].IsChecked) {
                    Write-Log "Skipping Entra ID removal for device $deviceName (not selected)"
                }

                # Get Intune Device
                if ($script:serviceCheckboxes["Intune"].IsChecked) {
                    if ($deviceName) {
                        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=deviceName eq '$deviceName'"
                        $IntuneDevice = (Invoke-MgGraphRequest -Uri $uri -Method GET).value | Select-Object -First 1
                    }
                    if (-not $IntuneDevice -and $serialNumber) {
                        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=serialNumber eq '$serialNumber'"
                        $IntuneDevice = (Invoke-MgGraphRequest -Uri $uri -Method GET).value | Select-Object -First 1
                    }
                    if ($IntuneDevice) {
                        $deviceResult.Intune.Found = $true
                        
                        # Capture the serial number from Intune device if we don't have it
                        if (-not $serialNumber -and $IntuneDevice.serialNumber) {
                            $serialNumber = $IntuneDevice.serialNumber
                            Write-Log "Retrieved serial number from Intune device: $serialNumber"
                        }
                        
                        try {
                            $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$($IntuneDevice.id)"
                            Invoke-MgGraphRequest -Uri $uri -Method DELETE
                            $deviceResult.Intune.Success = $true
                            Write-Log "Successfully removed device $deviceName from Intune."
                        }
                        catch {
                            $deviceResult.Intune.Error = $_.Exception.Message
                            Write-Log "Error removing device $deviceName from Intune: $_"
                        }
                    }
                    else {
                        Write-Log "Device $deviceName not found in Intune."
                    }
                }
                else {
                    Write-Log "Skipping Intune removal for device $deviceName (not selected)"
                }

                # Get Autopilot Device
                if ($script:serviceCheckboxes["Autopilot"].IsChecked) {
                    $AutopilotDevice = $null
                    
                    # Try to find by serial number first if available
                    if ($serialNumber) {
                        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$serialNumber')"
                        $AutopilotDevice = (Invoke-MgGraphRequest -Uri $uri -Method GET).value | Select-Object -First 1
                        
                        if (-not $AutopilotDevice) {
                            Write-Log "Device with serial $serialNumber not found in Autopilot, trying by display name..."
                        }
                    }
                    
                    # If not found by serial number or no serial number available, try by display name
                    if (-not $AutopilotDevice -and $deviceName) {
                        Write-Log "Searching Autopilot by display name: $deviceName (using client-side filtering)"
                        try {
                            # Get all Autopilot devices and filter client-side since API doesn't support displayName filtering
                            $uri = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities"
                            $allAutopilotDevices = Get-GraphPagedResults -Uri $uri
                            
                            # Filter by display name (case-insensitive partial match)
                            $AutopilotDevice = $allAutopilotDevices | Where-Object { 
                                $_.displayName -and $_.displayName -like "*$deviceName*" 
                            } | Select-Object -First 1
                            
                            if ($AutopilotDevice) {
                                Write-Log "Found Autopilot device matching display name: $($AutopilotDevice.displayName)"
                            }
                        }
                        catch {
                            Write-Log "Error searching Autopilot devices by display name: $_"
                        }
                    }
                    
                    if ($AutopilotDevice) {
                        $deviceResult.Autopilot.Found = $true
                        try {
                            $uri = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities/$($AutopilotDevice.id)"
                            Invoke-MgGraphRequest -Uri $uri -Method DELETE
                            $deviceResult.Autopilot.Success = $true
                            Write-Log "Successfully removed device $deviceName from Autopilot (ID: $($AutopilotDevice.id))."
                        }
                        catch {
                            $deviceResult.Autopilot.Error = $_.Exception.Message
                            Write-Log "Error removing device $deviceName from Autopilot: $_"
                        }
                    }
                    else {
                        $searchCriteria = if ($serialNumber) { "serial $serialNumber or name $deviceName" } else { "name $deviceName" }
                        Write-Log "Device with $searchCriteria not found in Autopilot."
                    }
                }
                else {
                    Write-Log "Skipping Autopilot removal for device $deviceName (not selected)"
                }

                # Get SCCM Device
                if ($script:serviceCheckboxes["SCCM"].IsChecked) {
                    # --- SCCM Offboarding Section ---
                    # Notes:
                    # - This section attempts to remove the device from SCCM using Remove-CMDevice.
                    # - It first connects to SCCM, then tries to remove the device by name.
                    # - Results are tracked in $deviceResult.SCCM.
                    # - Any errors are logged.
                    # - The original PowerShell location is restored at the end.

                    ConnectSCCM
                    try {
                        $removeResult = Remove-CMDevice -Name $deviceName -Force -ErrorAction Stop
                        if ($?) {
                            $deviceResult.SCCM.Found = $true
                            $deviceResult.SCCM.Success = $true
                            Write-Log "Successfully removed device $deviceName from SCCM."
                        }
                        else {
                            $deviceResult.SCCM.Found = $true
                            $deviceResult.SCCM.Success = $false
                            $deviceResult.SCCM.Error = "Remove-CMDevice did not complete successfully."
                            Write-Log "Remove-CMDevice did not complete successfully for $deviceName."
                        }

                    }
                    catch {
                        Write-Log "Error during SCCM offboarding for device $deviceName : $_"
                    }
                    Set-Location $originaldrive
                }
                else {
                    Write-Log "Skipping SCCM removal for device $deviceName (not selected)"
                }

                $offboardingResults += $deviceResult
                Write-Log "Completed offboarding attempt for device: $deviceName"
            }

            # Show summary of all operations
            Show-OffboardingSummary -Results $offboardingResults
            
            # Update UI status indicators if all operations were successful
            $allEntraSuccess = $offboardingResults | Where-Object { $_.EntraID.Found -and $_.EntraID.Success } | Measure-Object | Select-Object -ExpandProperty Count
            $allIntuneSuccess = $offboardingResults | Where-Object { $_.Intune.Found -and $_.Intune.Success } | Measure-Object | Select-Object -ExpandProperty Count
            $allAutopilotSuccess = $offboardingResults | Where-Object { $_.Autopilot.Found -and $_.Autopilot.Success } | Measure-Object | Select-Object -ExpandProperty Count
            $allSCCMSuccess = $offboardingResults | Where-Object { $_.SCCM.Found -and $_.SCCM.Success } | Measure-Object | Select-Object -ExpandProperty Count

            if ($allEntraSuccess -gt 0) {
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
            if ($allSCCMSuccess -gt 0) {
                $Window.FindName('sccm_status').Text = "SCCM: Devices Removed"
                $Window.FindName('sccm_status').Foreground = "#FC8181"
            }   
        }
        catch {
            Write-Log "Critical error in offboarding operation. Exception: $_"
            [System.Windows.MessageBox]::Show("Critical error in offboarding operation. Please check the logs for details.")
        }
    })

# Export search results button
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
                    DeviceName      = $device.DeviceName
                    SerialNumber    = $device.SerialNumber
                    LastContact     = $device.LastContact
                    OperatingSystem = $device.OperatingSystem
                    OSVersion       = $device.OSVersion
                    PrimaryUser     = $device.PrimaryUser
                    IntuneStatus    = $device.IntuneStatus
                    AutopilotStatus = $device.AutopilotStatus
                    EntraIDStatus   = $device.EntraIDStatus
                }
            }
            
            Export-DeviceListToCSV -DeviceList $exportData -DefaultFileName $fileName
        }
        else {
            [System.Windows.MessageBox]::Show(
                "No search results to export.",
                "Export",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )
        }
    })

# Export selected devices button
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
                    DeviceName      = $device.DeviceName
                    SerialNumber    = $device.SerialNumber
                    LastContact     = $device.LastContact
                    OperatingSystem = $device.OperatingSystem
                    OSVersion       = $device.OSVersion
                    PrimaryUser     = $device.PrimaryUser
                    IntuneStatus    = $device.IntuneStatus
                    AutopilotStatus = $device.AutopilotStatus
                    EntraIDStatus   = $device.EntraIDStatus
                }
            }
            
            Export-DeviceListToCSV -DeviceList $exportData -DefaultFileName $fileName
        }
        else {
            [System.Windows.MessageBox]::Show(
                "No devices selected to export.",
                "Export Selected",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )
        }
    })
    
function Show-OffboardingSummary {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Results
    )
    
    [xml]$summaryModalXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" 
        Title="Offboarding Summary" Height="600" Width="800" WindowStartupLocation="CenterScreen" Background="#F8F9FA">
    <Border Background="White" CornerRadius="8" Margin="16">
        <DockPanel Margin="24">
            <!-- Header -->
            <StackPanel DockPanel.Dock="Top" Margin="0,0,0,24">
                <TextBlock Text="Offboarding Summary" FontSize="24" FontWeight="SemiBold" Foreground="#1A202C"/>
                <TextBlock Text="Review the results of the offboarding operation below" Foreground="#4A5568" FontSize="14" Margin="0,8,0,0"/>
            </StackPanel>

            <!-- Close Button -->
            <Button x:Name="CloseButton" DockPanel.Dock="Bottom" Content="Close" Width="120" Height="40" 
                    Background="#0078D4" Foreground="White" BorderThickness="0" HorizontalAlignment="Right" Margin="0,24,0,0"/>

            <!-- Main Content ScrollViewer -->
            <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,0,0,16">
                <StackPanel>
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
                                        </Grid.RowDefinitions>
                                        
                                        <!-- Device Header -->
                                        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
                                            <TextBlock Text="{Binding DeviceName}" FontWeight="SemiBold" FontSize="14" Margin="0,0,12,0"/>
                                            <TextBlock Text="{Binding SerialNumber, StringFormat='Serial: {0}'}" FontSize="12" Foreground="#718096" VerticalAlignment="Center"/>
                                        </StackPanel>
                                        
                                        <!-- Service Results -->
                                        <Grid Grid.Row="1">
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
                                            <StackPanel Grid.Column="2">
                                                <TextBlock Text="Autopilot" FontWeight="Medium" FontSize="12" Margin="0,0,0,4"/>
                                                <TextBlock x:Name="AutopilotStatus" Text="{Binding AutopilotStatus}" FontSize="11" Foreground="{Binding AutopilotColor}"/>
                                                <TextBlock Text="{Binding AutopilotError}" FontSize="10" Foreground="#F56565" TextWrapping="Wrap" Visibility="{Binding AutopilotErrorVisibility}"/>
                                            </StackPanel>

                                            <StackPanel Grid.Column="3">
                                                <TextBlock Text="SCCM" FontWeight="Medium" FontSize="12" Margin="0,0,0,4"/>
                                                <TextBlock x:Name="SCCMStatus" Text="{Binding SCCMStatus}" FontSize="11" Foreground="{Binding SCCMColor}"/>
                                                <TextBlock Text="{Binding SCCMError}" FontSize="10" Foreground="#F56565" TextWrapping="Wrap" Visibility="{Binding SCCMErrorVisibility}"/>
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
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error creating summary window: $_"
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
    $totalDevicesText = $summaryWindow.FindName('TotalDevicesText')
    $successfulText = $summaryWindow.FindName('SuccessfulText')
    $partialText = $summaryWindow.FindName('PartialText')
    $failedText = $summaryWindow.FindName('FailedText')
    $resultsList = $summaryWindow.FindName('ResultsList')
    
    # Calculate statistics
    $totalDevices = $Results.Count
    $successful = 0
    $partial = 0
    $failed = 0
    
    # Process results and create display objects
    $displayResults = @()
    
    foreach ($result in $Results) {
        $deviceSuccess = 0
        $deviceTotal = 0
        
        # Create display object for this device
        $displayResult = [PSCustomObject]@{
            DeviceName               = $result.DeviceName
            SerialNumber             = if ($result.SerialNumber) { $result.SerialNumber } else { "N/A" }
            
            # Entra ID
            EntraIDStatus            = if ($script:serviceCheckboxes -and $script:serviceCheckboxes["Entra ID"] -and -not $script:serviceCheckboxes["Entra ID"].IsChecked) {
                "Skipped"
            }
            elseif ($result.EntraID.Found) {
                if ($result.EntraID.Success) { "✓ Removed"; $deviceSuccess++ } else { "✗ Failed" }
            }
            else { "Not Found" }
            EntraIDColor             = if ($script:serviceCheckboxes -and $script:serviceCheckboxes["Entra ID"] -and -not $script:serviceCheckboxes["Entra ID"].IsChecked) {
                "#A0AEC0"
            }
            elseif (!$result.EntraID.Found) { "#718096" } elseif ($result.EntraID.Success) { "#48BB78" } else { "#F56565" }
            EntraIDError             = $result.EntraID.Error
            EntraIDErrorVisibility   = if ($result.EntraID.Error) { "Visible" } else { "Collapsed" }
            
            # Intune
            IntuneStatus             = if ($script:serviceCheckboxes -and $script:serviceCheckboxes["Intune"] -and -not $script:serviceCheckboxes["Intune"].IsChecked) {
                "Skipped"
            }
            elseif ($result.Intune.Found) {
                if ($result.Intune.Success) { "✓ Removed"; $deviceSuccess++ } else { "✗ Failed" }
            }
            else { "Not Found" }
            IntuneColor              = if ($script:serviceCheckboxes -and $script:serviceCheckboxes["Intune"] -and -not $script:serviceCheckboxes["Intune"].IsChecked) {
                "#A0AEC0"
            }
            elseif (!$result.Intune.Found) { "#718096" } elseif ($result.Intune.Success) { "#48BB78" } else { "#F56565" }
            IntuneError              = $result.Intune.Error
            IntuneErrorVisibility    = if ($result.Intune.Error) { "Visible" } else { "Collapsed" }
            
            # Autopilot
            AutopilotStatus          = if ($script:serviceCheckboxes -and $script:serviceCheckboxes["Autopilot"] -and -not $script:serviceCheckboxes["Autopilot"].IsChecked) {
                "Skipped"
            }
            elseif ($result.Autopilot.Found) {
                if ($result.Autopilot.Success) { "✓ Removed"; $deviceSuccess++ } else { "✗ Failed" }
            }
            else { "Not Found" }
            AutopilotColor           = if ($script:serviceCheckboxes -and $script:serviceCheckboxes["Autopilot"] -and -not $script:serviceCheckboxes["Autopilot"].IsChecked) {
                "#A0AEC0"
            }
            elseif (!$result.Autopilot.Found) { "#718096" } elseif ($result.Autopilot.Success) { "#48BB78" } else { "#F56565" }
            AutopilotError           = $result.Autopilot.Error
            AutopilotErrorVisibility = if ($result.Autopilot.Error) { "Visible" } else { "Collapsed" }

            # SCCM
            SCCMStatus               = if ($script:serviceCheckboxes -and $script:serviceCheckboxes["SCCM"] -and -not $script:serviceCheckboxes["SCCM"].IsChecked) {
                "Skipped"
            }
            elseif ($result.SCCM.Found) {
                if ($result.SCCM.Success) { "✓ Removed"; $deviceSuccess++ } else { "✗ Failed" }
            }
            else { "Not Found" }
            SCCMColor                = if ($script:serviceCheckboxes -and $script:serviceCheckboxes["SCCM"] -and -not $script:serviceCheckboxes["SCCM"].IsChecked) {
                "#A0AEC0"
            }
            elseif (!$result.SCCM.Found) { "#718096" } elseif ($result.SCCM.Success) { "#48BB78" } else { "#F56565" }
            SCCMError                = $result.SCCM.Error
            SCCMErrorVisibility      = if ($result.SCCM.Error) { "Visible" } else { "Collapsed" }
        }
        
        # Count total services device was found in (only for selected services)
        if ($script:serviceCheckboxes -and $script:serviceCheckboxes["Entra ID"] -and $script:serviceCheckboxes["Entra ID"].IsChecked -and $result.EntraID.Found) { 
            $deviceTotal++ 
        }
        if ($script:serviceCheckboxes -and $script:serviceCheckboxes["Intune"] -and $script:serviceCheckboxes["Intune"].IsChecked -and $result.Intune.Found) { 
            $deviceTotal++ 
        }
        if ($script:serviceCheckboxes -and $script:serviceCheckboxes["Autopilot"] -and $script:serviceCheckboxes["Autopilot"].IsChecked -and $result.Autopilot.Found) { 
            $deviceTotal++ 
        }
        if ($script:serviceCheckboxes -and $script:serviceCheckboxes["SCCM"] -and $script:serviceCheckboxes["SCCM"].IsChecked -and $result.SCCM.Found) {
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
    
    # Set results list
    $resultsList.ItemsSource = $displayResults
    
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
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error showing summary dialog: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to show the summary dialog. Error: $_",
            "Dialog Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

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
                    <TextBlock x:Name="CountText" Text="0 devices found" Foreground="#4A5568" FontSize="14" Margin="0,8,0,0"/>
                </StackPanel>
                <Button Grid.Column="1"
                        x:Name="ExportButton"
                        Content="Export to CSV"
                        Height="36"
                        Padding="16,0"
                        Background="#0078D4"
                        Foreground="White"
                        BorderThickness="0"
                        VerticalAlignment="Center">
                    <Button.Resources>
                        <Style TargetType="Border">
                            <Setter Property="CornerRadius" Value="4"/>
                        </Style>
                    </Button.Resources>
                </Button>
            </Grid>

            <!-- Close Button -->
            <Button x:Name="CloseButton" DockPanel.Dock="Bottom" Content="Close" Width="120" Height="40" 
                    Background="#F0F0F0" Foreground="#2D3748" BorderThickness="0" HorizontalAlignment="Right" Margin="0,24,0,0"/>

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
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error creating dashboard window: $_"
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
    $closeButton = $dashboardWindow.FindName('CloseButton')
    
    # Ensure DeviceList is an array
    if ($null -eq $DeviceList) {
        $DeviceList = @()
    }
    elseif ($DeviceList -isnot [array]) {
        $DeviceList = @($DeviceList)
    }
    
    # Set title and count
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
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error showing dashboard dialog: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to show the dashboard dialog. Error: $_",
            "Dialog Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

function Show-PrerequisitesDialog {
    try {
        $reader = (New-Object System.Xml.XmlNodeReader $prerequisitesModalXaml)
        $prereqWindow = [Windows.Markup.XamlReader]::Load($reader)
        
        if ($null -eq $prereqWindow) {
            throw "Failed to create prerequisites window. XamlReader returned null."
        }
    }
    catch {
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error creating prerequisites window: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to create the prerequisites dialog. Error: $_",
            "Dialog Creation Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return
    }

    # Get controls
    $permissionsPanel = $prereqWindow.FindName('PermissionsPanel')
    $modulePanel = $prereqWindow.FindName('ModulePanel')
    $closeButton = $prereqWindow.FindName('ClosePrereqButton')

    # Add required permissions with checkboxes
    $requiredPermissions = @(
        @{
            Name        = "Device.ReadWrite.All"
            Description = "Read and delete device objects from Entra ID"
        },
        @{
            Name        = "DeviceManagementApps.Read.All"
            Description = "Read mobile app management policies and configurations"
        },
        @{
            Name        = "DeviceManagementConfiguration.Read.All"
            Description = "Read device configuration policies and assignments"
        },
        @{
            Name        = "DeviceManagementManagedDevices.ReadWrite.All"
            Description = "Read and modify managed device information and compliance policies"
        },
        @{
            Name        = "DeviceManagementServiceConfig.ReadWrite.All"
            Description = "Read and modify Autopilot deployment profiles"
        },
        @{
            Name        = "Group.Read.All"
            Description = "Read group information and memberships"
        },
        @{
            Name        = "User.Read.All"
            Description = "Read user profile information and check group memberships"
        },
        @{
            Name        = "BitlockerKey.Read.All"
            Description = "Read BitLocker recovery keys for Windows devices"
        }
    )

    $context = Get-MgContext
    $currentPermissions = if ($context) { $context.Scopes } else { @() }

    foreach ($permission in $requiredPermissions) {
        $permItem = New-Object System.Windows.Controls.StackPanel
        $permItem.Style = $prereqWindow.FindResource("CheckItemStyle")
        $permItem.Orientation = "Horizontal"

        $checkbox = New-Object System.Windows.Controls.CheckBox
        $checkbox.IsEnabled = $false
        $checkbox.VerticalAlignment = "Center"
        $checkbox.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)

        if ($currentPermissions -contains $permission.Name -or
            $currentPermissions -contains $permission.Name.Replace(".Read", ".ReadWrite")) {
            $checkbox.IsChecked = $true
            $checkbox.Foreground = "#28A745"
        }
        else {
            $checkbox.IsChecked = $false
            $checkbox.Foreground = "#DC3545"
        }

        # Create a StackPanel for permission text and description
        $textPanel = New-Object System.Windows.Controls.StackPanel
        $textPanel.Orientation = "Vertical"
        $textPanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)

        # Permission name
        $permText = New-Object System.Windows.Controls.TextBlock
        $permText.Text = $permission.Name
        $permText.Style = $prereqWindow.FindResource("CheckTextStyle")
        $permText.FontWeight = "SemiBold"

        # Permission description
        $descText = New-Object System.Windows.Controls.TextBlock
        $descText.Text = $permission.Description
        $descText.Style = $prereqWindow.FindResource("CheckTextStyle")
        $descText.Foreground = "#666666"
        $descText.FontSize = 12
        $descText.TextWrapping = "Wrap"
        $descText.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)

        $textPanel.Children.Add($permText)
        $textPanel.Children.Add($descText)

        $permItem.Children.Add($checkbox)
        $permItem.Children.Add($textPanel)
        $permissionsPanel.Children.Add($permItem)
    }

    # Add module check
    $moduleItem = New-Object System.Windows.Controls.StackPanel
    $moduleItem.Style = $prereqWindow.FindResource("CheckItemStyle")
    $moduleItem.Orientation = "Horizontal"

    $moduleCheckbox = New-Object System.Windows.Controls.CheckBox
    $moduleCheckbox.IsEnabled = $false
    $moduleCheckbox.VerticalAlignment = "Center"
    $moduleCheckbox.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)

    # Create a StackPanel for module text and description
    $textPanel = New-Object System.Windows.Controls.StackPanel
    $textPanel.Orientation = "Vertical"
    $textPanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)

    # Module name
    $moduleText = New-Object System.Windows.Controls.TextBlock
    $moduleText.Text = "Microsoft.Graph.Authentication"
    $moduleText.Style = $prereqWindow.FindResource("CheckTextStyle")
    $moduleText.FontWeight = "SemiBold"

    # Module description
    $descText = New-Object System.Windows.Controls.TextBlock
    $descText.Text = "Required for Microsoft Graph API authentication and operations"
    $descText.Style = $prereqWindow.FindResource("CheckTextStyle")
    $descText.Foreground = "#666666"
    $descText.FontSize = 12
    $descText.TextWrapping = "Wrap"
    $descText.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)

    $textPanel.Children.Add($moduleText)
    $textPanel.Children.Add($descText)

    $installButton = New-Object System.Windows.Controls.Button
    $installButton.Content = "Install"
    $installButton.Style = $prereqWindow.FindResource("InstallButtonStyle")
    $installButton.Visibility = "Collapsed"
    $installButton.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)

    if (Get-Module -ListAvailable -Name "Microsoft.Graph.Authentication") {
        $moduleCheckbox.IsChecked = $true
        $moduleCheckbox.Foreground = "#28A745"
    }
    else {
        $moduleCheckbox.IsChecked = $false
        $moduleCheckbox.Foreground = "#DC3545"
        $installButton.Visibility = "Visible"
    }

    $moduleItem.Children.Add($moduleCheckbox)
    $moduleItem.Children.Add($textPanel)
    $moduleItem.Children.Add($installButton)
    $modulePanel.Children.Add($moduleItem)

    # Add install button click handler
    $installButton.Add_Click({
            try {
                $installButton.IsEnabled = $false
                $installButton.Content = "Installing..."

                Install-Module "Microsoft.Graph.Authentication" -Scope CurrentUser -Force
            
                $moduleCheckbox.IsChecked = $true
                $moduleCheckbox.Foreground = "#28A745"
                $installButton.Visibility = "Collapsed"

                # Restart required message
                [System.Windows.MessageBox]::Show(
                    "Module installed successfully. Please restart the application for changes to take effect.",
                    "Installation Complete",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )
            }
            catch {
                Write-Log "Error installing module: $_"
                [System.Windows.MessageBox]::Show(
                    "Failed to install module. Please ensure you have internet connection and necessary permissions.",
                    "Installation Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
                $installButton.IsEnabled = $true
                $installButton.Content = "Install"
            }
        })

    # Add close button handler
    $closeButton.Add_Click({
            $prereqWindow.Close()
        })

    # Show dialog
    try {
        if ($null -eq $prereqWindow) {
            throw "Prerequisites window is null. Cannot show dialog."
        }
        $prereqWindow.ShowDialog()
    }
    catch {
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error showing prerequisites dialog: $_"
        [System.Windows.MessageBox]::Show(
            "Failed to show the prerequisites dialog. Error: $_",
            "Dialog Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

$PrerequisitesButton.Add_Click({
        Show-PrerequisitesDialog
    })

$logs_button.Add_Click({
       # $logFilePath = [System.IO.Path]::Combine([Environment]::GetFolderPath("Desktop"), "IntuneOffboardingTool_Log.txt")
        if (Test-Path $logFilePath) {
            Invoke-Item $logFilePath
        }
        else {
            Write-Host "Log file not found."
        }
    })
    
# Lightweight loading dialog shown during long-running UI actions
function Show-LoadingDialog {
    param(
        [string]$Title = 'Loading',
        [string]$Message = 'Please wait...'
    )

    try {
        [xml]$loadingXaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Loading" Height="180" Width="420"
    WindowStartupLocation="CenterOwner"
    WindowStyle="None"
    ResizeMode="NoResize"
    Background="#00000000"
    AllowsTransparency="True"
    ShowInTaskbar="False"
    Topmost="True">
    <Border Background="#FFFFFFFF" CornerRadius="8" Margin="12">
        <Border.Effect>
            <DropShadowEffect ShadowDepth="2" Direction="315" Color="#000000" Opacity="0.25" BlurRadius="4"/>
        </Border.Effect>
        <StackPanel Margin="20">
            <TextBlock x:Name="TitleText"
                       Text="Loading"
                       FontSize="20"
                       FontWeight="SemiBold"
                       Foreground="#1A202C"
                       Margin="0,0,0,6"/>
            <TextBlock x:Name="MessageText"
                       Text="Please wait..."
                       Foreground="#4A5568"
                       FontSize="13"
                       TextWrapping="Wrap"
                       Margin="0,0,0,14"/>
            <ProgressBar IsIndeterminate="True"
                         Height="6"
                         Background="#EDF2F7"
                         Foreground="#0078D4"/>
        </StackPanel>
    </Border>
</Window>
"@
        $reader = New-Object System.Xml.XmlNodeReader $loadingXaml
        $loadingWindow = [Windows.Markup.XamlReader]::Load($reader)

        if ($null -eq $loadingWindow) { throw "Failed to create loading window" }

    # Set owner to main window if available so it centers correctly
    if ($Window) { $loadingWindow.Owner = $Window }

        # Populate title/message labels
        $titleBlock = $loadingWindow.FindName('TitleText')
        $msgBlock = $loadingWindow.FindName('MessageText')
        if ($titleBlock) { $titleBlock.Text = $Title }
        if ($msgBlock) { $msgBlock.Text = $Message }
        $loadingWindow.Title = $Title

        return $loadingWindow
    }
    catch {
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error creating loading dialog: $_"
        return $null
    }
}
        
# Add new control connections
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


# Set initial page visibility
$Window.Add_Loaded({
        # Set initial page visibility
        $HomePage.Visibility = 'Visible'
        $DashboardPage.Visibility = 'Collapsed'
        $DeviceManagementPage.Visibility = 'Collapsed'
        $PlaybooksPage.Visibility = 'Collapsed'
        $PlaybookResultsGrid.Visibility = 'Collapsed'
    })

# Add menu switching functionality
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
            # Show a loading dialog while the dashboard populates
            $script:currentLoadingWindow = Show-LoadingDialog -Title 'Loading Dashboard' -Message 'Fetching device statistics and charts...'
            if ($script:currentLoadingWindow) { $script:currentLoadingWindow.Show() }
            try {
                # Run the update and keep UI responsive
                $Window.Dispatcher.Invoke([Action]{ Update-DashboardStatistics }, 'Background')
            }
            catch {
                if ($script:currentLoadingWindow) { try { $script:currentLoadingWindow.Close() } catch {} ; $script:currentLoadingWindow = $null }
                throw
            }
        }
    })


$MenuDeviceManagement.Add_Checked({
        $HomePage.Visibility = 'Collapsed'
        $DashboardPage.Visibility = 'Collapsed'
        $DeviceManagementPage.Visibility = 'Visible'
        $PlaybooksPage.Visibility = 'Collapsed'
        $PlaybookResultsGrid.Visibility = 'Collapsed'
    })

$MenuPlaybooks.Add_Checked({
        $HomePage.Visibility = 'Collapsed'
        $DashboardPage.Visibility = 'Collapsed'
        $DeviceManagementPage.Visibility = 'Collapsed'
        $PlaybooksPage.Visibility = 'Visible'
        $PlaybookResultsGrid.Visibility = 'Collapsed'
        $Window.FindName('PlaybooksScrollViewer').Visibility = 'Visible'
    })

function Update-DashboardStatistics {
    try {
        Write-Log "Updating dashboard statistics..."
        $startTime = Get-Date
        Write-Log "Starting parallel API calls at $startTime"
            
        # Run each call in a separate thread job with timing
        Write-Log "Starting Intune devices job..."
        $intuneJobStart = Get-Date
        $intuneJob = Start-ThreadJob -ScriptBlock {
            function Get-GraphPagedResults {
                param([string]$Uri)
                $results = @()
                $nextLink = $Uri
                do {
                    $response = Invoke-MgGraphRequest -Uri $nextLink -Method GET
                    if ($response.value) { $results += $response.value }
                    $nextLink = $response.'@odata.nextLink'
                } while ($nextLink)
                return $results
            }
            # Pull Intune devices
            $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
            $devices = Get-GraphPagedResults -Uri $uri
            # Ensure we return an array
            return @($devices)
        }
        
        Write-Log "Starting Autopilot devices job..."
        $autopilotJobStart = Get-Date
        $autopilotJob = Start-ThreadJob -ScriptBlock {
            function Get-GraphPagedResults {
                param([string]$Uri)
                $results = @()
                $nextLink = $Uri
                do {
                    $response = Invoke-MgGraphRequest -Uri $nextLink -Method GET
                    if ($response.value) { $results += $response.value }
                    $nextLink = $response.'@odata.nextLink'
                } while ($nextLink)
                return $results
            }
            # Pull Autopilot devices
            $uri = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities"
            $devices = Get-GraphPagedResults -Uri $uri
            # Ensure we return an array
            return @($devices)
        }
        
        Write-Log "Starting Entra ID devices job..."
        $entraJobStart = Get-Date
        $entraJob = Start-ThreadJob -ScriptBlock {
            function Get-GraphPagedResults {
                param([string]$Uri)
                $results = @()
                $nextLink = $Uri
                do {
                    $response = Invoke-MgGraphRequest -Uri $nextLink -Method GET
                    if ($response.value) { $results += $response.value }
                    $nextLink = $response.'@odata.nextLink'
                } while ($nextLink)
                return $results
            }
            # Pull Entra ID devices
            $uri = "https://graph.microsoft.com/v1.0/devices"
            $devices = Get-GraphPagedResults -Uri $uri
            # Ensure we return an array
            return @($devices)
        }

        Write-Log "Starting SCCM devices job..."
        $sccmJobStart = Get-Date
        $sccmJob = Start-ThreadJob -ScriptBlock {
            ##Load the Configuration Manager Module
            import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1')
            $Drive = Get-PSDrive -PSProvider CMSite
            Set-Location "$($Drive):"

            $devices = get-cmdevice -CollectionID 'SMSDM003' -fast | Where-Object { $_.IsClient -eq $true -and $_.IsActive -eq $true }

            # Ensure we return an array
            return @($devices)
        }
        
        # Use a DispatcherTimer so the UI remains responsive (allows loading bar to animate)
        if ($script:dashboardUpdateTimer) { $script:dashboardUpdateTimer.Stop(); $script:dashboardUpdateTimer = $null }
        $script:dashboardUpdateContext = [pscustomobject]@{
            IntuneJob        = $intuneJob
            AutopilotJob     = $autopilotJob
            EntraJob         = $entraJob
            SccmJob          = $sccmJob
            IntuneJobStart   = $intuneJobStart
            AutopilotJobStart= $autopilotJobStart
            EntraJobStart    = $entraJobStart
            SccmJobStart     = $sccmJobStart
        }

        $script:dashboardUpdateTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:dashboardUpdateTimer.Interval = [TimeSpan]::FromMilliseconds(250)
        $script:dashboardUpdateTimer.Add_Tick({
                $ctx = $script:dashboardUpdateContext
                if (-not $ctx) { return }

                $jobs = @($ctx.IntuneJob, $ctx.AutopilotJob, $ctx.EntraJob, $ctx.SccmJob)
                $allDone = $true
                foreach ($j in $jobs) {
                    if ($null -eq $j -or ($j.State -notin 'Completed','Failed','Stopped')) { $allDone = $false; break }
                }
                if (-not $allDone) { return }

                # Stop timer
                $script:dashboardUpdateTimer.Stop()
                $script:dashboardUpdateTimer = $null

                # Receive results with timing logs
                $intuneJobResult = try { Receive-Job -Job $ctx.IntuneJob -ErrorAction Stop } catch { Write-Log "Error receiving Intune devices job: $_"; $null }
                $intuneJobDuration = (Get-Date) - $ctx.IntuneJobStart
                Write-Log "Intune devices job completed in $($intuneJobDuration.TotalSeconds) seconds"

                $autopilotJobResult = try { Receive-Job -Job $ctx.AutopilotJob -ErrorAction Stop } catch { Write-Log "Error receiving Autopilot devices job: $_"; $null }
                $autopilotJobDuration = (Get-Date) - $ctx.AutopilotJobStart
                Write-Log "Autopilot devices job completed in $($autopilotJobDuration.TotalSeconds) seconds"

                $entraJobResult = try { Receive-Job -Job $ctx.EntraJob -ErrorAction Stop } catch { Write-Log "Error receiving Entra ID devices job: $_"; $null }
                $entraJobDuration = (Get-Date) - $ctx.EntraJobStart
                Write-Log "Entra ID devices job completed in $($entraJobDuration.TotalSeconds) seconds"

                $SCCMJobResult = try { Receive-Job -Job $ctx.SccmJob -ErrorAction Stop } catch { Write-Log "Error receiving SCCM devices job: $_"; $null }
                $sccmJobDuration = (Get-Date) - $ctx.SccmJobStart
                Write-Log "SCCM devices job completed in $($sccmJobDuration.TotalSeconds) seconds"

                # Clean up jobs
                try { Remove-Job -Job $jobs -Force -ErrorAction SilentlyContinue } catch {}

                # Convert results to arrays, handling various return types
                $intuneDevices = if ($null -eq $intuneJobResult) { @() } elseif ($intuneJobResult -is [System.Collections.Hashtable]) { Write-Log "WARNING: Intune job returned a hashtable instead of array. Converting..."; @($intuneJobResult.value) } elseif ($intuneJobResult -is [System.Array]) { $intuneJobResult } else { @($intuneJobResult) }
                $autopilotDevices = if ($null -eq $autopilotJobResult) { @() } elseif ($autopilotJobResult -is [System.Collections.Hashtable]) { Write-Log "WARNING: Autopilot job returned a hashtable instead of array. Converting..."; @($autopilotJobResult.value) } elseif ($autopilotJobResult -is [System.Array]) { $autopilotJobResult } else { @($autopilotJobResult) }
                $entraDevices = if ($null -eq $entraJobResult) { @() } elseif ($entraJobResult -is [System.Collections.Hashtable]) { Write-Log "WARNING: Entra job returned a hashtable instead of array. Converting..."; @($entraJobResult.value) } elseif ($entraJobResult -is [System.Array]) { $entraJobResult } else { @($entraJobResult) }
                $sccmDevices = if ($null -eq $SCCMJobResult) { @() } elseif ($SCCMJobResult -is [System.Collections.Hashtable]) { Write-Log "WARNING: SCCM job returned a hashtable instead of array. Converting..."; @($SCCMJobResult.value) } elseif ($SCCMJobResult -is [System.Array]) { $SCCMJobResult } else { @($SCCMJobResult) }

                Write-Log "Total devices - Intune: $($intuneDevices.Count), Autopilot: $($autopilotDevices.Count), Entra: $($entraDevices.Count), SCCM: $($sccmDevices.Count)"

                # Update top row counts
                $Window.FindName('IntuneDevicesCount').Text = $intuneDevices.Count
                $Window.FindName('AutopilotDevicesCount').Text = $autopilotDevices.Count
                $Window.FindName('EntraIDDevicesCount').Text = $entraDevices.Count
                $Window.FindName('SCCMDevicesCount').Text = $sccmDevices.Count

                # Calculate stale devices
                $thirtyDaysAgo = (Get-Date).AddDays(-30)
                $ninetyDaysAgo = (Get-Date).AddDays(-90)
                $onehundredEightyDaysAgo = (Get-Date).AddDays(-180)

                Write-Log "Total Intune devices to check: $($intuneDevices.Count)"

                $stale30 = ($intuneDevices | Where-Object {
                        if ($_.lastSyncDateTime) {
                            try {
                                $lastSync = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime
                                if (-not $lastSync) { return $false }
                                return $lastSync -lt $thirtyDaysAgo
                            }
                            catch {
                                Write-Log "Error parsing date: $($_.lastSyncDateTime). Error: $_"
                                return $false
                            }
                        }
                        else { return $false }
                    }).Count

                # Calculate 90-day stale devices
                Write-Log "Calculating 90-day stale devices from $($intuneDevices.Count) Intune devices"
                $stale90Count = 0
                foreach ($device in $intuneDevices) {
                    if ($device.lastSyncDateTime) {
                        try {
                            $lastSync = ConvertTo-SafeDateTime -dateString $device.lastSyncDateTime
                            if ($lastSync -and ($lastSync -lt $ninetyDaysAgo)) {
                                Write-Log "90-day stale device found: $($device.deviceName), LastSync: $lastSync"
                                $stale90Count++
                            }
                        }
                        catch {
                            Write-Log "Error parsing date for device $($device.deviceName): $_"
                        }
                    }
                }
                $stale90 = $stale90Count
                Write-Log "90-day stale devices found: $stale90"

                # Calculate 180-day stale devices
                Write-Log "Calculating 180-day stale devices from $($intuneDevices.Count) Intune devices"
                $stale180Count = 0
                foreach ($device in $intuneDevices) {
                    if ($device.lastSyncDateTime) {
                        try {
                            $lastSync = ConvertTo-SafeDateTime -dateString $device.lastSyncDateTime
                            if ($lastSync -and ($lastSync -lt $onehundredEightyDaysAgo)) {
                                Write-Log "180-day stale device found: $($device.deviceName), LastSync: $lastSync"
                                $stale180Count++
                            }
                        }
                        catch {
                            Write-Log "Error parsing date for device $($device.deviceName): $_"
                        }
                    }
                }
                $stale180 = $stale180Count

                Write-Log "Stale device counts - 30 days: $stale30, 90 days: $stale90, 180 days: $stale180"
                $Window.FindName('StaleDevices30Count').Text = $stale30
                $Window.FindName('StaleDevices90Count').Text = $stale90
                $Window.FindName('StaleDevices180Count').Text = $stale180

                # Update personal/corporate counts and progress bars
                $personalDevices = ($intuneDevices | Where-Object { $_.managedDeviceOwnerType -eq 'personal' }).Count
                $corporateDevices = ($intuneDevices | Where-Object { $_.managedDeviceOwnerType -eq 'company' }).Count
                $totalDevices = if ($intuneDevices) { $intuneDevices.Count } else { 0 }

                # Update counts
                $Window.FindName('PersonalDevicesCount').Text = $personalDevices
                $Window.FindName('CorporateDevicesCount').Text = $corporateDevices

                # Update progress bars
                if ($totalDevices -gt 0) {
                    $personalProgress = [Math]::Round(($personalDevices / $totalDevices) * 100)
                    $corporateProgress = [Math]::Round(($corporateDevices / $totalDevices) * 100)
                    $Window.FindName('PersonalDevicesProgress').Value = $personalProgress
                    $Window.FindName('CorporateDevicesProgress').Value = $corporateProgress
                }

                # Group platform distribution
                $platformGroups = $intuneDevices | Group-Object -Property {
                    $os = $_.operatingSystem
                    if ([string]::IsNullOrWhiteSpace($os)) { return 'Unknown' }
                    switch -Regex ($os.ToLower()) {
                        'windows' { 'Windows' }
                        'macos|mac os' { 'macOS' }
                        'linux' { 'Linux' }
                        'ios' { 'iOS' }
                        'android' { 'Android' }
                        default { 'Other' }
                    }
                } | Sort-Object Count -Descending

                # Define platform colors
                $platformColors = @{
                    'Windows' = '#0078D4'
                    'iOS'     = '#48BB78'
                    'Android' = '#9F7AEA'
                    'macOS'   = '#F6AD55'
                    'Linux'   = '#FC8181'
                    'Other'   = '#718096'
                    'Unknown' = '#718096'
                }

                # Get the canvas and legend panel
                $canvas = $Window.FindName('PlatformDistributionCanvas')
                $legendPanel = $Window.FindName('PlatformDistributionLegend')
                $canvas.Children.Clear()
                $legendPanel.Children.Clear()

                $total = ($platformGroups | Measure-Object Count -Sum).Sum
                if ($total -gt 0) {
                    $centerX = 100; $centerY = 100; $radius = 80; $startAngle = 0
                    foreach ($platform in $platformGroups) {
                        $percentage = $platform.Count / $total
                        $sweepAngle = 360 * $percentage
                        $startRad = $startAngle * [Math]::PI / 180
                        $endRad = ($startAngle + $sweepAngle) * [Math]::PI / 180
                        $startX = $centerX + $radius * [Math]::Cos($startRad)
                        $startY = $centerY + $radius * [Math]::Sin($startRad)
                        $endX = $centerX + $radius * [Math]::Cos($endRad)
                        $endY = $centerY + $radius * [Math]::Sin($endRad)
                        $path = New-Object System.Windows.Shapes.Path
                        $pathGeometry = New-Object System.Windows.Media.PathGeometry
                        $pathFigure = New-Object System.Windows.Media.PathFigure
                        $pathFigure.StartPoint = New-Object System.Windows.Point($centerX, $centerY)
                        $lineSegment = New-Object System.Windows.Media.LineSegment((New-Object System.Windows.Point($startX, $startY)), $true)
                        $pathFigure.Segments.Add($lineSegment)
                        $arcSegment = New-Object System.Windows.Media.ArcSegment((New-Object System.Windows.Point($endX, $endY)), (New-Object System.Windows.Size($radius, $radius)), 0, ($sweepAngle -gt 180), [System.Windows.Media.SweepDirection]::Clockwise, $true)
                        $pathFigure.Segments.Add($arcSegment)
                        $lineSegment = New-Object System.Windows.Media.LineSegment((New-Object System.Windows.Point($centerX, $centerY)), $true)
                        $pathFigure.Segments.Add($lineSegment)
                        $pathGeometry.Figures.Add($pathFigure)
                        $path.Data = $pathGeometry
                        $color = if ($platformColors.ContainsKey($platform.Name)) { $platformColors[$platform.Name] } else { $platformColors['Unknown'] }
                        $path.Fill = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($color))
                        $canvas.Children.Add($path)
                        $legendItem = New-Object System.Windows.Controls.StackPanel
                        $legendItem.Orientation = 'Horizontal'
                        $legendItem.Margin = New-Object System.Windows.Thickness(0,0,0,5)
                        $colorBox = New-Object System.Windows.Shapes.Rectangle
                        $colorBox.Width = 12; $colorBox.Height = 12; $colorBox.Fill = $path.Fill
                        $colorBox.Margin = New-Object System.Windows.Thickness(0,0,5,0)
                        $label = New-Object System.Windows.Controls.TextBlock
                        $label.Text = "$(($platform.Name)) ($([Math]::Round($percentage * 100))%)"
                        $label.Foreground = 'White'
                        $label.VerticalAlignment = 'Center'
                        $legendItem.Children.Add($colorBox)
                        $legendItem.Children.Add($label)
                        $legendPanel.Children.Add($legendItem)
                        $startAngle += $sweepAngle
                    }
                }

                # Close loading window if present
                if ($script:currentLoadingWindow) {
                    try { $script:currentLoadingWindow.Close() } catch {}
                    $script:currentLoadingWindow = $null
                }

                Write-Log 'Dashboard statistics updated successfully.'
            })

        # Start the timer and immediately return to keep UI responsive
        $script:dashboardUpdateTimer.Start()
        return
    }
    catch {
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error updating dashboard statistics: $_"
        [System.Windows.MessageBox]::Show("Error updating dashboard statistics. Please ensure you are connected to MS Graph.")
    }
}

# Connect playbook buttons
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
    $Window.FindName('PlaybookFileVault')
)

# Add click handlers for playbook buttons
# Add click handlers for playbook buttons
foreach ($button in $PlaybookButtons) {
    $button.Add_Click({
            if ($AuthenticateButton.IsEnabled) {
                [System.Windows.MessageBox]::Show(
                    "Please connect to Microsoft Graph first.",
                    "Authentication Required",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                )
                return
            }
            $playbookName = $this.Content.ToString()
            $playbookDescription = $this.Tag.ToString()
        
            switch ($playbookName) {
                "Autopilot Devices Not in Intune" {
                    $playbookUrl = "https://raw.githubusercontent.com/ugurkocde/DeviceOffboardingManager/refs/heads/main/Playbooks/Playbook_1.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookUrl $playbookUrl -Description $playbookDescription
                }
                "Intune Devices Not in Autopilot" {
                    $playbookUrl = "https://raw.githubusercontent.com/ugurkocde/DeviceOffboardingManager/refs/heads/main/Playbooks/Playbook_2.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookUrl $playbookUrl -Description $playbookDescription
                }
                "Corporate Device Inventory" {
                    $playbookUrl = "https://raw.githubusercontent.com/ugurkocde/DeviceOffboardingManager/refs/heads/main/Playbooks/Playbook_3.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookUrl $playbookUrl -Description $playbookDescription
                }
                "Personal Device Inventory" {
                    $playbookUrl = "https://raw.githubusercontent.com/ugurkocde/DeviceOffboardingManager/refs/heads/main/Playbooks/Playbook_4.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookUrl $playbookUrl -Description $playbookDescription
                }
                "Stale Device Report" {
                    $playbookUrl = "https://raw.githubusercontent.com/ugurkocde/DeviceOffboardingManager/refs/heads/main/Playbooks/Playbook_5.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookUrl $playbookUrl -Description $playbookDescription
                }
                default {
                    [System.Windows.MessageBox]::Show(
                        "This playbook is not yet implemented.",
                        "Not Implemented",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Information
                    )
                }
            }
        })
}

# Results Grid
$SearchResultsDataGrid = $Window.FindName('SearchResultsDataGrid')
$OffboardButton = $Window.FindName('OffboardButton')
$ExportSelectedButton = $Window.FindName('ExportSelectedButton')

# Create and configure Select All checkbox
$SelectAllCheckBox = New-Object System.Windows.Controls.CheckBox
$SelectAllCheckBox.Content = ""
$SelectAllCheckBox.ToolTip = "Select/Deselect All"
($SearchResultsDataGrid.Columns[0]).Width = 33
($SearchResultsDataGrid.Columns[0]).Header = $SelectAllCheckBox

# Add Select All checkbox click handler
$SelectAllCheckBox.Add_Click({
        $allChecked = $SelectAllCheckBox.IsChecked
        if ($SearchResultsDataGrid.ItemsSource) {
            foreach ($device in $SearchResultsDataGrid.ItemsSource) {
                $device.IsSelected = $allChecked
            }
            # Update button states
            $OffboardButton.IsEnabled = $allChecked
            $ExportSelectedButton.IsEnabled = $allChecked
        }
    })

# Initially disable the Offboard button and Export Selected button
$OffboardButton.IsEnabled = $false
$ExportSelectedButton.IsEnabled = $false

# Add selection changed event handler for the DataGrid
$SearchResultsDataGrid.Add_SelectionChanged({
        # Update the Offboard button state based on selected devices
        $selectedDevices = $SearchResultsDataGrid.ItemsSource | Where-Object { $_.IsSelected }
        $hasSelection = ($null -ne $selectedDevices -and $selectedDevices.Count -gt 0)
        $OffboardButton.IsEnabled = $hasSelection
        $ExportSelectedButton.IsEnabled = $hasSelection
    })

# Add handler for checkbox selection changes
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
                        
                        # Update Offboard button state
                        $selectedDevices = $SearchResultsDataGrid.ItemsSource | Where-Object { $_.IsSelected }
                        $hasSelection = ($null -ne $selectedDevices -and $selectedDevices.Count -gt 0)
                        $OffboardButton.IsEnabled = $hasSelection
                        $ExportSelectedButton.IsEnabled = $hasSelection
                    }
                })
        }
    })
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
                        Visibility="Collapsed"/>
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
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error creating progress window: $_"
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

# Function to execute playbook
function Invoke-Playbook {
    param(
        [string]$PlaybookName,
        [string]$PlaybookUrl,
        [string]$Description
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
        
        # Download playbook
        $status.Text = "Downloading playbook script..."
        Write-Log "Downloading playbook from: $PlaybookUrl"
        
        $playbookPath = ".\Playbook_1.ps1"
        
        try {
            Invoke-WebRequest -Uri $PlaybookUrl -OutFile $playbookPath -ErrorAction Stop
            Write-Log "Playbook downloaded successfully to: $playbookPath"
            
            # Execute playbook
            $status.Text = "Executing playbook..."
            Write-Log "Executing playbook: $playbookPath"
            
            $rawResults = & $playbookPath
            
            # Filter out only the actual device objects
            $results = $rawResults | Where-Object {
                $_ -and
                $_.PSObject.Properties['SerialNumber'] -and
                $_.SerialNumber -and
                -not $_.PSObject.Properties['ClassId2e4f51ef21dd47e99d3c952918aff9cd']
            }
            
            $status.Text = "Processing results..."
            
            if ($results) {
                # Create device objects
                $deviceObjects = $results | ForEach-Object {
                    [PSCustomObject]@{
                        DeviceName           = $_.DeviceName
                        SerialNumber         = $_.SerialNumber
                        OperatingSystem      = $_.OperatingSystem
                        PrimaryUser          = $_.PrimaryUser
                        AutopilotLastContact = $_.AutopilotLastContact
                    }
                }
                
                # Update the DataGrid with results
                $PlaybookResultsDataGrid.Dispatcher.Invoke([Action] {
                    
                        # Clear existing results
                        $PlaybookResultsDataGrid.ItemsSource = $null
                    
                        # Add each device to the collection
                        $collection = New-Object System.Collections.ObjectModel.ObservableCollection[object]
                        foreach ($device in $deviceObjects) {
                            $collection.Add($device)
                        }
                        # Configure DataGrid columns for playbook results
                        $PlaybookResultsDataGrid.Columns.Clear()
                        $PlaybookResultsDataGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
                                    Header  = "Device Name"
                                    Binding = New-Object System.Windows.Data.Binding("DeviceName")
                                    Width   = "Auto"
                                }))
                        $PlaybookResultsDataGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
                                    Header  = "Serial Number"
                                    Binding = New-Object System.Windows.Data.Binding("SerialNumber")
                                    Width   = "Auto"
                                }))
                        $PlaybookResultsDataGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
                                    Header  = "Operating System"
                                    Binding = New-Object System.Windows.Data.Binding("OperatingSystem")
                                    Width   = "Auto"
                                }))
                        $PlaybookResultsDataGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
                                    Header  = "Primary User"
                                    Binding = New-Object System.Windows.Data.Binding("PrimaryUser")
                                    Width   = "Auto"
                                }))
                        $PlaybookResultsDataGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
                                    Header  = "Last Contact"
                                    Binding = New-Object System.Windows.Data.Binding("AutopilotLastContact")
                                    Width   = "Auto"
                                }))

                        # Set the ItemsSource
                        $PlaybookResultsDataGrid.ItemsSource = $collection
                        # Update visibility and header text
                        $Window.FindName('PlaybooksScrollViewer').Visibility = 'Collapsed'
                        $PlaybookResultsGrid.Visibility = 'Visible'
                        $Window.FindName('PlaybookResultsHeader').Text = $PlaybookName
                    
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
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error executing playbook: $_"
        if ($null -ne $progressWindow) {
            $errorMessage.Text = $_.Exception.Message
            $errorSection.Visibility = 'Visible'
            $closeButton.Visibility = 'Visible'
            $status.Text = "Error occurred during execution"
        }
        else {
            [System.Windows.MessageBox]::Show(
                "Error executing playbook: $_",
                "Playbook Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
        }
    }
}


# Add changelog functionality
function Show-ChangelogDialog {
    try {
        Write-Log "Opening changelog dialog..."
        
        $reader = (New-Object System.Xml.XmlNodeReader $changelogModalXaml)
        try {
            $changelogWindow = [Windows.Markup.XamlReader]::Load($reader)
            
            if ($null -eq $changelogWindow) {
                throw "Failed to create changelog window. XamlReader returned null."
            }
        }
        catch {
            Write-Log "Error loading changelog window: $_"
            [System.Windows.MessageBox]::Show(
                "Failed to create the changelog dialog. Error: $_",
                "Dialog Creation Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
            return
        }
        
        # Get controls
        $closeButton = $changelogWindow.FindName('CloseChangelogButton')
        $contentBlock = $changelogWindow.FindName('ChangelogContent')
        
        # Add close button handler
        $closeButton.Add_Click({
                $changelogWindow.Close()
            })
        
        # Helper function to parse markdown formatting in text
        function Parse-MarkdownText {
            param($text, $paragraph)
            
            # Pattern to match bold (**text**), italic (*text*), and code (`text`) in any combination
            $pattern = '(\*\*[^\*]+\*\*|\*[^\*]+\*|`[^`]+`|[^*`]+)'
            
            $matches = [regex]::Matches($text, $pattern)
            
            foreach ($match in $matches) {
                $value = $match.Value
                
                if ($value -match '^\*\*(.+)\*\*$') {
                    # Bold text
                    $run = New-Object System.Windows.Documents.Run($matches[1])
                    $run.FontWeight = 'Bold'
                    $paragraph.Inlines.Add($run)
                }
                elseif ($value -match '^\*([^\*]+)\*$') {
                    # Italic text
                    $run = New-Object System.Windows.Documents.Run($matches[1])
                    $run.FontStyle = 'Italic'
                    $paragraph.Inlines.Add($run)
                }
                elseif ($value -match '^`([^`]+)`$') {
                    # Inline code
                    $run = New-Object System.Windows.Documents.Run($matches[1])
                    $run.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
                    $run.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(240, 240, 240))
                    $run.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(212, 0, 0))
                    $paragraph.Inlines.Add($run)
                }
                else {
                    # Regular text
                    if ($value.Trim()) {
                        $run = New-Object System.Windows.Documents.Run($value)
                        $paragraph.Inlines.Add($run)
                    }
                }
            }
        }
        
        # Fetch and display changelog content
        try {
            $markdownContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/ugurkocde/DeviceOffboardingManager/refs/heads/main/Changelog.md" -Method Get
            
            # Create new FlowDocument
            $flowDoc = New-Object System.Windows.Documents.FlowDocument
            $flowDoc.PageWidth = 700 # Set a fixed width for proper text flow
            
            # Process markdown content line by line
            $markdownContent -split "`n" | ForEach-Object {
                $line = $_.TrimEnd()
                
                if ($line) {
                    $paragraph = New-Object System.Windows.Documents.Paragraph
                    
                    # Headers
                    if ($line -match '^(#{1,6})\s+(.+)$') {
                        $headerLevel = $matches[1].Length
                        $headerText = $matches[2]
                        $run = New-Object System.Windows.Documents.Run($headerText)
                        $run.FontSize = (24 - ($headerLevel * 2))
                        $run.FontWeight = 'Bold'
                        if ($headerLevel -eq 2) {
                            # Main version headers
                            $run.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0, 120, 212))
                        }
                        $paragraph.Inlines.Add($run)
                        $paragraph.Margin = New-Object System.Windows.Thickness(0, 10, 0, 5)
                    }
                    # List items
                    elseif ($line -match '^(\s*)-\s+(.+)$') {
                        $indent = $matches[1].Length
                        $listText = $matches[2]
                        
                        # Calculate indentation level (2 spaces = 1 level)
                        $indentLevel = [Math]::Floor($indent / 2)
                        $leftMargin = 20 + ($indentLevel * 20)
                        
                        # Add bullet
                        $bullet = New-Object System.Windows.Documents.Run('• ')
                        $bullet.FontWeight = 'Bold'
                        $paragraph.Inlines.Add($bullet)
                        
                        # Parse the list item text for formatting
                        Parse-MarkdownText -text $listText -paragraph $paragraph
                        
                        $paragraph.Margin = New-Object System.Windows.Thickness($leftMargin, 0, 0, 5)
                    }
                    # Regular paragraph that might contain formatting
                    else {
                        Parse-MarkdownText -text $line -paragraph $paragraph
                        $paragraph.Margin = New-Object System.Windows.Thickness(0, 0, 0, 5)
                    }
                    
                    $flowDoc.Blocks.Add($paragraph)
                }
                else {
                    # Empty line - add spacing
                    $paragraph = New-Object System.Windows.Documents.Paragraph
                    $paragraph.Margin = New-Object System.Windows.Thickness(0, 5, 0, 5)
                    $flowDoc.Blocks.Add($paragraph)
                }
            }
            
            # Set the FlowDocument to the RichTextBox
            $contentBlock.Document = $flowDoc
            Write-Log "Successfully loaded changelog content"
        }
        catch {
            Write-Log "Error fetching changelog: $_"
            
            # Create error message in FlowDocument
            $flowDoc = New-Object System.Windows.Documents.FlowDocument
            $paragraph = New-Object System.Windows.Documents.Paragraph
            $run = New-Object System.Windows.Documents.Run("Error loading changelog. Please check your internet connection and try again.")
            $run.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(220, 38, 38))
            $paragraph.Inlines.Add($run)
            $flowDoc.Blocks.Add($paragraph)
            $contentBlock.Document = $flowDoc
        }
        
        # Show dialog
        try {
            if ($null -eq $changelogWindow) {
                throw "Changelog window is null. Cannot show dialog."
            }
            $changelogWindow.ShowDialog()
        }
        catch {
            Write-Log "Error showing changelog dialog: $_"
            [System.Windows.MessageBox]::Show(
                "Failed to show the changelog dialog. Error: $_",
                "Dialog Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
        }
    }
    catch {
        Write-Log "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error showing changelog dialog: $_"
        [System.Windows.MessageBox]::Show(
            "Error showing changelog dialog: $_",
            "Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

function Show-SettingsDialog {
    # Create window
    $settingsWindow = New-Object System.Windows.Window
    $settingsWindow.Title = "Settings"
    $settingsWindow.Width = 380
    $settingsWindow.Height = 320
    $settingsWindow.WindowStartupLocation = 'CenterOwner'
    $settingsWindow.ResizeMode = 'NoResize'
    if ($Window) { $settingsWindow.Owner = $Window }

    # Main grid
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = '20'
    $settingsWindow.Content = $grid

    # Row definitions
    $row1 = New-Object System.Windows.Controls.RowDefinition
    $row1.Height = "Auto"
    $row2 = New-Object System.Windows.Controls.RowDefinition
    $row2.Height = "Auto"
    $row3 = New-Object System.Windows.Controls.RowDefinition
    $row3.Height = "*"
    $grid.RowDefinitions.Add($row1)
    $grid.RowDefinitions.Add($row2)
    $grid.RowDefinitions.Add($row3)

    # Title
    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Authentication Settings"
    $title.FontSize = 18
    $title.FontWeight = 'Bold'
    $title.Margin = '0,0,0,10'
    [System.Windows.Controls.Grid]::SetRow($title, 0)
    $grid.Children.Add($title)

    # Description
    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = "Enable or disable automatic authentication"
    $desc.FontSize = 13
    $desc.Foreground = "#555"
    $desc.Margin = '0,0,0,18'
    [System.Windows.Controls.Grid]::SetRow($desc, 1)
    $grid.Children.Add($desc)

    # Auto Auth toggle panel
    $autoAuthPanel = New-Object System.Windows.Controls.StackPanel
    $autoAuthPanel.Orientation = 'Horizontal'
    $autoAuthPanel.Margin = '0,0,0,0'
    [System.Windows.Controls.Grid]::SetRow($autoAuthPanel, 2)
    $grid.Children.Add($autoAuthPanel)

    # Auto Auth checkbox
    $autoAuthCheck = New-Object System.Windows.Controls.CheckBox
    $autoAuthCheck.Content = "Enable Auto Authentication"
    $autoAuthCheck.FontSize = 14
    $autoAuthCheck.VerticalAlignment = 'Top'
    $autoAuthCheck.Margin = '0,0,0,10'
    $autoAuthPanel.Children.Add($autoAuthCheck)

    # Ensure SCCM checkbox is below Auto Auth checkbox
    $autoAuthPanel.Orientation = 'Vertical'
    $sccmCheck = New-Object System.Windows.Controls.CheckBox
    $sccmCheck.Content = "Enable SCCM Management"
    $sccmCheck.FontSize = 14
    $sccmCheck.VerticalAlignment = 'Top'
    $sccmCheck.Margin = '0,0,0,10'
    $autoAuthPanel.Children.Add($sccmCheck)

    # Load current SCCM setting
    if (Test-Path $settingsPath) {
        try {
            $settings = Get-Content $settingsPath | ConvertFrom-Json
            $sccmCheck.IsChecked = $settings.QuerySCCM
        } catch {
            Write-Log -message "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error loading SCCM setting from $($settingsPath): $_"
        }
    }

    # Handler for SCCM checkbox
    $sccmCheck.Add_Checked({
        Write-Log -message "Enabling SCCM Management"
        if (Test-Path $settingsPath) {
            try {
                $settings = Get-Content $settingsPath | ConvertFrom-Json
                $settings.QuerySCCM = $true
                $settings | ConvertTo-Json | Set-Content -Path $settingsPath
                $QuerySCCM = $true
            } catch {
                Write-Log -message "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error updating settings when enabling SCCM: $_"
            }
        }
        [System.Windows.MessageBox]::Show("SCCM Management enabled.", "Settings", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    $sccmCheck.Add_Unchecked({
        Write-Log -message "Disabling SCCM Management"
        if (Test-Path $settingsPath) {
            try {
                $settings = Get-Content $settingsPath | ConvertFrom-Json
                $settings.QuerySCCM = $false
                $settings | ConvertTo-Json | Set-Content -Path $settingsPath
                $QuerySCCM = $false
            } catch {
                Write-Log -message "|| Line: $($_.InvocationInfo.ScriptLineNumber) || Error updating settings when disabling SCCM: $_"
            }
        }
        [System.Windows.MessageBox]::Show("SCCM Management disabled.", "Settings", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    # Load current setting
    if (Test-Path $settingsPath) {
        try {
            Write-Log -message "Loading settings from $settingsPath"
            $settings = Get-Content $settingsPath | ConvertFrom-Json
            $rememberCertAuth = $settings.RememberCertAuthentication
            $rememberSecretAuth = $settings.RememberSecretAuthentication

            If ($rememberCertAuth -or $rememberSecretAuth) {
                Write-Log -message "Auto authentication is enabled"
                $autoAuthCheck.IsChecked = $true
            }
            else {
                Write-Log -message "Auto authentication is disabled"
                $autoAuthCheck.IsChecked = $false
            }
        } catch {
            Write-Log -message "Error loading settings from $($settingsPath): $_"
        }
    }
    
    # Handler for the auto authentication checkbox
    $autoAuthCheck.Add_Checked({
        Write-Log -message "Enabling auto authentication"
        if (Test-Path $settingsPath) {
            try {
                $settings = Get-Content $settingsPath | ConvertFrom-Json
                $settings.RememberCertAuthentication = $true
                $settings.RememberSecretAuthentication = $true
                $settings | ConvertTo-Json | Set-Content -Path $settingsPath
            } catch {
                Write-Log -message "Error updating settings when attempting to enable auto authentication from $($settingsPath): $_"
            }
        }
        # Prompt for credentials if not present
        $secretFilePath = [System.IO.Path]::Combine($env:LOCALAPPDATA, "DeviceOffBoardingManager", "IntuneOffboardingTool_Secret.json")
        if (-not (Test-Path $secretFilePath)) {
            Write-Log -message "Showing authentication dialog - $secretFilePath not found"
            Show-AuthenticationDialog | Out-Null
        }
        [System.Windows.MessageBox]::Show("Auto Authentication enabled.", "Settings", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    $autoAuthCheck.Add_Unchecked({
        Write-Log -message "Disabling auto authentication"
        if (Test-Path $settingsPath) {
            try {
                $settings = Get-Content $settingsPath | ConvertFrom-Json
                $settings.RememberCertAuthentication = $false
                $settings.RememberSecretAuthentication = $false
                $settings | ConvertTo-Json | Set-Content -Path $settingsPath
            } catch {
                Write-Log -message "Error updating settings when attempting to disable auto authentication from $($settingsPath): $_"
            }
        }
        [System.Windows.MessageBox]::Show("Auto Authentication disabled.", "Settings", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    # Add "Delete Saved Authentication" button
    $deleteAuthButton = New-Object System.Windows.Controls.Button
    $deleteAuthButton.Content = "Delete Saved Authentication"
    $deleteAuthButton.Width = 180
    $deleteAuthButton.Height = 30
    $deleteAuthButton.HorizontalAlignment = 'Right'
    $deleteAuthButton.Margin = '0,10,0,0'

    # Add to the grid as a new row
    $row4 = New-Object System.Windows.Controls.RowDefinition
    $row4.Height = "Auto"
    $grid.RowDefinitions.Add($row4)
    [System.Windows.Controls.Grid]::SetRow($deleteAuthButton, 3)
    $grid.Children.Add($deleteAuthButton)

    $deleteAuthButton.Add_Click({
        Write-Log -message "Deleting saved authentication files"
        $secretFile = [System.IO.Path]::Combine($env:LOCALAPPDATA, "DeviceOffBoardingManager", "IntuneOffboardingTool_Secret.json")
        $certFile = [System.IO.Path]::Combine($env:LOCALAPPDATA, "DeviceOffBoardingManager", "IntuneOffboardingTool_Secret.crt")
        $deleted = $false
        if (Test-Path $secretFile) {
            Remove-Item $secretFile -Force
            Write-Log -message "Deleted saved authentication file: $secretFile"
            $deleted = $true
        }
        if (Test-Path $certFile) {
            Remove-Item $certFile -Force
            Write-Log -message "Deleted saved authentication file: $certFile"
            $deleted = $true
        }
        if ($deleted) {
            Write-Log -message "Updating settings after deleting authentication files"
            $settings = Get-Content $settingsPath | ConvertFrom-Json
            $settings.RememberCertAuthentication = $false
            $settings.RememberSecretAuthentication = $false
            $settings | ConvertTo-Json | Set-Content -Path $settingsPath

            [System.Windows.MessageBox]::Show("Saved authentication files deleted.", "Delete Saved Authentication", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        } else {
            [System.Windows.MessageBox]::Show("No saved authentication files found.", "Delete Saved Authentication", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        }
    })

    # Disable the button if neither file exists
    $secretFile = [System.IO.Path]::Combine($env:LOCALAPPDATA, "DeviceOffBoardingManager", "IntuneOffboardingTool_Secret.json")
    $certFile = [System.IO.Path]::Combine($env:LOCALAPPDATA, "DeviceOffBoardingManager", "IntuneOffboardingTool_Secret.crt")
    if (-not (Test-Path $secretFile) -and -not (Test-Path $certFile)) {
        Write-Log -message "No saved authentication files found, disabling delete button"
        $deleteAuthButton.IsEnabled = $false
    } else {
        Write-Log -message "Saved authentication files found, enabling delete button"
        $deleteAuthButton.IsEnabled = $true
    }

    # Disable the checkbox and update settings if neither file exists
    if (-not (Test-Path $secretFile) -and -not (Test-Path $certFile)) {
        Write-Log -message "No saved authentication files found, disabling auto authentication"
        $deleteAuthButton.IsEnabled = $false
        $autoAuthCheck.IsChecked = $false
        if (Test-Path $settingsPath) {
            try {
                Write-Log -message "Updating settings after disabling auto authentication"
                $settings = Get-Content $settingsPath | ConvertFrom-Json
                $settings.RememberCertAuthentication = $false
                $settings.RememberSecretAuthentication = $false
                $settings | ConvertTo-Json | Set-Content -Path $settingsPath
            } catch {
                Write-Log -message "Error updating settings when attempting to disable auto authentication from $($settingsPath): $_"
            }
        }
    } else {
        $deleteAuthButton.IsEnabled = $true
    }

    $settingsWindow.ShowDialog()
}

# Connect back button
$BackToPlaybooksButton = $Window.FindName('BackToPlaybooksButton')
$BackToPlaybooksButton.Add_Click({
        $Window.FindName('PlaybooksScrollViewer').Visibility = 'Visible'
        $PlaybookResultsGrid.Visibility = 'Collapsed'
        $PlaybookResultsDataGrid.ItemsSource = $null
    })

# Connect export playbook results button
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
            [System.Windows.MessageBox]::Show(
                "No results to export.",
                "Export",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )
        }
    })

# Connect dashboard card click handlers
$StaleDevices30Card = $Window.FindName('StaleDevices30Card')
$StaleDevices30Card.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            try {
                Write-Log "Fetching 30-day stale devices..."
                $thirtyDaysAgo = (Get-Date).AddDays(-30)
                $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=lastSyncDateTime lt $($thirtyDaysAgo.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
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
                [System.Windows.MessageBox]::Show("Error fetching stale devices. Check logs for details.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            }
        }
    })

$StaleDevices90Card = $Window.FindName('StaleDevices90Card')
$StaleDevices90Card.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            try {
                Write-Log "Fetching 90-day stale devices..."
                $ninetyDaysAgo = (Get-Date).AddDays(-90)
                $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=lastSyncDateTime lt $($ninetyDaysAgo.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
                $staleDevices = Get-GraphPagedResults -Uri $uri
                
                
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
                [System.Windows.MessageBox]::Show("Error fetching stale devices. Check logs for details.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            }
        }
    })

$StaleDevices180Card = $Window.FindName('StaleDevices180Card')
$StaleDevices180Card.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            try {
                Write-Log "Fetching 180-day stale devices..."
                $hundredEightyDaysAgo = (Get-Date).AddDays(-180)
                $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=lastSyncDateTime lt $($hundredEightyDaysAgo.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
                $staleDevices = Get-GraphPagedResults -Uri $uri
                
                
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
                [System.Windows.MessageBox]::Show("Error fetching stale devices. Check logs for details.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            }
        }
    })

$PersonalDevicesCard = $Window.FindName('PersonalDevicesCard')
$PersonalDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            try {
                Write-Log "Fetching personal devices..."
                $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=managedDeviceOwnerType eq 'personal'"
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
                [System.Windows.MessageBox]::Show("Error fetching personal devices. Check logs for details.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            }
        }
    })

$CorporateDevicesCard = $Window.FindName('CorporateDevicesCard')
$CorporateDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            try {
                Write-Log "Fetching corporate devices..."
                $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=managedDeviceOwnerType eq 'company'"
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
                [System.Windows.MessageBox]::Show("Error fetching corporate devices. Check logs for details.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            }
        }
    })

# Connect total device count card click handlers
$IntuneDevicesCard = $Window.FindName('IntuneDevicesCard')
$IntuneDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            try {
                Write-Log "Fetching all Intune devices..."
                $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
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
                [System.Windows.MessageBox]::Show("Error fetching Intune devices. Check logs for details.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            }
        }
    })

$AutopilotDevicesCard = $Window.FindName('AutopilotDevicesCard')
$AutopilotDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            try {
                Write-Log "Fetching all Autopilot devices..."
                $uri = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities"
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
                [System.Windows.MessageBox]::Show("Error fetching Autopilot devices. Check logs for details.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            }
        }
    })

$EntraIDDevicesCard = $Window.FindName('EntraIDDevicesCard')
$EntraIDDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            try {
                Write-Log "Fetching all Entra ID devices..."
                $uri = "https://graph.microsoft.com/v1.0/devices"
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
                write-host "line 6817"
                Show-DashboardCardResults -Title $title -DeviceList $deviceList
            }
            catch {
                Write-Log "Error fetching Entra ID devices: $_"
                [System.Windows.MessageBox]::Show("Error fetching Entra ID devices. Check logs for details.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            }
        }
    })

$SCCMDevicesCard = $Window.FindName('SCCMDevicesCard')
$SCCMDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            try {
                Write-Log "Fetching all SCCM devices..."
                $originaldrive = Get-Location
                ConnectSCCM
                $SCCMDevices = get-cmdevice -CollectionID 'SMSDM003' -fast | Where-Object { $_.IsClient -eq $true -and $_.IsActive -eq $true }
                write-host ($SCCMDevices).count "SCCM Devices"
                set-location $originaldrive
                
                $deviceList = @()
                foreach ($device in $SCCMDevices) {
                    $deviceList += [PSCustomObject]@{
                        DeviceName      = $device.Name
                        SerialNumber    = $device.SerialNumber
                        LastContact     = if ($device.LastActiveTime) {
                            $date = ConvertTo-SafeDateTime -dateString $device.LastActiveTime
                            if ($date) { $date.ToString('yyyy-MM-dd HH:mm') } else { "Never" }
                        }
                        else { "Never" }
                        OperatingSystem = if ($device.DeviceOS) { $device.DeviceOS.Replace(" NT Workstation", "") } else { "Unknown" }
                        OSVersion       = $device.DeviceOSBuild
                        PrimaryUser     = $device.PrimaryUser
                        Ownership       = $tenantName
                    }
                }
                
                $title = "All SCCM Workstations"
                write-host "line 6856"
                Show-DashboardCardResults -Title $title -DeviceList $deviceList
            }
            catch {
                Write-Log "Error fetching SCCM devices: $_"
                [System.Windows.MessageBox]::Show("Error fetching SCCM devices. Check logs for details.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            }
        }
    })

# Connect changelog button
$changelog_button = $Window.FindName('changelog_button')
$changelog_button.Add_Click({
        Show-ChangelogDialog
    })

$settings_button = $Window.FindName('settings_button')
$settings_button.Add_Click({
    Write-log -Message "Opening settings dialog"
    Show-SettingsDialog
})

# Show Window
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
    exit 1
}
