using System.Text.Json.Nodes;
using DeviceOffboardingManager.WinUI.Graph;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.Services.Graph;
using DeviceOffboardingManager.WinUI.Utilities;

namespace DeviceOffboardingManager.WinUI.Services;

public sealed class DeviceInventoryService : IDeviceInventoryService
{
    private const string EntraSelect = "id,deviceId,displayName,operatingSystem,approximateLastSignInDateTime,accountEnabled,physicalIds";
    private const string IntuneSelect = "id,deviceName,serialNumber,operatingSystem,userDisplayName,lastSyncDateTime,azureADDeviceId,complianceState,managementAgent";

    private readonly GraphApiClient _graph;
    private readonly IAuditLogService _auditLog;

    public DeviceInventoryService(GraphApiClient graph, IAuditLogService auditLog)
    {
        _graph = graph;
        _auditLog = auditLog;
    }

    public async Task<DeviceSearchResult> SearchDevicesAsync(
        IReadOnlyCollection<string> searchTerms,
        DeviceSearchOption searchOption,
        CancellationToken cancellationToken = default)
    {
        var devices = new List<DeviceRecord>();
        IReadOnlyList<JsonNode>? allAutopilotDevices = null;

        if (searchOption is DeviceSearchOption.DeviceName or DeviceSearchOption.Contains)
        {
            allAutopilotDevices = await GetAllAutopilotDevicesAsync(cancellationToken);
        }

        foreach (var rawTerm in searchTerms)
        {
            var term = rawTerm.Trim();
            if (string.IsNullOrWhiteSpace(term))
            {
                continue;
            }

            var matches = searchOption switch
            {
                DeviceSearchOption.DeviceName => await SearchByDeviceNameAsync(term, allAutopilotDevices ?? Array.Empty<JsonNode>(), cancellationToken),
                DeviceSearchOption.SerialNumber => await SearchBySerialNumberAsync(term, cancellationToken),
                DeviceSearchOption.DeviceId => await SearchByDeviceIdAsync(term, cancellationToken),
                DeviceSearchOption.Contains => await SearchContainsAsync(term, allAutopilotDevices ?? Array.Empty<JsonNode>(), cancellationToken),
                _ => Array.Empty<DeviceRecord>()
            };

            AddDistinct(devices, matches);
        }

        return new DeviceSearchResult
        {
            Devices = devices,
            EntraCount = devices.Count(d => !string.IsNullOrWhiteSpace(d.EntraDeviceId)),
            IntuneCount = devices.Count(d => !string.IsNullOrWhiteSpace(d.IntuneDeviceId)),
            AutopilotCount = devices.Count(d => !string.IsNullOrWhiteSpace(d.AutopilotIdentityId))
        };
    }

    public async Task<DashboardSummary> GetDashboardSummaryAsync(CancellationToken cancellationToken = default)
    {
        var ninetyDaysAgo = DateTimeOffset.UtcNow.AddDays(-90).ToString("O");
        var thirtyDaysAgo = DateTimeOffset.UtcNow.AddDays(-30).ToString("O");
        var oneEightyDaysAgo = DateTimeOffset.UtcNow.AddDays(-180).ToString("O");

        var headers = new Dictionary<string, string> { ["ConsistencyLevel"] = "eventual" };
        var entraTask = _graph.GetCountAsync("https://graph.microsoft.com/beta/devices/$count", headers, cancellationToken);
        var intuneTask = _graph.GetCountAsync("https://graph.microsoft.com/beta/deviceManagement/managedDevices/$count", cancellationToken);
        var autopilotTask = _graph.GetCountAsync("https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$count", cancellationToken);
        var stale30Task = CountWithFallbackAsync(OData.Query("/deviceManagement/managedDevices", ("$filter", $"lastSyncDateTime lt {thirtyDaysAgo}"), ("$count", "true")), cancellationToken);
        var stale90Task = CountWithFallbackAsync(OData.Query("/deviceManagement/managedDevices", ("$filter", $"lastSyncDateTime lt {ninetyDaysAgo}"), ("$count", "true")), cancellationToken);
        var stale180Task = CountWithFallbackAsync(OData.Query("/deviceManagement/managedDevices", ("$filter", $"lastSyncDateTime lt {oneEightyDaysAgo}"), ("$count", "true")), cancellationToken);
        var personalTask = CountWithFallbackAsync(OData.Query("/deviceManagement/managedDevices", ("$filter", "managedDeviceOwnerType eq 'personal'"), ("$count", "true")), cancellationToken);
        var corporateTask = CountWithFallbackAsync(OData.Query("/deviceManagement/managedDevices", ("$filter", "managedDeviceOwnerType eq 'company'"), ("$count", "true")), cancellationToken);

        return new DashboardSummary
        {
            EntraDevices = await SafeCountAsync(entraTask, cancellationToken),
            IntuneDevices = await SafeCountAsync(intuneTask, cancellationToken),
            AutopilotDevices = await SafeCountAsync(autopilotTask, cancellationToken),
            StaleDevices30Days = await stale30Task,
            StaleDevices90Days = await stale90Task,
            StaleDevices180Days = await stale180Task,
            PersonalDevices = await personalTask,
            CorporateDevices = await corporateTask
        };
    }

