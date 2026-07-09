using System.Text.Json.Nodes;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.Services.Graph;
using DeviceOffboardingManager.WinUI.Utilities;

namespace DeviceOffboardingManager.WinUI.Services;

public sealed class PlaybookService : IPlaybookService
{
    private readonly GraphApiClient _graph;
    private readonly IAuditLogService _auditLog;
    private readonly IOsSupportBaselineProvider _osSupportBaselines;

    public PlaybookService(
        GraphApiClient graph,
        IAuditLogService auditLog,
        IOsSupportBaselineProvider osSupportBaselines)
    {
        _graph = graph;
        _auditLog = auditLog;
        _osSupportBaselines = osSupportBaselines;
    }

    public IReadOnlyList<PlaybookDefinition> Definitions { get; } =
        new[]
        {
            new PlaybookDefinition("autopilot-not-intune", AppResources.Get("PlaybookAutopilotNotIntune", "Autopilot not in Intune"), AppResources.Get("PlaybookAutopilotNotIntuneDescription", "List Autopilot identities whose serial number is not present in Intune.")),
            new PlaybookDefinition("intune-not-autopilot", AppResources.Get("PlaybookIntuneNotAutopilot", "Intune not in Autopilot"), AppResources.Get("PlaybookIntuneNotAutopilotDescription", "List Intune devices whose serial number is not present in Autopilot.")),
            new PlaybookDefinition("corporate-devices", AppResources.Get("PlaybookCorporateDevices", "Corporate devices"), AppResources.Get("PlaybookCorporateDevicesDescription", "List Intune devices marked as corporate.")),
            new PlaybookDefinition("personal-devices", AppResources.Get("PlaybookPersonalDevices", "Personal devices"), AppResources.Get("PlaybookPersonalDevicesDescription", "List Intune devices marked as personal.")),
            new PlaybookDefinition("stale-devices", AppResources.Get("PlaybookStaleDevices", "Stale devices"), AppResources.Get("PlaybookStaleDevicesDescription", "List Intune devices stale for 90 days.")),
            new PlaybookDefinition("specific-os", AppResources.Get("PlaybookSpecificOs", "Specific OS devices"), AppResources.Get("PlaybookSpecificOsDescription", "List Intune devices by operating system."), true, AppResources.Get("PlaybookSpecificOsParameter", "Windows, macOS, iOS, Android, or Linux")),
            new PlaybookDefinition("not-latest-os", AppResources.Get("PlaybookOutdatedOs", "Outdated OS devices"), AppResources.Get("PlaybookOutdatedOsDescription", "List devices that appear to be below the latest known OS baseline.")),
            new PlaybookDefinition("eol-os", AppResources.Get("PlaybookEolOs", "End-of-life OS devices"), AppResources.Get("PlaybookEolOsDescription", "List devices that appear to run end-of-life operating systems.")),
            new PlaybookDefinition("bitlocker", AppResources.Get("PlaybookBitLocker", "BitLocker key report"), AppResources.Get("PlaybookBitLockerDescription", "List BitLocker recovery key metadata.")),
            new PlaybookDefinition("filevault", AppResources.Get("PlaybookFileVault", "FileVault key availability"), AppResources.Get("PlaybookFileVaultDescription", "Check FileVault key availability for macOS Intune devices.")),
            new PlaybookDefinition("corporate-identifiers", AppResources.Get("PlaybookCorporateIdentifiers", "Corporate identifier stale report"), AppResources.Get("PlaybookCorporateIdentifiersDescription", "List imported corporate identifiers and enrollment state."))
        };

