<#
.SYNOPSIS
    This script generates a CSV report of Azure DevOps Advanced Security alerts for a given organization, project, and repository.
.DESCRIPTION
    This script retrieves the list of projects and repositories for a given organization, and then retrieves the list of Advanced Security alerts for each repository.
    It filters the alerts based on severity, alert type, and state and then generates a CSV report of the filtered alerts.
    The script contains an SLA based on number of days since the alert was first seen. For critical it is 7 days, high is 30 days, medium is 90 days, and low is 180 days.
.PARAMETER pat
    The Azure DevOps Personal Access Token (PAT) with Advanced Security=READ, Code=READ (to look up repositories for scope="organization" or scope="project"), and Project=READ (to look up projects in an organization for scope="organization") permissions.
    If not specified, the script will require the MAPPED_ADO_PAT environment variable.
.PARAMETER orgUri
    The URL of the Azure DevOps organization.
    If not specified, the script will use the SYSTEM_COLLECTIONURI environment variable. This is also accessible via $(System.CollectionUri) in Azure DevOps.
.PARAMETER project
    The name of the Azure DevOps project.
    If not specified, the script will use the SYSTEM_TEAMPROJECT environment variable. This is also accessible via $(System.TeamProject) in Azure DevOps.
    Only required if allRepos is set to $false.
.PARAMETER $repository
    The name of the Azure DevOps repository.
    If not specified, the script will use the BUILD_REPOSITORY_NAME environment variable. This is also accessible via $(Build.Repository.Name) in Azure DevOps.
    Only required if `scope` is set to "repository".
.PARAMETER reportName
    The name of the csv report.
    If not specified, the script will use the BUILD_BUILDNUMBER environment variable in the format "ghazdo-report-{BUILD_BUILDNUMBER}.csv".  This is also accessible via $(Build.BuildNumber) in Azure DevOps.
.PARAMETER scope
    The scope of the report. Valid values are "organization", "project", or "repository".
    If set to "organization", the script will run for all repositories in the organization.
    If set to "project", the script will run for all repositories in the specified project.
    If set to "repository", the script will run for the specified repository.
    If not specified, the script will default to "organization".
