#Requires -Version 7.0

<#
.SYNOPSIS
    Provisions the agent-intake reviewer model-driven app solution.

.DESCRIPTION
    Uses PAC CLI for model-driven app creation, table-to-solution registration,
    publishing, and optional managed export. When a Dataverse bearer token is
    available, the script also bootstraps the solution and publisher (if they do
    not already exist), creates reviewer queue system views, creates reviewer
    security roles, and associates those roles with the reviewer app.

    PAC CLI does not currently compose model-driven app table pages, dashboards,
    or business rules for this design. The script emits lines prefixed with
    'MANUAL STEP REQUIRED:' for those gaps so customer admins can finish the app
    in the Power Apps maker portal by following docs\reviewer-app-build.md.

.PARAMETER EnvironmentUrl
    Dataverse environment URL, for example https://contoso.crm.dynamics.com.

.PARAMETER AppSpecJson
    Path to reviewer-app-spec.json. Supports customer-specific spec overrides.

.PARAMETER Export
    If specified, exports the solution as a managed .zip to ExportPath.

.PARAMETER ExportPath
    Managed solution export path. Defaults to agent-intake\artifacts\reviewer-app\AgentIntakeReviewerApp_managed.zip.

.PARAMETER AccessToken
    Optional Dataverse bearer token. Recommended on the first run so the script
    can create the solution, reviewer views, and reviewer security roles via the
    Dataverse Web API.

.PARAMETER DryRun
    Prints PAC CLI and Web API actions without making changes.

.EXAMPLE
    .\provision_reviewer_app.ps1 -EnvironmentUrl https://contoso.crm.dynamics.com

.EXAMPLE
    .\provision_reviewer_app.ps1 -EnvironmentUrl https://contoso.crm.dynamics.com -Export -AccessToken $env:DATAVERSE_ACCESS_TOKEN

.EXAMPLE
    .\provision_reviewer_app.ps1 -EnvironmentUrl https://contoso.crm.dynamics.com -AppSpecJson .\customer-reviewer-app-spec.json -DryRun
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentUrl,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$AppSpecJson = (Join-Path $PSScriptRoot '..\templates\reviewer-app-spec.json'),

    [Parameter(Mandatory = $false)]
    [switch]$Export,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath = (Join-Path $PSScriptRoot '..\artifacts\reviewer-app\AgentIntakeReviewerApp_managed.zip'),

    [Parameter(Mandatory = $false)]
    [string]$AccessToken,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:BaseApiUrl = '{0}/api/data/v9.2/' -f $EnvironmentUrl.TrimEnd('/')
$script:PacCommandsUsed = [System.Collections.Generic.List[string]]::new()
$script:ManualSteps = [System.Collections.Generic.List[string]]::new()
$script:ProvisionedViews = [System.Collections.Generic.List[string]]::new()
$script:ProvisionedRoles = [System.Collections.Generic.List[string]]::new()

function Write-Info {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-WarnMessage {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Add-ManualStep {
    param([Parameter(Mandatory = $true)][string]$Message)

    if (-not $script:ManualSteps.Contains($Message)) {
        $script:ManualSteps.Add($Message) | Out-Null
    }

    Write-WarnMessage "MANUAL STEP REQUIRED: $Message"
}

function Test-PacInstalled {
    try {
        $null = Get-Command pac -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-PacVersion {
    if (-not (Test-PacInstalled)) {
        return $null
    }

    $raw = & pac 2>&1
    $match = [regex]::Match(($raw -join "`n"), 'Version:\s*([^\r\n]+)')
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    return 'unknown'
}

function Test-PacAuthenticated {
    if ($DryRun) {
        return
    }

    $raw = & pac auth who 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "PAC CLI is not authenticated. Run 'pac auth create --environment $EnvironmentUrl' and retry. Details: $($raw -join "`n")"
    }
}

function Invoke-PacCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $false)]
        [switch]$ExpectJson
    )

    $display = 'pac ' + ($Arguments -join ' ')
    $script:PacCommandsUsed.Add($display) | Out-Null
    Write-Info ("{0}: {1}" -f $Description, $display)

    if ($DryRun) {
        if ($ExpectJson) {
            return @()
        }

        return ''
    }

    $raw = & pac @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($raw | ForEach-Object { "$_" }) -join "`n"

    if ($exitCode -ne 0) {
        throw "$Description failed (exit $exitCode): $text"
    }

    if ($ExpectJson -or $text.Trim().StartsWith('[') -or $text.Trim().StartsWith('{')) {
        if ([string]::IsNullOrWhiteSpace($text)) {
            return @()
        }

        return ($text | ConvertFrom-Json)
    }

    return $text
}

function Get-ResolvedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-EnvironmentVariableValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    $item = Get-Item -Path ("Env:{0}" -f $Name) -ErrorAction SilentlyContinue
    if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace($item.Value)) {
        return $item.Value.Trim()
    }

    return $null
}

function Resolve-AccessToken {
    param(
        [Parameter(Mandatory = $false)][string]$ProvidedAccessToken,
        [Parameter(Mandatory = $true)][string]$ResolvedEnvironmentUrl
    )

    if (-not [string]::IsNullOrWhiteSpace($ProvidedAccessToken)) {
        return $ProvidedAccessToken.Trim()
    }

    foreach ($variableName in @('DATAVERSE_ACCESS_TOKEN', 'PAC_ACCESS_TOKEN')) {
        $value = Get-EnvironmentVariableValue -Name $variableName
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            Write-Info "Using access token from environment variable $variableName."
            return $value
        }
    }

    $az = Get-Command az -ErrorAction SilentlyContinue
    if ($null -ne $az) {
        try {
            $token = & az account get-access-token --resource $ResolvedEnvironmentUrl --query accessToken -o tsv 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($token)) {
                Write-Info 'Using Azure CLI access token for Dataverse Web API operations.'
                return $token.Trim()
            }
        }
        catch {
            Write-WarnMessage "Azure CLI access-token fallback was unavailable: $_"
        }
    }

    return $null
}

