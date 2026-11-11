<#
.SYNOPSIS
    Enables built-in Sysmon and applies sysmonconfig.xml (from the script folder).

    Intune install command (Sysnative forces 64-bit PowerShell):
    %SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-Sysmon.ps1

    Exit codes: 0 success, 3010 restart required, 1 failure
#>
$ErrorActionPreference = 'Stop'
$Config    = Join-Path $PSScriptRoot 'sysmonconfig.xml'
$MarkerKey = 'HKLM:\SOFTWARE\EUC\Sysmon'
Start-Transcript -Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\Install-Sysmon.log" -Append

try {
    # 1. Enable the optional feature
    $feature = Get-WindowsOptionalFeature -Online -FeatureName Sysmon
    if ($feature.State -ne 'Enabled') {
        $result = Enable-WindowsOptionalFeature -Online -FeatureName Sysmon -NoRestart
        if ($result.RestartNeeded -and -not (Get-Command sysmon.exe -ErrorAction SilentlyContinue)) {
            Write-Output 'Restart required before Sysmon can be installed.'
            exit 3010
        }
    }

    # 2. Install with the config, or update the config if already installed
    if (Get-Service -Name 'Sysmon*' -ErrorAction SilentlyContinue | Where-Object Name -notlike 'SysmonDrv*') {
        sysmon.exe -c $Config
    } else {
        sysmon.exe -accepteula -i $Config
    }
    if ($LASTEXITCODE -ne 0) { throw "sysmon.exe exited with code $LASTEXITCODE" }

    # 3. Record the applied config hash for detection
    New-Item -Path $MarkerKey -Force | Out-Null
    Set-ItemProperty -Path $MarkerKey -Name ConfigHash -Value (Get-FileHash $Config -Algorithm SHA256).Hash

    Write-Output 'Sysmon installed and configured.'
    exit 0
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}
