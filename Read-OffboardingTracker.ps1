

Import-module  Microsoft.Graph.Authentication


Connect-AzAccount -Identity


<##################################################################################################

    Setup

##################################################################################################>

    $TeamName             = 'Team Members on the move'
    $ChannelName          = 'Offboarding'
    $ListTitle            = 'Offboarding tracker'
    $DateFieldDisplayName = 'First Day'           # <-- change this to your date column display name

    #Fetch URL for webhook
        $VaultName = "ITCrowd-Key-Vault"
        $TargetScriptPath = Get-AzKeyVaultSecret -VaultName $vaultName -Name "InvokeOffboardingWebhookURL" -AsPlainText
    

    # Optional: how many days ahead
        $DaysAhead = 14

    # Optional: if you want to only dry-run first
        $DryRun = $true

<##################################################################################################

    Helper functions

##################################################################################################>

    function Ensure-GraphConnection {
        [CmdletBinding()]
        param()

        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        if (-not $ctx) {
            Connect-MgGraph -Scopes @(
                'Group.Read.All',
                'Channel.ReadBasic.All',
                'Sites.Selected'
            ) | Out-Null
        }
    }

    function Invoke-GraphGetAll {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Uri
        )

        $results = @()

        do {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType PSObject
            if ($resp.value) {
                $results += $resp.value
            }
            else {
                # some endpoints may return a single object instead of .value
                $results += $resp
            }

            $Uri = $resp.'@odata.nextLink'
        } while ($Uri)

        return $results
    }

    function Get-TeamByName {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$DisplayName
        )

        # Pull groups with matching display name, then keep only Team-enabled groups
        $safeName = $DisplayName.Replace("'", "''")

        $groups = Get-MgGroup -Filter "displayName eq '$safeName'" `
                            -Property "id,displayName,resourceProvisioningOptions" `
                            -All

        $teamGroup = $groups | Where-Object {
            $_.ResourceProvisioningOptions -contains 'Team'
        } | Select-Object -First 1

        if (-not $teamGroup) {
            throw "Team '$DisplayName' was not found."
        }

        return $teamGroup
    }

    function Get-ChannelByName {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$TeamId,

            [Parameter(Mandatory)]
            [string]$DisplayName
        )

        $channels = Invoke-GraphGetAll -Uri "https://graph.microsoft.com/v1.0/teams/$TeamId/channels"
        $channel  = $channels | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1

        if (-not $channel) {
            throw "Channel '$DisplayName' was not found in the team."
        }

        return $channel
    }

    function Get-TeamRootSite {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$GroupId
        )

        $site = Invoke-MgGraphRequest -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId/sites/root" `
            -OutputType PSObject

        if (-not $site.id) {
            throw "Could not resolve the SharePoint site for GroupId '$GroupId'."
        }

        return $site
    }

    function Get-ListByTitle {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$SiteId,

            [Parameter(Mandatory)]
            [string]$Title
        )

        $lists = Invoke-GraphGetAll -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/lists"
        $list  = $lists | Where-Object { $_.displayName -eq $Title } | Select-Object -First 1

        if (-not $list) {
            throw "List '$Title' was not found on site '$SiteId'."
        }

        return $list
    }

    function Get-ListColumnInternalName {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$SiteId,

            [Parameter(Mandatory)]
            [string]$ListId,

            [Parameter(Mandatory)]
            [string]$ColumnDisplayName
        )

        $columns = Invoke-GraphGetAll -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$ListId/columns"
        $column  = $columns | Where-Object { $_.displayName -eq $ColumnDisplayName } | Select-Object -First 1

        if (-not $column) {
            $available = ($columns.displayName | Sort-Object) -join ', '
            throw "Column '$ColumnDisplayName' was not found. Available columns: $available"
        }

        # In Microsoft Lists, the internal field name is generally in .name
        return $column.name
    }

    function Get-AllListItemsWithFields {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$SiteId,

            [Parameter(Mandatory)]
            [string]$ListId
        )

        $uri = "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$ListId/items?expand=fields&`$top=200"
        return Invoke-GraphGetAll -Uri $uri
    }

    function Convert-ToSafeDate {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false)]
            $Value
        )

        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
            return $null
        }

        try {
            return [datetime]$Value
        }
        catch {
            return $null
        }
    }

<##################################################################################################

    Main

