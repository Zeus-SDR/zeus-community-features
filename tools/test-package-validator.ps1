# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "zeus-package-validator-$([Guid]::NewGuid().ToString('N'))"
$validator = Join-Path $PSScriptRoot "validate-package.ps1"

function New-TestArchive {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string[]] $EntryNames
    )
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
    $archive = [IO.Compression.ZipArchive]::new(
        $stream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($entryName in $EntryNames) {
            $entry = $archive.CreateEntry($entryName)
            $writer = [IO.StreamWriter]::new($entry.Open())
            try { $writer.Write("{}") }
            finally { $writer.Dispose() }
        }
    }
    finally {
        $archive.Dispose()
        $stream.Dispose()
    }
}

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $cases = @(
        @{ Name = "dot-segment"; Entries = @("plugin.json", "./plugin.json") },
        @{ Name = "empty-segment"; Entries = @("plugin.json", "ui//module.js") },
        @{ Name = "case-alias"; Entries = @("plugin.json", "PLUGIN.json") },
        @{ Name = "wrong-manifest-case"; Entries = @("PLUGIN.json") },
        @{ Name = "backslash"; Entries = @("plugin.json", "ui\module.js") },
        @{ Name = "trailing-dot"; Entries = @("plugin.json", "ui./module.js") },
        @{ Name = "colon"; Entries = @("plugin.json", "ui/module.js:stream") }
    )
    foreach ($case in $cases) {
        $zipPath = Join-Path $tempRoot "$($case.Name).zip"
        New-TestArchive -Path $zipPath -EntryNames $case.Entries
        $rejected = $false
        try {
            & $validator -PackagePath $zipPath `
                -ExpectedId "com.example.invalid" -ExpectedVersion "1.0.0" | Out-Null
        }
        catch {
            $rejected = $true
            Write-Host "Rejected $($case.Name): $($_.Exception.Message)"
        }
        if (-not $rejected) { throw "Package validator accepted unsafe case: $($case.Name)" }
    }
}
finally {
    $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}

Write-Host "Package path safety regression tests passed."
