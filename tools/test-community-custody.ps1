# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot "CommunityCustody.psm1") -Force

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "zeus-custody-test-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $featureId = "com.example.custodytest"
    $version = "1.0.0"
    $packagePath = Join-Path $tempRoot "source.zip"
    $manifest = [ordered]@{
        schemaVersion = 1
        id = $featureId
        name = "Custody Test"
        version = $version
        author = "Test contributor"
        description = "Regression fixture for the community custody policy."
        homepage = "https://example.com/custody-test"
        license = "GPL-2.0-or-later"
        sdk = [ordered]@{ abi = 1; minVersion = "1.5.0" }
        entrypoint = [ordered]@{ assembly = "CustodyTest.dll"; type = "Example.CustodyTest" }
        capabilities = @()
        permissions = [ordered]@{ network = $false; fileSystemRead = $false; fileSystemWrite = $false }
    }
    $stream = [IO.File]::Open($packagePath, [IO.FileMode]::CreateNew)
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($item in @(
            @{ Name = "plugin.json"; Text = ($manifest | ConvertTo-Json -Depth 20) },
            @{ Name = "CustodyTest.dll"; Text = "fixture" },
            @{ Name = "LICENSE"; Text = "GPL-2.0-or-later regression fixture" }
        )) {
            $entry = $archive.CreateEntry($item.Name)
            $writer = [IO.StreamWriter]::new($entry.Open())
            try { $writer.Write($item.Text) } finally { $writer.Dispose() }
        }
    }
    finally {
        $archive.Dispose()
        $stream.Dispose()
    }
    $sha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()

    $basePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../registry.json"))
    $base = Get-Content -Raw -LiteralPath $basePath | ConvertFrom-Json -Depth 100
    $candidate = ($base | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100)
    $candidate.generated = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $entry = [pscustomobject][ordered]@{
        id = $featureId
        channel = "community"
        name = $manifest.name
        description = $manifest.description
        author = $manifest.author
        license = $manifest.license
        homepage = $manifest.homepage
        categories = @("tools")
        verified = $false
        versions = @([pscustomobject][ordered]@{
            version = $version
            sdkAbi = 1
            sdkMinVersion = "1.5.0"
            platforms = @("any")
            downloadUrl = Get-CommunityCustodyUrl -FeatureId $featureId -Version $version
            sha256 = $sha256
        })
    }
    $candidate.plugins = @($candidate.plugins) + $entry
    $candidatePath = Join-Path $tempRoot "candidate.json"
    [IO.File]::WriteAllText(
        $candidatePath,
        ($candidate | ConvertTo-Json -Depth 100) + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )

    & (Join-Path $PSScriptRoot "validate-community-submission.ps1") `
        -BaseRegistryPath $basePath `
        -CandidateRegistryPath $candidatePath `
        -ExpectedFeatureId $featureId `
        -ExpectedVersion $version
    $wrongTargetRejected = $false
    try {
        & (Join-Path $PSScriptRoot "validate-community-submission.ps1") `
            -BaseRegistryPath $basePath `
            -CandidateRegistryPath $candidatePath `
            -ExpectedFeatureId $featureId `
            -ExpectedVersion "9.9.9" | Out-Null
    }
    catch { $wrongTargetRejected = $true }
    if (-not $wrongTargetRejected) { throw "Submission policy accepted the wrong custody target" }

    $schemaInvalid = ($candidate | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100)
    $schemaInvalid.plugins[-1] | Add-Member -NotePropertyName unexpectedField -NotePropertyValue $true
    $schemaInvalidPath = Join-Path $tempRoot "schema-invalid.json"
    [IO.File]::WriteAllText(
        $schemaInvalidPath,
        ($schemaInvalid | ConvertTo-Json -Depth 100),
        [Text.UTF8Encoding]::new($false)
    )
    $registrySchemaPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../schema/registry.schema.json"))
    & npx --yes -p ajv-cli@5.0.0 -p ajv-formats@3.0.1 ajv validate `
        --spec=draft2020 --strict=false -c ajv-formats `
        -s $registrySchemaPath -d $schemaInvalidPath | Out-Null
    if ($LASTEXITCODE -eq 0) { throw "Registry schema accepted an unexpected feature field" }

    $releaseBasePath = Join-Path $tempRoot "release-base.json"
    [IO.File]::WriteAllText(
        $releaseBasePath,
        ($candidate | ConvertTo-Json -Depth 100) + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
    $releaseCandidate = ($candidate | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100)
    $releaseCandidate.generated = [DateTimeOffset]::UtcNow.AddSeconds(1).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $nextVersion = "1.1.0"
    $nextRelease = ($releaseCandidate.plugins[-1].versions[0] |
        ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20)
    $nextRelease.version = $nextVersion
    $nextRelease.downloadUrl = Get-CommunityCustodyUrl -FeatureId $featureId -Version $nextVersion
    $releaseCandidate.plugins[-1].versions = @($nextRelease) + @($releaseCandidate.plugins[-1].versions)
    $releaseCandidatePath = Join-Path $tempRoot "release-candidate.json"
    [IO.File]::WriteAllText(
        $releaseCandidatePath,
        ($releaseCandidate | ConvertTo-Json -Depth 100) + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
    & (Join-Path $PSScriptRoot "validate-community-submission.ps1") `
        -BaseRegistryPath $releaseBasePath `
        -CandidateRegistryPath $releaseCandidatePath `
        -ExpectedFeatureId $featureId `
        -ExpectedVersion $nextVersion

    $prepared = & (Join-Path $PSScriptRoot "prepare-community-custody.ps1") `
        -RegistryPath $candidatePath `
        -FeatureId $featureId `
        -Version $version `
        -ExpectedSha256 $sha256 `
        -SourcePackagePath $packagePath `
        -OutputDirectory (Join-Path $tempRoot "prepared")
    if ($prepared.custodyUrl -cne $entry.versions[0].downloadUrl -or
        $prepared.sha256 -cne $sha256) {
        throw "Prepared custody metadata mismatch"
    }

    foreach ($badSourceUrl in @(
        "https://example.com/owner/repo/releases/download/v1.0.0/feature.zip",
        "https://github.com/owner/repo/archive/refs/tags/v1.0.0.zip",
        "https://github.com/owner/repo/releases/download/v1.0.0/feature.exe",
        "https://github.com/owner/repo/releases/download/v1.0.0/feature.zip?changed=1"
    )) {
        $rejected = $false
        try {
            Copy-HttpsFileWithLimit -SourceUrl $badSourceUrl `
                -DestinationPath (Join-Path $tempRoot "should-not-download.zip") `
                -RequireGitHubRelease | Out-Null
        }
        catch { $rejected = $true }
        if (-not $rejected) { throw "Custody downloader accepted invalid intake URL: $badSourceUrl" }
    }

    $publishArguments = @{
        PackageDirectory = (Join-Path $tempRoot "prepared")
        TargetCommit = ("a" * 40)
        ExpectedFeatureId = $featureId
        ExpectedVersion = $version
        ExpectedSha256 = $sha256
    }
    foreach ($override in @(
        @{ ExpectedFeatureId = "com.example.wrongfeature" },
        @{ ExpectedVersion = "9.9.9" },
        @{ ExpectedSha256 = ("0" * 64) },
        @{ MaxPackageBytes = 1 }
    )) {
        $caseArguments = $publishArguments.Clone()
        foreach ($key in $override.Keys) { $caseArguments[$key] = $override[$key] }
        $rejected = $false
        try { & (Join-Path $PSScriptRoot "publish-community-custody.ps1") @caseArguments | Out-Null }
        catch { $rejected = $true }
        if (-not $rejected) { throw "Publish preflight accepted a dispatch or size mismatch" }
    }

    $badUrls = @(
        "https://github.com/example/project/releases/download/v1.0.0/source.zip",
        "https://github.com/Zeus-SDR.evil/zeus-community-features/releases/download/community-$featureId-v$version/$featureId-$version.zip",
        "https://github.com/Zeus-SDR/zeus-community-features/releases/download/community-$featureId-v$version/$featureId-$version.zip?replace=1",
        "https://github.com/Zeus-SDR/zeus-community-features/releases/download/community-$featureId-v$version/other.zip"
    )
    foreach ($badUrl in $badUrls) {
        $bad = ($candidate | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100)
        $bad.plugins[-1].versions[0].downloadUrl = $badUrl
        $badPath = Join-Path $tempRoot "bad-$([Guid]::NewGuid().ToString('N')).json"
        [IO.File]::WriteAllText($badPath, ($bad | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        $rejected = $false
        try { & (Join-Path $PSScriptRoot "validate-registry.ps1") -RegistryPath $badPath | Out-Null }
        catch { $rejected = $true }
        if (-not $rejected) { throw "Custody policy accepted invalid URL: $badUrl" }
    }

    $officialMutation = ($candidate | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100)
    $officialMutation.plugins[0].name = "$($officialMutation.plugins[0].name) changed"
    $officialPath = Join-Path $tempRoot "official-mutation.json"
    [IO.File]::WriteAllText($officialPath, ($officialMutation | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
    $rejected = $false
    try {
        & (Join-Path $PSScriptRoot "validate-community-submission.ps1") `
            -BaseRegistryPath $basePath -CandidateRegistryPath $officialPath | Out-Null
    }
    catch { $rejected = $true }
    if (-not $rejected) { throw "Submission policy accepted an official-entry mutation" }

    $multipleAdditions = ($candidate | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100)
    $secondEntry = ($multipleAdditions.plugins[-1] | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100)
    $secondEntry.id = "com.example.secondcustodytest"
    $secondEntry.versions[0].downloadUrl = Get-CommunityCustodyUrl `
        -FeatureId $secondEntry.id -Version $version
    $multipleAdditions.plugins = @($multipleAdditions.plugins) + $secondEntry
    $multiplePath = Join-Path $tempRoot "multiple-additions.json"
    [IO.File]::WriteAllText(
        $multiplePath,
        ($multipleAdditions | ConvertTo-Json -Depth 100),
        [Text.UTF8Encoding]::new($false)
    )
    $rejected = $false
    try {
        & (Join-Path $PSScriptRoot "validate-community-submission.ps1") `
            -BaseRegistryPath $basePath -CandidateRegistryPath $multiplePath | Out-Null
    }
    catch { $rejected = $true }
    if (-not $rejected) { throw "Submission policy accepted multiple new features" }
}
finally {
    $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTemp)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}

Write-Host "Community custody regression tests passed."
