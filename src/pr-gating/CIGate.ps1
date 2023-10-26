# This script is used as part of our PR gating strategy. It takes advantage of the GHAzDO REST API to check for CodeQL issues a PR source and target branch. 
# If there are new issues in the source branch, the script will report on that and fail with error code 1. 
$pass = ${env:MAPPED_ADO_PAT}
$orgUri = ${env:SYSTEM_COLLECTIONURI}
$orgName = $orgUri -replace "^https://dev.azure.com/|/$"
$project = ${env:SYSTEM_TEAMPROJECT} 
$repositoryId = ${env:BUILD_REPOSITORY_ID} 
$prTargetBranch = ${env:SYSTEM_PULLREQUEST_TARGETBRANCH}
$prSourceBranch = ${env:BUILD_SOURCEBRANCH}
$pair = ":${pass}"
$bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
$base64 = [System.Convert]::ToBase64String($bytes)
$basicAuthValue = "Basic $base64"
$headers = @{ Authorization = $basicAuthValue }

$alertType = "" # code,dependency,secret - If provided, only return alerts of this type. Otherwise, return alerts of all types.

$urlTargetAlerts = "https://advsec.dev.azure.com/{0}/{1}/_apis/Alert/Repositories/{2}/Alerts?top=5000&orderBy=lastSeen&criteria.alertType={4}&criteria.branchName={3}&criteria.onlyDefaultBranchAlerts=true&useDatabaseProvider=true" -f $orgName, $project, $repositoryId, $prTargetBranch, $alertType
$urlSourceAlerts = "https://advsec.dev.azure.com/{0}/{1}/_apis/Alert/repositories/{2}/Alerts?top=5000&orderBy=lastSeen&criteria.alertType={4}&criteria.ref={3}&criteria.states=1" -f $orgName, $project, $repositoryId, $prSourceBranch, $alertType

Write-Host "Will check to see if there are any new $alertType alerts in this PR branch" 
Write-Host "PR source : $($prSourceBranch). PR target: $($prTargetBranch)"

if (${env:BUILD_REASON} -ne 'PullRequest'){
   Write-Host "This is not a PR into main so all is ok"
   exit 0
}

# Get the alerts on the pr target branch (all without filter) and the PR source branch (only currently open)
$alertsPRTarget = Invoke-WebRequest -Uri $urlTargetAlerts -Headers $headers -Method Get
$alertsPRSource = Invoke-WebRequest -Uri $urlSourceAlerts -Headers $headers -Method Get

if ($alertsPRTarget.StatusCode -ne 200){
   Write-Host "##vso[task.logissue type=error] Error getting alerts from Azure DevOps Advanced Security Main:", $alertsPRTarget.StatusCode, $alertsPRTarget.StatusDescription
   exit 1
}

if ($alertsPRSource.StatusCode -ne 200){
   Write-Host "##vso[task.logissue type=error] Error getting alerts from Azure DevOps Advanced Security PR:", $alertsPRSource.StatusCode, $alertsPRSource.StatusDescription
   exit 1
}

$jsonPRTarget = $alertsPRTarget.Content | ConvertFrom-Json
$jsonPRSource = $alertsPRSource.Content | ConvertFrom-Json 

# Extract alert ids from the list of alerts on pr target/source branch.
$prTargetAlertIds = $jsonPRTarget.value | Select-Object -ExpandProperty alertId
$prSourceAlertIds = $jsonPRSource.value | Select-Object -ExpandProperty alertId

# Check for alert ids that are reported in the PR source branch but not the pr target branch
$newAlertIds = Compare-Object $prSourceAlertIds $prTargetAlertIds -PassThru | Where-Object { $_.SideIndicator -eq '<=' }

# Are there any new alert ids in the PR source branch?
if($newAlertIds.length -gt 0) {
    Write-Host "##[error] There are more alerts in the PR source branch $($prSourceBranch), compared to target branch $($prTargetBranch) :"

    # Loop over the objects in the prAlerts JSON object
    foreach ($prAlert in $jsonPRSource.value) {
        if ($newAlertIds -contains $prAlert.alertId) {
            # This is a new Alert for this PR. Log and report it.
            Write-Host  ""
            Write-Host  "##vso[task.logissue type=error;sourcepath=$($prAlert.physicalLocations.filePath);linenumber=$($prAlert.physicalLocations.region.lineStart);columnnumber=$($prAlert.physicalLocations.region.columnStart)] New $alertType alert detected #$($prAlert.alertId) : $($prAlert.title)."
            Write-Host  "##[error] Fix or dismiss this new alert in the Advanced Security UI for pr branch $($prSourceBranch)."
            $urlAlert = "https://dev.azure.com/{0}/_git/{1}/alerts/{2}?branch={3}" -f $orgName, $project, $prAlert.alertId, $prSourceBranch
            Write-Host  "##[error] Details for this new alert:  $($urlAlert)"
        }
    }
    Write-Host
    Write-Host "##[error] Please review these Code Scanning alerts for the $($prBranch) branch using the regular Advanced Security UI" 
    Write-Host "##[error] Dissmiss or fix the alerts listed and try re-queue the CIVerify task."
    exit 1
} else {
    Write-Output "No new CodeQL alerts - all is fine"
    exit 0
}

