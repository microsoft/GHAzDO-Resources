# This script is used as part of our PR gating strategy. It takes advantage of the GHAzDO REST API to check for Code Scanning and Dependency Scanning issues a PR source and target branch.
# If there are 'new' issues in the source branch, the script will fail with error code 1.
# The script will also log errors, 1 per new Code Scanning/Dependency alert, it will also add PR annotations for the alert
$pat = ${env:MAPPED_ADO_PAT}
$orgUri = ${env:SYSTEM_COLLECTIONURI}
$orgName = $orgUri -replace "^https://dev.azure.com/|/$"
$project = ${env:SYSTEM_TEAMPROJECT}
$repositoryId = ${env:BUILD_REPOSITORY_ID}
$prTargetBranch = ${env:SYSTEM_PULLREQUEST_TARGETBRANCH}
$prSourceBranch = ${env:BUILD_SOURCEBRANCH}
$prId = ${env:SYSTEM_PULLREQUEST_PULLREQUESTID}
$prCurrentIteration = ${env:SYSTEM_PULLREQUEST_PULLREQUESTITERATION}
$buildReason = ${env:BUILD_REASON}
$sourceDir = ${env:BUILD_SOURCESDIRECTORY}
$headers = @{ Authorization = "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(($pat.Contains(":") ? $pat : ":$pat"))))" }
#Get-ChildItem Env: | Format-Table -AutoSize

#GATING POLICY - Which alerts to check for and which severities to include
$alertTypes = @("dependency", "code")
$severityPolicy = @{
    "dependency" = @("critical", "high", "medium", "low")
    "code"       = @("critical", "high", "medium", "low", "error", "warning", "note" ) #Security and Quality Severities
}

# Alerts - List api: https://learn.microsoft.com/en-us/rest/api/azure/devops/advancedsecurity/alerts/list (criteria.states = 1 means open alerts, criteria.alertType does not support multiple values, so we need to allow default and filter out later)
$urlTargetAlerts = "https://advsec.dev.azure.com/{0}/{1}/_apis/Alert/repositories/{2}/Alerts?top=500&orderBy=lastSeen&criteria.ref={3}&criteria.states=1" -f $orgName, $project, $repositoryId, $prTargetBranch
$urlSourceAlerts = "https://advsec.dev.azure.com/{0}/{1}/_apis/Alert/repositories/{2}/Alerts?top=500&orderBy=lastSeen&criteria.ref={3}&criteria.states=1" -f $orgName, $project, $repositoryId, $prSourceBranch

#PR Threads - Create api: https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-threads/create
$urlComment = "https://dev.azure.com/{0}/{1}/_apis/git/repositories/{2}/pullRequests/{3}/threads?api-version=7.1-preview.1" -f $orgName, $project, $repositoryId, $prId
#PR Iteration Changes - Get API: https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-iteration-changes/get
$urlIteration = "https://dev.azure.com/{0}/{1}/_apis/git/repositories/{2}/pullRequests/{3}/iterations/{4}/changes?api-version=7.1-preview.1&`$compareTo={5}" -f $orgName, $project, $repositoryId, $prId, $prCurrentIteration, ($prCurrentIteration - 1)

# Add a PR annotations for the Alert in the changed file.  This is only intended for alerts where the alert intersects with source code found in the PR diff.
function AddPRComment($prAlert, $urlAlert) {
    $pathToCheck = $prAlert.physicalLocations[-1].filePath

    ## Todo - potentially improve this for transitive dependencies by walking the path to parent(will need to dedup as Dependency scanning will report findings on transitive manifests such as /node_modules/x/package.json )
    if ($prAlert.alertType -eq "dependency") {
        #dependency alerts physicalLocations always begin with the last directory in sourceDir (ex: 's/package.json'), so parse it out
        #$sourceDirSegment = Split-Path $sourceDir -Leaf ###also works but harder to test locally as it needs a real Path :)
        $sourceDirSegment = $sourceDir.Split([System.IO.Path]::DirectorySeparatorChar)[-1]
        $pathToCheck = $pathToCheck.TrimStart($sourceDirSegment)
    }
    elseif($prAlert.alertType -eq "code") {
        $pathToCheck = "/" + $pathToCheck
    }

    # Get Pull Request iterations, we need this to map the file to a changeTrackingId
    $prIterations = Invoke-RestMethod -Uri $urlIteration -Method Get -Headers $headers

    # Find the changeTrackingId mapping to the file with the Code Scanning alert
    $iterationItem = $prIterations.changeEntries | Where-Object { $_.item.path -like $pathToCheck } | Select-Object -First 1

    # Any change to the file with the alert in this PR iteration?
    if ($null -eq $iterationItem) {
        Write-Host "##[debug] In this iteration of the PR:Iteration $prCurrentIteration, there is no change to the file where the alert was detected: $pathToCheck."
        return
    }

    if ($prAlert.alertType -eq "dependency") {
        # Define the Body hashtable
        # Dependency alerts do not have line numbers, so we will not add a line number to the comment
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
            }
            "pullRequestThreadContext" = @{
                "changeTrackingId" = $($iterationItem.changeTrackingId)
                "iterationContext" = @{
                    "firstComparingIteration"  = $($prCurrentIteration)
                    "secondComparingIteration" = $($prCurrentIteration)
                }
            }
        }
    }
    elseif($prAlert.alertType -eq "code") {
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
                    "firstComparingIteration"  = $($prCurrentIteration)
                    "secondComparingIteration" = $($prCurrentIteration)
                }
            }
        }
    }

    # Convert the hashtable to a JSON string
    $bodyJson = $body | ConvertTo-Json -Depth 10
    #Write-Output $bodyJson

    # Send the PR Threads Create POST request
    $response = Invoke-RestMethod -Uri $urlComment -Method Post -Headers $headers -Body $bodyJson -ContentType "application/json"

    #Write-Output $response
    Write-Host "##[debug] New thread created in PR:Iteration $prCurrentIteration : $($response._links.self.href)"

    return
}

