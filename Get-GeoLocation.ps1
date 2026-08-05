
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

#These are the variables for each run
$Global:VisionDB = "MPSv76"

#Get user info used in Vision API calls
$VaultName = "Paylocity-Key-Vault"
$VisionUser = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VisionUser" -AsPlainText
$VisionPW = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VisionPW" -AsPlainText

#Set up Vision calls
#Proxy and URI for Vision
$Global:URI = "https://mps.visionhosted.com/mps/visionws.asmx?WSDL"
$Global:proxy = new-webserviceproxy $uri -Namespace X


#This is the connection to the Vision database. 
    $Global:ConnectionXML = "<VisionConnInfo>`
    <databaseDescription>$VisionDB</databaseDescription>`
    <userName>$VisionUser</userName>`
    <userPassword>$VisionPW</userPassword>`
    </VisionConnInfo>"

Function Get-XML {

    #This function generates the xml necessary to make the API call. 

        $MainXML = "<WBS1>$($Project.WBS1)</WBS1>"
        $MainXML += "<WBS2>$($Project.WBS2)</WBS2>"
        $MainXML += "<WBS3>$($Project.WBS3)</WBS3>"
        $MainXML += "<SubLevel>$SubLevel</SubLevel>"
   
        $CustomXML = "<WBS1>$($Project.WBS1)</WBS1>"
        $CustomXML += "<WBS2>$($Project.WBS2)</WBS2>"
        $CustomXML += "<WBS3>$($Project.WBS3)</WBS3>"
        $CustomXML += "<CustLatitude>$NewLatitude</CustLatitude>"
        $CustomXML += "<CustLongitude>$NewLongitude</CustLongitude>"
        $CustomXML += "<CustLocationDescription>$NewLocationDescription</CustLocationDescription>"

      [string]$XML = "<?xml version=""1.0""?>`
                <RECS xmlns=""http://deltek.vision.com/XMLSchema"" `
                xmlns:xdv=""http://deltek.vision.com/XMLSchema"" `
                xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""> `
                <REC>`
                <PR name=""PR"" alias=""PR"" keys=""WBS1,WBS2,WBS3""> `
                <ROW tranType=""UPDATE"">`
                $MainXML
                </ROW>`
                </PR>`
                <ProjectCustomTabFields name=""ProjectCustomTabFields"" `
                 alias = ""ProjectCustomTabFields"" keys=""WBS1,WBS2,WBS3"">`
                <ROW tranType=""UPDATE"">`
                $CustomXML
                </ROW>`
                </ProjectCustomTabFields>`
                </REC>`
                </RECS>"

            Return $XML

}


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



# This query returns one project based on the input variable.
#
$query = "SELECT PR.WBS1, ProjectCustomTabFields.CustLatitude, ProjectCustomTabFields.CustLongitude FROM PR INNER JOIN ProjectCustomTabFields ON PR.WBS1 = ProjectCustomTabFields.WBS1 AND PR.WBS2 = ProjectCustomTabFields.WBS2 AND PR.WBS3 = ProjectCustomTabFields.WBS3
WHERE  (PR.WBS1 = '$ProjNumber') AND (PR.WBS2 = '')"
#>


[xml]$results = $proxy.getProjectsByQuery($ConnectionXML,$query,"")

$ActiveProjects = $results.recs.rec.pr.row



foreach ($Project in $ActiveProjects) {


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

$SubLevel = $Project.SubLevel  #The API call requires this field

$XML = Get-XML


#Escape any ampersands
$xml = $XML -replace "&", "&amp;"

$xml

[xml]$result = $proxy.UpdateProject($ConnectionXML, $XML)

$result.DLTKVisionMessage.ReturnDesc


$Project.wbs1

}




#  This section calls the equivalent webhook to update Vantagepoint. 

$Body = @{
ProjNumber = $ProjNumber
}
        #This is the webhook for GEO script in the IT Automations group for VantagePoint
        $URI = "https://a820bc96-f0d4-4a0e-a996-c8a1db4b8416.webhook.eus.azure-automation.net/webhooks?token=NBiBvq%2fsVbR%2bKp7nrLHNIAmTl6MltAYtRvJgRH4O3V4%3d"

        $headerMessage = @{message = "Manually sent from Powershell"}

        $data = $body | ConvertTo-JSON

        $Response = Invoke-WebRequest -method Post -uri $URI -header $headerMessage -body $data -UseBasicParsing

# End of Vantagepoint section





$callbackResponse = Invoke-WebRequest -Uri $callbackuri -UseBasicParsing -Method POST -ContentType "application/json" #-Body $OutputJson

Write-Output "Response was relayed to $callbackuri"
Write-Output ("ADF replied with the response: " + ($callbackResponse | ConvertTo-Json -Compress))