<#PSScriptInfo

.VERSION 0.2

.GUID 75b3910b-1973-4926-8185-244efff75312

.AUTHOR nicour@microsoft.com

.COMPANYNAME Microsoft Corporation

.COPYRIGHT 2023 Microsoft Corporation. All rights reserved.

.LICENSEURI ./LICENSE.txt

.REQUIREDMODULES ./Common.psm1

.RELEASENOTES
#>

<#
.SYNOPSIS
Sets up CodeQL Classic Pipelines for all Repositories in a given ADO Project

.DESCRIPTION

.PARAMETER OrganizationName
The Azure DevOps Organization that we will work against

.PARAMETER ProjectName
The specific Project in that Organization that we will work against

.PARAMETER ADOPat
An ADO PAT that has permissions. Specific scopes for this PAT have not been determined, though it works with a full-scope PAT.

.PARAMETER EnablePushProtection
Boolean to enable or disable the Push Protection setting. Defaults to $true

.PARAMETER RepositoryList
A list of Repositories to enable GHAS on. If not specified, all Repositories will be enabled

.EXAMPLE
PS C:\> .\Enable-GHAS.ps1 -OrganizationName 'MyOrg' -ProjectName 'MyProject' -ADOPat 'ADOPAT'

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
   [Parameter(Mandatory=$false,Position=4)]
   [bool]$EnablePushProtection = $true,
   [Parameter(Mandatory=$false,Position=5)]
   [string]$RepositoryList
)

# Import our Common Functions
# -Force so we always get the latest
Import-Module ./Common.psm1 -Force

# Set up our constants
$Headers = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($ADOPat)")) }

$ProjectId = getProjectId $OrganizationName $ProjectName -AuthHeader $Headers
$Repositories = getRepositories $OrganizationName $ProjectId -AuthHeader $Headers
if ($Repositories.count -gt 2000){
    Throw "This script does not support more than 2000 Repositories. Please use the RepositoryList parameter to specify a subset of Repositories"
}
foreach ($repo in $Repositories.value) {
    if ($RepositoryList -and ($RepositoryList -notcontains $repo.name)) {
        Write-Verbose "Skipping $($repo.name) as it is not in the list of Repositories to enable"
        continue
    }

    $enabled = Get-GHASEnablement -OrganizationName $OrganizationName -ProjectId $ProjectId -Repository $repo -AuthHeader $Headers

    if ($enabled -eq $true) {
        Write-Verbose "GHAS is already enabled for $($repo.name)"
        continue
    }
    else {
        Write-Verbose "Enabling GHAS for $($repo.name)"
        Enable-GHAzDO -OrganizationName $OrganizationName -ProjectId $ProjectId -Repository $repo -EnablePushProtection $EnablePushProtection -AuthHeader $Headers
        Start-Sleep 1
    }
}