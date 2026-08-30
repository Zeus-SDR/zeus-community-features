// SPDX-License-Identifier: GPL-2.0-or-later
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Logging;
using Zeus.Plugins.Contracts;
using Zeus.Plugins.Contracts.Extensions;

namespace Zeus.Community.HelloWorld;

public sealed class HelloWorldPlugin : IZeusPlugin, IBackendPlugin
{
    private IPluginContext? _context;

    public Task InitializeAsync(IPluginContext context, CancellationToken ct)
    {
        _context = context;
        context.Logger.LogInformation("Hello World feature initialized");
        return Task.CompletedTask;
    }

    public Task ShutdownAsync(CancellationToken ct)
    {
        _context?.Logger.LogInformation("Hello World feature stopped");
        _context = null;
        return Task.CompletedTask;
    }

    public void MapEndpoints(IEndpointRouteBuilder endpoints) =>
        endpoints.MapGet("hello", () => Results.Ok(new
        {
            message = "Hello from a Zeus community feature.",
            pluginId = _context?.PluginId,
        }));
}
