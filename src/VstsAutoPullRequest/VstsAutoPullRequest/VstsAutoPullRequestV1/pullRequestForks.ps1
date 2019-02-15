[CmdletBinding()]
param(
)

# Dot source Utility functions.
. $PSScriptRoot/apiHelpers.ps1

$global:ErrorActionPreference = 'Stop'
$global:__vstsNoOverrideVerbose = $true
Trace-VstsEnteringInvocation $MyInvocation
# Import-VstsLocStrings "$PSScriptRoot\task.json"


#define object winth common parameters
$requestObject=@{
    headers = $null
    APIVersion = "5.1-preview"
    buildNumber = $null
    devInstance = $null
    apisInstance = $null
    isautocomplete = $true
    issquashmerge = $false
    exceptOnError = "continue"
    collectionId = $null
}

# Get inputs.
Write-Output "Inputs:"

$connectionMethod = Get-VstsInput -Name 'connectionmethod' -Require
switch ($connectionMethod) {
    "oauth" {
        $requestObject.headers = Combine-Headers
    }
    "pat" {
        $PAT = Get-VstsInput -Name 'pattoken' -Require
        $requestObject.headers = Combine-Headers -patToken $PAT
    }
}

$requestObject.instance = ($env:SYSTEM_TASKDEFINITIONSURI).split('//').GetValue(2).Split('.').GetValue(0)
$requestObject.buildNumber = "$env:BUILD_BUILDNUMBER"
$requestObject.devInstance = "https://dev.azure.com/$instance/"
$requestObject.apisInstance = "https://$instance.visualstudio.com/DefaultCollection/_apis/"
$requestObject.collectionId = $env:system_collectionId

$sourceProject = Get-VstsInput -Name 'sourceProject' -Require
$sourceRepositoryName = Get-VstsInput -Name 'sourceRepository' -Require
$sourceRefName = Get-VstsInput -Name 'sourceRefName' -Require
Write-Host "Source Project: $sourceProject"
Write-Host "Source Repository: $sourceRepositoryName"
Write-Host "Source Branch: $sourceRefName"
$sourceRepository = Get-SourceRepository -requestObject $requestObject -sourceProject $sourceProject -sourceRepository $sourceRepositoryName
$sourceRepository.sourceRefName = $sourceRefName

$ismultitargets = Get-VstsInput -Name 'ismultitargets' -Require -AsBool
if ($true -eq $ismultitargets) {
    $useallforks = Get-VstsInput -Name 'useallforks' -Require -AsBool
    if ($true -eq $useallforks) {
        $targetRepositoriesList = Get-AllForks -requestObject $requestObject -sourceRepo $sourceRepository
        $targetRefName = Get-VstsInput -Name 'targetrefnamemulti' -Require
        Write-Host "Target Repositories: all forks"
        Write-Host "Target Branch: $targetRefName"
    }
    else {
        $targetRepositoriesMulti = Get-VstsInput -Name 'targetrepositoriesmulti' -Require
        $targetRefName = Get-VstsInput -Name 'targetrefnamemulti' -Require
        Write-Host "Target Repositories: $targetRepositoriesMulti"
        Write-Host "Target Branch: $targetRefName"
        $targetRepositoriesList = $targetRepositoriesMulti.Split(',').Trim()        
    }
}
else {
    $targetRepository = Get-VstsInput -Name 'targetRepository' -Require
    $targetRefName = Get-VstsInput -Name 'targetRefName' -Require
    Write-Host "Target Repository: $targetRepository"
    Write-Host "Target Branch: $targetRefName"
}

$requestObject.isautocomplete = Get-VstsInput -Name 'isautocomplete' -AsBool
Write-Host "Autocomplete enabled: $($requestObject.isautocomplete)" 
if ($true -eq $requestObject.isautocomplete) {
    $requestObject.issquashmerge = Get-VstsInput -Name 'issquashmerge' -AsBool
    Write-Host "Squash merge enabled: $($requestObject.issquashmerge)" 
}   
$requestObject.APIVersion = Get-VstsInput -Name 'APIVersion' -Require
$requestObject.exceptOnError = Get-VstsInput -Name 'exceptiononerror' -Require

Write-Host "API Version: $($requestObject.APIVersion)"

if ($requestObject.CollectionId) {
    if ($true -eq $ismultitargets) {
        foreach ($tRepoID in $targetRepositoriesList) {
            Write-host "*****"
            $tRepo = Get-ForkedRepository -requestObject $requestObject -forkedRepoId $tRepoID 
            $tRepo.targetRefName = $targetRefName
            New-PullRequest -requestObject $requestObject -sourceRepo $sourceRepository -targetRepo $tRepo
        }
    }
    else {
        $tRepo = Get-ForkedRepository -requestObject $requestObject -forkedRepoId $targetRepository 
        $tRepo.targetRefName = $targetRefName
        New-PullRequest -requestObject $requestObject -sourceRepo $sourceRepository -targetRepo $tRepo            
    }
}
else {
    Write-VstsTaskWarning -Message "VSTS Collection not found. Do nothing"
}



