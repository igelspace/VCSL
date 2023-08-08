namespace VCSL.Shared.Models;

/// <summary>
/// Class <c>AzureAdOptions</c>.
/// </summary>
public class AzureAdOptions
{
    public string TenantId { get; set; } = string.Empty;
    public string ClientId { get; set; } = string.Empty;
    public string ClientSecret { get; set; } = string.Empty;
    public string Authority { get; set; } = string.Empty;
}