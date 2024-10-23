<#
.SYNOPSIS
    Gating script for Azure DevOps Advanced Security.
.DESCRIPTION
    This script checks for GHAzDO security alerts for a specific repository and fails the build if any alerts are found that are outside of the specified SLA policy.
.EXAMPLE
    $env:MAPPED_ADO_PAT = "TODO-ADVSEC-SCOPED-PAT-HERE"
    gating.ps1
.NOTES
    This script is intended to be used as a build pipeline task in Azure DevOps.

    This script requires the following environment variables to be set:
    - MAPPED_ADO_PAT: The Azure DevOps Personal Access Token (PAT) with Advanced Security read permissions.

    This script utilizes the following predefined environment variables:
    - SYSTEM_COLLECTIONURI: The URL of the Azure DevOps organization.
    - SYSTEM_TEAMPROJECT: The name of the Azure DevOps project.
    - BUILD_REPOSITORY_ID: The ID of the Azure DevOps repository.
    - BUILD_REPOSITORY_NAME: The name of the Azure DevOps repository.
    - BUILD_BUILDNUMBER: The build number of the Azure DevOps build.
#>

$pass = ${env:MAPPED_ADO_PAT} #$env:MAPPED_ADO_PAT = "TODO-ADVSEC-SCOPED-PAT-HERE"
$orgUri = ${env:SYSTEM_COLLECTIONURI} #$(System.CollectionUri) #$env:SYSTEM_COLLECTIONURI = "https://dev.azure.com/TODO-YOUR-ORG-HERE/"
$orgName = $orgUri -replace "^https://dev.azure.com/|/$"
$project = ${env:SYSTEM_TEAMPROJECT} #$(System.TeamProject) #$env:SYSTEM_TEAMPROJECT = "TODO-YOUR-PROJECT-NAME-HERE"
$repositoryId = ${env:BUILD_REPOSITORY_ID} #$(Build.Repository.ID) #env:BUILD_REPOSITORY_ID= "TODO-YOUR-REPO-GUID-HERE"

$headers = @{ Authorization = "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(($pass.Contains(":") ? $pass : ":$pass"))))" }
$maxAlertsPerRepo = 10000 #default is 100 - rate limiting: https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/rate-limits?view=azure-devops#api-client-experience
# Advanced Security - Alerts - List https://learn.microsoft.com/en-us/rest/api/azure/devops/advancedsecurity/alerts/list
$url = "https://advsec.dev.azure.com/{0}/{1}/_apis/alert/repositories/{2}/alerts?top={3}" -f $orgName, $project, $repositoryId, $maxAlertsPerRepo


$alerts = Invoke-WebRequest -Uri $url -Headers $headers -Method Get
if ($alerts.StatusCode -ne 200) {
    Write-Host "##vso[task.logissue type=error] Error getting alerts from Azure DevOps Advanced Security:", $alerts.StatusCode, $alerts.StatusDescription
    exit 1
}
$parsedAlerts = $alerts.content | ConvertFrom-Json

# Policy Threshold
$severities = @("critical", "high") #, "medium", "low", "error", "warning", "note"
$states = @("active") #"fixed", "dismissed")
$alertTypes = @("code", "secret", "dependency")
$severityDays = @{
    # Security Severties (active only)
    "critical" = 7
    "high"     = 30
    "medium"   = 90
    "low"      = 180
    #Quality Severities and SARIF integrations (active only)
    "error"    = 30
    "warning"  = 90
    "note"     = 180
}

[System.Collections.ArrayList]$failingAlerts = @()

$failingAlerts = foreach ($alert in $parsedAlerts.value) {
    if ($alert.severity -in $severities `
            -and $alert.state -in $states `
            -and ($alert.state -eq "active" -and $alert.firstSeenDate -lt (Get-Date).ToUniversalTime().AddDays(-$severityDays[$alert.severity]) ) `
            -and $alert.alertType -in $alertTypes) {
        @{
            "Alert Title"  = $alert.title
            "Alert Id"     = $alert.alertId
            "Alert Type"   = "$($alert.alertType) ($(($alert.tools | Select-Object -ExpandProperty name) -join ","))"
            "Severity"     = $alert.severity
            "Description"  = ($alert.tools | ForEach-Object { $_.rules } | Select-Object -ExpandProperty description) -join ","
            "First Seen"   = $alert.firstSeenDate
            "Days overdue" = [int]((Get-Date).ToUniversalTime().AddDays(-$severityDays[$alert.severity]) - ($alert.firstSeenDate)).TotalDays
            "Alert Link"   = "$($alert.repositoryUrl)/alerts/$($alert.alertId)"
        }
    }
}

if ($failingAlerts.Count -gt 0) {
    $errorText = "##vso[task.logissue type=error] Found {0} failing alerts out of SLA policy:" -f $failingAlerts.Count
    Write-Host $errorText
    foreach ($alert in $failingAlerts) {
        $alert | Format-Table -AutoSize -HideTableHeaders | Out-String -Width 512 | Write-Host
        Write-Host $([System.Environment]::NewLine)
    }
    exit 1
}
else {
    Write-Host "##vso[task.complete result=Succeeded;]DONE"
    exit 0
}
