using DeviceOffboardingManager.WinUI.Graph;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.Services.Defender;
using DeviceOffboardingManager.WinUI.Services.Graph;

namespace DeviceOffboardingManager.WinUI.Services;

public sealed class OffboardingService : IOffboardingService
{
    private readonly GraphApiClient _graph;
    private readonly DefenderApiClient _defender;
    private readonly ISettingsService _settingsService;
    private readonly IAuditLogService _auditLog;

    public OffboardingService(
        GraphApiClient graph,
        DefenderApiClient defender,
        ISettingsService settingsService,
        IAuditLogService auditLog)
    {
        _graph = graph;
        _defender = defender;
        _settingsService = settingsService;
        _auditLog = auditLog;
    }

    public async Task<OffboardingSummary> OffboardAsync(
        IReadOnlyCollection<DeviceRecord> devices,
        OffboardingOptions options,
        CancellationToken cancellationToken = default)
    {
        var settings = await _settingsService.LoadAsync(cancellationToken);
        var offboardDefender = settings.DefenderIntegrationEnabled && options.OffboardDefender;
        var results = new List<DeviceOffboardingResult>();

        foreach (var device in devices)
        {
            var preAction = await RunPreActionAsync(device, options.PreAction, cancellationToken);
            var defender = offboardDefender
                ? await RunDefenderOffboardingAsync(device, cancellationToken)
                : new ServiceOperationResult();

            var (entra, intune, autopilot) = await RunGraphOffboardingAsync(device, options, cancellationToken);
            results.Add(new DeviceOffboardingResult
            {
                DeviceName = device.DeviceName,
                SerialNumber = device.SerialNumber,
                PreAction = preAction,
                Defender = defender,
                Entra = entra,
                Intune = intune,
                Autopilot = autopilot
            });
        }

        return new OffboardingSummary { Results = results };
    }

    private async Task<ServiceOperationResult> RunPreActionAsync(DeviceRecord device, DevicePreAction preAction, CancellationToken cancellationToken)
    {
        if (preAction == DevicePreAction.None)
        {
            return new ServiceOperationResult();
        }

        if (string.IsNullOrWhiteSpace(device.IntuneDeviceId))
        {
            return new ServiceOperationResult { Found = false, Action = preAction.ToString(), Error = "No Intune device ID resolved." };
        }

        try
        {
            var action = preAction == DevicePreAction.Retire ? "retire" : "wipe";
            object? body = preAction == DevicePreAction.Wipe ? new { } : null;
            await _graph.SendAsync(
                HttpMethod.Post,
                $"/deviceManagement/managedDevices/{device.IntuneDeviceId}/{action}",
                body,
                cancellationToken: cancellationToken);
            await _auditLog.WriteAsync($"Executed {action} for {device.DeviceName}.", "AUDIT", cancellationToken);
            return new ServiceOperationResult { Found = true, Success = true, Action = action };
        }
        catch (Exception ex)
        {
            await _auditLog.WriteAsync($"Pre-action failed for {device.DeviceName}: {ex.Message}", "ERROR", cancellationToken);
            return new ServiceOperationResult { Found = true, Success = false, Action = preAction.ToString(), Error = ex.Message };
        }
    }

    private async Task<ServiceOperationResult> RunDefenderOffboardingAsync(DeviceRecord device, CancellationToken cancellationToken)
    {
        try
        {
            var machineId = device.MdeDeviceId;
            if (string.IsNullOrWhiteSpace(machineId) && !string.IsNullOrWhiteSpace(device.EntraDeviceObjectId))
            {
                machineId = await _defender.ResolveMachineIdByAadDeviceIdAsync(device.EntraDeviceObjectId, cancellationToken);
                device.MdeDeviceId = machineId;
            }

            if (string.IsNullOrWhiteSpace(machineId))
            {
                return new ServiceOperationResult { Found = false, Action = "Offboard", Error = "No Defender machine ID resolved." };
            }

            await _defender.OffboardMachineAsync(machineId, "Offboarded via DeviceOffboardingManager WinUI", cancellationToken);
            await _auditLog.WriteAsync($"Offboarded {device.DeviceName} from Defender for Endpoint.", "AUDIT", cancellationToken);
            return new ServiceOperationResult { Found = true, Success = true, Action = "Offboard" };
        }
        catch (Exception ex)
        {
            await _auditLog.WriteAsync($"Defender offboarding failed for {device.DeviceName}: {ex.Message}", "ERROR", cancellationToken);
            return new ServiceOperationResult { Found = true, Success = false, Action = "Offboard", Error = ex.Message };
        }
    }