function Get-DataverseHeaders {
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $false)][string]$SolutionUniqueName
    )

    $headers = @{
        'Authorization'    = 'Bearer ' + $Token
        'Accept'           = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
        'If-None-Match'    = 'null'
    }

    if (-not [string]::IsNullOrWhiteSpace($SolutionUniqueName)) {
        $headers['MSCRM.SolutionUniqueName'] = $SolutionUniqueName
    }

    return $headers
}

function ConvertTo-ODataStringLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'{0}'" -f $Value.Replace("'", "''")
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$RelativeUri,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $false)]
        [object]$Body,

        [Parameter(Mandatory = $false)]
        [string]$SolutionUniqueName,

        [Parameter(Mandatory = $false)]
        [switch]$AllowNotFound
    )

    $uri = $script:BaseApiUrl + $RelativeUri.TrimStart('/')
    $headers = Get-DataverseHeaders -Token $Token -SolutionUniqueName $SolutionUniqueName

    if ($Body) {
        $headers['Content-Type'] = 'application/json; charset=utf-8'
    }

    if ($DryRun) {
        Write-Info "[DRY RUN] $Method $uri"
        if ($Body) {
            Write-Info ((ConvertTo-Json $Body -Depth 20) -replace "`n", ' ')
        }

        return [pscustomobject]@{
            StatusCode = 200
            Body       = $null
            Headers    = @{}
        }
    }

    $bodyJson = $null
    if ($Body) {
        $bodyJson = $Body | ConvertTo-Json -Depth 20 -Compress
    }

    $response = Invoke-WebRequest -Uri $uri -Method $Method -Headers $headers -Body $bodyJson -UseBasicParsing -SkipHttpErrorCheck
    if ($AllowNotFound -and $response.StatusCode -eq 404) {
        return $null
    }

    if ($response.StatusCode -ge 400) {
        throw "Dataverse Web API request failed ($Method $RelativeUri): HTTP $($response.StatusCode) $($response.Content)"
    }

    $responseBody = $null
    if (-not [string]::IsNullOrWhiteSpace($response.Content)) {
        try {
            $responseBody = $response.Content | ConvertFrom-Json -AsHashtable
        }
        catch {
            $responseBody = $response.Content
        }
    }

    return [pscustomobject]@{
        StatusCode = [int]$response.StatusCode
        Body       = $responseBody
        Headers    = $response.Headers
    }
}

function Get-ChoiceValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Spec,
        [Parameter(Mandatory = $true)][string]$ChoiceSetName,
        [Parameter(Mandatory = $true)][string]$ChoiceLabel
    )

    $choiceSet = $Spec.optionsets[$ChoiceSetName]
    if ($null -eq $choiceSet) {
        throw "Choice set '$ChoiceSetName' was not found in the spec."
    }

    if (-not $choiceSet.ContainsKey($ChoiceLabel)) {
        throw "Choice '$ChoiceLabel' was not found in the '$ChoiceSetName' option set."
    }

    return [int]$choiceSet[$ChoiceLabel]
}

function Get-PrivilegeDepthValue {
    param([Parameter(Mandatory = $true)][string]$DepthName)

    switch ($DepthName) {
        'Basic'  { return 0 }
        'Local'  { return 1 }
        'Deep'   { return 2 }
        'Global' { return 3 }
        default  { throw "Unsupported privilege depth '$DepthName'." }
    }
}

function Copy-Hashtable {
    param([Parameter(Mandatory = $true)][hashtable]$InputObject)
    return ($InputObject | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable)
}

function Expand-ViewDefinitions {
    param([Parameter(Mandatory = $true)][hashtable]$Spec)

    $expanded = New-Object System.Collections.Generic.List[hashtable]
    foreach ($view in $Spec.views) {
        if ($view.ContainsKey('materializePerRole') -and $view.materializePerRole) {
            foreach ($role in $view.roles) {
                $copy = Copy-Hashtable -InputObject $view
                $copy.Remove('materializePerRole') | Out-Null
                $copy.Remove('roles') | Out-Null
                $copy.name = $view.namePattern.Replace('{role}', $role)
                $copy.logicalViewName = $view.name
                $copy.roleVariant = $role

                $conditions = New-Object System.Collections.Generic.List[hashtable]
                foreach ($condition in $view.conditions) {
                    $conditions.Add((Copy-Hashtable -InputObject $condition)) | Out-Null
                }

                $conditions.Add(@{
                    attribute = $view.roleCondition.attribute
                    operator  = $view.roleCondition.operator
                    choiceSet = $view.roleCondition.choiceSet
                    choice    = $role
                }) | Out-Null

                $copy.conditions = @($conditions)
                $expanded.Add($copy) | Out-Null
            }
        }
        else {
            $expanded.Add((Copy-Hashtable -InputObject $view)) | Out-Null
        }
    }

    return @($expanded)
}

