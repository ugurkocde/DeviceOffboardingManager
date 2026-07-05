namespace DeviceOffboardingManager.WinUI.Services;

public sealed class ShellNavigationService
{
    public event Action<string>? NavigationRequested;

    public void Navigate(string tag)
    {
        NavigationRequested?.Invoke(tag);
    }
}
