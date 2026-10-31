<#PSScriptInfo

.VERSION 0.3.2

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
Param(
    [switch]$Verbose
)

$script:VerboseMode = $Verbose.IsPresent

#Requires -Version 7.0
# Graph authentication and requests use the MgGraphCommunity module (WAM-free interactive
# sign-in). It is checked and auto-installed at startup rather than via #Requires so first
# run needs no manual steps.

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

# Ensure the MgGraphCommunity module is available and loaded. It replaces
# Microsoft.Graph.Authentication for sign-in and requests: interactive login uses the
# classic browser flow instead of the WAM broker, which blocks secondary/service
# accounts, and tokens refresh automatically during long sessions.
if (-not (Get-Module -ListAvailable -Name "MgGraphCommunity")) {
    Write-Host "The required MgGraphCommunity module is not installed. Installing from the PowerShell Gallery..." -ForegroundColor Cyan
    try {
        Install-Module MgGraphCommunity -Scope CurrentUser -Force -ErrorAction Stop
        Write-Host "MgGraphCommunity module installed." -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to install the MgGraphCommunity module: $_" -ForegroundColor Red
        Write-Host "Install it manually with: Install-Module MgGraphCommunity -Scope CurrentUser" -ForegroundColor Red
        exit 1
    }
}
try {
    Import-Module MgGraphCommunity -ErrorAction Stop
}
catch {
    Write-Host "Failed to load the MgGraphCommunity module: $_" -ForegroundColor Red
    exit 1
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
        Write-Log "Error getting installed version: $_"
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
        Write-Log "Error getting latest version: $_"
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
            }
        }
        else {
            $updateStatus.Text = "Version check unavailable"
            $updateStatus.Foreground = "#A0A0A0"
            $updateStatus.Cursor = "Arrow"
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

        // Graph IDs captured at search time for safe ID-based offboarding
        public string EntraDeviceId { get; set; }         // Entra object id for DELETE /devices/{id}
        public string EntraDeviceObjectId { get; set; }    // deviceId property (for BitLocker lookup)
        public string IntuneDeviceId { get; set; }         // Intune managed device id
        public string AutopilotIdentityId { get; set; }    // Autopilot identity id
        public string EntraAccountEnabled { get; set; }    // "True"/"False"/null for disable feature
        public string ComplianceState { get; set; }         // Intune compliance state
        public string MdeDeviceId { get; set; }             // Defender for Endpoint machine id
        public string ManagementAgent { get; set; }          // mdm, configurationManagerClientMdm, etc.

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
        [string]$Uri,
        [hashtable]$Headers = @{}
    )

    $results = @()
    $nextLink = $Uri

    do {
        try {
            $response = Invoke-GraphRequestWithRetry -Uri $nextLink -Method GET -Headers $Headers
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

# Retry wrapper for Graph API calls -- handles HTTP 429 (throttling) and transient 5xx errors
function Invoke-GraphRequestWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [string]$Method = "GET",
        [string]$Body,
        [string]$ContentType = "application/json",
        [hashtable]$Headers = @{},
        [int]$MaxRetries = 3,
        [int]$BaseDelaySeconds = 2
    )

    $attempt = 0
    while ($true) {
        try {
            $params = @{
                Uri        = $Uri
                Method     = $Method
                OutputType = 'Hashtable'
            }
            if ($Headers.Count -gt 0) { $params.Headers = $Headers }
            if ($Body) {
                $params.Body = $Body
                $params.ContentType = $ContentType
            }
            return Invoke-MgGraphCommunityRequest @params
        }
        catch {
            $attempt++
            # MgGraphCommunity surfaces Graph failures in the message text, e.g.
            # "Graph error 403 [Authorization_RequestDenied]: ..." or "HTTP 500 from <uri>"
            $statusCode = $null
            if ($_.Exception.Message -match '(?:Graph error|HTTP)\s+(\d{3})\b') {
                $statusCode = [int]$Matches[1]
            }

            # Throttled (429)
            if ($statusCode -eq 429) {
                if ($attempt -gt $MaxRetries) { throw }
                # Retry-After is honored inside Invoke-MgGraphCommunityRequest itself;
                # this outer retry handles sustained throttling with a plain delay.
                $retryAfter = $BaseDelaySeconds
                Write-Log "Throttled (429) on $Method $Uri -- retrying in ${retryAfter}s (attempt $attempt/$MaxRetries)" -Severity "WARN"
                Start-Sleep -Seconds $retryAfter
                continue
            }

            # Transient server errors (500-599) or network-level failures (null status)
            if ($null -eq $statusCode -or ($statusCode -ge 500 -and $statusCode -lt 600)) {
                if ($attempt -gt $MaxRetries) { throw }
                $delay = $BaseDelaySeconds * [Math]::Pow(2, $attempt - 1)
                Write-Log "Server error ($statusCode) on $Method $Uri -- retrying in ${delay}s (attempt $attempt/$MaxRetries)" -Severity "WARN"
                Start-Sleep -Seconds $delay
                continue
            }

            # Non-retryable error
            throw
        }
    }
}

# Batch helper -- sends up to 20 sub-requests per POST /$batch, auto-chunks larger sets
function Invoke-GraphBatchRequest {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Requests
    )

    $allResponses = @()
    $chunkSize = 20

    for ($i = 0; $i -lt $Requests.Count; $i += $chunkSize) {
        $end = [Math]::Min($i + $chunkSize, $Requests.Count) - 1
        $chunk = $Requests[$i..$end]

        $batchBody = @{ requests = $chunk } | ConvertTo-Json -Depth 10
        $batchResponse = Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/`$batch" -Method POST -Body $batchBody -ContentType "application/json"

        if ($batchResponse.responses) {
            # Retry individual sub-requests that returned 429 or 5xx
            $retryable = $batchResponse.responses | Where-Object { $_.status -eq 429 -or ($_.status -ge 500 -and $_.status -lt 600) }
            $successful = $batchResponse.responses | Where-Object { $_.status -lt 429 -or ($_.status -gt 429 -and $_.status -lt 500) -or $_.status -ge 600 }
            $allResponses += $successful

            $retryAttempt = 0
            while ($retryable -and $retryAttempt -lt 3) {
                $retryAttempt++
                $delay = 2 * [Math]::Pow(2, $retryAttempt - 1)
                Write-Log "Batch: retrying $($retryable.Count) sub-requests (attempt $retryAttempt/3)" -Severity "WARN"
                Start-Sleep -Seconds $delay

                $retryRequests = foreach ($resp in $retryable) {
                    $chunk | Where-Object { $_.id -eq $resp.id }
                }
                $retryBody = @{ requests = @($retryRequests) } | ConvertTo-Json -Depth 10
                $retryResponse = Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/`$batch" -Method POST -Body $retryBody -ContentType "application/json"

                if ($retryResponse.responses) {
                    $retryable = $retryResponse.responses | Where-Object { $_.status -eq 429 -or ($_.status -ge 500 -and $_.status -lt 600) }
                    $newSuccessful = $retryResponse.responses | Where-Object { $_.status -lt 429 -or ($_.status -gt 429 -and $_.status -lt 500) -or $_.status -ge 600 }
                    $allResponses += $newSuccessful
                } else {
                    break
                }
            }
            # If still retryable after max attempts, add them as-is
            if ($retryable) {
                $allResponses += $retryable
            }
        }
    }

    return $allResponses
}

# Maps a 403 Forbidden response during offboarding to an actionable message.
# Root cause is almost always a missing directory/Intune role rather than a
# missing Graph permission scope (Issues #52, #53).
function Get-Graph403Message {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('EntraID', 'Intune', 'Autopilot')]
        [string]$Service
    )

    switch ($Service) {
        'EntraID' {
            "Access denied (403). Deleting Entra ID devices requires the Cloud Device Administrator or Intune Administrator directory role in addition to the Device.ReadWrite.All permission. See the 'Required Roles' section in the README."
        }
        'Intune' {
            "Access denied (403). Deleting Intune devices requires the Intune Administrator role (or an Intune RBAC role with 'Managed devices - Delete') in addition to the DeviceManagementManagedDevices.ReadWrite.All permission. See the 'Required Roles' section in the README."
        }
        'Autopilot' {
            "Access denied (403). Deleting Autopilot identities requires the Intune Administrator role in addition to the DeviceManagementServiceConfig.ReadWrite.All permission. See the 'Required Roles' section in the README."
        }
    }
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
        Write-Log "Failed to parse date: $dateString"
        return $null
    }
}

