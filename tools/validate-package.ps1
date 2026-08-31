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

function Get-OptionalJsonProperty {
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)][string] $Name
    )
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

$resolved = (Resolve-Path -LiteralPath $PackagePath).Path
$archive = [IO.Compression.ZipFile]::OpenRead($resolved)
try {
    if ($archive.Entries.Count -gt 4096) { throw "Too many ZIP entries" }
    $entriesByPath = [Collections.Generic.Dictionary[string, IO.Compression.ZipArchiveEntry]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $pathKinds = [Collections.Generic.Dictionary[string, bool]]::new(
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
        $isDirectory = [string]::IsNullOrEmpty($entry.Name)
        if ($canonicalPath -ceq "plugin.json" -and $entry.Length -gt 1048576) {
            throw "plugin.json exceeds 1 MiB"
        }
        for ($i = 1; $i -lt $canonicalSegments.Count; $i++) {
            $ancestor = [string]::Join("/", $canonicalSegments.GetRange(0, $i))
            $ancestorKind = $false
            if ($pathKinds.TryGetValue($ancestor, [ref]$ancestorKind)) {
                if (-not $ancestorKind) {
                    throw "ZIP file conflicts with descendant path: $ancestor / $canonicalPath"
                }
            }
            else {
                $pathKinds.Add($ancestor, $true)
            }
        }
        $existingKind = $false
        if ($pathKinds.TryGetValue($canonicalPath, [ref]$existingKind)) {
            if (-not ($existingKind -and $isDirectory)) {
                throw "ZIP file/directory path collision: $canonicalPath"
            }
        }
        else {
            if (-not $isDirectory -and ($pathKinds.Keys | Where-Object {
                $_.StartsWith($canonicalPath + "/", [StringComparison]::OrdinalIgnoreCase)
            })) {
                throw "ZIP file conflicts with an existing directory path: $canonicalPath"
            }
            $pathKinds.Add($canonicalPath, $isDirectory)
        }
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
    $manifestUi = Get-OptionalJsonProperty -Object $manifest -Name "ui"
    $manifestAudio = Get-OptionalJsonProperty -Object $manifest -Name "audio"
    $uiModules = @()
    if ($null -ne $manifestUi) {
        $modules = Get-OptionalJsonProperty -Object $manifestUi -Name "modules"
        if ($null -ne $modules) { $uiModules = @($modules) }
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
    if ($ManifestSchemaPath -and $null -ne $manifestAudio) {
        $vst3PathValue = Get-OptionalJsonProperty -Object $manifestAudio -Name "vst3Path"
        $auComponentIdValue = Get-OptionalJsonProperty -Object $manifestAudio -Name "auComponentId"
        $vst3UidValue = Get-OptionalJsonProperty -Object $manifestAudio -Name "vst3Uid"
        switch ([string]$manifestAudio.format) {
            "managed" {
                if (-not [string]::IsNullOrWhiteSpace([string]$vst3PathValue) -or
                    -not [string]::IsNullOrWhiteSpace([string]$auComponentIdValue) -or
                    -not [string]::IsNullOrWhiteSpace([string]$vst3UidValue)) {
                    throw "Managed audio features cannot declare a native audio identity"
                }
            }
            "vst3" {
                if ([string]::IsNullOrWhiteSpace([string]$vst3PathValue)) {
                    throw "VST3 audio features must declare audio.vst3Path"
                }
            }
            "au" {
                if ([string]$auComponentIdValue -cnotmatch "^[^:]{4}:[^:]{4}:[^:]{4}$") {
                    throw "Audio Unit features must declare a type:subtype:manufacturer identity"
                }
            }
            default { throw "audio.format must be managed, vst3, or au" }
        }
    }
    $audioVst3Path = if ($null -ne $manifestAudio) {
        Get-OptionalJsonProperty -Object $manifestAudio -Name "vst3Path"
    } else { $null }
    if (-not [string]::IsNullOrWhiteSpace([string]$audioVst3Path)) {
        $vst3Path = ([string]$audioVst3Path).Replace("\", "/").TrimEnd("/")
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
