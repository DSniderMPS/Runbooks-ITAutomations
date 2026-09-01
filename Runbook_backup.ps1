param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName = 'MPS_Automations',

    [Parameter(Mandatory = $true)]
    [string]$AutomationAccountName = 'IT-Automations',

    [Parameter(Mandatory = $true)]
    [string]$GitHubOwner = 'DSniderMPS',

    [Parameter(Mandatory = $true)]
    [string]$GitHubRepo = 'Runbooks-ITAutomations',

    [Parameter(Mandatory = $false)]
    [string]$Branch = "main",

    # Name of the Credential Asset created in Azure Automation
    [Parameter(Mandatory = $false)]
    [string]$CredentialAssetName = "GitHubPatCredential"
)


# 1. Connect using System-Assigned Managed Identity
Connect-AzAccount -Identity | Out-Null

# 2. Retrieve GitHub PAT from Azure Automation Credential Asset
$ghCredential = Get-AutomationPSCredential -Name $CredentialAssetName
if (-not $ghCredential) {
    throw "Credential asset '$CredentialAssetName' could not be retrieved."
}

# Get NetworkCredential to extract the plain-text password (PAT) safely in memory
$gitHubPat = $ghCredential.GetNetworkCredential().Password

# Setup GitHub Authorization Header
$headers = @{
    "Authorization" = "token $gitHubPat"
    "Accept"        = "application/vnd.github.v3+json"
}

# 3. Fetch all published Runbooks
$runbooks = Get-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
                                     -AutomationAccountName $AutomationAccountName

Write-Output "Found $($runbooks.Count) runbooks. Starting sync process..."

$tempPath = $env:TEMP

foreach ($runbook in $runbooks) {
    $name = $runbook.Name
    $type = $runbook.RunbookType
    
    # Determine file extension based on runbook type
    $ext = switch ($type) {
        "PowerShell"          { ".ps1" }
        "PowerShellWorkflow"  { ".ps1" }
        "GraphicalPowerShell" { ".graphrunbook" }
        "Python2"             { ".py" }
        "Python3"             { ".py" }
        Default               { ".txt" }
    }
    
    $fileName = "$name$ext"
    $localFilePath = Join-Path -Path $tempPath -ChildPath $fileName

    # Export content locally
    Export-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
                              -AutomationAccountName $AutomationAccountName `
                              -Name $name `
                              -OutputFolder $tempPath `
                              | Out-Null

    # Calculate local content hash
    $localHash = (Get-FileHash -Path $localFilePath -Algorithm SHA256).Hash

    # Read bytes for Base64 encoding
    $contentRaw = Get-Content -Path $localFilePath -Raw
    $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($contentRaw)
    $base64Content = [System.Convert]::ToBase64String($contentBytes)

    # Check existing file on GitHub
    $ghApiUrl = "https://api.github.com/repos/$GitHubOwner/$GitHubRepo/contents/$fileName?ref=$Branch"
    $fileSha = $null
    $remoteHash = $null

    try {
        $existingFile = Invoke-RestMethod -Uri $ghApiUrl -Headers $headers -Method Get
        $fileSha = $existingFile.sha

        # Decode base64 content from GitHub to compute its SHA256 hash
        $remoteRawBytes = [System.Convert]::FromBase64String($existingFile.content)
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        $remoteHash = ([System.BitConverter]::ToString($hasher.ComputeHash($remoteRawBytes))).Replace("-", "")
    } catch {
        # File doesn't exist on GitHub yet (404)
    }

    # Compare hashes prior to committing
    if ($remoteHash -and ($localHash -eq $remoteHash)) {
        Write-Output "[-] No changes detected for $fileName. Skipping commit."
        Remove-Item -Path $localFilePath -Force -ErrorAction SilentlyContinue
        continue
    }

    # 4. Commit or update file on GitHub
    $body = @{
        message = "Sync runbook $fileName from Azure Automation"
        content = $base64Content
        branch  = $Branch
    }

    if ($fileSha) {
        $body.sha = $fileSha
    }

    $jsonBody = $body | ConvertTo-Json -Compress

    try {
        $commitUrl = "https://api.github.com/repos/$GitHubOwner/$GitHubRepo/contents/$fileName"
        $response = Invoke-RestMethod -Uri $commitUrl -Headers $headers -Method Put -Body $jsonBody
        Write-Output "[+] Successfully committed $fileName to $GitHubOwner/$GitHubRepo ($Branch)"
    } catch {
        Write-Error "Failed to commit $fileName to GitHub: $_"
    }

    # Clean up local temporary file
    Remove-Item -Path $localFilePath -Force -ErrorAction SilentlyContinue
}