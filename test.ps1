param (
    [Parameter(Mandatory = $false, HelpMessage = "Toggle the code should be recompiled")]
    [switch]$Recompile
)

Write-Host $Recompile