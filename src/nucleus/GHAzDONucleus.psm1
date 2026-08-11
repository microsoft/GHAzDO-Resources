Set-StrictMode -Version Latest

function Get-PropertyValue {
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string[]]$PropertyPath
    )

    $value = $InputObject
    foreach ($propertyName in $PropertyPath) {
        if ($null -eq $value) {
            return $null
        }

        $property = $value.PSObject.Properties[$propertyName]
        if ($null -eq $property) {
            return $null
        }
        $value = $property.Value
    }

    return $value
}

function ConvertTo-ConstrainedAscii {
    param(
        [AllowNull()]
        [object]$Value,

        [int]$MaximumLength = 0
    )

    if ($null -eq $Value) {
        return $null
    }

    $result = ([string]$Value) -replace '[^\x20-\x7E]', '?'
    if ($MaximumLength -gt 0 -and $result.Length -gt $MaximumLength) {
        return $result.Substring(0, $MaximumLength)
    }

    return $result
}

function Get-AdoAuthorizationHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Token,

        [ValidateSet('Bearer', 'Basic')]
        [string]$AuthenticationType = 'Bearer'
    )

    if ($AuthenticationType -eq 'Bearer') {
        return @{ Authorization = "Bearer $Token" }
    }

    $basicToken = if ($Token.Contains(':')) { $Token } else { ":$Token" }
    $encodedToken = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($basicToken))
    return @{ Authorization = "Basic $encodedToken" }
}

function Invoke-AdoApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [hashtable]$Headers
    )

    $response = Invoke-WebRequest -Uri $Uri -Headers $Headers -Method Get -SkipHttpErrorCheck
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        throw "Azure DevOps API request failed with HTTP $($response.StatusCode) for $Uri. $($response.StatusDescription)"
    }

    return $response
}

function Get-GHAzDORepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OrganizationUri,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [hashtable]$Headers,

        [scriptblock]$RequestInvoker = ${function:Invoke-AdoApiRequest}
    )

    $baseUri = $OrganizationUri.TrimEnd('/')
    $escapedProject = [Uri]::EscapeDataString($Project)
    $escapedRepository = [Uri]::EscapeDataString($Repository)
    $uri = "$baseUri/$escapedProject/_apis/git/repositories/$escapedRepository`?api-version=7.2"
    $response = & $RequestInvoker -Uri $uri -Headers $Headers
    $repositoryResponse = $response.Content | ConvertFrom-Json -Depth 20

    if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue $repositoryResponse id)) -or
        [string]::IsNullOrWhiteSpace([string](Get-PropertyValue $repositoryResponse name))) {
        throw "Azure DevOps returned incomplete repository metadata for '$Project/$Repository'."
    }

    return $repositoryResponse
}

function Get-ContinuationToken {
    param(
        [Parameter(Mandatory)]
        [object]$Response
    )

    $token = $Response.Headers['x-ms-continuationtoken']
    if ($null -eq $token) {
        return $null
    }

    if ($token -is [System.Collections.IEnumerable] -and $token -isnot [string]) {
        $token = @($token)[0]
    }

    if ([string]::IsNullOrWhiteSpace([string]$token)) {
        return $null
    }

    return [string]$token
}

function Get-GHAzDOAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Organization,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [ValidateSet('code', 'dependency', 'secret')]
        [string]$AlertType,

        [Parameter(Mandatory)]
        [hashtable]$Headers,

        [string]$Ref,

        [ValidateRange(1, 1000)]
        [int]$PageSize = 1000,

        [scriptblock]$RequestInvoker = ${function:Invoke-AdoApiRequest}
    )

    $alerts = [Collections.Generic.List[object]]::new()
    $continuationToken = $null

    do {
        $query = [Collections.Generic.List[string]]::new()
        $query.Add("top=$PageSize")
        $query.Add('criteria.states=active')
        $query.Add("criteria.alertType=$([Uri]::EscapeDataString($AlertType))")

        if ($AlertType -eq 'secret') {
            $query.Add('criteria.confidenceLevels=high')
            $query.Add('criteria.confidenceLevels=other')
        }
        elseif (-not [string]::IsNullOrWhiteSpace($Ref)) {
            $query.Add("criteria.ref=$([Uri]::EscapeDataString($Ref))")
        }

        if (-not [string]::IsNullOrWhiteSpace($continuationToken)) {
            $query.Add("continuationToken=$([Uri]::EscapeDataString($continuationToken))")
        }

        $query.Add('api-version=7.2-preview.1')
        $escapedOrganization = [Uri]::EscapeDataString($Organization)
        $escapedProject = [Uri]::EscapeDataString($Project)
        $escapedRepository = [Uri]::EscapeDataString($Repository)
        $uri = "https://advsec.dev.azure.com/$escapedOrganization/$escapedProject/_apis/alert/repositories/$escapedRepository/alerts?$($query -join '&')"
        $response = & $RequestInvoker -Uri $uri -Headers $Headers
        $body = $response.Content | ConvertFrom-Json -Depth 100

        $responseAlerts = Get-PropertyValue $body value
        if ($null -eq $responseAlerts) {
            throw "Azure DevOps returned an invalid alert response for '$Project/$Repository' ($AlertType)."
        }

        foreach ($alert in @($responseAlerts)) {
            $alerts.Add($alert)
        }

        $continuationToken = Get-ContinuationToken -Response $response
    } while ($null -ne $continuationToken)

    return $alerts.ToArray()
}

