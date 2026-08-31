# Zeus community feature contributor instructions

This repository is designed to be followed by people and automation agents.
Before changing anything, read `README.md`, `CONTRIBUTING.md`, and the two
schemas under `schema/`. `CONTRIBUTING.md` is the canonical submission and UI
style guide. The schemas are the machine-readable truth for JSON shape; tools
under `tools/` additionally enforce archive, catalog, submission, and custody
policy. Passing schema validation alone is not sufficient.

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
   this repository's Git tree; approved binaries enter Zeus-SDR release custody
   only through the maintainer workflow.
2. Validate and locally install the ZIP before publishing it.
3. Publish the exact ZIP as a `.zip` asset on a versioned public GitHub Release.
   Record its bare lowercase SHA-256 and never replace its bytes.
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
8. Use the deterministic Zeus-SDR custody `downloadUrl` from
   `CONTRIBUTING.md`; keep the contributor-owned intake URL in the pull request
   evidence, not in the final catalog entry.
9. Run every contributor command in the “Required local checks” section of
   `CONTRIBUTING.md`, then open a pull request to `main` and complete the pull
   request template with real evidence.
10. If the feature has UI, attach the required dark/light, normal/narrow,
    200%-scaling, keyboard-focus, and applicable state screenshots. Do not
    replace screenshots with a text-only claim that the UI was tested.

Use the pull request title `feat(registry): add <id> <version>` for a first
listing or `feat(registry): release <id> <version>` for an update. Do not edit
or bypass failed checks.

## Acceptance lifecycle

Protected `main` requires passing checks, resolved review conversations, and
approval from either Douglas J. Cerrato (KB2UKA / `@Kb2uka`) or Christian
Suarez (N9WAR / `@iamexemplar`). Either maintainer has full authority to
validate and merge a contribution; approval from both is not required.

Before approval, that maintainer uses the protected-main custody workflow to
mirror the exact reviewed ZIP into an immutable release owned by Zeus-SDR. The
workflow never checks out or executes contributor code, refuses a hash or
manifest mismatch, and never replaces an existing asset. The final catalog URL
must be the deterministic Zeus-SDR custody URL, so deleting the contributor's
release cannot remove the package from other users.

After a maintainer merges the listing into `main`, Zeus picks it up from the
public catalog and shows it in **Features → Community** after the catalog cache
refreshes. A listing does not auto-install the feature, mark it verified, or
make it sandboxed.
