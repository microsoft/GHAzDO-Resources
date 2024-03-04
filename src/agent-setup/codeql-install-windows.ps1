################################################################################
##  File:  CodeQL-Install-Windows.ps1
##  Desc:  Install the CodeQL CLI Bundles.
##         Borrowed from: https://github.com/actions/runner-images
################################################################################

function Get-DownloadWithRetry {
    Param
    (
        [Parameter(Mandatory)]
        [string] $Url,
        [string] $Name,
        [string] $DownloadPath = "${env:Temp}",
        [int] $Retries = 20
    )

    if ([String]::IsNullOrEmpty($Name)) {
        $Name = [IO.Path]::GetFileName($Url)
    }

    $filePath = Join-Path -Path $DownloadPath -ChildPath $Name
    $downloadStartTime = Get-Date

    # Default retry logic for the package.
    while ($Retries -gt 0)
    {
        try
        {
            $downloadAttemptStartTime = Get-Date
            Write-Host "Downloading package from: $Url to path $filePath ."
            (New-Object System.Net.WebClient).DownloadFile($Url, $filePath)
            break
        }
        catch
        {
            $failTime = [math]::Round(($(Get-Date) - $downloadStartTime).TotalSeconds, 2)
            $attemptTime = [math]::Round(($(Get-Date) - $downloadAttemptStartTime).TotalSeconds, 2)
            Write-Host "There is an error encounterd after $attemptTime seconds during package downloading:`n $_"
            $Retries--

            if ($Retries -eq 0)
            {
                Write-Host "File can't be downloaded. Please try later or check that file exists by url: $Url"
                Write-Host "Total time elapsed $failTime"
                exit 1
            }

            Write-Host "Waiting 30 seconds before retrying. Retries left: $Retries"
            Start-Sleep -Seconds 30
        }
    }

    $downloadCompleteTime = [math]::Round(($(Get-Date) - $downloadStartTime).TotalSeconds, 2)
    Write-Host "Package downloaded successfully in $downloadCompleteTime seconds"
    return $filePath
}


# Retrieve the name of the CodeQL bundle preferred by the Action (in the format codeql-bundle-YYYYMMDD).
$Defaults = (Invoke-RestMethod "https://raw.githubusercontent.com/github/codeql-action/v2/src/defaults.json")
$CodeQLTagName = $Defaults.bundleVersion
$CodeQLCliVersion = $Defaults.cliVersion
$PriorCodeQLTagName = $Defaults.priorBundleVersion
$PriorCodeQLCliVersion = $Defaults.priorCliVersion

# Convert the tag names to bundles with a version number (x.y.z-YYYYMMDD).
$CodeQLBundleVersion = $CodeQLCliVersion + "-" + $CodeQLTagName.split("-")[-1]
$PriorCodeQLBundleVersion = $PriorCodeQLCliVersion + "-" + $PriorCodeQLTagName.split("-")[-1]

$Bundles = @(
    [PSCustomObject]@{
        TagName=$CodeQLTagName;
        BundleVersion=$CodeQLBundleVersion;
    },
    [PSCustomObject]@{
        TagName=$PriorCodeQLTagName;
        BundleVersion=$PriorCodeQLBundleVersion;
    }
)

foreach ($Bundle in $Bundles) {
    Write-Host "Downloading CodeQL bundle $($Bundle.BundleVersion)..."
    $CodeQLBundlePath = Get-DownloadWithRetry -Url "https://github.com/github/codeql-action/releases/download/$($Bundle.TagName)/codeql-bundle.tar.gz" -Name "codeql-bundle.tar.gz"
    $DownloadDirectoryPath = (Get-Item $CodeQLBundlePath).Directory.FullName

    $CodeQLToolcachePath = Join-Path $Env:AGENT_TOOLSDIRECTORY -ChildPath "CodeQL" | Join-Path -ChildPath $Bundle.BundleVersion | Join-Path -ChildPath "x64"
    New-Item -Path $CodeQLToolcachePath -ItemType Directory -Force | Out-Null

    Write-Host "Unpacking the downloaded CodeQL bundle archive..."
    tar -xzf $CodeQLBundlePath -C $CodeQLToolcachePath

    # We only pin the latest version in the toolcache, to support overriding the CodeQL version specified in defaults.json on GitHub Enterprise.
    if ($Bundle.BundleVersion -eq $CodeQLBundleVersion) {
        New-Item -ItemType file (Join-Path $CodeQLToolcachePath -ChildPath "pinned-version")
    }

    # Touch a file to indicate to the toolcache that setting up CodeQL is complete.
    New-Item -ItemType file "$CodeQLToolcachePath.complete"
}
