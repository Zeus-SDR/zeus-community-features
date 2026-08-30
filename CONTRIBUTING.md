# Contributing a Zeus community feature

Contributions arrive through a fork and pull request to protected `main`.
Open an issue first for anything larger than a typo, and keep one feature in
one pull request.

## Start from the template

1. Copy `templates/hello-world` to an appropriate path under `features/`.
2. Replace every sample ID, assembly name, namespace, and metadata value.
3. Reference the vendored contracts project, or the matching published
   `Openhpsdr.Zeus.Plugins.Contracts` package when available. Never depend on
   a sibling Zeus checkout.
4. Add tests for behavior whose regression could affect an operator or radio.
5. Build and package from a clean checkout.

## Package and catalog rules

The ZIP must have exactly one top-level `plugin.json` and its declared
entrypoint DLL. Do not bundle `Zeus.Plugins.Contracts.dll`, framework
assemblies, secrets, build caches, or credentials.

Published `(id, version)` pairs are immutable. Release a new SemVer version;
never replace bytes at an existing URL. Compute the digest over the exact ZIP:

```powershell
(Get-FileHash -Algorithm SHA256 feature.zip).Hash.ToLowerInvariant()
```

New entries use this shape:

```json
{
  "id": "com.example.feature",
  "channel": "community",
  "name": "Example Feature",
  "description": "One-line operator-visible purpose.",
  "author": "Your name or callsign",
  "license": "GPL-2.0-or-later",
  "homepage": "https://github.com/example/feature",
  "categories": ["tools"],
  "verified": false,
  "versions": [{
    "version": "1.0.0",
    "sdkAbi": 1,
    "sdkMinVersion": "1.5.0",
    "platforms": ["any"],
    "downloadUrl": "https://example.com/feature-1.0.0.zip",
    "sha256": "64-lowercase-hex-characters"
  }]
}
```

`verified` is maintainer-controlled. Acceptance means the feature passed
repository checks and review; it is not a warranty or sandbox guarantee.

## Capabilities and radio safety

Declare only capabilities actually used. `ControlRadio`, `AudioStream`,
network/filesystem access, native code, and child processes receive elevated
review. Capability metadata does not technically prevent ordinary .NET code
from calling operating-system APIs, so undeclared access is grounds for
rejection or removal.

**PureSignal is forbidden.** Community features may not change PureSignal
logic, arm/disarm or startup state, persistence, calibration, attenuation
defaults, feedback selection, or any endpoint that indirectly changes those
behaviors. A feature must never auto-key a transmitter.

## Validate before submitting

```powershell
dotnet build Zeus.CommunityFeatures.slnx -c Release
pwsh tools/validate-registry.ps1
pwsh templates/hello-world/build-package.ps1
pwsh tools/validate-package.ps1 `
  -PackagePath artifacts/hello-world/com.example.zeus.helloworld-1.0.0.zip `
  -ExpectedId com.example.zeus.helloworld `
  -ExpectedVersion 1.0.0
```

Public-fork CI uses disposable GitHub-hosted runners, a read-only token, and no
secrets. It validates schemas, HTTPS URLs, exact hashes, embedded manifests,
SDK metadata, builds, and package shape. Outside contributions require one
approval from either `@Kb2uka` or `@iamexemplar`, passing checks, and
resolved conversations.

Include a feature license and required third-party notices. Identify copied,
translated, vendored, generated, or clean-room-derived code precisely.
