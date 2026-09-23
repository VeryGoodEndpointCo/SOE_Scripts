<#
Does all the device reg change needed by the ASD in one script
https://blueprint.asd.gov.au/configuration/intune/devices/scripts/
    
Run as:            SYSTEM
    Signature check:   No
    64-bit PowerShell: Yes
#>

Function Set-RegistryKey {
    
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [string]$Key,
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Mandatory = $false)]
        $Value,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Binary', 'DWord', 'ExpandString', 'MultiString', 'None', 'QWord', 'String', 'Unknown')]
        [Microsoft.Win32.RegistryValueKind]$Type
    )

    Try{

        if (!(Get-Item $Key -ErrorAction SilentlyContinue)) {
            $null = New-Item $Key -Force
        }

        New-ItemProperty -Path $regpath -Name $regname -Value $regvalue -PropertyType $regtype -Force -ErrorAction Stop | Out-Null
        Write-Output "Successfully applied key $regname, with value of $regvalue"
        }
    catch{
        Write-Output "Failed: $($_.Exception.Message)"
        exit 1
        }
}


Write-Host "# Allow Null Session Fallback #"
$Params = @{
    Key   = 'HKLM:\System\CurrentControlSet\Control\LSA\MSV1_0'
    Name  = 'allownullsessionfallback'
    Value = '0'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# Autodisconnect #"
$Params = @{
    Key   = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters'
    Name  = 'autodisconnect'
    Value = '15'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# VBA Require LM Trusted Publisher #"
$Params = @{
    Key   = 'HKCU:\Software\Policies\Microsoft\office\16.0\excel\security'
    Name  = 'vbarequirelmtrustedpublisher'
    Value = '1'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# Disable Domain Credentials #"
$Params = @{
    Key   = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    Name  = 'DisableDomainCreds'
    Value = '1'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# Disable Password Change #"
$Params = @{
    Key   = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
    Name  = 'DisablePasswordChange'
    Value = '0'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# Everyone Includes Anonymous #"
$Params = @{
    Key   = 'HKLM:\System\CurrentControlSet\Control\Lsa'
    Name  = 'EveryoneIncludesAnonymous'
    Value = '0'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# FIPS Algorithm Policy #"
$Params = @{
    Key   = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FIPSAlgorithmPolicy'
    Name  = 'Enabled'
    Value = '1'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# Force Key Protection #"
$Params = @{
    Key   = 'HKLM:\SOFTWARE\Policies\Microsoft\Cryptography'
    Name  = 'ForceKeyProtection'
    Value = '2'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# LDAP Client Integrity #"
$Params = @{
    Key   = 'HKLM:\System\CurrentControlSet\Services\LDAP'
    Name  = 'LDAPClientIntegrity'
    Value = '2'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# Maximum Password Age #"
$Params = @{
    Key   = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
    Name  = 'MaximumPasswordAge'
    Value = '30'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# ObCaseInsensitive #"
$Params = @{
    Key   = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel'
    Name  = 'ObCaseInsensitive'
    Value = '1'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# Protection Mode #"
$Params = @{
    Key   = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    Name  = 'ProtectionMode'
    Value = '1'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# Require Sign or Seal #"
$Params = @{
    Key   = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
    Name  = 'RequireSignOrSeal'
    Value = '1'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# Require Strong Key #"
$Params = @{
    Key   = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
    Name  = 'RequireStrongKey'
    Value = '1'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# SCE No Apply Legacy Audit Policy #"
$Params = @{
    Key   = 'HKLM:\System\CurrentControlSet\Control\Lsa'
    Name  = 'SCENoApplyLegacyAuditPolicy'
    Value = '1'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# Seal Secure Channel #"
$Params = @{
    Key   = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
    Name  = 'SealSecureChannel'
    Value = '1'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# Sign Secure Channel #"
$Params = @{
    Key   = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
    Name  = 'SignSecureChannel'
    Value = '1'
    $Type = 'DWord'
}
Set-RegistryKey @Params