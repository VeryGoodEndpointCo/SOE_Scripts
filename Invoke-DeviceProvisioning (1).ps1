<#
.SYNOPSIS
  Autopilot device provisioning: branding, built-in Sysmon, English (Australia), and forced
  Windows quality updates. One Intune Win32 app, run as SYSTEM during the device ESP phase.

.DESCRIPTION
  Steps run in this order and the script stops at the first failure (exit 1, no detection marker).
  Every step is safe to run again, so a retry only redoes what isn't finished.

    0. Pre-flight   Stops if the device is not in OOBE/ESP. Checks config, package files and
                    64-bit PowerShell before changing anything.
    1. Branding     winver organisation/owner, desktop wallpaper, default account picture.
    2. Sysmon       Enables the built-in Sysmon feature and applies sysmonconfig.xml
                    (same logic and marker as Install-Sysmon.ps1).
    3. Language     Installs English (Australia) for new user profiles, US keyboard only, sign-in
                    screen left on en-US (same logic and marker as Set-EnAULanguage.ps1).
    4. Updates      Installs the latest quality updates for
                    the feature version already installed. No feature upgrade, no drivers.
                    Adapted from Somesh Pathak's Force-WindowsUpdates-TechnicianPhase.ps1:
                    https://intuneirl.com/forcing-the-windows-updates-during-autopilot-pre-provisioning-esp-technician-phase
                    https://github.com/pathaksomesh06/scripts/blob/main/Force-WindowsUpdates-TechnicianPhase.ps1

  Language and Sysmon go before the updates on purpose: both use Windows servicing, which is
  unreliable once a cumulative update is waiting for a restart.

  Exit codes: 0 = done, 3010 = done and a restart is needed, 1 = failed (see the log).

.NOTES
  PACKAGE FOLDER (wrap with IntuneWinAppUtil.exe, setup file = Invoke-DeviceProvisioning.ps1)
    Invoke-DeviceProvisioning.ps1
    sysmonconfig.xml          your Sysmon config
    wallpaper.jpg             desktop wallpaper
    userpicture.png           default account picture, square, 448 x 448 or larger
    PSWindowsUpdate\          run in the package folder:  Save-Module PSWindowsUpdate -Path .

  WIN32 APP SETTINGS
    Install command:    %SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-DeviceProvisioning.ps1
    Uninstall command:  cmd /c exit 0
    Install behaviour:  System
    Restart behaviour:  Determine behaviour based on return codes (3010 = Soft reboot)
    Detection rule:     Registry  HKLM\SOFTWARE\EUC\Provisioning  value Version  String  equals 1
    Requirement rule:   Script  Requirement-InOOBE.ps1
                          Run script as 32-bit process on 64-bit clients: No
                          Run this script using the logged on credentials: No
                          Enforce script signature check: No
                          Output data type: String   Operator: Equals   Value: InOOBE
                        Provisioned devices then report "Not applicable" and never attempt the install.
    Assignment:         Required, all devices, and added to the ESP's blocking apps

  Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Invoke-DeviceProvisioning.log
#>

$ErrorActionPreference = 'Stop'

#region Config ------------------------------------------------------------------------------
$OrgName          = ''        # REQUIRED. Organisation shown in winver, e.g. 'Department of Example'
$RegisteredOwner  = ''        # Owner shown in winver. Blank = same as $OrgName

$LockWallpaper    = $true     # $true  = wallpaper enforced for all users (users can't change it)
                              # $false = default for new profiles only (not verified on 24H2 and later)
$ForceUserPicture = $false    # $true  = every user gets the default picture and can't change it
                              # $false = it is only the default (an Entra profile photo replaces it)

$WallpaperFile    = 'wallpaper.jpg'
$UserPictureFile  = 'userpicture.png'
$SysmonConfigFile = 'sysmonconfig.xml'

# Updates: exact 'Build.UBR' strings to treat as Insider builds and skip, e.g. @('26100.1').
# Never use a wildcard on a retail build family.
$InsiderBuildBlocklist = @()
#endregion

