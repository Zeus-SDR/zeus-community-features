# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [string] $Configuration = "Release",
    [string] $LicensePath,
    [string] $OutputRoot
)

$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
$manifestPath = Join-Path $PSScriptRoot "plugin.json"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100
if ([string]::IsNullOrWhiteSpace([string]$manifest.id) -or
    [string]::IsNullOrWhiteSpace([string]$manifest.version) -or
    [string]::IsNullOrWhiteSpace([string]$manifest.entrypoint.assembly)) {
    throw "plugin.json must declare id, version, and entrypoint.assembly"
}
$projects = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter *.csproj -File)
if ($projects.Count -ne 1) { throw "Expected exactly one project beside build-package.ps1" }
if (-not $LicensePath) { $LicensePath = Join-Path $repoRoot "LICENSE" }
if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot "artifacts/$($manifest.id)" }
$artifactRoot = [IO.Path]::GetFullPath($OutputRoot)
$stagingRoot = [IO.Path]::GetFullPath((Join-Path $artifactRoot "staging"))
$project = $projects[0].FullName
$assembly = Join-Path $PSScriptRoot "bin/$Configuration/net10.0/$($manifest.entrypoint.assembly)"
$package = Join-Path $artifactRoot "$($manifest.id)-$($manifest.version).zip"

if (-not $artifactRoot.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Artifact path escaped repository: $artifactRoot"
}
if (-not (Test-Path -LiteralPath $LicensePath -PathType Leaf)) {
    throw "Feature license not found: $LicensePath"
}
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

dotnet build $project -c $Configuration --nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed: $LASTEXITCODE" }

Copy-Item -LiteralPath $manifestPath -Destination $stagingRoot -Force
Copy-Item -LiteralPath $assembly -Destination $stagingRoot -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "README.md") -Destination $stagingRoot -Force
Copy-Item -LiteralPath $LicensePath -Destination (Join-Path $stagingRoot "LICENSE") -Force
$noticesPath = Join-Path (Split-Path -Parent $LicensePath) "THIRD_PARTY_NOTICES.md"
if (Test-Path -LiteralPath $noticesPath -PathType Leaf) {
    Copy-Item -LiteralPath $noticesPath -Destination $stagingRoot -Force
}
if (Test-Path -LiteralPath $package) { Remove-Item -LiteralPath $package -Force }
[IO.Compression.ZipFile]::CreateFromDirectory(
    $stagingRoot, $package, [IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item -LiteralPath $stagingRoot -Recurse -Force

$sha = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$package.sha256" -Encoding ascii -Value "$sha  $([IO.Path]::GetFileName($package))"
Write-Host "Package: $package"
Write-Host "SHA-256: $sha"
