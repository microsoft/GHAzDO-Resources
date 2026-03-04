# Handling CodeQL Exit Code 32 in Azure DevOps (GHAzDO)

## Background

CodeQL exit code 32 indicates that the database finalization completed but no analyzable source code was found. This can happen when:

 - Source files are commented out or empty
 - A language is initialized but no applicable source exists in the repository
 - Build steps produce no compiled output for traced languages

In centralized pipelines that serve many repositories, this is often expected behavior rather than a true failure. However, the AdvancedSecurity-Codeql-Analyze task treats all non-zero exit codes as fatal,
causing the pipeline to fail.

## Workaround

Since the task does not currently expose a configuration option to treat exit code 32 as non-fatal, you can use continueOnError combined with a post-analysis validation step that inspects the CodeQL
finalize logs.

<img width="1259" height="444" alt="image" src="https://github.com/user-attachments/assets/8d645706-05c0-443d-84a5-cb1326d7292f" />


### Pipeline YAML

```yml

#EX: NO JAVASCRIPT Exists - expect analyze to fail with:
#  ...codeql database finalize --finalize-dataset --threads=0 --ram=5874 /home/vsts/work/_temp/advancedsecurity.codeql/d/javascript
#  CodeQL detected code written in GitHub Actions, but not any written in JavaScript/TypeScript. Confirm that there is some source code for JavaScript/TypeScript in the project. For more information, review our troubleshooting guide at https://gh.io/troubleshooting-code-scanning/no-source-code-seen-during-build.
#  ##[warning] Error running the 'database finalize' CodeQL command (32)
#  ##[error]Error running the 'database finalize' CodeQL command (32)

 steps:
- task: AdvancedSecurity-Codeql-Init@1
  inputs:
    languages: 'javascript,python'
- task: AdvancedSecurity-Codeql-Analyze@1
  continueOnError: true
  name: codeqlAnalyze

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

### How It Works

| Step | Description |
|------|-------------|
| `continueOnError: true` | Allows the pipeline to proceed even if the Analyze task fails. The job status becomes `SucceededWithIssues`. |
| Log inspection | The validation step searches `database-finalize-*.log` files under `$(Agent.TempDirectory)/advancedsecurity.codeql/d/` for the string `Exiting with code 32`. |
| Conditional failure | If exit code 32 is found, a warning is logged and the pipeline continues. For any other non-zero exit code, the step fails the pipeline. |

### Log File Location

CodeQL finalize logs are written to:

```
$(Agent.TempDirectory)/advancedsecurity.codeql/d/<language>/log/database-finalize-<timestamp>.log
```

Each log contains an entry like `Exiting with code <N>` at the end of the finalize process.
