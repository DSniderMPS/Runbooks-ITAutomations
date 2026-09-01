param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = 'MPS_Automations',

    [Parameter(Mandatory = $false)]
    [string]$AutomationAccountName = 'IT-Automations',

    [Parameter(Mandatory = $false)]
    [string]$GitHubOwner = 'DSniderMPS',

    [Parameter(Mandatory = $false)]
    [string]$GitHubRepo = 'Runbooks-ITAutomations',

    [Parameter(Mandatory = $false)]
    [string]$Branch = "main",

    # Name of the Credential Asset created in Azure Automation
    [Parameter(Mandatory = $false)]
    [string]$CredentialAssetName = "GitHubPatCredential"
)


# 1. Connect via Managed Identity
Connect-AzAccount -Identity | Out-Null

# 2. Get GitHub PAT from Automation Assets
$ghCredential = Get-AutomationPSCredential -Name $CredentialAssetName
if (-not $ghCredential) {
    throw "Credential asset '$CredentialAssetName' could not be retrieved."
}

$gitHubPat = $ghCredential.GetNetworkCredential().Password

$headers = @{
    "Authorization" = "token $gitHubPat"
    "Accept"        = "application/vnd.github.v3+json"
    "User-Agent"    = "AzureAutomationRunbook"
}

# 3. Get all published Runbooks
$runbooks = Get-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
                                     -AutomationAccountName $AutomationAccountName

Write-Output "Found $($runbooks.Count) runbooks. Starting sync..."

$tempPath = $env:TEMP

foreach ($runbook in $runbooks) {
    $name = $runbook.Name
    $type = $runbook.RunbookType
    
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

    # Export published version locally
    Export-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
                              -AutomationAccountName $AutomationAccountName `
                              -Name $name `
                              -OutputFolder $tempPath `
                              -Slot Published | Out-Null

    # Compute SHA256 of local content
    $localHash = (Get-FileHash -Path $localFilePath -Algorithm SHA256).Hash

    # Prepare raw bytes and base64
    $contentRaw = Get-Content -Path $localFilePath -Raw
    $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($contentRaw)
    $base64Content = [System.Convert]::ToBase64String($contentBytes)

    # Check GitHub for existing file metadata
    $ghApiUrl = "https://api.github.com/repos/$GitHubOwner/$GitHubRepo/contents/$fileName?ref=$Branch"
    $fileSha = $null
    $remoteHash = $null

    try {
        $existingFile = Invoke-RestMethod -Uri $ghApiUrl -Headers $headers -Method Get -ErrorAction Stop
        
        # Verify SHA exists on the response object
        if ($null -ne $existingFile -and $null -ne $existingFile.sha) {
            $fileSha = $existingFile.sha

            # Decode existing GitHub file base64 content to compare hash
            $cleanBase64 = $existingFile.content -replace "\s", ""
            if (-not [string]::IsNullOrEmpty($cleanBase64)) {
                $remoteRawBytes = [System.Convert]::FromBase64String($cleanBase64)
                $hasher = [System.Security.Cryptography.SHA256]::Create()
                $remoteHash = ([System.BitConverter]::ToString($hasher.ComputeHash($remoteRawBytes))).Replace("-", "")
            }
        }
    } catch [System.Net.WebException] {
        $resp = $_.Exception.Response
        if ($resp -and $resp.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
            Write-Output "[i] $fileName is new (not found on GitHub)."
        } else {
            $errMessage = $_.Exception.Message
            Write-Warning "WebException checking GitHub for ${fileName}: ${errMessage}"
        }
    } catch {
        $errMessage = $_.Exception.Message
        Write-Warning "Error checking GitHub for ${fileName}: ${errMessage}"
    }

    # Skip commit if content hasn't changed
    if ($remoteHash -and ($localHash -eq $remoteHash)) {
        Write-Output "[-] No changes detected for $fileName. Skipping."
        Remove-Item -Path $localFilePath -Force -ErrorAction SilentlyContinue
        continue
    }

    # Construct request body
    $body = @{
        message = "Sync runbook $fileName from Azure Automation"
        content = $base64Content
        branch  = $Branch
    }

    # Attach SHA if the file already exists on GitHub
    if (-not [string]::IsNullOrEmpty($fileSha)) {
        $body["sha"] = $fileSha
    }

    $jsonBody = $body | ConvertTo-Json -Compress

    try {
        $commitUrl = "https://api.github.com/repos/$GitHubOwner/$GitHubRepo/contents/$fileName"
        $response = Invoke-RestMethod -Uri $commitUrl -Headers $headers -Method Put -Body $jsonBody -ErrorAction Stop
        Write-Output "[+] Successfully committed $fileName to $GitHubOwner/$GitHubRepo ($Branch)"
    } catch {
        $errMessage = $_.Exception.Message
        if ($_.Exception.Response) {
            # Capture full response body from API error if available
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $apiError = $reader.ReadToEnd()
            Write-Error "Failed to commit ${fileName} to GitHub: ${errMessage} | Details: ${apiError}"
        } else {
            Write-Error "Failed to commit ${fileName} to GitHub: ${errMessage}"
        }
    }

    # Clean up local temp file
    Remove-Item -Path $localFilePath -Force -ErrorAction SilentlyContinue
}

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

# Check existing file on GitHub safely in PowerShell 5.1
    $ghApiUrl = "https://api.github.com/repos/$GitHubOwner/$GitHubRepo/contents/$fileName?ref=$Branch"
    $fileSha = $null
    $remoteHash = $null

    try {
        $existingFile = Invoke-RestMethod -Uri $ghApiUrl -Headers $headers -Method Get
        
        if ($existingFile.sha) {
            $fileSha = $existingFile.sha

            # Decode base64 content from GitHub to compute its SHA256 hash
            $remoteRawBytes = [System.Convert]::FromBase64String($existingFile.content)
            $hasher = [System.Security.Cryptography.SHA256]::Create()
            $remoteHash = ([System.BitConverter]::ToString($hasher.ComputeHash($remoteRawBytes))).Replace("-", "")
        }
    } catch [System.Net.WebException] {
        # Check if error is a 404 (File does not exist on GitHub yet)
        $resp = $_.Exception.Response
        if ($resp -and $resp.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
            Write-Output "[i] $fileName does not exist on GitHub yet. Creating new file."
        } else {
            $errMessage = $_.Exception.Message
            Write-Warning "WebException checking GitHub for ${fileName}: ${errMessage}"
        }
    } catch {
        $errMessage = $_.Exception.Message
        Write-Warning "Unexpected error checking GitHub for ${fileName}: ${errMessage}"
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