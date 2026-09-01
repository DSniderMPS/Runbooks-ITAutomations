
#$ErrorActionPreference = 'Stop'
Connect-AzAccount -Identity

write-output "Starting..."

Import-Module Microsoft.Graph.Authentication -force -verbose
Import-Module Microsoft.Graph.Users -force -verbose

Import-Module ExchangeOnlineManagement -ErrorAction Stop

Write-Output "Authentication module loaded"
Write-Output "Users module loaded"

Connect-MgGraph -Identity -NoWelcome
Write-Output "Connected to Graph"

write-output "connecting to Exchange"
 Connect-ExchangeOnline -managedidentity -Organization 'mcmillanpazdansmith.onmicrosoft.com'



Get-MgContext | Format-List *

Write-Output "Context retrieved"

$email = 'wmpitts@mcmillanpazdansmith.com'

Get-MgUser -Top 1 | Select-Object DisplayName,Mail

$mgUser = Get-MgUser -userid $email  | Select-Object id,DisplayName,Mail

write-output $mgUser

write-output '*******************4********************'

$result = Get-MailboxPermission -Identity $email

write-output "permissions: $result"

$result = Get-MailboxAutoReplyConfiguration -Identity $email

 write-output "OOO: $result"

<#
    Import-Module Microsoft.Graph.Authentication
    Import-Module Microsoft.Graph.Users
    Import-Module Microsoft.Graph.Users.Actions

$ErrorActionPreference = 'Stop'

$email = 'dsnider@mcmillanpazdansmith.com'

try {

    Connect-MgGraph -Identity -NoWelcome

    $mguser = Get-MgUser -UserId $Email -Property `
    Id,
    DisplayName,
    GivenName,
    Surname,
    Mail,
    UserPrincipalName,
    EmployeeId,
    JobTitle,
    Department,
    OfficeLocation,
    MobilePhone,
    BusinessPhones,
    CompanyName,
    AccountEnabled,
    EmployeeLeaveDateTime,
    CreatedDateTime

    if (-not $mgUser) { throw "Entra user not found" } else {

            write-output "UserPrincipalName: $($mgUser.UserPrincipalName)"
            write-output "GivenName: $($mgUser.GivenName)"
            write-output "Surname: $($mgUser.Surname)"
            write-output "OnPremisesSamAccountName: $($mgUser.OnPremisesSamAccountName)"
            write-output "OnPremisesDistinguishedName: $($mgUser.OnPremisesDistinguishedName)"
            write-output "DisplayName: $($mgUser.DisplayName)"
            write-output "EmployeeId: $($mgUser.EmployeeId)"
            write-output "AccountEnabled: $($mgUser.AccountEnabled)"
    }

}
catch {
    Write-Error $_
    throw
}
finally {
    Disconnect-MgGraph | Out-Null
}

#>