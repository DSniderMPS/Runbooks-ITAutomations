<#
    This function takes information from a custom hub in Vantagepoint and creates a project. It was created as a proof of concept,
    but will probably never be used in production. It remains for reference only.
#>
 
<#   Webhook URL as of 4-23-26.     Remember to refresh every time webhook changes.

https://a820bc96-f0d4-4a0e-a996-c8a1db4b8416.webhook.eus.azure-automation.net/webhooks?token=7OpzLE5o4WIg0rm9M0D0DuL7uUF%2fIJLzz5TXsaGzAnA%3d


#>

param
(
    [Parameter(Mandatory=$false)]
    [object] $WebhookData,
    [Parameter(Mandatory=$false)]
    [string]$UID,   #this is the internal ID from VantagePoint of the Project Creation object
    [Parameter(Mandatory=$false)]
    [int]$Test
) 

Try {
 
    write-output "start"
    write-output ("object type: {0}" -f $WebhookData.gettype())
    write-output $WebhookData
    echo $WebhookData
    write-output "`n`n"
    write-output $WebhookData.WebhookName
    write-output $WebhookData.RequestBody
    write-output $WebhookData.RequestHeader
    write-output "end"

    $UID = (Convertfrom-json -InputObject $WebhookData.RequestBody).uid

}
Catch {

    write-output "Webhook is not being used..."
}



#************************************************************
#
#  1  -  Setup
#
#************************************************************

Connect-AzAccount -identity

Add-Type -AssemblyName System.Web   #This allows for decoding some HTML string that exist in memo fields

write-output "Parameter passed: $UID"

write-output "Importing VantagePoint module..."
Import-Module VantagePoint

#Retrieve VantagePoint credentials
$VaultName = "Paylocity-Key-Vault"
$Global:username = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VisionUser" -AsPlainText
$Global:password = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VisionPW" -AsPlainText
$Global:ClientID = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VantagePointClientID" -AsPlainText
$Global:ClientSecret = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VantagePointClientSecret" -AsPlainText

#Set VantagePoint server and database for token retrieval
$BaseURL = "https://mps.dvphosted.com/mps/api"
$database = "MPSVP_Preview"

#Get VantagePoint token
$Params = @{
username = $Username
password = $Password
ClientID = $ClientID
ClientSecret = $ClientSecret
database = $database
BaseURL = $BaseURL
}

write-output $Params

#Retrieve token for subsequent VantagePoint API calls
Write-output "Getting VantagePoint token..."
$VPAccessToken = Get-VantagePointToken @Params
write-output "VantagePoint token: $VPAccessToken"


	$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("content-type", "application/x-www-form-urlencoded")
    $headers.Add("Authorization", "Bearer $VPAccessToken")




#   END OF SETUP

#************************************************************
#
#  2  -  Read the Custom Hub record
#
#************************************************************



$queryParams = @{

        "filterHash[0][name]"     = "UDIC_UID"
        "filterHash[0][value]"    = $UID   
    }

    # Build query string safely
    $queryString = ($queryParams.GetEnumerator() | ForEach-Object {
        "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.Value))"
    }) -join "&"

    $CustomHub = "ProjectCreation"

    $URL = "$BaseURL/UDIC/UDIC_$CustomHub" + "?$queryString"

    $NewProject = Invoke-RestMethod $URL -Method get -headers $headers 


write-output $NewProject 


#************************************************************
#
#  3  -  Create the body of the VantagePoint request
#
#************************************************************

