using System.Globalization;
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
    private readonly HttpClient _httpClient;

    public GraphApiClient(
        IAuthenticationService authenticationService,
        IAuditLogService auditLog,
        HttpClient httpClient)
    {
        _authenticationService = authenticationService;
        _auditLog = auditLog;
        _httpClient = httpClient;
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
        if (requests.Select(request => request.Id).Distinct(StringComparer.Ordinal).Count() != requests.Count)
        {
            throw new ArgumentException("Graph batch request IDs must be unique.", nameof(requests));
        }

        var completed = new Dictionary<string, GraphBatchResponse>(StringComparer.Ordinal);
        foreach (var chunk in requests.Chunk(20))
        {
            var pending = chunk.ToList();
            for (var attempt = 1; pending.Count > 0; attempt++)
            {
                var batchRequests = pending.Select(request =>
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

                var response = await SendAsync(
                    HttpMethod.Post,
                    "https://graph.microsoft.com/beta/$batch",
                    new { requests = batchRequests },
                    cancellationToken: cancellationToken);
                if (response?["responses"] is not JsonArray batchResponses)
                {
                    throw new InvalidOperationException("Graph batch response did not contain a responses collection.");
                }

                var parsedResponses = batchResponses
                    .Where(item => item is not null)
                    .Select(ParseBatchResponse)
                    .ToDictionary(item => item.Id, StringComparer.Ordinal);
                var retry = new List<GraphBatchRequest>();
                var retryDelay = TimeSpan.Zero;

                foreach (var request in pending)
                {
                    if (!parsedResponses.TryGetValue(request.Id, out var parsed))
                    {
                        completed[request.Id] = new GraphBatchResponse(
                            request.Id,
                            0,
                            new JsonObject { ["error"] = "No subresponse was returned for this request." },
                            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase));
                        continue;
                    }

                    if (ShouldRetryBatchStatus(parsed.Status) && attempt < 4)
                    {
                        retry.Add(request);
                        retryDelay = Max(retryDelay, GetBatchRetryDelay(parsed, attempt));
                        continue;
                    }

                    completed[request.Id] = parsed;
                }

                if (retry.Count == 0)
                {
                    break;
                }

                await _auditLog.WriteAsync(
                    $"Graph batch contained {retry.Count:n0} transient subrequest failure(s); retrying in {retryDelay.TotalSeconds:n0}s.",
                    "WARN",
                    cancellationToken);
                await Task.Delay(retryDelay, cancellationToken);
                pending = retry;
            }
        }

        return requests.Select(request => completed[request.Id]).ToArray();
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

    private static bool ShouldRetryBatchStatus(int statusCode)
    {
        return statusCode == (int)HttpStatusCode.TooManyRequests || statusCode >= 500;
    }

    private static TimeSpan GetRetryDelay(HttpResponseMessage response, int attempt)
    {
        if (response.Headers.RetryAfter?.Delta is { } delta)
        {
            return delta;
        }

        if (response.Headers.RetryAfter?.Date is { } date)
        {
            return Max(TimeSpan.Zero, date - DateTimeOffset.UtcNow);
        }

        return TimeSpan.FromSeconds(Math.Pow(2, attempt));
    }

    private static GraphBatchResponse ParseBatchResponse(JsonNode item)
    {
        var headers = item["headers"] is JsonObject headerObject
            ? headerObject.ToDictionary(
                property => property.Key,
                property => property.Value?.ToString() ?? string.Empty,
                StringComparer.OrdinalIgnoreCase)
            : new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        return new GraphBatchResponse(
            item["id"]?.GetValue<string>() ?? string.Empty,
            item["status"]?.GetValue<int>() ?? 0,
            item["body"],
            headers);
    }

    private static TimeSpan GetBatchRetryDelay(GraphBatchResponse response, int attempt)
    {
        if (response.Headers.TryGetValue("Retry-After", out var retryAfter)
            && double.TryParse(retryAfter, NumberStyles.Number, CultureInfo.InvariantCulture, out var seconds)
            && seconds >= 0)
        {
            return TimeSpan.FromSeconds(seconds);
        }

        if (DateTimeOffset.TryParse(retryAfter, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var retryDate))
        {
            return Max(TimeSpan.Zero, retryDate - DateTimeOffset.UtcNow);
        }

        return TimeSpan.FromSeconds(Math.Pow(2, attempt));
    }

    private static TimeSpan Max(TimeSpan left, TimeSpan right)
    {
        return left >= right ? left : right;
    }
}
