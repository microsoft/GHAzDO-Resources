#Requires -Version 7.0

<#
.SYNOPSIS
    Generates a GHAzDO (GitHub Advanced Security for Azure DevOps) committer report
    across all accessible organizations.

.DESCRIPTION
    Enumerates all Azure DevOps organizations for the signed-in user, then for each
    org queries two org-level APIs:
      - meterUsageEstimate: committers who would be billed if AdvSec were enabled on
        remaining repos (repos where AdvSec is currently OFF)
      - meterusage: committers who are currently consuming a GHAzDO license
    Produces:
      - A distinct committer count across all orgs
      - A distinct committer count per org
      - A detailed list of all committers with their org memberships and a boolean
        indicating whether they are currently consuming a GHAzDO license

.PARAMETER CsvPath
    Optional. Path to export the committer report as a CSV file.
    If not specified, results are displayed in the console only.

.EXAMPLE
    .\Get-CommitterReport.ps1
    Displays the committer report in the console.

.EXAMPLE
    .\Get-CommitterReport.ps1 -CsvPath .\committer-report.csv
    Displays the report and exports it to a CSV file.

.NOTES
    Prerequisites:
      1. Install the Azure CLI   - https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
      2. Sign in                 - az login --tenant <tenant_id> --allow-no-subscriptions


    ex:
    az logout
    az login --tenant <tenant_id> --allow-no-subscriptions

#>

param(
    [Parameter(Mandatory = $false)]
    [string]$CsvPath
)

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------
$ApiTimeoutSec = 60

# -------------------------------------------------------------------
# Prerequisites (uncomment and run once if not already set up)
# -------------------------------------------------------------------
# az login

# -------------------------------------------------------------------
# Step 1 - Verify Azure CLI session
# -------------------------------------------------------------------
Write-Host "Checking Azure CLI login status..." -ForegroundColor Cyan

$account = az account show --output json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "You are not logged in to Azure CLI. Please run 'az login' first."
    exit 1
}

$accountInfo = $account | ConvertFrom-Json
$tenantId = $accountInfo.tenantId
Write-Host "Logged in successfully." -ForegroundColor Green
Write-Host "Tenant ID: $tenantId" -ForegroundColor Green

# -------------------------------------------------------------------
# Step 2 - Acquire an access token for Azure DevOps
# -------------------------------------------------------------------
Write-Host "Acquiring access token for Azure DevOps..." -ForegroundColor Cyan

$adoResource = "499b84ac-1321-427f-aa17-267ca6975798"
$tokenJson = az account get-access-token --resource $adoResource --output json 2>&1

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

try {
    $profile = Invoke-RestMethod -Uri "https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.1" -Headers $headers -Method Get
}
catch {
    Write-Error "Failed to retrieve Azure DevOps profile. Verify your token has the required scopes. Error: $($_.Exception.Message)"
    exit 1
}

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

try {
    $url = "https://app.vssps.visualstudio.com/_apis/accounts?memberId=$memberId&api-version=7.1"
    $orgs = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
}
catch {
    Write-Error "Failed to fetch Azure DevOps organizations. Error: $($_.Exception.Message)"
    exit 1
}

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
# Step 6 - For each org, get estimated + actual committers via org-level APIs
# -------------------------------------------------------------------

# Hashtable keyed by cuid (stable unique ID across Azure subscriptions) — tracks orgs and license status
$committerMap = @{}

# Helper to merge users into the committer map
function Add-CommittersToMap {
    param($Users, $OrgName, $IsLicensed, $Plan)

    foreach ($user in $Users) {
        $key = $user.cuid
        if ([string]::IsNullOrWhiteSpace($key)) { continue }

        if (-not $committerMap.ContainsKey($key)) {
            $committerMap[$key] = [PSCustomObject]@{
                DisplayName       = $user.userIdentity.displayName
                UserPrincipalName = $user.userIdentity.uniqueName
                Orgs              = [System.Collections.Generic.HashSet[string]]::new()
                GHAzDOLicensed    = $false
                OrgPlans          = @{}  # org name -> HashSet of plan labels
            }
        }

        $committerMap[$key].Orgs.Add($OrgName) | Out-Null
        if ($IsLicensed) {
            $committerMap[$key].GHAzDOLicensed = $true
            if ($Plan) {
                if (-not $committerMap[$key].OrgPlans.ContainsKey($OrgName)) {
                    $committerMap[$key].OrgPlans[$OrgName] = [System.Collections.Generic.HashSet[string]]::new()
                }
                $committerMap[$key].OrgPlans[$OrgName].Add($Plan) | Out-Null
            }
        }
    }
}

