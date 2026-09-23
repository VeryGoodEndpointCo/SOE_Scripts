<#
.NOTES
    Run as:            SYSTEM
    Signature check:   No
    64-bit PowerShell: Yes
#>

$path = "HKLM:\System\CurrentControlSet\Control\Lsa"
$name = "EveryoneIncludesAnonymous"
$expectedValue = "0"

Function DetRegValue{
    param (
        [Parameter(Mandatory=$true)]
        [string]$regpath,
        [Parameter(Mandatory=$true)]
        [string]$regname,
        [Parameter(Mandatory=$true)]
        [string]$regvalue
        )
    Try{
        $Value = Get-ItemPropertyValue -Path $regpath -Name $regname -ErrorAction Stop
        If ($Value -eq $regvalue){
            Write-Output "Compliant: $regname"
            exit 0
        }
        else{
            Write-Output "Non-Compiant: $regname = $Value"
            Exit 1
        }
    }
    catch{
        Write-Output "Non-Compliant: key or value missing - $($_.Exception.Message)"
        exit 1
        }
    }

DetRegValue -regpath $path -regname $name -regvalue $expectedValue
