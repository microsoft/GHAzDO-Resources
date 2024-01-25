# Implementing SBOM in Azure DevOps using GitHub Advanced Security

This guide will help you implement a Software Bill of Materials (SBOM) in Azure DevOps along side GitHub Advanced Security. 

## Overview

This sample utilizes the [microsoft/sbom-tool](https://github.com/microsoft/sbom-tool) for SBOM generation.
- generate SPDX 2.2 compatible SBOM
- The [microsoft/component-detection](https://github.com/microsoft/component-detection) framework is used to detect dependencies. This is the same core engine used for GHAzDO Dependency Scanning.
  - See: [supported ecosystems](https://github.com/microsoft/component-detection/blob/main/docs/feature-overview.md)
- The [ClearlyDefined API](https://github.com/clearlydefined/clearlydefined) is used to populate license information for the components via the `-li true` parameter.

## Pipelines

The generated SBOM can be uploaded as an artifact to the pipeline in Azure DevOps. Reference the [sbom-tool.yml](sbom-tool.yml) as a guide for implementation.