<#
.NOTES
    Run as:            USER
    Signature check:   No
    64-bit PowerShell: Yes
#>
$paths = @(
"HKCU:\Software\Microsoft\Office\16.0\Excel\Security",
"HKCU:\Software\Microsoft\Office\16.0\PowerPoint\Security",
"HKCU:\Software\Microsoft\Office\16.0\Word\Security"
)
$name = "PackagerPrompt"
$expectedValue = "2"

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

Foreach ($path in $paths){
    DetRegValue -regpath $path -regname $name -regvalue $expectedValue
}
