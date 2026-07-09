using System.Text.Json;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;

namespace DeviceOffboardingManager.WinUI.Services;

public sealed class OsSupportBaselineProvider : IOsSupportBaselineProvider
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly OsSupportBaselineCatalog _catalog;

    public OsSupportBaselineProvider()
        : this(Path.Combine(AppContext.BaseDirectory, "Configuration", "os-support-baselines.json"))
    {
    }

    public OsSupportBaselineProvider(string path)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException("OS support baseline configuration was not found.", path);
        }

        _catalog = JsonSerializer.Deserialize<OsSupportBaselineCatalog>(File.ReadAllText(path), JsonOptions)
            ?? throw new InvalidOperationException("OS support baseline configuration is invalid.");
        if (_catalog.SchemaVersion != 1 || _catalog.Platforms.Count == 0)
        {
            throw new InvalidOperationException("OS support baseline configuration has an unsupported schema or no platforms.");
        }
    }

    public bool IsOutdated(string? operatingSystem, string? version)
    {
        return TryGetBaseline(operatingSystem, version, out var baseline, out var normalizedVersion)
            && !baseline.CurrentVersionPrefixes.Any(prefix => normalizedVersion.StartsWith(prefix, StringComparison.OrdinalIgnoreCase));
    }

    public bool IsEndOfLife(string? operatingSystem, string? version)
    {
        return TryGetBaseline(operatingSystem, version, out var baseline, out var normalizedVersion)
            && baseline.EndOfLifeVersionPrefixes.Any(prefix => normalizedVersion.StartsWith(prefix, StringComparison.OrdinalIgnoreCase));
    }

    private bool TryGetBaseline(
        string? operatingSystem,
        string? version,
        out OsSupportBaseline baseline,
        out string normalizedVersion)
    {
        normalizedVersion = version?.Trim() ?? string.Empty;
        var platform = NormalizePlatform(operatingSystem);
        var match = _catalog.Platforms.FirstOrDefault(item =>
            string.Equals(item.Key, platform, StringComparison.OrdinalIgnoreCase));
        baseline = match.Value ?? new OsSupportBaseline();
        return !string.IsNullOrWhiteSpace(platform)
            && !string.IsNullOrWhiteSpace(normalizedVersion)
            && match.Value is not null;
    }

    private static string? NormalizePlatform(string? operatingSystem)
    {
        if (operatingSystem?.Contains("Windows", StringComparison.OrdinalIgnoreCase) == true)
        {
            return "Windows";
        }

        return operatingSystem?.Contains("macOS", StringComparison.OrdinalIgnoreCase) == true
            || operatingSystem?.Contains("Mac OS", StringComparison.OrdinalIgnoreCase) == true
                ? "macOS"
                : operatingSystem?.Trim();
    }
}