Write-Host "Will check to see if there are any new Dependency or Code scanning alerts in this PR branch"
Write-Host "PR source : $($prSourceBranch). PR target: $($prTargetBranch)"

if ($buildReason -ne 'PullRequest') {
    Write-Host "This build is not part of a Pull Request so all is ok"
    exit 0
}

# Get the alerts on the pr target branch (all without filter) and the PR source branch (only currently open)
$alertsPRSource = Invoke-WebRequest -Uri $urlSourceAlerts -Headers $headers -Method Get

# The Advanced Security scanning of the target branch runs in a separate pipeline. This scan might not have been completed.
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

# Filter out the alert types that we are interested in
$jsonPRTarget = ($alertsPRTarget.Content | ConvertFrom-Json).value | Where-Object { $alertTypes -contains $_.alertType }
$jsonPRSource = ($alertsPRSource.Content | ConvertFrom-Json).value | Where-Object { $alertTypes -contains $_.alertType }

# Extract alert ids from the list of alerts on pr target/source branch.
$prTargetAlertIds = $jsonPRTarget | Select-Object -ExpandProperty alertId
$prSourceAlertIds = $jsonPRSource | Select-Object -ExpandProperty alertId

# Check for alert ids that are reported in the PR source branch but not the pr target branch
$newAlertIds = Compare-Object $prSourceAlertIds $prTargetAlertIds -PassThru | Where-Object { $_.SideIndicator -eq '<=' }
$dependencyAlerts = $codeAlerts = 0

# Are there any new alert ids in the PR source branch?
if ($newAlertIds.length -gt 0) {
    Write-Host "##[warning] The code changes in this PR looks to be introducing new security alerts:"

    # Loop over the objects in the prAlerts JSON object
    foreach ($prAlert in $jsonPRSource) {
        if ($newAlertIds -contains $prAlert.alertId) {

            #check to see $alert.severity in $severityPolicy for given alertType - valid severities: https://learn.microsoft.com/en-us/rest/api/azure/devops/advancedsecurity/alerts/list#severity
            if ($severityPolicy[$prAlert.alertType] -notcontains $prAlert.severity) {
                Write-Host "##[warning] Ignored by policy - $($prAlert.severity) severity $($prAlert.alertType) alert detected #$($prAlert.alertId) : $($prAlert.title) in pr branch $($prSourceBranch)."
                continue
            }

            # New Alert for this PR. Log and report it.
            Write-Host  ""
            if ($prAlert.alertType -eq "dependency") {
                Write-Host  "##vso[task.logissue type=error] New $($prAlert.severity) severity $($prAlert.alertType) alert detected #$($prAlert.alertId) in library: $($prAlert.logicalLocations[-1].fullyQualifiedName). `"$($prAlert.title)`". Detected in manifest: $($prAlert.physicalLocations[-1].filePath)."
                $dependencyAlerts++
            }
            elseif ($prAlert.alertType -eq "code") {
                Write-Host  "##vso[task.logissue type=error;sourcepath=$($prAlert.physicalLocations[-1].filePath);linenumber=$($prAlert.physicalLocations[-1].region.lineStart);columnnumber=$($prAlert.physicalLocations[-1].region.columnStart)] New $($prAlert.severity) severity $($prAlert.alertType) alert detected #$($prAlert.alertId) : $($prAlert.title)."
                $codeAlerts++
            }

            Write-Host  "##[error] Fix or dismiss this new $($prAlert.alertType) alert in the Advanced Security UI for pr branch $($prSourceBranch)."
            $urlAlert = "https://dev.azure.com/{0}/{1}/_git/{2}/alerts/{3}?branch={4}" -f $orgName, $project, $repositoryId, $prAlert.alertId, $prSourceBranch
            Write-Host  "##[error] Details for this new alert:  $($urlAlert)"
            AddPRComment $prAlert $urlAlert
        }
    }

    if ($dependencyAlerts + $codeAlerts -gt 0) {
        Write-Host
        Write-Host "##[error] Dissmiss or fix failing alerts listed (dependency #: $dependencyAlerts / code #: $codeAlerts ) and try re-queue the CIVerify task."
        exit 1 #TODO - dynamically pass/fail the build only if a PR comment was added, indicating that there are new alerts that were directly created by this PR.  Since we do incremental PR iteration based comments this is not currently viable.
    }
    else {
        Write-Host "##[warning] New alerts detected but none that violate policy - all is fine though these will appear in the Advanced Security UI."
        exit 0
    }
}
else {
    Write-Output "No new alerts - all is fine"
    exit 0
}
