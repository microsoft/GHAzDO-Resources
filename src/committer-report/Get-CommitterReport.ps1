#Requires -Version 7.0

<#
.SYNOPSIS
    Generates a GHAzDO (GitHub Advanced Security for Azure DevOps) committer report
    across all accessible organizations.

.DESCRIPTION
    Enumerates all Azure DevOps organizations for the signed-in user, then for each
    org queries the Advanced Security meter usage estimate API to identify active
    committers. Produces:
      - A distinct committer count across all orgs
      - A distinct committer count per org
      - A detailed list of committers with their org memberships and GHAzDO license status

.NOTES
    Prerequisites:
      1. Install the Azure CLI   - https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
      2. Install the extension   - az extension add --name azure-devops
      3. Sign in                 - az login
#>

# -------------------------------------------------------------------
# Prerequisites (uncomment and run once if not already set up)
# -------------------------------------------------------------------
# az extension add --name azure-devops
# az login

# -------------------------------------------------------------------
# Step 1 - Verify Azure CLI session
# -------------------------------------------------------------------
Write-Host "Checking Azure CLI login status..." -ForegroundColor Cyan

$account = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "You are not logged in to Azure CLI. Please run 'az login' first."
    exit 1
}

Write-Host "Logged in successfully." -ForegroundColor Green

# -------------------------------------------------------------------
# Step 2 - Acquire an access token for Azure DevOps
# -------------------------------------------------------------------
Write-Host "Acquiring access token for Azure DevOps..." -ForegroundColor Cyan

$adoResource = "499b84ac-1321-427f-aa17-267ca6975798"
$tokenJson = az account get-access-token --resource $adoResource 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to acquire access token. Response: $tokenJson"
    exit 1
}

$accessToken = ($tokenJson | ConvertFrom-Json).accessToken
$headers = @{ Authorization = "Bearer $accessToken" }
Write-Host "Access token acquired." -ForegroundColor Green

# -------------------------------------------------------------------
# Step 3 - Get the signed-in user's VSSPS profile ID
# -------------------------------------------------------------------
Write-Host "Retrieving Azure DevOps profile..." -ForegroundColor Cyan

$profile = Invoke-RestMethod -Uri "https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.1" -Headers $headers -Method Get
$memberId = $profile.id

if ([string]::IsNullOrWhiteSpace($memberId)) {
    Write-Error "Failed to retrieve Azure DevOps profile ID."
    exit 1
}

Write-Host "Member ID: $memberId" -ForegroundColor Green

# -------------------------------------------------------------------
# Step 4 - List Azure DevOps organizations via REST API
# -------------------------------------------------------------------
Write-Host "Fetching Azure DevOps organizations..." -ForegroundColor Cyan

$url = "https://app.vssps.visualstudio.com/_apis/accounts?memberId=$memberId&api-version=7.1"
$orgs = Invoke-RestMethod -Uri $url -Headers $headers -Method Get

# -------------------------------------------------------------------
# Step 5 - Display organizations
# -------------------------------------------------------------------
if ($orgs.count -eq 0) {
    Write-Warning "No Azure DevOps organizations found for this account."
    exit 0
}

Write-Host "`nFound $($orgs.count) organization(s):`n" -ForegroundColor Green
$orgs.value | Select-Object accountName, accountUri | Format-Table -AutoSize

# -------------------------------------------------------------------
# Step 6 - For each org, get estimated committers via org-level API
# -------------------------------------------------------------------

# Hashtable keyed by committer identity — tracks orgs
$committerMap = @{}

foreach ($org in $orgs.value) {
    $orgName = $org.accountName
    Write-Host "Processing org: $orgName ..." -ForegroundColor Cyan

    # Org-level meter usage estimate — all projects/repos in one call
    try {
        $estimateUrl = "https://advsec.dev.azure.com/$orgName/_apis/management/meterUsageEstimate/default?plan=all&api-version=7.2-preview.3"
        $estimate = Invoke-RestMethod -Uri $estimateUrl -Headers $headers -Method Get -TimeoutSec 30

        # Merge committers from both Code Security and Secret Protection plans
        $allBilledUsers = @()
        if ($estimate.codeSecurityMeterUsageEstimate.billedUsers) {
            $allBilledUsers += $estimate.codeSecurityMeterUsageEstimate.billedUsers
        }
        if ($estimate.secretProtectionMeterUsageEstimate.billedUsers) {
            $allBilledUsers += $estimate.secretProtectionMeterUsageEstimate.billedUsers
        }

        if ($allBilledUsers.Count -gt 0) {
            # Deduplicate within the org by cuid
            $seenCuids = @{}
            $uniqueUsers = @()
            foreach ($u in $allBilledUsers) {
                if (-not $seenCuids.ContainsKey($u.cuid)) {
                    $seenCuids[$u.cuid] = $true
                    $uniqueUsers += $u
                }
            }

            Write-Host "  Estimated committers: $($uniqueUsers.Count)" -ForegroundColor Green

            foreach ($user in $uniqueUsers) {
                $upn = $user.userIdentity.uniqueName
                if ([string]::IsNullOrWhiteSpace($upn)) { $upn = $user.userIdentity.displayName }
                if ([string]::IsNullOrWhiteSpace($upn)) { continue }

                if (-not $committerMap.ContainsKey($upn)) {
                    $committerMap[$upn] = [PSCustomObject]@{
                        DisplayName       = $user.userIdentity.displayName
                        UserPrincipalName = $user.userIdentity.uniqueName
                        Orgs              = [System.Collections.Generic.HashSet[string]]::new()
                    }
                }

                $committerMap[$upn].Orgs.Add($orgName) | Out-Null
            }
        }
        else {
            Write-Host "  Estimated committers: 0" -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Warning "  Skipping org '$orgName' — unable to query: $($_.Exception.Message)"
    }
}

# -------------------------------------------------------------------
# Step 7 - Report: Distinct count across all orgs
# -------------------------------------------------------------------
$allCommitters = $committerMap.Values
$totalDistinct = $allCommitters.Count

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host " COMMITTER REPORT SUMMARY" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Total distinct committers across all orgs: $totalDistinct" -ForegroundColor Green

# -------------------------------------------------------------------
# Step 8 - Report: Distinct count per org
# -------------------------------------------------------------------
Write-Host "`n--- Committers Per Org ---" -ForegroundColor Yellow

$orgCounts = @{}
foreach ($c in $allCommitters) {
    foreach ($o in $c.Orgs) {
        if (-not $orgCounts.ContainsKey($o)) { $orgCounts[$o] = 0 }
        $orgCounts[$o]++
    }
}

$orgCounts.GetEnumerator() | Sort-Object Name | ForEach-Object {
    Write-Host "  $($_.Key): $($_.Value) committer(s)" -ForegroundColor White
}

# -------------------------------------------------------------------
# Step 9 - Report: Full committer list with org memberships
# -------------------------------------------------------------------
Write-Host "`n--- Committer Details ---" -ForegroundColor Yellow

$allCommitters |
    Sort-Object DisplayName |
    Select-Object DisplayName, UserPrincipalName, @{N='Organizations';E={$_.Orgs -join ', '}} |
    Format-Table -AutoSize -Wrap
