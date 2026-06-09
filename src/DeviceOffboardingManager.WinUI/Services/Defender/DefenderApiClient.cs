using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.Utilities;

namespace DeviceOffboardingManager.WinUI.Services.Defender;

public sealed class DefenderApiClient
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private readonly IAuthenticationService _authenticationService;
    private readonly IAuditLogService _auditLog;
    private readonly HttpClient _httpClient = new();

    public DefenderApiClient(IAuthenticationService authenticationService, IAuditLogService auditLog)
    {
        _authenticationService = authenticationService;
        _auditLog = auditLog;
    }

    public async Task<string?> ResolveMachineIdByAadDeviceIdAsync(string aadDeviceId, CancellationToken cancellationToken = default)
    {
        var filter = $"aadDeviceId eq '{OData.StringLiteral(aadDeviceId)}'";
        var url = "https://api.security.microsoft.com/api/machines?$filter=" + Uri.EscapeDataString(filter);
        var response = await SendAsync(HttpMethod.Get, url, cancellationToken: cancellationToken);
        return response?["value"] is JsonArray { Count: > 0 } value
            ? value[0]?["id"]?.GetValue<string>()
            : null;
    }

    public async Task OffboardMachineAsync(string machineId, string comment, CancellationToken cancellationToken = default)
    {
        var body = new { Comment = comment };
        await SendAsync(
            HttpMethod.Post,
            $"https://api.security.microsoft.com/api/machines/{Uri.EscapeDataString(machineId)}/offboard",
            body,
            cancellationToken);
    }

    private async Task<JsonNode?> SendAsync(HttpMethod method, string url, object? body = null, CancellationToken cancellationToken = default)
    {
        for (var attempt = 1; ; attempt++)
        {
            using var request = new HttpRequestMessage(method, url);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", await _authenticationService.GetDefenderAccessTokenAsync(cancellationToken));

            if (body is not null)
            {
                request.Content = new StringContent(JsonSerializer.Serialize(body, JsonOptions), Encoding.UTF8, "application/json");
            }

            using var response = await _httpClient.SendAsync(request, cancellationToken);
            var responseText = await response.Content.ReadAsStringAsync(cancellationToken);
            if (response.IsSuccessStatusCode)
            {
                return string.IsNullOrWhiteSpace(responseText) ? null : JsonNode.Parse(responseText);
            }

            if ((response.StatusCode == HttpStatusCode.TooManyRequests || (int)response.StatusCode >= 500) && attempt < 4)
            {
                var delay = response.Headers.RetryAfter?.Delta ?? TimeSpan.FromSeconds(Math.Pow(2, attempt));
                await _auditLog.WriteAsync($"Defender {method} {url} returned {(int)response.StatusCode}; retrying in {delay.TotalSeconds:n0}s.", "WARN", cancellationToken);
                await Task.Delay(delay, cancellationToken);
                continue;
            }

            throw new InvalidOperationException($"Defender {method} {url} failed with HTTP {(int)response.StatusCode}: {responseText}");
        }
    }
}
