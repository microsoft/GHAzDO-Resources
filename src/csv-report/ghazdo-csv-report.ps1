<#
.SYNOPSIS
    This script generates a CSV report of Azure DevOps Advanced Security alerts for a given organization, project, and repository.
.DESCRIPTION
    This script retrieves the list of projects and repositories for a given organization, and then retrieves the list of Advanced Security alerts for each repository. 
    It filters the alerts based on severity, alert type, and state and then generates a CSV report of the filtered alerts.
.PARAMETER None
    This script does not accept any parameters.
.EXAMPLE
    .\ghazdo-csv-report.ps1
    This command generates a CSV report of Advanced Security alerts for the organization, project, and repository specified in the environment variables.
.NOTES
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
$repositoryId = ${env:BUILD_REPOSITORY_ID} #$(Build.Repository.ID) #$env:BUILD_REPOSITORY_ID= "TODO-YOUR-REPO-GUID-HERE"
$repositoryName = ${env:BUILD_REPOSITORY_NAME} #$(Build.Repository.Name) #$env:BUILD_REPOSITORY_NAME= "TODO-YOUR-REPO-NAME-HERE"
$build = ${env:BUILD_BUILDNUMBER} # $env:BUILD_BUILDNUMBER= "$(Get-Date -Format "yyyyMMdd").1"

$headers = @{ Authorization = "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$pass")))"; }

# Report Configuration
$allRepos = $true #run for all repos in the org/projects
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

            if(!$enablement.advSecEnabled)
            {
                Write-Host "##vso[debug]Advanced Security is not enabled for org:$orgName, project:$project, repo:$repositoryName($repositoryId)"
            }
            else {
                # 403 = Token has no permissions to view Advanced Security alerts
                Write-Host "##vso[task.logissue type=warning] Error getting alerts from Azure DevOps Advanced Security: ", $alerts.StatusCode, $alerts.StatusDescription, $orgName, $project, $repositoryName, $repositoryId
            }
            
        }
        $parsedAlerts = $alerts.content | ConvertFrom-Json
        Write-Host "##vso[debug]Alerts(Count: $($parsedAlerts.Count)) loaded for org:$orgName, project:$project, repo:$repositoryName($repositoryId)"
    }
    catch {
        Write-Host "##vso[task.logissue type=warning] Exception getting alerts from Azure DevOps Advanced Security:", $_.Exception.Response.StatusCode, $_.Exception.Response.RequestMessage.RequestUri
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
$reportName = "ghazdo-report-$build.csv"

if ($alertList.Count -gt 0) {
    $alertList | Format-Table -AutoSize | Out-String | Write-Host
    $alertList | Export-Csv -Path "$reportName" -NoTypeInformation -Force
    Write-Host "##vso[artifact.upload artifactname=AdvancedSecurityReport]${env:BUILD_SOURCESDIRECTORY}/$reportName"
}

Write-Host "##vso[task.complete result=Succeeded;]DONE"
exit 0
