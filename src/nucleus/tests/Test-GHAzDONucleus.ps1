[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseSingularNouns',
    '',
    Justification = 'Test assertion and fixture helper names read naturally in plural form.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingPositionalParameters',
    '',
    Justification = 'Concise assertions keep the test cases readable.'
)]
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\GHAzDONucleus.psm1'
Import-Module $modulePath -Force

$script:TestCount = 0

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Actual,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Expected,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $script:TestCount++
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', received '$Actual'."
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $script:TestCount++
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $script:TestCount++
    try {
        & $Action
    }
    catch {
        return
    }

    throw $Message
}

function Read-FixtureAlerts {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $fixturePath = Join-Path $PSScriptRoot "fixtures\$Name"
    return @((Get-Content -Path $fixturePath -Raw | ConvertFrom-Json -Depth 100).value)
}

$repository = [pscustomobject]@{
    id = '11111111-2222-3333-4444-555555555555'
    name = 'payments'
    webUrl = 'https://dev.azure.com/contoso/security/_git/payments'
    defaultBranch = 'refs/heads/main'
}
$alerts = @(
    Read-FixtureAlerts 'codeql-alerts.json'
    Read-FixtureAlerts 'dependency-alerts.json'
    Read-FixtureAlerts 'secret-alerts.json'
    Read-FixtureAlerts 'third-party-alerts.json'
)
$duplicateThirdParty = (
    (Read-FixtureAlerts 'third-party-alerts.json')[0] |
        ConvertTo-Json -Depth 100 |
        ConvertFrom-Json -Depth 100
)
$duplicateThirdParty.alertId = 402
$duplicateThirdParty.severity = 'low'
$alerts += $duplicateThirdParty

$scan = ConvertTo-NucleusFlexConnect `
    -Alerts $alerts `
    -Repository $repository `
    -Organization 'contoso' `
    -Project 'security' `
    -Ref 'refs/heads/main' `
    -ScanDate ([datetime]'2026-08-10T14:00:00Z')

Assert-Equal $scan.scan_tool 'GHAZDO' 'The scan source must remain stable.'
Assert-Equal $scan.scan_type 'Application' 'The scan must create Application assets.'
Assert-Equal $scan.assets.Count 1 'The scan should contain one repository asset.'
Assert-Equal $scan.assets[0].host_name $repository.id 'The stable repository ID should identify the asset.'
Assert-Equal $scan.assets[0].findings.Count 5 'Only active alerts should become findings.'

$codeFinding = $scan.assets[0].findings |
    Where-Object { $_.finding_references['GHAzDO Alert ID'] -eq '101' }
Assert-Equal $codeFinding.finding_number 'GHAZDO:code:CodeQL:cs/sql-injection' 'CodeQL rules should correlate by tool and rule.'
Assert-Equal $codeFinding.finding_path 'src/Database.cs' 'Code paths should be preserved.'
Assert-Equal $codeFinding.finding_line_number '42' 'Code line numbers should be preserved.'
Assert-True ($codeFinding.finding_cve -match 'CWE-089') 'CWE references should be extracted.'

$dependencyFinding = $scan.assets[0].findings |
    Where-Object { $_.finding_references['GHAzDO Alert ID'] -eq '201' }
Assert-Equal $dependencyFinding.finding_package 'Newtonsoft.Json' 'Dependency package names should be parsed.'
Assert-Equal $dependencyFinding.finding_package_version '12.0.1' 'Dependency package versions should be parsed.'
Assert-Equal $dependencyFinding.finding_sub_type 'path_package' 'Dependency findings should expose path and package columns.'
Assert-True ($dependencyFinding.finding_cve -match 'CVE-2024-21907') 'Dependency CVEs should be extracted.'

$thirdPartyFindings = @($scan.assets[0].findings |
    Where-Object { $_.finding_number -eq 'GHAZDO:code:ThirdPartyIaC:iac/public-storage' })
