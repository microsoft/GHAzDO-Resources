<#PSScriptInfo

.VERSION 0.2

.GUID 85f6e4ed-0aea-4472-93d6-d62579127c4e

.AUTHOR nicour@microsoft.com

.COMPANYNAME Microsoft Corporation

.COPYRIGHT 2023 Microsoft Corporation. All rights reserved.

.LICENSEURI ./LICENSE.txt

.REQUIREDMODULES ./Setup_Common.psm1

.RELEASENOTES
#>

<#
.SYNOPSIS
Sets up CodeQL PRs for all Repositories in a given ADO Project
.DESCRIPTION
This Script is designed to raise PRs to add GitHub Advanced Security tasks to all Repositories in a given ADO Project. The script will also create a pipeline to run the CodeQL task on commits to the default branch.

YAML files are added on a well known branch and PR'd against main, then the Pipeline is run to create an initial bootstrap/baseline of results for a repository.

.PARAMETER OrganizationName
The Azure DevOps Organization that we will work against

.PARAMETER ProjectName
The specific Project in that Organization that we will work against

.PARAMETER ADOPat
An ADO PAT that has permissions to create PRs and Pipelines in the given Project. Specific scopes for this PAT have not been determined, though it works with a full-scope PAT.

.PARAMETER RepoId
Optional single-repo parameter that allows for a more targeted setup.

.EXAMPLE
PS C:\> .\Setup_CodeQL_PRs.ps1 -OrganizationName 'MyOrg' -ProjectName 'MyProject' -ADOPat 'ADOPAT'

#>

# Setup Our Parameters
[CmdletBinding()]
Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string]$OrganizationName,

   [Parameter(Mandatory=$True,Position=2)]
   [string]$ProjectName,

   [Parameter(Mandatory=$True,Position=3)]
   [string]$ADOPat,

   [Parameter(Mandatory=$False,Position=4)]
   [string]$RepoId
)

# Import our Common Functions
# -Force so we always get the latest
Import-Module ./Common.psm1 -Force

# Setup Constants
$Headers = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($ADOPat)")) }
$Folder = "GHAzDO-YAML"

$ProjectId = getProjectId $OrganizationName $ProjectName -AuthHeader $Headers
$ids = getExistingPipelines $OrganizationName $ProjectId $Folder $Headers
ensureFolder $OrganizationName $ProjectId $Folder $Headers
$RepoLanguage = getProjectLanguageMetrics $OrganizationName $ProjectId $Headers
foreach ($repo in $RepoLanguage) {
    if ($PSBoundParameters.ContainsKey('RepoId') -ne $True -or $repo.id -eq $RepoId){
        $languages = @()
        foreach($lang in $repo.languageBreakDown) {
            switch -regex ($lang.name){
                "Python" {$languages += "python"}
                "Ruby" {$languages += "ruby"}
                "JavaScript|TypeScript" {$languages += "javascript"}
                "Go|Golang" {$languages += "go"}
                default {}
            }
        }
        if ($languages.Length -gt 0){
            $distinct = $languages | sort-object | get-unique
            $langstring = $distinct -join ","
            $repository = getRepository $OrganizationName $ProjectId $repo.id $Headers
            if ($ids.ContainsKey($repository.id)){
                Write-Verbose "Updating YAML for $($repo.name)"
                updateYaml $OrganizationName $ProjectId $repository $langstring $Headers
            }
            else {
                Write-Verbose "Creating Build Definition PR for $($repo.name)"
                createYaml $OrganizationName $ProjectId $repository.id $langstring $repository.defaultBranch $Headers
                createPullRequest $OrganizationName $ProjectId $repository.id $repository.defaultBranch $Headers
                $pipelineId = createYamlPipeline $OrganizationName $ProjectId $repository.id $Folder $Headers
                execPipeline $OrganizationName $ProjectId $pipelineId $Headers
            }
        }
    }
    Else {
        Write-Verbose "Skipping Repository $($repo.name)"
    }
}