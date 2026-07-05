using System.Text;
using System.Text.Json.Nodes;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.Services.Graph;
using DeviceOffboardingManager.WinUI.Utilities;

namespace DeviceOffboardingManager.WinUI.Services;

public sealed class RecoveryKeyService : IRecoveryKeyService
{
    private readonly GraphApiClient _graph;
    private readonly IAuditLogService _auditLog;

    public RecoveryKeyService(GraphApiClient graph, IAuditLogService auditLog)
    {
        _graph = graph;
        _auditLog = auditLog;
    }

    public async Task<IReadOnlyList<RecoveryKeyRecord>> GetRecoveryKeysAsync(
        IReadOnlyCollection<DeviceRecord> devices,
        CancellationToken cancellationToken = default)
    {
        var results = new List<RecoveryKeyRecord>();
        foreach (var device in devices)
        {
            JsonNode? intuneDetails = null;
            if (!string.IsNullOrWhiteSpace(device.IntuneDeviceId))
            {
                try
                {
                    intuneDetails = await _graph.SendAsync(
                        HttpMethod.Get,
                        $"/deviceManagement/managedDevices/{device.IntuneDeviceId}?$select=operatingSystem,azureADDeviceId,serialNumber",
                        cancellationToken: cancellationToken);
                }
                catch (Exception ex)
                {
                    await _auditLog.WriteAsync($"Could not load Intune details for recovery key lookup on {device.DeviceName}: {ex.Message}", "WARN", cancellationToken);
                }
            }

            results.Add(await GetPlatformRecoveryKeyAsync(device, intuneDetails, cancellationToken));
            results.Add(await GetLapsPasswordAsync(device, intuneDetails, cancellationToken));
        }

        return results;
    }

    private async Task<RecoveryKeyRecord> GetPlatformRecoveryKeyAsync(DeviceRecord device, JsonNode? intuneDetails, CancellationToken cancellationToken)
    {
        var os = intuneDetails.GetStringValue("operatingSystem") ?? device.OperatingSystem;
        if (string.Equals(os, "Windows", StringComparison.OrdinalIgnoreCase))
        {
            return await GetBitLockerKeyAsync(device, intuneDetails, cancellationToken);
        }

        if (string.Equals(os, "macOS", StringComparison.OrdinalIgnoreCase))
        {
            return await GetFileVaultKeyAsync(device, cancellationToken);
        }

        return new RecoveryKeyRecord
        {
            DeviceName = device.DeviceName,
            KeyType = "Encryption",
            Status = "Encryption key not applicable for this device type."
        };
    }

    private async Task<RecoveryKeyRecord> GetBitLockerKeyAsync(DeviceRecord device, JsonNode? intuneDetails, CancellationToken cancellationToken)
    {
        try
        {
            var deviceId = device.EntraDeviceObjectId ?? intuneDetails.GetStringValue("azureADDeviceId");
            if (string.IsNullOrWhiteSpace(deviceId))
            {
                return new RecoveryKeyRecord { DeviceName = device.DeviceName, KeyType = "BitLocker", Status = "No Entra device ID available." };
            }

            var keys = await _graph.GetPagedAsync(
                OData.Query("/informationProtection/bitlocker/recoveryKeys", ("$filter", $"deviceId eq '{OData.StringLiteral(deviceId)}'")),
                cancellationToken: cancellationToken);
            var keyId = keys.FirstOrDefault().GetStringValue("id");
            if (string.IsNullOrWhiteSpace(keyId))
            {
                return new RecoveryKeyRecord { DeviceName = device.DeviceName, KeyType = "BitLocker", Status = "No BitLocker recovery key found." };
            }

            var keyDetails = await _graph.SendAsync(HttpMethod.Get, $"/informationProtection/bitlocker/recoveryKeys/{keyId}?$select=key", cancellationToken: cancellationToken);
            var key = keyDetails.GetStringValue("key");
            if (!string.IsNullOrWhiteSpace(key))
            {
                await _auditLog.WriteAsync($"Retrieved BitLocker recovery key for {device.DeviceName}.", "AUDIT", cancellationToken);
            }

            return new RecoveryKeyRecord { DeviceName = device.DeviceName, KeyType = "BitLocker", KeyValue = key, Status = string.IsNullOrWhiteSpace(key) ? "Key metadata found but key value missing." : "Found" };
        }
        catch (Exception ex)
        {
            await _auditLog.WriteAsync($"Error retrieving BitLocker key for {device.DeviceName}: {ex.Message}", "ERROR", cancellationToken);
            return new RecoveryKeyRecord { DeviceName = device.DeviceName, KeyType = "BitLocker", Status = ex.Message };
        }
    }

