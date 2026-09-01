
<#

    The URL to invoke this runbook is stored in a key vault. If it needs to be changed, update it in that key vault.
    
#>

param
(
    [Parameter(Mandatory=$false)]
    [object] $WebhookData
) 

Try { 

    write-output "start"
    $PSVersionTable.PSVersion

    write-output ("object type: {0}" -f $WebhookData.gettype())
    write-output $WebhookData
    write-output "`n`n"
    write-output $WebhookData.WebhookName
    write-output $WebhookData.RequestBody
    write-output $WebhookData.RequestHeader
    write-output "end"

<# Extract RequestBody using regex        THIS MAY ONLY APPLY WHEN INVOKING FROM ANOTHER RUNBOOK
if ($WebhookData -notmatch 'RequestBody:(\{.*?\})') {
    throw "RequestBody not found in WebhookData"
}

    $requestBodyJson = $matches[1]
    
    write-output $requestBodyJson
#>


    $payload = $requestBodyJson | ConvertFrom-Json
    $payload = $WebhookData.RequestBody | ConvertFrom-Json

    write-output "Payload: $payload"
    
    $email = $payload.email
    $assigneeEmail = $payload.assigneeEmail 

    write-output "Processing user: $email"

}
Catch {

    write-output "Webhook failed. "
    throw "Halting runbook execution"
}


Try {
    Import-Module Microsoft.Graph.Authentication -force -verbose
    Import-Module Microsoft.Graph.Users -force -verbose
    Import-Module Microsoft.Graph.Users.Actions -force -verbose
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
}
Catch{
    $_
}



Connect-MgGraph -Identity 

Get-MgUser -Top 1

Write-Output "Connected to Graph"

Get-MgContext | Format-List *

Write-Output "Context retrieved"

#>

<#######################################################################################

    Setup

########################################################################################>

   

    Connect-AzAccount -Identity

    #Set up email notifications. It will use a logic app named "Send_IT_Email"
    $LogicAppURL = "https://prod-57.eastus.logic.azure.com:443/workflows/6b556e09885f49fcbb5ab904a0265a8d/triggers/When_an_HTTP_request_is_received/paths/invoke?api-version=2016-10-01&sp=%2Ftriggers%2FWhen_an_HTTP_request_is_received%2Frun&sv=1.0&sig=eA-bW3ox4bYk-ybuZz57GtIfmr5bdwNlDSHMaOBSRc4"
    $ITEmail = 'dsnider@mcmillanpazdansmith.com,rjaquez@mcmillanpazdansmith.com'
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

    # fetch IDs and such from key vault
    $VaultName = "ITCrowd-Key-Vault"

    $TenantId = Get-AzKeyVaultSecret -VaultName $vaultName -Name "TenantId" -AsPlainText
    $GraphClientId = Get-AzKeyVaultSecret -VaultName $vaultName -Name "GraphClientId" -AsPlainText
    $GraphCertThumbprint = Get-AzKeyVaultSecret -VaultName $vaultName -Name "GraphCertThumbprint" -AsPlainText

    #Offboarding URL for notifications
    $WebhookURL = "https://default2f2f30649dcf49eaa3ca341498ba0c.ea.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/a9ea8a7f7f60463680d332dbc6767d15/triggers/manual/paths/invoke?api-version=1&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=lEzQUaKpbfI2lJlX21TLaathTbbe_MlrPHWOs0Q66NY"


    #Testing URL - IT alerts channel.     Comment this out after testing is completed
    $WebhookURL = "https://default2f2f30649dcf49eaa3ca341498ba0c.ea.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/194aa69bcc994a0cafb4ec1e47cff9de/triggers/manual/paths/invoke?api-version=1&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=7aJPxwEU_-k7B8a9G9WaJjhMyetIK2EF2R1hSFdZcYM"



    $Global:ErrorCount = 1  #tracks errors as they happen. Setting to 1 sends the notification email even without errors.

    # ----------------------------
    # Audit object
    # ----------------------------
    $Audit = [ordered]@{
        FirstName = ""
        LastName = ""
        UserEmail = $Email
        StartTime = Get-Date
        Actions   = @()
    }


<#######################################################################################

    Helper functions

