# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $PackagePath,
    [Parameter(Mandatory)][string] $ExpectedId,
    [Parameter(Mandatory)][string] $ExpectedVersion,
    [int] $ExpectedSdkAbi = 0,
    [string] $ExpectedSdkMinVersion = "",
    [string] $ExpectedName = "",
    [string] $ExpectedDescription = "",
    [string] $ExpectedAuthor = "",
    [string] $ExpectedLicense = "",
    [string] $ExpectedHomepage = "",
    [string] $ManifestSchemaPath = "",
    [switch] $AllowBundledContracts
)

$ErrorActionPreference = "Stop"
$resolved = (Resolve-Path -LiteralPath $PackagePath).Path
$archive = [IO.Compression.ZipFile]::OpenRead($resolved)
try {
    if ($archive.Entries.Count -gt 4096) { throw "Too many ZIP entries" }
    $entriesByPath = [Collections.Generic.Dictionary[string, IO.Compression.ZipArchiveEntry]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    [long] $expanded = 0
    foreach ($entry in $archive.Entries) {
        if ($entry.FullName.Contains("\")) {
            throw "ZIP paths must use forward slashes: $($entry.FullName)"
        }
        $rawName = $entry.FullName.Replace("\", "/")
        if ([string]::IsNullOrWhiteSpace($rawName) -or $rawName.StartsWith("/") -or
            $rawName -match "^[A-Za-z]:") {
            throw "Unsafe ZIP path: $($entry.FullName)"
        }
        $pathForSegments = $rawName.TrimEnd("/")
        if ([string]::IsNullOrWhiteSpace($pathForSegments)) {
            throw "Unsafe ZIP path: $($entry.FullName)"
        }
        $segments = @($pathForSegments.Split("/"))
        $canonicalSegments = [Collections.Generic.List[string]]::new()
        foreach ($segment in $segments) {
            if ([string]::IsNullOrEmpty($segment) -or $segment -in @(".", "..") -or
                $segment -match '[<>:"|?*\x00-\x1F]' -or $segment -match '[. ]$') {
                throw "Unsafe or non-portable ZIP path: $($entry.FullName)"
            }
            $normalized = $segment.Normalize([Text.NormalizationForm]::FormC)
            if (-not [string]::Equals($segment, $normalized, [StringComparison]::Ordinal)) {
                throw "ZIP paths must use Unicode normalization form C: $($entry.FullName)"
            }
            $reservedStem = $segment.Split(".")[0]
            if ($reservedStem -match "^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])$") {
                throw "Windows-reserved ZIP path: $($entry.FullName)"
            }
            $canonicalSegments.Add($normalized)
        }
        $canonicalPath = [string]::Join("/", $canonicalSegments)
        if (-not $entriesByPath.TryAdd($canonicalPath, $entry)) {
            throw "Duplicate or platform-colliding ZIP path: $canonicalPath"
        }
        if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) {
            throw "Symbolic links are forbidden: $canonicalPath"
        }
        $expanded += $entry.Length
        if ($expanded -gt 1073741824) { throw "Expanded package exceeds 1 GiB" }
        if ($entry.CompressedLength -gt 0 -and $entry.Length -gt 1048576 -and
            ($entry.Length / $entry.CompressedLength) -gt 200) {
            throw "Suspicious compression ratio: $canonicalPath"
        }
    }

    $manifestEntry = $null
    if (-not $entriesByPath.TryGetValue("plugin.json", [ref]$manifestEntry) -or
        [string]::IsNullOrEmpty($manifestEntry.Name) -or
        $manifestEntry.FullName -cne "plugin.json") {
        throw "Expected one top-level plugin.json"
    }
    $reader = [IO.StreamReader]::new($manifestEntry.Open())
    try { $manifestJson = $reader.ReadToEnd() }
    finally { $reader.Dispose() }

    if ($ManifestSchemaPath) {
        $licenseEntry = $null
        if (-not $entriesByPath.TryGetValue("LICENSE", [ref]$licenseEntry) -or
            [string]::IsNullOrEmpty($licenseEntry.Name) -or
            $licenseEntry.FullName -cne "LICENSE") {
            throw "Community packages must contain a top-level LICENSE"
        }
        $resolvedSchema = (Resolve-Path -LiteralPath $ManifestSchemaPath).Path
        $tempManifest = Join-Path ([IO.Path]::GetTempPath()) "zeus-manifest-$([Guid]::NewGuid().ToString('N')).json"
        try {
            Set-Content -LiteralPath $tempManifest -Value $manifestJson -Encoding utf8NoBOM -NoNewline
            & npx --yes -p ajv-cli@5.0.0 -p ajv-formats@3.0.1 ajv validate `
                --spec=draft2020 --strict=false -c ajv-formats `
                -s $resolvedSchema -d $tempManifest
            if ($LASTEXITCODE -ne 0) { throw "Embedded plugin.json does not match the public schema" }
        }
        finally {
            if (Test-Path -LiteralPath $tempManifest) {
                Remove-Item -LiteralPath $tempManifest -Force
            }
        }
    }
    $manifest = $manifestJson | ConvertFrom-Json -Depth 100

    if ($manifest.schemaVersion -ne 1) { throw "Manifest schemaVersion must be 1" }
    if ($manifest.id -cne $ExpectedId) { throw "Manifest id mismatch: $($manifest.id)" }
    if ($manifest.version -cne $ExpectedVersion) { throw "Manifest version mismatch: $($manifest.version)" }
    if ($ExpectedSdkAbi -gt 0 -and $manifest.sdk.abi -ne $ExpectedSdkAbi) {
        throw "Manifest sdk.abi mismatch"
    }
    if ($ExpectedSdkMinVersion -and $manifest.sdk.minVersion -cne $ExpectedSdkMinVersion) {
        throw "Manifest sdk.minVersion mismatch"
    }
    $metadataChecks = @(
        @{ Label = "name"; Expected = $ExpectedName; Actual = [string]$manifest.name },
        @{ Label = "description"; Expected = $ExpectedDescription; Actual = [string]$manifest.description },
        @{ Label = "author"; Expected = $ExpectedAuthor; Actual = [string]$manifest.author },
        @{ Label = "license"; Expected = $ExpectedLicense; Actual = [string]$manifest.license },
        @{ Label = "homepage"; Expected = $ExpectedHomepage; Actual = [string]$manifest.homepage }
    )
    foreach ($check in $metadataChecks) {
        if ($check.Expected -and $check.Actual -cne $check.Expected) {
            throw "Manifest $($check.Label) mismatch"
        }
    }
    $entrypoint = [string]$manifest.entrypoint.assembly
    if (-not $entrypoint.EndsWith(".dll", [StringComparison]::OrdinalIgnoreCase) -or
        $entrypoint.Contains("/") -or $entrypoint.Contains("\") -or $entrypoint.Contains("..")) {
        throw "Entrypoint must be a plain DLL filename"
    }
    $entrypointEntry = $null
    if (-not $entriesByPath.TryGetValue($entrypoint, [ref]$entrypointEntry) -or
        $entrypointEntry.FullName -cne $entrypoint) {
        throw "Missing entrypoint: $entrypoint"
    }
    if (-not $AllowBundledContracts -and ($entriesByPath.Keys | Where-Object {
        [IO.Path]::GetFileName($_) -ieq "Zeus.Plugins.Contracts.dll"
    })) { throw "Do not bundle Zeus.Plugins.Contracts.dll" }
    $uiModules = @()
    if ($null -ne $manifest.ui -and $null -ne $manifest.ui.modules) {
        $uiModules = @($manifest.ui.modules)
    }
    foreach ($module in $uiModules) {
        $path = [string]$module
        $moduleEntry = $null
        if ($path.Contains("..") -or $path.StartsWith("/") -or
            ($path -cnotmatch "\.m?js$") -or
            -not $entriesByPath.TryGetValue($path, [ref]$moduleEntry) -or
            $moduleEntry.FullName -cne $path) {
            throw "Unsafe or missing UI module: $path"
        }
    }
    if ($ManifestSchemaPath -and $null -ne $manifest.audio) {
        switch ([string]$manifest.audio.format) {
            "managed" {
                if (-not [string]::IsNullOrWhiteSpace([string]$manifest.audio.vst3Path) -or
                    -not [string]::IsNullOrWhiteSpace([string]$manifest.audio.auComponentId)) {
                    throw "Managed audio features cannot declare a native audio identity"
                }
            }
            "vst3" {
                if ([string]::IsNullOrWhiteSpace([string]$manifest.audio.vst3Path)) {
                    throw "VST3 audio features must declare audio.vst3Path"
                }
            }
            "au" {
                if ([string]$manifest.audio.auComponentId -cnotmatch "^[^:]{4}:[^:]{4}:[^:]{4}$") {
                    throw "Audio Unit features must declare a type:subtype:manufacturer identity"
                }
            }
            default { throw "audio.format must be managed, vst3, or au" }
        }
    }
    if ($null -ne $manifest.audio -and
        -not [string]::IsNullOrWhiteSpace([string]$manifest.audio.vst3Path)) {
        $vst3Path = ([string]$manifest.audio.vst3Path).Replace("\", "/").TrimEnd("/")
        $hasBundledVst = @($entriesByPath.Keys) -ccontains $vst3Path -or
            @($entriesByPath.Keys | Where-Object {
                $_.StartsWith($vst3Path + "/", [StringComparison]::Ordinal)
            }).Count -gt 0
        if (-not $hasBundledVst) { throw "Missing bundled VST3 path: $vst3Path" }
    }
    [pscustomobject]@{
        id = $manifest.id
        version = $manifest.version
        sdkAbi = $manifest.sdk.abi
        sdkMinVersion = $manifest.sdk.minVersion
        sha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLowerInvariant()
        entries = $archive.Entries.Count
        expandedBytes = $expanded
    }
}
finally { $archive.Dispose() }
