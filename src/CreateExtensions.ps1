$path = npm prefix -g

$tfxCli = Join-Path $path "node_modules\tfx-cli\_build\tfx-cli.js"

$extensions = Get-ChildItem -Path . -Filter *-extension.json -Recurse -Force

$extensions | % { $extensionArgs += $_.FullName + " " }

Save-Module -Name VstsTaskSdk -Path "." -MinimumVersion  0.11.0 -Force

New-Item -ItemType Directory -Path ".\VstsAutoPullRequest\ps_modules" -Force | Out-Null

Copy-Item -Path ".\azure-pipelines-tasks\Tasks\Common\*" -Destination ".\VstsAutoPullRequest\ps_modules\" -Recurse -Force

Get-ChildItem ".\VstsTaskSdk" | ForEach-Object {
    Copy-Item -Path ($_.FullName + '\*') -Destination ".\VstsAutoPullRequest\ps_modules\VstsTaskSdk\" -Recurse -Force
}

Invoke-WebRequest "https://vstsagenttools.blob.core.windows.net/tools/openssl/1.0.2/M138/openssl.zip" -OutFile openssl.zip

Expand-Archive openssl.zip -DestinationPath ".\VstsAutoPullRequest\ps_modules\VstsAzureHelpers_\openssl" -Force

Remove-Item openssl.zip

Get-ChildItem -Path ".\VstsAutoPullRequest\ps_modules\VstsAzureHelpers_\openssl" -Exclude *.exe, *.dll | Remove-Item -Force

Write-Output "Calling command: 'node $tfxCli extension create --manifest-globs $extensionArgs'"

Invoke-Expression -Command "node $tfxCli extension create --manifest-globs $extensionArgs"