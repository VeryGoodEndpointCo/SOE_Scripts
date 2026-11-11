<#
.SYNOPSIS
    Enables the built-in Windows 11 Sysmon optional feature and applies a custom config.

.DESCRIPTION
    Intended for Intune Win32 app deployment (runs as SYSTEM).

    1. Relaunches in 64-bit PowerShell if started from a 32-bit host.
    2. Detects a standalone (Sysinternals) Sysmon install - built-in Sysmon cannot
       coexist with it. Aborts unless -ReplaceStandalone is supplied.
    3. Enables the "Sysmon" Windows optional feature if not already enabled.
    4. Validates the bundled config XML, stages it to %ProgramData%\Sysmon with a
       locked-down ACL.
    5. Installs the Sysmon service/driver with the config (sysmon -i), or updates the
       running config (sysmon -c) if it's already installed and the config changed.
    6. Sizes the Microsoft-Windows-Sysmon/Operational event log.
    7. Writes a registry marker (config SHA256) used by Detect-Sysmon.ps1.

    Exit codes:
        0     Success
        3010  Feature enabled but a restart is required before Sysmon can be installed
        1     Failure (see log)

.PARAMETER ConfigFile
    Config XML file name, relative to the script folder. Default: sysmonconfig.xml

.PARAMETER ReplaceStandalone
    Uninstall an existing standalone Sysinternals Sysmon before enabling the built-in one.

.PARAMETER LogMaxSizeMB
    Max size of the Sysmon Operational event log. Default 256 MB. 0 = leave as is.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-Sysmon.ps1 -ReplaceStandalone
#>
[CmdletBinding()]
param(
    [string]$ConfigFile = 'sysmonconfig.xml',
    [switch]$ReplaceStandalone,
    [int]$LogMaxSizeMB = 256
)

$ErrorActionPreference = 'Stop'

# --- Settings -----------------------------------------------------------------
$FeatureName = 'Sysmon'
$StageDir    = Join-Path $env:ProgramData 'Sysmon'
$StagedCfg   = Join-Path $StageDir 'sysmonconfig.xml'
$MarkerKey   = 'HKLM:\SOFTWARE\EUC\Sysmon'          # change to your org's key
$LogChannel  = 'Microsoft-Windows-Sysmon/Operational'
$LogDir      = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
$LogFile     = Join-Path $LogDir 'Install-Sysmon.log'

