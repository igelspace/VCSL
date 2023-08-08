param(
    [Parameter(Mandatory = $true, HelpMessage = "Tenant Id of the Azure AD")]
    [Guid]$TenantId = $(throw "-TenantId is required"),
    [Parameter(Mandatory = $true, HelpMessage = "Subscription Id of the Resources")]
    [Guid]$SubscriptionId = $(throw "-SubscriptionId is required"),
    [Parameter(Mandatory = $false, HelpMessage = "Name of the App registration")]
    [string]$ServicePrincipalName = "VCSL vCard",
    [Parameter(Mandatory = $false, HelpMessage = "URL of the homepage used in the vCard")]
    [string]$HomepageUrl = "",
    [Parameter(Mandatory = $false, HelpMessage = "Toggle if photos of the users are included in the vCards")]
    [bool]$UsePhoto = $true,
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

    log "Checking Service Principal"
    $servicePrincipal = Get-AzADServicePrincipal -DisplayName $ServicePrincipalName
    
    if ($null -eq $servicePrincipal) {
        log "Service Principal does not exist. Creating new Service Principal"
        $servicePrincipal = New-AzADServicePrincipal -DisplayName $ServicePrincipalName
    }
    else {
        log "Service Principal already exists"
    }

    log "Creating new credentials for Service Principal"
    Get-AzADAppCredential -DisplayName $ServicePrincipalName | ForEach-Object {
        Remove-AzADAppCredential -DisplayName $ServicePrincipalName -KeyId $_.KeyId
    }

    $startDate = Get-Date
    $endDate = $startDate.AddYears(1)

    $servicePrincipalCredential = New-AzADAppCredential -DisplayName $ServicePrincipalName -StartDate $startDate -EndDate $endDate

    $appId = $($servicePrincipal.AppId)
    $appSecret = $($servicePrincipalCredential.SecretText)

    log "Creating ressource group"
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

    [void](New-AzResourceGroup -Name $ressourceGroupName -Location $locationDisplayName)

    log "Deploying bicep template"
    $random = Get-Random -Minimum 1000 -Maximum 10000
    [void](New-AzResourceGroupDeployment -Name "VCSLDeployment$(Get-Date -Format "yyyyMMddHHmmss")$($random)" -ResourceGroupName $ressourceGroupName -TemplateFile 'main.bicep' -TemplateParameterFile 'main.bicepparam')
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