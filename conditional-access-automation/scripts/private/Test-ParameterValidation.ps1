<#
.SYNOPSIS
    Parameter validation helpers for Conditional Access Automation scripts.

.DESCRIPTION
    Provides validation functions for common CAA script parameters including
    configuration files, template sets, break-glass accounts, and Graph connections.

.NOTES
    File: Test-ParameterValidation.ps1
    Version: 1.0.0
#>

function Test-CAAConfigPath {
    <#
    .SYNOPSIS
        Validates that a configuration JSON file exists and contains required keys.

    .DESCRIPTION
        Checks that the specified path points to a valid JSON file containing the
        required top-level keys: tenantId, groups, breakGlassAccounts, applications.
        Returns $true on success or throws a descriptive error.

    .PARAMETER Path
        Full path to the configuration JSON file.

    .EXAMPLE
        Test-CAAConfigPath -Path './config/ca-config.json'

        Validates the config file exists and has all required keys.

    .OUTPUTS
        System.Boolean
        Returns $true if validation passes. Throws on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Configuration file not found: $Path"
    }

    try {
        $config = Get-Content -Path $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Configuration file is not valid JSON: $Path — $($_.Exception.Message)"
    }

    $requiredKeys = @('tenantId', 'groups', 'breakGlassAccounts', 'applications')
    $missingKeys = @()

    foreach ($key in $requiredKeys) {
        if (-not ($config.PSObject.Properties.Name -contains $key)) {
            $missingKeys += $key
        }
    }

    if ($missingKeys.Count -gt 0) {
        throw "Configuration file missing required keys: $($missingKeys -join ', '). File: $Path"
    }

    Write-Verbose "Configuration file validated: $Path"
    return $true
}

function Test-CAATemplateSet {
    <#
    .SYNOPSIS
        Validates that a template set name is a recognized value.

    .DESCRIPTION
        Checks that the provided template set name is one of the valid options:
        All, Zone1, Zone2, Zone3. Returns $true on success or throws.

    .PARAMETER TemplateSet
        The template set name to validate.

    .EXAMPLE
        Test-CAATemplateSet -TemplateSet 'Zone3'

        Returns $true.

    .EXAMPLE
        Test-CAATemplateSet -TemplateSet 'InvalidName'

        Throws an error with valid options listed.

    .OUTPUTS
        System.Boolean
        Returns $true if validation passes. Throws on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TemplateSet
    )

    $validSets = @('All', 'Zone1', 'Zone2', 'Zone3')

    if ($TemplateSet -notin $validSets) {
        throw "Invalid template set: '$TemplateSet'. Valid options: $($validSets -join ', ')"
    }

    Write-Verbose "Template set validated: $TemplateSet"
    return $true
}

function Test-CAABreakGlassAccounts {
    <#
    .SYNOPSIS
        Validates that break-glass account identifiers are valid GUIDs.

    .DESCRIPTION
        Checks each provided account ID to confirm it is a well-formed GUID.
        Returns $true if all IDs are valid, or throws with details of invalid entries.

    .PARAMETER AccountIds
        Array of break-glass account GUID strings to validate.

    .EXAMPLE
        Test-CAABreakGlassAccounts -AccountIds @('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002')

        Returns $true — both are valid GUIDs.

    .EXAMPLE
        Test-CAABreakGlassAccounts -AccountIds @('not-a-guid')

        Throws an error identifying the invalid entry.

    .OUTPUTS
        System.Boolean
        Returns $true if all account IDs are valid GUIDs. Throws on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$AccountIds
    )

    $invalidIds = @()

    foreach ($id in $AccountIds) {
        $parsed = [guid]::Empty
        if (-not [guid]::TryParse($id, [ref]$parsed)) {
            $invalidIds += $id
        }
    }

    if ($invalidIds.Count -gt 0) {
        throw "Invalid break-glass account GUIDs: $($invalidIds -join ', '). Each account ID must be a valid GUID."
    }

    Write-Verbose "Break-glass accounts validated: $($AccountIds.Count) account(s)"
    return $true
}

function Test-CAAGraphConnection {
    <#
    .SYNOPSIS
        Verifies that an active Microsoft Graph session exists with required scopes.

    .DESCRIPTION
        Checks for an active Graph context using Get-MgContext and validates that the
        session includes the required permission scopes. Returns $true on success or
        throws with details about missing requirements.

    .PARAMETER RequiredScopes
        Optional array of Graph permission scopes to verify. Defaults to
        Policy.Read.All and Application.Read.All.

    .EXAMPLE
        Test-CAAGraphConnection

        Verifies a Graph session exists with default required scopes.

    .EXAMPLE
        Test-CAAGraphConnection -RequiredScopes @('Policy.ReadWrite.ConditionalAccess')

        Verifies a Graph session exists with the specified scope.

    .OUTPUTS
        System.Boolean
        Returns $true if Graph session exists with required scopes. Throws on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$RequiredScopes = @(
            'Policy.Read.All',
            'Application.Read.All'
        )
    )

    $ErrorActionPreference = 'Stop'

    try {
        $context = Get-MgContext
    } catch {
        throw "No active Microsoft Graph session. Run Connect-CAAGraphSession first."
    }

    if (-not $context) {
        throw "No active Microsoft Graph session. Run Connect-CAAGraphSession first."
    }

    Write-Verbose "Graph session active — Tenant: $($context.TenantId), Account: $($context.Account)"

    $existingScopes = $context.Scopes
    $missingScopes = $RequiredScopes | Where-Object { $_ -notin $existingScopes }

    if ($missingScopes) {
        throw "Graph session missing required scopes: $($missingScopes -join ', '). Reconnect with the required scopes."
    }

    Write-Verbose "All required scopes present: $($RequiredScopes -join ', ')"
    return $true
}
