# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $PackageDirectory,
    [Parameter(Mandatory)][string] $TargetCommit,
    [Parameter(Mandatory)][string] $ExpectedFeatureId,
    [Parameter(Mandatory)][string] $ExpectedVersion,
    [Parameter(Mandatory)][string] $ExpectedSha256,
    [long] $MaxPackageBytes = 268435456,
    [string] $Repository = "Zeus-SDR/zeus-community-features"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot "CommunityCustody.psm1") -Force

if ($Repository -cne "Zeus-SDR/zeus-community-features") {
    throw "Custody publishing is restricted to Zeus-SDR/zeus-community-features"
}
if ($TargetCommit -cnotmatch "^[0-9a-f]{40}$") { throw "TargetCommit must be a full lowercase Git commit SHA" }
Assert-CommunityIdentity -FeatureId $ExpectedFeatureId -Version $ExpectedVersion
if ($ExpectedSha256 -cnotmatch "^[0-9a-f]{64}$") {
    throw "ExpectedSha256 must be exactly 64 lowercase hexadecimal characters"
}
if ($MaxPackageBytes -lt 1) { throw "MaxPackageBytes must be positive" }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI is required" }

$packageRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PackageDirectory))
$metadataPath = Join-Path $packageRoot "custody.json"
$metadata = Get-Content -Raw -LiteralPath $metadataPath | ConvertFrom-Json -Depth 20
if ($metadata.schemaVersion -ne 1) { throw "Unsupported custody metadata schema" }
$featureId = [string]$metadata.featureId
$version = [string]$metadata.version
$custodySha256 = [string]$metadata.sha256
Assert-CommunityIdentity -FeatureId $featureId -Version $version
if ($custodySha256 -cnotmatch "^[0-9a-f]{64}$") { throw "Invalid custody SHA-256" }
if ($featureId -cne $ExpectedFeatureId -or $version -cne $ExpectedVersion -or
    $custodySha256 -cne $ExpectedSha256) {
    throw "Custody artifact identity or SHA-256 does not match the maintainer dispatch"
}

$tag = Get-CommunityCustodyTag -FeatureId $featureId -Version $version
$assetName = Get-CommunityCustodyAssetName -FeatureId $featureId -Version $version
$custodyUrl = Get-CommunityCustodyUrl -FeatureId $featureId -Version $version
if ([string]$metadata.tag -cne $tag -or
    [string]$metadata.assetName -cne $assetName -or
    [string]$metadata.custodyUrl -cne $custodyUrl) {
    throw "Custody metadata does not match the deterministic release identity"
}
$packagePath = Join-Path $packageRoot $assetName
$packageItem = Get-Item -LiteralPath $packagePath
$metadataSize = [long]$metadata.size
if ($metadataSize -lt 1 -or $metadataSize -gt $MaxPackageBytes -or
    $packageItem.Length -lt 1 -or $packageItem.Length -gt $MaxPackageBytes) {
    throw "Custody package size is outside the permitted range"
}
if ($packageItem.Length -ne $metadataSize) { throw "Custody package size changed between jobs" }
$actualSha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha256 -cne $custodySha256) { throw "Custody package hash changed between jobs" }

$immutable = (& gh api "repos/$Repository/immutable-releases" | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $immutable.enabled -ne $true) {
    throw "Immutable releases must be enabled before custody publishing"
}

function Get-CustodyRelease {
    $json = & gh release view $tag --repo $Repository --json tagName,isDraft,isImmutable,assets 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($json | ConvertFrom-Json -Depth 20)
}

function Assert-ReleaseShape {
    param([Parameter(Mandatory)] $Release)
    if ([string]$Release.tagName -cne $tag) { throw "Custody release tag mismatch" }
    $assets = @($Release.assets)
    if ($assets.Count -gt 1 -or
        ($assets.Count -eq 1 -and [string]$assets[0].name -cne $assetName)) {
        throw "Custody release contains an unexpected asset; refusing to replace anything"
    }
    return $assets
}

$release = Get-CustodyRelease
if ($null -eq $release) {
    $notes = "Zeus-SDR custody copy for $featureId $version.`nSHA-256: $custodySha256"
    & gh release create $tag `
        --repo $Repository `
        --target $TargetCommit `
        --title "$featureId $version" `
        --notes $notes `
        --draft `
        $packagePath
    if ($LASTEXITCODE -ne 0) {
        $release = Get-CustodyRelease
        if ($null -eq $release) { throw "Could not create or recover the custody draft" }
    }
    else {
        $release = Get-CustodyRelease
    }
}

$assets = @(Assert-ReleaseShape -Release $release)
if ($assets.Count -eq 0) {
    if ($release.isDraft -ne $true) { throw "Published custody release is missing its asset" }
    & gh release upload $tag $packagePath --repo $Repository
    if ($LASTEXITCODE -ne 0) { throw "Could not upload the custody asset" }
    $release = Get-CustodyRelease
    $assets = @(Assert-ReleaseShape -Release $release)
}
if ($assets.Count -ne 1) { throw "Custody release did not expose exactly one asset" }
if ([long]$assets[0].size -ne $packageItem.Length) { throw "Uploaded custody asset size mismatch" }

$verificationRoot = Join-Path ([IO.Path]::GetTempPath()) "zeus-custody-verify-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $verificationRoot | Out-Null
try {
    & gh release download $tag --repo $Repository --pattern $assetName --dir $verificationRoot
    if ($LASTEXITCODE -ne 0) { throw "Could not re-download the custody asset" }
    $verifiedPath = Join-Path $verificationRoot $assetName
    $verifiedSha256 = (Get-FileHash -LiteralPath $verifiedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($verifiedSha256 -cne $custodySha256) {
        throw "Re-downloaded custody asset SHA-256 mismatch"
    }
}
finally {
    $resolvedVerification = [IO.Path]::GetFullPath($verificationRoot)
    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedVerification.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedVerification)) {
        Remove-Item -LiteralPath $resolvedVerification -Recurse -Force
    }
}

if ($release.isDraft -eq $true) {
    & gh release edit $tag --repo $Repository --draft=false
    if ($LASTEXITCODE -ne 0) { throw "Custody asset verified but the draft could not be published" }
    $release = Get-CustodyRelease
    $assets = @(Assert-ReleaseShape -Release $release)
}
if ($release.isDraft -eq $true) { throw "Custody release is still a draft" }
if ($release.isImmutable -ne $true) {
    throw "Published custody release is not immutable"
}
if ([string]$assets[0].url -cne $custodyUrl) {
    throw "GitHub returned an unexpected custody asset URL: $($assets[0].url)"
}
if ([string]$assets[0].digest -cne "sha256:$custodySha256") {
    throw "GitHub returned an unexpected custody asset digest"
}
& gh release verify $tag --repo $Repository | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "GitHub could not verify the immutable release attestation"
}

[pscustomobject]@{
    featureId = $featureId
    version = $version
    sha256 = $custodySha256
    size = $packageItem.Length
    custodyUrl = [string]$assets[0].url
    immutable = $true
}