    public async Task<GroupTagUpdateResult> SetAutopilotGroupTagAsync(
        IReadOnlyCollection<DeviceRecord> devices,
        string groupTag,
        CancellationToken cancellationToken = default)
    {
        var updated = 0;
        var failed = 0;
        foreach (var device in devices)
        {
            try
            {
                var autopilotId = device.AutopilotIdentityId;
                if (string.IsNullOrWhiteSpace(autopilotId) && !string.IsNullOrWhiteSpace(device.SerialNumber))
                {
                    autopilotId = (await GetAutopilotDeviceBySerialAsync(device.SerialNumber, cancellationToken))?.GetStringValue("id");
                }

                if (string.IsNullOrWhiteSpace(autopilotId))
                {
                    failed++;
                    await _auditLog.WriteAsync($"Cannot set group tag for {device.DeviceName}: no Autopilot identity.", "WARN", cancellationToken);
                    continue;
                }

                await _graph.SendAsync(
                    HttpMethod.Post,
                    $"/deviceManagement/windowsAutopilotDeviceIdentities/{autopilotId}/updateDeviceProperties",
                    new { groupTag },
                    cancellationToken: cancellationToken);
                updated++;
                await _auditLog.WriteAsync($"Set Autopilot group tag for {device.DeviceName} to '{groupTag}'.", "AUDIT", cancellationToken);
            }
            catch (Exception ex)
            {
                failed++;
                await _auditLog.WriteAsync($"Failed to set Autopilot group tag for {device.DeviceName}: {ex.Message}", "ERROR", cancellationToken);
            }
        }

        return new GroupTagUpdateResult { Updated = updated, Failed = failed };
    }

    private async Task<int> CountWithFallbackAsync(string collectionUrl, CancellationToken cancellationToken)
    {
        try
        {
            var values = await _graph.GetPagedAsync(collectionUrl, cancellationToken: cancellationToken);
            return values.Count;
        }
        catch (Exception ex)
        {
            await _auditLog.WriteAsync($"Dashboard count fallback failed for {collectionUrl}: {ex.Message}", "WARN", cancellationToken);
            return 0;
        }
    }

    private async Task<int> SafeCountAsync(Task<int> task, CancellationToken cancellationToken)
    {
        try
        {
            return await task;
        }
        catch (Exception ex)
        {
            await _auditLog.WriteAsync($"Dashboard count failed: {ex.Message}", "WARN", cancellationToken);
            return 0;
        }
    }

