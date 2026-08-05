

param (
    [int]$DaysBack = 40
)




<#####################################################################################################

    Setup

#####################################################################################################>

    Import-Module Az.Accounts

    $TenantId   = "2f2f3064-9dcf-49ea-a3ca-341498ba0cea"
    $AppId      = "413af4fa-ba8b-4671-b724-28316367dc3e"
    $Thumbprint = "F7132556ADC49014DCE8ECD838B27E7C43C4ED74"

    $Cert = Get-Item "Cert:\LocalMachine\My\$Thumbprint"

    $cert

#Notification URL - IT alerts channel.    
$WebhookURL = "https://default2f2f30649dcf49eaa3ca341498ba0c.ea.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/194aa69bcc994a0cafb4ec1e47cff9de/triggers/manual/paths/invoke?api-version=1&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=7aJPxwEU_-k7B8a9G9WaJjhMyetIK2EF2R1hSFdZcYM"


#Set up email notifications. It will use a logic app named "Email_with_data_attachment"
$LogicAppURL = "https://prod-57.eastus.logic.azure.com:443/workflows/6b556e09885f49fcbb5ab904a0265a8d/triggers/When_an_HTTP_request_is_received/paths/invoke?api-version=2016-10-01&sp=%2Ftriggers%2FWhen_an_HTTP_request_is_received%2Frun&sv=1.0&sig=eA-bW3ox4bYk-ybuZz57GtIfmr5bdwNlDSHMaOBSRc4"
$ITEmail = 'dsnider@mcmillanpazdansmith.com,rjaquez@mcmillanpazdansmith.com'



