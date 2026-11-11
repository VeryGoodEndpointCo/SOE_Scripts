<#
.SYNOPSIS
    Removes built-in Windows 11 Sysmon and the custom config deployed by Install-Sysmon.ps1.

.DESCRIPTION
    Intended for Intune Win32 app uninstall (runs as SYSTEM).

    1. Relaunches in 64-bit PowerShell if started from a 32-bit host.
    2. Uninstalls the built-in Sysmon service/driver (sysmon -u force).
    3. Disables the "Sysmon" Windows optional feature.
    4. Removes the staged config (%ProgramData%\Sysmon) and the detection marker key.
    5. Optionally removes a standalone Sysinternals Sysmon as well (-IncludeStandalone).

    The Microsoft-Windows-Sysmon/Operational event log is left intact so existing
    events aren't lost before they've been forwarded.

    Exit codes:
        0     Success
        3010  Success, restart required to finish disabling the feature
        1     Failure (see log)

.PARAMETER IncludeStandalone
    Also uninstall a standalone (Sysinternals) Sysmon if one is found.

.PARAMETER KeepFeature
    Uninstall the Sysmon service/driver but leave the optional feature enabled.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-Sysmon.ps1
#>
[CmdletBinding()]
param(
    [switch]$IncludeStandalone,
    [switch]$KeepFeature
)

$ErrorActionPreference = 'Stop'

# --- Settings (keep in sync with Install-Sysmon.ps1) --------------------------
$FeatureName = 'Sysmon'
$StageDir    = Join-Path $env:ProgramData 'Sysmon'
$MarkerKey   = 'HKLM:\SOFTWARE\EUC\Sysmon'
$LogDir      = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
$LogFile     = Join-Path $LogDir 'Uninstall-Sysmon.log'

# --- Relaunch in 64-bit PowerShell if needed ----------------------------------
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', "`"$PSCommandPath`"")
    if ($IncludeStandalone) { $argList += '-IncludeStandalone' }
    if ($KeepFeature)       { $argList += '-KeepFeature' }
    $p = Start-Process -FilePath $ps64 -ArgumentList $argList -Wait -PassThru -NoNewWindow
    exit $p.ExitCode
}

# --- Logging ------------------------------------------------------------------
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogFile -Value $line
    Write-Output $line
}

function Invoke-Sysmon {
    param([string]$Exe, [string[]]$Arguments)
    Write-Log "Running: $Exe $($Arguments -join ' ')"
    $out = & $Exe @Arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($out.Trim()) { Write-Log "sysmon output: $($out.Trim())" }
    if ($code -ne 0) { throw "sysmon exited with code $code" }
}

function Get-SysmonServices {
    Get-CimInstance -ClassName Win32_Service -Filter "Name LIKE 'Sysmon%'" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike 'SysmonDrv*' }
}

function Get-ServiceExe {
    param($Service)
    return ($Service.PathName -replace '"', '').Trim()
}

function Test-IsStandalone {
    param($Service)
    return -not ((Get-ServiceExe $Service) -like "$env:SystemRoot\System32\*")
}

try {
    Write-Log "===== Uninstall-Sysmon starting ====="
    $restartNeeded = $false

    # --- 1. Uninstall Sysmon service/driver -----------------------------------
    $services = @(Get-SysmonServices)
    if (-not $services) { Write-Log "No Sysmon service found." }

    foreach ($svc in $services) {
        $exe = Get-ServiceExe $svc
        if (Test-IsStandalone $svc) {
            if (-not $IncludeStandalone) {
                Write-Log "Standalone Sysmon '$($svc.Name)' at '$exe' left in place (use -IncludeStandalone to remove)." 'WARN'
                continue
            }
            Write-Log "Removing standalone Sysmon '$($svc.Name)'."
        } else {
            Write-Log "Removing built-in Sysmon '$($svc.Name)'."
        }

        if (Test-Path $exe) {
            Invoke-Sysmon -Exe $exe -Arguments @('-u', 'force')
        } else {
            throw "Sysmon binary missing at '$exe'; cannot run uninstall."
        }
    }

    # --- 2. Disable optional feature ------------------------------------------
    if (-not $KeepFeature) {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
        if (-not $feature) {
            Write-Log "Optional feature '$FeatureName' not present on this OS."
        }
        elseif ($feature.State -in 'Enabled', 'EnablePending') {
            Write-Log "Disabling optional feature '$FeatureName' (state: $($feature.State))..."
            $result = Disable-WindowsOptionalFeature -Online -FeatureName $FeatureName -NoRestart
            $restartNeeded = [bool]$result.RestartNeeded
            Write-Log "Feature disabled. RestartNeeded: $restartNeeded"
        }
        else {
            Write-Log "Feature '$FeatureName' already $($feature.State)."
        }
    } else {
        Write-Log "-KeepFeature set; optional feature left enabled."
    }

    # --- 3. Clean up staged config and marker ---------------------------------
    if (Test-Path $StageDir) {
        Remove-Item -Path $StageDir -Recurse -Force
        Write-Log "Removed $StageDir."
    }
    if (Test-Path $MarkerKey) {
        Remove-Item -Path $MarkerKey -Recurse -Force
        Write-Log "Removed $MarkerKey."
    }

    # --- 4. Verify ------------------------------------------------------------
    $remaining = @(Get-SysmonServices | Where-Object { -not (Test-IsStandalone $_) })
    if ($remaining -and -not $restartNeeded) {
        throw "Built-in Sysmon service still present: $($remaining.Name -join ', ')"
    }

    if ($restartNeeded) {
        Write-Log "===== Completed; restart required ====="
        exit 3010
    }
    Write-Log "===== Completed successfully ====="
    exit 0
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    Write-Log "===== Failed =====" 'ERROR'
    exit 1
}
