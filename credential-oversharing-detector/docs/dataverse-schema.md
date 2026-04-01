# Dataverse Schema Reference

> Auto-generated from `create_cod_dataverse_schema.py`. Do not edit manually.

## Tables

| SchemaName | Logical Name | Description | Primary Name Attribute |
|---|---|---|---|
| fsi_CredentialScan | fsi_credentialscan | Immutable scan history for credential oversharing detection | fsi_scanid |
| fsi_CredentialViolation | fsi_credentialviolation | Individual credential oversharing violations detected by scans | fsi_violationid |
| fsi_CredentialPolicy | fsi_credentialpolicy | Zone-based credential governance policies | fsi_policyname |
| fsi_CredentialException | fsi_credentialexception | Approved exceptions to credential oversharing policy violations | fsi_exceptionid |
| fsi_AgentConnectorScope | fsi_agentconnectorscope | Per-agent connector scope baselines for credential governance | fsi_scopename |

## Columns

### fsi_CredentialScan (`fsi_credentialscan`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_ScanId | fsi_scanid | String | Yes | Unique scan run identifier |  |
| fsi_EnvironmentId | fsi_environmentid | String | No | Power Platform environment identifier |  |
| fsi_EnvironmentName | fsi_environmentname | String | No | Display name of the environment |  |
| fsi_ScanStartedAt | fsi_scanstartedat | DateTime | No | When the scan started |  |
| fsi_ScanCompletedAt | fsi_scancompletedat | DateTime | No | When the scan completed |  |
| fsi_ScanStatus | fsi_scanstatus | Picklist | Yes | Status of the scan run | **fsi_COD_scanstatus**: `100000000` = Completed, `100000001` = CompletedWithFindings, `100000002` = Failed, `100000003` = InProgress |
| fsi_AgentsScanned | fsi_agentsscanned | Integer | No | Number of agents scanned in this run |  |
| fsi_ViolationsFound | fsi_violationsfound | Integer | No | Number of violations found in this run |  |
| fsi_ConnectorsEvaluated | fsi_connectorsevaluated | Integer | No | Number of connectors evaluated in this run |  |
| fsi_Zone | fsi_zone | Picklist | No | Governance zone for the scanned environment | **fsi_acv_zone**: `100000000` = Unclassified, `100000001` = Zone 1, `100000002` = Zone 2, `100000003` = Zone 3 |
| fsi_ScanConfiguration | fsi_scanconfiguration | Memo | No | JSON snapshot of scan configuration at run time |  |
| fsi_RunBy | fsi_runby | String | No | Identity that initiated the scan run |  |

### fsi_CredentialViolation (`fsi_credentialviolation`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_ViolationId | fsi_violationid | String | Yes | Unique violation identifier |  |
| fsi_AgentId | fsi_agentid | String | Yes | Unique identifier of the agent |  |
| fsi_AgentName | fsi_agentname | String | No | Display name of the agent |  |
| fsi_EnvironmentId | fsi_environmentid | String | No | Power Platform environment identifier |  |
| fsi_EnvironmentName | fsi_environmentname | String | No | Display name of the environment |  |
| fsi_ConnectorId | fsi_connectorid | String | No | Identifier of the connector involved |  |
| fsi_ConnectorName | fsi_connectorname | String | No | Display name of the connector |  |
| fsi_ViolationType | fsi_violationtype | Picklist | Yes | Type of credential oversharing violation detected | **fsi_COD_violationtype**: `100000000` = OverprivilegedConnector, `100000001` = ExcessiveOAuthScope, `100000002` = UnauthorizedServiceAccount, `100000003` = CrossEnvironmentCredential, `100000004` = SharedCredentialMisuse, `100000005` = StaleCredentialAccess |
| fsi_ViolationStatus | fsi_violationstatus | Picklist | Yes | Current status of the violation | **fsi_COD_violationstatus**: `100000000` = Open, `100000001` = Remediated, `100000002` = ExceptionApproved, `100000003` = FalsePositive, `100000004` = UnderReview |
| fsi_Severity | fsi_severity | Picklist | Yes | Severity level of the violation | **fsi_COD_severity**: `100000000` = Critical, `100000001` = High, `100000002` = Medium, `100000003` = Low, `100000004` = Informational |
| fsi_Zone | fsi_zone | Picklist | No | Governance zone of the agent | **fsi_acv_zone**: `100000000` = Unclassified, `100000001` = Zone 1, `100000002` = Zone 2, `100000003` = Zone 3 |
| fsi_DetectedAt | fsi_detectedat | DateTime | Yes | When the violation was detected |  |
| fsi_ResolvedAt | fsi_resolvedat | DateTime | No | When the violation was resolved |  |
| fsi_Description | fsi_description | Memo | No | Detailed description of the violation |  |
| fsi_ApprovedScopes | fsi_approvedscopes | Memo | No | JSON array of approved OAuth scopes |  |
| fsi_ActualScopes | fsi_actualscopes | Memo | No | JSON array of actual OAuth scopes observed |  |
| fsi_EvidenceJson | fsi_evidencejson | Memo | No | Full evidence payload for the violation |  |
| fsi_RemediationNotes | fsi_remediationnotes | Memo | No | Notes on remediation actions taken |  |
| fsi_RelatedExceptionId | fsi_relatedexceptionid | Lookup | No | Optional link to the exception record for this violation |  |

