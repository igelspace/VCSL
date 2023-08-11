# VCSL

## Funktion

VSCL ist ein simples Tool um digitale Visitenkarten mittels vCards, anhand der Daten aus dem eigenen Azure Active Directory (AAD), bereitzustellen, ohne externen Personen einen direkten Zugriff auf selbiges zu geben.

## Aufbau

VCSL besteht aus 2 Azure Function Apps (VCSL Sync und VCSL Download), einem Storage Account und der Benötigten Infrastruktur für die Überwachung.
VCSL Sync hat 2 Azure Functions. VCardSync ruft die Kontaktdaten der Personen anhand der eingestellten aus dem AAD ab und speichert diese in dem Storage Account

```mermaid
graph TD
    subgraph rg-abcde-vcsl-gwc-001
        A[Azure Function<br>func-abcde-vcslsync-gwc-001]---C[Storage Account<br>saabcdevcsl]
        F[VCardSync]---A
        G[VCardCleanup]---A
        B[Azure Function<br>func-abcde-vcsldownload-gwc-001]---C
        A---D[Application Insights<br>appi-abcde-vcsl-gwc-001]
        B---D
        A---E[App Service Plan<br>asp-abcde-vcsl-gwc-001]
        B---E
        H[VCardDownload]---B
    end
    I[Azure Active Directory]---F
    I[Azure Active Directory]---G
```

<sub>Im gezeigten Graphen wird davon ausgegangen das die Organisation das Kürzel 'abcde' hat und die Lösung am Azure Standort 'Germany West Central' bereitgestellt wurde.</sub>

## Voraussetzungen

### PowerShell Module

Für die Ausführung des Deployments müssen folgende PowerShell Module installiert sein:

#### Az.Identity

``` PowerShell
Install-Module Az.Identity -Scope CurrentUser
```

#### Az.Resources ([Microsoft Learn | Az.Resources](https://learn.microsoft.com/en-us/powershell/module/az.resources/))

``` PowerShell
Install-Module Az.Ressources -Scope CurrentUser
```

#### Az.Websites ([Microsoft Learn | Az.Websites](https://learn.microsoft.com/en-us/powershell/module/az.websites/))

``` PowerShell
Install-Module Az.Websites -Scope CurrentUser
```

#### Az.Functions ([Microsoft Learn | Az.Functions](https://learn.microsoft.com/en-us/powershell/module/az.functions/))

``` PowerShell
Install-Module Az.Functions -Scope CurrentUser
```

### Bicep ([Microsoft Learn | Installieren von Bicep-Tools](https://learn.microsoft.com/de-de/azure/azure-resource-manager/bicep/install))

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

### .Net SDK `(Nur beim selbst Kompilieren erforderlich)` [.Net 6.0](https://dotnet.microsoft.com/en-us/download/dotnet/6.0)

``` PowerShell
winget install Microsoft.DotNet.SDK.6
```

## Deployment

### Parameter

#### -TenantId `(erforderlich)`

Die ID des eigenen Tenants in welchem das Tool laufen soll. Die eigene Tenant ID kann [hier (Azure Active Directory | Overview)](https://portal.azure.com/#view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/Overview) eingesehen werden.

#### -SubscriptionId `(erforderlich)`

Die ID der Subscription in welcher die Ressourcen liegen sollen. Die verfügbaren Subscriptions können [hier (Subscriptions)](https://portal.azure.com/#view/Microsoft_Azure_Billing/SubscriptionsBlade) eingesehen werden.

#### -GraphUserGroup `(erforderlich)`

Die ID der Gruppe in welchen alle Personen hinterlegt sind für welche die Daten der vCards vorgehalten werden sollen.

#### -OrgName `(erforderlich)`

Identifikator der eigenen Organisation. Dieser Wert wird in allen Ressourcennamen hinterlegt. Da die Namen einiger zu erstellender Ressourcen (Storage Account / Azure Functions) global eindeutig sein müssen sollte hier kein allzu allgemeiner Name verwendet werden. Empfehlenswert ist das Kürzel aus der Primary Domain

#### -ServicePrincipalName `(optional)`

Der Name des Service Principals (/App Registration) welche für die Graph Berechtigungen benutzt wird. Als Default ist `VCSL vCard` hinterlegt.

#### -HomepageUrl `(optional)`

Optionale Homepage welche in allen vCards hinterlegt wird.

#### -Location `(optional)`

Die Azure Region in welcher die Ressourcen erstellt werden sollen. Erlaubt sind:

- we (West Europe)
- ne (North Europe)
- gn (Germany North)
- gwc (Germany West Central) `default`

#### -UsePhoto `(optional)`

Wenn dieser Parameter mit angegeben wird werden die in Azure hinterlegten Bilder mit in die vCards eingefügt

#### -Recompile `(optional)`

Nur beim Deployment vom Source Code verfügbar. Wenn der Flag nicht gesetzt ist wird der Source Code nur bei der ersten Ausführung kompiliert.

#### -ExportLinks `(optional)`

Wenn dieser Flag gesetzt wird werden für alle Personen in der angegebenen Gruppe die Links zu den vCards generiert und als CSV exportiert.

<!-- ### Deployment vom Release

``` PowerShell
.\Run-Deployment.ps1 -TenantId "<TenantId>" -SubscriptionId "<SubscriptionId>" -GraphUserGroup "<GroupId (Aus Azure)>" -OrgName "<OrgName>" -HomepageUrl "<HomepageUrl>" -UsePhoto
``` -->

### Deployment vom Source Code

``` PowerShell
.\Run-DeploymentFromSource.ps1 -TenantId "<TenantId>" -SubscriptionId "<SubscriptionId>" -GraphUserGroup "<GroupId>" -OrgName "<OrgName>" -HomepageUrl "<HomepageUrl>" -UsePhoto -Recompile
```

### Berechtigungen vergeben

Um die Daten der Personen in der Organisation lesen zu können müssen nach dem Deployment noch Berechtigungen vergeben werden. Hierzu müss bei dem angelegten Service Principal [hier (Azure Active Directory | App registrations)](https://portal.azure.com/#view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/RegisteredApps) die API permissions geöffnet werden. Dort muss die Microsoft Graph Berechtigung (Application) `Directory.Read.All` vergeben werden. Um die Berechtigung zu genehmigen sind `Global Administrator` Rechte erforderlich

## Bekannte Probleme

Beim Anlegen der Azure Functions kann es zu einer Race-Condition zwischen dem zu erstellenden Storage Account und den Functions selbst kommen. Hierbei kann es dazu kommen das das erstellen einer oder beider Functions fehlschlägt. In diesem Fall einfach das Deployment-Script erneut ausführen.