function Get-TableMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$LogicalName,
        [Parameter(Mandatory = $true)][string]$Token
    )

    $relativeUri = "EntityDefinitions(LogicalName='{0}')?`$select=LogicalName,SchemaName,EntitySetName,PrimaryIdAttribute,ObjectTypeCode" -f $LogicalName
    $response = Invoke-DataverseRequest -Method GET -RelativeUri $relativeUri -Token $Token
    return $response.Body
}

function Test-TableExistsWithPac {
    param([Parameter(Mandatory = $true)][string]$LogicalName)

    $output = Invoke-PacCommand -Arguments @('model', 'list-tables', '--environment', $EnvironmentUrl, '--search', $LogicalName, '--type', 'all') -Description "Table discovery for $LogicalName"
    return ($output -match [regex]::Escape($LogicalName))
}

function Get-TableMap {
    param([Parameter(Mandatory = $true)][hashtable]$Spec)

    $map = @{}
    foreach ($table in $Spec.tables) {
        $map[$table.logicalName] = $table
    }

    return $map
}

function Get-ExistingPublisher {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Spec,
        [Parameter(Mandatory = $true)][string]$Token
    )

    $prefixFilter = ConvertTo-ODataStringLiteral -Value $Spec.publisher.prefix
    $nameFilter = ConvertTo-ODataStringLiteral -Value $Spec.publisher.uniqueName
    $response = Invoke-DataverseRequest -Method GET -Token $Token -RelativeUri "publishers?`$select=publisherid,uniquename,friendlyname,customizationprefix&`$filter=customizationprefix eq $prefixFilter or uniquename eq $nameFilter"

    if ($response.Body.value.Count -gt 0) {
        return $response.Body.value[0]
    }

    return $null
}

function New-PublisherRecord {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Spec,
        [Parameter(Mandatory = $true)][string]$Token
    )

    $body = @{
        friendlyname                   = $Spec.publisher.name
        uniquename                     = $Spec.publisher.uniqueName
        customizationprefix            = $Spec.publisher.prefix
        customizationoptionvalueprefix = [int]$Spec.publisher.customizationOptionValuePrefix
        description                    = $Spec.publisher.description
        supportingwebsiteurl           = 'https://judeper.github.io/FSI-AgentGov-Solutions/'
    }

    $response = Invoke-DataverseRequest -Method POST -Token $Token -RelativeUri 'publishers' -Body $body
    $odataEntityId = $response.Headers['OData-EntityId']
    if (-not $odataEntityId) {
        throw 'Publisher creation did not return an OData-EntityId header.'
    }

    $match = [regex]::Match($odataEntityId, 'publishers\(([0-9a-fA-F-]+)\)')
    if (-not $match.Success) {
        throw "Unable to parse publisherid from '$odataEntityId'."
    }

    return @{
        publisherid          = $match.Groups[1].Value
        uniquename           = $Spec.publisher.uniqueName
        friendlyname         = $Spec.publisher.name
        customizationprefix  = $Spec.publisher.prefix
    }
}

function Get-ExistingSolution {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Spec,
        [Parameter(Mandatory = $false)][string]$Token
    )

    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $solutionNameFilter = ConvertTo-ODataStringLiteral -Value $Spec.solutionName
        $response = Invoke-DataverseRequest -Method GET -Token $Token -RelativeUri "solutions?`$select=solutionid,uniquename,friendlyname,version&`$filter=uniquename eq $solutionNameFilter"
        if ($response.Body.value.Count -gt 0) {
            return $response.Body.value[0]
        }

        return $null
    }

    $solutions = Invoke-PacCommand -Arguments @('solution', 'list', '--environment', $EnvironmentUrl, '--json') -Description 'Solution inventory' -ExpectJson
    foreach ($solution in @($solutions)) {
        $uniqueName = $solution.uniquename
        if ([string]::IsNullOrWhiteSpace($uniqueName) -and $solution.PSObject.Properties['UniqueName']) {
            $uniqueName = $solution.UniqueName
        }

        if ($uniqueName -eq $Spec.solutionName) {
            return $solution
        }
    }

    return $null
}

function New-SolutionRecord {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Spec,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$PublisherId
    )

    $body = @{
        friendlyname            = $Spec.solutionDisplayName
        uniquename              = $Spec.solutionName
        version                 = $Spec.solutionVersion
        description             = 'Reviewer model-driven app and reviewer queue metadata for agent-intake Standard and Full routing.'
        'publisherid@odata.bind' = "/publishers($PublisherId)"
    }

    $response = Invoke-DataverseRequest -Method POST -Token $Token -RelativeUri 'solutions' -Body $body
    $odataEntityId = $response.Headers['OData-EntityId']
    if (-not $odataEntityId) {
        throw 'Solution creation did not return an OData-EntityId header.'
    }

    $match = [regex]::Match($odataEntityId, 'solutions\(([0-9a-fA-F-]+)\)')
    if (-not $match.Success) {
        throw "Unable to parse solutionid from '$odataEntityId'."
    }

    return @{
        solutionid   = $match.Groups[1].Value
        uniquename   = $Spec.solutionName
        friendlyname = $Spec.solutionDisplayName
        version      = $Spec.solutionVersion
    }
}