$Body = @{

CustAdditionRenovationUpfit = $NewProject.CustAdditionRenovationUpfit
CustAdvisoryServicesAdvancePlanning = $NewProject.CustAdvisoryServicesAdvancePlanning
CustAffordableHousingSection8etc = $NewProject.CustAffordableHousingSection8etc
CustCertificateofNeedCON = $NewProject.CustCertificateofNeedCON
CustDealOwner = $NewProject.CustDealOwner
CustFacilityStudy = $NewProject.CustFacilityStudy
CustFeasibilityStudyProgramming = $NewProject.CustFeasibilityStudyProgramming
CustFundingMechanismAbandonedBuildingTaxCredits = $NewProject.CustFundingMechanismAbandonedBuildingTaxCredits
CustFundingMechanismHistoricTaxCredits = $NewProject.CustFundingMechanismHistoricTaxCredits
CustFundingMechanismHUD = $NewProject.CustFundingMechanismHUD
CustFundingMechanismNewMarketTaxCredits = $NewProject.CustFundingMechanismNewMarketTaxCredits
CustFundingMechanismOpportunityZone = $NewProject.CustFundingMechanismOpportunityZone
CustFundingMechanismOther = $NewProject.CustFundingMechanismOther
CustFundingMechanismUSDA = $NewProject.CustFundingMechanismUSDA
CustHistoricPreservationAdaptiveReuse = $NewProject.CustHistoricPreservationAdaptiveReuse
CustHistoricPreservationRestoration = $NewProject.CustHistoricPreservationRestoration
CustIndefiniteDeliveryIDCIDIQ = $NewProject.CustIndefiniteDeliveryIDCIDIQ
CustInternalProjectOverhead = $NewProject.CustInternalProjectOverhead
CustLostReason = [System.Net.WebUtility]::HtmlDecode($NewProject.CustLostReason)
CustMasterPlanSitePlan = $NewProject.CustMasterPlanSitePlan
CustMixedUseHospitality = $NewProject.CustMixedUseHospitality
CustMixedUseMultiFamily = $NewProject.CustMixedUseMultiFamily
CustMixedUseOffice = $NewProject.CustMixedUseOffice
CustMixedUseOther = $NewProject.CustMixedUseOther
CustMixedUseParking = $NewProject.CustMixedUseParking
CustMixedUseRetail = $NewProject.CustMixedUseRetail
CustNewConstruction = $NewProject.CustNewConstruction
CustPracticeArea = $NewProject.CustPracticeArea
CustProBono = $NewProject.CustProBono
custProjectDescription = [System.Net.WebUtility]::HtmlDecode($NewProject.CustProjectDescription)
CustProjectType = $NewProject.CustProjectType
CustPrototypeNew = $NewProject.CustPrototypeNew
CustPrototypeSiteAdapt = $NewProject.CustPrototypeSiteAdapt
CustSustainableDesignEnergyStar = $NewProject.CustSustainableDesignEnergyStar
CustSustainableDesignGreenGlobesFour = $NewProject.CustSustainableDesignGreenGlobesFour
CustSustainableDesignGreenGlobesOne = $NewProject.CustSustainableDesignGreenGlobesOne
CustSustainableDesignGreenGlobesThree = $NewProject.CustSustainableDesignGreenGlobesThree
CustSustainableDesignGreenGlobesTwo = $NewProject.CustSustainableDesignGreenGlobesTwo
CustSustainableDesignLEEDCertified = $NewProject.CustSustainableDesignLEEDCertified
CustSustainableDesignLEEDGold = $NewProject.CustSustainableDesignLEEDGold
CustSustainableDesignLEEDPlatinum = $NewProject.CustSustainableDesignLEEDPlatinum
CustSustainableDesignLEEDSilver = $NewProject.CustSustainableDesignLEEDSilver
CustSustainableDesignMassTimber = $NewProject.CustSustainableDesignMassTimber
CustSustainableDesignPeachProgram = $NewProject.CustSustainableDesignPeachProgram
CustTechnicalCommunityCollege = $NewProject.CustTechnicalCommunityCollege
CustTestFit = $NewProject.CustTestFit
CustWELLCertification = $NewProject.CustWELLCertification
CustWELLHealthSafetyRating = $NewProject.CustWELLHealthSafetyRating
Address1 = $NewProject.CustAddress1
Address2 = $NewProject.CustAddress2
custMPSEmployee = $NewProject.CustBusinessDevelopmentOwner
City = $NewProject.CustCity
CustLostReasonDetail = $NewProject.CustClosedLostReason
CustWonReason = [System.Net.WebUtility]::HtmlDecode($NewProject.CustClosedWonReason)
CustConfidentialNonDisclosureAgreement = $NewProject.CustConfidentialNDA
CustHubspotDealType = $NewProject.CustDealType
custEstConstructionCost = $NewProject.CustEstimatedConstructionCost
custEstServicesFees = $NewProject.CustEstimatedGrossFeeAmount
CustEstNetFee = $NewProject.CustEstimatedNetFee
CustEstimatedCompletionDate = $NewProject.CustEstimatedProjectEndDate
custOfficeLocation = $NewProject.desc_CustManagingStudio
LongName = $NewProject.CustName
Name = $NewProject.CustName
Principal = $NewProject.CustPracticeAreaLeader
CustPrincipal = $NewProject.CustPrincipalinCharge
ProjMgr = $NewProject.CustProjectManager
State = $NewProject.CustProjectState
CustSustainableDesignEnergyTaxDeductionStudyAcctgOnly = $NewProject.CustSustainableDesignEnergyTaxDeductionStudyAccountingonly
CustSustainableDesignNon3rdPartycertified = $NewProject.CustSustainableDesignNon3rdPartycertified
Zip = $NewProject.CustZipCode

Stage = $NewProject.CustStage

}



