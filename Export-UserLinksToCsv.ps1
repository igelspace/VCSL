param(
    [Parameter(Mandatory = $true, HelpMessage = "Tenant Id of the Azure AD")]
    [Guid]$TenantId = $(throw "-TenantId is required"),
    [Parameter(Mandatory = $true, HelpMessage = "Id of the group to search the users in")]
    [string]$GraphUserGroup = $(throw "GraphUserGroup is required")
)

try {
    [Void] (Connect-AzAccount -TenantId $TenantId -UseDeviceAuthentication)

    $users = Get-AzADGroupMember -GroupObjectId $GraphUserGroup | ForEach-Object {
        [pscustomobject]@{DisplayName = $_.DisplayName; Url = "https://$($AzDownloadFuncName).azurewebsites.net/api/VCardDownload?id=$($_.Id)"; }            
    }

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