    private async Task<RecoveryKeyRecord> GetFileVaultKeyAsync(DeviceRecord device, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(device.IntuneDeviceId))
        {
            return new RecoveryKeyRecord { DeviceName = device.DeviceName, KeyType = "FileVault", Status = "No Intune device ID available." };
        }

        try
        {
            var response = await _graph.SendAsync(
                HttpMethod.Get,
                $"/deviceManagement/managedDevices('{device.IntuneDeviceId}')/getFileVaultKey",
                cancellationToken: cancellationToken);
            var key = response.GetStringValue("value");
            if (!string.IsNullOrWhiteSpace(key))
            {
                await _auditLog.WriteAsync($"Retrieved FileVault recovery key for {device.DeviceName}.", "AUDIT", cancellationToken);
            }

            return new RecoveryKeyRecord { DeviceName = device.DeviceName, KeyType = "FileVault", KeyValue = key, Status = string.IsNullOrWhiteSpace(key) ? "No FileVault recovery key found." : "Found" };
        }
        catch (Exception ex)
        {
            await _auditLog.WriteAsync($"Error retrieving FileVault key for {device.DeviceName}: {ex.Message}", "ERROR", cancellationToken);
            return new RecoveryKeyRecord { DeviceName = device.DeviceName, KeyType = "FileVault", Status = ex.Message };
        }
    }

    private async Task<RecoveryKeyRecord> GetLapsPasswordAsync(DeviceRecord device, JsonNode? intuneDetails, CancellationToken cancellationToken)
    {
        try
        {
            var deviceId = device.EntraDeviceObjectId ?? intuneDetails.GetStringValue("azureADDeviceId");
            if (string.IsNullOrWhiteSpace(deviceId))
            {
                return new RecoveryKeyRecord { DeviceName = device.DeviceName, KeyType = "LAPS", Status = "No Entra device ID available." };
            }

            var response = await _graph.SendAsync(
                HttpMethod.Get,
                $"/directory/deviceLocalCredentials/{deviceId}?$select=credentials",
                cancellationToken: cancellationToken);
            var latest = response.GetArrayValues("credentials")
                .OrderByDescending(credential => credential.GetDateTimeOffsetValue("backupDateTime"))
                .FirstOrDefault();
            if (latest is null)
            {
                return new RecoveryKeyRecord { DeviceName = device.DeviceName, KeyType = "LAPS", Status = "No LAPS password found." };
            }

            var passwordBase64 = latest.GetStringValue("passwordBase64");
            var password = string.IsNullOrWhiteSpace(passwordBase64)
                ? null
                : Encoding.UTF8.GetString(Convert.FromBase64String(passwordBase64));
            var accountName = latest.GetStringValue("accountName");
            if (!string.IsNullOrWhiteSpace(password))
            {
                await _auditLog.WriteAsync($"Retrieved LAPS password for {device.DeviceName} (account '{accountName}').", "AUDIT", cancellationToken);
            }

            return new RecoveryKeyRecord { DeviceName = device.DeviceName, KeyType = "LAPS", AccountName = accountName, KeyValue = password, Status = string.IsNullOrWhiteSpace(password) ? "Password metadata found but value missing." : "Found" };
        }
        catch (Exception ex)
        {
            await _auditLog.WriteAsync($"Error retrieving LAPS password for {device.DeviceName}: {ex.Message}", "ERROR", cancellationToken);
            return new RecoveryKeyRecord { DeviceName = device.DeviceName, KeyType = "LAPS", Status = ex.Message };
        }
    }
}
