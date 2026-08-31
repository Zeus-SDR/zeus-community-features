## Community feature release

- Feature ID:
- Version:
- Source repository (public):
- Immutable HTTPS ZIP:
- SHA-256 (lowercase):
- Platforms:

## Submission checklist

- [ ] This pull request adds one feature or one new version of one feature.
- [ ] This listing pull request changes only `registry.json`.
- [ ] The entry uses `channel: "community"`, `verified: false`, and no
      `subscription` field.
- [ ] The embedded `plugin.json` and catalog agree on ID, version, SDK ABI, and
      minimum SDK version.
- [ ] The published ZIP is the exact locally tested artifact, is available over
      HTTPS, and will not be replaced at this versioned URL.
- [ ] The feature uses only the public SDK/browser API and does not contain,
      reconstruct, or depend on private Zeus logic or undocumented endpoints.
- [ ] PureSignal is untouched and the feature never auto-keys a transmitter.
- [ ] Capabilities and permissions are complete and no broader than necessary.
- [ ] Package license, third-party notices, manifest, and catalog metadata agree.
- [ ] UI CSS follows the token, selector-scoping, theme, scaling, keyboard, and
      state guidance in `CONTRIBUTING.md`, or this feature has no UI.
- [ ] I installed the ZIP locally and tested the declared platforms and operator
      states. Results are described below.
- [ ] All commands in “Required local checks” pass, including the download/hash
      check after publication.

## Capability and safety review

Explain every requested capability and permission, any network hosts or file
paths used, all radio-control behavior, and how transmit is kept operator-led.

## Validation evidence

List tested OS/architecture combinations, local-install results, failure-state
tests, and screenshots for visual features.

## Review and publication

I understand that either Douglas J. Cerrato (KB2UKA / `@Kb2uka`) or Christian
Suarez (N9WAR / `@iamexemplar`) may validate and merge this contribution. After
merge to protected `main`, Zeus will include the listing in
**Features → Community** after its catalog cache refreshes; users must still
choose to install it.
