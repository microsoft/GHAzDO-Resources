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
$url = "https://advsec.dev.azure.com/{0}/{1}/_apis/AdvancedSecurity/Repositories/{2}/alerts?useDatabaseProvider=true" -f $orgName, $project, $repositoryId

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
            -and $alert.firstSeen -as [DateTime] -lt (Get-Date).ToUniversalTime().AddDays(-$slaDays) `
            -and $alert.alertType -in $alertTypes) {
        @{ 
            "Alert Title"  = $alert.title
            "Alert Id"     = $alert.alertId
            "Alert Type"   = $alert.alertType
            "Severity"     = $alert.severity
            "Description"  = $alert.rule.description
            "First Seen"   = $alert.firstSeen -as [DateTime]
            "Days overdue" = [int]((Get-Date).ToUniversalTime().AddDays(-$slaDays) - ($alert.firstSeen -as [DateTime])).TotalDays
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
