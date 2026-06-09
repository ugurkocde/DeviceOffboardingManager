using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using DeviceOffboardingManager.WinUI.Graph;
using DeviceOffboardingManager.WinUI.Services.Contracts;

namespace DeviceOffboardingManager.WinUI.Services.Graph;

public sealed class GraphApiClient
{
    private static readonly Uri GraphBaseUri = new("https://graph.microsoft.com/beta/");
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private readonly IAuthenticationService _authenticationService;
    private readonly IAuditLogService _auditLog;
    private readonly HttpClient _httpClient = new();

    public GraphApiClient(IAuthenticationService authenticationService, IAuditLogService auditLog)
    {
        _authenticationService = authenticationService;
        _auditLog = auditLog;
    }

    public async Task<JsonNode?> SendAsync(
        HttpMethod method,
        string url,
        object? body = null,
        IReadOnlyDictionary<string, string>? headers = null,
        CancellationToken cancellationToken = default)
    {
        for (var attempt = 1; ; attempt++)
        {
            using var request = new HttpRequestMessage(method, ResolveUri(url));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", await _authenticationService.GetGraphAccessTokenAsync(cancellationToken));

            if (headers is not null)
            {
                foreach (var header in headers)
                {
                    request.Headers.TryAddWithoutValidation(header.Key, header.Value);
                }
            }

            if (body is not null)
            {
                var json = body is string text ? text : JsonSerializer.Serialize(body, JsonOptions);
                request.Content = new StringContent(json, Encoding.UTF8, "application/json");
            }

            using var response = await _httpClient.SendAsync(request, cancellationToken);
            var responseText = await response.Content.ReadAsStringAsync(cancellationToken);
            if (response.IsSuccessStatusCode)
            {
                return string.IsNullOrWhiteSpace(responseText) ? null : JsonNode.Parse(responseText);
            }

            if (ShouldRetry(response.StatusCode) && attempt < 4)
            {
                var delay = GetRetryDelay(response, attempt);
                await _auditLog.WriteAsync($"Graph {method} {url} returned {(int)response.StatusCode}; retrying in {delay.TotalSeconds:n0}s.", "WARN", cancellationToken);
                await Task.Delay(delay, cancellationToken);
                continue;
            }

            throw new InvalidOperationException($"Graph {method} {url} failed with HTTP {(int)response.StatusCode}: {responseText}");
        }
    }

    public async Task<IReadOnlyList<JsonNode>> GetPagedAsync(
        string url,
        IReadOnlyDictionary<string, string>? headers = null,
        CancellationToken cancellationToken = default)
    {
        var results = new List<JsonNode>();
        var next = url;
        while (!string.IsNullOrWhiteSpace(next))
        {
            var response = await SendAsync(HttpMethod.Get, next, headers: headers, cancellationToken: cancellationToken);
            if (response?["value"] is JsonArray array)
            {
                results.AddRange(array.Where(item => item is not null).Cast<JsonNode>());
            }

            next = response?["@odata.nextLink"]?.GetValue<string>();
        }

        return results;
    }

    public async Task<int> GetCountAsync(string url, CancellationToken cancellationToken = default)
    {
        return await GetCountAsync(url, headers: null, cancellationToken: cancellationToken);
    }

    public async Task<int> GetCountAsync(
        string url,
        IReadOnlyDictionary<string, string>? headers = null,
        CancellationToken cancellationToken = default)
    {
        var response = await SendAsync(HttpMethod.Get, url, headers: headers, cancellationToken: cancellationToken);
        if (response is JsonValue value && value.TryGetValue<int>(out var count))
        {
            return count;
        }

        var text = response?.ToJsonString();
        return int.TryParse(text, out var parsed) ? parsed : 0;
    }

    public async Task<IReadOnlyList<GraphBatchResponse>> BatchAsync(
        IReadOnlyList<GraphBatchRequest> requests,
        CancellationToken cancellationToken = default)
    {
        var responses = new List<GraphBatchResponse>();
        foreach (var chunk in requests.Chunk(20))
        {
            var batchRequests = chunk.Select(request =>
            {
                var payload = new Dictionary<string, object?>
                {
                    ["id"] = request.Id,
                    ["method"] = request.Method,
                    ["url"] = request.Url
                };

                if (request.Headers is not null && request.Headers.Count > 0)
                {
                    payload["headers"] = request.Headers;
                }

                if (request.Body is not null)
                {
                    payload["body"] = request.Body;
                }

                return payload;
            }).ToArray();

            var body = new
            {
                requests = batchRequests
            };

            var response = await SendAsync(HttpMethod.Post, "https://graph.microsoft.com/beta/$batch", body, cancellationToken: cancellationToken);
            if (response?["responses"] is not JsonArray batchResponses)
            {
                continue;
            }

            responses.AddRange(batchResponses
                .Where(item => item is not null)
                .Select(item => new GraphBatchResponse(
                    item!["id"]?.GetValue<string>() ?? string.Empty,
                    item!["status"]?.GetValue<int>() ?? 0,
                    item!["body"])));
        }

        return responses;
    }

    private static Uri ResolveUri(string url)
    {
        return Uri.TryCreate(url, UriKind.Absolute, out var absolute)
            ? absolute
            : new Uri(GraphBaseUri, url.TrimStart('/'));
    }

    private static bool ShouldRetry(HttpStatusCode statusCode)
    {
        var code = (int)statusCode;
        return statusCode == HttpStatusCode.TooManyRequests || code >= 500;
    }

    private static TimeSpan GetRetryDelay(HttpResponseMessage response, int attempt)
    {
        if (response.Headers.RetryAfter?.Delta is { } delta)
        {
            return delta;
        }

        return TimeSpan.FromSeconds(Math.Pow(2, attempt));
    }
}