### fsi_CredentialPolicy (`fsi_credentialpolicy`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_PolicyName | fsi_policyname | String | Yes | Credential policy name |  |
| fsi_Zone | fsi_zone | Picklist | Yes | Governance zone this policy applies to | **fsi_acv_zone**: `100000000` = Unclassified, `100000001` = Zone 1, `100000002` = Zone 2, `100000003` = Zone 3 |
| fsi_MaxOAuthScopes | fsi_maxoauthscopes | Integer | No | Maximum number of OAuth scopes allowed per connector |  |
| fsi_RequireServicePrincipal | fsi_requireserviceprincipal | Boolean | No | Whether service principal authentication is required | `1` = Yes, `0` = No |
| fsi_AllowCrossEnvironment | fsi_allowcrossenvironment | Boolean | No | Whether cross-environment credential use is allowed | `1` = Yes, `0` = No |
| fsi_AllowSharedCredentials | fsi_allowsharedcredentials | Boolean | No | Whether shared credential use across agents is allowed | `1` = Yes, `0` = No |
| fsi_MaxCredentialAgeDays | fsi_maxcredentialagedays | Integer | No | Maximum allowed age of credentials in days |  |
| fsi_RequireCredentialRotation | fsi_requirecredentialrotation | Boolean | No | Whether periodic credential rotation is required | `1` = Yes, `0` = No |
| fsi_AutoRemediateEnabled | fsi_autoremediateenabled | Boolean | No | Whether automatic remediation is enabled for this policy | `1` = Yes, `0` = No |
| fsi_PolicyConfiguration | fsi_policyconfiguration | Memo | No | JSON with additional policy configuration details |  |
| fsi_RegulatoryContext | fsi_regulatorycontext | Memo | No | Applicable regulatory context for this policy |  |
| fsi_IsActive | fsi_isactive | Boolean | Yes | Whether this policy is currently active | `1` = Yes, `0` = No |

### fsi_CredentialException (`fsi_credentialexception`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_ExceptionId | fsi_exceptionid | String | Yes | Unique exception identifier |  |
| fsi_AgentId | fsi_agentid | String | Yes | Unique identifier of the agent |  |
| fsi_AgentName | fsi_agentname | String | No | Display name of the agent |  |
| fsi_ConnectorId | fsi_connectorid | String | No | Identifier of the connector involved |  |
| fsi_ExceptionStatus | fsi_exceptionstatus | Picklist | Yes | Current status of the exception request | **fsi_COD_exceptionstatus**: `100000000` = Pending, `100000001` = Approved, `100000002` = Rejected, `100000003` = Expired, `100000004` = Revoked |
| fsi_Justification | fsi_justification | Memo | Yes | Business justification for the exception |  |
| fsi_ApprovedBy | fsi_approvedby | String | No | UPN of the person who approved this exception |  |
| fsi_ApprovedAt | fsi_approvedat | DateTime | No | When the exception was approved |  |
| fsi_ExpiresAt | fsi_expiresat | DateTime | No | When the exception expires |  |
| fsi_Zone | fsi_zone | Picklist | No | Governance zone for this exception | **fsi_acv_zone**: `100000000` = Unclassified, `100000001` = Zone 1, `100000002` = Zone 2, `100000003` = Zone 3 |
| fsi_ApprovedScopes | fsi_approvedscopes | Memo | No | JSON array of approved OAuth scopes for this exception |  |
| fsi_ReviewNotes | fsi_reviewnotes | Memo | No | Notes from exception review process |  |

