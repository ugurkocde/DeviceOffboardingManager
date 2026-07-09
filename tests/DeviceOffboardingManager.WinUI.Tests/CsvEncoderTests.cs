using DeviceOffboardingManager.WinUI.Utilities;

namespace DeviceOffboardingManager.WinUI.Tests;

public sealed class CsvEncoderTests
{
    [Theory]
    [InlineData("=HYPERLINK(\"https://example.test\")")]
    [InlineData("+cmd|' /C calc'!A0")]
    [InlineData("-2+3")]
    [InlineData("@SUM(1,1)")]
    [InlineData("  =SUM(1,1)")]
    public void FormulaLikeValuesAreNeutralized(string value)
    {
        var encoded = CsvEncoder.EscapeCell(value);

        Assert.StartsWith("\"'", encoded, StringComparison.Ordinal);
    }

    [Fact]
    public void QuotesAreEscaped()
    {
        Assert.Equal("\"alpha \"\"beta\"\"\"", CsvEncoder.EscapeCell("alpha \"beta\""));
    }
}
