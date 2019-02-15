[CmdletBinding()]
param()

$global:ErrorActionPreference = 'Stop'

Trace-VstsEnteringInvocation $MyInvocation

$instance = ($env:SYSTEM_TASKDEFINITIONSURI).split('//').GetValue(2).Split('.').GetValue(0)
$buildNumber = "$env:BUILD_BUILDNUMBER"
$devInstance = "https://dev.azure.com/$instance/"
$apisInstance = "https://$instance.visualstudio.com/DefaultCollection/_apis/"
$collection = $null
$prStatuses = @{
    "conflicts"        = @{
        "message" = "Pull request merge failed due to conflicts."
        "state"   = "bad"
    }
    "failure"          = @{
        "message" = "Pull request merge failed."
        "state"   = "bad"
    }
    "notset"           = @{
        "message" = "Status is not set"
        "state"   = "wait"
    }
    "queued"           = @{
        "message" = "Pull request merge is queued."
        "state"   = "wait"
    }    
    "rejectedbypolicy" = @{
        "message" = "Pull request merge rejected by policy."
        "state"   = "bad"
    }
    "succeeded"        = @{
        "message" = "Pull request merge succeeded."
        "state"   = "success"
    }   
}

<#
    Get Collection ID of source project
#>
Function Get-VSTSCollection {
    try {
        [uri] $PRUri = $devInstance + "/_api/_common/GetJumpList?showTeamsOnly=false&__v=5&navigationContextPackage={}&showStoppedCollections=false"
        $Response = Invoke-RestMethod -Uri $PRUri `
            -Method GET `
            -ContentType "application/json" `
            -Headers $headers 
        
        $foundCollection = $null    

        foreach ($collection in $Response.__wrappedArray) {
            foreach ($project in $collection.projects) {
                if ($project.name.ToLower() -eq $sourceProject.ToLower()) {
                    $foundCollection = $collection
                    Write-Host "VSTS Collection found"
                }
            }
        }
        return $foundCollection  
    }
    Catch {
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-VstsTaskError -Message (ConvertFrom-Json $responseBody).message
        if ($exceptOnError -eq "break") {throw}
    }
}

<#
  Get target repo object
#>
Function Get-ForkedRepository {
    param (
        [string] $forkedRepoId
    )       
    try {
        [uri] $PRUri = $devInstance + "/_apis/git/repositories/$($forkedRepoId)?api-version=$APIVersion"
        Write-Host "Searching for forked repository $forkedRepoId"
        $Response = Invoke-RestMethod -Uri $PRUri `
            -Method GET `
            -ContentType "application/json" `
            -Headers $headers 

        Write-Host "Found repository with name $($Response.name) in project $($Response.project.name)"
        return $Response
    }
    Catch {
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-VstsTaskError -Message (ConvertFrom-Json $responseBody).message
        if ($exceptOnError -eq "break") {throw}
    }
}

Function Get-AllForks {
    try {
        [uri] $PRUri = $devInstance + $sourceProject + "/_apis/git/repositories/$($sourceRepository)/forks/$($CollectionId)?api-version=$APIVersion"
        Write-Host "Searching for forks"
        $Response = Invoke-RestMethod -Uri $PRUri `
            -Method GET `
            -ContentType "application/json" `
            -Headers $headers 

        $forks = @()
        Write-Host "Found forks:"
        Foreach ($repo in $response.value) {
            $forks += $repo.id
            Write-Host "   $($repo.name)"
        }    
        return $forks
    }
    Catch {
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-VstsTaskError -Message (ConvertFrom-Json $responseBody).message
        if ($exceptOnError -eq "break") {throw}
    }   
}




<#
  Get source repo object
 #>
Function Get-SourceRepository {
    try {
        [uri] $Uri = $devInstance + $sourceProject + "/_apis/git/repositories?api-version=$APIVersion"
        $Response = Invoke-RestMethod -Uri $Uri `
            -Method GET `
            -ContentType "application/json" `
            -Headers $headers 

        $foundRepo = $null
        foreach ($repo in $Response.value) {
            if ($repo.name.ToLower() -eq $sourceRepository) {
                $foundRepo = $repo
                Write-Host "Source repo data loaded"
            }
        } 
        return $foundRepo
    }
    Catch {
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-VstsTaskError -Message (ConvertFrom-Json $responseBody).message
        if ($exceptOnError -eq "break") {throw}
    }
}

