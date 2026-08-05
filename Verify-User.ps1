
$email = 'ajohnson@mcmillanpazdansmith.com'   # This will change to an input parameter eventually


<#######################################################################################

    Setup

########################################################################################>

$VerifyExchange = $false

$ExoAppId            = '413af4fa-ba8b-4671-b724-28316367dc3e'
$ExoCertThumbprint   = 'F7132556ADC49014DCE8ECD838B27E7C43C4ED74'
$ExoOrganization     = 'mcmillanpazdansmith.com'


$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$Report = [ordered]@{
    UserEmail = $Email
    RunTime   = Get-Date
    Checks    = @()
}


<#######################################################################################

    Helper functions

########################################################################################>

function Add-Check($Area,$Check,$Expected,$Actual,$Status) {
    $Report.Checks += [ordered]@{
        Area=$Area;Check=$Check;Expected=$Expected;Actual=$Actual;Status=$Status;Time=(Get-Date)
    }
}

<#######################################################################################

    Active Directory

########################################################################################>
Import-Module ActiveDirectory
$ad = Get-ADUser -Filter "Mail -eq '$Email'" -Properties Enabled,PasswordLastSet
Add-Check "AD" "Account Disabled" "False" $ad.Enabled ($(if(-not $ad.Enabled){"PASS"}else{"FAIL"}))


<#######################################################################################

    Entra

########################################################################################>

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users

Connect-MgGraph -Identity -NoWelcome

$mg = Get-MgUser -Filter "mail eq '$Email'" -Property accountEnabled,signInSessionsValidFromDateTime
Add-Check "Entra" "Account Disabled" "False" $mg.AccountEnabled ($(if(-not $mg.AccountEnabled){"PASS"}else{"FAIL"}))
Add-Check "Entra" "Session Revoked" "Updated timestamp" $mg.SignInSessionsValidFromDateTime "INFO"

Disconnect-MgGraph | Out-Null

<#######################################################################################

    Exchange

########################################################################################>


if ($VerifyExchange) {
    Import-Module ExchangeOnlineManagement
        Connect-ExchangeOnline -AppId $ExoAppId -CertificateThumbprint $ExoCertThumbprint `
        -Organization $ExoOrganization -ShowBanner:$false

    $cas = Get-CASMailbox -Identity $Email
    Add-Check "Exchange" "OWAEnabled" "False" $cas.OWAEnabled ($(if(-not $cas.OWAEnabled){"PASS"}else{"FAIL"}))

    Disconnect-ExchangeOnline -Confirm:$false | Out-Null
}

<#######################################################################################

    Output notifications

########################################################################################>

$Report | ConvertTo-Json -Depth 6 