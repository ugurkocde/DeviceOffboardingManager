function Show-Toast {
    param(
        [string]$Message,
        [ValidateSet('success','error','info','warning')][string]$Type = 'info',
        [int]$DurationSeconds = 4
    )
    $script:ToastGeneration++
    if ($script:ToastTimer) { $script:ToastTimer.Stop() }
    $bgColor = switch ($Type) {
        'success' { '#2F855A' }
        'error'   { '#C53030' }
        'info'    { '#2B6CB0' }
        'warning' { '#B7791F' }
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
    $script:ToastTimer.Add_Tick({ Hide-Toast }.GetNewClosure())
    $script:ToastTimer.Start()
}