Connect-AzAccount `
    -ServicePrincipal `
    -TenantID $TenantId `
    -ApplicationId $AppId `
    -CertificateThumbprint $Thumbprint `
    -ErrorAction Stop

    $database = "MPSVP_Preview"

   
    # Retrieve VP credentials to get a token
    $VaultName = "Paylocity-Key-Vault"
    $Global:username = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VisionUser" -AsPlainText
    $Global:password = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VisionPW" -AsPlainText
    $Global:ClientID = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VantagePointClientID" -AsPlainText
    $Global:ClientSecret = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VantagePointClientSecret" -AsPlainText
    $Global:BaseURL = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VantagePointAPIURL" -AsPlainText

    $body = @{

    username = $Username
    password = $Password
    Client_ID = $ClientID
    Client_Secret = $ClientSecret
    database = $database
    Integrated = 'N'
    grant_type = 'password'

    }

    $URL = "$BaseURL/token"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("content-type", "application/x-www-form-urlencoded")

    $AccessToken = (Invoke-RestMethod $URL -Method post -Body $body -headers $headers).access_token

	$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("content-type", "application/x-www-form-urlencoded")
    $headers.Add("Authorization", "Bearer $Accesstoken")

# ----------------------------
# Audit object
# ----------------------------
$Audit = [ordered]@{
    StartTime = Get-Date
    Actions   = @()
}

<#####################################################################################################

    Helper functions

#####################################################################################################>

function Add-Audit {
    param($User, $Change, $NewValue, $Result)
    $Audit.Actions += [ordered]@{
        User   = $User
        Change = $Change
        NewValue = $NewValue
        Result = $Result
        Time   = Get-Date
    }
}

function Convert-ToAdaptiveCard {
    param (
        [Parameter(Mandatory)]
        $InputObject
    )

    # Handle JSON string or object input
    if ($InputObject -is [string]) {
        $data = $InputObject | ConvertFrom-Json
    }
    else {
        $data = $InputObject
    }

    $startTime = $data.StartTime.DateTime
    $userColWidth = "160px"   # fixed width for ~10-char usernames

    # Header row
    $headerRow = @{
        type      = "ColumnSet"
        separator = $true
        spacing   = "Medium"
        columns   = @(
            @{
                type  = "Column"
                width = $userColWidth
                items = @(
                    @{
                        type   = "TextBlock"
                        text   = "User"
                        weight = "Bolder"
                        wrap   = $false
                        maxLines = 1
                    }
                )
            },
            @{
                type  = "Column"
                width = $userColWidth
                items = @(
                    @{
                        type   = "TextBlock"
                        text   = "Change"
                        weight = "Bolder"
                        wrap   = $true
                    }
                )
            },
            @{
                type  = "Column"
                width = $userColWidth
                items = @(
                    @{
                        type   = "TextBlock"
                        text   = "New Value"
                        weight = "Bolder"
                        wrap   = $true
                    }
                )
            },
            @{
                type  = "Column"
                width = $userColWidth
                items = @(
                    @{
                        type   = "TextBlock"
                        text   = "Result"
                        weight = "Bolder"
                        wrap   = $true
                    }
                )
            }
        )
    }

    # Data rows
    $rows = foreach ($action in $data.Actions) {
        $isEmailNotFound = $action.Change -match '(?i)email not found'

        $changeColor  = if ($isEmailNotFound) { "Attention" } else { "Default" }
        $changeWeight = if ($isEmailNotFound) { "Bolder" } else { "Default" }


        $auditColor = switch ($action.Result) {
            'Success' { 'Good' }
            'Failure' { 'Attention' }
            default   { 'Default' }
        }


        @{
            type      = "ColumnSet"
            separator = $true
            spacing   = "Small"
            columns   = @(
                @{
                    type  = "Column"
                    width = $userColWidth
                    items = @(
                        @{
                            type     = "TextBlock"
                            text     = "$($action.User)"
                            wrap     = $false
                            maxLines = 1
                        }
                    )
                },
                @{
                    type  = "Column"
                    width = $userColWidth
                    items = @(
                        @{
                            type   = "TextBlock"
                            text   = "$($action.Change)"
                            wrap   = $true
                            color  = $changeColor
                            weight = $changeWeight
                        }
                    )
                },
                @{
                    type  = "Column"
                    width = $userColWidth
                    items = @(
                        @{
                            type = "TextBlock"
                            text = "$($action.NewValue)"
                            wrap = $true
                        }
                    )
                },
                @{
                    type  = "Column"
                    width = $userColWidth
                    items = @(
                        @{
                            type = "TextBlock"
                            text = "$($action.Result)"
                            color = $auditColor
                            wrap = $true
                        }
                    )
                }
            )
        }
    }

    $card = @{
        '$schema' = "http://adaptivecards.io/schemas/adaptive-card.json"
        type      = "AdaptiveCard"
        version   = "1.4"
        msteams = @{
            width = "Full"
        }
        body      = @(
            @{
                type   = "TextBlock"
                text   = "User Update Summary"
                weight = "Bolder"
                size   = "Medium"
            },
            @{
                type     = "TextBlock"
                text     = "Started: $startTime"
                isSubtle = $true
                spacing  = "None"
            },
            $headerRow
        ) + $rows
    }

    return $card | ConvertTo-Json -Depth 25
}


<#####################################################################################################

    Retrieve all users from VP changed during last X days

#####################################################################################################>

# Calculate date filter (UTC, ISO 8601)
$SinceDate = (Get-Date).AddDays(-$DaysBack).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Build OData query
$QueryParams = @{
    "filterHash[0][name]"     = "status"
    "filterHash[0][value]"    = "a"

    "filterHash[1][name]"     = "moddate"
    "filterHash[1][opp]" = ">="
    "filterHash[1][value]"    = "$SinceDate"
}

# Build query string safely
$queryString = ($queryParams.GetEnumerator() | ForEach-Object {
    "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.Value))"
}) -join "&"

$Uri = "$baseUrl/employee?fieldfilter=employee,status,moddate&$queryString"

# Call Vantagepoint
$response = Invoke-RestMethod `
    -Uri $Uri `
    -Method Get `
    -Headers $Headers   # <-- include auth headers/session cookie

# Return only Employee values
$response.value | Select-Object -ExpandProperty Employee

$Users = $Response.Employee

# initialize Audit object 


