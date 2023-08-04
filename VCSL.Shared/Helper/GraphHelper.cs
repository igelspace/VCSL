using Microsoft.Graph;
using Microsoft.Identity.Client;
using System.Net.Http.Headers;
using Microsoft.Graph.Models;
using Azure.Identity;
using Microsoft.Extensions.Configuration;
using VCSL.Shared.Models;

namespace VCSL.Shared.Helper;

/// <summary>
/// Class <c>GraphHelper</c> provides static methods for connecting and interacting with Microsoft Graph.
/// </summary>
public static class GraphHelper
{
    /// <summary>
    /// Method <c>GetAuthenticatedGraphClient</c> returns an authenticated GraphServiceClient with the provided AzureAdOptions and optionally provided scopes.
    /// </summary>
    /// <param name="options">Options to set the connection details for the service principal.</param>
    /// <param name="scopes">Optionally provide scopes. Defaults to the default scopes provided with the service principal.</param>
    public static GraphServiceClient GetAuthenticatedGraphClient(AzureAdOptions options, List<string>? scopes = null)
    {
        if (scopes == null || scopes.Count == 0)
        {
            scopes = new List<string>
            {
                $"https://graph.microsoft.com/.default"
            };
        }

        var credentials = new ClientSecretCredential(options.TenantId, options.ClientId, options.ClientSecret);
        return new GraphServiceClient(credentials, scopes);
    }

    /// <summary>
    /// Method <c>GetMembersOfGroup</c> returns the members of the specified group, optionally with specific properties selected 
    /// </summary>
    /// <param name="graphClient">The authenticated GraphServiceClient with which to retrieve the data</param>
    /// <param name="groupIdentifier">The GUID of the group to retrieve as a string</param>
    /// <param name="properties">Optionally the properties which should be selected. If nothing is provided the default properties are returned</param>
    /// <returns></returns>
    public static async Task<List<User>> GetMembersOfGroup(GraphServiceClient graphClient, string groupIdentifier, string properties = "")
    {
        try
        {
            var members = new List<User>();

            if (string.IsNullOrEmpty(groupIdentifier)) return new List<User>();

            if (!GuidHelper.IsValidGuid(groupIdentifier)) return new List<User>();

            var groupUsers = (string.IsNullOrEmpty(properties))
                ? await graphClient.Groups[groupIdentifier].Members.GetAsync()
                : await graphClient.Groups[groupIdentifier].Members.GetAsync((requestConfiguration) =>
                {
                    requestConfiguration.QueryParameters.Select = properties.Split(", ");
                });

            if (groupUsers == null) return members;

            var pageIterator = PageIterator<DirectoryObject, DirectoryObjectCollectionResponse>.CreatePageIterator(graphClient,
                groupUsers, (user =>
                {
                    var usr = (User)user;
                    if (usr != null)
                    {
                        members.Add(usr);
                    }
                    return true;
                }),
                (req) => req);

            await pageIterator.IterateAsync();

            return members;

        }
        catch (Exception)
        {
            return new List<User>();
        }
    }
}