## Setup

- Copy the two files CIGate.ps1 and CIVerify.yml into your own GHAzDO enabled ADO project repo.

- Generate a new [PAT for ADO](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate).
  
  You can call it GHAZDO_READ_PAT, pick an expiry date.

  Give the new PAT ```Advanced Security - READ``` access.

  Save the PAT key before closing the UI.


- Add CIVerify as a new pipeline.
  
  Pipelines - New Pipeline - Select your code location and configure your pipeline as an existing yaml file.

  Select the CIVerify.yml file that was added in step 1.  Save the new Pipeline.

  Review the .yaml file, open up the UI to add a new Variable.

  Add a variable called GATING_PAT and set it's content to the PAT key you got in the previus step.

  Save your pipeline and optionaly run it.

  Find your new pipeline in the ADO UI, [rename it](https://learn.microsoft.com/en-us/azure/devops/pipelines/customize-pipeline?view=azure-devops#pipeline-settings) to CIVerify.

- Setup [build verification for your main branch](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies?view=azure-devops&tabs=browser#build-validation). Pick the CIVerify pipeline, you can keep the rest of the default settings.


- Figure out a way to test your new setup without adding any bad code to your main branch :) 

## Possible customizations
- Currently both language (javascript) and query suites (security-extended) are hard coded in CIVerify.yml. These settings might have to be updated to match your needs. 
- The CI Verification could be extended to also (or only) check new Dependency alerts. The same strategy could be used but tweaks would have to be done to both CIVerify.yml and CIGate.ps1. 
One complication to concider if you want to use the same strategy for dependency scanning. It could be that the reason we see new issues reported is that the advisory database has been extended since the last scan of main. That is, the new additions in the PR is not the issue but rather that this scan is the first one after an extention of the known vunarabilities. Still, since the alerts can be dismissed in the PR branch, or a new scan can be run on the main branch, I think this is acceptable. 
- Currently it is hard coded that we compaire to the main branch. If you have a different merge strategy, CIVerify.yml and CIGate.ps1 can be updated to accommodate that. 

   