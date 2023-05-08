<#
.DESCRIPTION
Common Functions Module for GHAzDO Setup Scripts

#>

$BranchName = 'GHAS-on-ADO-Autosetup'
$pipelineYmlPath = ".azuredevops/pipelines/advanced_security.yml"

<#
.SYNOPSIS
Gets the ProjectID GUID for a given ADO Project

.PARAMETER OrganizationName

.PARAMETER ProjectName

.PARAMETER AuthHeader
Pre-Created Auth Header using Basic Auth & and ADO PAT

#>
function  getProjectId {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$OrganizationName,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$ProjectName,
        [Parameter(Mandatory=$True,Position=3)]
        $AuthHeader
    )

    $uriAccount = "https://dev.azure.com/$($OrganizationName)/_apis/projects"
    $projects = Invoke-RestMethod -Uri $uriAccount -Method get -Headers $AuthHeader 
    $project = $projects.value | Where-Object {$_.name -EQ $ProjectName}
    return $project.id
}

<#
.DESCRIPTION
Gets the Project LanaguageMetrics Collection for a given AzureDevOps Project

.PARAMETER OrganizationName

.PARAMETER ProjectName

.PARAMETER AuthHeader
Pre-Created Auth Header using Basic Auth & and ADO PAT

#>
function getProjectLanguageMetrics {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$OrganizationName,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$ProjectId,
        [Parameter(Mandatory=$True,Position=3)]
        [hashtable]$AuthHeader
    )

    $MetricsURI="https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/projectanalysis/languagemetrics"
    $Metrics = Invoke-RestMethod -Uri $MetricsURI -Method GET -Headers $AuthHeader
    return $Metrics.repositoryLanguageAnalytics
}

<#
.DESCRIPTION
Get an Azure DevOps Repository Object

.PARAMETER OrganizationName

.PARAMETER ProjectId

.PARAMETER RepositoryId

.PARAMETER AuthHeader
Pre-Created Auth Header using Basic Auth & and ADO PAT

#>
function  getRepository {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$OrganizationName,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$ProjectId,
        [Parameter(Mandatory=$True,Position=3)]
        [string]$RepositoryId,
        [Parameter(Mandatory=$True,Position=4)]
        [hashtable]$AuthHeader
    )

    $ReposUri = "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/git/repositories/$($RepositoryId)?api-version=7.0"
    $repoObj = Invoke-RestMethod -Uri $ReposUri -Method get -Headers $AuthHeader
    return $repoObj
}

<#
.DESCRIPTION
Get an Azure DevOps Repository Collection

.PARAMETER OrganizationName

.PARAMETER ProjectId

.PARAMETER AuthHeader
Pre-Created Auth Header using Basic Auth & and ADO PAT

#>
function  getRepositories {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$OrganizationName,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$ProjectId,
        [Parameter(Mandatory=$True,Position=3)]
        [hashtable]$AuthHeader
    )

    $ReposUri = "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/git/repositories?api-version=7.0"
    $repoObj = Invoke-RestMethod -Uri $ReposUri -Method get -Headers $AuthHeader
    return $repoObj
}

<#
.DESCRIPTION
Gets the set of existing pipelines for a given ADO Pipelines Folder

.PARAMETER OrganizationName

.PARAMETER ProjectId

.PARAMETER FolderName
Name of the Pipelines folder that we are searching in

.PARAMETER AuthHeader
Pre-Created Auth Header using Basic Auth & and ADO PAT

#>
function getExistingPipelines {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$OrganizationName,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$ProjectId,
        [Parameter(Mandatory=$True,Position=3)]
        [string]$FolderName,
        [Parameter(Mandatory=$True,Position=4)]
        [hashtable]$AuthHeader
    )

    $pipelines=Invoke-RestMethod -URI "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/pipelines?api-version=7.0" -Method GET -Headers $AuthHeader
    $existingpipelines=$pipelines.value | Where-Object {$_.Folder -EQ "\$($FolderName)"}
    $repoIds=@{}
    foreach($obj in $existingpipelines){
        $r_id=$obj.name -Split {$_ -eq ' '}
        $r_uri=$obj.url -Split {$_ -eq "?"}
        $repoIds.Add($r_id[3],$r_uri[0])
    }
    return $repoIds
}

<#
.DESCRIPTION
Gets a Given Azure Pipelines Queue Object

.PARAMETER OrganizationName

.PARAMETER ProjectId

.PARAMETER AuthHeader
Pre-Created Auth Header using Basic Auth & and ADO PAT

