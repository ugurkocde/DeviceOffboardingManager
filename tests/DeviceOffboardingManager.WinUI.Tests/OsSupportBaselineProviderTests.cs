using DeviceOffboardingManager.WinUI.Services;

namespace DeviceOffboardingManager.WinUI.Tests;

public sealed class OsSupportBaselineProviderTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"dom-baselines-{Guid.NewGuid():N}");

    [Fact]
    public void UsesVersionedConfigurationForCurrentAndEolChecks()
    {
        Directory.CreateDirectory(_directory);
        var path = Path.Combine(_directory, "baselines.json");
        File.WriteAllText(path, """
            {
              "schemaVersion": 1,
              "updatedUtc": "2026-07-09T00:00:00Z",
              "platforms": {
                "Windows": {
                  "currentVersionPrefixes": ["10.0.26200"],
                  "endOfLifeVersionPrefixes": ["10.0.190"]
                }
              }
            }
            """);
        var provider = new OsSupportBaselineProvider(path);

        Assert.False(provider.IsOutdated("Windows", "10.0.26200.1234"));
        Assert.True(provider.IsOutdated("Windows", "10.0.22631.1"));
        Assert.True(provider.IsEndOfLife("Windows", "10.0.19045.1"));
        Assert.False(provider.IsOutdated("Linux", "1.0"));
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory))
        {
            Directory.Delete(_directory, recursive: true);
        }
    }
}
