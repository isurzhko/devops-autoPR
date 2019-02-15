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

###########################################################
#       Combine headers for request
###########################################################
Function Combine-Headers {
    [CmdletBinding(DefaultParameterSetName = 'OAuth')]
    param (
        [Parameter(Mandatory,
            ParameterSetName = 'PAT')]
            [string]$patToken
    )
    
    switch ($PSCmdlet.ParameterSetName.ToLower()) {
        "oauth" {
            $headers = @{ Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN" }
            Write-Output "Using OAuth authorization "
        }
        "pat" {
            $User = "" 
            $Base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $User, $patToken)))
            $headers = @{Authorization = ("Basic {0}" -f $Base64AuthInfo)} 
            Write-Host "Using PAT Token authorization: $patToken"
        }
    }
    return $headers
}

###########################################################
#       Get Collection ID of source project
###########################################################
Function Get-VSTSCollection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][PSCustomObject] $requestObject,
        [Parameter(Mandatory=$true, Position=2)][PSCustomObject] $sourceRepo
    )
    try {
        [uri] $PRUri = $requestObject.devInstance + "/_api/_common/GetJumpList?showTeamsOnly=false&__v=5&navigationContextPackage={}&showStoppedCollections=false"
        $Response = Invoke-RestMethod -Uri $PRUri `
            -Method GET `
            -ContentType "application/json" `
            -Headers $requestObject.headers 
        
        $foundCollection = $null    

        foreach ($collection in $Response.__wrappedArray) {
            foreach ($project in $collection.projects) {
                if ($project.name.ToLower() -eq $sourceRepo.Project.name.ToLower()) {
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
        if ($requestObject.exceptOnError -eq "break") {throw}
        else {return $null}
    }
}

###########################################################
#       Get Forked Repository by ID 
###########################################################
Function Get-ForkedRepository {
    param (
        [Parameter(Mandatory=$true)][PSCustomObject] $requestObject,
        [Parameter(Mandatory=$true)][string] $forkedRepoId
    )       
    try {
        [uri] $PRUri = $requestObject.devInstance + "/_apis/git/repositories/$($forkedRepoId)?api-version=$($requestObject.APIVersion)"
        Write-Host "Searching for forked repository $forkedRepoId"
        $Response = $null
        $Response = Invoke-RestMethod -Uri $PRUri `
            -Method GET `
            -ContentType "application/json" `
            -Headers $requestObject.headers 

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
        if ($requestObject.exceptOnError -eq "break") {throw}
        return $null
    }
}

###########################################################
#       Get source Repository by Project name and Repository Name
###########################################################
Function Get-SourceRepository {
    param (
        [Parameter(Mandatory=$true)][PSCustomObject] $requestObject,
        [Parameter(Mandatory=$true)][string] $sourceProject,
        [Parameter(Mandatory=$true)][string] $sourceRepository
    )    
    try {
        [uri] $Uri = $requestObject.devInstance + $sourceProject + "/_apis/git/repositories?api-version=$($requestObject.APIVersion)"
        $Response = Invoke-RestMethod -Uri $Uri `
            -Method GET `
            -ContentType "application/json" `
            -Headers $requestObject.headers 

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
        if ($requestObject.exceptOnError -eq "break") {throw}
        return $null
    }
}



###########################################################
#       Get all Forked Repositories by source Project name and and Repository Name
###########################################################
Function Get-AllForks {
    param (
        [Parameter(Mandatory=$true)][PSCustomObject] $requestObject,
        [Parameter(Mandatory=$true)][PSCustomObject] $sourceRepo
    )     
    try {
        [uri] $PRUri = $requestObject.devInstance + $sourceRepo.Project.name + "/_apis/git/repositories/$($sourceRepo.id)/forks/$($sourceRepo.CollectionId)?api-version=$($requestObject.APIVersion)"
        Write-Host "Searching for forks"
        $Response = Invoke-RestMethod -Uri $PRUri `
            -Method GET `
            -ContentType "application/json" `
            -Headers $requestObject.headers 

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
        if ($requestObject.exceptOnError -eq "break") {throw}
        return $null
    }   
}