    private async Task<IReadOnlyList<DeviceRecord>> SearchByDeviceNameAsync(string term, IReadOnlyList<JsonNode> allAutopilotDevices, CancellationToken cancellationToken)
    {
        var literal = OData.StringLiteral(term);
        var batch = await _graph.BatchAsync(
        new[]
        {
            new GraphBatchRequest("entra", "GET", OData.Query("/devices", ("$filter", $"displayName eq '{literal}'"), ("$select", EntraSelect))),
            new GraphBatchRequest("intune", "GET", OData.Query("/deviceManagement/managedDevices", ("$filter", $"deviceName eq '{literal}'"), ("$select", IntuneSelect)))
        }, cancellationToken);

        var entraDevices = GetBatchValue(batch, "entra");
        var intuneDevices = GetBatchValue(batch, "intune");
        var autopilotDevices = allAutopilotDevices
            .Where(device => OData.SameIdentifier(device.GetStringValue("displayName"), term))
            .ToArray();

        return await CombineDevicesAsync(entraDevices, intuneDevices, autopilotDevices, cancellationToken);
    }

    private async Task<IReadOnlyList<DeviceRecord>> SearchBySerialNumberAsync(string term, CancellationToken cancellationToken)
    {
        var literal = OData.StringLiteral(term);
        var batch = await _graph.BatchAsync(
        new[]
        {
            new GraphBatchRequest("intune", "GET", OData.Query("/deviceManagement/managedDevices", ("$filter", $"contains(serialNumber,'{literal}')"), ("$select", IntuneSelect))),
            new GraphBatchRequest("autopilot", "GET", OData.Query("/deviceManagement/windowsAutopilotDeviceIdentities", ("$filter", $"contains(serialNumber,'{literal}')")))
        }, cancellationToken);

        var intuneDevices = GetBatchValue(batch, "intune");
        var autopilotDevices = GetBatchValue(batch, "autopilot");
        var records = new List<DeviceRecord>();

        foreach (var intuneDevice in intuneDevices)
        {
            var entraDevice = await GetEntraDeviceForIntuneDeviceAsync(intuneDevice, cancellationToken);
            var autopilotDevice = SelectMatchingAutopilotDevice(autopilotDevices, intuneDevice.GetStringValue("serialNumber"), intuneDevice.GetStringValue("deviceName"));
            records.Add(ToDeviceRecord(entraDevice, intuneDevice, autopilotDevice));
        }

        foreach (var autopilotDevice in autopilotDevices)
        {
            if (records.Any(record => OData.SameIdentifier(record.SerialNumber, autopilotDevice.GetStringValue("serialNumber"))))
            {
                continue;
            }

            records.Add(ToDeviceRecord(null, null, autopilotDevice));
        }

        return records;
    }

    private async Task<IReadOnlyList<DeviceRecord>> SearchByDeviceIdAsync(string term, CancellationToken cancellationToken)
    {
        JsonNode? entraDevice = null;
        try
        {
            entraDevice = await _graph.SendAsync(HttpMethod.Get, $"/devices/{Uri.EscapeDataString(term)}", cancellationToken: cancellationToken);
        }
        catch
        {
            var literal = OData.StringLiteral(term);
            var matches = await _graph.GetPagedAsync(
                OData.Query("/devices", ("$filter", $"deviceId eq '{literal}'"), ("$select", EntraSelect)),
                cancellationToken: cancellationToken);
            entraDevice = matches.FirstOrDefault();
        }

        if (entraDevice is null)
        {
            return Array.Empty<DeviceRecord>();
        }

        JsonNode? intuneDevice = null;
        var entraDeviceObjectId = entraDevice.GetStringValue("deviceId");
        if (!string.IsNullOrWhiteSpace(entraDeviceObjectId))
        {
            var literal = OData.StringLiteral(entraDeviceObjectId);
            intuneDevice = (await _graph.GetPagedAsync(
                OData.Query("/deviceManagement/managedDevices", ("$filter", $"azureADDeviceId eq '{literal}'"), ("$select", IntuneSelect)),
                cancellationToken: cancellationToken)).FirstOrDefault();
        }

        var serial = intuneDevice.GetStringValue("serialNumber") ?? ExtractSerialFromPhysicalIds(entraDevice);
        var autopilotDevice = string.IsNullOrWhiteSpace(serial)
            ? null
            : await GetAutopilotDeviceBySerialAsync(serial, cancellationToken);

        return new[] { ToDeviceRecord(entraDevice, intuneDevice, autopilotDevice) };
    }