# Define WPF XAML
[xml]$xaml = @"
<Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Device Offboarding Manager (Preview)" Height="700" Width="1200" 
    Background="#F0F0F0"
    WindowStartupLocation="CenterScreen" 
    ResizeMode="CanResize"
    MinHeight="600" MinWidth="900">
    
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
                                CornerRadius="6"
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
            <Setter Property="Cursor" Value="Hand"/>
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
                                CornerRadius="6"
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
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#243447"/>
                            </Trigger>
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
            <ColumnDefinition x:Name="SidebarColumn" Width="200"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Sidebar -->
        <Border Grid.Column="0" Background="#2D2D2D">
            <DockPanel>
                <!-- Sidebar Toggle Button -->
                <Button x:Name="SidebarToggleButton" DockPanel.Dock="Top"
                        Content="&lt;&lt;" Background="#404040" Foreground="White"
                        FontSize="14" FontWeight="Bold" Height="32"
                        HorizontalAlignment="Right" Width="36"
                        Margin="5,8,10,0" ToolTip="Collapse sidebar (Ctrl+B)"/>
                <!-- Collapsed-mode connection status dot -->
                <Ellipse x:Name="CollapsedStatusDot" DockPanel.Dock="Top"
                         Width="12" Height="12" Fill="#FC8181"
                         HorizontalAlignment="Center" Margin="0,10,0,0"
                         Visibility="Collapsed" ToolTip="Disconnected"/>
                <!-- Top: Connect Button + Tenant Info -->
                <StackPanel x:Name="SidebarTopContent" DockPanel.Dock="Top" Margin="0,10,0,0">
                    <!-- Connect Button with Status Dot -->
                    <Border Margin="15,5,15,10"
                            Background="#0078D4"
                            CornerRadius="6">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <Button x:Name="AuthenticateButton"
                                    Content="Connect to MS Graph"
                                    Style="{StaticResource SidebarButtonStyle}"
                                    Background="Transparent"
                                    Foreground="White"
                                    Height="40"
                                    Margin="0"
                                    Grid.ColumnSpan="2"/>
                            <Ellipse x:Name="ConnectionStatusDot"
                                     Width="10" Height="10"
                                     Fill="#FC8181"
                                     Grid.Column="1"
                                     Margin="0,0,12,0"
                                     VerticalAlignment="Center"
                                     IsHitTestVisible="False"
                                     ToolTip="Disconnected"/>
                        </Grid>
                    </Border>

                    <!-- Tenant Info Section -->
                    <Border x:Name="TenantInfoSection"
                            Margin="15,0,15,10"
                            Background="#404040"
                            CornerRadius="6"
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
                </StackPanel>

                <!-- Bottom: Utility Buttons -->
                <StackPanel x:Name="SidebarBottomContent" DockPanel.Dock="Bottom" Margin="0,0,0,0">
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
                            ToolTip="Check required permissions and modules"
                            Margin="15,5"/>
                    <Button x:Name="logs_button"
                            Content="Logs"
                            Style="{StaticResource SidebarButtonStyle}"
                            ToolTip="Open log files directory"
                            Margin="15,5"/>
                    <Button x:Name="disconnect_button"
                            Content="Disconnect"
                            Style="{StaticResource SidebarButtonStyle}"
                            ToolTip="Disconnect from Microsoft Graph"
                            IsEnabled="False"
                            Margin="15,5"/>

                    <Button x:Name="changelog_button"
                            Content="Changelog"
                            Style="{StaticResource SidebarButtonStyle}"
                            ToolTip="View version history and release notes"
                            Margin="15,5,15,15"/>
                </StackPanel>

                <!-- Center: Navigation Menu -->
                <StackPanel x:Name="SidebarCenterContent" Margin="0,10,0,0">
                    <RadioButton x:Name="MenuHome"
                                Content="Home"
                                Style="{StaticResource MenuButtonStyle}"
                                ToolTip="Overview and getting started"
                                IsChecked="True"/>
                    <RadioButton x:Name="MenuDashboard"
                                Content="Dashboard"
                                Style="{StaticResource MenuButtonStyle}"
                                ToolTip="Device statistics and analytics"
                                IsEnabled="False"/>
                    <RadioButton x:Name="MenuDeviceManagement"
                                Content="Device Offboarding"
                                Style="{StaticResource MenuButtonStyle}"
                                ToolTip="Search and offboard devices"
                                IsEnabled="False"/>
                    <RadioButton x:Name="MenuPlaybooks"
                                Content="Playbooks"
                                Style="{StaticResource MenuButtonStyle}"
                                ToolTip="Automated reports and tasks"
                                IsEnabled="False"/>

                    <!-- Feedback Section -->
                    <Border Margin="15,15,15,5"
                            Background="#1A365D"
                            CornerRadius="6">
                        <StackPanel Margin="12,8">
                            <TextBlock Text="Have feedback or found a bug?"
                                     Foreground="#60A5FA"
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
        <Grid Grid.Column="1">
            <!-- Toast Notification Overlay -->
            <Border x:Name="ToastNotification" VerticalAlignment="Top" HorizontalAlignment="Stretch"
                    Margin="20,0,20,0" Panel.ZIndex="1000" Visibility="Collapsed" CornerRadius="0,0,6,6">
                <Border.Effect>
                    <DropShadowEffect ShadowDepth="2" Direction="270" Color="#000000" Opacity="0.3" BlurRadius="8"/>
                </Border.Effect>
                <Grid Margin="16,10">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock x:Name="ToastMessage" Foreground="White" FontSize="13"
                             VerticalAlignment="Center" TextWrapping="Wrap"/>
                    <Button x:Name="ToastDismissButton" Grid.Column="1" Content="X"
                            Background="Transparent" Foreground="White" FontSize="12"
                            Width="24" Height="24" Padding="0" Margin="8,0,0,0" ToolTip="Dismiss"/>
                </Grid>
            </Border>
            <Grid x:Name="MainContent" Margin="20">
            <!-- Home Page -->
            <Grid x:Name="HomePage" Visibility="Visible">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <!-- Header -->
                <StackPanel Grid.Row="0" Margin="0,0,0,20">
                    <TextBlock Text="Device Offboarding Manager"
                              FontSize="32"
                              FontWeight="Bold"
                              Margin="0,0,0,10"/>
                    <TextBlock Text="Remove devices from Intune, Autopilot, Entra ID, and Defender for Endpoint in a single workflow"
                              FontSize="16"
                              Opacity="0.7"
                              TextWrapping="Wrap"/>

                    <!-- Slim Preview Info Bar -->
                    <Border Background="#92400E"
                            CornerRadius="6"
                            Margin="0,15,0,0"
                            Padding="12,8">
                        <StackPanel Orientation="Horizontal">
                            <Path Data="M13,13H11V7H13M13,17H11V15H13M12,2A10,10 0 0,0 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12A10,10 0 0,0 12,2Z"
                                  Fill="#FDE68A"
                                  Width="16"
                                  Height="16"
                                  Stretch="Uniform"
                                  Margin="0,0,8,0"/>
                            <TextBlock Text="PREVIEW - Offboarding operations may be permanent and cannot be undone. Test in a non-production environment first."
                                     Foreground="#FDE68A"
                                     FontSize="12"
                                     VerticalAlignment="Center"/>
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

                    <!-- Get Started -->
                    <Border Grid.Column="0" Grid.Row="0"
                            Background="#1B2A47"
                            CornerRadius="8"
                            Margin="0,0,10,10">
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <TextBlock x:Name="HomeGetStartedTitle"
                                     Text="Get Started"
                                     FontSize="20"
                                     FontWeight="SemiBold"
                                     Foreground="White"
                                     Margin="0,0,0,10"/>
                            <TextBlock x:Name="HomeGetStartedDesc" Grid.Row="1"
                                     Text="Sign in with Microsoft Graph to search, audit, and offboard devices across all connected services."
                                     FontSize="13"
                                     Foreground="#A0AEC0"
                                     TextWrapping="Wrap"
                                     Margin="0,0,0,15"/>
                            <Button x:Name="HomeConnectButton"
                                    Grid.Row="2"
                                    Content="Connect to Microsoft Graph"
                                    Height="36"
                                    Padding="16,0"
                                    Background="#0078D4"
                                    Foreground="White"
                                    BorderThickness="0"
                                    HorizontalAlignment="Left"
                                    VerticalAlignment="Top"
                                    Cursor="Hand"
                                    ToolTip="Open authentication dialog"/>
                        </Grid>
                    </Border>

                    <!-- Key Features -->
                    <Border Grid.Column="1" Grid.Row="0"
                            Background="#1B2A47"
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
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                    <Ellipse Width="6" Height="6" Fill="#63B3ED" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                    <TextBlock Text="Single and bulk device offboarding"
                                             FontSize="14" Foreground="#A0AEC0"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                    <Ellipse Width="6" Height="6" Fill="#63B3ED" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                    <TextBlock Text="CSV import for batch operations"
                                             FontSize="14" Foreground="#A0AEC0"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                    <Ellipse Width="6" Height="6" Fill="#63B3ED" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                    <TextBlock Text="Stale device and compliance reporting"
                                             FontSize="14" Foreground="#A0AEC0"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                    <Ellipse Width="6" Height="6" Fill="#63B3ED" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                    <TextBlock Text="Encryption key backup before removal"
                                             FontSize="14" Foreground="#A0AEC0"/>
                                </StackPanel>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Supported Services -->
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

                                <StackPanel Grid.Column="0">
                                    <StackPanel Orientation="Horizontal" Margin="0,0,10,10">
                                        <Ellipse Width="6" Height="6" Fill="#48BB78" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                        <TextBlock Text="Microsoft Intune" FontSize="14" Foreground="#A0AEC0"/>
                                    </StackPanel>
                                    <StackPanel Orientation="Horizontal" Margin="0,0,10,10">
                                        <Ellipse Width="6" Height="6" Fill="#48BB78" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                        <TextBlock Text="Windows Autopilot" FontSize="14" Foreground="#A0AEC0"/>
                                    </StackPanel>
                                </StackPanel>

                                <StackPanel Grid.Column="1">
                                    <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                        <Ellipse Width="6" Height="6" Fill="#48BB78" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                        <TextBlock Text="Microsoft Entra ID" FontSize="14" Foreground="#A0AEC0"/>
                                    </StackPanel>
                                    <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                        <Ellipse Width="6" Height="6" Fill="#48BB78" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                        <TextBlock Text="Defender for Endpoint" FontSize="14" Foreground="#A0AEC0"/>
                                    </StackPanel>
                                </StackPanel>
                            </Grid>
                        </Grid>
                    </Border>

                    <!-- Quick Navigation -->
                    <Border Grid.Column="1" Grid.Row="1"
                            Background="#2D3748"
                            CornerRadius="8"
                            Margin="10,10,0,0">
                        <Grid Margin="20">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="Quick Navigation"
                                     FontSize="20"
                                     FontWeight="SemiBold"
                                     Foreground="White"
                                     Margin="0,0,0,15"/>
                            <StackPanel Grid.Row="1" VerticalAlignment="Top">
                                <Button x:Name="HomeNavDashboard"
                                        Content="Dashboard"
                                        Height="32"
                                        Padding="12,0"
                                        Background="#404040"
                                        Foreground="White"
                                        BorderThickness="0"
                                        Margin="0,0,0,8"
                                        HorizontalAlignment="Stretch"
                                        IsEnabled="False"
                                        Cursor="Hand"
                                        ToolTip="View device statistics and analytics (connect first)"/>
                                <Button x:Name="HomeNavDeviceMgmt"
                                        Content="Device Offboarding (Ctrl+K)"
                                        Height="32"
                                        Padding="12,0"
                                        Background="#404040"
                                        Foreground="White"
                                        BorderThickness="0"
                                        Margin="0,0,0,8"
                                        HorizontalAlignment="Stretch"
                                        IsEnabled="False"
                                        Cursor="Hand"
                                        ToolTip="Search and offboard devices (connect first)"/>
                                <Button x:Name="HomeNavPlaybooks"
                                        Content="Playbooks"
                                        Height="32"
                                        Padding="12,0"
                                        Background="#404040"
                                        Foreground="White"
                                        BorderThickness="0"
                                        Margin="0,0,0,8"
                                        HorizontalAlignment="Stretch"
                                        IsEnabled="False"
                                        Cursor="Hand"
                                        ToolTip="Run automated reports and tasks (connect first)"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                </Grid>
            </Grid>

            <!-- Dashboard Page -->
            <Grid x:Name="DashboardPage">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Page Header -->
                <Grid Grid.Row="0" Margin="20,10,20,4">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel>
                        <TextBlock Text="Dashboard"
                                 FontSize="28"
                                 FontWeight="Bold"
                                 Foreground="#323130"
                                 Margin="0,0,0,4"/>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Device inventory and health at a glance"
                                     FontSize="14"
                                     Opacity="0.7"/>
                            <TextBlock x:Name="DashboardLastRefreshed"
                                     Text=""
                                     FontSize="12"
                                     Foreground="#A0AEC0"
                                     VerticalAlignment="Center"
                                     Margin="16,0,0,0"/>
                        </StackPanel>
                    </StackPanel>
                    <Button x:Name="DashboardRefreshButton"
                            Grid.Column="2"
                            Content="Refresh"
                            Height="32"
                            Padding="16,0"
                            Background="#0078D4"
                            Foreground="White"
                            BorderThickness="0"
                            VerticalAlignment="Top"
                            Cursor="Hand"
                            ToolTip="Refresh dashboard statistics (F5)"/>
                </Grid>

                <!-- Platform Filter -->
                <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="20,10,20,4" VerticalAlignment="Center">
                    <TextBlock Text="Platform:" Foreground="#A0AEC0" FontSize="13" VerticalAlignment="Center" Margin="0,0,8,0"/>
                    <ComboBox x:Name="DashboardPlatformFilter" Width="160" SelectedIndex="0"
                              ToolTip="Filter Intune device counts by operating system platform">
                        <ComboBoxItem Content="All Platforms"/>
                        <ComboBoxItem Content="Windows"/>
                        <ComboBoxItem Content="macOS"/>
                        <ComboBoxItem Content="iOS"/>
                        <ComboBoxItem Content="Android"/>
                        <ComboBoxItem Content="Linux"/>
                    </ComboBox>
                </StackPanel>

                <!-- Top Row Statistics -->
                <UniformGrid Grid.Row="2" Rows="1" Margin="20,10,20,10">
                    <Border x:Name="IntuneDevicesCard" Background="#1B2A47" Margin="0,0,10,0" CornerRadius="8" Cursor="Hand"
                            ToolTip="Click to view all Intune devices">
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
                                     Text="--"
                                     Foreground="White"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="Managed by Intune"
                                     Foreground="#A0AEC0"
                                     FontSize="12"/>
                        </Grid>
                    </Border>

                    <Border x:Name="AutopilotDevicesCard" Background="#1B2A47" Margin="10,0" CornerRadius="8" Cursor="Hand"
                            ToolTip="Click to view all Autopilot devices">
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
                                     Text="--"
                                     Foreground="White"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="Registered in Autopilot"
                                     Foreground="#A0AEC0"
                                     FontSize="12"/>
                        </Grid>
                    </Border>

                    <Border x:Name="EntraIDDevicesCard" Background="#1B2A47" Margin="10,0,0,0" CornerRadius="8" Cursor="Hand"
                            ToolTip="Click to view all Entra ID devices">
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
                                <Path Data="M12,5.5A3.5,3.5 0 0,1 15.5,9A3.5,3.5 0 0,1 12,12.5A3.5,3.5 0 0,1 8.5,9A3.5,3.5 0 0,1 12,5.5M5,8C5.56,8 6.08,8.15 6.53,8.42C6.38,9.85 6.8,11.27 7.66,12.38C7.16,13.34 6.16,14 5,14A3,3 0 0,1 2,11A3,3 0 0,1 5,8M19,8A3,3 0 0,1 22,11A3,3 0 0,1 19,14C17.84,14 16.84,13.34 16.34,12.38C17.2,11.27 17.62,9.85 17.47,8.42C17.92,8.15 18.44,8 19,8M5.5,18.25C5.5,16.18 8.41,14.5 12,14.5C15.59,14.5 18.5,16.18 18.5,18.25V20H5.5V18.25M0,20V18.5C0,17.11 1.89,15.94 4.45,15.6C3.86,16.28 3.5,17.22 3.5,18.25V20H0M24,20H20.5V18.25C20.5,17.22 20.14,16.28 19.55,15.6C22.11,15.94 24,17.11 24,18.5V20Z"
                                      Fill="#ED64A6" Width="24" Height="24" Stretch="Uniform"/>
                                <TextBlock Text="Entra ID Devices"
                                         Foreground="#A0AEC0"
                                         FontSize="14"
                                         Margin="12,0,0,0"
                                         VerticalAlignment="Center"/>
                            </StackPanel>
                            <TextBlock Grid.Row="1"
                                     x:Name="EntraIDDevicesCount"
                                     Text="--"
                                     Foreground="White"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="Registered in Entra ID"
                                     Foreground="#A0AEC0"
                                     FontSize="12"/>
                        </Grid>
                    </Border>
                </UniformGrid>

                <!-- Middle Row - Stale Devices -->
                <UniformGrid Grid.Row="3" Rows="1" Margin="20,10,20,10">
                    <Border x:Name="StaleDevices30Card" Background="#1B2A47" Margin="0,0,10,0" CornerRadius="8" Cursor="Hand"
                            ToolTip="Click to view devices not synced in 30+ days">
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
                                     Text="--"
                                     Foreground="#F6AD55"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="Not synced in 30+ days"
                                     Foreground="#A0AEC0"
                                     FontSize="12"/>
                            <ProgressBar x:Name="StaleDevices30Progress"
                                       Grid.Row="3"
                                       Height="4"
                                       Margin="0,12,0,0"
                                       Background="#2D3748"
                                       Foreground="#F6AD55"
                                       Value="0"/>
                        </Grid>
                    </Border>

                    <Border x:Name="StaleDevices90Card" Background="#1B2A47" Margin="10,0" CornerRadius="8" Cursor="Hand"
                            ToolTip="Click to view devices not synced in 90+ days">
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
                                     Text="--"
                                     Foreground="#FC8181"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="Not synced in 90+ days"
                                     Foreground="#A0AEC0"
                                     FontSize="12"/>
                            <ProgressBar x:Name="StaleDevices90Progress"
                                       Grid.Row="3"
                                       Height="4"
                                       Margin="0,12,0,0"
                                       Background="#2D3748"
                                       Foreground="#FC8181"
                                       Value="0"/>
                        </Grid>
                    </Border>

                    <Border x:Name="StaleDevices180Card" Background="#1B2A47" Margin="10,0,0,0" CornerRadius="8" Cursor="Hand"
                            ToolTip="Click to view devices not synced in 180+ days">
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
                                     Text="--"
                                     Foreground="#F56565"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="Not synced in 180+ days"
                                     Foreground="#A0AEC0"
                                     FontSize="12"/>
                            <ProgressBar x:Name="StaleDevices180Progress"
                                       Grid.Row="3"
                                       Height="4"
                                       Margin="0,12,0,0"
                                       Background="#2D3748"
                                       Foreground="#F56565"
                                       Value="0"/>
                        </Grid>
                    </Border>
                </UniformGrid>

                <!-- Bottom Row - Personal/Corporate and Charts -->
                <Grid Grid.Row="4" Margin="20,10,20,20">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="2*"/>
                    </Grid.ColumnDefinitions>

                    <!-- Personal Devices -->
                    <Border x:Name="PersonalDevicesCard" Grid.Column="0" Background="#1B2A47" Margin="0,0,10,0" CornerRadius="8" Height="220" Cursor="Hand"
                            ToolTip="Click to view all personal (BYOD) devices">
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
                                     Text="--"
                                     Foreground="#9F7AEA"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="BYOD Devices in Intune"
                                     Foreground="#A0AEC0"
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
                    <Border x:Name="CorporateDevicesCard" Grid.Column="1" Background="#1B2A47" Margin="10,0" CornerRadius="8" Height="220" Cursor="Hand"
                            ToolTip="Click to view all corporate-owned devices">
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
                                     Text="--"
                                     Foreground="#4FD1C5"
                                     FontSize="36"
                                     FontWeight="Bold"
                                     Margin="0,0,0,8"/>
                            <TextBlock Grid.Row="2"
                                     Text="Company Devices in Intune"
                                     Foreground="#A0AEC0"
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
                </ScrollViewer>
            </Grid>

            <!-- Device Management Page -->
            <Grid x:Name="DeviceManagementPage">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Page Header -->
                <Grid Grid.Row="0" Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel>
                        <TextBlock Text="Device Offboarding"
                                 FontSize="28"
                                 FontWeight="Bold"
                                 Foreground="#323130"
                                 Margin="0,0,0,4"/>
                        <TextBlock Text="Search, select, and offboard devices from Microsoft services"
                                 FontSize="14"
                                 Opacity="0.7"/>
                    </StackPanel>
                    <TextBlock x:Name="ResultCountText"
                             Grid.Column="1"
                             Text=""
                             FontSize="13"
                             Foreground="#4A5568"
                             VerticalAlignment="Bottom"
                             Margin="0,0,0,4"/>
                </Grid>

                <!-- Search Controls -->
                <Grid Grid.Row="1" Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="150"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <ComboBox x:Name="dropdown"
                              Margin="0,0,8,0"/>
                    <!-- Search Input with Placeholder -->
                    <Grid Grid.Column="1" Margin="0,0,8,0">
                        <TextBox x:Name="SearchInputText"
                                 TextWrapping="NoWrap"/>
                        <TextBlock x:Name="SearchPlaceholder"
                                 Text="Enter device name, serial number, or ID..."
                                 Foreground="#A0A0A0"
                                 FontSize="12"
                                 IsHitTestVisible="False"
                                 VerticalAlignment="Center"
                                 Margin="10,0,0,0"/>
                    </Grid>
                    <Button x:Name="bulk_import_button"
                            Grid.Column="2"
                            Content="Bulk Import"
                            ToolTip="Import devices from a CSV file"
                            Margin="0,0,8,0"/>
                    <Button x:Name="SearchButton"
                            Grid.Column="3"
                            Content="Search"
                            Margin="0,0,8,0"
                            ToolTip="Search for devices (Enter)"/>
                    <Button x:Name="FilterToggleButton"
                            Grid.Column="4"
                            Content="Filter"
                            Height="28"
                            Padding="12,5"
                            Background="#2D3748"
                            Foreground="White"
                            BorderThickness="0"
                            Cursor="Hand"
                            ToolTip="Toggle column filters"
                            Margin="0,0,8,0"/>
                    <Button x:Name="ClearSearchButton"
                            Grid.Column="5"
                            Content="Clear"
                            Height="28"
                            Padding="12,5"
                            Background="#718096"
                            Foreground="White"
                            BorderThickness="0"
                            Cursor="Hand"
                            ToolTip="Clear search results and filters (Escape)"/>
                </Grid>

                <!-- Filter Row -->
                <Grid x:Name="FilterRow" Grid.Row="3" Margin="0,0,0,4" Visibility="Collapsed">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="50"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="140"/>
                        <ColumnDefinition Width="120"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="150"/>
                        <ColumnDefinition Width="150"/>
                        <ColumnDefinition Width="150"/>
                        <ColumnDefinition Width="100"/>
                        <ColumnDefinition Width="70"/>
                    </Grid.ColumnDefinitions>
                    <TextBox x:Name="FilterDeviceName" Grid.Column="1" Height="24" FontSize="11" Margin="1,0" VerticalContentAlignment="Center" ToolTip="Filter by device name"/>
                    <TextBox x:Name="FilterSerialNumber" Grid.Column="2" Height="24" FontSize="11" Margin="1,0" VerticalContentAlignment="Center" ToolTip="Filter by serial number"/>
                    <TextBox x:Name="FilterOS" Grid.Column="3" Height="24" FontSize="11" Margin="1,0" VerticalContentAlignment="Center" ToolTip="Filter by operating system"/>
                    <TextBox x:Name="FilterPrimaryUser" Grid.Column="4" Height="24" FontSize="11" Margin="1,0" VerticalContentAlignment="Center" ToolTip="Filter by primary user"/>
                    <TextBox x:Name="FilterCompliance" Grid.Column="8" Height="24" FontSize="11" Margin="1,0" VerticalContentAlignment="Center" ToolTip="Filter by compliance state"/>
                </Grid>

                <!-- Results Grid with empty state -->
                <Grid Grid.Row="4" Margin="0,0,0,15">
                <TextBlock x:Name="SearchEmptyState"
                         Text="Search for devices using the controls above to get started"
                         Foreground="#A0AEC0"
                         FontSize="14"
                         HorizontalAlignment="Center"
                         VerticalAlignment="Center"
                         Margin="0,40,0,0"/>
                <DataGrid x:Name="SearchResultsDataGrid"
                          Visibility="Collapsed"
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
                                                  Width="140"
                                                  IsReadOnly="True"/>
                        <DataGridTextColumn Binding="{Binding OperatingSystem}"
                                                  Header="Operating System"
                                                  Width="120"
                                                  IsReadOnly="True"/>
                        <DataGridTextColumn Binding="{Binding PrimaryUser}"
                                                  Header="Primary User"
                                                  Width="*"
                                                  IsReadOnly="True"/>
                        <DataGridTextColumn Binding="{Binding AzureADLastContact}"
                                                  Header="Entra ID Last Contact"
                                                  Width="150"
                                                  IsReadOnly="True"/>
                        <DataGridTextColumn Binding="{Binding IntuneLastContact}"
                                                  Header="Intune Last Contact"
                                                  Width="150"
                                                  IsReadOnly="True"/>
                        <DataGridTextColumn Binding="{Binding AutopilotLastContact}"
                                                  Header="Autopilot Last Contact"
                                                  Width="150"
                                                  IsReadOnly="True"/>
                        <DataGridTextColumn Binding="{Binding ComplianceState}"
                                                  Header="Compliance"
                                                  Width="100"
                                                  IsReadOnly="True"/>
                        <DataGridTemplateColumn Header="Groups" Width="70">
                            <DataGridTemplateColumn.CellTemplate>
                                <DataTemplate>
                                    <TextBlock Text="View" Foreground="#0078D4" Cursor="Hand" Tag="{Binding EntraDeviceId}"
                                               TextDecorations="Underline" FontSize="12"
                                               ToolTip="View Entra ID group memberships"/>
                                </DataTemplate>
                            </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                    </DataGrid.Columns>
                </DataGrid>
                </Grid>

                <!-- Status Section -->
                <UniformGrid Grid.Row="5"
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
                            <Path Data="M12,5.5A3.5,3.5 0 0,1 15.5,9A3.5,3.5 0 0,1 12,12.5A3.5,3.5 0 0,1 8.5,9A3.5,3.5 0 0,1 12,5.5M5,8C5.56,8 6.08,8.15 6.53,8.42C6.38,9.85 6.8,11.27 7.66,12.38C7.16,13.34 6.16,14 5,14A3,3 0 0,1 2,11A3,3 0 0,1 5,8M19,8A3,3 0 0,1 22,11A3,3 0 0,1 19,14C17.84,14 16.84,13.34 16.34,12.38C17.2,11.27 17.62,9.85 17.47,8.42C17.92,8.15 18.44,8 19,8M5.5,18.25C5.5,16.18 8.41,14.5 12,14.5C15.59,14.5 18.5,16.18 18.5,18.25V20H5.5V18.25M0,20V18.5C0,17.11 1.89,15.94 4.45,15.6C3.86,16.28 3.5,17.22 3.5,18.25V20H0M24,20H20.5V18.25C20.5,17.22 20.14,16.28 19.55,15.6C22.11,15.94 24,17.11 24,18.5V20Z"
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
                </UniformGrid>

                <!-- Bottom Section -->
                <Grid Grid.Row="6">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <!-- Export Buttons (Left) -->
                    <Button x:Name="ExportSearchResultsButton"
                            Content="Export Results"
                            Grid.Column="0"
                            Height="40"
                            MinWidth="140"
                            Padding="20,0"
                            Background="#0078D4"
                            Foreground="White"
                            BorderThickness="0"
                            Margin="0,0,8,0"
                            Cursor="Hand"
                            ToolTip="Export all search results to CSV">
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
                                                    <Setter Property="Background" Value="#106EBE"/>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                            </Style>
                        </Button.Style>
                    </Button>

                    <Button x:Name="ExportSelectedButton"
                            Content="Export Selected"
                            Grid.Column="1"
                            Height="40"
                            MinWidth="140"
                            Padding="20,0"
                            Background="#059669"
                            Foreground="White"
                            BorderThickness="0"
                            Margin="0,0,8,0"
                            Cursor="Hand"
                            IsEnabled="False"
                            ToolTip="Export only selected devices to CSV">
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

                    <Button x:Name="SetGroupTagButton"
                            Content="Set Group Tag"
                            Grid.Column="2"
                            HorizontalAlignment="Left"
                            Height="40"
                            MinWidth="140"
                            Padding="20,0"
                            Background="#7C3AED"
                            Foreground="White"
                            BorderThickness="0"
                            Margin="0,0,8,0"
                            Cursor="Hand"
                            IsEnabled="False"
                            ToolTip="Set or clear the Autopilot group tag on selected devices">
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
                                                    <Setter Property="Background" Value="#6D28D9"/>
                                                </Trigger>
                                                <Trigger Property="IsEnabled" Value="False">
                                                    <Setter Property="Background" Value="#DDD6FE"/>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                            </Style>
                        </Button.Style>
                    </Button>

                    <!-- Offboard Panel (Right, conditional) -->
                    <StackPanel x:Name="OffboardPanel"
                                Grid.Column="3"
                                Orientation="Horizontal"
                                Visibility="Collapsed">
                        <TextBlock x:Name="SelectedDeviceCount"
                                 Text=""
                                 FontSize="13"
                                 Foreground="#DC2626"
                                 VerticalAlignment="Center"
                                 Margin="0,0,12,0"/>
                        <Button x:Name="OffboardButton"
                                Content="Offboard Devices"
                            Height="40"
                            Padding="20,0"
                            Background="#DC2626"
                            Foreground="White"
                            BorderThickness="0"
                            Margin="0,0,8,0"
                            Cursor="Hand"
                            ToolTip="Remove selected devices from Intune, Autopilot, and Entra ID">
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
                    </StackPanel>
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
                             Text="Pre-built reports for device compliance, inventory, and security audits"
                             FontSize="16"
                             Opacity="0.7"
                             TextWrapping="Wrap"/>
                </Grid>

                <ScrollViewer Grid.Row="1"
                             x:Name="PlaybooksScrollViewer"
                             Margin="20,0,20,20"
                             VerticalScrollBarVisibility="Auto">
                    <StackPanel>
                        <!-- Enrollment Discrepancies -->
                        <TextBlock Text="Enrollment Discrepancies"
                                 FontSize="18"
                                 FontWeight="SemiBold"
                                 Foreground="#323130"
                                 Margin="0,0,0,10"/>
                        <WrapPanel Margin="0,0,0,20">
                            <Button x:Name="PlaybookAutopilotNotIntune"
                                    Style="{StaticResource PlaybookButtonStyle}"
                                    MinWidth="300" MaxWidth="450"
                                    Height="120"
                                    Margin="0,0,15,15"
                                    Content="Autopilot Devices Not in Intune"
                                    Tag="Identify devices registered in Autopilot but missing from Intune management"/>
                            <Button x:Name="PlaybookIntuneNotAutopilot"
                                    Style="{StaticResource PlaybookButtonStyle}"
                                    MinWidth="300" MaxWidth="450"
                                    Height="120"
                                    Margin="0,0,15,15"
                                    Content="Intune Devices Not in Autopilot"
                                    Tag="Find managed devices that aren't registered in Autopilot"/>
                        </WrapPanel>

                        <!-- Inventory Reports -->
                        <TextBlock Text="Inventory Reports"
                                 FontSize="18"
                                 FontWeight="SemiBold"
                                 Foreground="#323130"
                                 Margin="0,0,0,10"/>
                        <WrapPanel Margin="0,0,0,20">
                            <Button x:Name="PlaybookCorporateDevices"
                                    Style="{StaticResource PlaybookButtonStyle}"
                                    MinWidth="300" MaxWidth="450"
                                    Height="120"
                                    Margin="0,0,15,15"
                                    Content="Corporate Device Inventory"
                                    Tag="View all company-owned devices managed in Intune"/>
                            <Button x:Name="PlaybookPersonalDevices"
                                    Style="{StaticResource PlaybookButtonStyle}"
                                    MinWidth="300" MaxWidth="450"
                                    Height="120"
                                    Margin="0,0,15,15"
                                    Content="Personal Device Inventory"
                                    Tag="List all BYOD devices enrolled in Intune"/>
                            <Button x:Name="PlaybookSpecificOS"
                                    Style="{StaticResource PlaybookButtonStyle}"
                                    MinWidth="300" MaxWidth="450"
                                    Height="120"
                                    Margin="0,0,15,15"
                                    Content="OS-Specific Device List"
                                    Tag="Filter devices by operating system version"/>
                        </WrapPanel>

                        <!-- Health and Security -->
                        <TextBlock Text="Health and Security"
                                 FontSize="18"
                                 FontWeight="SemiBold"
                                 Foreground="#323130"
                                 Margin="0,0,0,10"/>
                        <WrapPanel Margin="0,0,0,20">
                            <Button x:Name="PlaybookStaleDevices"
                                    Style="{StaticResource PlaybookButtonStyle}"
                                    MinWidth="300" MaxWidth="450"
                                    Height="120"
                                    Margin="0,0,15,15"
                                    Content="Stale Device Report"
                                    Tag="Identify devices that haven't checked in recently"/>
                            <Button x:Name="PlaybookNotLatestOS"
                                    Style="{StaticResource PlaybookButtonStyle}"
                                    MinWidth="300" MaxWidth="450"
                                    Height="120"
                                    Margin="0,0,15,15"
                                    Content="Outdated OS Report"
                                    Tag="Find devices running older operating system versions"/>
                            <Button x:Name="PlaybookEOLOS"
                                    Style="{StaticResource PlaybookButtonStyle}"
                                    MinWidth="300" MaxWidth="450"
                                    Height="120"
                                    Margin="0,0,15,15"
                                    Content="End-of-Life OS Report"
                                    Tag="Identify devices running unsupported OS versions"/>
                            <Button x:Name="PlaybookBitLocker"
                                    Style="{StaticResource PlaybookButtonStyle}"
                                    MinWidth="300" MaxWidth="450"
                                    Height="120"
                                    Margin="0,0,15,15"
                                    Content="BitLocker Key Report"
                                    Tag="View BitLocker recovery keys for Windows devices"/>
                            <Button x:Name="PlaybookFileVault"
                                    Style="{StaticResource PlaybookButtonStyle}"
                                    MinWidth="300" MaxWidth="450"
                                    Height="120"
                                    Margin="0,0,15,15"
                                    Content="FileVault Key Report"
                                    Tag="View FileVault recovery keys for macOS devices"/>
                            <Button x:Name="PlaybookCorporateIdentifiers"
                                    Style="{StaticResource PlaybookButtonStyle}"
                                    MinWidth="300" MaxWidth="450"
                                    Height="120"
                                    Margin="0,0,15,15"
                                    Content="Corporate Identifier Stale Report"
                                    Tag="Find imported corporate device identifiers and their last contact state"/>
                        </WrapPanel>
                    </StackPanel>
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
                                Content="Back to Playbooks"
                                Height="32"
                                Padding="12,0"
                                Background="#F0F0F0"
                                Foreground="#2D3748"
                                BorderThickness="0"
                                Cursor="Hand"
                                ToolTip="Return to playbook list">
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
                                BorderThickness="0"
                                Cursor="Hand"
                                ToolTip="Export results to a CSV file">
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
                              Text=""
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
                                              Width="2*"/>
                            <DataGridTextColumn Header="Serial Number"
                                              Binding="{Binding SerialNumber}"
                                              Width="*"/>
                            <DataGridTextColumn Header="Operating System"
                                              Binding="{Binding OperatingSystem}"
                                              Width="*"/>
                            <DataGridTextColumn Header="Primary User"
                                              Binding="{Binding PrimaryUser}"
                                              Width="1.5*"/>
                            <DataGridTextColumn Header="Last Contact"
                                              Binding="{Binding AutopilotLastContact}"
                                              Width="*"/>
                        </DataGrid.Columns>
                    </DataGrid>
                </Grid>
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
                    Margin="0,24,0,0"
                    IsCancel="True"
                    Cursor="Hand"/>

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
                        BorderThickness="0"
                        IsCancel="True"
                        Cursor="Hand"/>
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
    Title="Connect to Microsoft Graph" Height="500" Width="650"
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
                <TextBlock Text="Select an authentication method to connect to Microsoft Graph"
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
                        Margin="0,0,12,0"
                        IsCancel="True"
                        Cursor="Hand"/>
                <Button x:Name="ConnectButton"
                        Content="Connect"
                        Style="{StaticResource AuthButtonStyle}"
                        Width="120"
                        IsDefault="True"
                        Cursor="Hand"/>
            </StackPanel>

            <!-- Scrollable Content -->
            <ScrollViewer VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Disabled"
                         Padding="0,0,16,0">
                <StackPanel Margin="0,0,8,0">
                    <RadioButton x:Name="InteractiveAuth"
                                Style="{StaticResource AuthRadioButtonStyle}"
                                Content="Interactive Login (Browser)"
                                IsChecked="True"/>

                    <RadioButton x:Name="DeviceCodeAuth"
                                Style="{StaticResource AuthRadioButtonStyle}"
                                Content="Device Code Login (No Browser Redirect)"/>

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

                        <!-- Import and Save Buttons -->
                        <StackPanel Grid.Row="3" Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
                            <Button x:Name="SaveCertButton"
                                    Content="Save Locally"
                                    Style="{StaticResource SecondaryButtonStyle}"
                                    Height="32"
                                    Width="120"
                                    Margin="0,0,8,0"
                                    Cursor="Hand"
                                    ToolTip="Save configuration to disk for auto-loading next time"/>
                            <Button x:Name="ImportCertButton"
                                    Content="Import"
                                    Style="{StaticResource SecondaryButtonStyle}"
                                    Height="32"
                                    Width="120"
                                    Cursor="Hand"
                                    ToolTip="Import configuration from a JSON file"/>
                        </StackPanel>

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

                        <!-- Import and Save Buttons -->
                        <StackPanel Grid.Row="3" Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
                            <Button x:Name="SaveSecretButton"
                                    Content="Save Locally"
                                    Style="{StaticResource SecondaryButtonStyle}"
                                    Height="32"
                                    Width="120"
                                    Margin="0,0,8,0"
                                    Cursor="Hand"
                                    ToolTip="Save App ID and Tenant ID to disk (secret is not stored)"/>
                            <Button x:Name="ImportSecretButton"
                                    Content="Import"
                                    Style="{StaticResource SecondaryButtonStyle}"
                                    Height="32"
                                    Width="120"
                                    Cursor="Hand"
                                    ToolTip="Import configuration from a JSON file"/>
                        </StackPanel>

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
                        Margin="0,0,12,0"
                        IsCancel="True"/>
                <Button x:Name="ImportButton"
                        Content="Import Devices"
                        Style="{StaticResource BulkImportButtonStyle}"
                        Width="140"
                        IsEnabled="False"
                        ToolTip="Import the listed devices and trigger a search"/>
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
                            <TextBlock Text="File Template" 
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
                                    CornerRadius="6"
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
                                    Content="Save Template"
                                    Style="{StaticResource BulkImportButtonStyle}"
                                    Width="180"
                                    HorizontalAlignment="Left"
                                    ToolTip="Save a sample CSV template to disk"/>
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
                                        Text="Click Browse to select a CSV or TXT file"/>
                                <Button x:Name="BrowseFileButton"
                                        Grid.Column="1"
                                        Content="Browse..."
                                        Style="{StaticResource BulkImportSecondaryButtonStyle}"
                                        Width="100"
                                        ToolTip="Select a CSV or TXT file with one device per line"/>
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
        Permission = "Device.ReadWrite.All"
        Reason     = "Needed to read and delete device objects from Entra ID"
    },
    @{
        Permission = "DeviceManagementServiceConfig.ReadWrite.All"
        Reason     = "Required for Autopilot configuration and management"
    },
    @{
        Permission = "BitlockerKey.Read.All"
        Reason     = "Required to read BitLocker recovery keys for device offboarding"
    },
    @{
        Permission = "DeviceLocalCredential.Read.All"
        Reason     = "Required to read LAPS passwords for device offboarding"
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
        Write-Log "Error creating authentication window: $_"
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
    $deviceCodeAuth = $authWindow.FindName('DeviceCodeAuth')
    $certificateAuth = $authWindow.FindName('CertificateAuth')
    $secretAuth = $authWindow.FindName('SecretAuth')
    $certificateInputs = $authWindow.FindName('CertificateInputs')
    $secretInputs = $authWindow.FindName('SecretInputs')
    $connectButton = $authWindow.FindName('ConnectButton')
    $cancelAuthButton = $authWindow.FindName('CancelAuthButton')
    $importCertButton = $authWindow.FindName('ImportCertButton')
    $importSecretButton = $authWindow.FindName('ImportSecretButton')
    $saveCertButton = $authWindow.FindName('SaveCertButton')
    $saveSecretButton = $authWindow.FindName('SaveSecretButton')

    # Auto-load saved config if available
    $certConfigPath = [System.IO.Path]::Combine($script:ConfigDirectory, "cert_config.json")
    $secretConfigPath = [System.IO.Path]::Combine($script:ConfigDirectory, "secret_config.json")
    if (Test-Path $certConfigPath) {
        try {
            $savedCert = Get-Content $certConfigPath -Raw | ConvertFrom-Json
            if ($savedCert.AppId) { $authWindow.FindName('CertAppId').Text = $savedCert.AppId }
            if ($savedCert.TenantId) { $authWindow.FindName('CertTenantId').Text = $savedCert.TenantId }
            if ($savedCert.Thumbprint) { $authWindow.FindName('CertThumbprint').Text = $savedCert.Thumbprint }
        }
        catch { }
    }
    if (Test-Path $secretConfigPath) {
        try {
            $savedSecret = Get-Content $secretConfigPath -Raw | ConvertFrom-Json
            if ($savedSecret.AppId) { $authWindow.FindName('SecretAppId').Text = $savedSecret.AppId }
            if ($savedSecret.TenantId) { $authWindow.FindName('SecretTenantId').Text = $savedSecret.TenantId }
        }
        catch { }
    }

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

    $deviceCodeAuth.Add_Checked({
            $certificateInputs.Visibility = 'Collapsed'
            $secretInputs.Visibility = 'Collapsed'
        })

    # Auto-select auth method if saved config exists
    if (Test-Path $certConfigPath) {
        $certificateAuth.IsChecked = $true
    } elseif (Test-Path $secretConfigPath) {
        $secretAuth.IsChecked = $true
    }

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

    # Save config button handlers
    $saveCertButton.Add_Click({
            $appId = $authWindow.FindName('CertAppId').Text
            $tenantId = $authWindow.FindName('CertTenantId').Text
            $thumbprint = $authWindow.FindName('CertThumbprint').Text
            if ([string]::IsNullOrWhiteSpace($appId) -or [string]::IsNullOrWhiteSpace($tenantId) -or [string]::IsNullOrWhiteSpace($thumbprint)) {
                [System.Windows.MessageBox]::Show(
                    "Please fill in App ID, Tenant ID, and Thumbprint before saving.",
                    "Validation Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                )
                return
            }
            try {
                $config = @{ AppId = $appId; TenantId = $tenantId; Thumbprint = $thumbprint }
                $configPath = [System.IO.Path]::Combine($script:ConfigDirectory, "cert_config.json")
                $config | ConvertTo-Json | Set-Content -Path $configPath -Force
                [System.Windows.MessageBox]::Show(
                    "Certificate configuration saved. It will be auto-loaded next time you open the authentication dialog.",
                    "Configuration Saved",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )
            }
            catch {
                [System.Windows.MessageBox]::Show(
                    "Error saving configuration: $_",
                    "Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            }
        })

    $saveSecretButton.Add_Click({
            $appId = $authWindow.FindName('SecretAppId').Text
            $tenantId = $authWindow.FindName('SecretTenantId').Text
            if ([string]::IsNullOrWhiteSpace($appId) -or [string]::IsNullOrWhiteSpace($tenantId)) {
                [System.Windows.MessageBox]::Show(
                    "Please fill in App ID and Tenant ID before saving.",
                    "Validation Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                )
                return
            }
            try {
                $config = @{ AppId = $appId; TenantId = $tenantId }
                $configPath = [System.IO.Path]::Combine($script:ConfigDirectory, "secret_config.json")
                $config | ConvertTo-Json | Set-Content -Path $configPath -Force
                [System.Windows.MessageBox]::Show(
                    "Configuration saved (App ID and Tenant ID only). The client secret is not persisted for security reasons and must be entered each session.",
                    "Configuration Saved",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )
            }
            catch {
                [System.Windows.MessageBox]::Show(
                    "Error saving configuration: $_",
                    "Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
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
        Write-Log "Error showing authentication dialog: $_"
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
        elseif ($deviceCodeAuth.IsChecked) {
            return @{
                Method = 'DeviceCode'
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

function Get-DeviceOffboardingSettings {
    $defaults = [ordered]@{
        DefenderIntegrationEnabled = $false
    }

    if (-not $script:ConfigDirectory) {
        return [pscustomobject]$defaults
    }

    $settingsPath = [System.IO.Path]::Combine($script:ConfigDirectory, "settings.json")
    if (-not (Test-Path $settingsPath)) {
        return [pscustomobject]$defaults
    }

    try {
        $savedSettings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
        foreach ($key in @($defaults.Keys)) {
            if ($savedSettings.PSObject.Properties.Name -contains $key) {
                $defaults[$key] = $savedSettings.$key
            }
        }
    }
    catch {
        Write-Log "Error reading settings file: $_" -Severity "WARN"
    }

    return [pscustomobject]$defaults
}

function Save-DeviceOffboardingSettings {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Settings
    )

    if (-not $script:ConfigDirectory) {
        throw "Config directory is not initialized."
    }

    if (-not (Test-Path $script:ConfigDirectory)) {
        New-Item -Path $script:ConfigDirectory -ItemType Directory -Force | Out-Null
    }

    $settingsPath = [System.IO.Path]::Combine($script:ConfigDirectory, "settings.json")
    $Settings | ConvertTo-Json | Set-Content -Path $settingsPath -Force
    $script:DeviceOffboardingSettings = $Settings
}

function Get-DefenderIntegrationEnabled {
    if (-not $script:DeviceOffboardingSettings) {
        $script:DeviceOffboardingSettings = Get-DeviceOffboardingSettings
    }

    return [bool]$script:DeviceOffboardingSettings.DefenderIntegrationEnabled
}

function Set-DefenderIntegrationEnabled {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    $settings = Get-DeviceOffboardingSettings
    $settings.DefenderIntegrationEnabled = $Enabled
    Save-DeviceOffboardingSettings -Settings $settings

    Write-Log "Defender for Endpoint integration setting changed to: $Enabled" -Severity "AUDIT"
}

function Connect-ToGraph {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthDetails
    )

    try {
        Write-Log "Attempting to connect to Microsoft Graph using $($AuthDetails.Method) authentication..."
        $script:CurrentAuthDetails = $null

        # Get required permissions
        $permissionsList = ($script:requiredPermissions | ForEach-Object { $_.Permission })

        # Connect based on authentication method
        switch ($AuthDetails.Method) {
            'Interactive' {
                # Classic browser-based authorization code flow (PKCE), no WAM broker
                $connectionResult = Connect-MgGraphCommunity -Scopes $permissionsList -NoWelcome -ErrorAction Stop
                $script:CurrentAuthDetails = @{
                    Method = 'Interactive'
                }
            }
            'DeviceCode' {
                $connectionResult = Connect-MgGraphCommunity -Scopes $permissionsList -UseDeviceCode -NoWelcome -ErrorAction Stop
                $script:CurrentAuthDetails = @{
                    Method = 'DeviceCode'
                }
            }
            'Certificate' {
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
                Disconnect-MgGraphCommunity -ErrorAction SilentlyContinue

                $connectionResult = Connect-MgGraphCommunity -ClientId $AuthDetails.AppId -TenantId $AuthDetails.TenantId -CertificateThumbprint $AuthDetails.Thumbprint -NoWelcome -ErrorAction Stop
                $script:CurrentAuthDetails = @{
                    Method     = 'Certificate'
                    AppId      = $AuthDetails.AppId
                    TenantId   = $AuthDetails.TenantId
                    Thumbprint = $AuthDetails.Thumbprint
                }
            }
            'Secret' {
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
                
                $connectionResult = Connect-MgGraphCommunity -ClientId $AuthDetails.AppId -TenantId $AuthDetails.TenantId -ClientSecretCredential $ClientSecretCredential -NoWelcome -ErrorAction Stop
                $script:CurrentAuthDetails = @{
                    Method             = 'Secret'
                    AppId              = $AuthDetails.AppId
                    TenantId           = $AuthDetails.TenantId
                    SecretSecureString = $SecuredPasswordPassword
                }

                # Clear sensitive credentials from memory
                $SecuredPasswordPassword = $null
                $ClientSecretCredential = $null
                $AuthDetails.Secret = $null
                $AuthDetails.Remove('Secret')
            }
            default {
                throw "Invalid authentication method specified"
            }
        }

        # Check permissions
        $context = Get-MgGraphCommunityContext
        if (-not $context) {
            throw "Failed to get Microsoft Graph context after connection"
        }

        # Capture admin identity for audit logging
        if ($context.Account) {
            $script:AdminUPN = $context.Account
        } else {
            $script:AdminUPN = "AppId:$($context.ClientId)"
        }
        Write-Log "Authenticated as $($script:AdminUPN)" -Severity "AUDIT"

        # Get tenant details and update UI
        try {
            Write-Log "Retrieving tenant information..."
            $tenantInfo = Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/organization?`$select=displayName,id,verifiedDomains" -Method GET
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
            $permission = $permissionInfo.Permission
            if (-not ($currentPermissions -contains $permission -or
                    $currentPermissions -contains $permission.Replace(".Read", ".ReadWrite"))) {
                $missingPermissions += $permission
            }
        }

        if ($missingPermissions.Count -gt 0) {
            $missingList = $missingPermissions -join ", "
            Write-Log "Warning: Missing permissions: $missingList"
            Show-Toast -Message "Missing permissions: $missingList" -Type "info" -DurationSeconds 6
        }

        Write-Log "Successfully connected to Microsoft Graph"
        return $true
    }
    catch {
        Write-Log "Failed to connect to Microsoft Graph: $_"
        Show-Toast -Message "Failed to connect to Microsoft Graph: $_" -Type "error" -DurationSeconds 8
        
        # Reset UI state on connection failure
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

$script:LogDirectory = [System.IO.Path]::Combine([Environment]::GetFolderPath("Desktop"), "DOM_Logs")
if (-not (Test-Path $script:LogDirectory)) { New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null }
$script:LogFilePath = [System.IO.Path]::Combine($script:LogDirectory, "DOM_$(Get-Date -Format 'yyyyMMdd_HHmmss').log")
$script:AdminUPN = $null
$script:CurrentAuthDetails = $null

# Config directory for saved authentication settings
$script:ConfigDirectory = [System.IO.Path]::Combine(
    [Environment]::GetFolderPath("LocalApplicationData"),
    "DeviceOffboardingManager")
if (-not (Test-Path $script:ConfigDirectory)) {
    New-Item -Path $script:ConfigDirectory -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARN", "ERROR", "AUDIT")]
        [string] $Severity = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $admin = if ($script:AdminUPN) { $script:AdminUPN } else { "N/A" }
    $logMessage = "$timestamp | $Severity | $admin | $Message"

    Add-Content -Path $script:LogFilePath -Value $logMessage

    if ($script:VerboseMode -and $Severity -in @("WARN", "ERROR")) {
        $color = if ($Severity -eq "ERROR") { "Red" } else { "Yellow" }
        Write-Host "[$Severity] $Message" -ForegroundColor $color
    }
}

$script:DeviceOffboardingSettings = Get-DeviceOffboardingSettings

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

function Export-OffboardingReport {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Results,
        [Parameter(Mandatory = $false)]
        [string]$DefaultFileName = "OffboardingReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    )

    try {
        $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveFileDialog.Filter = "HTML Files (*.html)|*.html"
        $saveFileDialog.DefaultExt = "html"
        $saveFileDialog.FileName = $DefaultFileName
        $saveFileDialog.Title = "Export Offboarding Report"

        if ($saveFileDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $false }

        $exportPath = $saveFileDialog.FileName
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $adminUPN = [System.Web.HttpUtility]::HtmlEncode($(if ($script:AdminUPN) { $script:AdminUPN } else { "N/A" }))
        $version = Get-ScriptVersion

        # Calculate summary stats
        $total = $Results.Count
        $successCount = 0
        $partialCount = 0
        $failedCount = 0
        foreach ($r in $Results) {
            $svc = 0; $ok = 0
            if ($r.EntraID.Found) { $svc++; if ($r.EntraID.Success) { $ok++ } }
            if ($r.Intune.Found) { $svc++; if ($r.Intune.Success) { $ok++ } }
            if ($r.Autopilot.Found) { $svc++; if ($r.Autopilot.Success) { $ok++ } }
            if ($r.MDE -and $r.MDE.Found) { $svc++; if ($r.MDE.Success) { $ok++ } }
            if ($svc -eq 0) { $failedCount++ }
            elseif ($ok -eq $svc) { $successCount++ }
            elseif ($ok -gt 0) { $partialCount++ }
            else { $failedCount++ }
        }

        # Build device rows
        $deviceRows = ""
        foreach ($r in $Results) {
            $entraStatus = if ($r.EntraID.Found) { if ($r.EntraID.Success) { "Removed" } else { "Failed" } } else { "N/A" }
            $entraClass = if (-not $r.EntraID.Found) { "na" } elseif ($r.EntraID.Success) { "success" } else { "failed" }
            $entraError = if ($r.EntraID.Error) { "<br><small>$([System.Web.HttpUtility]::HtmlEncode($r.EntraID.Error))</small>" } else { "" }

            $intuneStatus = if ($r.Intune.Found) { if ($r.Intune.Success) { "Removed" } else { "Failed" } } else { "N/A" }
            $intuneClass = if (-not $r.Intune.Found) { "na" } elseif ($r.Intune.Success) { "success" } else { "failed" }
            $intuneError = if ($r.Intune.Error) { "<br><small>$([System.Web.HttpUtility]::HtmlEncode($r.Intune.Error))</small>" } else { "" }

            $autopilotStatus = if ($r.Autopilot.Found) { if ($r.Autopilot.Success) { "Removed" } else { "Failed" } } else { "N/A" }
            $autopilotClass = if (-not $r.Autopilot.Found) { "na" } elseif ($r.Autopilot.Success) { "success" } else { "failed" }
            $autopilotError = if ($r.Autopilot.Error) { "<br><small>$([System.Web.HttpUtility]::HtmlEncode($r.Autopilot.Error))</small>" } else { "" }

            $mdeStatus = if ($r.MDE -and $r.MDE.Found) { if ($r.MDE.Success) { "Offboarded" } else { "Failed" } } else { "N/A" }
            $mdeClass = if (-not $r.MDE -or -not $r.MDE.Found) { "na" } elseif ($r.MDE.Success) { "success" } else { "failed" }
            $mdeError = if ($r.MDE -and $r.MDE.Error) { "<br><small>$([System.Web.HttpUtility]::HtmlEncode($r.MDE.Error))</small>" } else { "" }

            $deviceName = [System.Web.HttpUtility]::HtmlEncode($r.DeviceName)
            $serialNum = if ($r.SerialNumber) { [System.Web.HttpUtility]::HtmlEncode($r.SerialNumber) } else { "N/A" }

            # Determine row class
            $svc = 0; $ok = 0
            if ($r.EntraID.Found) { $svc++; if ($r.EntraID.Success) { $ok++ } }
            if ($r.Intune.Found) { $svc++; if ($r.Intune.Success) { $ok++ } }
            if ($r.Autopilot.Found) { $svc++; if ($r.Autopilot.Success) { $ok++ } }
            if ($r.MDE -and $r.MDE.Found) { $svc++; if ($r.MDE.Success) { $ok++ } }
            $rowClass = if ($svc -eq 0) { "row-failed" } elseif ($ok -eq $svc) { "row-success" } elseif ($ok -gt 0) { "row-partial" } else { "row-failed" }

            $deviceRows += @"
            <tr class="$rowClass">
                <td>$deviceName</td>
                <td>$serialNum</td>
                <td class="$entraClass">$entraStatus$entraError</td>
                <td class="$intuneClass">$intuneStatus$intuneError</td>
                <td class="$autopilotClass">$autopilotStatus$autopilotError</td>
                <td class="$mdeClass">$mdeStatus$mdeError</td>
            </tr>
"@
        }

        $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Device Offboarding Report</title>
<style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background: #f8f9fa; color: #1a202c; }
    .container { max-width: 1100px; margin: 0 auto; }
    .header { background: #1B2A47; color: white; padding: 24px 32px; border-radius: 8px 8px 0 0; }
    .header h1 { margin: 0 0 8px 0; font-size: 22px; }
    .header .meta { font-size: 12px; color: #a0aec0; }
    .summary { display: flex; gap: 16px; padding: 20px 32px; background: white; border-bottom: 1px solid #e2e8f0; }
    .stat { flex: 1; text-align: center; padding: 12px; border-radius: 6px; }
    .stat .number { font-size: 28px; font-weight: bold; }
    .stat .label { font-size: 12px; color: #718096; margin-top: 4px; }
    .stat-total { background: #edf2f7; }
    .stat-success { background: #f0fff4; }
    .stat-success .number { color: #48bb78; }
    .stat-partial { background: #fffbeb; }
    .stat-partial .number { color: #ecc94b; }
    .stat-failed { background: #fef2f2; }
    .stat-failed .number { color: #f56565; }
    table { width: 100%; border-collapse: collapse; background: white; }
    th { background: #edf2f7; padding: 10px 12px; text-align: left; font-size: 12px; font-weight: 600; color: #4a5568; border-bottom: 2px solid #e2e8f0; }
    td { padding: 10px 12px; font-size: 13px; border-bottom: 1px solid #e2e8f0; }
    td small { color: #f56565; }
    .row-success { border-left: 3px solid #48bb78; }
    .row-partial { border-left: 3px solid #ecc94b; }
    .row-failed { border-left: 3px solid #f56565; }
    .success { color: #48bb78; font-weight: 500; }
    .failed { color: #f56565; font-weight: 500; }
    .na { color: #a0aec0; }
    .footer { padding: 16px 32px; background: white; border-radius: 0 0 8px 8px; border-top: 1px solid #e2e8f0; font-size: 11px; color: #a0aec0; text-align: center; }
    @media print { body { background: white; padding: 0; } .container { max-width: 100%; } }
</style>
</head>
<body>
<div class="container">
    <div class="header">
        <h1>Device Offboarding Report</h1>
        <div class="meta">Generated: $timestamp | Admin: $adminUPN | Device Offboarding Manager $version</div>
    </div>
    <div class="summary">
        <div class="stat stat-total"><div class="number">$total</div><div class="label">Total Devices</div></div>
        <div class="stat stat-success"><div class="number">$successCount</div><div class="label">Successful</div></div>
        <div class="stat stat-partial"><div class="number">$partialCount</div><div class="label">Partial</div></div>
        <div class="stat stat-failed"><div class="number">$failedCount</div><div class="label">Failed</div></div>
    </div>
    <table>
        <thead>
            <tr>
                <th>Device Name</th>
                <th>Serial Number</th>
                <th>Entra ID</th>
                <th>Intune</th>
                <th>Autopilot</th>
                <th>MDE</th>
            </tr>
        </thead>
        <tbody>
$deviceRows
        </tbody>
    </table>
    <div class="footer">Device Offboarding Manager - Audit Report</div>
</div>
</body>
</html>
"@

        [System.IO.File]::WriteAllText($exportPath, $html)
        Write-Log "Exported offboarding report to: $exportPath" -Severity "AUDIT"
        Show-Toast -Message "Report exported successfully to: $exportPath" -Type "success"
        return $true
    }
    catch {
        Write-Log "Error exporting offboarding report: $_" -Severity "ERROR"
        Show-Toast -Message "Error exporting report: $_" -Type "error" -DurationSeconds 6
        return $false
    }
}

function ConvertTo-ODataStringValue {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return $Value.Replace("'", "''")
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

        # Pre-fetch Autopilot devices once for devicename search (API doesn't support displayName filtering)
        $allAutopilotDevices = $null
        if ($SearchOption -eq "Device Name") {
            try {
                $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
                $allAutopilotDevices = Get-GraphPagedResults -Uri $uri
                Write-Log "Pre-fetched $($allAutopilotDevices.Count) Autopilot devices for display name matching"
            }
            catch {
                Write-Log "Error pre-fetching Autopilot devices: $_"
                $allAutopilotDevices = @()
            }
        }

        foreach ($SearchText in $SearchTexts) {
            # Trim whitespace and newlines
            $SearchText = $SearchText.Trim()

            if ([string]::IsNullOrWhiteSpace($SearchText)) {
                continue
            }

            $escapedSearchText = ConvertTo-ODataStringValue -Value $SearchText

            if ($SearchOption -eq "Device Name") {
                # Batch Entra + Intune queries together
                $batchRequests = @(
                    @{ id = "entra"; method = "GET"; url = "/devices?`$filter=displayName eq '$escapedSearchText'&`$select=id,deviceId,displayName,operatingSystem,approximateLastSignInDateTime,accountEnabled,physicalIds" }
                    @{ id = "intune"; method = "GET"; url = "/deviceManagement/managedDevices?`$filter=deviceName eq '$escapedSearchText'&`$select=id,deviceName,serialNumber,operatingSystem,userDisplayName,lastSyncDateTime,azureADDeviceId,complianceState,managementAgent" }
                )
                $batchResponses = Invoke-GraphBatchRequest -Requests $batchRequests
                $entraResp = $batchResponses | Where-Object { $_.id -eq "entra" }
                $intuneResp = $batchResponses | Where-Object { $_.id -eq "intune" }
                $AADDevices = if ($entraResp -and $entraResp.status -eq 200 -and $entraResp.body.value) { $entraResp.body.value } else { @() }
                $IntuneDevices = if ($intuneResp -and $intuneResp.status -eq 200 -and $intuneResp.body.value) { $intuneResp.body.value } else { @() }

                # Filter pre-fetched Autopilot devices by display name (exact match)
                $AutopilotDevices = @()
                if ($allAutopilotDevices) {
                    $AutopilotDevices = $allAutopilotDevices | Where-Object {
                        $_.displayName -and $_.displayName -eq $SearchText
                    }
                }
                Write-Log "Found $(@($AutopilotDevices).Count) Autopilot devices matching display name: $SearchText"

                # Process Entra ID devices
                if ($AADDevices) {
                    foreach ($AADDevice in $AADDevices) {
                        $matchingIntuneDevice = $IntuneDevices | Where-Object { $_.deviceName -eq $AADDevice.displayName } | Select-Object -First 1
                        $matchingAutopilotDevice = $AutopilotDevices | Where-Object { $_.displayName -eq $AADDevice.displayName } | Select-Object -First 1
                        
                        # If no Autopilot match by displayName and we have Intune device with serial, try serial number
                        if (-not $matchingAutopilotDevice -and $matchingIntuneDevice -and $matchingIntuneDevice.serialNumber) {
                            $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$(ConvertTo-ODataStringValue -Value $matchingIntuneDevice.serialNumber)')"
                            $matchingAutopilotDevice = (Get-GraphPagedResults -Uri $uri) | Select-Object -First 1
                        }

                        $CombinedDevice = New-Object DeviceObject
                        $CombinedDevice.IsSelected = $false
                        $CombinedDevice.DeviceName = $AADDevice.displayName
                        
                        # Try to get serial number from multiple sources
                        $CombinedDevice.SerialNumber = $matchingIntuneDevice?.serialNumber ?? $matchingAutopilotDevice?.serialNumber
                        
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
                        $CombinedDevice.PrimaryUser = $matchingIntuneDevice?.userDisplayName
                        $CombinedDevice.AzureADLastContact = ConvertTo-SafeDateTime -dateString $AADDevice.approximateLastSignInDateTime
                        $CombinedDevice.IntuneLastContact = ConvertTo-SafeDateTime -dateString $matchingIntuneDevice.lastSyncDateTime
                        $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $matchingAutopilotDevice.lastContactedDateTime
                        $CombinedDevice.EntraDeviceId = $AADDevice.id
                        $CombinedDevice.EntraDeviceObjectId = $AADDevice.deviceId
                        $CombinedDevice.IntuneDeviceId = $matchingIntuneDevice?.id
                        $CombinedDevice.AutopilotIdentityId = $matchingAutopilotDevice?.id
                        $CombinedDevice.EntraAccountEnabled = if ($null -ne $AADDevice.accountEnabled) { $AADDevice.accountEnabled.ToString() } else { $null }
                        $CombinedDevice.ComplianceState = $matchingIntuneDevice?.complianceState
                        $CombinedDevice.ManagementAgent = $matchingIntuneDevice?.managementAgent

                        $searchResults.Add($CombinedDevice)
                        $AADCount++
                        if ($matchingIntuneDevice) { $IntuneCount++ }
                        if ($matchingAutopilotDevice) { $AutopilotCount++ }
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
                            $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$(ConvertTo-ODataStringValue -Value $IntuneDevice.serialNumber)')"
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
                        $CombinedDevice.IntuneDeviceId = $IntuneDevice.id
                        $CombinedDevice.AutopilotIdentityId = $matchingAutopilotDevice?.id
                        $CombinedDevice.ComplianceState = $IntuneDevice.complianceState
                        $CombinedDevice.ManagementAgent = $IntuneDevice.managementAgent

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
                        $CombinedDevice.AutopilotIdentityId = $AutopilotDevice.id

                        $searchResults.Add($CombinedDevice)
                        $AutopilotCount++
                    }
                }
            }
            elseif ($SearchOption -eq "Serial Number") {
                # Batch Intune + Autopilot queries together.
                # NOTE: Intune managedDevices only supports 'eq' on serialNumber; contains()/startswith()
                # are silently ignored and return zero results. Autopilot does support contains().
                $batchRequests = @(
                    @{ id = "intune"; method = "GET"; url = "/deviceManagement/managedDevices?`$filter=serialNumber eq '$escapedSearchText'&`$select=id,deviceName,serialNumber,operatingSystem,userDisplayName,lastSyncDateTime,azureADDeviceId,complianceState,managementAgent" }
                    @{ id = "autopilot"; method = "GET"; url = "/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$escapedSearchText')" }
                )
                $batchResponses = Invoke-GraphBatchRequest -Requests $batchRequests
                $intuneResp = $batchResponses | Where-Object { $_.id -eq "intune" }
                $autopilotResp = $batchResponses | Where-Object { $_.id -eq "autopilot" }
                $IntuneDevices = if ($intuneResp -and $intuneResp.status -eq 200 -and $intuneResp.body.value) { $intuneResp.body.value } else { @() }
                $AutopilotDevices = if ($autopilotResp -and $autopilotResp.status -eq 200 -and $autopilotResp.body.value) { $autopilotResp.body.value } else { @() }

                if ($IntuneDevices -or $AutopilotDevices) {
                    # If device is in Intune
                    if ($IntuneDevices) {
                        foreach ($IntuneDevice in $IntuneDevices) {
                            # Get Entra ID Device
                            $uri = "https://graph.microsoft.com/beta/devices?`$filter=displayName eq '$(ConvertTo-ODataStringValue -Value $IntuneDevice.deviceName)'&`$select=id,deviceId,displayName,operatingSystem,approximateLastSignInDateTime,accountEnabled,physicalIds"
                            $AADDevice = (Get-GraphPagedResults -Uri $uri) | Select-Object -First 1
                            
                            # Get Autopilot Device
                            $matchingAutopilotDevice = $AutopilotDevices | Where-Object { $_.serialNumber -eq $IntuneDevice.serialNumber } | Select-Object -First 1

                            $CombinedDevice = New-Object DeviceObject
                            $CombinedDevice.IsSelected = $false
                            $CombinedDevice.DeviceName = $IntuneDevice.deviceName
                            $CombinedDevice.SerialNumber = $IntuneDevice.serialNumber
                            $CombinedDevice.OperatingSystem = $AADDevice?.operatingSystem ?? $IntuneDevice.operatingSystem
                            $CombinedDevice.PrimaryUser = $IntuneDevice.userDisplayName
                            $CombinedDevice.AzureADLastContact = ConvertTo-SafeDateTime -dateString $AADDevice.approximateLastSignInDateTime
                            $CombinedDevice.IntuneLastContact = ConvertTo-SafeDateTime -dateString $IntuneDevice.lastSyncDateTime
                            $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $matchingAutopilotDevice.lastContactedDateTime
                            $CombinedDevice.EntraDeviceId = $AADDevice?.id
                            $CombinedDevice.EntraDeviceObjectId = $AADDevice?.deviceId
                            $CombinedDevice.IntuneDeviceId = $IntuneDevice.id
                            $CombinedDevice.AutopilotIdentityId = $matchingAutopilotDevice?.id
                            $CombinedDevice.EntraAccountEnabled = if ($null -ne $AADDevice -and $null -ne $AADDevice.accountEnabled) { $AADDevice.accountEnabled.ToString() } else { $null }
                            $CombinedDevice.ComplianceState = $IntuneDevice.complianceState
                            $CombinedDevice.ManagementAgent = $IntuneDevice.managementAgent

                            $searchResults.Add($CombinedDevice)
                            if ($AADDevice) { $AADCount++ }
                            $IntuneCount++
                            if ($matchingAutopilotDevice) { $AutopilotCount++ }
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
                            $CombinedDevice.AutopilotIdentityId = $AutopilotDevice.id

                            $searchResults.Add($CombinedDevice)
                            $AutopilotCount++
                        }
                    }
                }
            }
            elseif ($SearchOption -eq "Device ID") {
                # Direct lookup by Entra device object ID
                try {
                    $uri = "https://graph.microsoft.com/beta/devices/$SearchText"
                    $AADDevice = Invoke-MgGraphCommunityRequest -OutputType Hashtable -Uri $uri -Method GET
                }
                catch {
                    Write-Log "Device ID '$SearchText' not found in Entra ID: $_"
                    $AADDevice = $null
                }

                if ($AADDevice) {
                    $AADCount++
                    # Cross-reference Intune by azureADDeviceId for accurate matching
                    $IntuneDevice = $null
                    if ($AADDevice.deviceId) {
                        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=azureADDeviceId eq '$($AADDevice.deviceId)'&`$select=id,deviceName,serialNumber,operatingSystem,userDisplayName,lastSyncDateTime,azureADDeviceId,complianceState,managementAgent"
                        $IntuneDevice = (Get-GraphPagedResults -Uri $uri) | Select-Object -First 1
                        if ($IntuneDevice) { $IntuneCount++ }
                    }

                    # Cross-reference Autopilot by serial from physicalIds
                    $AutopilotDevice = $null
                    $serialFromPhysicalIds = $null
                    if ($AADDevice.physicalIds) {
                        foreach ($physicalId in $AADDevice.physicalIds) {
                            if ($physicalId -match '\[SerialNumber\]:(.+)') {
                                $serialFromPhysicalIds = $matches[1].Trim()
                                break
                            }
                        }
                    }
                    $serial = $IntuneDevice?.serialNumber ?? $serialFromPhysicalIds
                    if ($serial) {
                        $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$(ConvertTo-ODataStringValue -Value $serial)')"
                        $AutopilotDevice = (Get-GraphPagedResults -Uri $uri) | Select-Object -First 1
                        if ($AutopilotDevice) { $AutopilotCount++ }
                    }

                    $CombinedDevice = New-Object DeviceObject
                    $CombinedDevice.IsSelected = $false
                    $CombinedDevice.DeviceName = $AADDevice.displayName
                    $CombinedDevice.SerialNumber = $serial
                    $CombinedDevice.OperatingSystem = $AADDevice.operatingSystem
                    $CombinedDevice.PrimaryUser = $IntuneDevice?.userDisplayName
                    $CombinedDevice.AzureADLastContact = ConvertTo-SafeDateTime -dateString $AADDevice.approximateLastSignInDateTime
                    $CombinedDevice.IntuneLastContact = ConvertTo-SafeDateTime -dateString $IntuneDevice?.lastSyncDateTime
                    $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $AutopilotDevice?.lastContactedDateTime
                    $CombinedDevice.EntraDeviceId = $AADDevice.id
                    $CombinedDevice.EntraDeviceObjectId = $AADDevice.deviceId
                    $CombinedDevice.IntuneDeviceId = $IntuneDevice?.id
                    $CombinedDevice.AutopilotIdentityId = $AutopilotDevice?.id
                    $CombinedDevice.EntraAccountEnabled = if ($null -ne $AADDevice.accountEnabled) { $AADDevice.accountEnabled.ToString() } else { $null }
                    $CombinedDevice.ComplianceState = $IntuneDevice?.complianceState
                    $CombinedDevice.ManagementAgent = $IntuneDevice?.managementAgent

                    $searchResults.Add($CombinedDevice)
                }
                else {
                    Write-Log "No device found with ID: $SearchText"
                }
            }
            elseif ($SearchOption -eq "Contains (partial match)") {
                # Batch Entra (startsWith) + Intune (contains) queries.
                # NOTE: Intune managedDevices supports contains() on deviceName but NOT on serialNumber.
                # Combining them with 'or' makes the whole filter return zero rows (the unsupported clause
                # poisons the query), so we only filter on deviceName here. Partial serial matches are still
                # covered client-side for Autopilot below, and exact serials via the "Serial Number" search.
                $batchRequests = @(
                    @{ id = "entra"; method = "GET"; url = "/devices?`$filter=startsWith(displayName,'$escapedSearchText')&`$select=id,deviceId,displayName,operatingSystem,approximateLastSignInDateTime,accountEnabled,physicalIds&`$count=true"; headers = @{ "ConsistencyLevel" = "eventual" } }
                    @{ id = "intune"; method = "GET"; url = "/deviceManagement/managedDevices?`$filter=contains(deviceName,'$escapedSearchText')&`$select=id,deviceName,serialNumber,operatingSystem,userDisplayName,lastSyncDateTime,azureADDeviceId,complianceState,managementAgent" }
                )
                $batchResponses = Invoke-GraphBatchRequest -Requests $batchRequests
                $entraResp = $batchResponses | Where-Object { $_.id -eq "entra" }
                $intuneResp = $batchResponses | Where-Object { $_.id -eq "intune" }
                $AADDevices = if ($entraResp -and $entraResp.status -eq 200 -and $entraResp.body.value) { $entraResp.body.value } else { @() }
                $IntuneDevices = if ($intuneResp -and $intuneResp.status -eq 200 -and $intuneResp.body.value) { $intuneResp.body.value } else { @() }

                # Pre-fetch Autopilot devices for client-side filtering
                $AutopilotDevices = @()
                try {
                    $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
                    $allAutopilot = Get-GraphPagedResults -Uri $uri
                    $AutopilotDevices = $allAutopilot | Where-Object { $_.displayName -and $_.displayName -like "*$SearchText*" }
                } catch {
                    Write-Log "Error fetching Autopilot devices for partial match: $_"
                }

                # Process Entra ID devices
                if ($AADDevices) {
                    foreach ($AADDevice in $AADDevices) {
                        $matchingIntuneDevice = $IntuneDevices | Where-Object { $_.deviceName -eq $AADDevice.displayName } | Select-Object -First 1
                        $matchingAutopilotDevice = $AutopilotDevices | Where-Object { $_.displayName -eq $AADDevice.displayName } | Select-Object -First 1

                        if (-not $matchingAutopilotDevice -and $matchingIntuneDevice -and $matchingIntuneDevice.serialNumber) {
                            $matchingAutopilotDevice = $AutopilotDevices | Where-Object { $_.serialNumber -eq $matchingIntuneDevice.serialNumber } | Select-Object -First 1
                        }

                        $CombinedDevice = New-Object DeviceObject
                        $CombinedDevice.IsSelected = $false
                        $CombinedDevice.DeviceName = $AADDevice.displayName
                        $CombinedDevice.SerialNumber = $matchingIntuneDevice?.serialNumber ?? $matchingAutopilotDevice?.serialNumber
                        if (-not $CombinedDevice.SerialNumber -and $AADDevice.physicalIds) {
                            foreach ($physicalId in $AADDevice.physicalIds) {
                                if ($physicalId -match '\[SerialNumber\]:(.+)') {
                                    $CombinedDevice.SerialNumber = $matches[1].Trim()
                                    break
                                }
                            }
                        }
                        $CombinedDevice.OperatingSystem = $AADDevice.operatingSystem
                        $CombinedDevice.PrimaryUser = $matchingIntuneDevice?.userDisplayName
                        $CombinedDevice.AzureADLastContact = ConvertTo-SafeDateTime -dateString $AADDevice.approximateLastSignInDateTime
                        $CombinedDevice.IntuneLastContact = ConvertTo-SafeDateTime -dateString $matchingIntuneDevice.lastSyncDateTime
                        $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $matchingAutopilotDevice.lastContactedDateTime
                        $CombinedDevice.EntraDeviceId = $AADDevice.id
                        $CombinedDevice.EntraDeviceObjectId = $AADDevice.deviceId
                        $CombinedDevice.IntuneDeviceId = $matchingIntuneDevice?.id
                        $CombinedDevice.AutopilotIdentityId = $matchingAutopilotDevice?.id
                        $CombinedDevice.EntraAccountEnabled = if ($null -ne $AADDevice.accountEnabled) { $AADDevice.accountEnabled.ToString() } else { $null }
                        $CombinedDevice.ComplianceState = $matchingIntuneDevice?.complianceState
                        $CombinedDevice.ManagementAgent = $matchingIntuneDevice?.managementAgent

                        $searchResults.Add($CombinedDevice)
                        $AADCount++
                        if ($matchingIntuneDevice) { $IntuneCount++ }
                        if ($matchingAutopilotDevice) { $AutopilotCount++ }
                    }
                }

                # Process Intune devices not in Entra ID results
                if ($IntuneDevices) {
                    foreach ($IntuneDevice in $IntuneDevices) {
                        if ($searchResults | Where-Object { $_.DeviceName -eq $IntuneDevice.deviceName }) {
                            continue
                        }
                        $matchingAutopilotDevice = $AutopilotDevices | Where-Object { $_.displayName -eq $IntuneDevice.deviceName } | Select-Object -First 1
                        if (-not $matchingAutopilotDevice -and $IntuneDevice.serialNumber) {
                            $matchingAutopilotDevice = $AutopilotDevices | Where-Object { $_.serialNumber -eq $IntuneDevice.serialNumber } | Select-Object -First 1
                        }

                        $CombinedDevice = New-Object DeviceObject
                        $CombinedDevice.IsSelected = $false
                        $CombinedDevice.DeviceName = $IntuneDevice.deviceName
                        $CombinedDevice.SerialNumber = $IntuneDevice.serialNumber ?? $matchingAutopilotDevice?.serialNumber
                        $CombinedDevice.OperatingSystem = $IntuneDevice.operatingSystem
                        $CombinedDevice.PrimaryUser = $IntuneDevice.userDisplayName
                        $CombinedDevice.IntuneLastContact = ConvertTo-SafeDateTime -dateString $IntuneDevice.lastSyncDateTime
                        $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $matchingAutopilotDevice.lastContactedDateTime
                        $CombinedDevice.IntuneDeviceId = $IntuneDevice.id
                        $CombinedDevice.AutopilotIdentityId = $matchingAutopilotDevice?.id
                        $CombinedDevice.ComplianceState = $IntuneDevice.complianceState
                        $CombinedDevice.ManagementAgent = $IntuneDevice.managementAgent

                        $searchResults.Add($CombinedDevice)
                        $IntuneCount++
                        if ($matchingAutopilotDevice) { $AutopilotCount++ }
                    }
                }

                # Process Autopilot-only devices
                if ($AutopilotDevices) {
                    foreach ($AutopilotDevice in $AutopilotDevices) {
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
                        $CombinedDevice.AutopilotIdentityId = $AutopilotDevice.id

                        $searchResults.Add($CombinedDevice)
                        $AutopilotCount++
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

        if ($searchResults.Count -gt 0) {
            $script:AllSearchResults = $searchResults
            $SearchResultsDataGrid.ItemsSource = $searchResults
            $script:LastCheckedIndex = -1
            $ResultCountText.Text = "$($searchResults.Count) device(s) found"
            $SearchEmptyState.Visibility = 'Collapsed'
            $SearchResultsDataGrid.Visibility = 'Visible'
        }
        else {
            $script:AllSearchResults = $null
            $SearchResultsDataGrid.ItemsSource = $null
            $FilterRow.Visibility = 'Collapsed'
            $ResultCountText.Text = ""
            $SearchEmptyState.Visibility = 'Visible'
            $SearchResultsDataGrid.Visibility = 'Collapsed'
            Show-Toast -Message "No devices found matching the search criteria." -Type "info"
        }

        # Ensure Offboard button and Export Selected button are disabled until selection
        $OffboardButton.IsEnabled = $false
        $ExportSelectedButton.IsEnabled = $false
        $SetGroupTagButton.IsEnabled = $false
        $OffboardPanel.Visibility = 'Collapsed'
    }
    catch {
        Write-Log "Error occurred during search operation. Exception: $_"
        Show-Toast -Message "Error in search operation. Please ensure the Serial Number or Device Name is valid." -Type "error" -DurationSeconds 6
    }
}

# Connect to Controls
$SearchButton = $Window.FindName("SearchButton")
$OffboardButton = $Window.FindName("OffboardButton")
$ExportSelectedButton = $Window.FindName("ExportSelectedButton")
$SetGroupTagButton = $Window.FindName("SetGroupTagButton")
$AuthenticateButton = $Window.FindName("AuthenticateButton")
$SearchInputText = $Window.FindName("SearchInputText")
$bulk_import_button = $Window.FindName('bulk_import_button')
$Dropdown = $Window.FindName("dropdown")
$Disconnect = $Window.FindName('disconnect_button')

# Toast notification controls
$ToastNotification = $Window.FindName('ToastNotification')
$ToastMessage = $Window.FindName('ToastMessage')
$ToastDismissButton = $Window.FindName('ToastDismissButton')

# Sidebar controls
$SidebarToggleButton = $Window.FindName('SidebarToggleButton')
$SidebarTopContent = $Window.FindName('SidebarTopContent')
$SidebarBottomContent = $Window.FindName('SidebarBottomContent')
$SidebarCenterContent = $Window.FindName('SidebarCenterContent')
$SidebarColumn = $Window.Content.ColumnDefinitions[0]
$CollapsedStatusDot = $Window.FindName('CollapsedStatusDot')
$script:SidebarCollapsed = $false

$script:ToastGeneration = 0
$script:ToastHideGeneration = 0

# NOTE (Issue #64): toast handlers must be plain scriptblocks. GetNewClosure() binds a
# scriptblock to a dynamic module that cannot resolve script-scope functions on Windows
# PowerShell 5.1 ('Hide-Toast' is not recognized) and reads $script: variables as frozen
# snapshots instead of live values. Plain scriptblocks stay bound to the script session
# state; GetNewClosure() is only for capturing per-invocation locals.
function Hide-Toast {
    $script:ToastGeneration++
    $script:ToastHideGeneration = $script:ToastGeneration
    if ($script:ToastTimer) { $script:ToastTimer.Stop() }
    # Clear current animation hold and read actual position
    $ToastNotification.RenderTransform.BeginAnimation(
        [System.Windows.Media.TranslateTransform]::YProperty, $null)
    $currentY = $ToastNotification.RenderTransform.Y
    # Slide out animation
    $slideOut = New-Object System.Windows.Media.Animation.DoubleAnimation
    $slideOut.From = $currentY
    $slideOut.To = -50
    $slideOut.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(200))
    $slideOut.EasingFunction = New-Object System.Windows.Media.Animation.QuadraticEase
    $slideOut.EasingFunction.EasingMode = 'EaseIn'
    $slideOut.Add_Completed({ if ($script:ToastGeneration -eq $script:ToastHideGeneration) { $ToastNotification.Visibility = 'Collapsed' } })
    $ToastNotification.RenderTransform.BeginAnimation(
        [System.Windows.Media.TranslateTransform]::YProperty, $slideOut)
}

function Show-Toast {
    param(
        [string]$Message,
        [ValidateSet('success','error','info')][string]$Type = 'info',
        [int]$DurationSeconds = 4
    )
    $script:ToastGeneration++
    if ($script:ToastTimer) { $script:ToastTimer.Stop() }
    $bgColor = switch ($Type) {
        'success' { '#2F855A' }
        'error'   { '#C53030' }
        'info'    { '#2B6CB0' }
    }
    $ToastNotification.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($bgColor)
    $ToastMessage.Text = $Message
    # Reset transform and make visible
    $ToastNotification.RenderTransform = New-Object System.Windows.Media.TranslateTransform(0, -50)
    $ToastNotification.Visibility = 'Visible'
    # Slide in animation
    $slideIn = New-Object System.Windows.Media.Animation.DoubleAnimation
    $slideIn.From = -50
    $slideIn.To = 0
    $slideIn.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(250))
    $slideIn.EasingFunction = New-Object System.Windows.Media.Animation.QuadraticEase
    $slideIn.EasingFunction.EasingMode = 'EaseOut'
    $ToastNotification.RenderTransform.BeginAnimation(
        [System.Windows.Media.TranslateTransform]::YProperty, $slideIn)
    # Auto-dismiss timer
    $script:ToastTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:ToastTimer.Interval = [TimeSpan]::FromSeconds($DurationSeconds)
    $script:ToastTimer.Add_Tick({ Hide-Toast })
    $script:ToastTimer.Start()
}

$ToastDismissButton.Add_Click({ Hide-Toast })

function Set-SidebarState {
    param([bool]$Collapsed)
    $script:SidebarCollapsed = $Collapsed
    if ($Collapsed) {
        $SidebarColumn.Width = [System.Windows.GridLength]::new(48)
        $SidebarToggleButton.Content = ">>"
        $SidebarToggleButton.HorizontalAlignment = 'Center'
        $SidebarToggleButton.ToolTip = "Expand sidebar (Ctrl+B)"
        $SidebarTopContent.Visibility = 'Collapsed'
        $SidebarBottomContent.Visibility = 'Collapsed'
        $SidebarCenterContent.Visibility = 'Collapsed'
        # Show collapsed connection status dot (sync color from main dot)
        $CollapsedStatusDot.Fill = $ConnectionStatusDot.Fill
        $CollapsedStatusDot.ToolTip = $ConnectionStatusDot.ToolTip
        $CollapsedStatusDot.Visibility = 'Visible'
    } else {
        $SidebarColumn.Width = [System.Windows.GridLength]::new(200)
        $SidebarToggleButton.Content = "<<"
        $SidebarToggleButton.HorizontalAlignment = 'Right'
        $SidebarToggleButton.ToolTip = "Collapse sidebar (Ctrl+B)"
        $SidebarTopContent.Visibility = 'Visible'
        $SidebarBottomContent.Visibility = 'Visible'
        $SidebarCenterContent.Visibility = 'Visible'
        $CollapsedStatusDot.Visibility = 'Collapsed'
    }
}

$SidebarToggleButton.Add_Click({
    Set-SidebarState -Collapsed (-not $script:SidebarCollapsed)
})
$logs_button = $Window.FindName('logs_button')
$PrerequisitesButton = $Window.FindName('PrerequisitesButton')
$FeedbackLink = $Window.FindName('FeedbackLink')
$FilterRow = $Window.FindName('FilterRow')
$FilterDeviceName = $Window.FindName('FilterDeviceName')
$FilterSerialNumber = $Window.FindName('FilterSerialNumber')
$FilterOS = $Window.FindName('FilterOS')
$FilterPrimaryUser = $Window.FindName('FilterPrimaryUser')
$FilterCompliance = $Window.FindName('FilterCompliance')
$SearchResultsDataGrid = $Window.FindName('SearchResultsDataGrid')
$ConnectionStatusDot = $Window.FindName('ConnectionStatusDot')
$SearchPlaceholder = $Window.FindName('SearchPlaceholder')
$ResultCountText = $Window.FindName('ResultCountText')
$FilterToggleButton = $Window.FindName('FilterToggleButton')
$ClearSearchButton = $Window.FindName('ClearSearchButton')
$SearchEmptyState = $Window.FindName('SearchEmptyState')
$OffboardPanel = $Window.FindName('OffboardPanel')
$SelectedDeviceCount = $Window.FindName('SelectedDeviceCount')

# Grid filter function
function Update-DeviceFilter {
    if (-not $script:AllSearchResults) { return }
    $filtered = $script:AllSearchResults
    $nameFilter = $FilterDeviceName.Text
    $serialFilter = $FilterSerialNumber.Text
    $osFilter = $FilterOS.Text
    $userFilter = $FilterPrimaryUser.Text
    $compFilter = $FilterCompliance.Text
    if ($nameFilter) { $filtered = $filtered | Where-Object { $_.DeviceName -like "*$nameFilter*" } }
    if ($serialFilter) { $filtered = $filtered | Where-Object { $_.SerialNumber -like "*$serialFilter*" } }
    if ($osFilter) { $filtered = $filtered | Where-Object { $_.OperatingSystem -like "*$osFilter*" } }
    if ($userFilter) { $filtered = $filtered | Where-Object { $_.PrimaryUser -like "*$userFilter*" } }
    if ($compFilter) { $filtered = $filtered | Where-Object { $_.ComplianceState -like "*$compFilter*" } }
    $SearchResultsDataGrid.ItemsSource = @($filtered)
    $script:LastCheckedIndex = -1
}

# Wire filter TextChanged events
$FilterDeviceName.Add_TextChanged({ Update-DeviceFilter })
$FilterSerialNumber.Add_TextChanged({ Update-DeviceFilter })
$FilterOS.Add_TextChanged({ Update-DeviceFilter })
$FilterPrimaryUser.Add_TextChanged({ Update-DeviceFilter })
$FilterCompliance.Add_TextChanged({ Update-DeviceFilter })

# Search placeholder visibility
$SearchInputText.Add_GotFocus({ $SearchPlaceholder.Visibility = 'Collapsed' })
$SearchInputText.Add_LostFocus({
        if ([string]::IsNullOrEmpty($SearchInputText.Text)) {
            $SearchPlaceholder.Visibility = 'Visible'
        }
    })
$SearchInputText.Add_TextChanged({
        if ([string]::IsNullOrEmpty($SearchInputText.Text)) {
            $SearchPlaceholder.Visibility = 'Visible'
        } else {
            $SearchPlaceholder.Visibility = 'Collapsed'
        }
    })

# Filter Toggle button
$FilterToggleButton.Add_Click({
        if ($FilterRow.Visibility -eq 'Visible') {
            $FilterRow.Visibility = 'Collapsed'
            $FilterToggleButton.Content = 'Filter'
        } else {
            $FilterRow.Visibility = 'Visible'
            $FilterToggleButton.Content = 'Hide Filter'
        }
    })

# Clear Search button
$ClearSearchButton.Add_Click({
        $SearchInputText.Text = ''
        $SearchResultsDataGrid.ItemsSource = $null
        $script:AllSearchResults = $null
        $FilterRow.Visibility = 'Collapsed'
        $FilterToggleButton.Content = 'Filter'
        $FilterDeviceName.Text = ''
        $FilterSerialNumber.Text = ''
        $FilterOS.Text = ''
        $FilterPrimaryUser.Text = ''
        $FilterCompliance.Text = ''
        $ResultCountText.Text = ''
        $SearchEmptyState.Visibility = 'Visible'
        $SearchResultsDataGrid.Visibility = 'Collapsed'
        $OffboardPanel.Visibility = 'Collapsed'
        $OffboardButton.IsEnabled = $false
        $ExportSelectedButton.IsEnabled = $false
        $SetGroupTagButton.IsEnabled = $false
        $Window.FindName('intune_status').Text = 'Intune'
        $Window.FindName('autopilot_status').Text = 'Autopilot'
        $Window.FindName('aad_status').Text = 'Entra ID'
        $SearchInputText.Focus()
    })

# Shift-click range selection
$script:LastCheckedIndex = -1
$SearchResultsDataGrid.Add_PreviewMouseLeftButtonDown({
        param($sender, $e)
        $source = $e.OriginalSource
        # Walk up to find CheckBox
        $element = $source
        $isCheckBox = $false
        while ($element -ne $null) {
            if ($element -is [System.Windows.Controls.CheckBox]) {
                $isCheckBox = $true
                break
            }
            if ($element -is [System.Windows.Controls.DataGridRow]) { break }
            $element = [System.Windows.Media.VisualTreeHelper]::GetParent($element)
        }
        if (-not $isCheckBox) { return }

        # Find the DataGridRow
        $row = $source
        while ($row -ne $null -and $row -isnot [System.Windows.Controls.DataGridRow]) {
            $row = [System.Windows.Media.VisualTreeHelper]::GetParent($row)
        }
        if (-not $row) { return }
        $currentIndex = $SearchResultsDataGrid.ItemContainerGenerator.IndexFromContainer($row)
        if ($currentIndex -lt 0) { return }

        if ([System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::LeftShift) -or
            [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::RightShift)) {
            if ($script:LastCheckedIndex -ge 0) {
                $start = [Math]::Min($script:LastCheckedIndex, $currentIndex)
                $end = [Math]::Max($script:LastCheckedIndex, $currentIndex)
                $items = $SearchResultsDataGrid.ItemsSource
                $targetState = -not $items[$currentIndex].IsSelected
                for ($i = $start; $i -le $end; $i++) {
                    $items[$i].IsSelected = $targetState
                }
                $e.Handled = $true
            }
        }
        $script:LastCheckedIndex = $currentIndex
    })

# Add feedback link handler
$FeedbackLink.Add_Click({
        Start-Process "https://github.com/ugurkocde/DeviceOffboardingManager/issues"
    })

$SearchInputText.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Return) {
            $e.Handled = $true
            $SearchButton.RaiseEvent(
                (New-Object System.Windows.RoutedEventArgs(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        }
    })
    
$Window.Add_Loaded({
        $Dropdown.Items.Add("Device Name")
        $Dropdown.Items.Add("Serial Number")
        $Dropdown.Items.Add("Device ID")
        $Dropdown.Items.Add("Contains (partial match)")
        $Dropdown.SelectedIndex = 0
    })

# Update search placeholder text based on dropdown selection
$Dropdown.Add_SelectionChanged({
        $placeholderText = switch ($Dropdown.SelectedItem) {
            "Device Name"              { "Enter device name (e.g., DESKTOP-ABC123)..." }
            "Serial Number"            { "Enter serial number (e.g., 1234567890)..." }
            "Device ID"                { "Enter Intune device ID (GUID)..." }
            "Contains (partial match)" { "Enter partial name or serial (comma-separated)..." }
            default                    { "Enter device name, serial number, or ID..." }
        }
        $SearchPlaceholder.Text = $placeholderText
    })

$Window.Add_Loaded({
        try {
            Write-Log "Window is loading..."
    
            $context = Get-MgGraphCommunityContext
    
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
                $HomeNavDashboard.IsEnabled = $false
                $HomeNavDeviceMgmt.IsEnabled = $false
                $HomeNavPlaybooks.IsEnabled = $false
                Update-HomePageState -Connected $false

                # Force Home menu selection
                $MenuHome.IsChecked = $true
            }
            else {
                Write-Log "Successfully connected to MS Graph"
                # Capture admin identity for audit logging on existing connection
                if ($context.Account) {
                    $script:AdminUPN = $context.Account
                } else {
                    $script:AdminUPN = "AppId:$($context.ClientId)"
                }
                $AuthenticateButton.Content = "Successfully connected"
                $AuthenticateButton.IsEnabled = $false
                $Disconnect.IsEnabled = $true
                $PrerequisitesButton.IsEnabled = $true
                $ConnectionStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#48BB78')
                $ConnectionStatusDot.ToolTip = "Connected"
                $CollapsedStatusDot.Fill = $ConnectionStatusDot.Fill
                $CollapsedStatusDot.ToolTip = "Connected"

                # Enable navigation menus
                $MenuDashboard.IsEnabled = $true
                $MenuDeviceManagement.IsEnabled = $true
                $MenuPlaybooks.IsEnabled = $true
                $HomeNavDashboard.IsEnabled = $true
                $HomeNavDeviceMgmt.IsEnabled = $true
                $HomeNavPlaybooks.IsEnabled = $true
                Update-HomePageState -Connected $true

                # Get tenant details for existing connection
                try {
                    Write-Log "Retrieving tenant information for existing connection..."
                    $tenantInfo = Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/organization?`$select=displayName,id,verifiedDomains" -Method GET
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
                    Show-Toast -Message "Missing permissions: $missingList" -Type "info" -DurationSeconds 6
                }
            }

            # Update version displays
            Update-VersionDisplays -window $Window
            Write-Log "Version displays updated"

            # If already connected on launch, navigate to Dashboard
            if ($null -ne (Get-MgGraphCommunityContext)) {
                $MenuDashboard.IsChecked = $true
            }
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
            $HomeNavDashboard.IsEnabled = $false
            $HomeNavDeviceMgmt.IsEnabled = $false
            $HomeNavPlaybooks.IsEnabled = $false
            Update-HomePageState -Connected $false
        }
    })
    
$Disconnect.Add_Click({
        try {
            Write-Log "Attempting to disconnect from MS Graph..."
            
            # Disconnect from Graph
            Disconnect-MgGraphCommunity -ErrorAction Stop
            if ($script:CurrentAuthDetails -and $script:CurrentAuthDetails.SecretSecureString) {
                $script:CurrentAuthDetails.SecretSecureString.Dispose()
            }
            $script:CurrentAuthDetails = $null

            # Reset UI state
            $Disconnect.Content = "Disconnected"
            $Disconnect.IsEnabled = $false
            $AuthenticateButton.Content = "Connect to MS Graph"
            $AuthenticateButton.IsEnabled = $true
            $PrerequisitesButton.IsEnabled = $true
            $ConnectionStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FC8181')
            $ConnectionStatusDot.ToolTip = "Disconnected"
            $CollapsedStatusDot.Fill = $ConnectionStatusDot.Fill
            $CollapsedStatusDot.ToolTip = "Disconnected"

            # Hide tenant info
            $Window.FindName('TenantInfoSection').Visibility = 'Collapsed'
            $Window.FindName('TenantDisplayName').Text = ""
            $Window.FindName('TenantId').Text = ""
            $Window.FindName('TenantDomain').Text = ""
            
            # Disable navigation menus and force Home selection
            $MenuDashboard.IsEnabled = $false
            $MenuDeviceManagement.IsEnabled = $false
            $MenuPlaybooks.IsEnabled = $false
            $HomeNavDashboard.IsEnabled = $false
            $HomeNavDeviceMgmt.IsEnabled = $false
            $HomeNavPlaybooks.IsEnabled = $false
            Update-HomePageState -Connected $false
            $MenuHome.IsChecked = $true

            # Clear any sensitive data from the dashboard
            $Window.FindName('IntuneDevicesCount').Text = "--"
            $Window.FindName('AutopilotDevicesCount').Text = "--"
            $Window.FindName('EntraIDDevicesCount').Text = "--"
            $Window.FindName('StaleDevices30Count').Text = "--"
            $Window.FindName('StaleDevices90Count').Text = "--"
            $Window.FindName('StaleDevices180Count').Text = "--"
            $Window.FindName('PersonalDevicesCount').Text = "--"
            $Window.FindName('CorporateDevicesCount').Text = "--"
            $Window.FindName('DashboardLastRefreshed').Text = ""
            
            Write-Log "Successfully disconnected from MS Graph"
        }
        catch {
            if ($script:CurrentAuthDetails -and $script:CurrentAuthDetails.SecretSecureString) {
                $script:CurrentAuthDetails.SecretSecureString.Dispose()
            }
            $script:CurrentAuthDetails = $null
            Write-Log "Error occurred while attempting to disconnect from MS Graph: $_"
            Show-Toast -Message "Error disconnecting from Microsoft Graph: $_" -Type "error" -DurationSeconds 6
        }
    })
    
$AuthenticateButton.Add_Click({
        try {
            # Check if already connected
            $context = Get-MgGraphCommunityContext
            if ($context) {
                Write-Log "Already connected to MS Graph, skipping authentication dialog"
                return
            }
            
            Write-Log "Authentication button clicked, showing authentication dialog..."
            
            # Reset the connection failed flag
            $script:connectionFailed = $false
        
            # Show authentication dialog
            $authDetails = Show-AuthenticationDialog
            if (-not $authDetails) {
                Write-Log "Authentication cancelled by user"
                # Reset button state if cancelled
                $AuthenticateButton.Content = "Connect to MS Graph"
                $AuthenticateButton.IsEnabled = $true
                return
            }

            # Set button to "Connecting..." state
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
                $ConnectionStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#48BB78')
                $ConnectionStatusDot.ToolTip = "Connected"
                $CollapsedStatusDot.Fill = $ConnectionStatusDot.Fill
                $CollapsedStatusDot.ToolTip = "Connected"

                # Enable navigation menus
                $MenuDashboard.IsEnabled = $true
                $MenuDeviceManagement.IsEnabled = $true
                $MenuPlaybooks.IsEnabled = $true
                $HomeNavDashboard.IsEnabled = $true
                $HomeNavDeviceMgmt.IsEnabled = $true
                $HomeNavPlaybooks.IsEnabled = $true
                Update-HomePageState -Connected $true
            }
            else {
                # Reset button state on failed connection
                Write-Log "Authentication Failed"
                if ($script:CurrentAuthDetails -and $script:CurrentAuthDetails.SecretSecureString) {
                    $script:CurrentAuthDetails.SecretSecureString.Dispose()
                }
                $script:CurrentAuthDetails = $null
                $AuthenticateButton.Content = "Connect to MS Graph"
                $AuthenticateButton.IsEnabled = $true
                $Disconnect.Content = "Disconnected"
                $Disconnect.IsEnabled = $false
                $ConnectionStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FC8181')
                $ConnectionStatusDot.ToolTip = "Disconnected"
                $CollapsedStatusDot.Fill = $ConnectionStatusDot.Fill
                $CollapsedStatusDot.ToolTip = "Disconnected"

                # Disable navigation menus
                $MenuDashboard.IsEnabled = $false
                $MenuDeviceManagement.IsEnabled = $false
                $MenuPlaybooks.IsEnabled = $false
                $HomeNavDashboard.IsEnabled = $false
                $HomeNavDeviceMgmt.IsEnabled = $false
                $HomeNavPlaybooks.IsEnabled = $false
                Update-HomePageState -Connected $false

                # Hide tenant info
                $Window.FindName('TenantInfoSection').Visibility = 'Collapsed'
                $Window.FindName('TenantDisplayName').Text = ""
                $Window.FindName('TenantId').Text = ""
                $Window.FindName('TenantDomain').Text = ""
            }
        }
        catch {
            Write-Log "Error occurred during authentication. Exception: $_"
            if ($script:CurrentAuthDetails -and $script:CurrentAuthDetails.SecretSecureString) {
                $script:CurrentAuthDetails.SecretSecureString.Dispose()
            }
            $script:CurrentAuthDetails = $null
            # Reset button state on error
            $AuthenticateButton.Content = "Connect to MS Graph"
            $AuthenticateButton.IsEnabled = $true
            $Disconnect.Content = "Disconnected"
            $Disconnect.IsEnabled = $false
            
            # Disable navigation menus
            $MenuDashboard.IsEnabled = $false
            $MenuDeviceManagement.IsEnabled = $false
            $MenuPlaybooks.IsEnabled = $false
            Update-HomePageState -Connected $false

            # Hide tenant info
            $Window.FindName('TenantInfoSection').Visibility = 'Collapsed'
            $Window.FindName('TenantDisplayName').Text = ""
            $Window.FindName('TenantId').Text = ""
            $Window.FindName('TenantDomain').Text = ""
            
            Show-Toast -Message "Authentication failed: $_" -Type "error" -DurationSeconds 6
        }
    })
    

$SearchButton.Add_Click({
        if ($AuthenticateButton.IsEnabled) {
            Write-Log "User is not connected to MS Graph. Attempted search operation."
            Show-Toast -Message "You are not connected to MS Graph. Please connect first." -Type "info"
            return
        }

        try {
            # Trim the input and split by comma
            $searchInput = $SearchInputText.Text.Trim()
            $SearchTexts = $searchInput -split ', ' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

            if ($SearchTexts.Count -eq 0) {
                Show-Toast -Message "Please enter at least one device name or serial number." -Type "info"
                return
            }

            # Show searching state
            $SearchButton.Content = "Searching..."
            $SearchButton.IsEnabled = $false
            $Window.Cursor = [System.Windows.Input.Cursors]::Wait
            $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action]{})

            Write-Log "Searching for devices: $SearchTexts"
            $searchOption = $Dropdown.SelectedItem

            # Call the centralized search function
            Invoke-DeviceSearch -SearchTexts $SearchTexts -SearchOption $searchOption
        }
        catch {
            Write-Log "Error occurred during search operation. Exception: $_"
            Show-Toast -Message "Error in search operation. Please ensure the Serial Number or Device Name is valid." -Type "error" -DurationSeconds 6
        }
        finally {
            $SearchButton.Content = "Search"
            $SearchButton.IsEnabled = $true
            $Window.Cursor = $null
        }
    })
    
        
$bulk_import_button.Add_Click({
        if ($AuthenticateButton.IsEnabled) {
            Write-Log "User is not connected to MS Graph. Attempted bulk import operation."
            Show-Toast -Message "You are not connected to MS Graph. Please connect first." -Type "info"
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
                Invoke-DeviceSearch -SearchTexts $devices -SearchOption $searchOption
            }
            else {
                Write-Log "Bulk import cancelled or no devices imported"
            }
        }
        catch {
            Write-Log "Exception in bulk import: $_"
            Show-Toast -Message "Error in bulk import operation: $_" -Type "error" -DurationSeconds 6
        }
    })

$OffboardButton.Add_Click({
        if ($AuthenticateButton.IsEnabled) {
            Write-Log "User is not connected to MS Graph. Attempted offboarding operation."
            Show-Toast -Message "You are not connected to MS Graph. Please connect first." -Type "info"
            return
        }

        $selectedDevices = $SearchResultsDataGrid.ItemsSource | Where-Object { $_.IsSelected }

        if (-not $selectedDevices) {
            Show-Toast -Message "Please select at least one device to offboard." -Type "info"
            return
        }

        # Resolve missing IDs for selected devices before showing confirmation
        foreach ($device in $selectedDevices) {
            try {
                # If we have a device name but no Entra ID, try to resolve it
                if ($device.DeviceName -and -not $device.EntraDeviceId) {
                    $uri = "https://graph.microsoft.com/beta/devices?`$filter=displayName eq '$(ConvertTo-ODataStringValue -Value $device.DeviceName)'"
                    $entraDevices = Get-GraphPagedResults -Uri $uri
                    if ($entraDevices -and @($entraDevices).Count -eq 1) {
                        $entraDevice = $entraDevices | Select-Object -First 1
                        $device.EntraDeviceId = $entraDevice.id
                        $device.EntraDeviceObjectId = $entraDevice.deviceId
                        $device.EntraAccountEnabled = if ($null -ne $entraDevice.accountEnabled) { $entraDevice.accountEnabled.ToString() } else { $null }
                    }
                    elseif ($entraDevices -and @($entraDevices).Count -gt 1) {
                        Write-Log "Multiple Entra ID devices found for name '$($device.DeviceName)' - skipping auto-resolution to prevent wrong-device match" -Severity "WARN"
                    }
                }
                # If we have a device name but no Intune ID, try to resolve it
                if ($device.DeviceName -and -not $device.IntuneDeviceId) {
                    $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=deviceName eq '$(ConvertTo-ODataStringValue -Value $device.DeviceName)'"
                    $intuneDevices = Get-GraphPagedResults -Uri $uri
                    if ($intuneDevices -and @($intuneDevices).Count -eq 1) {
                        $device.IntuneDeviceId = ($intuneDevices | Select-Object -First 1).id
                    }
                    elseif ($intuneDevices -and @($intuneDevices).Count -gt 1) {
                        Write-Log "Multiple Intune devices found for name '$($device.DeviceName)' - skipping auto-resolution to prevent wrong-device match" -Severity "WARN"
                    }
                }
                # If we have a serial number but no Autopilot ID, try to resolve it
                if ($device.SerialNumber -and -not $device.AutopilotIdentityId) {
                    $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$(ConvertTo-ODataStringValue -Value $device.SerialNumber)')"
                    $autopilotDevice = (Get-GraphPagedResults -Uri $uri) | Select-Object -First 1
                    if ($autopilotDevice) {
                        $device.AutopilotIdentityId = $autopilotDevice.id
                    }
                }
                Write-Log "Resolved IDs for $($device.DeviceName): Entra=$($device.EntraDeviceId), Intune=$($device.IntuneDeviceId), Autopilot=$($device.AutopilotIdentityId)"
            }
            catch {
                Write-Log "Error resolving IDs for device $($device.DeviceName): $_" -Severity "WARN"
            }
        }

        # Show confirmation modal
        [xml]$confirmationModalXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Confirm Device Offboarding" Height="800" Width="700" WindowStartupLocation="CenterScreen" Background="#F8F9FA">
    <Border Background="White" CornerRadius="8" Margin="16">
        <DockPanel Margin="24">
            <!-- Header -->
            <StackPanel DockPanel.Dock="Top" Margin="0,0,0,16">
                <TextBlock Text="Confirm Device Offboarding" FontSize="24" FontWeight="SemiBold" Foreground="#1A202C"/>
                <TextBlock x:Name="ConfirmSubtitle" Text="Select which services to offboard from" Foreground="#4A5568" FontSize="14" Margin="0,8,0,0"/>
            </StackPanel>

            <!-- Warning Message (Top, always visible) -->
            <Border DockPanel.Dock="Top" Background="#FEF2F2" BorderBrush="#FEE2E2" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,16">
                <StackPanel Orientation="Horizontal">
                    <Path Data="M12,2L1,21H23M12,6L19.53,19H4.47M11,10V13H13V10M11,15V17H13V15" Fill="#DC2626" Width="24" Height="24" Stretch="Uniform" Margin="0,0,12,0"/>
                    <TextBlock Text="This action cannot be undone. Devices will be removed or disabled from the selected services." Foreground="#DC2626" TextWrapping="Wrap" VerticalAlignment="Center" MaxWidth="400"/>
                </StackPanel>
            </Border>

            <!-- Action Buttons with Type-to-Confirm -->
            <StackPanel DockPanel.Dock="Bottom" Margin="0,16,0,0">
                <StackPanel Margin="0,0,0,12">
                    <TextBlock Text="Type OFFBOARD to confirm:" FontWeight="SemiBold" FontSize="13" Foreground="#DC2626" Margin="0,0,0,6"/>
                    <TextBox x:Name="ConfirmationTextBox" Height="36" Padding="12,8" FontSize="14" BorderBrush="#FEE2E2" BorderThickness="1" MaxWidth="300" HorizontalAlignment="Left"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button x:Name="CancelButton" Content="Cancel" Width="120" Height="40" Background="#F0F0F0" Foreground="#2D3748" BorderThickness="0" Margin="0,0,12,0" IsCancel="True" Cursor="Hand"/>
                    <Button x:Name="ConfirmButton" Content="Confirm Offboarding" Width="160" Height="40" Background="#DC2626" Foreground="White" BorderThickness="0" IsEnabled="False" Cursor="Hand"/>
                </StackPanel>
            </StackPanel>

            <!-- Main Content -->
            <StackPanel>
                <!-- Co-Management Warning Banner -->
                <Border x:Name="CoMgmtBanner" Background="#FFFBEB" BorderBrush="#FDE68A" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,16" Visibility="Collapsed">
                    <TextBlock Text="One or more devices are co-managed with Configuration Manager. Removing from Intune may disrupt SCCM management." Foreground="#92400E" TextWrapping="Wrap" FontSize="13"/>
                </Border>

                <!-- Pre-Offboarding Action -->
                <StackPanel Margin="0,0,0,16">
                    <TextBlock Text="Pre-Offboarding Action" FontWeight="SemiBold" FontSize="14" Margin="0,0,0,8"/>
                    <TextBlock Text="Optionally retire or wipe devices before deletion." Foreground="#718096" FontSize="12" Margin="0,0,0,8"/>
                    <ComboBox x:Name="PreActionComboBox" Width="250" HorizontalAlignment="Left" SelectedIndex="0">
                        <ComboBoxItem Content="Delete only (no pre-action)"/>
                        <ComboBoxItem Content="Retire then Delete"/>
                        <ComboBoxItem Content="Wipe then Delete"/>
                    </ComboBox>
                </StackPanel>

                <!-- Services List -->
                <WrapPanel x:Name="ServicesList" Margin="0,0,0,24" Orientation="Horizontal"/>

                <!-- Device Identity Preview -->
                <Border Background="#F0FFF4" BorderBrush="#C6F6D5" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,16" MaxHeight="200">
                    <Grid VerticalAlignment="Stretch">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <TextBlock Grid.Row="0" Text="Device Identity Preview" FontWeight="SemiBold" FontSize="14" Margin="0,0,0,8"/>
                        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" VerticalAlignment="Stretch">
                            <ItemsControl x:Name="DevicePreviewList">
                                <ItemsControl.ItemTemplate>
                                    <DataTemplate>
                                        <Border Background="White" BorderBrush="#E2E8F0" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                                            <StackPanel>
                                                <TextBlock FontWeight="SemiBold" Margin="0,0,0,4">
                                                    <Run Text="{Binding DeviceName, Mode=OneWay}"/>
                                                    <Run Text=" | " Foreground="#A0AEC0"/>
                                                    <Run Text="{Binding SerialText, Mode=OneWay}" Foreground="#718096"/>
                                                </TextBlock>
                                                <WrapPanel>
                                                    <TextBlock Margin="0,0,16,0" FontSize="11">
                                                        <Run Text="Entra: " FontWeight="Medium"/>
                                                        <Run Text="{Binding EntraIdText, Mode=OneWay}" Foreground="{Binding EntraIdColor, Mode=OneWay}"/>
                                                    </TextBlock>
                                                    <TextBlock Margin="0,0,16,0" FontSize="11">
                                                        <Run Text="Intune: " FontWeight="Medium"/>
                                                        <Run Text="{Binding IntuneIdText, Mode=OneWay}" Foreground="{Binding IntuneIdColor, Mode=OneWay}"/>
                                                    </TextBlock>
                                                    <TextBlock FontSize="11">
                                                        <Run Text="Autopilot: " FontWeight="Medium"/>
                                                        <Run Text="{Binding AutopilotIdText, Mode=OneWay}" Foreground="{Binding AutopilotIdColor, Mode=OneWay}"/>
                                                    </TextBlock>
                                                </WrapPanel>
                                            </StackPanel>
                                        </Border>
                                    </DataTemplate>
                                </ItemsControl.ItemTemplate>
                            </ItemsControl>
                        </ScrollViewer>
                    </Grid>
                </Border>

                <!-- Encryption Key Section -->
                <Border Background="#EDF2F7" BorderBrush="#E2E8F0" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,16" Height="300">
                    <Grid VerticalAlignment="Stretch">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        
                        <TextBlock Grid.Row="0" Text="Device Credentials &amp; Keys" FontWeight="SemiBold" FontSize="14" Margin="0,0,0,8"/>
                        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" VerticalAlignment="Stretch">
                            <ItemsControl x:Name="EncryptionKeysList">
                                <ItemsControl.ItemTemplate>
                                    <DataTemplate>
                                        <StackPanel Margin="0,0,0,24">
                                            <TextBlock Text="{Binding DeviceName}" FontWeight="SemiBold" Margin="0,0,0,4"/>
                                            <TextBlock Text="{Binding KeyText}" TextWrapping="Wrap" Margin="0,0,0,12"/>
                                            <Button x:Name="CopyKeyButton" Content="Copy Key" Width="100" HorizontalAlignment="Left"
                                                    Height="32" Background="#0078D4" Foreground="White" BorderThickness="0"
                                                    Tag="{Binding Key}" Margin="0,0,0,4" Cursor="Hand"
                                                    ToolTip="Copy recovery key to clipboard">
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
            Show-Toast -Message "Failed to create the confirmation dialog: $_" -Type "error" -DurationSeconds 6
            return
        }
        
        # Get controls
        $servicesList = $confirmationWindow.FindName('ServicesList')
        $cancelButton = $confirmationWindow.FindName('CancelButton')
        $confirmButton = $confirmationWindow.FindName('ConfirmButton')
        $encryptionKeysList = $confirmationWindow.FindName('EncryptionKeysList')
        $devicePreviewList = $confirmationWindow.FindName('DevicePreviewList')
        $preActionCombo = $confirmationWindow.FindName('PreActionComboBox')
        $coMgmtBanner = $confirmationWindow.FindName('CoMgmtBanner')
        $confirmationTextBox = $confirmationWindow.FindName('ConfirmationTextBox')
        $confirmSubtitle = $confirmationWindow.FindName('ConfirmSubtitle')

        # Set device count in subtitle
        $deviceCount = @($selectedDevices).Count
        $confirmSubtitle.Text = "Offboarding $deviceCount device$(if ($deviceCount -ne 1) { 's' }) -- select which services to remove from"

        # Wire type-to-confirm: enable ConfirmButton only when user types "OFFBOARD"
        $confirmationTextBox.Add_TextChanged({
                if ($confirmationTextBox.Text -eq 'OFFBOARD') {
                    $confirmButton.IsEnabled = $true
                    $confirmationTextBox.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#48BB78')
                } else {
                    $confirmButton.IsEnabled = $false
                    $confirmationTextBox.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FEE2E2')
                }
            })

        # Check for co-managed devices and show warning banner
        $hasCoManaged = $selectedDevices | Where-Object { $_.ManagementAgent -and $_.ManagementAgent -like '*configurationManager*' }
        if ($hasCoManaged) {
            $coMgmtBanner.Visibility = 'Visible'
        }

        # Populate Device Identity Preview
        $previewItems = New-Object System.Collections.ObjectModel.ObservableCollection[Object]
        foreach ($device in $selectedDevices) {
            $resolvedColor = "#48BB78"
            $notFoundColor = "#F56565"
            $previewItems.Add([PSCustomObject]@{
                DeviceName     = if ($device.DeviceName) { $device.DeviceName } else { "Unknown" }
                SerialText     = if ($device.SerialNumber) { "S/N: $($device.SerialNumber)" } else { "S/N: N/A" }
                EntraIdText    = if ($device.EntraDeviceId) { $device.EntraDeviceId.Substring(0, [Math]::Min(8, $device.EntraDeviceId.Length)) + "..." } else { "Not found" }
                EntraIdColor   = if ($device.EntraDeviceId) { $resolvedColor } else { $notFoundColor }
                IntuneIdText   = if ($device.IntuneDeviceId) { $device.IntuneDeviceId.Substring(0, [Math]::Min(8, $device.IntuneDeviceId.Length)) + "..." } else { "Not found" }
                IntuneIdColor  = if ($device.IntuneDeviceId) { $resolvedColor } else { $notFoundColor }
                AutopilotIdText  = if ($device.AutopilotIdentityId) { $device.AutopilotIdentityId.Substring(0, [Math]::Min(8, $device.AutopilotIdentityId.Length)) + "..." } else { "Not found" }
                AutopilotIdColor = if ($device.AutopilotIdentityId) { $resolvedColor } else { $notFoundColor }
            })
        }
        $devicePreviewList.ItemsSource = $previewItems

        # Create a list to store encryption key information
        $encryptionKeys = New-Object System.Collections.ObjectModel.ObservableCollection[Object]

        # Get encryption keys for all selected devices using cached IDs
        foreach ($selectedDevice in $selectedDevices) {
            try {
                $keyInfo = @{
                    DeviceName = $selectedDevice.DeviceName
                    KeyText    = "Loading encryption key..."
                    Key        = $null
                }

                # Use cached Intune ID to get device details if needed
                $intuneDevice = $null
                if ($selectedDevice.IntuneDeviceId) {
                    $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($selectedDevice.IntuneDeviceId)?`$select=operatingSystem,azureADDeviceId,serialNumber"
                    try { $intuneDevice = Invoke-GraphRequestWithRetry -Uri $uri -Method GET } catch { $intuneDevice = $null }
                }

                if ($intuneDevice) {
                    # Check OS type and get appropriate encryption key
                    if ($intuneDevice.operatingSystem -eq "Windows") {
                        try {
                            # Use cached EntraDeviceObjectId for BitLocker lookup
                            $bitlockerDeviceId = $selectedDevice.EntraDeviceObjectId ?? $intuneDevice.azureADDeviceId
                            $uri = "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$bitlockerDeviceId'"
                            $keyIdResponse = Get-GraphPagedResults -Uri $uri

                            if ($keyIdResponse.Count -gt 0) {
                                $recoveryKeyId = $keyIdResponse[0].id
                                $uri = "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys/$($recoveryKeyId)?`$select=key"
                                $recoveryKeyData = Invoke-MgGraphCommunityRequest -OutputType Hashtable -Uri $uri -Method GET

                                if ($recoveryKeyData.key) {
                                    $keyInfo.KeyText = "BitLocker Recovery Key: $($recoveryKeyData.key)"
                                    $keyInfo.Key = $recoveryKeyData.key
                                    Write-Log "SENSITIVE: BitLocker recovery key retrieved for device $($selectedDevice.DeviceName)" -Severity "AUDIT"
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
                            Write-Log "Error retrieving BitLocker key: $_" -Severity "ERROR"
                            if ($_.Exception.Message -match '(?:Graph error|HTTP)\s+403\b') {
                                $keyInfo.KeyText = "BitLocker key access denied. Ensure BitlockerKey.Read.All permission is granted."
                            }
                            else {
                                $keyInfo.KeyText = "Error retrieving BitLocker key. Check logs for details."
                            }
                        }
                    }
                    elseif ($intuneDevice.operatingSystem -eq "macOS") {
                        # Get FileVault key using cached Intune ID
                        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$($selectedDevice.IntuneDeviceId)')/getFileVaultKey"
                        try {
                            $fileVaultKey = Invoke-MgGraphCommunityRequest -OutputType Hashtable -Uri $uri -Method GET
                            if ($fileVaultKey.value) {
                                $keyInfo.KeyText = "FileVault Recovery Key: $($fileVaultKey.value)"
                                $keyInfo.Key = $fileVaultKey.value
                                Write-Log "SENSITIVE: FileVault recovery key retrieved for device $($selectedDevice.DeviceName)" -Severity "AUDIT"
                            }
                            else {
                                $keyInfo.KeyText = "No FileVault recovery key found for this device."
                            }
                        }
                        catch {
                            Write-Log "Error retrieving FileVault key: $_" -Severity "ERROR"
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

                # LAPS password retrieval (works for any OS, uses Entra device ID)
                $lapsKeyInfo = @{
                    DeviceName = "$($selectedDevice.DeviceName) - LAPS"
                    KeyText    = "Loading LAPS password..."
                    Key        = $null
                }
                $lapsDeviceId = $selectedDevice.EntraDeviceObjectId
                if (-not $lapsDeviceId) { $lapsDeviceId = $intuneDevice.azureADDeviceId }
                Write-Log "LAPS lookup - EntraDeviceObjectId: '$($selectedDevice.EntraDeviceObjectId)', intuneDevice.azureADDeviceId: '$($intuneDevice.azureADDeviceId)', resolved lapsDeviceId: '$lapsDeviceId'" -Severity "INFO"
                if ($lapsDeviceId) {
                    try {
                        $uri = "https://graph.microsoft.com/beta/directory/deviceLocalCredentials/$($lapsDeviceId)?`$select=credentials"
                        $lapsResponse = Invoke-MgGraphCommunityRequest -OutputType Hashtable -Uri $uri -Method GET
                        if ($lapsResponse.credentials -and $lapsResponse.credentials.Count -gt 0) {
                            $latestCred = $lapsResponse.credentials | Sort-Object -Property backupDateTime -Descending | Select-Object -First 1
                            $lapsPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($latestCred.passwordBase64))
                            $lapsAccount = $latestCred.accountName
                            $lapsKeyInfo.KeyText = "LAPS Password: $lapsPassword (Account: $lapsAccount)"
                            $lapsKeyInfo.Key = $lapsPassword
                            Write-Log "SENSITIVE: LAPS password retrieved for device $($selectedDevice.DeviceName)" -Severity "AUDIT"
                        } else {
                            $lapsKeyInfo.KeyText = "No LAPS password found for this device."
                        }
                    }
                    catch {
                        if ($_.Exception.Message -match '(?:Graph error|HTTP)\s+404\b' -or $_ -match '404') {
                            $lapsKeyInfo.KeyText = "No LAPS password found for this device."
                        } else {
                            Write-Log "Error retrieving LAPS password: $_" -Severity "ERROR"
                            $lapsKeyInfo.KeyText = "Error retrieving LAPS password. Check logs for details."
                        }
                    }
                } else {
                    $lapsKeyInfo.KeyText = "No Entra device ID available for LAPS lookup."
                }
                $encryptionKeys.Add([PSCustomObject]$lapsKeyInfo)
            }
            catch {
                Write-Log "Error retrieving encryption key for $($selectedDevice.DeviceName): $_" -Severity "ERROR"
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
                        # Clipboard access can fail transiently (e.g. CLIPBRD_E_CANT_OPEN in
                        # RDP sessions or when another process holds the clipboard). Never let
                        # that exception escape the routed event handler (Issue #38).
                        try {
                            Set-Clipboard -Value $button.Tag -ErrorAction Stop
                            $button.Content = "Copied!"
                        }
                        catch {
                            Write-Log "Failed to copy recovery key to clipboard: $_" -Severity "WARN"
                            $button.Content = "Copy failed"
                        }
                        # Local variable, not $script:, so GetNewClosure() captures it;
                        # $script: variables read as null inside nested closures (Issue #64).
                        $timer = New-Object System.Windows.Threading.DispatcherTimer
                        $timer.Interval = [TimeSpan]::FromSeconds(2)
                        $timer.Add_Tick({
                                $button.Content = "Copy Key"
                                $timer.Stop()
                            }.GetNewClosure())
                        $timer.Start()
                    }
                }
            
                $encryptionKeysList = $confirmationWindow.FindName('EncryptionKeysList')
                $encryptionKeysList.AddHandler(
                    [System.Windows.Controls.Button]::ClickEvent,
                    [System.Windows.RoutedEventHandler]$copyKeyButton_Click
                )
            })
        
        # Add services to the list with checkboxes
        $services = @(
            @{ Name = "Entra ID"; Icon = "M12,5.5A3.5,3.5 0 0,1 15.5,9A3.5,3.5 0 0,1 12,12.5A3.5,3.5 0 0,1 8.5,9A3.5,3.5 0 0,1 12,5.5M5,8C5.56,8 6.08,8.15 6.53,8.42C6.38,9.85 6.8,11.27 7.66,12.38C7.16,13.34 6.16,14 5,14A3,3 0 0,1 2,11A3,3 0 0,1 5,8M19,8A3,3 0 0,1 22,11A3,3 0 0,1 19,14C17.84,14 16.84,13.34 16.34,12.38C17.2,11.27 17.62,9.85 17.47,8.42C17.92,8.15 18.44,8 19,8M5.5,18.25C5.5,16.18 8.41,14.5 12,14.5C15.59,14.5 18.5,16.18 18.5,18.25V20H5.5V18.25M0,20V18.5C0,17.11 1.89,15.94 4.45,15.6C3.86,16.28 3.5,17.22 3.5,18.25V20H0M24,20H20.5V18.25C20.5,17.22 20.14,16.28 19.55,15.6C22.11,15.94 24,17.11 24,18.5V20Z"; DefaultChecked = $true },
            @{ Name = "Disable in Entra ID"; Icon = "M12,5.5A3.5,3.5 0 0,1 15.5,9A3.5,3.5 0 0,1 12,12.5A3.5,3.5 0 0,1 8.5,9A3.5,3.5 0 0,1 12,5.5M5,8C5.56,8 6.08,8.15 6.53,8.42C6.38,9.85 6.8,11.27 7.66,12.38C7.16,13.34 6.16,14 5,14A3,3 0 0,1 2,11A3,3 0 0,1 5,8M19,8A3,3 0 0,1 22,11A3,3 0 0,1 19,14C17.84,14 16.84,13.34 16.34,12.38C17.2,11.27 17.62,9.85 17.47,8.42C17.92,8.15 18.44,8 19,8M5.5,18.25C5.5,16.18 8.41,14.5 12,14.5C15.59,14.5 18.5,16.18 18.5,18.25V20H5.5V18.25M0,20V18.5C0,17.11 1.89,15.94 4.45,15.6C3.86,16.28 3.5,17.22 3.5,18.25V20H0M24,20H20.5V18.25C20.5,17.22 20.14,16.28 19.55,15.6C22.11,15.94 24,17.11 24,18.5V20Z"; DefaultChecked = $false },
            @{ Name = "Intune"; Icon = "M21,14V4H3V14H21M21,2A2,2 0 0,1 23,4V16A2,2 0 0,1 21,18H14L16,21V22H8V21L10,18H3C1.89,18 1,17.1 1,16V4C1,2.89 1.89,2 3,2H21M4,5H20V13H4V5Z"; DefaultChecked = $true },
            @{ Name = "Autopilot"; Icon = "M12,3L1,9L12,15L21,10.09V17H23V9M5,13.18V17.18L12,21L19,17.18V13.18L12,17L5,13.18Z"; DefaultChecked = $true }
        )

        if (Get-DefenderIntegrationEnabled) {
            $services += @{ Name = "Defender for Endpoint"; Icon = "M12,1L3,5V11C3,16.55 6.84,21.74 12,23C17.16,21.74 21,16.55 21,11V5L12,1M12,3.18L19,6.3V11.22C19,15.54 16.18,19.5 12,20.93C7.82,19.5 5,15.54 5,11.22V6.3L12,3.18Z"; DefaultChecked = $false }
        }
        
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
            $checkbox.IsChecked = $service.DefaultChecked
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

        # Mutual exclusivity: "Entra ID" (delete) vs "Disable in Entra ID"
        # Plain scriptblocks: GetNewClosure() would read $script:serviceCheckboxes as null
        # here because closures only capture per-invocation locals (Issue #64).
        $script:serviceCheckboxes["Entra ID"].Add_Checked({
            $script:serviceCheckboxes["Disable in Entra ID"].IsChecked = $false
        })
        $script:serviceCheckboxes["Disable in Entra ID"].Add_Checked({
            $script:serviceCheckboxes["Entra ID"].IsChecked = $false
        })

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
            Show-Toast -Message "Failed to show the confirmation dialog: $_" -Type "error" -DurationSeconds 6
            return
        }
        if (-not $confirmationResult) {
            Write-Log "User canceled offboarding operation."
            return
        }

        # Capture pre-action selection (0=none, 1=retire, 2=wipe)
        $script:preAction = $preActionCombo.SelectedIndex
        if ($script:preAction -gt 0) {
            $preActionName = if ($script:preAction -eq 1) { "Retire" } else { "Wipe" }
            Write-Log "Pre-offboarding action selected: $preActionName" -Severity "AUDIT"
        }

        # Create results collection to track all operations
        $offboardingResults = @()

        try {
            # Determine which services are selected
            $disableEntra = $script:serviceCheckboxes.ContainsKey("Disable in Entra ID") -and $script:serviceCheckboxes["Disable in Entra ID"].IsChecked
            $deleteEntra = (-not $disableEntra) -and $script:serviceCheckboxes["Entra ID"].IsChecked
            $deleteIntune = $script:serviceCheckboxes["Intune"].IsChecked
            $deleteAutopilot = $script:serviceCheckboxes["Autopilot"].IsChecked
            $offboardMde = (Get-DefenderIntegrationEnabled) -and $script:serviceCheckboxes.ContainsKey("Defender for Endpoint") -and $script:serviceCheckboxes["Defender for Endpoint"].IsChecked

            # Resolve MDE device IDs if MDE offboarding is selected
            if ($offboardMde) {
                try {
                    $mdeToken = Get-MdeAccessToken
                    if ($mdeToken) {
                        foreach ($device in $selectedDevices) {
                            if ($device.EntraDeviceObjectId -and -not $device.MdeDeviceId) {
                                try {
                                    $mdeHeaders = @{ Authorization = "Bearer $mdeToken" }
                                    $mdeResponse = Invoke-RestMethod -Uri "https://api.security.microsoft.com/api/machines?`$filter=aadDeviceId eq '$($device.EntraDeviceObjectId)'" -Headers $mdeHeaders -Method GET
                                    if ($mdeResponse.value -and $mdeResponse.value.Count -gt 0) {
                                        $device.MdeDeviceId = $mdeResponse.value[0].id
                                        Write-Log "Resolved MDE device ID for $($device.DeviceName): $($device.MdeDeviceId)"
                                    }
                                } catch {
                                    Write-Log "Could not resolve MDE device ID for $($device.DeviceName): $_" -Severity "WARN"
                                }
                            }
                        }
                    } else {
                        Write-Log "Could not acquire MDE access token. MDE offboarding will be skipped." -Severity "WARN"
                        $offboardMde = $false
                    }
                } catch {
                    Write-Log "Error during MDE token acquisition: $_" -Severity "ERROR"
                    $offboardMde = $false
                }
            }

            # Collect serial numbers for potential bulk Autopilot deletion (2+ devices).
            # The deleteDevices endpoint takes serialNumbers, so only serials are needed.
            $bulkAutopilotSerials = @()
            if ($deleteAutopilot) {
                $bulkAutopilotSerials = @($selectedDevices | Where-Object { $_.AutopilotIdentityId -and $_.SerialNumber } | ForEach-Object { $_.SerialNumber })
            }
            $useBulkAutopilot = $bulkAutopilotSerials.Count -ge 2

            foreach ($device in $selectedDevices) {
                $deviceName = $device.DeviceName
                $serialNumber = $device.SerialNumber
                $deviceResult = @{
                    DeviceName   = $deviceName
                    SerialNumber = $serialNumber
                    EntraID      = @{ Found = $false; Success = $false; Error = $null; Action = $null }
                    Intune       = @{ Found = $false; Success = $false; Error = $null }
                    Autopilot    = @{ Found = $false; Success = $false; Error = $null }
                    MDE          = @{ Found = $false; Success = $false; Error = $null }
                    PreAction    = @{ Action = $null; Success = $false; Error = $null }
                }

                Write-Log "Starting offboarding for device: $deviceName (Serial: $serialNumber, EntraId: $($device.EntraDeviceId), IntuneId: $($device.IntuneDeviceId), AutopilotId: $($device.AutopilotIdentityId))" -Severity "AUDIT"

                # Execute pre-offboarding action (retire/wipe) if selected
                if ($script:preAction -gt 0 -and $device.IntuneDeviceId) {
                    $preActionName = if ($script:preAction -eq 1) { "retire" } else { "wipe" }
                    $deviceResult.PreAction.Action = $preActionName
                    try {
                        $preActionUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($device.IntuneDeviceId)/$preActionName"
                        $preActionBody = if ($script:preAction -eq 2) { '{}' } else { $null }
                        if ($preActionBody) {
                            Invoke-MgGraphCommunityRequest -OutputType Hashtable -Uri $preActionUri -Method POST -Body $preActionBody -ContentType "application/json"
                        } else {
                            Invoke-MgGraphCommunityRequest -OutputType Hashtable -Uri $preActionUri -Method POST
                        }
                        $deviceResult.PreAction.Success = $true
                        Write-Log "Successfully executed $preActionName on device $deviceName (IntuneId: $($device.IntuneDeviceId))" -Severity "AUDIT"
                        Start-Sleep -Seconds 2
                    } catch {
                        $deviceResult.PreAction.Error = $_.Exception.Message
                        Write-Log "Error executing $preActionName on device $deviceName`: $_" -Severity "ERROR"
                        $continueChoice = [System.Windows.MessageBox]::Show(
                            "Failed to $preActionName device '$deviceName'. Continue with deletion?`n`nError: $($_.Exception.Message)",
                            "Pre-Action Failed",
                            [System.Windows.MessageBoxButton]::YesNo,
                            [System.Windows.MessageBoxImage]::Warning
                        )
                        if ($continueChoice -eq [System.Windows.MessageBoxResult]::No) {
                            $offboardingResults += $deviceResult
                            continue
                        }
                    }
                }

                # Execute MDE offboarding if selected
                if ($offboardMde -and $device.MdeDeviceId) {
                    $deviceResult.MDE.Found = $true
                    try {
                        $mdeHeaders = @{ Authorization = "Bearer $mdeToken"; "Content-Type" = "application/json" }
                        $mdeBody = @{ Comment = "Offboarded via DeviceOffboardingManager" } | ConvertTo-Json
                        Invoke-RestMethod -Uri "https://api.security.microsoft.com/api/machines/$($device.MdeDeviceId)/offboard" -Headers $mdeHeaders -Method POST -Body $mdeBody -ContentType "application/json"
                        $deviceResult.MDE.Success = $true
                        Write-Log "Successfully offboarded device $deviceName from MDE (MdeId: $($device.MdeDeviceId))" -Severity "AUDIT"
                    } catch {
                        $deviceResult.MDE.Error = $_.Exception.Message
                        Write-Log "Error offboarding device $deviceName from MDE: $_" -Severity "ERROR"
                    }
                } elseif ($offboardMde -and -not $device.MdeDeviceId) {
                    Write-Log "Skipping MDE offboarding for $deviceName - no MDE device ID resolved" -Severity "WARN"
                }

                # Build batch requests for this device
                $batchRequests = @()

                if ($disableEntra) {
                    if ($device.EntraDeviceId) {
                        $deviceResult.EntraID.Found = $true
                        $deviceResult.EntraID.Action = "Disabled"
                        $batchRequests += @{ id = "entra"; method = "PATCH"; url = "/devices/$($device.EntraDeviceId)"; body = @{ accountEnabled = $false }; headers = @{ "Content-Type" = "application/json" } }
                    } else {
                        Write-Log "Skipping Entra ID disable for $deviceName - no Entra Device ID resolved" -Severity "WARN"
                    }
                } elseif ($deleteEntra) {
                    if ($device.EntraDeviceId) {
                        $deviceResult.EntraID.Found = $true
                        $deviceResult.EntraID.Action = "Removed"
                        $batchRequests += @{ id = "entra"; method = "DELETE"; url = "/devices/$($device.EntraDeviceId)" }
                    } else {
                        Write-Log "Skipping Entra ID deletion for $deviceName - no Entra Device ID resolved" -Severity "WARN"
                    }
                } else {
                    Write-Log "Skipping Entra ID operation for device $deviceName (not selected)"
                }

                if ($deleteIntune) {
                    if ($device.IntuneDeviceId) {
                        $deviceResult.Intune.Found = $true
                        $batchRequests += @{ id = "intune"; method = "DELETE"; url = "/deviceManagement/managedDevices/$($device.IntuneDeviceId)" }
                    } else {
                        Write-Log "Skipping Intune deletion for $deviceName - no Intune Device ID resolved" -Severity "WARN"
                    }
                } else {
                    Write-Log "Skipping Intune removal for device $deviceName (not selected)"
                }

                # Include Autopilot in per-device batch only if not using bulk deletion
                if ($deleteAutopilot -and -not $useBulkAutopilot) {
                    if ($device.AutopilotIdentityId) {
                        $deviceResult.Autopilot.Found = $true
                        $batchRequests += @{ id = "autopilot"; method = "DELETE"; url = "/deviceManagement/windowsAutopilotDeviceIdentities/$($device.AutopilotIdentityId)" }
                    } else {
                        Write-Log "Skipping Autopilot deletion for $deviceName - no Autopilot Identity ID resolved" -Severity "WARN"
                    }
                } elseif ($deleteAutopilot -and $useBulkAutopilot) {
                    if ($device.AutopilotIdentityId) {
                        $deviceResult.Autopilot.Found = $true
                        # Will be handled by bulk deletion after the loop
                    } else {
                        Write-Log "Skipping Autopilot deletion for $deviceName - no Autopilot Identity ID resolved" -Severity "WARN"
                    }
                } else {
                    Write-Log "Skipping Autopilot removal for device $deviceName (not selected)"
                }

                # Execute batch if there are requests
                if ($batchRequests.Count -gt 0) {
                    try {
                        $batchResponses = Invoke-GraphBatchRequest -Requests $batchRequests

                        # Parse Entra response
                        $entraResp = $batchResponses | Where-Object { $_.id -eq "entra" }
                        if ($entraResp) {
                            if ($entraResp.status -in @(200, 204)) {
                                $deviceResult.EntraID.Success = $true
                                Write-Log "Successfully $($deviceResult.EntraID.Action.ToLower()) device $deviceName in Entra ID (ID: $($device.EntraDeviceId))" -Severity "AUDIT"
                            } elseif ($entraResp.status -eq 403 -and $entraResp.body.error.code -match 'multipleAdminApproval|protectedOperation') {
                                $deviceResult.EntraID.Error = "Requires Multi-Admin Approval"
                                Write-Log "Entra ID operation for $deviceName requires Multi-Admin Approval" -Severity "WARN"
                            } elseif ($entraResp.status -eq 403) {
                                $deviceResult.EntraID.Error = Get-Graph403Message -Service 'EntraID'
                                Write-Log "Entra ID operation for $deviceName was denied (403) - likely missing Cloud Device Administrator / Intune Administrator role" -Severity "ERROR"
                            } else {
                                $deviceResult.EntraID.Error = "HTTP $($entraResp.status)"
                                Write-Log "Error with Entra ID operation for $deviceName`: HTTP $($entraResp.status)" -Severity "ERROR"
                            }
                        }

                        # Parse Intune response
                        $intuneResp = $batchResponses | Where-Object { $_.id -eq "intune" }
                        if ($intuneResp) {
                            if ($intuneResp.status -in @(200, 204)) {
                                $deviceResult.Intune.Success = $true
                                Write-Log "Successfully removed device $deviceName from Intune (ID: $($device.IntuneDeviceId))" -Severity "AUDIT"
                            } elseif ($intuneResp.status -eq 403 -and $intuneResp.body.error.code -match 'multipleAdminApproval|protectedOperation') {
                                $deviceResult.Intune.Error = "Requires Multi-Admin Approval"
                                Write-Log "Intune operation for $deviceName requires Multi-Admin Approval" -Severity "WARN"
                            } elseif ($intuneResp.status -eq 403) {
                                $deviceResult.Intune.Error = Get-Graph403Message -Service 'Intune'
                                Write-Log "Intune operation for $deviceName was denied (403) - likely missing Intune Administrator role or device-delete RBAC permission" -Severity "ERROR"
                            } else {
                                $deviceResult.Intune.Error = "HTTP $($intuneResp.status)"
                                Write-Log "Error removing device $deviceName from Intune: HTTP $($intuneResp.status)" -Severity "ERROR"
                            }
                        }

                        # Parse Autopilot response (only if not using bulk)
                        $autopilotResp = $batchResponses | Where-Object { $_.id -eq "autopilot" }
                        if ($autopilotResp) {
                            if ($autopilotResp.status -in @(200, 204)) {
                                $deviceResult.Autopilot.Success = $true
                                Write-Log "Successfully removed device $deviceName from Autopilot (ID: $($device.AutopilotIdentityId))" -Severity "AUDIT"
                            } elseif ($autopilotResp.status -eq 403 -and $autopilotResp.body.error.code -match 'multipleAdminApproval|protectedOperation') {
                                $deviceResult.Autopilot.Error = "Requires Multi-Admin Approval"
                                Write-Log "Autopilot operation for $deviceName requires Multi-Admin Approval" -Severity "WARN"
                            } elseif ($autopilotResp.status -eq 403) {
                                $deviceResult.Autopilot.Error = Get-Graph403Message -Service 'Autopilot'
                                Write-Log "Autopilot operation for $deviceName was denied (403) - likely missing Intune Administrator role" -Severity "ERROR"
                            } else {
                                $deviceResult.Autopilot.Error = "HTTP $($autopilotResp.status)"
                                Write-Log "Error removing device $deviceName from Autopilot: HTTP $($autopilotResp.status)" -Severity "ERROR"
                            }
                        }
                    }
                    catch {
                        Write-Log "Batch request failed for device $deviceName`: $_" -Severity "ERROR"
                        if ($deviceResult.EntraID.Found -and -not $deviceResult.EntraID.Success) { $deviceResult.EntraID.Error = $_.Exception.Message }
                        if ($deviceResult.Intune.Found -and -not $deviceResult.Intune.Success) { $deviceResult.Intune.Error = $_.Exception.Message }
                        if ($deviceResult.Autopilot.Found -and -not $deviceResult.Autopilot.Success) { $deviceResult.Autopilot.Error = $_.Exception.Message }
                    }
                }

                $offboardingResults += $deviceResult
                Write-Log "Completed offboarding attempt for device: $deviceName" -Severity "AUDIT"
            }

            # Bulk Autopilot deletion when 2+ devices have serial numbers
            if ($useBulkAutopilot -and $bulkAutopilotSerials.Count -ge 2) {
                Write-Log "Executing bulk Autopilot deletion for $($bulkAutopilotSerials.Count) devices by serial number" -Severity "AUDIT"
                try {
                    $bulkBody = @{
                        serialNumbers = $bulkAutopilotSerials
                    } | ConvertTo-Json -Depth 5
                    $bulkResponse = Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/deleteDevices" -Method POST -Body $bulkBody -ContentType "application/json"

                    # Parse per-device deletion status from response
                    if ($bulkResponse.value) {
                        foreach ($deleteState in $bulkResponse.value) {
                            $matchingResult = $offboardingResults | Where-Object { $_.SerialNumber -eq $deleteState.serialNumber }
                            if ($matchingResult) {
                                if ($deleteState.deletionState -eq "failed") {
                                    $matchingResult.Autopilot.Error = $deleteState.errorMessage
                                    Write-Log "Bulk Autopilot deletion failed for serial $($deleteState.serialNumber): $($deleteState.errorMessage)" -Severity "ERROR"
                                } else {
                                    $matchingResult.Autopilot.Success = $true
                                }
                            }
                        }
                    } else {
                        # No detailed response -- set optimistic success
                        foreach ($result in $offboardingResults) {
                            if ($result.Autopilot.Found) {
                                $result.Autopilot.Success = $true
                            }
                        }
                    }
                    Write-Log "Bulk Autopilot deletion completed for $($bulkAutopilotSerials.Count) devices" -Severity "AUDIT"
                }
                catch {
                    Write-Log "Bulk Autopilot deletion failed: $_ -- falling back to individual deletion" -Severity "ERROR"
                    foreach ($result in $offboardingResults) {
                        if ($result.Autopilot.Found -and -not $result.Autopilot.Success) {
                            $matchingDevice = $selectedDevices | Where-Object { $_.DeviceName -eq $result.DeviceName -and $_.AutopilotIdentityId }
                            if ($matchingDevice) {
                                try {
                                    Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$($matchingDevice.AutopilotIdentityId)" -Method DELETE
                                    $result.Autopilot.Success = $true
                                    Write-Log "Successfully removed device $($result.DeviceName) from Autopilot (fallback)" -Severity "AUDIT"
                                }
                                catch {
                                    if ($_.Exception.Message -match '(?:Graph error|HTTP)\s+403\b') {
                                        $result.Autopilot.Error = Get-Graph403Message -Service 'Autopilot'
                                    } else {
                                        $result.Autopilot.Error = $_.Exception.Message
                                    }
                                    Write-Log "Error removing device $($result.DeviceName) from Autopilot (fallback): $_" -Severity "ERROR"
                                }
                            }
                        }
                    }
                }
            }

            # Show summary of all operations
            Show-OffboardingSummary -Results $offboardingResults
            
            # Update UI status indicators if all operations were successful
            $allEntraSuccess = $offboardingResults | Where-Object { $_.EntraID.Found -and $_.EntraID.Success } | Measure-Object | Select-Object -ExpandProperty Count
            $allIntuneSuccess = $offboardingResults | Where-Object { $_.Intune.Found -and $_.Intune.Success } | Measure-Object | Select-Object -ExpandProperty Count
            $allAutopilotSuccess = $offboardingResults | Where-Object { $_.Autopilot.Found -and $_.Autopilot.Success } | Measure-Object | Select-Object -ExpandProperty Count
            
            $allEntraDisabled = $offboardingResults | Where-Object { $_.EntraID.Found -and $_.EntraID.Success -and $_.EntraID.Action -eq "Disabled" } | Measure-Object | Select-Object -ExpandProperty Count
            if ($allEntraDisabled -gt 0) {
                $Window.FindName('aad_status').Text = "Entra ID: Devices Disabled"
                $Window.FindName('aad_status').Foreground = "#ECC94B"
            }
            elseif ($allEntraSuccess -gt 0) {
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
        }
        catch {
            Write-Log "Critical error in offboarding operation. Exception: $_"
            Show-Toast -Message "Critical error in offboarding operation. Please check the logs for details." -Type "error" -DurationSeconds 8
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
                    DeviceName           = $device.DeviceName
                    SerialNumber         = $device.SerialNumber
                    OperatingSystem      = $device.OperatingSystem
                    PrimaryUser          = $device.PrimaryUser
                    ComplianceState      = $device.ComplianceState
                    AzureADLastContact   = $device.AzureADLastContact
                    IntuneLastContact    = $device.IntuneLastContact
                    AutopilotLastContact = $device.AutopilotLastContact
                }
            }

            Export-DeviceListToCSV -DeviceList $exportData -DefaultFileName $fileName
        }
        else {
            Show-Toast -Message "No search results to export." -Type "info"
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
                    DeviceName           = $device.DeviceName
                    SerialNumber         = $device.SerialNumber
                    OperatingSystem      = $device.OperatingSystem
                    PrimaryUser          = $device.PrimaryUser
                    ComplianceState      = $device.ComplianceState
                    AzureADLastContact   = $device.AzureADLastContact
                    IntuneLastContact    = $device.IntuneLastContact
                    AutopilotLastContact = $device.AutopilotLastContact
                }
            }

            Export-DeviceListToCSV -DeviceList $exportData -DefaultFileName $fileName
        }
        else {
            Show-Toast -Message "No devices selected to export." -Type "info"
        }
    })

function Get-MdeAccessToken {
    try {
        $context = Get-MgGraphCommunityContext
        if (-not $context) {
            Write-Log "No Graph context available for MDE token acquisition" -Severity "WARN"
            return $null
        }

        # Check if MSAL.PS module is available
        if (-not (Get-Module -ListAvailable -Name "MSAL.PS")) {
            Write-Log "MSAL.PS module not installed. MDE offboarding requires the MSAL.PS module. Install with: Install-Module MSAL.PS" -Severity "WARN"
            return $null
        }

        Import-Module MSAL.PS -ErrorAction Stop
        $resourceScopes = @(
            "https://api.securitycenter.microsoft.com/.default",
            "https://api.security.microsoft.com/.default"
        )

        if ($script:CurrentAuthDetails -and $script:CurrentAuthDetails.Method -eq 'Secret') {
            foreach ($scopes in $resourceScopes) {
                try {
                    $mdeToken = (Get-MsalToken `
                            -ClientId $script:CurrentAuthDetails.AppId `
                            -TenantId $script:CurrentAuthDetails.TenantId `
                            -ClientSecret $script:CurrentAuthDetails.SecretSecureString `
                            -Scopes @($scopes) `
                            -ErrorAction Stop).AccessToken

                    Write-Log "Acquired app-only Defender for Endpoint token with client secret for resource $scopes"
                    return $mdeToken
                } catch {
                    Write-Log "Client secret Defender token acquisition failed for $scopes`: $_" -Severity "WARN"
                }
            }
        }

        if ($script:CurrentAuthDetails -and $script:CurrentAuthDetails.Method -eq 'Certificate') {
            $thumbprint = ($script:CurrentAuthDetails.Thumbprint -replace '\s', '')
            $certificate = $null
            foreach ($certPath in @("Cert:\CurrentUser\My\$thumbprint", "Cert:\LocalMachine\My\$thumbprint")) {
                $certificate = Get-Item -Path $certPath -ErrorAction SilentlyContinue
                if ($certificate) {
                    break
                }
            }

            if (-not $certificate) {
                Write-Log "Could not find certificate with thumbprint $thumbprint for Defender token acquisition." -Severity "WARN"
            }
            else {
                foreach ($scopes in $resourceScopes) {
                    try {
                        $mdeToken = (Get-MsalToken `
                                -ClientId $script:CurrentAuthDetails.AppId `
                                -TenantId $script:CurrentAuthDetails.TenantId `
                                -ClientCertificate $certificate `
                                -Scopes @($scopes) `
                                -ErrorAction Stop).AccessToken

                        Write-Log "Acquired app-only Defender for Endpoint token with certificate for resource $scopes"
                        return $mdeToken
                    } catch {
                        Write-Log "Certificate Defender token acquisition failed for $scopes`: $_" -Severity "WARN"
                    }
                }
            }
        }

        foreach ($scopes in $resourceScopes) {
            try {
                $mdeToken = (Get-MsalToken -ClientId $context.ClientId -TenantId $context.TenantId -Scopes @($scopes) -Silent -ErrorAction Stop).AccessToken
                Write-Log "Acquired Defender for Endpoint token silently for resource $scopes"
                return $mdeToken
            } catch {
                Write-Log "Silent Defender token acquisition failed for $scopes`: $_" -Severity "WARN"
            }

            try {
                $mdeToken = (Get-MsalToken -ClientId $context.ClientId -TenantId $context.TenantId -Scopes @($scopes) -Interactive -ErrorAction Stop).AccessToken
                Write-Log "Acquired Defender for Endpoint token interactively for resource $scopes"
                return $mdeToken
            } catch {
                Write-Log "Interactive Defender token acquisition failed for $scopes`: $_" -Severity "WARN"
            }
        }

        Write-Log "Could not acquire Defender for Endpoint token. Ensure WindowsDefenderATP Machine.ReadWrite.All and Machine.Offboard permissions are consented for app-only auth, or Machine.ReadWrite and Machine.Offboard are consented for delegated auth." -Severity "ERROR"
        return $null
    } catch {
        Write-Log "Error acquiring MDE access token: $_" -Severity "ERROR"
        return $null
    }
}

function Set-AutopilotGroupTagForDevices {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Devices,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$GroupTag
    )

    $updated = 0
    $failed = 0
    foreach ($device in $Devices) {
        try {
            if (-not $device.AutopilotIdentityId -and $device.SerialNumber) {
                # Resolve the Autopilot identity by exact serial match only; contains() is
                # just the server-side prefilter (Autopilot does not support eq on serialNumber).
                $serial = $device.SerialNumber.Trim()
                $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$(ConvertTo-ODataStringValue -Value $serial)')"
                $candidates = @(Get-GraphPagedResults -Uri $uri)
                $exactMatches = @($candidates | Where-Object { $_.serialNumber -and $_.serialNumber.Trim() -ieq $serial })
                if ($exactMatches.Count -eq 1) {
                    $device.AutopilotIdentityId = $exactMatches[0].id
                }
                elseif ($exactMatches.Count -gt 1) {
                    Write-Log "Multiple Autopilot devices matched serial '$serial'. Skipping group tag for $($device.DeviceName) to prevent wrong-device operations." -Severity "WARN"
                }
            }

            if (-not $device.AutopilotIdentityId) {
                $failed++
                Write-Log "Cannot set Autopilot group tag for $($device.DeviceName): no Autopilot identity resolved" -Severity "WARN"
                continue
            }

            $body = @{ groupTag = $GroupTag } | ConvertTo-Json -Depth 3
            $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$($device.AutopilotIdentityId)/updateDeviceProperties"
            Invoke-GraphRequestWithRetry -Uri $uri -Method POST -Body $body -ContentType "application/json"
            $updated++
            Write-Log "Set Autopilot group tag for $($device.DeviceName) (AutopilotId: $($device.AutopilotIdentityId)) to '$GroupTag'" -Severity "AUDIT"
        }
        catch {
            $failed++
            Write-Log "Failed to set Autopilot group tag for $($device.DeviceName): $_" -Severity "ERROR"
        }
    }

    return @{
        Updated = $updated
        Failed  = $failed
    }
}

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
    $mdeSelected = (Get-DefenderIntegrationEnabled) -and $script:serviceCheckboxes -and $script:serviceCheckboxes.ContainsKey("Defender for Endpoint") -and $script:serviceCheckboxes["Defender for Endpoint"].IsChecked

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

function Show-PrerequisitesDialog {
    try {
        $reader = (New-Object System.Xml.XmlNodeReader $prerequisitesModalXaml)
        $prereqWindow = [Windows.Markup.XamlReader]::Load($reader)
        
        if ($null -eq $prereqWindow) {
            throw "Failed to create prerequisites window. XamlReader returned null."
        }
    }
    catch {
        Write-Log "Error creating prerequisites window: $_"
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

    $context = Get-MgGraphCommunityContext
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
    $moduleText.Text = "MgGraphCommunity"
    $moduleText.Style = $prereqWindow.FindResource("CheckTextStyle")
    $moduleText.FontWeight = "SemiBold"

    # Module description
    $descText = New-Object System.Windows.Controls.TextBlock
    $descText.Text = "Required for Microsoft Graph authentication and API operations (WAM-free interactive sign-in)"
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

    if (Get-Module -ListAvailable -Name "MgGraphCommunity") {
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

                Install-Module "MgGraphCommunity" -Scope CurrentUser -Force
                Import-Module MgGraphCommunity -ErrorAction Stop

                $moduleCheckbox.IsChecked = $true
                $moduleCheckbox.Foreground = "#28A745"
                $installButton.Visibility = "Collapsed"

                [System.Windows.MessageBox]::Show(
                    "Module installed and loaded successfully.",
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

    # Optional Defender for Endpoint integration toggle
    $defenderSettingsItem = New-Object System.Windows.Controls.StackPanel
    $defenderSettingsItem.Style = $prereqWindow.FindResource("CheckItemStyle")
    $defenderSettingsItem.Orientation = "Horizontal"

    $defenderToggle = New-Object System.Windows.Controls.CheckBox
    $defenderToggle.VerticalAlignment = "Center"
    $defenderToggle.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $defenderToggle.IsChecked = Get-DefenderIntegrationEnabled

    $defenderTextPanel = New-Object System.Windows.Controls.StackPanel
    $defenderTextPanel.Orientation = "Vertical"
    $defenderTextPanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)

    $defenderTitle = New-Object System.Windows.Controls.TextBlock
    $defenderTitle.Text = "Enable Defender for Endpoint integration"
    $defenderTitle.Style = $prereqWindow.FindResource("CheckTextStyle")
    $defenderTitle.FontWeight = "SemiBold"

    $defenderDescription = New-Object System.Windows.Controls.TextBlock
    $defenderDescription.Text = "Optional. When enabled, Defender appears as an offboarding target and requests a separate Defender API token only when selected. Requires WindowsDefenderATP permissions: Machine.ReadWrite.All and Machine.Offboard."
    $defenderDescription.Style = $prereqWindow.FindResource("CheckTextStyle")
    $defenderDescription.Foreground = "#666666"
    $defenderDescription.FontSize = 12
    $defenderDescription.TextWrapping = "Wrap"
    $defenderDescription.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)

    $defenderTextPanel.Children.Add($defenderTitle)
    $defenderTextPanel.Children.Add($defenderDescription)
    $defenderSettingsItem.Children.Add($defenderToggle)
    $defenderSettingsItem.Children.Add($defenderTextPanel)
    $modulePanel.Children.Add($defenderSettingsItem)

    # Optional MSAL.PS module check for Defender token acquisition
    $msalItem = New-Object System.Windows.Controls.StackPanel
    $msalItem.Style = $prereqWindow.FindResource("CheckItemStyle")
    $msalItem.Orientation = "Horizontal"

    $msalCheckbox = New-Object System.Windows.Controls.CheckBox
    $msalCheckbox.IsEnabled = $false
    $msalCheckbox.VerticalAlignment = "Center"
    $msalCheckbox.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)

    $msalTextPanel = New-Object System.Windows.Controls.StackPanel
    $msalTextPanel.Orientation = "Vertical"
    $msalTextPanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)

    $msalText = New-Object System.Windows.Controls.TextBlock
    $msalText.Text = "MSAL.PS"
    $msalText.Style = $prereqWindow.FindResource("CheckTextStyle")
    $msalText.FontWeight = "SemiBold"

    $msalDesc = New-Object System.Windows.Controls.TextBlock
    $msalDesc.Text = "Optional module used only for Defender for Endpoint token acquisition."
    $msalDesc.Style = $prereqWindow.FindResource("CheckTextStyle")
    $msalDesc.Foreground = "#666666"
    $msalDesc.FontSize = 12
    $msalDesc.TextWrapping = "Wrap"
    $msalDesc.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)

    $msalTextPanel.Children.Add($msalText)
    $msalTextPanel.Children.Add($msalDesc)

    $installMsalButton = New-Object System.Windows.Controls.Button
    $installMsalButton.Content = "Install"
    $installMsalButton.Style = $prereqWindow.FindResource("InstallButtonStyle")
    $installMsalButton.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)

    if (Get-Module -ListAvailable -Name "MSAL.PS") {
        $msalCheckbox.IsChecked = $true
        $msalCheckbox.Foreground = "#28A745"
        $installMsalButton.Visibility = "Collapsed"
    }
    else {
        $msalCheckbox.IsChecked = $false
        $msalCheckbox.Foreground = "#DC3545"
        $installMsalButton.Visibility = if (Get-DefenderIntegrationEnabled) { "Visible" } else { "Collapsed" }
    }

    $msalItem.Children.Add($msalCheckbox)
    $msalItem.Children.Add($msalTextPanel)
    $msalItem.Children.Add($installMsalButton)
    $modulePanel.Children.Add($msalItem)

    $defenderToggle.Add_Checked({
            Set-DefenderIntegrationEnabled -Enabled $true
            if (-not (Get-Module -ListAvailable -Name "MSAL.PS")) {
                $installMsalButton.Visibility = "Visible"
            }
        })

    $defenderToggle.Add_Unchecked({
            Set-DefenderIntegrationEnabled -Enabled $false
            if (-not (Get-Module -ListAvailable -Name "MSAL.PS")) {
                $installMsalButton.Visibility = "Collapsed"
            }
        })

    $installMsalButton.Add_Click({
            try {
                $installMsalButton.IsEnabled = $false
                $installMsalButton.Content = "Installing..."

                Install-Module "MSAL.PS" -Scope CurrentUser -Force -ErrorAction Stop

                $msalCheckbox.IsChecked = $true
                $msalCheckbox.Foreground = "#28A745"
                $installMsalButton.Visibility = "Collapsed"

                [System.Windows.MessageBox]::Show(
                    "MSAL.PS installed successfully. Please restart the application for changes to take effect.",
                    "Installation Complete",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )
            }
            catch {
                Write-Log "Error installing MSAL.PS module: $_"
                [System.Windows.MessageBox]::Show(
                    "Failed to install MSAL.PS. Please ensure you have internet connection and necessary permissions.",
                    "Installation Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
                $installMsalButton.IsEnabled = $true
                $installMsalButton.Content = "Install"
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
        Write-Log "Error showing prerequisites dialog: $_"
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
        if (Test-Path $script:LogDirectory) {
            Invoke-Item $script:LogDirectory
        }
        else {
            Show-Toast -Message "Log directory not found." -Type "info"
        }
    })
        
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

# Home page buttons
$HomeConnectButton = $Window.FindName('HomeConnectButton')
$HomeGetStartedTitle = $Window.FindName('HomeGetStartedTitle')
$HomeGetStartedDesc = $Window.FindName('HomeGetStartedDesc')
$HomeNavDashboard = $Window.FindName('HomeNavDashboard')
$HomeNavDeviceMgmt = $Window.FindName('HomeNavDeviceMgmt')
$HomeNavPlaybooks = $Window.FindName('HomeNavPlaybooks')

function Update-HomePageState {
    param([bool]$Connected)
    if ($Connected) {
        $HomeGetStartedTitle.Text = "Connected"
        $HomeGetStartedDesc.Text = "You are connected to Microsoft Graph. Use the navigation below or the sidebar to get started."
        $HomeConnectButton.Content = "Connected"
        $HomeConnectButton.IsEnabled = $false
        $HomeConnectButton.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2F855A')
        $HomeNavDashboard.ToolTip = "View device statistics and analytics"
        $HomeNavDeviceMgmt.ToolTip = "Search and offboard devices"
        $HomeNavPlaybooks.ToolTip = "Run automated reports and tasks"
    } else {
        $HomeGetStartedTitle.Text = "Get Started"
        $HomeGetStartedDesc.Text = "Sign in with Microsoft Graph to search, audit, and offboard devices across all connected services."
        $HomeConnectButton.Content = "Connect to Microsoft Graph"
        $HomeConnectButton.IsEnabled = $true
        $HomeConnectButton.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#0078D4')
        $HomeNavDashboard.ToolTip = "View device statistics and analytics (connect first)"
        $HomeNavDeviceMgmt.ToolTip = "Search and offboard devices (connect first)"
        $HomeNavPlaybooks.ToolTip = "Run automated reports and tasks (connect first)"
    }
}

# Wire HomeConnectButton to same handler as AuthenticateButton
$HomeConnectButton.Add_Click({
        $AuthenticateButton.RaiseEvent(
            (New-Object System.Windows.RoutedEventArgs(
                [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    })

# Wire quick nav buttons to sidebar menu
$HomeNavDashboard.Add_Click({ $MenuDashboard.IsChecked = $true })
$HomeNavDeviceMgmt.Add_Click({ $MenuDeviceManagement.IsChecked = $true })
$HomeNavPlaybooks.Add_Click({ $MenuPlaybooks.IsChecked = $true })

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
            Update-DashboardStatistics
            $DashboardLastRefreshed.Text = "Last refreshed: $(Get-Date -Format 'HH:mm:ss')"
        }
    })

$MenuDeviceManagement.Add_Checked({
        $HomePage.Visibility = 'Collapsed'
        $DashboardPage.Visibility = 'Collapsed'
        $DeviceManagementPage.Visibility = 'Visible'
        $PlaybooksPage.Visibility = 'Collapsed'
        $PlaybookResultsGrid.Visibility = 'Collapsed'
        # Auto-focus search input
        $Window.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [Action]{ if ($SearchInputText.Focus()) { $SearchInputText.SelectAll() } }
        )
    })

$MenuPlaybooks.Add_Checked({
        $HomePage.Visibility = 'Collapsed'
        $DashboardPage.Visibility = 'Collapsed'
        $DeviceManagementPage.Visibility = 'Collapsed'
        $PlaybooksPage.Visibility = 'Visible'
        $PlaybookResultsGrid.Visibility = 'Collapsed'
        $Window.FindName('PlaybooksScrollViewer').Visibility = 'Visible'
    })

# Global keyboard shortcuts
$Window.Add_PreviewKeyDown({
    param($sender, $e)
    # Ctrl+K: Navigate to Device Offboarding and focus search
    if ($e.Key -eq [System.Windows.Input.Key]::K -and
        ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        if ($MenuDeviceManagement.IsEnabled) {
            $e.Handled = $true
            if ($MenuDeviceManagement.IsChecked) {
                $SearchInputText.Focus()
                $SearchInputText.SelectAll()
            } else {
                $MenuDeviceManagement.IsChecked = $true
            }
        }
    }
    # Ctrl+B: Toggle sidebar
    if ($e.Key -eq [System.Windows.Input.Key]::B -and
        ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        $e.Handled = $true
        Set-SidebarState -Collapsed (-not $script:SidebarCollapsed)
    }
    # F5: Refresh dashboard when on Dashboard page
    if ($e.Key -eq [System.Windows.Input.Key]::F5) {
        if ($MenuDashboard.IsChecked -and $DashboardRefreshButton.IsEnabled) {
            $e.Handled = $true
            $DashboardRefreshButton.RaiseEvent(
                (New-Object System.Windows.RoutedEventArgs(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        }
    }
    # Escape: dismiss toast, collapse filter, clear search (contextual)
    if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
        # First priority: dismiss visible toast
        if ($ToastNotification.Visibility -eq 'Visible') {
            $e.Handled = $true
            Hide-Toast
        }
        # Second: collapse filter row if open
        elseif ($FilterRow.Visibility -eq 'Visible') {
            $e.Handled = $true
            $FilterRow.Visibility = 'Collapsed'
            $FilterToggleButton.Content = 'Filter'
        }
        # Third: clear search if search input has text and is on device management page
        elseif ($MenuDeviceManagement.IsChecked -and -not [string]::IsNullOrEmpty($SearchInputText.Text)) {
            $e.Handled = $true
            $ClearSearchButton.RaiseEvent(
                (New-Object System.Windows.RoutedEventArgs(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        }
    }
})

# Wire platform filter ComboBox
$DashboardPlatformFilter = $Window.FindName('DashboardPlatformFilter')
$DashboardPlatformFilter.Add_SelectionChanged({
        if (-not $AuthenticateButton.IsEnabled) {
            $selected = $DashboardPlatformFilter.SelectedItem.Content
            Update-DashboardStatistics -Platform $selected
        }
    })

# Wire Dashboard Refresh button
$DashboardRefreshButton = $Window.FindName('DashboardRefreshButton')
$DashboardLastRefreshed = $Window.FindName('DashboardLastRefreshed')
$DashboardRefreshButton.Add_Click({
        if (-not $AuthenticateButton.IsEnabled) {
            $DashboardRefreshButton.Content = "Refreshing..."
            $DashboardRefreshButton.IsEnabled = $false
            $Window.Cursor = [System.Windows.Input.Cursors]::Wait
            $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action]{})
            try {
                $selected = $DashboardPlatformFilter.SelectedItem.Content
                Update-DashboardStatistics -Platform $selected
                $DashboardLastRefreshed.Text = "Last refreshed: $(Get-Date -Format 'HH:mm:ss')"
            } finally {
                $DashboardRefreshButton.Content = "Refresh"
                $DashboardRefreshButton.IsEnabled = $true
                $Window.Cursor = $null
            }
        }
    })

function Update-DashboardStatistics {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Platform = "All Platforms"
    )

    try {
        Write-Log "Updating dashboard statistics (Platform: $Platform)..."
        $startTime = Get-Date

        # Build platform filter clause for $count queries
        $platformFilter = ""
        switch ($Platform) {
            "Windows" { $platformFilter = " and startswith(operatingSystem,'Windows')" }
            "macOS"   { $platformFilter = " and operatingSystem eq 'macOS'" }
            "iOS"     { $platformFilter = " and operatingSystem eq 'iOS'" }
            "Android" { $platformFilter = " and operatingSystem eq 'Android'" }
            "Linux"   { $platformFilter = " and operatingSystem eq 'Linux'" }
        }
        # For standalone filters (no preceding "and"), strip the leading " and "
        $platformFilterStandalone = if ($platformFilter) { $platformFilter.Substring(5) } else { "" }

        # Try $count batch approach first (single API call instead of fetching all devices)
        $countSuccess = $false
        try {
            $thirtyDaysAgo = (Get-Date).AddDays(-30).ToString('yyyy-MM-ddTHH:mm:ssZ')
            $ninetyDaysAgo = (Get-Date).AddDays(-90).ToString('yyyy-MM-ddTHH:mm:ssZ')
            $oneEightyDaysAgo = (Get-Date).AddDays(-180).ToString('yyyy-MM-ddTHH:mm:ssZ')

            # Build Intune/Entra count URLs with optional platform filter
            # Intune endpoints use ?$count=true&$top=1 (/$count path segment not supported in batch)
            $intuneCountUrl = if ($platformFilterStandalone) {
                "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=$platformFilterStandalone"
            } else {
                "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id"
            }
            $entraCountUrl = if ($platformFilterStandalone) {
                "/devices?`$count=true&`$top=1&`$select=id&`$filter=$platformFilterStandalone"
            } else {
                "/devices?`$count=true&`$top=1&`$select=id"
            }

            $batchBody = @{
                requests = @(
                    @{ id = "intune"; method = "GET"; url = $intuneCountUrl }
                    @{ id = "autopilot"; method = "GET"; url = "/deviceManagement/windowsAutopilotDeviceIdentities?`$count=true&`$top=1" }
                    @{ id = "entra"; method = "GET"; url = $entraCountUrl; headers = @{ "ConsistencyLevel" = "eventual" } }
                    @{ id = "stale30"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=lastSyncDateTime lt $thirtyDaysAgo$platformFilter" }
                    @{ id = "stale90"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=lastSyncDateTime lt $ninetyDaysAgo$platformFilter" }
                    @{ id = "stale180"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=lastSyncDateTime lt $oneEightyDaysAgo$platformFilter" }
                    @{ id = "personal"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=managedDeviceOwnerType eq 'personal'$platformFilter" }
                    @{ id = "corporate"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=managedDeviceOwnerType eq 'company'$platformFilter" }
                    @{ id = "osWindows"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=startswith(operatingSystem,'Windows')" }
                    @{ id = "osmacOS"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=operatingSystem eq 'macOS'" }
                    @{ id = "osiOS"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=operatingSystem eq 'iOS'" }
                    @{ id = "osAndroid"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=operatingSystem eq 'Android'" }
                    @{ id = "osLinux"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=operatingSystem eq 'Linux'" }
                )
            } | ConvertTo-Json -Depth 5

            $batchResponse = Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/`$batch" -Method POST -Body $batchBody -ContentType "application/json"
            $batchResponses = $batchResponse.responses
            Write-Log "Dashboard batch raw statuses: $(($batchResponses | ForEach-Object { "$($_.id)=$($_.status)" }) -join ', ')"

            # Helper to extract count from batch response (handles raw int, @odata.count, and hashtable wrapper)
            $getCount = {
                param([string]$id)
                $resp = $batchResponses | Where-Object { $_.id -eq $id }
                if (-not $resp -or $resp.status -ne 200) { return $null }
                $rawBody = $resp.body
                if ($null -eq $rawBody) { return $null }
                if ($rawBody -is [int] -or $rawBody -is [long]) { return [int]$rawBody }
                # Try @odata.count (from ?$count=true queries)
                try {
                    $odataCount = $rawBody.'@odata.count'
                    if ($null -ne $odataCount) { return [int]$odataCount }
                } catch {}
                # Try .value as raw int
                try {
                    $val = $rawBody.'value'
                    if ($null -ne $val -and ($val -is [int] -or $val -is [long])) { return [int]$val }
                } catch {}
                try { return [int]$rawBody } catch { return $null }
            }

            $intuneCount = & $getCount "intune"
            $autopilotCount = & $getCount "autopilot"
            $entraCount = & $getCount "entra"
            $stale30 = & $getCount "stale30"
            $stale90 = & $getCount "stale90"
            $stale180 = & $getCount "stale180"
            $personalDevices = & $getCount "personal"
            $corporateDevices = & $getCount "corporate"
            $osWindows = & $getCount "osWindows"
            $osmacOS = & $getCount "osmacOS"
            $osiOS = & $getCount "osiOS"
            $osAndroid = & $getCount "osAndroid"
            $osLinux = & $getCount "osLinux"

            # Log which counts failed and use defaults for non-critical ones
            $failedIds = @()
            if ($null -eq $intuneCount)  { $failedIds += "intune" }
            if ($null -eq $entraCount)   { $failedIds += "entra" }
            if ($failedIds.Count -gt 0) {
                throw "Core `$count queries failed: $($failedIds -join ', ')"
            }
            # Non-critical counts — default to 0 if the filter query is unsupported
            if ($null -eq $autopilotCount) {
                # Autopilot $count not supported in batch — fetch count directly
                try {
                    $apResponse = Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$top=1&`$count=true" -Method GET
                    $autopilotCount = if ($apResponse.'@odata.count') { [int]$apResponse.'@odata.count' } else { @($apResponse.value).Count }
                    Write-Log "Autopilot count fetched directly: $autopilotCount"
                } catch {
                    Write-Log "Autopilot count fetch failed, trying full list: $_" -Severity "WARN"
                    try {
                        $apAll = Get-GraphPagedResults -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
                        $autopilotCount = @($apAll).Count
                        Write-Log "Autopilot count from full list: $autopilotCount"
                    } catch {
                        Write-Log "Autopilot endpoint unavailable, defaulting to 0: $_" -Severity "WARN"
                        $autopilotCount = 0
                    }
                }
            }
            if ($null -eq $stale30)           { Write-Log "stale30 `$count returned null, defaulting to 0" -Severity "WARN";    $stale30 = 0 }
            if ($null -eq $stale90)           { Write-Log "stale90 `$count returned null, defaulting to 0" -Severity "WARN";    $stale90 = 0 }
            if ($null -eq $stale180)          { Write-Log "stale180 `$count returned null, defaulting to 0" -Severity "WARN";   $stale180 = 0 }
            if ($null -eq $personalDevices)   { Write-Log "personal `$count returned null, defaulting to 0" -Severity "WARN";   $personalDevices = 0 }
            if ($null -eq $corporateDevices)  { Write-Log "corporate `$count returned null, defaulting to 0" -Severity "WARN";  $corporateDevices = 0 }

            $countSuccess = $true
            $duration = (Get-Date) - $startTime
            Write-Log "Dashboard $count batch completed in $($duration.TotalSeconds) seconds"

            # Update top row counts
            $Window.FindName('IntuneDevicesCount').Text = $intuneCount
            $Window.FindName('AutopilotDevicesCount').Text = $autopilotCount
            $Window.FindName('EntraIDDevicesCount').Text = $entraCount

            Write-Log "Stale device counts - 30 days: $stale30, 90 days: $stale90, 180 days: $stale180"
            $Window.FindName('StaleDevices30Count').Text = $stale30
            $Window.FindName('StaleDevices90Count').Text = $stale90
            $Window.FindName('StaleDevices180Count').Text = $stale180

            # Update stale device progress bars
            $totalDevices = $intuneCount
            if ($totalDevices -gt 0) {
                $Window.FindName('StaleDevices30Progress').Value = [Math]::Round(($stale30 / $totalDevices) * 100)
                $Window.FindName('StaleDevices90Progress').Value = [Math]::Round(($stale90 / $totalDevices) * 100)
                $Window.FindName('StaleDevices180Progress').Value = [Math]::Round(($stale180 / $totalDevices) * 100)
            }

            # Update personal/corporate counts and progress bars
            $Window.FindName('PersonalDevicesCount').Text = $personalDevices
            $Window.FindName('CorporateDevicesCount').Text = $corporateDevices

            if ($totalDevices -gt 0) {
                $personalProgress = [Math]::Round(($personalDevices / $totalDevices) * 100)
                $corporateProgress = [Math]::Round(($corporateDevices / $totalDevices) * 100)
                $Window.FindName('PersonalDevicesProgress').Value = $personalProgress
                $Window.FindName('CorporateDevicesProgress').Value = $corporateProgress
            }

            # Build platform groups from $count results for pie chart
            # When a specific platform is selected, pie chart shows only that platform
            if ($platformFilterStandalone) {
                $platformGroups = @([PSCustomObject]@{ Name = $Platform; Count = $intuneCount })
            } else {
                if ($null -eq $osWindows) { $osWindows = 0 }
                if ($null -eq $osmacOS) { $osmacOS = 0 }
                if ($null -eq $osiOS) { $osiOS = 0 }
                if ($null -eq $osAndroid) { $osAndroid = 0 }
                if ($null -eq $osLinux) { $osLinux = 0 }
                $osOther = [Math]::Max(0, $intuneCount - ($osWindows + $osmacOS + $osiOS + $osAndroid + $osLinux))

                $platformGroups = @()
                if ($osWindows -gt 0) { $platformGroups += [PSCustomObject]@{ Name = 'Windows'; Count = $osWindows } }
                if ($osmacOS -gt 0) { $platformGroups += [PSCustomObject]@{ Name = 'macOS'; Count = $osmacOS } }
                if ($osiOS -gt 0) { $platformGroups += [PSCustomObject]@{ Name = 'iOS'; Count = $osiOS } }
                if ($osAndroid -gt 0) { $platformGroups += [PSCustomObject]@{ Name = 'Android'; Count = $osAndroid } }
                if ($osLinux -gt 0) { $platformGroups += [PSCustomObject]@{ Name = 'Linux'; Count = $osLinux } }
                if ($osOther -gt 0) { $platformGroups += [PSCustomObject]@{ Name = 'Other'; Count = $osOther } }
                $platformGroups = $platformGroups | Sort-Object Count -Descending
            }
        }
        catch {
            Write-Log "Dashboard `$count batch failed, falling back to full fetch: $_" -Severity "WARN"
        }

        # Fallback: full-fetch approach if $count batch failed
        if (-not $countSuccess) {
            $intuneDevices = @(Get-GraphPagedResults -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=deviceName,serialNumber,lastSyncDateTime,operatingSystem,managedDeviceOwnerType")
            $autopilotDevices = @()
            try {
                $autopilotDevices = @(Get-GraphPagedResults -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities")
            } catch {
                Write-Log "Autopilot fallback fetch failed (endpoint may be unavailable or permissions missing): $_" -Severity "WARN"
            }
            $entraDevices = @(Get-GraphPagedResults -Uri "https://graph.microsoft.com/beta/devices?`$select=displayName,operatingSystem,operatingSystemVersion")

            Write-Log "Fallback: Total devices - Intune: $($intuneDevices.Count), Autopilot: $($autopilotDevices.Count), Entra: $($entraDevices.Count)"

            $Window.FindName('IntuneDevicesCount').Text = $intuneDevices.Count
            $Window.FindName('AutopilotDevicesCount').Text = $autopilotDevices.Count
            $Window.FindName('EntraIDDevicesCount').Text = $entraDevices.Count

            # Calculate stale devices client-side
            $thirtyDaysAgo = (Get-Date).AddDays(-30)
            $ninetyDaysAgo = (Get-Date).AddDays(-90)
            $onehundredEightyDaysAgo = (Get-Date).AddDays(-180)

            $stale30 = ($intuneDevices | Where-Object {
                if ($_.lastSyncDateTime) {
                    try { $lastSync = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime; return $lastSync -and $lastSync -lt $thirtyDaysAgo }
                    catch { return $false }
                } else { return $false }
            }).Count
            $stale90 = ($intuneDevices | Where-Object {
                if ($_.lastSyncDateTime) {
                    try { $lastSync = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime; return $lastSync -and $lastSync -lt $ninetyDaysAgo }
                    catch { return $false }
                } else { return $false }
            }).Count
            $stale180 = ($intuneDevices | Where-Object {
                if ($_.lastSyncDateTime) {
                    try { $lastSync = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime; return $lastSync -and $lastSync -lt $onehundredEightyDaysAgo }
                    catch { return $false }
                } else { return $false }
            }).Count

            $Window.FindName('StaleDevices30Count').Text = $stale30
            $Window.FindName('StaleDevices90Count').Text = $stale90
            $Window.FindName('StaleDevices180Count').Text = $stale180

            $totalDevices = if ($intuneDevices) { $intuneDevices.Count } else { 0 }

            # Update stale device progress bars
            if ($totalDevices -gt 0) {
                $Window.FindName('StaleDevices30Progress').Value = [Math]::Round(($stale30 / $totalDevices) * 100)
                $Window.FindName('StaleDevices90Progress').Value = [Math]::Round(($stale90 / $totalDevices) * 100)
                $Window.FindName('StaleDevices180Progress').Value = [Math]::Round(($stale180 / $totalDevices) * 100)
            }

            $personalDevices = ($intuneDevices | Where-Object { $_.managedDeviceOwnerType -eq 'personal' }).Count
            $corporateDevices = ($intuneDevices | Where-Object { $_.managedDeviceOwnerType -eq 'company' }).Count

            $Window.FindName('PersonalDevicesCount').Text = $personalDevices
            $Window.FindName('CorporateDevicesCount').Text = $corporateDevices

            if ($totalDevices -gt 0) {
                $personalProgress = [Math]::Round(($personalDevices / $totalDevices) * 100)
                $corporateProgress = [Math]::Round(($corporateDevices / $totalDevices) * 100)
                $Window.FindName('PersonalDevicesProgress').Value = $personalProgress
                $Window.FindName('CorporateDevicesProgress').Value = $corporateProgress
            }

            # Group platform distribution client-side
            $platformGroups = $intuneDevices | Group-Object -Property {
                $os = $_.operatingSystem
                if ([string]::IsNullOrWhiteSpace($os)) { return "Unknown" }
                switch -Regex ($os.ToLower()) {
                    'windows' { "Windows" }
                    'macos|mac os' { "macOS" }
                    'linux' { "Linux" }
                    'ios' { "iOS" }
                    'android' { "Android" }
                    default { "Other" }
                }
            } | Sort-Object Count -Descending
        }

        # Draw pie chart from $platformGroups (works for both $count and fallback paths)
        $platformColors = @{
            'Windows' = '#0078D4'
            'iOS'     = '#48BB78'
            'Android' = '#9F7AEA'
            'macOS'   = '#F6AD55'
            'Linux'   = '#FC8181'
            'Other'   = '#718096'
            'Unknown' = '#718096'
        }

        $canvas = $Window.FindName('PlatformDistributionCanvas')
        $legendPanel = $Window.FindName('PlatformDistributionLegend')
        $canvas.Children.Clear()
        $legendPanel.Children.Clear()

        $total = ($platformGroups | Measure-Object Count -Sum).Sum
        if ($total -eq 0) { return }

        $centerX = 100
        $centerY = 100
        $radius = 80
        $startAngle = 0

        # Not $platform: names are case-insensitive and would collide with the [string]$Platform parameter
        foreach ($platformGroup in $platformGroups) {
            $percentage = $platformGroup.Count / $total
            # A full 360 degree arc has identical start/end points and WPF draws nothing
            $sweepAngle = [Math]::Min(360 * $percentage, 359.99)

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

            $lineSegment = New-Object System.Windows.Media.LineSegment(
                (New-Object System.Windows.Point($startX, $startY)), $true)
            $pathFigure.Segments.Add($lineSegment)

            $arcSegment = New-Object System.Windows.Media.ArcSegment(
                (New-Object System.Windows.Point($endX, $endY)),
                (New-Object System.Windows.Size($radius, $radius)),
                0,
                ($sweepAngle -gt 180),
                [System.Windows.Media.SweepDirection]::Clockwise,
                $true)
            $pathFigure.Segments.Add($arcSegment)

            $lineSegment = New-Object System.Windows.Media.LineSegment(
                (New-Object System.Windows.Point($centerX, $centerY)), $true)
            $pathFigure.Segments.Add($lineSegment)

            $pathGeometry.Figures.Add($pathFigure)
            $path.Data = $pathGeometry

            $pName = if ($platformGroup.Name) { $platformGroup.Name } else { 'Unknown' }
            $color = if ($platformColors[$pName]) { $platformColors[$pName] } else { $platformColors['Unknown'] }
            $path.Fill = New-Object System.Windows.Media.SolidColorBrush(
                [System.Windows.Media.ColorConverter]::ConvertFromString($color))

            $canvas.Children.Add($path)

            $legendItem = New-Object System.Windows.Controls.StackPanel
            $legendItem.Orientation = "Horizontal"
            $legendItem.Margin = New-Object System.Windows.Thickness(0, 0, 0, 5)

            $colorBox = New-Object System.Windows.Shapes.Rectangle
            $colorBox.Width = 12
            $colorBox.Height = 12
            $colorBox.Fill = $path.Fill
            $colorBox.Margin = New-Object System.Windows.Thickness(0, 0, 5, 0)

            $label = New-Object System.Windows.Controls.TextBlock
            $label.Text = "$pName ($([Math]::Round($percentage * 100))%)"
            $label.Foreground = "White"
            $label.VerticalAlignment = "Center"

            $legendItem.Children.Add($colorBox)
            $legendItem.Children.Add($label)
            $legendPanel.Children.Add($legendItem)

            $startAngle += $sweepAngle
        }

        Write-Log "Dashboard statistics updated successfully."
    }
    catch {
        Write-Log "Error updating dashboard statistics: $_"
        Show-Toast -Message "Error updating dashboard statistics. Please ensure you are connected to MS Graph." -Type "error" -DurationSeconds 6
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
    $Window.FindName('PlaybookFileVault'),
    $Window.FindName('PlaybookCorporateIdentifiers')
)

# Add click handlers for playbook buttons
# Add click handlers for playbook buttons
foreach ($button in $PlaybookButtons) {
    $button.Add_Click({
            if ($AuthenticateButton.IsEnabled) {
                Show-Toast -Message "Please connect to Microsoft Graph first." -Type "info"
                return
            }
            $playbookName = $this.Content.ToString()
            $playbookDescription = $this.Tag.ToString()
        
            switch ($playbookName) {
                "Autopilot Devices Not in Intune" {
                    $playbookPath = Join-Path (Get-PlaybookRoot) "Playbook_1.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "Intune Devices Not in Autopilot" {
                    $playbookPath = Join-Path (Get-PlaybookRoot) "Playbook_2.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "Corporate Device Inventory" {
                    $playbookPath = Join-Path (Get-PlaybookRoot) "Playbook_3.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "Personal Device Inventory" {
                    $playbookPath = Join-Path (Get-PlaybookRoot) "Playbook_4.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "Stale Device Report" {
                    $playbookPath = Join-Path (Get-PlaybookRoot) "Playbook_5.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "OS-Specific Device List" {
                    $selectedOS = Show-OSPickerDialog
                    if ($selectedOS) {
                        $playbookPath = Join-Path (Get-PlaybookRoot) "Playbook_6.ps1"
                        Invoke-Playbook -PlaybookName "$playbookName ($selectedOS)" -PlaybookPath $playbookPath -Description $playbookDescription -Parameters @{ OSFilter = $selectedOS }
                    }
                }
                "Outdated OS Report" {
                    $playbookPath = Join-Path (Get-PlaybookRoot) "Playbook_7.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "End-of-Life OS Report" {
                    $playbookPath = Join-Path (Get-PlaybookRoot) "Playbook_8.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "BitLocker Key Report" {
                    $playbookPath = Join-Path (Get-PlaybookRoot) "Playbook_9.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "FileVault Key Report" {
                    $playbookPath = Join-Path (Get-PlaybookRoot) "Playbook_10.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                "Corporate Identifier Stale Report" {
                    $playbookPath = Join-Path (Get-PlaybookRoot) "Playbook_11.ps1"
                    Invoke-Playbook -PlaybookName $playbookName -PlaybookPath $playbookPath -Description $playbookDescription
                }
                default {
                    Show-Toast -Message "This playbook is not yet implemented." -Type "info"
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
$SelectAllCheckBox.Content = "Select All"
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
            $SetGroupTagButton.IsEnabled = $allChecked
            if ($allChecked) {
                $count = @($SearchResultsDataGrid.ItemsSource).Count
                $SelectedDeviceCount.Text = "$count device(s) selected"
                $OffboardPanel.Visibility = 'Visible'
            } else {
                $OffboardPanel.Visibility = 'Collapsed'
            }
        }
    })

# Initially disable the Offboard button and Export Selected button
$OffboardButton.IsEnabled = $false
$ExportSelectedButton.IsEnabled = $false
$SetGroupTagButton.IsEnabled = $false

$SetGroupTagButton.Add_Click({
        if ($AuthenticateButton.IsEnabled) {
            Show-Toast -Message "Please connect to Microsoft Graph first." -Type "info"
            return
        }

        $selectedDevices = @($SearchResultsDataGrid.ItemsSource | Where-Object { $_.IsSelected })
        if (-not $selectedDevices -or $selectedDevices.Count -eq 0) {
            Show-Toast -Message "Select at least one device first." -Type "info"
            return
        }

        $groupTagResult = Show-GroupTagDialog
        if (-not $groupTagResult) {
            return
        }

        $tagText = if ($groupTagResult.Clear) { "(cleared)" } else { $groupTagResult.GroupTag }
        Write-Log "Starting Autopilot group tag update for $($selectedDevices.Count) selected device(s): $tagText" -Severity "AUDIT"
        $SetGroupTagButton.IsEnabled = $false
        try {
            $result = Set-AutopilotGroupTagForDevices -Devices $selectedDevices -GroupTag $groupTagResult.GroupTag
            if ($result.Failed -gt 0) {
                Show-Toast -Message "Group tag updated for $($result.Updated) device(s), failed for $($result.Failed). Check logs." -Type "warning" -DurationSeconds 7
            }
            else {
                Show-Toast -Message "Group tag updated for $($result.Updated) device(s)." -Type "success"
            }
        }
        catch {
            Write-Log "Group tag update failed: $_" -Severity "ERROR"
            Show-Toast -Message "Group tag update failed. Check logs." -Type "error" -DurationSeconds 6
        }
        finally {
            $selectedDevices = @($SearchResultsDataGrid.ItemsSource | Where-Object { $_.IsSelected })
            $SetGroupTagButton.IsEnabled = ($selectedDevices.Count -gt 0)
        }
    })

# Add click handler for "View" groups link in DataGrid
$SearchResultsDataGrid.Add_PreviewMouseDown({
        param($sender, $e)
        $element = $e.OriginalSource
        # Walk up the visual tree to find the TextBlock with Tag
        while ($element -and -not ($element -is [System.Windows.Controls.TextBlock] -and $element.Text -eq "View" -and $element.Tag)) {
            $element = [System.Windows.Media.VisualTreeHelper]::GetParent($element)
            if (-not $element -or $element -is [System.Windows.Controls.DataGrid]) { $element = $null; break }
        }
        if ($element -and $element.Tag) {
            $entraId = $element.Tag.ToString()
            if ($entraId) {
                # Find device name for display
                $deviceObj = $SearchResultsDataGrid.ItemsSource | Where-Object { $_.EntraDeviceId -eq $entraId } | Select-Object -First 1
                $devName = if ($deviceObj) { $deviceObj.DeviceName } else { "Device" }
                Show-DeviceGroupMembership -EntraDeviceId $entraId -DeviceName $devName
            } else {
                Show-Toast -Message "No Entra ID available for this device." -Type "info"
            }
        }
    })

# Add selection changed event handler for the DataGrid
$SearchResultsDataGrid.Add_SelectionChanged({
        # Update the Offboard button state based on selected devices
        $selectedDevices = $SearchResultsDataGrid.ItemsSource | Where-Object { $_.IsSelected }
        $hasSelection = ($null -ne $selectedDevices -and $selectedDevices.Count -gt 0)
        $OffboardButton.IsEnabled = $hasSelection
        $ExportSelectedButton.IsEnabled = $hasSelection
        $SetGroupTagButton.IsEnabled = $hasSelection
        if ($hasSelection) {
            $count = @($selectedDevices).Count
            $SelectedDeviceCount.Text = "$count device(s) selected"
            $OffboardPanel.Visibility = 'Visible'
        } else {
            $OffboardPanel.Visibility = 'Collapsed'
        }
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

                        # Update Offboard button state and panel visibility
                        $selectedDevices = $SearchResultsDataGrid.ItemsSource | Where-Object { $_.IsSelected }
                        $hasSelection = ($null -ne $selectedDevices -and $selectedDevices.Count -gt 0)
                        $OffboardButton.IsEnabled = $hasSelection
                        $ExportSelectedButton.IsEnabled = $hasSelection
                        $SetGroupTagButton.IsEnabled = $hasSelection
                        if ($hasSelection) {
                            $count = @($selectedDevices).Count
                            $SelectedDeviceCount.Text = "$count device(s) selected"
                            $OffboardPanel.Visibility = 'Visible'
                        } else {
                            $OffboardPanel.Visibility = 'Collapsed'
                        }
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

# Function to execute playbook
# Embedded copies of the bundled playbooks. Publish-Script/Install-Script only
# deliver this single .ps1, so gallery installs have no Playbooks/ directory;
# Get-PlaybookRoot extracts these to the config directory in that case.
# Keep in sync with the Playbooks/ directory.
$script:EmbeddedPlaybooks = [ordered]@{
    'PlaybookHelpers.ps1' = @'
# Shared helper functions for all playbooks
# Dot-source this file at the top of each playbook:
#   $helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
#   . $helpersPath

function ConvertTo-SafeDateTime {
    param(
        [Parameter(Mandatory = $false)]
        [string]$dateString
    )

    if ([string]::IsNullOrWhiteSpace($dateString)) {
        return $null
    }

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

    foreach ($format in $formats) {
        try {
            $parsedDate = [DateTime]::ParseExact($dateString, $format, $culture, [System.Globalization.DateTimeStyles]::None)
            if ($parsedDate -eq [DateTime]::MinValue) { return $null }
            return $parsedDate
        }
        catch { continue }
    }

    try {
        $parsedDate = [DateTime]::Parse($dateString, $culture)
        if ($parsedDate -eq [DateTime]::MinValue) { return $null }
        return $parsedDate
    }
    catch {
        Write-Warning "Failed to parse date: $dateString"
        return $null
    }
}

function Invoke-GraphRequestWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [string]$Method = "GET",
        [string]$Body,
        [string]$ContentType = "application/json",
        [hashtable]$Headers = @{},
        [int]$MaxRetries = 3,
        [int]$BaseDelaySeconds = 2
    )

    $attempt = 0
    while ($true) {
        try {
            $params = @{
                Uri        = $Uri
                Method     = $Method
                OutputType = 'Hashtable'
            }
            if ($Headers.Count -gt 0) { $params.Headers = $Headers }
            if ($Body) {
                $params.Body = $Body
                $params.ContentType = $ContentType
            }
            return Invoke-MgGraphCommunityRequest @params
        }
        catch {
            $attempt++
            # MgGraphCommunity surfaces Graph failures in the message text, e.g.
            # "Graph error 403 [Authorization_RequestDenied]: ..." or "HTTP 500 from <uri>"
            $statusCode = $null
            if ($_.Exception.Message -match '(?:Graph error|HTTP)\s+(\d{3})\b') {
                $statusCode = [int]$Matches[1]
            }

            if ($statusCode -eq 429) {
                if ($attempt -gt $MaxRetries) { throw }
                # Retry-After is honored inside Invoke-MgGraphCommunityRequest itself;
                # this outer retry handles sustained throttling with a plain delay.
                $retryAfter = $BaseDelaySeconds
                Write-Warning "Throttled (429) on $Method $Uri -- retrying in ${retryAfter}s (attempt $attempt/$MaxRetries)"
                Start-Sleep -Seconds $retryAfter
                continue
            }

            if ($null -eq $statusCode -or ($statusCode -ge 500 -and $statusCode -lt 600)) {
                if ($attempt -gt $MaxRetries) { throw }
                $delay = $BaseDelaySeconds * [Math]::Pow(2, $attempt - 1)
                Write-Warning "Server error ($statusCode) on $Method $Uri -- retrying in ${delay}s (attempt $attempt/$MaxRetries)"
                Start-Sleep -Seconds $delay
                continue
            }

            throw
        }
    }
}

function Get-GraphPagedResults {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [hashtable]$Headers = @{}
    )

    $results = @()
    $nextLink = $Uri

    do {
        try {
            $response = Invoke-GraphRequestWithRetry -Uri $nextLink -Method GET -Headers $Headers
            if ($response.value) {
                $results += $response.value
            }
            $nextLink = $response.'@odata.nextLink'
        }
        catch {
            Write-Error "Error in pagination: $_"
            break
        }
    } while ($nextLink)

    return $results
}

'@
    'Playbook_1.ps1' = @'
# Playbook: List all devices that are in Autopilot but not in Intune
# This script identifies devices that are registered in Windows Autopilot but not present in Intune management

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-AutopilotNotIntuneDevices {
    try {
        # Get all Autopilot devices
        Write-Host "Fetching Autopilot devices..." -ForegroundColor Cyan
        # No $select: the Autopilot endpoint returns HTTP 500 for any $select projection (Issue #65)
        $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
        $autopilotDevices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($autopilotDevices.Count) Autopilot devices" -ForegroundColor Green

        # Get all Intune devices
        Write-Host "Fetching Intune devices..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=serialNumber"
        $intuneDevices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($intuneDevices.Count) Intune devices" -ForegroundColor Green

        # Create a HashSet of Intune serial numbers for efficient lookup
        $intuneSerialNumbers = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($device in $intuneDevices) {
            if ($device.serialNumber) {
                $intuneSerialNumbers.Add($device.serialNumber) | Out-Null
            }
        }

        # Find devices in Autopilot but not in Intune using efficient HashSet lookup
        $notEnrolledDevices = $autopilotDevices | Where-Object {
            -not $intuneSerialNumbers.Contains($_.serialNumber)
        } | ForEach-Object {
            [PSCustomObject]@{
                DeviceName = $_.displayName
                SerialNumber = $_.serialNumber
                OperatingSystem = "$($_.model) ($($_.manufacturer))"
                PrimaryUser = "Not enrolled"
                AutopilotLastContact = ConvertTo-SafeDateTime -dateString $_.lastContactedDateTime
            }
        }

        Write-Host "Found $($notEnrolledDevices.Count) devices in Autopilot that are not enrolled in Intune" -ForegroundColor Yellow
        return $notEnrolledDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

# Execute the playbook and return results
$results = Get-AutopilotNotIntuneDevices
if ($results) {
    # Display results in console for debugging
    $results | Format-Table -AutoSize
}

# Return results to be displayed in UI
return $results

'@
    'Playbook_2.ps1' = @'
# Playbook: List all devices that are in Intune but not in Autopilot
# This script identifies devices that are managed in Intune but not registered in Windows Autopilot

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-IntuneNotAutopilotDevices {
    try {
        # Get all Autopilot devices
        Write-Host "Fetching Autopilot devices..." -ForegroundColor Cyan
        # No $select: the Autopilot endpoint returns HTTP 500 for any $select projection (Issue #65)
        $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
        $autopilotDevices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($autopilotDevices.Count) Autopilot devices" -ForegroundColor Green

        # Get all Intune devices
        Write-Host "Fetching Intune devices..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=id,deviceName,serialNumber,operatingSystem,model,userDisplayName,lastSyncDateTime"
        $intuneDevices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($intuneDevices.Count) Intune devices" -ForegroundColor Green

        # Create a HashSet of Autopilot serial numbers for efficient lookup
        $autopilotSerialNumbers = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($device in $autopilotDevices) {
            if ($device.serialNumber) {
                $autopilotSerialNumbers.Add($device.serialNumber) | Out-Null
            }
        }

        # Find devices in Intune but not in Autopilot using efficient HashSet lookup
        $notInAutopilotDevices = $intuneDevices | Where-Object {
            $_.serialNumber -and -not $autopilotSerialNumbers.Contains($_.serialNumber)
        } | ForEach-Object {
            [PSCustomObject]@{
                DeviceName        = $_.deviceName
                SerialNumber      = $_.serialNumber
                OperatingSystem   = $_.operatingSystem
                Model             = $_.model
                PrimaryUser       = $_.userDisplayName
                IntuneLastContact = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime
            }
        }

        Write-Host "Found $($notInAutopilotDevices.Count) devices in Intune that are not registered in Autopilot" -ForegroundColor Yellow
        return $notInAutopilotDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

# Execute the playbook and return results
$results = Get-IntuneNotAutopilotDevices
if ($results) {
    # Display results in console for debugging
    $results | Format-Table -AutoSize
}

# Return results to be displayed in UI
return $results
'@
    'Playbook_3.ps1' = @'
# Playbook: List all corporate devices in Intune
# This script identifies all company-owned devices managed in Intune

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-CorporateDevices {
    try {
        # Get all corporate devices from Intune
        Write-Host "Fetching corporate devices from Intune..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=managedDeviceOwnerType eq 'company'&`$select=deviceName,serialNumber,operatingSystem,model,managedDeviceOwnerType,lastSyncDateTime"
        $corporateDevices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($corporateDevices.Count) corporate devices" -ForegroundColor Green

        # Format the devices for display
        $formattedDevices = $corporateDevices | ForEach-Object {
            [PSCustomObject]@{
                DeviceName        = $_.deviceName
                SerialNumber      = $_.serialNumber
                OperatingSystem   = $_.operatingSystem
                Model             = $_.model
                OwnershipType     = $_.managedDeviceOwnerType
                IntuneLastContact = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime
            }
        }

        Write-Host "Successfully processed $($formattedDevices.Count) corporate devices" -ForegroundColor Yellow
        return $formattedDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

# Execute the playbook and return results
$results = Get-CorporateDevices
if ($results) {
    # Display results in console for debugging
    $results | Format-Table -AutoSize
}

# Return results to be displayed in UI
return $results
'@
    'Playbook_4.ps1' = @'
# Playbook: List all personal devices in Intune
# This script identifies all personally-owned devices managed in Intune

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-PersonalDevices {
    try {
        # Get all personal devices from Intune
        Write-Host "Fetching personal devices from Intune..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=managedDeviceOwnerType eq 'personal'&`$select=deviceName,serialNumber,operatingSystem,model,managedDeviceOwnerType,lastSyncDateTime"
        $personalDevices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($personalDevices.Count) personal devices" -ForegroundColor Green

        # Format the devices for display
        $formattedDevices = $personalDevices | ForEach-Object {
            [PSCustomObject]@{
                DeviceName        = $_.deviceName
                SerialNumber      = $_.serialNumber
                OperatingSystem   = $_.operatingSystem
                Model             = $_.model
                OwnershipType     = $_.managedDeviceOwnerType
                IntuneLastContact = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime
            }
        }

        Write-Host "Successfully processed $($formattedDevices.Count) personal devices" -ForegroundColor Yellow
        return $formattedDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

# Execute the playbook and return results
$results = Get-PersonalDevices
if ($results) {
    # Display results in console for debugging
    $results | Format-Table -AutoSize
}

# Return results to be displayed in UI
return $results
'@
    'Playbook_5.ps1' = @'
# Playbook: List all stale devices in Intune
# This script identifies devices that haven't checked in for a specified number of days

param(
    [int]$StaleDays = 30 # Default to 30 days if not specified
)

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-StaleDevices {
    param(
        [int]$StaleDays = 30
    )
    
    try {
        # Calculate the stale date threshold
        $staleDate = (Get-Date).AddDays(-$StaleDays)
        $staleDateString = $staleDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
        
        # Get all stale devices from Intune
        Write-Host "Fetching devices not synced since $staleDateString..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=lastSyncDateTime lt $staleDateString&`$select=deviceName,serialNumber,operatingSystem,model,managedDeviceOwnerType,lastSyncDateTime"
        $staleDevices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($staleDevices.Count) stale devices" -ForegroundColor Green

        # Format the devices for display and calculate days since last sync
        $formattedDevices = $staleDevices | ForEach-Object {
            $lastSyncDate = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime
            $diffDays = if ($lastSyncDate) { 
                [Math]::Ceiling(([DateTime]::Now - $lastSyncDate).TotalDays)
            }
            else { 
                "Unknown" 
            }
            
            [PSCustomObject]@{
                DeviceName        = $_.deviceName
                SerialNumber      = $_.serialNumber
                OperatingSystem   = $_.operatingSystem
                Model             = $_.model
                OwnershipType     = $_.managedDeviceOwnerType
                IntuneLastContact = $lastSyncDate
                DaysSinceLastSync = $diffDays
            }
        }

        # Sort by days since last sync (descending)
        $formattedDevices = $formattedDevices | Sort-Object -Property DaysSinceLastSync -Descending

        Write-Host "Successfully processed $($formattedDevices.Count) stale devices" -ForegroundColor Yellow
        return $formattedDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

# Execute the playbook and return results
$results = Get-StaleDevices -StaleDays $StaleDays
if ($results) {
    # Display results in console for debugging
    $results | Format-Table -AutoSize
}

# Return results to be displayed in UI
return $results
'@
    'Playbook_6.ps1' = @'
# Playbook: List devices by operating system
# This script filters managed devices by a specified operating system

param(
    [string]$OSFilter = "Windows"
)

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-OSSpecificDevices {
    param(
        [string]$OSFilter = "Windows"
    )

    try {
        Write-Host "Fetching $OSFilter devices from Intune..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=operatingSystem eq '$OSFilter'&`$select=deviceName,serialNumber,operatingSystem,model,osVersion,lastSyncDateTime,userDisplayName"
        $devices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($devices.Count) $OSFilter devices" -ForegroundColor Green

        $formattedDevices = $devices | ForEach-Object {
            [PSCustomObject]@{
                DeviceName        = $_.deviceName
                SerialNumber      = $_.serialNumber
                OperatingSystem   = $_.operatingSystem
                Model             = $_.model
                OSVersion         = $_.osVersion
                IntuneLastContact = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime
                PrimaryUser       = $_.userDisplayName
            }
        }

        Write-Host "Successfully processed $($formattedDevices.Count) devices" -ForegroundColor Yellow
        return $formattedDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

$results = Get-OSSpecificDevices -OSFilter $OSFilter
if ($results) {
    $results | Format-Table -AutoSize
}

return $results

'@
    'Playbook_7.ps1' = @'
# Playbook: Find devices running outdated OS versions
# This script compares device OS versions against known latest versions

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-OutdatedOSDevices {
    # Latest known OS versions (update these as new versions release)
    $latestVersions = @{
        "Windows" = "10.0.26100"   # Windows 11 24H2
        "macOS"   = "15.3"
        "iOS"     = "18.3"
        "Android" = "15"
    }

    try {
        Write-Host "Fetching all managed devices..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=deviceName,serialNumber,operatingSystem,osVersion,lastSyncDateTime"
        $devices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($devices.Count) total devices" -ForegroundColor Green

        $outdatedDevices = @()
        foreach ($device in $devices) {
            $os = $device.operatingSystem
            $currentVersion = $device.osVersion

            if (-not $currentVersion -or -not $os) { continue }

            $latestVersion = $null
            foreach ($key in $latestVersions.Keys) {
                if ($os -match $key) {
                    $latestVersion = $latestVersions[$key]
                    break
                }
            }

            if (-not $latestVersion) { continue }

            # Compare versions - device is outdated if its version is less than the latest
            try {
                $currentParts = $currentVersion -split '\.' | ForEach-Object { [int]$_ }
                $latestParts = $latestVersion -split '\.' | ForEach-Object { [int]$_ }

                $isOutdated = $false
                $maxParts = [Math]::Max($currentParts.Count, $latestParts.Count)
                for ($i = 0; $i -lt $maxParts; $i++) {
                    $c = if ($i -lt $currentParts.Count) { $currentParts[$i] } else { 0 }
                    $l = if ($i -lt $latestParts.Count) { $latestParts[$i] } else { 0 }
                    if ($c -lt $l) { $isOutdated = $true; break }
                    if ($c -gt $l) { break }
                }

                if ($isOutdated) {
                    $outdatedDevices += [PSCustomObject]@{
                        DeviceName        = $device.deviceName
                        SerialNumber      = $device.serialNumber
                        OperatingSystem   = $os
                        CurrentVersion    = $currentVersion
                        LatestVersion     = $latestVersion
                        IntuneLastContact = ConvertTo-SafeDateTime -dateString $device.lastSyncDateTime
                    }
                }
            }
            catch {
                # Skip devices with unparseable versions
                continue
            }
        }

        Write-Host "Found $($outdatedDevices.Count) devices with outdated OS" -ForegroundColor Yellow
        return $outdatedDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

$results = Get-OutdatedOSDevices
if ($results) {
    $results | Format-Table -AutoSize
}

return $results

'@
    'Playbook_8.ps1' = @'
# Playbook: Identify devices running end-of-life OS versions
# This script checks devices against known OS end-of-life dates

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-EOLDevices {
    # End-of-life dates for OS versions (OS name pattern -> EOL date)
    $eolTable = @(
        @{ Pattern = "^10\.0\.(1904[0-3]|1836[0-7]|1776[0-5]|1713[0-4]|1658[0-9]|1600[0-9]|1439[0-3]|1058[0-6]|1024[0-0])"; OS = "Windows 10"; EOLDate = "2025-10-14" }
        @{ Pattern = "^12\."; OS = "macOS 12 Monterey"; EOLDate = "2024-09-16" }
        @{ Pattern = "^13\."; OS = "macOS 13 Ventura"; EOLDate = "2025-10-01" }
        @{ Pattern = "^16\."; OS = "iOS 16"; EOLDate = "2024-09-16" }
        @{ Pattern = "^17\."; OS = "iOS 17"; EOLDate = "2025-09-15" }
        @{ Pattern = "^13$|^13\."; OS = "Android 13"; EOLDate = "2025-03-01" }
    )

    try {
        Write-Host "Fetching all managed devices..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=deviceName,serialNumber,operatingSystem,osVersion,lastSyncDateTime"
        $devices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($devices.Count) total devices" -ForegroundColor Green

        $eolDevices = @()
        $today = Get-Date

        foreach ($device in $devices) {
            $osVersion = $device.osVersion
            $osName = $device.operatingSystem
            if (-not $osVersion) { continue }

            foreach ($eolEntry in $eolTable) {
                $matchVersion = $osVersion
                # For Windows, use the full build number; for others use osVersion directly
                if ($osName -eq "Windows" -and $osVersion -match "^10\.0\.(\d+)") {
                    $matchVersion = $osVersion
                } elseif ($osName -ne "Windows") {
                    $matchVersion = $osVersion
                }

                if ($matchVersion -match $eolEntry.Pattern) {
                    $eolDate = [DateTime]::Parse($eolEntry.EOLDate)
                    $daysPast = [Math]::Ceiling(($today - $eolDate).TotalDays)

                    $eolDevices += [PSCustomObject]@{
                        DeviceName        = $device.deviceName
                        SerialNumber      = $device.serialNumber
                        OperatingSystem   = "$osName ($($eolEntry.OS))"
                        OSVersion         = $osVersion
                        EndOfSupportDate  = $eolEntry.EOLDate
                        DaysPastEOL       = $daysPast
                    }
                    break
                }
            }
        }

        $eolDevices = $eolDevices | Sort-Object -Property DaysPastEOL -Descending
        Write-Host "Found $($eolDevices.Count) devices running EOL operating systems" -ForegroundColor Yellow
        return $eolDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

$results = Get-EOLDevices
if ($results) {
    $results | Format-Table -AutoSize
}

return $results

'@
    'Playbook_9.ps1' = @'
# Playbook: BitLocker Key Report
# This script retrieves BitLocker recovery key metadata for all Windows devices

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-BitLockerKeyReport {
    try {
        # Get all BitLocker recovery keys (metadata only, not actual key values)
        Write-Host "Fetching BitLocker recovery key metadata..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys?`$select=id,createdDateTime,deviceId,volumeType"
        $recoveryKeys = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($recoveryKeys.Count) BitLocker recovery keys" -ForegroundColor Green

        if ($recoveryKeys.Count -eq 0) {
            Write-Host "No BitLocker recovery keys found" -ForegroundColor Yellow
            return @([PSCustomObject]@{
                DeviceName      = "No keys found"
                SerialNumber    = "N/A"
                KeyId           = "N/A"
                VolumeType      = "N/A"
                CreatedDateTime = $null
            })
        }

        # Get unique device IDs and resolve device names
        $deviceIds = $recoveryKeys | Select-Object -ExpandProperty deviceId -Unique | Where-Object { $_ }
        Write-Host "Resolving device names for $($deviceIds.Count) devices..." -ForegroundColor Cyan

        $deviceInfoMap = @{}
        foreach ($deviceId in $deviceIds) {
            try {
                # Get device name from Entra
                $uri = "https://graph.microsoft.com/beta/devices?`$filter=deviceId eq '$deviceId'&`$select=displayName"
                $device = (Get-GraphPagedResults -Uri $uri) | Select-Object -First 1
                $devName = if ($device) { $device.displayName } else { "Unknown Device" }

                # Get serial number from Intune via azureADDeviceId
                $serialNumber = "N/A"
                try {
                    $intuneUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=azureADDeviceId eq '$deviceId'&`$select=serialNumber"
                    $intuneDevice = (Get-GraphPagedResults -Uri $intuneUri) | Select-Object -First 1
                    if ($intuneDevice -and $intuneDevice.serialNumber) {
                        $serialNumber = $intuneDevice.serialNumber
                    }
                } catch {}

                $deviceInfoMap[$deviceId] = @{ Name = $devName; Serial = $serialNumber }
            }
            catch {
                continue
            }
        }

        $formattedKeys = $recoveryKeys | ForEach-Object {
            $info = if ($_.deviceId -and $deviceInfoMap.ContainsKey($_.deviceId)) {
                $deviceInfoMap[$_.deviceId]
            } else { @{ Name = "Unknown Device"; Serial = "N/A" } }

            [PSCustomObject]@{
                DeviceName      = $info.Name
                SerialNumber    = $info.Serial
                KeyId           = $_.id
                VolumeType      = $_.volumeType
                CreatedDateTime = ConvertTo-SafeDateTime -dateString $_.createdDateTime
            }
        }

        Write-Host "Successfully processed $($formattedKeys.Count) BitLocker keys" -ForegroundColor Yellow
        return $formattedKeys
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

$results = Get-BitLockerKeyReport
if ($results) {
    $results | Format-Table -AutoSize
}

return $results

'@
    'Playbook_10.ps1' = @'
# Playbook: FileVault Key Report
# This script checks FileVault key availability for all macOS devices

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-FileVaultKeyReport {
    try {
        Write-Host "Fetching macOS devices from Intune..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=operatingSystem eq 'macOS'&`$select=id,deviceName,serialNumber,lastSyncDateTime"
        $macDevices = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($macDevices.Count) macOS devices" -ForegroundColor Green

        if ($macDevices.Count -eq 0) {
            Write-Host "No macOS devices found" -ForegroundColor Yellow
            return @([PSCustomObject]@{
                DeviceName        = "No macOS devices found"
                SerialNumber      = "N/A"
                HasFileVaultKey   = "N/A"
                IntuneLastContact = $null
            })
        }

        Write-Host "Checking FileVault key availability for each device..." -ForegroundColor Cyan
        $formattedDevices = @()
        $counter = 0

        foreach ($device in $macDevices) {
            $counter++
            if ($counter % 10 -eq 0) {
                Write-Host "  Checked $counter of $($macDevices.Count) devices..." -ForegroundColor Gray
            }

            $hasKey = $false
            try {
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$($device.id)')/getFileVaultKey"
                $keyResponse = Invoke-MgGraphCommunityRequest -OutputType Hashtable -Uri $uri -Method GET
                if ($keyResponse.value) {
                    $hasKey = $true
                }
            }
            catch {
                # 404 or other error means no key available
                $hasKey = $false
            }

            $formattedDevices += [PSCustomObject]@{
                DeviceName        = $device.deviceName
                SerialNumber      = $device.serialNumber
                HasFileVaultKey   = if ($hasKey) { "Yes" } else { "No" }
                IntuneLastContact = ConvertTo-SafeDateTime -dateString $device.lastSyncDateTime
            }
        }

        Write-Host "Successfully processed $($formattedDevices.Count) macOS devices" -ForegroundColor Yellow
        return $formattedDevices
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

$results = Get-FileVaultKeyReport
if ($results) {
    $results | Format-Table -AutoSize
}

return $results

'@
    'Playbook_11.ps1' = @'
# Playbook: Corporate Identifier Stale Report
# This script lists imported corporate device identifiers and their last contact state.

$helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
. $helpersPath

function Get-CorporateIdentifierStaleReport {
    try {
        Write-Host "Fetching imported corporate device identifiers..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/importedDeviceIdentities?`$select=id,importedDeviceIdentifier,importedDeviceIdentityType,lastModifiedDateTime,createdDateTime,lastContactedDateTime,description,enrollmentState,platform"
        $identifiers = Get-GraphPagedResults -Uri $uri
        Write-Host "Found $($identifiers.Count) imported device identifiers" -ForegroundColor Green

        if ($identifiers.Count -eq 0) {
            Write-Host "No imported device identifiers found" -ForegroundColor Yellow
            return @([PSCustomObject]@{
                Identifier            = "No imported identifiers found"
                Type                  = "N/A"
                Platform              = "N/A"
                EnrollmentState       = "N/A"
                Description           = "N/A"
                CreatedDateTime       = $null
                LastModifiedDateTime  = $null
                LastContactedDateTime = $null
                DaysSinceLastContact  = $null
                ContactState          = "N/A"
            })
        }

        $now = Get-Date
        $formattedIdentifiers = $identifiers | ForEach-Object {
            $lastContact = ConvertTo-SafeDateTime -dateString $_.lastContactedDateTime
            $daysSinceLastContact = if ($lastContact) { [Math]::Round(($now - $lastContact).TotalDays, 1) } else { $null }
            $contactState = if (-not $lastContact) {
                "Never Contacted"
            }
            elseif ($daysSinceLastContact -ge 180) {
                "Stale 180+ Days"
            }
            elseif ($daysSinceLastContact -ge 90) {
                "Stale 90+ Days"
            }
            elseif ($daysSinceLastContact -ge 30) {
                "Stale 30+ Days"
            }
            else {
                "Recent"
            }

            [PSCustomObject]@{
                Identifier            = $_.importedDeviceIdentifier
                Type                  = $_.importedDeviceIdentityType
                Platform              = $_.platform
                EnrollmentState       = $_.enrollmentState
                Description           = $_.description
                CreatedDateTime       = ConvertTo-SafeDateTime -dateString $_.createdDateTime
                LastModifiedDateTime  = ConvertTo-SafeDateTime -dateString $_.lastModifiedDateTime
                LastContactedDateTime = $lastContact
                DaysSinceLastContact  = $daysSinceLastContact
                ContactState          = $contactState
            }
        }

        $formattedIdentifiers = $formattedIdentifiers | Sort-Object @{ Expression = { if ($null -eq $_.DaysSinceLastContact) { [double]::PositiveInfinity } else { $_.DaysSinceLastContact } }; Descending = $true }, Identifier
        Write-Host "Successfully processed $($formattedIdentifiers.Count) corporate identifiers" -ForegroundColor Yellow
        return $formattedIdentifiers
    }
    catch {
        Write-Error "Error executing playbook: $_"
        return $null
    }
}

$results = Get-CorporateIdentifierStaleReport
if ($results) {
    $results | Format-Table -AutoSize
}

return $results

'@
}

$script:ResolvedPlaybookRoot = $null

function Get-PlaybookRoot {
    if ($script:ResolvedPlaybookRoot -and (Test-Path (Join-Path $script:ResolvedPlaybookRoot "PlaybookHelpers.ps1"))) {
        return $script:ResolvedPlaybookRoot
    }

    # Repo/ZIP layout: Playbooks/ sits next to the script.
    if ($PSScriptRoot) {
        $localRoot = Join-Path $PSScriptRoot "Playbooks"
        if (Test-Path (Join-Path $localRoot "PlaybookHelpers.ps1")) {
            $script:ResolvedPlaybookRoot = $localRoot
            return $localRoot
        }
    }

    # Install-Script layout: only the .ps1 was delivered, so extract the
    # embedded playbooks into the per-user config directory.
    $extractRoot = Join-Path $script:ConfigDirectory "Playbooks"
    if (-not (Test-Path $extractRoot)) {
        New-Item -Path $extractRoot -ItemType Directory -Force | Out-Null
    }
    foreach ($name in $script:EmbeddedPlaybooks.Keys) {
        Set-Content -Path (Join-Path $extractRoot $name) -Value $script:EmbeddedPlaybooks[$name] -Force
    }
    Write-Log "Extracted $($script:EmbeddedPlaybooks.Keys.Count) bundled playbooks to $extractRoot"
    $script:ResolvedPlaybookRoot = $extractRoot
    return $extractRoot
}

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
        Write-Log "Error showing changelog dialog: $_"
        [System.Windows.MessageBox]::Show(
            "Error showing changelog dialog: $_",
            "Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
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
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $fileName = "Playbook_Results_${timestamp}.csv"
            Export-DeviceListToCSV -DeviceList $results -DefaultFileName $fileName
        }
        else {
            Show-Toast -Message "No results to export." -Type "info"
        }
    })

# Connect dashboard card click handlers
$StaleDevices30Card = $Window.FindName('StaleDevices30Card')
$StaleDevices30Card.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Show-Toast -Message "Loading devices..." -Type "info" -DurationSeconds 3
                $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action] {})
                Write-Log "Fetching 30-day stale devices..."
                $thirtyDaysAgo = (Get-Date).AddDays(-30)
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=lastSyncDateTime lt $($thirtyDaysAgo.ToString('yyyy-MM-ddTHH:mm:ssZ'))&`$select=deviceName,serialNumber,lastSyncDateTime,operatingSystem,osVersion,userPrincipalName,managedDeviceOwnerType"
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
                Show-Toast -Message "Error fetching stale devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

$StaleDevices90Card = $Window.FindName('StaleDevices90Card')
$StaleDevices90Card.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Show-Toast -Message "Loading devices..." -Type "info" -DurationSeconds 3
                $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action] {})
                Write-Log "Fetching 90-day stale devices..."
                $ninetyDaysAgo = (Get-Date).AddDays(-90)
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=lastSyncDateTime lt $($ninetyDaysAgo.ToString('yyyy-MM-ddTHH:mm:ssZ'))&`$select=deviceName,serialNumber,lastSyncDateTime,operatingSystem,osVersion,userPrincipalName,managedDeviceOwnerType"
                $staleDevices = Get-GraphPagedResults -Uri $uri

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

                $title = "90 Day Stale Devices"

                Show-DashboardCardResults -Title $title -DeviceList $deviceList
            }
            catch {
                Write-Log "Error fetching stale devices: $_"
                Show-Toast -Message "Error fetching stale devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

$StaleDevices180Card = $Window.FindName('StaleDevices180Card')
$StaleDevices180Card.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Show-Toast -Message "Loading devices..." -Type "info" -DurationSeconds 3
                $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action] {})
                Write-Log "Fetching 180-day stale devices..."
                $hundredEightyDaysAgo = (Get-Date).AddDays(-180)
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=lastSyncDateTime lt $($hundredEightyDaysAgo.ToString('yyyy-MM-ddTHH:mm:ssZ'))&`$select=deviceName,serialNumber,lastSyncDateTime,operatingSystem,osVersion,userPrincipalName,managedDeviceOwnerType"
                $staleDevices = Get-GraphPagedResults -Uri $uri

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

                $title = "180 Day Stale Devices"

                Show-DashboardCardResults -Title $title -DeviceList $deviceList
            }
            catch {
                Write-Log "Error fetching stale devices: $_"
                Show-Toast -Message "Error fetching stale devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

$PersonalDevicesCard = $Window.FindName('PersonalDevicesCard')
$PersonalDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Show-Toast -Message "Loading devices..." -Type "info" -DurationSeconds 3
                $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action] {})
                Write-Log "Fetching personal devices..."
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=managedDeviceOwnerType eq 'personal'&`$select=deviceName,serialNumber,lastSyncDateTime,operatingSystem,osVersion,userPrincipalName,managedDeviceOwnerType"
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
                Show-Toast -Message "Error fetching personal devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

$CorporateDevicesCard = $Window.FindName('CorporateDevicesCard')
$CorporateDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Show-Toast -Message "Loading devices..." -Type "info" -DurationSeconds 3
                $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action] {})
                Write-Log "Fetching corporate devices..."
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=managedDeviceOwnerType eq 'company'&`$select=deviceName,serialNumber,lastSyncDateTime,operatingSystem,osVersion,userPrincipalName,managedDeviceOwnerType"
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
                Show-Toast -Message "Error fetching corporate devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

# Connect total device count card click handlers
$IntuneDevicesCard = $Window.FindName('IntuneDevicesCard')
$IntuneDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Show-Toast -Message "Loading devices..." -Type "info" -DurationSeconds 3
                $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action] {})
                Write-Log "Fetching all Intune devices..."
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=deviceName,serialNumber,lastSyncDateTime,operatingSystem,osVersion,userPrincipalName,managedDeviceOwnerType"
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
                Show-Toast -Message "Error fetching Intune devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

$AutopilotDevicesCard = $Window.FindName('AutopilotDevicesCard')
$AutopilotDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Show-Toast -Message "Loading devices..." -Type "info" -DurationSeconds 3
                $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action] {})
                Write-Log "Fetching all Autopilot devices..."
                $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
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
                Show-Toast -Message "Error fetching Autopilot devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

$EntraIDDevicesCard = $Window.FindName('EntraIDDevicesCard')
$EntraIDDevicesCard.Add_MouseLeftButtonUp({
        if (-not $AuthenticateButton.IsEnabled) {
            $previousCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Show-Toast -Message "Loading devices..." -Type "info" -DurationSeconds 3
                $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action] {})
                Write-Log "Fetching all Entra ID devices..."
                $uri = "https://graph.microsoft.com/beta/devices?`$select=displayName,operatingSystem,operatingSystemVersion,approximateLastSignInDateTime,deviceOwnership"
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

                Show-DashboardCardResults -Title $title -DeviceList $deviceList
            }
            catch {
                Write-Log "Error fetching Entra ID devices: $_"
                Show-Toast -Message "Error fetching Entra ID devices. Check logs for details." -Type "error" -DurationSeconds 6
            }
            finally {
                $Window.Cursor = $previousCursor
            }
        }
    })

# Connect changelog button
$changelog_button = $Window.FindName('changelog_button')
$changelog_button.Add_Click({
        Show-ChangelogDialog
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
