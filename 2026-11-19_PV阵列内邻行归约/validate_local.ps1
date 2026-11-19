$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$linuxRoot = '/mnt/' + $root.Substring(0,1).ToLower() + '/' + ($root.Substring(3) -replace '\\','/')
& wsl.exe -d Ubuntu-24.04 -- bash -lc "cd '$linuxRoot' && bash ./validate_local_wsl.sh"
if ($LASTEXITCODE -ne 0) { throw "WSL local validation failed: $LASTEXITCODE" }
