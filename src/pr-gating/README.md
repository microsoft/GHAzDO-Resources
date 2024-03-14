# GHAzDO PR-Gating
Pipeline and script to handle Gated PRs using Advanced Security for ADO. Currently (February 2024) this is not supported out of the box by the product. We want to restrict new code going into main and only allow PRs if the new code does not introduce any new Code Scanning or Dependency scanning issues.

The idea is to set a branch protection policy (for main), forcing this pipeline to succeed before a PR into main can happen. The pipeline will run a Code Scanning/Dependency scan on the source branch of the PR. Later, using a PowerShell script, the alerts of the PR source and target will be compared. If there are alerts in the PR source that are not in the PR target this pipeline will fail.
If new alerts are detected, they can be viewed using the Advanced Security Hub for Code Scanning alerts. For Code Scanning, set the branch filter to the new PR branch to view/fix or dismiss the new alerts. For Dependency Scanning, use the link provided from the pull request comments or pipeline script output to link to view or dismiss the alert (currenlty the Advanced Security UI for Dependency Scanning does not show PR merge branch alerts). After that, the CIVerify Check for the PR can be re-run, hopefully this time with no issues.

If fixing the alerts is not the right choice and you do not have the rights to dismiss the alerts, one option is to setup this Check as optional. That way, a PR merge can still happen, even if the check failed and reported a new issue. This is mainly useful for false positives.  Alternatively, trusted users can be given the permissions to `Bypass policies` and force pushes or PRs.

[Setup](./Setup.md)

[Usage](./Usage.md)