#************************************************************#>
#
#  3a  -  Get next project number for current year
#
#************************************************************

        #Get last two digits of current year
        $now = (Get-Date).ToString('yy')

        $queryParams = @{
            "filterHash[0][name]"     = "WBS2"
            "filterHash[0][value]"    = ""

            "filterHash[1][name]"     = "WBS1"
            "filterHash[1][opp]" = "STARTSWITH"
            "filterHash[1][value]"    = "p$now"

            "filterHash[1][condition]"    = "OR"
            
            "filterHash[2][name]"     = "WBS1"
            "filterHash[2][opp]" = "STARTSWITH"
            "filterHash[2][value]"    = "0$now"
        }

        # Build query string safely
        $queryString = ($queryParams.GetEnumerator() | ForEach-Object {
            "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.Value))"
        }) -join "&"

        $url = "$baseUrl/project?fieldfilter=wbs1,wbs2,org&$queryString"

        $Projects = Invoke-RestMethod $URL -Method get -headers $headers

        #Find the highest value from the second character to the first period
        $Sequence = $Projects | ForEach-Object { $_.wbs1.split(".")[0].substring(1) }

        $max = $($Sequence | ForEach-Object { [int]$_ } | Measure-Object -Maximum).maximum

        $NextProjectNumber = '{0:00000000.00}' -f ($max + 1)

        if ($NextProjectNumber -eq '00000001.00') {
                $NextProjectNumber = "0" + $now + "00001.00"    #NOTE: THIS ISN'T CORRECT. NEEDS FIXING.
            }

#Add next Project Number to the body of the request
    $Body += @{WBS1 = $NextProjectNumber}



#************************************************************#>
#>
#  3b  -  Add various required fields
#
#************************************************************

    $Body += @{WBS2 = ' '}
    $Body += @{WBS3 = ' '}
    $Body += @{Sublevel = "Y"}
    



#************************************************************#>
#
#  3c  -  Assemble the ORG code and add to body
#
#************************************************************


    $Firm = $NewProject.CustFirm 
    $OfficeCode = $NewProject.CustManagingStudio
    $PracticeAreaCode = $NewProject.CustPracticeArea

    $ORG = $Firm + ":" + $OfficeCode + ":" + $PracticeAreaCode

    write-output "ORG: $Org"
    
#
    if ($firm.length -gt 0 -and $OfficeCode.length -gt 0 -and $PracticeAreaCode.length -gt 0 ) {

        $Body += @{ORG = $Org}
   }
#>
    


#************************************************************#>
#
#  4  -  Send request to VP 
#
#************************************************************

write-output "Body of API request"
$Body | ConvertTo-Json

$OriginalBody = $Body  # Save for future calls to API

$URL = "$BaseURL/project?requiredFieldValidation=Y&startWorkflow=N"

TRY {
    $response = Invoke-RestMethod $URL -Method Post -headers $headers -body $body
    write-output "RESPONSE:"
    $response 
}

CATCH {
            $ERR = $_    #Capture the whole message for later

            write-output "Errors: $ERR"
            write-output $($ERR.ErrorDetails.message | ConvertFrom-JSON).errors

            $exception = $_.Exception

            # Default values
            $statusCode   = $null
            $responseBody = $null

                if ($exception.Response) {
                    # HTTP status code
                    $statusCode = $exception.Response.StatusCode.value__

                    # Read response body safely
                    try {
                        $stream = $exception.Response.GetResponseStream()
                        $reader = [System.IO.StreamReader]::new($stream)
                        $responseBody = $reader.ReadToEnd()
                    }
                    catch {
                        $responseBody = "<Unable to read response body>"

                    }
                
                }
                    
            if (!responsebody) {

                $Responsebody = $($ERR.ErrorDetails.message | ConvertFrom-JSON).errors
            }

            Write-Output "REST API call failed."
            Write-Output "Status Code: $statusCode"
            Write-Output "Response Body: $responseBody"

}


 #If a response is returned, update the custom hub record
 if ($response.wbs1) {


     $URL = "$BaseURL/UDIC/UDIC_ProjectCreation/$($UID)?requiredFieldValidation=N&startWorkflow=N"

     $URL
    
     $Body = @{CustProjectID = $response.WBS1
                CustStatusofRequest = "Completed"
            }

            $Body | ConvertTo-Json


    TRY {
            $result = Invoke-RestMethod $URL -Method put -headers $headers -body $Body

            write-output "Result of custom record update:"

            $Result 
        }
    
    CATCH {

            $exception = $_.Exception

            # Default values
            $statusCode   = $null
            $responseBody = $null

                if ($exception.Response) {
                    # HTTP status code
                    $statusCode = $exception.Response.StatusCode.value__

                    # Read response body safely
                    try {
                        $stream = $exception.Response.GetResponseStream()
                        $reader = [System.IO.StreamReader]::new($stream)
                        $responseBody = $reader.ReadToEnd()
                    }
                    catch {
                        $responseBody = "<Unable to read response body>"

                    }
                
                }
                    

            Write-Error "REST API call failed."
            Write-Error "Status Code: $statusCode"
            Write-Error "Response Body: $responseBody"

        }

 }

 ELSE {

        #Exit if failure
        EXIT

 }

 #************************************************************#>
