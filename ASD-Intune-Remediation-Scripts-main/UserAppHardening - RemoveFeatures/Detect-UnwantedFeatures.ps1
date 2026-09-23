<#
.NOTES
    Run as:            SYSTEM
    Signature check:   No
    64-bit PowerShell: Yes
#>

Try {
    $PSv2 = Get-WindowsOptionalFeature -Online -FeatureName "MicrosoftWindowsPowerShellV2Root"
    if (($PSv2 -eq $null) -or ($PSv2.State -like "*Disabled*")){
        Write-Output "PowerShell 2 is not present"
    }
    else{
        Write-Output "PowerShell 2 installed, moving to remediation"
        exit 1
        }

    $dotNet35 = Get-WindowsOptionalFeature -Online -FeatureName "NetFx3"
    if (($dotNet35 -eq $null) -or ($dotNet35.State -like "*Disabled*")){
        Write-Output ".Net 3.5 is not present"
    }
    else{
        Write-Output ".Net 3.5 installed, moving to remediation"
        exit 1
        }

    $IE = Get-WindowsOptionalFeature -Online -FeatureName "Internet-Explorer-Optional-amd64"
    if (($IE -eq $null) -or ($IE.State -like "*Disabled*")){
        Write-Output "IE is not present"
    }
    else{
        Write-Output "IE installed, moving to remediation"
        exit 1
        }

    Write-Host "No Unwanted Features Detected"
    exit 0
}
catch{
    Write-Output "Failed: $($_.Exception.Message)"
    exit 1
    }