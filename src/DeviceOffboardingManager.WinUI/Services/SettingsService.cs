using System.Text.Json;
using System.Text.Json.Nodes;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;

namespace DeviceOffboardingManager.WinUI.Services;

public sealed class SettingsService : ISettingsService
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    private readonly IAuditLogService _auditLog;

    public SettingsService(IAuditLogService auditLog)
    {
        _auditLog = auditLog;
    }

    private static string SettingsDirectory
    {
        get
        {
            var path = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "DeviceOffboardingManager");
            Directory.CreateDirectory(path);
            return path;
        }
    }

    private static string SettingsPath => Path.Combine(SettingsDirectory, "settings.winui.json");

    public async Task<DeviceOffboardingSettings> LoadAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(SettingsPath))
        {
            return new DeviceOffboardingSettings();
        }

        await using var stream = File.OpenRead(SettingsPath);
        var settings = await JsonSerializer.DeserializeAsync<DeviceOffboardingSettings>(stream, SerializerOptions, cancellationToken);
        return settings ?? new DeviceOffboardingSettings();
    }

    public async Task SaveAsync(DeviceOffboardingSettings settings, CancellationToken cancellationToken = default)
    {
        await using var stream = File.Create(SettingsPath);
        await JsonSerializer.SerializeAsync(stream, settings, SerializerOptions, cancellationToken);
        await _auditLog.WriteAsync("Saved WinUI settings.", "AUDIT", cancellationToken);
    }

    public async Task<DeviceOffboardingSettings> ImportAppRegistrationConfigAsync(string path, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            throw new ArgumentException("Config path is required.", nameof(path));
        }

        if (!File.Exists(path))
        {
            throw new FileNotFoundException("Config file was not found.", path);
        }

        var existing = await LoadAsync(cancellationToken);
        var json = JsonNode.Parse(await File.ReadAllTextAsync(path, cancellationToken)) as JsonObject
            ?? throw new InvalidOperationException("Config file is not a JSON object.");

        var tenantId = GetConfigValue(json, "TenantId", "tenantId", "tenant_id") ?? existing.TenantId;
        var clientId = GetConfigValue(json, "ClientId", "AppId", "appId", "client_id") ?? existing.ClientId;
        var thumbprint = GetConfigValue(json, "CertificateThumbprint", "Thumbprint", "thumbprint") ?? existing.CertificateThumbprint;

        var imported = existing with
        {
            TenantId = tenantId,
            ClientId = clientId,
            CertificateThumbprint = thumbprint
        };

        await SaveAsync(imported, cancellationToken);
        await _auditLog.WriteAsync($"Imported app registration config from {path}.", "AUDIT", cancellationToken);
        return imported;
    }

    private static string? GetConfigValue(JsonObject json, params string[] names)
    {
        foreach (var name in names)
        {
            if (json.TryGetPropertyValue(name, out var value))
            {
                return value?.GetValue<string>();
            }
        }

        return null;
    }
}
