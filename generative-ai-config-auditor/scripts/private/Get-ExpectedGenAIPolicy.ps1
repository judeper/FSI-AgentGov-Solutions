<#
.SYNOPSIS
    Retrieves expected generative AI policy and severity classification for a zone.

.DESCRIPTION
    Zone-to-policy reference for generative AI features. Returns the expected
    configuration for each governance zone, including per-feature policies,
    violation severities, and regulatory context.

    Zone policies:
    - Zone1: AOAI allowed, generative orchestration allowed, gen answers allowed,
      AOAI whitelist advisory (Warning severity), Allow ungrounded responses allowed,
      Work IQ (semantic search) allowed
    - Zone2: AOAI approved connections only, gen orch allowed with approval,
      gen answers allowed, AOAI whitelist enforced (High severity), Allow ungrounded
      responses requires approval, Work IQ (semantic search) allowed with logging
    - Zone3: AOAI explicit allowlist only, gen orch restricted (classic unless
      exception), gen answers explicit allowlist per topic, AOAI whitelist
      enforced (Critical severity), Allow ungrounded responses disabled, Work IQ
      (semantic search) requires approval

.PARAMETER Zone
    The governance zone: Zone1, Zone2, Zone3, or Unknown.

.OUTPUTS
    PSCustomObject with per-feature policies, violation severities, and regulatory context.

.EXAMPLE
    $policy = & ./Get-ExpectedGenAIPolicy.ps1 -Zone "Zone3"
    $policy.AoaiPolicy                  # "ExplicitAllowlistOnly"
    $policy.AoaiViolationSeverity       # "Critical"

.EXAMPLE
    $policy = & ./Get-ExpectedGenAIPolicy.ps1 -Zone "Zone1"
    $policy.OrchestrationPolicy         # "Allowed"
    $policy.WhitelistEnforcement        # "Advisory"

.NOTES
    File: Get-ExpectedGenAIPolicy.ps1
    Version: 1.0.0
    Requires: PowerShell 7.0+
#>

#Requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Zone1', 'Zone2', 'Zone3', 'Unknown')]
    [string]$Zone
)

# Zone policy definitions
$zonePolicies = @{
    'Zone1' = [PSCustomObject]@{
        Zone                             = 'Zone1'
        # Feature policies
        AoaiPolicy                       = 'Allowed'
        OrchestrationPolicy              = 'Allowed'
        GenAnswersPolicy                 = 'Allowed'
        WhitelistEnforcement             = 'Advisory'
        ModelKnowledgePolicy             = 'Allowed'
        SemanticSearchPolicy             = 'Allowed'
        AoaiAllowed                      = $true
        AllowedOrchestrationModes        = @('Classic', 'Generative')
        GenerativeAnswersAllowed         = $true
        # Violation severities per feature type
        AoaiViolationSeverity            = 'Warning'
        OrchestrationViolationSeverity   = 'Warning'
        GenAnswersViolationSeverity      = 'Warning'
        WhitelistViolationSeverity       = 'Warning'
        ModelKnowledgeViolationSeverity  = 'Warning'
        SemanticSearchViolationSeverity  = 'Warning'
        # Regulatory context
        RegulatoryContext                = 'Zone 1 (Personal Productivity) - Advisory monitoring, minimal restrictions on generative AI features'
    }

    'Zone2' = [PSCustomObject]@{
        Zone                             = 'Zone2'
        # Feature policies
        AoaiPolicy                       = 'ApprovedConnectionsOnly'
        OrchestrationPolicy              = 'AllowedWithApproval'
        GenAnswersPolicy                 = 'Allowed'
        WhitelistEnforcement             = 'Enforced'
        ModelKnowledgePolicy             = 'RequiresApproval'
        SemanticSearchPolicy             = 'AllowedWithLogging'
        AoaiAllowed                      = $true
        AllowedOrchestrationModes        = @('Classic', 'Generative')
        GenerativeAnswersAllowed         = $true
        # Violation severities per feature type
        AoaiViolationSeverity            = 'High'
        OrchestrationViolationSeverity   = 'Medium'
        GenAnswersViolationSeverity      = 'Medium'
        WhitelistViolationSeverity       = 'High'
        ModelKnowledgeViolationSeverity  = 'Medium'
        SemanticSearchViolationSeverity  = 'Medium'
        # Regulatory context
        RegulatoryContext                = 'Zone 2 (Team/Collaborative) - Approved connections required, generative orchestration needs approval'
    }

    'Zone3' = [PSCustomObject]@{
        Zone                             = 'Zone3'
        # Feature policies
        AoaiPolicy                       = 'ExplicitAllowlistOnly'
        OrchestrationPolicy              = 'Restricted'
        GenAnswersPolicy                 = 'ExplicitAllowlistPerTopic'
        WhitelistEnforcement             = 'Enforced'
        ModelKnowledgePolicy             = 'Disabled'
        SemanticSearchPolicy             = 'RequiresApproval'
        AoaiAllowed                      = $true
        AllowedOrchestrationModes        = @('Classic')
        GenerativeAnswersAllowed         = $false
        # Violation severities per feature type
        AoaiViolationSeverity            = 'Critical'
        OrchestrationViolationSeverity   = 'Critical'
        GenAnswersViolationSeverity      = 'High'
        WhitelistViolationSeverity       = 'Critical'
        ModelKnowledgeViolationSeverity  = 'Critical'
        SemanticSearchViolationSeverity  = 'High'
        # Regulatory context
        RegulatoryContext                = 'Zone 3 (Enterprise/Regulated) - Explicit allowlist required, classic orchestration unless exception granted'
    }

    'Unknown' = [PSCustomObject]@{
        Zone                             = 'Unknown'
        # Feature policies — treat as restrictive until classified
        AoaiPolicy                       = 'RequiresClassification'
        OrchestrationPolicy              = 'RequiresClassification'
        GenAnswersPolicy                 = 'RequiresClassification'
        WhitelistEnforcement             = 'Advisory'
        ModelKnowledgePolicy             = 'RequiresClassification'
        SemanticSearchPolicy             = 'RequiresClassification'
        AoaiAllowed                      = $false
        AllowedOrchestrationModes        = @('Classic')
        GenerativeAnswersAllowed         = $false
        # Violation severities per feature type
        AoaiViolationSeverity            = 'Warning'
        OrchestrationViolationSeverity   = 'Warning'
        GenAnswersViolationSeverity      = 'Warning'
        WhitelistViolationSeverity       = 'Warning'
        ModelKnowledgeViolationSeverity  = 'Warning'
        SemanticSearchViolationSeverity  = 'Warning'
        # Regulatory context
        RegulatoryContext                = 'Unclassified environment - Zone classification required before policy enforcement'
    }
}

# Return the policy for the requested zone
$policy = $zonePolicies[$Zone]

if (-not $policy) {
    throw "Zone policy not found for: $Zone"
}

return $policy
