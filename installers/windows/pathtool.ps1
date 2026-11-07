# Adds/removes one directory on the machine PATH without ever shortening it.
# Works on the raw registry value (keeps %VARS% unexpanded), and saves a backup before any change.
param(
  [Parameter(Mandatory = $true)][ValidateSet('add', 'remove')][string]$Action,
  [Parameter(Mandatory = $true)][string]$Dir,
  [string]$BackupDir = ''
)
$ErrorActionPreference = 'Stop'
$k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$p = (Get-Item -LiteralPath $k).GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
if ([string]::IsNullOrEmpty($p)) { Write-Error 'Could not read PATH; leaving it unchanged.'; exit 1 }
$parts = @($p -split ';' | Where-Object { $_ -ne '' })
if ($Action -eq 'add') {
  if ($parts -contains $Dir) { exit 0 }
  if ($BackupDir -ne '') {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    Set-Content -LiteralPath (Join-Path $BackupDir 'path-backup.txt') -Value $p
  }
  $new = (($parts + $Dir) -join ';')
} else {
  $kept = @($parts | Where-Object { $_ -ne $Dir })
  if ($kept.Count -eq 0 -or $kept.Count -eq $parts.Count) { exit 0 }
  $new = ($kept -join ';')
}
Set-ItemProperty -LiteralPath $k -Name Path -Value $new -Type ExpandString
