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
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [long] $expanded = 0
    foreach ($entry in $archive.Entries) {
        $name = $entry.FullName.Replace("\", "/")
        if ([string]::IsNullOrWhiteSpace($name) -or $name.StartsWith("/") -or
            $name -match "^[A-Za-z]:" -or ($name.Split("/") -contains "..")) {
            throw "Unsafe ZIP path: $($entry.FullName)"
        }
        if (-not $names.Add($name)) { throw "Duplicate/case-colliding ZIP path: $name" }
        if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) {
            throw "Symbolic links are forbidden: $name"
        }
        $leaf = [IO.Path]::GetFileNameWithoutExtension($name)
        if ($leaf -match "^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])$") {
            throw "Windows-reserved ZIP path: $name"
        }
        $expanded += $entry.Length
        if ($expanded -gt 1073741824) { throw "Expanded package exceeds 1 GiB" }
        if ($entry.CompressedLength -gt 0 -and $entry.Length -gt 1048576 -and
            ($entry.Length / $entry.CompressedLength) -gt 200) {
            throw "Suspicious compression ratio: $name"
        }
    }

    $manifestEntries = @($archive.Entries | Where-Object FullName -CEQ "plugin.json")
    if ($manifestEntries.Count -ne 1) { throw "Expected one top-level plugin.json" }
    $reader = [IO.StreamReader]::new($manifestEntries[0].Open())
    try { $manifestJson = $reader.ReadToEnd() }
    finally { $reader.Dispose() }

    if ($ManifestSchemaPath) {
        if (-not ($archive.Entries | Where-Object FullName -CEQ "LICENSE")) {
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
    if (-not ($archive.Entries | Where-Object FullName -CEQ $entrypoint)) {
        throw "Missing entrypoint: $entrypoint"
    }
    if (-not $AllowBundledContracts -and ($archive.Entries | Where-Object {
        [IO.Path]::GetFileName($_.FullName) -ieq "Zeus.Plugins.Contracts.dll"
    })) { throw "Do not bundle Zeus.Plugins.Contracts.dll" }
    $uiModules = @()
    if ($null -ne $manifest.ui -and $null -ne $manifest.ui.modules) {
        $uiModules = @($manifest.ui.modules)
    }
    foreach ($module in $uiModules) {
        $path = [string]$module
        if ($path.Contains("..") -or $path.StartsWith("/") -or
            ($path -cnotmatch "\.m?js$") -or
            -not ($archive.Entries | Where-Object FullName -CEQ $path)) {
            throw "Unsafe or missing UI module: $path"
        }
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