    private async Task<(ServiceOperationResult Entra, ServiceOperationResult Intune, ServiceOperationResult Autopilot)> RunGraphOffboardingAsync(
        DeviceRecord device,
        OffboardingOptions options,
        CancellationToken cancellationToken)
    {
        var requests = new List<GraphBatchRequest>();

        if (options.DisableEntra && !string.IsNullOrWhiteSpace(device.EntraDeviceId))
        {
            requests.Add(new GraphBatchRequest("entra", "PATCH", $"/devices/{device.EntraDeviceId}", new { accountEnabled = false }, new Dictionary<string, string> { ["Content-Type"] = "application/json" }));
        }
        else if (options.DeleteEntra && !string.IsNullOrWhiteSpace(device.EntraDeviceId))
        {
            requests.Add(new GraphBatchRequest("entra", "DELETE", $"/devices/{device.EntraDeviceId}"));
        }

        if (options.DeleteIntune && !string.IsNullOrWhiteSpace(device.IntuneDeviceId))
        {
            requests.Add(new GraphBatchRequest("intune", "DELETE", $"/deviceManagement/managedDevices/{device.IntuneDeviceId}"));
        }

        if (options.DeleteAutopilot && !string.IsNullOrWhiteSpace(device.AutopilotIdentityId))
        {
            requests.Add(new GraphBatchRequest("autopilot", "DELETE", $"/deviceManagement/windowsAutopilotDeviceIdentities/{device.AutopilotIdentityId}"));
        }

        if (requests.Count == 0)
        {
            return (
                BuildMissingResult(options.DeleteEntra || options.DisableEntra, options.DisableEntra ? "Disable" : "Delete", device.EntraDeviceId),
                BuildMissingResult(options.DeleteIntune, "Delete", device.IntuneDeviceId),
                BuildMissingResult(options.DeleteAutopilot, "Delete", device.AutopilotIdentityId));
        }

        var responses = await _graph.BatchAsync(requests, cancellationToken);
        return (
            BuildGraphResult(responses, "entra", options.DeleteEntra || options.DisableEntra, options.DisableEntra ? "Disabled" : "Removed", device.EntraDeviceId),
            BuildGraphResult(responses, "intune", options.DeleteIntune, "Removed", device.IntuneDeviceId),
            BuildGraphResult(responses, "autopilot", options.DeleteAutopilot, "Removed", device.AutopilotIdentityId));
    }

    private static ServiceOperationResult BuildMissingResult(bool requested, string action, string? id)
    {
        if (!requested)
        {
            return new ServiceOperationResult();
        }

        return string.IsNullOrWhiteSpace(id)
            ? new ServiceOperationResult { Found = false, Action = action, Error = "No service ID resolved." }
            : new ServiceOperationResult();
    }

    private static ServiceOperationResult BuildGraphResult(
        IReadOnlyList<GraphBatchResponse> responses,
        string id,
        bool requested,
        string action,
        string? serviceId)
    {
        if (!requested)
        {
            return new ServiceOperationResult();
        }

        if (string.IsNullOrWhiteSpace(serviceId))
        {
            return new ServiceOperationResult { Found = false, Action = action, Error = "No service ID resolved." };
        }

        var response = responses.FirstOrDefault(item => item.Id == id);
        if (response is null)
        {
            return new ServiceOperationResult { Found = true, Success = false, Action = action, Error = "No batch response returned." };
        }

        var success = response.Status is >= 200 and < 300;
        return new ServiceOperationResult
        {
            Found = true,
            Success = success,
            Action = action,
            Error = success ? null : $"HTTP {response.Status}: {response.Body?.ToJsonString()}"
        };
    }
}