### fsi_AgentConnectorScope (`fsi_agentconnectorscope`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_ScopeName | fsi_scopename | String | Yes | Agent connector scope baseline name |  |
| fsi_AgentId | fsi_agentid | String | Yes | Unique identifier of the agent |  |
| fsi_AgentName | fsi_agentname | String | No | Display name of the agent |  |
| fsi_EnvironmentId | fsi_environmentid | String | No | Power Platform environment identifier |  |
| fsi_ConnectorId | fsi_connectorid | String | No | Identifier of the connector |  |
| fsi_ConnectorName | fsi_connectorname | String | No | Display name of the connector |  |
| fsi_OAuthScopes | fsi_oauthscopes | Memo | No | JSON array of OAuth scopes for this connector |  |
| fsi_ServicePrincipalId | fsi_serviceprincipalid | String | No | Entra ID service principal object ID |  |
| fsi_PermissionLevel | fsi_permissionlevel | String | No | Permission level granted to the connector |  |
| fsi_CapturedAt | fsi_capturedat | DateTime | No | When this scope baseline was captured |  |
| fsi_IsActive | fsi_isactive | Boolean | Yes | Whether this scope baseline is currently active | `1` = Yes, `0` = No |
| fsi_Zone | fsi_zone | Picklist | No | Governance zone for this agent connector scope | **fsi_acv_zone**: `100000000` = Unclassified, `100000001` = Zone 1, `100000002` = Zone 2, `100000003` = Zone 3 |
| fsi_ScopeConfiguration | fsi_scopeconfiguration | Memo | No | JSON with additional scope configuration details |  |

## Option Sets

### Shared Option Sets

#### fsi_acv_zone

Governance zone classification

| Value | Label |
|---|---|
| 100000000 | Unclassified |
| 100000001 | Zone 1 |
| 100000002 | Zone 2 |
| 100000003 | Zone 3 |

### COD Option Sets

#### fsi_COD_violationtype

Type of credential oversharing violation detected

| Value | Label |
|---|---|
| 100000000 | OverprivilegedConnector |
| 100000001 | ExcessiveOAuthScope |
| 100000002 | UnauthorizedServiceAccount |
| 100000003 | CrossEnvironmentCredential |
| 100000004 | SharedCredentialMisuse |
| 100000005 | StaleCredentialAccess |

#### fsi_COD_violationstatus

Current status of a credential oversharing violation

| Value | Label |
|---|---|
| 100000000 | Open |
| 100000001 | Remediated |
| 100000002 | ExceptionApproved |
| 100000003 | FalsePositive |
| 100000004 | UnderReview |

#### fsi_COD_severity

Severity level of credential oversharing violation

| Value | Label |
|---|---|
| 100000000 | Critical |
| 100000001 | High |
| 100000002 | Medium |
| 100000003 | Low |
| 100000004 | Informational |

#### fsi_COD_scanstatus

Status of a credential oversharing scan run

| Value | Label |
|---|---|
| 100000000 | Completed |
| 100000001 | CompletedWithFindings |
| 100000002 | Failed |
| 100000003 | InProgress |

#### fsi_COD_exceptionstatus

Status of a credential exception request

| Value | Label |
|---|---|
| 100000000 | Pending |
| 100000001 | Approved |
| 100000002 | Rejected |
| 100000003 | Expired |
| 100000004 | Revoked |

## Relationships

| SchemaName | Referenced Entity | Referencing Entity | Lookup Column |
|---|---|---|---|
| fsi_CredentialViolation_CredentialException | fsi_credentialexception | fsi_credentialviolation | fsi_RelatedExceptionId |
