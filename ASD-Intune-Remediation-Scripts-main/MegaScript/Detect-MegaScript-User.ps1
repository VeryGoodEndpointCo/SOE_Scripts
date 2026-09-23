<#
Does all the device reg change needed by the ASD in one script
https://blueprint.asd.gov.au/configuration/intune/devices/scripts/
    
Run as:            USER
    Signature check:   No
    64-bit PowerShell: Yes
#>

Function Check-RegistryKey {
    
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [string]$Key,
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Mandatory = $false)]
        $Value
    )

    Try{
        $RealValue = Get-ItemPropertyValue -Path $Key -Name $Name -ErrorAction Stop
        If ($RealValue -eq $Value){
            Write-Output "Compliant: $Name"
        }
        else{
            Write-Output "Non-Compiant: $Name = $RealValue"
            Exit 1
        }
    }
    catch{
        Write-Output "Non-Compliant: key or value missing - $($_.Exception.Message)"
        exit 1
        }
}


Write-Host "# Disable OLE Activation - Excel #"
$Params = @{
    Key   = 'HKCU:\Software\Microsoft\Office\16.0\Excel\Security"'
    Name  = 'PackagerPrompt'
    Value = '2'
}
Set-RegistryKey @Params

Write-Host "# Disable OLE Activation - PowerPoint #"
$Params = @{
    Key   = 'HKCU:\Software\Microsoft\Office\16.0\PowerPoint\Security'
    Name  = 'PackagerPrompt'
    Value = '2'
}
Set-RegistryKey @Params

Write-Host "# Disable OLE Activation - Word #"
$Params = @{
    Key   = 'HKCU:\Software\Microsoft\Office\16.0\Word\Security'
    Name  = 'PackagerPrompt'
    Value = '2'
}
Set-RegistryKey @Params

Write-Host "# Enable Trust Centre Logging #"
$Params = @{
    Key   = 'HKCU:\Software\Microsoft\office\16.0\Common\TrustCenter'
    Name  = 'EnableLogging'
    Value = '1'
}
Set-RegistryKey @Params

