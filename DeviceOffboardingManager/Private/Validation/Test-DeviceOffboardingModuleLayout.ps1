function Test-DeviceOffboardingModuleLayout {
    $moduleRoot = $script:DeviceOffboardingManagerModuleRoot
    $requiredFiles = @(
        'DeviceOffboardingManager.psd1',
        'DeviceOffboardingManager.psm1',
        'Public/Start-DeviceOffboardingManager.ps1',
        'Private/Runtime/Start-DeviceOffboardingManager.Runtime.ps1',
        'UI/MainWindow.xaml',
        'UI/AuthenticationDialog.xaml',
        'UI/BulkImportDialog.xaml',
        'UI/ChangelogDialog.xaml',
        'UI/PrerequisitesDialog.xaml',
        'Playbooks/PlaybookHelpers.ps1'
    )

    $missingFiles = foreach ($relativePath in $requiredFiles) {
        $path = Join-Path $moduleRoot $relativePath
        if (-not (Test-Path $path)) { $relativePath }
    }

    $parseErrors = New-Object System.Collections.Generic.List[string]
    foreach ($path in Get-ChildItem -Path $moduleRoot -Recurse -Filter '*.ps1') {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        foreach ($errorRecord in $errors) {
            $parseErrors.Add("$($path.FullName): $($errorRecord.Message)")
        }
    }

    $xamlErrors = New-Object System.Collections.Generic.List[string]
    foreach ($path in Get-ChildItem -Path (Join-Path $moduleRoot 'UI') -Filter '*.xaml') {
        try {
            [xml](Get-Content -Path $path.FullName -Raw) | Out-Null
        }
        catch {
            $xamlErrors.Add("$($path.FullName): $($_.Exception.Message)")
        }
    }

    $playbookFiles = Get-ChildItem -Path (Join-Path $moduleRoot 'Playbooks') -Filter 'Playbook_*.ps1' -ErrorAction SilentlyContinue
    $result = [pscustomobject]@{
        ModuleRoot    = $moduleRoot
        MissingFiles  = @($missingFiles)
        ParseErrors   = @($parseErrors)
        XamlErrors    = @($xamlErrors)
        PlaybookCount = @($playbookFiles).Count
        IsValid       = (-not $missingFiles -and $parseErrors.Count -eq 0 -and $xamlErrors.Count -eq 0 -and @($playbookFiles).Count -ge 11)
    }

    if (-not $result.IsValid) {
        throw "DeviceOffboardingManager module layout validation failed: $($result | ConvertTo-Json -Compress)"
    }

    return $result
}