    private async Task<IReadOnlyList<DeviceRecord>> SearchContainsAsync(string term, IReadOnlyList<JsonNode> allAutopilotDevices, CancellationToken cancellationToken)
    {
        var literal = OData.StringLiteral(term);
        var batch = await _graph.BatchAsync(
        new[]
        {
            new GraphBatchRequest(
                "entra",
                "GET",
                OData.Query("/devices", ("$filter", $"startsWith(displayName,'{literal}')"), ("$select", EntraSelect), ("$count", "true")),
                Headers: new Dictionary<string, string> { ["ConsistencyLevel"] = "eventual" }),
            new GraphBatchRequest(
                "intune",
                "GET",
                OData.Query("/deviceManagement/managedDevices", ("$filter", $"contains(deviceName,'{literal}') or contains(serialNumber,'{literal}')"), ("$select", IntuneSelect)))
        }, cancellationToken);

        var autopilotDevices = allAutopilotDevices.Where(device =>
            (device.GetStringValue("displayName")?.Contains(term, StringComparison.OrdinalIgnoreCase) ?? false)
            || (device.GetStringValue("serialNumber")?.Contains(term, StringComparison.OrdinalIgnoreCase) ?? false)).ToArray();

        return await CombineDevicesAsync(GetBatchValue(batch, "entra"), GetBatchValue(batch, "intune"), autopilotDevices, cancellationToken);
    }

    private async Task<IReadOnlyList<DeviceRecord>> CombineDevicesAsync(
        IReadOnlyList<JsonNode> entraDevices,
        IReadOnlyList<JsonNode> intuneDevices,
        IReadOnlyList<JsonNode> autopilotDevices,
        CancellationToken cancellationToken)
    {
        var records = new List<DeviceRecord>();

        foreach (var entraDevice in entraDevices)
        {
            var serialFromPhysicalIds = ExtractSerialFromPhysicalIds(entraDevice);
            var intuneDevice = SelectMatchingIntuneDevice(entraDevice, intuneDevices, serialFromPhysicalIds, entraDevice.GetStringValue("displayName"));
            var autopilotDevice = SelectMatchingAutopilotDevice(
                autopilotDevices,
                intuneDevice.GetStringValue("serialNumber") ?? serialFromPhysicalIds,
                entraDevice.GetStringValue("displayName"));

            if (autopilotDevice is null && !string.IsNullOrWhiteSpace(intuneDevice.GetStringValue("serialNumber")))
            {
                autopilotDevice = await GetAutopilotDeviceBySerialAsync(intuneDevice.GetStringValue("serialNumber")!, cancellationToken);
            }

            records.Add(ToDeviceRecord(entraDevice, intuneDevice, autopilotDevice));
        }

        foreach (var intuneDevice in intuneDevices)
        {
            if (records.Any(record => OData.SameIdentifier(record.IntuneDeviceId, intuneDevice.GetStringValue("id"))))
            {
                continue;
            }

            var autopilotDevice = SelectMatchingAutopilotDevice(autopilotDevices, intuneDevice.GetStringValue("serialNumber"), intuneDevice.GetStringValue("deviceName"));
            if (autopilotDevice is null && !string.IsNullOrWhiteSpace(intuneDevice.GetStringValue("serialNumber")))
            {
                autopilotDevice = await GetAutopilotDeviceBySerialAsync(intuneDevice.GetStringValue("serialNumber")!, cancellationToken);
            }

            var entraDevice = await GetEntraDeviceForIntuneDeviceAsync(intuneDevice, cancellationToken);
            records.Add(ToDeviceRecord(entraDevice, intuneDevice, autopilotDevice));
        }

        foreach (var autopilotDevice in autopilotDevices)
        {
            if (records.Any(record =>
                OData.SameIdentifier(record.AutopilotIdentityId, autopilotDevice.GetStringValue("id"))
                || OData.SameIdentifier(record.SerialNumber, autopilotDevice.GetStringValue("serialNumber"))))
            {
                continue;
            }

            records.Add(ToDeviceRecord(null, null, autopilotDevice));
        }

        return records;
    }

