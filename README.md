# VCSL

## Voraussetzungen
### PowerShell Module
Für die Ausführung des Deployments müssen folgende PowerShell Module installiert sein:

#### Az.Identity
``` PowerShell
Install-Module Az.Identity -Scope CurrentUser
```

#### Az.Ressources
``` PowerShell
Install-Module Az.Ressources -Scope CurrentUser
```

#### Az.Websites
``` PowerShell
Install-Module Az.Websites -Scope CurrentUser
```

#### Az.Functions
``` PowerShell
Install-Module Az.Functions -Scope CurrentUser
```



### Bicep
Ebenso muss die Bicep CLI installiert sein.

Installation mit Winget
``` PowerShell
winget install -e --id Microsoft.Bicep
```

Installation mittels Powershell
``` PowerShell
# Create the install folder
$installPath = "$env:USERPROFILE\.bicep"
$installDir = New-Item -ItemType Directory -Path $installPath -Force
$installDir.Attributes += 'Hidden'

# Fetch the latest Bicep CLI binary
(New-Object Net.WebClient).DownloadFile("https://github.com/Azure/bicep/releases/latest/download/bicep-win-x64.exe", "$installPath\bicep.exe")

# Add bicep to your PATH
$currentPath = (Get-Item -path "HKCU:\Environment" ).GetValue('Path', '', 'DoNotExpandEnvironmentNames')

if (-not $currentPath.Contains("%USERPROFILE%\.bicep")) { 
    setx PATH ($currentPath + ";%USERPROFILE%\.bicep") 
}
if (-not $env:path.Contains($installPath)) { 
    $env:path += ";$installPath" 
}

# Verify you can now access the 'bicep' command.
bicep --help

# Done!
```

### Berechtigung
Für das automatische angelegen bzw. für das einrichten des App Secrets für den Service Principal wird die aktivierte Rolle `Application Administrator` benötigt.



## Deployment

``` PowerShell
.\Run-Deployment.ps1 -TenantId "<TenantId>" -SubscriptionId "<SubscriptionId>" -GraphUserGroup "<GroupId (Aus Azure)>" -OrgName "<Orgname (Bsp. ihkhl)>" -ServicePrincipalName "VCSL vCard" -HomepageUrl "<HomepageUrl>" -UsePhoto $true -Location "gwc"
```