Function Abandon-ExistingPullRequests {
    param (
        $targetRepo
    )

    $sourceRepositoryId = (Get-SourceRepository).id
    #search active PR and abandon them
    Write-Output "Searching for active pullrequests to $($targetRepo.project.name)/$($targetRepo.name)/$($targetRefname) "

    [uri] $existingPR = $devInstance + $targetRepo.project.name + "/_apis/git/repositories/$($targetRepo.id)/pullRequests?api-version=$APIVersion&searchCriteria.status=active&searchCriteria.sourceRefName=$($sourceRefName)&searchCriteria.targetRefName=$($targetRefName)"
    $Response = $null
    $Response = Invoke-RestMethod -Uri $existingPR `
        -Method GET `
        -ContentType "application/json" `
        -Headers $headers 
    
    if ($Response.count -gt 0) {
        Write-Output " Found $($response.count) pull request(s) with state=active"
        foreach ($repo in $response.value) {
            if ($repo.forkSource.repository.id -eq $sourceRepositoryId) {
                $abandonJson = @{"status" = "abandoned"} | ConvertTo-Json
                [uri] $abandonUri = $devInstance + $targetRepo.project.name + "/_apis/git/repositories/$($targetRepo.id)/pullrequests/$($repo.pullRequestId)?api-version=5.1-preview"
                $Response = Invoke-RestMethod -Uri $abandonUri `
                    -Method PATCH `
                    -ContentType "application/json" `
                    -Headers $headers `
                    -Body $abandonJson
                Write-Output " Pull request $($repo.pullRequestId) state set to abandoned"    
            }
            else {
                Write-output "Pull request $($repo.pullRequestId) was not created from $($sourceProject)/$($sourceRepository). Ignoring"
            }
        }
    }
}


<#
    Create new pull request and autocomplete it
#>    
Function New-PullRequest {   
    param (
        $targetRepo
    )    

    try {  
        $sourceBranch = $sourceRefName
        $targetBranch = $targetRefName

        Abandon-ExistingPullRequests $targetRepo

        #create new PR
        [uri] $PRUri = $apisInstance + "git/repositories/$($targetRepo.id)/pullRequests?api-version=$APIVersion"
        $commitMessage = "PR from $($sourceProject)/$($sourceRepository) to $($targetRepo.Project.Name)/$($targetRepo.name)/$($targetRefName) with autocomlete. Build number is $buildNumber"
        $descriptionMessage = "PR from $($sourceRepository):$($sourceRefName) to $($targetRepo.name):$($targetRefName) branch with autocomlete. Build number is $buildNumber"

        $jsonPR = @{
            "sourceRefName" = $sourceBranch
            "targetRefName" = $targetBranch
            "Title"         = $commitMessage
            "Description"   = $descriptionMessage
            "ForkSource"    = @{
                "Repository" = @{
                    "id"            = $sourceRepo.id
                    "name"          = $sourceRepo.name
                    "url"           = $sourceRepo.RemoteUrl
                    "project"       = @{
                        "id"          = $sourceRepo.project.id
                        "name"        = $sourceRepo.project.name
                        "description" = $sourceRepo.project.description
                        "url"         = $sourceRepo.project.url
                    }
                    "defaultBranch" = $sourceRepo.defaultBranch
                    "remoteUrl"     = $sourceRepo.remoteUrl
                    "sshUrl"        = $sourceRepo.sshUrl
                }
            }
        }

        $jsonBody = $jsonPR | ConvertTo-Json -Depth 10
        Write-Output "Sending a REST call to create pull request from $($sourceProject)/$($sourceRepository) to $($targetRepo.Project.Name)/$($targetRepo.name)/$($targetRefName)"
        $Response = Invoke-RestMethod -Uri $PRUri `
            -Method Post `
            -ContentType "application/json" `
            -Headers $headers `
            -Body $jsonBody

        # Get new PR info from response
        $pullRequestId = $Response.pullRequestId
        $pullReuestArtifactId = $Response.artifactId
        $pullRequestCreatedBy = $Response.createdBy.id
        $pullRequestTitle = $Response.title

        ##Add workitems to PR
    
        #get commits from new PR
        [uri] $pullRequestCommitsUrl = $devInstance + "_apis/git/repositories/$($targetRepo.id)/pullRequests/" + $pullRequestId + "?api-version=$($APIVersion)&includeCommits=true"
        $response = $null
        $Response = Invoke-RestMethod -Uri $pullRequestCommitsUrl `
            -Method GET `
            -ContentType "application/json" `
            -Headers $headers
        Write-Output "Got commits list from new pull request"
        $commits = @()
        foreach ($resp in $response.commits.commitid) {
            $commits += $resp
            Write-Output "  Commit found: $($resp.Substring(0,8))"
        }
    
        #get workitems from source branch    
        [uri] $sourceRepoWorkItemsUrl = $devInstance + $sourceProject + "/_apis/git/repositories/$($sourceRepository)/commits?api-version=$($APIVersion)&searchCriteria.includeWorkItems=true"
        $response = $null
        $Response = Invoke-RestMethod -Uri $sourceRepoWorkItemsUrl `
            -Method GET `
            -ContentType "application/json" `
            -Headers $headers 
        $workitems = @()
        foreach ($resp in $response.value) {
            if ($resp.commitId -in $commits) {
                if ($resp.workitems.count -gt 0){
                    $workitems += $resp.workitems
                    Write-Output " For commit $($resp.commitId.Substring(0,8)) found work items:"
                    foreach ($wi in $resp.workitems) {
                        Write-Output "  $($wi.id)"
                    }
                }
            }
        }
        $workitems = @($workitems | Group-Object 'id','url' | ForEach-Object{ $_.Group | Select-Object 'id','url' -First 1})
        Write-host "Count of unique work items from source repository: $($workitems.count)" 
        foreach ($wi in $workitems) {
         write-output " $($wi.id): $($wi.url)"
        } 
            
        # REST call to set work items on Pull Request
        if ($workitems.count -gt 0) {
            foreach ($workitem in $workitems) {
                $wiId = $workitem.id
                [uri] $wiUri = $apisInstance + "wit/workitems/$($wiId)?api-version=5.1-preview"
                $body = @(
                    @{
                        op    = 'add'
                        path  = '/relations/-'
                        value = @{
                            rel        = "ArtifactLink"
                            url        = $pullReuestArtifactId
                            attributes = @{  
                                name = 'Pull request'
                            }
                        }
                    }
                )
                $jsonbody = ConvertTo-Json $body -Depth 10
                $Response = $null
                $Response = Invoke-RestMethod -Uri $wiUri `
                    -Method PATCH `
                    -ContentType application/json-patch+json `
                    -Headers $headers `
                    -Body $jsonbody
                Write-Output "Added work item $wiId to pull request"
            }
        }

        if ($true -eq $isautocomplete) {
            # Set PR to auto-complete
            $setAutoComplete = @{
                "autoCompleteSetBy" = @{
                    "id" = $pullRequestCreatedBy
                }
                "completionOptions" = @{
                    "mergeCommitMessage" = $pullRequestTitle
                    "deleteSourceBranch" = $false
                    "squashMerge"        = $issquashmerge
                    "bypassPolicy"       = $false
                }
            }
            $setAutoCompleteJson = ($setAutoComplete | ConvertTo-Json -Depth 5)
            Write-Output "Sending a REST call to set auto-complete on the newly created pull request"
        
            # REST call to set auto-complete on Pull Request
            $pullRequestUpdateUrl = ($apisInstance + "git/repositories/$($targetRepo.id)/pullRequests/" + $pullRequestId + "?api-version=$APIVersion")
            $Response = Invoke-RestMethod -Uri $pullRequestUpdateUrl `
                -Method PATCH `
                -ContentType "application/json" `
                -Headers $headers `
                -Body $setAutoCompleteJson 
            Write-Output "Pull request set to auto-complete"
            #Get pull request and check it's completion status
            $isCompleted = $false
            $retryCounter = 0 # exit from retry after 3 minutes when counter will be 18
            $pullRequestGetUrl = ($apisInstance + "git/repositories/$($targetRepo.Id)/pullRequests/" + $pullRequestId + "?api-version=$APIVersion")

            While ($isCompleted -eq $false -and $retryCounter -lt 18) {
                $Response = Invoke-RestMethod -Uri $pullRequestGetUrl `
                    -Method GET `
                    -ContentType "application/json" `
                    -Headers $headers 
                $status = $Response.mergeStatus.toLower()
                if ($prStatuses.$status) {
                    switch ($prStatuses.$status.state) {
                        "bad" { 
                            Write-VstsTaskWarning -Message "PR status is $($prStatuses.$status.state): $($prStatuses.$status.message)"
                            $isCompleted = $true 
                        }
                        "success" { 
                            write-host "PR status is $($prStatuses.$status.state): $($prStatuses.$status.message)"
                            $isCompleted = $true 
                        }
                        "wait" { 
                            write-host "PR status is $($prStatuses.$status.state). In 10 seconds we will try to update PR status"
                            $retryCounter++
                            Start-Sleep 10
                        }
                    }
                }
            }
        } #if autocomplete
        else {  # no need autocomplete
            $pullRequestGetUrl = ($apisInstance + "git/repositories/$($targetRepo.Id)/pullRequests/" + $pullRequestId + "?api-version=$APIVersion")
            $Response = Invoke-RestMethod -Uri $pullRequestGetUrl `
                -Method GET `
                -ContentType "application/json" `
                -Headers $headers 
            $status = $Response.mergeStatus.toLower()
            Write-Output "Current pull request status is $status. Autocomplete disabled."
        }    
    }
    Catch {
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-VstsTaskError -Message (ConvertFrom-Json $responseBody).message
        if ($exceptOnError -eq "break") {throw}
    }

}


Import-VstsLocStrings "$PSScriptRoot\task.json"
$global:__vstsNoOverrideVerbose = $true

# Get inputs.
Write-Host "Inputs:"
$connectionMethod = Get-VstsInput -Name 'connectionmethod' -Require
switch ($connectionMethod) {
    "oauth" {
        $headers = @{ Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN" }
        Write-Host "Using OAuth authorization "
    }
    "pat" {
        $PAT = Get-VstsInput -Name 'pattoken' -Require
        $User = "" 
        $Base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $User, $PAT)))
        $headers = @{Authorization = ("Basic {0}" -f $Base64AuthInfo)} 
        Write-Host "Using PAT Token authorization: $PAT"
    }
}

$sourceProject = Get-VstsInput -Name 'sourceProject' -Require
$sourceRepository = Get-VstsInput -Name 'sourceRepository' -Require
$sourceRefName = Get-VstsInput -Name 'sourceRefName' -Require
Write-Host "Source Project: $sourceProject"
Write-Host "Source Repository: $sourceRepository"
Write-Host "Source Branch: $sourceRefName"

$ismultitargets = Get-VstsInput -Name 'ismultitargets' -Require -AsBool

if ($true -eq $ismultitargets) {
    $useallforks = Get-VstsInput -Name 'useallforks' -Require -AsBool
    if ($true -eq $useallforks) {
        $targetRepositoriesList = Get-AllForks
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

$isautocomplete = Get-VstsInput -Name 'isautocomplete' -AsBool
Write-Host "Autocomplete enabled: $isautocomplete" 
if ($true -eq $isautocomplete) {
    $issquashmerge = Get-VstsInput -Name 'issquashmerge' -AsBool
    Write-Host "Squash merge enabled: $issquashmerge" 
}   
$APIVersion = Get-VstsInput -Name 'APIVersion' -Require
$exceptOnError = Get-VstsInput -Name 'exceptiononerror' -Require

Write-Host "API Version: $APIVersion"

#get source CollectionID
#$collection = Get-VSTSCollection
$collectionId = $env:system_collectionId
if ($CollectionId) {
    $sourceRepo = Get-SourceRepository
    if ($true -eq $ismultitargets) {
        foreach ($tRepoName in $targetRepositoriesList) {
            Write-host "*****"
            $tRepo = Get-ForkedRepository $tRepoName
            New-PullRequest $tRepo
        }
    }
    else {
        $tRepo = Get-ForkedRepository $targetRepository
        New-PullRequest $tRepo            
    }
}
else {
    Write-VstsTaskWarning -Message "VSTS Collection not found. Do nothing"
}



