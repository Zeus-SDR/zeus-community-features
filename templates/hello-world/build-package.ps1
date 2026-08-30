# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot "artifacts/hello-world"))
$stagingRoot = [IO.Path]::GetFullPath((Join-Path $artifactRoot "staging"))
$project = Join-Path $PSScriptRoot "Zeus.Community.HelloWorld.csproj"
$assembly = Join-Path $PSScriptRoot "bin/Release/net10.0/Zeus.Community.HelloWorld.dll"
$package = Join-Path $artifactRoot "com.example.zeus.helloworld-1.0.0.zip"

if (-not $artifactRoot.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Artifact path escaped repository: $artifactRoot"
}
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

dotnet build $project -c Release --nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed: $LASTEXITCODE" }

Copy-Item -LiteralPath (Join-Path $PSScriptRoot "plugin.json") -Destination $stagingRoot -Force
Copy-Item -LiteralPath $assembly -Destination $stagingRoot -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "README.md") -Destination $stagingRoot -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "LICENSE") -Destination $stagingRoot -Force
if (Test-Path -LiteralPath $package) { Remove-Item -LiteralPath $package -Force }
[IO.Compression.ZipFile]::CreateFromDirectory(
    $stagingRoot, $package, [IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item -LiteralPath $stagingRoot -Recurse -Force

$sha = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$package.sha256" -Encoding ascii -Value "$sha  $([IO.Path]::GetFileName($package))"
Write-Host "Package: $package"
Write-Host "SHA-256: $sha"