$thirdPartyFinding = $thirdPartyFindings |
    Where-Object { $_.finding_references['GHAzDO Alert ID'] -eq '401' }
Assert-Equal $thirdPartyFinding.finding_number 'GHAZDO:code:ThirdPartyIaC:iac/public-storage' 'Third-party code alerts should use normalized tool/rule identity.'
Assert-Equal $thirdPartyFinding.finding_severity 'Medium' 'SARIF warning severity should map to Medium.'
Assert-Equal $thirdPartyFinding.finding_references.Category 'iac' 'Third-party SARIF categories should be retained.'
Assert-True (
    @($thirdPartyFindings | Where-Object finding_severity -ne 'Medium').Count -eq 0
) 'Unique finding severity should be normalized to the highest instance severity.'

$json = $scan | ConvertTo-Json -Depth 100
Assert-True (-not $json.Contains('DO-NOT-EXPORT-TRUNCATED-SECRET')) 'Truncated secrets must not be exported.'
Assert-True (-not $json.Contains('DO-NOT-EXPORT-VALIDATION-FINGERPRINT')) 'Validation fingerprints must not be exported.'

Assert-True (
    Test-GHAzDODefaultBranch -CurrentRef 'refs/heads/main' -Repository $repository
) 'The default branch helper should recognize the default branch.'
Assert-True (
    -not (Test-GHAzDODefaultBranch -CurrentRef 'refs/heads/feature' -Repository $repository)
) 'The default branch helper should reject a different branch.'

$script:RequestUris = [Collections.Generic.List[string]]::new()
$script:RequestNumber = 0
$requestInvoker = {
    param($Uri, $Headers)
    $null = $Headers
    $script:RequestUris.Add($Uri)
    $script:RequestNumber++
    if ($script:RequestNumber -eq 1) {
        return [pscustomobject]@{
            StatusCode = 200
            Headers = @{ 'x-ms-continuationtoken' = 'next token/1' }
            Content = '{"count":1,"value":[{"alertId":1}]}'
        }
    }

    return [pscustomobject]@{
        StatusCode = 200
        Headers = @{}
        Content = '{"count":1,"value":[{"alertId":2}]}'
    }
}

$pagedAlerts = @(
    Get-GHAzDOAlert `
        -Organization 'contoso' `
        -Project 'security' `
        -Repository $repository.id `
        -AlertType secret `
        -Headers @{ Authorization = 'test' } `
        -RequestInvoker $requestInvoker
)
Assert-Equal $pagedAlerts.Count 2 'Pagination should retrieve every page.'
Assert-True ($script:RequestUris[1] -match 'continuationToken=next%20token%2F1') 'Continuation tokens must be encoded.'
Assert-True ($script:RequestUris[0] -match 'criteria\.confidenceLevels=high') 'High-confidence secrets should be requested.'
Assert-True ($script:RequestUris[0] -match 'criteria\.confidenceLevels=other') 'Other-confidence secrets should be requested.'
Assert-True (-not ($script:RequestUris[0] -match 'ValidationFingerprint')) 'Secret validation fingerprints must never be requested.'

$tempFile = Join-Path ([IO.Path]::GetTempPath()) "ghazdo-nucleus-test-$([guid]::NewGuid()).json"
try {
    Set-Content -Path $tempFile -Value '{}' -Encoding utf8NoBOM
    Assert-Throws -Message 'Nucleus upload failures must propagate.' -Action {
        Send-NucleusScan `
            -NucleusBaseUrl 'https://example.invalid/nucleus' `
            -NucleusProjectId '1' `
            -ApiKey 'not-a-real-key' `
            -Path $tempFile `
            -UploadInvoker {
                param($Uri, $Headers, $Form)
                $null = $Uri, $Headers, $Form
                [pscustomobject]@{
                    StatusCode = 500
                    StatusDescription = 'Test failure'
                }
            }
    }
}
finally {
    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
}

Write-Output "Passed $script:TestCount GHAzDO Nucleus integration assertions."
