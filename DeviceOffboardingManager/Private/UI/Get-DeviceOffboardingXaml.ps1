function Get-DeviceOffboardingXaml {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('MainWindow', 'ChangelogDialog', 'PrerequisitesDialog', 'AuthenticationDialog', 'BulkImportDialog')]
        [string]$Name
    )

    $fileName = switch ($Name) {
        'MainWindow' { 'MainWindow.xaml' }
        'ChangelogDialog' { 'ChangelogDialog.xaml' }
        'PrerequisitesDialog' { 'PrerequisitesDialog.xaml' }
        'AuthenticationDialog' { 'AuthenticationDialog.xaml' }
        'BulkImportDialog' { 'BulkImportDialog.xaml' }
    }

    $path = Join-Path $script:DeviceOffboardingManagerModuleRoot "UI/$fileName"
    if (-not (Test-Path $path)) {
        throw "Missing XAML resource: $path"
    }

    return [xml](Get-Content -Path $path -Raw)
}
