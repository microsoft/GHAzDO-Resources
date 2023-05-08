# Setup Our Parameters
[CmdletBinding()]
Param(
   # The ADO Organization that we will work with
   [Parameter(Mandatory=$True,Position=1)]
   [string]$OrganizationName,

   # The ADO Project that we will work with
   [Parameter(Mandatory=$True,Position=2)]
   [string]$ProjectName,

   # An ADO PAT to use for this work
   [Parameter(Mandatory=$True,Position=3)]
   [string]$ADOPat
)

# Import our Common Functions
# -Force so we always get the latest
Import-Module ./Common.psm1 -Force


$Headers = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($ADOPat)")) }

$FolderPath_Interpreted= "\GHAS-on-ADO-Scanning"
$FolderPath_Compiled= "\GHAS-on-ADO-Compiled"
$FolderPath_Yaml = "\GHAzDO-YAML"

$ProjectId = getProjectId $OrganizationName $ProjectName $Headers

$pipelines=Invoke-RestMethod -URI "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/pipelines?api-version=7.0" -Method GET -Headers $Headers

$interpretedpipelines=$pipelines.value | Where-Object {$_.Folder -EQ $FolderPath_Interpreted}
$compiledpipelines=$pipelines.value | Where-Object {$_.Folder -EQ $FolderPath_Compiled}
$yamlpipelines=$pipelines.value | Where-Object {$_.Folder -EQ $FolderPath_Yaml}

foreach($obj in $interpretedpipelines){
    Invoke-RestMethod -URI "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/build/builds?api-version=7.0&definitionId=$($obj.Id)" -Method POST -Headers $Headers -ContentType 'application/json'
}
foreach($obj in $compiledpipelines){
    Invoke-RestMethod -URI "https://dev.azure.com/$($OrganizationName)/$($ProjectId)/_apis/build/builds?api-version=7.0&definitionId=$($obj.Id)" -Method POST -Headers $Headers -ContentType 'application/json'
}
foreach($obj in $yamlpipelines){
    execPipeline $OrganizationName $ProjectName $obj.Id $Headers
}