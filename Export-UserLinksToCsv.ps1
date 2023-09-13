param(
    [Parameter(Mandatory = $true, HelpMessage = "Tenant Id of the Azure AD")]
    [Guid]$TenantId = $(throw "-TenantId is required"),
    [Parameter(Mandatory = $true, HelpMessage = "Id pf the group to search the users in")]
    [string]$GraphUserGroup = $(throw "GraphUserGroup is required"),
    [Parameter(Mandatory = $true, HelpMessage = "Shortname of the Company")]
    [string]$OrgName = $(throw "-OrgName is required"),
    [Parameter(Mandatory = $false, HelpMessage = "Set location of ressources")]
    [ValidateSet("gwc", "gn", "we", "ne")]
    [string]$Location = "gwc"
)

function log {
    param(
        $text
    )

    write-host $text -ForegroundColor Yellow -BackgroundColor DarkGreen
}

try {
    
    [Void] (Connect-AzAccount -TenantId $ctx.Tenant.Id -UseDeviceAuthentication)
    $AzDownloadFuncName = ("func-{0}-vcsldownload-{1}-001" -f $OrgName, $Location).ToLower().ToString()

    $users = Get-AzADGroupMember -GroupObjectId $GraphUserGroup | ForEach-Object {
        [pscustomobject]@{DisplayName = $_.DisplayName; Url = "https://$($AzDownloadFuncName).azurewebsites.net/api/VCardDownload?id=$($_.Id)"; }            
    }

    # $users | Format-Table
    Add-Type -AssemblyName System.Windows.Forms
    $saveDialog = New-Object -TypeName System.Windows.Forms.SaveFileDialog
    $saveDialog.initialDirectory = "C:${env:HOMEPATH}\Desktop"
    $saveDialog.filter = "CSV (*.csv)|*.csv|All files (*.*)|*.*";
    $saveDialog.ShowDialog()								
    $users | Export-Csv -Path $saveDialog.FileName
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