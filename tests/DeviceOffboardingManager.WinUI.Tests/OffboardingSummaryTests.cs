using DeviceOffboardingManager.WinUI.Models;

namespace DeviceOffboardingManager.WinUI.Tests;

public sealed class OffboardingSummaryTests
{
    [Fact]
    public void MissingRequestedTargetMakesDevicePartial()
    {
        var summary = CreateSummary(
            entra: ServiceOperationResult.MissingTarget("Delete", "No service ID resolved."),
            intune: ServiceOperationResult.Succeeded("Removed"));

        Assert.Equal(0, summary.SuccessfulDevices);
        Assert.Equal(1, summary.FailedDevices);
    }

    [Fact]
    public void AllRequestedOperationsMustSucceed()
    {
        var summary = CreateSummary(
            entra: ServiceOperationResult.Succeeded("Disabled"),
            intune: ServiceOperationResult.Succeeded("Removed"));

        Assert.Equal(1, summary.SuccessfulDevices);
        Assert.Equal(0, summary.FailedDevices);
    }

    [Fact]
    public void EntirelySkippedDeviceIsNotSuccessfulOrFailed()
    {
        var summary = CreateSummary();

        Assert.Equal(0, summary.SuccessfulDevices);
        Assert.Equal(0, summary.FailedDevices);
    }

    private static OffboardingSummary CreateSummary(
        ServiceOperationResult? entra = null,
        ServiceOperationResult? intune = null)
    {
        return new OffboardingSummary
        {
            Results =
            [
                new DeviceOffboardingResult
                {
                    Entra = entra ?? ServiceOperationResult.Skipped(),
                    Intune = intune ?? ServiceOperationResult.Skipped()
                }
            ]
        };
    }
}
