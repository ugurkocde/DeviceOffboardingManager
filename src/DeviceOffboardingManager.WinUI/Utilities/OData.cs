using System.Text;

namespace DeviceOffboardingManager.WinUI.Utilities;

public static class OData
{
    public static string StringLiteral(string value)
    {
        return value.Replace("'", "''", StringComparison.Ordinal);
    }

    public static string Query(string path, params (string Key, string Value)[] values)
    {
        if (values.Length == 0)
        {
            return path;
        }

        var builder = new StringBuilder(path);
        builder.Append('?');
        for (var i = 0; i < values.Length; i++)
        {
            if (i > 0)
            {
                builder.Append('&');
            }

            builder.Append(Uri.EscapeDataString(values[i].Key));
            builder.Append('=');
            builder.Append(Uri.EscapeDataString(values[i].Value));
        }

        return builder.ToString();
    }

    public static bool SameIdentifier(string? left, string? right)
    {
        return !string.IsNullOrWhiteSpace(left)
            && !string.IsNullOrWhiteSpace(right)
            && string.Equals(left.Trim(), right.Trim(), StringComparison.OrdinalIgnoreCase);
    }
}
