param(
    [Parameter(Mandatory = $true, HelpMessage = "Tenant Id of the Azure AD")]
    [Guid]$TenantId = $(throw "-TenantId is required"),
    [Parameter(Mandatory = $true, HelpMessage = "Subscription Id of the Resources")]
    [Guid]$SubscriptionId = $(throw "-SubscriptionId is required"),
    [Parameter(Mandatory = $true, HelpMessage = "Id pf the group to search the users in")]
    [string]$GraphUserGroup = $(throw "GraphUserGroup is required"),
    [Parameter(Mandatory = $false, HelpMessage = "Name of the App registration")]
    [string]$ServicePrincipalName = "VCSL vCard",
    [Parameter(Mandatory = $true, HelpMessage = "Shortname of the Company")]
    [string]$OrgName = $(throw "-OrgName is required"),
    [Parameter(Mandatory = $false, HelpMessage = "Set location of ressources")]
    [ValidateSet("gwc", "gn", "we", "ne")]
    [string]$Location = "gwc",
    [Parameter(Mandatory = $false, HelpMessage = "Export Links to all vCards as CSV")]
    [switch]$ExportLinks = $false
)

function log {
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

    $AzDownloadFuncName = ("func-{0}-vcsldownload-{1}-001" -f $OrgName, $Location).ToLower().ToString()

    if ($ExportLinks) {
        # $users = @{}
        # $iterator = 0
        $users = Get-AzADGroupMember -GroupObjectId $GraphUserGroup | ForEach-Object {
            [pscustomobject]@{DisplayName = $_.DisplayName; Url = "https://$($AzDownloadFuncName).azurewebsites.net/api/VCardDownload?id=$($_.Id)";}            
        }

        # $users | Format-Table
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