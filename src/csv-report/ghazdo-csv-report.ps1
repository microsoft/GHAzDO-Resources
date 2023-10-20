<#
.SYNOPSIS
    This script generates a CSV report of Azure DevOps Advanced Security alerts for a given organization, project, and repository.
.DESCRIPTION
    This script retrieves the list of projects and repositories for a given organization, and then retrieves the list of Advanced Security alerts for each repository.
    It filters the alerts based on severity, alert type, and state and then generates a CSV report of the filtered alerts.
.PARAMETER pass
    The Azure DevOps Personal Access Token (PAT) with Advanced Security read permissions.
    If not specified, the script will prompt the user to enter the PAT or use the MAPPED_ADO_PAT environment variable.
.PARAMETER orgUri
    The URL of the Azure DevOps organization.
    If not specified, the script will use the SYSTEM_COLLECTIONURI environment variable.
.PARAMETER project
    The name of the Azure DevOps project.
    If not specified, the script will use the SYSTEM_TEAMPROJECT environment variable.
    Only required if allRepos is set to $false.
.PARAMETER repositoryId
    The ID of the Azure DevOps repository.
    If not specified, the script will use the BUILD_REPOSITORY_ID environment variable.
    Only required if allRepos is set to $false.
.PARAMETER repositoryName
    The name of the Azure DevOps repository.
    If not specified, the script will use the BUILD_REPOSITORY_NAME environment variable.
    Only required if allRepos is set to $false.
.PARAMETER reportName
    The name of the csv report.
    If not specified, the script will use the BUILD_BUILDNUMBER environment variable or generate a default value.
.PARAMETER allRepos
    A boolean value that indicates whether to run the script for all repositories in the organization and project.
    If set to $true, the script will run for all repositories. If set to $false, the script use the specified Organization/Project/Repository.
    If not specified, the script will default to $true.
.EXAMPLE
    .\ghazdo-csv-report.ps1 `
    -pass "myPersonalAccessToken" `
    -orgUri "https://dev.azure.com/myOrganization" `
    -project "myProject" `
    -repositoryId "myRepositoryGUID" `
    -repositoryName "myRepositoryName" `
    -reportName "ghazdo-report-$(Get-Date -Format "yyyyMMdd").1.csv"
.NOTES
    This script requires the following environment variables to be set or passed in:
    - MAPPED_ADO_PAT: The Azure DevOps Personal Access Token (PAT) with Advanced Security read permissions.
#>

param(
    [string]$pass = ${env:MAPPED_ADO_PAT},
    #ADO: $(System.CollectionUri)
    [string]$orgUri = ${env:SYSTEM_COLLECTIONURI},
    #ADO: $(System.TeamProject)
    [string]$project = ${env:SYSTEM_TEAMPROJECT},
    #ADO: $(Build.Repository.ID)
    [string]$repositoryId = ${env:BUILD_REPOSITORY_ID},
    #ADO: $(Build.Repository.Name)
    [string]$repositoryName = ${env:BUILD_REPOSITORY_NAME},
    #ADO: $(Build.BuildNumber)
    [string]$reportName = "ghazdo-report-${env:BUILD_BUILDNUMBER}.csv",
    [bool]$allRepos = $true
)

$orgName = $orgUri -replace "^https://dev.azure.com/|/$"
$headers = @{ Authorization = "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$pass")))"; }
$isAzDO = $env:TF_BUILD -eq "True"

# Report Configuration
$severities = @("critical", "high", "medium", "low")
$states = @("active", "fixed", "dismissed")
$alertTypes = @("code", "secret", "dependency")
$severityDays = @{
    "critical" = 7
    "high"     = 30
    "medium"   = 90
    "low"      = 180
}

# get list of projects in the Organization
$url = "https://dev.azure.com/{0}/_apis/projects" -f $orgName
$projectsResponse = Invoke-WebRequest -Uri $url -Headers $headers -Method Get
$projects = ($projectsResponse.Content | ConvertFrom-Json).value

