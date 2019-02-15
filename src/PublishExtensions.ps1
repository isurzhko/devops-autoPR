param(
    [string] $publisher,
    [string] $pat
)

$path = npm prefix -g
$tfxCli = Join-Path $path "node_modules\tfx-cli\_build\tfx-cli.js"

$ext = Get-ChildItem -Path . -Filter *.vsix -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if($ext) {
    Invoke-Expression -Command "node $tfxCli extension publish --publisher $publisher --vsix '$ext' -t $pat"
}else {
    Write-Warning "No extensions found!"
}