    private async Task<JsonNode?> GetEntraDeviceForIntuneDeviceAsync(JsonNode? intuneDevice, CancellationToken cancellationToken)
    {
        if (intuneDevice is null)
        {
            return null;
        }

        var azureAdDeviceId = intuneDevice.GetStringValue("azureADDeviceId");
        if (!string.IsNullOrWhiteSpace(azureAdDeviceId))
        {
            var literal = OData.StringLiteral(azureAdDeviceId);
            var matches = await _graph.GetPagedAsync(
                OData.Query("/devices", ("$filter", $"deviceId eq '{literal}'"), ("$select", EntraSelect)),
                cancellationToken: cancellationToken);
            if (matches.Count == 1)
            {
                return matches[0];
            }

            if (matches.Count > 1)
            {
                await _auditLog.WriteAsync($"Multiple Entra devices matched deviceId {azureAdDeviceId}; skipping automatic correlation.", "WARN", cancellationToken);
                return null;
            }
        }

        var name = intuneDevice.GetStringValue("deviceName");
        if (!string.IsNullOrWhiteSpace(name))
        {
            var literal = OData.StringLiteral(name);
            var matches = await _graph.GetPagedAsync(
                OData.Query("/devices", ("$filter", $"displayName eq '{literal}'"), ("$select", EntraSelect)),
                cancellationToken: cancellationToken);
            if (matches.Count == 1)
            {
                return matches[0];
            }

            if (matches.Count > 1)
            {
                await _auditLog.WriteAsync($"Multiple Entra devices matched name {name}; skipping name-only correlation.", "WARN", cancellationToken);
            }
        }

        return null;
    }

    private async Task<JsonNode?> GetAutopilotDeviceBySerialAsync(string serialNumber, CancellationToken cancellationToken)
    {
        var literal = OData.StringLiteral(serialNumber);
        return (await _graph.GetPagedAsync(
            OData.Query("/deviceManagement/windowsAutopilotDeviceIdentities", ("$filter", $"contains(serialNumber,'{literal}')")),
            cancellationToken: cancellationToken)).FirstOrDefault(device => OData.SameIdentifier(device.GetStringValue("serialNumber"), serialNumber));
    }

    private async Task<IReadOnlyList<JsonNode>> GetAllAutopilotDevicesAsync(CancellationToken cancellationToken)
    {
        try
        {
            return await _graph.GetPagedAsync("/deviceManagement/windowsAutopilotDeviceIdentities", cancellationToken: cancellationToken);
        }
        catch (Exception ex)
        {
            await _auditLog.WriteAsync($"Could not prefetch Autopilot devices: {ex.Message}", "WARN", cancellationToken);
            return Array.Empty<JsonNode>();
        }
    }

    private static DeviceRecord ToDeviceRecord(JsonNode? entraDevice, JsonNode? intuneDevice, JsonNode? autopilotDevice)
    {
        var serial = intuneDevice.GetStringValue("serialNumber")
            ?? autopilotDevice.GetStringValue("serialNumber")
            ?? ExtractSerialFromPhysicalIds(entraDevice);

        return new DeviceRecord
        {
            DeviceName = entraDevice.GetStringValue("displayName")
                ?? intuneDevice.GetStringValue("deviceName")
                ?? autopilotDevice.GetStringValue("displayName"),
            SerialNumber = serial,
            OperatingSystem = entraDevice.GetStringValue("operatingSystem") ?? intuneDevice.GetStringValue("operatingSystem"),
            PrimaryUser = intuneDevice.GetStringValue("userDisplayName"),
            AzureAdLastContact = entraDevice.GetDateTimeOffsetValue("approximateLastSignInDateTime"),
            IntuneLastContact = intuneDevice.GetDateTimeOffsetValue("lastSyncDateTime"),
            AutopilotLastContact = autopilotDevice.GetDateTimeOffsetValue("lastContactedDateTime"),
            EntraDeviceId = entraDevice.GetStringValue("id"),
            EntraDeviceObjectId = entraDevice.GetStringValue("deviceId"),
            IntuneDeviceId = intuneDevice.GetStringValue("id"),
            AutopilotIdentityId = autopilotDevice.GetStringValue("id"),
            EntraAccountEnabled = entraDevice.GetBooleanValue("accountEnabled")?.ToString(),
            ComplianceState = intuneDevice.GetStringValue("complianceState"),
            ManagementAgent = intuneDevice.GetStringValue("managementAgent")
        };
    }

