# GHAzDO PR-Gating
Pipeline and script to handle Gated PRs using Advanced Security for ADO. Currently (October 2025) this gating policy is not supported out of the box by the product. We want to restrict new code going into main and only allow PRs if the new code does not introduce any new Code Scanning, Dependency Scanning, or Secret Scanning alerts.

The idea is to set a branch protection policy (for main), forcing this pipeline to succeed before a PR into main can happen. The pipeline will run a Code Scanning/Dependency scan on the source branch of the PR. Later, using a PowerShell script, the alerts of the PR source and target will be compared. If there are alerts in the PR source that are not in the PR target this pipeline will fail.  Secret Alerts are not branch based, instead they are discovered based on the commit hashes from the inital secret alert matching any commits in the PR.

If new alerts are detected, they can be viewed using the Advanced Security Hub for alerts. For Code Scanning and Dependency Scanning, set the branch filter to the new PR ref to view/fix or dismiss the new alerts.  Also, use the link provided from the pull request comments (Code Scanning / Dependency Scanning are [native](https://devblogs.microsoft.com/devops/introducing-pull-request-annotation-for-codeql-and-dependency-scanning-in-github-advanced-security-for-azure-devops/) but adding Secret Scanning comments requires using this script) or pipeline script output to link to view + revoke/rotate/fix or dismiss the alert. After that, the CIVerify Check for the PR can be re-run, hopefully this time with no issues.

If fixing the alerts is not the right choice and you do not have the rights to dismiss the alerts, one option is to setup this Check as optional. That way, a PR merge can still happen, even if the check failed and reported a new issue. This is mainly useful for false positives.  Alternatively, trusted users can be given the permissions to `Bypass policies` and force pushes or PRs.

[Setup](./Setup.md)

[Usage](./Usage.md)
