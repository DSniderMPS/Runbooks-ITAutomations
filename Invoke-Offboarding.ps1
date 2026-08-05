
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

# Extract RequestBody using regex
if ($WebhookData -notmatch 'RequestBody:(\{.*?\})') {
    throw "RequestBody not found in WebhookData"
}

    $requestBodyJson = $matches[1]

    write-output $requestBodyJson
    $payload = $requestBodyJson | ConvertFrom-Json

    write-output $payload
    
    $email = $payload.email

}
Catch {

    write-output "Webhook failed. "
    throw "Halting runbook execution"
}

Write-Output "WhoAmI:"
whoami
 
Write-Output "Current Identity:"
[System.Security.Principal.WindowsIdentity]::GetCurrent().Name

write-output "Processing $email..."



<#######################################################################################

    Setup

########################################################################################>

Import-Module ExchangeOnlineManagement -ErrorAction Stop

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$TenantId = '2f2f3064-9dcf-49ea-a3ca-341498ba0cea'
$GraphClientId = '413af4fa-ba8b-4671-b724-28316367dc3e'
$GraphCertThumbprint = 'F7132556ADC49014DCE8ECD838B27E7C43C4ED74'
$ExoOrganization = 'mcmillanpazdansmith.onmicrosoft.com'

#Offboarding URL for notifications
$WebhookURL = "https://default2f2f30649dcf49eaa3ca341498ba0c.ea.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/a9ea8a7f7f60463680d332dbc6767d15/triggers/manual/paths/invoke?api-version=1&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=lEzQUaKpbfI2lJlX21TLaathTbbe_MlrPHWOs0Q66NY"


#Testing URL - IT alerts channel.     Comment this out after testing is completed
$WebhookURL = "https://default2f2f30649dcf49eaa3ca341498ba0c.ea.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/194aa69bcc994a0cafb4ec1e47cff9de/triggers/manual/paths/invoke?api-version=1&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=7aJPxwEU_-k7B8a9G9WaJjhMyetIK2EF2R1hSFdZcYM"