foreach ($org in $orgs.value) {
    $orgName = $org.accountName
    Write-Host "Processing org: $orgName ..." -ForegroundColor Cyan

    # 6a - Org-level meter usage estimate (committers for repos where AdvSec is OFF)
    try {
        $estimateUrl = "https://advsec.dev.azure.com/$orgName/_apis/management/meterUsageEstimate/default?plan=all&api-version=7.2-preview.3"
        $estimate = Invoke-RestMethod -Uri $estimateUrl -Headers $headers -Method Get -TimeoutSec $ApiTimeoutSec

        $csEstUsers = @()
        $spEstUsers = @()
        if ($estimate.codeSecurityMeterUsageEstimate.billedUsers) {
            $csEstUsers = $estimate.codeSecurityMeterUsageEstimate.billedUsers
        }
        if ($estimate.secretProtectionMeterUsageEstimate.billedUsers) {
            $spEstUsers = $estimate.secretProtectionMeterUsageEstimate.billedUsers
        }

        # Deduplicate for count display
        $allCuids = @{}
        ($csEstUsers + $spEstUsers) | ForEach-Object { $allCuids[$_.cuid] = $_ }

        Write-Host "  Estimated (AdvSec OFF repos): $($allCuids.Count)" -ForegroundColor DarkGray
        Add-CommittersToMap -Users $csEstUsers -OrgName $orgName -IsLicensed $false -Plan 'CodeSecurity'
        Add-CommittersToMap -Users $spEstUsers -OrgName $orgName -IsLicensed $false -Plan 'SecretProtection'
    }
    catch {
        Write-Warning "  Estimate API skipped for '$orgName': $($_.Exception.Message)"
    }

    # 6b - Org-level actual meter usage per plan (committers currently consuming a license)
    # ⚠️ WARNING: UNDOCUMENTED BEHAVIOR — FRAGILE DETECTION ⚠️
    # The billing model (bundled vs unbundled) is not exposed by any documented API field.
    # This detection relies on an undocumented behavioral difference found by trial and error:
    #   - Bundled orgs accept plan=all on the meter usage API and return a unified response.
    #   - Unbundled orgs reject plan=all with a 400 "Invalid plan: All" error.
    # This behavior is not guaranteed by Microsoft and may change without notice.
    # If this detection breaks, fall back to querying each plan separately and remove
    # the bundled/unbundled distinction from the output.
    $isBundled = $false
    try {
        $allUrl = "https://advsec.dev.azure.com/$orgName/_apis/management/meterusage/default?plan=all&api-version=7.2-preview.3"
        $allUsage = Invoke-RestMethod -Uri $allUrl -Headers $headers -Method Get -TimeoutSec $ApiTimeoutSec
        $isBundled = $true

        $billedUsers = @()
        if ($allUsage.billedUsers.billedUsers) {
            $billedUsers = $allUsage.billedUsers.billedUsers
        }

        Write-Host "  Billing model: Bundled (AdvancedSecurity) [plan=all → 200]" -ForegroundColor Cyan
        if ($allUsage.isPlanEnabled) {
            Write-Host "  Licensed (AdvancedSecurity): $($billedUsers.Count)" -ForegroundColor Green
            Add-CommittersToMap -Users $billedUsers -OrgName $orgName -IsLicensed $true -Plan 'AdvancedSecurity'
        }
        else {
            Write-Host "  AdvancedSecurity plan not enabled" -ForegroundColor DarkGray
        }
    }
    catch {
        # plan=all rejected — determine why
        $errorMsg = $_.Exception.Message
        if ($errorMsg -match '404') {
            # 404 on plan=all: In all observed cases, bundled orgs return 404 when no
            # plan has been purchased, while unbundled orgs return 400 "Invalid plan: All"
            # regardless of purchase state. So we treat 404 as bundled (no plan purchased).
            Write-Host "  Billing model: Bundled (AdvancedSecurity) — no plan purchased [plan=all → 404]" -ForegroundColor DarkGray
        }
        elseif ($errorMsg -match 'Invalid plan|400') {
            # 400 "Invalid plan: All" = org is unbundled, query each plan separately
            $unbundledResults = @{}
            foreach ($plan in @('codeSecurity', 'secretProtection')) {
                $planLabel = if ($plan -eq 'codeSecurity') { 'CodeSecurity' } else { 'SecretProtection' }
                try {
                    $usageUrl = "https://advsec.dev.azure.com/$orgName/_apis/management/meterusage/default?plan=$plan&api-version=7.2-preview.3"
                    $usage = Invoke-RestMethod -Uri $usageUrl -Headers $headers -Method Get -TimeoutSec $ApiTimeoutSec
                    $unbundledResults[$planLabel] = @{ Success = $true; Usage = $usage }
                }
                catch {
                    $unbundledResults[$planLabel] = @{ Success = $false; Error = $_.Exception.Message }
                }
            }

            # If both plans returned 404, neither is purchased — show a single message
            $allNotPurchased = ($unbundledResults.Values | Where-Object { -not $_.Success -and $_.Error -match '404' }).Count -eq 2
            if ($allNotPurchased) {
                Write-Host "  Billing model: Unbundled (CodeSecurity + SecretProtection) — no plans purchased [plan=all → 400]" -ForegroundColor DarkGray
            }
            else {
                Write-Host "  Billing model: Unbundled (CodeSecurity + SecretProtection) [plan=all → 400]" -ForegroundColor Cyan
                foreach ($planLabel in @('CodeSecurity', 'SecretProtection')) {
                    $result = $unbundledResults[$planLabel]
                    if ($result.Success) {
                        $billedUsers = @()
                        if ($result.Usage.billedUsers.billedUsers) {
                            $billedUsers = $result.Usage.billedUsers.billedUsers
                        }

                        if ($result.Usage.isPlanEnabled) {
                            Write-Host "  Licensed ($planLabel):$((' ' * (20 - $planLabel.Length)))$($billedUsers.Count)" -ForegroundColor Green
                            Add-CommittersToMap -Users $billedUsers -OrgName $orgName -IsLicensed $true -Plan $planLabel
                        }
                        else {
                            Write-Host "  $planLabel plan not enabled" -ForegroundColor DarkGray
                        }
                    }
                    else {
                        if ($result.Error -match '404') {
                            Write-Host "  $planLabel not purchased" -ForegroundColor DarkGray
                        }
                        else {
                            Write-Host "  $planLabel meter usage unavailable: $($result.Error)" -ForegroundColor DarkGray
                        }
                    }
                }
            }
        }
        else {
            Write-Host "  Meter usage unavailable: $errorMsg" -ForegroundColor DarkGray
        }
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

$report = $allCommitters |
    Sort-Object DisplayName |
    Select-Object DisplayName, UserPrincipalName, GHAzDOLicensed, @{N='Plans';E={
        # Compute the effective plan per org, then deduplicate across orgs
        $effectivePlans = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($orgEntry in $_.OrgPlans.GetEnumerator()) {
            $orgPlanSet = $orgEntry.Value
            if ($orgPlanSet.Contains('CodeSecurity') -and $orgPlanSet.Contains('SecretProtection')) {
                $effectivePlans.Add('AdvancedSecurity') | Out-Null
            }
            else {
                foreach ($p in $orgPlanSet) { $effectivePlans.Add($p) | Out-Null }
            }
        }
        ($effectivePlans | Sort-Object) -join ', '
    }}, @{N='Organizations';E={$_.Orgs -join ', '}}

$report | Format-Table -Property DisplayName, GHAzDOLicensed, Plans, Organizations -AutoSize -Wrap

# -------------------------------------------------------------------
# Step 10 - Export to CSV if requested
# -------------------------------------------------------------------
if ($CsvPath) {
    $sanitizedReport = $report | ForEach-Object {
        $sanitizedRow = $_.PSObject.Copy()
        foreach ($property in $sanitizedRow.PSObject.Properties) {
            if ($property.Value -is [string] -and $property.Value -match '^[=+\-@]') {
                $property.Value = "'$($property.Value)"
            }
        }
        $sanitizedRow
    }
    $sanitizedReport | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "CSV exported to: $CsvPath" -ForegroundColor Green
}
