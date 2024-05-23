################################################################################
##  File:  CodeQL-Install-Windows.ps1
##  Desc:  Install the CodeQL CLI Bundles.
##         Borrowed from: https://github.com/actions/runner-images
################################################################################
param(
    <#
    .PARAMETER UseNightlies
    Specifies whether to use nightly builds.  These are pulled from the dsp-testing/codeql-cli-nightlies repository and are highly experimental.
    #>
    [bool]$UseNightlies = $false
)


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

# Nightly builds for testing new alpha feature pre-releases
if ($UseNightlies) {
    Write-Host "Using CodeQL CLI Nightly Release..."

    # Get the latest release from the repository
    $nightlyReleases = Invoke-RestMethod -Uri "https://api.github.com/repos/dsp-testing/codeql-cli-nightlies/releases"
    $latestRelease = $nightlyReleases[0]

    #Get the version number out of the name string like: "CodeQL Bundle and CLI v2.17.4+202405212055" is 2.17.4
    $version = $latestRelease.name -replace ".*CodeQL Bundle and CLI v|(\+.*$)"

    # Download the CodeQL CLI bundle from the Nightly release (no need to grab the large bundle - just windows in the windows script)
    Write-Host "Downloading CodeQL bundle $($latestRelease.name)..."
    $CodeQLBundlePath = Get-DownloadWithRetry -Url "https://github.com/dsp-testing/codeql-cli-nightlies/releases/download/$($latestRelease.tag_name)/codeql-bundle-win64.tar.gz" -Name "codeql-bundle-win64.tar.gz"

    #[2024-04-26 08:59:52] Using index-files script C:\agent\_work\_tool\CodeQL\0.0.0-codeql-bundle-v2.16.5\x64\codeql\xml\tools\index-files.cmd.
    #$Env:AGENT_TOOLSDIRECTORY = "C:\temp"

    $CodeQLToolcachePath = Join-Path $Env:AGENT_TOOLSDIRECTORY -ChildPath "CodeQL" | Join-Path -ChildPath $Bundle.BundleVersion | Join-Path -ChildPath "$version/x64"
    New-Item -Path $CodeQLToolcachePath -ItemType Directory -Force | Out-Null

    Write-Host "Unpacking the downloaded CodeQL bundle archive to $CodeQLToolcachePath ..."
    tar -xzf $CodeQLBundlePath -C $CodeQLToolcachePath

    # We only pin the latest version in the toolcache, to support overriding the CodeQL version specified in defaults.json on GitHub Enterprise.
    New-Item -ItemType file (Join-Path $CodeQLToolcachePath -ChildPath "pinned-version")


    # Touch a file to indicate to the toolcache that setting up CodeQL is complete.
    New-Item -ItemType file "$CodeQLToolcachePath.complete"
}
else {

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

}