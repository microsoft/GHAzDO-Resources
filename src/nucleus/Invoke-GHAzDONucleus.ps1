<#
.SYNOPSIS
    Exports GHAzDO alerts to Nucleus through a FlexConnect scan.
.DESCRIPTION
    Retrieves a complete active snapshot of code, dependency, and secret alerts
    for one Azure DevOps repository, converts the alerts to FlexConnect JSON,
    and optionally uploads the file to a Nucleus project.
.PARAMETER AdoToken
    Azure DevOps OAuth token or PAT. Defaults to SYSTEM_ACCESSTOKEN, then
    MAPPED_ADO_PAT.
.PARAMETER AdoAuthenticationType
    Bearer for System.AccessToken or Basic for a PAT.
.PARAMETER DryRun
    Generates the FlexConnect file without uploading it to Nucleus.
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
    [string]$Ref = $env:BUILD_SOURCEBRANCH,
    [string]$AdoToken,
    [ValidateSet('Bearer', 'Basic')]
    [string]$AdoAuthenticationType,
    [string]$NucleusBaseUrl = $env:NUCLEUS_BASE_URL,
    [string]$NucleusProjectId = $env:NUCLEUS_PROJECT_ID,
    [string]$NucleusApiKey = $env:NUCLEUS_API_KEY,
    [string]$OutputPath,
    [ValidateRange(1, 3600)]
    [int]$WaitTimeoutSeconds = 180,
    [ValidateRange(1, 300)]
    [int]$WaitIntervalSeconds = 15,
    [ValidateRange(1, 10)]
    [int]$StableIterations = 2,
    [ValidateRange(1, 1000)]
    [int]$PageSize = 1000,
    [switch]$DryRun,
    [switch]$PublishArtifact
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'GHAzDONucleus.psm1') -Force

if ([string]::IsNullOrWhiteSpace($AdoToken)) {
    if (-not [string]::IsNullOrWhiteSpace($env:SYSTEM_ACCESSTOKEN)) {
        $AdoToken = $env:SYSTEM_ACCESSTOKEN
        $AdoAuthenticationType = 'Bearer'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:MAPPED_ADO_PAT)) {
        $AdoToken = $env:MAPPED_ADO_PAT
        $AdoAuthenticationType = 'Basic'
    }
}

if ([string]::IsNullOrWhiteSpace($AdoAuthenticationType)) {
    $AdoAuthenticationType = 'Bearer'
}

foreach ($requiredValue in @{
        OrganizationUri = $OrganizationUri
        Project = $Project
        Repository = $Repository
        Ref = $Ref
        AdoToken = $AdoToken
    }.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace([string]$requiredValue.Value)) {
        throw "The $($requiredValue.Key) value is required."
    }
}

if (-not $DryRun) {
    foreach ($requiredValue in @{
            NucleusBaseUrl = $NucleusBaseUrl
            NucleusProjectId = $NucleusProjectId
            NucleusApiKey = $NucleusApiKey
        }.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$requiredValue.Value)) {
            throw "The $($requiredValue.Key) value is required unless -DryRun is used."
        }
    }
}

$organizationMatch = [regex]::Match(
    $OrganizationUri,
    '^https://dev\.azure\.com/(?<organization>[^/]+)/?$',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
if (-not $organizationMatch.Success) {
    throw "OrganizationUri must use the Azure DevOps Services format 'https://dev.azure.com/{organization}'."
}
$organization = $organizationMatch.Groups['organization'].Value
$headers = Get-AdoAuthorizationHeader `
    -Token $AdoToken `
    -AuthenticationType $AdoAuthenticationType
$repositoryMetadata = Get-GHAzDORepository `
    -OrganizationUri $OrganizationUri `
    -Project $Project `
    -Repository $Repository `
    -Headers $headers

Write-Host "Waiting for the active GHAzDO alert snapshot to stabilize for $Project/$Repository..."
$alerts = @(
    Wait-GHAzDOAlertSnapshot `
        -Organization $organization `
        -Project $Project `
        -Repository $repositoryMetadata.id `
        -Headers $headers `
        -Ref $Ref `
        -TimeoutSeconds $WaitTimeoutSeconds `
        -IntervalSeconds $WaitIntervalSeconds `
        -StableIterations $StableIterations `
        -PageSize $PageSize
)

$defaultBranch = [string]$repositoryMetadata.defaultBranch
if ($Ref -ne $defaultBranch) {
    $secretCount = @($alerts | Where-Object alertType -eq 'secret').Count
    if ($secretCount -gt 0) {
        Write-Warning (
            "Omitting $secretCount repository-level secret alerts from the non-default branch asset '$Ref'. " +
            "Secret alerts are exported with the default branch to avoid duplicating them across branch assets."
        )
        $alerts = @($alerts | Where-Object alertType -ne 'secret')
    }
}

$codeCount = @($alerts | Where-Object alertType -eq 'code').Count
$dependencyCount = @($alerts | Where-Object alertType -eq 'dependency').Count
$secretCount = @($alerts | Where-Object alertType -eq 'secret').Count
Write-Host (
    'Collected {0} active alerts (code: {1}, dependency: {2}, secret: {3}).' -f
    $alerts.Count,
    $codeCount,
    $dependencyCount,
    $secretCount
)

$flexConnect = ConvertTo-NucleusFlexConnect `
    -Alerts $alerts `
    -Repository $repositoryMetadata `
    -Organization $organization `
    -Project $Project `
    -Ref $Ref

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputDirectory = if (-not [string]::IsNullOrWhiteSpace($env:BUILD_ARTIFACTSTAGINGDIRECTORY)) {
        $env:BUILD_ARTIFACTSTAGINGDIRECTORY
    }
    else {
        $PWD.Path
    }
    $safeRepositoryName = $repositoryMetadata.name -replace '[^\w.-]', '-'
    $OutputPath = Join-Path $outputDirectory "ghazdo-nucleus-$safeRepositoryName.json"
}

$resolvedOutputPath = Write-NucleusFlexConnect -FlexConnect $flexConnect -Path $OutputPath
Write-Host "Generated FlexConnect scan at $resolvedOutputPath."

if ($PublishArtifact -and $env:TF_BUILD -eq 'True') {
    Write-Host "##vso[artifact.upload artifactname=NucleusFlexConnect]$resolvedOutputPath"
}

if ($DryRun) {
    Write-Host 'Dry run complete; the scan was not uploaded to Nucleus.'
    return
}

$null = Send-NucleusScan `
    -NucleusBaseUrl $NucleusBaseUrl `
    -NucleusProjectId $NucleusProjectId `
    -ApiKey $NucleusApiKey `
    -Path $resolvedOutputPath
Write-Host 'Nucleus accepted the FlexConnect scan upload.'
