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
$pair = ":${pass}"
$bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
$base64 = [System.Convert]::ToBase64String($bytes)
$basicAuthValue = "Basic $base64"
$headers = @{ Authorization = $basicAuthValue }
$url = "https://advsec.dev.azure.com/{0}/{1}/_apis/alert/repositories/{2}/alerts?api-version=7.2-preview.1" -f $orgName, $project, $repositoryId

$alerts = Invoke-WebRequest -Uri $url -Headers $headers -Method Get
if ($alerts.StatusCode -ne 200) {
    Write-Host "##vso[task.logissue type=error] Error getting alerts from Azure DevOps Advanced Security:", $alerts.StatusCode, $alerts.StatusDescription
    exit 1
}
$parsedAlerts = $alerts.content | ConvertFrom-Json

# Policy Threshold
$severities = @("critical", "high") #, "medium", "low"
$states = @("active")
$slaDays = 10
$alertTypes = @("code", "secret", "dependency")

[System.Collections.ArrayList]$failingAlerts = @()

$failingAlerts = foreach ($alert in $parsedAlerts.value) {
    if ($alert.severity -in $severities `
            -and $alert.state -in $states `
            -and $alert.firstSeenDate -lt (Get-Date).ToUniversalTime().AddDays(-$slaDays) `
            -and $alert.alertType -in $alertTypes) {
        @{
            "Alert Title"  = $alert.title
            "Alert Id"     = $alert.alertId
            "Alert Type"   = $alert.alertType
            "Severity"     = $alert.severity
            "Description"  = $alert.rule.description
            "First Seen"   = $alert.firstSeenDate
            "Days overdue" = [int]((Get-Date).ToUniversalTime().AddDays(-$slaDays) - ($alert.firstSeenDate)).TotalDays
            "Alert Link"   = "$($alert.repositoryUrl)/alerts/$($alert.alertId)"
        }
    }
}

if ($failingAlerts.Count -gt 0) {
    $errorText = "##vso[task.logissue type=error] Found {0} failing alerts out of SLA policy:" -f $failingAlerts.Count
    Write-Host $errorText
    foreach ($alert in $failingAlerts) {
        $alert | Format-Table -AutoSize -HideTableHeaders | Out-String | Write-Host
        Write-Host $([System.Environment]::NewLine)
    }
    exit 1
}
else {
    Write-Host "##vso[task.complete result=Succeeded;]DONE"
    exit 0
}