.PARAMETER QueueName
The name of the Queue that we are searching for

#>
function getQueue {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$OrganizationName,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$ProjectId,
        [Parameter(Mandatory=$True,Position=3)]
        [hashtable]$AuthHeader,
        [PArameter(Mandatory=$false,Position=4)]
        [string]$QueueName = "Azure Pipelines"
    )

    $uriQueue = "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/" + "_apis/distributedtask/queues"
    $queues = Invoke-RestMethod -Uri $uriQueue -Method get -Headers $AuthHeader 
    $queue = $queues.value | Where-Object {$_.name -EQ $QueueName}
    return $queue
}

<#
.DESCRIPTION
Idempotent Creation/Management of an Azure Pipelines Folder

.PARAMETER OrganizationName
.PARAMETER ProjectId
.PARAMETER FolderName
The Name of the Pipelines Folder to ensure exists

.PARAMETER AuthHeader
Pre-Created Auth Header using Basic Auth & and ADO PAT

#>
function ensureFolder {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$OrganizationName,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$ProjectId,
        [Parameter(Mandatory=$True,Position=3)]
        [string]$FolderName,
        [Parameter(Mandatory=$True,Position=4)]
        [hashtable]$AuthHeader
    )

    $FolderPath = "//$($FolderName)//"
    # Somehow the 7.0 Prod APIs aren't there yet, so we have to use the 7.1-preview.2
    $FolderUri = "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/build/folders/$($FolderPath)?api-version=7.1-preview.2"
    $Folder = Invoke-RestMethod -Uri $FolderUri -Method get -Headers $AuthHeader 
    if ($Folder.count = 0){ 
        $UriCreateFolder = "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/build/folders&api-version=7.1-preview.2"
        $Body="{"+'"path" : "'+$($FolderPath)+' "}'
        $Folder = Invoke-RestMethod -Uri $UriCreateFolder -Method PUT -Headers $AuthHeader -Body $Body -ContentType 'application/json'
    }
}

<#
.DESCRIPTION
Creates a template YAML definition on the branch specified in the SETUP_COMMON module

.PARAMETER OrganizationName

.PARAMETER ProjectId

.PARAMETER RepositoryId

.PARAMETER LanguageString
CodeQL Language String - comma separated list of languages to analyze

.PARAMETER DefaultRef
The git Ref that is the default branch for the repository

#>
function createYaml {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$OrganizationName,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$ProjectId,
        [Parameter(Mandatory=$True,Position=3)]
        [string]$RepositoryId,
        [Parameter(Mandatory=$True,Position=4)]
        [string]$LanguageString,
        [Parameter(Mandatory=$True,Position=5)]
        [string]$DefaultRef,
        [Parameter(Mandatory=$True,Position=6)]
        [hashtable]$AuthHeader
    )

    $defaultbranch = ($DefaultRef -Split "/")[-1]

    $headURI = "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/git/repositories/$RepositoryId/refs/heads/$defaultbranch"
    $resp = Invoke-RestMethod -Uri $headURI -Headers $AuthHeader -Method Get 
    $latestCommit = $resp.value.ObjectId
    # Create a new branch for the changes
    $branchRef = "refs/heads/$BranchName"
    $branchBody = @(@{
                name = $branchRef
                oldObjectId = "0000000000000000000000000000000000000000"
                newObjectId = $latestCommit
            })

    $createBranchUrl = "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/git/repositories/$($RepositoryId)/refs?api-version=7.0"
    Invoke-RestMethod -Uri $createBranchUrl -Headers $AuthHeader -Method Post -Body (ConvertTo-Json $branchBody) -ContentType 'application/json'

    $fileContents = Get-Content -Path .\advanced_security.yml -Raw
    $customLanguagesYml = $fileContents -replace "--REPLACE--", $LanguageString
    $finalYml = $customLanguagesYml -replace "--BRANCH_REPLACE--", $defaultbranch

    # Create a new commit with the changes
    $commitBody = @{
        refUpdates = @(
            @{
                name = $branchRef
                oldObjectId = $latestCommit
            }
        )
        commits = @(
            @{
                comment = "Integrate GitHub Advanced Security"
                changes = @(
                    @{
                        changeType = "add"
                        item = @{
                            path = $pipelineYmlPath
                        }
                        newContent = @{
                            content = $finalYml
                            contentType = "rawtext"
                        }
                    }
                )
            }
        )
    }

    $createCommitUrl = "https://dev.azure.com/$($OrganizationName)/_apis/git/repositories/$($RepositoryId)/pushes?api-version=7.0"
    Invoke-RestMethod -Uri $createCommitUrl -Headers $AuthHeader -Method Post -Body (ConvertTo-Json $commitBody -Depth 100) -ContentType 'application/json'
}

