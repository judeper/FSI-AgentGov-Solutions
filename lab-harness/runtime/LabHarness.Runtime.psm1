Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LabValidationAdapterCatalog {
    [CmdletBinding()]
    param()

    @{
        'runtime.powershell.pester' = @{
            channel           = 'runtime'
            requiredFields    = @('testPaths')
            allowedProperties = @('id', 'channel', 'adapter', 'description', 'testPaths')
        }
        'runtime.python.pytest'     = @{
            channel           = 'runtime'
            requiredFields    = @('testPaths')
            allowedProperties = @('id', 'channel', 'adapter', 'description', 'testPaths')
        }
        'runtime.powershell.script' = @{
            channel           = 'runtime'
            requiredFields    = @('scriptPath')
            allowedProperties = @('id', 'channel', 'adapter', 'description', 'scriptPath', 'parameters')
        }
        'playwright.portal-smoke'   = @{
            channel           = 'playwright'
            requiredFields    = @('packagePath', 'specPath')
            allowedProperties = @('id', 'channel', 'adapter', 'description', 'packagePath', 'specPath')
        }
    }
}

function Get-LabHarnessRepoRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$StartPath
    )

    $current = [System.IO.Path]::GetFullPath($StartPath)
    while ($true) {
        if (Test-Path -LiteralPath (Join-Path -Path $current -ChildPath '.git')) {
            return $current
        }

        $parent = [System.IO.Directory]::GetParent($current)
        if ($null -eq $parent) {
            throw [System.IO.InvalidDataException]::new("Could not locate repository root from '$StartPath'.")
        }

        $current = $parent.FullName
    }
}

function Resolve-LabConstrainedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$AllowedRoots,

        [Parameter()]
        [switch]$MustExist
    )

    $candidate = $Path
    if (-not [System.IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path -Path $BasePath -ChildPath $candidate
    }

    $resolvedPath = [System.IO.Path]::GetFullPath($candidate)
    $isAllowed = $false

    foreach ($root in $AllowedRoots) {
        $resolvedRoot = [System.IO.Path]::GetFullPath($root)
        $rootWithSeparator = $resolvedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if ($resolvedPath.Equals($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            $resolvedPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
            $isAllowed = $true
            break
        }
    }

    if (-not $isAllowed) {
        throw [System.UnauthorizedAccessException]::new("Path '$Path' resolves outside allowed roots.")
    }

    if ($MustExist -and -not (Test-Path -LiteralPath $resolvedPath)) {
        throw [System.IO.FileNotFoundException]::new("Path '$resolvedPath' does not exist.")
    }

    return $resolvedPath
}

function Assert-LabValidationStepModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Step,

        [Parameter(Mandatory)]
        [hashtable]$Catalog
    )

    if (-not $Catalog.ContainsKey($Step.adapter)) {
        throw [System.IO.InvalidDataException]::new("Adapter '$($Step.adapter)' is not in the allow-list.")
    }

    $adapterConfig = $Catalog[$Step.adapter]
    if ($Step.channel -ne $adapterConfig.channel) {
        throw [System.IO.InvalidDataException]::new("Step '$($Step.id)' channel '$($Step.channel)' does not match adapter '$($Step.adapter)'.")
    }

    $stepProperties = @($Step.Keys)
    foreach ($requiredField in $adapterConfig.requiredFields) {
        if (-not $Step.ContainsKey($requiredField)) {
            throw [System.IO.InvalidDataException]::new("Step '$($Step.id)' missing required field '$requiredField'.")
        }
    }

    foreach ($property in $stepProperties) {
        if ($property -notin $adapterConfig.allowedProperties) {
            throw [System.IO.InvalidDataException]::new("Step '$($Step.id)' contains unsupported property '$property'.")
        }
    }
}

