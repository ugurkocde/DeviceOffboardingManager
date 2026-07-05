namespace DeviceOffboardingManager.WinUI.Services;

public sealed class ConnectionState
{
    private bool _isConnected;

    public event Action? Changed;

    public bool IsConnected => _isConnected;

    public void SetConnected(bool isConnected)
    {
        if (_isConnected == isConnected)
        {
            return;
        }

        _isConnected = isConnected;
        Changed?.Invoke();
    }
}
