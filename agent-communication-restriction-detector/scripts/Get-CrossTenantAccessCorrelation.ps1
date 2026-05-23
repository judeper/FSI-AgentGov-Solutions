<#
.SYNOPSIS
    Correlates cross-tenant agent communication findings with Microsoft Entra ID
    cross-tenant access policies.

.DESCRIPTION
    Retrieves cross-tenant access policy configuration from Microsoft Graph and
    cross-references with detected agent communication patterns from ACRD scan
    results. Flags agents communicating with tenants outside the allowed
    cross-tenant access policy.

    Workflow:
    1. Reads cross-tenant access policy from Graph (crossTenantAccessPolicy)
    2. Reads partner-specific configurations (crossTenantAccessPolicy/partners)
    3. Queries ACRD violations with type CROSS_TENANT_VIOLATION from Dataverse
    4. Correlates: flags agents communicating with tenants not in the partner list
    5. Emits enriched violation objects with Entra policy context

    This script supports compliance with FINRA 3110 and GLBA 501(b) by providing
    evidence that cross-tenant agent communication aligns with organizational
    Entra ID trust boundaries.

.PARAMETER DataverseUrl
    Dataverse environment URL (e.g., https://org.crm.dynamics.com).

.PARAMETER OutputFormat
    Output format: Table (default), Json, or Object.

.PARAMETER WhatIf
    Preview mode — shows correlation results without persisting to Dataverse.

.NOTES
    File: Get-CrossTenantAccessCorrelation.ps1
    Version: 1.2.0
    Solution: Agent Communication Restriction Detector (ACRD)
    Control: 2.17 (Multi-Agent Orchestration Limits)
    Requires: Microsoft.Graph.Identity.SignIns module

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns

function Get-CrossTenantAccessCorrelation {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        # Accept commercial (.crm[N].dynamics.com), GCC High (.crm9.dynamics.com),
        # DoD (.crm.microsoftdynamics.us), and Germany (.crm.microsoftdynamics.de)
        # sovereign cloud URLs. (council review M-4)
        [ValidatePattern('^https://[a-zA-Z0-9\-]+\.(crm[0-9]*\.dynamics\.com|crm\.microsoftdynamics\.(us|de))/?$')]
        [string]$DataverseUrl,

        [ValidateSet('Table', 'Json', 'Object')]
        [string]$OutputFormat = 'Table',

        [switch]$IncludeCompliant
    )

    begin {
        $ErrorActionPreference = 'Stop'

        # Dot-source private helpers if available
        $privatePath = Join-Path $PSScriptRoot 'private'
        if (Test-Path (Join-Path $privatePath 'Connect-EnvironmentDataverse.ps1')) {
            . (Join-Path $privatePath 'Connect-EnvironmentDataverse.ps1')
        }

        Write-Verbose "Retrieving cross-tenant access policy from Microsoft Graph..."
    }

    process {
        # ---------------------------------------------------------------
        # Step 1: Retrieve default cross-tenant access policy
        # ---------------------------------------------------------------
        $defaultPolicy = Get-MgPolicyCrossTenantAccessPolicyDefault -ErrorAction Stop
        Write-Verbose "Default inbound trust: $($defaultPolicy.InboundTrust | ConvertTo-Json -Compress)"

        # ---------------------------------------------------------------
        # Step 2: Retrieve partner-specific configurations
        # ---------------------------------------------------------------
        $partners = Get-MgPolicyCrossTenantAccessPolicyPartner -All -ErrorAction Stop
        $allowedTenantIds = @{}
        foreach ($partner in $partners) {
            $tenantId = $partner.TenantId
            $allowedTenantIds[$tenantId] = @{
                TenantId            = $tenantId
                B2BCollaborationInbound  = $partner.B2BCollaborationInbound.IsServiceProvider
                B2BDirectConnectInbound  = $partner.B2BDirectConnectInbound.IsServiceProvider
                InboundTrustCompliant    = $null -ne $partner.InboundTrust
                AutomaticUserConsent     = $partner.AutomaticUserConsentSettings.InboundAllowed
            }
        }
        Write-Verbose "Found $($allowedTenantIds.Count) partner tenant configuration(s)."

        # ---------------------------------------------------------------
        # Step 3: Query ACRD cross-tenant violations from Dataverse
        # ---------------------------------------------------------------
        # Graph and Dataverse require tokens with different audiences. Reusing the
        # Microsoft Graph token from (Get-MgContext).AccessToken (which previously
        # produced 401 Unauthorized on every Dataverse call) is incorrect. Acquire
        # a Dataverse-audience token via the private helper, which calls
        # Az.Accounts Get-AzAccessToken with -ResourceUrl set to the env URL.
        # (council review C-1)
        $apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
        $dataverseToken = & (Join-Path $privatePath 'Connect-EnvironmentDataverse.ps1') `
            -DataverseUrl $DataverseUrl
        $headers = @{
            'Authorization' = "Bearer $dataverseToken"
            'Accept'        = 'application/json'
            'OData-Version' = '4.0'
        }

        $filter = "fsi_violationtype eq 100000001"  # CROSS_TENANT_VIOLATION
        $select = "fsi_agentcommviolationid,fsi_name,fsi_callingagentid,fsi_callingagentname,fsi_calledenvironmentid,fsi_calledagentid,fsi_calledagentname,fsi_severity,fsi_violationstatus,createdon"
        $violationsUri = "$apiBase/fsi_agentcommviolations?`$filter=$filter&`$select=$select&`$orderby=createdon desc&`$top=500"

        $violationsResp = Invoke-RestMethod -Uri $violationsUri -Headers $headers -Method Get -ErrorAction Stop
        $violations = $violationsResp.value
        Write-Verbose "Retrieved $($violations.Count) cross-tenant violation(s) from Dataverse."

        # ---------------------------------------------------------------
        # Step 4: Correlate violations with Entra policy
        # ---------------------------------------------------------------
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($violation in $violations) {
            # Extract target tenant ID from called environment ID or agent metadata
            $targetTenantId = $null
            if ($violation.fsi_calledenvironmentid -match '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}') {
                $targetTenantId = $Matches[0]
            }

            $isAllowedPartner = $false
            $partnerConfig = $null
            if ($targetTenantId -and $allowedTenantIds.ContainsKey($targetTenantId)) {
                $isAllowedPartner = $true
                $partnerConfig = $allowedTenantIds[$targetTenantId]
            }

            $correlationResult = [PSCustomObject]@{
                ViolationId          = $violation.fsi_agentcommviolationid
                ViolationName        = $violation.fsi_name
                CallingAgentId       = $violation.fsi_callingagentid
                CallingAgentName     = $violation.fsi_callingagentname
                CalledAgentId        = $violation.fsi_calledagentid
                CalledAgentName      = $violation.fsi_calledagentname
                TargetTenantId       = $targetTenantId
                IsAllowedPartner     = $isAllowedPartner
                HasInboundTrust      = if ($partnerConfig) { $partnerConfig.InboundTrustCompliant } else { $false }
                B2BDirectConnect     = if ($partnerConfig) { $partnerConfig.B2BDirectConnectInbound } else { $false }
                PolicyAction         = if ($isAllowedPartner) { 'AllowedByPartnerPolicy' } else { 'BlockedByPolicy' }
                RiskLevel            = if (-not $isAllowedPartner) { 'Critical' } elseif (-not $partnerConfig.InboundTrustCompliant) { 'High' } else { 'Low' }
                CreatedOn            = $violation.createdon
                RegulatoryContext    = 'FINRA 3110, GLBA 501(b)'
            }

            if ($correlationResult.PolicyAction -eq 'BlockedByPolicy' -or $IncludeCompliant) {
                $results.Add($correlationResult)
            }
        }

        # ---------------------------------------------------------------
        # Step 5: Output
        # ---------------------------------------------------------------
        switch ($OutputFormat) {
            'Json' {
                $output = @{
                    Timestamp          = (Get-Date -Format 'o')
                    TotalPartners      = $allowedTenantIds.Count
                    TotalViolations    = $violations.Count
                    PolicyViolations   = ($results | Where-Object PolicyAction -eq 'BlockedByPolicy').Count
                    Results            = $results
                }
                $output | ConvertTo-Json -Depth 10
            }
            'Object' {
                $results
            }
            default {
                if ($results.Count -eq 0) {
                    Write-Host "`nNo cross-tenant policy violations found." -ForegroundColor Green
                } else {
                    Write-Host "`nCross-Tenant Access Policy Correlation Results:" -ForegroundColor Cyan
                    Write-Host ("=" * 70) -ForegroundColor Cyan
                    $results | Format-Table -Property CallingAgentName, CalledAgentName, TargetTenantId, PolicyAction, RiskLevel -AutoSize
                }
            }
        }
    }
}