#region Constants ---------------------------------------------------------------------------
$MarkerVersion  = '1'
$Marker         = 'HKLM:\SOFTWARE\EUC\Provisioning'
$SysmonMarker   = 'HKLM:\SOFTWARE\EUC\Sysmon'       # read by Detect-Sysmon.ps1
$LanguageMarker = 'HKLM:\SOFTWARE\EUC\Language'     # read by the en-AU remediation pair
$UpdateTagDir   = "$env:ProgramData\IntuneWU"
$UpdateTag      = Join-Path $UpdateTagDir 'ForceUpdates.success.tag'
$WallpaperDest  = "$env:SystemRoot\Web\Wallpaper\EUC\wallpaper.jpg"
$PictureDir     = "$env:ProgramData\Microsoft\User Account Pictures"
$BundledModule  = Join-Path $PSScriptRoot 'PSWindowsUpdate'
$LogDir         = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile        = Join-Path $LogDir 'Invoke-DeviceProvisioning.log'

$Language = 'en-AU'
$Keyboard = '0C09:00000409'    # English (Australia) with the US layout
$GeoId    = 12                 # Australia
#endregion

#region Functions ---------------------------------------------------------------------------
function Write-Step([string] $Message) {
    Write-Output ''
    Write-Output ("=== {0}  {1} ===" -f (Get-Date -Format 'HH:mm:ss'), $Message)
}

# Runs a native program, logs its output and returns its exit code.
# Tools such as sysmon.exe write their banner to stderr; with $ErrorActionPreference = 'Stop'
# that would end the script, so the preference is relaxed for the call only.
function Invoke-Native([string] $FilePath, [string[]] $Arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $FilePath @Arguments 2>&1 | ForEach-Object { Write-Host "    $_" }
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
}

function Test-InOOBE {
    Add-Type -Namespace EUC -Name Oobe -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern int OOBEComplete(ref int isComplete);
'@
    $complete = 0
    [void][EUC.Oobe]::OOBEComplete([ref] $complete)
    return ($complete -eq 0)
}

function Test-DisplayLanguage([string] $Tag) {
    $lang = Get-InstalledLanguage -Language $Tag -ErrorAction SilentlyContinue
    return [bool]($lang -and ("$($lang.LanguagePacks)" -match 'LpCab|LXP'))
}

function Save-ResizedImage($Source, [int] $Size, [string] $Path, $Format, [switch] $WhiteBackground) {
    $bitmap   = New-Object System.Drawing.Bitmap $Size, $Size
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        if ($WhiteBackground) { $graphics.Clear([System.Drawing.Color]::White) }   # BMP has no transparency
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($Source, 0, 0, $Size, $Size)
        $bitmap.Save($Path, $Format)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}
#endregion

if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
Start-Transcript -Path $LogFile -Append | Out-Null

$RebootNeeded = $false
$UpdateStatus = 'NotRun'