    private static JsonNode? SelectMatchingIntuneDevice(JsonNode? entraDevice, IReadOnlyList<JsonNode> intuneDevices, string? serialNumber, string? deviceName)
    {
        if (entraDevice.GetStringValue("deviceId") is { } deviceId)
        {
            var byDeviceId = SelectUnique(intuneDevices, "azureADDeviceId", deviceId);
            if (byDeviceId is not null)
            {
                return byDeviceId;
            }
        }

        if (!string.IsNullOrWhiteSpace(serialNumber))
        {
            var bySerial = SelectUnique(intuneDevices, "serialNumber", serialNumber);
            if (bySerial is not null)
            {
                return bySerial;
            }
        }

        return string.IsNullOrWhiteSpace(deviceName) ? null : SelectUnique(intuneDevices, "deviceName", deviceName);
    }

    private static JsonNode? SelectMatchingAutopilotDevice(IReadOnlyList<JsonNode> autopilotDevices, string? serialNumber, string? deviceName)
    {
        if (!string.IsNullOrWhiteSpace(serialNumber))
        {
            var bySerial = SelectUnique(autopilotDevices, "serialNumber", serialNumber);
            if (bySerial is not null)
            {
                return bySerial;
            }
        }

        return string.IsNullOrWhiteSpace(deviceName) ? null : SelectUnique(autopilotDevices, "displayName", deviceName);
    }

    private static JsonNode? SelectUnique(IReadOnlyList<JsonNode> devices, string propertyName, string expectedValue)
    {
        var matches = devices.Where(device => OData.SameIdentifier(device.GetStringValue(propertyName), expectedValue)).ToArray();
        return matches.Length == 1 ? matches[0] : null;
    }

    private static IReadOnlyList<JsonNode> GetBatchValue(IReadOnlyList<GraphBatchResponse> responses, string id)
    {
        var response = responses.FirstOrDefault(item => item.Id == id);
        return response?.Body?["value"] is JsonArray array
            ? array.Where(item => item is not null).Cast<JsonNode>().ToArray()
            : Array.Empty<JsonNode>();
    }

    private static void AddDistinct(List<DeviceRecord> target, IEnumerable<DeviceRecord> source)
    {
        foreach (var device in source)
        {
            if (target.Any(existing =>
                OData.SameIdentifier(existing.EntraDeviceId, device.EntraDeviceId)
                || OData.SameIdentifier(existing.IntuneDeviceId, device.IntuneDeviceId)
                || OData.SameIdentifier(existing.AutopilotIdentityId, device.AutopilotIdentityId)
                || OData.SameIdentifier(existing.SerialNumber, device.SerialNumber)))
            {
                continue;
            }

            target.Add(device);
        }
    }

    private static string? ExtractSerialFromPhysicalIds(JsonNode? entraDevice)
    {
        foreach (var physicalId in entraDevice.GetArrayValues("physicalIds"))
        {
            var text = physicalId.GetValue<string>();
            const string marker = "[SerialNumber]:";
            var index = text.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
            if (index >= 0)
            {
                return text[(index + marker.Length)..].Trim();
            }
        }

        return null;
    }
}
