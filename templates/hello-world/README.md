# Hello World template

Copy this directory for a new feature and replace every sample identifier and
metadata value. It builds against the vendored ABI-1 SDK without another
repository beside it.

```powershell
dotnet build templates/hello-world/Zeus.Community.HelloWorld.csproj -c Release
pwsh templates/hello-world/build-package.ps1
```

The sample exposes
`GET /api/plugins/com.example.zeus.helloworld/hello`. It requests no radio,
network, filesystem, or audio capability. PureSignal is not an SDK surface and
must not be reached through private Zeus APIs.

