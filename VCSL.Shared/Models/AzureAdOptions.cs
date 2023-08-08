namespace VCSL.Shared.Models;

/// <summary>
/// Class <c>AzureAdOptions</c>.
/// </summary>
public class AzureAdOptions
{
    public string TenantId { get; init; } = string.Empty;
    public string ClientId { get; init; } = string.Empty;
    public string ClientSecret { get; init; } = string.Empty;
    public string Authority { get; init; } = string.Empty;
}