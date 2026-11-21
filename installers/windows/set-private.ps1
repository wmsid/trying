# Keeps the VPN adapter on the Private network profile.
#
# Windows labels the VPN adapter "Unidentified network" (it has no default gateway) and puts it on the Public
# profile, where block rules and "block all incoming connections" apply; it also forgets a manual change when the
# adapter reconnects. A scheduled task (installed by the setup) runs this at startup, whenever a network connects,
# and every 5 minutes. Only the adapter with this exact GUID is touched; Domain networks are left alone.
#
# Uses the Network List Manager COM API, which exists on Windows 7-11 and works with PowerShell 2.0
# (Set-NetConnectionProfile only exists on Windows 8 and later).
param([Parameter(Mandatory = $true)][string]$AdapterGuid)

$ErrorActionPreference = 'Stop'
$want = $AdapterGuid.Trim('{}').ToLowerInvariant()
$NLM_PRIVATE = 1
$NLM_DOMAIN = 2

try {
    $nlm = [Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]'DCB00C01-570F-4A9B-8D69-199FDBA5723B'))
    foreach ($conn in $nlm.GetNetworkConnections()) {
        $id = ([string]$conn.GetAdapterId()).Trim('{}').ToLowerInvariant()
        if ($id -ne $want) { continue }
        $net = $conn.GetNetwork()
        $cat = $net.GetCategory()
        if ($cat -ne $NLM_PRIVATE -and $cat -ne $NLM_DOMAIN) {
            $net.SetCategory($NLM_PRIVATE)
        }
    }
    exit 0
} catch {
    exit 1
}
