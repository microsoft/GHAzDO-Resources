# This script is used as part of our PR gating strategy. It takes advantage of the GHAzDO REST API to check for CodeQL issues a PR source and target branch.
# If there are 'new' issues in the source branch, the script will fail with error code 1.
# The script will also log errors, 1 per new CodeQL alert, it will also add PR annotations for the alert
$pass = ${env:MAPPED_ADO_PAT}
$orgUri = ${env:SYSTEM_COLLECTIONURI}
$orgName = $orgUri -replace "^https://dev.azure.com/|/$"
$project = ${env:SYSTEM_TEAMPROJECT}
$repositoryId = ${env:BUILD_REPOSITORY_ID}
$prTargetBranch = ${env:SYSTEM_PULLREQUEST_TARGETBRANCH}
$prSourceBranch = ${env:BUILD_SOURCEBRANCH}
$prId = ${env:SYSTEM_PULLREQUEST_PULLREQUESTID}
$prInteration = ${env:SYSTEM_PULLREQUEST_PULLREQUESTITERATION}
$pair = ":${pass}"
$bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
$base64 = [System.Convert]::ToBase64String($bytes)
$basicAuthValue = "Basic $base64"
$headers = @{ Authorization = $basicAuthValue }

$urlTargetAlerts = "https://advsec.dev.azure.com/{0}/{1}/_apis/Alert/repositories/{2}/Alerts?top=500&orderBy=lastSeen&criteria.alertType=3&criteria.ref={3}&criteria.states=1" -f $orgName, $project, $repositoryId, $prTargetBranch
$urlSourceAlerts = "https://advsec.dev.azure.com/{0}/{1}/_apis/Alert/repositories/{2}/Alerts?top=500&orderBy=lastSeen&criteria.alertType=3&criteria.ref={3}&criteria.states=1" -f $orgName, $project, $repositoryId, $prSourceBranch
$urlComment = "https://dev.azure.com/{0}/{1}/_apis/git/repositories/{2}/pullRequests/{3}/threads?api-version=7.1-preview.1" -f $orgName, $project, $repositoryId, $prId
$urlIteration = "https://dev.azure.com/{0}/{1}/_apis/git/repositories/{2}/pullRequests/{3}/iterations/{4}/changes?api-version=7.1-preview.1&`$compareTo={5}" -f $orgName, $project, $repositoryId, $prId, $prInteration, ($prInteration - 1)

#Get-ChildItem Env: | Format-Table -AutoSize

# Add a PR annotations for the Alert in the changed file.
function AddPRComment($prAlert, $urlAlert) {
    # Get Pull Request iterations, we need this to map the file to a changeTrackingId
    $prIterations = Invoke-RestMethod -Uri $urlIteration -Method Get -Headers $headers

    # Find the changeTrackingId mapping to the file with the CodeQL alert
    $iterationItem = $prIterations.changeEntries | Where-Object { $_.item.path -like "/$($prAlert.physicalLocations[-1].filePath)" } | Select-Object -First 1

    # Any change to the file with the CodeQL alert in this PR iteration?
    if ($null -eq $iterationItem) {
        Write-Host "In this iteration of the PR, there is no change to the file with the CodeQL alert. "
        return
    }

    $lineEnd = $($prAlert.physicalLocations[-1].region.lineEnd)
    $lineStart = $($prAlert.physicalLocations[-1].region.lineStart)

    if ($lineEnd -eq 0) {
        $lineEnd = $lineStart
    }

    # Define the Body hashtable
    $body = @{
        "comments"                 = @(
            @{
                "content"     = "**$($prAlert.title)**
                $($prAlert.tools.rules.description)
                See details [here]($($urlAlert))"
                "commentType" = 1
            }
        )
        "status"                   = 1
        "threadContext"            = @{
            "filePath"       = "./$($prAlert.physicalLocations[-1].filePath)"
            "rightFileStart" = @{
                "line"   = $lineStart
                "offset" = $($prAlert.physicalLocations[-1].region.columnStart)
            }
            "rightFileEnd"   = @{
                "line"   = $lineEnd
                "offset" = $($prAlert.physicalLocations[-1].region.columnEnd)
            }
        }
        "pullRequestThreadContext" = @{
            "changeTrackingId" = $($iterationItem.changeTrackingId)
            "iterationContext" = @{
                "firstComparingIteration"  = $($prInteration)
                "secondComparingIteration" = $($prInteration)
            }
        }
    }

    # Convert the hashtable to a JSON string
    $bodyJson = $body | ConvertTo-Json -Depth 10

    # Print the JSON string
    #Write-Output $bodyJson

    # Send the POST request
    $response = Invoke-RestMethod -Uri $urlComment -Method Post -Headers $headers -Body $bodyJson -ContentType "application/json"

    #Write-Output $response

}