    public async Task<PlaybookRunResult> RunAsync(string playbookId, string? parameter = null, CancellationToken cancellationToken = default)
    {
        var definition = Definitions.First(item => item.Id == playbookId);
        var rows = playbookId switch
        {
            "autopilot-not-intune" => await GetAutopilotNotInIntuneAsync(cancellationToken),
            "intune-not-autopilot" => await GetIntuneNotInAutopilotAsync(cancellationToken),
            "corporate-devices" => await QueryRowsAsync(OData.Query("/deviceManagement/managedDevices", ("$filter", "managedDeviceOwnerType eq 'company'"), ("$select", "deviceName,serialNumber,operatingSystem,model,managedDeviceOwnerType,lastSyncDateTime")), cancellationToken),
            "personal-devices" => await QueryRowsAsync(OData.Query("/deviceManagement/managedDevices", ("$filter", "managedDeviceOwnerType eq 'personal'"), ("$select", "deviceName,serialNumber,operatingSystem,model,managedDeviceOwnerType,lastSyncDateTime")), cancellationToken),
            "stale-devices" => await QueryRowsAsync(OData.Query("/deviceManagement/managedDevices", ("$filter", $"lastSyncDateTime lt {DateTimeOffset.UtcNow.AddDays(-90):O}"), ("$select", "deviceName,serialNumber,operatingSystem,model,managedDeviceOwnerType,lastSyncDateTime")), cancellationToken),
            "specific-os" => await QueryRowsAsync(OData.Query("/deviceManagement/managedDevices", ("$filter", $"operatingSystem eq '{OData.StringLiteral(parameter ?? "Windows")}'"), ("$select", "deviceName,serialNumber,operatingSystem,model,osVersion,lastSyncDateTime,userDisplayName")), cancellationToken),
            "not-latest-os" => await GetOutdatedOsAsync(cancellationToken),
            "eol-os" => await GetEolOsAsync(cancellationToken),
            "bitlocker" => await QueryRowsAsync(OData.Query("/informationProtection/bitlocker/recoveryKeys", ("$select", "id,createdDateTime,deviceId,volumeType")), cancellationToken),
            "filevault" => await GetFileVaultAvailabilityAsync(cancellationToken),
            "corporate-identifiers" => await QueryRowsAsync(OData.Query("/deviceManagement/importedDeviceIdentities", ("$select", "id,importedDeviceIdentifier,importedDeviceIdentityType,lastModifiedDateTime,createdDateTime,lastContactedDateTime,description,enrollmentState,platform")), cancellationToken),
            _ => Array.Empty<IReadOnlyDictionary<string, string?>>()
        };

        await _auditLog.WriteAsync($"Ran WinUI playbook '{definition.Name}' with {rows.Count} result rows.", "AUDIT", cancellationToken);
        return new PlaybookRunResult { Definition = definition, Rows = rows };
    }

    private async Task<IReadOnlyList<IReadOnlyDictionary<string, string?>>> GetAutopilotNotInIntuneAsync(CancellationToken cancellationToken)
    {
        var autopilot = await _graph.GetPagedAsync(OData.Query("/deviceManagement/windowsAutopilotDeviceIdentities", ("$select", "id,displayName,serialNumber,lastContactedDateTime,model,manufacturer")), cancellationToken: cancellationToken);
        var intune = await _graph.GetPagedAsync(OData.Query("/deviceManagement/managedDevices", ("$select", "serialNumber")), cancellationToken: cancellationToken);
        var intuneSerials = intune.Select(item => item.GetStringValue("serialNumber")).Where(value => !string.IsNullOrWhiteSpace(value)).ToHashSet(StringComparer.OrdinalIgnoreCase);
        return autopilot
            .Where(item => !string.IsNullOrWhiteSpace(item.GetStringValue("serialNumber")) && !intuneSerials.Contains(item.GetStringValue("serialNumber")!))
            .Select(ToDictionary)
            .ToArray();
    }

    private async Task<IReadOnlyList<IReadOnlyDictionary<string, string?>>> GetIntuneNotInAutopilotAsync(CancellationToken cancellationToken)
    {
        var autopilot = await _graph.GetPagedAsync(OData.Query("/deviceManagement/windowsAutopilotDeviceIdentities", ("$select", "serialNumber")), cancellationToken: cancellationToken);
        var intune = await _graph.GetPagedAsync(OData.Query("/deviceManagement/managedDevices", ("$select", "id,deviceName,serialNumber,operatingSystem,model,userDisplayName,lastSyncDateTime")), cancellationToken: cancellationToken);
        var autopilotSerials = autopilot.Select(item => item.GetStringValue("serialNumber")).Where(value => !string.IsNullOrWhiteSpace(value)).ToHashSet(StringComparer.OrdinalIgnoreCase);
        return intune
            .Where(item => !string.IsNullOrWhiteSpace(item.GetStringValue("serialNumber")) && !autopilotSerials.Contains(item.GetStringValue("serialNumber")!))
            .Select(ToDictionary)
            .ToArray();
    }

