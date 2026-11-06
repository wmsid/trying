$ErrorActionPreference = "Stop"
$name = ((Get-Content "$PSScriptRoot\brand.env" | Where-Object { $_ -match '^BRAND_NAME=' }) -split '=',2)[1]
$exe = Join-Path $env:ProgramFiles "$name\$name.exe"
if (Test-Path $exe) { & $exe down 2>$null; & $exe service stop 2>$null; & $exe service uninstall }
Remove-Item -Recurse -Force (Join-Path $env:ProgramFiles $name) -ErrorAction SilentlyContinue
