# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [ValidateSet("Release", "Debug")]
    [string] $Configuration = "Release",
    [string] $LicensePath,
    [string[]] $ManagedDependency = @(),
    [string[]] $AdditionalAsset = @()
)

$ErrorActionPreference = "Stop"

function Assert-StrictChildPath {
    param(
        [Parameter(Mandatory)][string] $Parent,
        [Parameter(Mandatory)][string] $Candidate,
        [Parameter(Mandatory)][string] $Label
    )
    $relative = [IO.Path]::GetRelativePath($Parent, $Candidate).Replace("\", "/")
    if ($relative -eq "." -or $relative -eq ".." -or
        $relative.StartsWith("../", [StringComparison]::Ordinal) -or
        [IO.Path]::IsPathRooted($relative)) {
        throw "$Label escaped its required directory: $Candidate"
    }
}

function Get-SafePackagePath {
    param([Parameter(Mandatory)][string] $Path)
    if ($Path.Contains("\")) { throw "Package asset paths must use forward slashes: $Path" }
    $normalized = $Path
    if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized.StartsWith("/")) {
        throw "Package asset path must be relative: $Path"
    }
    foreach ($segment in $normalized.Split("/")) {
        if ([string]::IsNullOrEmpty($segment) -or $segment -in @(".", "..") -or
            $segment -match '[<>:"|?*\x00-\x1F]' -or $segment -match '[. ]$' -or
            $segment -cne $segment.Normalize([Text.NormalizationForm]::FormC)) {
            throw "Unsafe or non-portable package asset path: $Path"
        }
    }
    return $normalized
}

function Assert-NotLinkedPath {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Label
    )
    if ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "$Label cannot be a filesystem link: $Path"
    }
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
$manifestPath = Join-Path $PSScriptRoot "plugin.json"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100
$featureId = [string]$manifest.id
$featureVersion = [string]$manifest.version
$entrypointName = [string]$manifest.entrypoint.assembly
if ($featureId -cnotmatch "^[a-z][a-z0-9]*(\.[a-z0-9]+)+$") {
    throw "plugin.json id must be a lowercase reverse-DNS identifier"
}
if ($featureVersion -cnotmatch "^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$") {
    throw "plugin.json version must be SemVer"
}
if ($entrypointName -cnotmatch "^[A-Za-z0-9][A-Za-z0-9._-]*\.dll$") {
    throw "plugin.json entrypoint.assembly must be a plain DLL filename"
}
$projects = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter *.csproj -File)
if ($projects.Count -ne 1) { throw "Expected exactly one project beside build-package.ps1" }
if (-not $LicensePath) { $LicensePath = Join-Path $repoRoot "LICENSE" }
$artifactsBase = [IO.Path]::GetFullPath((Join-Path $repoRoot "artifacts"))
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $artifactsBase $featureId))
$stagingRoot = [IO.Path]::GetFullPath((Join-Path $artifactRoot "staging"))
$project = $projects[0].FullName
$assemblyRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "bin/$Configuration/net10.0"))
$assembly = [IO.Path]::GetFullPath((Join-Path $assemblyRoot $entrypointName))
$package = [IO.Path]::GetFullPath((Join-Path $artifactRoot "$featureId-$featureVersion.zip"))

