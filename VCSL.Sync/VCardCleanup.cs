using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Azure.Data.Tables;
using Azure;
using Microsoft.AspNetCore.Http;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Host;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.Graph;
using VCSL.Shared.Helper;
using VCSL.Shared.Models;
using System.Transactions;
using System.Threading;

namespace VCSL.Sync;

public class VCardCleanup
{
    private readonly IConfiguration _configuration;
    private GraphServiceClient _graphServiceClient;

    public VCardCleanup(IConfiguration configuration)
    {
        _configuration = configuration;
    }
    
    [FunctionName("VCardCleanup")]
    public async Task Run([TimerTrigger("0 0 23 * * *")] TimerInfo myTimer, ILogger log, CancellationToken cancellationToken)
    {
        try
        {
            log.LogInformation("[VCardCleanup] vCard cleanup started execution at: {date}", DateTime.Now);

            #region TableClient setup

            log.LogInformation("[VCardCleanup] Connecting to storage");
            var connectionString = _configuration.GetConnectionString("VCSLStorage");
            var tableClient = new TableClient(connectionString, "VCardData");

            try
            {
                var tableCreationResult = await tableClient.CreateIfNotExistsAsync();
                if (tableCreationResult.HasValue)
                {
                    if (tableCreationResult.GetRawResponse().Status != StatusCodes.Status409Conflict)
                    {
                        log.LogInformation("[VCardCleanup] Table VCardData created");
                    }
                }
            }
            catch (RequestFailedException ex)
            {
                log.LogError(ex, "[VCardCleanup] The request to azure table storage failed");
                log.LogInformation($"[VCardCleanup] vCard sync stopped execution at: {DateTime.Now}");
                return;
            }
            catch (Exception ex)
            {
                log.LogError(ex, "[VCardCleanup] A general error occurred azure table storage failed");
                log.LogInformation($"[VCardCleanup] vCard sync stopped execution at: {DateTime.Now}");
                return;
            }

            #endregion

            #region GraphClient setup

            log.LogInformation("[VCardCleanup] Creating authenticated graph helper to retrieve users from Entra ID");
            
            _graphServiceClient = GraphHelper.GetAuthenticatedGraphClient(_configuration);

            #endregion

            #region Graph data retrieval

            var graphUserList = await GraphHelper.GetMembersOfGroup(_graphServiceClient, _configuration["GraphUserGroup"], "id, surname, givenName, displayName, department, jobTitle, companyName, businessPhones, mobilePhone, streetAddress, city, state, postalCode, country, mail, userPrincipalName");

            if (graphUserList?.Count > 0 is not true)
            {
                log.LogWarning("[VCardCleanup] No Users Found");
                log.LogInformation($"[VCardCleanup] vCard sync stopped execution at: {DateTime.Now}");
                return;
            }

            #endregion

            #region Remove old vCard data

            var vCardDataModelsToDelete = tableClient.Query<VCardDataModel>().Where(d => !graphUserList.Any(u => u.Id == d.RowKey)).ToList();

            if (vCardDataModelsToDelete.Any())
            {
                log.LogInformation("[VCardCleanup] Found {count} elements to upload", vCardDataModelsToDelete.Count);
                log.LogInformation("[VCardCleanup] Start uploading data to storage");

                var deleteVCardDataBatch = vCardDataModelsToDelete.Select(data => new TableTransactionAction(TableTransactionActionType.Delete, data)).ToList();

                try
                {
                    if (deleteVCardDataBatch.Count >= 100)
                    {
                        log.LogInformation("[VCardCleanup] Chunking vCard data to process transaction");
                        var blocks = deleteVCardDataBatch.Chunk(99);

                        var chunkCount = 1;
                        foreach (var transaction in blocks)
                        {
                            log.LogInformation("[VCardCleanup] Deleting chunk {chunkCount} with {transactionLength} elements", chunkCount, transaction.Length);
                            await tableClient.SubmitTransactionAsync(transaction, cancellationToken);
                            chunkCount += 1;
                        }
                    }
                    else
                    {
                        log.LogInformation("[VCardCleanup] Deleting chunk with {count} elements", deleteVCardDataBatch.Count);
                        await tableClient.SubmitTransactionAsync(deleteVCardDataBatch, cancellationToken);
                    }
                }
                catch (Exception ex)
                {
                    log.LogError(ex, "[VCardCleanup] Error submitting transaction to storage");
                }
            }
            else
            {
                log.LogWarning("[VCardCleanup] No vCard Data found");
            }

            #endregion

            #region Photo cleanup

            if (!_configuration.GetValue<bool>("UsePhoto"))
            {
                var vCardDataModels = tableClient.Query<VCardDataModel>(v => v.Photo != string.Empty || v.Photo != null).ToList();

                vCardDataModels.ForEach(d => d.Photo = string.Empty);
                var updateVCardDataBatch = vCardDataModelsToDelete.Select(data => new TableTransactionAction(TableTransactionActionType.UpsertMerge, data)).ToList();

                try
                {
                    if (updateVCardDataBatch.Count >= 100)
                    {
                        log.LogInformation("[VCardCleanup] Chunking vCard data to process photo removal transaction");
                        var blocks = updateVCardDataBatch.Chunk(99);

                        var chunkCount = 1;
                        foreach (var transaction in blocks)
                        {
                            log.LogInformation("[VCardCleanup] Updating chunk {chunkCount} with {transactionLength} elements to remove photo", chunkCount, transaction.Length);
                            await tableClient.SubmitTransactionAsync(transaction, cancellationToken);
                            chunkCount += 1;
                        }
                    }
                    else
                    {
                        log.LogInformation("[VCardSync] Updating chunk with {count} elements to remove photo", updateVCardDataBatch.Count);
                        await tableClient.SubmitTransactionAsync(updateVCardDataBatch, cancellationToken);
                    }
                }
                catch (Exception ex)
                {
                    log.LogError(ex, "[VCardSync] Error submitting photo removal transaction to storage");
                }
            }

            #endregion

            log.LogInformation("[VCardCleanup] vCard cleanup stopped execution at: {date}", DateTime.Now);
        }
        catch (OperationCanceledException)
        {
            log.LogWarning("[VCardCleanup] Function cancelled");
        }
    }
}