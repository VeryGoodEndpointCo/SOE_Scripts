<#
.SYNOPSIS
    Uninstalls a list of applications by matching DisplayName in the registry Uninstall keys.

.DESCRIPTION
    For each app in $AppsToRemove:
      - Searches HKLM (64-bit + WOW6432Node) Uninstall keys for a DisplayName match (wildcards supported)
      - Uses QuietUninstallString if present, otherwise UninstallString
      - If the string is "msiexec /i ...", swaps it to "msiexec /x ... /qn"
      - Runs it and reports the exit code

.PARAMETER WhatIf
    Show what would be run without executing anything.

.NOTES
    Exit codes 0, 1641 and 3010 are treated as success.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

# ============================ APPS TO REMOVE ============================
# Matched against DisplayName with -like, so wildcards work.
# "*Zoom*" matches anything containing Zoom; "7-Zip*" matches names starting with 7-Zip.
$AppsToRemove = @(
    "*Zoom*"
    "7-Zip*"
    "Google Chrome"
)
# ========================================================================

# Relaunch in 64-bit PowerShell if running 32-bit on a 64-bit OS (e.g. Intune default),
# otherwise HKLM\SOFTWARE is redirected and 64-bit apps are missed.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe"
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($WhatIfPreference) { $argList += '-WhatIf' }
    $p = Start-Process -FilePath $ps64 -ArgumentList $argList -Wait -PassThru -NoNewWindow
    exit $p.ExitCode
}

$LogDir = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
if (-not (Test-Path $LogDir)) { $LogDir = $env:TEMP }
Start-Transcript -Path (Join-Path $LogDir "Uninstall-Apps.log") -Append | Out-Null

$UninstallPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$SuccessCodes = @(0, 1641, 3010)
$OverallExit  = 0

function Split-Command {
    # Splits an uninstall string into executable + arguments.
    param([string]$Command)
    $Command = $Command.Trim()

    if ($Command -match '^"([^"]+)"\s*(.*)$') {
        return [pscustomobject]@{ FilePath = $Matches[1]; Arguments = $Matches[2].Trim() }
    }
    if ($Command -match '^(.+?\.exe)\s*(.*)$') {
        return [pscustomobject]@{ FilePath = $Matches[1]; Arguments = $Matches[2].Trim() }
    }
    # Fallback: first token is the exe
    $parts = $Command -split '\s+', 2
    return [pscustomobject]@{ FilePath = $parts[0]; Arguments = if ($parts.Count -gt 1) { $parts[1] } else { '' } }
}

# Gather all uninstall entries once
$Entries = foreach ($path in $UninstallPaths) {
    Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, QuietUninstallString, UninstallString, PSPath
}

foreach ($app in $AppsToRemove) {
    Write-Output "=== Searching for '$app' ==="
    $found = $Entries | Where-Object { $_.DisplayName -like $app }

    if (-not $found) {
        Write-Output "  No match found."
        continue
    }

    foreach ($entry in $found) {
        Write-Output "  Found: $($entry.DisplayName) $($entry.DisplayVersion)"

        if ($entry.QuietUninstallString) {
            $cmd = $entry.QuietUninstallString
            Write-Output "  Using QuietUninstallString"
        }
        elseif ($entry.UninstallString) {
            $cmd = $entry.UninstallString
            Write-Output "  Using UninstallString"
        }
        else {
            Write-Warning "  No uninstall string for $($entry.DisplayName) - skipping."
            continue
        }

        # MSI handling: swap /i for /x and make it silent
        if ($cmd -match 'msiexec') {
            $cmd = $cmd -replace '(?i)\s/i\s*', ' /x '
            if ($cmd -notmatch '(?i)\s/q[nb]?\b') { $cmd += ' /qn' }
            if ($cmd -notmatch '(?i)/norestart') { $cmd += ' /norestart' }
        }

        $parsed = Split-Command -Command $cmd
        Write-Output "  Command: $($parsed.FilePath) $($parsed.Arguments)"

        if ($PSCmdlet.ShouldProcess($entry.DisplayName, "Uninstall")) {
            try {
                $spArgs = @{ FilePath = $parsed.FilePath; Wait = $true; PassThru = $true; WindowStyle = 'Hidden' }
                if ($parsed.Arguments) { $spArgs.ArgumentList = $parsed.Arguments }

                $proc = Start-Process @spArgs
                if ($proc.ExitCode -in $SuccessCodes) {
                    Write-Output "  Success (exit code $($proc.ExitCode))"
                    if ($proc.ExitCode -in 1641, 3010) { $OverallExit = 3010 }
                }
                else {
                    Write-Warning "  Failed (exit code $($proc.ExitCode))"
                    $OverallExit = 1
                }
            }
            catch {
                Write-Warning "  Error running uninstall: $_"
                $OverallExit = 1
            }
        }
    }
}

Stop-Transcript | Out-Null
exit $OverallExit
