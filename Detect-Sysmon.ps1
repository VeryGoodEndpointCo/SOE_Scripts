<#
.SYNOPSIS
    Intune Win32 detection script for built-in Sysmon + custom config.

.DESCRIPTION
    Detected (exit 0 + STDOUT) only when:
      - the Sysmon optional feature is Enabled
      - a built-in (System32) Sysmon service exists and is Running
      - the applied config hash matches the hash below

    IMPORTANT: update $ExpectedHash whenever you change sysmonconfig.xml, and bump the
    app version in Intune. Get the hash with:
        (Get-FileHash .\sysmonconfig.xml -Algorithm SHA256).Hash
#>
$ExpectedHash = 'E79F87280C5EF47A96D9916C1066EADA3620D3756F6DF89A8DC83E3D90DD13D0'
$MarkerKey    = 'HKLM:\SOFTWARE\EUC\Sysmon'

try {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName Sysmon -ErrorAction Stop
    if ($feature.State -ne 'Enabled') { exit 1 }

    $svc = Get-CimInstance Win32_Service -Filter "Name LIKE 'Sysmon%'" |
        Where-Object { $_.Name -notlike 'SysmonDrv*' -and
                       (($_.PathName -replace '"','').Trim() -like "$env:SystemRoot\System32\*") } |
        Select-Object -First 1
    if (-not $svc -or $svc.State -ne 'Running') { exit 1 }

    $applied = (Get-ItemProperty -Path $MarkerKey -Name ConfigHash -ErrorAction Stop).ConfigHash
    if ($applied -ne $ExpectedHash) { exit 1 }

    Write-Output "Sysmon built-in running; config $applied"
    exit 0
}
catch {
    exit 1
}