<#
.DESCRIPTION
Creates a pull request with the previously committed changes to the repository

.PARAMETER OrganizationName

.PARAMETER ProjectId

.PARAMETER RepositoryId

.PARAMETER DefaultRef
Default Branch for the Repository referenced in RepositoryId. This is the merge base for the Pull Request.

.PARAMETER AuthHeader
Pre-Created Auth Header using Basic Auth & and ADO PAT

#>
function createPullRequest {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$OrganizationName,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$ProjectId,
        [Parameter(Mandatory=$True,Position=3)]
        [string]$RepositoryId,
        [Parameter(Mandatory=$True,Position=4)]
        [string]$DefaultRef,
        [Parameter(Mandatory=$True,Position=5)]
        [hashtable]$AuthHeader
    )

    
    # Create a new pull request with the changes
    $pullRequestTitle = "GitHub Advanced Security Pipeline Setup"
    $pullRequestBody = "This Pull Request adds a default GitHub Advanced Security Pipeline to the repository, for the interpreted languages detected by Azure DevOps. The pipeline will run on every push to the default branch, and will run CodeQL on the repository."
    $pullRequest = @{
        sourceRefName = "refs/heads/$BranchName"
        targetRefName = "$DefaultRef"
        title = $pullRequestTitle
        description = $pullRequestBody
    }
    $pullRequestsUrl = "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/git/repositories/$($RepositoryId)/pullrequests?api-version=7.0"
    # Create the pull request using the REST API
    Invoke-RestMethod -Method Post -Uri $pullRequestsUrl -Headers $AuthHeader -Body (ConvertTo-Json $pullRequest -Depth 100) -ContentType 'application/json'
}

<#
.DESCRIPTION
Create a YAML Pipeline in Azure DevOps with our previously committed YAML file

.PARAMETER OrganizationName

.PARAMETER ProjectId

.PARAMETER RepositoryId

.PARAMETER FolderName
Azure Pipelines Folder Name to create the pipeline in

.PARAMETER AuthHeader
Pre-Created Auth Header using Basic Auth & and ADO PAT

#>
function createYamlPipeline {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$OrganizationName,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$ProjectId,
        [Parameter(Mandatory=$True,Position=3)]
        [string]$RepositoryId,
        [Parameter(Mandatory=$True,Position=4)]
        [string]$FolderName,
        [Parameter(Mandatory=$True,Position=5)]
        [hashtable]$AuthHeader
    )

    $pipeline = @{
        folder = "//$($FolderName)//"
        name = "GHAzDO Analysis - "+$RepositoryId
        configuration = @{
            type =  "yaml"
            path = $pipelineYmlPath
            repository = @{
                id =  "$RepositoryId"
                type = "azureReposGit"
            }
        }
    }

    $UriPipelines="https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/pipelines?api-version=7.0"
    $body = $pipeline | convertto-json -Depth 100

    $pipeline = Invoke-RestMethod -Uri $UriPipelines -Method POST -Headers $AuthHeader -Body $body -ContentType 'application/json'
    return $pipeline.id
}

<#
.DESCRIPTION
Executes a YAML pipeline in Azure DevOps

.PARAMETER OrganizationName

.PARAMETER ProjectId

.PARAMETER PipelineId

.PARAMETER AuthHeader
Pre-Created Auth Header using Basic Auth & and ADO PAT

.PARAMETER ref
the branch to execute the pipeline against. Defaults to the BranchName variable

.NOTES
Executes against the defined Branch for Autosetup

#>
function execPipeline {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$OrganizationName,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$ProjectId,
        [Parameter(Mandatory=$True,Position=3)]
        [string]$PipelineId,
        [Parameter(Mandatory=$True,Position=4)]
        [hashtable]$AuthHeader,
        [Parameter(Mandatory=$False,Position=5)]
        [string]$ref = $BranchName
    )

    $postBody = @{
        "resources" = @{
            "repositories" = @{
                "self" = @{
                    "refName" = "refs/heads/$ref"
                }
            }
        }
    }

    Invoke-RestMethod -URI "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/pipelines/$($PipelineId)/runs?api-version=7.0" -Method POST -Headers $AuthHeader -ContentType 'application/json' -Body (ConvertTo-Json $postBody -Depth 100)
}

<#
.DESCRIPTION
Function to create a Classic Pipeline running the Advanced Security Tasks

