using Azure;
using Azure.Data.Tables;

namespace VCSL.Shared.Models;

/// <summary>
/// Class <c>VCardDataModel</c> ITableEntity containing the actual data for the vCards. The properties are just copies from Microsoft.Graph.Models.User but the object ist reduced to just the necessary information.
/// </summary>
public class VCardDataModel : ITableEntity
{
    public VCardDataModel()
    {

    }

    public string PartitionKey { get; set; } = "Data";
    public string RowKey { get; set; } = string.Empty;

    public string Surname { get; set; } = string.Empty;
    public string GivenName { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public string JobTitle { get; set; } = string.Empty;
    public string CompanyName { get; set; } = string.Empty;
    public string? TelephoneNumber { get; set; } = string.Empty;
    public string? MobilePhone { get; set; } = string.Empty;
    public string? Photo { get; set; } = string.Empty;
    public string StreetAddress { get; set; } = string.Empty;
    public string City { get; set; } = string.Empty;
    public string State { get; set; } = string.Empty;
    public string PostalCode { get; set; } = string.Empty;
    public string Country { get; set; } = string.Empty;
    public string Mail { get; set; } = string.Empty;
    public string UserPrincipalName { get; set; } = string.Empty;

    public DateTimeOffset? Timestamp { get; set; }
    public ETag ETag { get; set; }
}