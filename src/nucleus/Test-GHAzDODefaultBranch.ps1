<#
.SYNOPSIS
    Emits an Azure Pipelines variable indicating whether the current build is
    running on the repository default branch.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Justification = 'Azure Pipelines logging commands require host output.'
)]
[CmdletBinding()]
param(
    [string]$OrganizationUri = $env:SYSTEM_COLLECTIONURI,
    [string]$Project = $env:SYSTEM_TEAMPROJECT,
    [string]$Repository = $env:BUILD_REPOSITORY_NAME,
    [string]$CurrentRef = $env:BUILD_SOURCEBRANCH,
    [string]$AdoToken = $env:SYSTEM_ACCESSTOKEN,
    [ValidateSet('Bearer', 'Basic')]
    [string]$AdoAuthenticationType = 'Bearer',
    [string]$VariableName = 'RunNucleusIngestion'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'GHAzDONucleus.psm1') -Force

foreach ($requiredValue in @{
        OrganizationUri = $OrganizationUri
        Project = $Project
        Repository = $Repository
        CurrentRef = $CurrentRef
        AdoToken = $AdoToken
    }.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace([string]$requiredValue.Value)) {
        throw "The $($requiredValue.Key) value is required."
    }
}

$headers = Get-AdoAuthorizationHeader `
    -Token $AdoToken `
    -AuthenticationType $AdoAuthenticationType
$repositoryMetadata = Get-GHAzDORepository `
    -OrganizationUri $OrganizationUri `
    -Project $Project `
    -Repository $Repository `
    -Headers $headers
$isDefaultBranch = Test-GHAzDODefaultBranch `
    -CurrentRef $CurrentRef `
    -Repository $repositoryMetadata
$variableValue = $isDefaultBranch.ToString().ToLowerInvariant()

Write-Host "Current ref: $CurrentRef; default ref: $($repositoryMetadata.defaultBranch)."
if ($env:TF_BUILD -eq 'True') {
    Write-Host "##vso[task.setvariable variable=$VariableName]$variableValue"
}

return $isDefaultBranch