function Get-GHAzDOAlertSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Organization,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [hashtable]$Headers,

        [string]$Ref,

        [ValidateRange(1, 1000)]
        [int]$PageSize = 1000,

        [scriptblock]$RequestInvoker = ${function:Invoke-AdoApiRequest}
    )

    $alerts = [Collections.Generic.List[object]]::new()
    foreach ($alertType in @('dependency', 'code', 'secret')) {
        $typeAlerts = Get-GHAzDOAlert `
            -Organization $Organization `
            -Project $Project `
            -Repository $Repository `
            -AlertType $alertType `
            -Headers $Headers `
            -Ref $Ref `
            -PageSize $PageSize `
            -RequestInvoker $RequestInvoker

        foreach ($alert in $typeAlerts) {
            $alerts.Add($alert)
        }
    }

    return $alerts.ToArray()
}

function Get-AlertSnapshotSignature {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Alerts
    )

    $signatureInput = @(
        $Alerts |
            ForEach-Object {
                '{0}|{1}|{2}|{3}' -f
                (Get-PropertyValue $_ alertId),
                (Get-PropertyValue $_ alertType),
                (Get-PropertyValue $_ state),
                (Get-PropertyValue $_ lastSeenDate)
            } |
            Sort-Object
    ) -join "`n"

    $bytes = [Text.Encoding]::UTF8.GetBytes($signatureInput)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Wait-GHAzDOAlertSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Organization,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [hashtable]$Headers,

        [string]$Ref,

        [ValidateRange(1, 3600)]
        [int]$TimeoutSeconds = 180,

        [ValidateRange(1, 300)]
        [int]$IntervalSeconds = 15,

        [ValidateRange(1, 10)]
        [int]$StableIterations = 2,

        [ValidateRange(1, 1000)]
        [int]$PageSize = 1000,

        [scriptblock]$RequestInvoker = ${function:Invoke-AdoApiRequest}
    )

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $previousSignature = $null
    $stableCount = 0
    $latestAlerts = @()

    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $latestAlerts = @(
            Get-GHAzDOAlertSnapshot `
                -Organization $Organization `
                -Project $Project `
                -Repository $Repository `
                -Headers $Headers `
                -Ref $Ref `
                -PageSize $PageSize `
                -RequestInvoker $RequestInvoker
        )
        $signature = Get-AlertSnapshotSignature -Alerts $latestAlerts

        if ($signature -eq $previousSignature) {
            $stableCount++
        }
        else {
            $previousSignature = $signature
            $stableCount = 1
        }

        if ($stableCount -ge $StableIterations) {
            return $latestAlerts
        }

        Start-Sleep -Seconds $IntervalSeconds
    }

    throw "GHAzDO alerts did not stabilize within $TimeoutSeconds seconds for '$Project/$Repository'."
}

function ConvertTo-NucleusSeverity {
    param(
        [AllowNull()]
        [object]$Severity
    )

    switch (([string]$Severity).ToLowerInvariant()) {
        'critical' { return 'Critical' }
        'high' { return 'High' }
        'error' { return 'High' }
        'medium' { return 'Medium' }
        'warning' { return 'Medium' }
        'low' { return 'Low' }
        default { return 'Informational' }
    }
}

function Get-AlertRule {
    param(
        [Parameter(Mandatory)]
        [object]$Alert
    )

    $rules = [Collections.Generic.List[object]]::new()
    foreach ($tool in @((Get-PropertyValue $Alert tools))) {
        foreach ($rule in @((Get-PropertyValue $tool rules))) {
            $rules.Add([pscustomobject]@{
                    Tool = [string](Get-PropertyValue $tool name)
                    Rule = $rule
                })
        }
    }

    return $rules.ToArray()
}

function Get-RuleIdentifier {
    param(
        [Parameter(Mandatory)]
        [object]$Alert,

        [Parameter(Mandatory)]
        [string]$Organization
    )

    $ruleEntries = @(Get-AlertRule -Alert $Alert)
    if ($ruleEntries.Count -gt 0) {
        $entry = $ruleEntries[0]
        $opaqueId = Get-PropertyValue $entry.Rule opaqueId
        $id = Get-PropertyValue $entry.Rule id
        $friendlyName = Get-PropertyValue $entry.Rule friendlyName
        $ruleId = if (-not [string]::IsNullOrWhiteSpace([string]$opaqueId)) {
            [string]$opaqueId
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$id)) {
            [string]$id
        }
        else {
            [string]$friendlyName
        }

        if (-not [string]::IsNullOrWhiteSpace($ruleId)) {
            return ConvertTo-ConstrainedAscii `
                -Value "GHAZDO:$($Alert.alertType):$($entry.Tool):$ruleId" `
                -MaximumLength 250
        }
    }

    # Alert ID is the safest collision-free fallback, but it cannot group
    # separate instances when normalized rule metadata is unavailable.
    return ConvertTo-ConstrainedAscii `
        -Value "GHAZDO:$(Get-PropertyValue $Alert alertType):${Organization}:$(Get-PropertyValue $Alert alertId)" `
        -MaximumLength 250
}

function Get-RuleText {
    param(
        [Parameter(Mandatory)]
        [object]$Alert,

        [Parameter(Mandatory)]
        [ValidateSet('description', 'helpMessage')]
        [string]$Property
    )

    $values = @(
        Get-AlertRule -Alert $Alert |
            ForEach-Object { [string](Get-PropertyValue $_.Rule $Property) } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

    if ($values.Count -eq 0) {
        return $null
    }

    return $values -join "`n`n"
}

function Get-CveAndCweReference {
    param(
        [Parameter(Mandatory)]
        [object]$Alert
    )

    $ruleJson = @(Get-AlertRule -Alert $Alert | ForEach-Object { $_.Rule }) |
        ConvertTo-Json -Depth 30 -Compress
    $references = @(
        [regex]::Matches($ruleJson, '(?i)\b(?:CVE-\d{4}-\d{4,}|CWE-\d+)\b') |
            ForEach-Object { $_.Value.ToUpperInvariant() } |
            Select-Object -Unique
    )

    if ($references.Count -eq 0) {
        return $null
    }

    return ConvertTo-ConstrainedAscii -Value ($references -join ',') -MaximumLength 512
}

function Get-FirstPhysicalLocation {
    param(
        [Parameter(Mandatory)]
        [object]$Alert
    )

    $locations = @((Get-PropertyValue $Alert physicalLocations))
    if ($locations.Count -eq 0) {
        return $null
    }

    return $locations[0]
}

function Get-GHAzDODependencyInfo {
    param(
        [Parameter(Mandatory)]
        [object]$Alert
    )

    $locations = @((Get-PropertyValue $Alert logicalLocations))
    $component = $locations |
        Where-Object { ([string](Get-PropertyValue $_ kind)) -match '(?i)component' } |
        Select-Object -First 1
    if ($null -eq $component -and $locations.Count -gt 0) {
        $component = $locations[-1]
    }

    $ecosystem = $null
    $package = $null
    $version = $null
    if ($null -ne $component -and
        -not [string]::IsNullOrWhiteSpace([string](Get-PropertyValue $component fullyQualifiedName))) {
        $qualifiedName = [string](Get-PropertyValue $component fullyQualifiedName)
        $parts = $qualifiedName.Split(' ', 2, [StringSplitOptions]::RemoveEmptyEntries)
        if ($parts.Count -eq 2) {
            $ecosystem = $parts[0]
            $packageAndVersion = $parts[1]
        }
        else {
            $packageAndVersion = $qualifiedName
        }

        if ($packageAndVersion -match '^(?<package>.+)@(?<version>[^@]+)$') {
            $package = $Matches.package
            $version = $Matches.version
        }
        elseif ($packageAndVersion -match '^(?<package>\S+)\s+(?<version>\d\S*)$') {
            $package = $Matches.package
            $version = $Matches.version
        }
        else {
            $package = $packageAndVersion
        }
    }

    $rootDependency = $locations |
        Where-Object { ([string](Get-PropertyValue $_ kind)) -match '(?i)rootDependency' } |
        Select-Object -First 1

    return [pscustomobject]@{
        Ecosystem = ConvertTo-ConstrainedAscii -Value $ecosystem -MaximumLength 128
        Package = ConvertTo-ConstrainedAscii -Value $package -MaximumLength 256
        Version = ConvertTo-ConstrainedAscii -Value $version -MaximumLength 128
        RootDependency = ConvertTo-ConstrainedAscii `
            -Value (Get-PropertyValue $rootDependency fullyQualifiedName) `
            -MaximumLength 512
    }
}

function Add-ReferenceValue {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Specialized.OrderedDictionary]$References,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Value
    )

    if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) {
        $References[$Name] = ConvertTo-ConstrainedAscii -Value $Value
    }
}

function ConvertTo-NucleusFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Alert,

        [Parameter(Mandatory)]
        [string]$Organization
    )

    if (([string](Get-PropertyValue $Alert state)).ToLowerInvariant() -ne 'active') {
        return $null
    }

    $ruleEntries = @(Get-AlertRule -Alert $Alert)
    $toolNames = @($ruleEntries | ForEach-Object { $_.Tool } | Where-Object { $_ } | Select-Object -Unique)
    $ruleIds = @(
        $ruleEntries |
            ForEach-Object {
                $opaqueId = Get-PropertyValue $_.Rule opaqueId
                $id = Get-PropertyValue $_.Rule id
                if (-not [string]::IsNullOrWhiteSpace([string]$opaqueId)) {
                    [string]$opaqueId
                }
                elseif (-not [string]::IsNullOrWhiteSpace([string]$id)) {
                    [string]$id
                }
            } |
            Where-Object { $_ } |
            Select-Object -Unique
    )
    $categories = @(
        $ruleEntries |
            ForEach-Object {
                Get-PropertyValue $_.Rule @('additionalProperties', 'category')
            } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Select-Object -Unique
    )

    $location = Get-FirstPhysicalLocation -Alert $Alert
    $references = [ordered]@{}
    Add-ReferenceValue -References $references -Name 'GHAzDO Alert ID' -Value (Get-PropertyValue $Alert alertId)
    Add-ReferenceValue -References $references -Name 'Alert Type' -Value (Get-PropertyValue $Alert alertType)
    Add-ReferenceValue -References $references -Name 'State' -Value (Get-PropertyValue $Alert state)
    Add-ReferenceValue -References $references -Name 'Tool' -Value ($toolNames -join ',')
    Add-ReferenceValue -References $references -Name 'Rule ID' -Value ($ruleIds -join ',')
    Add-ReferenceValue -References $references -Name 'Category' -Value ($categories -join ',')
    Add-ReferenceValue -References $references -Name 'Git Ref' -Value (Get-PropertyValue $Alert gitRef)
    Add-ReferenceValue -References $references -Name 'Repository URL' -Value (Get-PropertyValue $Alert repositoryUrl)
    Add-ReferenceValue -References $references -Name 'Commit' -Value (Get-PropertyValue $location @('versionControl', 'commitHash'))
    Add-ReferenceValue -References $references -Name 'Confidence' -Value (Get-PropertyValue $Alert confidence)
    Add-ReferenceValue -References $references -Name 'Secret Validity' -Value (Get-PropertyValue $Alert @('validityDetails', 'validityStatus'))
    Add-ReferenceValue -References $references -Name 'Secret Validity Last Checked' -Value (Get-PropertyValue $Alert @('validityDetails', 'validityLastCheckedDate'))
    $repositoryUrl = Get-PropertyValue $Alert repositoryUrl
    $alertId = Get-PropertyValue $Alert alertId
    if ($null -ne $repositoryUrl -and $null -ne $alertId) {
        Add-ReferenceValue `
            -References $references `
            -Name 'Alert URL' `
            -Value "$repositoryUrl/alerts/$alertId"
    }

    $finding = [ordered]@{
        finding_type = 'Vuln'
        finding_number = Get-RuleIdentifier -Alert $Alert -Organization $Organization
        finding_name = ConvertTo-ConstrainedAscii -Value (Get-PropertyValue $Alert title) -MaximumLength 128
        finding_severity = ConvertTo-NucleusSeverity -Severity (Get-PropertyValue $Alert severity)
        finding_result = 'Failed'
        finding_references = $references
    }

    $description = Get-RuleText -Alert $Alert -Property description
    if ($null -ne $description) {
        $finding.finding_description = $description
    }

    $recommendation = Get-RuleText -Alert $Alert -Property helpMessage
    if ($null -ne $recommendation) {
        $finding.finding_recommendation = $recommendation
    }

    $cveReferences = Get-CveAndCweReference -Alert $Alert
    if ($null -ne $cveReferences) {
        $finding.finding_cve = $cveReferences
    }

    $firstSeenDate = Get-PropertyValue $Alert firstSeenDate
    if ($null -ne $firstSeenDate) {
        $finding.finding_discovered = ([datetime]$firstSeenDate).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
    }

    if ($null -ne $location) {
        $filePath = Get-PropertyValue $location filePath
        $lineStart = Get-PropertyValue $location @('region', 'lineStart')
        if (-not [string]::IsNullOrWhiteSpace([string]$filePath)) {
            $finding.finding_path = ConvertTo-ConstrainedAscii -Value $filePath -MaximumLength 4096
        }

        if ($null -ne $lineStart -and ([string]$lineStart) -match '^\d+$') {
            $finding.finding_line_number = [string]$lineStart
        }
    }

    if (([string](Get-PropertyValue $Alert alertType)).ToLowerInvariant() -eq 'dependency') {
        $dependency = Get-GHAzDODependencyInfo -Alert $Alert
        if (-not [string]::IsNullOrWhiteSpace($dependency.Package)) {
            $finding.finding_package = $dependency.Package
        }
        if (-not [string]::IsNullOrWhiteSpace($dependency.Version)) {
            $finding.finding_package_version = $dependency.Version
        }

        Add-ReferenceValue -References $references -Name 'Ecosystem' -Value $dependency.Ecosystem
        Add-ReferenceValue -References $references -Name 'Root Dependency' -Value $dependency.RootDependency

        if ($finding.Contains('finding_path') -and $finding.Contains('finding_package')) {
            $finding.finding_sub_type = 'path_package'
        }
        elseif ($finding.Contains('finding_package')) {
            $finding.finding_sub_type = 'package_only'
        }
        else {
            $finding.finding_sub_type = 'path_only'
        }
    }
    else {
        $finding.finding_sub_type = 'path_only'
    }

    return [pscustomobject]$finding
}

