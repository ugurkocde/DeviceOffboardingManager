function Hide-Toast {
    $script:ToastGeneration++
    $gen = $script:ToastGeneration
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
    $slideOut.Add_Completed({ if ($script:ToastGeneration -eq $gen) { $ToastNotification.Visibility = 'Collapsed' } }.GetNewClosure())
    $ToastNotification.RenderTransform.BeginAnimation(
        [System.Windows.Media.TranslateTransform]::YProperty, $slideOut)
}
