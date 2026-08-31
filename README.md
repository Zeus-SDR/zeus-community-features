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

## Submit a feature for approval

Read [CONTRIBUTING.md](CONTRIBUTING.md) before writing or packaging a feature.
It is the canonical guide for the public SDK boundary, `plugin.json` schema,
package layout, supported UI slots, Zeus styling tokens, validation commands,
and review policy. The JSON files under [`schema/`](schema/) are the
machine-readable source of truth for JSON shape; the scripts under
[`tools/`](tools/) additionally enforce catalog, archive, and cross-platform
path policy. Passing schema validation alone is not sufficient.
Repository-aware development agents must also read and follow
[AGENTS.md](AGENTS.md).

Use this release and submission flow:

1. **Create a separate public source repository for your feature.** Start from
   [`templates/hello-world/`](templates/hello-world/) and reference only the
   contracts under [`sdk/Openhpsdr.Zeus.Plugins.Contracts/`](sdk/Openhpsdr.Zeus.Plugins.Contracts/)
   and, for visual features, the documented `registerPanel` and `callBackend`
   browser API. Do not copy or depend on private Zeus source, undocumented
   endpoints, host internals, DSP/radio protocol code, credentials, binaries,
   or PureSignal.
2. **Define and build the package.** Follow
   [`schema/plugin.schema.json`](schema/plugin.schema.json) exactly. Visual
   features must use the public styling-token subset and scoped-selector rules
   in [CONTRIBUTING.md](CONTRIBUTING.md#4-uniform-ui-styling-contract).
3. **Validate and test locally.** Run every command in
   [Required local checks](CONTRIBUTING.md#7-required-local-checks), then install
   the resulting ZIP through **Features → Community → Install local feature**.
   Test every declared operating system and architecture and capture
   screenshots for visual features.
4. **Publish the exact tested ZIP** at an immutable public HTTPS release URL.
   Compute its SHA-256. Never replace the bytes for an existing `(id, version)`;
   publish a new SemVer version, URL, and checksum instead.
5. **Fork this catalog repository and branch from its latest `main`.** Edit only
   [`registry.json`](registry.json): add one new community feature or one new
   version, set `channel` to `community` and `verified` to `false`, omit
   `subscription`, preserve all existing entries, and update the top-level
   `generated` timestamp.
6. **Open one catalog pull request per feature version against `main`.** Use
   `feat(registry): add <id> <version>` for a first release or
   `feat(registry): release <id> <version>` for an update. Complete the pull
   request template with the source URL, immutable ZIP URL, SHA-256, platforms,
   capabilities and permissions, local test results, and UI screenshots when
   applicable. Do not bypass failed checks; push corrections to the same
   branch and resolve every review conversation.

Feature source and release binaries do not belong in this catalog repository;
a normal submission changes only `registry.json`. See
[Open the pull request](CONTRIBUTING.md#8-open-the-pull-request) for exact fork,
branch, commit, push, and `gh pr create` commands and a complete catalog-entry
example.

Protected `main` requires passing checks, resolved review conversations, and
approval from either Douglas J. Cerrato (KB2UKA / `@Kb2uka`) or Christian
Suarez (N9WAR / `@iamexemplar`). Either maintainer may validate and merge a
submission independently; approval from both is not required. After merge,
Zeus shows the listing in **Features → Community** when its catalog cache
refreshes, normally within about five minutes. Users still choose whether to
install it; catalog approval never auto-installs a feature or marks it verified.

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
