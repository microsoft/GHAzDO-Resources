<#
.SYNOPSIS
  One-click CodeQL enablement using dynamic pipelines.
  - No YAML injection or manual pipeline creation.
  - Enables Advanced Security + CodeQL for supported languages.
  - Supports -WhatIf and -Confirm parameters for safe execution.

.DESCRIPTION
  This script enables Advanced Security and CodeQL scanning for repositories in Azure DevOps using dynamic pipelines.
  It supports the -WhatIf and -Confirm parameters, allowing users to preview actions without making changes (-WhatIf)
  and to confirm before performing actions (-Confirm), as provided by SupportsShouldProcess.

.PARAMETERS
  -OrgName: Azure DevOps organization name.
  -ProjectName: Optional. If omitted, script runs org-wide.
  -Pat: Personal Access Token with Advanced Security permissions.
  -AgentPoolName: Optional. Defaults to 'AdvancedSecurityPool'.
  -RepoFilter: Optional. Wildcard pattern to filter repositories by name (e.g., "MyApp*", "*Test*").
  -WhatIf: Optional. Shows what would happen if the script runs, without making changes.
  -Confirm: Optional. Prompts for confirmation before making changes.

.EXAMPLE
  # Project-scoped execution
  .\Enable-CodeQL-Dynamic.ps1 -OrgName "contoso" -ProjectName "Payments" -Pat "<PAT>"

  # Org-wide execution (all projects)
  .\Enable-CodeQL-Dynamic.ps1 -OrgName "contoso" -Pat "<PAT>"

  # Filter repositories by name pattern
  .\Enable-CodeQL-Dynamic.ps1 -OrgName "contoso" -ProjectName "Payments" -Pat "<PAT>" -RepoFilter "MyApp*"

  # Filter repositories containing "Test" in the name
  .\Enable-CodeQL-Dynamic.ps1 -OrgName "contoso" -Pat "<PAT>" -RepoFilter "*Test*"

.NOTES
  Use -WhatIf to see what changes would be made without applying them.
  Use -Confirm to prompt for confirmation before making changes.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
  [Parameter(Mandatory = $true)]
  [string] $OrgName,

  [Parameter(Mandatory = $false)]
  [string] $ProjectName,

  [Parameter(Mandatory = $true)]
  [string] $Pat,

  [Parameter(Mandatory = $false)]
  [string] $AgentPoolName = "AdvancedSecurityPool",

  [Parameter(Mandatory = $false)]
  [string] $RepoFilter
)

# ------------ Setup ------------
$ErrorActionPreference = 'Stop'
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":" + $Pat))
$headers = @{ Authorization = "Basic $base64AuthInfo"; "Content-Type" = "application/json" }
$apiVersion = "7.1-preview.1"
$enablementApiVersion = "7.2-preview.3"

$report = New-Object System.Collections.Generic.List[psobject]
$scriptStart = Get-Date

# ------------ Get Repositories ------------
try {
    $reposUrl = if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        "https://dev.azure.com/$OrgName/_apis/git/repositories?api-version=$apiVersion"
    } else {
        "https://dev.azure.com/$OrgName/$ProjectName/_apis/git/repositories?api-version=$apiVersion"
    }

    $repos = (Invoke-RestMethod -Uri $reposUrl -Headers $headers).value
} catch {
    Write-Error "Failed to retrieve repositories: $($_.Exception.Message)"
    return
}

# Apply repository name filtering if specified
if (-not [string]::IsNullOrWhiteSpace($RepoFilter)) {
    $originalCount = $repos.Count
    $repos = $repos | Where-Object { $_.name -like $RepoFilter }
    $filteredCount = $repos.Count
    Write-Host "Repository filter '$RepoFilter' applied: $filteredCount of $originalCount repositories match"
    
    if ($filteredCount -eq 0) {
        Write-Warning "No repositories match the filter pattern '$RepoFilter'. Exiting."
        return
    }
}

# Group repositories by project for proper API calls
# Priority order: 1) Use repo.project.name if available, 2) Fall back to ProjectName parameter, 3) Skip if neither
$reposByProject = @{}
foreach ($repo in $repos) {
    # Determine project name with proper priority: repo object first, then parameter fallback
    if ($repo.project -and -not [string]::IsNullOrWhiteSpace($repo.project.name)) {
        # Repo has project info - use it (highest priority)
        $thisProject = $repo.project.name
    } elseif (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
        # No project info in repo object, but ProjectName parameter was provided - use as fallback
        $thisProject = $ProjectName
    } else {
        # Neither repo project info nor ProjectName parameter available
        Write-Warning "Skipping repository '$($repo.name)' - no project information available"
        continue
    }
    
    if (-not $reposByProject.ContainsKey($thisProject)) {
        $reposByProject[$thisProject] = @()
    }
    $reposByProject[$thisProject] += $repo
}

# Process each project separately
foreach ($projectKey in $reposByProject.Keys) {
    $projectRepos = $reposByProject[$projectKey]
    $enablementPayload = @()
    
    Write-Host "Processing project: $projectKey"
    
    foreach ($repo in $projectRepos) {
        Write-Host "Preparing enablement for repo: $($repo.name)"

        $enablementPayload += @{
            repositoryId = $repo.id
            advSecEnabled = $true
            codeScanningEnabled = $true
            advSecEnablementFeatures = @{
                codeQLEnabled = $true
            }
        }

        $report.Add([pscustomobject]@{
            Timestamp  = (Get-Date)
            Project    = $projectKey
            Repository = $repo.name
            RepoId     = $repo.id
            Action     = "Prepared for enablement"
            Result     = "Pending"
        })
    }

    $maxReposToShow = 10
    $repoNamesToShow = $projectRepos | Select-Object -First $maxReposToShow | ForEach-Object { $_.name }
    $repoNamesString = $repoNamesToShow -join ', '
    if ($projectRepos.Count -gt $maxReposToShow) {
        $repoNamesString += ", ...and $($projectRepos.Count - $maxReposToShow) more"
    }
    $actionDescription = "Enabling Advanced Security features for $($projectRepos.Count) repositories: $repoNamesString"
    if ($PSCmdlet.ShouldProcess("$OrgName/$projectKey", $actionDescription)) {
        # ------------ Send Enablement Request for this project ------------
        $enableUrl = "https://advsec.dev.azure.com/$OrgName/$projectKey/_apis/management/repositories/enablement?api-version=$enablementApiVersion"
    
        try {
            $body = $enablementPayload | ConvertTo-Json -Depth 5
            Invoke-RestMethod -Uri $enableUrl -Method Patch -Headers $headers -Body $body
            Write-Host "Successfully enabled Advanced Security features for all repositories in project: $projectKey"
    
            # Update report entries for this project
            foreach ($entry in $report) {
                if ($entry.Project -eq $projectKey -and $entry.Result -eq "Pending") {
                    $entry.Result = "Success"
                    $entry.Action = "Enabled"
                }
            }
        } catch {
            Write-Warning "Enablement failed for project $projectKey : $($_.Exception.Message)"
            
            # Update report entries for this project
            foreach ($entry in $report) {
                if ($entry.Project -eq $projectKey -and $entry.Result -eq "Pending") {
                    $entry.Result = "Failed: $($_.Exception.Message)"
                    $entry.Action = "Enablement"
                }
            }
        }
    }
}

# ------------ Output CSV Report ------------
$stamp = $scriptStart.ToString("yyyyMMdd-HHmmss")
$outFile = "codeql-enable-report-$stamp.csv"
$report | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
Write-Host "================ DONE ================"
Write-Host "Report written to: $outFile"