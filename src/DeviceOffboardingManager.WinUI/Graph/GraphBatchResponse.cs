using System.Text.Json.Nodes;

namespace DeviceOffboardingManager.WinUI.Graph;

public sealed record GraphBatchResponse(
    string Id,
    int Status,
    JsonNode? Body,
    IReadOnlyDictionary<string, string> Headers);
