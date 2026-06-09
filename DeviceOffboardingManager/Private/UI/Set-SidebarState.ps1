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
