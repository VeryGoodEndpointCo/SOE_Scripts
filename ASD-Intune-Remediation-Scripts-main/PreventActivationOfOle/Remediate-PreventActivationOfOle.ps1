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
    }
    catch{
        Write-Output "Failed: $($_.Exception.Message)"
        exit 1
        }
    }

Foreach ($path in $paths){
    RemRegValue -regpath $path -regname $name -regvalue $expectedValue -regtype $type
}