Assert-StrictChildPath -Parent $repoRoot -Candidate $artifactRoot -Label "Artifact directory"
Assert-StrictChildPath -Parent $artifactsBase -Candidate $artifactRoot -Label "Feature artifact directory"
Assert-StrictChildPath -Parent $artifactRoot -Candidate $stagingRoot -Label "Staging directory"
Assert-StrictChildPath -Parent $artifactRoot -Candidate $package -Label "Package path"
Assert-StrictChildPath -Parent $assemblyRoot -Candidate $assembly -Label "Entrypoint path"
if (-not (Test-Path -LiteralPath $LicensePath -PathType Leaf)) {
    throw "Feature license not found: $LicensePath"
}
Assert-NotLinkedPath -Path $LicensePath -Label "Feature license"
foreach ($directory in @($artifactsBase, $artifactRoot)) {
    if ((Test-Path -LiteralPath $directory) -and
        ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing to use a linked artifact directory: $directory"
    }
}
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
if (Test-Path -LiteralPath $stagingRoot) {
    if ((Get-Item -LiteralPath $stagingRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Refusing to remove a linked staging directory: $stagingRoot"
    }
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

function Copy-PackageAsset {
    param([Parameter(Mandatory)][string] $RelativePath)
    $packagePath = Get-SafePackagePath -Path $RelativePath
    $sourcePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $packagePath))
    $destinationPath = [IO.Path]::GetFullPath((Join-Path $stagingRoot $packagePath))
    Assert-StrictChildPath -Parent $PSScriptRoot -Candidate $sourcePath -Label "Package asset source"
    Assert-StrictChildPath -Parent $stagingRoot -Candidate $destinationPath -Label "Package asset destination"
    if (-not (Test-Path -LiteralPath $sourcePath)) { throw "Package asset not found: $packagePath" }
    $sourceItems = @(Get-Item -LiteralPath $sourcePath -Force)
    if ($sourceItems[0].PSIsContainer) {
        $sourceItems += @(Get-ChildItem -LiteralPath $sourcePath -Recurse -Force)
    }
    if ($sourceItems | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
        throw "Linked package assets are forbidden: $packagePath"
    }
    if (Test-Path -LiteralPath $destinationPath) {
        throw "Package asset collides with another staged path: $packagePath"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Recurse -Force
}

dotnet build $project -c $Configuration --nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed: $LASTEXITCODE" }
if (-not (Test-Path -LiteralPath $assembly -PathType Leaf)) {
    throw "Entrypoint assembly was not produced: $assembly"
}
Assert-NotLinkedPath -Path $assembly -Label "Entrypoint assembly"

Copy-Item -LiteralPath $manifestPath -Destination $stagingRoot -Force
Copy-Item -LiteralPath $assembly -Destination $stagingRoot -Force
$depsFile = [IO.Path]::ChangeExtension($assembly, ".deps.json")
if (Test-Path -LiteralPath $depsFile -PathType Leaf) {
    Assert-NotLinkedPath -Path $depsFile -Label "Dependency manifest"
    Copy-Item -LiteralPath $depsFile -Destination $stagingRoot -Force
}
foreach ($dependencyName in $ManagedDependency) {
    if ($dependencyName -cnotmatch "^[A-Za-z0-9][A-Za-z0-9._-]*\.dll$" -or
        $dependencyName -ieq $entrypointName -or
        $dependencyName -ieq "Zeus.Plugins.Contracts.dll") {
        throw "ManagedDependency must name a non-contract dependency DLL: $dependencyName"
    }
    $dependencyPath = [IO.Path]::GetFullPath((Join-Path $assemblyRoot $dependencyName))
    Assert-StrictChildPath -Parent $assemblyRoot -Candidate $dependencyPath -Label "Dependency path"
    if (-not (Test-Path -LiteralPath $dependencyPath -PathType Leaf)) {
        throw "Managed dependency not found in build output: $dependencyName"
    }
    Assert-NotLinkedPath -Path $dependencyPath -Label "Managed dependency"
    $dependencyDestination = Join-Path $stagingRoot $dependencyName
    if (Test-Path -LiteralPath $dependencyDestination) {
        throw "Managed dependency collides with another staged path: $dependencyName"
    }
    Copy-Item -LiteralPath $dependencyPath -Destination $dependencyDestination -Force
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "README.md") -Destination $stagingRoot -Force
Copy-Item -LiteralPath $LicensePath -Destination (Join-Path $stagingRoot "LICENSE") -Force
$noticesPath = Join-Path (Split-Path -Parent $LicensePath) "THIRD_PARTY_NOTICES.md"
if (Test-Path -LiteralPath $noticesPath -PathType Leaf) {
    Assert-NotLinkedPath -Path $noticesPath -Label "Third-party notices"
    Copy-Item -LiteralPath $noticesPath -Destination $stagingRoot -Force
}
if ($null -ne $manifest.ui) {
    foreach ($module in @($manifest.ui.modules)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$module)) {
            Copy-PackageAsset -RelativePath ([string]$module)
        }
    }
}
if ($null -ne $manifest.audio -and
    -not [string]::IsNullOrWhiteSpace([string]$manifest.audio.vst3Path)) {
    Copy-PackageAsset -RelativePath ([string]$manifest.audio.vst3Path)
}
foreach ($asset in $AdditionalAsset) {
    Copy-PackageAsset -RelativePath $asset
}
if (Test-Path -LiteralPath $package) {
    if ((Get-Item -LiteralPath $package -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Refusing to replace a linked package path: $package"
    }
    Remove-Item -LiteralPath $package -Force
}
[IO.Compression.ZipFile]::CreateFromDirectory(
    $stagingRoot, $package, [IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item -LiteralPath $stagingRoot -Recurse -Force

$sha = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$package.sha256" -Encoding ascii -Value "$sha  $([IO.Path]::GetFileName($package))"
Write-Host "Package: $package"
Write-Host "SHA-256: $sha"
