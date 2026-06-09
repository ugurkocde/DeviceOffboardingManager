using System.Net;
using System.Text;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;

namespace DeviceOffboardingManager.WinUI.Services;

public sealed class ReportExportService : IReportExportService
{
    private readonly IAuditLogService _auditLog;

    public ReportExportService(IAuditLogService auditLog)
    {
        _auditLog = auditLog;
    }

    public async Task<string> ExportDeviceCsvAsync(IReadOnlyCollection<DeviceRecord> devices, CancellationToken cancellationToken = default)
    {
        var path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            $"DOM_Devices_{DateTime.Now:yyyyMMdd_HHmmss}.csv");

        var builder = new StringBuilder();
        builder.AppendLine("DeviceName,SerialNumber,OperatingSystem,PrimaryUser,ComplianceState,EntraDeviceId,EntraDeviceObjectId,IntuneDeviceId,AutopilotIdentityId,MdeDeviceId,ManagementAgent");
        foreach (var device in devices)
        {
            builder.AppendLine(string.Join(",", new[]
            {
                Csv(device.DeviceName),
                Csv(device.SerialNumber),
                Csv(device.OperatingSystem),
                Csv(device.PrimaryUser),
                Csv(device.ComplianceState),
                Csv(device.EntraDeviceId),
                Csv(device.EntraDeviceObjectId),
                Csv(device.IntuneDeviceId),
                Csv(device.AutopilotIdentityId),
                Csv(device.MdeDeviceId),
                Csv(device.ManagementAgent)
            }));
        }

        await File.WriteAllTextAsync(path, builder.ToString(), cancellationToken);
        await _auditLog.WriteAsync($"Exported device CSV to {path}.", "AUDIT", cancellationToken);
        return path;
    }

    public async Task<string> ExportOffboardingHtmlAsync(OffboardingSummary summary, CancellationToken cancellationToken = default)
    {
        var path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            $"DOM_Offboarding_{DateTime.Now:yyyyMMdd_HHmmss}.html");

        var builder = new StringBuilder();
        builder.AppendLine("<!doctype html><html><head><meta charset=\"utf-8\"><title>Device Offboarding Report</title>");
        builder.AppendLine("<style>body{font-family:Segoe UI,Arial,sans-serif;margin:32px;color:#1f2937}table{border-collapse:collapse;width:100%}th,td{border:1px solid #d1d5db;padding:8px;text-align:left}th{background:#f3f4f6}.ok{color:#107c10}.fail{color:#c50f1f}.na{color:#6b7280}</style>");
        builder.AppendLine("</head><body>");
        builder.AppendLine("<h1>Device Offboarding Report</h1>");
        builder.AppendLine($"<p>Total devices: {summary.TotalDevices} | Successful: {summary.SuccessfulDevices} | Failed/partial: {summary.FailedDevices}</p>");
        builder.AppendLine("<table><thead><tr><th>Device</th><th>Serial</th><th>Pre-action</th><th>Entra</th><th>Intune</th><th>Autopilot</th><th>Defender</th></tr></thead><tbody>");
        foreach (var result in summary.Results)
        {
            builder.AppendLine("<tr>");
            builder.AppendLine($"<td>{Html(result.DeviceName)}</td>");
            builder.AppendLine($"<td>{Html(result.SerialNumber)}</td>");
            builder.AppendLine(RenderStatus(result.PreAction));
            builder.AppendLine(RenderStatus(result.Entra));
            builder.AppendLine(RenderStatus(result.Intune));
            builder.AppendLine(RenderStatus(result.Autopilot));
            builder.AppendLine(RenderStatus(result.Defender));
            builder.AppendLine("</tr>");
        }

        builder.AppendLine("</tbody></table></body></html>");
        await File.WriteAllTextAsync(path, builder.ToString(), cancellationToken);
        await _auditLog.WriteAsync($"Exported offboarding report to {path}.", "AUDIT", cancellationToken);
        return path;
    }

    private static string RenderStatus(ServiceOperationResult result)
    {
        if (!result.Found && string.IsNullOrWhiteSpace(result.Error))
        {
            return "<td class=\"na\">Skipped</td>";
        }

        if (!result.Found)
        {
            return $"<td class=\"na\">Not found<br><small>{Html(result.Error)}</small></td>";
        }

        return result.Success
            ? $"<td class=\"ok\">{Html(result.Action ?? "Success")}</td>"
            : $"<td class=\"fail\">Failed<br><small>{Html(result.Error)}</small></td>";
    }

    private static string Csv(string? value)
    {
        var text = value ?? string.Empty;
        return '"' + text.Replace("\"", "\"\"", StringComparison.Ordinal) + '"';
    }

    private static string Html(string? value)
    {
        return WebUtility.HtmlEncode(value ?? string.Empty);
    }
}