.EXAMPLE
    .\ghazdo-csv-report.ps1 `
    -pat "myPersonalAccessToken" `
    -orgUri "https://dev.azure.com/myOrganization" `
    -project "myProject" `
    -repository "myrepository" `
    -reportName "ghazdo-report-$(Get-Date -Format "yyyyMMdd").1.csv"
.NOTES
    The maxium number of alerts returned by the Advanced Security API is set to 10000 per repo - API client rate limiting may need to be considered in extreme cases.
    This script requires the `pat` parameter to be set or the `MAPPED_ADO_PAT` environment variable to be set.
    This script requires PS7 or higher.
    For HTTP payload size verbose debugging output, use $VerbosePreference = "Continue"
#>

param(
    [string]$pat = ${env:MAPPED_ADO_PAT},
    [string]$orgUri = ${env:SYSTEM_COLLECTIONURI},
    [string]$project = ${env:SYSTEM_TEAMPROJECT},
    [string]$repository = ${env:BUILD_REPOSITORY_NAME},
    [string]$reportName = "ghazdo-report-${env:BUILD_BUILDNUMBER}.csv",
    [ValidateSet("organization", "project", "repository")]
    [string]$scope = "organization"
)

if ([string]::IsNullOrEmpty($pat)) {
    throw "The `pat` parameter must be set or the `MAPPED_ADO_PAT` environment variable must be set."
}

$orgName = $orgUri -replace "^https://dev.azure.com/|/$"
$headers = @{ Authorization = "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(($pat.Contains(":") ? $pat : ":$pat"))))" }
$isAzDO = $env:TF_BUILD -eq "True"

# Report Configuration
$severities = @("critical", "high", "medium", "low", "error", "warning", "note")
$states = @("active", "fixed", "dismissed")
$alertTypes = @("code", "secret", "dependency")
$severityDays = @{
    "critical" = 7
    "high"     = 30
    "medium"   = 90
    "low"      = 180
    #Quality Severities and SARIF integrations
    "error"    = 30
    "warning"  = 90
    "note"     = 180
}
$maxAlertsPerRepo = 10000 #default is 100 - rate limiting: https://learn.microsoft.com/en-us/azure/devops/integrate/concepts/rate-limits?view=azure-devops#api-client-experience

#build the list of repos to scan
$scans = @()
if ($scope -in @("organization", "project")) {
    $projects = if ($scope -eq "organization") {
        # get list of projects in the Organization - https://learn.microsoft.com/en-us/rest/api/azure/devops/core/projects/get
        $url = "https://dev.azure.com/{0}/_apis/projects" -f $orgName
        $projectsResponse = Invoke-WebRequest -Uri $url -Headers $headers -Method Get -SkipHttpErrorCheck
        if ($projectsResponse.StatusCode -ne 200) {
            Write-Host "$($isAzdo ? '##vso[task.logissue type=warning]' : '')❌ - Error $($projectsResponse.StatusCode) $($projectsResponse.StatusDescription) Failed to retrieve projects for org: $orgName with $url"
            Write-Host "$($isAzdo ? '##[debug]' : '')⚠️ - Response for projects $url : $($projectsResponse.Content)"
        }
        ($projectsResponse.Content | ConvertFrom-Json).value
    }
    elseif ($scope -eq "project") {
        @(@{ name = $project })
    }

    foreach ($proj in $projects) {
        # get list of repos in the project - https://learn.microsoft.com/en-us/rest/api/azure/devops/git/repositories/get
        $url = "https://dev.azure.com/{0}/{1}/_apis/git/repositories" -f $orgName, $proj.name
        $reposResponse = Invoke-WebRequest -Uri $url -Headers $headers -Method Get -SkipHttpErrorCheck
        if ($reposResponse.StatusCode -ne 200) {
            Write-Host "$($isAzdo ? '##vso[task.logissue type=warning]' : '')❌ - Error $($reposResponse.StatusCode) $($reposResponse.StatusDescription) Failed to retrieve repositories for org: $orgName and project: $($proj.name) with $url"
            Write-Host "$($isAzdo ? '##[debug]' : '')⚠️ - Response for repositories $url : $($reposResponse.Content)"
            continue;
        }
        $repos = ($reposResponse.Content | ConvertFrom-Json).value
        # Add the org name, project name, and repo name to the hashtable for each repository
        foreach ($repo in $repos) {
            $scans += @{
                OrgName     = $orgName
                ProjectName = $proj.name
                RepoName    = $repo.name
            }
        }
    }
}
elseif ($scope -eq "repository") {
    $scans += @{
        OrgName     = $orgName
        ProjectName = $project
        RepoName    = $repository
    }
}

#loop through repo alert list - https://learn.microsoft.com/en-us/rest/api/azure/devops/advancedsecurity/alerts/list
[System.Collections.ArrayList]$alertList = @()
foreach ($scan in $scans) {
    $project = $scan.ProjectName
    $repository = $scan.RepoName
    $alertUri = $orgUri + ('/' * ($orgUri[-1] -ne '/')) + [uri]::EscapeUriString($project + '/_git/' + $repository + '/alerts')
    $alerts = $null
    $parsedAlerts = $null
    $url = "https://advsec.dev.azure.com/{0}/{1}/_apis/alert/repositories/{2}/alerts?top={3}" -f $orgName, $project, $repository, $maxAlertsPerRepo
    # Send out warnings for any org/project/repo that we cannot access alerts for!
    try {
        $alerts = Invoke-WebRequest -Uri $url -Headers $headers -Method Get -SkipHttpErrorCheck
        if ($alerts.StatusCode -ne 200) {
            # Check to see if advanced security is enabled for the repo - https://learn.microsoft.com/en-us/rest/api/azure/devops/advancedsecurity/repo-enablement/get?view=azure-devops-rest-7.2
            $enablementurl = "https://advsec.dev.azure.com/{0}/{1}/_apis/management/repositories/{2}/enablement" -f $orgName, $project, $repository
            $repoEnablement = Invoke-WebRequest -Uri $enablementurl -Headers $headers -Method Get -SkipHttpErrorCheck
            Write-Host "$($isAzdo ? '##[debug]' : '')⚠️ - Unable to access $alertUri ($($alerts.StatusCode) $($alerts.StatusDescription)) - Response from enablement endpoint: $enablementurl ($($repoEnablement.StatusCode) $($repoEnablement.StatusDescription))"
            $enablement = $repoEnablement.content | ConvertFrom-Json

            if (!$enablement.advSecEnabled) {
                Write-Host "$($isAzdo ? '##[debug]' : '')⚠️ - Advanced Security is not enabled for $alertUri"
                continue;
            }
            elseif ($alerts.StatusCode -eq 404) {
                # 404 = Repo has no source code
                Write-Host "$($isAzdo ? '##[debug]' : '')⚠️ - Repo is empty for $alertUri"
                continue;
            }
            else {
                # 403 = Token has no permissions to view Advanced Security alerts
                Write-Host "$($isAzdo ? '##vso[task.logissue type=warning]' : '')❌ - Error $($alerts.StatusCode) $($alerts.StatusDescription) getting alerts from Azure DevOps Advanced Security for $alertUri"
                continue;
            }
        }
        $parsedAlerts = $alerts.content | ConvertFrom-Json
        if ($parsedAlerts.Count -eq $maxAlertsPerRepo) {
            Write-Host "$($isAzdo ? '##vso[task.logissue type=warning]' : '')ℹ️ - Rate Limiter Prevention - Maximum amount of $maxAlertsPerRepo alerts has been reached for $alertUri. Consider raising the `maxAlertsPerRepo` variable in the script."
        }
        Write-Host "$($isAzdo ? '##[debug]' : '')✅ - $($parsedAlerts.Count) Alerts (Dependency: $($parsedAlerts.value.Where({$_.alertType -eq "dependency"}).Count) / Code: $($parsedAlerts.value.Where({$_.alertType -eq "code"}).Count) / Secrets: $($parsedAlerts.value.Where({$_.alertType -eq "secret"}).Count) ) loaded for $alertUri"
    }
    catch {
        Write-Host "$($isAzdo ? '##vso[task.logissue type=warning]' : '')⛔ - Unhandled Exception getting alerts from Azure DevOps Advanced Security:", $_.Exception.Message, $_.Exception.Response.StatusCode, $_.Exception.Response.RequestMessage.RequestUri
        continue;
    }

    $alertList += foreach ($alert in $parsedAlerts.value) {
        # -and $alert.firstSeen -as [DateTime] -lt (Get-Date).ToUniversalTime().AddDays(-$slaDays) `
        if ($alert.severity -in $severities `
                -and $alert.state -in $states `
                -and $alert.alertType -in $alertTypes) {
            # use a custom object so we can control sorting
            [pscustomobject]@{
                "Alert Id"          = $alert.alertId
                "Alert State"       = $alert.state
                "Alert Title"       = $alert.title
                "Alert Type"        = $alert.alertType
                "Tool"              = ($alert.tools | Select-Object -ExpandProperty name) -join ","
                "Rule Id"           = ($alert.tools | ForEach-Object { $_.rules } | Select-Object -ExpandProperty opaqueId) -join ","
                "Rule Name"         = ($alert.tools | ForEach-Object { $_.rules } | Select-Object -ExpandProperty friendlyName) -join ","
                "Rule Description"  = ($alert.tools | ForEach-Object { $_.rules } | Select-Object -ExpandProperty description) -join ","
                "Tags"              = ($alert.tools | ForEach-Object { $_.rules } | Select-Object -ExpandProperty tags) -join ","
                "Severity"          = $alert.severity
                "First Seen"        = $null -eq $alert.firstSeenDate ? "" : ($alert.lastSeenDate).ToString("yyyy-MM-ddTHH:mm:ssZ")
                "Last Seen"         = $null -eq $alert.lastSeenDate ? "" : ($alert.lastSeenDate).ToString("yyyy-MM-ddTHH:mm:ssZ")
                "Fixed On"          = $null -eq $alert.fixedDate ? "" : ($alert.fixedDate).ToString("yyyy-MM-ddTHH:mm:ssZ")
                "Dismissed On"      = $null -eq $alert.dismissal.requestedOn ? "" : ($alert.dismissal.requestedOn).ToString("yyyy-MM-ddTHH:mm:ssZ")
                "Dismissal Type"    = $alert.dismissal.dismissalType
                "Dismissal Message" = $alert.dismissal.message
                "SLA Days"          = $severityDays[$alert.severity]
                "Days overdue"      = $alert.state -ne "active" ? 0 : [Math]::Max([int]((Get-Date).ToUniversalTime().AddDays(-$severityDays[$alert.severity]) - ($alert.firstSeenDate)).TotalDays, 0)
                "Alert Link"        = $null -eq $alert.gitRef ? "$($alert.repositoryUrl)/alerts/$($alert.alertId)" : "$($alert.repositoryUrl)/alerts/$($alert.alertId)?branch=$($alert.gitRef)"
                "Organization"      = $orgName
                "Project"           = $project
                "Repository"        = $repository
                "Ref"               = $alert.gitRef
                "Ecosystem"         = if ($alert.logicalLocations) { ($alert.logicalLocations[0].fullyQualifiedName -split ' ')[0] } else { $null }
                "Dependency Type"   = if ($alert.logicalLocations) { $alert.logicalLocations.Count -eq 2 -and $alert.logicalLocations[0].fullyQualifiedName -eq $alert.logicalLocations[1].fullyQualifiedName ? "Direct" : "Transitive" } else { $null }
                "Location Paths"    = ($alert | ForEach-Object { $_.physicalLocations | ForEach-Object { "$($_.filePath)$($_.region.lineStart ? ':' + $_.region.lineStart : '')$($_.versionControl.commitHash ? ' @ ' + $_.versionControl.commitHash.Substring(0, 8) : '')" } }) -join ","
                "Logical Paths"     = if ($alert.logicalLocations.Count -eq 2 -and $alert.logicalLocations[0].fullyQualifiedName -eq $alert.logicalLocations[1].fullyQualifiedName ) { "$(($alert.logicalLocations[0].fullyQualifiedName).Split(' ', 2)[1])" } else { ($alert | ForEach-Object { $_.logicalLocations | ForEach-Object { "$(if ($_.fullyQualifiedName) {($_.fullyQualifiedName).Split(' ', 2)[1]} else { $null })$($_.kind -match "rootDependency" ? '(root)' : '')" } }) -join "," }
            }
        }
    }
}

