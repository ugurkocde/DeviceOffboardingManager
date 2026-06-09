function Test-DeviceOffboardingWindowsUi {
    Initialize-DeviceOffboardingAssemblies
    Initialize-DeviceObjectType

    $resources = @{
        MainWindow = @(
            'AuthenticateButton',
            'SearchButton',
            'OffboardButton',
            'ExportSelectedButton',
            'SetGroupTagButton',
            'SearchResultsDataGrid',
            'MenuHome',
            'MenuDashboard',
            'MenuDeviceManagement',
            'MenuPlaybooks',
            'PlaybookResultsDataGrid',
            'DashboardRefreshButton',
            'DashboardPlatformFilter'
        )
        AuthenticationDialog = @(
            'InteractiveAuth',
            'DeviceCodeAuth',
            'CertificateAuth',
            'SecretAuth',
            'ConnectButton',
            'CancelAuthButton'
        )
        BulkImportDialog = @(
            'BrowseFileButton',
            'DownloadTemplateButton',
            'PreviewDataGrid',
            'ImportButton',
            'CancelButton'
        )
        ChangelogDialog = @(
            'ChangelogContent',
            'CloseChangelogButton'
        )
        PrerequisitesDialog = @(
            'PermissionsPanel',
            'ModulePanel',
            'ClosePrereqButton'
        )
    }

    $loadedResources = New-Object System.Collections.Generic.List[string]
    $missingControls = New-Object System.Collections.Generic.List[string]

    foreach ($resourceName in $resources.Keys) {
        $xaml = Get-DeviceOffboardingXaml -Name $resourceName
        $reader = New-Object System.Xml.XmlNodeReader $xaml
        $window = [Windows.Markup.XamlReader]::Load($reader)
        if ($null -eq $window) {
            throw "Failed to load WPF resource: $resourceName"
        }

        foreach ($controlName in $resources[$resourceName]) {
            if ($null -eq $window.FindName($controlName)) {
                $missingControls.Add("${resourceName}:${controlName}")
            }
        }

        $loadedResources.Add($resourceName)
        if ($window -is [System.Windows.Window]) {
            $window.Close()
        }
    }

    if ($missingControls.Count -gt 0) {
        throw "Missing WPF controls: $($missingControls -join ', ')"
    }

    [pscustomobject]@{
        IsWindows       = $IsWindows
        LoadedResources = @($loadedResources)
        CheckedControls = ($resources.Values | ForEach-Object { $_ }).Count
        IsValid         = $true
    }
}
