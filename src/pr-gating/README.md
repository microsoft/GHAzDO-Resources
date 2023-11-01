# GHAzDO PR-Gating
Pipeline and script to handle Gated PRs using Advanced Security for ADO. Currently (November 2023) this is not supported out of the box by the product. We want to restrict new code going into main and only allow PRs if the new code does not introduce any new CodeQL issues. The same could be done for Dependencies with some tweaks.

The idea is to set a branch protection policy (for main), forcing this pipeline to succeed before a PR into main can happen. The pipeline will run a CodeQL scan on the source branch of the PR. Later, using a PowerShell script, the CodeQL issues of the PR source and target will be compared. If there are issues in the PR source that are not in the PR target this pipeline will fail. 
If new alerts are detected, these will have to be analysed using the regular Advanced Security UI for Code Scanning alerts. Set the branch filter to the new PR branch and fix or dismiss the new alerts. After that, the CIVerify Check for the PR can be re-run, hopefully this time with no issues.

If fixing the alerts is not the right choice and you do not have the rights to dismiss the alerts, one option is to setup this Check as optional. That way, a PR merge can still happen, even if the check failed and reported a new issue. This is mainly useful for false positives. 

[Setup](./Setup.md)

[Usage](./Usage.md)
