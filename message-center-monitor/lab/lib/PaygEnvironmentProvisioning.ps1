#Requires -Version 7.0

Set-StrictMode -Version Latest

function Get-PaygHeaderValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()] $Headers,
        [Parameter(Mandatory)] [string] $Name
    )

    if (-not $Headers) { return $null }

    if ($Headers -is [System.Collections.IDictionary]) {
        foreach ($key in $Headers.Keys) {
            if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                $value = $Headers[$key]
                if ($value -is [array]) { return [string]$value[0] }
                return [string]$value
            }
        }
        return $null
    }

    $property = $Headers.PSObject.Properties |
        Where-Object { [string]::Equals($_.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
    if (-not $property) { return $null }
    $propertyValue = $property.Value
    if ($propertyValue -is [array]) { return [string]$propertyValue[0] }
    return [string]$propertyValue
}

function Get-PaygRetryAfterSeconds {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter()] $Headers,
        [Parameter(Mandatory)] [int] $DefaultSeconds,
        [Parameter(Mandatory)] [int] $MaxSeconds
    )

    $retryAfter = Get-PaygHeaderValue -Headers $Headers -Name 'Retry-After'
    if ([string]::IsNullOrWhiteSpace($retryAfter)) {
        return [Math]::Min($DefaultSeconds, $MaxSeconds)
    }

    $seconds = 0
    if ([int]::TryParse($retryAfter, [ref]$seconds)) {
        return [Math]::Max(0, [Math]::Min($seconds, $MaxSeconds))
    }

    $retryDate = [datetime]::MinValue
    if ([datetime]::TryParse($retryAfter, [ref]$retryDate)) {
        $delta = [int][Math]::Ceiling(($retryDate.ToUniversalTime() - (Get-Date).ToUniversalTime()).TotalSeconds)
        return [Math]::Max(0, [Math]::Min($delta, $MaxSeconds))
    }

    return [Math]::Min($DefaultSeconds, $MaxSeconds)
}

function Get-PaygLifecycleOperationState {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Content
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        throw 'Lifecycle operation response did not include a JSON body with state/status.'
    }

    $body = $Content | ConvertFrom-Json
    if (($body.PSObject.Properties.Name -contains 'state') -and $body.state) {
        if ($body.state -is [string]) { return $body.state }
        if (($body.state.PSObject.Properties.Name -contains 'id') -and $body.state.id) { return $body.state.id }
        if (($body.state.PSObject.Properties.Name -contains 'name') -and $body.state.name) { return $body.state.name }
    }
    if (($body.PSObject.Properties.Name -contains 'status') -and $body.status) {
        if ($body.status -is [string]) { return $body.status }
        if (($body.status.PSObject.Properties.Name -contains 'id') -and $body.status.id) { return $body.status.id }
        if (($body.status.PSObject.Properties.Name -contains 'name') -and $body.status.name) { return $body.status.name }
    }
    if (($body.PSObject.Properties.Name -contains 'properties') -and $body.properties) {
        if (($body.properties.PSObject.Properties.Name -contains 'state') -and $body.properties.state) {
            if ($body.properties.state -is [string]) { return $body.properties.state }
            if (($body.properties.state.PSObject.Properties.Name -contains 'id') -and $body.properties.state.id) {
                return $body.properties.state.id
            }
        }
        if (($body.properties.PSObject.Properties.Name -contains 'status') -and $body.properties.status) {
            if ($body.properties.status -is [string]) { return $body.properties.status }
            if (($body.properties.status.PSObject.Properties.Name -contains 'id') -and $body.properties.status.id) {
                return $body.properties.status.id
            }
        }
    }

    throw 'Lifecycle operation response did not include a recognizable state/status.'
}

function Test-PaygLifecycleTerminalState {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $State
    )

    return $State -in @('Succeeded', 'Failed', 'Canceled', 'Cancelled', 'FailedCreated', 'ValidationFailed')
}

function Invoke-PaygLifecycleOperationPoll {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $OperationUri,
        [Parameter(Mandatory)] [hashtable] $Headers,
        [Parameter()] [int] $TimeoutSeconds = 1200,
        [Parameter()] [int] $PollIntervalSeconds = 15,
        [Parameter()] [int] $MaxRetryAfterSeconds = 60
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        $poll = Invoke-WebRequest -Method GET -Uri $OperationUri -Headers $Headers
        $state = Get-PaygLifecycleOperationState -Content $poll.Content
        Write-LabLog -Level Info -Message "    state=$state http=$($poll.StatusCode)"

        if (Test-PaygLifecycleTerminalState -State $state) {
            if ($state -eq 'Succeeded') { return $state }
            Write-LabLog -Level Error -Message "Env create lifecycle operation ended in state '$state'." -Throw
        }

        if ((Get-Date) -ge $deadline) {
            Write-LabLog -Level Error -Message "Timed out after $TimeoutSeconds seconds waiting for lifecycle operation '$OperationUri' to finish. Last state: '$state'." -Throw
        }

        $delay = Get-PaygRetryAfterSeconds -Headers $poll.Headers -DefaultSeconds $PollIntervalSeconds -MaxSeconds $MaxRetryAfterSeconds
        if ($delay -gt 0) {
            Start-Sleep -Seconds $delay
        }
    }
}

function Test-PaygEnvironmentHasLinkedMetadata {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()] $Environment
    )

    if (-not $Environment -or -not $Environment.properties) { return $false }
    $propertyNames = $Environment.properties.PSObject.Properties.Name
    if ($propertyNames -notcontains 'linkedEnvironmentMetadata') { return $false }
    if (-not $Environment.properties.linkedEnvironmentMetadata) { return $false }
    return $true
}

function Wait-PaygEnvironmentLinkedMetadata {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $DisplayName,
        [Parameter(Mandatory)] [scriptblock] $GetEnvironments,
        [Parameter()] [int] $TimeoutSeconds = 600,
        [Parameter()] [int] $PollIntervalSeconds = 15
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        $all = & $GetEnvironments
        $envObj = @($all.value | Where-Object { $_.properties.displayName -eq $DisplayName }) | Select-Object -First 1
        if (Test-PaygEnvironmentHasLinkedMetadata -Environment $envObj) {
            return $envObj
        }

        if ((Get-Date) -ge $deadline) {
            $envId = if ($envObj) { $envObj.name } else { '<not found>' }
            Write-LabLog -Level Error -Message "Timed out after $TimeoutSeconds seconds waiting for env '$DisplayName' ($envId) to expose linkedEnvironmentMetadata." -Throw
        }

        Write-LabLog -Level Info -Message "  Env shell exists but Dataverse metadata is not ready yet; waiting..."
        if ($PollIntervalSeconds -gt 0) {
            Start-Sleep -Seconds $PollIntervalSeconds
        }
    }
}
