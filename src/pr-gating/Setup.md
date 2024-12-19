## Setup

- Copy the two files CIGate.ps1 and CIVerify.yml into your own GHAzDO enabled ADO project repo.

- Add CIVerify as a new pipeline.

  Pipelines - New Pipeline - Select your code location and configure your pipeline as an existing yaml file.

  Select the CIVerify.yml file that was added in step 1.  Save the new Pipeline.

  Review the .yaml file, open up the UI to add a new Variable.

  Save your pipeline and optionaly run it.

  Find your new pipeline in the ADO UI, [rename it](https://learn.microsoft.com/en-us/azure/devops/pipelines/customize-pipeline?view=azure-devops#pipeline-settings) to CIVerify.

- Grant permissions to your pipeline

  The build service for your pipeline needs permissions to be able to contribute to PRs to add comments for each security finding.

  In your Project Settings -> Repositories -> Security, modify your repositories build service to `Allow` for `Contribute to pull requests`


- Setup [build verification for your main branch](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies?view=azure-devops&tabs=browser#build-validation). Pick the CIVerify pipeline. If your developers does not have access rights to dissmiss alerts it is a good idea to set this check to optional. That way, a PR can be completed even if the alert is a false possitive. The rest of the settings can be keep as their default settings.

  The CIVerify pipeline will add PR annotations as comments for the code related to the new alert. Consider setting the requirement 'Check for comment resolution' as a branch policy. This will require all CodeQL/Dependency Scanning generated comments to be considered before completing the merge.

  If you have more branches that should be protected, you can setup the same check for those branches.

  <img width="800" alt="buildpolicy" src="https://github.com/microsoft/GHAzDO-Resources/assets/106392052/74801e80-46e1-4d05-97b1-5f11396330e1">


- Figure out a way to test your new setup without adding any bad code to your main branch :)

## Possible customizations
- The CodeQL language (javascript) is hardcoded in CIVerify.yml. GHAzDO tasks will need to be updated to match your needs.
- CIGate.ps1 contains a policy coded for which alerts types (`code` and/or `dependency`) and vulnerability/quality severeties ( `critical`, `high`, `medium`, `low`, `error`, `warning`, and `note`).  Customize this in the script as needed to meet your policy thresholds (example: do not fail on Quality checks or Low severity security issues by removing `low`, `error`, `warning`, and `note` )
- One complication to consider for new alerts appearing for Code or Dependency scanning. It could be that the reason we see new issues reported is that this PR is the first time scanning using updated CodeQL tooling or the GitHub Advisory Database has been extended since the last scan of main. That is, the new additions in the PR is not the issue but rather that this scan is the first one after an extention of the known vunarabilities. Still, since the alerts can be dismissed in the PR branch, the branch policy check can be setup as optional, or a new scan can be run on the main branch, I think this is acceptable.
- Dynamically pass/fail the build only if a PR comment was added, indicating that there are new alerts that were directly created by this PR.  Since we do incremental PR iteration based comments this is not currently viable without a rewrite
- Consider a rollup comment for dependency alerts.  Transitives vulnerability detections may includle a graph so that we are able to walk the include path to the root, but there is not always a file in the repo we can easilly link them to.

