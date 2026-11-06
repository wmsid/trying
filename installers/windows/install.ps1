# Run as Administrator. Installs the service; optionally connects:
#   .\install.ps1 -SetupKey abcd
param([string]$SetupKey = "")
$ErrorActionPreference = "Stop"
$cfg = @{}; Get-Content "$PSScriptRoot\brand.env" | Where-Object { $_ -match '^\w+=' } |
  ForEach-Object { $k,$v = $_ -split '=',2; $cfg[$k] = $v }
$name = $cfg.BRAND_NAME
$dir  = Join-Path $env:ProgramFiles $name
New-Item -ItemType Directory -Force $dir | Out-Null
$exe = Join-Path $dir "$name.exe"
if (Get-Service -Name $name -ErrorAction SilentlyContinue) { & $exe service stop 2>$null; & $exe service uninstall 2>$null }
Copy-Item "$PSScriptRoot\$name.exe" $exe -Force
$machine = [Environment]::GetEnvironmentVariable("Path","Machine")
if ($machine -notlike "*$dir*") { [Environment]::SetEnvironmentVariable("Path","$machine;$dir","Machine") }
& $exe service install
& $exe service start
Write-Host "$name service installed and running. Open a new terminal, then: $name up --setup-key <KEY>"
if ($SetupKey) { & $exe up --setup-key $SetupKey }