function Sync-FindingProperty {
    param(
        [Parameter(Mandatory)]
        [object]$Finding,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Value
    )

    $property = $Finding.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Finding | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
    else {
        $property.Value = $Value
    }
}

function Sync-NucleusUniqueFindingField {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Findings
    )

    $severityRank = @{
        Informational = 0
        Low = 1
        Medium = 2
        High = 3
        Critical = 4
    }
    $subTypeRank = @{
        path_only = 1
        package_only = 2
        path_package = 3
    }

    foreach ($group in @($Findings | Group-Object -Property finding_number)) {
        $instances = @(
            $group.Group |
                Sort-Object {
                    [string](Get-PropertyValue $_ @('finding_references', 'GHAzDO Alert ID'))
                }
        )
        $canonical = $instances[0]

        $severity = $instances |
            Sort-Object { $severityRank[[string]$_.finding_severity] } -Descending |
            Select-Object -First 1 -ExpandProperty finding_severity
        $subType = $instances |
            Where-Object { $null -ne $_.PSObject.Properties['finding_sub_type'] } |
            Sort-Object { $subTypeRank[[string]$_.finding_sub_type] } -Descending |
            Select-Object -First 1 -ExpandProperty finding_sub_type
        $cve = @(
            $instances |
                ForEach-Object {
                    [string](Get-PropertyValue $_ finding_cve) -split ','
                } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
        ) -join ','

        foreach ($instance in $instances) {
            foreach ($fieldName in @(
                    'finding_name',
                    'finding_description',
                    'finding_recommendation'
                )) {
                $value = Get-PropertyValue $canonical $fieldName
                if ($null -ne $value) {
                    Sync-FindingProperty -Finding $instance -Name $fieldName -Value $value
                }
            }

            Sync-FindingProperty -Finding $instance -Name finding_severity -Value $severity
            if (-not [string]::IsNullOrWhiteSpace([string]$subType)) {
                Sync-FindingProperty -Finding $instance -Name finding_sub_type -Value $subType
            }
            if (-not [string]::IsNullOrWhiteSpace($cve)) {
                Sync-FindingProperty `
                    -Finding $instance `
                    -Name finding_cve `
                    -Value (ConvertTo-ConstrainedAscii $cve -MaximumLength 512)
            }
        }
    }

    return $Findings
}

function ConvertTo-NucleusFlexConnect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Alerts,

        [Parameter(Mandatory)]
        [object]$Repository,

        [Parameter(Mandatory)]
        [string]$Organization,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [string]$Ref,

        [datetime]$ScanDate = (Get-Date).ToUniversalTime()
    )

    $findings = @(
        foreach ($alert in $Alerts) {
            $finding = ConvertTo-NucleusFinding -Alert $alert -Organization $Organization
            if ($null -ne $finding) {
                $finding
            }
        }
    )
    $findings = @(Sync-NucleusUniqueFindingField -Findings $findings)

    $asset = [ordered]@{
        host_name = ConvertTo-ConstrainedAscii -Value (Get-PropertyValue $Repository id)
        app_name_secondary = @(
            ConvertTo-ConstrainedAscii -Value "$Organization/$Project/$(Get-PropertyValue $Repository name)"
        )
        app_branch = ConvertTo-ConstrainedAscii -Value $Ref
        app_repo_url = ConvertTo-ConstrainedAscii -Value (Get-PropertyValue $Repository webUrl)
        asset_info = [ordered]@{
            'azuredevops.organization' = ConvertTo-ConstrainedAscii -Value $Organization
            'azuredevops.project' = ConvertTo-ConstrainedAscii -Value $Project
            'azuredevops.repository-id' = ConvertTo-ConstrainedAscii -Value (Get-PropertyValue $Repository id)
            'azuredevops.repository-name' = ConvertTo-ConstrainedAscii -Value (Get-PropertyValue $Repository name)
        }
        findings = $findings
    }

    return [pscustomobject][ordered]@{
        nucleus_import_version = '1'
        scan_tool = 'GHAZDO'
        scan_type = 'Application'
        scan_date = $ScanDate.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss +00:00')
        assets = @([pscustomobject]$asset)
    }
}

function Test-GHAzDODefaultBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrentRef,

        [Parameter(Mandatory)]
        [object]$Repository
    )

    $defaultBranch = [string](Get-PropertyValue $Repository defaultBranch)
    if ([string]::IsNullOrWhiteSpace($defaultBranch)) {
        throw 'The Azure DevOps repository response did not include a defaultBranch value.'
    }

    return $CurrentRef -eq $defaultBranch
}

function Write-NucleusFlexConnect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$FlexConnect,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        $null = New-Item -Path $directory -ItemType Directory -Force
    }

    $FlexConnect |
        ConvertTo-Json -Depth 100 |
        Set-Content -Path $Path -Encoding utf8NoBOM

    return (Resolve-Path -Path $Path).Path
}

function Send-NucleusScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$NucleusBaseUrl,

        [Parameter(Mandatory)]
        [string]$NucleusProjectId,

        [Parameter(Mandatory)]
        [string]$ApiKey,

        [Parameter(Mandatory)]
        [string]$Path,

        [scriptblock]$UploadInvoker = {
            param($Uri, $Headers, $Form)
            Invoke-WebRequest `
                -Uri $Uri `
                -Method Post `
                -Headers $Headers `
                -Form $Form `
                -SkipHttpErrorCheck
        }
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "The FlexConnect file '$Path' does not exist."
    }

    $endpoint = '{0}/api/projects/{1}/scans' -f
        $NucleusBaseUrl.TrimEnd('/'),
        [Uri]::EscapeDataString($NucleusProjectId)
    $headers = @{ 'x-apikey' = $ApiKey }
    $form = @{ file = Get-Item -Path $Path }
    $response = & $UploadInvoker -Uri $endpoint -Headers $headers -Form $form

    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        throw "Nucleus scan upload failed with HTTP $($response.StatusCode). $($response.StatusDescription)"
    }

    return $response
}

Export-ModuleMember -Function @(
    'ConvertTo-NucleusFinding',
    'ConvertTo-NucleusFlexConnect',
    'Get-GHAzDOAlert',
    'Get-GHAzDOAlertSnapshot',
    'Get-GHAzDORepository',
    'Get-AdoAuthorizationHeader',
    'Send-NucleusScan',
    'Test-GHAzDODefaultBranch',
    'Wait-GHAzDOAlertSnapshot',
    'Write-NucleusFlexConnect'
)
