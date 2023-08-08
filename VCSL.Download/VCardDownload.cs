using System;
using System.IO;
using System.Threading.Tasks;
using System.Web.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using Azure.Data.Tables;
using VCSL.Shared.Extensions;
using VCSL.Shared.Helper;
using VCSL.Shared.Models;

namespace VCSL.Download;

public class VCardDownload
{
    private readonly IConfiguration _configuration;

    public VCardDownload(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [FunctionName("VCardDownload")]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", "post", Route = null)] HttpRequest req,
        ILogger log, ExecutionContext context)
    {
        log.LogInformation("[VCardDownload] vCard download started execution at: {date}", DateTime.Now);

        try
        {
            string id = req.Query["Id"];

            if (string.IsNullOrWhiteSpace(id) || GuidHelper.IsValidGuid(id) is not true)
            {
                log.LogError("[VCardDownload] No id provided");
                return new BadRequestObjectResult("No valid ID was provided");
            }

            #region Data retrieval

            log.LogInformation("[VCardDownload] Connecting to storage account");
            var connectionString = _configuration.GetConnectionString("VCSLStorage");
            var tableClient = new TableClient(connectionString, "VCardData");

            log.LogInformation("[VCardDownload] Retrieving vCard for id {id}", id);
            var vCardData = (VCardDataModel)tableClient.GetEntity<VCardDataModel>("Data", id);

            if (vCardData == null || string.IsNullOrWhiteSpace(vCardData.DisplayName))
            {
                log.LogError("[VCardDownload] No vCard found for id {id}", id);
                return new NotFoundResult();
            }

            log.LogInformation("[VCardDownload] Found vCard for {name}", vCardData.DisplayName);
            
            #endregion

            #region vCard preperation

            log.LogInformation("[VCardDownload] Loading template for vCard");
            var file = await System.IO.File.ReadAllTextAsync($"{context.FunctionAppDirectory}/Templates/vCardTemplate.txt");

            log.LogInformation("[VCardDownload] Substituting values in template");
            file = file.Replace("[surname]", vCardData.Surname);
            file = file.Replace("[givenName]", vCardData.GivenName);
            file = file.Replace("[displayName]", vCardData.DisplayName);
            file = file.Replace("[department]", vCardData.Department);
            file = file.Replace("[title]", vCardData.JobTitle);
            file = file.Replace("[company]", vCardData.CompanyName);
            file = file.Replace("[phone]", vCardData.TelephoneNumber);
            file = file.Replace("[street]", vCardData.StreetAddress);
            file = file.Replace("[city]", vCardData.City);
            file = file.Replace("[state]", vCardData.State);
            file = file.Replace("[postalCode]", vCardData.PostalCode);
            file = file.Replace("[country]", vCardData.Country);
            file = file.Replace("[mail]", vCardData.Mail);
            file = file.Replace("[upn]", vCardData.UserPrincipalName);
            file = file.Replace("[mobile]", (string.IsNullOrEmpty(vCardData.MobilePhone)
                ? ""
                : $"TEL;CELL:{vCardData.MobilePhone}"));
            file = file.Replace("[date]", (vCardData.Timestamp != null)
                ? vCardData.Timestamp.Value.Date.ToIsoDateString()
                : DateTime.Now.ToIsoDateString());

            file = file.Replace("[homepageUrl]", string.IsNullOrEmpty(_configuration["HomepageUrl"])
                ? ""
                : $"URL;WORK:{_configuration["HomepageUrl"]}");
            file = file.Replace("[source]", string.IsNullOrEmpty(_configuration["SourcePath"])
                ? ""
                : $"SOURCE:{_configuration["SourcePath"]}/api/VCardDownload?id={id}");
            file = file.Replace("[photo]", (string.IsNullOrEmpty(vCardData.Photo)
                ? ""
                : $"PHOTO;JPEG;ENCODING=BASE64:{vCardData.Photo}"));

            log.LogInformation("[VCardDownload] Preparing vCard file");
            var fileResult = new FileStreamResult(ToStream(file), "application/octet-stream")
            {
                FileDownloadName = $"{vCardData.GivenName}.{vCardData.Surname}.vcf"
            };

            #endregion

            log.LogInformation("[VCardDownload] Returning vCard file");
            log.LogInformation("[VCardDownload] vCard download stopped execution at: {date}", DateTime.Now);
            return fileResult;
        }
        catch (OperationCanceledException)
        {
            log.LogError("[VCardDownload] Function cancelled");
            log.LogInformation("[VCardDownload] vCard download stopped execution at: {date}", DateTime.Now);
            return new InternalServerErrorResult();
        }
        catch (Exception ex)
        {
            log.LogError(ex, "[VCardDownload] A general error occurred retrieving the vCard");
            log.LogInformation("[VCardDownload] vCard download stopped execution at: {date}", DateTime.Now);
            return new InternalServerErrorResult();
        }
    }

    private static Stream ToStream(string str)
    {
        var stream = new MemoryStream();
        var writer = new StreamWriter(stream);
        writer.Write(str);
        writer.Flush();
        stream.Position = 0;
        return stream;
    }
}