###########################################################
#       Abandon Existing Pull Requests
###########################################################
Function Abandon-ExistingPullRequests {
    param (
        [Parameter(Mandatory=$true)][PSCustomObject]$requestObject,
        [Parameter(Mandatory=$true)][PSCustomObject]$sourceRepo,
        [Parameter(Mandatory=$true)][PSCustomObject]$targetRepo
    )
    #search active PR and abandon them
    Write-Output "Searching for active pullrequests to $($targetRepo.project.name)/$($targetRepo.name)/$($targetRepo.targetRefname) "

    [uri] $existingPR = $requestObject.devInstance + $targetRepo.project.name + "/_apis/git/repositories/$($targetRepo.id)/pullRequests?api-version=$($requestObject.APIVersion)&searchCriteria.status=active&searchCriteria.sourceRefName=$($sourceRepo.sourceRefName)&searchCriteria.targetRefName=$($targetRepo.targetRefName)"
    $Response = $null
    $Response = Invoke-RestMethod -Uri $existingPR `
        -Method GET `
        -ContentType "application/json" `
        -Headers $requestObject.headers 
    
    if ($Response.count -gt 0) {
        Write-Output " Found $($response.count) pull request(s) with state=active"
        foreach ($repo in $response.value) {
            if ($repo.forkSource.repository.id -eq $sourceRepo.Id) {
                $abandonJson = @{"status" = "abandoned"} | ConvertTo-Json
                [uri] $abandonUri = $requestObject.devInstance + $targetRepo.project.name + "/_apis/git/repositories/$($targetRepo.id)/pullrequests/$($repo.pullRequestId)?api-version=5.1-preview"
                $Response = Invoke-RestMethod -Uri $abandonUri `
                    -Method PATCH `
                    -ContentType "application/json" `
                    -Headers $requestObject.headers `
                    -Body $abandonJson
                Write-Output " Pull request $($repo.pullRequestId) state set to abandoned"    
            }
            else {
                Write-output "Pull request $($repo.pullRequestId) was not created from $($sourceRepo.Project.Name)/$($sourceRepo.name). Ignoring"
            }
        }
    }
}

###########################################################
#       Create New Pull Request
###########################################################
Function Create-PullRequest {
    param (
        [Parameter(Mandatory=$true)][PSCustomObject] $requestObject,
        [Parameter(Mandatory=$true)][PSCustomObject] $sourceRepo,
        [Parameter(Mandatory=$true)][PSCustomObject] $targetRepo
    )    
    [uri] $PRUri = $requestObject.apisInstance + "git/repositories/$($targetRepo.id)/pullRequests?api-version=$($requestObject.APIVersion)"
    $commitMessage = "PR from $($sourceRepo.Project.Name)/$($sourceRepo.name) to $($targetRepo.Project.Name)/$($targetRepo.name)/$($targetRepo.targetRefName) with autocomlete. Build number is $($requestObject.buildNumber)"
    $descriptionMessage = "PR from $($sourceRepo.name):$($sourceRepo.sourceRefName) to $($targetRepo.name):$($targetRepo.targetRefName) branch with autocomlete. Build number is $($requestObject.buildNumber)"

    $jsonPR = @{
        "sourceRefName" = $sourceRepo.sourceRefName
        "targetRefName" = $targetRepo.targetRefname
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
    Write-Output "Sending a REST call to create pull request from $($sourceRepo.Project.Name)/$($sourceRepo.Name) to $($targetRepo.Project.Name)/$($targetRepo.name)/$($targetRepo.targetRefName)"
    $Response = Invoke-RestMethod -Uri $PRUri `
        -Method Post `
        -ContentType "application/json" `
        -Headers $requestObject.headers `
        -Body $jsonBody
}

###########################################################
#       Add Work Items to Pull Request
###########################################################
Function Add-WorkItemsToPR {
    param (
        [Parameter(Mandatory=$true)][PSCustomObject] $requestObject,
        [Parameter(Mandatory=$true)][PSCustomObject] $sourceRepo,
        [Parameter(Mandatory=$true)][PSCustomObject] $targetRepo,
        [Parameter(Mandatory=$true)][PSCustomObject] $pullRequest
    )
   
        #get commits from new PR
        [uri] $pullRequestCommitsUrl = $requestObject.devInstance + "_apis/git/repositories/$($targetRepo.id)/pullRequests/" + $pullRequest.Id + "?api-version=$($requestObject.APIVersion)&includeCommits=true"
        $response = $null
        $Response = Invoke-RestMethod -Uri $pullRequestCommitsUrl `
            -Method GET `
            -ContentType "application/json" `
            -Headers $requestObject.headers
        Write-Output "Got commits list from new pull request"
        $commits = @()
        foreach ($resp in $response.commits.commitid) {
            $commits += $resp
            Write-Output "  Commit found: $($resp.Substring(0,8))"
        }
    
        #get workitems from source branch    
        [uri] $sourceRepoWorkItemsUrl = $requestObject.devInstance + $sourceRepo.Project.name + "/_apis/git/repositories/$($sourceRepo.id)/commits?api-version=$($APIVersion)&searchCriteria.includeWorkItems=true"
        $response = $null
        $Response = Invoke-RestMethod -Uri $sourceRepoWorkItemsUrl `
            -Method GET `
            -ContentType "application/json" `
            -Headers $requestObject.headers 
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
                [uri] $wiUri = $requestObject.apisInstance + "wit/workitems/$($wiId)?api-version=5.1-preview"
                $body = @(
                    @{
                        op    = 'add'
                        path  = '/relations/-'
                        value = @{
                            rel        = "ArtifactLink"
                            url        = $pullRequest.ArtifactId
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
                    -Headers $requestObject.headers `
                    -Body $jsonbody
                Write-Output "Added work item $wiId to pull request"
            }
        }
}