function Get-ExistingAppRecord {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Spec,
        [Parameter(Mandatory = $false)][string]$Token
    )

    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $nameFilter = ConvertTo-ODataStringLiteral -Value $Spec.appDisplayName
        $response = Invoke-DataverseRequest -Method GET -Token $Token -RelativeUri "appmodules?`$select=appmoduleid,name,uniquename&`$filter=name eq $nameFilter"
        if ($response.Body.value.Count -gt 0) {
            return $response.Body.value[0]
        }

        return $null
    }

    $output = Invoke-PacCommand -Arguments @('model', 'list', '--environment', $EnvironmentUrl) -Description 'Model-driven app inventory'
    $lines = $output -split "`r?`n"
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -eq $Spec.appDisplayName) {
            $appId = ''
            $uniqueName = ''
            if ($index + 1 -lt $lines.Count) {
                $appIdMatch = [regex]::Match($lines[$index + 1], 'App ID:\s*(.+)$')
                if ($appIdMatch.Success) {
                    $appId = $appIdMatch.Groups[1].Value.Trim()
                }
            }

            if ($index + 2 -lt $lines.Count) {
                $uniqueNameMatch = [regex]::Match($lines[$index + 2], 'Unique Name:\s*(.+)$')
                if ($uniqueNameMatch.Success) {
                    $uniqueName = $uniqueNameMatch.Groups[1].Value.Trim()
                }
            }

            return @{
                appmoduleid = $appId
                name        = $Spec.appDisplayName
                uniquename  = $uniqueName
            }
        }
    }

    return $null
}

function New-AppRecord {
    param([Parameter(Mandatory = $true)][hashtable]$Spec)

    Invoke-PacCommand -Arguments @(
        'model',
        'create',
        '--name', $Spec.appDisplayName,
        '--description', $Spec.appDescription,
        '--environment', $EnvironmentUrl,
        '--solution', $Spec.solutionName,
        '--publish'
    ) -Description 'Create reviewer model-driven app'
}

function Add-TableToSolution {
    param([Parameter(Mandatory = $true)][hashtable]$TableSpec, [Parameter(Mandatory = $true)][hashtable]$Spec)

    Invoke-PacCommand -Arguments @(
        'solution',
        'add-solution-component',
        '--environment', $EnvironmentUrl,
        '--solutionUniqueName', $Spec.solutionName,
        '--component', $TableSpec.schemaName,
        '--componentType', '1',
        '--AddRequiredComponents'
    ) -Description "Add $($TableSpec.logicalName) to solution"
}

function Get-ExistingViewRecord {
    param(
        [Parameter(Mandatory = $true)][hashtable]$ViewSpec,
        [Parameter(Mandatory = $true)][string]$Token
    )

    $viewNameFilter = ConvertTo-ODataStringLiteral -Value $ViewSpec.name
    $tableFilter = ConvertTo-ODataStringLiteral -Value $ViewSpec.table
    $relativeUri = "savedqueries?`$select=savedqueryid,name,returnedtypecode&`$filter=name eq $viewNameFilter and returnedtypecode eq $tableFilter"
    $response = Invoke-DataverseRequest -Method GET -Token $Token -RelativeUri $relativeUri

    if ($response.Body.value.Count -gt 0) {
        return $response.Body.value[0]
    }

    return $null
}

function ConvertTo-ConditionXml {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Condition,
        [Parameter(Mandatory = $true)][hashtable]$Spec
    )

    $attribute = $Condition.attribute
    $operator = $Condition.operator

    if ($Condition.ContainsKey('valueOf')) {
        return "<condition attribute='$attribute' operator='$operator' valueof='$($Condition.valueOf)' />"
    }

    if ($Condition.ContainsKey('choiceSet')) {
        $value = Get-ChoiceValue -Spec $Spec -ChoiceSetName $Condition.choiceSet -ChoiceLabel $Condition.choice
        return "<condition attribute='$attribute' operator='$operator' value='$value' />"
    }

    if ($Condition.ContainsKey('value')) {
        $value = $Condition.value
        if ($value -is [bool]) {
            $value = if ($value) { 1 } else { 0 }
        }

        $escaped = [System.Security.SecurityElement]::Escape([string]$value)
        return "<condition attribute='$attribute' operator='$operator' value='$escaped' />"
    }

    return "<condition attribute='$attribute' operator='$operator' />"
}

