<#PSScriptInfo

.VERSION 0.2

.GUID 75b3910b-1973-4926-8185-244efff75312

.AUTHOR nicour@microsoft.com

.COMPANYNAME Microsoft Corporation

.COPYRIGHT 2023 Microsoft Corporation. All rights reserved.

.LICENSEURI ./LICENSE.txt

.REQUIREDMODULES ./Setup_Common.psm1

.RELEASENOTES
#>

<#
.SYNOPSIS
Sets up CodeQL Classic Pipelines for all Repositories in a given ADO Project

.DESCRIPTION
This Script is designed to create Classic Pipelines to tun GitHub Advanced Security tasks against all Repositories in a given ADO Project. The pipeline will also set a trigger to run the CodeQL tasks against new commits to the default branch.

.PARAMETER OrganizationName
The Azure DevOps Organization that we will work against

.PARAMETER ProjectName
The specific Project in that Organization that we will work against

.PARAMETER ADOPat
An ADO PAT that has permissions to create PRs and Pipelines in the given Project. Specific scopes for this PAT have not been determined, though it works with a full-scope PAT.

.EXAMPLE
PS C:\> .\Setup_CodeQL_Classic.ps1 -OrganizationName 'MyOrg' -ProjectName 'MyProject' -ADOPat 'ADOPAT'

#>

# Setup Our Parameters
[CmdletBinding()]
Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string]$OrganizationName,
   [Parameter(Mandatory=$True,Position=2)]
   [string]$ProjectName,
   [Parameter(Mandatory=$True,Position=3)]
   [string]$ADOPat
)

# Import our Common Functions
# -Force so we always get the latest
Import-Module ./Common.psm1 -Force

# Set up our constants
$Headers = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($ADOPat)")) }
$Folder = "GHAzDO-Classic"

$ProjectId = getProjectId $OrganizationName $ProjectName -AuthHeader $Headers
$ids = getExistingPipelines $OrganizationName $ProjectId $Folder $Headers
ensureFolder $OrganizationName $ProjectId $Folder $Headers
$RepoLanguage = getProjectLanguageMetrics $OrganizationName $ProjectId $Headers
foreach ($repo in $RepoLanguage) {
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
            updatePipeline $ids[$repository.id] "$langstring" $repository.defaultBranch $Headers
        }
        else {
            createBuildDefinition $OrganizationName $ProjectId $repository.id $langstring $repository.defaultBranch $Folder $Headers
        }
    }
}