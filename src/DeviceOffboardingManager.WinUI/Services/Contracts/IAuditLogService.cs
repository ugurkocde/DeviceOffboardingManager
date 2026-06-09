namespace DeviceOffboardingManager.WinUI.Services.Contracts;

public interface IAuditLogService
{
    string LogFilePath { get; }

    Task WriteAsync(string message, string severity = "INFO", CancellationToken cancellationToken = default);
}
