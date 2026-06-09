using System.Text.Json.Nodes;

namespace DeviceOffboardingManager.WinUI.Utilities;

public static class JsonExtensions
{
    public static string? GetStringValue(this JsonNode? node, string propertyName)
    {
        return node?[propertyName]?.GetValue<string?>();
    }

    public static bool? GetBooleanValue(this JsonNode? node, string propertyName)
    {
        var value = node?[propertyName];
        if (value is null)
        {
            return null;
        }

        try
        {
            return value.GetValue<bool>();
        }
        catch
        {
            var text = value.GetValue<string?>();
            return bool.TryParse(text, out var parsed) ? parsed : null;
        }
    }

    public static DateTimeOffset? GetDateTimeOffsetValue(this JsonNode? node, string propertyName)
    {
        var value = node.GetStringValue(propertyName);
        return DateTimeOffset.TryParse(value, out var parsed) ? parsed : null;
    }

    public static IReadOnlyList<JsonNode> GetArrayValues(this JsonNode? node, string propertyName)
    {
        return node?[propertyName] is JsonArray array
            ? array.Where(item => item is not null).Cast<JsonNode>().ToArray()
            : Array.Empty<JsonNode>();
    }
}
