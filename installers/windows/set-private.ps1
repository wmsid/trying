# Keeps the VPN adapter on the Private network profile.
#
# Windows puts a new VPN adapter on the Public profile, where block rules and "block all incoming connections"
# apply, and can reset it when the adapter is recreated. A scheduled task (installed by the setup) runs this at
# startup, whenever a network connects, and every 5 minutes. Only the VPN adapter is touched (matched by name and
# by its fixed GUID); Domain networks are left alone. The result of the last run is written to set-private.log.
#
# Windows 8+: Set-NetConnectionProfile by interface name. All versions (Windows 7 / PowerShell 2.0 too): the
# Network List Manager COM API by adapter GUID.
param(
    [Parameter(Mandatory = $true)][string]$AdapterGuid,
    [string]$InterfaceAlias = ''
)

$ErrorActionPreference = 'Stop'
$want = $AdapterGuid.Trim('{}').ToLowerInvariant()
$log = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'set-private.log'
$notes = @()
$NLM_PUBLIC = 0
$NLM_PRIVATE = 1

# 1) Windows 8+: by interface name
if ($InterfaceAlias -and (Get-Command Set-NetConnectionProfile -ErrorAction SilentlyContinue)) {
    try {
        $p = Get-NetConnectionProfile -InterfaceAlias $InterfaceAlias -ErrorAction Stop
        if ($p.NetworkCategory -eq 'Public') {
            Set-NetConnectionProfile -InterfaceAlias $InterfaceAlias -NetworkCategory Private -ErrorAction Stop
            $notes += "name ${InterfaceAlias}: Public -> Private"
        } else {
            $notes += "name ${InterfaceAlias}: already $($p.NetworkCategory)"
        }
    } catch {
        $notes += "name ${InterfaceAlias}: $($_.Exception.Message)"
    }
}

# 2) all versions: by adapter GUID
$found = $false
try {
    $nlm = [Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]'DCB00C01-570F-4A9B-8D69-199FDBA5723B'))
    foreach ($conn in $nlm.GetNetworkConnections()) {
        $id = ([string]$conn.GetAdapterId()).Trim('{}').ToLowerInvariant()
        if ($id -ne $want) { continue }
        $found = $true
        $net = $conn.GetNetwork()
        if ($net.GetCategory() -eq $NLM_PUBLIC) {
            $net.SetCategory($NLM_PRIVATE)
            $notes += "guid: Public -> Private"
        } else {
            $notes += "guid: already category $($net.GetCategory())"
        }
    }
    if (-not $found) { $notes += "guid: adapter not connected" }
} catch {
    $notes += "guid: $($_.Exception.Message)"
}

try {
    "$(Get-Date -Format s)  $($notes -join '; ')" | Out-File -FilePath $log -Encoding ascii
} catch { }
exit 0
