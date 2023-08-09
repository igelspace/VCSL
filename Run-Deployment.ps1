param(
    [Parameter(Mandatory = $true, HelpMessage = "Tenant Id of the Azure AD")]
    [Guid]$TenantId = $(throw "-TenantId is required"),
    [Parameter(Mandatory = $true, HelpMessage = "Subscription Id of the Resources")]
    [Guid]$SubscriptionId = $(throw "-SubscriptionId is required"),
    [Parameter(Mandatory = $true, HelpMessage = "Shortname of the Company")]
    [string]$OrgName = $(throw "-OrgName is required"),
    [Parameter(Mandatory = $true, HelpMessage = "Id pf the group to search the users in")]
    [string]$GraphUserGroup = $(throw "GraphUserGroup is required"),
    [Parameter(Mandatory = $false, HelpMessage = "Name of the App registration")]
    [string]$ServicePrincipalName = "VCSL vCard",
    [Parameter(Mandatory = $false, HelpMessage = "URL of the homepage used in the vCard")]
    [string]$HomepageUrl,
    [Parameter(Mandatory = $false, HelpMessage = "Toggle if photos of the users are included in the vCards")]
    [switch]$UsePhoto = $false,
    [Parameter(Mandatory = $false, HelpMessage = "Set location of ressources")]
    [ValidateSet("gwc", "gn", "we", "ne")]
    [string]$Location = "gwc"
)

function log{
    param(
        $text
    )

    write-host $text -ForegroundColor Yellow -BackgroundColor DarkGreen
}

