# Hello World template

Copy this directory and the public `sdk/` directory into your feature's own
source repository, preserve their relative project-reference layout, and
replace every sample identifier, assembly name, namespace, URL, and metadata
value. It builds against the vendored ABI-1 SDK without another repository
beside it. Follow the manifest, package, UI styling, validation, and catalog-PR
rules in the root `CONTRIBUTING.md`; do not commit third-party feature source or
release binaries to this catalog repository.

```powershell
dotnet build templates/hello-world/Zeus.Community.HelloWorld.csproj -c Release
pwsh templates/hello-world/build-package.ps1
```

The package is written to
`artifacts/com.example.zeus.helloworld/com.example.zeus.helloworld-1.0.0.zip`.
The packaging script derives the ID, version, and entrypoint from `plugin.json`;
after copying the template, make the repository-root `LICENSE` your feature's
real license (and add `THIRD_PARTY_NOTICES.md` there when needed). It includes
manifest-declared UI modules and a bundled VST3 automatically. Pass additional
managed DLL filenames with `-ManagedDependency` and other feature-relative
files/directories with `-AdditionalAsset`; see the root `CONTRIBUTING.md`.

The sample exposes
`GET /api/plugins/com.example.zeus.helloworld/hello`. It requests no radio,
network, filesystem, or audio capability. PureSignal is not an SDK surface and
must not be reached through private Zeus APIs. If the public SDK does not expose
something your feature needs, open an issue instead of depending on Zeus
internals.