.PARAMETER OrganizationName

.PARAMETER ProjectId

.PARAMETER RepositoryId

.PARAMETER LanguageString
CodeQL Language String - comma separated list of languages to analyze

.PARAMETER DefaultRef
The Git Ref that is the default branch for the repository

.PARAMETER FolderName
Pipeline Folder Name

.PARAMETER AuthHeader
Pre-Created Auth Header using Basic Auth & and ADO PAT

#>
function createBuildDefinition {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$OrganizationName,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$ProjectId,
        [Parameter(Mandatory=$True,Position=3)]
        [string]$RepositoryId,
        [Parameter(Mandatory=$True,Position=4)]
        [string]$LanguageString,
        [Parameter(Mandatory=$True,Position=5)]
        [string]$DefaultRef,
        [Parameter(Mandatory=$True,Position=6)]
        [string]$FolderName,
        [Parameter(Mandatory=$True,Position=7)]
        [hashtable]$AuthHeader
    )

    $FolderPath = "//$($FolderName)//"
    $definition = Get-Content '.\build_definition.json' | Out-String | convertfrom-json 
    $definition.repository.id=$RepositoryId
    $definition.name="GHAzDO Analysis - "+$RepositoryId
    $definition.folder=$FolderPath
    $definition.path=$FolderPath
    $definition.triggers[0].branchFilters[0] = "+"+$DefaultRef
    $definition.process.phases[0].steps[0].inputs.languages=$LanguageString
    $queue = getQueue $OrganizationName $ProjectId $AuthHeader
    $definition.queue = $queue

    $UriPipelines="https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/build/definitions?api-version=7.1-preview.7"
    $body = $definition | convertto-json -Depth 100

    Invoke-RestMethod -Uri $UriPipelines -Method POST -Headers $AuthHeader -Body $body -ContentType 'application/json'
}

<#
.DESCRIPTION
Updates a given previously created Classic Pipeline with the specified Language String and Default Ref for the Repository in question

.PARAMETER PipelineURI
Fully Qualified URI for the Pipeline to Update

.PARAMETER LanguageString
CodeQL Language String - comma separated list of languages to analyze

.PARAMETER DefaultRef
The Git Ref that is the default branch for the repository

.PARAMETER AuthHeader
Pre-Created Auth Header using Basic Auth & and ADO PAT

#>
function updatePipeline {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$PipelineURI,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$LanguageString,
        [Parameter(Mandatory=$True,Position=3)]
        [string]$DefaultRef,
        [Parameter(Mandatory=$True,Position=4)]
        [hashtable]$AuthHeader
    )

    $pipeline = Invoke-RestMethod -Uri $PipelineURI -Method Get -Headers $AuthHeader 
    $definition = $pipeline.configuration.designerJson
    if ($definition.process.phases[0].steps[0].inputs.languages -ne $LanguageString) {
        $definition.process.phases[0].steps[0].inputs.languages = $LanguageString
        $definition.triggers[0].branchFilters[0] = "+"+$DefaultRef
        $postURI=$($definition.url -Split {$_ -eq "?"})[0]+"?api-version=7.1-preview.7"
        $body = $definition | convertto-json -Depth 100
        Invoke-RestMethod -Uri $postURI -Method PUT -Headers $AuthHeader -Body $body -ContentType 'application/json'
    }
}

<#
.DESCRIPTION
Creates a template YAML definition on the branch specified in the SETUP_COMMON module

.PARAMETER OrganizationName

.PARAMETER ProjectId

.PARAMETER Repository
Repository Object to Operate against

.PARAMETER LanguageString
CodeQL Language String - comma separated list of languages to analyze

