using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Azure;
using Azure.Data.Tables;
using Microsoft.AspNetCore.Http;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Host;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.Graph;
using Microsoft.Graph.Models;
using VCSL.Shared;
using VCSL.Shared.Helper;
using VCSL.Shared.Models;

namespace VCSL.Sync;

public class VCardSync
{
    private readonly IConfiguration _configuration;
    private readonly AzureAdOptions _azureAdOptions;
    private readonly VcslOptions _options;
    private GraphServiceClient _graphServiceClient;

    public VCardSync(IConfiguration configuration, IOptions<AzureAdOptions> azureAdOptions, IOptions<VcslOptions> options)
    {
        _configuration = configuration;
        _azureAdOptions = azureAdOptions?.Value ?? throw new ArgumentNullException(nameof(AzureAdOptions));
        _options = options?.Value ?? throw new ArgumentNullException(nameof(VcslOptions));
    }

    [FunctionName("VCardSync")]
    public async Task Run([TimerTrigger("0 */5 * * * *")] TimerInfo myTimer, ILogger log, CancellationToken cancellationToken)
    // public async Task Run([TimerTrigger("0 0 6-18 * * *")] TimerInfo myTimer, ILogger log, CancellationToken cancellationToken)
    {
        try
        {
            log.LogInformation($"[VCardSync] vCard sync started execution at: {DateTime.Now}");

            // Seams i'm just to stupid
            _options.GraphUserGroup = (string.IsNullOrEmpty(_options.GraphUserGroup))
                ? System.Environment.GetEnvironmentVariable("GraphUserGroup")
                : _options.GraphUserGroup;

            _azureAdOptions.TenantId = (string.IsNullOrEmpty(_azureAdOptions.TenantId))
               ? System.Environment.GetEnvironmentVariable("TenantId")
               : _azureAdOptions.TenantId;
            _azureAdOptions.ClientId = (string.IsNullOrEmpty(_azureAdOptions.ClientId))
                ? System.Environment.GetEnvironmentVariable("ClientId")
                : _azureAdOptions.ClientId;
            _azureAdOptions.ClientSecret = (string.IsNullOrEmpty(_azureAdOptions.ClientSecret))
                ? System.Environment.GetEnvironmentVariable("ClientSecret")
                : _azureAdOptions.ClientSecret;

            #region TableClient setup

            log.LogInformation("[VCardSync] Connecting to storage");
            var connectionString = _configuration.GetConnectionString("VCSLStorage");
            var tableClient = new TableClient(connectionString, "VCardData");

            try
            {
                var tableCreationResult = await tableClient.CreateIfNotExistsAsync(cancellationToken);
                if (tableCreationResult.HasValue)
                {
                    if (tableCreationResult.GetRawResponse().Status != StatusCodes.Status409Conflict)
                    {
                        log.LogInformation("[VCardSync] Table VCardData created");
                    }
                }
            }
            catch (RequestFailedException ex)
            {
                log.LogError(ex, "[VCardSync] The request to azure table storage failed");
                log.LogInformation($"[VCardSync] vCard sync stopped execution at: {DateTime.Now}");
                return;

            }
            catch (Exception ex)
            {
                log.LogError(ex, "[VCardSync] A general error occurred azure table storage failed");
                log.LogInformation($"[VCardSync] vCard sync stopped execution at: {DateTime.Now}");
                return;
            }

            #endregion

            #region GraphClient setup
            log.LogInformation($"[VCardSync] TenantId {_azureAdOptions.TenantId}");
            log.LogInformation($"[VCardSync] ClientId {_azureAdOptions.ClientId}");
            log.LogInformation("[VCardSync] Creating authenticated graph helper to retrieve users from Entra ID");
            _graphServiceClient = GraphHelper.GetAuthenticatedGraphClient(_azureAdOptions);

            #endregion

            #region Graph data retrieval

            var graphUserList = await GraphHelper.GetMembersOfGroup(_graphServiceClient, _options.GraphUserGroup, "id, surname, givenName, displayName, department, jobTitle, companyName, businessPhones, mobilePhone, streetAddress, city, state, postalCode, country, mail, userPrincipalName");

            if (graphUserList?.Count > 0 is not true)
            {
                log.LogWarning("[VCardSync] No Users Found");
                log.LogInformation($"[VCardSync] vCard sync stopped execution at: {DateTime.Now}");
                return;
            }

            #endregion

            #region VCardDataModel preperation

            var updateVCardDataBatch = new List<TableTransactionAction>();

            foreach (var usr in graphUserList)
            {
                log.LogInformation("[VCardSync] Start processing user {name}", usr.DisplayName ?? $"with id {usr.Id}");

                #region Graph photo retrieval

                var photoBase64 = "";

                if (_options.UsePhoto)
                {
                    log.LogInformation("[VCardSync] Retrieving photo for user {name}", usr.DisplayName ?? $"with id {usr.Id}");
                    try
                    {
                        var photo = await _graphServiceClient.Users[usr.Id].Photos["64x64"].Content.GetAsync(cancellationToken: cancellationToken);
                        if (photo != null)
                        {
                            var memoryStream = new MemoryStream();
                            await photo.CopyToAsync(memoryStream, cancellationToken);
                            var photoBytes = memoryStream.ToArray();

                            photoBase64 = Convert.ToBase64String(photoBytes);
                            log.LogInformation("[VCardSync] Photo for user {name} found", usr.DisplayName ?? $"with id {usr.Id}");
                        }
                    }
                    catch (Exception)
                    {
                        log.LogWarning("[VCardSync] User {name} has no photo", usr.DisplayName ?? $"with id {usr.Id}");
                    }
                }

                #endregion

                try
                {
                    log.LogInformation("[VCardSync] Creating data model for user {name}", usr.DisplayName ?? $"with id {usr.Id}");
                    var vCardData = new VCardDataModel()
                    {
                        RowKey = usr.Id,
                        Surname = usr.Surname ?? string.Empty,
                        GivenName = usr.GivenName ?? string.Empty,
                        DisplayName = usr.DisplayName ?? string.Empty,
                        Department = usr.Department ?? string.Empty,
                        JobTitle = usr.JobTitle ?? string.Empty,
                        CompanyName = usr.CompanyName ?? string.Empty,
                        TelephoneNumber = usr.BusinessPhones?.FirstOrDefault(string.Empty),
                        MobilePhone = usr.MobilePhone,
                        StreetAddress = usr.StreetAddress ?? string.Empty,
                        City = usr.City ?? string.Empty,
                        State = usr.State ?? string.Empty,
                        PostalCode = usr.PostalCode ?? string.Empty,
                        Country = usr.Country ?? string.Empty,
                        Mail = usr.Mail ?? string.Empty,
                        UserPrincipalName = usr.UserPrincipalName ?? string.Empty,
                        Photo = photoBase64,
                    };

                    log.LogInformation("[VCardSync] Adding user {name} to transaction", usr.DisplayName ?? $"with id {usr.Id}");

                    updateVCardDataBatch.Add(new TableTransactionAction(TableTransactionActionType.UpdateMerge, vCardData));

                    log.LogInformation("[VCardSync] Finished processing user {name}", usr.DisplayName ?? $"with id {usr.Id}");
                }
                catch (Exception ex)
                {
                    log.LogError(ex, "Error processing user {name}", usr.DisplayName ?? $"with id {usr.Id}");
                }
            }

            #endregion

            #region Data upload

            log.LogInformation("[VCardSync] Start uploading data to storage");
            if (updateVCardDataBatch.Count > 0)
            {
                log.LogInformation("[VCardSync] Found {count} elements to upload", updateVCardDataBatch.Count);
                try
                {
                    if (updateVCardDataBatch.Count >= 100)
                    {
                        log.LogInformation("[VCardSync] Chunking vCard data to process transaction");
                        var blocks = updateVCardDataBatch.Chunk(99);

                        var chunkCount = 1;
                        foreach (var transaction in blocks)
                        {
                            log.LogInformation("[VCardSync] Updating chunk {chunkCount} with {transactionLength} elements", chunkCount, transaction.Length);
                            await tableClient.SubmitTransactionAsync(transaction, cancellationToken);
                            chunkCount += 1;
                        }
                    }
                    else
                    {
                        log.LogInformation("[VCardSync] Updating chunk with {count} elements", updateVCardDataBatch.Count);
                        await tableClient.SubmitTransactionAsync(updateVCardDataBatch, cancellationToken);
                    }
                }
                catch (Exception ex)
                {
                    log.LogError(ex, "[VCardSync] Error submitting transaction to storage");
                }
            }
            else
            {
                log.LogWarning("[VCardSync] No vCard Data found");
            }

            #endregion

            log.LogInformation($"[VCardSync] vCard sync stopped execution at: {DateTime.Now}");
        }
        catch (OperationCanceledException)
        {
            log.LogWarning("[VCardSync] Function cancelled");
        }
    }
}