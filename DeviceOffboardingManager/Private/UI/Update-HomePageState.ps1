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