function Test-LabValidationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Solution,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PlanPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EvidenceRoot
    )

    $schemaRoot = Join-Path -Path $RepoRoot -ChildPath 'lab-harness\schema'
    $planSchemaPath = Join-Path -Path $schemaRoot -ChildPath 'solution-validation-plan.schema.json'
    $ownershipSchemaPath = Join-Path -Path $schemaRoot -ChildPath 'ownership-cleanup.schema.json'

    $resolvedPlanPath = Resolve-LabConstrainedPath -Path $PlanPath -BasePath $RepoRoot -AllowedRoots @($RepoRoot, $EvidenceRoot) -MustExist
    $planJson = Get-Content -LiteralPath $resolvedPlanPath -Raw

    if (-not ($planJson | Test-Json -SchemaFile $planSchemaPath)) {
        throw [System.IO.InvalidDataException]::new("Plan file '$resolvedPlanPath' failed schema validation.")
    }

    $plan = ConvertFrom-Json -InputObject $planJson -AsHashtable
    if ($plan.solution -ne $Solution) {
        throw [System.IO.InvalidDataException]::new("Plan solution '$($plan.solution)' does not match requested solution '$Solution'.")
    }

    $resolvedOwnershipPath = Resolve-LabConstrainedPath -Path $plan.ownershipManifestPath -BasePath $RepoRoot -AllowedRoots @($RepoRoot, $EvidenceRoot) -MustExist
    $ownershipJson = Get-Content -LiteralPath $resolvedOwnershipPath -Raw
    if (-not ($ownershipJson | Test-Json -SchemaFile $ownershipSchemaPath)) {
        throw [System.IO.InvalidDataException]::new("Ownership manifest '$resolvedOwnershipPath' failed schema validation.")
    }

    $ownership = ConvertFrom-Json -InputObject $ownershipJson -AsHashtable
    if ($ownership.solution -ne $Solution) {
        throw [System.IO.InvalidDataException]::new("Ownership manifest solution '$($ownership.solution)' does not match requested solution '$Solution'.")
    }

    $catalog = Get-LabValidationAdapterCatalog
    $normalizedSteps = @()
    foreach ($step in $plan.steps) {
        Assert-LabValidationStepModel -Step $step -Catalog $catalog

        $normalizedStep = @{}
        foreach ($key in $step.Keys) {
            $normalizedStep[$key] = $step[$key]
        }

        switch ($step.adapter) {
            'runtime.powershell.pester' {
                $normalizedStep.testPaths = @(
                    foreach ($pathValue in $step.testPaths) {
                        Resolve-LabConstrainedPath -Path $pathValue -BasePath $RepoRoot -AllowedRoots @($RepoRoot) -MustExist
                    }
                )
            }
            'runtime.python.pytest' {
                $normalizedStep.testPaths = @(
                    foreach ($pathValue in $step.testPaths) {
                        Resolve-LabConstrainedPath -Path $pathValue -BasePath $RepoRoot -AllowedRoots @($RepoRoot) -MustExist
                    }
                )
            }
            'runtime.powershell.script' {
                $normalizedStep.scriptPath = Resolve-LabConstrainedPath -Path $step.scriptPath -BasePath $RepoRoot -AllowedRoots @($RepoRoot) -MustExist
            }
            'playwright.portal-smoke' {
                $normalizedStep.packagePath = Resolve-LabConstrainedPath -Path $step.packagePath -BasePath $RepoRoot -AllowedRoots @($RepoRoot) -MustExist
                $normalizedStep.specPath = Resolve-LabConstrainedPath -Path $step.specPath -BasePath $RepoRoot -AllowedRoots @($RepoRoot) -MustExist
            }
        }

        $normalizedSteps += $normalizedStep
    }

    return @{
        planPath      = $resolvedPlanPath
        ownershipPath = $resolvedOwnershipPath
        plan          = $plan
        ownership     = $ownership
        steps         = $normalizedSteps
    }
}

function Invoke-LabValidationStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Step,

        [Parameter()]
        [switch]$PlanOnly
    )

    $start = [System.DateTimeOffset]::UtcNow
    if ($PlanOnly) {
        return @{
            id              = $Step.id
            channel         = $Step.channel
            adapter         = $Step.adapter
            status          = 'not-run-planonly'
            startedAtUtc    = $start.ToString('o')
            durationSeconds = 0
        }
    }

    switch ($Step.adapter) {
        'runtime.powershell.pester' {
            Import-Module -Name Pester -ErrorAction Stop
            $config = New-PesterConfiguration
            $config.Run.Path = @($Step.testPaths)
            $config.Run.Exit = $false
            $config.Output.Verbosity = 'Detailed'
            $result = Invoke-Pester -Configuration $config
            if ($result.FailedCount -gt 0) {
                throw [System.InvalidOperationException]::new("Pester failed for step '$($Step.id)'.")
            }
        }
        'runtime.python.pytest' {
            $arguments = @('-m', 'pytest') + @($Step.testPaths)
            & python @arguments
            if ($LASTEXITCODE -ne 0) {
                throw [System.InvalidOperationException]::new("pytest failed for step '$($Step.id)' with exit code $LASTEXITCODE.")
            }
        }
        'runtime.powershell.script' {
            $arguments = @('-NoProfile', '-File', $Step.scriptPath)
            if ($Step.ContainsKey('parameters') -and $null -ne $Step.parameters) {
                foreach ($parameterName in $Step.parameters.Keys) {
                    $parameterValue = [string]$Step.parameters[$parameterName]
                    $arguments += @("-$parameterName", $parameterValue)
                }
            }

            & pwsh @arguments
            if ($LASTEXITCODE -ne 0) {
                throw [System.InvalidOperationException]::new("PowerShell script step '$($Step.id)' failed with exit code $LASTEXITCODE.")
            }
        }
        'playwright.portal-smoke' {
            $relativeSpecPath = [System.IO.Path]::GetRelativePath($Step.packagePath, $Step.specPath)
            & npm --prefix $Step.packagePath run test:smoke -- $relativeSpecPath
            if ($LASTEXITCODE -ne 0) {
                throw [System.InvalidOperationException]::new("Playwright smoke step '$($Step.id)' failed with exit code $LASTEXITCODE.")
            }
        }
        default {
            throw [System.IO.InvalidDataException]::new("Unsupported adapter '$($Step.adapter)'.")
        }
    }

    $finish = [System.DateTimeOffset]::UtcNow
    return @{
        id              = $Step.id
        channel         = $Step.channel
        adapter         = $Step.adapter
        status          = 'succeeded'
        startedAtUtc    = $start.ToString('o')
        durationSeconds = [System.Math]::Round(($finish - $start).TotalSeconds, 3)
    }
}

