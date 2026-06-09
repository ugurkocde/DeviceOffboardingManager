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
