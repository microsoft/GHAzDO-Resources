# CSV Report
A PowerShell [script](./ghazdo-csv-report.ps1) and sample [pipeline](./ghazdo-csv-report.yml) for querying the GHAzDO alert APIs and uploading a CSV report of an org's alerts for each repo as an artifact.

Script Filters:
- report scope ("organization", "project", or "repository")
- severities ("critical", "high", "medium", "low")
- states ("active", "fixed", "dismissed")
- alert types ("code", "secret", "dependency")
- SLA based on severity and # Days open ( "critical" 7 days, "high" 30 days, "medium" 90 days, and "low" 180 days)

Columns:
- "Alert Id"
- "Alert State"
- "Alert Title"
- "Alert Type"
- "Tool"
- "Rule Id"
- "Rule Name"
- "Rule Description"
- "Tags"
- "Severity"
- "First Seen"
- "Last Seen"
- "Fixed On"
- "Dismissed On"
- "Dismissal Type"
- "SLA Days"
- "Days overdue"
- "Alert Link"
- "Organization"
- "Project"
- "Repository"
- "Ref"
- "Ecosystem"
- "Location Paths"
- "Logical Paths"

## Setup

Inputs are documented on PowerShell [script](./ghazdo-csv-report.ps1).

Obtain a [Personal Access Token (PAT)](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=Windows) with the following scopes:
- `Advanced Security - Read`
- `Code - Read` (needed by default ... for Scope= `organization` or `project` lookup of repository list )
- `Projects - Read` (for Scope= `organization`)

### Pipeline Usage
1. Copy the [script](./ghazdo-csv-report.ps1) contents to your repository.
1. Reference the sample [pipeline](./ghazdo-csv-report.yml) and include the `PowerShell@2` task in a pipeline that references your repository.
   - the `filePath` property is a reference the script as you named the file in your repository (a relative path to the source root is needed if you moved into a different directory)
   - observe it is requiring a PAT to be set in the variable `reporting-pat` that is then passed to an environment variable used by the script.
1. Obtain the PAT as described above and [set as a secret variable](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/set-secret-variables) named `reporting-pat` from the sample [pipeline](./ghazdo-csv-report.yml)


## Output

### Script Logs

<img width="548" alt="image" src="https://github.com/microsoft/GHAzDO-Resources/assets/1760475/5cfb4be1-a4b4-42ed-be8f-b9aad306c5cd">

#### Pipeline Logs

<img width="580" alt="image" src="https://github.com/microsoft/GHAzDO-Resources/assets/1760475/1e4a085c-eefe-4dc7-9b68-eb9710112487">

<img width="466" alt="image" src="https://github.com/microsoft/GHAzDO-Resources/assets/1760475/897758f7-d1f6-43ed-a462-8814b4ad8273">

### Report Output

- See: [Sample Report](./ghazdo-report-20240325.1.csv)