function ConvertTo-ViewFetchXml {
    param(
        [Parameter(Mandatory = $true)][hashtable]$ViewSpec,
        [Parameter(Mandatory = $true)][hashtable]$Spec
    )

    $attributes = foreach ($column in $ViewSpec.columns) {
        "<attribute name='$($column.name)' />"
    }

    $orders = foreach ($sort in $ViewSpec.sort) {
        $descending = if ($sort.descending) { 'true' } else { 'false' }
        "<order attribute='$($sort.attribute)' descending='$descending' />"
    }

    $conditions = foreach ($condition in $ViewSpec.conditions) {
        ConvertTo-ConditionXml -Condition $condition -Spec $Spec
    }

    return @"
<fetch version='1.0' output-format='xml-platform' mapping='logical' distinct='false'>
  <entity name='$($ViewSpec.table)'>
    $($attributes -join "`n    ")
    $($orders -join "`n    ")
    <filter type='and'>
      $($conditions -join "`n      ")
    </filter>
  </entity>
</fetch>
"@
}

function ConvertTo-ViewLayoutXml {
    param(
        [Parameter(Mandatory = $true)][hashtable]$ViewSpec,
        [Parameter(Mandatory = $true)][hashtable]$TableMetadataMap
    )

    $metadata = $TableMetadataMap[$ViewSpec.table]
    if ($null -eq $metadata) {
        throw "Table metadata for '$($ViewSpec.table)' was not loaded."
    }

    $jump = $ViewSpec.columns[0].name
    $cells = foreach ($column in $ViewSpec.columns) {
        $width = if ($column.ContainsKey('width')) { [int]$column.width } else { 150 }
        "<cell name='$($column.name)' width='$width' />"
    }

    return @"
<grid name='resultset' object='$($metadata.ObjectTypeCode)' jump='$jump' select='1' icon='1' preview='1'>
  <row name='result' id='$($metadata.PrimaryIdAttribute)'>
    $($cells -join "`n    ")
  </row>
</grid>
"@
}

function Set-ReviewerView {
    param(
        [Parameter(Mandatory = $true)][hashtable]$ViewSpec,
        [Parameter(Mandatory = $true)][hashtable]$Spec,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][hashtable]$TableMetadataMap
    )

    $fetchXml = (ConvertTo-ViewFetchXml -ViewSpec $ViewSpec -Spec $Spec).Trim()
    $layoutXml = (ConvertTo-ViewLayoutXml -ViewSpec $ViewSpec -TableMetadataMap $TableMetadataMap).Trim()

    $payload = @{
        name             = $ViewSpec.name
        description      = $ViewSpec.description
        returnedtypecode = $ViewSpec.table
        querytype        = 0
        fetchxml         = $fetchXml
        layoutxml        = $layoutXml
        columnsetxml     = $layoutXml
        isdefault        = $false
        isquickfindquery = $false
    }

    $existing = Get-ExistingViewRecord -ViewSpec $ViewSpec -Token $Token
    if ($null -eq $existing) {
        Invoke-DataverseRequest -Method POST -Token $Token -RelativeUri 'savedqueries' -Body $payload -SolutionUniqueName $Spec.solutionName | Out-Null
        Write-Info "Created system view '$($ViewSpec.name)'."
    }
    else {
        Invoke-DataverseRequest -Method PATCH -Token $Token -RelativeUri ("savedqueries({0})" -f $existing.savedqueryid) -Body $payload | Out-Null
        Write-Info "Updated system view '$($ViewSpec.name)'."
    }

    if (-not $script:ProvisionedViews.Contains($ViewSpec.name)) {
        $script:ProvisionedViews.Add($ViewSpec.name) | Out-Null
    }
}

function Get-ExistingRoleRecord {
    param(
        [Parameter(Mandatory = $true)][hashtable]$RoleSpec,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$BusinessUnitId
    )

    $nameFilter = ConvertTo-ODataStringLiteral -Value $RoleSpec.name
    $relativeUri = "roles?`$select=roleid,name,_businessunitid_value&`$filter=name eq $nameFilter&`$expand=roleprivileges_association(`$select=name,privilegeid)"
    $response = Invoke-DataverseRequest -Method GET -Token $Token -RelativeUri $relativeUri

    foreach ($role in $response.Body.value) {
        if ($role['_businessunitid_value'] -eq $BusinessUnitId) {
            return $role
        }
    }

    return $null
}

function New-RoleRecord {
    param(
        [Parameter(Mandatory = $true)][hashtable]$RoleSpec,
        [Parameter(Mandatory = $true)][hashtable]$Spec,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$BusinessUnitId
    )

    $body = @{
        name                        = $RoleSpec.name
        description                 = $RoleSpec.description
        'businessunitid@odata.bind' = "/businessunits($BusinessUnitId)"
    }

    $response = Invoke-DataverseRequest -Method POST -Token $Token -RelativeUri 'roles' -Body $body -SolutionUniqueName $Spec.solutionName
    $odataEntityId = $response.Headers['OData-EntityId']
    if (-not $odataEntityId) {
        throw 'Role creation did not return an OData-EntityId header.'
    }

    $match = [regex]::Match($odataEntityId, 'roles\(([0-9a-fA-F-]+)\)')
    if (-not $match.Success) {
        throw "Unable to parse roleid from '$odataEntityId'."
    }

    return @{
        roleid                    = $match.Groups[1].Value
        name                      = $RoleSpec.name
        '_businessunitid_value'   = $BusinessUnitId
        roleprivileges_association = @()
    }
}

