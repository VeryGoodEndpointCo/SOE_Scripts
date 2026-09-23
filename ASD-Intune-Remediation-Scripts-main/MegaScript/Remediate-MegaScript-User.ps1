<#
Does all the device reg change needed by the ASD in one script
https://blueprint.asd.gov.au/configuration/intune/devices/scripts/
    
Run as:            USER
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


Write-Host "# Disable OLE Activation - Excel #"
$Params = @{
    Key   = 'HKCU:\Software\Microsoft\Office\16.0\Excel\Security"'
    Name  = 'PackagerPrompt'
    Value = '2'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# Disable OLE Activation - PowerPoint #"
$Params = @{
    Key   = 'HKCU:\Software\Microsoft\Office\16.0\PowerPoint\Security'
    Name  = 'PackagerPrompt'
    Value = '2'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# Disable OLE Activation - Word #"
$Params = @{
    Key   = 'HKCU:\Software\Microsoft\Office\16.0\Word\Security'
    Name  = 'PackagerPrompt'
    Value = '2'
    $Type = 'DWord'
}
Set-RegistryKey @Params

Write-Host "# Enable Trust Centre Logging #"
$Params = @{
    Key   = 'HKCU:\Software\Microsoft\office\16.0\Common\TrustCenter'
    Name  = 'EnableLogging'
    Value = '1'
    $Type = 'DWord'
}
Set-RegistryKey @Params