#
#  5  -  Add a promotional project if needed
#
#************************************************************

if ($response.ReadyForProcessing -eq 'N') {

        $Body = $OriginalBody    #Recall the first API body
        
        write-output "Adding promotional project"

        $Body.WBS1 = "P" + $Body.WBS1.substring(1)

        #$Body.stage = ''
        $Body += @{ChargeType = "P"}
        $Body += @{ReadyForProcessing = "Y"}
        $Body += @{RevType = "N"}
        $Body += @{SiblingWBS1 = $response.wbs1}
        $Body += @{Sublevel = "N"}

        write-output "Body of API request for Promotional"
        $Body | ConvertTo-Json

        $URL = "$BaseURL/project?requiredFieldValidation=Y&startWorkflow=N"

        $response = Invoke-RestMethod $URL -Method Post -headers $headers -body $body

        $response

    }
    ELSE {

        write-output "No Promotional Project needed."
    }



#************************************************************#>
#
#  6  -  Add the phase levels
#
#************************************************************

$Body = $OriginalBody    #Recall the first API body

write-output "Body of phase requests"
$Body | ConvertTo-Json

$URL = "$BaseURL/project?requiredFieldValidation=N&startWorkflow=N"

$Phases = @{
"000" = "Base Services"
"A00" = "Pre-Design"
"A01" = "Schematic Design"
"A02" = "Design Development"
"A03" = "Construction Documents"
"A04" = "Bid & Negotiate"
"A05" = "Construction Administration"
"A06" = "Post Construction"
"F00" = "Additional Services"
"Z99" = "Expenses"

}

write-output "Creating phases for $($body.wbs1)"

foreach ($entry in $Phases.GetEnumerator()) {

    $Phase   = $entry.Key
    $name = $entry.Value

    write-output "Adding phase: $phase - $name"

    #Update body with new phase and name
    $Body.WBS1 = $NextProjectNumber
    $Body.WBS2 = $Phase
    $Body.name = $name
    $Body.longname = $name
    $Body.ReadyForProcessing = "Y"
    $Body.sublevel = "N"

    $body | ConvertTo-Json
    
    $response = Invoke-RestMethod $URL -Method Post -headers $headers -body $body

}


#************************************************************#>
#
#  5  -  Add ACC Project if indicated
#
#************************************************************

if ($NewProject.CustCreateACCProject -eq "Y") {

        write-output "Adding ACC Project."
        # This is the URI for the webhook in ACC Automations named "Add-ACCProjectFromVantagePoint". If it changes, remember to update it here.
        $URI = "https://52b6f95d-b1cb-4809-86b7-bf72c954e2e8.webhook.eus.azure-automation.net/webhooks?token=14DoIfuCCnybHWuQu8eyWYTePuTL9Sa85YipRNIcaok%3d"

        $headerMessage = @{message = "Manually sent from Powershell"}

        $data=   @{  WBS1 = $NextProjectNumber  }  | ConvertTo-JSON

        $Response = Invoke-WebRequest -method Post -uri $URI -header $headerMessage -body $data -UseBasicParsing

}
Else {

        write-output "ACC project not requested."
}



#************************************************************#>
#
#  6  -  Send email notifications and exit
#
#************************************************************


$callbackResponse = Invoke-WebRequest -Uri $callbackuri -UseBasicParsing -Method POST -ContentType "application/json" #-Body $OutputJson

Write-Output "Response was relayed to $callbackuri"
Write-Output ("ADF replied with the response: " + ($callbackResponse | ConvertTo-Json -Compress))