Write-Host "Will check to see if there are any new CodeQL issues in this PR branch"
Write-Host "PR source : $($prSourceBranch). PR target: $($prTargetBranch)"

if (${env:BUILD_REASON} -ne 'PullRequest') {
    Write-Host "This build is not part of a Pull Request so all is ok"
    exit 0
}

# Get the alerts on the pr target branch (all without filter) and the PR source branch (only currently open)
$alertsPRSource = Invoke-WebRequest -Uri $urlSourceAlerts -Headers $headers -Method Get

# The CodeQL scanning of the target branch runs in a separate pipeline. This scan might not have been completed.
# Try to get the results 10 times with a 1 min wait between each try.
$retries = 10
while ($retries -gt 0) {
    try {
        $alertsPRTarget = Invoke-WebRequest -Uri $urlTargetAlerts -Headers $headers -Method Get -ErrorAction Stop
        # Success
        break
    }
    catch {
        # No GHAzDO results on the target branch, wait and retry?
        if ($_.ErrorDetails.Message.Split("`"") -contains "BranchNotFoundException") {
            $retries--
            if ($retries -eq 0) {
                # We have retried the maximum number of times, give up
                Write-Host "##vso[task.logissue type=error] We have retried the maximum number of times, give up."
                throw $_
            }

            # Wait and then try again
            Write-Host "There are no GHAzDO results on the target branch, wait and try again."
            Start-Sleep -Seconds 60
        }
        else {
            # Something else is wrong, give up
            Write-Host "##vso[task.logissue type=error] There was an unexpected error."
            throw $_
        }
    }
}

if ($alertsPRTarget.StatusCode -ne 200) {
    Write-Host "##vso[task.logissue type=error] Error getting alerts from Azure DevOps Advanced Security PR target branch:", $alertsPRTarget.StatusCode, $alertsPRTarget.StatusDescription
    exit 1
}

if ($alertsPRSource.StatusCode -ne 200) {
    Write-Host "##vso[task.logissue type=error] Error getting alerts from Azure DevOps Advanced Security PR source branch:", $alertsPRSource.StatusCode, $alertsPRSource.StatusDescription
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
if ($newAlertIds.length -gt 0) {
    Write-Host "##[error] The code changes in this PR looks to be introducing new CodeQL alerts:"

    # Loop over the objects in the prAlerts JSON object
    foreach ($prAlert in $jsonPRSource.value) {
        if ($newAlertIds -contains $prAlert.alertId) {
            # This is a new Alert for this PR. Log and report it.
            Write-Host  ""
            Write-Host  "##vso[task.logissue type=error;sourcepath=$($prAlert.physicalLocations[-1].filePath);linenumber=$($prAlert.physicalLocations[-1].region.lineStart);columnnumber=$($prAlert.physicalLocations[-1].region.columnStart)] New $alertType alert detected #$($prAlert.alertId) : $($prAlert.title)."
            Write-Host  "##[error] Fix or dismiss this new alert in the Advanced Security UI for pr branch $($prSourceBranch)."
            $urlAlert = "https://dev.azure.com/{0}/{1}/_git/{2}/alerts/{3}?branch={4}" -f $orgName, $project, $repositoryId, $prAlert.alertId, $prSourceBranch
            Write-Host  "##[error] Details for this new alert:  $($urlAlert)"

            AddPRComment $prAlert $urlAlert
        }
    }
    Write-Host
    Write-Host "##[error] Please review these Code Scanning alerts for the $($prBranch) branch using the regular Advanced Security UI"
    Write-Host "##[error] Dissmiss or fix the alerts listed and try re-queue the CIVerify task."
    exit 1
}
else {
    Write-Output "No new CodeQL alerts - all is fine"
    exit 0
}