function New-LabValidationSummary {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Solution,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PlanPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OwnershipPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EvidenceRoot,

        [Parameter(Mandatory)]
        [hashtable[]]$StepResults,

        [Parameter(Mandatory)]
        [ValidateSet('PlanValidatedNotExecuted', 'Succeeded', 'Failed')]
        [string]$Result,

        [Parameter(Mandatory)]
        [int]$ExitCode
    )

    $summaryDirectory = Join-Path -Path $EvidenceRoot -ChildPath 'summary'
    New-Item -Path $summaryDirectory -ItemType Directory -Force | Out-Null
    $summaryPath = Join-Path -Path $summaryDirectory -ChildPath ("{0}-summary.json" -f $Solution)

    $summary = @{
        schemaVersion      = '1.0.0'
        generatedAtUtc     = [System.DateTimeOffset]::UtcNow.ToString('o')
        solution           = $Solution
        planPath           = $PlanPath
        ownershipManifest  = $OwnershipPath
        executionMode      = if ($Result -eq 'PlanValidatedNotExecuted') { 'PlanOnly' } else { 'Execute' }
        result             = $Result
        exitCode           = $ExitCode
        steps              = $StepResults
    }

    $summaryJson = $summary | ConvertTo-Json -Depth 8
    if ($PSCmdlet.ShouldProcess($summaryPath, 'Write sanitized validation summary')) {
        Set-Content -LiteralPath $summaryPath -Value $summaryJson -Encoding utf8NoBOM
    }
    return $summaryPath
}

function Invoke-LabValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Solution,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PlanPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EvidenceRoot,

        [Parameter()]
        [switch]$PlanOnly
    )

    $repoRoot = Get-LabHarnessRepoRoot -StartPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $resolvedEvidenceRoot = Resolve-LabConstrainedPath -Path $EvidenceRoot -BasePath $repoRoot -AllowedRoots @($repoRoot, $EvidenceRoot)
    New-Item -Path $resolvedEvidenceRoot -ItemType Directory -Force | Out-Null

    $validated = Test-LabValidationPlan -Solution $Solution -PlanPath $PlanPath -RepoRoot $repoRoot -EvidenceRoot $resolvedEvidenceRoot
    $stepResults = @()

    $resultName = if ($PlanOnly) { 'PlanValidatedNotExecuted' } else { 'Succeeded' }
    $exitCode = if ($PlanOnly) { 2 } else { 0 }

    foreach ($step in $validated.steps) {
        try {
            $stepResults += Invoke-LabValidationStep -Step $step -PlanOnly:$PlanOnly
        }
        catch [System.Exception] {
            $stepResults += @{
                id              = $step.id
                channel         = $step.channel
                adapter         = $step.adapter
                status          = 'failed'
                startedAtUtc    = [System.DateTimeOffset]::UtcNow.ToString('o')
                durationSeconds = 0
            }
            $resultName = 'Failed'
            $exitCode = 20
            break
        }
    }

    $summaryPath = New-LabValidationSummary `
        -Solution $Solution `
        -PlanPath $validated.planPath `
        -OwnershipPath $validated.ownershipPath `
        -EvidenceRoot $resolvedEvidenceRoot `
        -StepResults $stepResults `
        -Result $resultName `
        -ExitCode $exitCode

    return @{
        ExitCode    = $exitCode
        Result      = $resultName
        SummaryPath = $summaryPath
        StepResults = $stepResults
    }
}

Export-ModuleMember -Function @(
    'Get-LabValidationAdapterCatalog',
    'Get-LabHarnessRepoRoot',
    'Resolve-LabConstrainedPath',
    'Test-LabValidationPlan',
    'Invoke-LabValidation'
)
