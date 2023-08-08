param(
    [Parameter(Mandatory = $true, HelpMessage = "Tenant Id of the Azure AD")]
    [Guid]$TenantId = $(throw "-TenantId is required"),
    [Parameter(Mandatory = $true, HelpMessage = "Subscription Id of the Resources")]
    [Guid]$SubscriptionId = $(throw "-SubscriptionId is required"),
    [Parameter(Mandatory = $true, HelpMessage = "GraphUserGroup Id where the users are located")]
    [Guid]$GraphUserGroup = $(throw "GraphUserGroup is required"),
    [Parameter(Mandatory = $false, HelpMessage = "Name of the App registration")]
    [string]$ServicePrincipalName = "VCSL vCard",
    [Parameter(Mandatory = $false, HelpMessage = "URL of the homepage used in the vCard")]
    [string]$HomepageUrl,
    [Parameter(Mandatory = $false, HelpMessage = "Toggle if photos of the users are included in the vCards")]
    [bool]$UsePhoto,
    [Parameter(Mandatory = $false, HelpMessage = "Set location of ressources")]
    [ValidateSet("gwc", "gn", "we", "ne")]
    [string]$Location = "gwc",
    [Parameter(Mandatory = $false, HelpMessage = "Working directory as a relative path to project location")]
    [string]$WorkDir = "temp",
    [Parameter(Mandatory = $false, HelpMessage = "Toggle the code should be recompiled")]
    [switch]$Recompile = $false,
    [switch]$SkipResourceGroupCreation = $false,
    [switch]$SkipBicepDeployment = $false
)

function log{
    param(
        $text
    )

    write-host $text -ForegroundColor Yellow -BackgroundColor DarkGreen
}

function publish{
    param(
        $projectName        
    )
    $basePath = $PSScriptRoot
    $workingDir = "$($basePath)/$($WorkDir)"
    If ((Test-Path -Path "$($workingDir)\$($projectName).zip") -and ($Recompile -eq $false)) {
        return
    }

    log "Publishing project $($projectName)"
    if (-not(Test-Path -Path $workingDir)) {
        New-Item -Path $basePath -Name $WorkDir -ItemType "directory"
    }

    $projectPath="$($basePath)\$($projectName)\$($projectName).csproj"
    $publishDestPath="$($workingDir)\$($projectName)"

    log "publishing project '$($projectName)' in folder '$($publishDestPath)' ..." 
    dotnet publish $projectPath -c Release -o $publishDestPath

    $zipArchiveFullPath="$($publishDestPath).zip"
    log "creating zip archive '$($zipArchiveFullPath)'"
    $compress = @{
        Path = $publishDestPath + "/*"
        CompressionLevel = "Fastest"
        DestinationPath = $zipArchiveFullPath
    }
    Compress-Archive @compress -Force

    log "cleaning up ..."
    Remove-Item -path "$($publishDestPath)" -recurse
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
    $ctx = Get-AzContext -ListAvailable | Where-Object { $_.Subscription.Id -eq $SubscriptionId }
    [Void] (Set-AzContext -Context $ctx)
    log "Creating new credentials for Service Principal"
    Get-AzADAppCredential -DisplayName $ServicePrincipalName | ForEach-Object {
        Remove-AzADAppCredential -DisplayName $ServicePrincipalName -KeyId $_.KeyId
    }

    $startDate = Get-Date
    $endDate = $startDate.AddYears(1)

    $servicePrincipalCredential = New-AzADAppCredential -DisplayName $ServicePrincipalName -StartDate $startDate -EndDate $endDate

    $appId = $($servicePrincipal.AppId)
    $appSecret = $($servicePrincipalCredential.SecretText)

    
    $ressourceGroupName = "rg-vcsl-${Location}-001"
    
    switch ($Location) {
        "gwc" {
            $locationDisplayName = "Germany West Central"
            $locationName = "germanywestcentral"
        }
        "gn" {
            $locationDisplayName = "Germany North"
            $locationName = "germanynorth"
        }
        "we" {
            $locationDisplayName = "West Europe"
            $locationName = "westeurope"
        }
        "ne" {
            $locationDisplayName = "North Europe"
            $locationName = "northeurope"
        }
    }

    if ($SkipResourceGroupCreation) {
        log "Skipping ressource group creation"
    }
    else {
        log "Creating ressource group"
        [void](New-AzResourceGroup -Name $ressourceGroupName -Location $locationDisplayName)
    }

    if ($SkipBicepDeployment) {
        log "Skipping bicep deployment"
    }
    else {
        log "Deploying bicep template"
        $random = Get-Random -Minimum 1000 -Maximum 10000
        [void](New-AzResourceGroupDeployment -Name "VCSLDeployment$(Get-Date -Format "yyyyMMddHHmmss")$($random)" -ResourceGroupName $ressourceGroupName -TemplateFile 'main.bicep' -TemplateParameterFile 'main.bicepparam')
    }

    $basePath = $PSScriptRoot
    $workingDir = "$($basePath)/$($WorkDir)"

    $AzSyncFuncName = 'func-ihkhl-vcslsync-germanywestcentral-001'
    $AzDownloadFuncName = 'func-ihkhl-vcsldownload-germanywestcentral-001';
    
    publish("VCSL.Download");
    log "Deploying ($AzDownloadFuncName) to azure"
    [void](Publish-AzWebapp -Name $AzDownloadFuncName -ResourceGroupName $ressourceGroupName -ArchivePath "$($workingDir)\VCSL.Download.zip" -Force -Clean)
    
    $ctx = Get-AzContext -ListAvailable | Where-Object { $_.Subscription.Id -eq $SubscriptionId }
    [Void] (Set-AzContext -Context $ctx)

    publish("VCSL.Sync");
    log "Deploying $($AzSyncFuncName) to azure"
    [void](Publish-AzWebapp -Name $AzSyncFuncName -ResourceGroupName $ressourceGroupName -ArchivePath "$($workingDir)\VCSL.Sync.zip" -Force -Clean)

    log "Updating settings for $($AzDownloadFuncName)"
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
    log "Finished updating settings for $($AzDownloadFuncName)"

    log "Updating settings for $($AzSyncFuncName)"
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
    $newAppSettingsSync["TenantId"] = $TenantId.ToString()
    $newAppSettingsSync["ClientId"] = $appId
    $newAppSettingsSync["ClientSecret"] = $appSecret
    $newAppSettingsSync["GraphUserGroup"] = $GraphUserGroup
    [void](Update-AzFunctionAppSetting -ResourceGroupName $ressourceGroupName -Name $AzSyncFuncName -SubscriptionId $SubscriptionId -AppSetting  $newAppSettingsSync -Force)
    log "Finished updating settings for $($AzSyncFuncName)"
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