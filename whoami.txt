Write-Output "=== Hybrid Worker Execution Context Test ==="
 
# 1. Standard user check
$currentUser = whoami
Write-Output "Current User (whoami): $currentUser"

# 2. Environment variable check
$envUser = $env:USERNAME
$envDomain = $env:USERDOMAIN
Write-Output "Environment Variables: $envDomain\$envUser"

# 3. Deep Process Account Check (More accurate for service accounts)
$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Output "Windows Identity Principal: $currentIdentity"

Write-Output "==========================================="