# create a hashtable to hold org name, project name and repo id
$scans = @()


if ($allRepos) {
    foreach ($proj in $projects) {
        $url = "https://dev.azure.com/{0}/{1}/_apis/git/repositories" -f $orgName, $proj.name
        $reposResponse = Invoke-WebRequest -Uri $url -Headers $headers -Method Get
        $repos = ($reposResponse.Content | ConvertFrom-Json).value
        #$repos.value | Where-Object { $_.id -eq $repositoryId } | Select-Object -ExpandProperty id
        # Add the org name, project name, and repo ID to the hashtable for each repository
        foreach ($repo in $repos) {
            $scans += @{
                OrgName     = $orgName
                ProjectName = $proj.name
                RepoName    = $repo.name
                RepoId      = $repo.id
            }
        }
    }
}
else {
    $scans += @{
        OrgName     = $orgName
        ProjectName = $project
        RepoName    = $repositoryName
        RepoId      = $repositoryId
    }
}

#loop through repo alert list - https://learn.microsoft.com/en-us/rest/api/azure/devops/alert/alerts/list
[System.Collections.ArrayList]$alertList = @()
foreach ($scan in $scans) {
    $project = $scan.ProjectName
    $repositoryName = $scan.RepoName
    $repositoryId = $scan.RepoId
    $alerts = $null
    $parsedAlerts = $null
    $url = "https://advsec.dev.azure.com/{0}/{1}/_apis/alert/repositories/{2}/alerts" -f $orgName, $project, $repositoryId
    # Send out warnings for any org/project/repo that we cannot access alerts for!
    try {
        $alerts = Invoke-WebRequest -Uri $url -Headers $headers -Method Get -SkipHttpErrorCheck
        if ($alerts.StatusCode -ne 200) {
            # Check to see if advanced security is enabled for the repo - https://learn.microsoft.com/en-us/rest/api/azure/devops/management/repo-enablement/get?view=azure-devops-rest-7.2
            $enablementurl = "https://advsec.dev.azure.com/{0}/{1}/_apis/management/repositories/{2}/enablement" -f $orgName, $project, $repositoryId
            $repoEnablement = Invoke-WebRequest -Uri $enablementurl -Headers $headers -Method Get -SkipHttpErrorCheck
            $enablement = $repoEnablement.content | ConvertFrom-Json

            if (!$enablement.advSecEnabled) {
                Write-Host "$($isAzdo ? '##vso[debug]' : '')Advanced Security is not enabled for org:$orgName, project:$project, repo:$repositoryName($repositoryId)"
            }
            else {
                # 403 = Token has no permissions to view Advanced Security alerts
                Write-Host "$($isAzdo ? '##vso[task.logissue type=warning]' : '')Error getting alerts from Azure DevOps Advanced Security: ", $alerts.StatusCode, $alerts.StatusDescription, $orgName, $project, $repositoryName, $repositoryId
            }
        }
        $parsedAlerts = $alerts.content | ConvertFrom-Json
        Write-Host "$($isAzdo ? '##vso[debug]' : '')Alerts(Count: $($parsedAlerts.Count)) loaded for org:$orgName, project:$project, repo:$repositoryName($repositoryId)"
    }
    catch {
        Write-Host "$($isAzdo ? '##vso[task.logissue type=warning]' : '')Exception getting alerts from Azure DevOps Advanced Security:", $_.Exception.Response.StatusCode, $_.Exception.Response.RequestMessage.RequestUri
    }

    $alertList += foreach ($alert in $parsedAlerts.value) {
        # -and $alert.firstSeen -as [DateTime] -lt (Get-Date).ToUniversalTime().AddDays(-$slaDays) `
        if ($alert.severity -in $severities `
                -and $alert.state -in $states `
                -and $alert.alertType -in $alertTypes) {
            # use a custom object so we can control sorting
            [pscustomobject]@{
                "Alert Id"         = $alert.alertId
                "Alert State"      = $alert.state
                "Alert Title"      = $alert.title
                "Alert Type"       = $alert.alertType
                "Rule Id"          = ($alert.tools | ForEach-Object { $_.rules } | Select-Object -ExpandProperty opaqueId) -join ","
                "Rule Name"        = ($alert.tools | ForEach-Object { $_.rules } | Select-Object -ExpandProperty friendlyName) -join ","
                "Rule Description" = ($alert.tools | ForEach-Object { $_.rules } | Select-Object -ExpandProperty description) -join ","
                "Tags"             = ($alert.tools | ForEach-Object { $_.rules } | Select-Object -ExpandProperty tags) -join ","
                "Severity"         = $alert.severity
                "First Seen"       = $null -eq $alert.firstSeenDate ? "" : ($alert.lastSeenDate).ToString("yyyy-MM-ddTHH:mm:ssZ")
                "Last Seen"        = $null -eq $alert.lastSeenDate ? "" : ($alert.lastSeenDate).ToString("yyyy-MM-ddTHH:mm:ssZ")
                "Fixed On"         = $null -eq $alert.fixedDate ? "" : ($alert.fixedDate).ToString("yyyy-MM-ddTHH:mm:ssZ")
                "Dismissed On"     = $null -eq $alert.dismissal.requestedOn ? "" : ($alert.dismissal.requestedOn).ToString("yyyy-MM-ddTHH:mm:ssZ")
                "Dismissal Type"   = $alert.dismissal.dismissalType
                "SLA Days"         = $severityDays[$alert.severity]
                "Days overdue"     = $alert.state -ne "active" ? 0 : [Math]::Max([int]((Get-Date).ToUniversalTime().AddDays(-$severityDays[$alert.severity]) - ($alert.firstSeenDate)).TotalDays, 0)
                "Alert Link"       = "$($alert.repositoryUrl)/alerts/$($alert.alertId)"
                "Organization"     = $orgName
                "Project"          = $project
                "Repository"       = $repositoryName
                "Ref"              = $alert.gitRef
                "Ecosystem"        = if ($alert.logicalLocations) { ($alert.logicalLocations[0].fullyQualifiedName -split ' ')[0] } else { $null }
                "Location Paths"   = ($alert | ForEach-Object { $_.physicalLocations | ForEach-Object { "$($_.filePath)$($_.region.lineStart ? ':' + $_.region.lineStart : '')$($_.versionControl.commitHash ? ' @ ' + $_.versionControl.commitHash.Substring(0, 8) : '')" } }) -join ","
                "Logical Paths"    = if ($alert.logicalLocations.Count -eq 2 -and $alert.logicalLocations[0].fullyQualifiedName -eq $alert.logicalLocations[1].fullyQualifiedName ) { "$(($alert.logicalLocations[0].fullyQualifiedName).Split(' ', 2)[1])" } else { ($alert | ForEach-Object { $_.logicalLocations | ForEach-Object { "$(if ($_.fullyQualifiedName) {($_.fullyQualifiedName).Split(' ', 2)[1]} else { $null })$($_.kind -match "rootDependency" ? '(root)' : '')" } }) -join "," }
            }
        }
    }
}

if ($alertList.Count -gt 1) {
    $alertList = $alertList | Sort-Object -Property "Alert Id"
}

if ($alertList.Count -gt 0) {
    $alertList | Format-Table -AutoSize | Out-String | Write-Host
    $alertList | Export-Csv -Path "$([regex]::Replace($reportName, '[^\w\d.-]', ''))" -NoTypeInformation -Force
    if ($isAzdo) {
        Write-Host "##vso[artifact.upload artifactname=AdvancedSecurityReport]${env:BUILD_SOURCESDIRECTORY}/$reportName"
    }
}

if ($isAzdo) {
    Write-Host "##vso[task.complete result=Succeeded;]DONE"
}
exit 0