if ($alertList.Count -gt 1) {
    $alertList = $alertList | Sort-Object -Property "Alert Id"
}

if ($alertList.Count -gt 0) {
    $reportName = [regex]::Replace($reportName, '[^\w\d.-]', '')
    $reportPath = [System.IO.Path]::Combine($isAzDO ? ${env:BUILD_ARTIFACTSTAGINGDIRECTORY} : $pwd, $reportName)
    #$alertList | Format-Table -AutoSize | Out-String | Write-Host

    $sanitizedAlertList = $alertList | ForEach-Object {
        $sanitizedAlert = $_.PSObject.Copy()
        foreach ($property in $sanitizedAlert.PSObject.Properties) {
            if ($property.Value -is [string] -and $property.Value -match '^[=+\-@]') {
                $property.Value = "'$($property.Value)"
            }
        }
        $sanitizedAlert
    }
    $sanitizedAlertList | Export-Csv -Path "$reportPath" -NoTypeInformation -Force

    if ($isAzdo) {
        Write-Host "##vso[artifact.upload artifactname=AdvancedSecurityReport]$reportPath"
    }
    else {
        Write-Host "📄 - Report generated at $reportPath"
    }
}
else {
    Write-Host "🤷 - No alerts found for at the scope:$scope ( org: $orgName$( $scope -in @('project','repository') ? ', project: ' + $project : '' )$( $scope -in @('repository') ? ', repository: ' + $repository : '' ))"
}

if ($isAzdo) {
    Write-Host "##vso[task.complete result=Succeeded;]DONE"
}
exit 0
