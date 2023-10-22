# This script is used as part of our PR gating strategy. It takes advantage of the GHAzDO REST API to check for CodeQL issues a PR source and target branch. 
# If there are new issues in the PR source branch, the script will fail and block the PR merge. 
$pass = ${env:MAPPED_ADO_PAT}
$orgUri = ${env:SYSTEM_COLLECTIONURI}
$orgName = $orgUri -replace "^https://dev.azure.com/|/$"
$project = ${env:SYSTEM_TEAMPROJECT} 
$mainBranch = ${env:SYSTEM_PULLREQUEST_TARGETBRANCH}
$prBranch = ${env:BUILD_SOURCEBRANCH}
$pair = ":${pass}"
$bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
$base64 = [System.Convert]::ToBase64String($bytes)
$basicAuthValue = "Basic $base64"
$headers = @{ Authorization = $basicAuthValue }

$urlMain = "https://advsec.dev.azure.com/{0}/{1}/_apis/Alert/repositories/{1}/Alerts?top=5000&orderBy=lastSeen&criteria.alertType=3&criteria.ref={2}&criteria.states=1" -f $orgName, $project, $mainBranch
$urlPR =   "https://advsec.dev.azure.com/{0}/{1}/_apis/Alert/repositories/{1}/Alerts?top=5000&orderBy=lastSeen&criteria.alertType=3&criteria.ref={2}&criteria.states=1" -f $orgName, $project, $prBranch

Write-Host "Will check to see if there are any new CodeQL issues in this PR branch" 

if (${env:BUILD_REASON} -ne 'PullRequest'){
   Write-Host "This is not a PR into main so all is ok"
   exit 0
}

# Get the alerts on the main branch (all without filter) and the PR branch (only currently open) 
$alertsMain = Invoke-WebRequest -Uri $urlMain -Headers $headers -Method Get
$alertsPR = Invoke-WebRequest -Uri $urlPR -Headers $headers -Method Get

if ($alertsMain.StatusCode -ne 200){
   Write-Host "##vso[task.logissue type=error] Error getting alerts from Azure DevOps Advanced Security Main:", $alertsMain.StatusCode, $alertsMain.StatusDescription
   exit 1
}

if ($alertsPR.StatusCode -ne 200){
   Write-Host "##vso[task.logissue type=error] Error getting alerts from Azure DevOps Advanced Security PR:", $alertsPR.StatusCode, $alertsPR.StatusDescription
   exit 1
}

$jsonMain = $alertsMain.Content | ConvertFrom-Json
$jsonPR = $alertsPR.Content | ConvertFrom-Json 

# Extract alert ids from the list of alerts on main branch, the PR branch. 
$mainAlertIds = $jsonMain.value | Select-Object -ExpandProperty alertId
$prAlertIds = $jsonPR.value | Select-Object -ExpandProperty alertId

# Check for alert ids that are reported in the PR branch but not the main branch
$newAlertIds = Compare-Object $prAlertIds $mainAlertIds -PassThru | Where-Object { $_.SideIndicator -eq '<=' }

# Are there any new alert ids in the PR branch?
if($newAlertIds.length -gt 0) {
    Write-Host "##[error] There are more alerts in the PR source branch $($prBranch), compared to main:"

    # Loop over the objects in the prAlerts JSON object, log an error per new alert
    foreach ($prAlert in $jsonPR.value) {
        if ($newAlertIds -contains $prAlert.alertId) {
            # This is a new Alert for this PR. Log and report it. 
            Write-Host  ""
            Write-Host  "##vso[task.logissue type=error;sourcepath=$($prAlert.physicalLocations.filePath);linenumber=$($prAlert.physicalLocations.region.lineStart);columnnumber=$($prAlert.physicalLocations.region.columnStart)] New CodeQL issue detected #$($prAlert.alertId) : $($prAlert.title)."
            Write-Host  "##[error] Fix or dismiss this new alert in the Advanced Security UI for pr branch $($prBranch)."
            $urlAlert = "https://dev.azure.com/{0}/_git/{1}/alerts/{2}?branch={3}" -f $orgName, $project, $prAlert.alertId, $prBranch
            Write-Host  "##[error] Details for this new alert:  $($urlAlert)"
        }
    }
    Write-Host  ""
    Write-Host "##[error] Please review these Code Scanning alerts for the $($prBranch) branch using the regular Advanced Security UI" 
    Write-Host "##[error] Dissmiss or fix the issues listed and try re-queue the CIVerify task."
    exit 1
} else {
    Write-Output "No new CodeQL alerts - all is fine"
    exit 0
}