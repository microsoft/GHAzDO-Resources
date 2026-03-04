# Handling CodeQL Exit Code 32 in Azure DevOps (GHAzDO)

## Background

CodeQL exit code 32 indicates that the database finalization completed but **no analyzable source code was found**. This can happen when:

- Source files are commented out or empty
- A language is initialized but no applicable source exists in the repository
- Build steps produce no compiled output for traced languages

In centralized pipelines that serve many repositories, this is often expected behavior rather than a true failure. However, the `AdvancedSecurity-Codeql-Analyze` task treats all non-zero exit codes as fatal, causing the pipeline to fail.

Since the task does not currently expose a configuration option to treat exit code 32 as non-fatal, the workaround below uses `continueOnError` combined with a post-analysis validation step that inspects the CodeQL finalize logs.

---

## Single Language Pipeline

**Use this approach when your pipeline scans exactly one language.**

The validation script checks the finalize log for the single language and either suppresses exit code 32 or fails the pipeline for any other error.

```yaml
pool:
  vmImage: ubuntu-latest

steps:
  - task: AdvancedSecurity-Codeql-Init@1
    inputs:
      languages: 'javascript'

  # Your build steps here (if applicable)

  - task: AdvancedSecurity-Codeql-Analyze@1
    continueOnError: true
    displayName: 'Run CodeQL Analysis'

  - task: PowerShell@2
    displayName: 'Validate CodeQL exit code'
    inputs:
      targetType: 'inline'
      script: |
        if ($env:AGENT_JOBSTATUS -eq "SucceededWithIssues") {
          $dbPath = "$env:AGENT_TEMPDIRECTORY/advancedsecurity.codeql/d"
          $langDirs = Get-ChildItem -Path $dbPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @("diagnostic", "log") }

          if (-not $langDirs) {
            Write-Host "##[error]No language databases found under $dbPath."
            exit 1
          }

          $failed = $false

          foreach ($langDir in $langDirs) {
            $lang = $langDir.Name
            $finalizeLog = Get-ChildItem -Path "$($langDir.FullName)/log" -Filter "database-finalize-*.log" -ErrorAction SilentlyContinue | Select-Object -Last 1

            if (-not $finalizeLog) {
              Write-Host "##[warning][$lang] No finalize log found. Skipping."
              continue
            }

            $exitMatch = Select-String -Path $finalizeLog.FullName -Pattern "Exiting with code (\d+)" | Select-Object -Last 1

            if (-not $exitMatch) {
              Write-Host "##[warning][$lang] No exit code found in finalize log."
              continue
            }

            $exitCode = $exitMatch.Matches[0].Groups[1].Value

            if ($exitCode -eq "32") {
              Write-Host "##[warning][$lang] CodeQL exited with code 32 (empty database — no source analyzed). Treating as non-fatal."
            } elseif ($exitCode -eq "0") {
              Write-Host "[$lang] CodeQL finalized successfully."
            } else {
              Write-Host "##[error][$lang] CodeQL finalize failed with exit code $exitCode."
              $failed = $true
            }
          }

          if ($failed) {
            exit 1
          }
        }

  - task: AdvancedSecurity-Publish@1
```

---

## Multiple Languages: You MUST Use a Matrix Strategy

**If your pipeline scans more than one language, do NOT put them in a single job.** You must use a matrix strategy so each language runs in its own isolated job.

When multiple languages are initialized in a single job, `database finalize` runs sequentially for each language. **If any language exits with code 32 (or any non-zero code), it throws an error that stops the entire Analyze task immediately.** This means subsequent languages never get finalized at all — even if they have valid, analyzable source code. A matrix strategy avoids this by running each language in its own job, so an exit code 32 for one language cannot block finalization of another.

### Matrix Pipeline YAML

```yaml
pool:
  vmImage: ubuntu-latest

strategy:
  matrix:
    frontend:
      language: javascript
    backend:
      language: python

steps:
  - task: AdvancedSecurity-Codeql-Init@1
    inputs:
      languages: "$(language)"
      buildtype: 'None'

  - task: AdvancedSecurity-Codeql-Analyze@1
    continueOnError: true
    displayName: 'Run CodeQL Analysis'

  - task: PowerShell@2
    displayName: 'Validate CodeQL exit code'
    inputs:
      targetType: 'inline'
      script: |
        if ($env:AGENT_JOBSTATUS -eq "SucceededWithIssues") {
          $dbPath = "$env:AGENT_TEMPDIRECTORY/advancedsecurity.codeql/d"
          $langDirs = Get-ChildItem -Path $dbPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @("diagnostic", "log") }

          if (-not $langDirs) {
            Write-Host "##[error]No language databases found under $dbPath."
            exit 1
          }

          $failed = $false

          foreach ($langDir in $langDirs) {
            $lang = $langDir.Name
            $finalizeLog = Get-ChildItem -Path "$($langDir.FullName)/log" -Filter "database-finalize-*.log" -ErrorAction SilentlyContinue | Select-Object -Last 1

            if (-not $finalizeLog) {
              Write-Host "##[warning][$lang] No finalize log found. Skipping."
              continue
            }

            $exitMatch = Select-String -Path $finalizeLog.FullName -Pattern "Exiting with code (\d+)" | Select-Object -Last 1

            if (-not $exitMatch) {
              Write-Host "##[warning][$lang] No exit code found in finalize log."
              continue
            }

            $exitCode = $exitMatch.Matches[0].Groups[1].Value

            if ($exitCode -eq "32") {
              Write-Host "##[warning][$lang] CodeQL exited with code 32 (empty database — no source analyzed). Treating as non-fatal."
            } elseif ($exitCode -eq "0") {
              Write-Host "[$lang] CodeQL finalized successfully."
            } else {
              Write-Host "##[error][$lang] CodeQL finalize failed with exit code $exitCode."
              $failed = $true
            }
          }

          if ($failed) {
            exit 1
          }
        }
```

---

## How It Works

| Step | Description |
|------|-------------|
| `continueOnError: true` | Allows the pipeline to proceed even if the Analyze task fails. The job status becomes `SucceededWithIssues`. |
| Log inspection | The validation step searches `database-finalize-*.log` files under `$(Agent.TempDirectory)/advancedsecurity.codeql/d/<language>/log/` for the string `Exiting with code 32`. |
| Conditional failure | If exit code 32 is found, a warning is logged and the pipeline continues. For any other non-zero exit code, the step fails the pipeline. |
| Per-language output | The script reports each language individually (e.g., `[javascript] CodeQL exited with code 32...`) so you can see exactly which language has the issue. |

### Log File Location

CodeQL finalize logs are written to:

```
$(Agent.TempDirectory)/advancedsecurity.codeql/d/<language>/log/database-finalize-<timestamp>.log
```

Each log contains an entry like `Exiting with code <N>` at the end of the finalize process.

---

## Alternatives

- Dynamically look up languages used in the repository and build the task input using the CodeQL language monikers (see partial example [here](https://github.com/microsoft/GHAzDO-Resources/blob/53c144f5c1620ddc28a3d196884eaaee88c29d07/src/setup/Setup_CodeQL_PRs.ps1#L69)) 
