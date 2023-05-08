# Project Level Setup for GHAS on ADO

This is a series of Proof-of-Concepts for setting up GitHub Advanced Security on Azure DevOps. Each Script in this repository has a slightly different function, and is a different method of setting up the CodeQL tasks for execution.

## Install

Everything should be just a script + local module - nothing to install.

### Dependencies

Powershell (Tested with 7.3.2)

## Usage

```bash
pwsh ./Setup_CodeQL_PRs.ps1 'ado_org' 'ado_project' PAT
```

## Maintainers

Nick Couraud (<nicour@microsoft.com>)

## Contributing

PRs accepted.

## License

MIT © Microsoft Corporation
