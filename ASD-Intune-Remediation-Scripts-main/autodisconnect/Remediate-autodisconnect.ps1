<#
.NOTES
    Run as:            SYSTEM
    Signature check:   No
    64-bit PowerShell: Yes
#>
$path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters"
$name = "autodisconnect"
$expectedValue = "15"
$type = "DWORD"

Function RemRegValue{
    param (
        [Parameter(Mandatory=$true)]
        [string]$regpath,
        [Parameter(Mandatory=$true)]
        [string]$regname,
        [Parameter(Mandatory=$true)]
        [string]$regvalue,
        [Parameter(Mandatory=$true)]
        [string]$regtype
        )
    Try{
        if (!(test-path $regpath)){
            New-Item $regpath -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -Path $regpath -Name $regname -Value $regvalue -PropertyType $regtype -Force -ErrorAction Stop | Out-Null
        Write-Output "Successfully applied key $regname, with value of $regvalue"
        Exit 0
    }
    catch{
        Write-Output "Failed: $($_.Exception.Message)"
        exit 1
        }
    }

RemRegValue -regpath $path -regname $name -regvalue $expectedValue -regtype $type