function Get-CustomPrivilegeMap {
    param([Parameter(Mandatory = $true)][string]$Token)

    $response = Invoke-DataverseRequest -Method GET -Token $Token -RelativeUri "privileges?`$select=privilegeid,name&`$filter=startswith(name,'prv') and contains(name,'fsi_')"
    $map = @{}
    foreach ($item in $response.Body.value) {
        $map[$item.name.ToLowerInvariant()] = $item
    }

    return $map
}

function Get-PrivilegeNameCandidates {
    param(
        [Parameter(Mandatory = $true)][string]$Right,
        [Parameter(Mandatory = $true)][hashtable]$TableSpec
    )

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($name in @($TableSpec.schemaName, $TableSpec.logicalName)) {
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $candidates.Add(("prv{0}{1}" -f $Right, $name)) | Out-Null
        }
    }

    return @($candidates | Select-Object -Unique)
}

function Add-RolePrivileges {
    param(
        [Parameter(Mandatory = $true)][hashtable]$RoleSpec,
        [Parameter(Mandatory = $true)][hashtable]$RoleRecord,
        [Parameter(Mandatory = $true)][hashtable]$TableMap,
        [Parameter(Mandatory = $true)][hashtable]$PrivilegeMap,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$BusinessUnitId
    )

    $existingPrivilegeNames = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($existing in @($RoleRecord.roleprivileges_association)) {
        $null = $existingPrivilegeNames.Add($existing.name)
    }

    $missing = New-Object System.Collections.Generic.List[hashtable]
    foreach ($tablePrivilege in $RoleSpec.tablePrivileges) {
        $tableSpec = $TableMap[$tablePrivilege.table]
        if ($null -eq $tableSpec) {
            throw "Table '$($tablePrivilege.table)' referenced by role '$($RoleSpec.name)' is not present in the spec."
        }

        foreach ($right in $tablePrivilege.rights) {
            $resolvedPrivilege = $null
            foreach ($candidate in (Get-PrivilegeNameCandidates -Right $right -TableSpec $tableSpec)) {
                if ($PrivilegeMap.ContainsKey($candidate.ToLowerInvariant())) {
                    $resolvedPrivilege = $PrivilegeMap[$candidate.ToLowerInvariant()]
                    break
                }
            }

            if ($null -eq $resolvedPrivilege) {
                throw "Unable to resolve privilege for right '$right' on table '$($tableSpec.logicalName)'."
            }

            if ($existingPrivilegeNames.Contains($resolvedPrivilege.name)) {
                continue
            }

            $missing.Add(@{
                PrivilegeId   = $resolvedPrivilege.privilegeid
                PrivilegeName = $resolvedPrivilege.name
                Depth         = (Get-PrivilegeDepthValue -DepthName $tablePrivilege.depth)
                BusinessUnitId = $BusinessUnitId
            }) | Out-Null
        }
    }

    if ($missing.Count -eq 0) {
        Write-Info "Security role '$($RoleSpec.name)' already has the required privileges."
        return
    }

    Invoke-DataverseRequest -Method POST -Token $Token -RelativeUri ("roles({0})/Microsoft.Dynamics.CRM.AddPrivilegesRole" -f $RoleRecord.roleid) -Body @{ Privileges = @($missing) } -SolutionUniqueName $Spec.solutionName | Out-Null
    Write-Info "Added $($missing.Count) privilege(s) to '$($RoleSpec.name)'."
}

function Get-AppRoleNames {
    param(
        [Parameter(Mandatory = $true)][string]$AppId,
        [Parameter(Mandatory = $true)][string]$Token
    )

    $response = Invoke-DataverseRequest -Method GET -Token $Token -RelativeUri ("appmodules({0})?`$select=name&`$expand=appmoduleroles_association(`$select=name,roleid)" -f $AppId)
    $names = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($response.Body.appmoduleroles_association)) {
        $null = $names.Add($item.name)
    }

    return $names
}

function Add-AppRoleAssociation {
    param(
        [Parameter(Mandatory = $true)][string]$AppId,
        [Parameter(Mandatory = $true)][hashtable]$RoleRecord,
        [Parameter(Mandatory = $true)][string]$Token
    )

    $body = @{
        '@odata.id' = '{0}roles({1})' -f $script:BaseApiUrl, $RoleRecord.roleid
    }

    Invoke-DataverseRequest -Method POST -Token $Token -RelativeUri ("appmodules({0})/appmoduleroles_association/`$ref" -f $AppId) -Body $body | Out-Null
    Write-Info "Associated security role '$($RoleRecord.name)' with the reviewer app."
}

function Initialize-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($DryRun) {
        Write-Info "[DRY RUN] Would create directory $Path"
        return
    }

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

$AppSpecJson = Get-ResolvedPath -Path $AppSpecJson
$ExportPath = Get-ResolvedPath -Path $ExportPath

if (-not (Test-Path -Path $AppSpecJson)) {
    throw "App spec file was not found: $AppSpecJson"
}

if (-not (Test-PacInstalled)) {
    throw 'PAC CLI (pac) was not found on PATH. Install the Microsoft Power Platform CLI before provisioning the reviewer app.'
}

Test-PacAuthenticated
$pacVersion = Get-PacVersion
Write-Info "PAC CLI version: $pacVersion"