########################################################################################>

    function Add-Audit {
        param($Step, $Status, $Detail)
        $Audit.Actions += [ordered]@{
            Step   = $Step
            Status = $Status
            Detail = $Detail
            Time   = Get-Date
        }
    }

    Function Record-Error {


    param(
            [Parameter(Mandatory)]
            [System.Management.Automation.ErrorRecord]$ErrorRecord,

            [string]$Context = "Unhandled error"
        )

        $msg =  "*********************************************************"
        $msg += "Error: $Global:ErrorCount"
        $msg += "Exception: $($ErrorRecord.Exception.Message)"
        $msg += "Type: $($ErrorRecord.Exception.GetType().FullName)"
        $msg += "Category: $($ErrorRecord.CategoryInfo)"
        $msg += "TargetObject: $($ErrorRecord.TargetObject)"
        $msg += "ScriptStackTrace: $($ErrorRecord.ScriptStackTrace)"
        $msg += "InvocationInfo: $($ErrorRecord.InvocationInfo.PositionMessage)"
        $msg += "*********************************************************"
        write-output $msg
        write-error $msg
        $Global:ErrorCount++
    }

    function New-RandomPassword {
        -join ((33..126) | Get-Random -Count 24 | ForEach-Object {[char]$_})

    }

    function Convert-RawJsonToAdaptiveCard {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Json
        )

        $data = $Json | ConvertFrom-Json

        $fullName = "$($data.FirstName) $($data.LastName)".Trim()
        if (-not $fullName) { $fullName = "Unknown User" }

        $body = New-Object System.Collections.Generic.List[object]

        # Title
        $body.Add(@{
            type   = "TextBlock"
            text   = "Cloud Offboarding $fullName"
            weight = "Bolder"
            size   = "Large"
        })

        # Optional subtitle (email)
        if ($data.UserEmail) {
            $body.Add(@{
                type     = "TextBlock"
                text     = $data.UserEmail
                isSubtle = $true
                wrap     = $true
            })
        }

        # Spacer
        $body.Add(@{ type = "TextBlock"; text = " " })

        # Table header (visual border via emphasis + separator)
        $body.Add(@{
            type = "ColumnSet"
            separator = $true
            columns = @(
                @{ type="Column"; width="stretch"; items=@(@{ type="TextBlock"; text="Step";   weight="Bolder" }) },
                @{ type="Column"; width="auto";    items=@(@{ type="TextBlock"; text="Status"; weight="Bolder" }) },
                @{ type="Column"; width="stretch"; items=@(@{ type="TextBlock"; text="Detail"; weight="Bolder" }) }
            )
        })

        # Action rows
        foreach ($a in @($data.Actions)) {
            $status = [string]$a.Status

            if ($status -match '^(Success|Succeeded)$') {
                $statusBlock = @{
                    type  = "TextBlock"
                    text  = "Success"
                    color = "Good"     # âœ… green
                    weight = "Bolder"
                    wrap  = $true
                }
            }
            else {
                $statusBlock = @{
                    type  = "TextBlock"
                    text  = "Failure"
                    color = "Attention" # âŒ red
                    weight = "Bolder"
                    wrap  = $true
                }
            }

            $body.Add(@{
                type      = "ColumnSet"
                separator = $true   # visual row border
                columns   = @(
                    @{ type="Column"; width="stretch"; items=@(@{
                        type = "TextBlock"
                        text = [string]$a.Step
                        wrap = $true
                    })},
                    @{ type="Column"; width="auto"; items=@($statusBlock) },
                    @{ type="Column"; width="stretch"; items=@(@{
                        type = "TextBlock"
                        text = [string]$a.Detail
                        wrap = $true
                    })}
                )
            })
        }

        # âœ… Final Adaptive Card (exactly what Flow expects)
        @{
            '$schema' = "http://adaptivecards.io/schemas/adaptive-card.json"
            type      = "AdaptiveCard"
            version   = "1.4"
            body      = $body
        } | ConvertTo-Json -Depth 40
    }



<#######################################################################################

    Active Directory
    - Invokes a hybrid runbook to run on on-prem machine

########################################################################################>

    $body = @{

        email = $email

    } | ConvertTo-Json -compress

    write-output "Body: $body"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("content-type", "application/json")
    $headers.Add("message", "Manually sent from Powershell")

    $invokeUrl = 'https://a820bc96-f0d4-4a0e-a996-c8a1db4b8416.webhook.eus.azure-automation.net/webhooks?token=wfp0AGVZCRZnERNJsDPhziXlRrky8bBC7wyHix7tanY%3d'
    
    $headerMessage = @{message = "Manually sent from Powershell"}

    $Response = Invoke-RestMethod -method Post -uri $invokeUrl -header $headers -body $body -UseBasicParsing -timeoutSec 20


        
<#######################################################################################

    Microsoft Graph
    - disables account in Entra
    - initiates disconnect from all devices

