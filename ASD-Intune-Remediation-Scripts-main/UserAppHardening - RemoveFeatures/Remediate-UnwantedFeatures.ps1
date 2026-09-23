<#
.NOTES
    Run as:            SYSTEM
    Signature check:   No
    64-bit PowerShell: Yes
#>
try {
    Disable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -ErrorAction Stop

} catch {
    Write-Output "Failed: $($_.Exception.Message)"
    exit 1

}

## Removing .NET 3.5 (and below)
try {
    Disable-WindowsOptionalFeature -Online -FeatureName NetFx3 -NoRestart

} catch {
    Write-Output "Failed: $($_.Exception.Message)"
    exit 1

}

## Removing Internet Explorer (for Windows 10)
try {
    Disable-WindowsOptionalFeature -Online -FeatureName Internet-Explorer-Optional-amd64 -NoRestart
    
    } catch {
    
    Write-Output "Failed: $($_.Exception.Message)"
    exit 1
    
    }

Write-Host "No Unwanted Features Detected"
exit 0
