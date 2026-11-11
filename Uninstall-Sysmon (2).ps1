<#
.SYNOPSIS
    Removes built-in Sysmon and the detection marker.

    Intune uninstall command (Sysnative forces 64-bit PowerShell):
    %SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-Sysmon.ps1

    Exit codes: 0 success, 3010 restart required, 1 failure
#>
$ErrorActionPreference = 'Stop'
$MarkerKey = 'HKLM:\SOFTWARE\EUC\Sysmon'
Start-Transcript -Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\Uninstall-Sysmon.log" -Append

try {
    # 1. Remove the Sysmon service and driver
    if (Get-Command sysmon.exe -ErrorAction SilentlyContinue) {
        sysmon.exe -u force
        if ($LASTEXITCODE -ne 0) { throw "sysmon.exe exited with code $LASTEXITCODE" }
    }

    # 2. Disable the optional feature
    $result = Disable-WindowsOptionalFeature -Online -FeatureName Sysmon -NoRestart

    # 3. Remove the detection marker
    Remove-Item -Path $MarkerKey -Recurse -Force -ErrorAction SilentlyContinue

    if ($result.RestartNeeded) { Write-Output 'Sysmon removed; restart required.'; exit 3010 }
    Write-Output 'Sysmon removed.'
    exit 0
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}
