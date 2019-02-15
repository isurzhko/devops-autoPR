
## Pull Request Automation ##

The **Pull Request Automation** task can help you to automate pull requests creation in case if you have a lot of forked repositories and need to update them as soon as core repository successfully tested.

Currently, this task supports two modes: manual and helper
Manual mode allows you to fill all fields but doesn't check if data entered correctly
Helper mode works if you use devops service connection with type "Azure Repos/Team Foundation Server"


### Learn More
The [source](https://eshopworld.visualstudio.com/evo-core/_git/devops-vstsautopr) to this extension is available. Feel free to take, fork, and extend.

  ### Quick steps to get started ###
 
1. Add **Pull Request Automation** task to the pipeline

2. Choose authentication method 
2.1 For PATToken fill the PATToken field with secret variable, defined in variables section of pipeline
2.2 For OAuth enable checkbox  *Allow scripts to access the OAuth token*

3. If use enable helper checkbox, you'll need to select devops service connection with type *Azure Repos/Team Foundation Server* from pick list. Then you'll need to select collection from next pick list (collection need for rest api, which get forked repositories)

4. Select or manually fill *source project*, *source repository* and *source branch name*

5. Select target repository(s). Single select or multi-select depends on checkboxes in a definition. If you'll fill repository(s) manually, you must remember that only ID's (not names) need to be used

6. Save the definition.

6. Queue a new build or create a new release.

  

### Known issue(s)
- None

### Minimum supported environments ###
- Azure DevOps

  

### Contributors ###
We thank the following contributor(s) for this extension:

  

### Feedback ###
- Add a review below.