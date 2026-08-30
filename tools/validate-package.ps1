# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $PackagePath,
    [Parameter(Mandatory)][string] $ExpectedId,
    [Parameter(Mandatory)][string] $ExpectedVersion,
    [int] $ExpectedSdkAbi = 0,
    [string] $ExpectedSdkMinVersion = "",
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
    try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json -Depth 100 }
    finally { $reader.Dispose() }

    if ($manifest.schemaVersion -ne 1) { throw "Manifest schemaVersion must be 1" }
    if ($manifest.id -cne $ExpectedId) { throw "Manifest id mismatch: $($manifest.id)" }
    if ($manifest.version -cne $ExpectedVersion) { throw "Manifest version mismatch: $($manifest.version)" }
    if ($ExpectedSdkAbi -gt 0 -and $manifest.sdk.abi -ne $ExpectedSdkAbi) {
        throw "Manifest sdk.abi mismatch"
    }
    if ($ExpectedSdkMinVersion -and $manifest.sdk.minVersion -cne $ExpectedSdkMinVersion) {
        throw "Manifest sdk.minVersion mismatch"
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
        if ($path.Contains("..") -or -not ($archive.Entries | Where-Object FullName -CEQ $path)) {
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
