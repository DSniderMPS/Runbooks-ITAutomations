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

# Helper Function: Calculate GitHub's native Git Blob SHA-1
function Get-GitBlobSha {
    param([byte[]]$fileBytes)

    $headerStr = "blob $($fileBytes.Length)`0"
    $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($headerStr)
    
    $combinedBytes = New-Object byte[] ($headerBytes.Length + $fileBytes.Length)
    [Array]::Copy($headerBytes, 0, $combinedBytes, 0, $headerBytes.Length)
    [Array]::Copy($fileBytes, 0, $combinedBytes, $headerBytes.Length, $fileBytes.Length)

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    $hashBytes = $sha1.ComputeHash($combinedBytes)
    return ([System.BitConverter]::ToString($hashBytes)).Replace("-", "").ToLower()
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
    
    $targetFileName = "$name$ext"
    $escapedFileName = [Uri]::EscapeDataString($targetFileName)

    # Export published version locally
    Export-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
                              -AutomationAccountName $AutomationAccountName `
                              -Name $name `
                              -OutputFolder $tempPath `
                              -Slot Published | Out-Null

    # Dynamically locate exported file (handles varying default export naming)
    $exportedFile = Get-ChildItem -Path $tempPath -Filter "$name*" | Select-Object -First 1

    if (-not $exportedFile -or -not (Test-Path $exportedFile.FullName)) {
        Write-Error "Could not find exported local file for runbook '$name' in $tempPath"
        continue
    }

    $localFilePath = $exportedFile.FullName

    # Read raw bytes directly
    $fileBytes = [System.IO.File]::ReadAllBytes($localFilePath)
    $localBlobSha = Get-GitBlobSha -fileBytes $fileBytes
    
    # Ensure raw Base64 string has NO line insertions (PS 5.1 safe)
    $base64Content = [System.Convert]::ToBase64String($fileBytes, [System.Base64FormattingOptions]::None)


Write-Output "*********************************************BEGIN*************************************************************"

$testUrl = "https://api.github.com/repos/$GitHubOwner/$GitHubRepo/contents/Create-VantagePointProject.ps1?ref=$Branch"
try {
    $res = Invoke-RestMethod -Uri $testUrl -Headers $headers -Method Get
    Write-Output "SUCCESS: Found file! SHA is $($res.sha)"
} catch {
    Write-Output "DEBUG ERROR: $_"
    Write-Output "Status Code: $($_.Exception.Response.StatusCode)"
}


Write-Output "********************************************END**************************************************************"

    # Check GitHub for existing file metadata
    $ghApiUrl = "https://api.github.com/repos/$GitHubOwner/$GitHubRepo/contents/${escapedFileName}?ref=$Branch"
    $fileSha = $null

    try {
        $existingFile = Invoke-RestMethod -Uri $ghApiUrl -Headers $headers -Method Get -ErrorAction Stop
        if ($existingFile -and $existingFile.sha) {
            $fileSha = $existingFile.sha
        }
    } catch [System.Net.WebException] {
        $resp = $_.Exception.Response
        if ($resp -and $resp.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
            Write-Output "[i] $targetFileName is a new file."
        } else {
            $errMessage = $_.Exception.Message
            Write-Warning "WebException checking GitHub for ${targetFileName}: ${errMessage}"
        }
    } catch {
        $errMessage = $_.Exception.Message
        Write-Warning "Error checking GitHub for ${targetFileName}: ${errMessage}"
    }

    # Compare local Git Blob SHA directly with GitHub's returned blob SHA
    if ($fileSha -and ($localBlobSha -eq $fileSha)) {
        Write-Output "[-] No changes detected for $targetFileName. Skipping commit."
        Remove-Item -Path $localFilePath -Force -ErrorAction SilentlyContinue
        continue
    }

    # Construct request payload
    $body = @{
        message = "Sync runbook $targetFileName from Azure Automation"
        content = $base64Content
        branch  = $Branch
    }

    # Include existing file SHA if updating
    if ($fileSha) {
        $body["sha"] = $fileSha
    }

    $jsonBody = $body | ConvertTo-Json -Compress

    try {
        $commitUrl = "https://api.github.com/repos/$GitHubOwner/$GitHubRepo/contents/${escapedFileName}"
        $response = Invoke-RestMethod -Uri $commitUrl -Headers $headers -Method Put -Body $jsonBody -ErrorAction Stop
        Write-Output "[+] Successfully committed $targetFileName to $GitHubOwner/$GitHubRepo ($Branch)"
    } catch [System.Net.WebException] {
        $errMessage = $_.Exception.Message
        $respStream = $_.Exception.Response.GetResponseStream()
        if ($respStream) {
            $reader = New-Object System.IO.StreamReader($respStream)
            $apiError = $reader.ReadToEnd()
            Write-Error "Failed to commit ${targetFileName} to GitHub: ${errMessage} | API Response: ${apiError}"
        } else {
            Write-Error "Failed to commit ${targetFileName} to GitHub: ${errMessage}"
        }
    } catch {
        $errMessage = $_.Exception.Message
        Write-Error "Failed to commit ${targetFileName} to GitHub: ${errMessage}"
    }

    # Clean up local temp file
    Remove-Item -Path $localFilePath -Force -ErrorAction SilentlyContinue
}