$spec = Get-Content -Path $AppSpecJson -Raw | ConvertFrom-Json -AsHashtable
$tableMap = Get-TableMap -Spec $spec
$accessToken = Resolve-AccessToken -ProvidedAccessToken $AccessToken -ResolvedEnvironmentUrl $EnvironmentUrl

if (-not [string]::IsNullOrWhiteSpace($accessToken)) {
    Write-Info 'Dataverse Web API automation is enabled.'
}
else {
    Write-WarnMessage 'No Dataverse access token was resolved. PAC CLI actions can continue, but solution bootstrap, reviewer views, reviewer security roles, and app-role association require manual completion unless they already exist.'
}

$tableMetadataMap = @{}
if ($DryRun) {
    Write-Info '[DRY RUN] Skipping live environment discovery and using spec-defined placeholders.'
    foreach ($table in $spec.tables) {
        $tableMetadataMap[$table.logicalName] = @{
            LogicalName       = $table.logicalName
            SchemaName        = $table.schemaName
            EntitySetName     = $table.entitySetName
            PrimaryIdAttribute = $table.primaryIdAttribute
            ObjectTypeCode    = 1
        }
        Write-Info "[DRY RUN] Assuming table '$($table.logicalName)' exists."
    }

    foreach ($table in $spec.tables) {
        Add-TableToSolution -TableSpec $table -Spec $spec
    }

    New-AppRecord -Spec $spec

    if (-not [string]::IsNullOrWhiteSpace($accessToken)) {
        foreach ($view in (Expand-ViewDefinitions -Spec $spec)) {
            $null = $script:ProvisionedViews.Add($view.name)
            Write-Info "[DRY RUN] Would create or update system view '$($view.name)'."
        }

        foreach ($roleSpec in $spec.securityRoles) {
            $null = $script:ProvisionedRoles.Add($roleSpec.name)
            Write-Info "[DRY RUN] Would create or update security role '$($roleSpec.name)' and associate it with the reviewer app."
        }
    }
    else {
        Add-ManualStep -Message 'Create or confirm the reviewer queue system views and reviewer security roles in the maker portal. Re-run this script with -AccessToken to automate those steps.'
    }

    foreach ($manualStep in $spec.manualSteps) {
        Add-ManualStep -Message $manualStep.message
    }

    Invoke-PacCommand -Arguments @('solution', 'publish', '--environment', $EnvironmentUrl) -Description 'Publish customizations'

    if ($Export) {
        Initialize-Directory -Path (Split-Path -Path $ExportPath -Parent)
        Invoke-PacCommand -Arguments @(
            'solution',
            'export',
            '--environment', $EnvironmentUrl,
            '--name', $spec.solutionName,
            '--managed',
            '--overwrite',
            '--include', 'general,customization',
            '--path', $ExportPath
        ) -Description 'Export managed reviewer app solution'
    }

    Write-Host ''
    Write-Host '--- Reviewer app provisioning summary ---' -ForegroundColor Green
    Write-Host ("Solution       : {0}" -f $spec.solutionName)
    Write-Host ("App            : {0}" -f $spec.appDisplayName)
    Write-Host ("PAC version    : {0}" -f $pacVersion)
    Write-Host ("Views updated  : {0}" -f $script:ProvisionedViews.Count)
    Write-Host ("Roles updated  : {0}" -f $script:ProvisionedRoles.Count)
    if ($Export) {
        Write-Host ("Managed export : {0}" -f $ExportPath)
    }
    Write-Host ''
    Write-Host 'PAC CLI commands used:' -ForegroundColor Green
    foreach ($command in $script:PacCommandsUsed) {
        Write-Host ("  - {0}" -f $command)
    }
    Write-Host ''
    Write-Host 'Manual follow-up:' -ForegroundColor Green
    foreach ($manual in $script:ManualSteps) {
        Write-Host ("  - {0}" -f $manual)
    }

    return
}

$tableMetadataMap = @{}
foreach ($table in $spec.tables) {
    if (-not [string]::IsNullOrWhiteSpace($accessToken)) {
        $metadata = Get-TableMetadata -LogicalName $table.logicalName -Token $accessToken
        if ($null -eq $metadata) {
            throw "Required table '$($table.logicalName)' was not found in the target environment. Run create_fsi_intake_dataverse_schema.py first."
        }

        $tableMetadataMap[$table.logicalName] = $metadata
        Write-Info "Verified table '$($table.logicalName)' via Dataverse metadata."
    }
    else {
        if (-not (Test-TableExistsWithPac -LogicalName $table.logicalName)) {
            throw "Required table '$($table.logicalName)' was not found. Run create_fsi_intake_dataverse_schema.py before provisioning the reviewer app."
        }

        Write-Info "Verified table '$($table.logicalName)' via PAC CLI."
    }
}

