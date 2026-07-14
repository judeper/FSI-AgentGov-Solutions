Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LabRedactionPatterns {
    [CmdletBinding()]
    param()

    @(
        @{ Name = 'upn'; Pattern = '(?i)\b[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}\b'; Replacement = '<redacted:upn>' },
        @{ Name = 'tenant-domain'; Pattern = '(?i)\b[a-z0-9\-]+\.onmicrosoft\.com\b'; Replacement = '<redacted:tenant-domain>' },
        @{ Name = 'guid'; Pattern = '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b'; Replacement = '<redacted:guid>' },
        @{ Name = 'dynamics-url'; Pattern = '(?i)https:\/\/[a-z0-9\-]+\.crm\d*\.dynamics\.com'; Replacement = '<redacted:dynamics-url>' },
        @{ Name = 'webhook-url'; Pattern = '(?i)https:\/\/[^ \r\n]*webhook[^ \r\n]*'; Replacement = '<redacted:webhook-url>' },
        @{ Name = 'token-parameter'; Pattern = '(?i)(sig|code|token|access_token|client_secret)=([^&\s]+)'; Replacement = '$1=<redacted:token>' }
    )
}

function Invoke-LabEvidenceRedaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$InputPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath
    )

    $source = Get-Content -LiteralPath $InputPath -Raw
    $redacted = $source
    $counts = @{}

    foreach ($definition in (Get-LabRedactionPatterns)) {
        $before = $redacted
        $redacted = [System.Text.RegularExpressions.Regex]::Replace($redacted, $definition.Pattern, $definition.Replacement)
        $matchCount = [System.Text.RegularExpressions.Regex]::Matches($before, $definition.Pattern).Count
        $counts[$definition.Name] = $matchCount
    }

    $outputDirectory = Split-Path -Path $OutputPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
        New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
    }

    Set-Content -LiteralPath $OutputPath -Value $redacted -Encoding utf8NoBOM

    return @{
        InputPath   = $InputPath
        OutputPath  = $OutputPath
        Replacements = $counts
    }
}

function New-LabEvidenceManifest {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ManifestPath
    )

    $resolvedArtifactRoot = [System.IO.Path]::GetFullPath($ArtifactRoot)
    $resolvedManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)

    if (-not (Test-Path -LiteralPath $resolvedArtifactRoot)) {
        throw [System.IO.DirectoryNotFoundException]::new("Artifact root '$resolvedArtifactRoot' was not found.")
    }

    $manifestDirectory = Split-Path -Path $resolvedManifestPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($manifestDirectory)) {
        New-Item -Path $manifestDirectory -ItemType Directory -Force | Out-Null
    }

    $files = Get-ChildItem -Path $resolvedArtifactRoot -Recurse -File | Where-Object {
        $_.FullName -ne $resolvedManifestPath
    }

    $entries = @(
        foreach ($file in $files) {
            $hash = Get-FileHash -Path $file.FullName -Algorithm SHA256
            @{
                path      = [System.IO.Path]::GetRelativePath($resolvedArtifactRoot, $file.FullName)
                sizeBytes = [int64]$file.Length
                sha256    = $hash.Hash.ToLowerInvariant()
            }
        }
    )

    $manifest = @{
        schemaVersion = '1.0.0'
        generatedAtUtc = [System.DateTimeOffset]::UtcNow.ToString('o')
        artifactRoot = $resolvedArtifactRoot
        files = $entries
    }

    $manifestJson = $manifest | ConvertTo-Json -Depth 8
    if ($PSCmdlet.ShouldProcess($resolvedManifestPath, 'Write SHA-256 evidence manifest')) {
        Set-Content -LiteralPath $resolvedManifestPath -Value $manifestJson -Encoding utf8NoBOM
    }

    return @{
        ManifestPath = $resolvedManifestPath
        FileCount = $entries.Count
    }
}

Export-ModuleMember -Function @(
    'Get-LabRedactionPatterns',
    'Invoke-LabEvidenceRedaction',
    'New-LabEvidenceManifest'
)