# --- Relaunch in 64-bit PowerShell if needed ----------------------------------
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', "`"$PSCommandPath`"",
                 '-ConfigFile', "`"$ConfigFile`"", '-LogMaxSizeMB', $LogMaxSizeMB)
    if ($ReplaceStandalone) { $argList += '-ReplaceStandalone' }
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
    # Returns Sysmon services with their binary paths (covers Sysmon, Sysmon64, renamed installs via SysmonDrv-style driver)
    Get-CimInstance -ClassName Win32_Service -Filter "Name LIKE 'Sysmon%'" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike 'SysmonDrv*' }
}

function Get-BuiltInSysmonExe {
    $candidates = @(
        (Join-Path $env:SystemRoot 'System32\Sysmon.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command sysmon.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -like "$env:SystemRoot\System32\*") { return $cmd.Source }
    return $null
}

function Test-IsStandalone {
    param($Service)
    # Standalone Sysinternals Sysmon installs its binary to C:\Windows\Sysmon(64).exe.
    # Anything outside System32 is treated as standalone.
    $path = ($Service.PathName -replace '"', '').Trim()
    return -not ($path -like "$env:SystemRoot\System32\*")
}

try {
    Write-Log "===== Install-Sysmon starting (PS $($PSVersionTable.PSVersion), 64-bit: $([Environment]::Is64BitProcess)) ====="

    # --- 1. Validate config ---------------------------------------------------
    $srcCfg = Join-Path $PSScriptRoot $ConfigFile
    if (-not (Test-Path $srcCfg)) { throw "Config file not found: $srcCfg" }

    try {
        [xml]$xml = Get-Content -Path $srcCfg -Raw
    } catch {
        throw "Config XML is not well-formed: $($_.Exception.Message)"
    }
    if ($xml.DocumentElement.Name -ne 'Sysmon' -or -not $xml.Sysmon.schemaversion) {
        throw "Config root must be <Sysmon schemaversion=`"x.xx`">"
    }
    $cfgHash = (Get-FileHash -Path $srcCfg -Algorithm SHA256).Hash
    Write-Log "Config: $srcCfg (schema $($xml.Sysmon.schemaversion), SHA256 $cfgHash)"

    # --- 2. Check for standalone Sysmon ---------------------------------------
    $standalone = Get-SysmonServices | Where-Object { Test-IsStandalone $_ }
    foreach ($svc in $standalone) {
        $exe = ($svc.PathName -replace '"', '').Trim()
        Write-Log "Standalone Sysmon found: service '$($svc.Name)' at '$exe'" 'WARN'
        if (-not $ReplaceStandalone) {
            throw "Standalone Sysmon is installed and built-in Sysmon cannot coexist with it. Re-run with -ReplaceStandalone to remove it."
        }
        if (-not (Test-Path $exe)) { throw "Standalone Sysmon binary missing at '$exe'; remove it manually." }
        Invoke-Sysmon -Exe $exe -Arguments @('-u', 'force')
        Write-Log "Standalone Sysmon removed."
    }

    # --- 3. Enable optional feature -------------------------------------------
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
    if (-not $feature) {
        throw "Optional feature '$FeatureName' not available on this OS (build $([Environment]::OSVersion.Version)). Requires Windows 11 24H2+ with the March 2026 or later cumulative update."
    }
    Write-Log "Feature '$FeatureName' state: $($feature.State)"

    $restartNeeded = $false
    if ($feature.State -ne 'Enabled') {
        Write-Log "Enabling optional feature '$FeatureName'..."
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $FeatureName -All -NoRestart
        $restartNeeded = [bool]$result.RestartNeeded
        Write-Log "Feature enabled. RestartNeeded: $restartNeeded"
    }

    $sysmonExe = Get-BuiltInSysmonExe
    if (-not $sysmonExe) {
        if ($restartNeeded) {
            Write-Log "sysmon.exe not yet available; restart required. Intune will retry after reboot." 'WARN'
            exit 3010
        }
        throw "Feature enabled but sysmon.exe not found in System32."
    }
    Write-Log "Built-in Sysmon binary: $sysmonExe"

    # --- 4. Stage config with restricted ACL ----------------------------------
    if (-not (Test-Path $StageDir)) { New-Item -Path $StageDir -ItemType Directory -Force | Out-Null }
    Copy-Item -Path $srcCfg -Destination $StagedCfg -Force

    # SYSTEM + Administrators full control only; no inheritance (stops users reading/altering rules)
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in 'S-1-5-18', 'S-1-5-32-544') {
        $id = New-Object System.Security.Principal.SecurityIdentifier($sid)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $id, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -Path $StageDir -AclObject $acl
    Write-Log "Config staged to $StagedCfg"

    # --- 5. Install or update -------------------------------------------------
    $builtIn = Get-SysmonServices | Where-Object { -not (Test-IsStandalone $_) }
    $appliedHash = (Get-ItemProperty -Path $MarkerKey -Name ConfigHash -ErrorAction SilentlyContinue).ConfigHash

    if (-not $builtIn) {
        Invoke-Sysmon -Exe $sysmonExe -Arguments @('-accepteula', '-i', $StagedCfg)
        Write-Log "Sysmon installed with custom config."
    }
    elseif ($appliedHash -ne $cfgHash) {
        Invoke-Sysmon -Exe $sysmonExe -Arguments @('-c', $StagedCfg)
        Write-Log "Sysmon config updated (was: $appliedHash)."
    }
    else {
        Write-Log "Sysmon already installed with current config; nothing to do."
    }

    # Ensure the service is running
    $svc = Get-SysmonServices | Where-Object { -not (Test-IsStandalone $_) } | Select-Object -First 1
    if (-not $svc) { throw "Sysmon service not found after install." }
    if ($svc.State -ne 'Running') {
        Start-Service -Name $svc.Name
        Write-Log "Started service '$($svc.Name)'."
    }
    Write-Log "Service '$($svc.Name)' running."

    # --- 6. Event log size ----------------------------------------------------
    if ($LogMaxSizeMB -gt 0) {
        $bytes = [int64]$LogMaxSizeMB * 1MB
        & wevtutil.exe sl $LogChannel /ms:$bytes 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Log "Set $LogChannel max size to $LogMaxSizeMB MB." }
        else { Write-Log "Could not set $LogChannel size (wevtutil exit $LASTEXITCODE)." 'WARN' }
    }

    # --- 7. Detection marker --------------------------------------------------
    if (-not (Test-Path $MarkerKey)) { New-Item -Path $MarkerKey -Force | Out-Null }
    Set-ItemProperty -Path $MarkerKey -Name ConfigHash    -Value $cfgHash
    Set-ItemProperty -Path $MarkerKey -Name SchemaVersion -Value ([string]$xml.Sysmon.schemaversion)
    Set-ItemProperty -Path $MarkerKey -Name AppliedUtc    -Value ((Get-Date).ToUniversalTime().ToString('o'))
    Write-Log "Detection marker written to $MarkerKey."

    Write-Log "===== Completed successfully ====="
    exit 0
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    Write-Log "===== Failed =====" 'ERROR'
    exit 1
}
