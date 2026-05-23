#Requires -Version 7.0

<#
.SYNOPSIS
    Deprecated compatibility stub for the legacy UASD sharing audit script.

.DESCRIPTION
    This script is intentionally disabled. Earlier versions depended on
    non-published chatbot admin cmdlets and older sharing abstractions that no
    longer match Microsoft Learn's Copilot Studio bot table reference.

    Use Test-AgentSharingCompliance.ps1 instead. It queries the Dataverse
    bot table through the Web API and evaluates accesscontrolpolicy,
    authorizedsecuritygroupids, authenticationmode, and authenticationtrigger.

.PARAMETER HomeTenantId
    Retained for command-line compatibility. Ignored.

.PARAMETER OutputFormat
    Retained for command-line compatibility. Ignored.

.PARAMETER OutputPath
    Retained for command-line compatibility. Ignored.

.PARAMETER IncludeEvidence
    Retained for command-line compatibility. Ignored.

.PARAMETER MaxIndividualShares
    Retained for command-line compatibility. Ignored.

.PARAMETER ApprovedGroupsPath
    Retained for command-line compatibility. Ignored.

.EXAMPLE
    .\Invoke-SharingAudit.ps1

    Exits with code 2 and directs the operator to Test-AgentSharingCompliance.ps1.

.NOTES
    FSI Agent Governance Framework - Unrestricted Agent Sharing Detector
#>

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = 'PSScriptAnalyzer honors this rule at script or function scope; flagged compatibility parameters below include individual justifications.'
)]
param(
    [Parameter()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Deprecated wrapper retains historical CLI parameters so existing callers receive the documented deprecation error; intentionally unused.'
    )]
    [string]$HomeTenantId,

    [Parameter()]
    [ValidateSet("JSON", "CSV")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Deprecated wrapper retains historical CLI parameters so existing callers receive the documented deprecation error; intentionally unused.'
    )]
    [string]$OutputFormat = "JSON",

    [Parameter()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Deprecated wrapper retains historical CLI parameters so existing callers receive the documented deprecation error; intentionally unused.'
    )]
    [string]$OutputPath = ".\uasd-sharing-audit.json",

    [Parameter()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Deprecated wrapper retains historical CLI parameters so existing callers receive the documented deprecation error; intentionally unused.'
    )]
    [switch]$IncludeEvidence,

    [Parameter()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Deprecated wrapper retains historical CLI parameters so existing callers receive the documented deprecation error; intentionally unused.'
    )]
    [int]$MaxIndividualShares = 5,

    [Parameter()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Deprecated wrapper retains historical CLI parameters so existing callers receive the documented deprecation error; intentionally unused.'
    )]
    [string]$ApprovedGroupsPath
)

$ErrorActionPreference = "Stop"

Write-Error "Invoke-SharingAudit.ps1 is deprecated in UASD v2.0.1. Use Test-AgentSharingCompliance.ps1, which queries the Dataverse bot table and supports the current Copilot Studio sharing fields."
exit 2
