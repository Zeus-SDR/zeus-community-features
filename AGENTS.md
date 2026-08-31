# Zeus community feature contributor instructions

This repository is designed to be followed by people and automation agents.
Before changing anything, read `README.md`, `CONTRIBUTING.md`, and the two
schemas under `schema/`. `CONTRIBUTING.md` is the canonical submission and UI
style guide; the schemas are the machine-readable truth.

## Public boundary

- Treat `sdk/Openhpsdr.Zeus.Plugins.Contracts/` as the complete integration
  boundary. Use only its public types and the browser API documented in
  `CONTRIBUTING.md`.
- Never request, copy, translate, reconstruct, or depend on private Zeus source,
  host internals, DSP/radio protocol implementations, credentials, binaries, or
  undocumented endpoints. If the public SDK cannot support a feature, stop and
  open an issue describing the missing capability without proposing private
  implementation details.
- Never add Zeus product source to this repository. Changes under `sdk/` must be
  made by a maintainer in a dedicated SDK-update pull request and must pass the
  SDK allowlist audit.
- PureSignal is not an SDK surface. Do not inspect, call, proxy, persist, or
  change any PureSignal behavior.

## Catalog-listing task

For a new feature or release:

1. Build the feature in its own source repository from the public SDK and
   `templates/hello-world/`. Do not add feature source or release binaries to
   this catalog repository.
2. Validate and locally install the ZIP before publishing it.
3. Publish the exact ZIP at an immutable HTTPS release URL.
4. Fork this repository and edit only `registry.json`. A listing pull request
   must not change schemas, SDK files, templates, tools, workflows, or existing
   official entries.
5. For a new listing, set `channel` to `community` and `verified` to `false`.
   Do not add `subscription`. Make the catalog metadata and embedded
   `plugin.json` metadata agree.
6. Add one feature, or one new version of one feature, per pull request. Keep
   existing versions and URLs unchanged; published `(id, version)` pairs are
   immutable.
7. Update the top-level `generated` timestamp to the current UTC RFC 3339 time.
8. Run every command in the “Required local checks” section of
   `CONTRIBUTING.md`, then open a pull request to `main` and complete the pull
   request template with real evidence.

Use the pull request title `feat(registry): add <id> <version>` for a first
listing or `feat(registry): release <id> <version>` for an update. Do not edit
or bypass failed checks.

## Acceptance lifecycle

Protected `main` requires passing checks, resolved review conversations, and
approval from either Douglas J. Cerrato (KB2UKA / `@Kb2uka`) or Christian
Suarez (N9WAR / `@iamexemplar`). Either maintainer has full authority to
validate and merge a contribution; approval from both is not required.

After a maintainer merges the listing into `main`, Zeus picks it up from the
public catalog and shows it in **Features → Community** after the catalog cache
refreshes. A listing does not auto-install the feature, mark it verified, or
make it sandboxed.