$Global:ErrorCount = 1  #tracks errors as they happen

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
        text   = "Offboarding – $fullName"
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
                color = "Good"     # ✅ green
                weight = "Bolder"
                wrap  = $true
            }
        }
        else {
            $statusBlock = @{
                type  = "TextBlock"
                text  = "Failure"
                color = "Attention" # ❌ red
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

    # ✅ Final Adaptive Card (exactly what Flow expects)
    @{
        '$schema' = "http://adaptivecards.io/schemas/adaptive-card.json"
        type      = "AdaptiveCard"
        version   = "1.4"
        body      = $body
    } | ConvertTo-Json -Depth 40
}


<#######################################################################################

    Active Directory
    - sets a random password
    - disables the account
    - moves to disabled OU

########################################################################################>


Import-Module ActiveDirectory

    write-output "Getting AD User."
    $adUser = Get-ADUser -Filter "Mail -eq '$Email'" -Properties SamAccountName,givenname,sn,DistinguishedName
    if (-not $adUser) { throw "AD user not found" }

    $Audit.FirstName = $adUser.givenname
    $Audit.LastName = $adUser.sn

    Add-Audit "Get AD User" "Success" $adUser.SamAccountName

    write-output "Setting to random password."
    Try {
    $pw = New-RandomPassword
    Set-ADAccountPassword -Identity $adUser.SamAccountName `
        -NewPassword (ConvertTo-SecureString $pw -AsPlainText -Force) `
        -Reset
    Add-Audit "Reset AD Password" "Success" "Password reset"
    } Catch {
        Add-Audit "Reset AD Password" "Failed" $_.Exception.Message
        Record-Error -ErrorRecord $_
    }

    write-output "Disabling local A/D account"
    Try {
    Disable-ADAccount -Identity $adUser.SamAccountName
    Add-Audit "Disable AD Account" "Success" "Account disabled"
    } Catch {
        Add-Audit "Disable AD Account" "Failed" $_.Exception.Message
        Record-Error -ErrorRecord $_
    }

    write-output "Moving to disabled OU"
    Try {
    $dn = [string]($adUser.DistinguishedName | Select-Object -First 1)
    Move-ADObject -TargetPath "OU=Old Users and Computers,DC=mcmillanpazdansmith,DC=com" -Identity $dn
    Add-Audit "Move to Disabled OU" "Success" "Account in OUR"
    } Catch {
        Add-Audit "Move to Disabled OU" "Failed" $_.Exception.Message
        Record-Error -ErrorRecord $_
    }
    
<#######################################################################################

    Microsoft Graph
    - disables account in Entra
    - initiates disconnect from all devices

########################################################################################>

    Import-Module Microsoft.Graph.Authentication
    Import-Module Microsoft.Graph.Users
    Import-Module Microsoft.Graph.Users.Actions

    write-output "Connecting to MgGraph."
    Try {
        Connect-MgGraph -TenantId $TenantId -ClientId $GraphClientId  -CertificateThumbprint $GraphCertThumbprint -NoWelcome
        Add-Audit "Connect Graph" "Success" "Certificate auth"
    } Catch {
        Add-Audit "Connect Graph" "Failed" $_.Exception.Message
    }


    write-output "Getting Entra account."
    $mgUser = Get-MgUser -Filter "mail eq '$Email'"
    if (-not $mgUser) { throw "Entra user not found" }

    write-output "Disabling Entra Account."
    Try {
        Update-MgUser -UserId $mgUser.Id -AccountEnabled:$false
        Add-Audit "Disable Entra Account" "Success" "Account disabled"
    } Catch {
        Add-Audit "Disable Entra Account" "Failed" $_.Exception.Message
    }

    write-output "Revoking all connected sessions."
    Try {
        Revoke-MgUserSignInSession -UserId $mgUser.Id
        Add-Audit "Revoke Sessions" "Success" "Sessions revoked"
    } Catch {
        Add-Audit "Revoke Sessions" "Failed" $_.Exception.Message
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
    - disables OWA
    - Turns off ActiveSync
    - Turns off MAPI
    - Turns off POP
    - Turns off IMAP

########################################################################################>

    Import-Module ExchangeOnlineManagement

    Try {
    Connect-ExchangeOnline -AppId $GraphClientId `
        -CertificateThumbprint $GraphCertThumbprint `
        -Organization $ExoOrganization `
        -ShowBanner:$false

        Add-Audit "Connect Exchange Online" "Success" "Connected"
    } Catch {
        Add-Audit "Connect Exchange Online" "Failed" $_.Exception.Message
    }
<#
    Try {
        Set-CASMailbox -Identity $Email `
            -OWAEnabled $false `
            -ActiveSyncEnabled $false `
            -MAPIEnabled $false `
            -PopEnabled $false `
            -ImapEnabled $false
    
        Add-Audit "Disable Exchange Access" "Success" "CAS protocols disabled"
    } Catch {
        Add-Audit "Disable Exchange Access" "Failed" $_.Exception.Message
    }
#>

<#
    #grant permissions for someone to monitor the email inbox
    Try {

        Add-MailboxPermission `
        -Identity $Email `
        -User delegate.user@domain.com `
        -AccessRights FullAccess `
        -InheritanceType All `
        -AutoMapping:$true

    
        Add-Audit "Add mailbox permissions" "Success" "User"

        # Set mailbox to shared
        # Set-Mailbox $Email -Type Shared

    } Catch {
        Add-Audit "Add mailbox permissions" "Failed" $_.Exception.Message
    }

#>

<#
    # Add OOO message for all incoming email.

    $Message = "Dave's not here, man."
    
    Try {

        Set-MailboxAutoReplyConfiguration `
        -Identity departed.user@domain.com `
        -AutoReplyState Enabled `
        -InternalMessage $message `
        -ExternalMessage $message

    
        Add-Audit "Add Out of Office message" "Success" "OOO set"
    } Catch {
        Add-Audit "Add Out of Office message" "Failed" $_.Exception.Message
    }

#>




    Disconnect-ExchangeOnline -Confirm:$false | Out-Null


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
