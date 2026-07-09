namespace DeviceOffboardingManager.WinUI.Utilities;

public static class CsvEncoder
{
    private static readonly char[] FormulaPrefixes = ['=', '+', '-', '@', '\t', '\r'];

    public static string EscapeCell(string? value)
    {
        var text = value ?? string.Empty;
        var firstNonWhitespace = text.AsSpan().TrimStart();
        if (!firstNonWhitespace.IsEmpty && FormulaPrefixes.Contains(firstNonWhitespace[0]))
        {
            text = "'" + text;
        }

        return '"' + text.Replace("\"", "\"\"", StringComparison.Ordinal) + '"';
    }
}
