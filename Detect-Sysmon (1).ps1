<#
.SYNOPSIS
    Intune detection: Sysmon service running and the applied config matches.
    Update $ExpectedHash whenever sysmonconfig.xml changes:
        (Get-FileHash .\sysmonconfig.xml -Algorithm SHA256).Hash
#>
$ExpectedHash = 'E79F87280C5EF47A96D9916C1066EADA3620D3756F6DF89A8DC83E3D90DD13D0'

$svc     = Get-Service -Name 'Sysmon*' -ErrorAction SilentlyContinue | Where-Object Name -notlike 'SysmonDrv*'
$applied = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\EUC\Sysmon' -ErrorAction SilentlyContinue).ConfigHash

if ($svc.Status -eq 'Running' -and $applied -eq $ExpectedHash) {
    Write-Output 'Detected'
    exit 0
}
exit 1