###########################################################
#       Set Pull Request to Autocomplete
###########################################################
Function Set-PullRequestAutocomplete {
    param (
        [Parameter(Mandatory=$true)][PSCustomObject] $requestObject,
        [Parameter(Mandatory=$true)][PSCustomObject] $targetRepo,
        [Parameter(Mandatory=$true)][PSCustomObject] $pullRequest
    )
    $setAutoComplete = @{
        "autoCompleteSetBy" = @{
            "id" = $pullRequest.CreatedBy
        }
        "completionOptions" = @{
            "mergeCommitMessage" = $pullRequest.Title
            "deleteSourceBranch" = $false
            "squashMerge"        = $requestObject.issquashmerge
            "bypassPolicy"       = $false
        }
    }
    $setAutoCompleteJson = ($setAutoComplete | ConvertTo-Json -Depth 5)
    Write-Output "Sending a REST call to set auto-complete on the newly created pull request"

    # REST call to set auto-complete on Pull Request
    $pullRequestUpdateUrl = $requestObject.apisInstance + "git/repositories/$($targetRepo.id)/pullRequests/" + $pullRequest.Id + "?api-version=$($requestObject.APIVersion)"
    $Response = Invoke-RestMethod -Uri $pullRequestUpdateUrl `
        -Method PATCH `
        -ContentType "application/json" `
        -Headers $requestObject.headers `
        -Body $setAutoCompleteJson 
    Write-Output "Pull request set to auto-complete"
    #Get pull request and check it's completion status
    $isCompleted = $false
    $retryCounter = 0 # exit from retry after 3 minutes when counter will be 18
    $pullRequestGetUrl = ($requestObject.apisInstance + "git/repositories/$($targetRepo.Id)/pullRequests/" + $pullRequest.Id + "?api-version=$($requestObject.APIVersion)")

    While ($isCompleted -eq $false -and $retryCounter -lt 18) {
        $Response = Invoke-RestMethod -Uri $pullRequestGetUrl `
            -Method GET `
            -ContentType "application/json" `
            -Headers $requestObject.headers 
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
}

###########################################################
#       Get Pull Request Status
###########################################################
Function Get-PullRequestStatus {
    param (
        [Parameter(Mandatory=$true)][PSCustomObject] $requestObject,
        [Parameter(Mandatory=$true)][PSCustomObject] $targetRepo,
        [Parameter(Mandatory=$true)][PSCustomObject] $pullRequest
    )
    $pullRequestGetUrl = ($requestObject.apisInstance + "git/repositories/$($targetRepo.Id)/pullRequests/" + $pullRequest.Id + "?api-version=$($requestObject.APIVersion)")
    $Response = Invoke-RestMethod -Uri $pullRequestGetUrl `
        -Method GET `
        -ContentType "application/json" `
        -Headers $requestObject.headers 
    $status = $Response.mergeStatus.toLower()
    return $status
}

###########################################################
#       New pull request with all options
###########################################################
Function New-PullRequest {   
    param (
        [Parameter(Mandatory=$true)][PSCustomObject] $requestObject,
        [Parameter(Mandatory=$true)][PSCustomObject] $sourceRepo,
        [Parameter(Mandatory=$true)][PSCustomObject] $targetRepo
    )    

    try {  
        Abandon-ExistingPullRequests -requestObject $requestObject -sourceRepo $sourceRepo -targetRepo $targetRepo

        #create new PR
        Create-PullRequest -requestObject $requestObject -sourceRepo $sourceRepo -targetRepo $targetRepo

        # Get new PR info from response
        $pullRequest.Id = $Response.pullRequestId
        $pullRequestArtifact.Id = $Response.artifactId
        $pullRequest.CreatedBy = $Response.createdBy.id
        $pullRequest.Title = $Response.title

        #Add workitems to PR
        Add-WorkItemsToPR -requestObject $requestObject -sourceRepo $sourceRepo -targetRepo $targetRepo -pullRequest $pullRequest

        if ($true -eq $isautocomplete) {
            # Set PR to auto-complete
            Set-PullRequestAutocomplete -requestObject $requestObject -targetRepo $targetRepo -pullRequest $pullRequest
        } #if autocomplete
        else {  # no need autocomplete
            $status = Get-PullRequestStatus -requestObject $requestObject -targetRepo $targetRepo -pullRequest $pullRequest
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
        if ($requestObject.exceptOnError -eq "break") {throw}
    }
}