using System.Net;
using System.Text;
using DeviceOffboardingManager.WinUI.Graph;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.Services.Graph;

namespace DeviceOffboardingManager.WinUI.Tests;

public sealed class GraphApiClientTests
{
    [Fact]
    public async Task BatchRetriesTransientSubresponses()
    {
        var handler = new SequenceHandler(
            JsonResponse("""{"responses":[{"id":"one","status":429,"headers":{"Retry-After":"0"},"body":{"error":{"message":"throttled"}}}]}"""),
            JsonResponse("""{"responses":[{"id":"one","status":200,"headers":{},"body":{"value":[{"id":"device-1"}]}}]}"""));
        var client = CreateClient(handler);

        var responses = await client.BatchAsync([new GraphBatchRequest("one", "GET", "/devices")]);

        Assert.Equal(2, handler.RequestCount);
        Assert.Equal(200, Assert.Single(responses).Status);
    }

    [Fact]
    public async Task BatchPreservesPermanentSubresponseFailure()
    {
        var handler = new SequenceHandler(
            JsonResponse("""{"responses":[{"id":"one","status":403,"headers":{},"body":{"error":{"message":"forbidden"}}}]}"""));
        var client = CreateClient(handler);

        var response = Assert.Single(await client.BatchAsync([new GraphBatchRequest("one", "GET", "/devices")]));

        Assert.Equal(403, response.Status);
        Assert.Contains("forbidden", response.Body?.ToJsonString() ?? string.Empty, StringComparison.Ordinal);
    }

    [Fact]
    public async Task GetPagedFollowsNextLink()
    {
        var handler = new SequenceHandler(
            JsonResponse("""{"value":[{"id":"one"}],"@odata.nextLink":"https://graph.microsoft.com/beta/devices?$skiptoken=next"}"""),
            JsonResponse("""{"value":[{"id":"two"}]}"""));
        var client = CreateClient(handler);

        var values = await client.GetPagedAsync("/devices");

        Assert.Equal(2, values.Count);
        Assert.Equal(2, handler.RequestCount);
    }

    [Fact]
    public async Task BatchRejectsDuplicateRequestIdsBeforeSending()
    {
        var handler = new SequenceHandler();
        var client = CreateClient(handler);

        await Assert.ThrowsAsync<ArgumentException>(() => client.BatchAsync(
        [
            new GraphBatchRequest("duplicate", "GET", "/devices"),
            new GraphBatchRequest("duplicate", "GET", "/deviceManagement/managedDevices")
        ]));

        Assert.Equal(0, handler.RequestCount);
    }

    [Fact]
    public async Task BatchSurfacesMissingSubresponse()
    {
        var handler = new SequenceHandler(JsonResponse("""{"responses":[]}"""));
        var client = CreateClient(handler);

        var response = Assert.Single(await client.BatchAsync([new GraphBatchRequest("missing", "GET", "/devices")]));

        Assert.Equal(0, response.Status);
        Assert.Contains("No subresponse", response.Body?.ToJsonString() ?? string.Empty, StringComparison.Ordinal);
    }

    private static GraphApiClient CreateClient(HttpMessageHandler handler)
    {
        return new GraphApiClient(new FakeAuthenticationService(), new FakeAuditLogService(), new HttpClient(handler));
    }

    private static HttpResponseMessage JsonResponse(string json)
    {
        return new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };
    }

    private sealed class SequenceHandler(params HttpResponseMessage[] responses) : HttpMessageHandler
    {
        private readonly Queue<HttpResponseMessage> _responses = new(responses);

        public int RequestCount { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            RequestCount++;
            return Task.FromResult(_responses.Dequeue());
        }
    }

    private sealed class FakeAuthenticationService : IAuthenticationService
    {
        public bool IsConnected => true;

        public string? AccountDisplayName => "test";

        public Task<bool> ConnectAsync(AuthenticationRequest request, CancellationToken cancellationToken = default) => Task.FromResult(true);

        public Task DisconnectAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;

        public Task<string> GetGraphAccessTokenAsync(CancellationToken cancellationToken = default) => Task.FromResult("token");

        public Task<string> GetDefenderAccessTokenAsync(CancellationToken cancellationToken = default) => Task.FromResult("token");
    }

    private sealed class FakeAuditLogService : IAuditLogService
    {
        public string LogFilePath => "test.log";

        public Task WriteAsync(string message, string severity = "INFO", CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
}
