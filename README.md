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

The package is written under `artifacts/hello-world/`. During development,
install it using **Features → Community → Install local feature**.

## Contribute

Fork this repository, copy the Hello World template, choose a globally unique
reverse-DNS ID, add tests and documentation, publish an immutable HTTPS ZIP,
and add its lowercase SHA-256 to `registry.json`. Read
[CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Trust model

Catalog visibility never installs a feature automatically. Community features
are .NET assemblies loaded in-process and may also load JavaScript into the
Zeus origin. Assembly load contexts and manifest capabilities are compatibility
and disclosure mechanisms, **not a security sandbox**. Install only code you
trust.

PureSignal is not a community SDK surface. Community features must not arm,
disarm, calibrate, persist, proxy, or otherwise alter PureSignal behavior.

## License

Repository code and catalog material are GPL-2.0-or-later. Individual feature
directories may use another declared compatible license; their manifest,
`LICENSE`, notices, and catalog entry must agree.
