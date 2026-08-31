# Zeus Community Features

This public repository is the source and catalog for community-built features
that run with [Zeus SDR](https://github.com/Zeus-SDR/zeussdr). A feature
accepted into protected `main` appears in the **Community** tab after Zeus
refreshes the catalog.

It contains:

- `registry.json`, the schema-version 1 catalog consumed by Zeus;
- `schema/`, the registry and embedded `plugin.json` contracts;
- `sdk/Openhpsdr.Zeus.Plugins.Contracts/`, a standalone source snapshot of
  ABI 1 / SDK 1.5.0;
- `templates/hello-world/`, a feature that builds without a sibling Zeus
  checkout;
- `tools/`, local package and catalog validators.

The seeded `channel: "official"` entries preserve every existing Zeus package
URL, checksum, and update path during migration. New outside contributions use
`channel: "community"`.

## Build

Install the .NET 10 SDK, then run:

```powershell
dotnet build Zeus.CommunityFeatures.slnx -c Release
pwsh templates/hello-world/build-package.ps1
```

The package is written under `artifacts/com.example.zeus.helloworld/`. During
development, install it using **Features → Community → Install local feature**.

## Contribute

Build your feature in its own source repository from the public SDK and Hello
World template, publish an immutable HTTPS release ZIP, then submit a
catalog-only pull request that adds the release to `registry.json`. The schema,
UI styling rules, package rules, exact validation commands, and
human/automation-agent workflow are all defined in
[CONTRIBUTING.md](CONTRIBUTING.md). Repository-aware automation should also
follow [AGENTS.md](AGENTS.md).

Either Zeus maintainer may validate and merge a contribution. Once merged into
protected `main`, the listing appears in **Features → Community** after Zeus's
catalog cache refreshes. Listing never auto-installs a feature.

## Trust model

Catalog visibility never installs a feature automatically. Community features
are .NET assemblies loaded in-process and may also load JavaScript into the
Zeus origin. Assembly load contexts and manifest capabilities are compatibility
and disclosure mechanisms, **not a security sandbox**. Install only code you
trust.

PureSignal is not a community SDK surface. Community features must not arm,
disarm, calibrate, persist, proxy, or otherwise alter PureSignal behavior.

The vendored SDK contains public contracts only. It does not contain or expose
Zeus product source, host implementations, DSP or radio protocol logic,
credentials, native libraries, or PureSignal logic. Community features must
not depend on undocumented product internals.

## License

Repository code and catalog material are GPL-2.0-or-later. Individually listed
feature packages may use another declared compatible license; their source,
manifest, packaged `LICENSE`, notices, and catalog entry must agree.
