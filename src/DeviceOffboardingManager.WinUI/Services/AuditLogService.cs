using DeviceOffboardingManager.WinUI.Services.Contracts;

namespace DeviceOffboardingManager.WinUI.Services;

public sealed class AuditLogService : IAuditLogService
{
    private readonly SemaphoreSlim _writeLock = new(1, 1);

    public AuditLogService()
    {
        var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        var logDirectory = Path.Combine(desktop, "DOM_Logs");
        Directory.CreateDirectory(logDirectory);
        LogFilePath = Path.Combine(logDirectory, $"DOM_WinUI_{DateTime.Now:yyyyMMdd_HHmmss}.log");
    }

    public string LogFilePath { get; }

    public async Task WriteAsync(string message, string severity = "INFO", CancellationToken cancellationToken = default)
    {
        var line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} | {severity} | {message}{Environment.NewLine}";
        await _writeLock.WaitAsync(cancellationToken);
        try
        {
            await File.AppendAllTextAsync(LogFilePath, line, cancellationToken);
        }
        finally
        {
            _writeLock.Release();
        }
    }
}