.PARAMETER AuthHeader
Pre-Created Auth Header using Basic Auth & and ADO PAT
#>
function updateYaml {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$OrganizationName,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$ProjectId,
        [Parameter(Mandatory=$True,Position=3)]
        $Repository,
        [Parameter(Mandatory=$True,Position=4)]
        [string]$LanguageString,
        [Parameter(Mandatory=$True,Position=5)]
        [hashtable]$AuthHeader
    )

    $defaultbranch = ($Repository.defaultBranch -Split '/')[-1]
    $branchRef = "refs/heads/$BranchName"

    $headURI = "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/git/repositories/$($Repository.id)/$($Repository.defaultBranch)"
    $resp = Invoke-RestMethod -Uri $headURI -Headers $AuthHeader -Method Get 
    $latestCommit = $resp.value.ObjectId
    # check if we need a new branch for the changes
    $branchURI = "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/git/repositories/$($Repository.Id)/refs/heads/$($BranchName)"
    $branchResp = Invoke-RestMethod -Uri $branchURI -Headers $AuthHeader -Method Get -ErrorAction SilentlyContinue

    $BranchUrl = "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/git/repositories/$($Repository.Id)/refs?api-version=7.0"
    if ($branchResp.count -ge 1) {
        $deleteBranchBody = @(@{
            name = $branchRef
            oldObjectId = $branchResp.value.ObjectId
            newObjectId = "0000000000000000000000000000000000000000"
        })
        Invoke-RestMethod -Uri $BranchUrl -Headers $AuthHeader -Method Post -Body (ConvertTo-Json $deleteBranchBody) -ContentType 'application/json'
    }
    # Our Branch is gone, create it
    $action = "add"
    $CommitMessage = "Integrate Advanced Security"
    $branchBody = @(@{
                name = $branchRef
                oldObjectId = "0000000000000000000000000000000000000000"
                newObjectId = $latestCommit
            })

    Invoke-RestMethod -Uri $BranchUrl -Headers $AuthHeader -Method Post -Body (ConvertTo-Json $branchBody) -ContentType 'application/json'

    $fileContents = Get-Content -Path .\advanced_security.yml -Raw
    $customLanguagesYml = $fileContents -replace "--REPLACE--", $LanguageString
    $finalYml = $customLanguagesYml -replace "--BRANCH_REPLACE--", $defaultbranch

    # Create a new commit with the changes
    $commitBody = @{
        refUpdates = @(
            @{
                name = $branchRef
                oldObjectId = $latestCommit
            }
        )
        commits = @(
            @{
                comment = $CommitMessage
                changes = @(
                    @{
                        changeType = $action
                        item = @{
                            path = $pipelineYmlPath
                        }
                        newContent = @{
                            content = $finalYml
                            contentType = "rawtext"
                        }
                    }
                )
            }
        )
    }

    $createCommitUrl = "https://dev.azure.com/$($OrganizationName)/_apis/git/repositories/$($Repository.Id)/pushes?api-version=7.0"
    Invoke-RestMethod -Uri $createCommitUrl -Headers $AuthHeader -Method Post -Body (ConvertTo-Json $commitBody -Depth 100) -ContentType 'application/json'
}

<#
.DESCRIPTION
Function to enable the Advanced Security feature on a repository

.PARAMETER OrganizationName
.PARAMETER ProjectId

.PARAMETER Repository
Repository Object to Operate against

.PARAMETER EnablePushProtection
Boolean to enable push protection or not for the repository

.PARAMETER AuthHeader
Pre-Created Auth Header using Basic Auth & and ADO PAT
#>
function Enable-GHAzDO {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$OrganizationName,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$ProjectId,
        [Parameter(Mandatory=$True,Position=3)]
        $Repository,
        [Parameter(Mandatory=$True,Position=4)]
        [bool]$EnablePushProtection,
        [Parameter(Mandatory=$True,Position=5)]
        [hashtable]$AuthHeader
    )

    $enableURI = "https://advsec.dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/advancedsecurity/repositories/$($Repository.Id)/enablement?api-version=1.0"

    $enableBody = @{
        "projectId"= $ProjectId
        "repositoryId"= $Repository.Id
        "advSecEnabled"= $True
        "blockPushes" = $EnablePushProtection
        }

    Invoke-RestMethod -Uri $enableURI -Headers $AuthHeader -Method PATCH -Body (ConvertTo-Json $enableBody) -ContentType 'application/json'
}

<#
.SYNOPSIS
Function to get the current enablement status of the Advanced Security feature on a repository

.DESCRIPTION
Function to get the current enablement status of the Advanced Security feature on a repository

.PARAMETER OrganizationName
.PARAMETER ProjectId
.PARAMETER Repository
Repository Object to Operate against

.PARAMETER AuthHeader
Pre-Created Auth Header using Basic Auth & and ADO PAT
#>
function Get-GHASEnablement {
    param (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$OrganizationName,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$ProjectId,
        [Parameter(Mandatory=$True,Position=3)]
        $Repository,
        [Parameter(Mandatory=$True,Position=4)]
        [hashtable]$AuthHeader
    )

    $enableURI = "https://advsec.dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/advancedsecurity/repositories/$($Repository.Id)/enablement?api-version=1.0"

    $resp = Invoke-RestMethod -Uri $enableURI -Headers $AuthHeader -Method GET -ContentType 'application/json'
    return $resp.advSecEnabled
}