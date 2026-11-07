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
Copy-Item "$PSScriptRoot\wintun.dll" (Join-Path $dir "wintun.dll") -Force
# Add to the machine PATH on the raw registry value (keeps %VARS% unexpanded), with a backup first.
$k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$p = (Get-Item -LiteralPath $k).GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
if ($p -and (@($p -split ';') -notcontains $dir)) {
  $b = Join-Path $env:ProgramData $cfg.BRAND_DISPLAY; New-Item -ItemType Directory -Force -Path $b | Out-Null
  Set-Content -LiteralPath (Join-Path $b 'path-backup.txt') -Value $p
  Set-ItemProperty -LiteralPath $k -Name Path -Value ($p.TrimEnd(';') + ';' + $dir) -Type ExpandString
}
& $exe service install
& $exe service start
Write-Host "$name service installed and running. Open a new terminal, then: $name up --setup-key <KEY>"
if ($SetupKey) { & $exe up --setup-key $SetupKey }
