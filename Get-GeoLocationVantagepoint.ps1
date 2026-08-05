 
<#  This is the webhook URL as of 3-26-2026. Update here for documentation whenever it is refreshed.

https://a820bc96-f0d4-4a0e-a996-c8a1db4b8416.webhook.eus.azure-automation.net/webhooks?token=NBiBvq%2fsVbR%2bKp7nrLHNIAmTl6MltAYtRvJgRH4O3V4%3d

#>

param
(
    [Parameter(Mandatory=$false)]
    [object] $WebhookData,
    [Parameter(Mandatory=$false)]
    [string]$ProjNumber,
    [Parameter(Mandatory=$false)]
    [string]$callBackUri

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

    $ProjNumber = (Convertfrom-json -InputObject $WebhookData.RequestBody).ProjNumber
    $CallbackURI = (Convertfrom-json -InputObject $WebhookData.RequestBody).callbackURI
}
Catch {

    write-output "Webhook is not being used..."
}

Connect-AzAccount -identity

write-output "Importing VantagePoint module..."
Import-Module VantagePoint

#Set up for API calls to Vantagepoint
#Retrieve VantagePoint credentials
$VaultName = "Paylocity-Key-Vault"
$Global:username = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VisionUser" -AsPlainText
$Global:password = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VisionPW" -AsPlainText
$Global:ClientID = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VantagePointClientID" -AsPlainText
$Global:ClientSecret = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VantagePointClientSecret" -AsPlainText


#Set VantagePoint server and database for token retrieval
$BaseURL = "https://demov20261.dvphosted.com/mps/api"
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








function Get-LatAndLong
{
		<#
	.SYNOPSIS
		    Given input parameters for a location, will return Geolocation data from an API
	
	.DESCRIPTION
		 
	    This pulls long/lat from an API at https://geocode.maps.co/

        Forward Geocode: https://geocode.maps.co/search?q=address&api_key=api_key

        Reverse Geocode: https://geocode.maps.co/reverse?lat=latitude&lon=longitude&api_key=api_key

        Examples:

        https://geocode.maps.co/search?q=555+5th+Ave+New+York+NY+10017+US&api_key=api_key

        Or you can search by name, e.g. for the Statue of Liberty:

        https://geocode.maps.co/search?q=Statue+of+Liberty+NY+US&api_key=api_key

        However, you can also reverse geocode by providing the following parameters (all are optional, but no results will be returned if none are supplied):

        street=<housenumber> <streetname>
        city=<city>
        county=<county>
        state=<state>
        country=<country>
        postalcode=<postalcode>

	.PARAMETER 1
		Street - the street address. Secondary (ie suite or apt numbers) are not necessary
	
	.PARAMETER 2
		City
	
	.PARAMETER 3
		State - This may only be relevant when Country="US", so we will blank it if country is something else

    .PARAMETER 4
        Country - will default to US if not supplied

    .PARAMETER 5
        Zip
                    		
	
	.EXAMPLE
        Get-LatAndLong -zip 29642
				
	
	.NOTES
		Additional information about the function.
#>
	
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $false)]
		[string]$Street,
		[Parameter(Mandatory = $false)]
		[string]$city,
		[Parameter(Mandatory = $false)]
		[string]$state,
		[Parameter(Mandatory = $false)]
		[string]$country="US",
        [Parameter(Mandatory = $false)]
        [string]$Zip

	)
	
$APIKey = "679a32f16928f637158487rqe1aff16"

$url = "https://geocode.maps.co/search?<search>api_key=$APIkey"

$strSearch = ""

#If the country isn't blank and isn't 'US', the state needs to be cleared. This may end up being a kludge for foreign projects, so may need
#refinement later

if ($country -and $Country -ne 'US') {
    $State = ""
}

if ($Street) {
    $strSearch = "street=" + $Street.replace(" ", "+") + "&"
}

if ($Zip) {
    $strSearch += "postalcode=" + $Zip.replace(" ", "+") + "&"
}

ELSE {
        # Only use the city and state if there is no zip code
    if ($City) {
        $strSearch += "city=" + $City.replace(" ", "+") + "&"
    }

    if ($State) {
        $strSearch += "state=" + $State.replace(" ", "+") + "&"
    }
}

if ($Country) {
    $strSearch += "country=" + $Country.replace(" ", "+") + "&"
} 
Else {
    $strSearch += "country=US&" 
}

$url = $url.replace("<search>",$strSearch)

    return Invoke-RestMethod -Uri $url -Method Get #-Headers $headers
}



# Retrieve project info from Vantagepoint
#


$URL = "$BaseURL/project/$projNumber"  #used to get top level (WBS2 = '')



	$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("content-type", "application/x-www-form-urlencoded")
    $headers.Add("Authorization", "Bearer $VPAccessToken")

    $Project = Invoke-RestMethod $URL -Method get -headers $headers 



#Call Geocode API.

$params = @{
    Street = $Project.Address1
    City =$Project.City
    State = $Project.State
    Zip = $Project.Zip
    Country= $Project.Country   #Will default to US if not entered
}

$Params

$i = 0

#Try to get the location 5 times before moving on
Do {

    Try {
        $Location = Get-LatAndLong @params
        $i = 5
    }
    Catch {
        #Wait one second before trying again
        Start-Sleep -Seconds 1
        $i++
    }


} Until ($i -eq 5)




#If the street address isn't right, location might not be returned. If so, remove it and try again.
if (!$Location) {

    $Params.street = ""

    $i = 0
    #Try to get the location 5 times before moving on
    Do {
        Try {
            $Location = Get-LatAndLong @params
            $i = 5
        }
        Catch {
            #Wait one second before trying again
            Start-Sleep -Seconds 1
            $i++
        }
    } Until ($i -eq 5)


}



    [double]$NewLatitude = $location[0].lat

    [double]$NewLongitude = $location[0].lon

$NewLocationDescription = $location[0].display_name

#If the location description is blank or simply says "United States", then we need to change it.

If ($NewLocationDescription -eq $null -or $NewLocationDescription -eq "United States") {

    $NewLatitude = 0
    $NewLongitude = 0
    $NewLocationDescription = "Unable to discover"
}


#Write results back to Vantagepoint

$body = @{

CustLatitude=$NewLatitude
CustLongitude=$NewLongitude
CustLocationDescription=$NewLocationDescription


}

    $URL = "$BaseURL/project/$($ProjNumber)?requiredFieldValidation=N&startWorkflow=N"  #the two parameters prevent field validation and workflows, respectively


	$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("content-type", "application/x-www-form-urlencoded")
    $headers.Add("Authorization", "Bearer $VPAccesstoken")


    #This will update a project
    $response = Invoke-RestMethod $URL -Method put -headers $headers -body $body

$response.wbs1
$response.CustLatitude
$response.CustLongitude



$callbackResponse = Invoke-WebRequest -Uri $callbackuri -UseBasicParsing -Method POST -ContentType "application/json" #-Body $OutputJson

Write-Output "Response was relayed to $callbackuri"
Write-Output ("ADF replied with the response: " + ($callbackResponse | ConvertTo-Json -Compress))