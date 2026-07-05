namespace DeviceOffboardingManager.WinUI.Models;

public sealed record AuthenticationRequest
{
    public AuthenticationMethod Method { get; init; }

    public string? TenantId { get; init; }

    public string? ClientId { get; init; }

    public string? CertificateThumbprint { get; init; }

    public string? ClientSecret { get; init; }

    public IntPtr ParentWindowHandle { get; init; }

    public Action<string>? StatusMessageCallback { get; init; }
}
