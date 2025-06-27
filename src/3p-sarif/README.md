# 3P SARIF

The AdvancedSecurity-Publish@1 task allows you to easily retrieve results from third-party providers, enhancing the integration with GitHub advanced security for AzureDevOps. These providers can include both open-source and commercial security analysis pipeline tasks that generate results in the conforming SARIF format. By leveraging this, you can now view the results within the Advanced Security Code Scanning alerts hub, providing a unified view of code security alerts from currently supported analysis tools directly within Azure DevOps. This integration supports SARIF 2.1, offering you a comprehensive overview of their security posture.

## Technical Details

- [Advanced-Security-Publish task](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/advanced-security-publish-v1?view=azure-pipelines)
- [Release Notes](https://learn.microsoft.com/en-us/azure/devops/release-notes/2024/ghazdo/sprint-238-update#publish-task-for-integrating-with-third-party-providers)
- [SARIF Validator](https://sarifweb.azurewebsites.net/Validation) - Azure DevOps ingestion rules
- [Extensions overview](https://learn.microsoft.com/en-us/azure/devops/extend/overview?view=azure-devops) 
- [Extension packaging/creation docs](https://learn.microsoft.com/en-us/azure/devops/extend/publish/overview?view=azure-devops)



## Marketplace

- Infrastructure As Code
  - [AdvancedSecurity.iac-tasks Marketplace](https://marketplace.visualstudio.com/items?itemName=advancedsecurity.iac-tasks)
  - [Docs](https://github.com/microsoft/advancedsecurity/wiki/Infrastructure%E2%80%90as%E2%80%90Code-Scanning)
  - See also, the [Advanced Security](https://marketplace.visualstudio.com/publishers/advancedsecurity) Publisher

- [Endor Labs](https://www.endorlabs.com/learn/endor-labs-partners-with-microsoft-to-strengthen-software-supply-chains)
  - [Docs](https://docs.endorlabs.com/scan-with-endorlabs/integrating-into-ci/scan-with-azuredevops/)

## Samples

The following samples provide boilerplate code to integrate with 3rd party code scanning tools into an Azure DevOps pipelines and upload their scan results into Advanced Security Code Scanning. 

- [Bandit](./.ado/bandit/)
- [Brakeman](./.ado/brakeman/)
- [Opengrep](./.ado/opengrep/)
- [PMD](./.ado/pmd/)
- [Psalm](./.ado/psalm/)
- [Security Code Scan](./.ado/security-code-scan/)