##################################################################################################>

    try {
        Ensure-GraphConnection

        Write-Host "Resolving team..." -ForegroundColor Cyan
        $team = Get-TeamByName -DisplayName $TeamName
        Write-Host ("Found Team: {0} ({1})" -f $team.DisplayName, $team.Id) -ForegroundColor Green

        Write-Host "Resolving channel..." -ForegroundColor Cyan
        $channel = Get-ChannelByName -TeamId $team.Id -DisplayName $ChannelName
        Write-Host ("Found Channel: {0} ({1})" -f $channel.displayName, $channel.id) -ForegroundColor Green

        Write-Host "Resolving Team site..." -ForegroundColor Cyan
        $site = Get-TeamRootSite -GroupId $team.Id
        Write-Host ("Found Site: {0}" -f $site.webUrl) -ForegroundColor Green

        Write-Host "Resolving list..." -ForegroundColor Cyan
        $list = Get-ListByTitle -SiteId $site.id -Title $ListTitle
        Write-Host ("Found List: {0} ({1})" -f $list.displayName, $list.id) -ForegroundColor Green

        Write-Host "Resolving date column internal name..." -ForegroundColor Cyan
        $dateFieldInternalName = Get-ListColumnInternalName -SiteId $site.id -ListId $list.id -ColumnDisplayName $DateFieldDisplayName
        Write-Host ("Date field internal name: {0}" -f $dateFieldInternalName) -ForegroundColor Green

        Write-Host "Reading list items..." -ForegroundColor Cyan
        $items = Get-AllListItemsWithFields -SiteId $site.id -ListId $list.id

        $today     = (Get-Date).Date
        $windowEnd = $today.AddDays($DaysAhead)

        $matches = foreach ($item in $items) {
            $fields = $item.fields
            if (-not $fields) { continue }

            # fields is a dynamic object returned by Graph.
            # Convert to a normal hashtable-ish view for safe access.
            $fieldBag = @{}
            $fields.PSObject.Properties | ForEach-Object {
                $fieldBag[$_.Name] = $_.Value
            }

            $rawDate = $fieldBag[$dateFieldInternalName]
            $dt = Convert-ToSafeDate -Value $rawDate
            if (-not $dt) { continue }

            # Compare by date only
            $itemDate = $dt.Date
            if ($itemDate -ge $today -and $itemDate -le $windowEnd) {
                [pscustomobject]@{
                    ItemId       = $item.id
                    Title        = $fieldBag['Title']
                    ItemDate     = $itemDate
                    RawDate      = $rawDate
                    EmployeeName = $fieldBag['EmployeeName']   # <-- change if your column has a different name
                    Manager      = $fieldBag['Manager']        # <-- change if your column has a different name
                    Email        = $fieldBag['Email']          # <-- change if your column has a different name
                    Fields       = $fieldBag
                }
            }
        }

        Write-Host ("Found {0} matching item(s) in the next {1} day(s)." -f $matches.Count, $DaysAhead) -ForegroundColor Yellow

        foreach ($row in $matches) {
            Write-Host ("Match: ItemId={0}, Title={1}, Date={2}" -f $row.ItemId, $row.Title, $row.ItemDate.ToString('yyyy-MM-dd')) -ForegroundColor Magenta

            # Example payload you can pass to the next script
            $payload = [pscustomobject]@{
                ItemId       = $row.ItemId
                Title        = $row.Title
                ItemDate     = $row.ItemDate.ToString('yyyy-MM-dd')
                EmployeeName = $row.EmployeeName
                Manager      = $row.Manager
                Email        = $row.Email
            }

            if ($DryRun) {
                Write-Host "DRY RUN - would call target script with payload:" -ForegroundColor DarkYellow
                $payload | ConvertTo-Json -Depth 5 | Write-Host
            }
            else {
                # Option 1: pass a JSON blob
                & $TargetScriptPath -PayloadJson ($payload | ConvertTo-Json -Compress)

                # Option 2: if your target script has named parameters, use this instead:
                # & $TargetScriptPath `
                #     -ItemId $row.ItemId `
                #     -Title $row.Title `
                #     -ItemDate $row.ItemDate `
                #     -EmployeeName $row.EmployeeName `
                #     -Manager $row.Manager `
                #     -Email $row.Email
            }
        }
    }
    catch {
        Write-Error $_
        throw
    }