#  Loop through all users
ForEach ($user in $Users) {

    write-output "****************************************************************************************"
<#####################################################################################################

    Read Deltek user info

#####################################################################################################>

    $URL = "$BaseURL/employee/$user"

    $response = ""
    $response = Invoke-RestMethod $URL -Method get -headers $headers -ErrorAction Stop

    #Retrieve supervisor email
    $URL = "$BaseURL/employee/$($response.supervisor)"

    $Supervisor = ""
    $Supervisor = Invoke-RestMethod $URL -Method get -headers $headers

    $user
    $response.email
    $response.supervisor
    $Supervisor.email
    $response.title
    $response.custOfficeLocation
    $response.moddate
    $response.org


<#####################################################################################################

    Update A/D

#####################################################################################################>

    # Find A/D user record
    $Email = $response.email
    $filter = "UserPrincipalName -eq '$Email'"

    $adUser = $null

    if ($Email) {
        $adUser = Get-ADUser -Filter $filter -Properties SamAccountName,givenname,sn,DistinguishedName, title,manager,physicalDeliveryOfficeName,description,displayName,EmployeeID,department
    }

    if ($adUser)  {

        $adUser
        
    } Else {

        write-output "Email not found in Active Directory: $Email"
        Add-Audit $User "Email Not Found" $Email "Failure"
        Continue # this ends processing for this user and skips to the next user 
    }
    

    # Update Supervisor
    $Email = $Supervisor.email
    $filter  = "UserPrincipalName -eq '$Email'" 
    $Manager = Get-ADUser -Filter $filter -Properties SamAccountName,givenname,sn,DistinguishedName

    if ($Manager ) {
            $Manager

            if ($aduser.manager -ne $Manager.DistinguishedName) {
                write-output  "Manager has changed."

                Try {
                #Update Manager
                Set-ADUser -identity $($adUser.SamAccountName) -manager $Manager.DistinguishedName

                #Add Audit record upon success
                Add-Audit $adUser.displayName "Manager" $($Manager.Name) "Success"
                }
                Catch {
                    # Add audit record upon failure
                    Add-Audit $adUser.displayName "Manager" $($Manager.Name) "Failure"

                }
        }


    } Else {
            write-output "Supervisor email not found in Active Directory: $Email"
            Add-Audit $adUser.displayName "Manager email not found in A/D" $Email "Failure"
    }
     




    # Update job title
    if ($adUser.jobtitle -ne $response.title) {

        write-output "Job title has changed."

        Try {
            # Update Job title
            Set-ADUser -Identity $($adUser.SamAccountName) -Title $response.title

            # Add Audit record upon success
            Add-Audit $adUser.displayName "Job Title" $($response.title) "Success"
        }
        Catch {
            Add-Audit $adUser.displayName "Job Title" $($response.title) "Failure"

        }
    }

    # Update location
    if ($adUser.physicalDeliveryOfficeName -ne $response.custOfficeLocation) {

        write-output "Office Location has changed: $($response.custOfficeLocation)"

        # update location 
        Try {
            Set-ADUser -Identity $($adUser.SamAccountName) -Office $($response.custOfficeLocation) -ErrorAction stop
            
            # Add audit record upon success
            Add-Audit $adUser.displayName "Office Location" $($response.custOfficeLocation) "Success"
        }
        Catch {
            # Add audit record upon failure
            Add-Audit $adUser.displayName "Office Location" $($response.custOfficeLocation) "Failure"
        }
    }

    #Update EmployeeID
    if ($aduser.employeeID -ne $User) {

        write-output "Employee ID is updated: $User"

        # update EmployeeID 
        Try {
            Set-ADUser -Identity $($adUser.SamAccountName) -EmployeeID $User -ErrorAction stop
            
            # Add audit record upon success
            Add-Audit $adUser.displayName "EmployeeID" $User "Success"
        }
        Catch {
            # Add audit record upon failure
            Add-Audit $adUser.displayName "EmployeeID" $User "Failure"
        }

    }

    #Update Department with Practice Area

    #find the current practice area

    $URL = "$BaseURL/organization/$($response.org)"

    $response = Invoke-RestMethod $URL -Method get -headers $headers 

    $PracticeArea = $response.name.Substring($response.name.IndexOf(':') + 1)


    if ($aduser.department -ne $PracticeArea) {

        write-output "Department is updated: $PracticeArea"

        # update EmployeeID 
        Try {
            Set-ADUser -Identity $($adUser.SamAccountName) -department $PracticeArea -ErrorAction stop
            
            # Add audit record upon success
            Add-Audit $adUser.displayName "Department" $PracticeArea "Success"
        }
        Catch {
            # Add audit record upon failure
            Add-Audit $adUser.displayName "Department" $PracticeArea "Failure"
        }

    }

<#####################################################################################################

    End of all users loop

#####################################################################################################>
}


<#####################################################################################################

    Send Teams channel notification

#####################################################################################################>

#Create adaptiveCard from audit 
$adaptiveCardJson = Convert-ToAdaptiveCard -InputObject ($Audit | ConvertTo-Json -Depth 6)


$response = Invoke-RestMethod `
  -Method Post `
  -Uri $WebhookUrl `
  -ContentType 'application/json' `
  -Body $adaptiveCardJson -verbose

$response


<#####################################################################################################

    Send email notification

#####################################################################################################>

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
    subject = "Sync-Vision-To-AD Results"
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


