 
param
(
    [Parameter(Mandatory=$false)]
    [object] $WebhookData,
    [Parameter(Mandatory=$false)]
    [PSCustomObject]$InputObject
)
 
 
Try {

    write-output "start"
    write-output ("object type: {0}" -f $WebhookData.gettype())
    #write-output "WebhookData: $WebhookData"
    #echo $WebhookData
    write-output "`n`n"
    write-output "WebhookData: $($WebhookData.WebhookName)"
    write-output "RequestBody: $($WebhookData.RequestBody)"
    write-output "RequestHeader: $($WebhookData.RequestHeader)"
    write-output "end"

    #$PaylocityID = (Convertfrom-json -InputObject $WebhookData.RequestBody).employeeid
    $CallbackURI = (Convertfrom-json -InputObject $WebhookData.RequestBody).callbackURI

}
Catch {

    write-output "Webhook is not being used..."
}


$Input = Convertfrom-json -InputObject $WebhookData.RequestBody

write-output "Input: $Input"

$Street = $Input.street
$City = $Input.city
$state = $Input.state
$zip = $Input.zip
$country = $Input.country


write-output "City: $city"
write-output "State: $state"
write-output "Zip: $zip"


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

write-output $url

$Result = Invoke-RestMethod -Uri $url -Method Get #-Headers $headers


write-output $Result


$OutputJson = $result[0] | ConvertTo-JSON

$callbackResponse = Invoke-WebRequest -Uri $callbackuri -UseBasicParsing -Method POST -ContentType "application/json" -Body $OutputJson