########################################################################################>



    write-output "Getting Entra account."
    try {
        $mgUser = Get-MgUser -Filter "UserPrincipalName eq '$Email'" -Property  Id,DisplayName,GivenName,Surname,Mail,UserPrincipalName
    }
    Catch {
        write-output "failure to get Entra user"
        write-output $_
    }

    if (-not $mgUser) { throw "Entra user not found" } else {

            $Audit.FirstName = $mgUser.GivenName
            $Audit.LastName = $mgUser.Surname

            write-output "UserPrincipalName: $($mgUser.UserPrincipalName)"
            write-output "GivenName: $($mgUser.GivenName)"
            write-output "Surname: $($mgUser.Surname)"
            write-output "DisplayName: $($mgUser.DisplayName)"

    }

    write-output "Getting Entra account of assignee."
    $assigneeUser = Get-MgUser -userid $assigneeEmail -Property  Id,DisplayName,GivenName,Surname,Mail,UserPrincipalName

    if (-not $assigneeUser) {
        
            Add-Audit "Get assignee email" "Failure" "$assigneeUser"
            $ErrorCount++
         
          } else {

              Add-Audit "Get assignee email" "Success" "$($assigneeUser.DisplayName)"

            write-output "UserPrincipalName: $($assigneeUser.UserPrincipalName)"
            write-output "GivenName: $($assigneeUser.GivenName)"
            write-output "Surname: $($assigneeUser.Surname)"
            write-output "DisplayName: $($assigneeUser.DisplayName)"

    }

    write-output "Disabling Entra Account."
    Try {
        Update-MgUser -UserId $mgUser.Id -AccountEnabled:$false
        Add-Audit "Disable Entra Account" "Success" "Account disabled"
    } Catch {
        Add-Audit "Disable Entra Account" "Failed" $_.Exception.Message
        $ErrorCount ++
    }

    write-output "Revoking all connected sessions."
    Try {
        Revoke-MgUserSignInSession -UserId $mgUser.Id
        Add-Audit "Revoke Sessions" "Success" "Sessions revoked"
    } Catch {
        Add-Audit "Revoke Sessions" "Failed" $_.Exception.Message
        $ErrorCount ++
    }

    <#
    # Remove from M365 groups
        $m365Groups = Get-MgUserMemberOf -UserId $mguser.Id -All |
            Where-Object {
                $_.AdditionalProperties.groupTypes -contains "Unified"
            }


        foreach ($group in $m365Groups) {
            try {
                Write-Output "Removing $email from M365 group: $($group.AdditionalProperties.displayName)"
            
                Remove-MgGroupMemberByRef `
                        -GroupId $group.Id `
                        -DirectoryObjectId $user.Id `
                        -ErrorAction Stop
            }
            catch {
                Write-Error "Failed to remove from M365 group [$($group.Id)]: $_"
            }

        }

    #>

    Disconnect-MgGraph | Out-Null

<#######################################################################################

    Exchange Online
    - calls a different runbook and waits for results to be returned (10 min timeout)

########################################################################################>

    Try {
    Connect-ExchangeOnline -managedidentity -Organization 'mcmillanpazdansmith.onmicrosoft.com'

        Add-Audit "Connect Exchange Online" "Success" "Connected"
    } Catch {
        Add-Audit "Connect Exchange Online" "Failed" $_.Exception.Message
        $ErrorCount ++
    }


       #grant permissions for someone to monitor the email inbox
    Try {

        Add-MailboxPermission `
        -Identity $Email `
        -User $AssigneeEmail `
        -AccessRights FullAccess `
        -InheritanceType All `
        -AutoMapping:$true

    
        Add-Audit "Add mailbox permissions" "Success" "$($assigneeUser.displayname)"

        # Set mailbox to shared
        # Set-Mailbox $Email -Type Shared

    } Catch {
        Add-Audit "Add mailbox permissions" "Failed" $_.Exception.Message
        $ErrorCount ++
    }




    # Add OOO message for all incoming email.
    $Message = "Thank you for your email. $($mgUser.displayname) is no longer at MPS, and the email you reached is no longer active. Please direct your inquiry to $($assigneeUser.displayname) at $AssigneeEmail"
    
    write-output $message

    Try {

        $result = Set-MailboxAutoReplyConfiguration -Identity $email -AutoReplyState Enabled `
        -InternalMessage $message -ExternalMessage $message -ExternalAudience All 

        $result | fl *

    
        Add-Audit "Add Out of Office message" "Success" "OOO set"
    } Catch {
        Add-Audit "Add Out of Office message" "Failed" $_.Exception.Message
        $ErrorCount ++
    }



<#######################################################################################

    Finish the audit trail

########################################################################################>

    $Audit.EndTime = Get-Date
    $Audit.Duration = ($Audit.EndTime - $Audit.StartTime).ToString()
    $Audit.GeneratedPassword = $pw

    $Audit | ConvertTo-Json -Depth 6



<#######################################################################################

    Send notifications

########################################################################################>

#Create adaptiveCard from audit 
$adaptiveCardJson = Convert-RawJsonToAdaptiveCard -Json ($Audit | ConvertTo-Json -Depth 6)


Invoke-RestMethod `
  -Method Post `
  -Uri $WebhookUrl `
  -ContentType 'application/json' `
  -Body $adaptiveCardJson


<#####################################################################################################

    Send email notification

#####################################################################################################>

write-output "Errors: $ErrorCount"

    if ($ErrorCount -gt 0) {
        $EmailHtmlBody = @"
        <html>
        <head>
        <script type="application/adaptivecard+json">
            $AdaptiveCardJson
        </script>
        </head>
        <body>
        <p>If your email client doesn't support Actionable Messages, you will see this fallback text.</p>
        </body>
        </html>
"@

        $payload = @{
            to      = $ITEmail
            subject = "Cloud Offboarding failure - $email"
            message    = $EmailHtmlBody
        } | ConvertTo-Json -Depth 5

        try {
            Invoke-RestMethod -Uri $logicAppUrl `
                -Method POST `
                -Body $payload `
                -ContentType "application/json"

            Write-Output "Email sent via Logic App"
        }
        catch {
            Write-Error "Failed to call Logic App. $_"
        }
    }