try {
    # =========================================================================================
    Write-Step '0. Pre-flight'
    # =========================================================================================
    if (-not [Environment]::Is64BitProcess) {
        throw 'Not running in 64-bit PowerShell. Use the Sysnative install command from the script header.'
    }
    if ([string]::IsNullOrWhiteSpace($OrgName)) { throw 'Set $OrgName in the Config section of the script.' }
    if ([string]::IsNullOrWhiteSpace($RegisteredOwner)) { $RegisteredOwner = $OrgName }

    $Wallpaper    = Join-Path $PSScriptRoot $WallpaperFile
    $UserPicture  = Join-Path $PSScriptRoot $UserPictureFile
    $SysmonConfig = Join-Path $PSScriptRoot $SysmonConfigFile
    foreach ($file in $Wallpaper, $UserPicture, $SysmonConfig) {
        if (-not (Test-Path $file -PathType Leaf)) { throw "Package file missing: $file" }
    }

    # Backstop for the Intune requirement rule (Requirement-InOOBE.ps1): outside OOBE/ESP the
    # script stops here, before changing anything.
    if (-not (Test-InOOBE)) {
        Write-Output 'Device is not in OOBE/ESP. Nothing was changed. Add Requirement-InOOBE.ps1 as a requirement rule so Intune does not attempt this on provisioned devices.'
        Stop-Transcript | Out-Null
        exit 1
    }
    $RunUpdates = -not (Test-Path $UpdateTag)
    Write-Output "Device is in OOBE/ESP. Updates will run: $RunUpdates."

    if ($RunUpdates) {
        $ModuleManifest = Get-ChildItem -Path $BundledModule -Recurse -Filter 'PSWindowsUpdate.psd1' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $ModuleManifest) {
            throw "PSWindowsUpdate isn't in the package. Run 'Save-Module PSWindowsUpdate -Path .' in the package folder and rebuild it."
        }
    }
    Write-Output 'Pre-flight passed.'

    # =========================================================================================
    Write-Step '1. Branding'
    # =========================================================================================
    # --- winver: "This product is licensed ... to:" -------------------------------------------
    foreach ($key in 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion',
                     'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion') {
        Set-ItemProperty -Path $key -Name 'RegisteredOrganization' -Value $OrgName
        Set-ItemProperty -Path $key -Name 'RegisteredOwner'        -Value $RegisteredOwner
    }
    Write-Output "winver: owner '$RegisteredOwner', organisation '$OrgName'."

    # --- Wallpaper ----------------------------------------------------------------------------
    New-Item -Path (Split-Path $WallpaperDest) -ItemType Directory -Force | Out-Null
    Copy-Item -Path $Wallpaper -Destination $WallpaperDest -Force

    if ($LockWallpaper) {
        # Same registry values the Intune Personalization policy writes. Applies to every user.
        $csp = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
        if (-not (Test-Path $csp)) { New-Item -Path $csp -Force | Out-Null }   # no -Force on an existing key: it would clear lock screen values
        Set-ItemProperty -Path $csp -Name 'DesktopImagePath'   -Value $WallpaperDest
        Set-ItemProperty -Path $csp -Name 'DesktopImageUrl'    -Value $WallpaperDest
        Set-ItemProperty -Path $csp -Name 'DesktopImageStatus' -Value 1 -Type DWord
        Write-Output "Wallpaper enforced for all users: $WallpaperDest"
    }
    else {
        # Default for new profiles only: written to the default user's registry hive.
        $hive = 'HKU\EUCDefaultUser'
        if ((Invoke-Native 'reg.exe' @('load', $hive, "$env:SystemDrive\Users\Default\NTUSER.DAT")) -ne 0) {
            throw 'Could not load the default user registry hive.'
        }
        try {
            $values = @(
                @("$hive\Control Panel\Desktop", 'WallPaper',      'REG_SZ',    $WallpaperDest),
                @("$hive\Control Panel\Desktop", 'WallpaperStyle', 'REG_SZ',    '10'),          # fill
                @("$hive\Control Panel\Desktop", 'TileWallpaper',  'REG_SZ',    '0'),
                @("$hive\Software\Microsoft\Windows\CurrentVersion\DesktopSpotlight\Settings", 'EnabledState', 'REG_DWORD', '0')
            )
            foreach ($v in $values) {
                if ((Invoke-Native 'reg.exe' @('add', $v[0], '/v', $v[1], '/t', $v[2], '/d', $v[3], '/f')) -ne 0) {
                    throw "Could not set $($v[1]) in the default user hive."
                }
            }
        } finally {
            if ((Invoke-Native 'reg.exe' @('unload', $hive)) -ne 0) { throw 'Could not unload the default user registry hive.' }
        }
        Write-Output "Wallpaper set as the default for new profiles: $WallpaperDest"
    }

    # --- Default account picture ----------------------------------------------------------------
    Add-Type -AssemblyName System.Drawing
    $backup = Join-Path $PictureDir 'Original'
    if (-not (Test-Path $backup)) {
        New-Item -Path $backup -ItemType Directory -Force | Out-Null
        Copy-Item -Path (Join-Path $PictureDir 'user*') -Destination $backup -Force
    }
    $source = [System.Drawing.Image]::FromFile($UserPicture)
    try {
        if ($source.Width -ne $source.Height) { Write-Output "WARNING: $UserPictureFile isn't square and will be stretched." }
        $png = [System.Drawing.Imaging.ImageFormat]::Png
        Save-ResizedImage $source 448 (Join-Path $PictureDir 'user.png')     $png
        Save-ResizedImage $source 192 (Join-Path $PictureDir 'user-192.png') $png
        Save-ResizedImage $source 48  (Join-Path $PictureDir 'user-48.png')  $png
        Save-ResizedImage $source 40  (Join-Path $PictureDir 'user-40.png')  $png
        Save-ResizedImage $source 32  (Join-Path $PictureDir 'user-32.png')  $png
        Save-ResizedImage $source 448 (Join-Path $PictureDir 'user.bmp') ([System.Drawing.Imaging.ImageFormat]::Bmp) -WhiteBackground
    } finally {
        $source.Dispose()
    }
    if ($ForceUserPicture) {
        $explorer = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
        if (-not (Test-Path $explorer)) { New-Item -Path $explorer -Force | Out-Null }
        Set-ItemProperty -Path $explorer -Name 'UseDefaultTile' -Value 1 -Type DWord
    }
    Write-Output "Default account picture replaced (originals kept in $backup)."

    # =========================================================================================
    Write-Step '2. Sysmon'
    # =========================================================================================
    $configHash = (Get-FileHash -Path $SysmonConfig -Algorithm SHA256).Hash
    $service    = Get-Service -Name 'Sysmon*' -ErrorAction SilentlyContinue | Where-Object Name -notlike 'SysmonDrv*'
    $storedHash = (Get-ItemProperty -Path $SysmonMarker -Name ConfigHash -ErrorAction SilentlyContinue).ConfigHash

    if ($service -and $service.Status -eq 'Running' -and $storedHash -eq $configHash) {
        Write-Output 'Sysmon is already running with this config. Skipping.'
    }
    else {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName Sysmon
        if ($feature.State -ne 'Enabled') {
            Write-Output 'Enabling the Sysmon optional feature...'
            Enable-WindowsOptionalFeature -Online -FeatureName Sysmon -NoRestart | Out-Null
        }
        $sysmon = Get-Command sysmon.exe -ErrorAction SilentlyContinue
        if (-not $sysmon) { throw 'sysmon.exe is not available after enabling the feature. A restart may be needed first.' }

        if ($service) { $code = Invoke-Native $sysmon.Source @('-c', $SysmonConfig) }                    # already installed: update the config
        else          { $code = Invoke-Native $sysmon.Source @('-accepteula', '-i', $SysmonConfig) }     # new install
        if ($code -ne 0) { throw "sysmon.exe exited with code $code" }

        New-Item -Path $SysmonMarker -Force | Out-Null
        Set-ItemProperty -Path $SysmonMarker -Name 'ConfigHash' -Value $configHash
        Write-Output 'Sysmon installed and configured.'
    }

    # =========================================================================================
    Write-Step '3. English (Australia)'
    # =========================================================================================
    if ((Get-ItemProperty -Path $LanguageMarker -Name enAU -ErrorAction SilentlyContinue).enAU -eq '1') {
        Write-Output 'English (Australia) is already set up. Skipping.'
    }
    else {
        # Install English (Australia), or fall back to the English (UK) language pack
        Write-Output "Installing $Language..."
        try {
            Install-Language -Language $Language -ErrorAction Stop | Out-Null
        } catch {
            Write-Output "Install-Language $Language reported: $($_.Exception.Message)"
        }

        if (Test-DisplayLanguage $Language) {
            $Display = $Language
        } else {
            Write-Output "$Language display language not available. Installing the en-GB language pack instead."
            # -ExcludeFeatures: the language pack only. en-GB typing/keyboard features aren't wanted.
            Install-Language -Language 'en-GB' -ExcludeFeatures -ErrorAction Stop | Out-Null
            if (-not (Test-DisplayLanguage 'en-GB')) { throw 'Neither en-AU nor en-GB display language could be installed.' }
            $Display = 'en-GB'
        }
        Write-Output "Display language: $Display"

        # Settings for the SYSTEM context (copied to new users below)
        $list = New-WinUserLanguageList $Language
        $list[0].InputMethodTips.Clear()
        $list[0].InputMethodTips.Add($Keyboard)
        Set-WinUserLanguageList -LanguageList $list -Force
        Set-WinUILanguageOverride -Language $Display
        Set-Culture -CultureInfo $Language
        Set-WinHomeLocation -GeoId $GeoId

        # Copy to new user profiles only
        Copy-UserInternationalSettingsToSystem -WelcomeScreen $false -NewUser $true

        # SYSTEM shares its settings with the sign-in screen. Put its display language back to en-US
        # (the image default); the language list stays English (Australia) with the US keyboard.
        Set-WinUILanguageOverride -Language 'en-US'

        New-Item -Path $LanguageMarker -Force | Out-Null
        Set-ItemProperty -Path $LanguageMarker -Name 'enAU'            -Value '1'
        Set-ItemProperty -Path $LanguageMarker -Name 'DisplayLanguage' -Value $Display
        $RebootNeeded = $true
        Write-Output 'English (Australia) set for new profiles. Restart required.'
    }

    # =========================================================================================
    Write-Step '4. Windows quality updates'
    # =========================================================================================
    if (Test-Path $UpdateTag) {
        $UpdateStatus = 'AlreadyDone'
        Write-Output 'Updates were already forced on this device. Skipping.'
    }
    else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # --- Skip Windows Insider / flighting devices -----------------------------------------
        $SkipReason = $null
        $SelfHost   = 'HKLM:\SOFTWARE\Microsoft\WindowsSelfHost\Applicability'
        if (Test-Path $SelfHost) {
            $sh = Get-ItemProperty -Path $SelfHost -ErrorAction SilentlyContinue
            if ($sh.BranchName -or $sh.Ring -or $sh.ContentType -or ($sh.EnablePreviewBuilds -eq 1)) {
                $SkipReason = "Insider/flighting device (BranchName='$($sh.BranchName)', Ring='$($sh.Ring)', ContentType='$($sh.ContentType)')"
            }
        }
        $CV       = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $BuildUBR = "$($CV.CurrentBuildNumber).$($CV.UBR)"
        if (-not $SkipReason -and $InsiderBuildBlocklist -contains $BuildUBR) {
            $SkipReason = "build $BuildUBR is in the Insider block list"
        }

        if ($SkipReason) {
            $UpdateStatus = 'SkippedInsider'
            Write-Output "Skipping the update run: $SkipReason."
        }
        else {
            # --- PSWindowsUpdate: copy the bundled module into the system Modules folder ------
            $moduleVersion = (Import-PowerShellDataFile -Path $ModuleManifest.FullName).ModuleVersion
            $moduleDest    = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules\PSWindowsUpdate\$moduleVersion"
            if (-not (Test-Path (Join-Path $moduleDest 'PSWindowsUpdate.psd1'))) {
                New-Item -Path $moduleDest -ItemType Directory -Force | Out-Null
                Copy-Item -Path (Join-Path $ModuleManifest.DirectoryName '*') -Destination $moduleDest -Recurse -Force
                Write-Output "PSWindowsUpdate $moduleVersion copied to $moduleDest"
            }
            Import-Module (Join-Path $moduleDest 'PSWindowsUpdate.psd1') -Force

            # --- Lift the quality deferral for the scan only, then restore it -----------------
            $PolicyPath = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update'
            $OrigDefer  = (Get-ItemProperty $PolicyPath -Name DeferQualityUpdatesPeriodInDays -ErrorAction SilentlyContinue).DeferQualityUpdatesPeriodInDays
            try {
                if (Test-Path $PolicyPath) {
                    Set-ItemProperty $PolicyPath -Name DeferQualityUpdatesPeriodInDays -Value 0 -Type DWord -ErrorAction SilentlyContinue
                    Write-Output "Quality deferral temporarily set to 0 (was: $OrigDefer)."
                    Start-Sleep -Seconds 5
                }

                Write-Output ("Current feature version: {0} (build {1}). Installing quality updates for this version only." -f $CV.DisplayVersion, $BuildUBR)

                # Exclusions: Upgrades (feature updates), Drivers (firmware prompts can stall ESP),
                # and by title the enablement package, so the feature version never changes.
                $Pending = Get-WindowsUpdate -NotCategory 'Upgrades','Drivers' -NotTitle 'Feature update|Enablement Package' -ErrorAction SilentlyContinue
                if (-not $Pending) {
                    Write-Output 'No quality updates pending.'
                }
                else {
                    Write-Output ("Found {0} update(s):" -f @($Pending).Count)
                    foreach ($u in $Pending) { Write-Output ("  - {0}  {1}  ({2})" -f $u.KB, $u.Title, $u.Size) }

                    # Call Install-WindowsUpdate directly. Never pipe update objects into it.
                    $InstallResults = @()
                    Install-WindowsUpdate -NotCategory 'Upgrades','Drivers' -NotTitle 'Feature update|Enablement Package' -AcceptAll -IgnoreReboot -Verbose 4>&1 |
                        ForEach-Object {
                            if ($_ -is [System.Management.Automation.VerboseRecord]) {
                                $line = $_.Message
                            } else {
                                $InstallResults += $_
                                $line = ($_ | Out-String).Trim()
                            }
                            if ($line) { Write-Output ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $line) }
                        }

                    $InstalledOK = @($InstallResults | Where-Object { $_.Result -eq 'Installed' } | Sort-Object Title -Unique)
                    $FailedSet   = @($InstallResults | Where-Object { $_.Result -eq 'Failed' }    | Sort-Object Title -Unique)
                    Write-Output ("Result check: {0} installed, {1} failed, of {2} pending." -f $InstalledOK.Count, $FailedSet.Count, @($Pending).Count)
                    foreach ($f in $FailedSet) { Write-Output ("  FAILED: {0} {1}" -f $f.KB, $f.Title) }

                    # Gate 1: nothing installed at all
                    if ($InstalledOK.Count -eq 0) { throw 'All pending updates failed to install.' }

                    # Gate 2: if a cumulative update was pending, it must be among the installed set
                    $LcuPattern = 'Cumulative Update for Windows|Security Update \(KB'
                    $LcuPending = @($Pending | Where-Object { $_.Title -match $LcuPattern })
                    if ($LcuPending.Count -gt 0) {
                        $LcuInstalled = @($InstalledOK | Where-Object { $_.Title -match $LcuPattern })
                        if ($LcuInstalled.Count -eq 0) { throw ("Cumulative update '{0}' failed to install." -f $LcuPending[0].Title) }
                        Write-Output ("LCU check passed: {0}" -f $LcuInstalled[0].Title)
                        $RebootNeeded = $true    # an LCU always needs a restart; the WU flag isn't trusted
                    }
                }

                if (Get-WURebootStatus -Silent) { $RebootNeeded = $true }
                if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $RebootNeeded = $true }
                if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $RebootNeeded = $true }
            }
            finally {
                if ($null -ne $OrigDefer) {
                    Set-ItemProperty $PolicyPath -Name DeferQualityUpdatesPeriodInDays -Value $OrigDefer -Type DWord -ErrorAction SilentlyContinue
                    Write-Output "Quality deferral restored to $OrigDefer."
                }
            }
            $UpdateStatus = 'Installed'
        }

        if (-not (Test-Path $UpdateTagDir)) { New-Item -Path $UpdateTagDir -ItemType Directory -Force | Out-Null }
        New-Item -Path $UpdateTag -ItemType File -Force | Out-Null
    }

    # =========================================================================================
    Write-Step 'Finished'
    # =========================================================================================
    # Written last, and before exiting: Intune checks the detection rule straight after the
    # script ends, and during ESP a 3010 restart doesn't happen until the end of the phase.
    New-Item -Path $Marker -Force | Out-Null
    Set-ItemProperty -Path $Marker -Name 'Version'   -Value $MarkerVersion
    Set-ItemProperty -Path $Marker -Name 'Updates'   -Value $UpdateStatus
    Set-ItemProperty -Path $Marker -Name 'Completed' -Value (Get-Date -Format 's')

    if ($RebootNeeded) {
        Write-Output 'All steps complete. Restart required (exit 3010).'
        Stop-Transcript | Out-Null
        exit 3010
    }
    Write-Output 'All steps complete. No restart required (exit 0).'
    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Output "FAILED: $($_.Exception.Message)"
    Write-Output $_.ScriptStackTrace
    Stop-Transcript | Out-Null
    exit 1
}
