# GHAzDO Committer Report

Generates a committer report for GitHub Advanced Security for Azure DevOps (GHAzDO) across all accessible organizations for the signed-in user.

## What it does

- Enumerates all Azure DevOps organizations for your account
- Queries **estimated** committers (repos where AdvSec is currently OFF)
- Queries **licensed** committers (currently consuming a GHAzDO license) per plan (CodeSecurity / SecretProtection)
- Produces a deduplicated committer list with org memberships, license status, and plan details
- Optionally exports results to CSV

## Prerequisites

1. Install the [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
2. Sign in to the tenant that contains your Azure DevOps organizations:
   ```powershell
   az login --tenant <tenant_id> --allow-no-subscriptions
   ```

> **Note:** The script discovers organizations based on the signed-in user's tenant. If you have orgs across multiple tenants, run the script separately for each tenant after logging in with `az login --tenant <tenant_id> --allow-no-subscriptions`.

## Usage

Requires **PowerShell 7+**.

```powershell
# Display report in the console only
.\Get-CommitterReport.ps1

# Export report to CSV (recommended)
.\Get-CommitterReport.ps1 -CsvPath .\committer-report.csv
```

## Output

The report includes the following columns:

| Column | Description |
|---|---|
| **DisplayName** | The committer's display name |
| **UserPrincipalName** | The committer's UPN or identity |
| **GHAzDOLicensed** | `True` if currently consuming a license, `False` if estimated only |
| **Plans** | Active plan(s): `AdvancedSecurity`, `CodeSecurity`, `SecretProtection`, or a combination |
| **Organizations** | Comma-separated list of orgs the committer belongs to |

## Limitations

**Bundled vs. unbundled plan detection:** The Azure DevOps Advanced Security APIs do not expose a documented, supported way to tell whether an organization uses a bundled (`AdvancedSecurity`) or unbundled (separate `CodeSecurity` / `SecretProtection`) billing model. For bundled orgs, the API simply duplicates the same committers into both the `codeSecurity` and `secretProtection` plan responses. This means:

- A bundled org with both plans active looks **identical** to an unbundled org with both plans active
- The script reports an **effective** `AdvancedSecurity` plan whenever both per-plan responses contain users for an org, regardless of the actual billing SKU or billing model
- There is no reliable, documented API field or endpoint that definitively reports the true billing model

The script also prints a `Billing model: Bundled/Unbundled` line based on an **undocumented heuristic** that inspects `plan=all` behavior. This is a best-effort guess only, may be incorrect, and may stop working if the underlying API behavior changes. The **Plans** column in the report continues to reflect an *effective plan* view (for example, `AdvancedSecurity` when both plan responses contain users), and **must not** be interpreted as an authoritative billing SKU from Azure DevOps billing systems.