    private async Task<IReadOnlyList<IReadOnlyDictionary<string, string?>>> GetOutdatedOsAsync(CancellationToken cancellationToken)
    {
        var devices = await _graph.GetPagedAsync(OData.Query("/deviceManagement/managedDevices", ("$select", "deviceName,serialNumber,operatingSystem,osVersion,lastSyncDateTime")), cancellationToken: cancellationToken);
        return devices
            .Where(device => _osSupportBaselines.IsOutdated(device.GetStringValue("operatingSystem"), device.GetStringValue("osVersion")))
            .Select(ToDictionary)
            .ToArray();
    }

    private async Task<IReadOnlyList<IReadOnlyDictionary<string, string?>>> GetEolOsAsync(CancellationToken cancellationToken)
    {
        var devices = await _graph.GetPagedAsync(OData.Query("/deviceManagement/managedDevices", ("$select", "deviceName,serialNumber,operatingSystem,osVersion,lastSyncDateTime")), cancellationToken: cancellationToken);
        return devices
            .Where(device => _osSupportBaselines.IsEndOfLife(device.GetStringValue("operatingSystem"), device.GetStringValue("osVersion")))
            .Select(ToDictionary)
            .ToArray();
    }

    private async Task<IReadOnlyList<IReadOnlyDictionary<string, string?>>> GetFileVaultAvailabilityAsync(CancellationToken cancellationToken)
    {
        var devices = await _graph.GetPagedAsync(OData.Query("/deviceManagement/managedDevices", ("$filter", "operatingSystem eq 'macOS'"), ("$select", "id,deviceName,serialNumber,lastSyncDateTime")), cancellationToken: cancellationToken);
        var rows = new List<IReadOnlyDictionary<string, string?>>();
        foreach (var device in devices)
        {
            var row = new Dictionary<string, string?>
            {
                ["deviceName"] = device.GetStringValue("deviceName"),
                ["serialNumber"] = device.GetStringValue("serialNumber"),
                ["lastSyncDateTime"] = device.GetStringValue("lastSyncDateTime")
            };

            try
            {
                var response = await _graph.SendAsync(HttpMethod.Get, $"/deviceManagement/managedDevices('{device.GetStringValue("id")}')/getFileVaultKey", cancellationToken: cancellationToken);
                row["hasFileVaultKey"] = string.IsNullOrWhiteSpace(response.GetStringValue("value")) ? "No" : "Yes";
            }
            catch (Exception ex)
            {
                row["hasFileVaultKey"] = "Error";
                row["error"] = ex.Message;
            }

            rows.Add(row);
        }

        return rows;
    }

    private async Task<IReadOnlyList<IReadOnlyDictionary<string, string?>>> QueryRowsAsync(string url, CancellationToken cancellationToken)
    {
        var rows = await _graph.GetPagedAsync(url, cancellationToken: cancellationToken);
        return rows.Select(ToDictionary).ToArray();
    }

    private static IReadOnlyDictionary<string, string?> ToDictionary(JsonNode node)
    {
        if (node is not JsonObject obj)
        {
            return new Dictionary<string, string?> { ["value"] = node.ToJsonString() };
        }

        return obj.ToDictionary(property => property.Key, property => GetDisplayValue(property.Value));
    }

    private static string? GetDisplayValue(JsonNode? value)
    {
        if (value is null)
        {
            return null;
        }

        if (value is JsonValue jsonValue && jsonValue.TryGetValue<string>(out var text))
        {
            return text;
        }

        return value.ToJsonString();
    }
}