$currentCtx = Get-AzContext;
try {
    $freshLogin = $false;
    $ctx = Get-AzContext -ListAvailable | Where-Object { $_.Subscription.Id -eq $SubscriptionId }
    if (!$ctx) {
        [Void] (Connect-AzAccount -TenantId $TenantId -UseDeviceAuthentication)
        $ctx = Get-AzContext -ListAvailable | Where-Object { $_.Subscription.Id -eq $SubscriptionId }
        $freshLogin = $true;
    }
    if ($ctx.Count -gt 1 -and $Account) {
        $ctx = $ctx | Where-Object { $_.Account.Id -eq $Account }
    }
    if ($ctx.Count -gt 1) {
        $confirm = Read-Host "Too many azure contexts found. Clear all and relogin? (y/N)";
        if ($confirm -ne 'Y' -and $confirm -ne 'y') {
            Write-Host "Exiting";
            exit;
        }
        else {
            [Void] (Clear-AzContext -Force)
            [Void] (Connect-AzAccount -TenantId $TenantId -UseDeviceAuthentication)
            $ctx = Get-AzContext -ListAvailable | Where-Object { $_.Subscription.Id -eq $SubscriptionId }
            $freshLogin = $true;
        }

    }
    if (!$ctx) {
        throw "No valid azure context found!";
    }
    $confirm = Read-Host "Run Deployment for Azure '$($ctx.Name)'. Continue? (y/N)";
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        exit;
    }
    if (!$freshLogin) {
        $confirm = Read-Host "Relogin for Deployment? (y/N)";
        if ($confirm -eq 'Y' -and $confirm -eq 'y') {
            [Void] (Connect-AzAccount -TenantId $ctx.Tenant.Id -UseDeviceAuthentication)
            $ctx = Get-AzContext -ListAvailable | Where-Object { $_.Subscription.Id -eq $SubscriptionId }
        }
    }
    [Void] (Set-AzContext -Context $ctx)

    <#
        Preparing variables for bicep deployment
    #>
    $ressourceGroupName = "rg-${OrgName}-vcsl-${Location}-001"

    $bicepParams = Get-Item -Path .\main_param.bicepparam
    $bicepParamsContent = Get-Content -Path $bicepParams.FullName
    $bicepParamsContent = $bicepParamsContent -replace "ihkhl", $OrgName.ToLower()
    Set-Content -Path $bicepParams.FullName -Value $bicepParamsContent

    switch ($Location) {
        "gwc" {
            $locationDisplayName = "Germany West Central"
            # $locationName = "germanywestcentral"
        }
        "gn" {
            $locationDisplayName = "Germany North"
            # $locationName = "germanynorth"
        }
        "we" {
            $locationDisplayName = "West Europe"
            # $locationName = "westeurope"
        }
        "ne" {
            $locationDisplayName = "North Europe"
            # $locationName = "northeurope"
        }
    }

    <#
        Creating ressource group and deeploying bicep template
    #>
    log "Creating creating / updating resource group"
    [void](New-AzResourceGroup -Name $ressourceGroupName -Location $locationDisplayName)
    log "Deploying bicep template"
    [void](New-AzResourceGroupDeployment -Name "AppDeployment$(Get-Date -Format "yyyyMMddHHmmss")$(Get-Random -Minimum 000000 -Maximum 999999)" -ResourceGroupName $ressourceGroupName -TemplateFile 'main.bicep' -TemplateParameterFile 'main_param.bicepparam')
    log "Completed deploying bicep template"

    <#
        Creating service principal and renewing app secrets
    #>
    log "Checking service principal"
    $servicePrincipal = Get-AzADServicePrincipal -DisplayName $ServicePrincipalName    
    if ($null -eq $servicePrincipal) {
        log "Service principal not found. Creating new service principal"
        $servicePrincipal = New-AzADServicePrincipal -DisplayName $ServicePrincipalName
        log "Service Principal created!"
    }

    log "Creating app secret for service principal"
    Get-AzADAppCredential -DisplayName $ServicePrincipalName | ForEach-Object {
        Remove-AzADAppCredential -DisplayName $ServicePrincipalName -KeyId $_.KeyId
    }

    $startDate = Get-Date
    $endDate = $startDate.AddYears(1)

    $servicePrincipalCredential = New-AzADAppCredential -DisplayName $ServicePrincipalName -StartDate $startDate -EndDate $endDate

    $appId = $($servicePrincipal.AppId)
    $appSecret = $($servicePrincipalCredential.SecretText)

    <#
        Preparing variables for deployment
    #>
    # $path = $PSScriptRoot

    $AzSyncFuncName = ("func-{0}-vcslsync-{1}-001" -f $OrgName, $Location).ToLower().ToString()
    # $AzSyncFuncZip = "${path}/VCSL.Sync.zip";
    $AzDownloadFuncName = ("func-{0}-vcsldownload-{1}-001" -f $OrgName, $Location).ToLower().ToString()
    # $AzDownloadFuncZip = "${path}/VCSL.Download.zip";
    
    <#
        Deploying Sync functions
    #>
    log "Updating settings for Azure function $($AzSyncFuncName)"
    $webAppSync = Get-AzFunctionAppSetting -Name $AzSyncFuncName -ResourceGroupName $ressourceGroupName -SubscriptionId $SubscriptionId
    $newAppSettingsSync = @{}
    ForEach ($kvp in $webAppSync.SiteConfig.AppSettings) {
        $newAppSettingsSync[$kvp.Name] = $kvp.Value
    }
    $newAppSettingsSync["updated"] = $(Get-Date -Format "yyyyMMddHHmmss").ToString()
    $newAppSettingsSync["FUNCTIONS_EXTENSION_VERSION"] = "~4"
    $newAppSettingsSync["FUNCTIONS_WORKER_RUNTIME"] = "dotnet"
    $newAppSettingsSync["AzureWebJobsFeatureFlags"] = "EnableProxies"
    $newAppSettingsSync["UsePhoto"] = $UsePhoto.ToString()
    $newAppSettingsSync["GraphUserGroup"] = $GraphUserGroup
    $newAppSettingsSync["TenantId"] = $TenantId.ToString()
    if (($null -ne $appId) -and ($appId -ne "")){
        $newAppSettingsSync["ClientId"] = $appId
    }
    if (($null -ne $appSecret) -and ($appSecret -ne "")){
        $newAppSettingsSync["ClientSecret"] = $appSecret
    }
    $newAppSettingsSync["Authority"] = ""    

    [void](Update-AzFunctionAppSetting -ResourceGroupName $ressourceGroupName -Name $AzSyncFuncName -SubscriptionId $SubscriptionId -AppSetting  $newAppSettingsSync -Force)
    log "Finished updating $($webApp.Name) settings"

    log "Start deploy Azure Function to $($AzSyncFuncName) in $($ressourceGroupName)..."
    # $AzSyncFuncApp = Get-AzWebApp -ResourceGroupName $ressourceGroupName -Name $AzSyncFuncName
    [void](Publish-AzWebapp -Name $AzSyncFuncName -ResourceGroupName $ressourceGroupName -ArchivePath (Get-Item .\VCSL.Sync.zip).FullName -Force)
    log "Finished deploying Function $($AzSyncFuncName)"
    <#
        Deploying Download functions
    #>
    log "Updating settings for Azure function $($AzDownloadFuncName)"
    $webAppDownload = Get-AzFunctionAppSetting -Name $AzDownloadFuncName -ResourceGroupName $ressourceGroupName -SubscriptionId $SubscriptionId
    $newAppSettingsDownload = @{}
    ForEach ($kvp in $webAppDownload.SiteConfig.AppSettings) {
        $newAppSettingsDownload[$kvp.Name] = $kvp.Value
    }
    $newAppSettingsDownload["updated"] = $(Get-Date -Format "yyyyMMddHHmmss").ToString()
    $newAppSettingsDownload["FUNCTIONS_EXTENSION_VERSION"] = "~4"
    $newAppSettingsDownload["FUNCTIONS_WORKER_RUNTIME"] = "dotnet"
    $newAppSettingsDownload["AzureWebJobsFeatureFlags"] = "EnableProxies"
    $newAppSettingsDownload["SourcePath"] = "${AzDownloadFuncName}.azurewebsites.net"
    $newAppSettingsDownload["HomepageUrl"] = $HomepageUrl

    [void](Update-AzFunctionAppSetting -ResourceGroupName $ressourceGroupName -Name $AzDownloadFuncName -SubscriptionId $SubscriptionId -AppSetting $newAppSettingsDownload -Force)
    log "Finished pdating $($AzDownloadFuncName) settings"

    log "Start deploy Azure Function to $($AzDownloadFuncName) in $($ressourceGroupName)..."
    # $AzDownloadFuncApp = Get-AzWebApp -ResourceGroupName $ressourceGroupName -Name $AzDownloadFuncName
    [void](Publish-AzWebapp -Name $AzDownloadFuncName -ResourceGroupName $ressourceGroupName -ArchivePath (Get-Item .\VCSL.Download.zip).FullName -Force)
    log "Finished deploying Function $($AzDownloadFuncName)"

    Write-Host ""
    log "To use the vCards prepage NFC Cards / AR Codes with the following link structure for each user:"
    log "https://$($AzDownloadFuncName).azurewebsites.net/api/VCardDownload?id=<ID of the User>"

    Write-Host ""
    log "The final touch needed is to give GroupMember.Read.All Permission to the Service Principal created (See documentation)"

    if ($ExportLinks) {
        log "Exporting vCard Links for users as CSV"
        $users = Get-AzADGroupMember -GroupObjectId $GraphUserGroup | ForEach-Object {
            [pscustomobject]@{DisplayName = $_.DisplayName; Url = "https://$($AzDownloadFuncName).azurewebsites.net/api/VCardDownload?id=$($_.Id)";}            
        }

        Add-Type -AssemblyName System.Windows.Forms
        $saveDialog = New-Object -TypeName System.Windows.Forms.SaveFileDialog
        $saveDialog.initialDirectory = "C:${env:HOMEPATH}\Desktop"
        $saveDialog.filter = "CSV (*.csv)|*.csv|All files (*.*)|*.*";
        $saveDialog.ShowDialog()								
        $users | Export-Csv -Path $saveDialog.FileName
    }
}
catch {
    Write-Error $_.Exception.Message
    Break
}
finally {
    if ($currentCtx) {
        [Void] (Set-AzContext -Context $currentCtx -ErrorAction SilentlyContinue)
    }
}