$solutionRecord = Get-ExistingSolution -Spec $spec -Token $accessToken
if ($null -eq $solutionRecord) {
    if ([string]::IsNullOrWhiteSpace($accessToken)) {
        throw "Solution '$($spec.solutionName)' does not exist and could not be created because no Dataverse access token was available. Provide -AccessToken or DATAVERSE_ACCESS_TOKEN for the first bootstrap run."
    }

    $publisherRecord = Get-ExistingPublisher -Spec $spec -Token $accessToken
    if ($null -eq $publisherRecord) {
        Write-Info "Publisher '$($spec.publisher.uniqueName)' was not found. Creating it now."
        $publisherRecord = New-PublisherRecord -Spec $spec -Token $accessToken
    }
    else {
        Write-Info "Using existing publisher '$($publisherRecord.friendlyname)'."
    }

    Write-Info "Creating solution '$($spec.solutionName)'."
    $solutionRecord = New-SolutionRecord -Spec $spec -Token $accessToken -PublisherId $publisherRecord.publisherid
}
else {
    Write-Info "Using existing solution '$($spec.solutionName)'."
}

foreach ($table in $spec.tables) {
    Add-TableToSolution -TableSpec $table -Spec $spec
}

$appRecord = Get-ExistingAppRecord -Spec $spec -Token $accessToken
if ($null -eq $appRecord) {
    New-AppRecord -Spec $spec
    $appRecord = Get-ExistingAppRecord -Spec $spec -Token $accessToken
}
else {
    Write-Info "Model-driven app '$($spec.appDisplayName)' already exists."
}

if ([string]::IsNullOrWhiteSpace($accessToken)) {
    Add-ManualStep -Message 'Create or confirm the reviewer queue system views and reviewer security roles in the maker portal. Re-run this script with -AccessToken to automate those steps.'
}
else {
    $expandedViews = Expand-ViewDefinitions -Spec $spec
    foreach ($view in $expandedViews) {
        Set-ReviewerView -ViewSpec $view -Spec $spec -Token $accessToken -TableMetadataMap $tableMetadataMap
    }

    $whoAmI = Invoke-DataverseRequest -Method GET -Token $accessToken -RelativeUri 'WhoAmI'
    $businessUnitId = $whoAmI.Body.BusinessUnitId
    if ([string]::IsNullOrWhiteSpace($businessUnitId)) {
        throw 'Unable to resolve the current business unit via WhoAmI.'
    }

    $privilegeMap = Get-CustomPrivilegeMap -Token $accessToken
    $appId = $appRecord.appmoduleid
    $associatedRoleNames = if (-not [string]::IsNullOrWhiteSpace($appId)) { Get-AppRoleNames -AppId $appId -Token $accessToken } else { New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase) }

    foreach ($roleSpec in $spec.securityRoles) {
        $roleRecord = Get-ExistingRoleRecord -RoleSpec $roleSpec -Token $accessToken -BusinessUnitId $businessUnitId
        if ($null -eq $roleRecord) {
            $roleRecord = New-RoleRecord -RoleSpec $roleSpec -Spec $spec -Token $accessToken -BusinessUnitId $businessUnitId
            Write-Info "Created security role '$($roleSpec.name)'."
        }
        else {
            Write-Info "Using existing security role '$($roleSpec.name)'."
        }

        Add-RolePrivileges -RoleSpec $roleSpec -RoleRecord $roleRecord -TableMap $tableMap -PrivilegeMap $privilegeMap -Token $accessToken -BusinessUnitId $businessUnitId

        if (-not [string]::IsNullOrWhiteSpace($appId) -and $roleSpec.appAccess -and -not $associatedRoleNames.Contains($roleSpec.name)) {
            Add-AppRoleAssociation -AppId $appId -RoleRecord $roleRecord -Token $accessToken
            $null = $associatedRoleNames.Add($roleSpec.name)
        }

        if (-not $script:ProvisionedRoles.Contains($roleSpec.name)) {
            $script:ProvisionedRoles.Add($roleSpec.name) | Out-Null
        }
    }
}

foreach ($manualStep in $spec.manualSteps) {
    Add-ManualStep -Message $manualStep.message
}

Invoke-PacCommand -Arguments @('solution', 'publish', '--environment', $EnvironmentUrl) -Description 'Publish customizations'

if ($Export) {
    Initialize-Directory -Path (Split-Path -Path $ExportPath -Parent)
    Invoke-PacCommand -Arguments @(
        'solution',
        'export',
        '--environment', $EnvironmentUrl,
        '--name', $spec.solutionName,
        '--managed',
        '--overwrite',
        '--include', 'general,customization',
        '--path', $ExportPath
    ) -Description 'Export managed reviewer app solution'
}

Write-Host ''
Write-Host '--- Reviewer app provisioning summary ---' -ForegroundColor Green
Write-Host ("Solution       : {0}" -f $spec.solutionName)
Write-Host ("App            : {0}" -f $spec.appDisplayName)
Write-Host ("PAC version    : {0}" -f $pacVersion)
Write-Host ("Views updated  : {0}" -f $script:ProvisionedViews.Count)
Write-Host ("Roles updated  : {0}" -f $script:ProvisionedRoles.Count)
if ($Export) {
    Write-Host ("Managed export : {0}" -f $ExportPath)
}
Write-Host ''
Write-Host 'PAC CLI commands used:' -ForegroundColor Green
foreach ($command in $script:PacCommandsUsed) {
    Write-Host ("  - {0}" -f $command)
}
Write-Host ''
Write-Host 'Manual follow-up:' -ForegroundColor Green
foreach ($manual in $script:ManualSteps) {
    Write-Host ("  - {0}" -f $manual)
}
